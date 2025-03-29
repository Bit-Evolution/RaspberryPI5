#!/bin/bash

# Farben für die Ausgabe
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Funktion zum Prüfen, ob ein Befehl erfolgreich war
check_success() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Fehler bei der Ausführung des letzten Befehls. Skript wird beendet.${NC}"
        exit 1
    fi
}

# --- System aktualisieren ---
echo -e "${GREEN}Aktualisiere das System...${NC}"
sudo apt update && sudo apt upgrade -y
check_success

# --- Notwendige Pakete installieren ---
echo -e "${GREEN}Installiere notwendige Pakete...${NC}"
sudo apt install -y curl wget git unzip jq
check_success

# --- Docker installieren ---
echo -e "${GREEN}Installiere Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
check_success
sudo usermod -aG docker $USER
newgrp docker

# --- Docker Compose installieren ---
echo -e "${GREEN}Installiere Docker Compose...${NC}"
sudo apt install -y docker-compose
check_success

# --- Verzeichnisse für Datenpersistenz erstellen ---
echo -e "${GREEN}Erstelle Verzeichnisse für Datenpersistenz...${NC}"
mkdir -p ~/docker/{proxy,webserver,mailserver}
check_success

# --- Eingabeaufforderungen für Konfigurationsdetails ---
read -p "Gib deine Domain ein (z.B. meinefirma.dyndns.http.net): " DOMAIN
read -p "Gib deine E-Mail-Adresse für Let's Encrypt ein: " EMAIL

# --- Abfrage zur Deaktivierung von Bluetooth ---
read -p "Soll Bluetooth deaktiviert werden? (y/n): " DISABLE_BT
if [ "$DISABLE_BT" == "y" ]; then
    echo -e "${GREEN}Deaktiviere Bluetooth...${NC}"
    sudo systemctl disable bluetooth
    sudo systemctl stop bluetooth
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/config.txt
    echo -e "${GREEN}Bluetooth wurde deaktiviert. Ein Neustart ist erforderlich.${NC}"
fi

# --- Abfrage zur Deaktivierung von WLAN ---
read -p "Soll WLAN deaktiviert werden? (y/n): " DISABLE_WIFI
if [ "$DISABLE_WIFI" == "y" ]; then
    echo -e "${GREEN}Deaktiviere WLAN...${NC}"
    sudo iwconfig wlan0 down
    sudo ip link set wlan0 down
    echo "dtoverlay=disable-wifi" | sudo tee -a /boot/config.txt
    echo -e "${GREEN}WLAN wurde deaktiviert. Ein Neustart ist erforderlich.${NC}"
fi

# --- NGINX Proxy Manager installieren ---
echo -e "${GREEN}Installiere NGINX Proxy Manager...${NC}"
docker run -d \
  --name nginx-proxy-manager \
  -p 80:80 \
  -p 443:443 \
  -p 81:81 \
  -v ~/docker/proxy/data:/data \
  -v ~/docker/proxy/letsencrypt:/etc/letsencrypt \
  --restart=unless-stopped \
  jlesage/nginx-proxy-manager
check_success

# Warte kurz, bis NGINX Proxy Manager gestartet ist
sleep 10

# --- NGINX Proxy Manager konfigurieren ---
echo -e "${GREEN}Bitte öffne http://<RaspberryPi-IP>:81 im Browser und konfiguriere NGINX Proxy Manager.${NC}"
echo -e "${GREEN}Standard-Login: admin@example.com / changeme${NC}"
echo -e "${GREEN}Erstelle Proxy Hosts für alle Dienste mit SSL über Let's Encrypt.${NC}"
echo -e "${GREEN}Beispiel für Subdomains: web.$DOMAIN -> Webserver, mail.$DOMAIN -> Mailserver${NC}"
read -p "Drücke Enter, wenn du die Konfiguration abgeschlossen hast..."

# --- Webserver-Container installieren ---
echo -e "${GREEN}Installiere Webserver-Container...${NC}"
docker run -d \
  --name webserver \
  -p 3000:3000 \
  -v ~/docker/webserver/data:/config \
  --restart=unless-stopped \
  linuxserver/webtop
check_success

# --- Mailserver mit Roundcube installieren ---
echo -e "${GREEN}Installiere Mailserver mit Roundcube...${NC}"
docker run -d \
  --name mailserver \
  -p 25:25 \
  -p 143:143 \
  -p 587:587 \
  -p 993:993 \
  -v ~/docker/mailserver/data:/var/mail \
  -v ~/docker/mailserver/config:/tmp/docker-mailserver \
  --restart=unless-stopped \
  mailserver/docker-mailserver
check_success

# --- Abschluss ---
echo -e "${GREEN}Installation abgeschlossen!${NC}"
echo -e "${GREEN}Bitte konfiguriere die Dienste über NGINX Proxy Manager und teste die Funktionalität:${NC}"
echo -e "- Webserver: http://<RaspberryPi-IP>:3000 oder https://web.$DOMAIN (nach Konfiguration)"
echo -e "- Mailserver mit Roundcube: Konfiguriere über https://mail.$DOMAIN (nach Setup)"
echo -e "${GREEN}Hinweis: Für den Mailserver musst du die Konfiguration in ~/docker/mailserver/config anpassen.${NC}"
echo -e "${GREEN}Für Subdomains: Nutze NGINX Proxy Manager, um Subdomains wie web.$DOMAIN oder mail.$DOMAIN zu routen.${NC}"
