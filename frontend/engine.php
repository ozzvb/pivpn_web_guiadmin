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
        $output = [];
        $exitCode = 0;
        exec("sudo /usr/local/bin/pivpn -a nopass -n $nombreSeguro -d 1080 2>&1", $output, $exitCode);
        if ($exitCode === 0) {
            log_action("Cliente creado: {$vpnNombre}");
            set_flash('success', 'Cliente creado exitosamente.');
        } else {
            log_action("Error al crear cliente {$vpnNombre}: " . implode(' | ', $output));
            set_flash('danger', 'No se pudo crear el cliente. Revise el log de acciones.');
        }
        header('Location: index.php');
        exit;
    }

    set_flash('danger', 'Nombre inválido. Use solo letras, números, guion o guion bajo.');
    header('Location: index.php');
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['deleteVPN'])) {
    $vpnNombre = basename(str_replace('.ovpn', '', $_GET['deleteVPN'] ?? ''));

    if (validarNombre($vpnNombre)) {
        $nombreSeguro = escapeshellarg($vpnNombre);
        $output = [];
        $exitCode = 0;
        exec("sudo /usr/local/bin/pivpn -r $nombreSeguro -y 2>&1", $output, $exitCode);
        if ($exitCode === 0) {
            exec("sudo /bin/rm " . escapeshellarg(OVPN_DIR . "/$vpnNombre.ovpn") . ' 2>&1');
            log_action("Cliente eliminado: {$vpnNombre}");
            set_flash('warning', 'Cliente eliminado.');
        } else {
            log_action("Error al eliminar cliente {$vpnNombre}: " . implode(' | ', $output));
            set_flash('danger', 'No se pudo eliminar el cliente. Revise el log de acciones.');
        }
        header('Location: index.php');
        exit;
    }

    set_flash('danger', 'Nombre inválido. Use solo letras, números, guion o guion bajo.');
    header('Location: index.php');
    exit;
}

set_flash('secondary', 'Sin cambios solicitados.');
header('Location: index.php');
exit;
