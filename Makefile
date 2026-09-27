# make package                              -> rootless (iphoneos-arm64)
# make package THEOS_PACKAGE_SCHEME=roothide -> roothide (iphoneos-arm64e), needs roothide/theos
THEOS_PACKAGE_SCHEME ?= rootless
export THEOS_PACKAGE_SCHEME
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0
export FINALPACKAGE = 1

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
export ADDITIONAL_LDFLAGS = -lroothide
endif

include $(THEOS)/makefiles/common.mk

SUBPROJECTS = Core SpringBoard App
include $(THEOS_MAKE_PATH)/aggregate.mk

before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control
	$(ECHO_NOTHING)echo "Icon: file://$(THEOS_PACKAGE_INSTALL_PREFIX)/Applications/LumenBoard.app/AppIcon60x60@3x.png" >> "$(THEOS_STAGING_DIR)/DEBIAN/control"$(ECHO_END)

after-install::
	install.exec "sbreload || killall -9 SpringBoard"
