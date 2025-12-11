#!/bin/bash
# ==============================================================================
#  ZOTAC ZONE DRIVER UNINSTALLER
# ==============================================================================
#  Drivers by: flukejones (Luke D. Jones)
#  Script by:  Pfahli
# ==============================================================================

# --- Colors & Formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Configuration ---
INSTALL_DIR="/usr/local/lib/zotac-zone"
SERVICE_NAME="zotac-zone-drivers.service"

# --- Helper Functions ---
log_header() { echo -e "\n${BLUE}${BOLD}:: $1${NC}"; }
log_info()   { echo -e "   ${CYAN}ℹ${NC} $1"; }
log_success() { echo -e "   ${GREEN}✔${NC} $1"; }
log_warn()   { echo -e "   ${YELLOW}⚠${NC} $1"; }
log_error()  { echo -e "   ${RED}✖ $1${NC}"; }

print_banner() {
    clear
    echo -e "${RED}${BOLD}"
    echo "############################################################"
    echo "#                                                          #"
    echo "#           ZOTAC ZONE DRIVER UNINSTALLER                  #"
    echo "#                                                          #"
    echo "#   Target OS:   Bazzite / Fedora Atomic                   #"
    echo "#   Action:      Remove Drivers & Services                 #"
    echo "#                                                          #"
    echo "############################################################"
    echo -e "${NC}"
}

# --- Root Check ---
if [ "$EUID" -ne 0 ]; then
   log_error "This script must be run as root."
   echo -e "   Please run: ${BOLD}sudo $0${NC}"
   exit 1
fi

print_banner

echo -e "This will completely remove the Zotac Zone drivers and auto-start service."
echo -n "Are you sure you want to continue? [y/N]: "
read -r response
if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "\n${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# --- Step 1: Service Removal ---
log_header "Step 1/4: Removing System Service..."

if systemctl is-active --quiet $SERVICE_NAME; then
    log_info "Stopping service..."
    systemctl stop $SERVICE_NAME
fi

if systemctl is-enabled --quiet $SERVICE_NAME 2>/dev/null; then
    log_info "Disabling auto-start..."
    systemctl disable $SERVICE_NAME
fi

if [ -f "/etc/systemd/system/$SERVICE_NAME" ]; then
    rm -f "/etc/systemd/system/$SERVICE_NAME"
    log_success "Service file removed."
else
    log_warn "Service file not found (already removed?)"
fi

# --- Step 2: Unload Modules ---
log_header "Step 2/4: Unloading Kernel Modules..."

# Helper to remove module and log result
remove_module() {
    if lsmod | grep -q "^$1"; then
        if rmmod "$1" 2>/dev/null; then
            log_success "Module '$1' unloaded."
        else
            log_error "Failed to unload '$1' (is it in use?)."
        fi
    else
        log_info "Module '$1' is not loaded."
    fi
}

# Unload in reverse order of dependency
remove_module "zotac_zone_hid"
remove_module "zotac_zone_platform"
remove_module "firmware_attributes_class"

# --- Step 3: File Cleanup ---
log_header "Step 3/4: Deleting Driver Files..."

if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    log_success "Removed driver directory: $INSTALL_DIR"
else
    log_warn "Driver directory not found (already removed?)"
fi

# --- Step 4: System Refresh ---
log_header "Step 4/4: Refreshing System..."

log_info "Reloading systemd daemon..."
systemctl daemon-reload

log_success "System refreshed."

# --- Final Summary ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}${BOLD}             UNINSTALLATION COMPLETE                        ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "   ${BOLD}Status:${NC}   Cleaned"
echo -e "   ${BOLD}Note:${NC}     You may need to reboot for all changes to settle."
echo -e "${GREEN}============================================================${NC}"
