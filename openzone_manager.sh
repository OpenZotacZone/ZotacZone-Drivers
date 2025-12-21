#!/bin/bash
# ==============================================================================
#  OPENZONE MANAGER v1.6
# ==============================================================================
#  Features:
#  - Deadzone Fix (Forces Outer Deadzone to 0)
#  - Dial Configuration (Direct Systemd Service Modification)
#  - Back Button Mapping (M1/M2)
#  - Advanced RGB (Hex/Presets/Fix)
#  - Vibration Control
# ==============================================================================

# --- Styling & Colors ---
B_RED='\033[1;31m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_BLUE='\033[1;34m'
B_PURPLE='\033[1;35m'
B_CYAN='\033[1;36m'
B_WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

# --- Paths & Detection ---
HID_PATH=""
for path in /sys/class/hidraw/hidraw*/device; do
    if [ -f "$path/save_config" ]; then HID_PATH="$path"; break; fi
done
LED_BASE="/sys/class/leds"

# Dial Config Paths (Service Based)
DIAL_SERVICE_NAME="zotac-dials.service"
DIAL_SERVICE_PATH="/etc/systemd/system/$DIAL_SERVICE_NAME"
DIAL_SCRIPT_PATH="/usr/local/bin/zotac_dial_daemon.py"

if [ "$EUID" -ne 0 ]; then
    echo -e "${B_RED}Error:${NC} Run as root: ${B_WHITE}sudo $0${NC}"
    exit 1
fi

if [ -z "$HID_PATH" ]; then
    echo -e "${B_RED}Error:${NC} Zotac Zone driver not found."
    exit 1
fi

# --- Helper Functions ---

set_hid_val() {
    echo "$2" > "$1" 2>/dev/null
    echo "1" > "$HID_PATH/save_config" 2>/dev/null
}

get_clean_val() {
    if [ -f "$1" ]; then cat "$1" | tr -d '\0' | sed 's/^[ \t]*//;s/[ \t]*$//'; else echo "none"; fi
}

get_button_status() {
    local btn="$1"
    local g=$(get_clean_val "$HID_PATH/$btn/remap/gamepad")
    local k=$(get_clean_val "$HID_PATH/$btn/remap/keyboard")
    local m=$(get_clean_val "$HID_PATH/$btn/remap/mouse")

    if [[ "$m" != "none" && -n "$m" ]]; then echo -e "${B_PURPLE}Mouse: $m${NC}"
    elif [[ "$k" != "none" && -n "$k" ]]; then echo -e "${B_CYAN}Key: $k${NC}"
    elif [[ "$g" != "none" && -n "$g" ]]; then echo -e "${B_GREEN}Gamepad: $g${NC}"
    else echo -e "${GRAY}Unmapped${NC}"; fi
}

draw_header() {
    clear
    echo -e "${B_BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${B_BLUE}║              ${B_WHITE}OPENZONE MANAGER ${B_YELLOW}v1.6${B_BLUE}                  ║${NC}"
    echo -e "${B_BLUE}╚══════════════════════════════════════════════════════╝${NC}"
}

# --- DIAL CONFIGURATION (SYSTEMD) ---

# Extract current config from the ExecStart line in the service file
get_dial_state() {
    local side="$1" # "left" or "right"
    if [ ! -f "$DIAL_SERVICE_PATH" ]; then echo "Unknown"; return; fi
    local val=$(grep "ExecStart=" "$DIAL_SERVICE_PATH" | sed -n "s/.*--$side \([^ ]*\).*/\1/p")
    if [ -z "$val" ]; then echo "default"; else echo "$val"; fi
}

update_dial_service() {
    local target_side="$1"
    local new_val="$2"
    local cur_left=$(get_dial_state "left")
    local cur_right=$(get_dial_state "right")

    if [ "$target_side" == "left" ]; then cur_left="$new_val"; fi
    if [ "$target_side" == "right" ]; then cur_right="$new_val"; fi

    echo -e "\n  ${CYAN}Updating Systemd Service...${NC}"
    local new_line="ExecStart=/usr/bin/python3 $DIAL_SCRIPT_PATH --left $cur_left --right $cur_right"
    sed -i "s|^ExecStart=.*|$new_line|" "$DIAL_SERVICE_PATH"

    echo -e "  ${CYAN}Reloading Daemon...${NC}"
    systemctl daemon-reload
    systemctl restart "$DIAL_SERVICE_NAME"

    if systemctl is-active --quiet "$DIAL_SERVICE_NAME"; then
        echo -e "  ${B_GREEN}✔ Success.${NC}"
    else
        echo -e "  ${B_RED}✖ Error restarting service.${NC}"
    fi
    sleep 1
}

configure_single_dial() {
    local side="$1"
    local label="$2"
    draw_header
    echo -e "${B_YELLOW}  :: $label CONFIGURATION ::${NC}"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${B_WHITE}[1]${NC} Volume (+/-)               ${GRAY}(Default)${NC}"
    echo -e "  ${B_WHITE}[2]${NC} Brightness (+/-)"
    echo -e "  ${B_WHITE}[3]${NC} Mouse Wheel                ${GRAY}(Scroll)${NC}"
    echo -e "  ${B_WHITE}[4]${NC} Mouse Wheel Inv.           ${GRAY}(Scroll Rev)${NC}"
    echo -e "  ${B_WHITE}[5]${NC} Arrow Up & Down            ${GRAY}(Vertical)${NC}"
    echo -e "  ${B_WHITE}[6]${NC} Arrow Left & Right         ${GRAY}(Horizontal)${NC}"
    echo -e "  ${B_WHITE}[7]${NC} Page Up & Page Down        ${GRAY}(Browser)${NC}"
    echo -e "  ${B_WHITE}[8]${NC} Zoom                       ${GRAY}(Ctrl+Scroll)${NC}"
    echo -e "  ${B_WHITE}[9]${NC} Media                      ${GRAY}(Next/Prev)${NC}"
    echo -e "  ${B_WHITE}[b]${NC} Back"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -n -e "  ${B_GREEN}>> Selection:${NC} "
    read choice

    local func=""
    case $choice in
        1) func="volume" ;;
        2) func="brightness" ;;
        3) func="scroll" ;;
        4) func="scroll_inverted" ;;
        5) func="arrows_vertical" ;;
        6) func="arrows_horizontal" ;;
        7) func="page_scroll" ;;
        8) func="zoom" ;;
        9) func="media" ;;
        b|B) return ;;
        *) return ;;
    esac

    if [ -n "$func" ]; then
        update_dial_service "$side" "$func"
    fi
}

configure_dials_menu() {
    if [ ! -f "$DIAL_SERVICE_PATH" ]; then
        draw_header
        echo -e "${B_RED}  Error: Dial Service not found.${NC}"
        echo -e "  Expecting: $DIAL_SERVICE_PATH"
        read -p "  Press Enter..."
        return
    fi

    while true; do
        draw_header
        local l_st=$(get_dial_state "left")
        local r_st=$(get_dial_state "right")
        echo -e "${B_YELLOW}  :: RADIAL DIAL CONFIGURATION ::${NC}"
        echo -e "  ──────────────────────────────────────────────────────"
        echo -e "  ${B_WHITE}[1]${NC} Configure ${B_CYAN}Left Dial${NC}   ➜  ${B_GREEN}$l_st${NC}"
        echo -e "  ${B_WHITE}[2]${NC} Configure ${B_CYAN}Right Dial${NC}  ➜  ${B_GREEN}$r_st${NC}"
        echo -e "  ${B_WHITE}[b]${NC} Back to Main Menu"
        echo -e "  ──────────────────────────────────────────────────────"
        echo -n -e "  ${B_GREEN}>> Option:${NC} "
        read d_opt
        case $d_opt in
            1) configure_single_dial "left" "LEFT DIAL" ;;
            2) configure_single_dial "right" "RIGHT DIAL" ;;
            b|B) return ;;
        esac
    done
}

# --- RGB CONFIGURATION ---

configure_rgb() {
    draw_header
    echo -e "${B_YELLOW}  :: RGB LIGHTING ::${NC}"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${B_WHITE}[1]${NC} Static   ${GRAY}(Solid Color)${NC}"
    echo -e "  ${B_WHITE}[2]${NC} Breathe  ${GRAY}(Pulsing)${NC}"
    echo -e "  ${B_WHITE}[3]${NC} Cycle    ${GRAY}(Rainbow Loop)${NC}"
    echo -e "  ${B_WHITE}[4]${NC} Wave     ${GRAY}(Rainbow Wave)${NC}"
    echo -e "  ${B_WHITE}[5]${NC} Off"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -n -e "  ${B_GREEN}>> Effect:${NC} "
    read EFF_CHOICE
    case $EFF_CHOICE in
        1) ID=5; NAME="Static" ;;
        2) ID=2; NAME="Breathe" ;;
        3) ID=3; NAME="Cycle" ;;
        4) ID=0; NAME="Wave" ;;
        5) ID=240; NAME="Off" ;;
        *) return ;;
    esac

    echo -n -e "  ${B_GREEN}>> Brightness (0-4):${NC} "
    read B_VAL
    [[ ! "$B_VAL" =~ ^[0-4]$ ]] && B_VAL=4

    C_DEC="16711680"
    if [[ "$NAME" == "Static" || "$NAME" == "Breathe" ]]; then
        echo -n -e "  ${B_GREEN}>> Color (Name or Hex):${NC} "
        read C_IN
        C_IN=$(echo "$C_IN" | tr '[:upper:]' '[:lower:]')
        case $C_IN in
            red) C_DEC=$((0xFF0000)) ;; green) C_DEC=$((0x00FF00)) ;; blue) C_DEC=$((0x0000FF)) ;;
            white) C_DEC=$((0xFFFFFF)) ;; pink) C_DEC=$((0xFF1493)) ;; orange) C_DEC=$((0xFF8000)) ;;
            cyan) C_DEC=$((0x00FFFF)) ;; purple) C_DEC=$((0xFF00FF)) ;;
            [0-9a-f]*) C_DEC=$((16#$C_IN)) ;;
        esac
    fi

    echo -e "\n  ${CYAN}Applying...${NC}"
    INT_STR=""; for i in {1..10}; do INT_STR="$INT_STR $C_DEC"; done

    for z in $LED_BASE/zotac:rgb:spectra_zone_*; do
        if [ -d "$z" ]; then
            [ -f "$z/rgb/effect" ] && P="$z/rgb" || P="$z"
            [ -f "$z/multi_intensity" ] && echo "$INT_STR" > "$z/multi_intensity"
            [ -f "$P/brightness" ] && echo $B_VAL > "$P/brightness"
            if [ -f "$P/effect" ]; then
                if [ "$ID" -eq 5 ]; then echo 4 > "$P/effect"; sleep 0.1; echo 5 > "$P/effect"
                else echo $ID > "$P/effect"; fi
            fi
            [ -f "$z/brightness" ] && echo 255 > "$z/brightness"
        fi
    done
    set_hid_val "$HID_PATH/save_config" "1"
    echo -e "  ${B_GREEN}✔ Done.${NC}"; sleep 1
}

# --- BUTTON CONFIGURATION ---

configure_button() {
    local btn="$1"; local name="$2"
    draw_header
    echo -e "${B_YELLOW}  :: MAPPING ($name) ::${NC}"
    echo -e "  Current: $(get_button_status "$btn")"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${B_WHITE}[1]${NC} Gamepad Button  ${GRAY}(ABXY, Triggers)${NC}"
    echo -e "  ${B_WHITE}[2]${NC} Keyboard Key    ${GRAY}(Any Key)${NC}"
    echo -e "  ${B_WHITE}[3]${NC} Mouse Click     ${GRAY}(Left/Right)${NC}"
    echo -e "  ${B_WHITE}[4]${NC} Clear"
    echo -e "  ${B_WHITE}[b]${NC} Back"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -n -e "  ${B_GREEN}>> Selection:${NC} "
    read opt
    case $opt in
        1) read -p "  Button Code (a,b,x,y...): " v
           set_hid_val "$HID_PATH/$btn/remap/keyboard" "none"
           set_hid_val "$HID_PATH/$btn/remap/mouse" "none"
           set_hid_val "$HID_PATH/$btn/remap/gamepad" "$v" ;;
        2) read -p "  Key Code (m, space, enter...): " v
           set_hid_val "$HID_PATH/$btn/remap/gamepad" "none"
           set_hid_val "$HID_PATH/$btn/remap/mouse" "none"
           set_hid_val "$HID_PATH/$btn/remap/keyboard" "$v" ;;
        3) read -p "  Mouse (left, right, middle): " v
           set_hid_val "$HID_PATH/$btn/remap/gamepad" "none"
           set_hid_val "$HID_PATH/$btn/remap/keyboard" "none"
           set_hid_val "$HID_PATH/$btn/remap/mouse" "$v" ;;
        4) set_hid_val "$HID_PATH/$btn/remap/gamepad" "none"
           set_hid_val "$HID_PATH/$btn/remap/keyboard" "none"
           set_hid_val "$HID_PATH/$btn/remap/mouse" "none" ;;
    esac
}

# --- DEADZONE & VIBRATION ---

configure_deadzones() {
    draw_header
    echo -e "${B_YELLOW}  :: DEADZONES ::${NC}"
    echo -e "  Current (Inner Outer):"
    echo -e "  L-Stick: $(get_clean_val "$HID_PATH/axis_xy_left/deadzone")"
    echo -e "  R-Stick: $(get_clean_val "$HID_PATH/axis_xy_right/deadzone")"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${GRAY}Note: Outer deadzone will be set to 0 (Default/Raw).${NC}"
    echo -n -e "  ${B_GREEN}>> New Inner Deadzone % (0-20 recommended):${NC} "
    read v
    if [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -le 100 ]; then
        # Force outer deadzone to 0 to fix stick drift issues
        set_hid_val "$HID_PATH/axis_xy_left/deadzone" "$v 0"
        set_hid_val "$HID_PATH/axis_xy_right/deadzone" "$v 0"
        echo -e "  ${B_GREEN}✔ Updated (Inner: $v, Outer: 0).${NC}"; sleep 1
    else
        echo -e "  ${B_RED}Invalid input.${NC}"; sleep 1
    fi
}

configure_vibration() {
    draw_header
    echo -e "${B_YELLOW}  :: VIBRATION ::${NC}"
    echo -e "  Current: $(get_clean_val "$HID_PATH/vibration_intensity")"
    echo -e "  Format:  [L-Trig] [R-Trig] [L-Main] [R-Main]"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${B_WHITE}[1]${NC} 100% (Max)"
    echo -e "  ${B_WHITE}[2]${NC} 0%   (Off)"
    echo -e "  ${B_WHITE}[3]${NC} Custom"
    echo -n -e "  ${B_GREEN}>> Selection:${NC} "
    read opt
    case $opt in
        1) set_hid_val "$HID_PATH/vibration_intensity" "100 100 100 100" ;;
        2) set_hid_val "$HID_PATH/vibration_intensity" "0 0 0 0" ;;
        3) read -p "  Enter 4 values (0-100): " v
           set_hid_val "$HID_PATH/vibration_intensity" "$v" ;;
    esac
}

# --- MAIN MENU ---

while true; do
    draw_header
    echo -e "${B_YELLOW}  :: DASHBOARD ::${NC}"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${B_WHITE}[1]${NC} Configure ${B_CYAN}Left Back (M2)${NC}   ➜  $(get_button_status "btn_m2")"
    echo -e "  ${B_WHITE}[2]${NC} Configure ${B_CYAN}Right Back (M1)${NC}  ➜  $(get_button_status "btn_m1")"
    echo -e "  ${B_WHITE}[3]${NC} ${B_PURPLE}RGB Lighting Control${NC}"
    echo -e "  ${B_WHITE}[4]${NC} ${B_BLUE}Deadzone Calibration${NC}"
    echo -e "  ${B_WHITE}[5]${NC} ${B_RED}Vibration Intensity${NC}"
    echo -e "  ${B_WHITE}[6]${NC} ${B_YELLOW}Dial Configuration${NC}    ➜  ${GRAY}(Systemd Service)${NC}"
    echo -e "  ──────────────────────────────────────────────────────"
    echo -e "  ${B_WHITE}[q]${NC} Quit"
    echo -e ""
    echo -n -e "  ${B_GREEN}>> Option:${NC} "
    read main_choice

    case $main_choice in
        1) configure_button "btn_m2" "Left Back (M2)" ;;
        2) configure_button "btn_m1" "Right Back (M1)" ;;
        3) configure_rgb ;;
        4) configure_deadzones ;;
        5) configure_vibration ;;
        6) configure_dials_menu ;;
        q|Q) clear; exit 0 ;;
    esac
done
