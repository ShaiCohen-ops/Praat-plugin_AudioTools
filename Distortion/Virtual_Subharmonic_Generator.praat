# ============================================================
# Praat AudioTools - Virtual_Subharmonic_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7.1 (2026) - Split-band generator, linked stereo layer
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Virtual Subharmonic Generator - phantom bass enhancement
#   (MaxxBass-style "missing fundamental" harmonics).
#
#   Architecture (v0.7+):
#
#       y = D{x} + g * H{x}
#
#     D  direct path. By default the identity: the original
#        samples, untouched (no filter, no stereo change, no
#        normalisation). Only the opt-in "Small-Speaker
#        Replacement" preset / Original_low_cut setting turns it
#        into a low-cut, which is the classic MaxxBass replacement.
#     H  enhancement layer, computed in a separate branch:
#          1. bass band  B = band-pass[Bass_low, Bass_high], split
#             into three log-spaced sub-bands that are shaped
#             separately (default; see v0.7.1 changelog)
#          2. nonlinear residual  N = (tanh(k*B) - k*B) / s
#             (the waveshaper MINUS its own linear part, so the
#             layer contains distortion products only - the bass
#             fundamental is not re-added through the layer;
#             k = Drive * s, s = optional bass reference scale)
#          3. harmonic band  H = band-pass[Bass_high + edge,
#             Harmonic_lowpass]
#     g  Harmonic_level (linear addition gain).
#
#   With Harmonic_level = 0 and Original_low_cut = 0 the output is
#   sample-identical to the input (same channel count, same start
#   time, same level) in the default Output_mode.
#
#   Because tanh is odd-symmetric, a balanced sinusoid mostly
#   produces ODD harmonics (3f, 5f, ...). The script does not create
#   true subharmonics (f/2, f/3); it reinforces the PERCEIVED bass via
#   upper harmonics, which is what the "virtual" in the name means.
#   Polyphonic bass material also produces intermodulation products.
#
#   Filter design: bass-band, sub-band crossover and harmonic-band
#   lower-edge filters use smoothing of at most 20 Hz, so each cutoff
#   is the -6 dB point of a clean transition. The harmonic band's
#   UPPER edge is deliberately gentler (up to 100 Hz). v0.6.1 used a fixed 100 Hz,
#   which on a 90 Hz-wide bass band overlapped both transitions:
#   measured response 0.99 at 120 Hz, 0.50 at 130 Hz, 0.35 at 10 Hz.
#
#   Optional creative stereo processing (M/S width, Side low-cut) is
#   OFF by default and applies to stereo input only.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.7.1 (2026) - DSP refinement; v0.7 output is reproduced
# to 1e-16 by Harmonic_generator = Single band + Bass_reference
# = file peak + Stereo_layer = Per channel. Measured on sines (Drive 3):
#   - Three-sub-band generator (default): the bass band is split by
#     successive subtraction (sums exactly), each sub-band shaped alone.
#     60 + 80 Hz together: intermodulation/harmonic energy +13.5 dB ->
#     -8.8 dB.
#   - Sub-band equalisation, measured at run time on a sine at each
#     sub-band centre (boost cap +12 dB), plus more drive for deeper
#     sub-bands ((top centre / centre) ^ 0.5). Layer level across 30-110
#     Hz fundamentals: spread 23 dB -> ~6 dB (30 Hz -35.6 -> -16.7 dB,
#     40 Hz -29.6 -> -10.8 dB; 60-110 Hz ~ -11 to -14 dB). 30 Hz remains
#     ~5 dB below the rest: only its 5th harmonic and up pass the band.
#   - Stereo_layer = Linked (default): one layer from the mono bass,
#     spread by each channel's bass RMS. 60 Hz at 5:1 L/R -> added
#     harmonics 5.0:1 (per-channel shaping gives 42.7:1).
#   - Bass reference (default): gated RMS level (frames within 30 dB of
#     the loudest), boost capped at +24 dB. One 20 ms hit lowered the
#     layer on the rest of a file by 16.9 dB with the file-peak
#     reference; now 0.2 dB.
#   - Default preset is Subtle Enhancement.
#   - Info and figure report the layer relative to the input's own
#     energy in the harmonic band. Spectrum panel is now a per-channel
#     energy average instead of a mono sum.
#   - Known, unchanged: Hann filters are zero-phase, so the layer can
#     start slightly before a bass onset (measured -28 to -44 dB re the
#     sustained layer in the last 100 ms before a hard 40-90 Hz onset).
#   - Not done: level-dependent (windowed) dynamic control of the layer.
#
# Changelog v0.7 (2026) - AUDIO/DSP CHANGE, not bit-compatible with 0.6.x:
#   - Direct path is no longer high-passed. The layer is added to the
#     untouched original (y = x + g*H{x}, was HP{x} + g*H{x}).
#     Identity test: Harmonic_level = 0 returns the input exactly.
#   - Waveshaper output now has its linear term removed
#     (tanh(k*B) - k*B), so the "harmonic branch" no longer carries a
#     filtered copy of the bass fundamental back into the mix. Its
#     harmonics are the same as 0.6.1's tanh(k*B) at equal Drive, so
#     Harmonic_level keeps its meaning (preset levels unchanged).
#   - Bass and harmonic filters: smoothing 100 Hz -> <= 20 Hz, and the
#     harmonic band now starts a full transition above Bass_high, so
#     the fundamental region is rejected (v0.6.1: 0.345 at 100 Hz).
#   - Bass_reference normalisation (now the default) uses ONE peak for
#     all channels, so the layer keeps the source's inter-channel
#     balance (v0.6.1 normalised L and R separately).
#   - Any channel count is processed and preserved: mono stays mono,
#     >2 channels are all kept (v0.6.1 forced stereo and discarded
#     channels 3+).
#   - M/S processing moved to Advanced, OFF by default, stereo only.
#     Default width 1.0 (v0.6.1 default 0.5 narrowed the image).
#   - Output_mode default: Preserve rendered level (was Normalize to
#     0.95). The safety ceiling only acts when processing pushes the
#     peak above both 0.999 and the input peak.
#   - Presets reworked; Bass-Centered Narrowing and Wide Stereo removed
#     (stereo is no longer part of bass enhancement). runScript callers
#     using those option texts must be updated. New opt-in preset
#     "Small-Speaker Replacement" keeps the classic low-cut behaviour,
#     named for what it does.
#   - Presets are applied BEFORE the Advanced dialog, which opens
#     pre-filled with the preset's values; edits there now stick.
#   - New optional output: difference object (output - input) for QA.
#   - Info reports layer level, RMS change and difference peak.
#   - Visualization: parallel signal-flow diagram, measured long-term
#     spectrum (input / output / difference, log frequency), and the
#     difference waveform on the input's amplitude scale.
#
# Earlier history (0.2-0.6.1) condensed:
#   0.6.1 output/reporting wording; 0.6 Advanced pause dialog;
#   0.5 visualization standardization; 0.4 QA fixes (domain-relative
#   drawing, near-silence normalisation guard, Harmonic_mix renamed
#   Harmonic_level, odd-harmonic documentation, frequency validation);
#   0.3 removed the non-functional Haas stage; 0.2 syntax fixes.
# ============================================================

form Virtual Subharmonic Generator v0.7.1
    comment Select a Sound object first
    optionmenu Preset: 2
        option Custom (use settings below)
        option Subtle Enhancement
        option Moderate Enhancement
        option Strong Enhancement
        option Small-Speaker Replacement (cuts original lows)
    comment === Phantom bass layer (added to the untouched original) ===
    positive Bass_low_freq 30
    positive Bass_high_freq 120
    positive Drive 3.0
    real Harmonic_level 0.6
    boolean Advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
sr = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels
xminOrig = Get start time
xmaxOrig = Get end time
inputPeak = Get absolute extremum: 0, 0, "None"
inputRms = Get root-mean-square: 0, 0
nyquist = sr / 2

# === Advanced defaults ===
harmonic_lowpass = 800
original_low_cut = 0
bass_reference_mode = 2
bass_reference_peak = 0.5
apply_MS_width = 0
stereo_width = 1.0
mono_bass_side_lowcut = 0
output_mode = 1
normalize_target = 0.95
near_silence_dB = -80
keep_difference = 0
harmonic_generator = 1
stereo_layer = 2

# === Apply Presets (before the Advanced dialog, so it shows them) ===
if preset = 2
    bass_low_freq = 30
    bass_high_freq = 100
    drive = 2.0
    harmonic_level = 0.4
    harmonic_lowpass = 600
    original_low_cut = 0
    presetName$ = "Subtle"
elsif preset = 3
    bass_low_freq = 30
    bass_high_freq = 120
    drive = 3.0
    harmonic_level = 0.6
    harmonic_lowpass = 800
    original_low_cut = 0
    presetName$ = "Moderate"
elsif preset = 4
    bass_low_freq = 25
    bass_high_freq = 150
    drive = 5.0
    harmonic_level = 0.8
    harmonic_lowpass = 1000
    original_low_cut = 0
    presetName$ = "Strong"
elsif preset = 5
    # Classic MaxxBass replacement for small speakers: the original's
    # lows are cut and replaced by their harmonics. This preset
    # deliberately modifies the original.
    bass_low_freq = 30
    bass_high_freq = 120
    drive = 4.0
    harmonic_level = 0.8
    harmonic_lowpass = 800
    original_low_cut = 100
    presetName$ = "Replacement"
else
    presetName$ = "Custom"
endif

# Praat permits only one form...endform block. Optional secondary
# controls use beginPause/endPause and appear only when requested.
if advanced_settings
    beginPause: "Virtual Subharmonic Generator v0.7.1 - Advanced settings"
        comment: "Pre-filled with the current preset; edits here are applied."
        positive: "Harmonic_lowpass", string$(harmonic_lowpass)
        real: "Original_low_cut", string$(original_low_cut)
        optionmenu: "Harmonic_generator", harmonic_generator
            option: "Three sub-bands, equalised (less intermodulation)"
            option: "Single band (v0.7)"
        optionmenu: "Stereo_layer", stereo_layer
            option: "Per channel (harmonics follow each channel bass)"
            option: "Linked (one layer, spread by channel bass level)"
        optionmenu: "Bass_reference_mode", bass_reference_mode
            option: "Off: Drive scales with input loudness"
            option: "Normalize to gated RMS level (robust)"
            option: "Normalize to file peak (v0.7)"
        positive: "Bass_reference_peak", string$(bass_reference_peak)
        comment: "Original_low_cut 0 = untouched.  M/S below: stereo input only."
        boolean: "Apply_MS_width", apply_MS_width
        real: "Stereo_width", string$(stereo_width)
        boolean: "Mono_bass_side_lowcut", mono_bass_side_lowcut
        optionmenu: "Output_mode", output_mode
            option: "Preserve rendered level (safety attenuation only)"
            option: "Normalize to target"
            option: "Attenuate to target only if peak > target"
            option: "Legacy (always normalize to 0.95)"
        real: "Normalize_target", string$(normalize_target)
        real: "Near_silence_dB", string$(near_silence_dB)
        boolean: "Keep_difference", keep_difference
    clicked = endPause: "Continue", 1
endif

# === Filter geometry ===
# Every Hann transition spans [cutoff - w, cutoff + w], -6 dB at the
# cutoff. Smoothing is kept at or below 20 Hz so transitions never
# overlap inside the bass band.
bassSmooth = min(20, (bass_high_freq - bass_low_freq) / 4)
harmEdgeSmooth = min(20, bass_high_freq / 4)
harmLowEdge = bass_high_freq + harmEdgeSmooth
harmTopSmooth = min(100, (harmonic_lowpass - harmLowEdge) / 4)
if original_low_cut > 0
    lowCutSmooth = min(20, original_low_cut / 4)
else
    lowCutSmooth = 0
endif

# === Validation ===
if bass_low_freq >= bass_high_freq
    exitScript: "Bass_low_freq (", bass_low_freq, " Hz) must be less than Bass_high_freq (", bass_high_freq, " Hz)."
endif
if bass_high_freq >= nyquist
    exitScript: "Bass_high_freq (", bass_high_freq, " Hz) must be below the Nyquist frequency (", nyquist, " Hz)."
endif
if harmonic_lowpass < bass_high_freq + 4 * harmEdgeSmooth
    exitScript: "Harmonic_lowpass (", harmonic_lowpass, " Hz) must be at least ", bass_high_freq + 4 * harmEdgeSmooth, " Hz (Bass_high_freq plus room for the lower transition of the harmonic band)."
endif
if harmonic_lowpass >= nyquist
    exitScript: "Harmonic_lowpass (", harmonic_lowpass, " Hz) must be below the Nyquist frequency (", nyquist, " Hz)."
endif
if original_low_cut < 0 or original_low_cut >= nyquist
    exitScript: "Original_low_cut must be 0 (off) or between 0 and the Nyquist frequency."
endif
if output_mode = 2 or output_mode = 3
    if normalize_target <= 0 or normalize_target > 1
        exitScript: "Normalize_target must be greater than 0 and at most 1 in this Output_mode (got " + fixed$(normalize_target, 4) + ")."
    endif
endif

msActive = apply_MS_width and numChannels = 2
linkedActive = stereo_layer = 2 and numChannels > 1

# === Status strings ===
if original_low_cut > 0
    directStr$ = "LOW-CUT at " + fixed$(original_low_cut, 0) + " Hz (replacement)"
    directShort$ = "low-cut " + fixed$(original_low_cut, 0) + " Hz"
else
    directStr$ = "untouched (identity)"
    directShort$ = "untouched"
endif
if msActive
    msStr$ = "ON (width " + fixed$(stereo_width, 2) + ")"
    if mono_bass_side_lowcut
        monoStr$ = "ON (200 Hz)"
    else
        monoStr$ = "OFF"
    endif
elsif apply_MS_width
    msStr$ = "requested, skipped (input is not stereo)"
    monoStr$ = "inactive"
else
    msStr$ = "OFF (stereo untouched)"
    monoStr$ = "inactive"
endif
if bass_reference_mode = 2
    bassRefStr$ = "gated RMS -> sine-equivalent peak " + fixed$(bass_reference_peak, 2) + " (boost cap +24 dB)"
    bassRefShort$ = "gated RMS to " + fixed$(bass_reference_peak, 2)
elsif bass_reference_mode = 3
    bassRefStr$ = "file peak -> " + fixed$(bass_reference_peak, 2)
    bassRefShort$ = "peak to " + fixed$(bass_reference_peak, 2)
else
    bassRefStr$ = "OFF (level-dependent Drive)"
    bassRefShort$ = "level-dependent"
endif
if harmonic_generator = 1
    genStr$ = "3 sub-bands, equalised"
else
    genStr$ = "single band"
endif
if linkedActive
    stereoLayerStr$ = "linked"
elsif numChannels > 1
    stereoLayerStr$ = "per channel"
else
    stereoLayerStr$ = "mono"
endif
if output_mode = 1
    outputModeStr$ = "Preserve rendered level (safety attenuation only)"
    outputModeShort$ = "Preserve + safety"
elsif output_mode = 2
    outputModeStr$ = "Normalize to target " + fixed$(normalize_target, 3)
    outputModeShort$ = "Normalize " + fixed$(normalize_target, 2)
elsif output_mode = 3
    outputModeStr$ = "Attenuate to target only if peak > " + fixed$(normalize_target, 3)
    outputModeShort$ = "Attenuate > " + fixed$(normalize_target, 2)
else
    outputModeStr$ = "Legacy: normalize to 0.95"
    outputModeShort$ = "Legacy norm 0.95"
endif

nearSilenceLin = 10 ^ (near_silence_dB / 20)

# === Info ===
writeInfoLine: "=== Virtual Subharmonic Generator v0.7.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", numChannels, " ch, starts at ", fixed$(xminOrig, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channel count is preserved (", numChannels, " in, ", numChannels, " out)."
appendInfoLine: ""
appendInfoLine: "Direct path: ", directStr$
appendInfoLine: "Enhancement layer:"
appendInfoLine: "  Bass band: ", fixed$(bass_low_freq, 1), "-", fixed$(bass_high_freq, 1), " Hz (smoothing ", fixed$(bassSmooth, 1), " Hz)"
appendInfoLine: "  Drive: ", fixed$(drive, 2), "   residual = tanh(kB) - kB"
appendInfoLine: "  Harmonic band: ", fixed$(harmLowEdge, 1), "-", fixed$(harmonic_lowpass, 1), " Hz (edges ", fixed$(harmEdgeSmooth, 1), " / ", fixed$(harmTopSmooth, 1), " Hz)"
appendInfoLine: "  Generator: ", genStr$, "   stereo layer: ", stereoLayerStr$
appendInfoLine: "  Bass reference: ", bassRefStr$
appendInfoLine: "  Harmonic addition gain: ", fixed$(harmonic_level, 2)
if harmonic_level < 0
    appendInfoLine: "    Note: negative -- layer is added phase-inverted."
endif
appendInfoLine: "M/S: ", msStr$
if msActive and stereo_width < 0
    appendInfoLine: "    Note: negative width -- Side polarity is inverted."
endif
appendInfoLine: "Side low-cut: ", monoStr$
appendInfoLine: "Output mode: ", outputModeStr$
appendInfoLine: ""

# ============================================================
# ENHANCEMENT LAYER  (all channels at once; filters act per channel)
# ============================================================

appendInfoLine: "Extracting bass band..."
selectObject: original
Filter (pass Hann band): bass_low_freq, bass_high_freq, bassSmooth
bassBand = selected("Sound")
bassPeak = Get absolute extremum: 0, 0, "None"
bassRms = Get root-mean-square: 0, 0
@gatedSinePeak: bassBand
gatedPeak = gatedSinePeak.level
appendInfoLine: "  Extracted bass peak: ", fixed$(bassPeak, 4), "   gated sine-equivalent level: ", fixed$(gatedPeak, 4)

# One shared reference scale for all channels keeps the layer's
# inter-channel balance at its input. Mode 2 uses the gated RMS level
# (frames within 30 dB of the loudest), so one short bass hit no longer
# sets the drive for the whole file; the boost is capped at +24 dB.
refScale = 1
if bass_reference_mode = 2 and gatedPeak > 0
    refScale = min(16, bass_reference_peak / gatedPeak)
elsif bass_reference_mode = 3 and bassPeak > 0
    refScale = bass_reference_peak / bassPeak
endif
k = drive * refScale

# --- sub-band split (log-spaced crossovers) ---
deepDriveExp = 0.5
if harmonic_generator = 1
    nSub = 3
else
    nSub = 1
endif
for i to nSub
    subLo[i] = bass_low_freq * (bass_high_freq / bass_low_freq) ^ ((i - 1) / nSub)
    subHi[i] = bass_low_freq * (bass_high_freq / bass_low_freq) ^ (i / nSub)
    subGain[i] = 1
    subResp[i] = undefined
endfor
# Deeper sub-bands are shaped harder: only their high orders (5th and
# up for a 30 Hz fundamental) reach the harmonic band, and more drive
# moves tanh's energy toward those orders. Factor = (top-band centre /
# this centre) ^ deepDriveExp (0.5: measured best compromise).
for i to nSub
    subDrive[i] = (sqrt(subLo[nSub] * subHi[nSub]) / sqrt(subLo[i] * subHi[i])) ^ deepDriveExp
endfor
for i to nSub - 1
    xoW[i] = min(20, (subHi[i] - subLo[i]) / 3, (subHi[i + 1] - subLo[i + 1]) / 3)
endfor

# --- calibration: measure each sub-band's layer response on a sine at
# its centre, at the level the real bass is shaped at, and equalise
# the sub-bands to the strongest one (boost capped at +12 dB) ---
if nSub > 1 and harmonic_level <> 0
    if bass_reference_mode = 1
        calAmp = gatedPeak
        if calAmp <= 0
            calAmp = 0.5
        endif
    else
        calAmp = bass_reference_peak / refScale
    endif
    linkedSave = linkedActive
    linkedActive = 0
    respMax = 0
    for i to nSub
        calF = sqrt(subLo[i] * subHi[i])
        Create Sound from formula: "vsg_cal", 1, 0, 1, sr, string$(calAmp) + " * sin(2 * pi * " + string$(calF) + " * x)"
        calSrc = selected("Sound")
        Filter (pass Hann band): bass_low_freq, bass_high_freq, bassSmooth
        calBB = selected("Sound")
        calIn = Get root-mean-square: 0.2, 0.8
        @buildLayer: calBB
        selectObject: buildLayer.layer
        calOut = Get root-mean-square: 0.2, 0.8
        subResp[i] = calOut / calIn
        if subResp[i] > respMax
            respMax = subResp[i]
        endif
        removeObject: calSrc, calBB, buildLayer.layer
    endfor
    for i to nSub
        if subResp[i] > 0
            subGain[i] = min(4, respMax / subResp[i])
        else
            subGain[i] = 4
        endif
    endfor
    linkedActive = linkedSave
endif

appendInfoLine: "Generating layer (k = ", fixed$(k, 3), ", ", nSub, " sub-band(s))..."
for i to nSub
    if subResp[i] = undefined
        respStr$ = "not calibrated"
    else
        respStr$ = "response " + fixed$(20 * log10(subResp[i] + 1e-30), 1) + " dB"
    endif
    appendInfoLine: "  ", fixed$(subLo[i], 1), "-", fixed$(subHi[i], 1), " Hz: ", respStr$, ", eq gain ", fixed$(20 * log10(subGain[i]), 1), " dB"
endfor
@buildLayer: bassBand
layer = buildLayer.layer
removeObject: bassBand

selectObject: layer
layerPeak = Get absolute extremum: 0, 0, "None"
layerRms = Get root-mean-square: 0, 0
appendInfoLine: "  Layer peak (before gain): ", fixed$(layerPeak, 4)

# ============================================================
# DIRECT PATH + SUM
# ============================================================

selectObject: original
if original_low_cut > 0
    appendInfoLine: "Direct path: low-cut at ", original_low_cut, " Hz (replacement mode)..."
    Filter (stop Hann band): 0, original_low_cut, lowCutSmooth
else
    Copy: "vsg_direct"
endif
result = selected("Sound")
Rename: originalName$ + "_vsg_" + presetName$

appendInfoLine: "Adding layer x ", fixed$(harmonic_level, 2), "..."
Formula: "self + object[" + string$(layer) + ", row, col] * " + string$(harmonic_level)
removeObject: layer

# ============================================================
# OPTIONAL CREATIVE M/S (stereo only)
# ============================================================

if msActive
    appendInfoLine: "Applying M/S width ", stereo_width, "..."
    selectObject: result
    Extract one channel: 1
    chL = selected("Sound")
    selectObject: result
    Extract one channel: 2
    chR = selected("Sound")
    lStr$ = string$(chL)
    rStr$ = string$(chR)

    selectObject: chL
    Copy: "vsg_mid"
    midSignal = selected("Sound")
    Formula: "(object[" + lStr$ + ", col] + object[" + rStr$ + ", col]) / 2"

    selectObject: chL
    Copy: "vsg_side"
    sideSignal = selected("Sound")
    Formula: "(object[" + lStr$ + ", col] - object[" + rStr$ + ", col]) / 2 * " + string$(stereo_width)

    if mono_bass_side_lowcut
        selectObject: sideSignal
        Filter (stop Hann band): 0, 200, 20
        sideFiltered = selected("Sound")
        removeObject: sideSignal
        sideSignal = sideFiltered
    endif

    selectObject: result
    Formula: "if row = 1 then object[" + string$(midSignal) + ", col] + object[" + string$(sideSignal) + ", col] else object[" + string$(midSignal) + ", col] - object[" + string$(sideSignal) + ", col] fi"
    removeObject: chL, chR, midSignal, sideSignal
endif

# ============================================================
# OUTPUT LEVEL
# ============================================================

selectObject: result
preOutputPeak = Get absolute extremum: 0, 0, "None"
isNearSilent = preOutputPeak < nearSilenceLin
normFactor = 1

if output_mode = 1
    # Attenuate only if processing pushed the peak above the ceiling
    # AND above the input's own peak, so an untouched full-scale input
    # still passes the identity test.
    if preOutputPeak > 0.999 and preOutputPeak > inputPeak
        normFactor = max(0.999, inputPeak) / preOutputPeak
        Formula: "self * " + string$(normFactor)
        outputActionDesc$ = "preserved level; safety-attenuated to " + fixed$(max(0.999, inputPeak), 3)
    else
        outputActionDesc$ = "preserved rendered level; no output scaling"
    endif
elsif output_mode = 2
    if isNearSilent
        outputActionDesc$ = "near-silent; normalization skipped"
    else
        normFactor = normalize_target / preOutputPeak
        Scale peak: normalize_target
        outputActionDesc$ = "normalized to " + fixed$(normalize_target, 3)
    endif
elsif output_mode = 3
    if isNearSilent
        outputActionDesc$ = "near-silent; attenuation not needed"
    elsif preOutputPeak > normalize_target
        normFactor = normalize_target / preOutputPeak
        Scale peak: normalize_target
        outputActionDesc$ = "attenuated to " + fixed$(normalize_target, 3)
    else
        outputActionDesc$ = "below target; no attenuation"
    endif
else
    if isNearSilent
        outputActionDesc$ = "near-silent; legacy normalization skipped"
    else
        normFactor = 0.95 / preOutputPeak
        Scale peak: 0.95
        outputActionDesc$ = "legacy normalized to 0.95"
    endif
endif

# === Final stats + difference signal (output - input) ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
outputRms = Get root-mean-square: 0, 0

Copy: originalName$ + "_vsg_difference"
diffSound = selected("Sound")
Formula: "self - object[" + string$(original) + ", row, col]"
diffPeak = Get absolute extremum: 0, 0, "None"
diffRms = Get root-mean-square: 0, 0

if inputRms > 0 and outputRms > 0
    rmsChange$ = fixed$(20 * log10(outputRms / inputRms), 2) + " dB"
else
    rmsChange$ = "n/a"
endif
if inputRms > 0 and diffRms > 0
    diffRel$ = fixed$(20 * log10(diffRms / inputRms), 1) + " dB re input RMS"
elsif diffRms = 0
    diffRel$ = "exactly zero (output = input)"
else
    diffRel$ = "n/a"
endif
# Layer relative to the ORIGINAL's own energy in the harmonic band:
# how much the addition stands out where it is actually added.
selectObject: original
Filter (pass Hann band): harmLowEdge, 0, harmEdgeSmooth
hbTmp = selected("Sound")
Filter (pass Hann band): 0, harmonic_lowpass, harmTopSmooth
hbOrig = selected("Sound")
hbOrigRms = Get root-mean-square: 0, 0
removeObject: hbTmp, hbOrig
if hbOrigRms > 0 and layerRms > 0 and harmonic_level <> 0
    bandRel$ = fixed$(20 * log10(abs(harmonic_level) * layerRms / hbOrigRms), 1) + " dB re input in " + fixed$(harmLowEdge, 0) + "-" + fixed$(harmonic_lowpass, 0) + " Hz"
else
    bandRel$ = "n/a"
endif
if bassRms > 0 and layerRms > 0 and harmonic_level <> 0
    layerRel$ = fixed$(20 * log10(abs(harmonic_level) * layerRms / bassRms), 1) + " dB re bass-band RMS"
else
    layerRel$ = "n/a (no layer)"
endif

# ============================================================
# VISUALIZATION  (8-inch page, suite standard)
# ============================================================

if draw_visualization
    pageHeight = 8.0
    vizName$ = replace$(originalName$, "_", "\_ ", 0)
    Erase all
    Line width: 1
    Colour: "Black"
    Solid line

    # ---------------- TITLE BAR ----------------
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Virtual Subharmonic Generator v0.7.1##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  y = direct + " + fixed$(harmonic_level, 2) + " x layer"
        ... + "  |  direct: " + directShort$
        ... + "  |  M/S: " + msStr$

    # ---------------- PANEL A: SIGNAL FLOW ----------------
    Font size: 7
    Select inner viewport: 0.60, 3.85, 0.95, 3.90
    Axes: 0, 1, 0, 6
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 6

    # Input
    Paint rectangle: "{0.85, 0.85, 0.88}", 0.30, 0.70, 5.25, 5.75
    Colour: "Black"
    Text: 0.50, "centre", 5.58, "half", "INPUT"
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.50, "centre", 5.38, "half", string$(numChannels) + " ch"

    # Split arrows
    Select inner viewport: 0.60, 3.85, 0.95, 3.90
    Axes: 0, 1, 0, 6
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.40, 5.25, 0.22, 4.75
    Draw arrow: 0.60, 5.25, 0.76, 4.95

    # Direct path (left column, spans the layer stages)
    if original_low_cut > 0
        Paint rectangle: "{0.92, 0.78, 0.70}", 0.05, 0.40, 1.95, 4.70
    else
        Paint rectangle: "{0.80, 0.90, 0.80}", 0.05, 0.40, 1.95, 4.70
    endif
    Colour: "Black"
    Text: 0.225, "centre", 3.55, "half", "DIRECT"
    Colour: "{0.30, 0.30, 0.30}"
    if original_low_cut > 0
        Text: 0.225, "centre", 3.25, "half", "low-cut"
        Text: 0.225, "centre", 3.00, "half", fixed$(original_low_cut, 0) + " Hz"
    else
        Text: 0.225, "centre", 3.25, "half", "untouched"
        Text: 0.225, "centre", 3.00, "half", "(identity)"
    endif

    # Layer stages (right column)
    Paint rectangle: "{0.85, 0.70, 0.55}", 0.52, 0.98, 4.30, 4.90
    Colour: "Black"
    Text: 0.75, "centre", 4.72, "half", "BASS BAND"
    Colour: "{0.40, 0.20, 0.10}"
    Text: 0.75, "centre", 4.48, "half", fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
    Paint rectangle: "{0.85, 0.70, 0.55}", 0.52, 0.98, 3.30, 3.90
    Colour: "Black"
    Text: 0.75, "centre", 3.72, "half", "tanh RESIDUAL x " + string$(nSub)
    Colour: "{0.40, 0.20, 0.10}"
    if nSub > 1
        Text: 0.75, "centre", 3.48, "half", "sub-bands, equalised, drive " + fixed$(drive, 1)
    else
        Text: 0.75, "centre", 3.48, "half", "drive " + fixed$(drive, 1) + ", linear removed"
    endif
    Paint rectangle: "{0.85, 0.70, 0.55}", 0.52, 0.98, 2.30, 2.90
    Colour: "Black"
    Text: 0.75, "centre", 2.72, "half", "HARMONIC BAND"
    Colour: "{0.40, 0.20, 0.10}"
    Text: 0.75, "centre", 2.48, "half", fixed$(harmLowEdge, 0) + "-" + fixed$(harmonic_lowpass, 0) + " Hz, x " + fixed$(harmonic_level, 2)

    Select inner viewport: 0.60, 3.85, 0.95, 3.90
    Axes: 0, 1, 0, 6
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.75, 4.30, 0.75, 3.92
    Draw arrow: 0.75, 3.30, 0.75, 2.92
    Draw arrow: 0.75, 2.30, 0.56, 1.55
    Draw arrow: 0.225, 1.95, 0.44, 1.55

    # Sum
    Paint rectangle: "{0.65, 0.65, 0.85}", 0.30, 0.70, 1.00, 1.50
    Colour: "Black"
    Text: 0.50, "centre", 1.33, "half", "SUM"
    Colour: "{0.15, 0.15, 0.40}"
    if msActive
        Text: 0.50, "centre", 1.13, "half", "then M/S x " + fixed$(stereo_width, 2)
    else
        Text: 0.50, "centre", 1.13, "half", "stereo untouched"
    endif
    Select inner viewport: 0.60, 3.85, 0.95, 3.90
    Axes: 0, 1, 0, 6
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 1.00, 0.50, 0.75
    Paint rectangle: "{0.65, 0.85, 0.75}", 0.30, 0.70, 0.20, 0.70
    Colour: "Black"
    Text: 0.50, "centre", 0.53, "half", "OUTPUT"
    Colour: "{0.15, 0.40, 0.30}"
    Text: 0.50, "centre", 0.33, "half", outputModeShort$

    Select inner viewport: 0.60, 3.85, 0.95, 3.90
    Axes: 0, 1, 0, 6
    Colour: "Black"
    Draw inner box

    # ---------------- PANEL B: PARAMETER REPORT ----------------
    Font size: 6
    Select inner viewport: 4.45, 7.70, 0.95, 3.90
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.94, "half", "##Direct path##"
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.87, "half", directStr$
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.78, "half", "##Enhancement layer##"
    Colour: "{0.85, 0.55, 0.20}"
    Text: 0.10, "left", 0.71, "half", "Bass " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz  |  Drive " + fixed$(drive, 2) + "  |  ref: " + bassRefShort$
    Text: 0.10, "left", 0.64, "half", "Harmonic band " + fixed$(harmLowEdge, 0) + "-" + fixed$(harmonic_lowpass, 0) + " Hz  |  gain " + fixed$(harmonic_level, 2)
    Text: 0.10, "left", 0.57, "half", "Generator: " + genStr$ + "  |  stereo layer: " + stereoLayerStr$
    Text: 0.10, "left", 0.50, "half", "Layer: " + layerRel$
    Text: 0.10, "left", 0.43, "half", "In band: " + bandRel$
    Colour: "{0.30, 0.30, 0.30}"
    Colour: "{0.30, 0.30, 0.78}"
    Text: 0.10, "left", 0.36, "half", "M/S: " + msStr$ + "  |  Side low-cut: " + monoStr$
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.29, "half", "##Measured##"
    Colour: "{0.30, 0.45, 0.68}"
    Text: 0.10, "left", 0.23, "half", "RMS change: " + rmsChange$ + "  |  output: " + outputActionDesc$
    Text: 0.10, "left", 0.17, "half", "Difference: " + diffRel$
    Text: 0.10, "left", 0.11, "half", "Peak in " + fixed$(inputPeak, 3) + "  ->  out " + fixed$(finalPeak, 3)
    Select inner viewport: 4.45, 7.70, 0.95, 3.90
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # Panel titles
    Font size: 7
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Colour: "Black"
    Text: 2.225, "centre", 7.20, "half", "Signal flow (parallel branches)"
    Text: 6.075, "centre", 7.20, "half", "Parameter report"

    # ---------------- PANEL C: LONG-TERM SPECTRUM ----------------
    # Mono sums of input, output and difference; 5 Hz Ltas read on
    # log-spaced bands 20-2000 Hz.
    # Per-channel Ltas averaged in the energy domain (a mono sum would
    # cancel out-of-phase content and misreport the energy).
    @energyLtas: original
    ltIn = energyLtas.ltas
    @energyLtas: result
    ltOut = energyLtas.ltas
    @energyLtas: diffSound
    ltDiff = energyLtas.ltas

    specLo = 20
    specHi = min(2000, nyquist)
    nBands = 140
    specMax = -1000
    for ib to nBands
        fLo = specLo * (specHi / specLo) ^ ((ib - 1) / nBands)
        fHi = specLo * (specHi / specLo) ^ (ib / nBands)
        fC = sqrt(fLo * fHi)
        specF[ib] = fC
        for il to 3
            if il = 1
                selectObject: ltIn
            elsif il = 2
                selectObject: ltOut
            else
                selectObject: ltDiff
            endif
            if fHi - fLo >= 10
                v = Get mean: fLo, fHi, "energy"
            else
                v = Get value at frequency: fC, "linear"
            endif
            if v = undefined
                v = -300
            endif
            spec[il, ib] = v
            if il < 3 and v > specMax
                specMax = v
            endif
        endfor
    endfor
    if specMax < -200
        specMax = 0
    endif
    specTop = ceiling((specMax + 5) / 10) * 10
    specBot = specTop - 70

    Font size: 7
    Select inner viewport: 0.60, 7.70, 4.45, 5.75
    Axes: log10(specLo), log10(specHi), specBot, specTop
    Paint rectangle: "{0.97, 0.97, 0.97}", log10(specLo), log10(specHi), specBot, specTop
    # Band shading: bass band and harmonic band
    Paint rectangle: "{0.95, 0.90, 0.84}", log10(max(specLo, bass_low_freq)), log10(min(specHi, bass_high_freq)), specBot, specTop
    if harmLowEdge < specHi
        Paint rectangle: "{0.93, 0.93, 0.86}", log10(harmLowEdge), log10(min(specHi, harmonic_lowpass)), specBot, specTop
    endif

    Select inner viewport: 0.60, 7.70, 4.45, 5.75
    Axes: log10(specLo), log10(specHi), specBot, specTop
    for il to 3
        if il = 1
            Colour: "{0.60, 0.60, 0.60}"
            Line width: 2
        elsif il = 2
            Colour: "{0.55, 0.30, 0.65}"
            Line width: 1
        else
            Colour: "{0.85, 0.50, 0.15}"
            Line width: 1
        endif
        for ib from 2 to nBands
            y1 = max(specBot, min(specTop, spec[il, ib - 1]))
            y2 = max(specBot, min(specTop, spec[il, ib]))
            Draw line: log10(specF[ib - 1]), y1, log10(specF[ib]), y2
        endfor
    endfor
    Line width: 1

    # Marks first (fresh frame), box after: Draw inner box moves the
    # drawing frame to the outer viewport.
    Font size: 6
    Select inner viewport: 0.60, 7.70, 4.45, 5.75
    Axes: log10(specLo), log10(specHi), specBot, specTop
    Colour: "Black"
    One mark bottom: log10(20), "no", "yes", "no", "20"
    One mark bottom: log10(50), "no", "yes", "no", "50"
    One mark bottom: log10(100), "no", "yes", "no", "100"
    One mark bottom: log10(200), "no", "yes", "no", "200"
    One mark bottom: log10(500), "no", "yes", "no", "500"
    One mark bottom: log10(1000), "no", "yes", "no", "1000"
    if specHi >= 2000
        One mark bottom: log10(2000), "no", "yes", "no", "2000"
    endif
    Marks left every: 1, 20, "yes", "yes", "no"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 4.45, 5.75
    Axes: log10(specLo), log10(specHi), specBot, specTop
    Draw inner box
    Text top: "no", "Long-term spectrum, channel energy average  (grey = input, purple = output, orange = difference)"
    Text left: "yes", "dB"

    removeObject: ltIn, ltOut, ltDiff

    # ---------------- PANEL D: DIFFERENCE WAVEFORM ----------------
    # Difference (output - input), channel 1, drawn on the INPUT's
    # amplitude scale so its true size is visible.
    Font size: 7
    Select inner viewport: 0.60, 7.70, 6.20, 6.95
    selectObject: original
    resultStart = xminOrig
    resultEnd = xmaxOrig
    ampViz = max(inputPeak, diffPeak)
    if ampViz < 0.001
        ampViz = 0.001
    endif
    ampViz = ampViz * 1.1
    Axes: resultStart, resultEnd, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", resultStart, resultEnd, -ampViz, ampViz

    selectObject: original
    Extract one channel: 1
    vIn = selected("Sound")
    Select inner viewport: 0.60, 7.70, 6.20, 6.95
    Colour: "{0.75, 0.75, 0.75}"
    Draw: resultStart, resultEnd, -ampViz, ampViz, "no", "Curve"
    removeObject: vIn
    selectObject: diffSound
    Extract one channel: 1
    vD = selected("Sound")
    Select inner viewport: 0.60, 7.70, 6.20, 6.95
    Colour: "{0.85, 0.50, 0.15}"
    Draw: resultStart, resultEnd, -ampViz, ampViz, "no", "Curve"
    removeObject: vD

    Select inner viewport: 0.60, 7.70, 6.20, 6.95
    Axes: resultStart, resultEnd, -ampViz, ampViz
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Difference output - input, ch 1  (orange), over input  (grey), same scale"
    Text left: "no", "Amp"

    # ---------------- PANEL E: SUMMARY BAR ----------------
    Font size: 6
    Select inner viewport: 0.60, 7.70, 7.15, 7.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.78, "half",
        ... "##" + presetName$ + "##  " + vizName$
        ... + "  |  " + fixed$(finalDur, 2) + " s, " + string$(numChannels) + " ch"
        ... + "  |  direct: " + directShort$
        ... + "  |  layer: " + layerRel$
    Text: 0.02, "left", 0.50, "half",
        ... "Bass " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
        ... + "  |  Drive " + fixed$(drive, 2) + " (" + bassRefShort$ + ")"
        ... + "  |  harmonic band " + fixed$(harmLowEdge, 0) + "-" + fixed$(harmonic_lowpass, 0) + " Hz"
        ... + "  |  gain " + fixed$(harmonic_level, 2)
    Text: 0.02, "left", 0.22, "half",
        ... "Output: " + outputModeShort$
        ... + "  |  RMS change " + rmsChange$
        ... + "  |  peak " + fixed$(inputPeak, 3) + " -> " + fixed$(finalPeak, 3)
        ... + "  |  M/S: " + msStr$
    Select inner viewport: 0.60, 7.70, 7.15, 7.85
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Select outer viewport: 0, 8, 0, pageHeight
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
selectObject: result
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s, ", numChannels, " ch"
appendInfoLine: "Layer level: ", layerRel$
appendInfoLine: "Layer in its own band: ", bandRel$
appendInfoLine: "Pre-output peak: ", fixed$(preOutputPeak, 4)
appendInfoLine: "Output action: ", outputActionDesc$
appendInfoLine: "Output scale factor applied: ", fixed$(normFactor, 4)
appendInfoLine: "Peak: ", fixed$(inputPeak, 4), " in -> ", fixed$(finalPeak, 4), " out"
appendInfoLine: "RMS change: ", rmsChange$
appendInfoLine: "Difference (output - input): peak ", fixed$(diffPeak, 6), ", ", diffRel$

if keep_difference
    appendInfoLine: "Kept difference object: ", originalName$, "_vsg_difference"
else
    removeObject: diffSound
endif

if play_result
    selectObject: result
    Play
endif

selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

# Enhancement layer from a (multichannel) bass-band Sound.
# Uses globals: nSub, subHi[], xoW[], subGain[], k, refScale,
# linkedActive, harmLowEdge, harmEdgeSmooth, harmonic_lowpass,
# harmTopSmooth. Sub-bands are split by successive subtraction, so
# they sum exactly to the input band; each is shaped on its own, so
# notes in different sub-bands cannot intermodulate.
procedure buildLayer: .bb
    selectObject: .bb
    .nch = Get number of channels
    if linkedActive and .nch > 1
        Convert to mono
    else
        Copy: "vsg_bb"
    endif
    .rest = selected("Sound")
    Copy: "vsg_res"
    .res = selected("Sound")
    Formula: "0"
    for .i to nSub
        if .i < nSub
            selectObject: .rest
            Filter (pass Hann band): 0, subHi[.i], xoW[.i]
            .sub = selected("Sound")
            selectObject: .rest
            Formula: "self - object[" + string$(.sub) + ", row, col]"
        else
            .sub = .rest
        endif
        selectObject: .sub
        .kk = k * subDrive[.i]
        Formula: "(tanh(self * " + string$(.kk) + ") - self * " + string$(.kk) + ") * " + string$(subGain[.i] / (refScale * subDrive[.i]))
        selectObject: .res
        Formula: "self + object[" + string$(.sub) + ", row, col]"
        removeObject: .sub
    endfor
    selectObject: .res
    Filter (pass Hann band): harmLowEdge, 0, harmEdgeSmooth
    .tmp = selected("Sound")
    Filter (pass Hann band): 0, harmonic_lowpass, harmTopSmooth
    .lay = selected("Sound")
    removeObject: .tmp, .res
    if linkedActive and .nch > 1
        # Spread the shared layer by each channel's bass RMS relative
        # to the mono sum, so harmonic level ratios follow the
        # fundamentals' ratios instead of being exaggerated by tanh.
        selectObject: .bb
        Convert to mono
        .bm = selected("Sound")
        .rm = Get root-mean-square: 0, 0
        removeObject: .bm
        .w$ = "0"
        for .c to .nch
            selectObject: .bb
            Extract one channel: .c
            .bc = selected("Sound")
            .rc = Get root-mean-square: 0, 0
            removeObject: .bc
            if .rm > 0
                .wc = .rc / .rm
            else
                .wc = 1
            endif
            .w$ = "if row = " + string$(.c) + " then " + string$(.wc) + " else " + .w$ + " fi"
        endfor
        selectObject: .bb
        Copy: "vsg_layer"
        .layer = selected("Sound")
        Formula: "object[" + string$(.lay) + ", 1, col] * (" + .w$ + ")"
        removeObject: .lay
    else
        .layer = .lay
    endif
endproc

# Gated level of a bass-band Sound: energy mean of 10 ms Intensity
# frames within 30 dB of the loudest frame, loudest channel, returned
# as a sine-equivalent peak (RMS * sqrt 2).
procedure gatedSinePeak: .snd
    selectObject: .snd
    .nch = Get number of channels
    .dur = Get total duration
    .level = 0
    for .c to .nch
        selectObject: .snd
        Extract one channel: .c
        .ch = selected("Sound")
        if .dur >= 0.2
            To Intensity: 40, 0.01, "no"
            .int = selected("Intensity")
            .nf = Get number of frames
            .mx = Get maximum: 0, 0, "None"
            .acc = 0
            .n = 0
            if .mx <> undefined
                for .j to .nf
                    .v = Get value in frame: .j
                    if .v <> undefined
                        if .v > .mx - 30
                            .acc = .acc + 10 ^ (.v / 10)
                            .n = .n + 1
                        endif
                    endif
                endfor
            endif
            if .n > 0
                .rms = 2e-5 * sqrt(.acc / .n)
            else
                .rms = 0
            endif
            removeObject: .int
        else
            .rms = Get root-mean-square: 0, 0
        endif
        removeObject: .ch
        .level = max(.level, .rms * sqrt(2))
    endfor
endproc

# Long-term spectrum averaged over channels in the energy domain.
procedure energyLtas: .snd
    selectObject: .snd
    .nch = Get number of channels
    for .c to .nch
        selectObject: .snd
        Extract one channel: .c
        .ch = selected("Sound")
        To Ltas: 5
        .lt = selected("Ltas")
        removeObject: .ch
        if .c = 1
            .ltas = .lt
            Formula: "10 ^ (self / 10)"
        else
            selectObject: .ltas
            Formula: "self + 10 ^ (object[" + string$(.lt) + ", col] / 10)"
            removeObject: .lt
        endif
    endfor
    selectObject: .ltas
    Formula: "10 * log10(max(self / " + string$(.nch) + ", 1e-30))"
endproc
