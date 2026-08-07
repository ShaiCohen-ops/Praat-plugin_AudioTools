# ============================================================
# Praat AudioTools - Spectral_Band_EQ.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral Band EQ - zero-phase frequency-domain shaping with
#   explicit bell, bandpass, low/high-pass, and low/high-shelf modes.
#   Raised-cosine transitions are used to avoid hard spectral edges.
#
#   Parameter semantics:
#     Parametric Bell : center = maximum boost/cut; bandwidth = full
#                       raised-cosine span (gain returns to 0 dB at edges)
#     Bandpass        : center + bandwidth define the FLAT passband;
#                       transition width is applied outside both edges
#     Low Pass        : center = flat-passband edge; transition above it
#     High Pass       : center = flat-passband edge; transition below it
#     Low Shelf       : gain is flat below center; transition to 0 dB above
#     High Shelf      : gain is flat above center; transition from 0 dB below
#
#   Processing is applied independently to every input channel. The original
#   channel count, duration, sample rate, and start time are preserved.
#
#   NOTE: This is whole-file, zero-phase spectral filtering. Smooth spectral
#   transitions reduce hard-edge ringing but do not make the process causal.
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
originalStart = Get start time
nSamples = Get number of samples

if originalDur <= 0
    exitScript: "The selected Sound is empty."
endif

# ============================================================
# FORM
# ============================================================
form Spectral Band EQ v1.1
    optionmenu Preset: 1
        option Custom
        option Telephone Bandpass (300-3400 Hz)
        option AM Radio Bandpass (500-4500 Hz)
        option Sub Bass Shelf (+6 dB below 100 Hz)
        option Presence Bell (+4 dB at 3.5 kHz)
        option Mud Bell (-6 dB at 350 Hz)
        option Air Shelf (+3 dB above 10 kHz)
        option Mid Scoop Bell (-8 dB at 2 kHz)
        option Low Pass (flat below 2 kHz)
        option High Pass (flat above 500 Hz)
    comment === Filter Mode ===
    optionmenu Filter_mode: 1
        option Parametric Bell
        option Bandpass
        option Low Pass
        option High Pass
        option Low Shelf
        option High Shelf
    comment === Frequency Parameters ===
    positive Center_frequency_Hz 1000
    positive Bandwidth_Hz 500
    positive Transition_width_Hz 100
    real Gain_dB 6.0
    comment Bell: bandwidth = full cosine span. Bandpass: bandwidth = flat passband.
    comment LP/HP/Shelf: center = passband/shelf edge; transition = rolloff width.
    comment === Output ===
    real Safety_peak 0.99
    comment (0 = off; otherwise only attenuates when peak exceeds this value)
    boolean Draw_response 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================
presetName$ = "Custom"
if preset = 2
    filter_mode = 2
    center_frequency_Hz = 1850
    bandwidth_Hz = 3100
    transition_width_Hz = 150
    gain_dB = 0
    presetName$ = "TelephoneBandpass"
elsif preset = 3
    filter_mode = 2
    center_frequency_Hz = 2500
    bandwidth_Hz = 4000
    transition_width_Hz = 200
    gain_dB = 0
    presetName$ = "AMRadioBandpass"
elsif preset = 4
    filter_mode = 5
    center_frequency_Hz = 100
    bandwidth_Hz = 100
    transition_width_Hz = 80
    gain_dB = 6
    presetName$ = "SubBassShelf"
elsif preset = 5
    filter_mode = 1
    center_frequency_Hz = 3500
    bandwidth_Hz = 3000
    transition_width_Hz = 100
    gain_dB = 4
    presetName$ = "PresenceBell"
elsif preset = 6
    filter_mode = 1
    center_frequency_Hz = 350
    bandwidth_Hz = 300
    transition_width_Hz = 100
    gain_dB = -6
    presetName$ = "MudBell"
elsif preset = 7
    filter_mode = 6
    center_frequency_Hz = 10000
    bandwidth_Hz = 8000
    transition_width_Hz = 2000
    gain_dB = 3
    presetName$ = "AirShelf"
elsif preset = 8
    filter_mode = 1
    center_frequency_Hz = 2000
    bandwidth_Hz = 2000
    transition_width_Hz = 100
    gain_dB = -8
    presetName$ = "MidScoopBell"
elsif preset = 9
    filter_mode = 3
    center_frequency_Hz = 2000
    bandwidth_Hz = 500
    transition_width_Hz = 500
    gain_dB = 0
    presetName$ = "LowPass"
elsif preset = 10
    filter_mode = 4
    center_frequency_Hz = 500
    bandwidth_Hz = 500
    transition_width_Hz = 500
    gain_dB = 0
    presetName$ = "HighPass"
endif

# ============================================================
# VALIDATE & DERIVE
# ============================================================
warnLines$ = ""

if center_frequency_Hz < 0
    center_frequency_Hz = 0
endif
if center_frequency_Hz > nyquist
    warnLines$ = warnLines$ + "  Center clamped to Nyquist." + newline$
    center_frequency_Hz = nyquist
endif
if bandwidth_Hz < 1
    bandwidth_Hz = 1
endif
if transition_width_Hz < 1
    transition_width_Hz = 1
endif
if gain_dB < -120
    gain_dB = -120
endif
if gain_dB > 36
    gain_dB = 36
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

linearGain = 10 ^ (gain_dB / 20)

if filter_mode = 1
    modeName$ = "Parametric Bell"
    bandLow = max(0, center_frequency_Hz - bandwidth_Hz / 2)
    bandHigh = min(nyquist, center_frequency_Hz + bandwidth_Hz / 2)
    if bandHigh <= bandLow
        exitScript: "The bell bandwidth does not overlap the sampled spectrum."
    endif
    bellCenter = (bandLow + bandHigh) / 2
    bellHalf = (bandHigh - bandLow) / 2
elsif filter_mode = 2
    modeName$ = "Bandpass"
    passLow = max(0, center_frequency_Hz - bandwidth_Hz / 2)
    passHigh = min(nyquist, center_frequency_Hz + bandwidth_Hz / 2)
    if passHigh <= passLow
        exitScript: "The bandpass width does not overlap the sampled spectrum."
    endif
    stopLow = max(0, passLow - transition_width_Hz)
    stopHigh = min(nyquist, passHigh + transition_width_Hz)
elsif filter_mode = 3
    modeName$ = "Low Pass"
    passEdge = center_frequency_Hz
    stopEdge = min(nyquist, center_frequency_Hz + transition_width_Hz)
elsif filter_mode = 4
    modeName$ = "High Pass"
    passEdge = center_frequency_Hz
    stopEdge = max(0, center_frequency_Hz - transition_width_Hz)
elsif filter_mode = 5
    modeName$ = "Low Shelf"
    shelfEdge = center_frequency_Hz
    unityEdge = min(nyquist, center_frequency_Hz + transition_width_Hz)
else
    modeName$ = "High Shelf"
    shelfEdge = center_frequency_Hz
    unityEdge = max(0, center_frequency_Hz - transition_width_Hz)
endif

# ============================================================
# BUILD SPECTRUM FORMULA
# ============================================================
if filter_mode = 1
    lo$ = fixed$(bandLow, 8)
    hi$ = fixed$(bandHigh, 8)
    ctr$ = fixed$(bellCenter, 8)
    half$ = fixed$(bellHalf, 8)
    gm1$ = fixed$(linearGain - 1, 12)
    eqFormula$ = "if x < " + lo$ + " or x > " + hi$ + " then self else self * (1 + 0.5 * (1 + cos(pi * (x - " + ctr$ + ") / " + half$ + ")) * " + gm1$ + ") fi"
elsif filter_mode = 2
    pl$ = fixed$(passLow, 8)
    ph$ = fixed$(passHigh, 8)
    sl$ = fixed$(stopLow, 8)
    sh$ = fixed$(stopHigh, 8)
    twL = passLow - stopLow
    twH = stopHigh - passHigh
    if twL < 1e-9
        twL = 1e-9
    endif
    if twH < 1e-9
        twH = 1e-9
    endif
    twL$ = fixed$(twL, 12)
    twH$ = fixed$(twH, 12)
    eqFormula$ = "if x < " + sl$ + " or x > " + sh$ + " then 0 else (if x < " + pl$ + " then self * 0.5 * (1 - cos(pi * (x - " + sl$ + ") / " + twL$ + ")) else (if x <= " + ph$ + " then self else self * 0.5 * (1 + cos(pi * (x - " + ph$ + ") / " + twH$ + ")) fi) fi) fi"
elsif filter_mode = 3
    pe$ = fixed$(passEdge, 8)
    se$ = fixed$(stopEdge, 8)
    tw = stopEdge - passEdge
    if tw < 1e-9
        tw = 1e-9
    endif
    tw$ = fixed$(tw, 12)
    eqFormula$ = "if x <= " + pe$ + " then self else (if x >= " + se$ + " then 0 else self * 0.5 * (1 + cos(pi * (x - " + pe$ + ") / " + tw$ + ")) fi) fi"
elsif filter_mode = 4
    pe$ = fixed$(passEdge, 8)
    se$ = fixed$(stopEdge, 8)
    tw = passEdge - stopEdge
    if tw < 1e-9
        tw = 1e-9
    endif
    tw$ = fixed$(tw, 12)
    eqFormula$ = "if x >= " + pe$ + " then self else (if x <= " + se$ + " then 0 else self * 0.5 * (1 - cos(pi * (x - " + se$ + ") / " + tw$ + ")) fi) fi"
elsif filter_mode = 5
    se$ = fixed$(shelfEdge, 8)
    ue$ = fixed$(unityEdge, 8)
    tw = unityEdge - shelfEdge
    if tw < 1e-9
        tw = 1e-9
    endif
    tw$ = fixed$(tw, 12)
    gm1$ = fixed$(linearGain - 1, 12)
    eqFormula$ = "if x <= " + se$ + " then self * " + fixed$(linearGain, 12) + " else (if x >= " + ue$ + " then self else self * (1 + 0.5 * (1 + cos(pi * (x - " + se$ + ") / " + tw$ + ")) * " + gm1$ + ") fi) fi"
else
    se$ = fixed$(shelfEdge, 8)
    ue$ = fixed$(unityEdge, 8)
    tw = shelfEdge - unityEdge
    if tw < 1e-9
        tw = 1e-9
    endif
    tw$ = fixed$(tw, 12)
    gm1$ = fixed$(linearGain - 1, 12)
    eqFormula$ = "if x >= " + se$ + " then self * " + fixed$(linearGain, 12) + " else (if x <= " + ue$ + " then self else self * (1 + 0.5 * (1 - cos(pi * (x - " + ue$ + ") / " + tw$ + ")) * " + gm1$ + ") fi) fi"
endif

# ============================================================
# PROCESSING
# ============================================================
# Work at time zero so Spectrum->Sound and object indexing are independent of
# the input Sound's original time domain. Restore originalStart at the end.
selectObject: originalID
workID = Copy: "sbeq_work"
selectObject: workID
Shift times to: "start time", 0

outputID = Create Sound from formula: "sbeq_out", nChannels, 0, originalDur, sampleRate, "0"

for ch from 1 to nChannels
    selectObject: workID
    chID = Extract one channel: ch
    selectObject: chID
    spID = To Spectrum: "yes"
    selectObject: spID
    Formula: eqFormula$
    filtID = To Sound

    selectObject: outputID
    Formula (part): 0, originalDur, ch, ch, "object['filtID:0', 1, col]"

    removeObject: chID, spID, filtID
endfor
removeObject: workID

selectObject: outputID
if originalStart <> 0
    Shift times by: originalStart
endif
outputName$ = originalName$ + "_spectralEQ_" + presetName$
Rename: outputName$
outputID = selected("Sound")

# Safety attenuation only; never boost.
selectObject: outputID
peakOut = Get absolute extremum: 0, 0, "None"
safetyApplied = 0
if safety_peak > 0 and peakOut > safety_peak
    Formula: "self * " + string$(safety_peak / peakOut)
    safetyApplied = 1
    peakOut = Get absolute extremum: 0, 0, "None"
endif

selectObject: originalID
peakIn = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_response
    Erase all
    colIn$ = "{0.48, 0.48, 0.52}"
    colOut$ = "{0.20, 0.42, 0.82}"
    colAcc$ = "{0.42, 0.34, 0.72}"
    colGrey$ = "{0.96, 0.96, 0.97}"
    colGrid$ = "{0.86, 0.86, 0.88}"

    # Title
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.75, "half", "##Spectral Band EQ v1.1##"
    Font size: 7
    Colour: colAcc$
    Text: 0.5, "centre", 0.22, "half", originalName$ + " | " + modeName$ + " | " + presetName$

    vizDur = min(originalDur, 8)

    # Input waveform
    Select outer viewport: 0, 4, 0.65, 1.95
    Select inner viewport: 0.55, 3.85, 0.78, 1.88
    selectObject: originalID
    monoIn = Convert to mono
    Colour: colIn$
    Draw: originalStart, originalStart + vizDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Text bottom: "yes", "Time (s)"

    # Output waveform
    Select outer viewport: 4, 8, 0.65, 1.95
    Select inner viewport: 4.2, 7.7, 0.78, 1.88
    selectObject: outputID
    monoOut = Convert to mono
    Colour: colOut$
    Draw: originalStart, originalStart + vizDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Output"
    Text bottom: "yes", "Time (s)"

    # Theoretical response
    Select outer viewport: 0, 8, 2.05, 4.65
    Select inner viewport: 0.75, 7.7, 2.22, 4.48
    if gain_dB > 0
        yMax = max(12, gain_dB + 3)
    else
        yMax = 6
    endif
    yMin = -36
    Axes: 0, nyquist, yMin, yMax
    Paint rectangle: colGrey$, 0, nyquist, yMin, yMax
    Colour: colGrid$
    dbGrid = -30
    while dbGrid <= yMax
        Draw line: 0, dbGrid, nyquist, dbGrid
        dbGrid = dbGrid + 6
    endwhile
    Colour: "{0.65,0.65,0.68}"
    Draw line: 0, 0, nyquist, 0

    nPlot = 500
    prevF = 0
    prevG = 1
    for ip from 0 to nPlot
        f = nyquist * ip / nPlot
        # Evaluate the same response used in processing.
        if filter_mode = 1
            if f < bandLow or f > bandHigh
                g = 1
            else
                shape = 0.5 * (1 + cos(pi * (f - bellCenter) / bellHalf))
                g = 1 + shape * (linearGain - 1)
            endif
        elsif filter_mode = 2
            if f < stopLow or f > stopHigh
                g = 0
            elsif f < passLow
                if passLow > stopLow
                    g = 0.5 * (1 - cos(pi * (f - stopLow) / (passLow - stopLow)))
                else
                    g = 1
                endif
            elsif f <= passHigh
                g = 1
            else
                if stopHigh > passHigh
                    g = 0.5 * (1 + cos(pi * (f - passHigh) / (stopHigh - passHigh)))
                else
                    g = 1
                endif
            endif
        elsif filter_mode = 3
            if f <= passEdge
                g = 1
            elsif f >= stopEdge
                g = 0
            else
                g = 0.5 * (1 + cos(pi * (f - passEdge) / (stopEdge - passEdge)))
            endif
        elsif filter_mode = 4
            if f >= passEdge
                g = 1
            elsif f <= stopEdge
                g = 0
            else
                g = 0.5 * (1 - cos(pi * (f - stopEdge) / (passEdge - stopEdge)))
            endif
        elsif filter_mode = 5
            if f <= shelfEdge
                g = linearGain
            elsif f >= unityEdge
                g = 1
            else
                shape = 0.5 * (1 + cos(pi * (f - shelfEdge) / (unityEdge - shelfEdge)))
                g = 1 + shape * (linearGain - 1)
            endif
        else
            if f >= shelfEdge
                g = linearGain
            elsif f <= unityEdge
                g = 1
            else
                shape = 0.5 * (1 - cos(pi * (f - unityEdge) / (shelfEdge - unityEdge)))
                g = 1 + shape * (linearGain - 1)
            endif
        endif
        if g <= 1e-6
            gdB = yMin
        else
            gdB = 20 * log10(g)
            if gdB < yMin
                gdB = yMin
            endif
            if gdB > yMax
                gdB = yMax
            endif
        endif
        if ip > 0
            Colour: colAcc$
            Line width: 2
            Draw line: prevF, prevDB, f, gdB
        endif
        prevF = f
        prevDB = gdB
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 6, "yes", "yes", "no"
    if nyquist >= 20000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist >= 10000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    Font size: 7
    Text left: "yes", "Gain (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Theoretical spectral gain"

    # Summary strip
    Select outer viewport: 0, 8, 4.8, 5.75
    Select inner viewport: 0.55, 7.7, 4.86, 5.68
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.95}", 0, 1, 0, 1
    Colour: "{0.25,0.25,0.32}"
    Font size: 6
    Text: 0.02, "left", 0.76, "half", "##Mode##  " + modeName$ + "   center=" + fixed$(center_frequency_Hz, 1) + " Hz   bandwidth=" + fixed$(bandwidth_Hz, 1) + " Hz"
    Text: 0.02, "left", 0.48, "half", "##Transition##  " + fixed$(transition_width_Hz, 1) + " Hz   gain=" + fixed$(gain_dB, 2) + " dB   channels=" + string$(nChannels) + "   SR=" + string$(round(sampleRate)) + " Hz"
    Text: 0.02, "left", 0.20, "half", "##Peak##  " + fixed$(peakIn, 4) + " -> " + fixed$(peakOut, 4) + "   safety=" + fixed$(safety_peak, 2) + "   start=" + fixed$(originalStart, 3) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: monoIn, monoOut
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# INFO
# ============================================================
clearinfo
writeInfoLine: "=== Spectral Band EQ v1.1 ==="
appendInfoLine: "Source: ", originalName$, "   ", fixed$(originalDur, 3), " s   ", nChannels, " ch   ", round(sampleRate), " Hz"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Center/edge: ", fixed$(center_frequency_Hz, 2), " Hz"
if filter_mode = 1
    appendInfoLine: "Bell span: ", fixed$(bandLow, 2), " - ", fixed$(bandHigh, 2), " Hz; peak gain ", fixed$(gain_dB, 2), " dB"
elsif filter_mode = 2
    appendInfoLine: "Flat passband: ", fixed$(passLow, 2), " - ", fixed$(passHigh, 2), " Hz"
    appendInfoLine: "Transitions: ", fixed$(stopLow, 2), " - ", fixed$(passLow, 2), " Hz and ", fixed$(passHigh, 2), " - ", fixed$(stopHigh, 2), " Hz"
elsif filter_mode = 3
    appendInfoLine: "Flat passband: 0 - ", fixed$(passEdge, 2), " Hz; transition to ", fixed$(stopEdge, 2), " Hz"
elsif filter_mode = 4
    appendInfoLine: "Transition: ", fixed$(stopEdge, 2), " - ", fixed$(passEdge, 2), " Hz; flat above"
elsif filter_mode = 5
    appendInfoLine: "Low shelf: ", fixed$(gain_dB, 2), " dB through ", fixed$(shelfEdge, 2), " Hz; transition to ", fixed$(unityEdge, 2), " Hz"
else
    appendInfoLine: "High shelf: transition from ", fixed$(unityEdge, 2), " Hz; ", fixed$(gain_dB, 2), " dB from ", fixed$(shelfEdge, 2), " Hz upward"
endif
appendInfoLine: "Peak: ", fixed$(peakIn, 4), " -> ", fixed$(peakOut, 4)
if safetyApplied
    appendInfoLine: "Safety attenuation applied to final output."
endif
if warnLines$ <> ""
    appendInfoLine: "Notes:"
    appendInfo: warnLines$
endif
appendInfoLine: "Output: ", outputName$

selectObject: outputID
if play_result
    Play
endif
selectObject: outputID
