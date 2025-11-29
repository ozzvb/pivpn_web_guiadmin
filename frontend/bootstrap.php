<?php
declare(strict_types=1);

session_name('pivpn_web_gui');
session_start();

const PASSWORD_FILE = '/etc/pivpn-web-gui/password.enc';
const KEY_FILE = '/etc/pivpn-web-gui/secret.key';
const LOG_FILE = '/var/log/pivpn-web-gui/actions.log';
const OVPN_DIR = '/var/www/pivpn-web-gui/ovpns';
const SESSION_FLAG = 'pivpn_authenticated';

function read_password_hash(): string
{
    if (!file_exists(PASSWORD_FILE) || !file_exists(KEY_FILE)) {
        http_response_code(500);
        exit('Falta el almacén de credenciales. Ejecute el instalador nuevamente.');
    }

    $passwordData = json_decode((string) file_get_contents(PASSWORD_FILE), true);
    if (!is_array($passwordData) || empty($passwordData['iv']) || empty($passwordData['cipher'])) {
        http_response_code(500);
        exit('El formato del almacén de credenciales no es válido.');
    }

    $key = base64_decode((string) file_get_contents(KEY_FILE), true);
    $iv = base64_decode((string) $passwordData['iv'], true);
    $cipher = (string) $passwordData['cipher'];

    if ($key === false || $iv === false) {
        http_response_code(500);
        exit('No se pudo decodificar el almacén de credenciales.');
    }

    $hash = openssl_decrypt($cipher, 'aes-256-cbc', $key, 0, $iv);
    if (!is_string($hash) || $hash === '') {
        http_response_code(500);
        exit('No se pudo desencriptar la contraseña.');
    }

    return $hash;
}

function verify_gui_password(string $password): bool
{
    return password_verify($password, read_password_hash());
}

function complete_login(): void
{
    $_SESSION[SESSION_FLAG] = true;
}

function require_authentication(): void
{
    if (empty($_SESSION[SESSION_FLAG])) {
        header('Location: /login.php');
        exit;
    }
}

function logout_user(): void
{
    session_destroy();
}

function log_action(string $message): void
{
    $line = sprintf('[%s] %s%s', date('c'), $message, PHP_EOL);
    @file_put_contents(LOG_FILE, $line, FILE_APPEND | LOCK_EX);
}

function list_ovpn_files(): array
{
    $archivos = [];
    if (is_dir(OVPN_DIR)) {
        foreach (scandir(OVPN_DIR) ?: [] as $f) {
            if ($f === '.' || $f === '..') {
                continue;
            }
            $ruta = OVPN_DIR . DIRECTORY_SEPARATOR . $f;
            if (is_file($ruta)) {
                $archivos[] = $f;
            }
        }
    }
    natcasesort($archivos);
    return $archivos;
}
