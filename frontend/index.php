<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
require_authentication();
?>
<!doctype html>
<html lang="es" data-bs-theme="dark">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Administrador PiVPN</title>
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">

  <!-- Estilos propios -->
  <style>
    /* Tabla dinámica en móvil, ancho completo en escritorio */
    .table-auto-width {
      width: auto;
      max-width: 100%;
      margin-left: auto;
      margin-right: auto;
    }
    @media (min-width: 768px) {
      .table-auto-width {
        width: 100%;
        max-width: 100%;
      }
    }
    /* Mantener celdas en una línea en escritorio */
    @media (min-width: 768px) {
      .table-auto-width td,
      .table-auto-width th {
        white-space: nowrap;
      }
    }
    /* En móvil permitir quiebres */
    @media (max-width: 767.98px) {
      .table-auto-width td,
      .table-auto-width th {
        white-space: normal;
        word-break: break-word;
      }
    }
  </style>

  <script>
  document.addEventListener("DOMContentLoaded", function () {
    const input = document.getElementById("nombreVPN");
    if (input) {
      input.addEventListener("input", function () {
        this.value = this.value.replace(/[^a-zA-Z0-9_-]/g, '');
      });
    }
  });
  </script>
</head>
<body class="bg-dark text-light">

<nav class="navbar navbar-expand-lg navbar-dark bg-black mb-4 shadow-sm">
  <div class="container-fluid">
    <a class="navbar-brand" href="#">
      <img src="http://www.pivpn.io/images/pivpn_logo.png" alt="" width="30" height="30" class="me-2">
      Panel Administrador PiVPN
    </a>
    <div class="d-flex ms-auto">
      <a class="btn btn-outline-light btn-sm" href="logout.php">Cerrar sesión</a>
    </div>
  </div>
</nav>

<div class="container">

  <?php
    // Mensajes de estado
    $statusMap = [
      'created' => ['success', 'Cliente creado exitosamente.'],
      'deleted' => ['warning', 'Cliente eliminado.'],
      'invalid' => ['danger',  'Nombre inválido.'],
      'ok'      => ['secondary','Acción completada.']
    ];
    if (isset($_GET['status']) && isset($statusMap[$_GET['status']])) {
      [$cls, $msg] = $statusMap[$_GET['status']];
      echo '<div class="alert alert-'.$cls.' alert-dismissible fade show" role="alert">'
          . htmlspecialchars($msg)
          . '<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>'
          . '</div>';
    }
  ?>

  <!-- Crear cliente VPN -->
  <div class="card bg-secondary mb-4 shadow">
    <div class="card-header text-white">Crear cliente VPN</div>
    <div class="card-body">
      <form action="engine.php" method="post">
        <div class="mb-3">
          <input
            type="text"
            class="form-control"
            id="nombreVPN"
            name="nombreVPN"
            placeholder="Ingrese el nombre del cliente VPN"
            required
            pattern="[a-zA-Z0-9_-]{1,30}"
            title="Solo letras, números, guion y guion bajo (máx 30 caracteres)">
          <div class="form-text text-light">
            Use solo letras, números, guion o guion bajo. Máximo 30 caracteres.
          </div>
        </div>
        <button type="submit" name="crearVPN" class="btn btn-success w-100">Crear cliente</button>
      </form>
    </div>
  </div>

  <!-- Listado de clientes -->
  <div class="card bg-dark mb-4 shadow" id="lista">
    <div class="card-header text-white">Clientes VPN</div>
    <div class="card-body">
      <pre class="bg-black p-2 text-success border rounded"><?php echo shell_exec('sudo /usr/local/bin/pivpn -l | grep -v Revoked'); ?></pre>
      <a href="#lista" class="btn btn-outline-success w-100 mt-2">Actualizar listado</a>
    </div>
  </div>

  <!-- Conexiones activas -->
  <div class="card bg-dark mb-4 shadow" id="con">
    <div class="card-header text-white">Conexiones VPN activas</div>
    <div class="card-body">
      <pre class="bg-black p-2 text-info border rounded"><?php echo shell_exec('sudo /usr/local/bin/pivpn -c'); ?></pre>
      <a href="#con" class="btn btn-outline-info w-100 mt-2">Actualizar estado</a>
    </div>
  </div>

  <!-- Archivos .ovpn -->
  <div class="card bg-dark mb-4 shadow">
    <div class="card-header text-white">Administrar archivos de cliente</div>
    <div class="card-body">

      <?php
        $archivos = list_ovpn_files();
      ?>

      <div class="table-responsive">
        <table class="table table-dark table-striped align-middle text-center table-auto-width">
          <thead>
            <tr>
              <th>Cliente VPN</th>
              <th class="d-none d-md-table-cell">Descargar</th>
              <th class="d-none d-md-table-cell">Eliminar</th>
            </tr>
          </thead>
          <tbody>
            <?php if (empty($archivos)): ?>
              <tr>
                <td colspan="3" class="text-muted">No hay archivos .ovpn disponibles.</td>
              </tr>
            <?php else: ?>
              <?php foreach ($archivos as $archivo): ?>
                <tr>
                  <td class="text-start">
                    <?= htmlspecialchars($archivo) ?>
                    <div class="d-flex flex-column flex-sm-row gap-2 mt-2 d-md-none">
                      <a href="/ovpns/<?= rawurlencode($archivo) ?>" download
                         class="btn btn-outline-success btn-sm">Descargar</a>
                      <a href="engine.php?deleteVPN=<?= rawurlencode($archivo) ?>"
                         class="btn btn-outline-danger btn-sm"
                         onclick="return confirm('¿Eliminar <?= htmlspecialchars($archivo) ?>?');">
                        Eliminar
                      </a>
                    </div>
                  </td>
                  <td class="d-none d-md-table-cell">
                    <a href="/ovpns/<?= rawurlencode($archivo) ?>" download
                       class="btn btn-outline-success btn-sm w-100">Descargar</a>
                  </td>
                  <td class="d-none d-md-table-cell">
                    <a href="engine.php?deleteVPN=<?= rawurlencode($archivo) ?>"
                       class="btn btn-outline-danger btn-sm w-100"
                       onclick="return confirm('¿Eliminar <?= htmlspecialchars($archivo) ?>?');">
                      Eliminar
                    </a>
                  </td>
                </tr>
              <?php endforeach; ?>
            <?php endif; ?>
          </tbody>
        </table>
      </div>

    </div>
  </div>

  <footer class="text-center mt-4 mb-2 text-muted">
    <small>
      <a href="https://github.com/ozzvb" class="text-decoration-none text-muted">ozzvb</a> |
      <a href="https://github.com/pivpn/pivpn" class="text-decoration-none text-muted">pivpn</a>
    </small>
  </footer>

</div><!-- /.container -->

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>

