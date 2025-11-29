# Panel de Administración PiVPN

Este es un panel web liviano escrito en PHP para administrar clientes de PiVPN (WireGuard/OpenVPN).

## Funcionalidades

- Crear cliente VPN
- Listar clientes existentes (`pivpn -l`)
- Ver conexiones activas (`pivpn -c`)
- Descargar/eliminar archivos `.ovpn`

## Requisitos

- PiVPN instalado correctamente
- `www-data` con permisos en sudoers para:
  - `/usr/local/bin/pivpn`
  - `/bin/ls`, `/bin/rm` para `/var/www/html/vpn/ovpns`
- Servidor web con PHP 7.4+ (Apache, Nginx, etc.)

## Archivos

- `index.php`: Interfaz web (modo oscuro, Bootstrap 5)
- `engine.php`: Backend para creación y eliminación
- `assets/css/styles.css`: Espacio para personalizar estilos

## Seguridad

La validación del nombre del cliente solo permite: letras, números, guion y guion bajo.

