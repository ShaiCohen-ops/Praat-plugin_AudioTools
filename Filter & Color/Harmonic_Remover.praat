# ============================================================
# Praat AudioTools - Harmonic_Remover.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Remover — selectively removes the fundamental
#   frequency and/or chosen overtones from a sound.
#
#   Pipeline:
#     1. Pitch detection (To Pitch) gives F0 per frame
#     2. Short overlapping Hann-windowed frames (75% overlap,
#        COLA-compliant at hop = win/4)
#     3. For each frame: FFT → Gaussian notch at tracked
#        harmonic frequencies → iFFT
#     4. Overlap-add with normalization factor 2.0
#        (exact COLA constant for Hann at 75% overlap)
#     5. Unvoiced frames pass through unmodified
#
#   The notch uses a smooth Gaussian shape:
#     gain(f) = 1 - exp(-((f - f_harmonic) / sigma)^2)
#   Multiple harmonics multiply (product of notch gains).
#   This avoids ringing artifacts from hard rectangular notches.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

# ---- Input validation ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

if duration < 0.1
    exitScript: "Sound must be at least 100 ms."
endif

# ============================================================
# FORM
# ============================================================

form Harmonic Remover v1.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Remove Fundamental (de-buzz)
        option Remove Odd Harmonics (3,5,7...)
        option Remove Even Harmonics (2,4,6...)
        option Remove All Overtones (keep F0 only)
        option Remove F0 + All Overtones (noise/breath only)
        option Remove High Harmonics (warm/mellow, keep 1-3)
    comment === What to Remove ===
    optionmenu Removal_mode: 1
        option Fundamental only
        option Selected overtone numbers
        option All overtones (keep fundamental)
        option Fundamental + all overtones
    sentence Overtone_numbers 2,4,6
    comment (used when mode = "Selected overtone numbers")
    comment === Pitch Detection ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    comment === Harmonics ===
    natural Number_of_harmonics 8
    comment === Spectral Removal ===
    positive Analysis_window_ms 60
    positive Notch_bandwidth_Hz 60
    comment (half-width of bandpass around each harmonic)
    comment === Threshold ===
    real Min_amplitude_dB -50
    comment (skip frames below this RMS level)
    comment === Output ===
    real Wet_dry_percent 100
    positive Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

presetName$ = "Custom"

if preset = 2
    # Remove Fundamental (de-buzz)
    removal_mode = 1
    number_of_harmonics = 8
    notch_bandwidth_Hz = 50
    analysis_window_ms = 60
    presetName$ = "RemoveFundamental"
elsif preset = 3
    # Remove Odd Harmonics
    removal_mode = 2
    overtone_numbers$ = "3,5,7,9,11"
    number_of_harmonics = 12
    notch_bandwidth_Hz = 50
    analysis_window_ms = 60
    presetName$ = "RemoveOddHarmonics"
elsif preset = 4
    # Remove Even Harmonics
    removal_mode = 2
    overtone_numbers$ = "2,4,6,8,10"
    number_of_harmonics = 10
    notch_bandwidth_Hz = 50
    analysis_window_ms = 60
    presetName$ = "RemoveEvenHarmonics"
elsif preset = 5
    # Remove All Overtones (keep F0 only — sine-like output)
    removal_mode = 3
    number_of_harmonics = 12
    notch_bandwidth_Hz = 60
    analysis_window_ms = 80
    presetName$ = "KeepF0Only"
elsif preset = 6
    # Remove F0 + All Overtones (noise/breath residual)
    removal_mode = 4
    number_of_harmonics = 12
    notch_bandwidth_Hz = 60
    analysis_window_ms = 80
    presetName$ = "NoiseResidual"
elsif preset = 7
    # Remove High Harmonics (warm — keep harmonics 1-3)
    removal_mode = 2
    overtone_numbers$ = "4,5,6,7,8,9,10,11,12"
    number_of_harmonics = 12
    notch_bandwidth_Hz = 40
    analysis_window_ms = 60
    presetName$ = "WarmMellow"
endif

# ============================================================
# CLAMPS AND SETUP
# ============================================================

if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

if analysis_window_ms < 20
    analysis_window_ms = 20
endif
if analysis_window_ms > 200
    analysis_window_ms = 200
endif
if notch_bandwidth_Hz < 5
    notch_bandwidth_Hz = 5
endif
if notch_bandwidth_Hz > 200
    notch_bandwidth_Hz = 200
endif
if number_of_harmonics < 1
    number_of_harmonics = 1
endif
if number_of_harmonics > 20
    number_of_harmonics = 20
endif

winLen = analysis_window_ms / 1000
hop = winLen / 4

# ============================================================
# PARSE OVERTONE NUMBERS (for "selected overtone" mode)
# ============================================================

# Parse comma-separated overtone numbers into an array
maxOvertones = 20
for ot from 1 to maxOvertones
    removeOvertone[ot] = 0
endfor
nSelectedOvertones = 0

if removal_mode = 2
    parseStr$ = overtone_numbers$ + ","
    numBuf$ = ""
    strLen = length(parseStr$)

    for ci from 1 to strLen
        ch$ = mid$(parseStr$, ci, 1)
        if ch$ = "," or ch$ = ";" or ch$ = " "
            if length(numBuf$) > 0 and nSelectedOvertones < maxOvertones
                nSelectedOvertones = nSelectedOvertones + 1
                removeOvertone[nSelectedOvertones] = number(numBuf$)
                numBuf$ = ""
            endif
        elsif ch$ >= "0" and ch$ <= "9"
            numBuf$ = numBuf$ + ch$
        endif
    endfor
endif

# ============================================================
# REMOVAL MODE NAMES
# ============================================================

if removal_mode = 1
    modeName$ = "Fundamental only"
elsif removal_mode = 2
    modeName$ = "Selected overtones [" + overtone_numbers$ + "]"
elsif removal_mode = 3
    modeName$ = "All overtones (keep F0)"
else
    modeName$ = "F0 + all overtones"
endif

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine: "=== Harmonic Remover v1.0 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
appendInfoLine: "Harmonics: ", number_of_harmonics
appendInfoLine: "Pitch range: ", pitch_floor, " - ", pitch_ceiling, " Hz"
appendInfoLine: "Window: ", fixed$(analysis_window_ms, 0), " ms"
    ... + "  Hop: ", fixed$(hop * 1000, 1), " ms  (75% overlap)"
appendInfoLine: "Notch BW: ±", fixed$(notch_bandwidth_Hz, 0), " Hz"
    ... + "  (bandpass isolation + subtraction)"
appendInfoLine: "Min amp: ", fixed$(min_amplitude_dB, 0), " dB"
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# ============================================================
# PITCH DETECTION
# ============================================================

appendInfoLine: "[1/4] Detecting pitch..."

selectObject: sound
if numChannels > 1
    monoWork = Convert to mono
else
    monoWork = Copy: "mono_work"
endif

selectObject: monoWork
pitchObj = To Pitch: 0.01, pitch_floor, pitch_ceiling

# Count voiced frames
selectObject: pitchObj
nPitchFrames = Get number of frames
nVoiced = Count voiced frames
appendInfoLine: "  Voiced frames: ", nVoiced, " / ", nPitchFrames

if nVoiced = 0
    removeObject: pitchObj, monoWork
    exitScript: "No pitched content detected." + newline$
        ... + "Try adjusting pitch floor/ceiling, or check input."
endif

# Get median F0 for info
selectObject: pitchObj
medianF0 = Get quantile: 0, 0, 0.5, "Hertz"
appendInfoLine: "  Median F0: ", fixed$(medianF0, 1), " Hz"
appendInfoLine: ""

# ============================================================
# FRAME-BY-FRAME PROCESSING
# ============================================================
#
# Architecture:
#   - Hann window with 75% overlap (hop = win/4)
#   - COLA property: sum of Hann windows = 2.0 at every point
#   - After OLA, divide by 2.0 for unity gain
#   - Unvoiced frames contribute unmodified (preserves noise)
#   - Per-frame Gaussian notch at tracked harmonic frequencies

appendInfoLine: "[2/4] Processing frames..."

# Calculate frame count
nFrames = floor((duration - winLen) / hop) + 1
if nFrames < 1
    nFrames = 1
endif
appendInfoLine: "  Frames: ", nFrames, "  (window=", fixed$(winLen * 1000, 0), "ms, hop=", fixed$(hop * 1000, 1), "ms)"

# Create output buffer (mono, same duration, silence)
Create Sound from formula: "output", 1, 0, duration, sampleRate, "0"
outputBuf = selected("Sound")

# Amplitude threshold in linear
minAmpLinear = 10 ^ (min_amplitude_dB / 20)

# Track statistics
nProcessed = 0
nSkippedUnvoiced = 0
nSkippedQuiet = 0

startTime = stopwatch

for iframe from 1 to nFrames
    # Frame time boundaries
    frameStart = (iframe - 1) * hop
    frameEnd = frameStart + winLen
    if frameEnd > duration
        frameEnd = duration
    endif
    frameMid = (frameStart + frameEnd) / 2

    # ---- Extract frame with Hann window ----
    selectObject: monoWork
    Extract part: frameStart, frameEnd, "Hanning", 1, "no"
    frameSound = selected("Sound")

    # ---- Check amplitude threshold ----
    selectObject: frameSound
    frameRMS = Get root-mean-square: 0, 0
    if frameRMS < minAmpLinear
        # Below threshold — add frame unmodified and skip
        nSkippedQuiet = nSkippedQuiet + 1

        selectObject: frameSound
        Shift times to: "start time", 0

        selectObject: outputBuf
        s1 = Get sample number from time: frameStart
        if s1 < 1
            s1 = 1
        endif
        sOff = s1 - 1
        Formula (part): frameStart, frameEnd, 1, 1,
            ... "self + object[" + string$(frameSound) + ", col - " + string$(sOff) + "]"

        removeObject: frameSound

    else
        # ---- Get F0 for this frame ----
        selectObject: pitchObj
        f0 = Get value at time: frameMid, "Hertz", "Linear"

        if f0 = undefined
            # Unvoiced — add frame unmodified
            nSkippedUnvoiced = nSkippedUnvoiced + 1

            selectObject: frameSound
            Shift times to: "start time", 0

            selectObject: outputBuf
            s1 = Get sample number from time: frameStart
            if s1 < 1
                s1 = 1
            endif
            sOff = s1 - 1
            Formula (part): frameStart, frameEnd, 1, 1,
                ... "self + object[" + string$(frameSound) + ", col - " + string$(sOff) + "]"

            removeObject: frameSound

        else
            # ---- Voiced frame: isolate & subtract harmonics ----
            #
            # Instead of a narrow spectral notch (which misses vibrato),
            # isolate each harmonic with Praat's Filter (pass Hann band),
            # then subtract the isolated content from the frame.
            # The bandpass captures the full width of each harmonic
            # including vibrato and spectral spread.
            nProcessed = nProcessed + 1

            # Start with the original windowed frame
            selectObject: frameSound
            Copy: "frame_result"
            frameResult = selected("Sound")

            # Build list of harmonics to remove and subtract each
            if removal_mode = 1
                # Fundamental only
                lowB = max(20, f0 - notch_bandwidth_Hz)
                highB = min(sampleRate / 2 - 50, f0 + notch_bandwidth_Hz)
                selectObject: frameSound
                isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                selectObject: frameResult
                Formula: "self - object[" + string$(isolated) + "]"
                removeObject: isolated

            elsif removal_mode = 2
                # Selected overtones
                for ot from 1 to nSelectedOvertones
                    harmN = removeOvertone[ot]
                    if harmN >= 1 and harmN <= number_of_harmonics
                        fh = harmN * f0
                        if fh < sampleRate / 2 - 100
                            lowB = max(20, fh - notch_bandwidth_Hz)
                            highB = min(sampleRate / 2 - 50, fh + notch_bandwidth_Hz)
                            selectObject: frameSound
                            isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                            selectObject: frameResult
                            Formula: "self - object[" + string$(isolated) + "]"
                            removeObject: isolated
                        endif
                    endif
                endfor

            elsif removal_mode = 3
                # All overtones (keep F0) — ISOLATE F0 directly
                # Instead of subtracting N overtones (cumulative error),
                # extract F0 with a single bandpass.  One filter, zero
                # accumulation error, and the rolloff tails don't matter
                # because we're keeping what passes, not subtracting.
                lowB = max(20, f0 - notch_bandwidth_Hz)
                highB = min(sampleRate / 2 - 50, f0 + notch_bandwidth_Hz)
                selectObject: frameSound
                isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                # Replace frameResult with the isolated F0
                removeObject: frameResult
                frameResult = isolated

            elsif removal_mode = 4
                # F0 + all overtones
                for hn from 1 to number_of_harmonics
                    fh = hn * f0
                    if fh < sampleRate / 2 - 100
                        lowB = max(20, fh - notch_bandwidth_Hz)
                        highB = min(sampleRate / 2 - 50, fh + notch_bandwidth_Hz)
                        selectObject: frameSound
                        isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                        selectObject: frameResult
                        Formula: "self - object[" + string$(isolated) + "]"
                        removeObject: isolated
                    endif
                endfor
            endif

            # OLA into output buffer
            selectObject: frameResult
            Shift times to: "start time", 0

            selectObject: outputBuf
            s1 = Get sample number from time: frameStart
            if s1 < 1
                s1 = 1
            endif
            sOff = s1 - 1
            Formula (part): frameStart, frameEnd, 1, 1,
                ... "self + object[" + string$(frameResult) + ", col - " + string$(sOff) + "]"

            removeObject: frameSound, frameResult
        endif
    endif

    # Progress indicator
    if iframe mod 50 = 0 or iframe = nFrames
        appendInfoLine: "  Frame ", iframe, " / ", nFrames,
            ... "  (processed=", nProcessed,
            ... "  unvoiced=", nSkippedUnvoiced,
            ... "  quiet=", nSkippedQuiet, ")"
    endif
endfor

# ============================================================
# NORMALIZE OLA
# ============================================================
#
# Hann window at 75% overlap (hop = win/4):
# The sum of overlapping windows = 2.0 at every point
# (verified analytically). Divide output by 2.0.

selectObject: outputBuf
Formula: "self / 2"

appendInfoLine: ""
appendInfoLine: "  Total: ", nProcessed, " voiced frames processed"

# ============================================================
# WET/DRY MIX
# ============================================================

if dry_level > 0
    appendInfoLine: "  Mixing wet/dry..."
    monoStr$ = string$(monoWork)
    selectObject: outputBuf
    Formula: "self * " + string$(wet_level)
        ... + " + object[" + monoStr$ + ", col] * " + string$(dry_level)
endif

# ============================================================
# FINALIZE
# ============================================================

selectObject: outputBuf
Scale peak: scale_peak
Rename: soundName$ + "_harmonicRemoved_" + presetName$
resultID = selected("Sound")

processingTime = stopwatch

removeObject: monoWork, pitchObj

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 1), " s"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "[3/4] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Harmonic Remover##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... soundName$ + "  |  " + presetName$
        ... + "  |  " + modeName$

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizIn = selected("Sound")
    else
        Copy: "vizIn"
        vizIn = selected("Sound")
    endif
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.36, 2.16
    Select inner viewport: 0.55, 7.65, 1.41, 2.11
    selectObject: resultID
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # Input spectrogram
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.24, 3.64
    Select inner viewport: 0.55, 3.85, 2.34, 3.54
    selectObject: sound
    if numChannels > 1
        Extract one channel: 1
        vizSpecIn = selected("Sound")
    else
        Copy: "vizSpecIn"
        vizSpecIn = selected("Sound")
    endif
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig, vizSpecIn
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original spectrogram"

    # ----------------------------------------------------------
    # Output spectrogram (shows removed harmonics)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.24, 3.64
    Select inner viewport: 4.40, 7.65, 2.34, 3.54
    selectObject: resultID
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specRes = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specRes
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "After harmonic removal"

    # ----------------------------------------------------------
    # Notch shape diagram (at median F0)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.72, 4.92
    Select inner viewport: 0.55, 7.65, 3.80, 4.84

    vizMaxFreq = min(medianF0 * (number_of_harmonics + 1), sampleRate / 2)
    Axes: 0, vizMaxFreq, -0.05, 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, vizMaxFreq, -0.05, 1.15

    # Unity gain line
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 1, vizMaxFreq, 1

    # For mode 3: show F0 isolation band (green)
    if removal_mode = 3
        lowBViz = max(0, medianF0 - notch_bandwidth_Hz)
        highBViz = min(vizMaxFreq, medianF0 + notch_bandwidth_Hz)
        Paint rectangle: "{0.85, 1.00, 0.85}", lowBViz, highBViz, -0.05, 1.15
    endif

    # Draw removal bands as shaded rectangles + harmonic markers
    # Mark harmonic positions
    for hn from 1 to number_of_harmonics
        fh = hn * medianF0
        if fh < vizMaxFreq
            # Check if this harmonic is being removed
            isRemoved = 0
            if removal_mode = 1 and hn = 1
                isRemoved = 1
            elsif removal_mode = 2
                for ot from 1 to nSelectedOvertones
                    if removeOvertone[ot] = hn
                        isRemoved = 1
                    endif
                endfor
            elsif removal_mode = 3 and hn >= 2
                isRemoved = 1
            elsif removal_mode = 4
                isRemoved = 1
            endif

            if isRemoved
                # Red shaded removal band
                lowB = max(0, fh - notch_bandwidth_Hz)
                highB = min(vizMaxFreq, fh + notch_bandwidth_Hz)
                Paint rectangle: "{1.00, 0.85, 0.85}", lowB, highB, -0.05, 1.15
                # Vertical centre line
                Colour: "{0.80, 0.25, 0.25}"
                Draw line: fh, 0, fh, 1.0
                Font size: 5
                Text: fh, "centre", 1.08, "half", "×" + string$(hn)
            else
                # Green kept marker
                Paint circle (mm): "{0.25, 0.65, 0.30}", fh, 1.0, 1.0
                Font size: 5
                Colour: "{0.25, 0.55, 0.25}"
                Text: fh, "centre", 1.08, "half", string$(hn)
            endif
        endif
    endfor

    # Redraw unity line on top
    Colour: "{0.60, 0.60, 0.60}"
    Draw line: 0, 1, vizMaxFreq, 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"
    if removal_mode = 3
        Text top: "no",
            ... "F0 isolation band at " + fixed$(medianF0, 1) + " Hz"
            ... + "  (±" + fixed$(notch_bandwidth_Hz, 0) + " Hz)"
    else
        Text top: "no",
            ... "Removal bands at median F0 (" + fixed$(medianF0, 1) + " Hz)"
            ... + "  ×=removed  green=kept"
    endif

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.02, 5.72
    Select inner viewport: 0.55, 7.65, 5.08, 5.66
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.48, "half",
        ... "Mode: " + modeName$
        ... + "  |  Harmonics: " + string$(number_of_harmonics)
        ... + "  |  Notch BW: " + fixed$(notch_bandwidth_Hz, 0) + " Hz"
        ... + "  |  Window: " + fixed$(analysis_window_ms, 0) + " ms"
    Text: 0.02, "left", 0.18, "half",
        ... "Median F0: " + fixed$(medianF0, 1) + " Hz"
        ... + "  |  Voiced: " + string$(nProcessed) + " frames"
        ... + "  |  Wet/Dry: " + fixed$(wet_dry_percent, 0) + "%"
        ... + "  |  Time: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
else
    appendInfoLine: "[3/4] Visualization skipped."
endif

# ============================================================
# FINAL
# ============================================================

selectObject: resultID

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID
