// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * HID driver for ZOTAC Gaming Zone Controller
 *
 * Copyright (c) 2025 Luke D. Jones <luke@ljones.dev>
 * Modded by Pfahli
 */

#ifndef __HID_ZOTAC_ZONE_H
#define __HID_ZOTAC_ZONE_H

#include <linux/hid.h>
#include <linux/usb.h>
#include <linux/input.h>
#include <linux/leds.h>
#include <linux/led-class-multicolor.h>

#define ZOTAC_VERSION "0.1.5"

#define ZOTAC_VENDOR_ID 0x1ee9
#define ZOTAC_ALT_VENDOR_ID 0x1e19
#define ZOTAC_PRODUCT_ID 0x1590

#define ZOTAC_GAMEPAD_INTERFACE 0
#define ZOTAC_DIAL_INTERFACE 1
#define ZOTAC_REPORT_INTERFACE 2
#define ZOTAC_COMMAND_INTERFACE 3

#define ZOTAC_FF_REPORT_ID 0x00
#define ZOTAC_FF_REPORT_LEN 8
#define ZOTAC_NUM_URBS 3
#define ZOTAC_NUM_FF_URBS 2

#define CMD_SAVE_CONFIG 0xFB
#define CMD_SET_RGB 0xAD
#define CMD_GET_RGB 0xAE

#define ZOTAC_RGB_ZONE_COUNT 2
#define ZOTAC_RGB_LEDS_PER_ZONE 10

#define SENSITIVITY_POINT_COUNT 4

/* Command codes for button mapping */
#define CMD_SET_BUTTON_MAPPING 0xA1
#define CMD_GET_BUTTON_MAPPING 0xA2

#define BUTTON_MAX 0x18
#define MAX_GAMEPAD_BUTTONS 14
#define MAX_KEYBOARD_KEYS 6
#define MAX_MOUSE_BUTTONS 3

#define DEVICE_ATTR_RO_NAMED(_name, _attr_name)               \
struct device_attribute dev_attr_##_name = {   \
	.attr = { .name = _attr_name, .mode = 0444 }, \
	.show = _name##_show,                         \
}

#define DEVICE_ATTR_WO_NAMED(_name, _attr_name)               \
struct device_attribute dev_attr_##_name = {   \
	.attr = { .name = _attr_name, .mode = 0200 }, \
	.store = _name##_store,                       \
}

#define DEVICE_ATTR_RW_NAMED(_name, _attr_name)               \
struct device_attribute dev_attr_##_name = {   \
	.attr = { .name = _attr_name, .mode = 0644 }, \
	.show = _name##_show,                         \
	.store = _name##_store,                       \
}

enum qam_mode {
	QAM_MODE_KEYBOARD = 0,
	QAM_MODE_STEAM,
	QAM_MODE_CUSTOM,
	QAM_MODE_LENGTH,
};

/* Dial Functions */
enum zotac_dial_function {
	DIAL_SCROLL = 0,        /* Vertical Scroll */
	DIAL_SCROLL_INV,        /* Inverted Vertical Scroll */
	DIAL_SCROLL_H,          /* Horizontal Scroll */
	DIAL_VOLUME,            /* Volume Up/Down */
	DIAL_BRIGHTNESS,        /* Brightness Up/Down */
	DIAL_ARROWS_V,          /* Up/Down Keys */
	DIAL_ARROWS_H,          /* Left/Right Keys */
	DIAL_MEDIA,             /* Next/Prev Track */
	DIAL_PAGE_SCROLL,       /* PageUp/PageDown */
	DIAL_ZOOM,              /* Ctrl + Wheel */
	DIAL_FUNC_MAX
};

struct zotac_gamepad {
	struct input_dev *dev;
	struct zotac_device *zotac;
	bool disconnect;

	struct usb_endpoint_descriptor *ep_in;
	struct usb_endpoint_descriptor *ep_out;

	struct urb *urbs[ZOTAC_NUM_URBS];
	unsigned char *urb_buf[ZOTAC_NUM_URBS];

	struct urb *ff_urbs[ZOTAC_NUM_FF_URBS];
	unsigned char *ff_data[ZOTAC_NUM_FF_URBS];
	dma_addr_t ff_dma[ZOTAC_NUM_FF_URBS];
	atomic_t ff_active[ZOTAC_NUM_FF_URBS];

	atomic_t button_press_in_progress;

	struct delayed_work button_work;
	unsigned int button_to_press;
	unsigned int button_to_press2;
	bool update_qam;
	enum qam_mode qam_mode;
};

struct zotac_rgb_dev {
	struct zotac_device *zotac;
	struct hid_device *hdev;
	struct led_classdev_mc led_rgb_dev;
	struct work_struct work;
	bool output_worker_initialized;
	spinlock_t lock;

	bool removed;
	bool update_rgb;
	uint8_t red[ZOTAC_RGB_LEDS_PER_ZONE];
	uint8_t green[ZOTAC_RGB_LEDS_PER_ZONE];
	uint8_t blue[ZOTAC_RGB_LEDS_PER_ZONE];
	uint8_t brightness;
};

struct zotac_rgb_data {
	struct {
		uint8_t red[ZOTAC_RGB_LEDS_PER_ZONE];
		uint8_t green[ZOTAC_RGB_LEDS_PER_ZONE];
		uint8_t blue[ZOTAC_RGB_LEDS_PER_ZONE];
		uint8_t brightness;
	} zone[ZOTAC_RGB_ZONE_COUNT];
	uint8_t effect;
	uint8_t speed;
	uint8_t brightness;
	bool initialized;
};

struct stick_sensitivity {
	u8 values[SENSITIVITY_POINT_COUNT * 2];
};

struct deadzone {
	u8 inner;
	u8 outer;
};

struct button_mapping {
	u32 target_gamepad_buttons;
	u8 target_modifier_keys;
	u8 target_keyboard_keys[MAX_KEYBOARD_KEYS];
	u8 target_mouse_buttons;
};

struct zotac_cfg_data {
	struct mutex command_mutex;
	u8 sequence_num;
	/* deadzones */
	struct deadzone ls_dz;
	struct deadzone rs_dz;
	struct deadzone lt_dz;
	struct deadzone rt_dz;
	struct stick_sensitivity left_stick_sensitivity;
	struct stick_sensitivity right_stick_sensitivity;
	u8 button_turbo;
	/* Indexed by the button number */
	struct button_mapping button_mappings[BUTTON_MAX+1];

	/* Dial configuration */
	enum zotac_dial_function left_dial_func;
	enum zotac_dial_function right_dial_func;
};

struct zotac_device {
	struct hid_device *hdev;
	struct input_dev *wheel_input;
	struct input_dev *mouse_input;
	struct zotac_gamepad *gamepad;
	struct usb_device *udev;
	struct zotac_cfg_data *cfg_data;
	struct zotac_rgb_dev *led_rgb_dev;
	struct zotac_rgb_data led_rgb_data;
};
extern struct zotac_device zotac;

void zotac_init_input_device(struct input_dev *input_dev,
							 struct hid_device *hdev, const char *name);

struct usb_interface *zotac_get_usb_interface(struct hid_device *hdev);

int zotac_init_gamepad(struct zotac_device *zotac, struct usb_interface *intf);

void zotac_process_gamepad_report(struct zotac_device *zotac, u8 *data,
								  int size);

void zotac_cleanup_gamepad(struct zotac_device *zotac);

void zotac_gamepad_send_button(struct zotac_device *zotac, int buttons[],
							   int num_buttons);

int zotac_cfg_init(struct zotac_device *zotac);

void zotac_cfg_cleanup(struct zotac_device *zotac);

int zotac_register_sysfs(struct zotac_device *zotac);

void zotac_unregister_sysfs(struct zotac_device *zotac);

int zotac_send_get_command(struct zotac_device *zotac, u8 cmd_code, u8 setting,
						   const u8 *req_data, size_t req_data_len,
						   u8 *output_data, size_t *output_len);

int zotac_send_set_command(struct zotac_device *zotac, u8 cmd_code, u8 setting,
						   const u8 *data, size_t data_len);

int zotac_send_get_byte(struct zotac_device *zotac, u8 cmd_code, u8 setting,
						const u8 *req_data, size_t req_data_len);

/* RGB LED functions */
int zotac_rgb_init(struct zotac_device *zotac);
void zotac_rgb_cleanup(struct zotac_device *zotac);
void zotac_rgb_resume(struct zotac_device *zotac);
void zotac_rgb_suspend(struct zotac_device *zotac);

#endif /* __HID_ZOTAC_ZONE_H */
