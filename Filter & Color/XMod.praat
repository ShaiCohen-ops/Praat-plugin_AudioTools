# ============================================================
# Praat AudioTools - XMod.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-modulation effects: Ring Modulation, bipolar Amplitude
#   Modulation, and Rhythmic/Envelope Gating. Oscillator modulators
#   or a second Sound can be used. Carrier channel count, sample rate,
#   duration, and start time are preserved.
#
# Notes:
#   - Ring depth 0..1 crossfades dry -> ring; values >1 scale pure ring.
#   - AM depth 0..1 crossfades dry -> unipolar AM. For a second Sound,
#     the modulator is peak-normalized only as a CONTROL signal; its
#     source object is never modified.
#   - Gate attack and release are independent one-pole time constants.
#     A second Sound drives the gate from its rectified peak-normalized
#     envelope. A shorter second Sound is zero-padded; a longer one is
#     trimmed to the carrier duration.
#   - Safety_peak attenuates only when needed; it never boosts.
#
# Changelog v1.2 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v1.1:
#   - Fixed AM depth=0 so it is an exact dry bypass (v1.0 was -6 dB).
#   - Removed unconditional Scale peak normalization.
#   - Preserved arbitrary carrier channel count and start time.
#   - Fixed Second Sound path (v1.0 contained invalid Praat syntax).
#   - Added sample-rate conversion and explicit trim/zero-pad handling
#     for external modulators.
#   - Implemented independent gate attack/release instead of one
#     symmetric spectral smoothing value.
#   - External gate now follows rectified modulator amplitude.
#   - Renamed Sidechain preset to Sidechain-like Pump (oscillator based).
#   - Updated visualization to AudioTools house style.
# ============================================================

form XMod - Cross Modulation v1.2
    optionmenu Preset: 1
        option Custom
        option Ring Mod - Metallic
        option Ring Mod - Deep
        option AM - Radio Style
        option AM - Tremolo
        option Gate - Fast Stutter
        option Gate - Slow Pulse
        option Gate - Helicopter
        option Sidechain-like Pump
    comment === Modulation Type ===
    optionmenu Mod_type: 1
        option Ring Modulation
        option Amplitude Modulation (AM)
        option Rhythmic Gate
    comment === Modulator Source ===
    optionmenu Mod_source: 1
        option Sine Oscillator
        option Square Oscillator
        option Triangle Oscillator
        option Sawtooth Oscillator
        option Second Sound (select 2 sounds)
    comment === Oscillator / Depth ===
    positive Mod_frequency_(Hz) 10
    real Mod_depth 1.0
    comment (AM/Gate 0..1; Ring 0..1 dry-to-ring, >1 scales pure ring)
    comment === Gate Envelope ===
    positive Attack_(ms) 5
    positive Release_(ms) 5
    real Duty_cycle 0.5
    comment (0..1; used by Square oscillator)
    comment === Output ===
    real Safety_peak 0.99
    comment (0 disables; otherwise attenuate only when peak exceeds this value)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    mod_type = 1
    mod_source = 1
    mod_frequency = 440
    mod_depth = 1.0
    presetName$ = "RingMetallic"
elsif preset = 3
    mod_type = 1
    mod_source = 1
    mod_frequency = 80
    mod_depth = 1.0
    presetName$ = "RingDeep"
elsif preset = 4
    mod_type = 2
    mod_source = 1
    mod_frequency = 1000
    mod_depth = 0.8
    presetName$ = "AMRadio"
elsif preset = 5
    mod_type = 2
    mod_source = 1
    mod_frequency = 6
    mod_depth = 0.7
    presetName$ = "Tremolo"
elsif preset = 6
    mod_type = 3
    mod_source = 2
    mod_frequency = 10
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 2
    release = 2
    presetName$ = "FastStutter"
elsif preset = 7
    mod_type = 3
    mod_source = 2
    mod_frequency = 2
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 10
    release = 10
    presetName$ = "SlowPulse"
elsif preset = 8
    mod_type = 3
    mod_source = 2
    mod_frequency = 12.5
    mod_depth = 1.0
    duty_cycle = 0.5
    attack = 1
    release = 1
    presetName$ = "Helicopter"
elsif preset = 9
    mod_type = 3
    mod_source = 2
    mod_frequency = 2
    mod_depth = 0.9
    duty_cycle = 0.3
    attack = 5
    release = 80
    presetName$ = "SidechainLikePump"
else
    presetName$ = "Custom"
endif

modTypeNames$[1] = "Ring Modulation"
modTypeNames$[2] = "Amplitude Modulation"
modTypeNames$[3] = "Rhythmic Gate"
modSourceNames$[1] = "Sine"
modSourceNames$[2] = "Square"
modSourceNames$[3] = "Triangle"
modSourceNames$[4] = "Sawtooth"
modSourceNames$[5] = "Second Sound"

# ============================================================
# INPUT VALIDATION
# ============================================================
numSounds = numberOfSelected("Sound")
if mod_source = 5
    if numSounds <> 2
        exitScript: "Please select exactly 2 Sound objects for Second Sound modulation."
    endif
    carrierID = selected("Sound", 1)
    modulatorSoundID = selected("Sound", 2)
else
    if numSounds <> 1
        exitScript: "Please select exactly one Sound object."
    endif
    carrierID = selected("Sound")
    modulatorSoundID = 0
endif

selectObject: carrierID
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
carrierXmin = Get start time
nCarrier = Get number of samples
nyquist = sampleRate / 2

if duration < 0.01
    exitScript: "Sound too short (minimum 0.01 s)."
endif

if mod_depth < 0
    mod_depth = 0
endif
if mod_type <> 1 and mod_depth > 1
    mod_depth = 1
endif
if duty_cycle < 0
    duty_cycle = 0
endif
if duty_cycle > 1
    duty_cycle = 1
endif
if safety_peak > 1
    safety_peak = 1
endif
if safety_peak < 0
    safety_peak = 0
endif
if mod_frequency >= nyquist
    mod_frequency = max(0.01, nyquist * 0.95)
endif

attackSec = attack / 1000
releaseSec = release / 1000
attackAlpha = exp(-1 / max(attackSec * sampleRate, 1e-12))
releaseAlpha = exp(-1 / max(releaseSec * sampleRate, 1e-12))

writeInfoLine: "=== XMod - Cross Modulation v1.2 ==="
appendInfoLine: "Carrier: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s   Start: ", fixed$(carrierXmin, 3), " s"
appendInfoLine: "Channels: ", numChannels, "   SR: ", round(sampleRate), " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Type: ", modTypeNames$[mod_type]
appendInfoLine: "Source: ", modSourceNames$[mod_source]
appendInfoLine: "Depth: ", fixed$(mod_depth, 3)
appendInfoLine: ""

startTime = stopwatch

# ============================================================
# CREATE / PREPARE MODULATOR ON CARRIER SAMPLE GRID
# ============================================================
if mod_source = 5
    selectObject: modulatorSoundID
    modName$ = selected$("Sound")
    modDurOrig = Get total duration
    modSR = Get sampling frequency
    modCh = Get number of channels
    modXmin = Get start time

    if modCh > 1
        modRaw = Convert to mono
    else
        modRaw = Copy: "xmod_modraw"
    endif

    selectObject: modRaw
    if modXmin <> 0
        Shift times by: -modXmin
    endif
    if modSR <> sampleRate
        modResamp = Resample: sampleRate, 50
        removeObject: modRaw
        modRaw = modResamp
    endif

    selectObject: modRaw
    nMod = Get number of samples
    modDurWork = Get total duration

    modulatorMono = Create Sound from formula: "xmod_modulator", 1, 0, duration, sampleRate,
        ... "if col <= 'nMod:0' then object['modRaw:0', 1, col] else 0 fi"

    selectObject: modulatorMono
    modPeak = Get absolute extremum: 0, 0, "None"
    if modPeak < 1e-12
        modPeak = 1
    endif

    appendInfoLine: "External modulator: ", modName$
    appendInfoLine: "  Original duration: ", fixed$(modDurOrig, 3), " s"
    if modDurOrig < duration
        appendInfoLine: "  Shorter than carrier: zero-padded after its end."
    elsif modDurOrig > duration
        appendInfoLine: "  Longer than carrier: trimmed to carrier duration."
    endif
    if modSR <> sampleRate
        appendInfoLine: "  Resampled: ", round(modSR), " -> ", round(sampleRate), " Hz"
    endif

    removeObject: modRaw
else
    freqStr$ = fixed$(mod_frequency, 12)
    dutyStr$ = fixed$(duty_cycle, 12)
    if mod_source = 1
        modulatorMono = Create Sound from formula: "xmod_modulator", 1, 0, duration, sampleRate,
            ... "sin(2*pi*" + freqStr$ + "*x)"
    elsif mod_source = 2
        modulatorMono = Create Sound from formula: "xmod_modulator", 1, 0, duration, sampleRate,
            ... "if ((" + freqStr$ + "*x) mod 1) < " + dutyStr$ + " then 1 else -1 fi"
    elsif mod_source = 3
        modulatorMono = Create Sound from formula: "xmod_modulator", 1, 0, duration, sampleRate,
            ... "if ((" + freqStr$ + "*x) mod 1) < 0.5 then 4*((" + freqStr$ + "*x) mod 1)-1 else 3-4*((" + freqStr$ + "*x) mod 1) fi"
    else
        modulatorMono = Create Sound from formula: "xmod_modulator", 1, 0, duration, sampleRate,
            ... "2*((" + freqStr$ + "*x) mod 1)-1"
    endif
    modPeak = 1
    appendInfoLine: "Oscillator: ", modSourceNames$[mod_source], " @ ", fixed$(mod_frequency, 3), " Hz"
endif

# ============================================================
# OUTPUT: COPY CARRIER SO CHANNELS + TIME DOMAIN ARE PRESERVED
# ============================================================
selectObject: carrierID
outputSound = Copy: originalName$ + "_xmod_" + presetName$

modID$ = string$(modulatorMono)
depthStr$ = fixed$(mod_depth, 12)
modPeakStr$ = fixed$(modPeak, 12)

# ============================================================
# APPLY MODULATION
# ============================================================
if mod_type = 1
    # Ring modulation. 0..1 = dry-to-ring crossfade; >1 = pure ring gain.
    selectObject: outputSound
    if mod_depth <= 1
        Formula: "self * ((1 - " + depthStr$ + ") + " + depthStr$ + " * object[" + modID$ + ", 1, col])"
    else
        Formula: "self * " + depthStr$ + " * object[" + modID$ + ", 1, col]"
    endif

elsif mod_type = 2
    # Bipolar modulator -> unipolar amplitude control. Depth 0 is exact dry.
    # External modulators are normalized only as a control signal.
    selectObject: outputSound
    Formula: "self * ((1 - " + depthStr$ + ") + " + depthStr$ + " * (1 + object[" + modID$ + ", 1, col] / " + modPeakStr$ + ") / 2)"

else
    # Gate target. Oscillators are mapped [-1,1] -> [0,1].
    # External Sound uses rectified peak-normalized amplitude.
    if mod_source = 5
        gateTarget = Create Sound from formula: "xmod_gate_target", 1, 0, duration, sampleRate,
            ... "min(1, abs(object['modulatorMono:0', 1, col]) / 'modPeak:12')"
    else
        gateTarget = Create Sound from formula: "xmod_gate_target", 1, 0, duration, sampleRate,
            ... "0.5 * (object['modulatorMono:0', 1, col] + 1)"
    endif

    # Independent attack/release smoothing in the sample domain.
    gateEnvelope = Create Sound from formula: "xmod_gate_envelope", 1, 0, duration, sampleRate, "0"
    targetID$ = string$(gateTarget)
    attackAlphaStr$ = fixed$(attackAlpha, 15)
    releaseAlphaStr$ = fixed$(releaseAlpha, 15)
    selectObject: gateEnvelope
    Formula: "if col = 1 then object[" + targetID$ + ", 1, col] else if object[" + targetID$ + ", 1, col] > self[col-1] then " + attackAlphaStr$ + " * self[col-1] + (1 - " + attackAlphaStr$ + ") * object[" + targetID$ + ", 1, col] else " + releaseAlphaStr$ + " * self[col-1] + (1 - " + releaseAlphaStr$ + ") * object[" + targetID$ + ", 1, col] fi fi"

    envID$ = string$(gateEnvelope)
    selectObject: outputSound
    Formula: "self * ((1 - " + depthStr$ + ") + " + depthStr$ + " * object[" + envID$ + ", 1, col])"
endif

# ============================================================
# SAFETY ATTENUATION ONLY
# ============================================================
selectObject: outputSound
peakOut = Get absolute extremum: 0, 0, "None"
if mod_depth > 0 and safety_peak > 0 and peakOut > safety_peak
    Scale peak: safety_peak
    appendInfoLine: "Safety attenuation: peak ", fixed$(peakOut, 4), " -> ", fixed$(safety_peak, 4)
endif
selectObject: outputSound
peakFinal = Get absolute extremum: 0, 0, "None"

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_visualization
    selectObject: carrierID
    if numChannels > 1
        vizIn = Convert to mono
    else
        vizIn = Copy: "xmod_vizin"
    endif
    selectObject: outputSound
    if numChannels > 1
        vizOut = Convert to mono
    else
        vizOut = Copy: "xmod_vizout"
    endif

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    # Title
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##XMod - Cross Modulation v1.2##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.72, 1.48
    Select inner viewport: 0.55, 7.70, 0.80, 1.40
    selectObject: vizIn
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Output waveform
    Select outer viewport: 0, 8, 1.52, 2.28
    Select inner viewport: 0.55, 7.70, 1.60, 2.20
    selectObject: vizOut
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Modulator / gate envelope
    displayDur = min(duration, 0.6)
    Select outer viewport: 0, 8, 2.46, 3.58
    Select inner viewport: 0.55, 7.70, 2.54, 3.50
    Axes: 0, displayDur, -1.05, 1.05
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, displayDur, -1.05, 1.05
    Colour: "{0.55, 0.55, 0.55}"
    Draw line: 0, 0, displayDur, 0
    selectObject: modulatorMono
    Colour: "{0.45, 0.40, 0.70}"
    Draw: 0, displayDur, -1, 1, "no", "Curve"
    if mod_type = 3
        selectObject: gateEnvelope
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 2
        Draw: 0, displayDur, 0, 1.05, "no", "Curve"
        Line width: 1
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Control"
    Text bottom: "yes", "Time (s)"

    # Spectrogram pair
    maxDisplayHz = min(5000, nyquist)
    Select outer viewport: 0, 4, 3.76, 5.02
    Select inner viewport: 0.55, 3.82, 3.84, 4.94
    selectObject: vizIn
    To Spectrogram: 0.03, maxDisplayHz, 0.01, 20, "Gaussian"
    specIn = selected("Spectrogram")
    Paint: 0, 0, 0, maxDisplayHz, 100, "yes", 50, 6, 0, "no"
    removeObject: specIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input spectrum"

    Select outer viewport: 4, 8, 3.76, 5.02
    Select inner viewport: 4.28, 7.70, 3.84, 4.94
    selectObject: vizOut
    To Spectrogram: 0.03, maxDisplayHz, 0.01, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, maxDisplayHz, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output spectrum"

    # Summary
    Select outer viewport: 0, 8, 5.12, 5.97
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if mod_source = 5
        sourceDetail$ = "external Sound"
    else
        sourceDetail$ = fixed$(mod_frequency, 2) + " Hz"
    endif
    Text: 0.02, "left", 0.80, "half", "##Mode##  " + modTypeNames$[mod_type] + "   ##Source##  " + modSourceNames$[mod_source] + " (" + sourceDetail$ + ")"
    Text: 0.02, "left", 0.50, "half", "##Depth##  " + fixed$(mod_depth, 3) + "   ##Channels##  " + string$(numChannels) + "   ##SR##  " + fixed$(sampleRate, 0) + " Hz"
    if mod_type = 3
        Text: 0.02, "left", 0.18, "half", "##Gate##  attack " + fixed$(attack, 1) + " ms   release " + fixed$(release, 1) + " ms   duty " + fixed$(duty_cycle * 100, 0) + "%   peak " + fixed$(peakFinal, 4)
    else
        Text: 0.02, "left", 0.18, "half", "##Output##  peak " + fixed$(peakFinal, 4) + "   safety " + fixed$(safety_peak, 3) + "   time " + fixed$(processingTime, 3) + " s"
    endif
    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizIn, vizOut
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# CLEANUP / OUTPUT
# ============================================================
removeObject: modulatorMono
if mod_type = 3
    removeObject: gateTarget, gateEnvelope
endif

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", originalName$, "_xmod_", presetName$
appendInfoLine: "Peak: ", fixed$(peakFinal, 4)
appendInfoLine: "Processing time: ", fixed$(processingTime, 3), " s"
if mod_type = 3
    appendInfoLine: "Gate attack/release: ", fixed$(attack, 2), " / ", fixed$(release, 2), " ms"
endif

selectObject: outputSound
if play_result
    Play
endif
selectObject: outputSound