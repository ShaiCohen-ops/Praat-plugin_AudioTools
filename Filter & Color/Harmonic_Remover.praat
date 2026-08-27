# ============================================================
# Praat AudioTools - Harmonic_Remover.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.3 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Description:
#   Harmonic Remover — selectively removes the fundamental
#   frequency and/or chosen harmonic components from a sound.
#
#   Pipeline:
#     1. Pitch detection (To Pitch) gives F0 per frame.
#     2. Short overlapping Hanning-windowed frames (75% overlap).
#     3. Harmonics are isolated with Praat's Hann-band filter and
#        subtracted sequentially from the current frame result.
#        Sequential subtraction makes overlapping removal bands
#        combine multiplicatively instead of being over-subtracted.
#     4. The working signal is zero-padded by one full analysis window
#        on both sides before framing. This keeps every original sample
#        inside the steady-overlap region and prevents filtered frame-edge
#        leakage from being divided by near-zero Hann weights.
#     5. Overlap-add is normalized by the actual accumulated window
#        weight, then the padding is cropped away.
#     6. Quiet and unvoiced frames contribute their unprocessed
#        windowed signal.
#
#   Notes:
#     - Processing/output is mono. Multichannel input is mixed to mono.
#     - "Isolate F0 band" keeps only the tracked F0 band in voiced
#       frames; it also rejects non-harmonic energy outside that band.
#     - "Remove harmonics 1..N" removes only the first N harmonics,
#       not every possible harmonic up to Nyquist.
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
originalXmin = Get start time

if duration < 0.1
    exitScript: "Sound must be at least 100 ms."
endif

# ============================================================
# FORM
# ============================================================

form Harmonic Remover v1.3.1
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Remove Fundamental (de-buzz)
        option Remove Odd Harmonics (3,5,7...)
        option Remove Even Harmonics (2,4,6...)
        option Isolate Fundamental (F0 band only)
        option Remove Harmonics 1..N (residual/noise emphasis)
        option Remove High Harmonics (warm/mellow, keep 1-3)
    comment === What to Remove ===
    optionmenu Removal_mode: 1
        option Fundamental only
        option Selected harmonic numbers
        option Isolate F0 band
        option Harmonics 1..N
    sentence Harmonic_numbers 2,4,6
    comment (harmonic numbers: 1=F0, 2=second harmonic, etc.)
    comment === Pitch Detection ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    comment === Harmonics ===
    natural Number_of_harmonics 8
    comment (N used by the 1..N removal mode; maximum 20)
    comment === Spectral Removal ===
    positive Analysis_window_ms 60
    positive Notch_bandwidth_Hz 60
    comment (nominal half-width around each tracked harmonic; Hann transitions extend beyond it)
    comment === Threshold ===
    real Min_amplitude_dB -50
    comment (measured before windowing; dB relative to amplitude 1.0)
    comment === Output ===
    real Wet_dry_percent 100
    positive Normalize_peak_to 0.95
    comment (final peak normalization target; skipped at 0% wet for exact dry bypass)
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
    harmonic_numbers$ = "3,5,7,9,11"
    number_of_harmonics = 12
    notch_bandwidth_Hz = 50
    analysis_window_ms = 60
    presetName$ = "RemoveOddHarmonics"
elsif preset = 4
    # Remove Even Harmonics
    removal_mode = 2
    harmonic_numbers$ = "2,4,6,8,10"
    number_of_harmonics = 10
    notch_bandwidth_Hz = 50
    analysis_window_ms = 60
    presetName$ = "RemoveEvenHarmonics"
elsif preset = 5
    # Isolate F0 band only (sine-like voiced-frame output)
    removal_mode = 3
    number_of_harmonics = 12
    notch_bandwidth_Hz = 60
    analysis_window_ms = 80
    presetName$ = "KeepF0Only"
elsif preset = 6
    # Remove harmonics 1..N (residual/noise emphasis)
    removal_mode = 4
    number_of_harmonics = 12
    notch_bandwidth_Hz = 60
    analysis_window_ms = 80
    presetName$ = "NoiseResidual"
elsif preset = 7
    # Remove High Harmonics (warm — keep harmonics 1-3)
    removal_mode = 2
    harmonic_numbers$ = "4,5,6,7,8,9,10,11,12"
    number_of_harmonics = 12
    notch_bandwidth_Hz = 40
    analysis_window_ms = 60
    presetName$ = "WarmMellow"
endif

# ============================================================
# CLAMPS AND SETUP
# ============================================================

if pitch_floor >= pitch_ceiling
    exitScript: "Pitch floor must be lower than pitch ceiling."
endif
if pitch_ceiling >= sampleRate / 2
    exitScript: "Pitch ceiling must be below Nyquist (" + fixed$(sampleRate / 2, 1) + " Hz)."
endif

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
# PARSE HARMONIC NUMBERS (for selected-harmonic mode)
# ============================================================

# Parse comma-separated harmonic numbers into an array
maxHarmonics = 20
for ot from 1 to maxHarmonics
    removeHarmonic[ot] = 0
endfor
nSelectedHarmonics = 0

if removal_mode = 2
    parseStr$ = harmonic_numbers$ + ","
    numBuf$ = ""
    strLen = length(parseStr$)

    for ci from 1 to strLen
        ch$ = mid$(parseStr$, ci, 1)
        if ch$ = "," or ch$ = ";" or ch$ = " "
            if length(numBuf$) > 0
                candidateHarmonic = number(numBuf$)
                if candidateHarmonic < 1 or candidateHarmonic > maxHarmonics
                    exitScript: "Selected harmonic numbers must be integers from 1 to " + string$(maxHarmonics) + "."
                endif
                alreadyListed = 0
                for prev from 1 to nSelectedHarmonics
                    if removeHarmonic[prev] = candidateHarmonic
                        alreadyListed = 1
                    endif
                endfor
                if alreadyListed = 0 and nSelectedHarmonics < maxHarmonics
                    nSelectedHarmonics = nSelectedHarmonics + 1
                    removeHarmonic[nSelectedHarmonics] = candidateHarmonic
                endif
                numBuf$ = ""
            endif
        elsif ch$ >= "0" and ch$ <= "9"
            numBuf$ = numBuf$ + ch$
        else
            exitScript: "Harmonic_numbers accepts only integers separated by commas, semicolons, or spaces."
        endif
    endfor
    if nSelectedHarmonics = 0
        exitScript: "Please provide at least one harmonic number to remove."
    endif
endif

# Harmonic count used only for visualization extent. In selected mode,
# include any explicitly selected harmonic even if it is above N.
vizHarmonics = number_of_harmonics
if removal_mode = 2
    for ot from 1 to nSelectedHarmonics
        if removeHarmonic[ot] > vizHarmonics
            vizHarmonics = removeHarmonic[ot]
        endif
    endfor
endif

# ============================================================
# REMOVAL MODE NAMES
# ============================================================

if removal_mode = 1
    modeName$ = "Fundamental only"
elsif removal_mode = 2
    modeName$ = "Selected harmonics [" + harmonic_numbers$ + "]"
elsif removal_mode = 3
    modeName$ = "Isolate F0 band"
else
    modeName$ = "Harmonics 1..N"
endif

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine: "=== Harmonic Remover v1.3.1 ==="
appendInfoLine: "Source: ", soundName$, " (", fixed$(duration, 2), " s, ",
    ... sampleRate, " Hz, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", modeName$
if removal_mode = 2
    appendInfoLine: "Selected harmonics: ", harmonic_numbers$
elsif removal_mode = 3
    appendInfoLine: "Harmonic limit: n/a (F0-band isolation)"
else
    appendInfoLine: "Harmonic limit N: ", number_of_harmonics
endif
appendInfoLine: "Pitch range: ", pitch_floor, " - ", pitch_ceiling, " Hz"
appendInfoLine: "Window: ", fixed$(analysis_window_ms, 0), " ms"
    ... + "  Hop: ", fixed$(hop * 1000, 1), " ms  (75% overlap)"
appendInfoLine: "Removal band: approx ±", fixed$(notch_bandwidth_Hz, 0), " Hz"
    ... + "  (Hann-band isolation + sequential subtraction)"
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
Shift times to: "start time", 0

# Pad by one full analysis window on both sides. Praat's Hann-band
# filtering can produce non-zero values at the edges of a windowed frame.
# Without padding, dividing the first/last OLA samples by tiny Hann weights
# can create huge edge spikes, which then make final peak normalization
# collapse the useful signal almost to zero.
pad = winLen
padSamples = round(pad * sampleRate)
paddedDuration = duration + 2 * pad
Create Sound from formula: "padded_work", 1, 0, paddedDuration, sampleRate, "0"
paddedWork = selected("Sound")
selectObject: paddedWork
Formula (part): pad, pad + duration, 1, 1,
    ... "object[" + string$(monoWork) + ", col - " + string$(padSamples) + "]"

# Run pitch tracking on the padded signal so frame-centre queries use the
# same time axis as the processing frames. Padding itself remains unvoiced.
selectObject: paddedWork
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
#   - Hanning window with 75% overlap (hop = win/4)
#   - The signal is padded by one full window on both sides
#   - Actual window weights are accumulated in a normalization buffer
#   - The original region is cropped only after normalization/mixing
#   - Quiet/unvoiced frames contribute their unprocessed windowed signal
#   - Harmonic removals use sequential Hann-band subtraction

appendInfoLine: "[2/4] Processing frames..."

# Process only full frames on the padded signal. Because one complete
# window of padding exists on each side, the entire original signal lies
# safely inside the steady-overlap region.
nFrames = floor((paddedDuration - winLen) / hop) + 1
appendInfoLine: "  Frames: ", nFrames, "  (window=", fixed$(winLen * 1000, 0), "ms, hop=", fixed$(hop * 1000, 1), "ms)"
appendInfoLine: "  Boundary protection: ±", fixed$(pad * 1000, 0), " ms zero-padding"

# Create padded output and OLA-normalization buffers.
Create Sound from formula: "output", 1, 0, paddedDuration, sampleRate, "0"
outputBuf = selected("Sound")
Create Sound from formula: "ola_norm", 1, 0, paddedDuration, sampleRate, "0"
normBuf = selected("Sound")
Create Sound from formula: "ola_ones", 1, 0, paddedDuration, sampleRate, "1"
onesSource = selected("Sound")

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
    frameMid = (frameStart + frameEnd) / 2

    # ---- Check amplitude threshold BEFORE windowing ----
    selectObject: paddedWork
    frameRMS = Get root-mean-square: frameStart, frameEnd

    # ---- Extract frame with Hanning window ----
    selectObject: paddedWork
    Extract part: frameStart, frameEnd, "Hanning", 1, "no"
    frameSound = selected("Sound")

    # ---- Accumulate the exact analysis-window weight for OLA ----
    selectObject: onesSource
    Extract part: frameStart, frameEnd, "Hanning", 1, "no"
    frameWeight = selected("Sound")
    selectObject: frameWeight
    Shift times to: "start time", 0
    selectObject: normBuf
    s1norm = Get sample number from time: frameStart
    if s1norm < 1
        s1norm = 1
    endif
    sOffNorm = s1norm - 1
    Formula (part): frameStart, frameEnd, 1, 1,
        ... "self + object[" + string$(frameWeight) + ", col - " + string$(sOffNorm) + "]"
    removeObject: frameWeight

    # ---- Apply amplitude threshold ----
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
                if highB > lowB
                    selectObject: frameSound
                    isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                    selectObject: frameResult
                    Formula: "self - object[" + string$(isolated) + "]"
                    removeObject: isolated
                endif

            elsif removal_mode = 2
                # Selected harmonics
                for ot from 1 to nSelectedHarmonics
                    harmN = removeHarmonic[ot]
                    if harmN >= 1 and harmN <= maxHarmonics
                        fh = harmN * f0
                        if fh < sampleRate / 2 - 100
                            lowB = max(20, fh - notch_bandwidth_Hz)
                            highB = min(sampleRate / 2 - 50, fh + notch_bandwidth_Hz)
                            selectObject: frameResult
                            isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                            selectObject: frameResult
                            Formula: "self - object[" + string$(isolated) + "]"
                            removeObject: isolated
                        endif
                    endif
                endfor

            elsif removal_mode = 3
                # Isolate F0 band — this intentionally rejects all other voiced-frame spectrum
                # Instead of subtracting N harmonic bands (cumulative error),
                # extract F0 with a single bandpass.  One filter, zero
                # accumulation error, and the rolloff tails don't matter
                # because we're keeping what passes, not subtracting.
                lowB = max(20, f0 - notch_bandwidth_Hz)
                highB = min(sampleRate / 2 - 50, f0 + notch_bandwidth_Hz)
                if highB > lowB
                    selectObject: frameSound
                    isolated = Filter (pass Hann band): lowB, highB, notch_bandwidth_Hz / 2
                    # Replace frameResult with the isolated F0
                    removeObject: frameResult
                    frameResult = isolated
                endif

            elsif removal_mode = 4
                # Harmonics 1..N
                for hn from 1 to number_of_harmonics
                    fh = hn * f0
                    if fh < sampleRate / 2 - 100
                        lowB = max(20, fh - notch_bandwidth_Hz)
                        highB = min(sampleRate / 2 - 50, fh + notch_bandwidth_Hz)
                        selectObject: frameResult
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
# Normalize by the actual accumulated Hanning-window weight. The original
# signal is one full window away from the padded boundaries, so no retained
# sample is divided by a near-zero edge weight.

selectObject: outputBuf
Formula: "if object[" + string$(normBuf) + ", col] > 1e-12 then self / object[" + string$(normBuf) + ", col] else 0 fi"

appendInfoLine: ""
appendInfoLine: "  Total: ", nProcessed, " voiced frames processed"

# ============================================================
# WET/DRY MIX
# ============================================================

if dry_level > 0
    appendInfoLine: "  Mixing wet/dry..."
    paddedStr$ = string$(paddedWork)
    selectObject: outputBuf
    Formula: "self * " + string$(wet_level)
        ... + " + object[" + paddedStr$ + ", col] * " + string$(dry_level)
endif

# ============================================================
# CROP PADDING AND FINALIZE
# ============================================================

# Crop only after OLA normalization and wet/dry mixing. The retained region
# never includes the unstable outer edges of the padded processing buffer.
selectObject: outputBuf
Extract part: pad, pad + duration, "rectangular", 1, "no"
croppedOutput = selected("Sound")
removeObject: outputBuf
outputBuf = croppedOutput
selectObject: outputBuf
Shift times to: "start time", 0
# At 0% wet the output must remain the unprocessed dry path. Peak
# normalization is therefore skipped for an exact dry bypass.
if wet_level > 0
    Scale peak: normalize_peak_to
endif
Rename: soundName$ + "_harmonicRemoved_" + presetName$
resultID = selected("Sound")

processingTime = stopwatch

removeObject: pitchObj, normBuf, onesSource, paddedWork

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 1), " s"

# ============================================================
# VISUALIZATION
# ============================================================

pageHeight = 8.00
if draw_visualization
    appendInfoLine: "[3/4] Creating visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, pageHeight

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    suiteVizName$ = replace$(soundName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Harmonic Remover v1.3.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.52, 1.32
    Select inner viewport: 0.55, 7.65, 0.57, 1.27
    selectObject: monoWork
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input (mono processing signal)"

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
    selectObject: monoWork
    To Spectrogram: 0.02, 5000, 0.005, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: specOrig
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Input spectrogram (mono processing signal)"

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
    Text top: "no", "Processed output"

    # ----------------------------------------------------------
    # Removal-band diagram (at median F0)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.72, 4.92
    Select inner viewport: 0.55, 7.65, 3.80, 4.84

    vizMaxFreq = min(medianF0 * (vizHarmonics + 1), sampleRate / 2)
    Axes: 0, vizMaxFreq, -0.05, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizMaxFreq, -0.05, 1.15

    # Unity gain line
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 1, vizMaxFreq, 1

    # For mode 3: show the kept F0 isolation band (green)
    if removal_mode = 3
        lowBViz = max(0, medianF0 - notch_bandwidth_Hz)
        highBViz = min(vizMaxFreq, medianF0 + notch_bandwidth_Hz)
        Paint rectangle: "{0.85, 1.00, 0.85}", lowBViz, highBViz, -0.05, 1.15
    endif

    # In F0-isolation mode, everything outside the green band is rejected.
    if removal_mode = 3
        Paint rectangle: "{1.00, 0.90, 0.90}", 0, lowBViz, -0.05, 1.15
        Paint rectangle: "{1.00, 0.90, 0.90}", highBViz, vizMaxFreq, -0.05, 1.15
        Paint rectangle: "{0.85, 1.00, 0.85}", lowBViz, highBViz, -0.05, 1.15
    endif

    # Draw removal bands as shaded rectangles + harmonic markers
    # Mark harmonic positions
    for hn from 1 to vizHarmonics
        fh = hn * medianF0
        if fh < vizMaxFreq
            # Check if this harmonic is being removed
            isRemoved = 0
            if removal_mode = 1 and hn = 1
                isRemoved = 1
            elsif removal_mode = 2
                for ot from 1 to nSelectedHarmonics
                    if removeHarmonic[ot] = hn
                        isRemoved = 1
                    endif
                endfor
            elsif removal_mode = 3 and hn >= 2
                isRemoved = 1
            elsif removal_mode = 4
                isRemoved = 1
            endif

            if isRemoved
                # Red shaded removal band (except mode 3, where the whole
                # spectrum outside the F0 band is already shaded)
                lowB = max(0, fh - notch_bandwidth_Hz)
                highB = min(vizMaxFreq, fh + notch_bandwidth_Hz)
                if removal_mode <> 3
                    Paint rectangle: "{1.00, 0.85, 0.85}", lowB, highB, -0.05, 1.15
                endif
                # Vertical centre line
                Colour: "{0.80, 0.25, 0.25}"
                Draw line: fh, 0, fh, 1.0
                Font size: 6
                Text: fh, "centre", 1.08, "half", "×" + string$(hn)
            else
                # Green kept marker
                Paint circle (mm): "{0.25, 0.65, 0.30}", fh, 1.0, 1.0
                Font size: 6
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
        ... + "  |  Display harmonics: " + string$(vizHarmonics)
        ... + "  |  Removal BW: " + fixed$(notch_bandwidth_Hz, 0) + " Hz"
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

# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line

# ============================================================
# FINAL
# ============================================================

removeObject: monoWork
selectObject: resultID
# Processing uses a zero-based work copy; restore the source time domain
# only after visualization so input/output plots share the same local axis.
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: resultID