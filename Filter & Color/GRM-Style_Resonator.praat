# ============================================================
# Praat AudioTools - GRM-Style_Resonator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026) - Fix object[] channel indexing in mix; honest "GRM-style" naming
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   GRM-STYLE (not the GRM algorithm): evokes the tuned resonant-bank
#   textures of GRM Tools, but implemented as an OFFLINE Karplus-Strong /
#   delay-line resonator (Hann band-pass + feedback comb), NOT real-time
#   tunable resonant biquad filters. "GRM-style" = aesthetic lineage.
# - Pitch-Tracking Delays (Karplus-Strong style)
# - Spectral Tilt to tame high bands
# - Auto-leveling Wet signal before mixing (Safety)
# - NEW: Comprehensive 6-panel visualization
#
# Features:
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form GRM-Style Resonator v1.2
    comment === PRESET ===
    optionmenu Preset: 1
        option Custom
        option Harmonic (organ-like)
        option Inharmonic metallic
        option Formant-ish (voice coloring)
        option Sparse bells
    comment === GENERATOR SETTINGS ===
    integer numBands 6
    optionmenu tuningMode: 1
        option Manual list
        option Harmonic series
        option Inharmonic ratios
    sentence manualFrequencies 300 520 890 1440 2330 3770
    real baseFreqHz 110
    sentence ratioList 1 1.41 1.89 2.37 2.98 3.56
    real bandwidthHz 80
    comment === PHYSICS (RESONANCE) ===
    # NEW: If checked, delay is calculated as 1/freq
    boolean Tune_Delay_To_Pitch 1
    # Used only if Tune_Delay is unchecked
    real Manual_Ring_Delay_Ms 8
    integer ringIterations 3
    real ringDecay 0.6
    comment === GAIN & MIX ===
    real gainDB 6
    # NEW: Prevents high bands from screaming
    optionmenu Gain_Profile: 2
        option Flat (Equal)
        option Dampen Highs (Tilt Down)
        option Boost Highs (Tilt Up)
    comment === STEREO MIXER ===
    optionmenu Stereo_Panning: 3
        option All Center (Mono)
        option Stereo Spread (Alternate)
        option Wide Spread (Hard L/R)
        option Left Heavy
        option Right Heavy
        option V Shape (Outside In)
        option Random
    real dryWet 0.6
    real finalPeak 0.99
    comment === OUTPUT ===
    boolean Keep_individual_bands 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# --- 1. PRESETS ---
if preset = 2
    # Harmonic Organ
    tuningMode = 2
    baseFreqHz = 110
    numBands = 8
    bandwidthHz = 100
    tune_Delay_To_Pitch = 1
    ringIterations = 20
    ringDecay = 0.85
    gain_Profile = 2
    stereo_Panning = 2
    presetName$ = "HarmonicOrgan"
elsif preset = 3
    # Metallic
    tuningMode = 3
    baseFreqHz = 200
    ratioList$ = "1 1.59 2.14 2.76 3.41 4.07"
    numBands = 6
    bandwidthHz = 40
    tune_Delay_To_Pitch = 1
    ringIterations = 10
    ringDecay = 0.7
    gain_Profile = 1
    stereo_Panning = 3
    presetName$ = "Metallic"
elsif preset = 4
    # Voice Formants
    tuningMode = 1
    manualFrequencies$ = "500 1500 2500 3500 4500"
    numBands = 5
    bandwidthHz = 200
    tune_Delay_To_Pitch = 0
    manual_Ring_Delay_Ms = 6
    ringIterations = 2
    ringDecay = 0.4
    gain_Profile = 2
    stereo_Panning = 6
    presetName$ = "Formant"
elsif preset = 5
    # Bells
    tuningMode = 1
    manualFrequencies$ = "287 645 1203 2156"
    numBands = 4
    bandwidthHz = 35
    tune_Delay_To_Pitch = 1
    ringIterations = 40
    ringDecay = 0.95
    gain_Profile = 2
    gainDB = 12
    stereo_Panning = 7
    presetName$ = "Bells"
else
    presetName$ = "Custom"
endif

# --- 2. SETUP ---
numberOfSelected = numberOfSelected("Sound")
if numberOfSelected <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")
selectObject: original
samplingRate = Get sampling frequency
duration = Get total duration
nyquist = samplingRate / 2
numChannels = Get number of channels

# --- 3. PARSE FREQUENCIES ---
if tuningMode = 1
    str$ = manualFrequencies$
    count = 0
    repeat
        space = index(str$, " ")
        if space > 0
            token$ = left$(str$, space - 1)
            str$ = mid$(str$, space + 1, 10000)
        else
            token$ = str$
            str$ = ""
        endif
        token$ = replace$(token$, " ", "", 0)
        if token$ <> ""
            count = count + 1
            freqs[count] = number(token$)
        endif
    until str$ = ""
    actualNumBands = count
    tuningStr$ = "Manual List"
elsif tuningMode = 2
    actualNumBands = numBands
    for i from 1 to actualNumBands
        freqs[i] = baseFreqHz * i
    endfor
    tuningStr$ = "Harmonic (" + string$(baseFreqHz) + " Hz)"
elsif tuningMode = 3
    str$ = ratioList$
    count = 0
    repeat
        space = index(str$, " ")
        if space > 0
            token$ = left$(str$, space - 1)
            str$ = mid$(str$, space + 1, 10000)
        else
            token$ = str$
            str$ = ""
        endif
        token$ = replace$(token$, " ", "", 0)
        if token$ <> ""
            count = count + 1
            freqs[count] = baseFreqHz * number(token$)
        endif
    until str$ = ""
    actualNumBands = count
    tuningStr$ = "Inharmonic (" + string$(baseFreqHz) + " Hz)"
endif

if actualNumBands > numBands
    actualNumBands = numBands
endif

# --- 4. CALC GAIN PROFILE (TILT) ---
baseGainLin = 10^(gainDB/20)
for i from 1 to actualNumBands
    if gain_Profile = 1
        # Flat
        bandGain[i] = baseGainLin
        gainProfileStr$ = "Flat"
    elsif gain_Profile = 2
        # Dampen Highs
        factor = 1.0 - (0.8 * (i - 1) / actualNumBands)
        bandGain[i] = baseGainLin * factor
        gainProfileStr$ = "Dampen Highs"
    elsif gain_Profile = 3
        # Boost Highs
        factor = 0.2 + (0.8 * (i - 1) / actualNumBands)
        bandGain[i] = baseGainLin * factor
        gainProfileStr$ = "Boost Highs"
    endif
endfor

# --- 5. GENERATION LOOP ---
clearinfo
appendInfoLine: "Generating ", actualNumBands, " bands..."

for i from 1 to actualNumBands
    fc = freqs[i]
    low = fc - bandwidthHz/2
    high = fc + bandwidthHz/2
    
    # CLAMP EDGES
    if low < 20 
        low = 20 
    endif
    if high > nyquist - 20
        high = nyquist - 20
    endif
    if low >= high
        low = fc - 10
        high = fc + 10
    endif

    # A. Copy to Temp
    selectObject: original
    tempSource = Copy: "temp_source"
    
    # B. Filter
    Filter (pass Hann band): low, high, 100
    bandSound = selected("Sound")

    # Bands are positioned in the stereo field by the panner below, so each
    # band must be a single (mono) signal. Convert if the source was stereo
    # (otherwise object[band, col] below would only read channel 1 and the
    # panning would be inconsistent).
    selectObject: bandSound
    bandCh = Get number of channels
    if bandCh > 1
        monoBand = Convert to mono
        removeObject: bandSound
        bandSound = monoBand
    endif
    
    # C. Cleanup Temp
    selectObject: tempSource
    Remove
    
    # D. Process Band
    selectObject: bandSound
    
    # Apply Gain
    Formula: "self * " + string$(bandGain[i])
    
    # Apply Resonator Physics
    if ringIterations > 0
        if tune_Delay_To_Pitch
            # TUNED MODE: 1000 ms / Hz
            delSamples = round((1000.0 / fc) * samplingRate / 1000.0)
        else
            # MANUAL MODE
            if manual_Ring_Delay_Ms > 0
                delSamples = round(manual_Ring_Delay_Ms * samplingRate / 1000.0)
            else
                delSamples = 1
            endif
        endif
        
        if delSamples < 1 
            delSamples = 1 
        endif
        
        for it from 1 to ringIterations
            decay = ringDecay ^ it
            currentDel = delSamples * it
            Formula: "if col > " + string$(currentDel) + " then self + " + string$(decay) + " * self[col-" + string$(currentDel) + "] else self fi"
        endfor
    endif
    
    # E. Rename and Store
    Rename: "band" + string$(i)
    bandIDs[i] = selected("Sound")
    
    appendInfoLine: "Band ", i, ": ", fixed$(fc,0), " Hz (Delay: ", delSamples, " spls)"
endfor

# --- 6. PREPARE MIXER PANS ---
# FIXED: Commands are now on separate lines (semicolons removed)
for i from 1 to actualNumBands
    if stereo_Panning = 1
        # Mono
        pL[i] = 1.0
        pR[i] = 1.0
        panningStr$ = "Center Mono"
    elsif stereo_Panning = 2
        # Spread (Alternate)
        if (i mod 2) = 1
            pL[i] = 1.0
            pR[i] = 0.3
        else
            pL[i] = 0.3
            pR[i] = 1.0
        endif
        panningStr$ = "Stereo Alternate"
    elsif stereo_Panning = 3
        # Wide Spread (Hard)
        if (i mod 2) = 1
            pL[i] = 1.0
            pR[i] = 0.0
        else
            pL[i] = 0.0
            pR[i] = 1.0
        endif
        panningStr$ = "Hard L/R"
    elsif stereo_Panning = 4
        # Left Heavy
        pL[i] = 1.0
        pR[i] = 0.3
        panningStr$ = "Left Heavy"
    elsif stereo_Panning = 5
        # Right Heavy
        pL[i] = 0.3
        pR[i] = 1.0
        panningStr$ = "Right Heavy"
    elsif stereo_Panning = 6
        # V Shape
        mid = (actualNumBands + 1) / 2
        if i <= mid
            if mid > 1
                prog = (i - 1) / (mid - 1)
            else
                prog = 0
            endif
            pL[i] = 1.0 - prog * 0.7
            pR[i] = 0.3 + prog * 0.7
        else
            rem = actualNumBands - mid
            if rem > 0
                prog = (i - mid) / rem
            else
                prog = 0
            endif
            pL[i] = 0.3 + prog * 0.7
            pR[i] = 1.0 - prog * 0.7
        endif
        panningStr$ = "V-Shape"
    elsif stereo_Panning = 7
        # Random
        rr = randomUniform(0, 1)
        pL[i] = 1.0 - rr
        pR[i] = rr
        panningStr$ = "Random"
    endif
endfor

# --- 7. STEREO MIXING ---
appendInfoLine: "Mixing..."

Create Sound from formula: "Wet_Mix", 2, 0, duration, samplingRate, "0"
wetSum = selected("Sound")

for i from 1 to actualNumBands
    theBand = bandIDs[i]
    valL = pL[i]
    valR = pR[i]
    
    selectObject: wetSum, theBand
    Formula (part): 0, 0, 1, 1, "self + (object[" + string$(theBand) + ", col] * " + string$(valL) + ")"
    Formula (part): 0, 0, 2, 2, "self + (object[" + string$(theBand) + ", col] * " + string$(valR) + ")"
endfor

# --- 8. WET SAFETY & FINAL MIX ---

selectObject: wetSum
# Safety: Normalize Wet signal (0.9) to prevent mathematical clipping in the summing stage
Scale peak: 0.9

# Handle different dry/wet scenarios
if dryWet >= 0.999
    # Full wet - no dry signal needed
    selectObject: wetSum
    Rename: originalName$ + "_GRMstyle_" + presetName$
    output = selected("Sound")
elsif dryWet <= 0.001
    # Full dry - no wet signal needed
    selectObject: original
    if numChannels = 1
        Convert to stereo
        output = selected("Sound")
    else
        output = Copy: originalName$ + "_GRMstyle_" + presetName$
    endif
    selectObject: wetSum
    Remove
else
    # Mixed signal
    selectObject: original
    dry = Copy: "dry_temp"
    
    # Ensure Dry is Stereo
    if numChannels = 1
        Convert to stereo
        stereoDry = selected("Sound")
        selectObject: dry
        Remove
        dry = stereoDry
    endif
    
    # Apply Dry/Wet Levels
    selectObject: dry
    Formula: "self * " + string$(1 - dryWet)
    
    selectObject: wetSum
    Formula: "self * " + string$(dryWet)
    
    # Sum (both dry and wetSum are stereo -> index row and col)
    selectObject: dry, wetSum
    Formula: ~ self + object[wetSum, row, col]
    
    # Finalize
    selectObject: dry
    Rename: originalName$ + "_GRMstyle_" + presetName$
    output = selected("Sound")
    
    # Cleanup
    selectObject: wetSum
    Remove
endif

# Final peak scaling
selectObject: output
Scale peak: finalPeak

selectObject: output
appendInfoLine: "Finished."

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # --- TITLE PANEL ---
    Select outer viewport: 0, 8, 0, 0.6
    Select inner viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "GRM-Style Resonator: " + originalName$ + " [" + presetName$ + "]"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.25, "half", "Pitch-Tracking Delays | Spectral Tilt | Stereo Architecture"
    
    # --- 1. ORIGINAL WAVEFORM ---
    Select outer viewport: 0, 4, 0.7, 2.0
    Select inner viewport: 0.6, 3.7, 0.8, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original Signal"
    
    # --- 2. BAND FREQUENCY ARCHITECTURE ---
    Select outer viewport: 4, 8, 0.7, 2.0
    Select inner viewport: 4.4, 7.7, 0.8, 1.9
    
    # Find frequency range
    minFreq = freqs[1]
    maxFreq = freqs[1]
    for i from 1 to actualNumBands
        if freqs[i] < minFreq
            minFreq = freqs[i]
        endif
        if freqs[i] > maxFreq
            maxFreq = freqs[i]
        endif
    endfor
    
    # Add padding
    freqRange = maxFreq - minFreq
    plotMinFreq = max(20, minFreq - freqRange * 0.1)
    plotMaxFreq = min(nyquist, maxFreq + freqRange * 0.1)
    
    Axes: 0, actualNumBands + 1, plotMinFreq, plotMaxFreq
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actualNumBands + 1, plotMinFreq, plotMaxFreq
    
    # Draw bands
    for i from 1 to actualNumBands
        fc = freqs[i]
        low = fc - bandwidthHz/2
        high = fc + bandwidthHz/2
        
        # Clamp
        if low < 20
            low = 20
        endif
        if high > nyquist - 20
            high = nyquist - 20
        endif
        
        # Color based on gain profile
        if gain_Profile = 1
            bandColor$ = "{0.3, 0.5, 0.8}"
        elsif gain_Profile = 2
            # Darker for damped bands
            darkness = 0.3 + 0.5 * (1 - (i - 1) / actualNumBands)
            bandColor$ = "{" + fixed$(darkness * 0.3, 2) + ", " + fixed$(darkness * 0.5, 2) + ", " + fixed$(darkness * 0.8, 2) + "}"
        elsif gain_Profile = 3
            # Brighter for boosted bands
            brightness = 0.2 + 0.8 * ((i - 1) / actualNumBands)
            bandColor$ = "{" + fixed$(0.3 + brightness * 0.4, 2) + ", " + fixed$(0.5 + brightness * 0.3, 2) + ", 0.8}"
        endif
        
        Colour: bandColor$
        Paint rectangle: bandColor$, i - 0.3, i + 0.3, low, high
        
        # Center line
        Colour: "{0.8, 0.3, 0.3}"
        Line width: 2
        Draw line: i, fc, i, fc
        Line width: 1
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Band Architecture"
    Text bottom: "yes", "Band Number"
    
    # --- 3. STEREO PANNING VISUALIZATION ---
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.7, 2.2, 3.4
    
    Axes: 0, actualNumBands + 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actualNumBands + 1, 0, 1
    
    # Draw panning for each band
    for i from 1 to actualNumBands
        # Left channel
        Colour: "{0.9, 0.7, 0.3}"
        Paint rectangle: "{0.9, 0.7, 0.3}", i - 0.35, i, 0.5, 0.5 + pL[i] * 0.45
        
        # Right channel
        Colour: "{0.3, 0.6, 0.8}"
        Paint rectangle: "{0.3, 0.6, 0.8}", i, i + 0.35, 0.5, 0.5 - pR[i] * 0.45
        
        # Center line
        Colour: "{0.7, 0.7, 0.7}"
        Dotted line
        Draw line: i - 0.4, 0.5, i + 0.4, 0.5
        Solid line
    endfor
    
    # Center reference
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 1.5
    Draw line: 0, 0.5, actualNumBands + 1, 0.5
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Pan Position"
    Text top: "no", "Stereo Panning: " + panningStr$
    Text bottom: "yes", "Band Number"
    
    # Legend
    Font size: 6
    Colour: "{0.9, 0.7, 0.3}"
    Paint rectangle: "{0.9, 0.7, 0.3}", 0.3, 0.8, 0.85, 0.92
    Colour: "Black"
    Text: 1.0, "left", 0.885, "half", "Left"
    
    Colour: "{0.3, 0.6, 0.8}"
    Paint rectangle: "{0.3, 0.6, 0.8}", 0.3, 0.8, 0.08, 0.15
    Colour: "Black"
    Text: 1.0, "left", 0.115, "half", "Right"
    
    # --- 4. PROCESSED WAVEFORM ---
    Select outer viewport: 0, 8, 3.6, 4.9
    Select inner viewport: 0.6, 7.7, 3.7, 4.8
    selectObject: output
    Colour: "{0.2, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Processed Signal (Stereo)"
    Text bottom: "yes", "Time (s)"
    
    # --- 5. GAIN PROFILE VISUALIZATION ---
    Select outer viewport: 0, 4, 5.0, 6.2
    Select inner viewport: 0.6, 3.7, 5.1, 6.1
    
    Axes: 0, actualNumBands + 1, 0, baseGainLin * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, actualNumBands + 1, 0, baseGainLin * 1.2
    
    # Draw gain profile
    Colour: "{0.7, 0.3, 0.7}"
    Line width: 3
    for i from 1 to actualNumBands - 1
        Draw line: i, bandGain[i], i + 1, bandGain[i + 1]
    endfor
    Line width: 1
    
    # Mark points
    for i from 1 to actualNumBands
        Colour: "{0.5, 0.2, 0.5}"
        Paint circle: "Magenta", i, bandGain[i], 0.15
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain (Linear)"
    Text top: "no", "Gain Profile: " + gainProfileStr$
    Text bottom: "yes", "Band Number"
    
    # --- 6. INFO PANEL ---
    Select outer viewport: 4, 8, 5.0, 6.2
    Select inner viewport: 4.4, 7.7, 5.1, 6.1
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    
    # Left column
    Text: 0.05, "left", 0.85, "half", "Processing Parameters"
    Text: 0.05, "left", 0.70, "half", "Bands: " + string$(actualNumBands)
    Text: 0.05, "left", 0.58, "half", "Tuning: " + tuningStr$
    Text: 0.05, "left", 0.46, "half", "Bandwidth: " + string$(bandwidthHz) + " Hz"
    Text: 0.05, "left", 0.34, "half", "Ring: " + string$(ringIterations) + " iter"
    Text: 0.05, "left", 0.22, "half", "Decay: " + fixed$(ringDecay, 2)
    Text: 0.05, "left", 0.10, "half", "Tuned Delay: " + if tune_Delay_To_Pitch then "Yes" else "No" fi
    
    # Right column
    Text: 0.55, "left", 0.70, "half", "Gain: " + string$(gainDB) + " dB"
    Text: 0.55, "left", 0.58, "half", "Tilt: " + gainProfileStr$
    Text: 0.55, "left", 0.46, "half", "Panning: " + panningStr$
    Text: 0.55, "left", 0.34, "half", "Dry/Wet: " + fixed$(dryWet * 100, 0) + "% wet"
    Text: 0.55, "left", 0.22, "half", "Peak: " + fixed$(finalPeak, 2)
    Text: 0.55, "left", 0.10, "half", "Duration: " + fixed$(duration, 2) + " s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    
    appendInfoLine: "Visualization complete"
endif

# --- CLEANUP ---
if keep_individual_bands = 0
    selectObject: bandIDs[1]
    for i from 2 to actualNumBands
        plusObject: bandIDs[i]
    endfor
    Remove
endif

selectObject: output
appendInfoLine: "=== Complete ==="
if play_result
    Play
endif
