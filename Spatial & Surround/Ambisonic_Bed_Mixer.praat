# ============================================================
# Praat AudioTools - Ambisonic_Bed_Mixer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3.1 (2026) - grid validation, self-contained export,
# v0.3 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
#                        explicit gain mapping, no direct playback
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sums 2-8 B-format ambisonic Sound objects (same order / same
#   channel count / same sample rate / same time grid) into a
#   single combined bed, the way independently-encoded point
#   sources correctly combine in a linear ambisonic soundfield.
#
#   Supported orders: 1st (4ch) / 2nd (9ch) / 3rd (16ch) only.
#   This script does NOT support or imply 4th/5th order.
#
#   ASSUMPTION (cannot be verified from the samples themselves):
#   every input is Full-3D ACN/SN3D B-format. A 16-channel Sound
#   could equally be ACN/N3D, FuMa-derived, or an unrelated
#   16-channel recording - channel count alone does not confirm
#   the convention. Encode all stems with the same library
#   (Higher-Order Ambisonic Encoder) to keep this assumption safe.
#
#   Design rules (do not relax these without re-deriving the math):
#   - one gain value per STEM, applied uniformly across all of that
#     stem's ACN channels. Per-channel gains would distort the
#     direction a stem was encoded at.
#   - straight per-channel addition (ACN0+ACN0, ACN1+ACN1, ...),
#     never channel-stacking/interleaving ("Combine to stereo" is
#     the wrong tool for this - it grows channel count, it never
#     sums).
#   - peak protection happens exactly ONCE, on the final summed
#     bed, attenuate-only (never boosts), so the relative levels
#     between stems (their encoded directions/distances) survive.
#   - no post-mix SN3D self-test: that identity only holds for a
#     SINGLE point source. Validate each stem individually with
#     the Encoder's own self-test BEFORE mixing; trust linearity
#     for the sum.
#   - do not pass the finished bed back through the Encoder. The
#     Encoder is a source-to-B-format tool; the bed is already
#     B-format. Re-encoding it would treat it as new raw audio
#     and destroy the existing soundfield. This script exports
#     the bed directly instead.
#
# Encoding your stems for this script:
#   In the Higher-Order Ambisonic Encoder, make sure BOTH of these
#   are true for every stem (these are two separate switches -
#   turning one off does not turn the other off):
#     - Submission mode: OFF   (submission mode force-enables its
#       own peak protection, which is exactly what we don't want
#       per-stem)
#     - Peak protection: OFF
#   All stems also need identical start time (0), sample rate,
#   and duration/sample count - this script now checks all of
#   those and refuses to mix stems that don't match, rather than
#   guessing.
#
# Usage:
#   Select 2-8 B-format Sound objects (same order, same sample
#   rate, same start time, same sample count) and run this script.
#   The script prints a numbered list of what you selected BEFORE
#   opening the gain form, so gain numbers can be matched to names
#   with certainty.
# ============================================================

# === Input Validation (before form) ===
numSounds = numberOfSelected("Sound")
if numSounds < 2
    exitScript: "Select 2 to 8 B-format Sound objects (same order, same sample rate, same time grid)."
endif
if numSounds > 8
    exitScript: "Too many sounds selected! Maximum is 8."
endif

# Store sound IDs before form (form selection can disturb the Objects list)
for i from 1 to numSounds
    tempSoundID_'i' = selected("Sound", i)
endfor

# === Full grid check BEFORE the form: channels, sample rate, start time, sample count ===
refCh = 0
refSR = 0
refXmin = 0
refSamples = 0
mismatch$ = ""

writeInfoLine: "=== Ambisonic Bed Mixer v0.3 ==="
appendInfoLine: "Assumption: every selected input is Full-3D ACN/SN3D B-format."
appendInfoLine: "(Channel count alone cannot confirm this - verify at encode time.)"
appendInfoLine: ""
appendInfoLine: "Selected sounds (this order maps to Gain_1..Gain_" + string$(numSounds) + " in the form):"

for i from 1 to numSounds
    selectObject: tempSoundID_'i'
    thisCh = Get number of channels
    thisSR = Get sampling frequency
    thisXmin = Get start time
    thisSamples = Get number of samples
    thisName$ = selected$("Sound")
    thisID = tempSoundID_'i'

    appendInfoLine: "  Gain_", i, "  ->  ", thisName$, "  (id ", thisID, ", ",
        ... thisCh, " ch, ", thisSR, " Hz, ", thisSamples, " samples)"

    if i = 1
        refCh = thisCh
        refSR = thisSR
        refXmin = thisXmin
        refSamples = thisSamples
    else
        if thisCh <> refCh
            mismatch$ = mismatch$ + newline$ + "  " + thisName$
                ... + ": " + string$(thisCh) + " channels (expected " + string$(refCh) + ")"
        endif
        if thisSR <> refSR
            mismatch$ = mismatch$ + newline$ + "  " + thisName$
                ... + ": " + string$(thisSR) + " Hz (expected " + string$(refSR) + " Hz)"
        endif
        if thisXmin <> refXmin
            mismatch$ = mismatch$ + newline$ + "  " + thisName$
                ... + ": starts at " + string$(thisXmin) + " s (expected " + string$(refXmin) + " s)"
        endif
        if thisSamples <> refSamples
            mismatch$ = mismatch$ + newline$ + "  " + thisName$
                ... + ": " + string$(thisSamples) + " samples (expected " + string$(refSamples) + ")"
        endif
    endif
endfor

appendInfoLine: ""

if mismatch$ <> ""
    exitScript: "Stems do not share an identical time grid - fix these before mixing "
        ... + "(pad/trim externally so every stem has the same start time, sample "
        ... + "rate, and sample count; this script deliberately does not guess):" + mismatch$
endif

if refCh = 4
    orderName$ = "1st"
elsif refCh = 9
    orderName$ = "2nd"
elsif refCh = 16
    orderName$ = "3rd"
else
    exitScript: "Selected sounds have " + string$(refCh)
        ... + " channels - not a supported ambisonic channel count (this script supports 1st/2nd/3rd order: 4, 9, or 16 ch)."
endif

refDur = refSamples / refSR

# === FORM ===
form Ambisonic Bed Mixer
    comment === STEM GAINS (uniform across all ACN channels of that stem) ===
    comment See the Info window above for the Gain_N -> sound-name mapping.
    comment Negative values are valid (polarity flip, direction unchanged).
    real Gain_1 1.0
    real Gain_2 1.0
    real Gain_3 1.0
    real Gain_4 1.0
    real Gain_5 1.0
    real Gain_6 1.0
    real Gain_7 1.0
    real Gain_8 1.0
    comment === PEAK PROTECTION (single attenuate-only pass, applied once, after summing) ===
    boolean Peak_protect 1
    real Target_peak 0.95
    comment === EXPORT (writes the bed directly - never re-run through the Encoder) ===
    boolean Export_wav 0
    sentence Output_folder
    sentence File_name AmbisonicBed
    comment === OUTPUT ===
    boolean Draw_visualization 1
endform

if target_peak <= 0 or target_peak > 1
    exitScript: "Target_peak must be greater than 0 and less than or equal to 1 (got "
        ... + string$(target_peak) + "). A practical range is about 0.90-0.99."
endif

stopwatch

gain# = zero#(8)
gain#[1] = gain_1
gain#[2] = gain_2
gain#[3] = gain_3
gain#[4] = gain_4
gain#[5] = gain_5
gain#[6] = gain_6
gain#[7] = gain_7
gain#[8] = gain_8

appendInfoLine: "Order: ", orderName$, " (", refCh, " ch)  |  ", refSR, " Hz  |  ",
    ... fixed$(refDur, 3), " s  |  Stems: ", numSounds
appendInfoLine: ""

for i from 1 to numSounds
    soundID_'i' = tempSoundID_'i'
    selectObject: soundID_'i'
    soundName_'i'$ = selected$("Sound")
    appendInfoLine: i, ". ", soundName_'i'$, "  gain ", fixed$(gain#[i], 3)
endfor
appendInfoLine: ""

# === Create accumulation buffer (identical grid to every validated stem) ===
Create Sound from formula: "ambisonic_bed", refCh, refXmin, refXmin + refDur, refSR, "0"
resultID = selected("Sound")

# === Accumulate stems: per-stem gain -> straight per-channel add ===
appendInfoLine: "Summing stems:"
for i from 1 to numSounds
    thisID = soundID_'i'
    thisName$ = soundName_'i'$

    selectObject: thisID
    Copy: "layer_temp"
    tempID = selected("Sound")

    thisGain = gain#[i]
    if thisGain <> 1.0
        Formula: "self * " + string$(thisGain)
    endif

    tempIDstr$ = string$(tempID)
    selectObject: resultID
    Formula: "self + object[" + tempIDstr$ + ", row, col]"

    removeObject: tempID
    appendInfoLine: "  + ", thisName$
endfor

# === Single global peak-protect pass (attenuate-only) ===
selectObject: resultID
peakVal = 0
for c from 1 to refCh
    selectObject: resultID
    Extract one channel: c
    chID = selected("Sound")
    chPeak = Get absolute extremum: 0, 0, "None"
    if chPeak > peakVal
        peakVal = chPeak
    endif
    removeObject: chID
endfor

appendInfoLine: ""
appendInfoLine: "Combined bed peak (pre-protect): ", fixed$(peakVal, 4)

attenFactor = 1.0
if peak_protect and peakVal > target_peak
    attenFactor = target_peak / peakVal
    selectObject: resultID
    Formula: "self * " + string$(attenFactor)
    appendInfoLine: "Peak protection: attenuated by factor ",
        ... fixed$(attenFactor, 4), " (", fixed$(20 * log10(attenFactor), 2), " dB)"
elsif peak_protect
    appendInfoLine: "Peak protection: no attenuation needed (peak already <= target)"
else
    appendInfoLine: "Peak protection: OFF (bed left as summed, may clip on export)"
endif

resultName$ = "AmbisonicBed_" + orderName$ + "_" + string$(numSounds) + "stems"
selectObject: resultID
Rename: resultName$

# === Direct WAV export + reopen validation (NOT via the Encoder) ===
if export_wav
    if output_folder$ = ""
        outFolder$ = homeDirectory$ + "/"
    else
        outFolder$ = output_folder$ + "/"
    endif
    createFolder: outFolder$

    baseName$ = file_name$ + "_" + orderName$ + "_ambiX_ACN_SN3D"
    outPath$ = outFolder$ + baseName$ + ".wav"
    suffix = 1
    while fileReadable (outPath$)
        outPath$ = outFolder$ + baseName$ + "_" + string$(suffix) + ".wav"
        suffix = suffix + 1
    endwhile

    selectObject: resultID
    expectedSamples = Get number of samples
    expectedDur = Get total duration

    Save as WAV file: outPath$
    appendInfoLine: ""
    appendInfoLine: "Exported: ", outPath$

    Read from file: outPath$
    reopenedID = selected("Sound")
    checkCh = Get number of channels
    checkSR = Get sampling frequency
    checkSamples = Get number of samples
    checkDur = Get total duration
    removeObject: reopenedID

    validationOK = 1
    if checkCh <> refCh
        validationOK = 0
    endif
    if checkSR <> refSR
        validationOK = 0
    endif
    if checkSamples <> expectedSamples
        validationOK = 0
    endif

    if validationOK
        appendInfoLine: "Validation: PASS  (", checkCh, " ch, ", checkSR, " Hz, ",
            ... checkSamples, " samples, ", fixed$(checkDur, 3), " s)"
    else
        appendInfoLine: "Validation: FAIL  (expected ", refCh, " ch / ", refSR,
            ... " Hz / ", expectedSamples, " samples - got ", checkCh, " ch / ",
            ... checkSR, " Hz / ", checkSamples, " samples)"
        appendInfoLine: "Deleting non-conformant file and stopping."
        deleteFile: outPath$
        exitScript: "Export validation failed - see Info window. No file was left on disk."
    endif
endif

elapsed = stopwatch

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Ambisonic Bed Mixer v0.3.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... resultName$ + "  |  " + orderName$ + " order  |  " + string$(numSounds) + " stems"

    # Stem gain bars - dynamic axis, supports negative gains
    gMin = gain#[1]
    gMax = gain#[1]
    for i from 2 to numSounds
        if gain#[i] < gMin
            gMin = gain#[i]
        endif
        if gain#[i] > gMax
            gMax = gain#[i]
        endif
    endfor
    if gMin > 0
        gMin = 0
    endif
    if gMax < 0
        gMax = 0
    endif
    axPad = (gMax - gMin) * 0.2
    if axPad = 0
        axPad = 0.2
    endif
    axLo = gMin - axPad
    axHi = gMax + axPad

    Select outer viewport: 0.3, 7.7, 0.9, 3.3
    Select inner viewport: 0.60, 7.55, 1.00, 3.18
    Axes: axLo, axHi, 0, numSounds + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", axLo, axHi, 0, numSounds + 1
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0, 0, numSounds + 1
    Solid line
    for i from 1 to numSounds
        yPos = numSounds - i + 1
        g = gain#[i]
        if g >= 0
            col$ = "{0.30, 0.50, 0.80}"
        else
            col$ = "{0.80, 0.35, 0.35}"
        endif
        Paint rectangle: col$, 0, g, yPos - 0.35, yPos + 0.35
        Colour: "Black"
        Font size: 6
        Text: axLo + 0.02 * (axHi - axLo), "left", yPos, "half", soundName_'i'$
        Text: g, "centre", yPos, "half", fixed$(g, 2)
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Per-Stem Gains##"

    # Output waveform, channel 1 (W / ACN0)
    Select outer viewport: 0.3, 7.7, 3.55, 4.65
    Select inner viewport: 0.60, 7.55, 3.63, 4.43
    selectObject: resultID
    Extract one channel: 1
    vizW = selected("Sound")
    Colour: "{0.20, 0.40, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizW
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 3.55, 4.65
    Select inner viewport: 0.08, 0.52, 3.57, 4.63
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "ACN0 (W)"
    Select outer viewport: 0.3, 7.7, 3.55, 4.65
    Select inner viewport: 0.60, 7.55, 3.63, 4.43
    Text bottom: "yes", "Time (s)"

    # Summary panel
    Select outer viewport: 0.3, 7.7, 4.95, 5.75
    Select inner viewport: 0.60, 7.55, 5.01, 5.69
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.64, "half",
        ... string$(numSounds) + " stems  |  " + orderName$ + " order ("
        ... + string$(refCh) + " ch)  |  " + fixed$(refDur, 2) + " s  |  " + string$(refSR) + " Hz"
    Text: 0.02, "left", 0.28, "half",
        ... "Peak pre-protect: " + fixed$(peakVal, 3)
        ... + "  |  Attenuation: " + fixed$(attenFactor, 3)
        ... + "  |  Time: " + fixed$(elapsed, 1) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Select outer viewport: 0, 8, 0, 5.85
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Line width: 1
endif

# === Final log ===
selectObject: resultID
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Result: ", resultName$
appendInfoLine: "Order: ", orderName$, " (", refCh, " channels, ACN, assumed SN3D)"
appendInfoLine: "Duration: ", fixed$(refDur, 3), " s  |  ", refSR, " Hz"
appendInfoLine: "Time: ", fixed$(elapsed, 1), " s"
appendInfoLine: ""
appendInfoLine: "Do NOT audition this Sound directly with Play - it is B-format"
appendInfoLine: "(W/Y/Z/X...), not speaker feeds. Decode it first (Higher-Order"
appendInfoLine: "Ambisonic Decoder, Quad speaker preset) for a loudspeaker preview,"
appendInfoLine: "or run that decode through the Spat5 chain (HRTF) for binaural."
appendInfoLine: ""
appendInfoLine: "Do NOT pass this Sound back through the Ambisonic Encoder - it is"
appendInfoLine: "already B-format; the exported WAV above is your ambiX master."
