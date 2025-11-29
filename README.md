# Instalador PiVPN Web GUI (OpenVPN)

Script de despliegue para Ubuntu 24.04 que publica el panel PHP ubicado en `frontend/` y lo deja listo detrás de un proxy. El instalador asume que **PiVPN con OpenVPN ya está configurado** y que existe `/etc/pivpn/openvpn/setupVars.conf`.

## Qué hace el instalador
- Instala Apache + PHP y dependencias requeridas (sin npm).
- Copia el frontend a `/var/www/pivpn-web-gui` y crea un **login protegido por contraseña**.
- Enlaza los perfiles `.ovpn` de PiVPN (`install_home/ovpns`) al directorio web.
- Configura sudoers para que `www-data` ejecute `pivpn` sin contraseña.
- Publica el sitio en el puerto `51821` (cámbielo con la variable `PIVPN_WEB_PORT`).
- Genera un almacén cifrado para la contraseña de acceso en `/etc/pivpn-web-gui`.
- Habilita rotación de logs en `/var/log/pivpn-web-gui`.
- Crea el script de desinstalación `pivpn-web-gui-uninstall`.

## Requisitos previos
- Ubuntu 24.04 (amd64/arm probados con paquetes nativos).
- PiVPN (OpenVPN) ya instalado y operativo.
- Ejecute como `root` o con `sudo`.
- Tras instalar PiVPN/OpenVPN cree al menos un cliente inicial (ejemplo):
  - `pivpn -a -n TESTVPN nopass -d 1080`

## Instalación
```bash
cd /ruta/al/repositorio
sudo bash install.sh
```
Durante la instalación se le pedirá la contraseña para acceder al panel.

### Variables opcionales
- `PIVPN_WEB_PORT`: Puerto donde escuchará Apache para el panel (por defecto `51821`).

## Desinstalación
```bash
sudo /usr/local/bin/pivpn-web-gui-uninstall
```

## Credenciales y seguridad
- La contraseña se almacena como `password_hash` cifrada con AES-256-CBC en `/etc/pivpn-web-gui/password.enc`.
- La clave simétrica reside en `/etc/pivpn-web-gui/secret.key` (permisos `640`, grupo `www-data`).
- El panel fuerza login antes de ejecutar comandos PiVPN.

### Cambiar la contraseña de ingreso
Ejecute el asistente y defina la nueva contraseña cuando se le solicite:

```bash
sudo pivpn-web-gui-reset-password
```

### Recuperar o resetear la contraseña de ingreso
Si el login falla o pierde la contraseña, regenere el almacén cifrado con un valor nuevo:

```bash
sudo PIVPN_GUI_PASSWORD="NUEVA_CONTRASEÑA" php -r '
$pwd = getenv("PIVPN_GUI_PASSWORD");
if (!$pwd) { fwrite(STDERR, "Falta PIVPN_GUI_PASSWORD\\n"); exit(1); }
$passwordFile = "/etc/pivpn-web-gui/password.enc";
$keyFile = "/etc/pivpn-web-gui/secret.key";
$key = file_exists($keyFile) ? base64_decode(file_get_contents($keyFile)) : random_bytes(32);
$hash = password_hash($pwd, PASSWORD_DEFAULT);
$iv = random_bytes(openssl_cipher_iv_length("aes-256-cbc"));
$cipher = openssl_encrypt($hash, "aes-256-cbc", $key, 0, $iv);
file_put_contents($passwordFile, json_encode(["iv" => base64_encode($iv), "cipher" => $cipher], JSON_PRETTY_PRINT));
file_put_contents($keyFile, base64_encode($key));
';
sudo chown root:www-data /etc/pivpn-web-gui/password.enc /etc/pivpn-web-gui/secret.key
sudo chmod 640 /etc/pivpn-web-gui/password.enc /etc/pivpn-web-gui/secret.key
sudo systemctl reload apache2
```

## Logs
- Acciones del panel: `/var/log/pivpn-web-gui/actions.log`.
- Apache (sitio): `/var/log/pivpn-web-gui/apache-access.log` y `apache-error.log`.

## Alcance
El instalador realiza despliegues **nuevos**. Las actualizaciones del código deberán reemplazarse manualmente o mediante un futuro modo `update`.
