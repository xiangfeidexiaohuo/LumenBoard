export THEOS_PACKAGE_SCHEME = rootless
export ARCHS = arm64 arm64e
export TARGET = iphone:clang:16.5:15.0
export FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

SUBPROJECTS = Core SpringBoard App
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "sbreload || killall -9 SpringBoard"
