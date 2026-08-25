# ============================================================
# Praat AudioTools - Knight's Tour Sonification.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Click-free segment boundaries
# v0.5 (2026): Removed the audible clicks at every segment boundary. Per-segment gain is now ramped across the join (raised-cosine, default 5 ms) instead of stepping, and segment boundaries are computed on the sample grid so no sample is duplicated or dropped. Tour data, mapping and visualization unchanged.
# v0.4 (2026): Replaced invalid/repeating preset paths with five validated 64-square Knight's Tours; added runtime tour-integrity checks; tightened input/range validation. DSP mapping and visualization architecture unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Knight's Tour Audio Mapping with Sonification & Visualization
#   Maps the classic chess Knight's Tour to audio parameters:
#   - X coordinate (1-8) → Stereo position
#   - Y coordinate (1-8) → Intensity/loudness
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.5:
#   - Fixed audible clicks at all 63 segment joins (piecewise-constant L/R gain
#     stepped discontinuously at every boundary)
#   - Intensity and constant-power pan gains are now folded into one per-channel
#     gain and ramped from the previous segment's value with a raised cosine
#   - New form field: Declick ramp (ms), default 5.0; set to 0 for v0.4 behaviour
#   - Segment boundaries computed in samples (round(k*n/64)) instead of seconds,
#     so output length now matches the input exactly (was +1 sample)
#   - One Formula pass per channel instead of three per segment
#
# Changelog v0.4:
#   - Replaced all five preset paths with validated 64-square Knight's Tours
#   - Added runtime checks for coordinate range, square uniqueness, and legal knight moves
#   - Input validation now requires exactly one selected Sound
#   - Custom intensity/stereo ranges are fully clamped to 0..1 before ordering
#
# Previous v0.3 changes:
#   - Fixed critical formula interpolation bugs
#   - Modern selectObject: syntax throughout
#   - Efficient batch processing (pre-build all segments, single concatenate)
#   - Added effect presets
#   - Added visualization modes (off, final, realtime, step-by-step with audio)
#   - Added play_result toggle
#   - Proper string building for formulas
#   - Cleaner object management
# ============================================================

# ============================================================
# FORM
# ============================================================

form Knight's Tour Sonification
    comment Tour Pattern
    comment ─────────────────────────────────────────
    optionmenu Tour_preset: 1
        option Warnsdorff (Classic)
        option Spiral-biased Tour
        option Diagonal-biased Tour
        option Center-start Tour
        option Side-switching Tour
    comment ─────────────────────────────────────────
    comment Effect Preset
    optionmenu Effect_preset: 1
        option Custom
        option Full Range (dramatic)
        option Subtle Movement
        option Center Focused
        option Left-Heavy
        option Right-Heavy
        option Intensity Only (no pan)
        option Pan Only (no intensity)
    comment ─────────────────────────────────────────
    real Intensity_min 0.3
    real Intensity_max 1.0
    real Stereo_min 0.0
    real Stereo_max 1.0
    comment ─────────────────────────────────────────
    comment Visualization Mode
    optionmenu Visualization_mode: 4
        option Off (fastest processing)
        option Final only
        option Real-time (visual only)
        option Step-by-step with audio (original)
    positive Visualization_delay_(s) 0.03
    comment ─────────────────────────────────────────
    boolean Play_result 1
    comment Boundary de-click ramp — 0 restores the v0.4 hard steps
    real Declick_ramp_(ms) 5.0
endform

clearinfo

# ============================================================
# EFFECT PRESETS
# ============================================================

if effect_preset = 2
    # Full Range - dramatic
    intensity_min = 0.2
    intensity_max = 1.0
    stereo_min = 0.0
    stereo_max = 1.0
    effectName$ = "full_range"
elsif effect_preset = 3
    # Subtle Movement
    intensity_min = 0.7
    intensity_max = 1.0
    stereo_min = 0.3
    stereo_max = 0.7
    effectName$ = "subtle"
elsif effect_preset = 4
    # Center Focused
    intensity_min = 0.5
    intensity_max = 1.0
    stereo_min = 0.35
    stereo_max = 0.65
    effectName$ = "center"
elsif effect_preset = 5
    # Left-Heavy
    intensity_min = 0.4
    intensity_max = 1.0
    stereo_min = 0.0
    stereo_max = 0.5
    effectName$ = "left"
elsif effect_preset = 6
    # Right-Heavy
    intensity_min = 0.4
    intensity_max = 1.0
    stereo_min = 0.5
    stereo_max = 1.0
    effectName$ = "right"
elsif effect_preset = 7
    # Intensity Only
    intensity_min = 0.2
    intensity_max = 1.0
    stereo_min = 0.5
    stereo_max = 0.5
    effectName$ = "intensity_only"
elsif effect_preset = 8
    # Pan Only
    intensity_min = 1.0
    intensity_max = 1.0
    stereo_min = 0.0
    stereo_max = 1.0
    effectName$ = "pan_only"
else
    effectName$ = "custom"
endif

# ============================================================
# VISUALIZATION MODE FLAGS
# ============================================================

showRealtime = 0
showFinal = 0
playEachSegment = 0

if visualization_mode = 2
    # Final only
    showFinal = 1
elsif visualization_mode = 3
    # Real-time visual only
    showRealtime = 1
    showFinal = 1
elsif visualization_mode = 4
    # Step-by-step with audio
    showRealtime = 1
    showFinal = 1
    playEachSegment = 1
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# Clamp both endpoints to 0..1, then order each pair
if intensity_min < 0
    intensity_min = 0
endif
if intensity_min > 1
    intensity_min = 1
endif
if intensity_max < 0
    intensity_max = 0
endif
if intensity_max > 1
    intensity_max = 1
endif
if intensity_min > intensity_max
    temp = intensity_min
    intensity_min = intensity_max
    intensity_max = temp
endif

if stereo_min < 0
    stereo_min = 0
endif
if stereo_min > 1
    stereo_min = 1
endif
if stereo_max < 0
    stereo_max = 0
endif
if stereo_max > 1
    stereo_max = 1
endif
if stereo_min > stereo_max
    temp = stereo_min
    stereo_min = stereo_max
    stereo_max = temp
endif

original = selected("Sound")
originalName$ = selected$("Sound")

if declick_ramp < 0
    declick_ramp = 0
endif

selectObject: original
duration = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# Convert to mono if stereo
if nChannels > 1
    selectObject: original
    monoSound = Convert to mono
    createdMono = 1
else
    monoSound = original
    createdMono = 0
endif

# Sample grid for exact, gap-free segment boundaries
selectObject: monoSound
nSamples = Get number of samples
dt = 1 / sr
xminMono = Get start time

# ============================================================
# KNIGHT'S TOUR PATTERNS
# ============================================================

# Initialize arrays
for i from 1 to 64
    tourX[i] = 0
    tourY[i] = 0
endfor

# Load selected validated tour pattern
if tour_preset = 1
    # Warnsdorff - validated 64-square Knight's Tour
    tourName$ = "Warnsdorff"
    tourX[1] = 1
    tourY[1] = 1
    tourX[2] = 2
    tourY[2] = 3
    tourX[3] = 1
    tourY[3] = 5
    tourX[4] = 2
    tourY[4] = 7
    tourX[5] = 4
    tourY[5] = 8
    tourX[6] = 6
    tourY[6] = 7
    tourX[7] = 8
    tourY[7] = 8
    tourX[8] = 7
    tourY[8] = 6
    tourX[9] = 6
    tourY[9] = 8
    tourX[10] = 8
    tourY[10] = 7
    tourX[11] = 7
    tourY[11] = 5
    tourX[12] = 8
    tourY[12] = 3
    tourX[13] = 7
    tourY[13] = 1
    tourX[14] = 5
    tourY[14] = 2
    tourX[15] = 3
    tourY[15] = 1
    tourX[16] = 1
    tourY[16] = 2
    tourX[17] = 2
    tourY[17] = 4
    tourX[18] = 1
    tourY[18] = 6
    tourX[19] = 2
    tourY[19] = 8
    tourX[20] = 4
    tourY[20] = 7
    tourX[21] = 3
    tourY[21] = 5
    tourX[22] = 1
    tourY[22] = 4
    tourX[23] = 2
    tourY[23] = 2
    tourX[24] = 4
    tourY[24] = 1
    tourX[25] = 6
    tourY[25] = 2
    tourX[26] = 8
    tourY[26] = 1
    tourX[27] = 7
    tourY[27] = 3
    tourX[28] = 6
    tourY[28] = 1
    tourX[29] = 8
    tourY[29] = 2
    tourX[30] = 7
    tourY[30] = 4
    tourX[31] = 8
    tourY[31] = 6
    tourX[32] = 7
    tourY[32] = 8
    tourX[33] = 5
    tourY[33] = 7
    tourX[34] = 3
    tourY[34] = 8
    tourX[35] = 1
    tourY[35] = 7
    tourX[36] = 3
    tourY[36] = 6
    tourX[37] = 5
    tourY[37] = 5
    tourX[38] = 4
    tourY[38] = 3
    tourX[39] = 5
    tourY[39] = 1
    tourX[40] = 7
    tourY[40] = 2
    tourX[41] = 8
    tourY[41] = 4
    tourX[42] = 6
    tourY[42] = 3
    tourX[43] = 4
    tourY[43] = 2
    tourX[44] = 2
    tourY[44] = 1
    tourX[45] = 3
    tourY[45] = 3
    tourX[46] = 5
    tourY[46] = 4
    tourX[47] = 6
    tourY[47] = 6
    tourX[48] = 8
    tourY[48] = 5
    tourX[49] = 6
    tourY[49] = 4
    tourX[50] = 4
    tourY[50] = 5
    tourX[51] = 2
    tourY[51] = 6
    tourX[52] = 1
    tourY[52] = 8
    tourX[53] = 3
    tourY[53] = 7
    tourX[54] = 5
    tourY[54] = 8
    tourX[55] = 7
    tourY[55] = 7
    tourX[56] = 5
    tourY[56] = 6
    tourX[57] = 4
    tourY[57] = 4
    tourX[58] = 2
    tourY[58] = 5
    tourX[59] = 4
    tourY[59] = 6
    tourX[60] = 6
    tourY[60] = 5
    tourX[61] = 5
    tourY[61] = 3
    tourX[62] = 3
    tourY[62] = 4
    tourX[63] = 1
    tourY[63] = 3
    tourX[64] = 3
    tourY[64] = 2

elsif tour_preset = 2
    # Spiral-biased - validated 64-square Knight's Tour
    tourName$ = "Spiral-biased"
    tourX[1] = 4
    tourY[1] = 4
    tourX[2] = 3
    tourY[2] = 2
    tourX[3] = 1
    tourY[3] = 1
    tourX[4] = 2
    tourY[4] = 3
    tourX[5] = 1
    tourY[5] = 5
    tourX[6] = 2
    tourY[6] = 7
    tourX[7] = 4
    tourY[7] = 8
    tourX[8] = 3
    tourY[8] = 6
    tourX[9] = 1
    tourY[9] = 7
    tourX[10] = 3
    tourY[10] = 8
    tourX[11] = 5
    tourY[11] = 7
    tourX[12] = 7
    tourY[12] = 8
    tourX[13] = 8
    tourY[13] = 6
    tourX[14] = 6
    tourY[14] = 7
    tourX[15] = 8
    tourY[15] = 8
    tourX[16] = 7
    tourY[16] = 6
    tourX[17] = 8
    tourY[17] = 4
    tourX[18] = 7
    tourY[18] = 2
    tourX[19] = 5
    tourY[19] = 1
    tourX[20] = 6
    tourY[20] = 3
    tourX[21] = 8
    tourY[21] = 2
    tourX[22] = 6
    tourY[22] = 1
    tourX[23] = 4
    tourY[23] = 2
    tourX[24] = 2
    tourY[24] = 1
    tourX[25] = 1
    tourY[25] = 3
    tourX[26] = 2
    tourY[26] = 5
    tourX[27] = 4
    tourY[27] = 6
    tourX[28] = 5
    tourY[28] = 8
    tourX[29] = 7
    tourY[29] = 7
    tourX[30] = 6
    tourY[30] = 5
    tourX[31] = 5
    tourY[31] = 3
    tourX[32] = 3
    tourY[32] = 4
    tourX[33] = 5
    tourY[33] = 5
    tourX[34] = 7
    tourY[34] = 4
    tourX[35] = 6
    tourY[35] = 6
    tourX[36] = 8
    tourY[36] = 5
    tourX[37] = 7
    tourY[37] = 3
    tourX[38] = 8
    tourY[38] = 1
    tourX[39] = 6
    tourY[39] = 2
    tourX[40] = 4
    tourY[40] = 1
    tourX[41] = 2
    tourY[41] = 2
    tourX[42] = 1
    tourY[42] = 4
    tourX[43] = 2
    tourY[43] = 6
    tourX[44] = 1
    tourY[44] = 8
    tourX[45] = 3
    tourY[45] = 7
    tourX[46] = 1
    tourY[46] = 6
    tourX[47] = 2
    tourY[47] = 8
    tourX[48] = 4
    tourY[48] = 7
    tourX[49] = 6
    tourY[49] = 8
    tourX[50] = 8
    tourY[50] = 7
    tourX[51] = 7
    tourY[51] = 5
    tourX[52] = 5
    tourY[52] = 4
    tourX[53] = 3
    tourY[53] = 5
    tourX[54] = 5
    tourY[54] = 6
    tourX[55] = 6
    tourY[55] = 4
    tourX[56] = 8
    tourY[56] = 3
    tourX[57] = 7
    tourY[57] = 1
    tourX[58] = 5
    tourY[58] = 2
    tourX[59] = 3
    tourY[59] = 3
    tourX[60] = 4
    tourY[60] = 5
    tourX[61] = 2
    tourY[61] = 4
    tourX[62] = 1
    tourY[62] = 2
    tourX[63] = 3
    tourY[63] = 1
    tourX[64] = 4
    tourY[64] = 3

elsif tour_preset = 3
    # Diagonal-biased - validated 64-square Knight's Tour
    tourName$ = "Diagonal-biased"
    tourX[1] = 1
    tourY[1] = 1
    tourX[2] = 3
    tourY[2] = 2
    tourX[3] = 1
    tourY[3] = 3
    tourX[4] = 2
    tourY[4] = 1
    tourX[5] = 4
    tourY[5] = 2
    tourX[6] = 6
    tourY[6] = 1
    tourX[7] = 8
    tourY[7] = 2
    tourX[8] = 7
    tourY[8] = 4
    tourX[9] = 8
    tourY[9] = 6
    tourX[10] = 7
    tourY[10] = 8
    tourX[11] = 5
    tourY[11] = 7
    tourX[12] = 3
    tourY[12] = 8
    tourX[13] = 1
    tourY[13] = 7
    tourX[14] = 2
    tourY[14] = 5
    tourX[15] = 3
    tourY[15] = 7
    tourX[16] = 1
    tourY[16] = 8
    tourX[17] = 2
    tourY[17] = 6
    tourX[18] = 1
    tourY[18] = 4
    tourX[19] = 2
    tourY[19] = 2
    tourX[20] = 4
    tourY[20] = 1
    tourX[21] = 5
    tourY[21] = 3
    tourX[22] = 7
    tourY[22] = 2
    tourX[23] = 5
    tourY[23] = 1
    tourX[24] = 6
    tourY[24] = 3
    tourX[25] = 7
    tourY[25] = 1
    tourX[26] = 8
    tourY[26] = 3
    tourX[27] = 6
    tourY[27] = 2
    tourX[28] = 8
    tourY[28] = 1
    tourX[29] = 7
    tourY[29] = 3
    tourX[30] = 8
    tourY[30] = 5
    tourX[31] = 7
    tourY[31] = 7
    tourX[32] = 5
    tourY[32] = 8
    tourX[33] = 6
    tourY[33] = 6
    tourX[34] = 8
    tourY[34] = 7
    tourX[35] = 7
    tourY[35] = 5
    tourX[36] = 5
    tourY[36] = 4
    tourX[37] = 3
    tourY[37] = 3
    tourX[38] = 4
    tourY[38] = 5
    tourX[39] = 6
    tourY[39] = 4
    tourX[40] = 5
    tourY[40] = 2
    tourX[41] = 3
    tourY[41] = 1
    tourX[42] = 1
    tourY[42] = 2
    tourX[43] = 2
    tourY[43] = 4
    tourX[44] = 4
    tourY[44] = 3
    tourX[45] = 5
    tourY[45] = 5
    tourX[46] = 3
    tourY[46] = 4
    tourX[47] = 4
    tourY[47] = 6
    tourX[48] = 6
    tourY[48] = 7
    tourX[49] = 8
    tourY[49] = 8
    tourX[50] = 7
    tourY[50] = 6
    tourX[51] = 8
    tourY[51] = 4
    tourX[52] = 6
    tourY[52] = 5
    tourX[53] = 4
    tourY[53] = 4
    tourX[54] = 2
    tourY[54] = 3
    tourX[55] = 1
    tourY[55] = 5
    tourX[56] = 2
    tourY[56] = 7
    tourX[57] = 4
    tourY[57] = 8
    tourX[58] = 3
    tourY[58] = 6
    tourX[59] = 2
    tourY[59] = 8
    tourX[60] = 1
    tourY[60] = 6
    tourX[61] = 3
    tourY[61] = 5
    tourX[62] = 4
    tourY[62] = 7
    tourX[63] = 6
    tourY[63] = 8
    tourX[64] = 5
    tourY[64] = 6

elsif tour_preset = 4
    # Center-start - validated 64-square Knight's Tour
    tourName$ = "Center-start"
    tourX[1] = 4
    tourY[1] = 4
    tourX[2] = 3
    tourY[2] = 2
    tourX[3] = 1
    tourY[3] = 1
    tourX[4] = 2
    tourY[4] = 3
    tourX[5] = 1
    tourY[5] = 5
    tourX[6] = 2
    tourY[6] = 7
    tourX[7] = 4
    tourY[7] = 8
    tourX[8] = 3
    tourY[8] = 6
    tourX[9] = 2
    tourY[9] = 8
    tourX[10] = 1
    tourY[10] = 6
    tourX[11] = 2
    tourY[11] = 4
    tourX[12] = 1
    tourY[12] = 2
    tourX[13] = 3
    tourY[13] = 1
    tourX[14] = 5
    tourY[14] = 2
    tourX[15] = 7
    tourY[15] = 1
    tourX[16] = 8
    tourY[16] = 3
    tourX[17] = 7
    tourY[17] = 5
    tourX[18] = 8
    tourY[18] = 7
    tourX[19] = 6
    tourY[19] = 8
    tourX[20] = 5
    tourY[20] = 6
    tourX[21] = 7
    tourY[21] = 7
    tourX[22] = 8
    tourY[22] = 5
    tourX[23] = 6
    tourY[23] = 4
    tourX[24] = 7
    tourY[24] = 2
    tourX[25] = 5
    tourY[25] = 1
    tourX[26] = 4
    tourY[26] = 3
    tourX[27] = 3
    tourY[27] = 5
    tourX[28] = 4
    tourY[28] = 7
    tourX[29] = 6
    tourY[29] = 6
    tourX[30] = 5
    tourY[30] = 8
    tourX[31] = 3
    tourY[31] = 7
    tourX[32] = 1
    tourY[32] = 8
    tourX[33] = 2
    tourY[33] = 6
    tourX[34] = 1
    tourY[34] = 4
    tourX[35] = 2
    tourY[35] = 2
    tourX[36] = 4
    tourY[36] = 1
    tourX[37] = 6
    tourY[37] = 2
    tourX[38] = 8
    tourY[38] = 1
    tourX[39] = 7
    tourY[39] = 3
    tourX[40] = 5
    tourY[40] = 4
    tourX[41] = 3
    tourY[41] = 3
    tourX[42] = 4
    tourY[42] = 5
    tourX[43] = 5
    tourY[43] = 7
    tourX[44] = 7
    tourY[44] = 8
    tourX[45] = 8
    tourY[45] = 6
    tourX[46] = 7
    tourY[46] = 4
    tourX[47] = 8
    tourY[47] = 2
    tourX[48] = 6
    tourY[48] = 1
    tourX[49] = 5
    tourY[49] = 3
    tourX[50] = 6
    tourY[50] = 5
    tourX[51] = 8
    tourY[51] = 4
    tourX[52] = 6
    tourY[52] = 3
    tourX[53] = 4
    tourY[53] = 2
    tourX[54] = 2
    tourY[54] = 1
    tourX[55] = 1
    tourY[55] = 3
    tourX[56] = 3
    tourY[56] = 4
    tourX[57] = 5
    tourY[57] = 5
    tourX[58] = 7
    tourY[58] = 6
    tourX[59] = 8
    tourY[59] = 8
    tourX[60] = 6
    tourY[60] = 7
    tourX[61] = 4
    tourY[61] = 6
    tourX[62] = 2
    tourY[62] = 5
    tourX[63] = 1
    tourY[63] = 7
    tourX[64] = 3
    tourY[64] = 8

else
    # Side-switching - validated 64-square Knight's Tour
    tourName$ = "Side-switching"
    tourX[1] = 1
    tourY[1] = 1
    tourX[2] = 3
    tourY[2] = 2
    tourX[3] = 5
    tourY[3] = 1
    tourX[4] = 7
    tourY[4] = 2
    tourX[5] = 8
    tourY[5] = 4
    tourX[6] = 7
    tourY[6] = 6
    tourX[7] = 8
    tourY[7] = 8
    tourX[8] = 6
    tourY[8] = 7
    tourX[9] = 4
    tourY[9] = 8
    tourX[10] = 2
    tourY[10] = 7
    tourX[11] = 1
    tourY[11] = 5
    tourX[12] = 2
    tourY[12] = 3
    tourX[13] = 3
    tourY[13] = 1
    tourX[14] = 1
    tourY[14] = 2
    tourX[15] = 2
    tourY[15] = 4
    tourX[16] = 1
    tourY[16] = 6
    tourX[17] = 2
    tourY[17] = 8
    tourX[18] = 3
    tourY[18] = 6
    tourX[19] = 1
    tourY[19] = 7
    tourX[20] = 3
    tourY[20] = 8
    tourX[21] = 5
    tourY[21] = 7
    tourX[22] = 7
    tourY[22] = 8
    tourX[23] = 8
    tourY[23] = 6
    tourX[24] = 6
    tourY[24] = 5
    tourX[25] = 7
    tourY[25] = 7
    tourX[26] = 8
    tourY[26] = 5
    tourX[27] = 7
    tourY[27] = 3
    tourX[28] = 8
    tourY[28] = 1
    tourX[29] = 6
    tourY[29] = 2
    tourX[30] = 4
    tourY[30] = 1
    tourX[31] = 2
    tourY[31] = 2
    tourX[32] = 1
    tourY[32] = 4
    tourX[33] = 2
    tourY[33] = 6
    tourX[34] = 1
    tourY[34] = 8
    tourX[35] = 3
    tourY[35] = 7
    tourX[36] = 5
    tourY[36] = 8
    tourX[37] = 4
    tourY[37] = 6
    tourX[38] = 2
    tourY[38] = 5
    tourX[39] = 1
    tourY[39] = 3
    tourX[40] = 2
    tourY[40] = 1
    tourX[41] = 3
    tourY[41] = 3
    tourX[42] = 5
    tourY[42] = 2
    tourX[43] = 4
    tourY[43] = 4
    tourX[44] = 5
    tourY[44] = 6
    tourX[45] = 6
    tourY[45] = 8
    tourX[46] = 8
    tourY[46] = 7
    tourX[47] = 7
    tourY[47] = 5
    tourX[48] = 8
    tourY[48] = 3
    tourX[49] = 7
    tourY[49] = 1
    tourX[50] = 6
    tourY[50] = 3
    tourX[51] = 8
    tourY[51] = 2
    tourX[52] = 6
    tourY[52] = 1
    tourX[53] = 4
    tourY[53] = 2
    tourX[54] = 5
    tourY[54] = 4
    tourX[55] = 3
    tourY[55] = 5
    tourX[56] = 4
    tourY[56] = 7
    tourX[57] = 6
    tourY[57] = 6
    tourX[58] = 4
    tourY[58] = 5
    tourX[59] = 6
    tourY[59] = 4
    tourX[60] = 4
    tourY[60] = 3
    tourX[61] = 5
    tourY[61] = 5
    tourX[62] = 3
    tourY[62] = 4
    tourX[63] = 5
    tourY[63] = 3
    tourX[64] = 7
    tourY[64] = 4
endif

# ============================================================
# TOUR INTEGRITY CHECK
# ============================================================

# Every preset must contain each board square exactly once and
# every consecutive pair must be a legal knight move.
for i from 1 to 64
    visitedSquare[i] = 0
endfor

for k from 1 to 64
    if tourX[k] < 1 or tourX[k] > 8 or tourY[k] < 1 or tourY[k] > 8
        exitScript: "Internal tour error: coordinate outside 1..8 at step " + string$(k) + "."
    endif

    squareIndex = (tourY[k] - 1) * 8 + tourX[k]
    if visitedSquare[squareIndex] = 1
        exitScript: "Internal tour error: repeated square at step " + string$(k) + "."
    endif
    visitedSquare[squareIndex] = 1

    if k > 1
        dx = abs(tourX[k] - tourX[k - 1])
        dy = abs(tourY[k] - tourY[k - 1])
        if not ((dx = 1 and dy = 2) or (dx = 2 and dy = 1))
            exitScript: "Internal tour error: illegal knight move into step " + string$(k) + "."
        endif
    endif
endfor

# ============================================================
# COMPUTE MAPPINGS
# ============================================================

segmentDur = duration / 64

for k from 1 to 64
    # Map X (1-8) to stereo position
    rawStereo = (tourX[k] - 1) / 7
    stereoVal[k] = stereo_min + rawStereo * (stereo_max - stereo_min)
    
    # Map Y (1-8) to intensity
    rawIntensity = (tourY[k] - 1) / 7
    intensityVal[k] = intensity_min + rawIntensity * (intensity_max - intensity_min)
    
    # Segment boundaries on the sample grid (no duplicated or dropped samples)
    sampleStart[k] = round((k - 1) * nSamples / 64)
    sampleEnd[k] = round(k * nSamples / 64)
    
    # Time position
    timePos[k] = sampleStart[k] * dt
    
    # Combined per-channel gain: intensity x constant-power pan
    panAngle = stereoVal[k] * (pi / 2)
    gainL[k] = intensityVal[k] * cos(panAngle)
    gainR[k] = intensityVal[k] * sin(panAngle)
endfor

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Knight's Tour Sonification v0.4"
writeInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Tour pattern: ", tourName$
appendInfoLine: "Effect: ", effectName$
appendInfoLine: "Intensity range: ", fixed$(intensity_min, 2), " - ", fixed$(intensity_max, 2)
appendInfoLine: "Stereo range: ", fixed$(stereo_min, 2), " - ", fixed$(stereo_max, 2)
appendInfoLine: "Segment duration: ", fixed$(segmentDur * 1000, 1), " ms"
if declick_ramp > 0
    appendInfoLine: "De-click ramp: ", fixed$(declick_ramp, 1), " ms (raised cosine at each join)"
else
    appendInfoLine: "De-click ramp: off (hard gain steps - expect clicks)"
endif
appendInfoLine: "--------------------------------------------"
if visualization_mode = 1
    appendInfoLine: "Visualization: Off (fastest)"
elsif visualization_mode = 2
    appendInfoLine: "Visualization: Final only"
elsif visualization_mode = 3
    appendInfoLine: "Visualization: Real-time (visual)"
else
    appendInfoLine: "Visualization: Step-by-step with audio"
endif
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# PROCESS ALL SEGMENTS
# ============================================================

appendInfoLine: "Processing 64 segments..."

for k from 1 to 64
    # === Real-time visualization ===
    if showRealtime
        @drawVisualization: k, 0
    endif
    
    # Progress indicator (only if no realtime viz)
    if not showRealtime
        if k mod 8 = 0
            appendInfoLine: "  Step ", k, "/64"
        endif
    endif
    
    # Extract segment on the sample grid.
    # These boundaries fall midway between sample centres (Praat's x1 = xmin + 0.5*dx),
    # so Extract part returns exactly sampleEnd - sampleStart samples.
    startTime = xminMono + sampleStart[k] * dt
    endTime = xminMono + sampleEnd[k] * dt
    
    selectObject: monoSound
    segmentMono = Extract part: startTime, endTime, "rectangular", 1, "no"
    
    # === De-click: ramp the gain in from the previous segment's value ===
    # A hard step in gain at the join is a step in the waveform, i.e. a click.
    # The raised cosine is C1-continuous, so neither the gain nor its slope jumps.
    if k = 1
        prevL = gainL[1]
        prevR = gainR[1]
    else
        prevL = gainL[k - 1]
        prevR = gainR[k - 1]
    endif
    
    segLen = (sampleEnd[k] - sampleStart[k]) * dt
    rampSec = declick_ramp / 1000
    if rampSec > segLen * 0.4
        rampSec = segLen * 0.4
    endif
    
    if rampSec <= 0 or (prevL = gainL[k] and prevR = gainR[k])
        leftFormula$ = "self * " + fixed$(gainL[k], 10)
        rightFormula$ = "self * " + fixed$(gainR[k], 10)
    else
        rampStr$ = fixed$(rampSec, 10)
        shape$ = " * (0.5 - 0.5 * cos(pi * x / " + rampStr$ + "))"
        leftFormula$ = "self * (if x < " + rampStr$ + " then " + fixed$(prevL, 10)
            ... + " + " + fixed$(gainL[k] - prevL, 10) + shape$
            ... + " else " + fixed$(gainL[k], 10) + " fi)"
        rightFormula$ = "self * (if x < " + rampStr$ + " then " + fixed$(prevR, 10)
            ... + " + " + fixed$(gainR[k] - prevR, 10) + shape$
            ... + " else " + fixed$(gainR[k], 10) + " fi)"
    endif
    
    # Create left channel
    selectObject: segmentMono
    leftChannel = Copy: "L_" + string$(k)
    selectObject: leftChannel
    Formula: leftFormula$
    
    # Create right channel
    selectObject: segmentMono
    rightChannel = Copy: "R_" + string$(k)
    selectObject: rightChannel
    Formula: rightFormula$
    
    # Combine to stereo
    selectObject: leftChannel
    plusObject: rightChannel
    stereoSegment = Combine to stereo
    
    # Store for later concatenation
    segment[k] = stereoSegment
    
    # Clean up intermediate objects
    removeObject: segmentMono, leftChannel, rightChannel
    
    # Play segment if step-by-step mode
    if playEachSegment
        selectObject: stereoSegment
        Play
    endif
    
    # Pause for visualization (only in realtime modes)
    if showRealtime
        if not playEachSegment
            # Only add delay if not playing (playing already takes time)
            sleep: visualization_delay
        endif
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Concatenating segments..."

# ============================================================
# CONCATENATE ALL SEGMENTS AT ONCE
# ============================================================

selectObject: segment[1]
for k from 2 to 64
    plusObject: segment[k]
endfor

result = Concatenate
selectObject: result
Rename: originalName$ + "_KnightsTour_" + tourName$

# Clean up all segment objects
for k from 1 to 64
    removeObject: segment[k]
endfor

# Clean up mono if we created it
if createdMono
    removeObject: monoSound
endif

# ============================================================
# FINAL VISUALIZATION
# ============================================================

if showFinal
    @drawVisualization: 64, 1
endif

# ============================================================
# PROCEDURE: VISUALIZATION
# ============================================================

procedure drawVisualization: .step, .isFinal
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    if .isFinal
        Text: 0.5, "centre", 0.5, "half", "Knight's Tour: " + tourName$ + " - COMPLETE"
    else
        Text: 0.5, "centre", 0.5, "half", "Knight's Tour: " + tourName$ + " - Step " + string$(.step) + "/64"
    endif
    
    # === PANEL A: Chess Board ===
    Select outer viewport: 0, 4, 0.6, 4.2
    Select inner viewport: 0.4, 3.8, 0.8, 4.0
    
    Axes: 0.5, 8.5, 0.5, 8.5
    
    # Draw checkerboard pattern
    for row from 1 to 8
        for col from 1 to 8
            if (row + col) mod 2 = 0
                Paint rectangle: "{0.85, 0.85, 0.85}", col - 0.5, col + 0.5, row - 0.5, row + 0.5
            else
                Paint rectangle: "{0.95, 0.95, 0.95}", col - 0.5, col + 0.5, row - 0.5, row + 0.5
            endif
        endfor
    endfor
    
    # Draw grid lines
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    for i from 0 to 8
        Draw line: 0.5, i + 0.5, 8.5, i + 0.5
        Draw line: i + 0.5, 0.5, i + 0.5, 8.5
    endfor
    
    # Draw path (completed segments)
    Colour: "{0.3, 0.5, 0.7}"
    Line width: 2
    for j from 1 to .step - 1
        Draw line: tourX[j], tourY[j], tourX[j+1], tourY[j+1]
    endfor
    
    # Draw visited squares
    Font size: 7
    for j from 1 to .step
        if j = 1
            # Start position - green
            Paint circle (mm): "{0.3, 0.7, 0.3}", tourX[j], tourY[j], 3
            Colour: "White"
        elsif j = .step and not .isFinal
            # Current position - red
            Paint circle (mm): "{0.8, 0.3, 0.3}", tourX[j], tourY[j], 3.5
            Colour: "White"
        elsif j = 64 and .isFinal
            # End position - blue
            Paint circle (mm): "{0.3, 0.3, 0.8}", tourX[j], tourY[j], 3
            Colour: "White"
        else
            # Visited - gray
            Paint circle (mm): "{0.5, 0.5, 0.5}", tourX[j], tourY[j], 2.5
            Colour: "White"
        endif
        Text: tourX[j], "centre", tourY[j], "half", string$(j)
    endfor
    
    # Border
    Colour: "Black"
    Line width: 1
    Draw rectangle: 0.5, 8.5, 0.5, 8.5
    
    # Axis labels
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text bottom: "yes", "X → Stereo"
    Select outer viewport: 0.08, 0.52, 0.6, 4.2
    Select inner viewport: 0.08, 0.52, 0.62, 4.18
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Y → Intensity"
    Select outer viewport: 0, 4, 0.6, 4.2
    Select inner viewport: 0.4, 3.8, 0.8, 4
    Axes: 0.5, 8.5, 0.5, 8.5
    
    # === PANEL B: Parameter Curves ===
    Select outer viewport: 4, 8, 0.6, 4.2
    Select inner viewport: 4.4, 7.8, 0.8, 4.0
    
    Axes: 0, duration, -0.1, 1.1
    
    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -0.1, 1.1
    
    # Reference lines
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    Draw line: 0, 0, duration, 0
    Draw line: 0, 0.5, duration, 0.5
    Draw line: 0, 1, duration, 1
    
    # Range indicators
    Colour: "{0.9, 0.8, 0.8}"
    Paint rectangle: "{0.95, 0.9, 0.9}", 0, duration, intensity_min, intensity_max
    Colour: "{0.8, 0.8, 0.9}"
    Paint rectangle: "{0.9, 0.9, 0.95}", 0, duration, stereo_min, stereo_max
    
    # Draw stereo curve
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    for j from 1 to .step - 1
        Draw line: timePos[j], stereoVal[j], timePos[j+1], stereoVal[j+1]
    endfor
    
    # Draw intensity curve
    Colour: "{0.3, 0.3, 0.8}"
    Line width: 2
    for j from 1 to .step - 1
        Draw line: timePos[j], intensityVal[j], timePos[j+1], intensityVal[j+1]
    endfor
    
    # Draw points
    for j from 1 to .step
        if j = .step and not .isFinal
            Paint circle (mm): "{0.8, 0.3, 0.3}", timePos[j], stereoVal[j], 2
            Paint circle (mm): "{0.3, 0.3, 0.8}", timePos[j], intensityVal[j], 2
        else
            Paint circle (mm): "{0.8, 0.3, 0.3}", timePos[j], stereoVal[j], 1
            Paint circle (mm): "{0.3, 0.3, 0.8}", timePos[j], intensityVal[j], 1
        endif
    endfor
    
    # Current time marker
    if not .isFinal
        Colour: "{0.3, 0.3, 0.3}"
        Line width: 1
        Dotted line
        Draw line: timePos[.step], -0.1, timePos[.step], 1.1
        Solid line
    endif
    
    # Border and labels
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 4.02, 4.4, 0.6, 4.2
    Select inner viewport: 4.02, 4.4, 0.62, 4.18
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Value"
    Select outer viewport: 4, 8, 0.6, 4.2
    Select inner viewport: 4.4, 7.8, 0.8, 4
    Axes: 0, duration, -0.1, 1.1
    
    # Legend
    Font size: 7
    Colour: "{0.8, 0.3, 0.3}"
    Text: duration * 0.95, "right", 1.05, "half", "Stereo"
    Colour: "{0.3, 0.3, 0.8}"
    Text: duration * 0.95, "right", 0.95, "half", "Intensity"
    
    # === SUMMARY / STEP STATUS ===
    Select outer viewport: 0, 8, 4.35, 5.15
    Select inner viewport: 0.60, 7.70, 4.42, 5.08
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    if .isFinal
        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.76, "half", "##Summary##"
        Font size: 6
        Colour: "{0.35, 0.35, 0.50}"
        Text: 0.02, "left", 0.46, "half", originalName$ + " | " + tourName$ + " | duration " + fixed$(duration, 2) + " s"
        Text: 0.02, "left", 0.18, "half", "Intensity " + fixed$(intensity_min, 2) + "-" + fixed$(intensity_max, 2) + " | Stereo " + fixed$(stereo_min, 2) + "-" + fixed$(stereo_max, 2) + " | 64-square tour"
    else
        currentStereo = stereoVal[.step]
        currentIntensity = intensityVal[.step]
        Font size: 6
        Colour: "{0.35, 0.35, 0.50}"
        Text: 0.02, "left", 0.62, "half", "##Step " + string$(.step) + "/64##  X=" + string$(tourX[.step]) + "  Y=" + string$(tourY[.step])
        Text: 0.02, "left", 0.28, "half", "Stereo=" + fixed$(currentStereo, 2) + " | Intensity=" + fixed$(currentIntensity, 2)
    endif
    Select inner viewport: 0.60, 7.70, 4.42, 5.08
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0, 8, 0, 5.25
    Font size: 10
    Colour: "Black"
endproc

# ============================================================
# FINAL OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PROCESSING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Tour: ", tourName$
appendInfoLine: "Effect: ", effectName$
appendInfoLine: ""
appendInfoLine: "Mapping:"
appendInfoLine: "  X (1-8) → Stereo [", fixed$(stereo_min, 2), " - ", fixed$(stereo_max, 2), "]"
appendInfoLine: "  Y (1-8) → Intensity [", fixed$(intensity_min, 2), " - ", fixed$(intensity_max, 2), "]"

# ============================================================
# PLAY RESULT
# ============================================================

if play_result
    selectObject: result
    Play
endif

selectObject: result
