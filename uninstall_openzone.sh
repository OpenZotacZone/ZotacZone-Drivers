#!/bin/bash
# ==============================================================================
#  OPENZONE UNINSTALLER
# ==============================================================================
#  Removes Kernel Drivers, Dial Services, and Manager Tools.
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
   echo -e "${RED}Error: Must run as root (sudo $0)${NC}"
   exit 1
fi

echo -e "\n${BOLD}${RED}:: ZOTAC ZONE DRIVER REMOVAL ::${NC}"
echo "This will remove all drivers, services, and configurations."
read -p "Are you sure? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then exit 0; fi

echo -e "\n${YELLOW}1. Stopping Services...${NC}"
systemctl stop zotac-dials.service 2>/dev/null
systemctl disable zotac-dials.service 2>/dev/null
systemctl stop zotac-zone-drivers.service 2>/dev/null
systemctl disable zotac-zone-drivers.service 2>/dev/null

echo -e "${YELLOW}2. Removing Files...${NC}"
rm -f /etc/systemd/system/zotac-dials.service
rm -f /etc/systemd/system/zotac-zone-drivers.service
rm -rf /usr/local/lib/zotac-zone
rm -f /usr/local/bin/zotac_dial_daemon.py
rm -f /usr/local/bin/openzone_manager.sh
rm -f ./openzone_manager.sh 2>/dev/null # Remove local copy if exists

echo -e "${YELLOW}3. Unloading Kernel Modules...${NC}"
rmmod zotac_zone_platform 2>/dev/null
rmmod firmware_attributes_class 2>/dev/null
rmmod zotac_zone_hid 2>/dev/null

echo -e "${YELLOW}4. Cleaning up Systemd...${NC}"
systemctl daemon-reload

echo -e "\n${GREEN}${BOLD}✔ Uninstallation Complete.${NC}"
echo "You may need to reboot to clear any lingering kernel states."
