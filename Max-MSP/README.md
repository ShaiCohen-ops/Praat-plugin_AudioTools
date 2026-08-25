# Praat AudioTools for Max/MSP

Current test packages for Max 9. These builds are provided for testing and are not yet an official release.

## Windows 64-bit

Download:

`Praat_AudioTools_1.0.0_Windows_x64.zip`

1. Unzip the archive.
2. Move the extracted `Praat_AudioTools` folder to:

   `Documents/Max 9/Packages/`

3. Restart Max.

The Windows package already includes both:

- `AudioTools.praat~.mxe64`
- `Praat.exe`

They are located in the package `externals` folder, so no additional Praat installation is required for this test package.

## macOS Universal2

Download:

`Praat_AudioTools_1.0.0_macOS_Universal2.zip`

This build supports both Apple Silicon (`arm64`) and Intel (`x86_64`) Macs.

1. Unzip the archive.
2. Move the extracted `Praat_AudioTools` folder to:

   `Documents/Max 9/Packages/`

3. Download Praat for macOS separately from the official Praat distribution.
4. Place `Praat.app` inside:

   `Praat_AudioTools/externals/`

   next to:

   `AudioTools.praat~.mxo`

The resulting structure should be:

```text
Praat_AudioTools/
└── externals/
    ├── AudioTools.praat~.mxo
    └── Praat.app
```

5. Restart Max.

### macOS quarantine

On first use, macOS or Max may report that the external is quarantined. If Max offers to remove the quarantine attribute, approve it.

If needed, quarantine can also be removed from the whole package in Terminal:

```bash
xattr -dr com.apple.quarantine "$HOME/Documents/Max 9/Packages/Praat_AudioTools"
```

## Current build

- Max package: `1.0.0`
- `AudioTools.praat~`: `v1.36.1`
- macOS: Universal2 (`arm64` + `x86_64`)
- Windows: x64

The package includes the current Praat AudioTools script library under:

`misc/plugin_AudioTools/`
