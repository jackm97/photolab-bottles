# DxO PhotoLab 9 on Bottles

1. Bottles → Preferences → General → Repositories: set the catalogs, then restart Bottles.
   - Components: `https://raw.githubusercontent.com/jackm97/photolab-bottles/catalog/components`
   - Dependencies: `https://raw.githubusercontent.com/jackm97/photolab-bottles/catalog/dependencies`
2. Preferences → Runners → Other Wine runners: download the newest `photolab-wine-<sha7>`.
3. Download
   `https://raw.githubusercontent.com/jackm97/photolab-bottles/main/artifacts/dxo-photolab9.bottle.yml`,
   save it locally, and use Bottles' Import to load it. If a later `photolab-wine` runner is
   listed, pick the newest one as the bottle's runner.
4. Run DxO's own `Setup.exe` in the bottle and activate DxO.
5. Updating: run `build-runner` (Actions tab), which runs the catalog sync. Then download the new
   runner and switch the bottle to it.

## Refreshing the mirror

Run `catalog-sync` from the Actions tab with the defaults.
