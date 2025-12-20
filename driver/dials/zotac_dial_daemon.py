#!/usr/bin/env python3
# ==============================================================================
#  ZOTAC ZONE DIAL DAEMON (v2.0)
# ==============================================================================
#  Interprets raw dial events from the Zotac Zone HID driver.
#  - Features Direct Backlight Control to fix Steam Gaming Mode issues.
# ==============================================================================

import evdev
import argparse
import sys
import time
import glob
import os
from evdev import UInput, ecodes as e

# --- Argument Parsing ---
parser = argparse.ArgumentParser()
parser.add_argument("--left", default="volume", help="Left Dial Function")
parser.add_argument("--right", default="brightness", help="Right Dial Function")
args = parser.parse_args()

# --- Constants ---
TARGET_NAME = "ZOTAC Gaming Zone Dials"

# --- Hardware Identification (Brightness Fix) ---
# We look for the backlight controller to write to it directly.
# This bypasses Steam Input issues in Gaming Mode.
BACKLIGHT_PATH = None
try:
    # Usually /sys/class/backlight/amdgpu_bl0 or similar
    paths = glob.glob("/sys/class/backlight/*")
    if paths:
        # Sort to prefer 'amdgpu' if multiple exist
        paths.sort(key=lambda x: "amdgpu" not in x) 
        BACKLIGHT_PATH = paths[0]
        print(f"Backlight Controller found: {BACKLIGHT_PATH}")
except Exception as err:
    print(f"Warning: Could not detect backlight: {err}")

# --- Action Map ---
# (Key_List, Modifier_Key, Relative_Axis, Multiplier)
ACTIONS = {
    "volume":            ([e.KEY_VOLUMEUP, e.KEY_VOLUMEDOWN], None, None, 1),
    "brightness":        (None, None, None, 0), # Handled specially via Sysfs
    "scroll":            (None, None, e.REL_WHEEL, 1),
    "scroll_inverted":   (None, None, e.REL_WHEEL, -1),
    "scroll_horizontal": (None, None, e.REL_HWHEEL, 1),
    "arrows_vertical":   ([e.KEY_UP, e.KEY_DOWN], None, None, 1),
    "arrows_horizontal": ([e.KEY_RIGHT, e.KEY_LEFT], None, None, 1),
    "page_scroll":       ([e.KEY_PAGEUP, e.KEY_PAGEDOWN], None, None, 1),
    "media":             ([e.KEY_NEXTSONG, e.KEY_PREVIOUSSONG], None, None, 1),
    "zoom":              (None, e.KEY_LEFTCTRL, e.REL_WHEEL, 1),
}

# --- Setup Virtual Device ---
cap = {
    e.EV_KEY: [e.KEY_VOLUMEUP, e.KEY_VOLUMEDOWN, e.KEY_BRIGHTNESSUP, e.KEY_BRIGHTNESSDOWN,
               e.KEY_UP, e.KEY_DOWN, e.KEY_LEFT, e.KEY_RIGHT, e.KEY_PAGEUP, e.KEY_PAGEDOWN,
               e.KEY_NEXTSONG, e.KEY_PREVIOUSSONG, e.KEY_LEFTCTRL],
    e.EV_REL: [e.REL_WHEEL, e.REL_HWHEEL]
}

try:
    ui = UInput(cap, name="Zotac Zone Virtual Dials", version=0x3)
except OSError as e:
    print(f"Error creating UInput device: {e}")
    sys.exit(1)

def adjust_backlight_hardware(direction):
    """Directly modifies the system brightness file."""
    if not BACKLIGHT_PATH: return

    try:
        # Paths
        val_file = os.path.join(BACKLIGHT_PATH, "brightness")
        max_file = os.path.join(BACKLIGHT_PATH, "max_brightness")

        # Read current state
        with open(max_file, 'r') as f: max_val = int(f.read().strip())
        with open(val_file, 'r') as f: cur_val = int(f.read().strip())

        # Calculate step (5% of max)
        step = max(1, max_val // 20)
        
        # Calculate new value
        new_val = cur_val + (step * direction)
        new_val = max(0, min(new_val, max_val))

        # Write
        with open(val_file, 'w') as f: f.write(str(new_val))
        
    except Exception as e:
        print(f"Backlight Error: {e}")

def handle_event(mode, value):
    # 1. SPECIAL CASE: Brightness (Direct Hardware Control)
    if mode == "brightness":
        # value is 1 (CW) or -1 (CCW)
        adjust_backlight_hardware(1 if value > 0 else -1)
        return

    # 2. STANDARD CASES: Input Emulation
    if mode not in ACTIONS: return
    keys, modifier, rel_axis, mult = ACTIONS[mode]

    if rel_axis:
        if modifier: ui.write(e.EV_KEY, modifier, 1)
        ui.write(e.EV_REL, rel_axis, value * mult)
        if modifier: ui.write(e.EV_KEY, modifier, 0)
    elif keys:
        key = keys[0] if value > 0 else keys[1]
        ui.write(e.EV_KEY, key, 1)
        ui.write(e.EV_KEY, key, 0)

    ui.syn()

def main_loop():
    print(f"Starting Dial Daemon...")
    print(f" -> Left: {args.left} | Right: {args.right}")
    
    while True:
        try:
            device = None
            devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
            for dev in devices:
                if TARGET_NAME in dev.name:
                    device = dev
                    break
            
            if device:
                print(f"Captured: {device.name}")
                try:
                    device.grab()
                    for event in device.read_loop():
                        if event.type == e.EV_REL:
                            if event.code == e.REL_HWHEEL:
                                handle_event(args.left, event.value)
                            elif event.code == e.REL_WHEEL:
                                handle_event(args.right, event.value)
                except OSError:
                    print("Device busy (Steam grabbed it?). Retrying...")
                    time.sleep(2)
            else:
                time.sleep(3)
                
        except Exception as err:
            print(f"Error: {err}")
            time.sleep(3)

if __name__ == "__main__":
    main_loop()
