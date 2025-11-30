#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pivpn-web-gui"
WEB_USER="www-data"
SERVICE_PORT="${PIVPN_WEB_PORT:-51821}"
WEB_ROOT="/var/www/${APP_NAME}"
PASSWORD_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
SETUP_VARS_FILE="/etc/pivpn/openvpn/setupVars.conf"
APACHE_SITE="/etc/apache2/sites-available/${APP_NAME}.conf"
SUDOERS_FILE="/etc/sudoers.d/${APP_NAME}"
UNINSTALL_BIN="/usr/local/bin/${APP_NAME}-uninstall"
RESET_BIN="/usr/local/bin/${APP_NAME}-reset-password"
DIAG_BIN="/usr/local/bin/${APP_NAME}-diagnose"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Debe ejecutar este instalador como root o con sudo." >&2
    exit 1
  fi
}

require_ubuntu_2404() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
      echo "[ADVERTENCIA] Este instalador está probado solo en Ubuntu 24.04. Continuando de todas formas..." >&2
    fi
  fi
}

ensure_setup_vars() {
  if [[ ! -f "${SETUP_VARS_FILE}" ]]; then
    echo "[ERROR] No se encontró ${SETUP_VARS_FILE}. Instale PiVPN (OpenVPN) antes de continuar." >&2
    exit 1
  fi
}

read_install_home() {
  local install_home
  install_home=$(awk -F '=' '/^install_home=/{print $2}' "${SETUP_VARS_FILE}")
  if [[ -z "${install_home}" ]]; then
    echo "[ERROR] No se pudo obtener install_home desde ${SETUP_VARS_FILE}." >&2
    exit 1
  fi
  echo "${install_home}"
}

prompt_password() {
  local pass1 pass2
  read -r -s -p "Defina la contraseña de acceso a la GUI: " pass1; echo
  read -r -s -p "Confirme la contraseña: " pass2; echo
  if [[ -z "${pass1}" ]]; then
    echo "[ERROR] La contraseña no puede estar vacía." >&2
    exit 1
  fi
  if [[ "${pass1}" != "${pass2}" ]]; then
    echo "[ERROR] Las contraseñas no coinciden." >&2
    exit 1
  fi
  echo "${pass1}"
}

install_packages() {
  echo "[INFO] Instalando dependencias..."
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 libapache2-mod-php php php-cli acl rsync logrotate openssl
}

prepare_directories() {
  mkdir -p "${WEB_ROOT}" "${PASSWORD_DIR}" "${LOG_DIR}"
  chown root:"${WEB_USER}" "${WEB_ROOT}" "${PASSWORD_DIR}" "${LOG_DIR}"
  chmod 750 "${PASSWORD_DIR}" "${LOG_DIR}"
}

remember_port() {
  echo "${SERVICE_PORT}" > "${PASSWORD_DIR}/port.conf"
  chmod 640 "${PASSWORD_DIR}/port.conf"
  chown root:"${WEB_USER}" "${PASSWORD_DIR}/port.conf"
}

sync_frontend() {
  echo "[INFO] Copiando frontend a ${WEB_ROOT}..."
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
    setfacl -R -m u:"${WEB_USER}":rwx "${ovpn_src}"
    setfacl -R -m d:u:"${WEB_USER}":rwx "${ovpn_src}"
  fi
}

generate_password_store() {
  local password="$1"
  printf '%s' "${password}" > "${PASSWORD_DIR}/password.txt"
  chmod 640 "${PASSWORD_DIR}/password.txt"
  chown root:"${WEB_USER}" "${PASSWORD_DIR}/password.txt"
}

create_reset_password_bin() {
  cat <<'EOF' > "${RESET_BIN}"
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pivpn-web-gui"
WEB_USER="www-data"
PASSWORD_DIR="/etc/${APP_NAME}"
PASSWORD_FILE="${PASSWORD_DIR}/password.txt"

if [[ ${EUID} -ne 0 ]]; then
  echo "Ejecute como root" >&2
  exit 1
fi

read -r -s -p "Nueva contraseña: " pass1; echo
read -r -s -p "Confirmar contraseña: " pass2; echo
if [[ -z "${pass1}" ]]; then
  echo "La contraseña no puede estar vacía" >&2
  exit 1
fi
if [[ "${pass1}" != "${pass2}" ]]; then
  echo "Las contraseñas no coinciden" >&2
  exit 1
fi

printf '%s' "${pass1}" > "${PASSWORD_FILE}"

chown root:"${WEB_USER}" "${PASSWORD_FILE}"
chmod 640 "${PASSWORD_FILE}"

systemctl reload apache2 >/dev/null 2>&1 || true

echo "[OK] Contraseña actualizada"
EOF

  chmod +x "${RESET_BIN}"
}

create_diagnose_bin() {
  cat <<'EOF' > "${DIAG_BIN}"
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pivpn-web-gui"
WEB_USER="www-data"
WEB_ROOT="/var/www/${APP_NAME}"
PASSWORD_DIR="/etc/${APP_NAME}"
PASSWORD_FILE="${PASSWORD_DIR}/password.txt"
LOG_DIR="/var/log/${APP_NAME}"
SUDOERS_FILE="/etc/sudoers.d/${APP_NAME}"
SETUP_VARS_FILE="/etc/pivpn/openvpn/setupVars.conf"

if [[ ${EUID} -ne 0 ]]; then
  echo "Ejecute como root" >&2
  exit 1
fi

echo "[INFO] Verificando archivos principales..."
for f in "${PASSWORD_FILE}" "${SUDOERS_FILE}" "${SETUP_VARS_FILE}"; do
  if [[ -f "${f}" ]]; then
    echo "  [OK] Existe: ${f}"
  else
    echo "  [FALTA] ${f}" >&2
  fi
done

echo "[INFO] Validando almacén de contraseña..."
if sudo -u "${WEB_USER}" test -r "${PASSWORD_FILE}"; then
  if [[ -s "${PASSWORD_FILE}" ]]; then
    echo "  [OK] ${WEB_USER} puede leer el password.txt y no está vacío"
  else
    echo "  [ERROR] password.txt está vacío" >&2
  fi
else
  echo "  [ERROR] ${WEB_USER} no puede leer ${PASSWORD_FILE}" >&2
fi

echo "[INFO] Probando sudoers para ${WEB_USER}..."
if sudo -u "${WEB_USER}" sudo -l /usr/local/bin/pivpn >/dev/null 2>&1; then
  echo "  [OK] ${WEB_USER} puede ejecutar pivpn"
else
  echo "  [ERROR] ${WEB_USER} no tiene permisos sudo para pivpn" >&2
fi

echo "[INFO] Probando respuesta de pivpn..."
if sudo -u "${WEB_USER}" sudo /usr/local/bin/pivpn --help >/dev/null 2>&1; then
  echo "  [OK] pivpn responde"
else
  echo "  [ERROR] pivpn no responde para ${WEB_USER}" >&2
fi

echo "[INFO] Validando directorio de perfiles OVPN..."
if [[ -d "${WEB_ROOT}/ovpns" ]]; then
  if sudo -u "${WEB_USER}" ls "${WEB_ROOT}/ovpns" >/dev/null 2>&1; then
    echo "  [OK] ${WEB_USER} puede listar ovpns"
  else
    echo "  [ERROR] ${WEB_USER} no puede acceder a ${WEB_ROOT}/ovpns" >&2
  fi
else
  echo "  [FALTA] ${WEB_ROOT}/ovpns" >&2
fi

echo "[INFO] Últimas entradas del log de acciones:"
if [[ -f "${LOG_DIR}/actions.log" ]]; then
  tail -n 20 "${LOG_DIR}/actions.log"
else
  echo "  No hay log de acciones aún."
fi
EOF

  chmod +x "${DIAG_BIN}"
}

configure_sudoers() {
  cat <<EOF > "${SUDOERS_FILE}"
Defaults:${WEB_USER} !requiretty
${WEB_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/pivpn *, /bin/ls -w 1 ${WEB_ROOT}/ovpns, /bin/rm ${WEB_ROOT}/ovpns/*
EOF
  chmod 440 "${SUDOERS_FILE}"
}

configure_apache() {
  local port="$1"
  if ! grep -q "Listen ${port}" /etc/apache2/ports.conf; then
    echo "Listen ${port}" >> /etc/apache2/ports.conf
  fi
  cat <<EOF > "${APACHE_SITE}"
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
EOF
  a2enmod php* headers rewrite >/dev/null
  a2ensite "${APP_NAME}.conf" >/dev/null
  systemctl enable --now apache2 >/dev/null
  systemctl reload apache2 >/dev/null
}

configure_logrotate() {
  cat <<EOF > /etc/logrotate.d/${APP_NAME}
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
EOF
}

create_uninstall() {
  cat <<'EOF' > "${UNINSTALL_BIN}"
#!/usr/bin/env bash
set -euo pipefail
APP_NAME="pivpn-web-gui"
WEB_ROOT="/var/www/${APP_NAME}"
PASSWORD_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
APACHE_SITE="/etc/apache2/sites-available/${APP_NAME}.conf"
SUDOERS_FILE="/etc/sudoers.d/${APP_NAME}"
SERVICE_PORT="${PIVPN_WEB_PORT:-51821}"
PORT_FILE="${PASSWORD_DIR}/port.conf"
RESET_BIN="/usr/local/bin/${APP_NAME}-reset-password"
DIAG_BIN="/usr/local/bin/${APP_NAME}-diagnose"

if [[ ${EUID} -ne 0 ]]; then
  echo "Ejecute como root" >&2
  exit 1
fi

if [[ -f "${PORT_FILE}" ]]; then
  SERVICE_PORT=$(cat "${PORT_FILE}" 2>/dev/null || echo "${SERVICE_PORT}")
fi

systemctl stop apache2 >/dev/null 2>&1 || true
a2dissite "${APP_NAME}.conf" >/dev/null 2>&1 || true
sed -i "/Listen ${SERVICE_PORT}/d" /etc/apache2/ports.conf || true
rm -f "${APACHE_SITE}" "${SUDOERS_FILE}" /etc/logrotate.d/${APP_NAME}
rm -rf "${WEB_ROOT}" "${PASSWORD_DIR}"
rm -f "${LOG_DIR}"/*.log
rmdir "${LOG_DIR}" 2>/dev/null || true
rm -f "${RESET_BIN}" "${DIAG_BIN}"
systemctl reload apache2 >/dev/null 2>&1 || true

echo "Desinstalación completada"
EOF
  chmod +x "${UNINSTALL_BIN}"
}

main() {
  require_root
  require_ubuntu_2404
  ensure_setup_vars
  local install_home ovpn_dir password
  install_home=$(read_install_home)
  ovpn_dir="${install_home}/ovpns"
  if [[ ! -d "${ovpn_dir}" ]]; then
    echo "[ERROR] No se encontró el directorio de perfiles OVPN en ${ovpn_dir}." >&2
    exit 1
  fi

  install_packages
  prepare_directories
  sync_frontend
  configure_ovpn_link "${ovpn_dir}"
  password=$(prompt_password)
  generate_password_store "${password}"
  remember_port
  configure_sudoers
  configure_apache "${SERVICE_PORT}"
  configure_logrotate
  create_uninstall
  create_reset_password_bin
  create_diagnose_bin

  echo "[OK] Instalación finalizada. La GUI está disponible en http://<host>:${SERVICE_PORT}/"
  echo "[INFO] Para desinstalar ejecute: sudo ${UNINSTALL_BIN}"
}

main "$@"
