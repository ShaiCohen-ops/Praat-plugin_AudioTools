# ============================================================
# Praat AudioTools - Onset-Based Oscillator Bank
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Onset-triggered resonator bank. Detects onsets from Intensity-rise
#   candidates, refines their timing, extracts pitch, and synthesizes
#   harmonic bursts with attack/decay envelopes. Each valid-pitch onset
#   triggers a multi-partial oscillator
#   with detuning, brightness control, and waveshaping.
#
# Features:
#   - Intensity-based onset detection with configurable threshold
#   - Autocorrelation pitch extraction with value/mean/median fallbacks
#   - Harmonic oscillator bank (1-32 partials) with detuning
#   - Attack + exponential-decay envelopes with randomization
#   - Cubic waveshaping for brightness, with Nyquist-safe 3rd harmonic
#   - Velocity sensitivity (onset strength -> burst amplitude)
#   - Speed modes for faster processing
#   - Comprehensive visualization: onsets, valid pitches, bursts
#   - 6 presets from gentle to dense
#
# Categories: Resynthesis, Pitch-Based Effects, Creative Effects
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.3 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v2.2:
#   - Locally refines Intensity onset candidates with short RMS windows.
#   - Uses a 0-based mono analysis copy; restores the original start time.
#   - Preserves arbitrary channel counts (wet bank is identical per channel).
#   - Removes the fixed 500-onset limit.
#   - Pitch ceiling follows the working sample rate up to 4 kHz.
#   - Expands cubic waveshaping analytically and suppresses aliased 3rd harmonics.
#   - Peak safety only attenuates; it never boosts quiet output.
#   - Adds parameter clamps and correct stopwatch timing.
#
# Changelog v2.1:
#
#   PRAAT-SIDE POLISH (no audio change):
#     - Dropped 5 decorative `comment === ... ===` form rows
#       (PRESETS / Onset Detection / Oscillators / Performance /
#       Output). Form: 20 rows -> 15 rows. All optionmenus already
#       had colons.
#     - Title font 14 -> 12 in visualization (suite standard).
#     - Visualization rewritten from custom 5-panel layout to
#       suite 8x8 standard:
#         Title bar (suite light) + metadata subtitle
#         Panel A (left, headline): original waveform + onsets
#         Panel B (right, headline): processed output waveform
#         Panel C: detected pitches per onset
#         Panel D: onset velocities (with valid-pitch coloring)
#         Panel E: light-grey summary stats bar (suite standard)
#
#   SMALL FIXES (no audio change):
#     - Final selection: now selects the output Sound at end
#       (v2.0 selected the original sound, inconsistent with the
#       rest of the suite which ends on the generated output).
#     - Consolidated `numChan` (line 189 of v2.0) and `numChannels`
#       (line 447) into a single `numChan` variable. Both held the
#       same value (channel count of the original sound) and were
#       used in different sections; now there is one variable.
#
#   Audio output is bit-identical to v2.0 for any given input,
#   preset, and random seed state.
# ============================================================

form Onset-Based Oscillator Bank v2.3
    optionmenu Preset: 1
        option Custom
        option Gentle Resonance
        option Percussive Bells
        option Ethereal Pad
        option Metallic Shimmer
        option Natural Pluck
        option Dense Cluster
    positive Onset_threshold_(dB) 1.5
    positive Min_intensity_(dB) 35.0
    positive Min_interval_(s) 0.1
    boolean Velocity_sensitive 1
    integer Num_partials 12
    positive Partial_spread_(percent) 0.5
    positive Decay_(s) 1.5
    real Brightness 0.7
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 16 kHz)
    positive Tail_duration_(s) 2.0
    positive Fadeout_duration_(s) 0.5
    real Dry_wet_mix 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET DEFINITIONS
# ============================================================
attackBase = 0.005
attackRandom = 0.01
decayRandom = 0.5
ampRandom = 0.3
waveshapeAmt = 0.2
decayTime = decay

if preset = 2
    # Gentle Resonance
    onset_threshold = 2.0
    min_intensity = 35.0
    min_interval = 0.15
    num_partials = 8
    partial_spread = 0.3
    decayTime = 2.0
    brightness = 0.5
    dry_wet_mix = 0.7
    attackBase = 0.01
    waveshapeAmt = 0.1
    presetName$ = "GentleResonance"
elsif preset = 3
    # Percussive Bells
    onset_threshold = 1.5
    min_intensity = 40.0
    min_interval = 0.08
    num_partials = 15
    partial_spread = 0.8
    decayTime = 1.0
    brightness = 0.9
    dry_wet_mix = 1.0
    attackBase = 0.002
    waveshapeAmt = 0.3
    presetName$ = "PercussiveBells"
elsif preset = 4
    # Ethereal Pad
    onset_threshold = 2.5
    min_intensity = 30.0
    min_interval = 0.2
    num_partials = 20
    partial_spread = 0.2
    decayTime = 3.5
    brightness = 0.6
    dry_wet_mix = 0.8
    attackBase = 0.05
    waveshapeAmt = 0.15
    presetName$ = "EtherealPad"
elsif preset = 5
    # Metallic Shimmer
    onset_threshold = 1.2
    min_intensity = 35.0
    min_interval = 0.1
    num_partials = 18
    partial_spread = 1.0
    decayTime = 1.2
    brightness = 1.0
    dry_wet_mix = 1.0
    attackBase = 0.003
    waveshapeAmt = 0.4
    presetName$ = "MetallicShimmer"
elsif preset = 6
    # Natural Pluck
    onset_threshold = 1.5
    min_intensity = 35.0
    min_interval = 0.12
    num_partials = 6
    partial_spread = 0.4
    decayTime = 0.8
    brightness = 0.7
    dry_wet_mix = 0.9
    attackBase = 0.001
    waveshapeAmt = 0.15
    presetName$ = "NaturalPluck"
elsif preset = 7
    # Dense Cluster
    onset_threshold = 1.0
    min_intensity = 32.0
    min_interval = 0.05
    num_partials = 25
    partial_spread = 1.2
    decayTime = 1.8
    brightness = 0.8
    dry_wet_mix = 1.0
    attackBase = 0.008
    waveshapeAmt = 0.25
    presetName$ = "DenseCluster"
else
    presetName$ = "Custom"
endif

# Speed mode
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 16000
    speedStr$ = "Fast"
endif

timerReset = stopwatch

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
name$ = selected$("Sound")
totalDur = Get total duration
origSR = Get sampling frequency
origStart = Get start time
nOrigSamples = Get number of samples
numChan = Get number of channels

if totalDur < 0.1
    exitScript: "Sound too short (min 0.1s)."
endif

# Keep public parameters inside the documented/safe operating range.
if num_partials < 1
    num_partials = 1
elsif num_partials > 32
    num_partials = 32
endif
if brightness < 0
    brightness = 0
elsif brightness > 1
    brightness = 1
endif
if partial_spread > 5
    partial_spread = 5
endif
if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

writeInfoLine: "=== Onset-Based Oscillator Bank v2.3 ==="
appendInfoLine: "Input:    ", name$
appendInfoLine: "Preset:   ", presetName$
appendInfoLine: "Speed:    ", speedStr$
appendInfoLine: ""

# Optional downsampling
workingSound = sound
if targetSR > 0 and origSR > targetSR
    appendInfoLine: "[SPEED] Downsampling to ", targetSR, " Hz"
    selectObject: sound
    Resample: targetSR, 50
    workingSound = selected("Sound")
    workingSR = targetSR
else
    workingSR = origSR
endif

selectObject: workingSound
sampleRate = Get sampling frequency
nyquistFreq = sampleRate / 2

# Analysis is always mono and 0-based, so detected times do not depend
# on the original Sound object's xmin.
selectObject: workingSound
if numChan > 1
    analysisSound = Convert to mono
else
    analysisSound = Copy: "onset_analysis"
endif
selectObject: analysisSound
Shift times to: "start time", 0

pitchCeiling = min(4000, sampleRate / 4)
if pitchCeiling < 200
    pitchCeiling = 200
endif

# ============================================================
# ONSET DETECTION
# ============================================================
appendInfo: "Stage 1: Detecting onsets... "

selectObject: analysisSound
intensityObj = To Intensity: 50, 0, "yes"

selectObject: intensityObj
numFrames = Get number of frames

# At most one accepted onset per Intensity frame: no fixed event cap.
onset_times# = zero#(numFrames)
onset_velocities# = zero#(numFrames)
numOnsets = 0
lastOnset = -1

for iFrame from 3 to numFrames - 1
    selectObject: intensityObj
    frameTime = Get time from frame number: iFrame
    currInt = Get value in frame: iFrame
    prev2Int = Get value in frame: iFrame - 2
    
    if currInt <> undefined and prev2Int <> undefined
        intDiff = (currInt - prev2Int) / 2
        if intDiff > onset_threshold and currInt > min_intensity
            # The symmetric Intensity window sees sharp attacks early.
            # Refine each candidate by locating the strongest short-RMS rise.
            candidateTime = frameTime
            refinedTime = candidateTime
            bestRise = 0
            refineStart = max(0.005, candidateTime)
            refineEnd = min(totalDur - 0.005, candidateTime + 0.080)
            tref = refineStart
            while tref <= refineEnd
                selectObject: analysisSound
                rmsPre = Get root-mean-square: tref - 0.005, tref
                rmsPost = Get root-mean-square: tref, tref + 0.005
                riseScore = rmsPost - rmsPre
                if riseScore > bestRise
                    bestRise = riseScore
                    refinedTime = tref
                endif
                tref = tref + 0.002
            endwhile

            if refinedTime - lastOnset > min_interval
                numOnsets += 1
                onset_times#[numOnsets] = refinedTime

                # Velocity is a normalized Intensity-rise score.
                velocity = (intDiff - onset_threshold) / 10
                velocity = min(1, max(0.3, velocity))
                onset_velocities#[numOnsets] = velocity

                lastOnset = refinedTime
            endif
        endif
    endif
endfor

removeObject: intensityObj

if numOnsets = 0
    if workingSound <> sound
        removeObject: workingSound
    endif
    exitScript: "No onsets found. Try lowering threshold."
endif

appendInfoLine: numOnsets, " onsets"

# ============================================================
# PITCH EXTRACTION
# ============================================================
appendInfo: "Stage 2: Extracting pitches... "

onset_pitches# = zero#(numOnsets)

for onsetIdx from 1 to numOnsets
    onsetTime = onset_times#[onsetIdx]
    
    selectObject: analysisSound
    segStart = max(0, onsetTime - 0.02)
    segEnd = min(onsetTime + 0.12, totalDur)
    
    if segEnd - segStart > 0.03
        Extract part: segStart, segEnd, "rectangular", 1, "no"
        segment = selected("Sound")
        
        To Pitch (ac): 0, 50, 15, "no", 0.01, 0.5, 0.01, 0.2, 0.1, pitchCeiling
        pitchObj = selected("Pitch")
        
        relTime = onsetTime - segStart
        detectedPitch = Get value at time: relTime, "Hertz", "Linear"
        
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get mean: 0, 0, "Hertz"
        endif
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get quantile: 0, 0, 0.5, "Hertz"
        endif
        
        removeObject: segment, pitchObj
        
        # Store valid pitch
        if detectedPitch <> undefined and detectedPitch >= 50 and detectedPitch <= pitchCeiling
            onset_pitches#[onsetIdx] = detectedPitch
        else
            onset_pitches#[onsetIdx] = 0
        endif
    else
        onset_pitches#[onsetIdx] = 0
    endif
endfor

appendInfoLine: "done"

# ============================================================
# SYNTHESIZE OSCILLATOR BANK (OPTIMIZED)
# ============================================================
appendInfo: "Stage 3: Synthesizing bursts... "

# Add tail space for burst decay
totalDurWithTail = totalDur + tail_duration

wetSignal = Create Sound from formula: "wet", numChan, 0, totalDurWithTail, sampleRate, "0"

maxBurstDur = attackBase + attackRandom + (decayTime + decayRandom) * 4
maxBurstDur = min(maxBurstDur, 5)

validOnsets = 0

for onsetIdx from 1 to numOnsets
    detectedPitch = onset_pitches#[onsetIdx]
    
    if detectedPitch > 0
        validOnsets += 1
        onsetTime = onset_times#[onsetIdx]
        velocity = onset_velocities#[onsetIdx]
        
        # Apply velocity sensitivity
        if velocity_sensitive
            ampScale = velocity
        else
            ampScale = 1.0
        endif
        
        # Allow bursts to extend into tail
        burstEnd = min(onsetTime + maxBurstDur, totalDurWithTail)
        burstDur = burstEnd - onsetTime
        
        if burstDur > 0.01
            maxPartial = min(num_partials, floor(nyquistFreq * 0.9 / detectedPitch))
            
            # BUILD ALL PARTIALS IN ONE FORMULA (FAST!)
            formula$ = "0"
            
            for partialNum from 1 to maxPartial
                partialFreq = detectedPitch * partialNum * (1 + randomUniform(-0.01, 0.01) * partial_spread)
                
                if partialFreq < nyquistFreq * 0.95
                    attackTime = attackBase + randomUniform(0, attackRandom)
                    decayVal = decayTime + randomUniform(-decayRandom, decayRandom)
                    decayVal = max(decayVal, 0.05)
                    
                    ampVal = (0.1 / sqrt(partialNum)) * (brightness ^ (partialNum - 1)) * ampScale
                    ampVal = ampVal * (1 + randomUniform(-ampRandom, ampRandom))
                    
                    wsBlend = waveshapeAmt * brightness
                    ampClean = ampVal * (1 - wsBlend)
                    ampWS = ampVal * wsBlend

                    attStr$ = fixed$(attackTime, 6)
                    decStr$ = fixed$(decayVal, 6)
                    freqStr$ = fixed$(partialFreq, 3)

                    # Attack + exponential-decay envelope.
                    env$ = "(if x<" + attStr$ + " then x/" + attStr$ + " else exp(-(x-" + attStr$ + ")/" + decStr$ + ") fi)"

                    # sin^3(theta) = 3/4 sin(theta) - 1/4 sin(3 theta).
                    # Expanding it explicitly lets us omit only the 3rd
                    # harmonic when it would alias above Nyquist.
                    fundAmp = ampClean + 0.75 * ampWS
                    if fundAmp > 0.001
                        ampStr$ = fixed$(fundAmp, 6)
                        formula$ = formula$ + "+" + ampStr$ + "*sin(2*pi*" + freqStr$ + "*x)*" + env$
                    endif

                    thirdAmp = -0.25 * ampWS
                    thirdFreq = 3 * partialFreq
                    if abs(thirdAmp) > 0.001 and thirdFreq < nyquistFreq * 0.95
                        thirdAmpStr$ = fixed$(thirdAmp, 6)
                        thirdFreqStr$ = fixed$(thirdFreq, 3)
                        formula$ = formula$ + "+" + thirdAmpStr$ + "*sin(2*pi*" + thirdFreqStr$ + "*x)*" + env$
                    endif

                endif
            endfor
            
            # Create burst with all partials at once
            burstSound = Create Sound from formula: "burst", 1, 0, burstDur, sampleRate, formula$
            
            # Add to wet signal
            onsetStr$ = fixed$(onsetTime, 8)
            selectObject: wetSignal
            Formula (part): onsetTime, burstEnd, 1, numChan, "self + Sound_burst(x - " + onsetStr$ + ")"
            
            removeObject: burstSound
        endif
    endif
    
    if onsetIdx mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " ", validOnsets, " bursts"
if validOnsets = 0
    appendInfoLine: "  NOTE: onsets were detected, but none had a valid pitch; wet output is silent."
endif

# ============================================================
# MIX AND FINALIZE
# ============================================================
appendInfo: "Stage 4: Mixing... "

# Apply fadeout to wet signal. Clamp it so a large user value cannot
# start the fade before time zero.
fadeDurEffective = min(fadeout_duration, totalDurWithTail)
if fadeDurEffective > 0
    selectObject: wetSignal
    fadeStart = totalDurWithTail - fadeDurEffective
    Formula (part): fadeStart, totalDurWithTail, 1, numChan,
    ... "self * (1 - (x - " + fixed$(fadeStart, 6) + ") / " + fixed$(fadeDurEffective, 6) + ")"
endif

# Upsample if needed
if targetSR > 0 and origSR > targetSR
    selectObject: wetSignal
    Resample: origSR, 50
    wetUpsampled = selected("Sound")
    removeObject: wetSignal
    wetSignal = wetUpsampled
    finalSR = origSR
else
    finalSR = sampleRate
endif

# Get wet signal name
selectObject: wetSignal
wetName$ = selected$("Sound")

# Get original sound name for formula
selectObject: sound
origName$ = selected$("Sound")

# Create extended output (original + tail) at time 0. Copy the dry
# path by sample index so a non-zero original xmin cannot break lookup.
soundIdStr$ = string$(sound)
output = Create Sound from formula: name$ + "_resonated_" + presetName$,
    ... numChan, 0, totalDurWithTail, finalSR,
    ... "if col <= 'nOrigSamples:0' then object[" + soundIdStr$ + ", row, col] else 0 fi"

# Apply mix. The synthesized wet bank is identical in each channel;
# the dry path retains each original channel independently.
selectObject: wetSignal
nWetSamples = Get number of samples
wetIdStr$ = string$(wetSignal)

selectObject: output
if dry_wet_mix >= 0.99
    Formula: "if col <= 'nWetSamples:0' then object[" + wetIdStr$ + ", row, col] else 0 fi"
elsif dry_wet_mix <= 0.01
    # Exact dry path (plus tail silence): do not normalize.
else
    wetStr$ = fixed$(dry_wet_mix, 6)
    dryStr$ = fixed$(1 - dry_wet_mix, 6)
    Formula: "self * " + dryStr$ + " + (if col <= 'nWetSamples:0' then object[" + wetIdStr$ + ", row, col] else 0 fi) * " + wetStr$
endif

# Safety attenuation only: never boost a quiet result.
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
safetyScaled = 0
if dry_wet_mix > 0.01 and peakBeforeSafety > 0.99
    Scale peak: 0.99
    safetyScaled = 1
endif

# stopwatch returns elapsed time since its previous invocation.
processingTime = stopwatch

# Get output stats for visualization / summary
selectObject: output
outDur = Get total duration
rms_out = Get root-mean-square: 0, 0

appendInfoLine: "done"
appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Valid onsets:    ", validOnsets, " / ", numOnsets
appendInfoLine: "Tail duration:   ", fixed$(tail_duration, 2), " seconds"
appendInfoLine: "Output RMS:      ", fixed$(rms_out, 6)

###############################################################################
# VISUALIZATION  (8 x 8 canvas — suite standard)
# Panel A: Original waveform + onset markers  (left, headline)
# Panel B: Processed output waveform          (right, headline)
# Panel C: Detected pitches per onset
# Panel D: Onset velocities
# Panel E: light-grey summary stats bar
###############################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    # Find pitch range across all valid onsets (used in Panel C)
    minPitch = 5000
    maxPitch = 0
    numValidPitches = 0
    for i to numOnsets
        if onset_pitches#[i] > 0
            numValidPitches += 1
            if onset_pitches#[i] < minPitch
                minPitch = onset_pitches#[i]
            endif
            if onset_pitches#[i] > maxPitch
                maxPitch = onset_pitches#[i]
            endif
        endif
    endfor

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    suiteVizName$ = replace$(origName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Onset-Based Oscillator Bank v2.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    selectObject: analysisSound
    Colour: "{0.65, 0.65, 0.65}"
    Draw: 0, totalDur, 0, 0, "no", "Curve"

    # Mark onsets: red = valid pitch, grey = no pitch
    maxAmp = Get maximum: 0, 0, "None"
    minAmp = Get minimum: 0, 0, "None"
    Line width: 1
    for i to numOnsets
        if onset_pitches#[i] > 0
            Colour: "{0.85, 0.30, 0.30}"
        else
            Colour: "{0.55, 0.55, 0.60}"
        endif
        Draw line: onset_times#[i], minAmp, onset_times#[i], maxAmp
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL B: PROCESSED OUTPUT WAVEFORM  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    selectObject: output
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES  (above A and B)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Original  +  onsets  (red = valid pitch,  grey = no pitch)"
    Text: 6.10, "centre", 7.30, "half",
        ... "Output  (" + fixed$(outDur, 2) + " s)"

    # ----------------------------------------------------------
    # PANEL C: DETECTED PITCHES  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    if numValidPitches > 0 and maxPitch > minPitch
        yLo = minPitch * 0.9
        yHi = maxPitch * 1.1
    else
        yLo = 0
        yHi = 1000
    endif

    Axes: 0, totalDur, yLo, yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, yLo, yHi

    Colour: "{0.30, 0.60, 0.30}"
    Line width: 1
    for i to numOnsets
        if onset_pitches#[i] > 0
            Draw circle: onset_times#[i], onset_pitches#[i], 0.02
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no",
        ... "Detected pitches per onset  ("
        ... + string$(numValidPitches) + " of " + string$(numOnsets) + " onsets,  "
        ... + fixed$(minPitch, 1) + "-" + fixed$(maxPitch, 1) + " Hz)"
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: ONSET VELOCITIES  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, totalDur, 0, 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, 0, 1.1

    # Reference dashed line at velocity = 1.0
    Colour: "{0.78, 0.78, 0.82}"
    Line width: 1
    Dotted line
    Draw line: 0, 1, totalDur, 1
    Solid line

    # Draw velocity stems: valid pitch = orange, no pitch = grey
    Line width: 2
    for i to numOnsets
        if onset_pitches#[i] > 0
            Colour: "{0.78, 0.42, 0.22}"
        else
            Colour: "{0.55, 0.55, 0.60}"
        endif
        Draw line: onset_times#[i], 0, onset_times#[i], onset_velocities#[i]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Onset velocities  (orange = valid pitch,  grey = no pitch)"
    Text left: "yes", "Level"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  Onsets: " + string$(validOnsets) + " valid / " + string$(numOnsets) + " detected"
        ... + "  |  Partials: " + string$(num_partials)
        ... + "  |  Spread: " + fixed$(partial_spread, 2) + "%"
        ... + "  |  Decay: " + fixed$(decayTime, 2) + " s"

    Text: 0.02, "left", 0.50, "half",
        ... "Threshold: " + fixed$(onset_threshold, 2) + " dB"
        ... + "  |  Min interval: " + fixed$(min_interval, 3) + " s"
        ... + "  |  Brightness: " + fixed$(brightness, 2)
        ... + "  |  Dry/Wet: " + fixed$(dry_wet_mix, 2)
        ... + "  |  Tail: " + fixed$(tail_duration, 1) + " s"

    Text: 0.02, "left", 0.18, "half",
        ... speedStr$
        ... + "  |  Time: " + fixed$(processingTime, 2) + " s"
        ... + "  |  Out RMS: " + fixed$(rms_out, 4)
        ... + "  |  Safety scale: " + string$(safetyScaled)
        ... + "  |  Output: " + name$ + "_resonated_" + presetName$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: wetSignal, analysisSound

if workingSound <> sound
    removeObject: workingSound
endif

# Restore the input Sound's absolute time domain only after visualization,
# which uses a normalized 0..duration axis.
selectObject: output
if origStart <> 0
    Shift times by: origStart
endif

if play_result
    Play
endif

selectObject: output