#!/bin/bash
# ==============================================================================
#  OpenZONE RGB CONTROL
# ==============================================================================
#  Version: 1.2
#  Author:  Pfahli
#  Credits: Drivers by flukejones | Testing by Community
# ==============================================================================
#  CHANGELOG:
#  v1.2 - Added driver health check & improved UI layout.
#  v1.1 - Implemented "Magic Sequence" (Dance->Static) to fix frozen LEDs.
#       - Forced Speed 2 for Static Mode to ensure signal lock.
#  v1.0 - Initial release with basic Effect and Color support.
# ==============================================================================

# --- Styling & Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color
LED_BASE="/sys/class/leds"

# --- Helper Functions ---
print_header() {
    clear
    echo -e "${PURPLE}${BOLD}"
    echo "############################################################"
    echo "#                                                          #"
    echo "#              OPENZONE RGB CONTROL  v1.2                  #"
    echo "#                                                          #"
    echo "############################################################"
    echo -e "${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: Permission Denied.${NC}"
        echo "Please run as root: ${BOLD}sudo ./openzone_rgb_control.sh${NC}"
        exit 1
    fi
}

check_driver() {
    echo -e "${CYAN}:: Checking System Status...${NC}"
    if ! ls $LED_BASE/zotac:rgb:spectra_zone_* 1> /dev/null 2>&1; then
        echo -e "${RED}✖ Driver not detected!${NC}"
        echo -e "   The Zotac Zone drivers do not appear to be loaded."
        echo -e "   Please verify installation or run:"
        echo -e "   ${YELLOW}sudo systemctl restart zotac-zone-drivers${NC}"
        exit 1
    else
        echo -e "${GREEN}✔ Driver Active.${NC} Found LED zones."
        echo ""
    fi
}

# --- Main Execution ---
check_root
print_header
check_driver

# ==============================================================================
# STEP 1: EFFECT SELECTION
# ==============================================================================
echo -e "${BLUE}${BOLD}[1] Select Lighting Effect${NC}"
echo "   1) Static  (Solid Color)"
echo "   2) Breathe (Pulsing)"
echo "   3) Cycle   (Color Loop)"
echo "   4) Rainbow (Wave)"
echo "   5) Off"
echo -n -e "${YELLOW}>> Choose [1-5]: ${NC}"
read -r EFF_CHOICE

case $EFF_CHOICE in
    1) EFFECT_ID=5; EFFECT_NAME="Static" ;;
    2) EFFECT_ID=2; EFFECT_NAME="Breathe" ;;
    3) EFFECT_ID=3; EFFECT_NAME="Cycle" ;;
    4) EFFECT_ID=0; EFFECT_NAME="Rainbow" ;;
    5) EFFECT_ID=240; EFFECT_NAME="Off" ;;
    *) echo "   Invalid. Defaulting to Static."; EFFECT_ID=5; EFFECT_NAME="Static" ;;
esac

# ==============================================================================
# STEP 2: BRIGHTNESS
# ==============================================================================
echo -e "\n${BLUE}${BOLD}[2] Select Brightness${NC}"
echo "   0) Off"
echo "   1) Low"
echo "   2) Medium"
echo "   3) High"
echo "   4) Max"
echo -n -e "${YELLOW}>> Choose [0-4] (Default: 4): ${NC}"
read -r BRIGHT_CHOICE
if [[ ! "$BRIGHT_CHOICE" =~ ^[0-4]$ ]]; then BRIGHT_CHOICE=4; fi

# ==============================================================================
# STEP 3: COLOR (Conditional)
# ==============================================================================
COLOR_DEC="16711680" # Default Red

if [[ "$EFFECT_NAME" == "Static" || "$EFFECT_NAME" == "Breathe" ]]; then
    echo -e "\n${BLUE}${BOLD}[3] Select Color${NC}"
    echo "   Presets: red, blue, green, white, purple, orange, cyan, pink"
    echo "   Custom:  Enter HEX code (e.g. FF00FF)"
    echo -n -e "${YELLOW}>> Input: ${NC}"
    read -r COLOR_INPUT

    COLOR_INPUT=$(echo "$COLOR_INPUT" | tr '[:upper:]' '[:lower:]')
    case $COLOR_INPUT in
        red|rot)    COLOR_DEC=$((0xFF0000)) ;;
        green|grün) COLOR_DEC=$((0x00FF00)) ;;
        blue|blau)  COLOR_DEC=$((0x0000FF)) ;;
        white|weiß) COLOR_DEC=$((0xFFFFFF)) ;;
        purple|lila) COLOR_DEC=$((0xFF00FF)) ;;
        pink)       COLOR_DEC=$((0xFF1493)) ;;
        yellow|gelb) COLOR_DEC=$((0xFFFF00)) ;;
        orange)     COLOR_DEC=$((0xFF8000)) ;;
        cyan|türkis) COLOR_DEC=$((0x00FFFF)) ;;
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) COLOR_DEC=$((16#$COLOR_INPUT)) ;;
        *) echo "   Unknown color. Using RED."; COLOR_DEC=$((0xFF0000)) ;;
    esac
fi

# ==============================================================================
# STEP 4: SPEED
# ==============================================================================
if [[ "$EFFECT_NAME" == "Static" ]]; then
    SPEED_VAL=2 # Force Speed 2 for Static fix
elif [[ "$EFFECT_NAME" == "Off" ]]; then
    SPEED_VAL=1
else
    echo -e "\n${BLUE}${BOLD}[4] Select Speed${NC}"
    echo "   0) Slow"
    echo "   1) Normal"
    echo "   2) Fast"
    echo -n -e "${YELLOW}>> Choose [0-2]: ${NC}"
    read -r SPEED_INPUT
    if [[ "$SPEED_INPUT" =~ ^[0-2]$ ]]; then SPEED_VAL=$SPEED_INPUT; else SPEED_VAL=1; fi
fi

# ==============================================================================
# APPLY
# ==============================================================================
echo -e "\n${CYAN}:: Applying Settings...${NC}"

# Build 10-LED String
INTENSITY_STR=""
for i in {1..10}; do INTENSITY_STR="$INTENSITY_STR $COLOR_DEC"; done

for zone in $LED_BASE/zotac:rgb:spectra_zone_*; do
    if [ -d "$zone" ]; then
        if [ -f "$zone/rgb/effect" ]; then P="$zone/rgb"; else P="$zone"; fi

        # 1. Color
        if [ -f "$zone/multi_intensity" ]; then echo "$INTENSITY_STR" > "$zone/multi_intensity"; fi

        # 2. Brightness
        if [ -f "$P/brightness" ]; then echo $BRIGHT_CHOICE > "$P/brightness"; fi

        # 3. Speed
        if [ -f "$P/speed" ]; then echo $SPEED_VAL > "$P/speed"; fi

        # 4. Effect (Magic Sequence for Static)
        if [ -f "$P/effect" ]; then
            if [ "$EFFECT_ID" -eq 5 ]; then
                # The Magic Sequence: Dance (4) -> Wait -> Static (5)
                echo 4 > "$P/effect" 2>/dev/null
                sleep 0.1
                echo 5 > "$P/effect" 2>/dev/null
            else
                echo $EFFECT_ID > "$P/effect" 2>/dev/null
            fi
        fi

        # 5. Trigger
        if [ -f "$zone/brightness" ]; then echo 255 > "$zone/brightness"; fi
    fi
done

echo -e "${GREEN}${BOLD}✔ Done! Configuration applied.${NC}"
echo ""
