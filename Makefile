TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PCZHExecutor
PCZHExecutor_FILES = $(wildcard Actions/*.xm)
PCZHExecutor_CFLAGS = -fobjc-arc -w -fno-modules

include $(THEOS_MAKE_PATH)/tweak.mk
