# LumenBoard

Icon theme engine for iOS 17 - 26. Works with SnowBoard, Anemone and WinterBoard themes.

Supports rootless (Dopamine, palera1n) and roothide (Relaxin, Bootstrap, Dopamine-roothide).

## Features

- themes every app icon: home screen, dock, App Library, Spotlight, Settings, notifications, share sheet
- icons are rendered before the respring, so nothing pops in afterwards
- multiple themes, drag them in the order you want
- theme icons keep their own shape, or use the iOS shape
- dark and tinted icons on iOS 18 (`-dark.png` / `-tinted.png`)
- app in English and German

## Install

Get the .deb for your jailbreak from Releases:

- rootless: `com.xsxs18.lumenboard_<version>_iphoneos-arm64.deb`
- roothide: `com.xsxs18.lumenboard_<version>_iphoneos-arm64e.deb`

Install themes (rootless: `/var/jb/Library/Themes`, roothide: `/Library/Themes` in the jbroot), open LumenBoard,
enable them and tap Apply.

Don't install it together with SnowBoard, Anemone or NeonBoard. Themes that depend on SnowBoard or Anemone install
fine, LumenBoard provides both.

## Themes

```
<Theme>.theme/IconBundles/<bundle id>[-large][-dark|-tinted][@2x|@3x][~iphone|~ipad].png
<Theme>.theme/Icons/<App Name>.png
```

## Building

```sh
make package                                   # rootless
make package THEOS_PACKAGE_SCHEME=roothide     # roothide, needs roothide/theos
```

Logos has to be on a623700, newer versions break lines that continue after `%orig`.

## License

MIT
