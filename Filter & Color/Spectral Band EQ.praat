# ============================================================
# Praat AudioTools - Spectral Band EQ
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Band EQ
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Spectral Band EQ
    optionmenu Preset: 1
        option Custom
        option Telephone (300-3400 Hz)
        option AM Radio (500-4500 Hz)
        option Sub Bass Boost (+6dB < 100 Hz)
        option Presence Boost (+4dB 2-5 kHz)
        option Mud Cut (-6dB 200-500 Hz)
        option Air Boost (+3dB > 10 kHz)
        option Mid Scoop (-8dB 1-3 kHz)
        option Low Pass (< 2 kHz)
        option High Pass (> 500 Hz)
    comment === Filter Parameters ===
    positive Center_frequency_(Hz) 1000
    positive Bandwidth_(Hz) 500
    real Gain_(dB) 6.0
    comment (positive=boost, negative=cut, -inf=remove)
    comment === Output ===
    boolean Draw_response 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Telephone bandpass
    center_frequency = 1850
    bandwidth = 3100
    gain = -100
    isPassFilter = 1
elsif preset = 3
    # AM Radio bandpass
    center_frequency = 2500
    bandwidth = 4000
    gain = -100
    isPassFilter = 1
elsif preset = 4
    # Sub Bass Boost
    center_frequency = 50
    bandwidth = 100
    gain = 6
    isPassFilter = 0
elsif preset = 5
    # Presence Boost
    center_frequency = 3500
    bandwidth = 3000
    gain = 4
    isPassFilter = 0
elsif preset = 6
    # Mud Cut
    center_frequency = 350
    bandwidth = 300
    gain = -6
    isPassFilter = 0
elsif preset = 7
    # Air Boost
    center_frequency = 14000
    bandwidth = 8000
    gain = 3
    isPassFilter = 0
elsif preset = 8
    # Mid Scoop
    center_frequency = 2000
    bandwidth = 2000
    gain = -8
    isPassFilter = 0
elsif preset = 9
    # Low Pass
    center_frequency = 1000
    bandwidth = 2000
    gain = -100
    isPassFilter = 2
elsif preset = 10
    # High Pass
    center_frequency = 1000
    bandwidth = 2000
    gain = -100
    isPassFilter = 3
else
    isPassFilter = 0
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
originalDur = Get total duration
sampleRate = Get sampling frequency
nyquist = sampleRate / 2

# Validate frequency range
if center_frequency >= nyquist
    exitScript: "Center frequency must be below Nyquist (" + string$(round(nyquist)) + " Hz)."
endif

# Calculate filter boundaries
lowFreq = max(0, center_frequency - bandwidth / 2)
highFreq = min(nyquist, center_frequency + bandwidth / 2)

# Convert gain to linear
if gain <= -100
    linearGain = 0
else
    linearGain = 10 ^ (gain / 20)
endif

# ============================================================
# DRAW FREQUENCY RESPONSE
# ============================================================
if draw_response
    Erase all
    Select outer viewport: 0, 6, 0, 4.5
    
    # Y-axis in dB (-24 to +12)
    minDB = -24
    maxDB = 12
    Axes: 0, nyquist, minDB, maxDB
    
    Colour: "Black"
    Draw inner box
    
    # Grid lines
    Colour: "{0.8,0.8,0.8}"
    
    # Horizontal grid (every 6 dB)
    dbLine = -18
    while dbLine <= 6
        Draw line: 0, dbLine, nyquist, dbLine
        dbLine = dbLine + 6
    endwhile
    
    # 0 dB reference line
    Colour: "{0.5,0.5,0.5}"
    Line width: 1
    Draw line: 0, 0, nyquist, 0
    
    # Vertical grid
    Colour: "{0.8,0.8,0.8}"
    if nyquist > 15000
        gridStep = 5000
    elsif nyquist > 8000
        gridStep = 2000
    else
        gridStep = 1000
    endif
    
    gridFreq = gridStep
    while gridFreq < nyquist
        Draw line: gridFreq, minDB, gridFreq, maxDB
        gridFreq = gridFreq + gridStep
    endwhile
    
    # Draw filter response curve
    Colour: "Blue"
    Line width: 2
    
    step = nyquist / 300
    plotFreq = step
    
    # Determine first point
    if isPassFilter = 1
        # Bandpass - outside band is -inf
        if 0 < lowFreq
            prevDB = minDB
        else
            prevDB = 0
        endif
    elsif isPassFilter = 2
        # Low pass
        prevDB = 0
    elsif isPassFilter = 3
        # High pass
        prevDB = minDB
    else
        # EQ boost/cut - flat outside band
        prevDB = 0
    endif
    prevX = 0
    
    while plotFreq <= nyquist
        if isPassFilter = 1
            # Bandpass mode
            if plotFreq < lowFreq
                responseDB = minDB
            elsif plotFreq > highFreq
                responseDB = minDB
            else
                # Raised cosine inside band
                phase = pi * (plotFreq - center_frequency) / (bandwidth / 2)
                response = 0.5 * (1 + cos(phase))
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, responseDB)
                endif
            endif
        elsif isPassFilter = 2
            # Low pass mode
            if plotFreq < lowFreq
                responseDB = 0
            elsif plotFreq > highFreq
                responseDB = minDB
            else
                # Smooth rolloff
                phase = pi * (plotFreq - lowFreq) / bandwidth
                response = 0.5 * (1 + cos(phase))
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, responseDB)
                endif
            endif
        elsif isPassFilter = 3
            # High pass mode
            if plotFreq < lowFreq
                responseDB = minDB
            elsif plotFreq > highFreq
                responseDB = 0
            else
                # Smooth rolloff
                phase = pi * (highFreq - plotFreq) / bandwidth
                response = 0.5 * (1 + cos(phase))
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, responseDB)
                endif
            endif
        else
            # EQ boost/cut mode
            if plotFreq < lowFreq or plotFreq > highFreq
                responseDB = 0
            else
                # Raised cosine shape
                phase = pi * (plotFreq - center_frequency) / (bandwidth / 2)
                boostAmount = 0.5 * (1 + cos(phase))
                
                if gain >= 0
                    # Boost
                    response = 1 + boostAmount * (linearGain - 1)
                else
                    # Cut
                    response = 1 - boostAmount * (1 - linearGain)
                endif
                
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, min(maxDB, responseDB))
                endif
            endif
        endif
        
        Draw line: prevX, prevDB, plotFreq, responseDB
        prevX = plotFreq
        prevDB = responseDB
        plotFreq = plotFreq + step
    endwhile
    
    # Mark center frequency
    Colour: "{0.6,0.6,0.6}"
    Line width: 1
    Dotted line
    Draw line: center_frequency, minDB, center_frequency, maxDB
    Solid line
    
    # Mark bandwidth edges
    Draw line: lowFreq, minDB, lowFreq, maxDB
    Draw line: highFreq, minDB, highFreq, maxDB
    
    # Labels
    Colour: "Black"
    Font size: 12
    
    # Title
    if isPassFilter = 1
        titleText$ = "Bandpass Filter"
    elsif isPassFilter = 2
        titleText$ = "Low Pass Filter"
    elsif isPassFilter = 3
        titleText$ = "High Pass Filter"
    elsif gain >= 0
        titleText$ = "Band Boost (+" + fixed$(gain, 1) + " dB)"
    else
        titleText$ = "Band Cut (" + fixed$(gain, 1) + " dB)"
    endif
    Text: nyquist / 2, "Centre", maxDB + 1.5, "Half", titleText$
    
    # Axis labels
    Font size: 10
    Text: nyquist / 2, "Centre", minDB - 2, "Half", "Frequency (Hz)"
    
    # Parameter info
    Colour: "{0.3,0.3,0.3}"
    Font size: 9
    Text: nyquist * 0.85, "Centre", maxDB - 2, "Half", "Center: " + string$(round(center_frequency)) + " Hz"
    Text: nyquist * 0.85, "Centre", maxDB - 4, "Half", "Width: " + string$(round(bandwidth)) + " Hz"
    
    # Axis marks
    Colour: "Black"
    if nyquist > 15000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 8000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    Marks left every: 1, 6, "yes", "yes", "no"
    
    Line width: 1
endif

# ============================================================
# SPECTRAL PROCESSING
# ============================================================
selectObject: originalID
spectrumObj = To Spectrum: "yes"

# Build formula strings
lowStr$ = fixed$(lowFreq, 2)
highStr$ = fixed$(highFreq, 2)
centerStr$ = fixed$(center_frequency, 2)
halfBW$ = fixed$(bandwidth / 2, 2)
bwStr$ = fixed$(bandwidth, 2)
gainStr$ = fixed$(linearGain, 6)

selectObject: spectrumObj

if isPassFilter = 1
    # Bandpass: raised cosine window, zero outside
    Formula: "if x < " + lowStr$ + " or x > " + highStr$ + " then 0 else self * 0.5 * (1 + cos(pi * (x - " + centerStr$ + ") / " + halfBW$ + ")) fi"

elsif isPassFilter = 2
    # Low pass: smooth rolloff
    Formula: "if x < " + lowStr$ + " then self else (if x > " + highStr$ + " then 0 else self * 0.5 * (1 + cos(pi * (x - " + lowStr$ + ") / " + bwStr$ + ")) fi) fi"

elsif isPassFilter = 3
    # High pass: smooth rolloff
    Formula: "if x > " + highStr$ + " then self else (if x < " + lowStr$ + " then 0 else self * 0.5 * (1 + cos(pi * (" + highStr$ + " - x) / " + bwStr$ + ")) fi) fi"

else
    # EQ boost/cut mode
    if gain >= 0
        # Boost: multiply by (1 + shape * (gain - 1))
        gainMinusOne$ = fixed$(linearGain - 1, 6)
        Formula: "if x < " + lowStr$ + " or x > " + highStr$ + " then self else self * (1 + 0.5 * (1 + cos(pi * (x - " + centerStr$ + ") / " + halfBW$ + ")) * " + gainMinusOne$ + ") fi"
    else
        # Cut: multiply by (1 - shape * (1 - gain))
        oneMinusGain$ = fixed$(1 - linearGain, 6)
        Formula: "if x < " + lowStr$ + " or x > " + highStr$ + " then self else self * (1 - 0.5 * (1 + cos(pi * (x - " + centerStr$ + ") / " + halfBW$ + ")) * " + oneMinusGain$ + ") fi"
    endif
endif

# Convert back to sound
To Sound
filteredID = selected("Sound")

# Crop to original duration (remove FFT padding)
selectObject: filteredID
croppedID = Extract part: 0, originalDur, "rectangular", 1, "no"
Rename: originalName$ + "_eq"

# Scale to prevent clipping
selectObject: croppedID
Scale peak: 0.95

# Cleanup
removeObject: spectrumObj, filteredID

# ============================================================
# INFO OUTPUT
# ============================================================
writeInfoLine: "Spectral Band EQ Complete"
appendInfoLine: "========================="
appendInfoLine: "Center: ", round(center_frequency), " Hz"
appendInfoLine: "Bandwidth: ", round(bandwidth), " Hz"
appendInfoLine: "Range: ", round(lowFreq), " - ", round(highFreq), " Hz"
if isPassFilter = 1
    appendInfoLine: "Mode: Bandpass"
elsif isPassFilter = 2
    appendInfoLine: "Mode: Low Pass"
elsif isPassFilter = 3
    appendInfoLine: "Mode: High Pass"
else
    appendInfoLine: "Gain: ", fixed$(gain, 1), " dB"
endif

if play_result
    selectObject: croppedID
    Play
endif
