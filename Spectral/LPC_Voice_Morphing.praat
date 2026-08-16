# ============================================================
# Praat AudioTools - LPC_Voice_Morphing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - preserves vocoder character; stability / source-path fixes
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LPC excitation-replacement vocoder. A pitch-driven phonation source or
#   Gaussian noise is filtered through the time-varying LPC envelope of the
#   input. Despite the historical file name, this is not a two-voice LPC
#   coefficient morph; the "morph" is the replacement of the excitation while
#   retaining the source spectral envelope.
#
#   The pulse path intentionally keeps the v0.3 continuous PitchTier bridge
#   across unvoiced gaps. This is a musical character choice: it avoids the
#   chopped voiced/unvoiced gating that can occur in stricter speech resynthesis.
#
# Changelog v0.4:
#   - FIX: stereo analysis no longer sums channels to mono; the strongest-RMS
#     channel drives pitch/LPC, avoiding anti-phase cancellation.
#   - MUSICAL PRESERVATION: autocorrelation remains the default v0.3 LPC
#     character. If it numerically runs away, the render automatically falls
#     back to Burg instead of returning infinities. Burg can also be selected.
#   - FIX: pulse excitation is aligned to the original sample grid without
#     resampling, removing the extra sample produced by phonation synthesis.
#   - FIX: empty PitchTier input gets a continuous monotone fallback rather
#     than aborting; existing pitch bridges are otherwise unchanged.
#   - FORM: noise excitation is available in Custom instead of being reachable
#     only through the Whisper preset.
#   - SAFETY: target-intensity scaling is silence-safe and a final 0.99 peak
#     ceiling prevents accidental clipping; Whisper's recursive bright colour
#     is intentionally retained.
#   - VIZ: waveform comparison now uses one shared amplitude scale; mechanism
#     labels report the actual analysis channel and LPC method.
# ============================================================

form LPC Vocoder Pro v0.4
    comment === PRESETS ===
    optionmenu Preset: 1
        option Custom
        option Natural Resynthesis
        option Robot Voice (Monotone)
        option Whisper (True Noise)
        option Deep Demon
    
    comment === SOURCE PARAMETERS ===
    optionmenu Excitation_source: 1
        option Pitch-driven pulse
        option Gaussian noise
    positive Time_step 0.01
    positive Minimum_pitch 75
    positive Maximum_pitch 600
    boolean Force_monotone 0
    positive Monotone_frequency 120
    
    comment === LPC FILTER PARAMETERS ===
    optionmenu LPC_method: 1
        option Legacy autocorrelation (v0.3 character)
        option Burg (stable)
    comment (0 = Auto-calculate based on sample rate)
    integer LPC_order 0
    positive Analysis_window 0.025
    positive Pre_emphasis_hz 50
    
    comment === OUTPUT ===
    positive Target_intensity_dB 70
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# --- 1. PRESET LOGIC ---

source_type = excitation_source
# 1=Pitch-driven pulse, 2=Gaussian noise

if preset = 2
    # Natural
    source_type = 1
    lPC_order = 0
    analysis_window = 0.025
    force_monotone = 0
    presetName$ = "Natural"
elsif preset = 3
    # Robot
    source_type = 1
    lPC_order = 0
    analysis_window = 0.030
    force_monotone = 1
    monotone_frequency = 100
    presetName$ = "Robot"
elsif preset = 4
    # Whisper
    source_type = 2
    lPC_order = 0
    analysis_window = 0.015
    presetName$ = "Whisper"
elsif preset = 5
    # Deep Demon
    source_type = 1
    lPC_order = 0
    analysis_window = 0.040
    minimum_pitch = 50
    force_monotone = 0
    presetName$ = "DeepDemon"
else
    presetName$ = "Custom"
endif

# --- 2. SETUP & CALIBRATION ---

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
numChannels = Get number of channels

# Pitch / LPC use one mono analysis driver. For multichannel material choose
# the strongest-RMS channel instead of summing channels, so anti-phase stereo
# cannot disappear before analysis. The vocoder output itself remains mono.
analysisChannel = 1
if numChannels > 1
    analysisID = 0
    bestRms = -1
    for ch from 1 to numChannels
        selectObject: originalID
        tempCh = Extract one channel: ch
        selectObject: tempCh
        tempRms = Get root-mean-square: 0, 0
        if tempRms > bestRms
            if analysisID <> 0
                removeObject: analysisID
            endif
            analysisID = tempCh
            analysisChannel = ch
            bestRms = tempRms
        else
            removeObject: tempCh
        endif
    endfor
    selectObject: analysisID
    Rename: "analysis_ch" + string$(analysisChannel)
else
    selectObject: originalID
    analysisID = Copy: "analysis_mono"
endif

if maximum_pitch <= minimum_pitch
    exitScript: "Maximum pitch must be greater than minimum pitch."
endif
if lPC_order < 0
    exitScript: "LPC order must be 0 (auto) or a positive integer."
endif
if pre_emphasis_hz < 0
    exitScript: "Pre-emphasis frequency must be 0 Hz or greater."
endif

selectObject: analysisID
analysisInputRms = Get root-mean-square: 0, 0

# Auto-Calculate LPC Order if set to 0
# Formula: round(SamplingRate / 1000) + 4 (legacy detail-preserving rule)
if lPC_order = 0
    lPC_order = round(sr / 1000) + 4
    writeInfoLine: "Auto-calibrated LPC Order to: ", lPC_order, " poles"
else
    writeInfoLine: "Using manual LPC Order: ", lPC_order
endif

appendInfoLine: "Processing source: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Analysis driver: channel ", analysisChannel
if lPC_method = 1
    requestedLpcMethod$ = "Autocorrelation (v0.3 character)"
else
    requestedLpcMethod$ = "Burg"
endif
appendInfoLine: "Requested LPC method: ", requestedLpcMethod$
appendInfoLine: ""

# --- 3. SOURCE GENERATION (Excitation) ---

selectObject: analysisID

if source_type = 1
    # --- VOICED SOURCE (PULSE TRAIN) ---
    appendInfo: "Generating glottal source..."
    
    # Extract Pitch
    To Pitch: time_step, minimum_pitch, maximum_pitch
    pitchID = selected("Pitch")
    
    # Convert to PitchTier for manipulation
    Down to PitchTier
    ptID = selected("PitchTier")

    # PitchTier has no voiced/unvoiced flags; the v0.3 path deliberately bridges
    # gaps. If the tier is completely empty, seed a continuous fallback so that
    # noisy/silent material still produces a usable creative vocoder source.
    selectObject: ptID
    nPitchPoints = Get number of points
    if nPitchPoints = 0
        Add point: 0, monotone_frequency
        Add point: dur, monotone_frequency
        appendInfoLine: "  No pitch detected: using ", fixed$(monotone_frequency, 1), " Hz fallback."
    endif
    
    if preset = 5
        # Deep Demon pitch shift
        Formula: "self * 0.6"
    endif
    
    if force_monotone
        # Flatten the pitch tier
        monoStr$ = fixed$(monotone_frequency, 2)
        Formula: monoStr$
    endif
    
    # Preserve the v0.3 continuous PitchTier -> Pitch bridge. This intentionally
    # keeps a pulse source through gaps instead of reinstating voiced/unvoiced cuts.
    selectObject: ptID
    To Pitch: time_step, minimum_pitch, maximum_pitch
    modPitchID = selected("Pitch")
    
    To PointProcess
    ppID = selected("PointProcess")
    
    # THE FIX: 7 Arguments exactly
    # 1. Sampling freq, 2. Adaptation(1.0), 3. Max Period(0.05)
    # 4. OpenPhase(0.7), 5. CollisionPhase(0.03), 6. Power1(3.0), 7. Power2(4.0)
    To Sound (phonation): sr, 1.0, 0.05, 0.7, 0.03, 3.0, 4.0
    sourceRawID = selected("Sound")

    # PointProcess phonation places samples at t=0 and therefore returns one extra
    # sample for a 0..dur domain. Shift the sample grid by half a sample and trim
    # to the original domain: sample values are not resampled or interpolated.
    Shift times by: 0.5 / sr
    sourceID = Extract part: 0, dur, "rectangular", 1, "no"
    Rename: "excitation_pulse"
    removeObject: sourceRawID
    
    # Clean up intermediate pitch objects
    removeObject: pitchID, ptID, modPitchID, ppID
    
else
    # --- UNVOICED SOURCE (WHISPER) ---
    appendInfo: "Generating noise source..."
    # Gaussian noise provides a better "whisper" texture than uniform noise
    sourceID = Create Sound from formula: "excitation_noise", 1, 0, dur, sr, "randomGauss(0,0.2)"
endif

appendInfoLine: " done."

# --- 4. FILTER GENERATION (LPC) ---

appendInfo: "Analyzing spectral envelope..."
selectObject: analysisID
if lPC_method = 1
    To LPC (autocorrelation): lPC_order, analysis_window, 0.005, pre_emphasis_hz
    usedLpcMethod$ = "Autocorrelation"
else
    To LPC (burg): lPC_order, analysis_window, 0.005, pre_emphasis_hz
    usedLpcMethod$ = "Burg"
endif
lpcID = selected("LPC")
appendInfoLine: " done (", usedLpcMethod$, ")."

# --- 5. SYNTHESIS (Filtering) ---

appendInfo: "Vocoding..."
selectObject: lpcID
plusObject: sourceID
Filter: "no"
vocodedID = selected("Sound")
Rename: originalName$ + "_vocoded_" + presetName$

# Autocorrelation is retained for its v0.3 colour, but on some highly periodic
# or otherwise ill-conditioned inputs it can numerically run away. Detect only
# catastrophic growth and rerender with Burg; normal legacy renders are untouched.
selectObject: vocodedID
rawFilterPeak = Get absolute extremum: 0, 0, "None"
rawFilterRms = Get root-mean-square: 0, 0
legacyUnstable = 0
if rawFilterPeak = undefined
    legacyUnstable = 1
elsif rawFilterRms = undefined
    legacyUnstable = 1
elsif rawFilterPeak > 1e6
    legacyUnstable = 1
endif

lpcFallback = 0
if lPC_method = 1 and legacyUnstable
    appendInfoLine: " legacy LPC unstable; retrying with Burg."
    removeObject: vocodedID, lpcID
    selectObject: analysisID
    To LPC (burg): lPC_order, analysis_window, 0.005, pre_emphasis_hz
    lpcID = selected("LPC")
    usedLpcMethod$ = "Burg fallback"
    selectObject: lpcID
    plusObject: sourceID
    Filter: "no"
    vocodedID = selected("Sound")
    Rename: originalName$ + "_vocoded_" + presetName$
    lpcFallback = 1
endif
appendInfoLine: " done."

# --- 6. POST-PROCESSING ---

# A. Gain Compensation (silence-safe). A truly silent analysis input has no
# spectral envelope to transfer, so keep the final output silent rather than
# inventing an audible tone from the fallback excitation.
selectObject: vocodedID
if analysisInputRms <= 1e-12
    Formula: "0"
    outRmsBefore = 0
else
    outRmsBefore = Get root-mean-square: 0, 0
    if outRmsBefore = undefined
        exitScript: "LPC synthesis became numerically unstable even after the selected/fallback analysis."
    elsif outRmsBefore > 1e-15
        Scale intensity: target_intensity_dB
    endif
endif

# B. Whisper Brightness Correction
if preset = 4
    # Preserve the distinctive v0.3 recursive brightness colour. Because Formula
    # writes left-to-right, self[col-1] is the already-processed previous sample;
    # this is an IIR high-frequency lift, not a simple one-sample FIR difference.
    Formula: "self + 0.5 * (self - self[col-1])"
endif

# C. Safety ceiling only when needed; normal target-intensity renders are unchanged.
selectObject: vocodedID
outPeak = Get absolute extremum: 0, 0, "None"
if outPeak > 0.99
    Scale peak: 0.99
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "LPC Vocoder: " + originalName$ + " [" + presetName$ + "]"
    
    # Original / vocoded waveforms share one amplitude scale for a valid comparison.
    selectObject: originalID
    srcPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: vocodedID
    outPeakViz = Get absolute extremum: 0, 0, "None"
    wavePeakViz = 1.05 * max(srcPeakViz, outPeakViz)
    if wavePeakViz < 1e-9
        wavePeakViz = 1
    endif

    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, -wavePeakViz, wavePeakViz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    # Vocoded waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: vocodedID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, -wavePeakViz, wavePeakViz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Vocoded"
    
    # Original spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    Select inner viewport: 0.5, 3.7, 2.15, 3.65
    selectObject: originalID
    origSpecID = To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    selectObject: origSpecID
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    # Vocoded spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    Select inner viewport: 4.5, 7.7, 2.15, 3.65
    selectObject: vocodedID
    resSpecID = To Spectrogram: 0.01, 4000, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, 4000, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Vocoded Spectrogram"
    removeObject: resSpecID
    
    # Info panel
    Select outer viewport: 0, 8, 4.0, 4.6
    Select inner viewport: 0.5, 7.7, 4.05, 4.55
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.68, "half", "LPC: " + string$(lPC_order) + " | " + usedLpcMethod$
    if source_type = 1
        Text: 0.02, "left", 0.32, "half", "Excitation: continuous pitch-driven phonation"
    else
        if preset = 4
            Text: 0.02, "left", 0.32, "half", "Excitation: Gaussian noise + recursive brightness"
        else
            Text: 0.02, "left", 0.32, "half", "Excitation: Gaussian noise"
        endif
    endif
    Text: 0.52, "left", 0.68, "half", "Analysis ch: " + string$(analysisChannel) + " | window " + fixed$(analysis_window * 1000, 0) + " ms"
    if force_monotone and source_type = 1
        Text: 0.52, "left", 0.32, "half", "Monotone: " + string$(monotone_frequency) + " Hz | target " + string$(target_intensity_dB) + " dB"
    elsif source_type = 1
        Text: 0.52, "left", 0.32, "half", "Pitch bridge: " + string$(minimum_pitch) + "-" + string$(maximum_pitch) + " Hz | target " + string$(target_intensity_dB) + " dB"
    else
        Text: 0.52, "left", 0.32, "half", "Target intensity: " + string$(target_intensity_dB) + " dB"
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# --- 7. CLEANUP ---

removeObject: sourceID
removeObject: lpcID
removeObject: analysisID

selectObject: vocodedID

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", originalName$, "_vocoded_", presetName$
appendInfoLine: "Used LPC method: ", usedLpcMethod$

selectObject: vocodedID
if play_result
    Play
endif
selectObject: vocodedID