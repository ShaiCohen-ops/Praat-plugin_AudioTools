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

# Store all sound IDs using dynamic variables
for index to number_of_selected_sounds
    sound'index' = selected("Sound", index)
endfor

# Create results table with new spectral analysis columns
Create Table with column names: "Results", number_of_selected_sounds, "SoundName Duration_s Pitch_mean_Hz Pitch_min_Hz Pitch_max_Hz Pitch_median_Hz Pitch_stdev_Hz Intensity_max_dB Intensity_min_dB Intensity_median_dB Intensity_variance_dB Jitter_local Shimmer_local Harmonicity_dB SPR_dB Spectral_centroid_Hz Spectral_spread_Hz Spectral_rolloff_Hz Spectral_flatness Spectral_roughness"

# Analyze each sound
for current_sound_index from 1 to number_of_selected_sounds
    # Select the current sound
    select sound'current_sound_index'
    soundName$ = selected$("Sound")
    
    appendInfoLine: "Processing: ", soundName$
    
    # Initialize all variables to prevent undefined errors
    duration = 0
    meanPitch = 0
    minPitch = 0
    maxPitch = 0
    medianPitch = 0
    stdevPitch = 0
    intensityMax = 0
    intensityMin = 0
    intensityMedian = 0
    intensityVariance = 0
    jitter = 0
    shimmer = 0
    hnr = 0
    spr = 0
    spectralCentroid = 0
    spectralSpread = 0
    spectralRolloff = 0
    spectralFlatness = 0
    spectralRoughness = 0
    
    # Duration
    duration = Get total duration
    
    # Pitch analysis using raw cc method
    To Pitch (raw cc): 0, 75, 600, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
    pitch = selected("Pitch")
    
    # Count voiced frames first
    voiced_frames = Count voiced frames
    
    if voiced_frames > 0
        # Get pitch statistics only if we have voiced frames
        meanPitch = Get mean: 0, 0, "Hertz"
        minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
        maxPitch = Get maximum: 0, 0, "Hertz", "Parabolic"
        medianPitch = Get quantile: 0, 0, 0.50, "Hertz"
        
        # Standard deviation needs at least 2 voiced frames
        if voiced_frames > 1
            stdevPitch = Get standard deviation: 0, 0, "Hertz"
        else
            stdevPitch = 0
        endif
        
        # Final check - replace any remaining undefined values
        if meanPitch = undefined
            meanPitch = 0
        endif
        if minPitch = undefined
            minPitch = 0
        endif
        if maxPitch = undefined
            maxPitch = 0
        endif
        if medianPitch = undefined
            medianPitch = 0
        endif
        if stdevPitch = undefined
            stdevPitch = 0
        endif
    else
        # No voiced frames found - set all to 0
        meanPitch = 0
        minPitch = 0
        maxPitch = 0
        medianPitch = 0
        stdevPitch = 0
    endif
    removeObject: pitch
    
    # Intensity analysis
    select sound'current_sound_index'
    intensity = To Intensity: 100, 0, "yes"
    select intensity
    
    intensityMax = Get maximum: 0, 0, "Parabolic"
    intensityMin = Get minimum: 0, 0, "Parabolic"
    intensityMedian = Get quantile: 0, 0, 0.50
    intensityStdev = Get standard deviation: 0, 0
    intensityVariance = intensityStdev * intensityStdev
    
    # Handle undefined intensity values
    if intensityMax = undefined
        intensityMax = 0
    endif
    if intensityMin = undefined
        intensityMin = 0
    endif
    if intensityMedian = undefined
        intensityMedian = 0
    endif
    if intensityStdev = undefined
        intensityStdev = 0
        intensityVariance = 0
    endif
    if intensityVariance = undefined
        intensityVariance = 0
    endif
    
    removeObject: intensity
    
    # Select sound again for point process analysis
    select sound'current_sound_index'
    pointProcess = To PointProcess (periodic, cc): 75, 600
    
    # Check if we have any periods detected
    select pointProcess
    number_of_periods = Get number of periods: 0, 0, 0.0001, 0.02, 1.3
    
    if number_of_periods > 1
        # Jitter calculation (needs PointProcess with periods)
        jitter = Get jitter (local): 0, 0, 0.0001, 0.02, 1.3
        
        # Shimmer calculation (needs both Sound and PointProcess selected)
        plus sound'current_sound_index'
        shimmer = Get shimmer (local): 0, 0, 0.0001, 0.02, 1.3, 1.6
        
        # Handle undefined values
        if jitter = undefined
            jitter = 0
        endif
        if shimmer = undefined
            shimmer = 0
        endif
    else
        # No periods found - set to 0
        jitter = 0
        shimmer = 0
    endif
    
    # Clean up point process
    removeObject: pointProcess
    
    # Harmonicity calculation
    select sound'current_sound_index'
    harmonicity = To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    select harmonicity
    hnr = Get mean: 0, 0
    removeObject: harmonicity
    
    # Singing Power Ratio (SPR) analysis
    select sound'current_sound_index'
    spectrum = To Spectrum: "yes"
    select spectrum
    
    # Tabulate spectrum values
    Tabulate: "no", "yes", "no", "no", "no", "yes"
    spectrumTable = selected("Table")
    
    # Extract maximum from 50-2000 Hz band
    select spectrumTable
    lowTable1 = Extract rows where column (number): "freq(Hz)", "greater than or equal to", 50
    select lowTable1
    lowTable2 = Extract rows where column (number): "freq(Hz)", "less than or equal to", 2000
    select lowTable2
    lowBandMax = Get maximum: "pow(dB/Hz)"
    
    # Extract maximum from 2000-4000 Hz band  
    select spectrumTable
    highTable1 = Extract rows where column (number): "freq(Hz)", "greater than or equal to", 2000
    select highTable1
    highTable2 = Extract rows where column (number): "freq(Hz)", "less than or equal to", 4000
    select highTable2
    highBandMax = Get maximum: "pow(dB/Hz)"
    
    # Calculate SPR (difference between low and high band maxima)
    spr = lowBandMax - highBandMax
    
    # Clean up spectrum analysis objects
    removeObject: spectrum, spectrumTable, lowTable1, lowTable2, highTable1, highTable2
    
    # Spectral centroid and spread analysis (measure of spectral brightness and bandwidth)
    select sound'current_sound_index'
    spectrum2 = To Spectrum: "yes"
    selectObject: spectrum2
    spectralCentroid = Get centre of gravity: 2
    spectralSpread = Get standard deviation: 2
    
    # === NEW: Spectral Roll-off Frequency Analysis ===
    selectObject: spectrum2
    numberOfBins = Get number of bins
    
    # Calculate total energy
    totalEnergy = 0
    for i from 1 to numberOfBins
        amplitude = Get real value in bin: i
        totalEnergy += amplitude ^ 2
    endfor
    
    # Find roll-off frequency (85% of total energy)
    if totalEnergy > 1e-10
        cumulativeEnergy = 0
        targetEnergy = totalEnergy * 0.85
        spectralRolloff = 0
        
        for i from 1 to numberOfBins
            amplitude = Get real value in bin: i
            cumulativeEnergy += amplitude ^ 2
            if cumulativeEnergy >= targetEnergy
                spectralRolloff = Get frequency from bin number: i
                goto rolloff_found
            endif
        endfor
        label rolloff_found
    endif
    
    # === NEW: Spectral Flatness and Roughness Analysis ===
    # Parameters for flatness/roughness analysis
    minFreq = 80
    maxFreq = 5000
    lnSum = 0
    linearSum = 0
    validBins = 0
    roughnessSum = 0
    roughnessBins = 0
    binWidth = Get bin width
    
    # Main analysis loop for flatness and roughness
    for bin from 1 to numberOfBins
        freq = (bin - 1) * binWidth
        if freq >= minFreq and freq <= maxFreq
            # Flatness calculation
            amp = Get real value in bin: bin
            power = amp * amp
            power = max(power, 1e-12)
            lnSum = lnSum + ln(power)
            linearSum = linearSum + power
            
            # Roughness calculation (skip first and last bins)
            if bin > 1 and bin < numberOfBins
                ampPrev = Get real value in bin: bin-1
                ampNext = Get real value in bin: bin+1
                roughnessSum = roughnessSum + abs(amp - (ampPrev + ampNext)/2)
                roughnessBins = roughnessBins + 1
            endif
            
            validBins = validBins + 1
        endif
    endfor
    
    # Calculate spectral flatness and roughness
    if validBins > 0
        spectralFlatness = exp(lnSum / validBins) / (linearSum / validBins)
        if roughnessBins > 0
            spectralRoughness = roughnessSum / roughnessBins
        endif
    endif
    
    # Handle undefined spectral values
    if spectralCentroid = undefined
        spectralCentroid = 0
    endif
    if spectralSpread = undefined
        spectralSpread = 0
    endif
    if spectralRolloff = undefined
        spectralRolloff = 0
    endif
    if spectralFlatness = undefined
        spectralFlatness = 0
    endif
    if spectralRoughness = undefined
        spectralRoughness = 0
    endif
    
    removeObject: spectrum2
    
    # Ensure all variables are defined before table filling
    if spr = undefined
        spr = 0
    endif
    if hnr = undefined
        hnr = 0
    endif
    
    # Fill table
    selectObject: "Table Results"
    Set string value: current_sound_index, "SoundName", soundName$
    Set numeric value: current_sound_index, "Duration_s", duration
    Set numeric value: current_sound_index, "Pitch_mean_Hz", meanPitch
    Set numeric value: current_sound_index, "Pitch_min_Hz", minPitch
    Set numeric value: current_sound_index, "Pitch_max_Hz", maxPitch
    Set numeric value: current_sound_index, "Pitch_median_Hz", medianPitch
    Set numeric value: current_sound_index, "Pitch_stdev_Hz", stdevPitch
    Set numeric value: current_sound_index, "Intensity_max_dB", intensityMax
    Set numeric value: current_sound_index, "Intensity_min_dB", intensityMin
    Set numeric value: current_sound_index, "Intensity_median_dB", intensityMedian
    Set numeric value: current_sound_index, "Intensity_variance_dB", intensityVariance
    Set numeric value: current_sound_index, "Jitter_local", jitter
    Set numeric value: current_sound_index, "Shimmer_local", shimmer
    Set numeric value: current_sound_index, "Harmonicity_dB", hnr
    Set numeric value: current_sound_index, "SPR_dB", spr
    Set numeric value: current_sound_index, "Spectral_centroid_Hz", spectralCentroid
    Set numeric value: current_sound_index, "Spectral_spread_Hz", spectralSpread
    Set numeric value: current_sound_index, "Spectral_rolloff_Hz", spectralRolloff
    Set numeric value: current_sound_index, "Spectral_flatness", spectralFlatness
    Set numeric value: current_sound_index, "Spectral_roughness", spectralRoughness
endfor

# Reselect all original sounds at the end
select sound1
for current_sound_index from 2 to number_of_selected_sounds
    plus sound'current_sound_index'
endfor

selectObject: "Table Results"

appendInfoLine: ""
appendInfoLine: "=== ANALYSIS COMPLETE ==="
appendInfoLine: "Results saved in 'Table Results'"
appendInfoLine: "Analyzed ", number_of_selected_sounds, " sound file(s)"
appendInfoLine: ""
appendInfoLine: "New spectral features added:"
appendInfoLine: "- Spectral_rolloff_Hz: Frequency at 85% energy accumulation"
appendInfoLine: "- Spectral_flatness: 0=tonal, 1=noisy (80-5000 Hz range)"
appendInfoLine: "- Spectral_roughness: Higher values = more spectral irregularity"
appendInfoLine: ""
appendInfoLine: "To export results:"
appendInfoLine: "1. Select 'Table Results' in the Objects window"
appendInfoLine: "2. Choose 'Save as comma-separated file...'"
appendInfoLine: "3. Save as .csv file for Excel/analysis"