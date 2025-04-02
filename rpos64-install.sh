#!/bin/bash

# Farben für die Ausgabe
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Funktion zum Überprüfen des Erfolgs eines Befehls
check_success() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Fehler bei der Ausführung des letzten Befehls. Skript wird beendet.${NC}"
        exit 1
    fi
}

# --- Automatische IP-Erkennung ---
echo -e "${GREEN}Ermittle lokale IP-Adresse...${NC}"
LOCAL_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "$LOCAL_IP" ]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
fi
if [ -z "$LOCAL_IP" ]; then
    echo -e "${RED}Konnte die IP-Adresse nicht ermitteln. Bitte überprüfe die Netzwerkverbindung.${NC}"
    exit 1
fi
echo -e "${GREEN}Lokale IP-Adresse: $LOCAL_IP${NC}"

# --- Benutzereingaben abfragen ---
read -p "Gib deine Domain ein (z.B. example.com): " DOMAIN
read -p "Gib deine E-Mail-Adresse für Let's Encrypt ein: " EMAIL
read -p "Gib deinen DynDNS-Benutzernamen ein: " DYNDNS_USER
read -s -p "Gib dein DynDNS-Passwort ein: " DYNDNS_PASS
echo ""
read -p "Möchtest du Gateway und DNS manuell eingeben? (y/n): " SET_NETWORK_MANUALLY
if [ "$SET_NETWORK_MANUALLY" == "y" ]; then
    read -p "Gib das Gateway ein (z.B. 192.168.1.1): " GATEWAY
    read -p "Gib die DNS-Server ein (z.B. 192.168.1.1,8.8.8.8): " DNS_SERVERS
else
    GATEWAY=$(ip route | grep default | awk '{print $3}')
    DNS_SERVERS=$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | paste -sd "," -)
fi
read -p "Soll Bluetooth deaktiviert werden? (y/n): " DISABLE_BT
read -p "Soll WLAN deaktiviert werden? (y/n): " DISABLE_WIFI
read -p "Verwendest du Raspberry Pi OS Desktop? (y/n): " USE_DESKTOP

# --- System aktualisieren (benötigt sudo) ---
echo -e "${GREEN}Aktualisiere das System...${NC}"
sudo apt update && sudo apt upgrade -y
check_success

# --- Notwendige Pakete installieren (benötigt sudo) ---
echo -e "${GREEN}Installiere notwendige Pakete...${NC}"
sudo apt install -y curl wget git unzip jq
check_success

# --- Docker installieren (benötigt sudo) ---
echo -e "${GREEN}Installiere Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
check_success
sudo usermod -aG docker $USER
echo -e "${GREEN}Hinweis: Bitte logge dich aus und wieder ein, um die Docker-Gruppenänderung zu aktivieren.${NC}"
newgrp docker

# --- Docker Compose installieren (benötigt sudo) ---
echo -e "${GREEN}Installiere Docker Compose...${NC}"
sudo apt install -y docker-compose
check_success

# --- Verzeichnisse für Datenpersistenz erstellen ---
echo -e "${GREEN}Erstelle Verzeichnisse für Datenpersistenz...${NC}"
mkdir -p ~/docker/{proxy,caprover,mailserver,nextcloud,bitwarden}
check_success

# --- Docker-Netzwerk erstellen ---
echo -e "${GREEN}Erstelle Docker-Netzwerk 'proxy_net'...${NC}"
sg docker -c "docker network create proxy_net"
check_success

# --- Skript für feste IP-Adresse erstellen ---
echo -e "${GREEN}Erstelle Skript für feste IP-Adresse...${NC}"
NETWORK=$(echo $LOCAL_IP | cut -d. -f1-3)
STATIC_IP="${NETWORK}.11"

cat << EOF > ~/set_static_ip.sh
#!/bin/bash
echo "interface eth0
static ip_address=${STATIC_IP}/24
static routers=${GATEWAY}
static domain_name_servers=${DNS_SERVERS}" | sudo tee /etc/dhcpcd.conf > /dev/null
sudo systemctl restart dhcpcd
EOF

chmod +x ~/set_static_ip.sh

# --- Skript zum Systemstart hinzufügen (benötigt sudo) ---
echo -e "${GREEN}Füge Skript zum Systemstart hinzu...${NC}"
sudo bash -c "echo '@reboot $USER /home/$USER/set_static_ip.sh' > /etc/cron.d/set_static_ip"
echo -e "${GREEN}Feste IP-Adresse ($STATIC_IP) wird bei jedem Start gesetzt.${NC}"

# --- Deaktivierung von Bluetooth und WLAN (benötigt sudo) ---
if [ "$DISABLE_BT" == "y" ]; then
    echo -e "${GREEN}Deaktiviere Bluetooth...${NC}"
    sudo systemctl disable bluetooth
    sudo systemctl stop bluetooth
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/config.txt
fi

if [ "$DISABLE_WIFI" == "y" ]; then
    echo -e "${GREEN}Deaktiviere WLAN...${NC}"
    sudo iwconfig wlan0 down
    sudo ip link set wlan0 down
    echo "dtoverlay=disable-wifi" | sudo tee -a /boot/config.txt
fi

# --- DynDNS-Einrichtung (benötigt sudo) ---
echo -e "${GREEN}Richte DynDNS ein...${NC}"
sudo apt install -y ddclient
echo "protocol=dyndns2
use=web, web=checkip.dyndns.org/, web-skip='IP Address'
server=dynupdate.http.net
login=$DYNDNS_USER
password=$DYNDNS_PASS
$DOMAIN" | sudo tee /etc/ddclient.conf
sudo systemctl restart ddclient
check_success
echo -e "${GREEN}Hinweis: Überprüfe die DynDNS-Konfiguration in /etc/ddclient.conf und passe sie bei Bedarf an.${NC}"

# --- NGINX Proxy Manager installieren ---
echo -e "${GREEN}Installiere NGINX Proxy Manager...${NC}"
sg docker -c "docker run -d \
  --name nginx-proxy-manager \
  --network proxy_net \
  -p 80:80 \
  -p 443:443 \
  -p 81:81 \
  -v ~/docker/proxy/data:/data \
  -v ~/docker/proxy/letsencrypt:/etc/letsencrypt \
  --restart=unless-stopped \
  jlesage/nginx-proxy-manager"
check_success

# Warte kurz, bis NGINX Proxy Manager gestartet ist
sleep 10

# --- NGINX Proxy Manager konfigurieren ---
echo -e "${GREEN}Bitte öffne http://$LOCAL_IP:81 im Browser und konfiguriere NGINX Proxy Manager.${NC}"
echo -e "${GREEN}Standard-Login: admin@example.com / changeme${NC}"
echo -e "${GREEN}Erstelle Proxy Hosts für alle Dienste mit SSL über Let's Encrypt.${NC}"
read -p "Drücke Enter, wenn du die Konfiguration abgeschlossen hast..."

# --- CapRover installieren ---
echo -e "${GREEN}Installiere CapRover...${NC}"
sg docker -c "docker run -d \
  --name caprover \
  --network proxy_net \
  -p 3000:3000 \
  -p 8080:8080 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/docker/caprover:/captain/data \
  --restart=unless-stopped \
  caprover/caprover"
check_success

# --- Mailserver mit Roundcube installieren ---
echo -e "${GREEN}Installiere Mailserver mit Roundcube...${NC}"
sg docker -c "docker run -d \
  --name mailserver \
  --network proxy_net \
  -p 25:25 \
  -p 143:143 \
  -p 587:587 \
  -p 993:993 \
  -p 8083:80 \
  -v ~/docker/mailserver/data:/var/mail \
  -v ~/docker/mailserver/config:/tmp/docker-mailserver \
  --restart=unless-stopped \
  mailserver/docker-mailserver"
check_success

# --- NextcloudPi installieren ---
echo -e "${GREEN}Installiere NextcloudPi...${NC}"
sg docker -c "docker run -d \
  --name nextcloudpi \
  --network proxy_net \
  -p 8081:80 \
  -p 8443:443 \
  -p 4443:4443 \
  -v ~/docker/nextcloud:/data \
  --restart=unless-stopped \
  ownyourbits/nextcloudpi-aarch64 $DOMAIN"
check_success

# --- Vaultwarden installieren ---
echo -e "${GREEN}Installiere Vaultwarden...${NC}"
sg docker -c "docker run -d \
  --name vaultwarden \
  --network proxy_net \
  -p 8082:80 \
  -v ~/docker/bitwarden:/data \
  --restart=unless-stopped \
  vaultwarden/server"
check_success

# --- Desktop-Sicherheitsskript ausführen, wenn Desktop-Modus bestätigt ---
if [ "$USE_DESKTOP" == "y" ]; then
    echo -e "${GREEN}Führe Desktop-Sicherheitskonfiguration aus...${NC}"
    cat << 'EOF' > ~/desktop-security.sh
#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

check_success() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Fehler bei der Ausführung. Skript wird beendet.${NC}"
        exit 1
    fi
}

echo -e "${GREEN}Aktualisiere das System mit Sicherheitsupdates...${NC}"
sudo apt update && sudo apt upgrade -y
check_success

echo -e "${GREEN}Installiere und konfiguriere die Firewall (UFW)...${NC}"
sudo apt install -y ufw
check_success

sudo ufw default deny incoming
sudo ufw default allow outgoing

echo -e "${GREEN}Öffne erforderliche Ports für Cloud-Dienste...${NC}"
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 81/tcp
sudo ufw allow 3000/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 25/tcp
sudo ufw allow 143/tcp
sudo ufw allow 587/tcp
sudo ufw allow 993/tcp
sudo ufw allow 8083/tcp
sudo ufw allow 8081/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 4443/tcp
sudo ufw allow 8082/tcp

sudo ufw enable
check_success

echo -e "${GREEN}Deaktiviere SSH-Dienst...${NC}"
sudo systemctl stop ssh
sudo systemctl disable ssh
check_success

echo -e "${GREEN}Deaktiviere IPv6...${NC}"
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
check_success

echo -e "${GREEN}Sicherheitskonfiguration abgeschlossen!${NC}"
echo -e "${GREEN}Bitte starte das System neu mit 'sudo reboot', um alle Änderungen zu übernehmen.${NC}"
EOF

    chmod +x ~/desktop-security.sh
    bash ~/desktop-security.sh
    rm ~/desktop-security.sh
fi

# --- Abschluss ---
echo -e "${GREEN}Installation abgeschlossen!${NC}"
echo -e "${GREEN}Bitte konfiguriere die Dienste über NGINX Proxy Manager und teste die Funktionalität.${NC}"
echo -e "- NGINX Proxy Manager: http://$LOCAL_IP:81"
echo -e "- CapRover: http://$LOCAL_IP:3000"
echo -e "- Mailserver: Konfiguriere über https://mail.$DOMAIN"
echo -e "- NextcloudPi: https://$LOCAL_IP:4443 für Initialsetup"
echo -e "- Vaultwarden: http://$LOCAL_IP:8082"
echo -e "${GREEN}Hinweis: Für den Mailserver musst du die Konfiguration in ~/docker/mailserver/config anpassen.${NC}"
echo -e "${GREEN}Für Subdomains: Nutze NGINX Proxy Manager, um Subdomains wie web.$DOMAIN oder mail.$DOMAIN zu routen.${NC}"
echo -e "${GREEN}Die feste IP-Adresse ($STATIC_IP) wird beim nächsten Neustart aktiv.${NC}"
echo -e "${GREEN}WICHTIG: Bitte ändere die Standard-Logins für NGINX Proxy Manager und andere Dienste, um die Sicherheit zu erhöhen.${NC}"
