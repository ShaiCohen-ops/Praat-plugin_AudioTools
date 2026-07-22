# ============================================================
# Praat AudioTools - 8-Channel_Spectral_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Eight parallel whole-file FFT spectral translations of one source.
#   Each channel receives a constant additive frequency offset, applied
#   by translating the FFT bins and inverse-transforming. Output as
#   octophonic, stems, or a downmix.
#
#   This is spectral translation with truncation at DC and Nyquist:
#   components pushed above Nyquist or below 0 Hz are discarded, not
#   wrapped. One transform is taken over the whole file, so the shift
#   is constant for its whole length - there are no frames, no windows
#   and no time variation. Chunked STFT processing remains future work.
#
# Changelog v0.8 (2026):
#   - RENAME: the description said "8-voice frequency shift canons".
#     There are no staggered entries, no delays and no temporal
#     imitation between the voices - they are eight parallel variations
#     of the same material, starting together. Called what it is.
#   - FIX (default): shift amounts are now entered in Hertz. Bin width
#     is sampling rate divided by FFT length, and To Spectrum "fast"
#     pads to the next power of two, so at 44.1 kHz a bin is 0.673 Hz
#     for a 1 s file, 0.084 Hz for 10 s and 0.0105 Hz for 60 s. The
#     same "Shift 100" therefore meant 67 Hz on a short file and 1 Hz
#     on a long one, and the Gentle / Moderate / Extreme presets had no
#     stable meaning across sources. The script converts Hz to a bin
#     offset against the measured bin width and reports the requested
#     shift, the achieved shift and the quantisation error. Bins remain
#     available as an advanced unit for Custom.
#   - FIX: per-channel Scale peak erased exactly the differences the
#     shifts create. A channel that lost most of its energy past
#     Nyquist and a channel that kept nearly all of it were both lifted
#     to the same peak. That is peak equalisation, not normalisation.
#     One shared gain is now taken from the loudest of the eight and
#     applied to all of them, so the energy differences survive; the
#     two summing formats normalise once after the sums.
#   - FIX: DC and Nyquist carried illegal imaginary parts. In a valid
#     spectrum of a real signal Im(X[0]) = 0, and Im at the Nyquist bin
#     = 0. Shifting every column alike moves an interior complex bin
#     into those slots along with its imaginary part. Both are now
#     zeroed after the shift.
#   - FIX: no check that the shift fits. A bin offset at or beyond the
#     bin count zeroes the whole matrix and the channel comes out
#     silent with no explanation. The offset is now validated against
#     the bin count, which is only known after the transform, and large
#     truncations are reported rather than discovered by ear.
#   - FIX: "Octave-like (doubling pattern)" was neither. The offsets
#     double, but the operation is additive, so it is not a frequency
#     ratio: +100 Hz takes 100 Hz to 200 Hz (an octave, 1200 cents),
#     200 Hz to 300 Hz (702 cents) and 4000 Hz to 4100 Hz (43 cents).
#     A constant Hz offset cannot be an octave except at one frequency.
#     Renamed to doubling offsets, with the additive nature stated.
#   - FIX: four preset labels disagreed with their values - Gentle Up
#     said 50-200 and reached 225, Moderate Up said 200-500 and reached
#     550, Extreme Up said 500-1500 and reached 1550, All Down said
#     -100 to -400 and reached -450. All labels now match exactly, in
#     the new Hz units.
#   - FIX: the waveform panel was titled "Output 8-ch mix" but drew
#     channels 1 and 2 of the eight-channel object. Those are two of
#     the variations, not a mix. Renamed, and drawn from the working
#     channels so it is identical in every output format.
#   - FIX: the shift Formula interpolated 'sInt' with backticks;
#     string$() is the portable idiom.
#   - NEW: per-channel energy retention is measured and reported, and
#     replaces the decorative scatter panel. This is what explains why
#     an extreme shift sounds thin: the energy pushed past Nyquist or
#     below DC is gone, and with the shared gain that loss is now
#     audible instead of being normalised away.
#   - NEW: Output_format menu.
#       1  8 channels - octophonic     Ch1-Ch8
#       2  4 stereo pairs              Ch1|Ch2 Ch3|Ch4 Ch5|Ch6 Ch7|Ch8
#       3  2 quad groups               Ch1-Ch4, Ch5-Ch8
#       4  4-channel fold-down         Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8
#       5  Stereo mix                  L: Ch1-Ch4   R: Ch5-Ch8
#     Positional rather than odd/even here, because the channels are
#     usually arranged as two spectral banks: in Symmetrical it is up
#     against down, in Spread negative against positive, in All Up low
#     shifts against high.
#   - NEW: monitoring mix (L Ch1-4, R Ch5-8) for preview playback in
#     the stem formats.
#
# Changelog v0.7:
#   - Forced exact sample rate after the roundtrip; trimmed the padded
#     IFFT output back to the source duration.
# Changelog v0.6:
#   - Source spectrum and Matrix computed once, shared across 8 shifts.
# Changelog v0.5:
#   - Negative shifts read from the unmodified source Matrix.
# ============================================================

# === Check Input (before the form) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Spectral Shift
    comment === PRESETS (values in Hz) ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Gentle Up (20-120 Hz)"
        option: "Moderate Up (100-600 Hz)"
        option: "Extreme Up (500-2600 Hz)"
        option: "Symmetrical (+400..+100 / -100..-400 Hz)"
        option: "All Down (-50 to -400 Hz)"
        option: "Spread (-400 to +400 Hz)"
        option: "Cluster Up (100-170 Hz)"
        option: "Doubling offsets (additive, NOT octaves)"

    comment === Units for the values below (presets are always Hz) ===
    optionmenu Shift_units: 1
        option: "Hertz (stable across files)"
        option: "FFT bins (advanced; depends on file length)"

    comment === Shift amounts (positive = up, negative = down) ===
    real Shift_1 100
    real Shift_2 200
    real Shift_3 300
    real Shift_4 400
    real Shift_5 -100
    real Shift_6 -200
    real Shift_7 -300
    real Shift_8 -400

    comment === OUTPUT FORMAT ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 stereo pairs (Ch1|Ch2, Ch3|Ch4, Ch5|Ch6, Ch7|Ch8)"
        option: "2 quad groups (Ch1-Ch4, Ch5-Ch8)"
        option: "4-channel fold-down (Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8)"
        option: "Stereo mix (L: Ch1-Ch4, R: Ch5-Ch8)"

    comment === Output ===
    real Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
# v0.8: preset values are Hertz. A preset therefore forces Hz units;
# bins remain available for Custom only, where the user has chosen them
# deliberately.
presetForcedHz = 0
if preset = 2
    shift_1 = 20
    shift_2 = 30
    shift_3 = 40
    shift_4 = 50
    shift_5 = 65
    shift_6 = 80
    shift_7 = 100
    shift_8 = 120
    presetName$ = "GentleUp"
elsif preset = 3
    shift_1 = 100
    shift_2 = 150
    shift_3 = 200
    shift_4 = 250
    shift_5 = 300
    shift_6 = 400
    shift_7 = 500
    shift_8 = 600
    presetName$ = "ModerateUp"
elsif preset = 4
    shift_1 = 500
    shift_2 = 700
    shift_3 = 900
    shift_4 = 1200
    shift_5 = 1500
    shift_6 = 1800
    shift_7 = 2200
    shift_8 = 2600
    presetName$ = "ExtremeUp"
elsif preset = 5
    shift_1 = 400
    shift_2 = 300
    shift_3 = 200
    shift_4 = 100
    shift_5 = -100
    shift_6 = -200
    shift_7 = -300
    shift_8 = -400
    presetName$ = "Symmetrical"
elsif preset = 6
    shift_1 = -50
    shift_2 = -100
    shift_3 = -150
    shift_4 = -200
    shift_5 = -250
    shift_6 = -300
    shift_7 = -350
    shift_8 = -400
    presetName$ = "AllDown"
elsif preset = 7
    shift_1 = -400
    shift_2 = -250
    shift_3 = -100
    shift_4 = 0
    shift_5 = 0
    shift_6 = 100
    shift_7 = 250
    shift_8 = 400
    presetName$ = "Spread"
elsif preset = 8
    shift_1 = 100
    shift_2 = 110
    shift_3 = 120
    shift_4 = 130
    shift_5 = 140
    shift_6 = 150
    shift_7 = 160
    shift_8 = 170
    presetName$ = "ClusterUp"
elsif preset = 9
    shift_1 = 50
    shift_2 = 100
    shift_3 = 200
    shift_4 = 400
    shift_5 = -50
    shift_6 = -100
    shift_7 = -200
    shift_8 = -400
    presetName$ = "DoublingOffsets"
else
    presetName$ = "Custom"
endif

if preset > 1 and shift_units = 2
    shift_units = 1
    presetForcedHz = 1
endif

if shift_units = 1
    unitName$ = "Hz"
else
    unitName$ = "bins"
endif

if scale_peak <= 0
    scale_peak = 0.99
endif
if scale_peak > 1
    scale_peak = 1
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency
nch = Get number of channels

requested[1] = shift_1
requested[2] = shift_2
requested[3] = shift_3
requested[4] = shift_4
requested[5] = shift_5
requested[6] = shift_6
requested[7] = shift_7
requested[8] = shift_8

# === Mono base ===
selectObject: originalID
if nch > 1
    Convert to mono
else
    Copy: "mono_work"
endif
monoID = selected("Sound")
selectObject: monoID
srcEnergy = Get energy: 0, 0
if srcEnergy <= 0
    srcEnergy = 1e-30
endif

# ============================================================
# Shared forward FFT (once, not eight times)
# ============================================================
stopwatch
selectObject: monoID
To Spectrum: "yes"
sourceSpecID = selected("Spectrum")
binHz = Get bin width
nBins = Get number of bins
nyquist = Get highest frequency

To Matrix
sourceMatID = selected("Matrix")
Rename: "shiftsrc"
fftElapsed = stopwatch

# ============================================================
# Requested shift -> bin offset
# ============================================================
# The bin offset is the only thing the transform can actually apply, so
# the achieved shift is a whole number of bins and the report shows how
# far that lands from what was asked for.
anyClamped = 0
for ch from 1 to 8
    if shift_units = 1
        binOffset[ch] = round(requested[ch] / binHz)
    else
        binOffset[ch] = round(requested[ch])
    endif

    # v0.8: an offset at or beyond the bin count empties the matrix and
    # the channel comes out silent with nothing said.
    if binOffset[ch] > nBins - 1
        binOffset[ch] = nBins - 1
        anyClamped = anyClamped + 1
    endif
    if binOffset[ch] < -(nBins - 1)
        binOffset[ch] = -(nBins - 1)
        anyClamped = anyClamped + 1
    endif

    actualHz[ch] = binOffset[ch] * binHz
    if shift_units = 1
        quantErr[ch] = actualHz[ch] - requested[ch]
    else
        quantErr[ch] = 0
    endif
endfor

# ============================================================
# PER-CHANNEL SHIFT
# ============================================================
stopwatch
for ch from 1 to 8
    selectObject: sourceMatID
    Copy: "shiftdst"
    matDstID = selected("Matrix")

    s = binOffset[ch]
    sInt = abs(s)
    sIntStr$ = string$(sInt)

    # Read from the untouched source matrix, write to the destination,
    # so an in-place overlap cannot corrupt the read.
    selectObject: matDstID
    if s >= 0
        Formula: "if col - " + sIntStr$ + " >= 1 then Matrix_shiftsrc[row, col - "
            ... + sIntStr$ + "] else 0 fi"
    else
        Formula: "if col + " + sIntStr$ + " <= ncol then Matrix_shiftsrc[row, col + "
            ... + sIntStr$ + "] else 0 fi"
    endif

    # v0.8: a valid spectrum of a real signal has a zero imaginary part
    # at DC and at Nyquist. Translating every column alike can move an
    # interior complex bin into either slot with its imaginary part
    # intact, which is not a legal representation of a real signal.
    # Row 2 of the Matrix is the imaginary part.
    selectObject: matDstID
    Set value: 2, 1, 0
    Set value: 2, nBins, 0

    To Spectrum
    shiftedSpecID = selected("Spectrum")

    To Sound
    fullID = selected("Sound")

    # Force the exact sample rate: the Sound -> Spectrum -> Matrix ->
    # Spectrum -> Sound roundtrip can leave sub-sample-rate drift that
    # Combine to stereo refuses to merge.
    Override sampling frequency: sr

    # To Sound returns the zero-padded FFT length, often about 50%
    # longer than the source. Trimming here also guarantees the eight
    # channels share one duration.
    selectObject: fullID
    Extract part: 0, originalDur, "rectangular", 1, "no"
    shifted[ch] = selected("Sound")

    # v0.8: no per-channel Scale peak. Measure instead, so the energy
    # lost past Nyquist or below DC stays visible and audible.
    selectObject: shifted[ch]
    chEnergy[ch] = Get energy: 0, 0
    retained[ch] = chEnergy[ch] / srcEnergy * 100
    if retained[ch] > 100
        retained[ch] = 100
    endif

    removeObject: fullID, matDstID, shiftedSpecID
endfor
shiftElapsed = stopwatch

removeObject: sourceMatID, sourceSpecID

# ============================================================
# SHARED-GAIN NORMALISATION  (stage 1)
# ============================================================
peakAll = 0
for ch from 1 to 8
    selectObject: shifted[ch]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
if peakAll < 1e-9
    peakAll = 1e-9
endif
sharedGain = scale_peak / peakAll
sharedGain$ = fixed$(sharedGain, 10)
for ch from 1 to 8
    selectObject: shifted[ch]
    Formula: "self * " + sharedGain$
endfor

# ============================================================
# FORMAT LABELS AND BANK FOLD
# ============================================================
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 stereo pairs"
    mapLine$ = "Ch1|Ch2   Ch3|Ch4   Ch5|Ch6   Ch7|Ch8"
elsif output_format = 3
    formatName$ = "2 quad groups"
    mapLine$ = "quad 1 = Ch1-Ch4    quad 2 = Ch5-Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "1=Ch1+Ch5  2=Ch2+Ch6  3=Ch3+Ch7  4=Ch4+Ch8"
else
    formatName$ = "Stereo mix (L bank 1 / R bank 2)"
    mapLine$ = "L = Ch1+Ch2+Ch3+Ch4    R = Ch5+Ch6+Ch7+Ch8"
endif

needFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needFold = 1
endif

# Bank fold: Ch1-4 to the left, Ch5-8 to the right. Positional rather
# than odd/even, because the channels are normally laid out as two
# spectral banks - up against down in Symmetrical, negative against
# positive in Spread, low shifts against high in All Up.
if needFold
    selectObject: shifted[1], shifted[2], shifted[3], shifted[4]
    Combine to stereo
    bank1 = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "ss_mixL"
    removeObject: bank1

    selectObject: shifted[5], shifted[6], shifted[7], shifted[8]
    Combine to stereo
    bank2 = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "ss_mixR"
    removeObject: bank2
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
stopwatch
downmixNorm = 0
monitorID = 0

if output_format = 1
    selectObject: shifted[1], shifted[2]
    Combine to stereo
    pair12 = selected("Sound")
    selectObject: shifted[3], shifted[4]
    Combine to stereo
    pair34 = selected("Sound")
    selectObject: shifted[5], shifted[6]
    Combine to stereo
    pair56 = selected("Sound")
    selectObject: shifted[7], shifted[8]
    Combine to stereo
    pair78 = selected("Sound")
    selectObject: pair12, pair34
    Combine to stereo
    quad1234 = selected("Sound")
    selectObject: pair56, pair78
    Combine to stereo
    quad5678 = selected("Sound")
    selectObject: quad1234, quad5678
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_8chSpectral_" + presetName$
    outCount = 1
    outChannels = 8
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

elsif output_format = 2
    for k from 1 to 4
        selectObject: shifted[2 * k - 1], shifted[2 * k]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: originalName$ + "_spectral_pair_" + string$(2 * k - 1)
            ... + string$(2 * k) + "_" + presetName$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    selectObject: shifted[1], shifted[2], shifted[3], shifted[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_spectral_quad_1to4_" + presetName$
    selectObject: shifted[5], shifted[6], shifted[7], shifted[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_spectral_quad_5to8_" + presetName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for k from 1 to 4
        selectObject: shifted[k], shifted[k + 4]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "ss_fold" + string$(k)
        removeObject: foldPair
    endfor
    selectObject: fold[1], fold[2], fold[3], fold[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_spectral_fold4_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_spectral_stereo_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "ss_monitor"
    Scale peak: scale_peak
endif

if needFold
    removeObject: mixL, mixR
endif

combineElapsed = stopwatch

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel Spectral Shift ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(originalDur, 2), " s @ ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$, "   input units: ", unitName$
if presetForcedHz = 1
    appendInfoLine: "  (preset values are in Hz, so the bins option was ignored)"
endif
appendInfoLine: "FFT: ", nBins, " bins, ", fixed$(binHz, 4), " Hz per bin, Nyquist ",
    ... fixed$(nyquist, 0), " Hz   (forward FFT ", fixed$(fftElapsed, 2), " s)"
appendInfoLine: "  Bin width is sampling rate over FFT length, so it depends on the"
appendInfoLine: "  file length. That is why shifts are entered in Hz by default."
appendInfoLine: ""
appendInfoLine: "Whole-file FFT: one transform over the entire source, so each shift"
appendInfoLine: "is constant for the whole duration. No frames, no windows, no time"
appendInfoLine: "variation. Translation truncates at DC and Nyquist - nothing wraps."
appendInfoLine: ""

appendInfoLine: "Channel shifts:"
for ch from 1 to 8
    if shift_units = 1
        appendInfoLine: "  Ch", ch, ": requested ", fixed$(requested[ch], 1),
            ... " Hz  ->  ", binOffset[ch], " bins = ", fixed$(actualHz[ch], 2),
            ... " Hz  (error ", fixed$(quantErr[ch], 3), " Hz)   energy kept ",
            ... fixed$(retained[ch], 1), "%"
    else
        appendInfoLine: "  Ch", ch, ": ", binOffset[ch], " bins = ",
            ... fixed$(actualHz[ch], 2), " Hz   energy kept ",
            ... fixed$(retained[ch], 1), "%"
    endif
endfor
if anyClamped > 0
    appendInfoLine: ""
    appendInfoLine: "  NOTE: ", anyClamped, " shift(s) exceeded the bin count and were"
    appendInfoLine: "        clamped. An offset at or beyond ", nBins,
        ... " bins empties the whole"
    appendInfoLine: "        spectrum and the channel would be silent."
endif

worstKeep = 100
for ch from 1 to 8
    if retained[ch] < worstKeep
        worstKeep = retained[ch]
    endif
endfor
if worstKeep < 50
    appendInfoLine: ""
    appendInfoLine: "  NOTE: the weakest channel keeps only ", fixed$(worstKeep, 1),
        ... "% of the source energy."
    appendInfoLine: "        Components pushed past Nyquist or below DC are discarded."
    appendInfoLine: "        v0.7 hid this by scaling every channel to its own peak."
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
appendInfoLine: "  ", mapLine$
appendInfoLine: ""
appendInfoLine: "Normalisation:"
appendInfoLine: "  Shared gain across all eight channels: x", fixed$(sharedGain, 4),
    ... " (from peak ", fixed$(peakAll, 4), ")"
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif
appendInfoLine: ""
appendInfoLine: "(8 inverse FFTs: ", fixed$(shiftElapsed, 2), " s   combine: ",
    ... fixed$(combineElapsed, 2), " s)"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
# The working channels are still alive here, so Panel D draws them
# directly and is identical in all five output formats.

if draw_visualization

    Erase all

    # Per-channel colour: blue = up, orange/red = down, grey = zero
    maxAbsHz = 1
    for ch from 1 to 8
        if abs(actualHz[ch]) > maxAbsHz
            maxAbsHz = abs(actualHz[ch])
        endif
    endfor

    for ch from 1 to 8
        s = binOffset[ch]
        intensity = abs(actualHz[ch]) / maxAbsHz
        if s > 0
            chR[ch] = 0.22 + intensity * 0.08
            chG[ch] = 0.42 + intensity * 0.08
            chB[ch] = 0.80 + intensity * 0.15
            if chB[ch] > 1
                chB[ch] = 1
            endif
        elsif s < 0
            chR[ch] = 0.78 + intensity * 0.18
            if chR[ch] > 1
                chR[ch] = 1
            endif
            chG[ch] = 0.42 - intensity * 0.28
            if chG[ch] < 0
                chG[ch] = 0
            endif
            chB[ch] = 0.20 - intensity * 0.10
            if chB[ch] < 0
                chB[ch] = 0
            endif
        else
            chR[ch] = 0.60
            chG[ch] = 0.60
            chB[ch] = 0.60
        endif
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPECTRAL SHIFT##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + fixed$(originalDur, 2) + " s @ " + string$(sr) + " Hz"
        ... + "  |  " + fixed$(binHz, 3) + " Hz/bin"
        ... + "  |  Format: " + formatName$

    # ----------------------------------------------------------
    # PANEL A: BIN OFFSET BAR CHART  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 0.85, 4.50

    minShift = binOffset[1]
    maxShift = binOffset[1]
    for ch from 2 to 8
        if binOffset[ch] < minShift
            minShift = binOffset[ch]
        endif
        if binOffset[ch] > maxShift
            maxShift = binOffset[ch]
        endif
    endfor
    range = maxShift - minShift
    if range < 10
        range = 10
    endif
    plotMin = minShift - range * 0.18
    plotMax = maxShift + range * 0.18
    if plotMin > 0
        plotMin = -range * 0.10
    endif
    if plotMax < 0
        plotMax = range * 0.10
    endif

    Axes: 0.5, 8.5, plotMin, plotMax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, 8.5, plotMin, plotMax

    Colour: "{0.65, 0.65, 0.65}"
    Line width: 2
    Draw line: 0.5, 0, 8.5, 0
    Line width: 1

    for ch from 1 to 8
        s = binOffset[ch]
        xL = ch - 0.38
        xR = ch + 0.38
        colStr$ = "{" + fixed$(chR[ch], 2) + ", " + fixed$(chG[ch], 2)
            ... + ", " + fixed$(chB[ch], 2) + "}"

        if s >= 0
            Paint rectangle: colStr$, xL, xR, 0, s
            Colour: "{0.30, 0.30, 0.30}"
            Draw rectangle: xL, xR, 0, s
        else
            Paint rectangle: colStr$, xL, xR, s, 0
            Colour: "{0.30, 0.30, 0.30}"
            Draw rectangle: xL, xR, s, 0
        endif

        Font size: 6
        Colour: "White"
        if abs(s) > (plotMax - plotMin) * 0.12
            Text: ch, "centre", s / 2, "half", string$(s)
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: ch, "centre", plotMin + (plotMax - plotMin) * 0.05, "half",
            ... "Ch" + string$(ch)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 5, "yes", "yes", "no"
    Text left: "yes", "Bin offset"
    Text bottom: "yes", "Channel  (blue = up,  orange = down)"

    # ----------------------------------------------------------
    # PANEL B: ACHIEVED FREQUENCY SHIFT (Hz)  (right col, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92

    hzAbs = maxAbsHz * 1.15
    if hzAbs < 5
        hzAbs = 5
    endif
    hzMin = -hzAbs
    hzMax = hzAbs

    Axes: hzMin, hzMax, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", hzMin, hzMax, 0.5, 8.5

    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0.5, 0, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        yLo = y - 0.38
        yHi = y + 0.38
        hz = actualHz[ch]
        colStr$ = "{" + fixed$(chR[ch], 2) + ", " + fixed$(chG[ch], 2)
            ... + ", " + fixed$(chB[ch], 2) + "}"

        if hz >= 0
            Paint rectangle: colStr$, 0, hz, yLo, yHi
        else
            Paint rectangle: colStr$, hz, 0, yLo, yHi
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: hzMin + (hzMax - hzMin) * 0.02, "left", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if abs(hz) > (hzMax - hzMin) * 0.08
            Text: hz / 2, "centre", y, "half", fixed$(hz, 0) + " Hz"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Achieved shift (Hz)  — quantised to whole bins"

    # ----------------------------------------------------------
    # PANEL C: SPECTRAL ENERGY RETAINED  (right col, lower)
    # ----------------------------------------------------------
    # v0.8: replaces the decorative scatter. This is the panel that
    # explains why an extreme shift sounds thin - and it only means
    # anything now that per-channel Scale peak is gone.
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52

    Axes: 0, 105, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 105, 0.5, 8.5

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 100, 0.5, 100, 8.5
    Draw line: 50, 0.5, 50, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        colStr$ = "{" + fixed$(chR[ch], 2) + ", " + fixed$(chG[ch], 2)
            ... + ", " + fixed$(chB[ch], 2) + "}"
        Paint rectangle: colStr$, 0, retained[ch], y - 0.38, y + 0.38
        Colour: "{0.30, 0.30, 0.30}"
        Draw rectangle: 0, retained[ch], y - 0.38, y + 0.38
        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: -2, "right", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if retained[ch] > 14
            Text: retained[ch] / 2, "centre", y, "half", fixed$(retained[ch], 0) + "%"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Energy kept after truncation at DC / Nyquist (%)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Bin offset per channel"
    Text: 6.10, "centre", 7.30, "half", "Achieved Hz (upper) & energy retained (lower)"

    # ----------------------------------------------------------
    # PANEL D: TWO CHANNEL EXAMPLES (full width)
    # ----------------------------------------------------------
    # v0.7 called this "Output 8-ch mix" but drew channels 1 and 2 of
    # the eight-channel object. They are two of the variations.
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    selectObject: shifted[1]
    outDurViz = Get total duration
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: shifted[8]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: shifted[1]
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: shifted[8]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Channel examples  (blue = Ch1 " + fixed$(actualHz[1], 0)
        ... + " Hz,  orange = Ch8 " + fixed$(actualHz[8], 0)
        ... + " Hz)  — shared gain, so levels are comparable"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.85
    Select inner viewport: 0.55, 7.72, 5.88, 6.79
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.80, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  @" + string$(sr) + " Hz"
        ... + "  |  " + string$(nBins) + " bins x " + fixed$(binHz, 3) + " Hz"
        ... + "  |  input in " + unitName$

    Text: 0.02, "left", 0.50, "half",
        ... "Achieved Hz:  "
        ... + fixed$(actualHz[1], 0) + "  " + fixed$(actualHz[2], 0)
        ... + "  " + fixed$(actualHz[3], 0) + "  " + fixed$(actualHz[4], 0)
        ... + "  " + fixed$(actualHz[5], 0) + "  " + fixed$(actualHz[6], 0)
        ... + "  " + fixed$(actualHz[7], 0) + "  " + fixed$(actualHz[8], 0)
        ... + "   [Ch1-Ch8]"

    Text: 0.02, "left", 0.20, "half",
        ... "Format: " + formatName$
        ... + "  |  " + string$(outCount) + objWord$
        ... + " x " + string$(outChannels) + " ch"
        ... + "  |  " + mapLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoID
for ch from 1 to 8
    removeObject: shifted[ch]
endfor

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel spectral translation"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels, "-channel each"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview, L = Ch1-Ch4, R = Ch5-Ch8."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

if monitorID <> 0
    removeObject: monitorID
endif

# === Select the output object(s) ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
