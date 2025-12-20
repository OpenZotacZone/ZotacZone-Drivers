#!/bin/bash
# ==============================================================================
#  ZOTAC ZONE LINUX DRIVER INSTALLER (OpenZONE)
# ==============================================================================
#  Drivers by: flukejones (Luke D. Jones)
#  Installer by: Pfahli
#  Repository: OpenZotacZone/ZotacZone-Drivers
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
REPO_RAW_BASE="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"
INSTALL_DIR="/usr/local/lib/zotac-zone"
BUILD_DIR="/tmp/zotac_zone_build"
SERVICE_NAME="zotac-zone-drivers.service"

# Dial Configuration
DIAL_SCRIPT_URL="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main/driver/dials/zotac_dial_daemon.py"
DIAL_INSTALL_DIR="/usr/local/bin"
DIAL_SCRIPT_NAME="zotac_dial_daemon.py"
DIAL_SERVICE_NAME="zotac-dials.service"
DIAL_SERVICE_PATH="/etc/systemd/system/$DIAL_SERVICE_NAME"
MANAGER_SCRIPT="./openzone_manager.sh"

# Local source directory to check (relative to script execution)
LOCAL_SRC_DIR="./driver"

# --- Helper Functions ---
log_header() { echo -e "\n${BLUE}${BOLD}:: $1${NC}"; }
log_info()   { echo -e "   ${CYAN}ℹ${NC} $1"; }
log_success() { echo -e "   ${GREEN}✔${NC} $1"; }
log_warn()   { echo -e "   ${YELLOW}⚠${NC} $1"; }
log_error()  { echo -e "   ${RED}✖ $1${NC}"; }

print_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "############################################################"
    echo "#                                                          #"
    echo "#        OPENZONE DRIVER INSTALLER (v1.4)                  #"
    echo "#                                                          #"
    echo "#   Target OS:   Bazzite / Fedora Atomic                   #"
    echo "#   Drivers:     flukejones                                #"
    echo "#   Script by:   Pfahli                                    #"
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

# --- Step 1: Cleanup ---
log_header "Step 1/7: Cleaning up old installations..."
log_info "Stopping services and unloading modules..."

systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true
rm -f /etc/systemd/system/$SERVICE_NAME

systemctl stop $DIAL_SERVICE_NAME 2>/dev/null || true
systemctl disable $DIAL_SERVICE_NAME 2>/dev/null || true
rm -f $DIAL_SERVICE_PATH

# Unload modules
rmmod zotac_zone_platform 2>/dev/null || true
rmmod zotac_zone_platform_driver 2>/dev/null || true
rmmod firmware_attributes_class 2>/dev/null || true
rmmod zotac_zone_hid 2>/dev/null || true

# Clean directories
rm -rf $INSTALL_DIR
rm -rf $BUILD_DIR

systemctl daemon-reload
log_success "System clean. Ready for fresh install."

# --- Step 2: Prerequisites ---
log_header "Step 2/7: Checking system prerequisites..."
KERNEL_VER=$(uname -r)
log_info "Detected Kernel: $KERNEL_VER"

if [ ! -d "/lib/modules/$KERNEL_VER/build" ]; then
    log_error "Kernel headers are missing!"
    echo -e "\n   ${YELLOW}Action Required:${NC}"
    echo -e "   Please run this command and then reboot:"
    echo -e "   ${BOLD}rpm-ostree install kernel-devel-$KERNEL_VER gcc make${NC}"
    exit 1
fi

# Check Python Evdev
if ! python3 -c "import evdev" &> /dev/null; then
    log_info "Installing python-evdev..."
    if command -v rpm-ostree &> /dev/null; then
        pip install evdev --break-system-packages 2>/dev/null || pip install evdev
    elif command -v apt &> /dev/null; then
        apt update && apt install -y python3-evdev
    else
        pip install evdev
    fi
fi

# Ensure uinput
modprobe uinput
echo "uinput" > /etc/modules-load.d/zotac-uinput.conf
log_success "Prerequisites check passed."

# --- Step 3: Acquire Kernel Source ---
log_header "Step 3/7: Acquiring Kernel Driver source..."
mkdir -p $BUILD_DIR

HID_FILES=("zotac-zone-hid-core.c" "zotac-zone-hid-rgb.c" "zotac-zone-hid-input.c" "zotac-zone-hid-config.c" "zotac-zone.h")
PLATFORM_FILES=("zotac-zone-platform.c" "firmware_attributes_class.h" "firmware_attributes_class.c")

if [ -d "$LOCAL_SRC_DIR/hid" ] && [ -d "$LOCAL_SRC_DIR/platform" ]; then
    log_info "Found local 'driver' folder. Using local files..."
    for file in "${HID_FILES[@]}"; do cp "$LOCAL_SRC_DIR/hid/$file" "$BUILD_DIR/" 2>/dev/null || { log_error "Missing $file"; exit 1; }; done
    for file in "${PLATFORM_FILES[@]}"; do cp "$LOCAL_SRC_DIR/platform/$file" "$BUILD_DIR/" 2>/dev/null || { log_error "Missing $file"; exit 1; }; done
    log_success "Local source copied."
else
    log_info "Downloading from OpenZotacZone GitHub..."
    cd $BUILD_DIR
    for file in "${HID_FILES[@]}"; do wget -q "${REPO_RAW_BASE}/driver/hid/$file" || { log_error "Download failed: $file"; exit 1; }; echo -ne "."; done
    for file in "${PLATFORM_FILES[@]}"; do wget -q "${REPO_RAW_BASE}/driver/platform/$file" || { log_error "Download failed: $file"; exit 1; }; echo -ne "."; done
    echo ""
    log_success "Download complete."
fi

# --- Step 4: Compile ---
log_header "Step 4/7: Compiling Kernel Drivers..."
cd $BUILD_DIR
cat > Makefile <<EOF
obj-m += zotac-zone-hid.o
zotac-zone-hid-y := zotac-zone-hid-core.o zotac-zone-hid-rgb.o zotac-zone-hid-input.o zotac-zone-hid-config.o
obj-m += firmware_attributes_class.o
obj-m += zotac-zone-platform.o
all:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD) modules
clean:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD) clean
EOF

if make > /dev/null; then
    log_success "Compilation successful."
else
    log_error "Compilation failed."
    exit 1
fi

# --- Step 5: Install Kernel Drivers ---
log_header "Step 5/7: Installing Kernel Drivers..."
mkdir -p $INSTALL_DIR
cp *.ko $INSTALL_DIR/

# SELinux Fix
if command -v chcon &> /dev/null; then
    chcon -v -t modules_object_t $INSTALL_DIR/*.ko > /dev/null 2>&1
fi

cat > /etc/systemd/system/$SERVICE_NAME <<EOF
[Unit]
Description=Load Zotac Zone Drivers (OpenZONE)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/modprobe led-class-multicolor
ExecStart=/usr/sbin/modprobe platform_profile
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/firmware_attributes_class.ko
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/zotac-zone-platform.ko
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/zotac-zone-hid.ko
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME > /dev/null
systemctl restart $SERVICE_NAME

if systemctl is-active --quiet $SERVICE_NAME; then
    log_success "Kernel Drivers loaded."
else
    log_error "Failed to load Kernel Drivers."
    journalctl -xeu $SERVICE_NAME --no-pager | tail -n 5
    exit 1
fi

# --- Step 6: Install Dial Daemon ---
log_header "Step 6/7: Installing Dial Daemon..."
mkdir -p $DIAL_INSTALL_DIR

log_info "Downloading Dial Daemon from GitHub..."
wget -q -O "$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME" "$DIAL_SCRIPT_URL"

if [ -f "$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME" ]; then
    chmod +x "$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME"
    log_success "Dial Daemon installed."
else
    log_error "Failed to download Dial Daemon."
    exit 1
fi

log_info "Setting up Service with defaults (Left: Volume, Right: Brightness)..."

cat > "$DIAL_SERVICE_PATH" <<EOF
[Unit]
Description=Zotac Zone Dial Daemon
After=multi-user.target

[Service]
Type=simple
# Defaults: Left=Volume, Right=Brightness
ExecStart=/usr/bin/python3 $DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME --left volume --right brightness
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$DIAL_SERVICE_NAME" > /dev/null
log_success "Dial Service Installed."

# --- Step 7: Launch Dials ---
log_header "Step 7/7: Starting Services..."
systemctl restart "$DIAL_SERVICE_NAME"

if systemctl is-active --quiet "$DIAL_SERVICE_NAME"; then
    log_success "Dial Service is running!"
else
    log_warn "Dial Service failed to start. Check logs."
fi

# Cleanup
rm -rf $BUILD_DIR

# --- Summary & Manager Prompt ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}${BOLD}             INSTALLATION COMPLETE!                         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "   ${BOLD}Kernel Drivers:${NC} Active"
echo -e "   ${BOLD}Dial Service:${NC}   Active (Defaults: Vol/Bright)"
echo -e "${GREEN}============================================================${NC}"

if [ -f "$MANAGER_SCRIPT" ]; then
    echo -e "\n${BOLD}${CYAN}Would you like to run the OpenZone Manager now to configure?${NC}"
    echo -e "This allows you to customize Buttons, RGB, Dials, and Deadzones."
    echo -n -e "${GREEN}>> Run Manager? [Y/n]: ${NC}"
    read -r choice
    if [[ ! "$choice" =~ ^[Nn]$ ]]; then
        chmod +x "$MANAGER_SCRIPT"
        exec "$MANAGER_SCRIPT"
    else
        echo -e "\nOK. You can run it later via: ${BOLD}sudo $MANAGER_SCRIPT${NC}"
    fi
else
    echo -e "\n${YELLOW}Tip: Run 'sudo ./openzone_manager.sh' to configure your device.${NC}"
fi
