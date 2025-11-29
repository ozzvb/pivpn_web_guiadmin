<?php
function validarNombre($nombre) {
    // Acepta letras, números, guion y guion bajo, entre 1 y 30 caracteres
    return preg_match('/^[a-zA-Z0-9_-]{1,30}$/', $nombre);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['crearVPN'])) {
    $vpnNombre = $_POST['nombreVPN'] ?? '';

    if (validarNombre($vpnNombre)) {
        $nombreSeguro = escapeshellarg($vpnNombre);
        shell_exec("sudo /usr/local/bin/pivpn -a nopass -n $nombreSeguro -d 1080");
        header("Location: index.php?status=created");
        exit;
    } else {
        header("Location: index.php?status=invalid");
        exit;
    }
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['deleteVPN'])) {
    $vpnNombre = basename(str_replace('.ovpn', '', $_GET['deleteVPN'] ?? ''));

    if (validarNombre($vpnNombre)) {
        $nombreSeguro = escapeshellarg($vpnNombre);
        shell_exec("sudo /usr/local/bin/pivpn -r $nombreSeguro -y");
        shell_exec("sudo /bin/rm /var/www/vpn/ovpns/$vpnNombre.ovpn");
        header("Location: index.php?status=deleted");
        exit;
    } else {
        header("Location: index.php?status=invalid");
        exit;
    }
}
?>
