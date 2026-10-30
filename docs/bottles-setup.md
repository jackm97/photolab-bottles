# DxO PhotoLab 9 on Bottles

1. Bottles → Preferences → General → Repositories: set the catalogs, then restart Bottles.
   - Components: `https://raw.githubusercontent.com/jackm97/photolab-bottles/catalog/components`
   - Dependencies: `https://raw.githubusercontent.com/jackm97/photolab-bottles/catalog/dependencies`
   The Dependencies catalog is required for `netfx48-winrt`.
2. Preferences → Runners: enable showing unstable/pre-release components, since the runner is in
   the unstable channel, and install `soda-11.0-35-photolab-b649ee9`.
3. Open [dxo-photolab9.bottle.yml](https://github.com/jackm97/photolab-bottles/blob/main/artifacts/dxo-photolab9.bottle.yml)
   on GitHub, use the page's "Download raw file" button, save the file, and then import it in
   Bottles. The bottle already names the soda runner. X11 is a toggle (`wayland: false`), and the
   bottle file's header has the Hub hint.
4. Run DxO's own `Setup.exe` in the bottle and activate DxO.
5. Updating: run `build-runner` (Actions tab), which runs the catalog sync. New runner builds
   appear in the catalog after the catalog sync; change the bottle's runner in its settings. Older
   `photolab-wine-*` runners are still listed in the catalog but are superseded.

## Refreshing the mirror

Run `catalog-sync` from the Actions tab with the defaults.

## Known gaps

- winedmo (Wine's media demuxer) links `libavcodec.so.63`, which the Bottles flatpak runtime lacks.
- wineopenxr needs `libopenxr_loader`, which the flatpak lacks, so no OpenXR json ships.
- The Windows App Runtime can't install under Wine, so DxO runs in its "Compatible" mode.
