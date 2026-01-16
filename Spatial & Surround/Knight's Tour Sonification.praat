# ============================================================
# Praat AudioTools - Knight's Tour Sonification.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
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
# Changelog v0.2:
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
        option Spiral Pattern
        option Diagonal Heavy
        option Center-Out
        option Alternating Sides
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

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

# Clamp and validate ranges
if intensity_min < 0
    intensity_min = 0
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

# ============================================================
# KNIGHT'S TOUR PATTERNS
# ============================================================

# Initialize arrays
for i from 1 to 64
    tourX[i] = 0
    tourY[i] = 0
endfor

# Load selected tour pattern
if tour_preset = 1
    # Warnsdorff (Classic)
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
    tourX[9] = 8
    tourY[9] = 4
    tourX[10] = 7
    tourY[10] = 2
    tourX[11] = 5
    tourY[11] = 1
    tourX[12] = 3
    tourY[12] = 2
    tourX[13] = 1
    tourY[13] = 3
    tourX[14] = 2
    tourY[14] = 5
    tourX[15] = 1
    tourY[15] = 7
    tourX[16] = 3
    tourY[16] = 8
    tourX[17] = 5
    tourY[17] = 7
    tourX[18] = 7
    tourY[18] = 8
    tourX[19] = 8
    tourY[19] = 6
    tourX[20] = 7
    tourY[20] = 4
    tourX[21] = 8
    tourY[21] = 2
    tourX[22] = 6
    tourY[22] = 1
    tourX[23] = 4
    tourY[23] = 2
    tourX[24] = 2
    tourY[24] = 1
    tourX[25] = 1
    tourY[25] = 2
    tourX[26] = 3
    tourY[26] = 1
    tourX[27] = 5
    tourY[27] = 2
    tourX[28] = 7
    tourY[28] = 1
    tourX[29] = 8
    tourY[29] = 3
    tourX[30] = 6
    tourY[30] = 4
    tourX[31] = 8
    tourY[31] = 5
    tourX[32] = 7
    tourY[32] = 7
    tourX[33] = 5
    tourY[33] = 8
    tourX[34] = 3
    tourY[34] = 7
    tourX[35] = 1
    tourY[35] = 8
    tourX[36] = 2
    tourY[36] = 6
    tourX[37] = 4
    tourY[37] = 7
    tourX[38] = 6
    tourY[38] = 8
    tourX[39] = 8
    tourY[39] = 7
    tourX[40] = 7
    tourY[40] = 5
    tourX[41] = 5
    tourY[41] = 6
    tourX[42] = 3
    tourY[42] = 5
    tourX[43] = 1
    tourY[43] = 6
    tourX[44] = 2
    tourY[44] = 8
    tourX[45] = 4
    tourY[45] = 6
    tourX[46] = 6
    tourY[46] = 5
    tourX[47] = 8
    tourY[47] = 6
    tourX[48] = 7
    tourY[48] = 8
    tourX[49] = 5
    tourY[49] = 7
    tourX[50] = 3
    tourY[50] = 8
    tourX[51] = 1
    tourY[51] = 7
    tourX[52] = 2
    tourY[52] = 5
    tourX[53] = 4
    tourY[53] = 4
    tourX[54] = 6
    tourY[54] = 3
    tourX[55] = 8
    tourY[55] = 4
    tourX[56] = 7
    tourY[56] = 6
    tourX[57] = 5
    tourY[57] = 5
    tourX[58] = 3
    tourY[58] = 6
    tourX[59] = 1
    tourY[59] = 5
    tourX[60] = 2
    tourY[60] = 7
    tourX[61] = 4
    tourY[61] = 8
    tourX[62] = 6
    tourY[62] = 7
    tourX[63] = 8
    tourY[63] = 8
    tourX[64] = 7
    tourY[64] = 7

elsif tour_preset = 2
    # Spiral Pattern
    tourName$ = "Spiral"
    tourX[1] = 4
    tourY[1] = 4
    tourX[2] = 6
    tourY[2] = 5
    tourX[3] = 7
    tourY[3] = 7
    tourX[4] = 5
    tourY[4] = 8
    tourX[5] = 3
    tourY[5] = 7
    tourX[6] = 1
    tourY[6] = 8
    tourX[7] = 2
    tourY[7] = 6
    tourX[8] = 1
    tourY[8] = 4
    tourX[9] = 2
    tourY[9] = 2
    tourX[10] = 4
    tourY[10] = 1
    tourX[11] = 6
    tourY[11] = 2
    tourX[12] = 8
    tourY[12] = 1
    tourX[13] = 7
    tourY[13] = 3
    tourX[14] = 8
    tourY[14] = 5
    tourX[15] = 7
    tourY[15] = 7
    tourX[16] = 5
    tourY[16] = 6
    tourX[17] = 3
    tourY[17] = 5
    tourX[18] = 1
    tourY[18] = 6
    tourX[19] = 2
    tourY[19] = 4
    tourX[20] = 4
    tourY[20] = 3
    tourX[21] = 6
    tourY[21] = 4
    tourX[22] = 8
    tourY[22] = 3
    tourX[23] = 7
    tourY[23] = 5
    tourX[24] = 5
    tourY[24] = 4
    tourX[25] = 3
    tourY[25] = 3
    tourX[26] = 1
    tourY[26] = 2
    tourX[27] = 3
    tourY[27] = 1
    tourX[28] = 5
    tourY[28] = 2
    tourX[29] = 7
    tourY[29] = 1
    tourX[30] = 8
    tourY[30] = 3
    tourX[31] = 6
    tourY[31] = 4
    tourX[32] = 4
    tourY[32] = 5
    tourX[33] = 2
    tourY[33] = 4
    tourX[34] = 1
    tourY[34] = 6
    tourX[35] = 3
    tourY[35] = 7
    tourX[36] = 5
    tourY[36] = 8
    tourX[37] = 7
    tourY[37] = 7
    tourX[38] = 8
    tourY[38] = 5
    tourX[39] = 6
    tourY[39] = 6
    tourX[40] = 4
    tourY[40] = 7
    tourX[41] = 2
    tourY[41] = 8
    tourX[42] = 1
    tourY[42] = 6
    tourX[43] = 3
    tourY[43] = 5
    tourX[44] = 5
    tourY[44] = 6
    tourX[45] = 7
    tourY[45] = 5
    tourX[46] = 8
    tourY[46] = 7
    tourX[47] = 6
    tourY[47] = 8
    tourX[48] = 4
    tourY[48] = 7
    tourX[49] = 2
    tourY[49] = 6
    tourX[50] = 1
    tourY[50] = 4
    tourX[51] = 3
    tourY[51] = 3
    tourX[52] = 5
    tourY[52] = 4
    tourX[53] = 7
    tourY[53] = 3
    tourX[54] = 8
    tourY[54] = 1
    tourX[55] = 6
    tourY[55] = 2
    tourX[56] = 4
    tourY[56] = 3
    tourX[57] = 2
    tourY[57] = 2
    tourX[58] = 1
    tourY[58] = 4
    tourX[59] = 3
    tourY[59] = 5
    tourX[60] = 5
    tourY[60] = 4
    tourX[61] = 7
    tourY[61] = 5
    tourX[62] = 8
    tourY[62] = 7
    tourX[63] = 6
    tourY[63] = 6
    tourX[64] = 4
    tourY[64] = 5

elsif tour_preset = 3
    # Diagonal Heavy
    tourName$ = "Diagonal"
    tourX[1] = 1
    tourY[1] = 1
    tourX[2] = 3
    tourY[2] = 2
    tourX[3] = 5
    tourY[3] = 3
    tourX[4] = 7
    tourY[4] = 4
    tourX[5] = 8
    tourY[5] = 6
    tourX[6] = 6
    tourY[6] = 7
    tourX[7] = 4
    tourY[7] = 8
    tourX[8] = 2
    tourY[8] = 7
    tourX[9] = 1
    tourY[9] = 5
    tourX[10] = 2
    tourY[10] = 3
    tourX[11] = 4
    tourY[11] = 2
    tourX[12] = 6
    tourY[12] = 1
    tourX[13] = 8
    tourY[13] = 2
    tourX[14] = 7
    tourY[14] = 4
    tourX[15] = 5
    tourY[15] = 5
    tourX[16] = 3
    tourY[16] = 6
    tourX[17] = 1
    tourY[17] = 7
    tourX[18] = 2
    tourY[18] = 5
    tourX[19] = 4
    tourY[19] = 4
    tourX[20] = 6
    tourY[20] = 3
    tourX[21] = 8
    tourY[21] = 4
    tourX[22] = 7
    tourY[22] = 6
    tourX[23] = 5
    tourY[23] = 7
    tourX[24] = 3
    tourY[24] = 8
    tourX[25] = 1
    tourY[25] = 7
    tourX[26] = 2
    tourY[26] = 5
    tourX[27] = 4
    tourY[27] = 6
    tourX[28] = 6
    tourY[28] = 5
    tourX[29] = 8
    tourY[29] = 6
    tourX[30] = 7
    tourY[30] = 8
    tourX[31] = 5
    tourY[31] = 7
    tourX[32] = 3
    tourY[32] = 6
    tourX[33] = 1
    tourY[33] = 5
    tourX[34] = 2
    tourY[34] = 3
    tourX[35] = 4
    tourY[35] = 4
    tourX[36] = 6
    tourY[36] = 5
    tourX[37] = 8
    tourY[37] = 4
    tourX[38] = 7
    tourY[38] = 2
    tourX[39] = 5
    tourY[39] = 1
    tourX[40] = 3
    tourY[40] = 2
    tourX[41] = 1
    tourY[41] = 3
    tourX[42] = 2
    tourY[42] = 5
    tourX[43] = 4
    tourY[43] = 6
    tourX[44] = 6
    tourY[44] = 7
    tourX[45] = 8
    tourY[45] = 8
    tourX[46] = 7
    tourY[46] = 6
    tourX[47] = 5
    tourY[47] = 5
    tourX[48] = 3
    tourY[48] = 4
    tourX[49] = 1
    tourY[49] = 3
    tourX[50] = 2
    tourY[50] = 1
    tourX[51] = 4
    tourY[51] = 2
    tourX[52] = 6
    tourY[52] = 3
    tourX[53] = 8
    tourY[53] = 2
    tourX[54] = 7
    tourY[54] = 4
    tourX[55] = 5
    tourY[55] = 3
    tourX[56] = 3
    tourY[56] = 4
    tourX[57] = 1
    tourY[57] = 5
    tourX[58] = 2
    tourY[58] = 7
    tourX[59] = 4
    tourY[59] = 8
    tourX[60] = 6
    tourY[60] = 7
    tourX[61] = 8
    tourY[61] = 8
    tourX[62] = 7
    tourY[62] = 6
    tourX[63] = 5
    tourY[63] = 5
    tourX[64] = 3
    tourY[64] = 6

elsif tour_preset = 4
    # Center-Out
    tourName$ = "Center-Out"
    tourX[1] = 4
    tourY[1] = 4
    tourX[2] = 6
    tourY[2] = 5
    tourX[3] = 8
    tourY[3] = 4
    tourX[4] = 7
    tourY[4] = 6
    tourX[5] = 5
    tourY[5] = 7
    tourX[6] = 3
    tourY[6] = 8
    tourX[7] = 1
    tourY[7] = 7
    tourX[8] = 2
    tourY[8] = 5
    tourX[9] = 1
    tourY[9] = 3
    tourX[10] = 3
    tourY[10] = 2
    tourX[11] = 5
    tourY[11] = 1
    tourX[12] = 7
    tourY[12] = 2
    tourX[13] = 8
    tourY[13] = 4
    tourX[14] = 6
    tourY[14] = 5
    tourX[15] = 4
    tourY[15] = 6
    tourX[16] = 2
    tourY[16] = 7
    tourX[17] = 1
    tourY[17] = 5
    tourX[18] = 2
    tourY[18] = 3
    tourX[19] = 4
    tourY[19] = 2
    tourX[20] = 6
    tourY[20] = 1
    tourX[21] = 8
    tourY[21] = 2
    tourX[22] = 7
    tourY[22] = 4
    tourX[23] = 5
    tourY[23] = 5
    tourX[24] = 3
    tourY[24] = 6
    tourX[25] = 1
    tourY[25] = 7
    tourX[26] = 2
    tourY[26] = 5
    tourX[27] = 4
    tourY[27] = 4
    tourX[28] = 6
    tourY[28] = 3
    tourX[29] = 8
    tourY[29] = 4
    tourX[30] = 7
    tourY[30] = 6
    tourX[31] = 5
    tourY[31] = 7
    tourX[32] = 3
    tourY[32] = 8
    tourX[33] = 1
    tourY[33] = 7
    tourX[34] = 2
    tourY[34] = 5
    tourX[35] = 4
    tourY[35] = 6
    tourX[36] = 6
    tourY[36] = 7
    tourX[37] = 8
    tourY[37] = 8
    tourX[38] = 7
    tourY[38] = 6
    tourX[39] = 5
    tourY[39] = 5
    tourX[40] = 3
    tourY[40] = 4
    tourX[41] = 1
    tourY[41] = 3
    tourX[42] = 2
    tourY[42] = 1
    tourX[43] = 4
    tourY[43] = 2
    tourX[44] = 6
    tourY[44] = 3
    tourX[45] = 8
    tourY[45] = 2
    tourX[46] = 7
    tourY[46] = 4
    tourX[47] = 5
    tourY[47] = 3
    tourX[48] = 3
    tourY[48] = 2
    tourX[49] = 1
    tourY[49] = 1
    tourX[50] = 2
    tourY[50] = 3
    tourX[51] = 4
    tourY[51] = 4
    tourX[52] = 6
    tourY[52] = 5
    tourX[53] = 8
    tourY[53] = 6
    tourX[54] = 7
    tourY[54] = 8
    tourX[55] = 5
    tourY[55] = 7
    tourX[56] = 3
    tourY[56] = 6
    tourX[57] = 1
    tourY[57] = 5
    tourX[58] = 2
    tourY[58] = 7
    tourX[59] = 4
    tourY[59] = 8
    tourX[60] = 6
    tourY[60] = 7
    tourX[61] = 8
    tourY[61] = 8
    tourX[62] = 7
    tourY[62] = 6
    tourX[63] = 5
    tourY[63] = 5
    tourX[64] = 4
    tourY[64] = 4

else
    # Alternating Sides
    tourName$ = "Alternating"
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
    tourX[6] = 6
    tourY[6] = 5
    tourX[7] = 8
    tourY[7] = 6
    tourX[8] = 7
    tourY[8] = 8
    tourX[9] = 5
    tourY[9] = 7
    tourX[10] = 3
    tourY[10] = 8
    tourX[11] = 1
    tourY[11] = 7
    tourX[12] = 2
    tourY[12] = 5
    tourX[13] = 1
    tourY[13] = 3
    tourX[14] = 2
    tourY[14] = 1
    tourX[15] = 4
    tourY[15] = 2
    tourX[16] = 6
    tourY[16] = 1
    tourX[17] = 8
    tourY[17] = 2
    tourX[18] = 7
    tourY[18] = 4
    tourX[19] = 8
    tourY[19] = 6
    tourX[20] = 6
    tourY[20] = 7
    tourX[21] = 4
    tourY[21] = 8
    tourX[22] = 2
    tourY[22] = 7
    tourX[23] = 1
    tourY[23] = 5
    tourX[24] = 2
    tourY[24] = 3
    tourX[25] = 4
    tourY[25] = 4
    tourX[26] = 6
    tourY[26] = 3
    tourX[27] = 8
    tourY[27] = 4
    tourX[28] = 7
    tourY[28] = 6
    tourX[29] = 5
    tourY[29] = 5
    tourX[30] = 3
    tourY[30] = 6
    tourX[31] = 1
    tourY[31] = 7
    tourX[32] = 2
    tourY[32] = 5
    tourX[33] = 4
    tourY[33] = 6
    tourX[34] = 6
    tourY[34] = 5
    tourX[35] = 8
    tourY[35] = 6
    tourX[36] = 7
    tourY[36] = 8
    tourX[37] = 5
    tourY[37] = 7
    tourX[38] = 3
    tourY[38] = 8
    tourX[39] = 1
    tourY[39] = 7
    tourX[40] = 2
    tourY[40] = 5
    tourX[41] = 1
    tourY[41] = 3
    tourX[42] = 3
    tourY[42] = 2
    tourX[43] = 5
    tourY[43] = 3
    tourX[44] = 7
    tourY[44] = 2
    tourX[45] = 8
    tourY[45] = 4
    tourX[46] = 6
    tourY[46] = 5
    tourX[47] = 4
    tourY[47] = 4
    tourX[48] = 2
    tourY[48] = 3
    tourX[49] = 1
    tourY[49] = 1
    tourX[50] = 3
    tourY[50] = 2
    tourX[51] = 5
    tourY[51] = 1
    tourX[52] = 7
    tourY[52] = 2
    tourX[53] = 8
    tourY[53] = 4
    tourX[54] = 6
    tourY[54] = 3
    tourX[55] = 4
    tourY[55] = 2
    tourX[56] = 2
    tourY[56] = 1
    tourX[57] = 1
    tourY[57] = 3
    tourX[58] = 3
    tourY[58] = 4
    tourX[59] = 5
    tourY[59] = 5
    tourX[60] = 7
    tourY[60] = 6
    tourX[61] = 8
    tourY[61] = 8
    tourX[62] = 6
    tourY[62] = 7
    tourX[63] = 4
    tourY[63] = 6
    tourX[64] = 2
    tourY[64] = 5
endif

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
    
    # Time position
    timePos[k] = (k - 1) * segmentDur
endfor

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
writeInfoLine: "Knight's Tour Sonification v0.2"
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
    
    # Extract segment
    startTime = timePos[k]
    endTime = startTime + segmentDur
    if endTime > duration
        endTime = duration
    endif
    
    selectObject: monoSound
    segmentMono = Extract part: startTime, endTime, "rectangular", 1, "no"
    
    # Apply intensity scaling
    intensityGain = intensityVal[k]
    intensityStr$ = fixed$(intensityGain, 10)
    
    selectObject: segmentMono
    Formula: "self * " + intensityStr$
    
    # Calculate constant-power panning gains
    panAngle = stereoVal[k] * (pi / 2)
    leftGain = cos(panAngle)
    rightGain = sin(panAngle)
    
    leftStr$ = fixed$(leftGain, 10)
    rightStr$ = fixed$(rightGain, 10)
    
    # Create left channel
    selectObject: segmentMono
    leftChannel = Copy: "L_" + string$(k)
    selectObject: leftChannel
    Formula: "self * " + leftStr$
    
    # Create right channel
    selectObject: segmentMono
    rightChannel = Copy: "R_" + string$(k)
    selectObject: rightChannel
    Formula: "self * " + rightStr$
    
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
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text bottom: "yes", "X → Stereo"
    Text left: "yes", "Y → Intensity"
    
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
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Value"
    
    # Legend
    Font size: 7
    Colour: "{0.8, 0.3, 0.3}"
    Text: duration * 0.95, "right", 1.05, "half", "Stereo"
    Colour: "{0.3, 0.3, 0.8}"
    Text: duration * 0.95, "right", 0.95, "half", "Intensity"
    
    # === Info bar ===
    Select outer viewport: 0, 8, 4.3, 4.7
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    if .isFinal
        Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + tourName$ + " | I:[" + fixed$(intensity_min, 2) + "-" + fixed$(intensity_max, 2) + "] S:[" + fixed$(stereo_min, 2) + "-" + fixed$(stereo_max, 2) + "]"
    else
        currentStereo = stereoVal[.step]
        currentIntensity = intensityVal[.step]
        Text: 0.5, "centre", 0.5, "half", "Step " + string$(.step) + ": X=" + string$(tourX[.step]) + " Y=" + string$(tourY[.step]) + " → Stereo=" + fixed$(currentStereo, 2) + " Intensity=" + fixed$(currentIntensity, 2)
    endif
    
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