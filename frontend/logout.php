<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

logout_user();
log_action('Sesión cerrada por el usuario');
header('Location: /login.php');
exit;
