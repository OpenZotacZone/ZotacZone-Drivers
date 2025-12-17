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
# Updated URL structure based on your feedback
REPO_RAW_BASE="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"
INSTALL_DIR="/usr/local/lib/zotac-zone"
BUILD_DIR="/tmp/zotac_zone_build"
SERVICE_NAME="zotac-zone-drivers.service"

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
    echo "#        OPENZONE DRIVER INSTALLER (v1.1)                  #"
    echo "#                                                          #"
    echo "#   Target OS:   Bazzite / Fedora Atomic                   #"
    echo "#   Drivers:     flukejones                  #"
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
log_info "Stopping existing services and unloading modules..."

systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true
rm -f /etc/systemd/system/$SERVICE_NAME

# Unload modules safely
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
    echo -e "   Please run this command and then reboot your device:"
    echo -e "   ${BOLD}rpm-ostree install kernel-devel-$KERNEL_VER gcc make${NC}"
    exit 1
fi
log_success "Kernel headers, gcc, and make are present."

# --- Step 3: Acquire Source ---
log_header "Step 3/7: Acquiring source code..."
mkdir -p $BUILD_DIR

# Define file lists relative to their specific subdirectories
HID_FILES=(
    "zotac-zone-hid-core.c"
    "zotac-zone-hid-rgb.c"
    "zotac-zone-hid-input.c"
    "zotac-zone-hid-config.c"
    "zotac-zone.h"
)

PLATFORM_FILES=(
    "zotac-zone-platform.c"
    "firmware_attributes_class.h"
    "firmware_attributes_class.c"
)

# Logic: Check if local folder './driver' exists and has content
if [ -d "$LOCAL_SRC_DIR/hid" ] && [ -d "$LOCAL_SRC_DIR/platform" ]; then
    # --- LOCAL MODE ---
    log_info "Found local 'driver' folder with hid/platform subdirs."
    log_info "Using LOCAL files..."

    # Copy HID files
    for file in "${HID_FILES[@]}"; do
        cp "$LOCAL_SRC_DIR/hid/$file" "$BUILD_DIR/" 2>/dev/null || { log_error "Missing local file: hid/$file"; exit 1; }
    done

    # Copy Platform files
    for file in "${PLATFORM_FILES[@]}"; do
        cp "$LOCAL_SRC_DIR/platform/$file" "$BUILD_DIR/" 2>/dev/null || { log_error "Missing local file: platform/$file"; exit 1; }
    done

    log_success "Local source files copied to build directory."
else
    # --- DOWNLOAD MODE ---
    log_info "Local 'driver' folder not found (or incomplete)."
    log_info "Downloading from OpenZotacZone/ZotacZone-Drivers..."

    cd $BUILD_DIR

    # Download HID files
    log_info "Fetching HID drivers..."
    for file in "${HID_FILES[@]}"; do
        wget -q "${REPO_RAW_BASE}/driver/hid/$file" || { log_error "Failed to download $file"; exit 1; }
        echo -ne "."
    done
    echo ""

    # Download Platform files
    log_info "Fetching Platform drivers..."
    for file in "${PLATFORM_FILES[@]}"; do
        wget -q "${REPO_RAW_BASE}/driver/platform/$file" || { log_error "Failed to download $file"; exit 1; }
        echo -ne "."
    done
    echo ""
    log_success "All source files downloaded successfully."
fi

# --- Step 4: Compile ---
log_header "Step 4/7: Compiling drivers..."
log_info "Building kernel modules..."

cd $BUILD_DIR
cat > Makefile <<EOF
obj-m += zotac-zone-hid.o
zotac-zone-hid-y := zotac-zone-hid-core.o zotac-zone-hid-rgb.o zotac-zone-hid-input.o zotac-zone-hid-config.o

# Build as separate modules to prevent symbol conflicts
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

# --- Step 5: Install & Security ---
log_header "Step 5/7: Installing files & Fixing Permissions..."
mkdir -p $INSTALL_DIR

log_info "Copying modules to $INSTALL_DIR..."
cp zotac-zone-hid.ko $INSTALL_DIR/
cp firmware_attributes_class.ko $INSTALL_DIR/
cp zotac-zone-platform.ko $INSTALL_DIR/

log_info "Applying SELinux labels..."
if command -v chcon &> /dev/null; then
    if chcon -v -t modules_object_t $INSTALL_DIR/*.ko > /dev/null; then
        log_success "SELinux labels applied (Permission denied fix)."
    else
        log_warn "Failed to apply SELinux labels. Drivers might not load."
    fi
else
    log_warn "SELinux tool 'chcon' not found. Skipping."
fi

# --- Step 6: Service Creation ---
log_header "Step 6/7: Configuring auto-start service..."

cat > /etc/systemd/system/$SERVICE_NAME <<EOF
[Unit]
Description=Load Zotac Zone Drivers (OpenZONE)
After=network.target

[Service]
Type=oneshot
# Load kernel dependencies
ExecStart=/usr/sbin/modprobe led-class-multicolor
ExecStart=/usr/sbin/modprobe platform_profile
# Load custom modules in dependency order
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/firmware_attributes_class.ko
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/zotac-zone-platform.ko
ExecStart=/usr/sbin/insmod ${INSTALL_DIR}/zotac-zone-hid.ko
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME > /dev/null
log_success "Service $SERVICE_NAME created and enabled."

# --- Step 7: Launch ---
log_header "Step 7/7: Loading drivers..."

if systemctl restart $SERVICE_NAME; then
    log_success "Drivers loaded successfully!"
else
    log_error "Failed to load drivers."
    echo -e "\n   ${YELLOW}Debug Info:${NC}"
    journalctl -xeu $SERVICE_NAME --no-pager | tail -n 10
    exit 1
fi

# Cleanup build
rm -rf $BUILD_DIR

# --- Final Summary ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}${BOLD}             INSTALLATION COMPLETE!                         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "   ${BOLD}Status:${NC}   Active & Running"
echo -e "   ${BOLD}Source:${NC}   $(if [ -d "$LOCAL_SRC_DIR/hid" ]; then echo "Local Files"; else echo "OpenZotacZone GitHub"; fi)"
echo -e "   ${BOLD}Credits:${NC}  Drivers by flukejones | Script by Pfahli"
echo -e "${GREEN}============================================================${NC}"
