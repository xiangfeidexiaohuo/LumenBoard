include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Lumen
Lumen_FILES = main.m LMAppDelegate.m LMConfigStore.m LMThemesViewController.m LMSettingsViewController.m LMApplyViewController.m ../Shared/LMThemeLibrary.m
Lumen_FRAMEWORKS = UIKit QuartzCore
Lumen_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new
Lumen_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
