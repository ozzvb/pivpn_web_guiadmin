<?php
declare(strict_types=1);

session_set_cookie_params([
    'httponly' => true,
    'secure' => isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== '' && $_SERVER['HTTPS'] !== 'off',
    'samesite' => 'Lax',
]);
session_name('pivpn_web_gui');
session_start();

const PASSWORD_FILE = '/etc/pivpn-web-gui/password.txt';
const LOG_FILE = '/var/log/pivpn-web-gui/actions.log';
const OVPN_DIR = '/var/www/pivpn-web-gui/ovpns';
const SESSION_FLAG = 'pivpn_authenticated';
const FLASH_KEY = 'pivpn_flash';

function read_password_plain(): string
{
    if (!file_exists(PASSWORD_FILE)) {
        http_response_code(500);
        exit('Falta el almacén de credenciales. Ejecute el instalador nuevamente.');
    }

    $raw = file_get_contents(PASSWORD_FILE);
    if (!is_string($raw) || $raw === '') {
        http_response_code(500);
        exit('El almacén de credenciales está vacío o dañado.');
    }

    return trim($raw);
}

function verify_gui_password(string $password): bool
{
    return hash_equals(read_password_plain(), $password);
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
    $_SESSION = [];
    if (PHP_SESSION_ACTIVE === session_status()) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000, $params['path'], $params['domain'], $params['secure'], $params['httponly']);
    }
    session_destroy();
}

function set_flash(string $type, string $message): void
{
    $_SESSION[FLASH_KEY] = ['type' => $type, 'message' => $message];
}

function consume_flash(): ?array
{
    if (!isset($_SESSION[FLASH_KEY]) || !is_array($_SESSION[FLASH_KEY])) {
        return null;
    }

    $flash = $_SESSION[FLASH_KEY];
    unset($_SESSION[FLASH_KEY]);
    return $flash;
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
