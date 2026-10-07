TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PowercutsActionsPackZH
PowercutsActionsPackZH_FILES = $(wildcard Actions/*.xm)
PowercutsActionsPackZH_LIBRARIES = powercuts
PowercutsActionsPackZH_CFLAGS = -fobjc-arc -w -fno-modules -I$(PWD)/include
PowercutsActionsPackZH_LDFLAGS = -L$(PWD)/lib

include $(THEOS_MAKE_PATH)/tweak.mk
