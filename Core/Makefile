include $(THEOS)/makefiles/common.mk

# Injected into iconservicesagent and every app: Foundation only, no UIKit.
TWEAK_NAME = AvalancheCore
AvalancheCore_FILES = AVIconStore.m AVIconServices.x
AvalancheCore_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations
AvalancheCore_FRAMEWORKS = Foundation CoreGraphics ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk
