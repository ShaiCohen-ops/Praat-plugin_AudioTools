# ============================================================
# Praat AudioTools - BrightnessClassifier.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025) - Full feature set
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Comprehensive Audio Brightness Classifier with multiple spectral
#   metrics, time-varying analysis, customizable thresholds, and
#   enhanced visualization including brightness trajectory.
#
# Features:
#   - Spectral centroid, spread, rolloff, flux, crest factor
#   - Presets for speech, music, percussion, ambient
#   - Custom brightness thresholds
#   - Time-varying brightness trajectory
#   - Comparison mode for two sounds
#   - Color-coded category display with brightness meter
#
# Usage:
#   Select one or more Sound objects in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis 
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

clearinfo

# === INPUT VALIDATION ===
number_of_selected_sounds = numberOfSelected("Sound")
if number_of_selected_sounds = 0
    exitScript: "Please select at least one Sound object first."
endif

# Store references
for index to number_of_selected_sounds
    sound'index' = selected("Sound", index)
endfor

# === USER PARAMETERS ===
form Audio Brightness Classifier v1.0
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Speech (voice-optimized)
        option Music (full spectrum)
        option Percussion (transient-focused)
        option Ambient (low frequency emphasis)
        option Bright Sources (synths, strings)
    
    comment === Frequency Bands (Hz) ===
    positive Bass_upper 200
    positive Low_mid_upper 800
    positive High_mid_upper 4000
    positive High_upper 12000
    
    comment === Brightness Thresholds (Hz) ===
    positive Threshold_very_dark 300
    positive Threshold_dark 600
    positive Threshold_medium 1200
    positive Threshold_bright 2000
    
    comment === Analysis ===
    positive Time_step_(s) 0.05
    positive Rolloff_percent 85
    
    comment === Visualization ===
    boolean Draw_visualization 1
    boolean Show_time_analysis 1
    boolean Comparison_mode 0
    boolean Play_result 0
endform

# === APPLY PRESETS ===
if preset = 2
    # Speech
    bass_upper = 250
    low_mid_upper = 1000
    high_mid_upper = 4000
    high_upper = 8000
    threshold_very_dark = 400
    threshold_dark = 700
    threshold_medium = 1100
    threshold_bright = 1600
    presetName$ = "Speech"
elsif preset = 3
    # Music
    bass_upper = 200
    low_mid_upper = 800
    high_mid_upper = 4000
    high_upper = 12000
    threshold_very_dark = 300
    threshold_dark = 600
    threshold_medium = 1200
    threshold_bright = 2000
    presetName$ = "Music"
elsif preset = 4
    # Percussion
    bass_upper = 150
    low_mid_upper = 500
    high_mid_upper = 3000
    high_upper = 10000
    threshold_very_dark = 500
    threshold_dark = 1000
    threshold_medium = 2000
    threshold_bright = 3500
    presetName$ = "Percussion"
elsif preset = 5
    # Ambient
    bass_upper = 300
    low_mid_upper = 1200
    high_mid_upper = 5000
    high_upper = 10000
    threshold_very_dark = 200
    threshold_dark = 400
    threshold_medium = 800
    threshold_bright = 1400
    presetName$ = "Ambient"
elsif preset = 6
    # Bright Sources
    bass_upper = 200
    low_mid_upper = 600
    high_mid_upper = 3000
    high_upper = 15000
    threshold_very_dark = 600
    threshold_dark = 1200
    threshold_medium = 2200
    threshold_bright = 3500
    presetName$ = "BrightSources"
else
    presetName$ = "Custom"
endif

# Check comparison mode requirements
if comparison_mode and number_of_selected_sounds < 2
    comparison_mode = 0
    appendInfoLine: "Note: Comparison mode requires 2 sounds. Disabled."
endif

# === SETUP ===
writeInfoLine: "=============================================="
writeInfoLine: "  BRIGHTNESS CLASSIFIER v1.0"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Files to process: ", number_of_selected_sounds
appendInfoLine: ""

# Arrays for batch processing
for i to number_of_selected_sounds
    sound_names$[i] = ""
    centroids[i] = 0
    spreads[i] = 0
    rolloffs[i] = 0
    crests[i] = 0
    categories$[i] = ""
    bass_energy[i] = 0
    low_mid_energy[i] = 0
    high_mid_energy[i] = 0
    high_energy[i] = 0
endfor

# ============================================================
# PROCEDURE: Calculate spectral metrics
# ============================================================
procedure calculateMetrics: .soundID
    selectObject: .soundID
    .name$ = selected$("Sound")
    .duration = Get total duration
    .sampleRate = Get sampling frequency
    .nyquist = .sampleRate / 2
    
    # Clamp high_upper to nyquist
    .actualHighUpper = min(high_upper, .nyquist - 100)
    
    # === Overall Spectrum ===
    selectObject: .soundID
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")
    
    # === Band Energies ===
    selectObject: .spectrum
    .bass = Get band energy: 20, bass_upper
    .lowMid = Get band energy: bass_upper, low_mid_upper
    .highMid = Get band energy: low_mid_upper, high_mid_upper
    .high = Get band energy: high_mid_upper, .actualHighUpper
    
    .totalEnergy = .bass + .lowMid + .highMid + .high
    
    # === Spectral Centroid ===
    if .totalEnergy > 0
        .bassCenterFreq = (20 + bass_upper) / 2
        .lowMidCenterFreq = (bass_upper + low_mid_upper) / 2
        .highMidCenterFreq = (low_mid_upper + high_mid_upper) / 2
        .highCenterFreq = (high_mid_upper + .actualHighUpper) / 2
        
        .centroid = ((.bass * .bassCenterFreq) + (.lowMid * .lowMidCenterFreq) + (.highMid * .highMidCenterFreq) + (.high * .highCenterFreq)) / .totalEnergy
    else
        .centroid = 0
    endif
    
    # === Spectral Spread (standard deviation around centroid) ===
    if .totalEnergy > 0
        .variance = ((.bass * (.bassCenterFreq - .centroid)^2) + (.lowMid * (.lowMidCenterFreq - .centroid)^2) + (.highMid * (.highMidCenterFreq - .centroid)^2) + (.high * (.highCenterFreq - .centroid)^2)) / .totalEnergy
        .spread = sqrt(.variance)
    else
        .spread = 0
    endif
    
    # === Spectral Rolloff (frequency below which X% of energy lies) ===
    .cumulativeEnergy = 0
    .targetEnergy = .totalEnergy * (rolloff_percent / 100)
    .rolloff = .actualHighUpper
    .rolloffFound = 0
    
    # Sample at multiple frequency points
    .freqStep = 50
    .freq = 20
    while .freq < .actualHighUpper and .rolloffFound = 0
        selectObject: .spectrum
        .bandE = Get band energy: .freq, .freq + .freqStep
        .cumulativeEnergy = .cumulativeEnergy + .bandE
        
        if .cumulativeEnergy >= .targetEnergy
            .rolloff = .freq
            .rolloffFound = 1
        endif
        
        .freq = .freq + .freqStep
    endwhile
    
    # === Crest Factor (peak to RMS ratio) ===
    selectObject: .soundID
    .rms = Get root-mean-square: 0, 0
    .peak = Get maximum: 0, 0, "Sinc70"
    
    if .rms > 0
        .crest = .peak / .rms
    else
        .crest = 0
    endif
    
    # === Classification ===
    if .centroid < threshold_very_dark
        .category$ = "very_dark"
    elsif .centroid < threshold_dark
        .category$ = "dark"
    elsif .centroid < threshold_medium
        .category$ = "medium"
    elsif .centroid < threshold_bright
        .category$ = "bright"
    else
        .category$ = "very_bright"
    endif
    
    # Cleanup
    removeObject: .spectrum
endproc

# ============================================================
# PROCEDURE: Time-varying brightness analysis
# ============================================================
procedure timeVaryingAnalysis: .soundID, .arrayIndex
    selectObject: .soundID
    .duration = Get total duration
    .sampleRate = Get sampling frequency
    .nyquist = .sampleRate / 2
    .actualHighUpper = min(high_upper, .nyquist - 100)
    
    .numFrames = floor(.duration / time_step)
    if .numFrames < 2
        .numFrames = 2
    endif
    if .numFrames > 200
        .numFrames = 200
    endif
    
    # Store time-varying centroids
    for .f from 1 to .numFrames
        timePoints[.arrayIndex, .f] = 0
        timeCentroids[.arrayIndex, .f] = 0
    endfor
    numTimeFrames[.arrayIndex] = .numFrames
    
    .prevCentroid = 0
    .totalFlux = 0
    
    for .frame from 1 to .numFrames
        .frameStart = (.frame - 1) * time_step
        .frameEnd = min(.frameStart + time_step * 2, .duration)
        .frameMid = (.frameStart + .frameEnd) / 2
        
        timePoints[.arrayIndex, .frame] = .frameMid
        
        # Extract frame
        selectObject: .soundID
        .frameSound = Extract part: .frameStart, .frameEnd, "Hanning", 1, "no"
        
        To Spectrum: "yes"
        .frameSpec = selected("Spectrum")
        
        # Calculate frame centroid
        selectObject: .frameSpec
        .bass = Get band energy: 20, bass_upper
        .lowMid = Get band energy: bass_upper, low_mid_upper
        .highMid = Get band energy: low_mid_upper, high_mid_upper
        .high = Get band energy: high_mid_upper, .actualHighUpper
        
        .totalE = .bass + .lowMid + .highMid + .high
        
        if .totalE > 0
            .bassCF = (20 + bass_upper) / 2
            .lowMidCF = (bass_upper + low_mid_upper) / 2
            .highMidCF = (low_mid_upper + high_mid_upper) / 2
            .highCF = (high_mid_upper + .actualHighUpper) / 2
            
            .frameCentroid = ((.bass * .bassCF) + (.lowMid * .lowMidCF) + (.highMid * .highMidCF) + (.high * .highCF)) / .totalE
        else
            .frameCentroid = 0
        endif
        
        timeCentroids[.arrayIndex, .frame] = .frameCentroid
        
        # Spectral flux (change from previous frame)
        if .frame > 1
            .totalFlux = .totalFlux + abs(.frameCentroid - .prevCentroid)
        endif
        .prevCentroid = .frameCentroid
        
        removeObject: .frameSound, .frameSpec
    endfor
    
    # Average flux
    if .numFrames > 1
        spectralFlux[.arrayIndex] = .totalFlux / (.numFrames - 1)
    else
        spectralFlux[.arrayIndex] = 0
    endif
endproc

# ============================================================
# PROCEDURE: Get category color
# ============================================================
procedure getCategoryColor: .category$
    if .category$ = "very_dark"
        categoryColor$ = "{0.2, 0.2, 0.4}"
        categoryColorLight$ = "{0.3, 0.3, 0.5}"
    elsif .category$ = "dark"
        categoryColor$ = "{0.3, 0.4, 0.6}"
        categoryColorLight$ = "{0.4, 0.5, 0.7}"
    elsif .category$ = "medium"
        categoryColor$ = "{0.4, 0.6, 0.4}"
        categoryColorLight$ = "{0.5, 0.7, 0.5}"
    elsif .category$ = "bright"
        categoryColor$ = "{0.7, 0.6, 0.3}"
        categoryColorLight$ = "{0.8, 0.7, 0.4}"
    else
        categoryColor$ = "{0.8, 0.4, 0.3}"
        categoryColorLight$ = "{0.9, 0.5, 0.4}"
    endif
endproc

# ============================================================
# MAIN PROCESSING
# ============================================================

for current_sound_index from 1 to number_of_selected_sounds
    select sound'current_sound_index'
    sound_name$ = selected$("Sound")
    sound_names$[current_sound_index] = sound_name$
    
    appendInfoLine: "Processing: ", sound_name$
    
    # Calculate metrics
    @calculateMetrics: sound'current_sound_index'
    
    centroids[current_sound_index] = calculateMetrics.centroid
    spreads[current_sound_index] = calculateMetrics.spread
    rolloffs[current_sound_index] = calculateMetrics.rolloff
    crests[current_sound_index] = calculateMetrics.crest
    categories$[current_sound_index] = calculateMetrics.category$
    bass_energy[current_sound_index] = calculateMetrics.bass
    low_mid_energy[current_sound_index] = calculateMetrics.lowMid
    high_mid_energy[current_sound_index] = calculateMetrics.highMid
    high_energy[current_sound_index] = calculateMetrics.high
    
    # Time-varying analysis
    if show_time_analysis
        @timeVaryingAnalysis: sound'current_sound_index', current_sound_index
    endif
    
    # Output
    appendInfoLine: "  Centroid: ", fixed$(centroids[current_sound_index], 0), " Hz → ", categories$[current_sound_index]
    appendInfoLine: "  Spread: ", fixed$(spreads[current_sound_index], 0), " Hz"
    appendInfoLine: "  Rolloff (", rolloff_percent, "%): ", fixed$(rolloffs[current_sound_index], 0), " Hz"
    appendInfoLine: "  Crest: ", fixed$(crests[current_sound_index], 2)
    if show_time_analysis
        appendInfoLine: "  Flux: ", fixed$(spectralFlux[current_sound_index], 1), " Hz/frame"
    endif
    appendInfoLine: ""
endfor

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    
    # === COMPARISON MODE (2 sounds side by side) ===
    if comparison_mode and number_of_selected_sounds >= 2
        appendInfoLine: "Drawing comparison visualization..."
        Erase all
        
        # Title
        Select outer viewport: 0, 8, 0, 0.6
        Axes: 0, 1, 0, 1
        Font size: 12
        Colour: "Black"
        Text: 0.5, "centre", 0.6, "half", "##Brightness Comparison##"
        Font size: 9
        Colour: "{0.4, 0.4, 0.5}"
        Text: 0.5, "centre", 0.2, "half", sound_names$[1] + " vs " + sound_names$[2]
        
        # === Left: Sound 1 Spectrogram ===
        Select outer viewport: 0, 4, 0.7, 2.3
        Select inner viewport: 0.5, 3.8, 0.8, 2.2
        
        select sound1
        To Spectrogram: 0.03, 8000, 0.002, 20, "Gaussian"
        spec1 = selected("Spectrogram")
        Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", sound_names$[1]
        
        removeObject: spec1
        
        # === Right: Sound 2 Spectrogram ===
        Select outer viewport: 4, 8, 0.7, 2.3
        Select inner viewport: 4.4, 7.8, 0.8, 2.2
        
        select sound2
        To Spectrogram: 0.03, 8000, 0.002, 20, "Gaussian"
        spec2 = selected("Spectrogram")
        Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", sound_names$[2]
        
        removeObject: spec2
        
        # === Brightness Meters ===
        Select outer viewport: 0, 8, 2.4, 3.6
        Select inner viewport: 0.5, 7.5, 2.5, 3.5
        
        # Meter background
        Axes: 0, 1, 0, 1
        
        # Draw meter scale
        meterLeft = 0.05
        meterRight = 0.95
        meterWidth = meterRight - meterLeft
        
        # Color gradient background
        numGradientSteps = 50
        for g from 1 to numGradientSteps
            gPos = (g - 1) / numGradientSteps
            gX1 = meterLeft + gPos * meterWidth
            gX2 = meterLeft + (g / numGradientSteps) * meterWidth
            
            # Dark to bright gradient
            gR = 0.2 + gPos * 0.7
            gG = 0.2 + gPos * 0.3
            gB = 0.5 - gPos * 0.3
            
            Paint rectangle: "{" + fixed$(gR, 2) + "," + fixed$(gG, 2) + "," + fixed$(gB, 2) + "}", gX1, gX2, 0.55, 0.75
            Paint rectangle: "{" + fixed$(gR, 2) + "," + fixed$(gG, 2) + "," + fixed$(gB, 2) + "}", gX1, gX2, 0.25, 0.45
        endfor
        
        # Threshold markers
        Colour: "White"
        Line width: 1
        
        maxCentroidDisplay = threshold_bright * 1.5
        
        t1Pos = meterLeft + (threshold_very_dark / maxCentroidDisplay) * meterWidth
        t2Pos = meterLeft + (threshold_dark / maxCentroidDisplay) * meterWidth
        t3Pos = meterLeft + (threshold_medium / maxCentroidDisplay) * meterWidth
        t4Pos = meterLeft + (threshold_bright / maxCentroidDisplay) * meterWidth
        
        Draw line: t1Pos, 0.55, t1Pos, 0.75
        Draw line: t2Pos, 0.55, t2Pos, 0.75
        Draw line: t3Pos, 0.55, t3Pos, 0.75
        Draw line: t4Pos, 0.55, t4Pos, 0.75
        
        Draw line: t1Pos, 0.25, t1Pos, 0.45
        Draw line: t2Pos, 0.25, t2Pos, 0.45
        Draw line: t3Pos, 0.25, t3Pos, 0.45
        Draw line: t4Pos, 0.25, t4Pos, 0.45
        
        # Sound 1 marker
        c1Pos = meterLeft + min(1, centroids[1] / maxCentroidDisplay) * meterWidth
        Colour: "Black"
        Line width: 3
        Draw line: c1Pos, 0.52, c1Pos, 0.78
        
        Font size: 7
        Text: c1Pos, "centre", 0.85, "half", fixed$(centroids[1], 0) + " Hz"
        
        # Sound 2 marker
        c2Pos = meterLeft + min(1, centroids[2] / maxCentroidDisplay) * meterWidth
        Draw line: c2Pos, 0.22, c2Pos, 0.48
        Text: c2Pos, "centre", 0.15, "half", fixed$(centroids[2], 0) + " Hz"
        
        # Labels
        Font size: 6
        Colour: "{0.3, 0.3, 0.3}"
        Text: meterLeft, "left", 0.65, "half", sound_names$[1]
        Text: meterLeft, "left", 0.35, "half", sound_names$[2]
        
        # Category labels
        @getCategoryColor: categories$[1]
        Colour: categoryColor$
        Text: meterRight, "right", 0.65, "half", categories$[1]
        
        @getCategoryColor: categories$[2]
        Colour: categoryColor$
        Text: meterRight, "right", 0.35, "half", categories$[2]
        
        Line width: 1
        
        # === Time-varying comparison ===
        if show_time_analysis
            Select outer viewport: 0, 8, 3.7, 5.3
            Select inner viewport: 0.6, 7.6, 3.8, 5.2
            
            # Find axis range
            minC = centroids[1]
            maxC = centroids[1]
            maxDur = 0
            
            for s from 1 to 2
                select sound's'
                dur = Get total duration
                if dur > maxDur
                    maxDur = dur
                endif
                
                for f from 1 to numTimeFrames[s]
                    if timeCentroids[s, f] < minC and timeCentroids[s, f] > 0
                        minC = timeCentroids[s, f]
                    endif
                    if timeCentroids[s, f] > maxC
                        maxC = timeCentroids[s, f]
                    endif
                endfor
            endfor
            
            minC = max(0, minC - 200)
            maxC = maxC + 200
            
            Axes: 0, maxDur, minC, maxC
            Paint rectangle: "{0.97, 0.98, 1.0}", 0, maxDur, minC, maxC
            
            # Threshold lines
            Colour: "{0.85, 0.85, 0.9}"
            Line width: 1
            if threshold_very_dark > minC and threshold_very_dark < maxC
                Draw line: 0, threshold_very_dark, maxDur, threshold_very_dark
            endif
            if threshold_dark > minC and threshold_dark < maxC
                Draw line: 0, threshold_dark, maxDur, threshold_dark
            endif
            if threshold_medium > minC and threshold_medium < maxC
                Draw line: 0, threshold_medium, maxDur, threshold_medium
            endif
            if threshold_bright > minC and threshold_bright < maxC
                Draw line: 0, threshold_bright, maxDur, threshold_bright
            endif
            
            # Draw trajectories
            # Sound 1 - Blue
            Colour: "{0.2, 0.4, 0.8}"
            Line width: 2
            for f from 2 to numTimeFrames[1]
                if timeCentroids[1, f-1] > 0 and timeCentroids[1, f] > 0
                    Draw line: timePoints[1, f-1], timeCentroids[1, f-1], timePoints[1, f], timeCentroids[1, f]
                endif
            endfor
            
            # Sound 2 - Orange
            Colour: "{0.9, 0.5, 0.2}"
            for f from 2 to numTimeFrames[2]
                if timeCentroids[2, f-1] > 0 and timeCentroids[2, f] > 0
                    Draw line: timePoints[2, f-1], timeCentroids[2, f-1], timePoints[2, f], timeCentroids[2, f]
                endif
            endfor
            
            Line width: 1
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Centroid (Hz)"
            Text bottom: "yes", "Time (s)"
            Marks left: 4, "yes", "yes", "no"
            
            # Legend
            Font size: 6
            Colour: "{0.2, 0.4, 0.8}"
            Text: maxDur * 0.02, "left", maxC - 50, "half", sound_names$[1]
            Colour: "{0.9, 0.5, 0.2}"
            Text: maxDur * 0.02, "left", maxC - 150, "half", sound_names$[2]
        endif
        
        # === Metrics comparison table ===
        Select outer viewport: 0, 8, 5.4, 6.8
        Axes: 0, 1, 0, 1
        
        Font size: 8
        Colour: "Black"
        
        # Headers
        Text: 0.35, "centre", 0.9, "half", sound_names$[1]
        Text: 0.65, "centre", 0.9, "half", sound_names$[2]
        
        # Metrics
        Font size: 7
        Colour: "{0.4, 0.4, 0.4}"
        
        Text: 0.08, "left", 0.7, "half", "Centroid:"
        Text: 0.35, "centre", 0.7, "half", fixed$(centroids[1], 0) + " Hz"
        Text: 0.65, "centre", 0.7, "half", fixed$(centroids[2], 0) + " Hz"
        
        Text: 0.08, "left", 0.55, "half", "Spread:"
        Text: 0.35, "centre", 0.55, "half", fixed$(spreads[1], 0) + " Hz"
        Text: 0.65, "centre", 0.55, "half", fixed$(spreads[2], 0) + " Hz"
        
        Text: 0.08, "left", 0.4, "half", "Rolloff:"
        Text: 0.35, "centre", 0.4, "half", fixed$(rolloffs[1], 0) + " Hz"
        Text: 0.65, "centre", 0.4, "half", fixed$(rolloffs[2], 0) + " Hz"
        
        Text: 0.08, "left", 0.25, "half", "Crest:"
        Text: 0.35, "centre", 0.25, "half", fixed$(crests[1], 2)
        Text: 0.65, "centre", 0.25, "half", fixed$(crests[2], 2)
        
        if show_time_analysis
            Text: 0.08, "left", 0.1, "half", "Flux:"
            Text: 0.35, "centre", 0.1, "half", fixed$(spectralFlux[1], 1) + " Hz/f"
            Text: 0.65, "centre", 0.1, "half", fixed$(spectralFlux[2], 1) + " Hz/f"
        endif
        
        Font size: 10
        Colour: "Black"
    
    # === SINGLE FILE / BATCH MODE ===
    else
        for viz_index from 1 to number_of_selected_sounds
            Erase all
            
            select sound'viz_index'
            thisDuration = Get total duration
            thisSampleRate = Get sampling frequency
            thisNyquist = thisSampleRate / 2
            
          # === TITLE ===
Select outer viewport: 0, 8, 0, 1.0
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.8, "half", "##Brightness Analysis## | " + sound_names$[viz_index]

@getCategoryColor: categories$[viz_index]
Font size: 10
Colour: categoryColor$
Text special: 0.5, "centre", 0.05, "half", "Times", 12, "0", categories$[viz_index]
            
            # === SPECTROGRAM ===
            Select outer viewport: 0, 8, 0.8, 2.6
            Select inner viewport: 0.6, 7.6, 0.9, 2.5
            
            select sound'viz_index'
            To Spectrogram: 0.03, 8000, 0.002, 20, "Gaussian"
            specViz = selected("Spectrogram")
            Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
            
            # Mark centroid line
            Colour: "{1.0, 0.3, 0.3}"
            Line width: 2
            Axes: 0, thisDuration, 0, 8000
            Draw line: 0, centroids[viz_index], thisDuration, centroids[viz_index]
            
            Colour: "Black"
            Line width: 1
            Draw inner box
            Font size: 7
            Marks left every: 1, 2000, "yes", "yes", "no"
            Text left: "yes", "Freq (Hz)"
            
            removeObject: specViz
            
            # === BRIGHTNESS METER ===
            Select outer viewport: 0, 8, 2.7, 3.5
            Select inner viewport: 0.6, 7.6, 2.8, 3.4
            
            Axes: 0, 1, 0, 1
            
            # Gradient background
            meterLeft = 0.02
            meterRight = 0.98
            meterWidth = meterRight - meterLeft
            
            numGradientSteps = 60
            for g from 1 to numGradientSteps
                gPos = (g - 1) / numGradientSteps
                gX1 = meterLeft + gPos * meterWidth
                gX2 = meterLeft + (g / numGradientSteps) * meterWidth
                
                gR = 0.15 + gPos * 0.75
                gG = 0.15 + gPos * 0.45
                gB = 0.5 - gPos * 0.35
                
                Paint rectangle: "{" + fixed$(gR, 2) + "," + fixed$(gG, 2) + "," + fixed$(gB, 2) + "}", gX1, gX2, 0.3, 0.7
            endfor
            
            # Threshold markers and labels
            maxCentroidDisplay = threshold_bright * 1.5
            
            Colour: "White"
            Line width: 1
            Font size: 5
            
            t1Pos = meterLeft + (threshold_very_dark / maxCentroidDisplay) * meterWidth
            t2Pos = meterLeft + (threshold_dark / maxCentroidDisplay) * meterWidth
            t3Pos = meterLeft + (threshold_medium / maxCentroidDisplay) * meterWidth
            t4Pos = meterLeft + (threshold_bright / maxCentroidDisplay) * meterWidth
            
            Draw line: t1Pos, 0.3, t1Pos, 0.7
            Draw line: t2Pos, 0.3, t2Pos, 0.7
            Draw line: t3Pos, 0.3, t3Pos, 0.7
            Draw line: t4Pos, 0.3, t4Pos, 0.7
            
            Text: t1Pos, "centre", 0.15, "half", string$(threshold_very_dark)
            Text: t2Pos, "centre", 0.15, "half", string$(threshold_dark)
            Text: t3Pos, "centre", 0.15, "half", string$(threshold_medium)
            Text: t4Pos, "centre", 0.15, "half", string$(threshold_bright)
            
            # Current value marker
            cPos = meterLeft + min(1, centroids[viz_index] / maxCentroidDisplay) * meterWidth
            Colour: "Black"
            Line width: 3
            Draw line: cPos, 0.25, cPos, 0.75
            
            Font size: 8
            Text: cPos, "centre", 0.88, "half", fixed$(centroids[viz_index], 0) + " Hz"
            
            Line width: 1
            
            # === TIME-VARYING BRIGHTNESS ===
            if show_time_analysis
                Select outer viewport: 0, 8, 3.6, 5.0
                Select inner viewport: 0.6, 7.6, 3.7, 4.9
                
                # Find range
                minTC = centroids[viz_index]
                maxTC = centroids[viz_index]
                for f from 1 to numTimeFrames[viz_index]
                    if timeCentroids[viz_index, f] > 0
                        if timeCentroids[viz_index, f] < minTC
                            minTC = timeCentroids[viz_index, f]
                        endif
                        if timeCentroids[viz_index, f] > maxTC
                            maxTC = timeCentroids[viz_index, f]
                        endif
                    endif
                endfor
                
                minTC = max(0, minTC - 150)
                maxTC = maxTC + 150
                
                Axes: 0, thisDuration, minTC, maxTC
                Paint rectangle: "{0.97, 0.98, 1.0}", 0, thisDuration, minTC, maxTC
                
                # Threshold regions (color-coded background)
                if threshold_very_dark > minTC
                    Paint rectangle: "{0.9, 0.9, 0.95}", 0, thisDuration, minTC, min(threshold_very_dark, maxTC)
                endif
                if threshold_dark > minTC and threshold_dark < maxTC
                    Paint rectangle: "{0.92, 0.94, 0.96}", 0, thisDuration, max(threshold_very_dark, minTC), min(threshold_dark, maxTC)
                endif
                if threshold_medium > minTC and threshold_medium < maxTC
                    Paint rectangle: "{0.94, 0.96, 0.94}", 0, thisDuration, max(threshold_dark, minTC), min(threshold_medium, maxTC)
                endif
                if threshold_bright > minTC and threshold_bright < maxTC
                    Paint rectangle: "{0.96, 0.95, 0.92}", 0, thisDuration, max(threshold_medium, minTC), min(threshold_bright, maxTC)
                endif
                if maxTC > threshold_bright
                    Paint rectangle: "{0.96, 0.92, 0.9}", 0, thisDuration, max(threshold_bright, minTC), maxTC
                endif
                
                # Draw trajectory
                Colour: "{0.3, 0.5, 0.8}"
                Line width: 2
                for f from 2 to numTimeFrames[viz_index]
                    if timeCentroids[viz_index, f-1] > 0 and timeCentroids[viz_index, f] > 0
                        Draw line: timePoints[viz_index, f-1], timeCentroids[viz_index, f-1], timePoints[viz_index, f], timeCentroids[viz_index, f]
                    endif
                endfor
                
                # Mean line
                Colour: "{0.8, 0.3, 0.3}"
                Line width: 1
                Dotted line
                Draw line: 0, centroids[viz_index], thisDuration, centroids[viz_index]
                Solid line
                
                Line width: 1
                Colour: "Black"
                Draw inner box
                Font size: 7
                Text left: "yes", "Centroid (Hz)"
                Text bottom: "yes", "Time (s)"
                Marks left: 4, "yes", "yes", "no"
                
                # Legend
                Font size: 6
                Colour: "{0.3, 0.5, 0.8}"
                Text: thisDuration * 0.02, "left", maxTC - 30, "half", "Trajectory"
                Colour: "{0.8, 0.3, 0.3}"
                Text: thisDuration * 0.15, "left", maxTC - 30, "half", "Mean"
            endif
            
            # === ENERGY DISTRIBUTION ===
            if show_time_analysis
                Select outer viewport: 0, 4, 5.1, 6.5
            else
                Select outer viewport: 0, 4, 3.6, 5.5
            endif
            Select inner viewport: 0.6, 3.8, 5.2, 6.4
            
            # Normalize
            maxE = max(bass_energy[viz_index], low_mid_energy[viz_index], high_mid_energy[viz_index], high_energy[viz_index])
            if maxE > 0
                bassN = (bass_energy[viz_index] / maxE) * 100
                lowMidN = (low_mid_energy[viz_index] / maxE) * 100
                highMidN = (high_mid_energy[viz_index] / maxE) * 100
                highN = (high_energy[viz_index] / maxE) * 100
            else
                bassN = 0
                lowMidN = 0
                highMidN = 0
                highN = 0
            endif
            
            Axes: 0, 5, 0, 110
            
            # Bars
            Colour: "{0.3, 0.4, 0.7}"
            Paint rectangle: "{0.3, 0.4, 0.7}", 0.5, 1.5, 0, bassN
            Colour: "{0.3, 0.6, 0.5}"
            Paint rectangle: "{0.3, 0.6, 0.5}", 1.5, 2.5, 0, lowMidN
            Colour: "{0.7, 0.6, 0.3}"
            Paint rectangle: "{0.7, 0.6, 0.3}", 2.5, 3.5, 0, highMidN
            Colour: "{0.8, 0.3, 0.3}"
            Paint rectangle: "{0.8, 0.3, 0.3}", 3.5, 4.5, 0, highN
            
            # Labels
            Font size: 6
            Colour: "Black"
            Text special: 1, "centre", -8, "half", "Helvetica", 6, "0", "Bass"
            Text special: 2, "centre", -8, "half", "Helvetica", 6, "0", "Low-Mid"
            Text special: 3, "centre", -8, "half", "Helvetica", 6, "0", "High-Mid"
            Text special: 4, "centre", -8, "half", "Helvetica", 6, "0", "High"
            
            Draw inner box
            Font size: 7
            Text left: "yes", "Energy (%)"
            
            # === METRICS PANEL ===
            if show_time_analysis
                Select outer viewport: 4, 8, 5.1, 6.5
            else
                Select outer viewport: 4, 8, 3.6, 5.5
            endif
            Axes: 0, 1, 0, 1
            
            Font size: 8
            Colour: "Black"
            Text: 0.5, "centre", 0.9, "half", "##Spectral Metrics##"
            
            Font size: 7
            Colour: "{0.3, 0.3, 0.4}"
            
            Text: 0.1, "left", 0.72, "half", "Centroid:"
            Text: 0.7, "right", 0.72, "half", fixed$(centroids[viz_index], 0) + " Hz"
            
            Text: 0.1, "left", 0.56, "half", "Spread:"
            Text: 0.7, "right", 0.56, "half", fixed$(spreads[viz_index], 0) + " Hz"
            
            Text: 0.1, "left", 0.40, "half", "Rolloff (" + string$(rolloff_percent) + "%):"
            Text: 0.7, "right", 0.40, "half", fixed$(rolloffs[viz_index], 0) + " Hz"
            
            Text: 0.1, "left", 0.24, "half", "Crest Factor:"
            Text: 0.7, "right", 0.24, "half", fixed$(crests[viz_index], 2)
            
            if show_time_analysis
                Text: 0.1, "left", 0.08, "half", "Spectral Flux:"
                Text: 0.7, "right", 0.08, "half", fixed$(spectralFlux[viz_index], 1) + " Hz/frame"
            endif
            
            Font size: 10
            Colour: "Black"
            
            # Play if requested
            if play_result
                select sound'viz_index'
                Play
            endif
            
            # Pause for batch if more than one
            if number_of_selected_sounds > 1 and viz_index < number_of_selected_sounds
                pauseScript: "File " + string$(viz_index) + "/" + string$(number_of_selected_sounds) + ": " + sound_names$[viz_index] + newline$ + "Press Continue for next file..."
            endif
        endfor
        
        # === BATCH SUMMARY ===
        if number_of_selected_sounds > 1
            Erase all
            
            # Title
            Select outer viewport: 0, 8, 0, 0.6
            Axes: 0, 1, 0, 1
            Font size: 12
            Colour: "Black"
            Text: 0.5, "centre", 0.6, "half", "##Brightness Classification Summary##"
            Font size: 9
            Colour: "{0.4, 0.4, 0.5}"
            Text: 0.5, "centre", 0.2, "half", string$(number_of_selected_sounds) + " files | Preset: " + presetName$
            
            # Find range
            minCent = centroids[1]
            maxCent = centroids[1]
            for i from 2 to number_of_selected_sounds
                if centroids[i] < minCent
                    minCent = centroids[i]
                endif
                if centroids[i] > maxCent
                    maxCent = centroids[i]
                endif
            endfor
            
            yMin = max(0, minCent - 300)
            yMax = maxCent + 300
            
            # Centroid plot
            Select outer viewport: 0, 8, 0.7, 3.3
            Select inner viewport: 0.8, 7.6, 0.8, 3.2
            
            Axes: 0, number_of_selected_sounds + 1, yMin, yMax
            
            # Threshold regions
            if threshold_very_dark > yMin
                Paint rectangle: "{0.9, 0.9, 0.95}", 0, number_of_selected_sounds + 1, yMin, min(threshold_very_dark, yMax)
            endif
            if threshold_dark < yMax and threshold_dark > yMin
                Paint rectangle: "{0.92, 0.94, 0.96}", 0, number_of_selected_sounds + 1, max(threshold_very_dark, yMin), min(threshold_dark, yMax)
            endif
            if threshold_medium < yMax and threshold_medium > yMin
                Paint rectangle: "{0.94, 0.96, 0.94}", 0, number_of_selected_sounds + 1, max(threshold_dark, yMin), min(threshold_medium, yMax)
            endif
            if threshold_bright < yMax and threshold_bright > yMin
                Paint rectangle: "{0.96, 0.95, 0.92}", 0, number_of_selected_sounds + 1, max(threshold_medium, yMin), min(threshold_bright, yMax)
            endif
            if yMax > threshold_bright
                Paint rectangle: "{0.96, 0.92, 0.9}", 0, number_of_selected_sounds + 1, max(threshold_bright, yMin), yMax
            endif
            
            # Threshold lines
            Colour: "{0.7, 0.7, 0.75}"
            Line width: 1
            if threshold_very_dark > yMin and threshold_very_dark < yMax
                Draw line: 0, threshold_very_dark, number_of_selected_sounds + 1, threshold_very_dark
            endif
            if threshold_dark > yMin and threshold_dark < yMax
                Draw line: 0, threshold_dark, number_of_selected_sounds + 1, threshold_dark
            endif
            if threshold_medium > yMin and threshold_medium < yMax
                Draw line: 0, threshold_medium, number_of_selected_sounds + 1, threshold_medium
            endif
            if threshold_bright > yMin and threshold_bright < yMax
                Draw line: 0, threshold_bright, number_of_selected_sounds + 1, threshold_bright
            endif
            
            # Plot points with category colors
            Line width: 2
            for i from 1 to number_of_selected_sounds
                @getCategoryColor: categories$[i]
                Colour: categoryColor$
                Paint circle: categoryColor$, i, centroids[i], 0.15
                
                if i < number_of_selected_sounds
                    Draw line: i, centroids[i], i+1, centroids[i+1]
                endif
            endfor
            Line width: 1
            
            # Labels
            Font size: 6
            Colour: "Black"
            for i to number_of_selected_sounds
                label$ = sound_names$[i]
                if length(label$) > 12
                    label$ = left$(label$, 9) + "..."
                endif
                Text special: i, "centre", yMin + 80, "half", "Helvetica", 6, "90", label$
                Text special: i, "centre", centroids[i] + 60, "half", "Helvetica", 6, "0", fixed$(centroids[i], 0)
            endfor
            
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Centroid (Hz)"
            Marks left every: 1, 500, "yes", "yes", "no"
            
            # Stacked energy bars
            Select outer viewport: 0, 8, 3.4, 5.4
            Select inner viewport: 0.8, 7.6, 3.5, 5.3
            
            # Find global max
            globalMax = 0
            for i to number_of_selected_sounds
                fileMax = bass_energy[i] + low_mid_energy[i] + high_mid_energy[i] + high_energy[i]
                if fileMax > globalMax
                    globalMax = fileMax
                endif
            endfor
            
            Axes: 0, number_of_selected_sounds + 1, 0, 110
            
            barW = 0.5
            for i to number_of_selected_sounds
                if globalMax > 0
                    bN = (bass_energy[i] / globalMax) * 100
                    lmN = (low_mid_energy[i] / globalMax) * 100
                    hmN = (high_mid_energy[i] / globalMax) * 100
                    hN = (high_energy[i] / globalMax) * 100
                else
                    bN = 0
                    lmN = 0
                    hmN = 0
                    hN = 0
                endif
                
                Colour: "{0.3, 0.4, 0.7}"
                Paint rectangle: "{0.3, 0.4, 0.7}", i - barW/2, i + barW/2, 0, bN
                Colour: "{0.3, 0.6, 0.5}"
                Paint rectangle: "{0.3, 0.6, 0.5}", i - barW/2, i + barW/2, bN, bN + lmN
                Colour: "{0.7, 0.6, 0.3}"
                Paint rectangle: "{0.7, 0.6, 0.3}", i - barW/2, i + barW/2, bN + lmN, bN + lmN + hmN
                Colour: "{0.8, 0.3, 0.3}"
                Paint rectangle: "{0.8, 0.3, 0.3}", i - barW/2, i + barW/2, bN + lmN + hmN, bN + lmN + hmN + hN
            endfor
            
            Colour: "Black"
            Draw inner box
            Font size: 7
            Text left: "yes", "Energy (%)"
            Marks left every: 1, 25, "yes", "yes", "no"
            
            # Legend
            Select outer viewport: 0, 8, 5.5, 6.0
            Axes: 0, 1, 0, 1
            Font size: 7
            
            xS = 0.08
            boxS = 0.03
            sp = 0.22
            
            Colour: "{0.3, 0.4, 0.7}"
            Paint rectangle: "{0.3, 0.4, 0.7}", xS, xS + boxS, 0.4, 0.6
            Colour: "Black"
            Text: xS + boxS + 0.02, "left", 0.5, "half", "Bass"
            
            Colour: "{0.3, 0.6, 0.5}"
            Paint rectangle: "{0.3, 0.6, 0.5}", xS + sp, xS + sp + boxS, 0.4, 0.6
            Colour: "Black"
            Text: xS + sp + boxS + 0.02, "left", 0.5, "half", "Low-Mid"
            
            Colour: "{0.7, 0.6, 0.3}"
            Paint rectangle: "{0.7, 0.6, 0.3}", xS + sp*2, xS + sp*2 + boxS, 0.4, 0.6
            Colour: "Black"
            Text: xS + sp*2 + boxS + 0.02, "left", 0.5, "half", "High-Mid"
            
            Colour: "{0.8, 0.3, 0.3}"
            Paint rectangle: "{0.8, 0.3, 0.3}", xS + sp*3, xS + sp*3 + boxS, 0.4, 0.6
            Colour: "Black"
            Text: xS + sp*3 + boxS + 0.02, "left", 0.5, "half", "High"
            
            Font size: 10
            Colour: "Black"
        endif
    endif
endif

# ============================================================
# SUMMARY STATISTICS
# ============================================================

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  SUMMARY STATISTICS"
appendInfoLine: "=============================================="
appendInfoLine: ""

# Count categories
very_dark_count = 0
dark_count = 0
medium_count = 0
bright_count = 0
very_bright_count = 0

for i to number_of_selected_sounds
    if categories$[i] = "very_dark"
        very_dark_count = very_dark_count + 1
    elsif categories$[i] = "dark"
        dark_count = dark_count + 1
    elsif categories$[i] = "medium"
        medium_count = medium_count + 1
    elsif categories$[i] = "bright"
        bright_count = bright_count + 1
    else
        very_bright_count = very_bright_count + 1
    endif
endfor

appendInfoLine: "Category Distribution:"
appendInfoLine: "  Very Dark: ", very_dark_count
appendInfoLine: "  Dark: ", dark_count
appendInfoLine: "  Medium: ", medium_count
appendInfoLine: "  Bright: ", bright_count
appendInfoLine: "  Very Bright: ", very_bright_count
appendInfoLine: ""

# Calculate averages
sum_centroid = 0
sum_spread = 0
sum_rolloff = 0
sum_crest = 0

for i to number_of_selected_sounds
    sum_centroid = sum_centroid + centroids[i]
    sum_spread = sum_spread + spreads[i]
    sum_rolloff = sum_rolloff + rolloffs[i]
    sum_crest = sum_crest + crests[i]
endfor

avg_centroid = sum_centroid / number_of_selected_sounds
avg_spread = sum_spread / number_of_selected_sounds
avg_rolloff = sum_rolloff / number_of_selected_sounds
avg_crest = sum_crest / number_of_selected_sounds

appendInfoLine: "Average Metrics:"
appendInfoLine: "  Centroid: ", fixed$(avg_centroid, 0), " Hz"
appendInfoLine: "  Spread: ", fixed$(avg_spread, 0), " Hz"
appendInfoLine: "  Rolloff: ", fixed$(avg_rolloff, 0), " Hz"
appendInfoLine: "  Crest Factor: ", fixed$(avg_crest, 2)

if show_time_analysis
    sum_flux = 0
    for i to number_of_selected_sounds
        sum_flux = sum_flux + spectralFlux[i]
    endfor
    avg_flux = sum_flux / number_of_selected_sounds
    appendInfoLine: "  Spectral Flux: ", fixed$(avg_flux, 1), " Hz/frame"
endif

# Reselect all original sounds
select sound1
for current_sound_index from 2 to number_of_selected_sounds
    plus sound'current_sound_index'
endfor

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  Done!"
appendInfoLine: "=============================================="