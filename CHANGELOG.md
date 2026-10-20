# Changelog

## 1.0.3
- Fixed themes randomly showing "0 icons" and no preview, for example while your package manager is still installing themes
- Themes that change while LumenBoard is open (installed, updated, removed) are picked up right away
- Pull down on the theme list to read every theme again
- A theme that can't be read now says so instead of showing "0 icons"
- Diagnostics list every installed theme, with details for themes that have no icons

## 1.0.2
- Fixed theme previews and icon counts not showing when many themes are installed
- Theme previews load faster and use less memory
- Previews are kept until a theme changes, so they no longer reload every time you open the app

## 1.0.1
- If iconservicesagent renders a theme icon without the theme, SpringBoard now renders it itself (should fix icons not changing on some palera1n devices)
- Large theme icons are scaled down to 512 px to save memory
- New diagnostics page (Settings → Diagnostics) with a report you can copy

## 1.0.0
- First release as LumenBoard
