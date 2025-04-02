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

# --- UFW deaktivieren und Regeln zurücksetzen ---
echo -e "${GREEN}Deaktiviere UFW und setze Regeln zurück...${NC}"
sudo ufw disable
sudo ufw reset
check_success

# --- Bluetooth und WLAN wieder aktivieren ---
echo -e "${GREEN}Aktiviere Bluetooth und WLAN, falls deaktiviert...${NC}"
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
sudo sed -i '/dtoverlay=disable-bt/d' /boot/config.txt
sudo ip link set wlan0 up
sudo sed -i '/dtoverlay=disable-wifi/d' /boot/config.txt
check_success

# --- SSH-Einstellungen zurücksetzen ---
echo -e "${GREEN}Setze SSH-Einstellungen auf Standard zurück...${NC}"
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/PermitRootLogin no/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sudo systemctl restart ssh
check_success

# --- IPv6 wieder aktivieren ---
echo -e "${GREEN}Aktiviere IPv6, falls deaktiviert...${NC}"
sudo sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sudo sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sudo sysctl -p
check_success

# --- Abschluss ---
echo -e "${GREEN}Deinstallation abgeschlossen!${NC}"
echo -e "${GREEN}Bitte starte das System neu, um alle Änderungen zu übernehmen.${NC}"
