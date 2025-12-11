#!/bin/bash
# ==============================================================================
#  ZOTAC ZONE LINUX DRIVER INSTALLER
# ==============================================================================
#  Drivers by: flukejones (Luke D. Jones)
#  Installer by: Pfahli
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
REPO_BRANCH="wip/zotac-zone-6.15"
BASE_URL="https://raw.githubusercontent.com/flukejones/linux/${REPO_BRANCH}"
INSTALL_DIR="/usr/local/lib/zotac-zone"
BUILD_DIR="/tmp/zotac_zone_build"
SERVICE_NAME="zotac-zone-drivers.service"

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
    echo "#            ZOTAC ZONE DRIVER INSTALLER                   #"
    echo "#                                                          #"
    echo "#   Target OS:   Bazzite / Fedora Atomic                   #"
    echo "#   Drivers by:  flukejones                                #"
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

# --- Step 3: Download ---
log_header "Step 3/7: Downloading source code..."
log_info "Fetching drivers from flukejones/linux ($REPO_BRANCH)..."

mkdir -p $BUILD_DIR
cd $BUILD_DIR

# List of files to fetch
files=(
    "drivers/hid/zotac-zone-hid/zotac-zone-hid-core.c"
    "drivers/hid/zotac-zone-hid/zotac-zone-hid-rgb.c"
    "drivers/hid/zotac-zone-hid/zotac-zone-hid-input.c"
    "drivers/hid/zotac-zone-hid/zotac-zone-hid-config.c"
    "drivers/hid/zotac-zone-hid/zotac-zone.h"
    "drivers/platform/x86/zotac-zone-platform.c"
    "drivers/platform/x86/firmware_attributes_class.h"
    "drivers/platform/x86/firmware_attributes_class.c"
)

for file in "${files[@]}"; do
    filename=$(basename "$file")
    # log_info "Downloading $filename..."
    if wget -q "${BASE_URL}/$file"; then
        echo -ne "."
    else
        echo ""
        log_error "Failed to download $filename"
        exit 1
    fi
done
echo ""
log_success "All source files downloaded successfully."

# --- Step 4: Compile ---
log_header "Step 4/7: Compiling drivers..."
log_info "Building kernel modules (this may take a moment)..."

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
    log_error "Compilation failed. Check usage of correct kernel headers."
    exit 1
fi

# --- Step 5: Install & Security ---
log_header "Step 5/7: Installing files & Fixing Permissions..."
mkdir -p $INSTALL_DIR

log_info "Copying modules to $INSTALL_DIR..."
cp zotac-zone-hid.ko $INSTALL_DIR/
cp firmware_attributes_class.ko $INSTALL_DIR/
cp zotac-zone-platform.ko $INSTALL_DIR/

log_info "Applying SELinux security labels..."
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
Description=Load Zotac Zone Drivers (flukejones)
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
echo -e "   ${BOLD}Control:${NC}  Your dials, RGB, and Fan control should work now."
echo -e "   ${BOLD}Credits:${NC}  Driver by flukejones | Script by Pfahli"
echo -e "${GREEN}============================================================${NC}"
