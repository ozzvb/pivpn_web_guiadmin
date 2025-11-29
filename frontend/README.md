# Panel de Administración PiVPN

Este es un panel web liviano escrito en PHP para administrar clientes de PiVPN (WireGuard/OpenVPN).

## Funcionalidades

- Login protegido por contraseña (almacenada cifrada en `/etc/pivpn-web-gui`).
- Crear cliente VPN.
- Listar clientes existentes (`pivpn -l`).
- Ver conexiones activas (`pivpn -c`).
- Descargar/eliminar archivos `.ovpn`.

## Requisitos

- PiVPN instalado correctamente (OpenVPN).
- `www-data` con permisos en sudoers para:
  - `/usr/local/bin/pivpn`
  - `/bin/ls`, `/bin/rm` para `/var/www/pivpn-web-gui/ovpns`
- Servidor web con PHP 8+ (Apache recomendado).

## Archivos

- `index.php`: Interfaz web (modo oscuro, Bootstrap 5)
- `engine.php`: Backend para creación y eliminación
- `login.php`: Página de autenticación
- `logout.php`: Salida de sesión
- `bootstrap.php`: Utilidades compartidas (autenticación, logs, rutas)
- `assets/css/styles.css`: Espacio para personalizar estilos

## Seguridad

- La validación del nombre del cliente solo permite: letras, números, guion y guion bajo.
- El panel exige autenticación antes de ejecutar comandos PiVPN.

