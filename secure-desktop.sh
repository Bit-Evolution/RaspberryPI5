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

# 1. Systemaktualisierung
echo -e "${GREEN}Aktualisiere das System mit Sicherheitsupdates...${NC}"
sudo apt update && sudo apt upgrade -y
check_success

# 2. Firewall (UFW) installieren und konfigurieren
echo -e "${GREEN}Installiere und konfiguriere die Firewall (UFW)...${NC}"
sudo apt install -y ufw
check_success

# Standardregeln: Alles eingehende blockieren, ausgehende erlauben
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Notwendige Ports für Cloud-Dienste öffnen
echo -e "${GREEN}Öffne erforderliche Ports für Cloud-Dienste...${NC}"
sudo ufw allow 80/tcp     # HTTP
sudo ufw allow 443/tcp    # HTTPS
sudo ufw allow 81/tcp     # NGINX Proxy Manager Admin
sudo ufw allow 3000/tcp   # CapRover Admin
sudo ufw allow 8080/tcp   # CapRover HTTP
sudo ufw allow 25/tcp     # SMTP
sudo ufw allow 143/tcp    # IMAP
sudo ufw allow 587/tcp    # Submission
sudo ufw allow 993/tcp    # IMAPS
sudo ufw allow 8083/tcp   # Roundcube
sudo ufw allow 8081/tcp   # NextcloudPi HTTP
sudo ufw allow 8443/tcp   # NextcloudPi HTTPS
sudo ufw allow 4443/tcp   # NextcloudPi Admin
sudo ufw allow 8082/tcp   # Vaultwarden

# UFW aktivieren
sudo ufw enable
check_success

# 3. SSH deaktivieren
echo -e "${GREEN}Deaktiviere SSH-Dienst...${NC}"
sudo systemctl stop ssh
sudo systemctl disable ssh
check_success

# 4. IPv6 deaktivieren
echo -e "${GREEN}Deaktiviere IPv6...${NC}"
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
check_success

# 5. Optionale Deaktivierung von Bluetooth und WLAN
read -p "Soll Bluetooth deaktiviert werden? (y/n): " DISABLE_BT
if [ "$DISABLE_BT" == "y" ]; then
    echo -e "${GREEN}Deaktiviere Bluetooth...${NC}"
    sudo systemctl stop bluetooth
    sudo systemctl disable bluetooth
    echo "dtoverlay=disable-bt" | sudo tee -a /boot/config.txt
    check_success
fi

read -p "Soll WLAN deaktiviert werden? (y/n): " DISABLE_WIFI
if [ "$DISABLE_WIFI" == "y" ]; then
    echo -e "${GREEN}Deaktiviere WLAN...${NC}"
    sudo iwconfig wlan0 down
    sudo ip link set wlan0 down
    echo "dtoverlay=disable-wifi" | sudo tee -a /boot/config.txt
    check_success
fi

# 6. Abschluss
echo -e "${GREEN}Sicherheitskonfiguration abgeschlossen!${NC}"
echo -e "${GREEN}Bitte starte das System neu mit 'sudo reboot', um alle Änderungen zu übernehmen.${NC}"
