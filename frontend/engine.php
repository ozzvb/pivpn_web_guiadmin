<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_authentication();

function validarNombre(string $nombre): bool
{
    return (bool) preg_match('/^[a-zA-Z0-9_-]{1,30}$/', $nombre);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['crearVPN'])) {
    $vpnNombre = $_POST['nombreVPN'] ?? '';

    if (validarNombre($vpnNombre)) {
        $nombreSeguro = escapeshellarg($vpnNombre);
        shell_exec("sudo /usr/local/bin/pivpn -a nopass -n $nombreSeguro -d 1080");
        log_action("Cliente creado: {$vpnNombre}");
        header("Location: index.php?status=created");
        exit;
    }

    header("Location: index.php?status=invalid");
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['deleteVPN'])) {
    $vpnNombre = basename(str_replace('.ovpn', '', $_GET['deleteVPN'] ?? ''));

    if (validarNombre($vpnNombre)) {
        $nombreSeguro = escapeshellarg($vpnNombre);
        shell_exec("sudo /usr/local/bin/pivpn -r $nombreSeguro -y");
        shell_exec("sudo /bin/rm " . escapeshellarg(OVPN_DIR . "/$vpnNombre.ovpn"));
        log_action("Cliente eliminado: {$vpnNombre}");
        header("Location: index.php?status=deleted");
        exit;
    }

    header("Location: index.php?status=invalid");
    exit;
}

header("Location: index.php?status=ok");
exit;
