# ============================================================
# Praat AudioTools - Spectral_Band_EQ.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Band EQ — frequency-domain equalizer with
#   bandpass, low-pass, high-pass, and parametric boost/cut
#   modes. Uses raised cosine window functions applied to
#   the Spectrum object for smooth, artifact-free shaping.
#
#   Modes:
#     Bandpass:  raised cosine passband, zero outside
#     Low pass:  flat below cutoff, cosine rolloff, zero above
#     High pass: zero below, cosine rolloff, flat above cutoff
#     EQ boost:  parametric gain increase in band
#     EQ cut:    parametric gain reduction in band
#
#   For bandpass/EQ modes: center_frequency + bandwidth define
#   the affected band symmetrically.
#   For LP/HP modes: center_frequency = cutoff point,
#   bandwidth = transition width of the rolloff.
#
#   Handles mono and stereo input (channels processed
#   independently and recombined).
#
# Changelog v1.0 (from v0.1):
#   - Added stereo support (per-channel processing)
#   - Fixed Scale peak: only clamp if peak > 1.0 (cuts no
#     longer boost overall level back up)
#   - Fixed LP/HP presets: cutoff + transition width gives
#     a proper flat passband
#   - LP/HP frequency computation uses cutoff semantics
#   - Added library-standard header and visualization
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Spectral & Frequency Domain
# ============================================================

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
nChannels = Get number of channels

# ============================================================
# FORM
# ============================================================
form Spectral Band EQ v1.0
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
    comment For LP/HP: center = cutoff, bandwidth = transition
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
    # Low Pass < 2 kHz: flat below 2 kHz, 500 Hz rolloff
    center_frequency = 2000
    bandwidth = 500
    gain = -100
    isPassFilter = 2
elsif preset = 10
    # High Pass > 500 Hz: 500 Hz rolloff, flat above 500 Hz
    center_frequency = 500
    bandwidth = 500
    gain = -100
    isPassFilter = 3
else
    isPassFilter = 0
endif

# ============================================================
# VALIDATE & DERIVE
# ============================================================
if center_frequency >= nyquist
    exitScript: "Center frequency must be below Nyquist ("
        ... + string$(round(nyquist)) + " Hz)."
endif

# Calculate filter boundaries
# For bandpass/EQ: symmetric around center
# For LP: flat below center, rolloff from center to center+bandwidth
# For HP: rolloff from center-bandwidth to center, flat above
if isPassFilter = 2
    # Low pass: center = cutoff
    lowFreq = max(0, center_frequency)
    highFreq = min(nyquist, center_frequency + bandwidth)
elsif isPassFilter = 3
    # High pass: center = cutoff
    lowFreq = max(0, center_frequency - bandwidth)
    highFreq = min(nyquist, center_frequency)
else
    # Bandpass / EQ: symmetric
    lowFreq = max(0, center_frequency - bandwidth / 2)
    highFreq = min(nyquist, center_frequency + bandwidth / 2)
endif

# Transition width for LP/HP
transWidth = highFreq - lowFreq
if transWidth < 1
    transWidth = 1
endif

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

    # --- Viewport ---
    Select outer viewport: 0, 8, 0, 5.5
    Select inner viewport: 0.8, 7.5, 0.6, 4.8

    minDB = -24
    maxDB = 12
    Axes: 0, nyquist, minDB, maxDB

    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, nyquist, minDB, maxDB

    # Horizontal grid (every 6 dB)
    Colour: "{0.85, 0.85, 0.85}"
    dbLine = -18
    while dbLine <= 6
        Draw line: 0, dbLine, nyquist, dbLine
        dbLine += 6
    endwhile

    # 0 dB reference
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: 0, 0, nyquist, 0

    # Vertical grid
    Colour: "{0.85, 0.85, 0.85}"
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
        gridFreq += gridStep
    endwhile

    # --- Filter band shading ---
    if isPassFilter = 1
        # Bandpass: shade passband
        Paint rectangle: "{0.85, 0.92, 1.0}",
            ... lowFreq, highFreq, minDB, maxDB
    elsif isPassFilter = 2
        # LP: shade passband (left of cutoff)
        Paint rectangle: "{0.85, 0.95, 0.88}",
            ... 0, lowFreq, minDB, maxDB
        Paint rectangle: "{0.92, 0.92, 0.97}",
            ... lowFreq, highFreq, minDB, maxDB
    elsif isPassFilter = 3
        # HP: shade passband (right of cutoff)
        Paint rectangle: "{0.85, 0.95, 0.88}",
            ... highFreq, nyquist, minDB, maxDB
        Paint rectangle: "{0.92, 0.92, 0.97}",
            ... lowFreq, highFreq, minDB, maxDB
    else
        # EQ: shade affected band
        if gain >= 0
            Paint rectangle: "{0.88, 0.95, 0.88}",
                ... lowFreq, highFreq, 0, maxDB
        else
            Paint rectangle: "{0.98, 0.90, 0.88}",
                ... lowFreq, highFreq, minDB, 0
        endif
    endif

    # --- Draw response curve ---
    Colour: "{0.2, 0.4, 0.85}"
    Line width: 2.5

    step = nyquist / 400
    plotFreq = step

    # First point
    if isPassFilter = 1
        if 0 < lowFreq
            prevDB = minDB
        else
            prevDB = 0
        endif
    elsif isPassFilter = 2
        prevDB = 0
    elsif isPassFilter = 3
        if lowFreq > 0
            prevDB = minDB
        else
            prevDB = 0
        endif
    else
        prevDB = 0
    endif
    prevX = 0

    while plotFreq <= nyquist
        if isPassFilter = 1
            # Bandpass
            if plotFreq < lowFreq or plotFreq > highFreq
                responseDB = minDB
            else
                halfBW = (highFreq - lowFreq) / 2
                ctr = (lowFreq + highFreq) / 2
                if halfBW < 1
                    halfBW = 1
                endif
                phase = pi * (plotFreq - ctr) / halfBW
                response = 0.5 * (1 + cos(phase))
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, responseDB)
                endif
            endif
        elsif isPassFilter = 2
            # Low pass
            if plotFreq <= lowFreq
                responseDB = 0
            elsif plotFreq >= highFreq
                responseDB = minDB
            else
                phase = pi * (plotFreq - lowFreq) / transWidth
                response = 0.5 * (1 + cos(phase))
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, responseDB)
                endif
            endif
        elsif isPassFilter = 3
            # High pass
            if plotFreq >= highFreq
                responseDB = 0
            elsif plotFreq <= lowFreq
                responseDB = minDB
            else
                phase = pi * (highFreq - plotFreq) / transWidth
                response = 0.5 * (1 + cos(phase))
                if response <= 0.001
                    responseDB = minDB
                else
                    responseDB = 20 * log10(response)
                    responseDB = max(minDB, responseDB)
                endif
            endif
        else
            # EQ boost/cut
            if plotFreq < lowFreq or plotFreq > highFreq
                responseDB = 0
            else
                halfBW = (highFreq - lowFreq) / 2
                ctr = (lowFreq + highFreq) / 2
                if halfBW < 1
                    halfBW = 1
                endif
                phase = pi * (plotFreq - ctr) / halfBW
                boostAmount = 0.5 * (1 + cos(phase))
                if gain >= 0
                    response = 1 + boostAmount * (linearGain - 1)
                else
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
        plotFreq += step
    endwhile

    Line width: 1

    # --- Band edge markers ---
    Colour: "{0.7, 0.7, 0.7}"
    Dotted line
    Draw line: lowFreq, minDB, lowFreq, maxDB
    Draw line: highFreq, minDB, highFreq, maxDB
    if isPassFilter = 0
        # Center line for EQ
        Draw line: center_frequency, minDB, center_frequency, maxDB
    endif
    Solid line

    # --- Frame and labels ---
    Colour: "Black"
    Draw inner box

    Font size: 11
    if isPassFilter = 1
        titleText$ = "Bandpass: " + string$(round(lowFreq))
            ... + " – " + string$(round(highFreq)) + " Hz"
    elsif isPassFilter = 2
        titleText$ = "Low Pass: cutoff "
            ... + string$(round(center_frequency)) + " Hz"
    elsif isPassFilter = 3
        titleText$ = "High Pass: cutoff "
            ... + string$(round(center_frequency)) + " Hz"
    elsif gain >= 0
        titleText$ = "Band Boost: +" + fixed$(gain, 1)
            ... + " dB @ " + string$(round(center_frequency)) + " Hz"
    else
        titleText$ = "Band Cut: " + fixed$(gain, 1)
            ... + " dB @ " + string$(round(center_frequency)) + " Hz"
    endif
    Text top: "yes", "##" + titleText$ + "##"

    Font size: 8
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Gain (dB)"

    # Parameter info
    Colour: "{0.35, 0.35, 0.4}"
    Font size: 7
    Axes: 0, 1, 0, 1
    if isPassFilter = 2 or isPassFilter = 3
        Text: 0.97, "right", 0.95, "half",
            ... "Cutoff: " + string$(round(center_frequency)) + " Hz"
        Text: 0.97, "right", 0.88, "half",
            ... "Transition: " + string$(round(bandwidth)) + " Hz"
    else
        Text: 0.97, "right", 0.95, "half",
            ... "Center: " + string$(round(center_frequency)) + " Hz"
        Text: 0.97, "right", 0.88, "half",
            ... "Width: " + string$(round(bandwidth)) + " Hz"
        if isPassFilter = 0
            Text: 0.97, "right", 0.81, "half",
                ... "Gain: " + fixed$(gain, 1) + " dB"
        endif
    endif
    Text: 0.97, "right", 0.05, "half",
        ... originalName$ + " | "
        ... + string$(round(sampleRate)) + " Hz | "
        ... + string$(nChannels) + "ch"

    # Axis marks
    Colour: "Black"
    Font size: 8
    Axes: 0, nyquist, minDB, maxDB
    if nyquist > 15000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 8000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    Marks left every: 1, 6, "yes", "yes", "no"

    Line width: 1
    Font size: 10
endif

# ============================================================
# SPECTRAL PROCESSING
# ============================================================

# Build baked formula strings
lowStr$ = fixed$(lowFreq, 2)
highStr$ = fixed$(highFreq, 2)
twStr$ = fixed$(transWidth, 2)

if isPassFilter = 0
    halfBW = (highFreq - lowFreq) / 2
    if halfBW < 1
        halfBW = 1
    endif
    ctr = (lowFreq + highFreq) / 2
    centerStr$ = fixed$(ctr, 2)
    halfBWStr$ = fixed$(halfBW, 2)
endif

# Build the Formula string once
if isPassFilter = 1
    halfBW = (highFreq - lowFreq) / 2
    if halfBW < 1
        halfBW = 1
    endif
    ctr = (lowFreq + highFreq) / 2
    eqFormula$ = "if x < " + lowStr$ + " or x > " + highStr$
        ... + " then 0 else self * 0.5 * (1 + cos(pi * (x - "
        ... + fixed$(ctr, 2) + ") / " + fixed$(halfBW, 2) + ")) fi"
elsif isPassFilter = 2
    eqFormula$ = "if x <= " + lowStr$ + " then self"
        ... + " else (if x >= " + highStr$ + " then 0"
        ... + " else self * 0.5 * (1 + cos(pi * (x - " + lowStr$
        ... + ") / " + twStr$ + ")) fi) fi"
elsif isPassFilter = 3
    eqFormula$ = "if x >= " + highStr$ + " then self"
        ... + " else (if x <= " + lowStr$ + " then 0"
        ... + " else self * 0.5 * (1 + cos(pi * (" + highStr$
        ... + " - x) / " + twStr$ + ")) fi) fi"
else
    if gain >= 0
        gainMinusOne$ = fixed$(linearGain - 1, 6)
        eqFormula$ = "if x < " + lowStr$ + " or x > " + highStr$
            ... + " then self else self * (1 + 0.5 * (1 + cos(pi * (x - "
            ... + centerStr$ + ") / " + halfBWStr$ + ")) * "
            ... + gainMinusOne$ + ") fi"
    else
        oneMinusGain$ = fixed$(1 - linearGain, 6)
        eqFormula$ = "if x < " + lowStr$ + " or x > " + highStr$
            ... + " then self else self * (1 - 0.5 * (1 + cos(pi * (x - "
            ... + centerStr$ + ") / " + halfBWStr$ + ")) * "
            ... + oneMinusGain$ + ") fi"
    endif
endif

# --- Process per channel ---
if nChannels = 1
    selectObject: originalID
    spectrumObj = To Spectrum: "yes"
    selectObject: spectrumObj
    Formula: eqFormula$
    To Sound
    filteredID = selected("Sound")
    selectObject: filteredID
    croppedID = Extract part: 0, originalDur, "rectangular", 1, "no"
    removeObject: spectrumObj, filteredID
else
    # Stereo: process each channel independently
    selectObject: originalID
    ch1src = Extract one channel: 1
    selectObject: originalID
    ch2src = Extract one channel: 2

    # Channel 1
    selectObject: ch1src
    sp1 = To Spectrum: "yes"
    selectObject: sp1
    Formula: eqFormula$
    To Sound
    filt1 = selected("Sound")
    selectObject: filt1
    crop1 = Extract part: 0, originalDur, "rectangular", 1, "no"
    removeObject: sp1, filt1

    # Channel 2
    selectObject: ch2src
    sp2 = To Spectrum: "yes"
    selectObject: sp2
    Formula: eqFormula$
    To Sound
    filt2 = selected("Sound")
    selectObject: filt2
    crop2 = Extract part: 0, originalDur, "rectangular", 1, "no"
    removeObject: sp2, filt2

    # Recombine
    selectObject: crop1
    plusObject: crop2
    Combine to stereo
    croppedID = selected("Sound")
    removeObject: ch1src, ch2src, crop1, crop2
endif

# Name
selectObject: croppedID
Rename: originalName$ + "_eq"

# Scale peak ONLY if clipping (boosts may exceed 1.0; cuts should not be gained up)
selectObject: croppedID
peakVal = Get maximum: 0, 0, "Sinc70"
peakNeg = Get minimum: 0, 0, "Sinc70"
if peakNeg < 0
    peakNeg = -peakNeg
endif
if peakNeg > peakVal
    peakVal = peakNeg
endif
if peakVal > 1.0
    Scale peak: 0.95
endif

# ============================================================
# INFO OUTPUT
# ============================================================
clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  SPECTRAL BAND EQ v1.0"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source:     ", originalName$
appendInfoLine: "Duration:   ", fixed$(originalDur, 3), " s"
appendInfoLine: "Rate:       ", round(sampleRate), " Hz"
appendInfoLine: "Channels:   ", nChannels
appendInfoLine: ""
if isPassFilter = 1
    appendInfoLine: "Mode:       Bandpass"
    appendInfoLine: "Passband:   ", round(lowFreq), " – ",
        ... round(highFreq), " Hz"
    appendInfoLine: "Center:     ", round(center_frequency), " Hz"
    appendInfoLine: "Bandwidth:  ", round(bandwidth), " Hz"
elsif isPassFilter = 2
    appendInfoLine: "Mode:       Low Pass"
    appendInfoLine: "Cutoff:     ", round(center_frequency), " Hz"
    appendInfoLine: "Transition: ", round(bandwidth), " Hz"
    appendInfoLine: "Flat:       0 – ", round(lowFreq), " Hz"
    appendInfoLine: "Rolloff:    ", round(lowFreq), " – ",
        ... round(highFreq), " Hz"
elsif isPassFilter = 3
    appendInfoLine: "Mode:       High Pass"
    appendInfoLine: "Cutoff:     ", round(center_frequency), " Hz"
    appendInfoLine: "Transition: ", round(bandwidth), " Hz"
    appendInfoLine: "Rolloff:    ", round(lowFreq), " – ",
        ... round(highFreq), " Hz"
    appendInfoLine: "Flat:       ", round(highFreq), " – ",
        ... round(nyquist), " Hz"
else
    if gain >= 0
        appendInfoLine: "Mode:       EQ Boost"
    else
        appendInfoLine: "Mode:       EQ Cut"
    endif
    appendInfoLine: "Gain:       ", fixed$(gain, 1), " dB"
    appendInfoLine: "Center:     ", round(center_frequency), " Hz"
    appendInfoLine: "Bandwidth:  ", round(bandwidth), " Hz"
    appendInfoLine: "Band:       ", round(lowFreq), " – ",
        ... round(highFreq), " Hz"
endif
appendInfoLine: ""
appendInfoLine: "Output:     ", originalName$ + "_eq"
appendInfoLine: ""
appendInfoLine: "=================================================="

if play_result
    selectObject: croppedID
    Play
endif

selectObject: croppedID
