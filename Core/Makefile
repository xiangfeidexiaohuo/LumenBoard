include $(THEOS)/makefiles/common.mk

# Injected into iconservicesagent and every app: Foundation only, no UIKit.
TWEAK_NAME = LumenCore
LumenCore_FILES = LMIconStore.m LMIconServices.x
LumenCore_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations
LumenCore_FRAMEWORKS = Foundation CoreGraphics ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk
