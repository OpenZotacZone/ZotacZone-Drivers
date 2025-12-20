#!/usr/bin/env python3
# ==============================================================================
#  ZOTAC ZONE DIAL DAEMON
# ==============================================================================
#  Interprets raw dial events from the Zotac Zone HID driver and translates
#  them into keyboard/mouse actions (Volume, Scroll, etc.) via uinput.
# ==============================================================================

import evdev
import argparse
import sys
import time
from evdev import UInput, ecodes as e

# --- Argument Parsing ---
parser = argparse.ArgumentParser()
parser.add_argument("--left", default="volume", help="Left Dial Function")
parser.add_argument("--right", default="brightness", help="Right Dial Function")
args = parser.parse_args()

# --- Constants ---
TARGET_NAME = "ZOTAC Gaming Zone Dials"

# Action Map: (Key_List, Modifier_Key, Relative_Axis, Multiplier)
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

# --- Setup Virtual Device ---
# Define capabilities (Keys and Relative Axes we might use)
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
    print("Ensure you have permissions (root) and uinput module is loaded.")
    sys.exit(1)

def handle_event(mode, value):
    """Translates a raw dial turn (1 or -1) into the target action."""
    if mode not in ACTIONS:
        return

    keys, modifier, rel_axis, mult = ACTIONS[mode]

    # Value is typically 1 (CW) or -1 (CCW)
    # We map positive value to the first key/positive relative

    if rel_axis:
        # Relative Event (Scroll, Zoom)
        if modifier: ui.write(e.EV_KEY, modifier, 1)
        ui.write(e.EV_REL, rel_axis, value * mult)
        if modifier: ui.write(e.EV_KEY, modifier, 0)
    elif keys:
        # Key Press Event
        # If value > 0 (CW) use keys[0], else keys[1]
        key = keys[0] if value > 0 else keys[1]
        ui.write(e.EV_KEY, key, 1)
        ui.write(e.EV_KEY, key, 0)

    ui.syn()

def main_loop():
    print(f"Starting Dial Daemon...")
    print(f" -> Left Dial Mode:  {args.left}")
    print(f" -> Right Dial Mode: {args.right}")

    device = None

    while True:
        try:
            # 1. Locate the Device
            found = False
            devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
            for dev in devices:
                if TARGET_NAME in dev.name:
                    device = dev
                    found = True
                    break

            if found and device:
                print(f"Captured Input Device: {device.name} ({device.path})")

                # 2. Grab the device (Exclusive Access)
                # This prevents the default kernel events (if any) from leaking through
                try:
                    device.grab()
                except IOError:
                    print("Warning: Could not grab device. Is another service using it?")

                # 3. Event Loop
                for event in device.read_loop():
                    if event.type == e.EV_REL:
                        # Map REL_HWHEEL to Left Dial logic
                        if event.code == e.REL_HWHEEL:
                            handle_event(args.left, event.value)
                        # Map REL_WHEEL to Right Dial logic
                        elif event.code == e.REL_WHEEL:
                            handle_event(args.right, event.value)

            else:
                print("Waiting for Zotac Dials device...")
                time.sleep(3)

        except Exception as err:
            print(f"Error in main loop: {err}")
            time.sleep(3)

if __name__ == "__main__":
    main_loop()
