HOST ?= 0
KILL ?= 0
ROOTLESS ?= 1

ifeq ($(ROOTLESS),1)
export THEOS_PACKAGE_SCHEME=rootless
endif

DEBUG = 1
PACKAGE_VERSION = $(THEOS_PACKAGE_BASE_VERSION)

export ARCHS = arm64 arm64e
export SYSROOT = $(THEOS)/sdks/iPhoneOS16.5.sdk
export TARGET = iphone:clang:16.5:15.0

SUBPROJECTS += Tweak Prefs

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk




