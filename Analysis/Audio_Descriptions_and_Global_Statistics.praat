# ============================================================
# Praat AudioTools - descriptions.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

clearinfo

# Automatically select all Sound objects
select all
number_of_selected_sounds = numberOfSelected("Sound")

if number_of_selected_sounds = 0
    appendInfoLine: "No Sound objects found in the Objects window."
    appendInfoLine: "Please load some audio files first."
    exit
endif

appendInfoLine: "Analyzing ", number_of_selected_sounds, " Sound file(s)..."

for index to number_of_selected_sounds
    sound'index' = selected("Sound", index)
endfor

# Create results table
Create Table with column names: "Results", number_of_selected_sounds, "SoundName Duration_s Pitch_mean_Hz Pitch_min_Hz Pitch_max_Hz Pitch_median_Hz Pitch_stdev_Hz Intensity_max_dB Intensity_min_dB Intensity_median_dB Intensity_variance_dB Jitter_local Shimmer_local Harmonicity_dB SPR_dB Spectral_centroid_Hz Spectral_spread_Hz Spectral_rolloff_Hz Spectral_flatness Spectral_roughness"

for current_sound_index from 1 to number_of_selected_sounds
    select sound'current_sound_index'
    soundName$ = selected$("Sound")
    appendInfoLine: "Processing: ", soundName$
    
    # 1. Duration
    duration = Get total duration
    
    # 2. Pitch analysis
    To Pitch (raw cc): 0, 75, 600, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
    pitch = selected("Pitch")
    voiced_frames = Count voiced frames
    
    if voiced_frames > 1
        meanPitch = Get mean: 0, 0, "Hertz"
        minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
        maxPitch = Get maximum: 0, 0, "Hertz", "Parabolic"
        medianPitch = Get quantile: 0, 0, 0.50, "Hertz"
        stdevPitch = Get standard deviation: 0, 0, "Hertz"
    else
        meanPitch = 0
        minPitch = 0
        maxPitch = 0
        medianPitch = 0
        stdevPitch = 0
    endif
    removeObject: pitch
    
    # 3. Intensity
    select sound'current_sound_index'
    intensity = To Intensity: 100, 0, "yes"
    intensityMax = Get maximum: 0, 0, "Parabolic"
    intensityMin = Get minimum: 0, 0, "Parabolic"
    intensityMedian = Get quantile: 0, 0, 0.50
    intensityStdev = Get standard deviation: 0, 0
    intensityVariance = intensityStdev * intensityStdev
    removeObject: intensity
    
    # 4. Jitter/Shimmer
    select sound'current_sound_index'
    pointProcess = To PointProcess (periodic, cc): 75, 600
    number_of_periods = Get number of periods: 0, 0, 0.0001, 0.02, 1.3
    if number_of_periods > 1
        jitter = Get jitter (local): 0, 0, 0.0001, 0.02, 1.3
        plus sound'current_sound_index'
        shimmer = Get shimmer (local): 0, 0, 0.0001, 0.02, 1.3, 1.6
    else
        jitter = 0
        shimmer = 0
    endif
    removeObject: pointProcess
    
    # 5. Harmonicity
    select sound'current_sound_index'
    harmonicity = To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    hnr = Get mean: 0, 0
    removeObject: harmonicity
    
    # 6. Spectral Analysis
    select sound'current_sound_index'
    spectrum = To Spectrum: "yes"
    spectralCentroid = Get centre of gravity: 2
    spectralSpread = Get standard deviation: 2
    
    # SPR Calculation
    Tabulate: "no", "yes", "no", "no", "no", "yes"
    spectrumTable = selected("Table")
    Extract rows where column (number): "freq(Hz)", "greater than or equal to", 50
    low1 = selected()
    Extract rows where column (number): "freq(Hz)", "less than or equal to", 2000
    low2 = selected()
    lowBandMax = Get maximum: "pow(dB/Hz)"
    
    select spectrumTable
    Extract rows where column (number): "freq(Hz)", "greater than or equal to", 2000
    high1 = selected()
    Extract rows where column (number): "freq(Hz)", "less than or equal to", 4000
    high2 = selected()
    highBandMax = Get maximum: "pow(dB/Hz)"
    spr = lowBandMax - highBandMax
    removeObject: spectrumTable
    removeObject: low1
    removeObject: low2
    removeObject: high1
    removeObject: high2
    
    # Rolloff Calculation
    select spectrum
    numberOfBins = Get number of bins
    binWidth = Get bin width
    totalEnergy = 0
    for i from 1 to numberOfBins
        amp = Get real value in bin: i
        totalEnergy += amp ^ 2
    endfor
    
    spectralRolloff = 0
    if totalEnergy > 1e-12
        target = totalEnergy * 0.85
        cum = 0
        found = 0
        for i from 1 to numberOfBins
            if found = 0
                amp = Get real value in bin: i
                cum += amp^2
                if cum >= target
                    spectralRolloff = Get frequency from bin number: i
                    found = 1
                endif
            endif
        endfor
    endif
    
    # Flatness & Roughness
    lnSum = 0
    linearSum = 0
    validBins = 0
    roughnessSum = 0
    roughnessBins = 0
    
    for bin from 1 to numberOfBins
        freq = (bin - 1) * binWidth
        if freq >= 80 and freq <= 5000
            amp = Get real value in bin: bin
            power = max(amp * amp, 1e-12)
            lnSum += ln(power)
            linearSum += power
            if bin > 1 and bin < numberOfBins
                ampPrev = Get real value in bin: bin-1
                ampNext = Get real value in bin: bin+1
                roughnessSum += abs(amp - (ampPrev + ampNext)/2)
                roughnessBins += 1
            endif
            validBins += 1
        endif
    endfor
    
    if validBins > 0
        spectralFlatness = exp(lnSum / validBins) / (linearSum / validBins)
    else
        spectralFlatness = 0
    endif
    
    if roughnessBins > 0
        spectralRoughness = roughnessSum / roughnessBins
    else
        spectralRoughness = 0
    endif
    
    removeObject: spectrum

    # Fill Table
    selectObject: "Table Results"
    Set string value: current_sound_index, "SoundName", soundName$
    Set numeric value: current_sound_index, "Duration_s", duration
    Set numeric value: current_sound_index, "Pitch_mean_Hz", if meanPitch = undefined then 0 else meanPitch endif
    Set numeric value: current_sound_index, "Pitch_min_Hz", if minPitch = undefined then 0 else minPitch endif
    Set numeric value: current_sound_index, "Pitch_max_Hz", if maxPitch = undefined then 0 else maxPitch endif
    Set numeric value: current_sound_index, "Pitch_median_Hz", if medianPitch = undefined then 0 else medianPitch endif
    Set numeric value: current_sound_index, "Pitch_stdev_Hz", if stdevPitch = undefined then 0 else stdevPitch endif
    Set numeric value: current_sound_index, "Intensity_max_dB", if intensityMax = undefined then 0 else intensityMax endif
    Set numeric value: current_sound_index, "Intensity_min_dB", if intensityMin = undefined then 0 else intensityMin endif
    Set numeric value: current_sound_index, "Intensity_median_dB", if intensityMedian = undefined then 0 else intensityMedian endif
    Set numeric value: current_sound_index, "Intensity_variance_dB", if intensityVariance = undefined then 0 else intensityVariance endif
    Set numeric value: current_sound_index, "Jitter_local", if jitter = undefined then 0 else jitter endif
    Set numeric value: current_sound_index, "Shimmer_local", if shimmer = undefined then 0 else shimmer endif
    Set numeric value: current_sound_index, "Harmonicity_dB", if hnr = undefined then 0 else hnr endif
    Set numeric value: current_sound_index, "SPR_dB", if spr = undefined then 0 else spr endif
    Set numeric value: current_sound_index, "Spectral_centroid_Hz", if spectralCentroid = undefined then 0 else spectralCentroid endif
    Set numeric value: current_sound_index, "Spectral_spread_Hz", if spectralSpread = undefined then 0 else spectralSpread endif
    Set numeric value: current_sound_index, "Spectral_rolloff_Hz", if spectralRolloff = undefined then 0 else spectralRolloff endif
    Set numeric value: current_sound_index, "Spectral_flatness", if spectralFlatness = undefined then 0 else spectralFlatness endif
    Set numeric value: current_sound_index, "Spectral_roughness", if spectralRoughness = undefined then 0 else spectralRoughness endif
endfor

# ============================================================
# VISUALIZATION SECTION
# ============================================================

Erase all
selectObject: "Table Results"
nRows = Get number of rows

# Global Font Size
Font size: 9

# -------------------------------------------------------------------------
# TABLE 1: DURATION, PITCH (5), INTENSITY (4)
# -------------------------------------------------------------------------
Select inner viewport: 0.5, 9.5, 0.5, 4.5
Axes: 0, 14, 0, nRows + 1
Text top: "yes", "Table 1: Time, Pitch & Intensity Features"

# Background
Colour: "{0.8, 0.8, 0.8}"
Paint rectangle: "{0.8, 0.8, 0.8}", 0, 14, nRows + 0.5, nRows + 1
Colour: "Black"

# Headers
Text: 0.8, "centre", nRows + 0.75, "half", "Name"
Text: 2.1, "centre", nRows + 0.75, "half", "Dur"
Text: 3.3, "centre", nRows + 0.75, "half", "P_Mean"
Text: 4.5, "centre", nRows + 0.75, "half", "P_Min"
Text: 5.7, "centre", nRows + 0.75, "half", "P_Max"
Text: 6.9, "centre", nRows + 0.75, "half", "P_Med"
Text: 8.1, "centre", nRows + 0.75, "half", "P_Std"
Text: 9.3, "centre", nRows + 0.75, "half", "I_Max"
Text: 10.5, "centre", nRows + 0.75, "half", "I_Min"
Text: 11.7, "centre", nRows + 0.75, "half", "I_Med"
Text: 12.9, "centre", nRows + 0.75, "half", "I_Var"

for row from 1 to nRows
    yPos = nRows - row + 0.75
    selectObject: "Table Results"
    name$ = Get value: row, "SoundName"
    dur = Get value: row, "Duration_s"
    p_mean = Get value: row, "Pitch_mean_Hz"
    p_min = Get value: row, "Pitch_min_Hz"
    p_max = Get value: row, "Pitch_max_Hz"
    p_med = Get value: row, "Pitch_median_Hz"
    p_std = Get value: row, "Pitch_stdev_Hz"
    i_max = Get value: row, "Intensity_max_dB"
    i_min = Get value: row, "Intensity_min_dB"
    i_med = Get value: row, "Intensity_median_dB"
    i_var = Get value: row, "Intensity_variance_dB"
    
    if row mod 2 = 0
        Colour: "{0.95, 0.95, 0.95}"
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 14, yPos - 0.45, yPos + 0.45
    endif
    Colour: "Black"
    
    Text: 0.8, "centre", yPos, "half", name$
    Text: 2.1, "centre", yPos, "half", fixed$(dur, 2)
    Text: 3.3, "centre", yPos, "half", fixed$(p_mean, 0)
    Text: 4.5, "centre", yPos, "half", fixed$(p_min, 0)
    Text: 5.7, "centre", yPos, "half", fixed$(p_max, 0)
    Text: 6.9, "centre", yPos, "half", fixed$(p_med, 0)
    Text: 8.1, "centre", yPos, "half", fixed$(p_std, 1)
    Text: 9.3, "centre", yPos, "half", fixed$(i_max, 1)
    Text: 10.5, "centre", yPos, "half", fixed$(i_min, 1)
    Text: 11.7, "centre", yPos, "half", fixed$(i_med, 1)
    Text: 12.9, "centre", yPos, "half", fixed$(i_var, 1)
endfor
Draw rectangle: 0, 14, 0.5, nRows + 1


# -------------------------------------------------------------------------
# TABLE 2: SPECTRAL & VOICE QUALITY (9 features)
# -------------------------------------------------------------------------
Select inner viewport: 0.5, 9.5, 5.5, 9.5
Axes: 0, 14, 0, nRows + 1
Text top: "yes", "Table 2: Spectral & Quality Features"

# Background
Colour: "{0.8, 0.8, 0.8}"
Paint rectangle: "{0.8, 0.8, 0.8}", 0, 14, nRows + 0.5, nRows + 1
Colour: "Black"

# Headers
Text: 0.8, "centre", nRows + 0.75, "half", "Name"
Text: 2.2, "centre", nRows + 0.75, "half", "Jitter"
Text: 3.5, "centre", nRows + 0.75, "half", "Shimmer"
Text: 4.8, "centre", nRows + 0.75, "half", "HNR"
Text: 6.1, "centre", nRows + 0.75, "half", "SPR"
Text: 7.4, "centre", nRows + 0.75, "half", "Centrd"
Text: 8.7, "centre", nRows + 0.75, "half", "Spread"
Text: 10.0, "centre", nRows + 0.75, "half", "Rolloff"
Text: 11.3, "centre", nRows + 0.75, "half", "Flat"
Text: 12.6, "centre", nRows + 0.75, "half", "Rough"

for row from 1 to nRows
    yPos = nRows - row + 0.75
    selectObject: "Table Results"
    name$ = Get value: row, "SoundName"
    jit = Get value: row, "Jitter_local"
    shim = Get value: row, "Shimmer_local"
    hnr = Get value: row, "Harmonicity_dB"
    spr = Get value: row, "SPR_dB"
    cent = Get value: row, "Spectral_centroid_Hz"
    spread = Get value: row, "Spectral_spread_Hz"
    roll = Get value: row, "Spectral_rolloff_Hz"
    flat = Get value: row, "Spectral_flatness"
    rough = Get value: row, "Spectral_roughness"
    
    if row mod 2 = 0
        Colour: "{0.95, 0.95, 0.95}"
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 14, yPos - 0.45, yPos + 0.45
    endif
    Colour: "Black"
    
    Text: 0.8, "centre", yPos, "half", name$
    Text: 2.2, "centre", yPos, "half", fixed$(jit, 4)
    Text: 3.5, "centre", yPos, "half", fixed$(shim, 4)
    Text: 4.8, "centre", yPos, "half", fixed$(hnr, 1)
    Text: 6.1, "centre", yPos, "half", fixed$(spr, 1)
    Text: 7.4, "centre", yPos, "half", fixed$(cent, 0)
    Text: 8.7, "centre", yPos, "half", fixed$(spread, 0)
    Text: 10.0, "centre", yPos, "half", fixed$(roll, 0)
    Text: 11.3, "centre", yPos, "half", fixed$(flat, 4)
    Text: 12.6, "centre", yPos, "half", fixed$(rough, 4)
endfor
Draw rectangle: 0, 14, 0.5, nRows + 1

appendInfoLine: "Analysis Complete."
appendInfoLine: "Table 1 (Top): Duration, Pitch, Intensity"
appendInfoLine: "Table 2 (Bottom): Jitter/Shimmer, HNR, SPR, Spectral Features"