# SPDX-License-Identifier: GPL-2.0+
#
# Makefile - Zotac Zone handheld device driver
# Adapted for out-of-tree compilation (Bazzite/Fedora Atomic)
#

# HID Driver Module
obj-m += zotac-zone-hid.o
zotac-zone-hid-y := zotac-zone-hid-core.o zotac-zone-hid-rgb.o zotac-zone-hid-input.o zotac-zone-hid-config.o

# Platform Driver Modules
# Built as separate modules to prevent symbol conflicts as per install script
obj-m += firmware_attributes_class.o
obj-m += zotac-zone-platform.o

# Standard Kbuild for external modules
all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean
