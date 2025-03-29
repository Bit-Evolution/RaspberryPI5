#!/bin/bash

# Skript zur automatischen Installation eines abgesicherten Servers auf Raspberry Pi 5
# Erstellt für NextcloudPi, Docker, Nginx Proxy Manager, Bitwarden, Floccus und Webserver

# Farben für Ausgabe
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Willkommen beim Raspberry Pi 5 Setup-Skript!${NC}"
echo "Dieses Skript richtet eine Docker-Umgebung, NextcloudPi, Bitwarden, Floccus und einen Webserver ein."

# Überprüfen, ob das Skript als Root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Bitte führe dieses Skript als Root aus (mit sudo).${NC}"
    exit 1
fi

# System aktualisieren
echo -e "${GREEN}Aktualisiere das System...${NC}"
apt update && apt upgrade -y

# Eingabeaufforderungen für benutzerdefinierte Konfigurationen
read -p "Gib deine Haupt-Domain ein (z. B. example.com): " DOMAIN
read -p "Gib deine E-Mail-Adresse für Let's Encrypt ein: " EMAIL
read -p "Gib deinen HTTP.net DynDNS-Benutzernamen ein: " DYNDNS_USER
read -p "Gib dein HTTP.net DynDNS-Passwort ein: " DYNDNS_PASS
read -p "Gib den gewünschten Bitwarden-Admin-Token ein: " BW_ADMIN_TOKEN

# 1. Docker und Nginx Proxy Manager installieren
echo -e "${GREEN}Installiere Docker und Docker Compose...${NC}"
apt install docker.io docker-compose -y
systemctl enable docker
systemctl start docker

echo -e "${GREEN}Richte Nginx Proxy Manager ein...${NC}"
mkdir -p /home/pi/nginx-proxy
cat <<EOF > /home/pi/nginx-proxy/docker-compose.yml
version: '3'
services:
  app:
    image: 'jc21/nginx-proxy-manager:latest'
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
      - '81:81'
    environment:
      DB_MYSQL_HOST: "db"
      DB_MYSQL_PORT: 3306
      DB_MYSQL_USER: "npm"
      DB_MYSQL_PASSWORD: "npm_password"
      DB_MYSQL_DATABASE: "npm"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
  db:
    image: 'mariadb:latest'
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "npm_root_password"
      MYSQL_DATABASE: "npm"
      MYSQL_USER: "npm"
      MYSQL_PASSWORD: "npm_password"
    volumes:
      - ./mysql:/var/lib/mysql
EOF
cd /home/pi/nginx-proxy
docker-compose up -d

# Konfiguration von Let's Encrypt und Domains erfolgt später über die Nginx Proxy Manager UI

# 2. NextcloudPi Installation und Festplatten-Einbindung
echo -e "${GREEN}Installiere NextcloudPi in Docker...${NC}"
mkdir -p /home/pi/nextcloudpi

# Erkenne angeschlossene Festplatten
echo -e "${GREEN}Suche nach angeschlossenen Festplatten...${NC}"
DISKS=$(lsblk -o NAME,TYPE | grep disk | awk '{print $1}')
MOUNT_POINTS=""
for DISK in $DISKS; do
    DISK_PATH="/dev/$DISK"
    MOUNT_DIR="/mnt/$DISK"
    mkdir -p "$MOUNT_DIR"
    mkfs.ext4 -F "$DISK_PATH" || echo "Festplatte $DISK_PATH bereits formatiert"
    mount "$DISK_PATH" "$MOUNT_DIR"
    echo "$DISK_PATH $MOUNT_DIR ext4 defaults 0 0" >> /etc/fstab
    MOUNT_POINTS="$MOUNT_POINTS -v $MOUNT_DIR:/data/$DISK"
done

cat <<EOF > /home/pi/nextcloudpi/docker-compose.yml
version: '3'
services:
  nextcloudpi:
    image: ownyourbits/nextcloudpi:latest
    restart: unless-stopped
    ports:
      - "4443:4443"
      - "8080:80"
      - "8443:443"
    volumes:
      - /home/pi/nextcloudpi/data:/data
      $MOUNT_POINTS
    environment:
      - TRUSTED_DOMAINS=cloud.$DOMAIN
EOF
cd /home/pi/nextcloudpi
docker-compose up -d

# 3. Nextcloud-Plugins installieren
echo -e "${GREEN}Installiere empfohlene Nextcloud-Plugins...${NC}"
docker exec -it nextcloudpi ncp-config <<EOF
ncp-app install files_automatedtagging
ncp-app install groupfolders
ncp-app install tasks
ncp-app install calendar
ncp-app install contacts
ncp-app install notes
ncp-app install drawio
ncp-app install documentserver_community
EOF

# 4. Webserver mit MySQL, PHP, FTP, WebDAV und Verwaltungsoberfläche
echo -e "${GREEN}Richte Webserver mit Verwaltungsoberfläche ein...${NC}"
mkdir -p /home/pi/webserver
cat <<EOF > /home/pi/webserver/docker-compose.yml
version: '3'
services:
  web:
    image: litespeedtech/openlitespeed:latest
    restart: unless-stopped
    ports:
      - "7080:7080" # Admin UI
    volumes:
      - /home/pi/webserver/html:/var/www/vhosts/localhost/html
    environment:
      - ADMIN_USER=admin
      - ADMIN_PASSWORD=admin_password
  mysql:
    image: mariadb:latest
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=root_password
      - MYSQL_DATABASE=webdb
      - MYSQL_USER=webuser
      - MYSQL_PASSWORD=webpass
    volumes:
      - /home/pi/webserver/mysql:/var/lib/mysql
EOF
cd /home/pi/webserver
docker-compose up -d

# 5. Bitwarden Installation
echo -e "${GREEN}Installiere Bitwarden (Vaultwarden)...${NC}"
mkdir -p /home/pi/vaultwarden
cat <<EOF > /home/pi/vaultwarden/docker-compose.yml
version: '3'
services:
  vaultwarden:
    image: vaultwarden/server:latest
    restart: unless-stopped
    ports:
      - "8555:80"
    volumes:
      - /home/pi/vaultwarden/data:/data
    environment:
      - ADMIN_TOKEN=$BW_ADMIN_TOKEN
      - DOMAIN=https://bitwarden.$DOMAIN
EOF
cd /home/pi/vaultwarden
docker-compose up -d

# 6. Floccus Installation
echo -e "${GREEN}Installiere Floccus...${NC}"
mkdir -p /home/pi/floccus
cat <<EOF > /home/pi/floccus/docker-compose.yml
version: '3'
services:
  floccus:
    image: floccus/floccus:latest
    restart: unless-stopped
    ports:
      - "8666:80"
    volumes:
      - /home/pi/floccus/data:/data
EOF
cd /home/pi/floccus
docker-compose up -d

# DynDNS Einrichtung für HTTP.net
echo -e "${GREEN}Richte DynDNS mit HTTP.net ein...${NC}"
apt install ddclient -y
cat <<EOF > /etc/ddclient.conf
daemon=300
syslog=yes
pid=/var/run/ddclient.pid
protocol=dyndns2
use=web, web=checkip.dyndns.org/, web-skip='Current IP Address: '
server=dynupdate.http.net
login=$DYNDNS_USER
password=$DYNDNS_PASS
$DOMAIN
EOF
systemctl restart ddclient

# Sicherheitskonfiguration
echo -e "${GREEN}Sichere das System ab...${NC}"
apt install fail2ban ufw -y
ufw allow 22
ufw allow 80
ufw allow 443
ufw allow 4443
ufw allow 7080
ufw allow 8080
ufw allow 8443
ufw allow 8555
ufw allow 8666
ufw enable

# Abschluss
echo -e "${GREEN}Installation abgeschlossen!${NC}"
echo "Nginx Proxy Manager: http://<Pi-IP>:81 (Domain- und Zertifikatskonfiguration)"
echo "NextcloudPi: https://cloud.$DOMAIN:4443"
echo "Webserver Admin: http://$DOMAIN:7080"
echo "Bitwarden: http://bitwarden.$DOMAIN:8555"
echo "Floccus: http://<Pi-IP>:8666"
echo "Bitte konfiguriere Nginx Proxy Manager für SSL und Domains."
