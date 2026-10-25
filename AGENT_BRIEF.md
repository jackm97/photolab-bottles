# PhotoLab-on-Bottles — Agent Brief

You are starting a project to run DxO PhotoLab 9.14 (Windows, x64) on Linux through
Bottles (Flatpak), delivered as a reproducible setup: a custom Wine runner built in
GitHub Actions, plus Bottles catalog entries and an installer manifest served from a
GitHub repo. A human (Jack) owns decisions; you do the work and report evidence.

Read this whole file before acting. The `analysis/` directory next to it contains
ground truth extracted from the real installer; use it instead of re-deriving.

---

## 0. Rundown

1. **Goal:** new machine → install Bottles → paste repo URLs in Preferences → Repositories →
   run the "DxO PhotoLab 9" installer from the Installers tab → pick DxO's own Setup.exe → done.
2. **Milestone 1 (do this first):** custom runner with four honest Wine patches; unmodified
   Setup.exe installs; app launches; RAW preview renders; export works; GPU identified as the
   RTX 4090; DeepPRIME runs on the GPU via ONNX Runtime + DirectML over vkd3d-proton.
3. **Workflow:** evidence first. Every claim in a commit message or report points at a log line,
   a disassembly, a spec file, or a test. Never cite a community script as proof.
4. **Environment:** host is Bluefin Dakota (immutable, bootc, NVIDIA RTX 4090 + Intel iGPU).
   All tooling via pixi (`pixi.toml`), Windows binaries via `zig cc`, runtime testing in the
   Bottles Flatpak, official builds in GitHub Actions driven with `gh`. No distrobox.
5. **Hard rules:** no DxO or Microsoft binaries in the repo or Releases. No patches that fake
   installed MSIX packages except the single, isolated, opt-in Bootstrap stub. Do not modify
   DxO's installed files at runtime.

---

## 1. Ground truth (already established — do not re-research)

### 1.1 Installer
- `DxO_PhotoLab9_Setup.exe` = 7-Zip SFX → 32-bit MFC `DxOPhotoLab_9.14.0_Bootstrapper.exe`,
  `DxO.PhotoLab.Installer.WiX.msi` (WiX 5), `Data1..9.cab` (~860 MB).
- Bootstrapper calls `ntdll!RtlGetVersion` and accepts only
  `(Major==10 && 19045<=Build<=21999) || (Major==10 && Build>=22621) || Major>10`.
  See `analysis/bootstrapper-IsPlatformSupported.asm`. Builds 22000–22620 rejected.
  It runs `msiexec /i <msi> /qn /log "<Temp>\photolab_install_log.log" INSTALLERDIRECTORY=<dir>`
  and writes `<Temp>\photolab_installer_bootstrap_log.log`.
- Because the bootstrapper is 32-bit, Wine resolves its version from the **Wow6432Node** copy of
  `HKLM\Software\Microsoft\Windows NT\CurrentVersion`. Fixes must land in both views
  (`reg add ... /reg:32` and `/reg:64`). Bottles' presets are wrong: `win11`=22000, `win10`=19043.
  Bottles' `dotnet48` dependency recipe ends with `set_windows: win10`, re-breaking it.
- MSI: no `LaunchCondition` table. Custom actions of interest (`analysis/msi-*.idt`):
  - `CheckWindowsAppSDKRuntime` (seq 6589, `NOT REMOVE`): WiX DTF managed CA calling WinRT
    `Windows.Management.Deployment.PackageManager.FindPackagesForUser`. Absent in every Wine
    tree checked (upstream 11.20, wine-staging, Kron4ek wine-tkg, Proton experimental_11)
    → throws → msiexec rolls back.
  - `SetIsWebView2RuntimeRequired` (seq 6588): skipped if
    `HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}\pv`
    exists (the WebView2 Evergreen installer creates it).
  - `DownloadDependencies`/`InstallDependencies`: fetch ONNX models, SAM masks, FilmPack assets,
    and three execution providers (CUDA, OpenVINO, TensorRT-RTX cu13) from download-center.dxo.com.
    Manifest: `analysis/dependencies.json`. The managed CA needs .NET Framework 4.8 in the prefix.
- `artifacts/DxO.PhotoLab.Installer.WiX.patched.msi` = original with the two CA conditions
  repointed to `PREVENTDOWNGRADING` (false on fresh install). Fallback only; Milestone 1 should
  make it unnecessary. `tools/msipatch.py` reproduces it (needs `olefile`; libmsi cannot rewrite
  this MSI — string pool > 64K entries and embedded language-transform substorages).

### 1.2 Installed app (see `analysis/native-imports.txt`, `analysis/*.config`)
- `DxO.PhotoLab.exe` (.NET 4.8 WPF) + `DxO.PhotoLab.ProcessingCore.exe` ("DopCor" sidecar),
  WCF over `net.pipe://localhost/DopCor/` → Windows transport auth → NTLM → needs `ntlm_auth`
  (Samba winbind). The Bottles Flatpak base `org.winehq.Wine` bundles Samba for this.
- `DxOCorrectionEngine.dll` statically imports `Microsoft.WindowsAppRuntime.Bootstrap.dll`
  (`MddBootstrapInitialize2`, `MddBootstrapShutdown`), `dxgi`, `d3d12` (incl. `D3D12GetInterface`
  — missing in Wine's d3d12, exported by vkd3d-proton → **vkd3d-proton is mandatory**),
  `opengl32`, `pdh`, `cfgmgr32`, `GFSDK_Aftermath_Lib.x64.dll` (shipped). Delay-loads
  `InferenceHelpersProviderOnnx.dll` (→ `onnxruntime.dxo.dll` → `DirectML.dll` → D3D12) and
  `libInferenceWinML.dll` (not shipped; Windows ML via App SDK → dead under Wine).
- `Microsoft.WindowsAppRuntime.Bootstrap.dll` imports kernel32/kernelbase functions that are
  `@ stub` in all Wine trees: `GetPackageInfo`, `OpenPackageInfoByFullName`, `ClosePackageInfo`,
  `FormatApplicationUserModelId`, `VerifyPackageFamilyName`. Wine loads the DLL (missing imports
  become crash thunks); calling `MddBootstrapInitialize2` crashes.
- `Microsoft.WindowsAPICodePack.dll` P/Invokes `kernel32!UnregisterApplicationRecoveryCallback`
  (absent in Wine; `Register...` exists) → exception at exit.
- Wine's `dxcore.dll`: `IsAttributeSupported` returns FALSE (stub), `QueryState` returns
  E_NOTIMPL — in upstream, staging, tkg and Proton. DirectML/ORT/DxO query DXCore → CPU-only.
- Settings: `UseWindowsMLAccelerationWhenAvailable` (in `user.config`; must be False under Wine),
  `EnableWindowsML=true` (compiled feature flag), `EnableOnnxForInferenceDevice`,
  `WinMLUseGraphicQueue`, `EnableWpfGpuAcceleration`, `PrefsOpenCLAcceleration`, `RequireGPU=true`.
- Logs: `drive_c/users/<u>/AppData/Local/DxO/DxO PhotoLab 9/Logs/{DxO.PhotoLab.txt,DopCor.txt}`.

### 1.3 Empirical run (Furlot script, Ubuntu 26.04 distrobox, Wine Staging 11.19)
- Installed and launched. GPU reported as "NVIDIA GeForce GTX 470" (wined3d's fallback identity
  → Wine's builtin dxgi/d3d answered, not DXVK). Loading sample RAWs hung. Treat the script
  (github.com/Furlot/Dxo-Photolab-Wine) as one data point, not a reference.

### 1.4 Bottles facts (v67.x, Flatpak)
- Preferences → Repositories: per-catalog personal URLs (Components, Dependencies, Installers);
  env vars `PERSONAL_COMPONENTS/DEPENDENCIES/INSTALLERS`. Override **replaces** the catalog, so
  mirror upstream entries you still need (DXVK 3.1.1, vkd3d-proton 3.0.1, dotnet48, webview2,
  selawik, corefonts, vcredist2022).
- Installer manifest (bottlesdevs/programs format): `Runners` allowlist, `Dependencies`,
  `Parameters`, `Steps` with `install_exe`/`install_msi` (`url: local` for user-supplied file),
  `run_script` (bash on host with `!bottle_path`/`!bottle_drive` placeholders),
  `run_winecommand`, `update_config` (yaml/json/ini only — `user.config` is XML).
- Registry Rules exist (reusable .reg blobs, triggers: components, dependencies, start_program,
  stop_program, all) but config-backup import dropped them; deliver registry via manifest steps.
- Flatpak sandbox sees only its own data dir by default; `flatpak override --user
  --filesystem=<dir> com.usebottles.bottles` to expose a folder.
- `artifacts/dxo-photolab9.bottle.yml` is a working config-backup import (env vars, deps, params).

---

## 2. Environment setup (Bluefin Dakota, no distrobox)

Everything runs on the host through **pixi** (`pixi.toml` at the repo root) plus the Bottles
Flatpak. `pixi install` once, then `pixi run <task>`; tasks are listed in `pixi.toml`.

- **Analysis tooling:** msitools, 7zip, cabextract, binutils, python + pefile/olefile — all from
  conda-forge/PyPI via pixi.
- **Windows helper binaries** (Bootstrap stub, dxcore/winver/PackageManager probes): built with
  `zig cc -target x86_64-windows-gnu` / `x86-windows-gnu`. Zig bundles mingw headers, so no
  mingw-w64 package is needed (conda-forge has none). Tasks: `build-stub`, `build-probes`.
- **Wine builds — two routes, try A first, fall back to B:**
  - **Route A (pure pixi, experimental):** conda-forge gcc for the Unix side, clang+lld as the
    PE cross-compiler (`CROSSCC="clang --target=x86_64-windows"`), WoW64 mode
    (`--enable-archs=i386,x86_64`) so no 32-bit host libs are needed. Unix-side libraries
    (freetype, gnutls, X11, Vulkan, GStreamer…) come from pixi at build time and are dlopened from
    the host at runtime. If configure or link fails on a conda-vs-glibc detail, stop and switch.
  - **Route B (same as CI):** the forked Kron4ek `build_wine.sh` inside `bubblewrap` (from pixi)
    with an Ubuntu bootstrap tarball. Bootstraps need debootstrap/root to *create*, so
    `.github/workflows/bootstraps.yml` builds and publishes them as a Release asset once; locally
    just download and build. Unprivileged user namespaces are enabled on Bluefin (Flatpak
    requires them), so bwrap needs no root.
  - Official artifacts always come from Actions (`pixi run ci-build-runner`, then
    `ci-fetch-runner`); local builds are for iteration only.
- **Bottles:** host Flatpak. Drop a runner dir into
  `~/.var/app/com.usebottles.bottles/data/bottles/runners/` (`pixi run runner-install`) and it
  appears in Bottles. Expose the work folder once:
  `flatpak override --user --filesystem=~/photolab-work com.usebottles.bottles`.
- **gh CLI** is authenticated: create the repo, trigger workflows, download run artifacts and
  releases, open issues/PRs. Prefer `gh run watch` over polling.
- Vulkan check on the host: `pixi run vulkaninfo --summary` must list the RTX 4090.
- Wine upstream source: GitHub mirror `wine-mirror/wine` (gitlab.winehq.org is bot-walled for
  non-browser fetches). Staging: `wine-staging/wine-staging`. Builds reference: `Kron4ek/Wine-Builds`.
- Keep DxO's Setup.exe and extracted MSI/CABs in `~/photolab-work/dxo/`; never commit them.

## 3. Repository layout to create

```
photolab-bottles/
├── AGENT_BRIEF.md            # this file
├── pixi.toml                 # all tooling; `pixi run` tasks for analysis, builds, Bottles, CI
├── analysis/                 # from bundle; append new findings as dated .md files
├── wine-patches/
│   ├── honest/               # upstream-quality, LGPL, each with a commit-style description
│   │   ├── 0001-dxcore-attributes-querystate.patch
│   │   ├── 0002-kernelbase-appmodel-package-info.patch
│   │   ├── 0003-windows.management.deployment-packagemanager-empty.patch
│   │   └── 0004-kernel32-UnregisterApplicationRecoveryCallback.patch
│   ├── lie/                  # never upstreamed, opt-in via DLL override
│   │   └── 0101-mddbootstrap-builtin-stub.patch
│   ├── extra/                # community patchsets we carry (see §5)
│   └── series.{staging,vanilla}
├── bootstrap-stub/           # clean-room MddBootstrap*.c + .def (MIT headers from microsoft/WindowsAppSDK); built with zig cc
├── tools/
│   ├── msipatch.py           # fallback MSI CA neutralizer (from bundle)
│   ├── dxcore-probe.c        # enumerates adapters, prints attributes/QueryState (zig cc)
│   ├── winver-probe.c        # prints RtlGetVersion; build i686 AND x86_64
│   ├── pm-probe.cpp          # activates PackageManager, calls FindPackagesForUser
│   └── dxo-userconfig.py     # sets UseWindowsMLAccelerationWhenAvailable=False etc. in user.config
├── build/                    # fork of Kron4ek build_wine.sh + bootstraps; CUSTOM_PATCHES_DIR hook
├── components/  dependencies/  installers/   # Bottles catalogs: mirror + our entries + index files
└── .github/workflows/
    ├── bootstraps.yml        # one-off: build Kron4ek-style Ubuntu bootstraps, publish as Release asset
    ├── build-runner.yml      # dispatch(wine_tag) → tarball → Release → PR adding component YAML
    ├── rebase-watch.yml      # daily: try `git am -3` of series on new Wine tags; open issue on conflict
    ├── build-helpers.yml     # mingw builds + CI tests under the built runner
    ├── mirror-sync.yml       # daily: refresh mirrored catalog entries
    └── catalog-index.yml     # regenerate index.yml (+ per-version index) and lint
```

---

## 4. Tasks, in order (each has an acceptance test)

### T1 — Reproduce the baseline (1 day)
- Build a plain WoW64 Wine 11.20-staging, unpatched (Route A; Route B if A fails — record which).
- Create a prefix; set build 26100 in both views; verify:
  `wine cmd /c ver` and `wine C:\\windows\\syswow64\\cmd.exe /c ver` both print 26100.
- Install DXVK 3.1.1 + vkd3d-proton 3.0.1 into the prefix (DLLs into system32/syswow64, overrides).
- Run `winetricks dotnet48 vcrun2022 d3dcompiler_47 corefonts` and the WebView2 Evergreen installer.
- Run unmodified Setup.exe with `WINEDEBUG=+loaddll` captured. **Expected:** bootstrapper passes;
  MSI log ends at `CheckWindowsAppSDKRuntime`. Record the exact log lines. This is the control.
- Acceptance: `analysis/T1-baseline.md` with the MSI log excerpt and the loaddll list for
  `msiexec`, showing which `dxgi`/`d3d12`/`dxcore` loaded (builtin vs native).

### T2 — Honest patch 0003: empty PackageManager (2–3 days)
- New builtin `windows.management.deployment.dll` (model: `dlls/windows.applicationmodel/`).
  Implement `Windows.Management.Deployment.PackageManager` with `FindPackagesForUser*` returning
  an empty `IIterable<Package>`; deployment methods return `E_NOTIMPL`. Register the class.
- Test: `tools/pm-probe` gets an empty enumeration, no exception.
- Re-run Setup.exe. **Key experiment:** does `CheckWindowsAppSDKRuntime` now complete, and does
  the MSI then try (and fail) to install the App SDK runtime? Record both outcomes.
  If install still aborts → use `artifacts/*.patched.msi` as the fallback path and note why.

### T3 — Honest patches 0002 + 0004 (1–2 days)
- kernelbase: `OpenPackageInfoByFullName` / `GetPackageInfo` / `ClosePackageInfo` → look up the
  package repository key
  `HKLM\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\PackageRepository\Packages`
  (pattern: existing `GetPackagesByPackageFamily`); return `ERROR_NOT_FOUND` when absent.
  `FormatApplicationUserModelId` / `VerifyPackageFamilyName`: full implementations (pure string).
  Add the api-ms-win-appmodel forwarders.
- kernel32/kernelbase: `UnregisterApplicationRecoveryCallback` → S_OK.
- Test: a small exe calling each export; no crash, expected return codes.
- Launch PhotoLab. **Key experiment:** with the real Bootstrap now failing *cleanly*
  (`0x80670016`), does DxOCorrectionEngine tolerate it? If the app aborts → apply lie patch 0101
  (builtin stub, active only with override `Microsoft.WindowsAppRuntime.Bootstrap=b`; return
  value configurable via `MDDSTUB_HR`). Record which was needed.

### T4 — Honest patch 0001: dxcore (3–5 days)
- `IsAttributeSupported`: report `D3D11_GRAPHICS`, `D3D12_GRAPHICS`, `D3D12_CORE_COMPUTE`,
  `D3D12_GENERIC_ML`, and `DXCORE_HARDWARE_TYPE_ATTRIBUTE_GPU` for hardware Vulkan adapters.
- `IsQueryStateSupported`/`QueryState(AdapterMemoryBudget)` via `D3DKMTQueryVideoMemoryInfo`.
- `GetProperty`: real `DedicatedAdapterMemory`, `DriverDescription`, `HardwareID`.
- `CreateAdapterListByPreference(HighPerformance)`: discrete before integrated (this machine has
  an Intel iGPU; the 4090 must come first).
- Check upstream state first: MRs !8634/!8729 (GetAdapterByLuid), !8737 (DriverDescription),
  !8949, !6391 (prefer native dxcore). Rebase on whatever merged.
- Test: `tools/dxcore-probe` under the runner; in CI with lavapipe, on the host with the 4090.
- In PhotoLab: Preferences → Performance shows "NVIDIA GeForce RTX 4090", ~24 GB. DopCor log
  shows the same. **If it still says GTX 470**, trace with `WINEDEBUG=+loaddll,+dxgi,+dxcore`
  for *both* `DxO.PhotoLab.exe` and `DxO.PhotoLab.ProcessingCore.exe` and find which builtin
  answered.

### T5 — Runtime config and the RAW hang (1–2 days)
- `tools/dxo-userconfig.py`: ensure `UseWindowsMLAccelerationWhenAvailable=False`,
  `EnableWpfGpuAcceleration=False` in `user.config` (XML; create the setting if absent).
- Registry: `HKCU\Software\Microsoft\Avalon.Graphics\DisableHWAcceleration=1`, ClearType,
  per-app builtin d3d for `msedgewebview2.exe`.
- Env: `VK_LOADER_DRIVERS_DISABLE=lvp_icd.*` (Unix side), `DXVK_FILTER_DEVICE_NAME=RTX`,
  `VKD3D_FILTER_DEVICE_NAME=RTX`, `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--no-sandbox --disable-gpu --disable-gpu-compositing`.
- Reproduce the sample-RAW hang; capture `DxO.PhotoLab.txt`, `DopCor.txt`, `nvidia-smi dmon`,
  and `VK_LOADER_DEBUG=driver`. Identify whether inference went to WinML, llvmpipe, iGPU, or CPU.
- Acceptance: a RAW renders; DeepPRIME XD3 preview shows GPU load in `nvidia-smi`; JPEG export
  completes; app exits cleanly (no CodePack exception).

### T6 — Actions pipeline (2–3 days)
- `build/`: fork Kron4ek `build_wine.sh` + `create_ubuntu_bootstraps.sh`; add
  `CUSTOM_PATCHES_DIR` applied after staging; build WoW64 (`--enable-archs=i386,x86_64`) and also
  classic amd64 as fallback artifact. Name: `photolab-wine-<ver>-staging-r<N>-amd64[-wow64]`.
- `build-runner.yml`: inputs `wine_tag`, `series`; cache bootstraps; publish Release with
  tarball + MD5 + patched-source tarball (LGPL); open PR adding `components/runners/wine/<name>.yml`.
- `build-helpers.yml`: zig cross-builds of stub + probes (same commands as pixi tasks); run probes under the fresh runner with
  lavapipe; run the 32/64 registry-view test.
- `rebase-watch.yml`: daily `git am -3` of both series on new Wine tags; issue on conflict;
  pre-release build on success (never auto-added to the installer allowlist).
- Acceptance: a green run producing a runner tarball that Bottles lists after dropping it in
  `~/.var/app/com.usebottles.bottles/data/bottles/runners/`.

### T7 — Bottles catalogs + installer manifest (1–2 days)
- Mirror the needed upstream entries; add our runner; regenerate `index.yml` (check which index
  file Bottles 67.x actually fetches — per-version files exist in the components repo).
- `installers/Software/dxo-photolab-9.yml`: `Runners: [photolab-wine-…-r1]`; deps
  `dotnet48, vcredist2022, d3dcompiler_47, corefonts, selawik, webview2`; steps: registry fix
  (both views, after deps), prefix config, `install_exe url: local`, `run_script` → userconfig;
  `Executable` entry. Resolve: where Bottles stages `url: local` files, valid `Parameters` keys,
  whether a manifest can set bottle env vars (if not: document the two env vars for the user).
- Acceptance: fresh Bottles on the host, repo URLs pasted, installer completes end-to-end;
  T5 acceptance holds in that bottle.

### T8 — Report
- `analysis/MILESTONE1.md`: what was needed (honest vs lie), what wasn't, logs for each gate,
  open questions. Which honest patches are ready to submit upstream.

### Stretch (only after T8)
- CUDA EP via SveSop/nvcuda relay (needs NVAPI off; check if DxO prefers it over DirectML).
- OpenCL in the Flatpak. WebView2 "what's new". Upstream submissions. Vanilla-only series.

---

## 5. Community patchsets to carry (`wine-patches/extra/`)

Jack wants the runner to include common patchsets beyond ours. Base is **wine-staging**
(already includes nvapi stub, ntdll-RtlQueryPackageIdentity, dxgi/d3d fixes). Evaluate and
carry these, each in its own file with a one-paragraph justification, and *drop* anything that
only matters for games:

- **From wine-tkg "staging" profile:** the proton-win10-default change is irrelevant (we set the
  version ourselves); `proton_battleye`/`eac_bridge` irrelevant. Kron4ek's tkg config reverts
  `dcomp-DCompositionCreateDevice2` "due to breakage" — note that WebView2 uses DirectComposition;
  test both ways.
- **Proton/GE-sourced, potentially relevant:** media-foundation/GStreamer improvements (video
  thumbnails in PhotoLibrary), child-window rendering and Vulkan child windows (WPF + WebView2
  hosting), any `pdh`/`cfgmgr32` improvements, shared-memory/futex sync (if not already upstream
  as ntsync). Cherry-pick by subject from `ValveSoftware/wine` experimental branches;
  record upstream commit IDs.
- **Kron4ek's own:** `EnableMouseInPointer.patch`, `fix-proton-compilation…` — include if they
  apply cleanly; harmless.
- **Explicit decisions needed from Jack:** whether to include wine-staging's `nvapi` stub vs
  DXVK-NVAPI (NVAPI off for M1 anyway), and whether to pull SveSop/nvcuda into the runner or keep
  it a Bottles dependency (recommended: dependency).
- Keep a `PATCHSETS.md` table: name, source commit, why, tested-on-runner version.

---

## 6. Diagnostics cheat sheet

- Which DLL answered: `WINEDEBUG=+loaddll` → look for `dxgi.dll`, `d3d11.dll`, `d3d12.dll`,
  `d3d12core.dll`, `dxcore.dll` with `(native)` vs `(builtin)` — for **each** process.
- Version seen by a 32-bit process: `wine C:\\windows\\syswow64\\cmd.exe /c ver`.
- Bootstrap/appmodel: `WINEDEBUG=+appmodel,+module,+seh`; "unimplemented function" = missing patch.
- Export failure: `DopCor.txt` "Unable to contact DopCor instance" → check `which ntlm_auth`
  in the sandbox, `WINEDEBUG=+ntlm,+secur32`.
- MSI: always `/l*v`; grep `return value 3` and `CustomAction ... returned actual error`.
- Inference device: `nvidia-smi dmon` during preview; `VK_LOADER_DEBUG=driver`; dxcore-probe
  in the same prefix/env.
- Bottles sandbox: `flatpak run --command=sh com.usebottles.bottles` for a shell with the
  Flatpak's view of the filesystem.

---

## 7. Reporting format

Short rundown first (what changed, what passed, what's blocked), then details with log
excerpts and file paths. Light structure, no walls of prose. Flag every unverified claim.
Ask Jack before: any patch that fakes package presence beyond 0101, any change to the
installer allowlist, any spend (Actions minutes are fine), anything touching DxO activation.
