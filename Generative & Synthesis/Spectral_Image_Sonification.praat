# ============================================================
# Praat AudioTools - Spectral_Image_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   RGB-column sonification by additive synthesis.
#   Horizontal image position maps to time. Sparse rows are sampled and
#   averaged within each analysis column. RGB controls three interleaved
#   harmonic families:
#       Red   -> harmonics 1, 4, 7, 10, ...
#       Green -> harmonics 2, 5, 8, 11, ...
#       Blue  -> harmonics 3, 6, 9, 12, ...
#   Harmonic amplitude is C(t)/h and the control values are linearly
#   interpolated between analysis columns. Red-blue balance controls
#   constant-power stereo position; green remains centred.
#
# Important:
#   The vertical image dimension is not mapped to frequency. It is
#   collapsed by sparse row averaging. The visualization makes this
#   reduction explicit.
#
# Changelog v0.5:
#   - Removed global contrast stretching that made flat grey/white images silent
#   - Removed a second brightness multiplication that squared temporal contrast
#   - Replaced non-overlapping half-sine slices with continuous interpolation
#     between RGB control columns (constant images no longer pulse at slice rate)
#   - Added Nyquist, resolution and parameter validation
#   - Added compact main form and Edit details page
#   - Added explicit stereo width and output peak controls
#   - Rebuilt visualization as source -> mapping -> synthesis -> output process
#   - Added measured QC and independent Picture viewports for all text strips
# ============================================================

form Spectral Image Sonification v0.5
    comment === Musical controls ===
    positive duration_s 5.0
    positive fundamental_hz 110
    integer max_harmonics 12

    boolean edit_details 0
    boolean draw_visualization 1
    boolean play_result 1
endform

# ------------------------------------------------------------
# Details defaults
# ------------------------------------------------------------
sample_rate_hz = 44100
analysis_columns = 80
sample_rows_per_column = 8
stereo_width = 0.60
output_peak = 0.90

if edit_details
    beginPause: "Spectral Image Sonification v0.5 - Details"
        integer: "Sample rate (Hz)", sample_rate_hz
        integer: "Analysis columns", analysis_columns
        integer: "Sample rows per column", sample_rows_per_column
        real: "Stereo width (0..1)", stereo_width
        real: "Output peak (0..1)", output_peak
    endPause: "Run", 1
endif

# ------------------------------------------------------------
# Selection / validation
# ------------------------------------------------------------
nPhotos = numberOfSelected("Photo")
if nPhotos <> 1
    exitScript: "Please select exactly one Photo object."
endif

photoID = selected("Photo")
photoName$ = selected$("Photo")

if duration_s <= 0
    exitScript: "Duration must be positive."
endif
if sample_rate_hz < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if duration_s * sample_rate_hz < 8
    exitScript: "Duration is too short for the selected sample rate (need at least 8 samples)."
endif
if fundamental_hz <= 0
    exitScript: "Fundamental frequency must be positive."
endif
if max_harmonics < 1 or max_harmonics > 64
    exitScript: "Max harmonics must be between 1 and 64."
endif
if analysis_columns < 1 or analysis_columns > 512
    exitScript: "Analysis columns must be between 1 and 512."
endif
if sample_rows_per_column < 1 or sample_rows_per_column > 512
    exitScript: "Sample rows per column must be between 1 and 512."
endif
if stereo_width < 0 or stereo_width > 1
    exitScript: "Stereo width must be between 0 and 1."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and at most 1."
endif

nyquist_hz = sample_rate_hz / 2
safe_nyquist_hz = 0.95 * nyquist_hz
highest_harmonic_hz = fundamental_hz * max_harmonics
if highest_harmonic_hz > safe_nyquist_hz
    exitScript: "Highest requested harmonic (" + fixed$(highest_harmonic_hz, 1) + " Hz) exceeds 95% of Nyquist (" + fixed$(safe_nyquist_hz, 1) + " Hz). Reduce F0/harmonics or increase sample rate."
endif

# ------------------------------------------------------------
# Extract RGB channels
# ------------------------------------------------------------
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

selectObject: photoID
Extract red
redID = selected("Matrix")

selectObject: photoID
Extract green
greenID = selected("Matrix")

selectObject: photoID
Extract blue
blueID = selected("Matrix")

selectObject: redID
imgRows = Get number of rows
imgCols = Get number of columns

if imgCols < 1 or imgRows < 1
    removeObject: redID, greenID, blueID
    exitScript: "Invalid image dimensions."
endif

requested_columns = analysis_columns
requested_rows = sample_rows_per_column
if analysis_columns > imgCols
    analysis_columns = imgCols
endif
if sample_rows_per_column > imgRows
    sample_rows_per_column = imgRows
endif

if analysis_columns > 1
    prospective_interval_s = duration_s / (analysis_columns - 1)
    if prospective_interval_s * sample_rate_hz < 2
        removeObject: redID, greenID, blueID
        exitScript: "Analysis resolution is too dense for the requested duration/sample rate (need at least 2 samples between control columns)."
    endif
endif

colStep = imgCols / analysis_columns
rowStep = imgRows / sample_rows_per_column

# ------------------------------------------------------------
# Sample image and reduce each sampled column to RGB means
# ------------------------------------------------------------
meanRed = 0
meanGreen = 0
meanBlue = 0
meanBrightness = 0
maxBrightness = 0
meanLeftPower = 0

for aCol to analysis_columns
    imgCol = round((aCol - 0.5) * colStep)
    if imgCol < 1
        imgCol = 1
    endif
    if imgCol > imgCols
        imgCol = imgCols
    endif

    rSum = 0
    gSum = 0
    bSum = 0

    for sRow to sample_rows_per_column
        imgRow = round((sRow - 0.5) * rowStep)
        if imgRow < 1
            imgRow = 1
        endif
        if imgRow > imgRows
            imgRow = imgRows
        endif

        selectObject: redID
        rVal = Get value in cell: imgRow, imgCol
        selectObject: greenID
        gVal = Get value in cell: imgRow, imgCol
        selectObject: blueID
        bVal = Get value in cell: imgRow, imgCol

        # Photo colour channels are used directly as synthesis controls.
        # Clamp only for robust handling of non-standard Photo formulas.
        rControl = min(1, max(0, rVal))
        gControl = min(1, max(0, gVal))
        bControl = min(1, max(0, bVal))

        rSum = rSum + rControl
        gSum = gSum + gControl
        bSum = bSum + bControl

        sampleIndex = (aCol - 1) * sample_rows_per_column + sRow
        sampleR[sampleIndex] = rControl
        sampleG[sampleIndex] = gControl
        sampleB[sampleIndex] = bControl
    endfor

    redAmp[aCol] = rSum / sample_rows_per_column
    greenAmp[aCol] = gSum / sample_rows_per_column
    blueAmp[aCol] = bSum / sample_rows_per_column
    brightness[aCol] = (redAmp[aCol] + greenAmp[aCol] + blueAmp[aCol]) / 3

    # pLeft is the fraction of channel power assigned to the left.
    # width=0 -> centre; width=1 -> pure red can reach hard left and pure blue hard right.
    pLeft[aCol] = 0.5 + 0.5 * stereo_width * (redAmp[aCol] - blueAmp[aCol])
    pLeft[aCol] = min(1, max(0, pLeft[aCol]))

    meanRed = meanRed + redAmp[aCol]
    meanGreen = meanGreen + greenAmp[aCol]
    meanBlue = meanBlue + blueAmp[aCol]
    meanBrightness = meanBrightness + brightness[aCol]
    meanLeftPower = meanLeftPower + pLeft[aCol]
    if brightness[aCol] > maxBrightness
        maxBrightness = brightness[aCol]
    endif
endfor

meanRed = meanRed / analysis_columns
meanGreen = meanGreen / analysis_columns
meanBlue = meanBlue / analysis_columns
meanBrightness = meanBrightness / analysis_columns
meanLeftPower = meanLeftPower / analysis_columns

if analysis_columns > 1
    control_interval_s = duration_s / (analysis_columns - 1)
else
    control_interval_s = duration_s
endif

# ------------------------------------------------------------
# Information
# ------------------------------------------------------------
writeInfoLine: "=== Spectral Image Sonification v0.5 ==="
appendInfoLine: "Image: ", photoName$, " (", imgCols, " x ", imgRows, ")"
appendInfoLine: "Mapping: horizontal position -> time; sampled rows -> RGB column mean"
appendInfoLine: "Harmonics: R=1,4,7... G=2,5,8... B=3,6,9...; amplitude = RGB/h"
appendInfoLine: "Analysis: ", analysis_columns, " columns x ", sample_rows_per_column, " sampled rows"
if analysis_columns <> requested_columns or sample_rows_per_column <> requested_rows
    appendInfoLine: "Analysis resolution was clamped to image dimensions."
endif
appendInfoLine: "F0: ", fixed$(fundamental_hz, 2), " Hz | harmonics: ", max_harmonics, " | max frequency: ", fixed$(highest_harmonic_hz, 1), " Hz"
appendInfoLine: "Stereo width: ", fixed$(stereo_width, 2), " | output peak: ", fixed$(output_peak, 2)
appendInfoLine: "Mean RGB: ", fixed$(meanRed, 3), ", ", fixed$(meanGreen, 3), ", ", fixed$(meanBlue, 3)
appendInfoLine: ""

# ------------------------------------------------------------
# Additive synthesis with continuous control interpolation
# ------------------------------------------------------------
appendInfoLine: "Synthesizing..."
leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_hz, "0"
rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_hz, "0"

if analysis_columns = 1
    harmonicSum$ = ""
    for h to max_harmonics
        freq = fundamental_hz * h
        colorIdx = ((h - 1) mod 3) + 1
        if colorIdx = 1
            hAmp = redAmp[1] / h
        elsif colorIdx = 2
            hAmp = greenAmp[1] / h
        else
            hAmp = blueAmp[1] / h
        endif

        if hAmp > 0.000001
            term$ = fixed$(hAmp, 8) + "*sin(twoPi*" + fixed$(freq, 4) + "*x)"
            if harmonicSum$ = ""
                harmonicSum$ = term$
            else
                harmonicSum$ = harmonicSum$ + "+" + term$
            endif
        endif
    endfor

    if harmonicSum$ <> ""
        leftGain = sqrt(pLeft[1])
        rightGain = sqrt(1 - pLeft[1])
        selectObject: leftSound
        Formula: "self + " + fixed$(leftGain, 8) + "*(" + harmonicSum$ + ")"
        selectObject: rightSound
        Formula: "self + " + fixed$(rightGain, 8) + "*(" + harmonicSum$ + ")"
    endif
else
    intervalCount = analysis_columns - 1
    intervalsPerChunk = 8
    nChunks = ceiling(intervalCount / intervalsPerChunk)

    for chunk to nChunks
        startInterval = (chunk - 1) * intervalsPerChunk + 1
        endInterval = min(chunk * intervalsPerChunk, intervalCount)
        leftFormula$ = ""
        rightFormula$ = ""

        for aCol from startInterval to endInterval
            tStart = (aCol - 1) * control_interval_s
            tEnd = aCol * control_interval_s
            tStart$ = fixed$(tStart, 8)
            tEnd$ = fixed$(tEnd, 8)
            interval$ = fixed$(control_interval_s, 8)
            uFormula$ = "((x-" + tStart$ + ")/" + interval$ + ")"

            harmonicSum$ = ""
            for h to max_harmonics
                freq = fundamental_hz * h
                colorIdx = ((h - 1) mod 3) + 1
                if colorIdx = 1
                    amp0 = redAmp[aCol] / h
                    amp1 = redAmp[aCol + 1] / h
                elsif colorIdx = 2
                    amp0 = greenAmp[aCol] / h
                    amp1 = greenAmp[aCol + 1] / h
                else
                    amp0 = blueAmp[aCol] / h
                    amp1 = blueAmp[aCol + 1] / h
                endif

                if max(amp0, amp1) > 0.000001
                    ampDiff = amp1 - amp0
                    ampFormula$ = "(" + fixed$(amp0, 8) + "+(" + fixed$(ampDiff, 8) + ")*" + uFormula$ + ")"
                    term$ = ampFormula$ + "*sin(twoPi*" + fixed$(freq, 4) + "*x)"
                    if harmonicSum$ = ""
                        harmonicSum$ = term$
                    else
                        harmonicSum$ = harmonicSum$ + "+" + term$
                    endif
                endif
            endfor

            if harmonicSum$ <> ""
                p0 = pLeft[aCol]
                p1 = pLeft[aCol + 1]
                pDiff = p1 - p0
                pFormula$ = "(" + fixed$(p0, 8) + "+(" + fixed$(pDiff, 8) + ")*" + uFormula$ + ")"

                sliceL$ = "if x>=" + tStart$ + " and x<" + tEnd$ + " then sqrt(" + pFormula$ + ")*(" + harmonicSum$ + ") else 0 fi"
                sliceR$ = "if x>=" + tStart$ + " and x<" + tEnd$ + " then sqrt(1-(" + pFormula$ + "))*(" + harmonicSum$ + ") else 0 fi"

                if leftFormula$ = ""
                    leftFormula$ = sliceL$
                    rightFormula$ = sliceR$
                else
                    leftFormula$ = leftFormula$ + "+" + sliceL$
                    rightFormula$ = rightFormula$ + "+" + sliceR$
                endif
            endif
        endfor

        if leftFormula$ <> ""
            selectObject: leftSound
            Formula: "self + (" + leftFormula$ + ")"
            selectObject: rightSound
            Formula: "self + (" + rightFormula$ + ")"
        endif
        appendInfoLine: "  Chunk ", chunk, "/", nChunks
    endfor
endif

# ------------------------------------------------------------
# Combine, edge fade and output level
# ------------------------------------------------------------
selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "spectral_" + photoName$
removeObject: leftSound, rightSound

# Short cosine edge fade only at the beginning/end of the whole sound.
# Internal analysis boundaries remain continuous and are not gated to zero.
fade_s = min(0.02, duration_s / 4)
if fade_s > 0
    fade$ = fixed$(fade_s, 8)
    dur$ = fixed$(duration_s, 8)
    endFadeStart$ = fixed$(duration_s - fade_s, 8)
    selectObject: outputSound
    Formula: "if x<" + fade$ + " then self*0.5*(1-cos(pi*x/" + fade$ + ")) else self fi"
    Formula: "if x>" + endFadeStart$ + " then self*0.5*(1-cos(pi*(" + dur$ + "-x)/" + fade$ + ")) else self fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
if preNormPeak > 0
    Scale peak: output_peak
endif
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0

# ------------------------------------------------------------
# Visualization before cleanup so all sampled controls remain available
# ------------------------------------------------------------
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing process visualization..."
    @drawVisualization
endif

# Cleanup extracted matrices only; source Photo and output remain.
removeObject: redID, greenID, blueID

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output peak: ", fixed$(finalPeak, 4), " | RMS: ", fixed$(finalRMS, 4)

# ============================================================================
# Visualization: show the mapping process, not only the result
# ============================================================================
procedure drawVisualization
    Erase all

    # Every title/text strip gets an independent inner viewport so that
    # Picture state from a previous panel cannot collide with later text.

    # ---------------- Title strip ----------------
    Select outer viewport: 0, 8, 0.04, 0.32
    Select inner viewport: 0.18, 7.82, 0.06, 0.30
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Spectral Image Sonification - " + photoName$

    # ---------------- Process strip ----------------
    Select outer viewport: 0, 8, 0.34, 0.62
    Select inner viewport: 0.20, 7.80, 0.37, 0.59
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30,0.30,0.30}"
    Text: 0.5, "centre", 0.52, "half", "Photo -> sparse RGB rows -> column means -> RGB harmonic families (1/h) -> linear time interpolation -> constant-power pan -> additive output"

    # ---------------- Panel A title ----------------
    Select outer viewport: 0, 8, 0.67, 0.88
    Select inner viewport: 0.10, 7.90, 0.69, 0.86
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "A  Image reduction: sampled RGB grid (left) -> row-mean RGB controls over sonification time (right)"

    # A-left: sampled RGB grid
    Select outer viewport: 0, 3.45, 0.90, 2.20
    Select inner viewport: 0.48, 3.18, 1.00, 2.02
    Axes: 0, analysis_columns, 0, sample_rows_per_column
    Paint rectangle: "{0.96,0.96,0.96}", 0, analysis_columns, 0, sample_rows_per_column
    for .c to analysis_columns
        for .r to sample_rows_per_column
            .idx = (.c - 1) * sample_rows_per_column + .r
            .colour$ = "{" + fixed$(sampleR[.idx], 4) + "," + fixed$(sampleG[.idx], 4) + "," + fixed$(sampleB[.idx], 4) + "}"
            .y0 = sample_rows_per_column - .r
            .y1 = .y0 + 1
            Paint rectangle: .colour$, .c - 1, .c, .y0, .y1
        endfor
    endfor
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.48, 3.18, 1.00, 2.02
    Axes: 0, analysis_columns, 0, sample_rows_per_column
    Font size: 7
    Marks bottom: 4, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Analysis column"
    Text left: "yes", "Sampled row"

    # A-right: row-mean RGB controls
    Select outer viewport: 3.45, 8, 0.90, 2.20
    Select inner viewport: 3.82, 7.62, 1.00, 2.02
    Axes: 0, duration_s, 0, 1
    Paint rectangle: "{0.96,0.96,0.96}", 0, duration_s, 0, 1

    if analysis_columns = 1
        Colour: "{0.86,0.20,0.20}"
        Draw line: 0, redAmp[1], duration_s, redAmp[1]
        Colour: "{0.20,0.68,0.25}"
        Draw line: 0, greenAmp[1], duration_s, greenAmp[1]
        Colour: "{0.20,0.32,0.86}"
        Draw line: 0, blueAmp[1], duration_s, blueAmp[1]
    else
        for .c from 2 to analysis_columns
            .t0 = (.c - 2) * control_interval_s
            .t1 = (.c - 1) * control_interval_s
            Colour: "{0.86,0.20,0.20}"
            Draw line: .t0, redAmp[.c - 1], .t1, redAmp[.c]
            Colour: "{0.20,0.68,0.25}"
            Draw line: .t0, greenAmp[.c - 1], .t1, greenAmp[.c]
            Colour: "{0.20,0.32,0.86}"
            Draw line: .t0, blueAmp[.c - 1], .t1, blueAmp[.c]
        endfor
    endif
    Colour: "Black"
    Draw inner box
    Select inner viewport: 3.82, 7.62, 1.00, 2.02
    Axes: 0, duration_s, 0, 1
    Font size: 7
    Marks bottom: 4, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "RGB mean"

    # ---------------- Panel B title ----------------
    Select outer viewport: 0, 8, 2.30, 2.51
    Select inner viewport: 0.10, 7.90, 2.32, 2.49
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "B  Spectral control score: each RGB family drives every third harmonic; line weight follows the actual 1/h coefficient"

    # Panel B: harmonic allocation score
    Select outer viewport: 0, 8, 2.53, 4.00
    Select inner viewport: 0.78, 7.62, 2.64, 3.80
    Axes: 0, duration_s, 0.5, max_harmonics + 0.5
    Paint rectangle: "{0.965,0.965,0.965}", 0, duration_s, 0.5, max_harmonics + 0.5

    # Faint harmonic lattice
    Colour: "{0.86,0.86,0.86}"
    Line width: 0.5
    for .h to max_harmonics
        Draw line: 0, .h, duration_s, .h
    endfor
    Line width: 1

    if analysis_columns = 1
        for .h to max_harmonics
            .group = ((.h - 1) mod 3) + 1
            if .group = 1
                .amp = redAmp[1] / .h
                Colour: "{0.82,0.22,0.20}"
            elsif .group = 2
                .amp = greenAmp[1] / .h
                Colour: "{0.20,0.62,0.24}"
            else
                .amp = blueAmp[1] / .h
                Colour: "{0.20,0.32,0.82}"
            endif
            if .amp > 0.000001
                Line width: 0.55 + 3.0 * sqrt(.amp)
                Draw line: 0, .h, duration_s, .h
            endif
        endfor
    else
        for .c from 1 to analysis_columns - 1
            .t0 = (.c - 1) * control_interval_s
            .t1 = .c * control_interval_s
            for .h to max_harmonics
                .group = ((.h - 1) mod 3) + 1
                if .group = 1
                    .amp = 0.5 * (redAmp[.c] + redAmp[.c + 1]) / .h
                    Colour: "{0.82,0.22,0.20}"
                elsif .group = 2
                    .amp = 0.5 * (greenAmp[.c] + greenAmp[.c + 1]) / .h
                    Colour: "{0.20,0.62,0.24}"
                else
                    .amp = 0.5 * (blueAmp[.c] + blueAmp[.c + 1]) / .h
                    Colour: "{0.20,0.32,0.82}"
                endif
                if .amp > 0.000001
                    Line width: 0.55 + 3.0 * sqrt(.amp)
                    Draw line: .t0, .h, .t1, .h
                endif
            endfor
        endfor
    endif
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 2.64, 3.80
    Axes: 0, duration_s, 0.5, max_harmonics + 0.5
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    if max_harmonics <= 16
        Marks left every: 1, 1, "yes", "yes", "no"
    else
        Marks left: 6, "yes", "yes", "no"
    endif
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Harmonic h"

    # Panel B formula strip
    Select outer viewport: 0, 8, 4.01, 4.20
    Select inner viewport: 0.20, 7.80, 4.03, 4.18
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.30,0.30,0.30}"
    Text: 0.5, "centre", 0.50, "half", "fh = h F0     Ah(t) = Cgroup(t) / h     group = 1 + ((h-1) mod 3)     RGB controls are linearly interpolated between sampled columns"

    # ---------------- Panel C title ----------------
    Select outer viewport: 0, 8, 4.25, 4.46
    Select inner viewport: 0.10, 7.90, 4.27, 4.44
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "C  Stereo mapping: red-blue balance controls left power; gains are constant-power sqrt(p) and sqrt(1-p)"

    # Panel C: stereo gain curves
    Select outer viewport: 0, 8, 4.48, 5.62
    Select inner viewport: 0.78, 7.62, 4.58, 5.42
    Axes: 0, duration_s, 0, 1.05
    Paint rectangle: "{0.965,0.965,0.965}", 0, duration_s, 0, 1.05
    Colour: "{0.78,0.78,0.78}"
    Dotted line
    Draw line: 0, sqrt(0.5), duration_s, sqrt(0.5)
    Solid line

    if analysis_columns = 1
        .gL = sqrt(pLeft[1])
        .gR = sqrt(1 - pLeft[1])
        Colour: "{0.82,0.22,0.20}"
        Line width: 1.5
        Draw line: 0, .gL, duration_s, .gL
        Colour: "{0.20,0.32,0.82}"
        Draw line: 0, .gR, duration_s, .gR
    else
        .sub = 4
        for .c from 1 to analysis_columns - 1
            .baseT = (.c - 1) * control_interval_s
            .prevT = .baseT
            .prevP = pLeft[.c]
            .prevL = sqrt(.prevP)
            .prevR = sqrt(1 - .prevP)
            for .k to .sub
                .u = .k / .sub
                .t = .baseT + .u * control_interval_s
                .p = pLeft[.c] + .u * (pLeft[.c + 1] - pLeft[.c])
                .gL = sqrt(.p)
                .gR = sqrt(1 - .p)
                Colour: "{0.82,0.22,0.20}"
                Line width: 1.5
                Draw line: .prevT, .prevL, .t, .gL
                Colour: "{0.20,0.32,0.82}"
                Draw line: .prevT, .prevR, .t, .gR
                .prevT = .t
                .prevL = .gL
                .prevR = .gR
            endfor
        endfor
    endif
    Line width: 1
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.78, 7.62, 4.58, 5.42
    Axes: 0, duration_s, 0, 1.05
    Font size: 7
    Marks bottom: 5, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Channel gain"

    # ---------------- Panel D title ----------------
    Select outer viewport: 0, 8, 5.69, 5.90
    Select inner viewport: 0.10, 7.90, 5.71, 5.88
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "D  Measured output: final stereo waveform after interpolation, additive sum, edge fade and peak normalization"

    .waveRange = max(0.001, finalPeak * 1.08)

    # D-left channel
    selectObject: outputSound
    Extract one channel: 1
    .leftOut = selected("Sound")
    Select outer viewport: 0, 8, 5.92, 6.55
    Select inner viewport: 0.78, 7.62, 5.98, 6.43
    selectObject: .leftOut
    Colour: "{0.82,0.22,0.20}"
    Draw: 0, duration_s, -.waveRange, .waveRange, "no", "Curve"
    Select inner viewport: 0.78, 7.62, 5.98, 6.43
    Axes: 0, duration_s, -.waveRange, .waveRange
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "L"

    # D-right channel
    selectObject: outputSound
    Extract one channel: 2
    .rightOut = selected("Sound")
    Select outer viewport: 0, 8, 6.57, 7.25
    Select inner viewport: 0.78, 7.62, 6.63, 7.10
    selectObject: .rightOut
    Colour: "{0.20,0.32,0.82}"
    Draw: 0, duration_s, -.waveRange, .waveRange, "no", "Curve"
    Select inner viewport: 0.78, 7.62, 6.63, 7.10
    Axes: 0, duration_s, -.waveRange, .waveRange
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Marks bottom: 5, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "R"
    Text bottom: "yes", "Time (s)"
    removeObject: .leftOut, .rightOut

    # ---------------- QC summary ----------------
    Select outer viewport: 0, 8, 7.34, 8.18
    Select inner viewport: 0.34, 7.66, 7.38, 8.14
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955,0.955,0.96}", 0, 1, 0, 1
    Colour: "{0.72,0.72,0.74}"
    Draw rectangle: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.84, "half", "PROCESS / QC"
    Font size: 5.8
    Colour: "{0.27,0.27,0.32}"

    .imgQC$ = "IMAGE  " + string$(imgCols) + "x" + string$(imgRows) + " | sample " + string$(analysis_columns) + "x" + string$(sample_rows_per_column)
    .mapQC$ = "RGB  mean " + fixed$(meanRed,2) + "/" + fixed$(meanGreen,2) + "/" + fixed$(meanBlue,2) + " | no stretch"
    .timeQC$ = "TIME  " + string$(analysis_columns) + " controls | " + fixed$(1000*control_interval_s,1) + " ms | linear"
    .specQC$ = "SPEC  F0 " + fixed$(fundamental_hz,1) + " | H" + string$(max_harmonics) + " | top " + fixed$(highest_harmonic_hz,0) + " Hz"
    .stereoQC$ = "STEREO  w " + fixed$(stereo_width,2) + " | mean L-power " + fixed$(meanLeftPower,2)
    .outQC$ = "OUT  peak " + fixed$(finalPeak,3) + " | RMS " + fixed$(finalRMS,3) + " | Nyq " + fixed$(nyquist_hz/1000,1) + "k"

    Text: 0.02, "left", 0.58, "half", .imgQC$
    Text: 0.35, "left", 0.58, "half", .mapQC$
    Text: 0.68, "left", 0.58, "half", .timeQC$
    Text: 0.02, "left", 0.25, "half", .specQC$
    Text: 0.35, "left", 0.25, "half", .stereoQC$
    Text: 0.68, "left", 0.25, "half", .outQC$

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
