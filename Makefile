TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = zz_pczh
zz_pczh_FILES = $(wildcard Actions/*.xm)
zz_pczh_CFLAGS = -fobjc-arc -w -fno-modules -I$(PWD)/include

include $(THEOS_MAKE_PATH)/tweak.mk
zz_pczh_LDFLAGS = -Wl,-no_fixup_chains
