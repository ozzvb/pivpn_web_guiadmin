#! /bin/bash -x

#VARIABLES GLOBALES
userInstall=$EUID
installDir=$(cat /etc/pivpn/setupVars.conf | grep install_home | cut -d "=" -f 2)
systemDirWeb="/var/www/html"

#VERIFICAR USUARIO

if [ "$userInstall" != "0"  ]
then
	echo  The script must be run by root!
	echo  Please run the script again via root or via sudo
	exit 2
fi

#INSTALANDO DEPENDENCIAS
echo Instalando dependencias.
apt install -y  apache2 libapache2-mod-php php php-cli sudo acl acl2

#CREAR VPN SOPORTE
/usr/local/bin/pivpn -a nopass -n support -d 1080

#Copiar Sistema en WEB - Server
rsync -av --delete  ./WEB_SYSTEM/ "$systemDirWeb"

#Crear enlace a los pvpn
ln -s "$installDir/ovpns" "$systemDirWeb/ovpns"

#Cambiar permisos
chmod 775 "$systemDirWeb" -R
setfacl -R -m u:www-data:rwx "$installDir/ovpns"  
setfacl -R -m d:u:www-data:rwx "$installDir/ovpns"

#Permir comandos
echo User_Alias WWW_USER = www-data >> /etc/sudoers
echo Cmnd_Alias WWW_COMMANDS = /usr/local/bin/pivpn *, /bin/ls -w 1 /var/www/html/ovpns, /bin/rm /var/www/html/ovpns* >> /etc/sudoers
echo 'WWW_USER ALL = (ALL) NOPASSWD: WWW_COMMANDS' >> /etc/sudoers
 
