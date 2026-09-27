# Avalanche

A theme engine for **iOS 17 – 26** (rootless jailbreaks). It reads the icon themes made for SnowBoard, Anemone and
WinterBoard and themes **every app icon on the system**: home screen, dock, App Library, Spotlight, Settings,
notifications and share sheets.

Written from scratch, it's not based on any other theme engine.

## Features

- **All apps, all places.** Icons are themed inside IconServices, the framework iOS renders every app icon with,
  including apps whose icon comes from an asset catalog.
- **No delay, no stale icons.** Themed icons get their own entries in the system icon cache (the theme's token is part
  of the cache key), so a stock icon cached earlier never shows up again and cached theme icons load instantly.
- **Apply = pre-render.** Tapping *Apply* renders all changed icons before the respring, with progress in the app.
  After the respring the home screen is themed right away.
- **Theme icons as designed.** Theme icons keep their own shape and transparency (circles, glyphs), or use the iOS
  shape with one switch. iOS 18 dark and tinted mode derive from the theme icon, can be turned off, and themes can ship
  their own `-dark.png` / `-tinted.png` icons.
- **Several themes with priorities.** Activate any number of themes and drag them into order; the first one that has
  an icon for an app wins.
- **Home screen app** in English and German with theme previews and an icon cache reset.

## Theme formats

```
/var/jb/Library/Themes/<Theme>.theme/IconBundles/<bundle id>[-large][-dark|-tinted][@2x|@3x][~iphone|~ipad].png
/var/jb/Library/Themes/<Theme>.theme/Icons/<App Name>.png
```

Bundle identifiers are matched case-insensitively; the best file per icon is picked (right device, then `-large`,
then the highest scale).

## How it works

| Part | Runs in | Does |
| --- | --- | --- |
| `Core` (`AvalancheCore.dylib`) | apps, SpringBoard, `iconservicesagent` | Foundation only. Marks themed icons (`ISBundleIdentifierIcon`, `ISBundleIcon`, `ISApplicationIdentityIcon`) with a themed cache key and gives `iconservicesagent` a resource provider with the theme artwork when it renders them. |
| `SpringBoard` (`AvalancheSpringBoard.dylib`) | SpringBoard | Resolves the active themes into `IconMap.plist`, pre-renders changed icons on *Apply* and resprings. |
| `App` (`Avalanche.app`) | – | Picks themes and options, writes `Config.plist`. |

Settings and the icon map live in `/var/jb/var/mobile/Library/Avalanche`, inside the jailbreak root, where sandboxed
processes like `iconservicesagent` can read them.

The hooks were written against the decompiled IconServices of iOS 17, 18.2, 26.1 and 26.3. **Not tested on a device
yet.**

## Building

```sh
export THEOS=~/theos
make package
```

Uses the Theos iOS 16.5 SDK (private frameworks); pin Theos' Logos to `a623700` (see `.github/workflows/build.yml`).

## License

MIT, see `LICENSE`.
