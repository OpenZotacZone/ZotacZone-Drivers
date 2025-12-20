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
NC='\033[0m'

# --- Configuration ---
REPO_RAW_BASE="https://raw.githubusercontent.com/OpenZotacZone/ZotacZone-Drivers/refs/heads/main"
INSTALL_DIR="/usr/local/lib/zotac-zone"
BUILD_DIR="/tmp/zotac_zone_build"
SERVICE_NAME="zotac-zone-drivers.service"

# Dial Config
DIAL_INSTALL_DIR="/usr/local/bin"
DIAL_SCRIPT_NAME="zotac_dial_daemon.py"
DIAL_SERVICE_NAME="zotac-dials.service"
DIAL_SERVICE_PATH="/etc/systemd/system/$DIAL_SERVICE_NAME"
# Udev Rule to hide dials from Steam
UDEV_RULE_PATH="/etc/udev/rules.d/99-zotac-zone.rules"

# Manager Config
MANAGER_SCRIPT_NAME="openzone_manager.sh"
MANAGER_SCRIPT_URL="${REPO_RAW_BASE}/openzone_manager.sh"

START_DIR="$(pwd)"
MANAGER_LOCAL_PATH="$START_DIR/$MANAGER_SCRIPT_NAME"
LOCAL_SRC_DIR="$START_DIR/driver"

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
    echo "#        OPENZONE DRIVER INSTALLER (v1.9)                  #"
    echo "#                                                          #"
    echo "#   Target OS:   Bazzite / Fedora Atomic                   #"
    echo "#   Fixes:       Steam Gaming Mode Dial Support            #"
    echo "#                                                          #"
    echo "############################################################"
    echo -e "${NC}"
}

if [ "$EUID" -ne 0 ]; then
   log_error "This script must be run as root."
   echo -e "   Please run: ${BOLD}sudo $0${NC}"
   exit 1
fi

print_banner

# --- Step 0: Disclaimer ---
echo -e "${YELLOW}${BOLD}IMPORTANT NOTICE:${NC}"
echo -e "This script installs custom Kernel Drivers and System Services."
echo -e "It will modify system files and install a Udev rule to hide the"
echo -e "dials from Steam so the custom driver can work."
echo -e ""
echo -e "${RED}DISCLAIMER:${NC} Software provided 'as is'. No warranty."
echo -e "Developers are not responsible for instability or damage."
echo -n -e "${GREEN}Do you proceed? [y/N]: ${NC}"
read -r confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n${RED}Aborted.${NC}"; exit 0
fi

# --- Step 1: Cleanup ---
log_header "Step 1/8: Cleaning up..."
systemctl stop $SERVICE_NAME 2>/dev/null || true
systemctl disable $SERVICE_NAME 2>/dev/null || true
rm -f /etc/systemd/system/$SERVICE_NAME

systemctl stop $DIAL_SERVICE_NAME 2>/dev/null || true
systemctl disable $DIAL_SERVICE_NAME 2>/dev/null || true
rm -f $DIAL_SERVICE_PATH

rmmod zotac_zone_platform 2>/dev/null || true
rmmod zotac_zone_platform_driver 2>/dev/null || true
rmmod firmware_attributes_class 2>/dev/null || true
rmmod zotac_zone_hid 2>/dev/null || true

rm -rf $INSTALL_DIR
rm -rf $BUILD_DIR
log_success "Cleaned."

# --- Step 2: Prerequisites ---
log_header "Step 2/8: Checking prerequisites..."
KERNEL_VER=$(uname -r)
if [ ! -d "/lib/modules/$KERNEL_VER/build" ]; then
    log_error "Kernel headers missing!"
    echo -e "   Run: ${BOLD}rpm-ostree install kernel-devel-$KERNEL_VER gcc make${NC}"
    exit 1
fi

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

modprobe uinput
echo "uinput" > /etc/modules-load.d/zotac-uinput.conf
log_success "Prerequisites OK."

# --- Step 3: Source ---
log_header "Step 3/8: Acquiring Source..."
mkdir -p $BUILD_DIR

HID_FILES=("zotac-zone-hid-core.c" "zotac-zone-hid-rgb.c" "zotac-zone-hid-input.c" "zotac-zone-hid-config.c" "zotac-zone.h")
PLATFORM_FILES=("zotac-zone-platform.c" "firmware_attributes_class.h" "firmware_attributes_class.c")

if [ -d "$LOCAL_SRC_DIR/hid" ]; then
    log_info "Using local files."
    for f in "${HID_FILES[@]}"; do cp "$LOCAL_SRC_DIR/hid/$f" "$BUILD_DIR/" 2>/dev/null; done
    for f in "${PLATFORM_FILES[@]}"; do cp "$LOCAL_SRC_DIR/platform/$f" "$BUILD_DIR/" 2>/dev/null; done
else
    log_info "Downloading from GitHub..."
    cd $BUILD_DIR
    for f in "${HID_FILES[@]}"; do wget -q "${REPO_RAW_BASE}/driver/hid/$f"; done
    for f in "${PLATFORM_FILES[@]}"; do wget -q "${REPO_RAW_BASE}/driver/platform/$f"; done
fi

# --- Step 4: Compile ---
log_header "Step 4/8: Compiling..."
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

make > /dev/null || { log_error "Compile failed."; exit 1; }
log_success "Compiled."

# --- Step 5: Install Kernel Drivers ---
log_header "Step 5/8: Installing Kernel Drivers..."
mkdir -p $INSTALL_DIR
cp *.ko $INSTALL_DIR/
[ -x "$(command -v chcon)" ] && chcon -v -t modules_object_t $INSTALL_DIR/*.ko >/dev/null 2>&1

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
log_success "Kernel Drivers Active."

# --- Step 6: Install Dial Daemon (UPDATED) ---
log_header "Step 6/8: Installing Dial Daemon (Steam Fix)..."
mkdir -p $DIAL_INSTALL_DIR

# 1. Create Udev Rule to hide physical dials from Steam
log_info "Creating Udev Rule to prevent Steam Input grab..."
cat > "$UDEV_RULE_PATH" <<EOF
# Zotac Zone Dials - Hide from Steam/Seat, allow root/daemon access
# This prevents "Device busy" errors in Gaming Mode
KERNEL=="event*", ATTRS{name}=="ZOTAC Gaming Zone Dials", ENV{LIBINPUT_IGNORE_DEVICE}="1", ENV{ID_INPUT}="0"
EOF
udevadm control --reload-rules && udevadm trigger

# 2. Generate Python Script (With Retry Logic)
cat << 'EOF' > "$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME"
#!/usr/bin/env python3
import evdev
import argparse
import sys
import time
from evdev import UInput, ecodes as e

parser = argparse.ArgumentParser()
parser.add_argument("--left", default="volume")
parser.add_argument("--right", default="brightness")
args = parser.parse_args()

TARGET_NAME = "ZOTAC Gaming Zone Dials"

ACTIONS = {
    "volume":            ([e.KEY_VOLUMEUP, e.KEY_VOLUMEDOWN], None, None, 1),
    "brightness":        ([e.KEY_BRIGHTNESSUP, e.KEY_BRIGHTNESSDOWN], None, None, 1),
    "scroll":            (None, None, e.REL_WHEEL, 1),
    "scroll_inverted":   (None, None, e.REL_WHEEL, -1),
    "scroll_horizontal": (None, None, e.REL_HWHEEL, 1),
    "arrows_vertical":   ([e.KEY_UP, e.KEY_DOWN], None, None, 1),
    "arrows_horizontal": ([e.KEY_RIGHT, e.KEY_LEFT], None, None, 1),
    "page_scroll":       ([e.KEY_PAGEUP, e.KEY_PAGEDOWN], None, None, 1),
    "media":             ([e.KEY_NEXTSONG, e.KEY_PREVIOUSSONG], None, None, 1),
    "zoom":              (None, e.KEY_LEFTCTRL, e.REL_WHEEL, 1),
}

cap = {
    e.EV_KEY: [e.KEY_VOLUMEUP, e.KEY_VOLUMEDOWN, e.KEY_BRIGHTNESSUP, e.KEY_BRIGHTNESSDOWN,
               e.KEY_UP, e.KEY_DOWN, e.KEY_LEFT, e.KEY_RIGHT, e.KEY_PAGEUP, e.KEY_PAGEDOWN,
               e.KEY_NEXTSONG, e.KEY_PREVIOUSSONG, e.KEY_LEFTCTRL],
    e.EV_REL: [e.REL_WHEEL, e.REL_HWHEEL]
}

try:
    ui = UInput(cap, name="Zotac Zone Virtual Dials", version=0x3)
except Exception as err:
    print(f"UInput Error: {err}")
    sys.exit(1)

def handle_event(mode, value):
    if mode not in ACTIONS: return
    keys, mod, rel, mult = ACTIONS[mode]
    if rel:
        if mod: ui.write(e.EV_KEY, mod, 1)
        ui.write(e.EV_REL, rel, value * mult)
        if mod: ui.write(e.EV_KEY, mod, 0)
    elif keys:
        k = keys[0] if value > 0 else keys[1]
        ui.write(e.EV_KEY, k, 1)
        ui.write(e.EV_KEY, k, 0)
    ui.syn()

def main_loop():
    print(f"Daemon Started. L:{args.left} R:{args.right}")
    while True:
        try:
            device = None
            for dev in [evdev.InputDevice(p) for p in evdev.list_devices()]:
                if TARGET_NAME in dev.name:
                    device = dev
                    break
            
            if device:
                # Retry grab if busy (Steam conflict)
                try:
                    device.grab()
                    print(f"Grabbed: {device.name}")
                    for event in device.read_loop():
                        if event.type == e.EV_REL:
                            if event.code == e.REL_HWHEEL: handle_event(args.left, event.value)
                            elif event.code == e.REL_WHEEL: handle_event(args.right, event.value)
                except OSError:
                    print("Device busy. Steam might have grabbed it. Retrying...")
                    time.sleep(2)
            else:
                time.sleep(3)
        except Exception as err:
            print(f"Loop Error: {err}")
            time.sleep(3)

if __name__ == "__main__":
    main_loop()
EOF
chmod +x "$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME"

# 3. Create Service
cat > "$DIAL_SERVICE_PATH" <<EOF
[Unit]
Description=Zotac Zone Dial Daemon
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME --left volume --right brightness
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$DIAL_SERVICE_NAME" > /dev/null
log_success "Dial Daemon Installed & Udev Rule Applied."

# --- Step 7: Launch Dials ---
log_header "Step 7/8: Starting Services..."
systemctl restart "$DIAL_SERVICE_NAME"
if systemctl is-active --quiet "$DIAL_SERVICE_NAME"; then
    log_success "Dial Service Running."
else
    log_warn "Dial Service failed start. Check logs."
fi

# --- Step 8: Optional CoolerControl ---
log_header "Step 8/8: Additional Software"
CC_INSTALLED=false
if command -v coolercontrol &> /dev/null; then
    log_info "CoolerControl already installed."
    CC_INSTALLED=true
else
    echo -e "Install ${BOLD}CoolerControl${NC} for Fan Curves? (Recommended)"
    echo -n -e "${GREEN}>> Install? [y/N]: ${NC}"
    read -r cc_choice
    if [[ "$cc_choice" =~ ^[Yy]$ ]]; then
        if command -v rpm-ostree &> /dev/null; then
            log_info "Bazzite/Atomic detected. Adding COPR..."
            wget -q https://copr.fedorainfracloud.org/coprs/codifryed/CoolerControl/repo/fedora-$(rpm -E %fedora)/codifryed-CoolerControl-fedora-$(rpm -E %fedora).repo -O /etc/yum.repos.d/_copr_codifryed-CoolerControl.repo
            rpm-ostree install coolercontrol
            CC_INSTALLED=true
        elif command -v dnf &> /dev/null; then
            dnf copr enable -y codifryed/CoolerControl
            dnf install -y coolercontrol
            systemctl enable --now coolercontrold
            CC_INSTALLED=true
        fi
    fi
fi

# Cleanup
cd "$START_DIR" || exit 1
rm -rf $BUILD_DIR

# --- Summary ---
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}${BOLD}             INSTALLATION COMPLETE!                         ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "   ${BOLD}Kernel Drivers:${NC} Active"
echo -e "   ${BOLD}Dial Service:${NC}   Active (Steam Fix Applied)"
if [ "$CC_INSTALLED" = true ]; then
    echo -e "   ${BOLD}CoolerControl:${NC}  ${YELLOW}Installed/Queued${NC} (Reboot required)"
fi
echo -e "${GREEN}============================================================${NC}"

if [ ! -f "$MANAGER_LOCAL_PATH" ]; then
    log_info "Downloading OpenZone Manager..."
    wget -q -O "$MANAGER_LOCAL_PATH" "$MANAGER_SCRIPT_URL"
    chmod +x "$MANAGER_LOCAL_PATH"
fi

if [ -f "$MANAGER_LOCAL_PATH" ]; then
    echo -e "\n${BOLD}${CYAN}Run OpenZone Manager now?${NC}"
    echo -n -e "${GREEN}>> [Y/n]: ${NC}"
    read -r choice
    if [[ ! "$choice" =~ ^[Nn]$ ]]; then
        exec "$MANAGER_LOCAL_PATH"
    else
        echo -e "\nRun later: ${BOLD}sudo $MANAGER_LOCAL_PATH${NC}"
    fi
fi
