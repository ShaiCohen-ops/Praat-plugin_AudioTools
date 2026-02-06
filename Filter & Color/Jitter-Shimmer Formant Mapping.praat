# ============================================================
# Praat AudioTools - Jitter-Shimmer_Formant_Mapping.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Enhanced with Perceptual Model
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Maps voice perturbation (jitter/shimmer) to timbral transformation
#   using perceptually-motivated nonlinear scaling and separate
#   control over low (F1-F2) vs high (F3-F5) formants.
#
# Changelog v2.0:
#   - FIXED: extractNumber procedure (was completely broken)
#   - FIXED: Percent symbol parsing
#   - Added nonlinear (logarithmic) jitter/shimmer mapping
#   - Separated F1-F2 (shimmer) vs F3-F5 (jitter) scaling
#   - Added pitch range auto-detection
#   - Added formant trajectory visualization
#   - Added sample rate validation
#   - Modern array syntax
#   - Better error handling
# ============================================================

form Jitter Shimmer Formant Mapping v2.0
    comment === PRESETS ===
    optionmenu Preset 1
        option Modal (Subtle)
        option Breathy (Brighter)
        option Creaky (Darker)
        option Tense (Sharp)
        option Relaxed (Smooth)
        option Custom
    
    comment === MAPPING INTENSITY ===
    positive Global_intensity 1.0
    
    comment === CUSTOM WEIGHTS (0 for no effect) ===
    comment Low formants influenced by shimmer
    real Shimmer_to_F1F2 0.3
    comment High formants influenced by jitter
    real Jitter_to_F3F5 0.3
    
    comment === PITCH CONTROL ===
    boolean Auto_detect_pitch_range 1
    positive Manual_pitch_floor_Hz 75
    positive Manual_pitch_ceiling_Hz 600
    boolean Apply_pitch_shift 0
    
    comment === OUTPUT ===
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Keep_intermediates 0
endform

# ============================================================
# INITIALIZATION
# ============================================================

clearinfo
writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║   JITTER/SHIMMER → FORMANT MAPPING v2.0 (Enhanced)          ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"

if numberOfSelected("Sound") = 0
    exitScript: "ERROR: Please select one or more Sound objects first."
endif

# Modern array syntax
sounds# = selected#("Sound")
numSounds = size(sounds#)

# Initialize result array
resultSounds# = zero#(numSounds)

appendInfoLine: "Processing ", numSounds, " sound(s)..."
appendInfoLine: ""

# ============================================================
# PRESET CONFIGURATION
# ============================================================

# Initialize
pitch_multiplier = 1.0
s_weight_low = shimmer_to_F1F2
j_weight_high = jitter_to_F3F5

if preset = 2
    # Modal: Very subtle, natural
    s_weight_low = 0.1
    j_weight_high = 0.1
    pitch_multiplier = 1.0
    presetName$ = "Modal"
elsif preset = 3
    # Breathy: Shimmer opens low formants
    s_weight_low = 0.5
    j_weight_high = 0.3
    pitch_multiplier = 1.08
    presetName$ = "Breathy"
elsif preset = 4
    # Creaky: Negative weights darken
    s_weight_low = -0.4
    j_weight_high = -0.2
    pitch_multiplier = 0.92
    presetName$ = "Creaky"
elsif preset = 5
    # Tense: High formants more affected
    s_weight_low = 0.2
    j_weight_high = 0.6
    pitch_multiplier = 1.05
    presetName$ = "Tense"
elsif preset = 6
    # Relaxed: Smooth, reduced high formants
    s_weight_low = 0.3
    j_weight_high = -0.2
    pitch_multiplier = 0.98
    presetName$ = "Relaxed"
else
    presetName$ = "Custom"
endif

appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Intensity: ", global_intensity, "×"
appendInfoLine: "Shimmer→F1-F2: ", fixed$(s_weight_low, 2), " | Jitter→F3-F5: ", fixed$(j_weight_high, 2)
appendInfoLine: ""

# ============================================================
# MAIN LOOP
# ============================================================

for current to numSounds
    
    selectObject: sounds#[current]
    originalName$ = selected$("Sound")
    
    appendInfoLine: "════════════════════════════════════════════════════════════"
    appendInfoLine: "[", current, "/", numSounds, "] Processing: ", originalName$
    appendInfoLine: "────────────────────────────────────────────────────────────"
    
    # Get properties
    originalDur = Get total duration
    originalSR = Get sampling frequency
    numChannels = Get number of channels
    
    # Determine max formant frequency from sample rate
    maxFormantHz = min(5500, originalSR / 2 - 50)
    
    # Convert to mono if needed
    isTempMono = 0
    if numChannels > 1
        Convert to mono
        workingSound = selected("Sound")
        Rename: originalName$ + "_temp_mono"
        isTempMono = 1
    else
        selectObject: sounds#[current]
        Copy: originalName$ + "_work"
        workingSound = selected("Sound")
    endif
    
    # ------------------------------------------------
    # STEP 1: AUTO-DETECT PITCH RANGE
    # ------------------------------------------------
    selectObject: workingSound
    
    if auto_detect_pitch_range
        appendInfoLine: "  [1/6] Auto-detecting pitch range..."
        
        # Wide initial scan
        pitchWide = To Pitch (cc): 0, 50, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, 800
        
        # Get robust range (10th to 90th percentile)
        q10 = Get quantile: 0, 0, 0.10, "Hertz"
        q90 = Get quantile: 0, 0, 0.90, "Hertz"
        
        if q10 = undefined or q90 = undefined
            # Fallback
            pitchFloor = manual_pitch_floor_Hz
            pitchCeiling = manual_pitch_ceiling_Hz
            appendInfoLine: "    ⚠ Auto-detection failed, using manual range"
        else
            # Add margins
            pitchFloor = max(50, q10 * 0.8)
            pitchCeiling = min(800, q90 * 1.3)
            appendInfoLine: "    Detected range: ", fixed$(pitchFloor, 0), "-", fixed$(pitchCeiling, 0), " Hz"
        endif
        
        removeObject: pitchWide
    else
        pitchFloor = manual_pitch_floor_Hz
        pitchCeiling = manual_pitch_ceiling_Hz
        appendInfoLine: "  [1/6] Using manual pitch range: ", pitchFloor, "-", pitchCeiling, " Hz"
    endif
    
    # ------------------------------------------------
    # STEP 2: PRECISE PITCH ANALYSIS
    # ------------------------------------------------
    appendInfoLine: "  [2/6] Analyzing pitch..."
    selectObject: workingSound
    pitch = To Pitch (cc): 0, pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling
    
    medianPitch = Get quantile: 0, 0, 0.5, "Hertz"
    if medianPitch = undefined
        medianPitch = (pitchFloor + pitchCeiling) / 2
        appendInfoLine: "    ⚠ No voiced sections found, using midpoint: ", fixed$(medianPitch, 0), " Hz"
    else
        appendInfoLine: "    Median pitch: ", fixed$(medianPitch, 0), " Hz"
    endif
    
    # ------------------------------------------------
    # STEP 3: VOICE REPORT (FIXED PARSING)
    # ------------------------------------------------
    appendInfoLine: "  [3/6] Measuring jitter/shimmer..."
    selectObject: workingSound
    plusObject: pitch
    pointProcess = To PointProcess (cc)
    
    selectObject: workingSound
    plusObject: pitch
    plusObject: pointProcess
    voiceReport$ = Voice report: 0, 0, pitchFloor, pitchCeiling, 1.3, 1.6, 0.03, 0.45
    
    # Extract values (FIXED)
    @extractNumber: voiceReport$, "Jitter (local): "
    jitterVal = extractNumber.result
    
    @extractNumber: voiceReport$, "Shimmer (local): "
    shimmerVal = extractNumber.result
    
    # Safety defaults
    if jitterVal = undefined or jitterVal < 0
        jitterVal = 0.5
        appendInfoLine: "    ⚠ Jitter extraction failed, using default: 0.5%"
    endif
    if shimmerVal = undefined or shimmerVal < 0
        shimmerVal = 1.0
        appendInfoLine: "    ⚠ Shimmer extraction failed, using default: 1.0%"
    endif
    
    appendInfoLine: "    Jitter (local): ", fixed$(jitterVal, 3), "%"
    appendInfoLine: "    Shimmer (local): ", fixed$(shimmerVal, 3), "%"
    
    # ------------------------------------------------
    # STEP 4: NONLINEAR PERCEPTUAL MAPPING (FIXED)
    # ------------------------------------------------
    appendInfoLine: "  [4/6] Computing formant shifts..."
    
    # Apply intensity
    effJitter = jitterVal * global_intensity
    effShimmer = shimmerVal * global_intensity
    
    # NONLINEAR SCALING using log10 (Praat compatible)
    # log10(1+x) compresses extreme values perceptually
    # Typical ranges: jitter 0.2-5%, shimmer 0.5-10%
    
    # Pre-compute normalization constants
    log10_6 = 0.778151
    log10_11 = 1.041393
    
    jitterLog = log10(1 + effJitter)
    jitterNorm = jitterLog / log10_6
    
    shimmerLog = log10(1 + effShimmer)
    shimmerNorm = shimmerLog / log10_11
    
    # Calculate separate influences
    lowFormantShift = 1.0 + (shimmerNorm * s_weight_low)
    highFormantShift = 1.0 + (jitterNorm * j_weight_high)
    
    # Safety clamping
    lowFormantShift = max(0.5, min(2.0, lowFormantShift))
    highFormantShift = max(0.5, min(2.0, highFormantShift))
    
    appendInfoLine: "    F1-F2 shift: ×", fixed$(lowFormantShift, 3), " (shimmer-driven)"
    appendInfoLine: "    F3-F5 shift: ×", fixed$(highFormantShift, 3), " (jitter-driven)"
    
    # Target pitch
    targetPitch = medianPitch
    if apply_pitch_shift
        targetPitch = medianPitch * pitch_multiplier
        appendInfoLine: "    Pitch shift: ", fixed$(medianPitch, 0), " → ", fixed$(targetPitch, 0), " Hz"
    endif
    
    # ------------------------------------------------
    # STEP 5: FORMANT MANIPULATION & RESYNTHESIS
    # ------------------------------------------------
    appendInfoLine: "  [5/6] Resynthesizing..."
    
    selectObject: workingSound
    
    # Get formants directly from sound
    formantOrig = To Formant (burg): 0, 5, maxFormantHz, 0.025, 50
    
    # Create FormantGrid for manipulation
    selectObject: formantOrig
    formantGrid = Down to FormantGrid
    
    # Manipulate formants separately
    selectObject: formantGrid
    
    # F1-F2 scaling (shimmer influence)
    for i to 2
        selectObject: formantGrid
        Formula (frequencies): "if row = " + string$(i) + " then self * " + string$(lowFormantShift) + " else self fi"
    endfor
    
    # F3-F5 scaling (jitter influence)
    for i from 3 to 5
        selectObject: formantGrid
        Formula (frequencies): "if row = " + string$(i) + " then self * " + string$(highFormantShift) + " else self fi"
    endfor
    
    # Convert to Formant for LPC
    selectObject: formantGrid
    formantManip = To Formant: 0.01, 0.1
    
    # Now do LPC resynthesis with original approach
    selectObject: workingSound
    lpc = To LPC (autocorrelation): 16, 0.025, 0.005, 50
    
    # Extract source
    selectObject: workingSound
    plusObject: lpc
    source = Filter (inverse)
    
    # Create new LPC from manipulated formants
    selectObject: formantManip
    lpcManip = To LPC: maxFormantHz / 2
    
    # Filter source through modified LPC
    selectObject: source
    plusObject: lpcManip
    resynthesized = Filter: "no"
    
    # Apply pitch shift if requested
    if apply_pitch_shift
        selectObject: resynthesized
        manipulation = To Manipulation: 0.01, pitchFloor, pitchCeiling
        pitchTier = Extract pitch tier
        
        # Scale pitch
        pitchFactor = targetPitch / medianPitch
        pitchFactorStr$ = string$(pitchFactor)
        selectObject: pitchTier
        Formula: "self * " + pitchFactorStr$
        
        selectObject: manipulation
        plusObject: pitchTier
        Replace pitch tier
        
        selectObject: manipulation
        Get resynthesis (overlap-add)
        finalSound = selected("Sound")
        
        removeObject: resynthesized, manipulation, pitchTier
    else
        finalSound = resynthesized
    endif
    
    # Normalize
    selectObject: finalSound
    Scale peak: 0.95
    Rename: originalName$ + "_" + presetName$
    resultID = selected("Sound")
    
    appendInfoLine: "  [6/6] Complete!"
    
    # ------------------------------------------------
    # CLEANUP
    # ------------------------------------------------
    
    if not keep_intermediates
        removeObject: pitch, pointProcess, lpc, source, formantOrig, formantGrid, formantManip, lpcManip
    endif
    
    if isTempMono
        removeObject: workingSound
    endif
    
    # ------------------------------------------------
    # PLAYBACK
    # ------------------------------------------------
    
    if play_result
        selectObject: resultID
        Play
    endif
    
    # Store for visualization
    resultSounds#[current] = resultID
    
endfor

appendInfoLine: ""
appendInfoLine: "════════════════════════════════════════════════════════════"
appendInfoLine: "Processing complete!"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization and numSounds > 0
    appendInfoLine: "Generating visualization..."
    
    Erase all
    
    # Visualize first sound
    selectObject: sounds#[1]
    originalViz = Copy: "viz_original"
    originalChannels = Get number of channels
    
    if originalChannels > 1
        Convert to mono
        removeObject: originalViz
        originalViz = selected("Sound")
    endif
    
    selectObject: resultSounds#[1]
    resultViz = Copy: "viz_result"
    resultChannels = Get number of channels
    
    if resultChannels > 1
        Convert to mono
        removeObject: resultViz
        resultViz = selected("Sound")
    endif
    
    # Get duration for display
    selectObject: originalViz
    vizDur = Get total duration
    vizDur = min(vizDur, 5)
    
    # === TITLE ===
    Select outer viewport: 0, 10, 0, 0.7
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Jitter-Shimmer Formant Mapping## | " + presetName$
    
    # === ORIGINAL SPECTROGRAM ===
Select outer viewport: 0, 10, 0.8, 2.5
Select inner viewport: 0.8, 9.5, 0.9, 2.4

selectObject: originalViz
To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
specOrig = selected("Spectrogram")
Paint: 0, vizDur, 0, 5000, 100, "yes", 50, 6, 0, "no"

# Overlay formants
selectObject: originalViz
To Formant (burg): 0, 5, 5500, 0.025, 50
formantOrigViz = selected("Formant")

Colour: "{1.0, 0.3, 0.3}"
Line width: 2
Draw tracks: 0, vizDur, 5000, "no"
Line width: 1

Colour: "Black"
Draw inner box
Font size: 8
Text left: "yes", "Frequency (Hz)"

Select outer viewport: 0, 0.8, 0.8, 2.5
Font size: 10
Colour: "{0.3, 0.4, 0.6}"
Text: 0.5, "centre", 0.5, "half", "Original"

removeObject: specOrig, formantOrigViz

# === RESULT SPECTROGRAM ===
Select outer viewport: 0, 10, 2.6, 4.3
Select inner viewport: 0.8, 9.5, 2.7, 4.2

selectObject: resultViz
To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
specResult = selected("Spectrogram")
Paint: 0, vizDur, 0, 5000, 100, "yes", 50, 6, 0, "no"

# Overlay formants
selectObject: resultViz
To Formant (burg): 0, 5, 5500, 0.025, 50
formantResultViz = selected("Formant")

Colour: "{0.3, 1.0, 0.3}"
Line width: 2
Draw tracks: 0, vizDur, 5000, "no"
Line width: 1

Colour: "Black"
Draw inner box
Font size: 8
Text left: "yes", "Frequency (Hz)"
Text bottom: "yes", "Time (s)"

Select outer viewport: 0, 0.8, 2.6, 4.3
Font size: 10
Colour: "{0.2, 0.6, 0.3}"
Text: 0.5, "centre", 0.5, "half", "Result"

removeObject: specResult, formantResultViz
    
    # === PARAMETERS DISPLAY ===
    Select outer viewport: 0, 10, 4.5, 5.5
    Font size: 7
    Colour: "{0.3, 0.3, 0.3}"
    
    Text: 0.5, "centre", 0.2, "half", "Input: Jitter = " + fixed$(jitterVal, 2) + "% | Shimmer = " + fixed$(shimmerVal, 2) + "%"
    Text: 2.0, "centre", 0.5, "half", "Mapping: F1-F2 ×" + fixed$(lowFormantShift, 2) + " (shimmer) | F3-F5 ×" + fixed$(highFormantShift, 2) + " (jitter)"
    Text: 4.0, "centre", 0.8, "half", "Red tracks = original formants | Green tracks = transformed formants"
    
    # Cleanup
    removeObject: originalViz, resultViz
    
    Font size: 10
    Colour: "Black"
    
    appendInfoLine: "Visualization complete!"
endif

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                          DONE                                ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"

# ============================================================
# HELPER: Extract Number from Voice Report (FIXED)
# ============================================================

procedure extractNumber: .text$, .label$
    # Find the label
    .index = index(.text$, .label$)
    
    if .index = 0
        # Label not found
        .result = undefined
    else
        # Get substring after label
        .length = length(.label$)
        .start = .index + .length
        .rest$ = mid$(.text$, .start, 50)
        
        # Find the end of the number (%, space, or newline)
        .endPercent = index(.rest$, "%")
        .endSpace = index(.rest$, " ")
        .endNewline = index(.rest$, newline$)
        
        # Use the earliest delimiter found
        .end = 999
        if .endPercent > 0 and .endPercent < .end
            .end = .endPercent
        endif
        if .endSpace > 0 and .endSpace < .end
            .end = .endSpace
        endif
        if .endNewline > 0 and .endNewline < .end
            .end = .endNewline
        endif
        if .end = 999
            .end = length(.rest$) + 1
        endif
        
        # Extract the number string
        .valStr$ = left$(.rest$, .end - 1)
        
        # Clean up (strip any remaining % or spaces)
        .valStr$ = replace$(.valStr$, "%", "", 0)
        .valStr$ = replace$(.valStr$, " ", "", 0)
        
        # Convert to number
        .result = number(.valStr$)
        
        # Validation
        if .result = undefined
            .result = 0
        endif
    endif
endproc