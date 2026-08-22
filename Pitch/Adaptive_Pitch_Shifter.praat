# ============================================================
# Praat AudioTools - Adaptive_Pitch_Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive Pitch Shifter - applies pitch shifting modulated
#   by amplitude, pitch contour, LFO, or combined sources.
#   Creates effects from subtle vibrato to extreme warping.
#
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - Corrected modulation smoothing (smooths modulation state, not modified pitch)
#   - Centered modulation sources around zero so Base_pitch_shift is the centre
#   - Made amplitude and pitch-contour normalization adaptive to the input
#   - Replaced undocumented PSOLA branch with documented Manipulation resynthesis paths
#   - Uses LPC resynthesis for speech-oriented formant/spectral-envelope preservation
#   - Fixed stereo widening (row = channel; col = sample) with delayed decorrelation
#   - Output_gain is now the actual final gain (no unconditional peak normalization)
#   - Visualization is sampled across the whole file and respects Nyquist
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
originalName$ = selected$("Sound")

# === Form ===
form Adaptive Pitch Shifter v0.4.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Wobble
        option Robot Voice
        option Harmonic Shimmer
        option Deep Bass Mod
        option Vibrato Effect
        option Extreme Warp
    
    comment === Basic Controls ===
    positive Base_pitch_shift 1.0
    positive Modulation_amount 0.5
    
    comment === Modulation Source ===
    optionmenu Modulation_source 1
        option Amplitude
        option Pitch Contour
        option Time-based LFO
        option Combined
    positive LFO_frequency 3.0
    real Smoothing_factor 0.1
    
    comment === Processing ===
    boolean Apply_formant_preservation 1
    boolean Add_stereo_width 0
    positive Output_gain 1.0
    
    comment === Quality ===
    optionmenu Quality 2
        option Fast
        option Standard
        option High Quality
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Wobble
    base_pitch_shift = 1.0
    modulation_amount = 0.15
    modulation_source = 1
    lFO_frequency = 4.0
    smoothing_factor = 0.2
elsif preset = 3
    # Robot Voice
    base_pitch_shift = 0.8
    modulation_amount = 0.8
    modulation_source = 3
    lFO_frequency = 8.0
    smoothing_factor = 0.05
elsif preset = 4
    # Harmonic Shimmer
    base_pitch_shift = 1.5
    modulation_amount = 0.3
    modulation_source = 2
    lFO_frequency = 2.0
    smoothing_factor = 0.3
elsif preset = 5
    # Deep Bass Mod
    base_pitch_shift = 0.5
    modulation_amount = 1.0
    modulation_source = 4
    lFO_frequency = 1.5
    smoothing_factor = 0.15
elsif preset = 6
    # Vibrato Effect
    base_pitch_shift = 1.0
    modulation_amount = 0.08
    modulation_source = 3
    lFO_frequency = 5.5
    smoothing_factor = 0.4
elsif preset = 7
    # Extreme Warp
    base_pitch_shift = 1.2
    modulation_amount = 1.5
    modulation_source = 4
    lFO_frequency = 10.0
    smoothing_factor = 0.0
endif

# === Validate Parameters ===
if smoothing_factor < 0 or smoothing_factor > 1
    exitScript: "Smoothing_factor must be between 0 and 1."
endif
if modulation_amount < 0
    exitScript: "Modulation_amount must be zero or greater."
endif

# === Get Names ===
if preset = 1
    presetName$ = "Custom"
elsif preset = 2
    presetName$ = "Subtle Wobble"
elsif preset = 3
    presetName$ = "Robot Voice"
elsif preset = 4
    presetName$ = "Harmonic Shimmer"
elsif preset = 5
    presetName$ = "Deep Bass"
elsif preset = 6
    presetName$ = "Vibrato"
else
    presetName$ = "Extreme Warp"
endif

if modulation_source = 1
    modSourceName$ = "Amplitude"
elsif modulation_source = 2
    modSourceName$ = "Pitch Contour"
elsif modulation_source = 3
    modSourceName$ = "LFO"
else
    modSourceName$ = "Combined"
endif

# === Set Quality Parameters ===
if quality = 1
    timestep = 0.01
    pitchFloor = 75
    pitchCeiling = 600
elsif quality = 2
    timestep = 0.005
    pitchFloor = 75
    pitchCeiling = 600
else
    timestep = 0.001
    pitchFloor = 50
    pitchCeiling = 800
endif

# === Info ===
writeInfoLine: "=== Adaptive Pitch Shifter ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Modulation: ", modSourceName$
appendInfoLine: ""
appendInfoLine: "Base shift: ", base_pitch_shift
appendInfoLine: "Mod amount: ", modulation_amount
if modulation_source = 3 or modulation_source = 4
    appendInfoLine: "LFO freq: ", lFO_frequency, " Hz"
endif
appendInfoLine: ""

# === Extract Analysis Objects ===
# Pitch analysis is needed only for the Pitch Contour modulation source.
if modulation_source = 2
    appendInfoLine: "Extracting pitch contour..."
    selectObject: sound
    pitch = To Pitch: timestep, pitchFloor, pitchCeiling
    selectObject: pitch
    pitchMin = Get minimum: 0, 0, "Hertz", "Parabolic"
    pitchMax = Get maximum: 0, 0, "Hertz", "Parabolic"
endif

# Intensity is queried directly; an intermediate IntensityTier is unnecessary.
if modulation_source = 1 or modulation_source = 4
    selectObject: sound
    appendInfoLine: "Extracting amplitude envelope..."
    intensity = To Intensity: pitchFloor, timestep, "yes"
    selectObject: intensity
    intensityMin = Get minimum: 0, 0, "Parabolic"
    intensityMax = Get maximum: 0, 0, "Parabolic"
endif

# === Create Manipulation Object ===
selectObject: sound
appendInfoLine: "Creating manipulation object..."
manipulation = To Manipulation: timestep, pitchFloor, pitchCeiling

# === Extract Pitch Tier ===
selectObject: manipulation
pitchTier = Extract pitch tier

selectObject: pitchTier
numPoints = Get number of points

if numPoints = 0
    if modulation_source = 2
        removeObject: pitch
    endif
    if modulation_source = 1 or modulation_source = 4
        removeObject: intensity
    endif
    removeObject: manipulation, pitchTier
    selectObject: sound
    exitScript: "No voiced pitch points were detected. Try different pitch bounds or a pitched input."
endif

appendInfoLine: "Modifying pitch at ", numPoints, " points..."

# === Store for Visualization ===
# Sample points across the whole file instead of keeping only the first 500.
vizStride = ceiling(numPoints / 500)
if vizStride < 1
    vizStride = 1
endif
maxPoints = ceiling(numPoints / vizStride)
originalFreqs# = zero#(maxPoints)
newFreqs# = zero#(maxPoints)
times# = zero#(maxPoints)
modValues# = zero#(maxPoints)
storedPoints = 0
nextVizPoint = 1

# Smoothing state: 0 means no smoothing; 1 means maximum memory.
havePreviousModulation = 0
previousModulation = 0

# === Modify Pitch Tier ===
for i from 1 to numPoints
    selectObject: pitchTier
    time = Get time from index: i
    originalFreq = Get value at index: i

    if originalFreq <> undefined
        rawModulation = 0

        # Calculate a bipolar modulation signal in the range approximately -1..+1.
        if modulation_source = 1
            # Amplitude-based: adapt to the measured intensity range of this input.
            selectObject: intensity
            amplitude = Get value at time: time, "cubic"
            if amplitude <> undefined and intensityMax <> undefined and intensityMin <> undefined and intensityMax > intensityMin
                normalizedAmp = (amplitude - intensityMin) / (intensityMax - intensityMin)
                normalizedAmp = max(0, min(1, normalizedAmp))
                rawModulation = 2 * normalizedAmp - 1
            endif

        elsif modulation_source = 2
            # Pitch-contour-based: adapt to the detected pitch range of this input.
            selectObject: pitch
            currentPitch = Get value at time: time, "Hertz", "linear"
            if currentPitch <> undefined and pitchMax <> undefined and pitchMin <> undefined and pitchMax > pitchMin
                normalizedPitch = (currentPitch - pitchMin) / (pitchMax - pitchMin)
                normalizedPitch = max(0, min(1, normalizedPitch))
                rawModulation = 2 * normalizedPitch - 1
            endif

        elsif modulation_source = 3
            # Bipolar sine LFO. This makes Base_pitch_shift the centre of vibrato.
            rawModulation = sin(2 * pi * lFO_frequency * time)

        elsif modulation_source = 4
            # Combined = Amplitude + LFO, as documented.
            ampModulation = 0
            selectObject: intensity
            amplitude = Get value at time: time, "cubic"
            if amplitude <> undefined and intensityMax <> undefined and intensityMin <> undefined and intensityMax > intensityMin
                normalizedAmp = (amplitude - intensityMin) / (intensityMax - intensityMin)
                normalizedAmp = max(0, min(1, normalizedAmp))
                ampModulation = 2 * normalizedAmp - 1
            endif
            lfo = sin(2 * pi * lFO_frequency * time)
            rawModulation = (ampModulation + lfo) / 2
        endif

        # One-pole smoothing of the modulation signal itself.
        if havePreviousModulation = 0
            modulation = rawModulation
            havePreviousModulation = 1
        else
            modulation = rawModulation * (1 - smoothing_factor) + previousModulation * smoothing_factor
        endif
        previousModulation = modulation

        # Calculate new frequency. Keep multiplier positive even for extreme presets.
        pitchMultiplier = base_pitch_shift + modulation * modulation_amount
        pitchMultiplier = max(0.05, pitchMultiplier)
        newFreq = originalFreq * pitchMultiplier

        # Broad safety bounds for resynthesis; these do not redefine analysis bounds.
        newFreq = max(20, min(2000, newFreq))

        # Store a decimated visualization point spanning the full sound.
        if i = nextVizPoint and storedPoints < maxPoints
            storedPoints = storedPoints + 1
            originalFreqs#[storedPoints] = originalFreq
            newFreqs#[storedPoints] = newFreq
            times#[storedPoints] = time
            modValues#[storedPoints] = modulation
            nextVizPoint = nextVizPoint + vizStride
        endif

        # Update pitch tier point in place.
        selectObject: pitchTier
        Remove point: i
        Add point: time, newFreq
    endif
endfor

# === Apply Modified Pitch Tier ===
selectObject: manipulation, pitchTier
Replace pitch tier

# === Synthesize Output ===
selectObject: manipulation
appendInfoLine: "Synthesizing output..."
if apply_formant_preservation
    # LPC keeps the original speech filter/spectral-envelope model while the pitch source changes.
    # This is speech-oriented formant preservation, not mathematical formant locking.
    output = Get resynthesis (LPC)
    resynthesisName$ = "LPC (spectral-envelope/formant oriented)"
else
    output = Get resynthesis (overlap-add)
    resynthesisName$ = "Overlap-add"
endif

outputName$ = originalName$ + "_shifted_" + presetName$
Rename: outputName$

# === Add Stereo Width ===
# Praat Sound formulas use row for channel and col for sample.
# For mono output, duplicate to stereo and decorrelate the right channel with a short delayed component.
selectObject: output
numChannels = Get number of channels
if add_stereo_width and numChannels = 1
    appendInfoLine: "Adding stereo width..."
    leftCopy = Copy: "AT_width_L"
    selectObject: output
    rightCopy = Copy: "AT_width_R"
    selectObject: leftCopy
    plusObject: rightCopy
    stereoOutput = Combine to stereo
    removeObject: leftCopy, rightCopy, output
    output = stereoOutput
    selectObject: output
    Rename: outputName$

    stereoDelaySamples = max(1, round(0.012 * sampleRate))
    selectObject: output
    Formula: ~ if row = 1 then self else 0.85 * self + 0.15 * self[1, col - stereoDelaySamples] fi
endif

# === Apply Output Gain ===
# Apply gain last and do not normalize afterwards; this keeps Output_gain truthful.
selectObject: output
Formula: ~ self * output_gain

# === Cleanup ===
if modulation_source = 2
    removeObject: pitch
endif
if modulation_source = 1 or modulation_source = 4
    removeObject: intensity
endif
removeObject: manipulation, pitchTier

# === Visualization ===
if draw_visualization and storedPoints > 0
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Adaptive Pitch Shifter v0.4.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  Mod: " + modSourceName$
        ... + "  |  Base=" + fixed$(base_pitch_shift, 2) + "x"
        ... + "  Amt=" + fixed$(modulation_amount, 2)

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: output
    outCh = Get number of channels
    if outCh > 1
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: output
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: output
        Colour: "{0.38, 0.55, 0.72}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Shifted"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Pitch curves comparison (original grey, shifted blue)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.22, 3.52
    Select inner viewport: 0.55, 7.65, 2.30, 3.44

    # Find pitch range across both curves
    vizMinFreq = 9999
    vizMaxFreq = 0
    for pt from 1 to storedPoints
        if originalFreqs#[pt] > 0
            if originalFreqs#[pt] < vizMinFreq
                vizMinFreq = originalFreqs#[pt]
            endif
            if originalFreqs#[pt] > vizMaxFreq
                vizMaxFreq = originalFreqs#[pt]
            endif
        endif
        if newFreqs#[pt] > 0
            if newFreqs#[pt] < vizMinFreq
                vizMinFreq = newFreqs#[pt]
            endif
            if newFreqs#[pt] > vizMaxFreq
                vizMaxFreq = newFreqs#[pt]
            endif
        endif
    endfor

    pMargin = (vizMaxFreq - vizMinFreq) * 0.12
    if pMargin < 20
        pMargin = 20
    endif

    Axes: 0, duration, vizMinFreq - pMargin, vizMaxFreq + pMargin
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, vizMinFreq - pMargin, vizMaxFreq + pMargin

    # Original pitch (grey)
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    for pt from 2 to storedPoints
        if originalFreqs#[pt] > 0 and originalFreqs#[pt - 1] > 0
            Draw line: times#[pt - 1], originalFreqs#[pt - 1], times#[pt], originalFreqs#[pt]
        endif
    endfor

    # Shifted pitch (blue)
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 2
    for pt from 2 to storedPoints
        if newFreqs#[pt] > 0 and newFreqs#[pt - 1] > 0
            Draw line: times#[pt - 1], newFreqs#[pt - 1], times#[pt], newFreqs#[pt]
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pitch (Hz)"
    Text top: "no", "Pitch contour  (grey = original,  blue = shifted)"

    # ----------------------------------------------------------
    # Modulation curve (the adaptive signal)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 3.60, 4.80
    Select inner viewport: 0.55, 3.85, 3.68, 4.72

    # Find modulation range
    modMin = modValues#[1]
    modMax = modValues#[1]
    for pt from 2 to storedPoints
        if modValues#[pt] < modMin
            modMin = modValues#[pt]
        endif
        if modValues#[pt] > modMax
            modMax = modValues#[pt]
        endif
    endfor
    modMargin = (modMax - modMin) * 0.12
    if modMargin < 0.05
        modMargin = 0.05
    endif

    Axes: 0, duration, modMin - modMargin, modMax + modMargin
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, modMin - modMargin, modMax + modMargin

    # Zero line
    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 0, 0, duration, 0
    Solid line

    Colour: "{0.72, 0.42, 0.25}"
    Line width: 1.5
    for pt from 2 to storedPoints
        Draw line: times#[pt - 1], modValues#[pt - 1], times#[pt], modValues#[pt]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mod"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Modulation signal  (" + modSourceName$ + ")"

    # ----------------------------------------------------------
    # Output spectrogram (shows shifted harmonics)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 3.60, 4.80
    Select inner viewport: 4.40, 7.65, 3.68, 4.72

    selectObject: output
    if outCh > 1
        Extract one channel: 1
        vizSpec = selected("Sound")
    else
        Copy: "vizSpec"
        vizSpec = selected("Sound")
    endif
    specMaxHz = min(5000, 0.5 * sampleRate)
    To Spectrogram: 0.02, specMaxHz, 0.005, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, specMaxHz, 100, "yes", 50, 6, 0, "no"
    removeObject: specOut, vizSpec

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output spectrogram"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.90, 5.46
    Select inner viewport: 0.55, 7.65, 4.90 + 0.04, 5.46 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.45, "half",
        ... "Preset: " + presetName$
        ... + "  |  Base shift: " + fixed$(base_pitch_shift, 2) + "x"
        ... + "  |  Mod source: " + modSourceName$
        ... + "  |  Mod amount: " + fixed$(modulation_amount, 2)
        ... + "  |  Smoothing: " + fixed$(smoothing_factor, 2)

    lfoStr$ = ""
    if modulation_source = 3 or modulation_source = 4
        lfoStr$ = "  |  LFO: " + fixed$(lFO_frequency, 1) + " Hz"
    endif

    if apply_formant_preservation
        formStr$ = "LPC"
    else
        formStr$ = "Overlap-add"
    endif
    if add_stereo_width
        stereoStr$ = "ON"
    else
        stereoStr$ = "OFF"
    endif

    Text: 0.02, "left", 0.20, "half",
        ... "Pitch points: " + string$(numPoints)
        ... + "  |  Resynthesis: " + formStr$
        ... + "  |  Stereo width: " + stereoStr$
        ... + lfoStr$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    pageHeight = 5.56
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: output

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Resynthesis: ", resynthesisName$
appendInfoLine: "Output gain: ", output_gain, "x"

# === Play ===
if play_result
    selectObject: output
    Play
endif

selectObject: output
