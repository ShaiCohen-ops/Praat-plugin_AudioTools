# ============================================================
# Praat AudioTools - Acoustic_Features_Batch_Extraction
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Acoustic_Features_Batch_Extraction
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

number_of_selected_sounds = numberOfSelected ("Sound")
if number_of_selected_sounds = 0
    writeInfoLine: "ERROR: Please select one or more Sound objects first."
    exit
endif

for i to number_of_selected_sounds
    sound'i' = selected ("Sound", i)
endfor

Create Table with column names: "AudioTools_Results", number_of_selected_sounds, "Filename IntensityMean_dB HarmonicityMean_dB JitterLocal RollOff85_Hz Flatness Roughness SPR_dB SPR_LowBandMax_dBHz SPR_HighBandMax_dBHz"

appendInfoLine: "AudioTools batch analysis"
appendInfoLine: "======================="
appendInfoLine: "Files: ", number_of_selected_sounds
appendInfoLine: ""
appendInfoLine: "Filename", tab$, "Intensity", tab$, "Harmonicity", tab$, "Jitter", tab$, "RollOff85", tab$, "Flatness", tab$, "Roughness", tab$, "SPR"
appendInfoLine: "--------------------------------------------------------------------------------"

for s from 1 to number_of_selected_sounds
    currentSoundID = sound's'
    selectObject: currentSoundID
    name$ = selected$("Sound")

    intensityMean = undefined
    harmonicityMean = undefined
    jitterLocal = undefined
    rolloff85 = undefined
    flatness = undefined
    roughness = undefined
    spr = undefined
    lowbandmax = undefined
    highbandmax = undefined

    # 1) INTENSITY
    selectObject: currentSoundID
    To Intensity: 100, 0, "yes"
    intensityID = selected()
    intensityMean = Get mean: 0, 0, "energy"
    selectObject: intensityID
    Remove
    selectObject: currentSoundID

    # 2) HARMONICITY (cc)
    selectObject: currentSoundID
    To Harmonicity (cc): 0.01, 75, 0.1, 1
    harmID = selected()
    harmonicityMean = Get mean: 0, 0
    selectObject: harmID
    Remove
    selectObject: currentSoundID

    # 3) JITTER (local)
    selectObject: currentSoundID
    To PointProcess (extrema): 1, "yes", "no", "sinc70"
    ppID = selected()
    jitterLocal = Get jitter (local): 0, 0, 0.0001, 0.02, 1.3
    selectObject: ppID
    Remove
    selectObject: currentSoundID

    # 4) SPECTRAL ROLL-OFF (85% energy) - NO break
    selectObject: currentSoundID
    To Spectrum... "yes"
    specID = selected()

    nBins = Get number of bins
    totalEnergy = 0
    for b from 1 to nBins
        amp = Get real value in bin: b
        totalEnergy += amp^2
    endfor

    if totalEnergy >= 1e-12
        targetEnergy = 0.85 * totalEnergy
        cumEnergy = 0
        found = 0
        for b from 1 to nBins
            if found = 0
                amp = Get real value in bin: b
                cumEnergy += amp^2
                if cumEnergy >= targetEnergy
                    rolloff85 = Get frequency from bin number: b
                    found = 1
                endif
            endif
        endfor
    endif

    selectObject: specID
    Remove
    selectObject: currentSoundID

    # 5) SPECTRAL FLATNESS + ROUGHNESS (80–5000 Hz)
    selectObject: currentSoundID
    To Spectrum... "yes"
    spec2ID = selected()

    minFreq = 80
    maxFreq = 5000

    nBins = Get number of bins
    binWidth = Get bin width

    lnSum = 0
    linearSum = 0
    validBins = 0

    roughnessSum = 0
    roughnessBins = 0

    for b from 1 to nBins
        freq = (b - 1) * binWidth
        if freq >= minFreq and freq <= maxFreq
            amp = Get real value in bin: b
            power = amp * amp
            if power < 1e-12
                power = 1e-12
            endif

            lnSum += ln(power)
            linearSum += power
            validBins += 1

            if b > 1 and b < nBins
                ampPrev = Get real value in bin: b - 1
                ampNext = Get real value in bin: b + 1
                roughnessSum += abs(amp - (ampPrev + ampNext) / 2)
                roughnessBins += 1
            endif
        endif
    endfor

    if validBins > 0
        flatness = exp(lnSum / validBins) / (linearSum / validBins)
    endif

    if roughnessBins > 0
        roughness = roughnessSum / roughnessBins
    endif

    selectObject: spec2ID
    Remove
    selectObject: currentSoundID

    # 6) SPR (Tabulate)
    selectObject: currentSoundID
    To Spectrum... "yes"
    spec3ID = selected()

    Tabulate: "no", "yes", "no", "no", "no", "yes"
    tabID = selected()

    selectObject: tabID
    Extract rows where column (number): "freq(Hz)", "greater than or equal to", 50
    low1ID = selected()
    Extract rows where column (number): "freq(Hz)", "less than or equal to", 2000
    low2ID = selected()
    lowbandmax = Get maximum: "pow(dB/Hz)"

    selectObject: tabID
    Extract rows where column (number): "freq(Hz)", "greater than or equal to", 2000
    high1ID = selected()
    Extract rows where column (number): "freq(Hz)", "less than or equal to", 4000
    high2ID = selected()
    highbandmax = Get maximum: "pow(dB/Hz)"

    spr = lowbandmax - highbandmax

    selectObject: spec3ID
    plusObject: tabID
    plusObject: low1ID
    plusObject: low2ID
    plusObject: high1ID
    plusObject: high2ID
    Remove

    selectObject: currentSoundID

    # WRITE TABLE
    selectObject: "Table AudioTools_Results"
    Set string value:  s, "Filename", name$

    Set numeric value: s, "IntensityMean_dB", intensityMean
    Set numeric value: s, "HarmonicityMean_dB", harmonicityMean
    Set numeric value: s, "JitterLocal", jitterLocal

    Set numeric value: s, "RollOff85_Hz", rolloff85
    Set numeric value: s, "Flatness", flatness
    Set numeric value: s, "Roughness", roughness

    Set numeric value: s, "SPR_dB", spr
    Set numeric value: s, "SPR_LowBandMax_dBHz", lowbandmax
    Set numeric value: s, "SPR_HighBandMax_dBHz", highbandmax

    appendInfoLine: name$, tab$, fixed$(intensityMean, 3), tab$, fixed$(harmonicityMean, 3), tab$, fixed$(jitterLocal, 6), tab$, fixed$(rolloff85, 2), tab$, fixed$(flatness, 6), tab$, fixed$(roughness, 6), tab$, fixed$(spr, 3)

endfor

selectObject: sound1
for i from 2 to number_of_selected_sounds
    plusObject: sound'i'
endfor

# ============================================================
# TABLE VISUALIZATION SECTION
# ============================================================

selectObject: "Table AudioTools_Results"
tableID = selected("Table")
nRows = Get number of rows

# Erase the Picture window
Erase all

# Set viewport - using proper Praat Picture window coordinates (wider for more columns)
Select inner viewport: 0.3, 7.7, 0.5, 4

# Set up axes for the table (wider X range for 10 columns)
Axes: 0, 14, 0, nRows + 1

# Title
Text top: "yes", "Acoustic Features Analysis - Complete Results Table"

# Draw table header with background
Colour: "{0.8, 0.8, 0.8}"
Paint rectangle: "{0.8, 0.8, 0.8}", 0, 14, nRows + 0.5, nRows + 1

# Header text
Colour: "Black"
Line width: 2
Draw line: 0, nRows + 0.5, 14, nRows + 0.5
Line width: 1

Text: 1.2, "centre", nRows + 0.75, "half", "File"
Text: 2.4, "centre", nRows + 0.75, "half", "Intensity"
Text: 3.6, "centre", nRows + 0.75, "half", "Harmonicity"
Text: 4.8, "centre", nRows + 0.75, "half", "Jitter"
Text: 6, "centre", nRows + 0.75, "half", "RollOff85"
Text: 7.2, "centre", nRows + 0.75, "half", "Flatness"
Text: 8.4, "centre", nRows + 0.75, "half", "Roughness"
Text: 9.6, "centre", nRows + 0.75, "half", "SPR"
Text: 10.8, "centre", nRows + 0.75, "half", "LowBand"
Text: 12, "centre", nRows + 0.75, "half", "HighBand"

# Draw data rows
for row from 1 to nRows
    yPos = nRows - row + 0.75
    
    selectObject: tableID
    filename$ = Get value: row, "Filename"
    intensity = Get value: row, "IntensityMean_dB"
    harmonicity = Get value: row, "HarmonicityMean_dB"
    jitter = Get value: row, "JitterLocal"
    rolloff = Get value: row, "RollOff85_Hz"
    flatness = Get value: row, "Flatness"
    roughness = Get value: row, "Roughness"
    spr = Get value: row, "SPR_dB"
    lowband = Get value: row, "SPR_LowBandMax_dBHz"
    highband = Get value: row, "SPR_HighBandMax_dBHz"
    
    # Alternate row shading
    if row mod 2 = 0
        Colour: "{0.95, 0.95, 0.95}"
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 14, yPos - 0.45, yPos + 0.45
    endif
    
    # Draw values
    Colour: "Black"
    Text: 1.2, "centre", yPos, "half", filename$
    Text: 2.4, "centre", yPos, "half", fixed$(intensity, 1)
    Text: 3.6, "centre", yPos, "half", fixed$(harmonicity, 1)
    Text: 4.8, "centre", yPos, "half", fixed$(jitter, 4)
    Text: 6, "centre", yPos, "half", fixed$(rolloff, 0)
    Text: 7.2, "centre", yPos, "half", fixed$(flatness, 4)
    Text: 8.4, "centre", yPos, "half", fixed$(roughness, 4)
    Text: 9.6, "centre", yPos, "half", fixed$(spr, 1)
    Text: 10.8, "centre", yPos, "half", fixed$(lowband, 1)
    Text: 12, "centre", yPos, "half", fixed$(highband, 1)
endfor

# Draw grid lines
Colour: "{0.7, 0.7, 0.7}"
for row from 0 to nRows
    Draw line: 0, row + 0.5, 14, row + 0.5
endfor

# Draw vertical column lines
Draw line: 0, 0.5, 0, nRows + 1
Draw line: 1.8, 0.5, 1.8, nRows + 1
Draw line: 3, 0.5, 3, nRows + 1
Draw line: 4.2, 0.5, 4.2, nRows + 1
Draw line: 5.4, 0.5, 5.4, nRows + 1
Draw line: 6.6, 0.5, 6.6, nRows + 1
Draw line: 7.8, 0.5, 7.8, nRows + 1
Draw line: 9, 0.5, 9, nRows + 1
Draw line: 10.2, 0.5, 10.2, nRows + 1
Draw line: 11.4, 0.5, 11.4, nRows + 1
Draw line: 14, 0.5, 14, nRows + 1

# Draw outer border
Colour: "Black"
Line width: 2
Draw rectangle: 0, 14, 0.5, nRows + 1
Line width: 1

appendInfoLine: ""
appendInfoLine: "✓ TABLE VISUALIZATION COMPLETE!"
appendInfoLine: "✓ Check the PICTURE WINDOW to see your table"
appendInfoLine: "  (Menu: Windows → Picture)"
