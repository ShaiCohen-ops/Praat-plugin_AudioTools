# ============================================================
# Praat AudioTools - Hamasaki_Square_Ambience.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2025)
# v1.3.1 (2026): RUNTIME VISUAL QA - waveform/summary gap corrected; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Psychoacoustic approximation of a Hamasaki Square ambience
#   processor. Takes a mono or stereo input and produces a
#   4-channel output in the order:
#       Ch 1 — Left (L)
#       Ch 2 — Right (R)
#       Ch 3 — Left Surround (Ls)
#       Ch 4 — Right Surround (Rs)
#
#   This is a practical signal-processing approximation, not a
#   claim of physically accurate Hamasaki decoding. No external
#   tools, plug-ins, or binaries are required.
#
# Input:
#   One selected Sound object (mono or stereo). Any other
#   channel count causes a clean error exit.
#
# Output:
#   One 4-channel Sound object left in the Praat Objects list,
#   named  <original>_HamasakiSq
#   Optionally saved to disk as a WAV file.
#
# Processing summary:
#   STEREO input
#     Front L/R  → original stereo channels (preserved)
#     Rear Ls/Rs → channel-difference (L−R) signal, bandpass-
#                  filtered, delayed, decorrelated, and scaled
#
#   MONO input
#     Front L/R  → real ITD widening: L = original, R = delayed
#                  by mono_width_ms. Only delaying one channel
#                  creates a genuine inter-channel timing offset.
#                  Praat cannot advance a signal, only delay it,
#                  so ±half symmetry is not achievable natively.
#                  A mild spectral tilt is added for extra decorr.
#     Rear Ls/Rs → bandpass-filtered mono, symmetrically delayed,
#                  and spectrally decorrelated between channels
#
#   In both cases the rear channels are additionally:
#     - high-pass filtered to reduce LF buildup
#     - low-pass filtered to reduce directness / HF sharpness
#     - symmetrically delayed: Ls = rear_delay − half_offset
#                              Rs = rear_delay + half_offset
#     - spectrally decorrelated: Rs LP cutoff is slightly lower
#       than Ls, creating a smooth timbral difference that is
#       less abrupt than polarity inversion
#     - gain-scaled by rear_level_dB
#     - optionally blended with mid signal (L+R) to ensure
#       audible rears even when side energy is low
#
#   Final output is peak-normalised with headroom_dB of clearance.
#
# Changelog v1.3:
#   - Fixed mono front widening: L=original, R=delayed by full
#     mono_width_ms, creating a real ITD (v1.1 delayed both
#     channels equally, producing zero net timing difference)
#   - Spectral tilt cutoffs for mono fronts raised to 18k/15k Hz
#     (v1.1 tied them to rear_lowpass_Hz, which was incorrect)
#   - Updated header to accurately describe the mono path
# ============================================================

# ============================================================
# FORM
# ============================================================

form Hamasaki Square Ambience
    comment === PRESET ===
    optionmenu Preset: 1
        option Custom
        option Subtle (−6 dB rear, 20 ms delay)
        option Natural (−9 dB rear, 30 ms delay)
        option Spacious (−6 dB rear, 45 ms delay)
        option Cinematic (−3 dB rear, 60 ms delay)
        option Wide Mono (for mono sources, light widening)

    comment === REAR CHANNEL LEVEL ===
    real Rear_level_dB -9.0
    comment (dB relative to front; typically -12 to -3)

    comment === REAR DELAY ===
    positive Rear_delay_ms 30.0
    comment (Hamasaki-style delay for rears; typically 20–80 ms)

    comment === DECORRELATION OFFSET ===
    positive Decorr_offset_ms 7.0
    comment (Extra offset between Ls and Rs; 5–15 ms typical)

    comment === MONO FRONT WIDENING ===
    positive Mono_width_ms 0.35
    comment (Micro-delay for L vs R when input is mono; 0.1–1 ms)

    comment === REAR MID BLEND ===
    real Rear_mid_blend_dB -12.0
    comment (Blends mid/sum signal into rears; useful when side energy is low)
    comment (Set to -100 to disable; typically -18 to -6 dB)

    comment === REAR BANDPASS ===
    positive Rear_highpass_Hz 120.0
    comment (High-pass cutoff for rear channels; removes LF)
    positive Rear_lowpass_Hz 6000.0
    comment (Low-pass cutoff for rear channels; softens HF)

    comment === OUTPUT ===
    real Headroom_dB -1.0
    comment (Peak ceiling in dBFS; e.g. -1.0)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# APPLY PRESETS (override form values when not Custom)
# ============================================================

if preset = 2
    # Subtle
    rear_level_dB     = -6.0
    rear_delay_ms     = 20.0
    decorr_offset_ms  = 5.0
    mono_width_ms     = 0.25
    rear_highpass_Hz  = 100.0
    rear_lowpass_Hz   = 7000.0
    rear_mid_blend_dB = -14.0
    presetName$       = "Subtle"
elsif preset = 3
    # Natural
    rear_level_dB     = -9.0
    rear_delay_ms     = 30.0
    decorr_offset_ms  = 7.0
    mono_width_ms     = 0.35
    rear_highpass_Hz  = 120.0
    rear_lowpass_Hz   = 6000.0
    rear_mid_blend_dB = -12.0
    presetName$       = "Natural"
elsif preset = 4
    # Spacious
    rear_level_dB     = -6.0
    rear_delay_ms     = 45.0
    decorr_offset_ms  = 10.0
    mono_width_ms     = 0.40
    rear_highpass_Hz  = 100.0
    rear_lowpass_Hz   = 5500.0
    rear_mid_blend_dB = -10.0
    presetName$       = "Spacious"
elsif preset = 5
    # Cinematic
    rear_level_dB     = -3.0
    rear_delay_ms     = 60.0
    decorr_offset_ms  = 12.0
    mono_width_ms     = 0.50
    rear_highpass_Hz  = 80.0
    rear_lowpass_Hz   = 8000.0
    rear_mid_blend_dB = -9.0
    presetName$       = "Cinematic"
elsif preset = 6
    # Wide Mono
    rear_level_dB     = -9.0
    rear_delay_ms     = 35.0
    decorr_offset_ms  = 8.0
    mono_width_ms     = 0.60
    rear_highpass_Hz  = 150.0
    rear_lowpass_Hz   = 5000.0
    rear_mid_blend_dB = -12.0
    presetName$       = "WideMono"
else
    presetName$ = "Custom"
endif

# ============================================================
# INPUT VALIDATION
# ============================================================

# Must have exactly one Sound selected
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object before running this script."
endif

original     = selected("Sound")
sourceName$  = selected$("Sound")

selectObject: original
numInputChannels = Get number of channels
sourceDuration   = Get total duration
sourceSR         = Get sampling frequency

# Guard: reject anything other than mono or stereo
if numInputChannels > 2
    exitScript: "Input has " + string$(numInputChannels) + " channels. " +
        ... "This script accepts mono (1 ch) or stereo (2 ch) only."
endif

# Clamp headroom so it is always negative or zero
if headroom_dB > 0
    headroom_dB = 0
endif

# ============================================================
# INFO HEADER
# ============================================================

writeInfoLine:  "=== Hamasaki Square Ambience ==="
appendInfoLine: "Source       : ", sourceName$
appendInfoLine: "Channels in  : ", numInputChannels
appendInfoLine: "Sample rate  : ", sourceSR, " Hz"
appendInfoLine: "Duration     : ", fixed$(sourceDuration, 3), " s"
appendInfoLine: "Preset       : ", presetName$
appendInfoLine: ""
appendInfoLine: "Parameters:"
appendInfoLine: "  Rear level      : ", fixed$(rear_level_dB, 1), " dB"
appendInfoLine: "  Rear delay      : ", fixed$(rear_delay_ms, 1), " ms"
appendInfoLine: "  Decorr offset   : ", fixed$(decorr_offset_ms, 1), " ms"
appendInfoLine: "  Mono width      : ", fixed$(mono_width_ms, 2), " ms"
appendInfoLine: "  HP / LP rear    : ", fixed$(rear_highpass_Hz, 0),
    ... " / ", fixed$(rear_lowpass_Hz, 0), " Hz"
appendInfoLine: "  Mid blend       : ", fixed$(rear_mid_blend_dB, 1), " dB"
appendInfoLine: "  Headroom        : ", fixed$(headroom_dB, 1), " dBFS"
appendInfoLine: ""

# ============================================================
# GAIN CONSTANTS
# ============================================================

# Convert rear_level_dB to a linear multiplier
rearGain = 10 ^ (rear_level_dB / 20)

# Convert rear_mid_blend_dB to a linear multiplier.
# Values at or below -100 dB are treated as disabled (gain = 0).
if rear_mid_blend_dB <= -100
    midBlendGain = 0
else
    midBlendGain = 10 ^ (rear_mid_blend_dB / 20)
endif

# Convert headroom to a peak ceiling (linear)
headroomLinear = 10 ^ (headroom_dB / 20)

# ============================================================
# EXTRACT OR BUILD FRONT CHANNELS (ch_L, ch_R)
# ============================================================
# Strategy:
#   Stereo input → extract left and right directly.
#   Mono input   → copy twice; add a tiny micro-delay to L to
#                  create a minimal width cue (Haas-effect range).
#                  A small gain tilt (+0.5 dB / −0.5 dB) further
#                  softens the phantom centre without sounding
#                  processed.

appendInfoLine: "Building front channels..."

if numInputChannels = 2
    # --- STEREO PATH ---
    # Extract left channel (channel 1) as a working copy
    selectObject: original
    Extract one channel: 1
    ch_L = selected("Sound")
    Rename: "work_L"

    # Extract right channel (channel 2) as a working copy
    selectObject: original
    Extract one channel: 2
    ch_R = selected("Sound")
    Rename: "work_R"

    appendInfoLine: "  Stereo: front L/R extracted from source."
    isStereoInput = 1

else
    # --- MONO PATH ---
    # L = original source (no delay).
    # R = source delayed by the full mono_width_ms.
    # This creates a real inter-channel timing difference (ITD)
    # of mono_width_ms between the two channels, which the ear
    # interprets as spatial width via the Haas effect.
    #
    # Why not ±half on each side:
    #   Praat can only prepend silence (delay forward in time).
    #   Prepending the same silence to both channels produces
    #   zero net timing difference — the bug in v1.1.
    #   The correct approach is: one channel unmodified, the
    #   other delayed by the full offset. The absolute timing
    #   shift of R doesn't matter perceptually; only the
    #   difference between L and R is heard as image width.
    #
    # A mild spectral tilt is added on top of the ITD:
    #   L gets a wide-open LP (near-transparent).
    #   R gets a very slightly lower LP cutoff.
    #   The tilt is too subtle to hear as EQ but reinforces
    #   inter-channel decorrelation.

    selectObject: original
    ch_L = Copy: "work_L"

    selectObject: original
    ch_R = Copy: "work_R"

    # Delay R by the full mono_width_ms
    widthSamples = round(mono_width_ms / 1000 * sourceSR)
    if widthSamples > 0
        widthDur = widthSamples / sourceSR

        # Prepend silence to R only, then trim to original duration
        Create Sound from formula: "sil_wR", 1, 0, widthDur, sourceSR, "0"
        sil_wR = selected("Sound")
        selectObject: sil_wR
        plusObject: ch_R
        concat_wR = Concatenate
        removeObject: sil_wR, ch_R
        selectObject: concat_wR
        ch_R_trim = Extract part: 0, sourceDuration, "rectangular", 1, "no"
        removeObject: concat_wR
        ch_R = ch_R_trim
        Rename: "work_R"
    endif

    # Spectral tilt: L wide-open, R very slightly softer
    # Cutoffs are set well above the audible EQ range for front
    # channels; this only contributes mild decorrelation.
    monoTiltLP_L = 18000.0
    monoTiltLP_R = 15000.0

    selectObject: ch_L
    Filter (pass Hann band): 20, monoTiltLP_L, 100
    ch_L_filt = selected("Sound")
    removeObject: ch_L
    ch_L = ch_L_filt
    Rename: "work_L"

    selectObject: ch_R
    Filter (pass Hann band): 20, monoTiltLP_R, 100
    ch_R_filt = selected("Sound")
    removeObject: ch_R
    ch_R = ch_R_filt
    Rename: "work_R"

    appendInfoLine: "  Mono: L=original, R delayed by ",
        ... fixed$(mono_width_ms, 3), " ms (real ITD) + spectral tilt."
    isStereoInput = 0
endif

# ============================================================
# BUILD REAR AMBIENCE SOURCE SIGNAL (rearSrc)
# ============================================================
# For stereo: use the side signal (L − R), which contains the
#             diffuse / out-of-phase ambience. The side signal
#             naturally emphasises room and suppresses the
#             phantom centre, making it ideal for rears.
# For mono:   use the mono source directly; its lack of width
#             already makes it suitable for a diffuse rear.
#
# The rear source is NOT yet delayed or filtered here —
# those steps come next, per-channel.

appendInfoLine: "Building rear ambience source..."

if isStereoInput = 1
    # Side signal = L − R
    # We compute it by copying L and subtracting R sample-by-sample.
    selectObject: ch_L
    rearSrc = Copy: "rear_src"

    # Build a formula string that references the R channel object
    rRid$ = string$(ch_R)
    selectObject: rearSrc
    Formula: "self - Object_" + rRid$ + "[col]"

    appendInfoLine: "  Side signal (L−R) used as rear source."
else
    # Mono input: rear source is just the mono signal
    selectObject: original
    rearSrc = Copy: "rear_src"
    appendInfoLine: "  Mono source used as rear source."
endif

# ============================================================
# OPTIONAL: BLEND MID (L+R) SIGNAL INTO REAR SOURCE
# ============================================================
# For centered or mono-ish sources the side signal (L−R) has
# very little energy, making the rears nearly silent even at
# 0 dB rear level. Blending in a fraction of the mid signal
# (L+R) ensures the rears are always audible while still
# sitting behind the front image perceptually.
# The mid is attenuated by rear_mid_blend_dB and added on top
# of the existing rear source. It is filtered together with
# the side in the bandpass step that follows, so it receives
# the same HP/LP shaping and sounds diffuse rather than direct.

if midBlendGain > 0
    # Build mid signal from the original input
    if isStereoInput = 1
        # Mid = (L + R) * 0.5
        selectObject: ch_L
        midSig = Copy: "mid_blend"
        rLid$ = string$(ch_R)
        selectObject: midSig
        Formula: "(self + Object_" + rLid$ + "[col]) * 0.5"
    else
        # Mono input: mid is just the source itself
        selectObject: original
        midSig = Copy: "mid_blend"
    endif

    # Add scaled mid into rear source
    midSigId$ = string$(midSig)
    selectObject: rearSrc
    Formula: "self + " + string$(midBlendGain) + " * Object_" + midSigId$ + "[col]"

    removeObject: midSig
    appendInfoLine: "  Mid blend: ", fixed$(rear_mid_blend_dB, 1), " dB added to rear source."
else
    appendInfoLine: "  Mid blend: disabled."
endif

# ============================================================
# BANDPASS FILTER THE REAR SOURCE
# ============================================================
# A high-pass removes LF boom and LFE bleed in the surrounds.
# A low-pass softens the HF presence so the rears sound diffuse
# rather than direct. Both use Praat's Hann-windowed bandpass.

appendInfoLine: "Filtering rear source: HP=",
    ... fixed$(rear_highpass_Hz, 0), " Hz, LP=",
    ... fixed$(rear_lowpass_Hz, 0), " Hz..."

selectObject: rearSrc
Filter (pass Hann band): rear_highpass_Hz, rear_lowpass_Hz, 100
rearFilt = selected("Sound")
Rename: "rear_filt"
removeObject: rearSrc

# ============================================================
# BUILD Ls (LEFT SURROUND) — Ch 3
# ============================================================
# Ls = filtered rear source, delayed by rear_delay_ms − half the
# decorrelation offset. Keeping both rears symmetric around the
# base delay means neither surround leads or lags unnaturally;
# the offset only creates the inter-channel difference needed
# for decorrelation, without biasing the overall rear image.

appendInfoLine: "Building Ls..."

selectObject: rearFilt
ch_Ls = Copy: "work_Ls"

# Symmetric delay: base − half offset
halfOffsetSec = (decorr_offset_ms / 2) / 1000
lsDelaySec = rear_delay_ms / 1000 - halfOffsetSec
# Guard: delay can't be negative (clamp to zero)
if lsDelaySec < 0
    lsDelaySec = 0
endif

if lsDelaySec > 0
    Create Sound from formula: "sil_Ls", 1, 0, lsDelaySec, sourceSR, "0"
    sil_Ls = selected("Sound")
    selectObject: sil_Ls
    plusObject: ch_Ls
    concat_Ls = Concatenate
    removeObject: sil_Ls, ch_Ls
    selectObject: concat_Ls
    ch_Ls_trimmed = Extract part: 0, sourceDuration, "rectangular", 1, "no"
    removeObject: concat_Ls
    ch_Ls = ch_Ls_trimmed
    Rename: "work_Ls"
endif

# Apply rear gain
selectObject: ch_Ls
Formula: "self * " + string$(rearGain)

appendInfoLine: "  Ls delay: ", fixed$(lsDelaySec * 1000, 1), " ms"

# ============================================================
# BUILD Rs (RIGHT SURROUND) — Ch 4
# ============================================================
# Rs = filtered rear source, delayed by rear_delay_ms + half the
# decorrelation offset. Polarity is kept positive (same as Ls).
# Decorrelation is achieved by the combined effect of:
#   1. The delay difference (lsDelaySec vs rsDelaySec)
#   2. A slightly lower LP cutoff on Rs (spectral tilt)
# This produces a gentler, more natural decorrelation than a
# blunt polarity inversion, which can sound hollow and creates
# mono-compatibility issues.

appendInfoLine: "Building Rs..."

# Rs uses a slightly lower LP cutoff than Ls to create a mild
# timbral difference — the simplest form of spectral decorrelation
# available with Praat's native filter commands.
# The cutoff reduction is 15% of the rear LP frequency, which is
# perceptible as a soft air-reduction without sounding like EQ.
rsLowpassHz = rear_lowpass_Hz * 0.85

selectObject: rearFilt
Filter (pass Hann band): rear_highpass_Hz, rsLowpassHz, 100
ch_Rs_src = selected("Sound")
Rename: "work_Rs_src"

# Symmetric delay: base + half offset
rsDelaySec = rear_delay_ms / 1000 + halfOffsetSec

if rsDelaySec > 0
    Create Sound from formula: "sil_Rs", 1, 0, rsDelaySec, sourceSR, "0"
    sil_Rs = selected("Sound")
    selectObject: sil_Rs
    plusObject: ch_Rs_src
    concat_Rs = Concatenate
    removeObject: sil_Rs, ch_Rs_src
    selectObject: concat_Rs
    ch_Rs_trimmed = Extract part: 0, sourceDuration, "rectangular", 1, "no"
    removeObject: concat_Rs
    ch_Rs = ch_Rs_trimmed
    Rename: "work_Rs"
else
    ch_Rs = ch_Rs_src
    Rename: "work_Rs"
endif

# Apply rear gain (positive polarity — no inversion)
selectObject: ch_Rs
Formula: "self * " + string$(rearGain)

appendInfoLine: "  Rs delay: ", fixed$(rsDelaySec * 1000, 1),
    ... " ms  (LP cutoff: ", fixed$(rsLowpassHz, 0), " Hz, spectral decorr)"

# Clean up the shared filtered source
removeObject: rearFilt

# ============================================================
# VERIFY DURATION CONSISTENCY
# ============================================================
# All four working channels must have the same duration before
# combining. Extract part trims to sourceDuration, but floating-
# point rounding can leave samples off. We check and pad if needed.

for chIdx from 1 to 4
    if chIdx = 1
        chCheck = ch_L
    elsif chIdx = 2
        chCheck = ch_R
    elsif chIdx = 3
        chCheck = ch_Ls
    else
        chCheck = ch_Rs
    endif

    selectObject: chCheck
    chDur = Get total duration
    # If shorter than source by more than one sample, extend with silence
    if sourceDuration - chDur > 1 / sourceSR
        appendInfoLine: "  Padding ch", chIdx, " by ",
            ... fixed$((sourceDuration - chDur) * 1000, 2), " ms"
        padDur = sourceDuration - chDur
        Create Sound from formula: "pad_tmp", 1, 0, padDur, sourceSR, "0"
        padTmp = selected("Sound")
        selectObject: chCheck
        plusObject: padTmp
        padConcat = Concatenate
        removeObject: padTmp, chCheck
        if chIdx = 1
            ch_L = padConcat
            Rename: "work_L"
        elsif chIdx = 2
            ch_R = padConcat
            Rename: "work_R"
        elsif chIdx = 3
            ch_Ls = padConcat
            Rename: "work_Ls"
        else
            ch_Rs = padConcat
            Rename: "work_Rs"
        endif
    endif
endfor

# ============================================================
# COMBINE INTO 4-CHANNEL SOUND
# ============================================================
# Praat's "Combine to stereo" accepts any number of mono objects
# selected simultaneously and stacks them as channels in the
# order they appear in the Objects list (top → bottom = ch1 → N).

appendInfoLine: ""
appendInfoLine: "Combining 4 channels..."

selectObject: ch_L
plusObject: ch_R
plusObject: ch_Ls
plusObject: ch_Rs
quad = Combine to stereo
Rename: sourceName$ + "_HamasakiSq"

# ============================================================
# FINAL PEAK NORMALISATION
# ============================================================
# Peak across ALL channels; scale so the loudest peak sits at
# headroomLinear (e.g. 0.891 for −1 dBFS).

selectObject: quad
rawPeak = Get absolute extremum: 0, 0, "None"
if rawPeak < 0.0001
    rawPeak = 0.0001
endif
normGain = headroomLinear / rawPeak
selectObject: quad
Formula: "self * " + string$(normGain)

appendInfoLine: "Peak normalised: raw peak=", fixed$(rawPeak, 4),
    ... "  normGain=", fixed$(normGain, 4),
    ... "  ceiling=", fixed$(headroom_dB, 1), " dBFS"

# ============================================================
# CLEAN UP TEMPORARY CHANNEL OBJECTS
# ============================================================

removeObject: ch_L, ch_R, ch_Ls, ch_Rs

# ============================================================
# DONE — LOG
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== Done ==="
selectObject: quad
quadName$ = selected$("Sound")
quadDur = Get total duration
appendInfoLine: "Output: ", quadName$
appendInfoLine: "Channels: 4  (L, R, Ls, Rs)"
appendInfoLine: "Duration: ", fixed$(quadDur, 3), " s"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title bar
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.72
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Hamasaki Square Ambience v1.3.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"

    # Input type label
    if isStereoInput
        inTypeStr$ = "stereo"
    else
        inTypeStr$ = "mono"
    endif

    Text: 0.5, "centre", -0.12, "half",
        ... sourceName$
        ... + "  |  " + inTypeStr$
        ... + "  |  preset: " + presetName$
        ... + "  |  rear " + fixed$(rear_level_dB, 1) + " dB"
        ... + "  |  delay " + fixed$(rear_delay_ms, 0) + " ms"

    # ----------------------------------------------------------
    # Hamasaki Square layout diagram (left panel)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 0.62, 4.10
    Select inner viewport: 0.50, 3.85, 0.78, 3.98

    Axes: -1.6, 1.6, -1.6, 1.6
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.6, 1.6, -1.6, 1.6

    # Room boundary (the square)
    Colour: "{0.30, 0.30, 0.30}"
    Line width: 2
    Draw rectangle: -1.2, 1.2, -1.2, 1.2
    Line width: 1

    # Grid / crosshair
    Colour: "{0.84, 0.84, 0.84}"
    Draw line: 0, -1.45, 0, 1.45
    Draw line: -1.45, 0, 1.45, 0

    # ---- Speaker dots ----
    # L  (front left)
    Paint circle (mm): "{0.25, 0.50, 0.82}", -1.2, 1.2, 4.5
    Font size: 6
    Colour: "{0.15, 0.38, 0.65}"
    Text: -1.2, "centre", 1.38, "half", "L"

    # R  (front right)
    Paint circle (mm): "{0.82, 0.45, 0.25}", 1.2, 1.2, 4.5
    Colour: "{0.65, 0.32, 0.12}"
    Text: 1.2, "centre", 1.38, "half", "R"

    # Ls (rear left)
    Paint circle (mm): "{0.35, 0.62, 0.82}", -1.2, -1.2, 4.5
    Colour: "{0.15, 0.38, 0.65}"
    Text: -1.2, "centre", -1.38, "half", "Ls"

    # Rs (rear right)
    Paint circle (mm): "{0.82, 0.60, 0.35}", 1.2, -1.2, 4.5
    Colour: "{0.65, 0.32, 0.12}"
    Text: 1.2, "centre", -1.38, "half", "Rs"

    # Listener at centre
    Paint circle (mm): "White", 0, 0, 5.0
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 4.0
    Font size: 6
    Colour: "{0.15, 0.45, 0.18}"
    Text: 0, "centre", -0.20, "half", "Listener"

    # Direction labels
    Font size: 6
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0, "centre", 1.52, "half", "Front"
    Text: 0, "centre", -1.52, "half", "Back"

    # Arrows: source → front speakers (blue/orange)
    # Dashed lines from listener to each speaker
    Line width: 1
    Colour: "{0.25, 0.50, 0.82}"
    Dotted line
    Draw line: 0, 0, -1.15, 1.15
    Colour: "{0.82, 0.45, 0.25}"
    Draw line: 0, 0, 1.15, 1.15
    # Rear lines thinner, more muted
    Colour: "{0.55, 0.72, 0.82}"
    Draw line: 0, 0, -1.15, -1.15
    Colour: "{0.82, 0.72, 0.50}"
    Draw line: 0, 0, 1.15, -1.15
    Solid line

    # Delay annotations next to rear speakers
    Font size: 6
    Colour: "{0.35, 0.35, 0.35}"
    Text: -0.70, "centre", -0.75, "half",
        ... fixed$(lsDelaySec * 1000, 0) + " ms"
    Text: 0.70, "centre", -0.75, "half",
        ... fixed$(rsDelaySec * 1000, 0) + " ms"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "4-channel layout  (Ls/Rs symmetrically delayed + spectrally decorrelated)"

    # ----------------------------------------------------------
    # Parameter bars (right panel)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 0.62, 4.10
    Select inner viewport: 4.45, 7.70, 0.78, 3.98

    Axes: 0, 1, -0.5, 7.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, -0.5, 7.5

    Font size: 7
    Colour: "Black"
    barL = 0.28
    barR = 0.86

    # Helper: draw a labelled horizontal bar
    # (Praat has no subroutines with local scope, so we inline each bar)

    # --- Rear Level bar ---
    # Fraction: map -20..0 dB → 0..1
    rLevFrac = (rear_level_dB + 20) / 20
    if rLevFrac < 0
        rLevFrac = 0
    endif
    Text: 0.03, "left", 7.0, "half", "Rear lvl"
    Paint rectangle: "{0.50, 0.65, 0.80}", barL, barL + rLevFrac * (barR - barL), 6.78, 7.22
    Font size: 6
    Text: 0.88, "left", 7.0, "half", fixed$(rear_level_dB, 1) + " dB"

    # --- Mid Blend bar ---
    Font size: 7
    Text: 0.03, "left", 6.2, "half", "Mid blend"
    if midBlendGain > 0
        midFrac = (rear_mid_blend_dB + 24) / 24
        if midFrac < 0
            midFrac = 0
        endif
        if midFrac > 1
            midFrac = 1
        endif
        Paint rectangle: "{0.65, 0.55, 0.75}", barL, barL + midFrac * (barR - barL), 5.98, 6.42
        Font size: 6
        Text: 0.88, "left", 6.2, "half", fixed$(rear_mid_blend_dB, 1) + " dB"
    else
        Colour: "{0.65, 0.65, 0.65}"
        Font size: 6
        Text: 0.55, "centre", 6.2, "half", "OFF"
        Colour: "Black"
    endif

    # --- Rear Delay bar ---
    rDelFrac = rear_delay_ms / 80
    if rDelFrac > 1
        rDelFrac = 1
    endif
    Font size: 7
    Text: 0.03, "left", 5.2, "half", "Rear dly"
    Paint rectangle: "{0.72, 0.55, 0.38}", barL, barL + rDelFrac * (barR - barL), 4.98, 5.42
    Font size: 6
    Text: 0.88, "left", 5.2, "half", fixed$(rear_delay_ms, 0) + " ms"

    # --- Decorr Offset bar ---
    dOFrac = decorr_offset_ms / 20
    if dOFrac > 1
        dOFrac = 1
    endif
    Font size: 7
    Text: 0.03, "left", 4.2, "half", "Decorr Δ"
    Paint rectangle: "{0.55, 0.45, 0.72}", barL, barL + dOFrac * (barR - barL), 3.98, 4.42
    Font size: 6
    Text: 0.88, "left", 4.2, "half", fixed$(decorr_offset_ms, 1) + " ms"

    # --- HP freq bar ---
    hpFrac = (rear_highpass_Hz - 60) / (500 - 60)
    if hpFrac < 0
        hpFrac = 0
    endif
    if hpFrac > 1
        hpFrac = 1
    endif
    Font size: 7
    Text: 0.03, "left", 3.2, "half", "HP rear"
    Paint rectangle: "{0.45, 0.70, 0.55}", barL, barL + hpFrac * (barR - barL), 2.98, 3.42
    Font size: 6
    Text: 0.88, "left", 3.2, "half", fixed$(rear_highpass_Hz, 0) + " Hz"

    # --- LP freq bar ---
    lpFrac = (rear_lowpass_Hz - 1000) / (12000 - 1000)
    if lpFrac < 0
        lpFrac = 0
    endif
    if lpFrac > 1
        lpFrac = 1
    endif
    Font size: 7
    Text: 0.03, "left", 2.2, "half", "LP rear"
    Paint rectangle: "{0.70, 0.55, 0.45}", barL, barL + lpFrac * (barR - barL), 1.98, 2.42
    Font size: 6
    Text: 0.88, "left", 2.2, "half", fixed$(rear_lowpass_Hz, 0) + " Hz"

    # --- Mono Width bar (shown even for stereo, greyed if stereo) ---
    Font size: 7
    Text: 0.03, "left", 1.2, "half", "Widen"
    if isStereoInput = 0
        wFrac = mono_width_ms / 1.0
        if wFrac > 1
            wFrac = 1
        endif
        Paint rectangle: "{0.62, 0.62, 0.45}", barL, barL + wFrac * (barR - barL), 0.98, 1.42
        Font size: 6
        Text: 0.88, "left", 1.2, "half", fixed$(mono_width_ms, 2) + " ms"
    else
        Colour: "{0.65, 0.65, 0.65}"
        Font size: 6
        Text: 0.55, "centre", 1.2, "half", "n/a (stereo)"
        Colour: "Black"
    endif

    # --- Norm gain indicator ---
    Font size: 7
    Colour: "Black"
    Text: 0.03, "left", 0.2, "half", "Norm"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.28, "left", 0.2, "half",
        ... "×" + fixed$(normGain, 3) + "  (" + fixed$(headroom_dB, 1) + " dBFS)"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Parameters"

    # ----------------------------------------------------------
    # Output waveform — all 4 channels overlaid
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.20, 5.35
    Select inner viewport: 0.55, 7.70, 4.27, 5.28

    selectObject: quad
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampMax = outPeak * 1.15

    outDur = Get total duration
    Axes: 0, outDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDur, 0

    # Ch 1 — L (blue)
    selectObject: quad
    Extract one channel: 1
    vizCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizCh1

    # Ch 2 — R (orange)
    selectObject: quad
    Extract one channel: 2
    vizCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizCh2

    # Ch 3 — Ls (light blue)
    selectObject: quad
    Extract one channel: 3
    vizCh3 = selected("Sound")
    Colour: "{0.55, 0.78, 0.92}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizCh3

    # Ch 4 — Rs (light orange)
    selectObject: quad
    Extract one channel: 4
    vizCh4 = selected("Sound")
    Colour: "{0.92, 0.72, 0.50}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizCh4

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 4.2, 5.35
    Select inner viewport: 0.08, 0.52, 4.22, 5.33
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 4.2, 5.35
    Select inner viewport: 0.55, 7.7, 4.27, 5.28
    Axes: 0, outDur, -ampMax, ampMax
    Text top: "no", "4-ch output  (blue=L  orange=R  lt.blue=Ls  lt.orange=Rs)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Summary bar
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.60, 6.35
    Select inner viewport: 0.55, 7.70, 5.65, 6.29
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.64, "half",
        ... "##" + presetName$ + "##  " + inTypeStr$ + " in → 4 ch out  |  "
        ... + sourceName$
    Text: 0.02, "left", 0.28, "half",
        ... "RearLvl=" + fixed$(rear_level_dB, 1) + "dB"
        ... + "  MidBlend=" + fixed$(rear_mid_blend_dB, 1) + "dB"
        ... + "  LsDly=" + fixed$(lsDelaySec * 1000, 0) + "ms"
        ... + "  RsDly=" + fixed$(rsDelaySec * 1000, 0) + "ms"
        ... + "  RsLP=" + fixed$(rsLowpassHz, 0) + "Hz"
        ... + "  HP=" + fixed$(rear_highpass_Hz, 0) + "Hz"
        ... + "  LP=" + fixed$(rear_lowpass_Hz, 0) + "Hz"
        ... + "  Norm×" + fixed$(normGain, 3)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Reset drawing state
    Select outer viewport: 0, 8, 0, 6.45
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# OPTIONAL PLAYBACK
# ============================================================

if play_result
    selectObject: quad
    Play
endif

# Leave the result selected in the Objects list
selectObject: quad
