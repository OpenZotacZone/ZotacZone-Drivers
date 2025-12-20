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
    echo "#        OPENZONE DRIVER INSTALLER (v2.1)                  #"
    echo "#                                                          #"
    echo "#   Target OS:   Bazzite / Fedora Atomic                   #"
    echo "#   Fixes:       Steam Gaming Mode (Polled HID)            #"
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
echo -e ""
echo -e "${RED}DISCLAIMER:${NC} Software provided 'as is'. No warranty."
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

# --- Step 6: Install Dial Daemon (PROVEN WORKING VERSION) ---
log_header "Step 6/8: Installing Dial Daemon..."
mkdir -p $DIAL_INSTALL_DIR

# 1. Udev Rule
cat > "/etc/udev/rules.d/99-zotac-zone.rules" <<EOF
KERNEL=="hidraw*", ATTRS{idVendor}=="1ee9", ATTRS{idProduct}=="1590", MODE="0666"
EOF
udevadm control --reload-rules && udevadm trigger

# 2. Generate Python Script (Using the Logic you verified works)
cat << 'EOF' > "$DIAL_INSTALL_DIR/$DIAL_SCRIPT_NAME"
#!/usr/bin/env python3
# Zotac Zone Dial Daemon (Polled HID + Direct Backlight)
import os
import sys
import glob
import time
import select
import argparse
from evdev import UInput, ecodes as e

# --- ARGS ---
parser = argparse.ArgumentParser()
parser.add_argument("--left", default="volume")
parser.add_argument("--right", default="brightness")
args = parser.parse_args()

# --- CONSTANTS ---
DIAL_REPORT_ID = 0x03
VID_PART = "1EE9"
PID_PART = "1590"

# --- ACTIONS ---
ACTIONS = {
    "volume":            {"type": "key", "up": e.KEY_VOLUMEUP, "down": e.KEY_VOLUMEDOWN},
    "brightness":        {"type": "backlight", "step": 5},
    "scroll":            {"type": "rel", "axis": e.REL_WHEEL, "up": 1, "down": -1},
    "scroll_inverted":   {"type": "rel", "axis": e.REL_WHEEL, "up": -1, "down": 1},
    "arrows_vertical":   {"type": "key", "up": e.KEY_UP, "down": e.KEY_DOWN},
    "arrows_horizontal": {"type": "key", "up": e.KEY_RIGHT, "down": e.KEY_LEFT},
    "media":             {"type": "key", "up": e.KEY_NEXTSONG, "down": e.KEY_PREVIOUSSONG},
    "page_scroll":       {"type": "key", "up": e.KEY_PAGEUP, "down": e.KEY_PAGEDOWN},
    "zoom":              {"type": "key", "up": e.KEY_ZOOMIN, "down": e.KEY_ZOOMOUT}
}

# --- HELPERS ---
def find_backlight():
    paths = glob.glob("/sys/class/backlight/*")
    if not paths: return None
    for p in paths:
        if "amdgpu" in p: return p
    return paths[0]

def set_backlight(path, direction, step_pct):
    try:
        mf = os.path.join(path, "max_brightness")
        vf = os.path.join(path, "brightness")
        with open(mf, "r") as f: max_v = int(f.read().strip())
        with open(vf, "r") as f: cur_v = int(f.read().strip())
        
        step = max(1, int(max_v * (step_pct / 100.0)))
        new_v = cur_v + step if direction == "up" else cur_v - step
        new_v = max(0, min(new_v, max_v))
        
        with open(vf, "w") as f: f.write(str(new_v))
    except Exception as e:
        print(f"Backlight Error: {e}")

def find_device():
    # Robust search matching the working script
    paths = sorted(glob.glob("/sys/class/hidraw/hidraw*"))
    for path in paths:
        try:
            uevent = os.path.join(path, "device/uevent")
            if not os.path.exists(uevent): continue
            with open(uevent, "r") as f:
                content = f.read().upper()
                if VID_PART in content and PID_PART in content:
                    return f"/dev/{os.path.basename(path)}"
        except: continue
    return None

# --- MAIN ---
def main():
    print(f"Daemon Started. Left:{args.left} Right:{args.right}")
    backlight = find_backlight()
    print(f"Backlight Path: {backlight}")
    
    # Setup UInput
    keys, rels = [], []
    for a in ACTIONS.values():
        if a["type"] == "key": keys.extend([a["up"], a["down"]])
        elif a["type"] == "rel": rels.append(a["axis"])
        
    try:
        ui = UInput({e.EV_KEY: keys, e.EV_REL: rels}, name="Zotac-Zone-Dials")
    except Exception as err:
        print(f"UInput Failed: {err}")
        sys.exit(1)

    while True:
        dev_path = find_device()
        if not dev_path:
            time.sleep(3)
            continue
            
        print(f"Monitoring {dev_path}")
        try:
            f = open(dev_path, "rb", buffering=0)
            fd = f.fileno()
            poller = select.poll()
            poller.register(fd, select.POLLIN)
            
            while True:
                # Poll with 2s timeout to check connection
                events = poller.poll(2000)
                if not events:
                    # Check if device still exists
                    if not os.path.exists(dev_path): raise OSError("Disconnected")
                    continue
                    
                try:
                    data = f.read(64)
                except: break
                
                if not data or len(data) < 4: continue
                if data[0] != DIAL_REPORT_ID: continue
                
                trig = data[3]
                if trig == 0x00: continue
                
                target, direction = None, None
                if trig == 0x10: target, direction = ACTIONS.get(args.left), "down"
                elif trig == 0x08: target, direction = ACTIONS.get(args.left), "up"
                elif trig == 0x02: target, direction = ACTIONS.get(args.right), "down"
                elif trig == 0x01: target, direction = ACTIONS.get(args.right), "up"
                
                if target:
                    t = target["type"]
                    if t == "backlight" and backlight:
                        set_backlight(backlight, direction, target["step"])
                    elif t == "key":
                        k = target[direction]
                        ui.write(e.EV_KEY, k, 1)
                        ui.write(e.EV_KEY, k, 0)
                        ui.syn()
                    elif t == "rel":
                        ui.write(e.EV_REL, target["axis"], target[direction])
                        ui.syn()

        except Exception as e:
            print(f"Device Loop Error: {e}")
            try: f.close() 
            except: pass
            time.sleep(2)

if __name__ == "__main__":
    main()
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
log_success "Dial Daemon Installed."

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
echo -e "   ${BOLD}Dial Service:${NC}   Active (Raw Access)"
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
        echo -e "\nRun to configure: ${BOLD}sudo $MANAGER_LOCAL_PATH${NC}"
    fi
fi
