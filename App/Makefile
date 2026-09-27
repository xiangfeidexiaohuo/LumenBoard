include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Avalanche
Avalanche_FILES = main.m AVAppDelegate.m AVConfigStore.m AVThemesViewController.m AVSettingsViewController.m AVApplyViewController.m ../Shared/AVThemeLibrary.m
Avalanche_FRAMEWORKS = UIKit QuartzCore
Avalanche_CFLAGS = -fobjc-arc -Wall -Wno-deprecated-declarations -Wno-unguarded-availability-new
Avalanche_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
