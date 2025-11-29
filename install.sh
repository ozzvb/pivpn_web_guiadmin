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
  local tmp_script
  tmp_script=$(mktemp)
  cat <<'PHP' > "${tmp_script}"
<?php
$password = getenv('PIVPN_GUI_PASSWORD');
$passwordFile = $argv[1];
$keyFile = $argv[2];
if ($password === false || $password === '') {
    fwrite(STDERR, "Contraseña no recibida\n");
    exit(1);
}
$hash = password_hash($password, PASSWORD_DEFAULT);
$key = random_bytes(32);
$iv = random_bytes(openssl_cipher_iv_length('aes-256-cbc'));
$cipher = openssl_encrypt($hash, 'aes-256-cbc', $key, 0, $iv);
file_put_contents($passwordFile, json_encode([
    'iv' => base64_encode($iv),
    'cipher' => $cipher
], JSON_PRETTY_PRINT));
file_put_contents($keyFile, base64_encode($key));
PHP
  PIVPN_GUI_PASSWORD="${password}" php "${tmp_script}" "${PASSWORD_DIR}/password.enc" "${PASSWORD_DIR}/secret.key"
  rm -f "${tmp_script}"
  chmod 640 "${PASSWORD_DIR}/password.enc" "${PASSWORD_DIR}/secret.key"
  chown root:"${WEB_USER}" "${PASSWORD_DIR}/password.enc" "${PASSWORD_DIR}/secret.key"
}

create_reset_password_bin() {
  cat <<'EOF' > "${RESET_BIN}"
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="pivpn-web-gui"
WEB_USER="www-data"
PASSWORD_DIR="/etc/${APP_NAME}"
PASSWORD_FILE="${PASSWORD_DIR}/password.enc"
KEY_FILE="${PASSWORD_DIR}/secret.key"

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

tmp_script=$(mktemp)
cat <<'PHP' > "${tmp_script}"
<?php
$password = getenv('PIVPN_GUI_PASSWORD');
$passwordFile = $argv[1];
$keyFile = $argv[2];
if ($password === false || $password === '') {
    fwrite(STDERR, "Falta PIVPN_GUI_PASSWORD\n");
    exit(1);
}
$key = file_exists($keyFile) ? base64_decode(file_get_contents($keyFile)) : random_bytes(32);
$hash = password_hash($password, PASSWORD_DEFAULT);
$iv = random_bytes(openssl_cipher_iv_length('aes-256-cbc'));
$cipher = openssl_encrypt($hash, 'aes-256-cbc', $key, 0, $iv);
file_put_contents($passwordFile, json_encode([
    'iv' => base64_encode($iv),
    'cipher' => $cipher
], JSON_PRETTY_PRINT));
file_put_contents($keyFile, base64_encode($key));
PHP
PIVPN_GUI_PASSWORD="${pass1}" php "${tmp_script}" "${PASSWORD_FILE}" "${KEY_FILE}"
rm -f "${tmp_script}"

chown root:"${WEB_USER}" "${PASSWORD_FILE}" "${KEY_FILE}"
chmod 640 "${PASSWORD_FILE}" "${KEY_FILE}"

systemctl reload apache2 >/dev/null 2>&1 || true

echo "[OK] Contraseña actualizada"
EOF

  chmod +x "${RESET_BIN}"
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
rm -f "${RESET_BIN}"
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

  echo "[OK] Instalación finalizada. La GUI está disponible en http://<host>:${SERVICE_PORT}/"
  echo "[INFO] Para desinstalar ejecute: sudo ${UNINSTALL_BIN}"
}

main "$@"
