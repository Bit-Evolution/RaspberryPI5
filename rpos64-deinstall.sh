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

# --- Stoppen und Entfernen der Docker-Container ---
echo -e "${GREEN}Stoppe und entferne Docker-Container...${NC}"
docker stop nginx-proxy-manager caprover mailserver nextcloudpi vaultwarden
docker rm nginx-proxy-manager caprover mailserver nextcloudpi vaultwarden
check_success

# --- Entfernen der Docker-Volumes und Netzwerke ---
echo -e "${GREEN}Entferne Docker-Volumes und Netzwerke...${NC}"
rm -rf ~/docker
docker network rm proxy_net
check_success

# --- Deinstallation von Docker und Docker Compose ---
echo -e "${GREEN}Deinstalliere Docker und Docker Compose...${NC}"
sudo apt remove -y docker docker-engine docker.io containerd runc
sudo apt purge -y docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
sudo apt remove -y docker-compose
check_success

# --- Rückgängigmachen der Netzwerkkonfiguration ---
echo -e "${GREEN}Setze Netzwerkkonfiguration zurück...${NC}"
sudo sed -i '/interface eth0/d' /etc/dhcpcd.conf
sudo sed -i '/static ip_address/d' /etc/dhcpcd.conf
sudo sed -i '/static routers/d' /etc/dhcpcd.conf
sudo sed -i '/static domain_name_servers/d' /etc/dhcpcd.conf
sudo systemctl restart dhcpcd
check_success

# --- Entfernen des Cronjobs ---
echo -e "${GREEN}Entferne Cronjob für statische IP...${NC}"
sudo rm /etc/cron.d/set_static_ip
check_success

# --- Rückgängigmachen der Bluetooth- und WLAN-Deaktivierung ---
echo -e "${GREEN}Aktiviere Bluetooth und WLAN...${NC}"
sudo sed -i '/dtoverlay=disable-bt/d' /boot/config.txt
sudo sed -i '/dtoverlay=disable-wifi/d' /boot/config.txt
check_success

# --- Entfernen des DynDNS-Dienstes ---
echo -e "${GREEN}Deinstalliere DynDNS-Dienst...${NC}"
sudo apt remove -y ddclient
sudo rm /etc/ddclient.conf
check_success

# --- Entfernen des Sicherheits-Skripts ---
echo -e "${GREEN}Setze Sicherheitskonfiguration zurück...${NC}"
sudo ufw disable
sudo systemctl enable ssh
sudo systemctl start ssh
sudo sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sudo sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sudo sysctl -p
check_success

# --- Abschluss ---
echo -e "${GREEN}Deinstallation abgeschlossen!${NC}"
echo -e "${GREEN}Bitte starte das System neu mit 'sudo reboot', um alle Änderungen zu übernehmen.${NC}"
