#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pivpn-web-gui"
WEB_USER="www-data"
DEFAULT_PORT="${PIVPN_WEB_PORT:-51821}"
WEB_ROOT="/var/www/${APP_NAME}"
PASSWORD_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
SETUP_VARS_FILE="/etc/pivpn/openvpn/setupVars.conf"
APACHE_SITE="/etc/apache2/sites-available/${APP_NAME}.conf"
SUDOERS_FILE="/etc/sudoers.d/${APP_NAME}"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Debe ejecutar este actualizador como root o con sudo." >&2
    exit 1
  fi
}

require_ubuntu_2404() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
      echo "[ADVERTENCIA] Este script está probado en Ubuntu 24.04." >&2
    fi
  fi
}

ensure_setup_vars() {
  if [[ ! -f "${SETUP_VARS_FILE}" ]]; then
    echo "[ERROR] No se encontró ${SETUP_VARS_FILE}. Ejecute sobre un host con PiVPN (OpenVPN) instalado." >&2
    exit 1
  fi
}

read_install_home() {
  local install_home
  install_home=$(awk -F '=' '/^install_home=/{print $2}' "${SETUP_VARS_FILE}")
  if [[ -z "${install_home}" ]]; then
    echo "[ERROR] No se pudo leer install_home desde ${SETUP_VARS_FILE}." >&2
    exit 1
  fi
  echo "${install_home}"
}

load_port() {
  local stored_port
  if [[ -f "${PASSWORD_DIR}/port.conf" ]]; then
    stored_port=$(cat "${PASSWORD_DIR}/port.conf" 2>/dev/null || true)
  fi
  if [[ -n "${stored_port:-}" ]]; then
    echo "${stored_port}"
  else
    echo "${DEFAULT_PORT}"
  fi
}

install_packages() {
  echo "[INFO] Actualizando dependencias..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 libapache2-mod-php php php-cli acl rsync logrotate openssl
}

prepare_directories() {
  mkdir -p "${WEB_ROOT}" "${PASSWORD_DIR}" "${LOG_DIR}"
  chown root:"${WEB_USER}" "${WEB_ROOT}" "${PASSWORD_DIR}" "${LOG_DIR}"
  chmod 750 "${PASSWORD_DIR}" "${LOG_DIR}"
}

sync_frontend() {
  echo "[INFO] Sincronizando código frontend en ${WEB_ROOT}..."
  rsync -a --delete "frontend/" "${WEB_ROOT}/"
  chown -R root:"${WEB_USER}" "${WEB_ROOT}"
  find "${WEB_ROOT}" -type d -print0 | xargs -0 chmod 755
  find "${WEB_ROOT}" -type f -print0 | xargs -0 chmod 640
  chmod 750 "${WEB_ROOT}/ovpns" 2>/dev/null || true
}

configure_ovpn_link() {
  local ovpn_src="$1"
  ln -sfn "${ovpn_src}" "${WEB_ROOT}/ovpns"
  if command -v setfacl >/dev/null 2>&1; then
    local parent_dir
    parent_dir=$(dirname "${ovpn_src}")
    setfacl -m u:"${WEB_USER}":rx "${parent_dir}" 2>/dev/null || true
    setfacl -m d:u:"${WEB_USER}":rx "${parent_dir}" 2>/dev/null || true
    setfacl -R -m u:"${WEB_USER}":rwx "${ovpn_src}"
    setfacl -R -m d:u:"${WEB_USER}":rwx "${ovpn_src}"
  fi
}

remember_port() {
  local port="$1"
  echo "${port}" > "${PASSWORD_DIR}/port.conf"
  chmod 640 "${PASSWORD_DIR}/port.conf"
  chown root:"${WEB_USER}" "${PASSWORD_DIR}/port.conf"
}

configure_sudoers() {
  cat <<SUDOERS > "${SUDOERS_FILE}"
Defaults:${WEB_USER} !requiretty
${WEB_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/pivpn *, /bin/ls -w 1 ${WEB_ROOT}/ovpns, /bin/rm ${WEB_ROOT}/ovpns/*
SUDOERS
  chmod 440 "${SUDOERS_FILE}"
}

configure_apache() {
  local port="$1"
  if ! grep -q "Listen ${port}" /etc/apache2/ports.conf; then
    echo "Listen ${port}" >> /etc/apache2/ports.conf
  fi
  cat <<APACHECONF > "${APACHE_SITE}"
<VirtualHost *:${port}>
    ServerAdmin webmaster@localhost
    DocumentRoot ${WEB_ROOT}

    <Directory ${WEB_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
        DirectoryIndex login.php
    </Directory>

    ErrorLog ${LOG_DIR}/apache-error.log
    CustomLog ${LOG_DIR}/apache-access.log combined
</VirtualHost>
APACHECONF
  a2enmod php* headers rewrite >/dev/null
  a2ensite "${APP_NAME}.conf" >/dev/null
  systemctl enable --now apache2 >/dev/null
  systemctl reload apache2 >/dev/null
}

configure_logrotate() {
  cat <<LOGROTATE > /etc/logrotate.d/${APP_NAME}
${LOG_DIR}/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 0640 root ${WEB_USER}
    sharedscripts
    postrotate
        systemctl reload apache2 >/dev/null 2>&1 || true
    endscript
}
LOGROTATE
}

main() {
  require_root
  require_ubuntu_2404
  ensure_setup_vars

  if [[ ! -d "${WEB_ROOT}" ]]; then
    echo "[ERROR] No existe ${WEB_ROOT}. Ejecute primero install.sh" >&2
    exit 1
  fi

  local install_home ovpn_dir service_port
  install_home=$(read_install_home)
  ovpn_dir="${install_home}/ovpns"
  if [[ ! -d "${ovpn_dir}" ]]; then
    echo "[ERROR] No se encontró el directorio de perfiles OVPN en ${ovpn_dir}." >&2
    exit 1
  fi

  service_port=$(load_port)

  install_packages
  prepare_directories
  sync_frontend
  configure_ovpn_link "${ovpn_dir}"
  remember_port "${service_port}"
  configure_sudoers
  configure_apache "${service_port}"
  configure_logrotate

  echo "[OK] Actualización completada. La GUI sigue disponible en http://<host>:${service_port}/"
  echo "[INFO] Contraseña y archivos existentes se conservaron. Si necesita regenerar la clave use: sudo pivpn-web-gui-reset-password"
}

main "$@"
