# Praat AudioTools – Ableton Live Bridge

This Max for Live device provides bidirectional integration between Ableton Live and Praat.

## Requirements

- Ableton Live with Max for Live
- Praat

No Python installation is required.

The Praat AudioTools Max package and the `AudioTools.praat~` external are not required.

## Open an Ableton Audio Clip in Praat

1. Select an Audio Clip in Ableton Live.
2. Click **OPEN IN PRAAT** in the Max for Live device.
3. The source audio file of the selected clip will open automatically in Praat.

The device opens the original source audio file referenced by the Ableton clip.

Ableton-specific processing such as Warp, Clip Gain, Transpose, Detune, fades, or track effects is not rendered into the file opened in Praat.

## Praat Location

The device searches automatically for Praat in common locations.

### Windows

Recommended location:

`C:\Program Files\Praat\Praat.exe`

The device also checks common user locations, the system PATH, and `PRAAT_PATH`.

If you use the portable version of Praat, place `Praat.exe` in one of the standard locations or add it to the system PATH.

### macOS

Recommended location:

`/Applications/Praat.app`

The device also checks common user locations, the system PATH, and `PRAAT_PATH`.

## Praat → Ableton Live

Audio processed in Praat can also be sent back to Ableton Live using the Praat AudioTools Ableton bridge.

The processed Sound is transferred through a WAV file and inserted into the Ableton Arrangement at the current playhead position.

## Installation

1. Install Praat.
2. Place the `.amxd` device in your Ableton Live User Library or another convenient location.
3. Drag the device onto an Audio Track.
4. No additional Max package installation is required.

## Praat AudioTools

Praat AudioTools is an open-source environment for experimental composition, sound transformation, and analysis using Praat.

GitHub:  
https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools

Shai Cohen  
Department of Music  
Bar-Ilan University