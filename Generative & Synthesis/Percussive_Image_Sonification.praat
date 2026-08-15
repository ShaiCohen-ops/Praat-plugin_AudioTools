# ============================================================
# Praat AudioTools - Percussive_Image_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 form runtime fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# PERCUSSIVE IMAGE SONIFICATION
#
# CONCEPTUAL MODEL
# ----------------
# This script is a deterministic parameter-mapping sonification of a selected
# Praat Photo. It does NOT attempt object recognition or semantic image-to-audio
# translation. It preserves explicit spatial/data relations:
#
#   image X position
#       -> linear scan time
#
#   image vertical band
#       -> logarithmic percussion register
#
#   perceptual luminance
#       -> event strength
#
#   local 2-D luminance contrast
#       -> high-frequency / inharmonic attack content
#
#   red-vs-blue chromatic balance
#       -> equal-power stereo position
#          red -> left, neutral -> centre, blue -> right
#
# This makes the mapping inspectable and reproducible: the same Photo and
# parameters always produce the same event map and the same Sound.
#
# WHY v0.3 WAS CONCEPTUALLY INCONSISTENT
# --------------------------------------
# v0.3 simultaneously claimed:
#
#   Column position -> Time
#   Brightness      -> Click interval
#
# But the next column was advanced only after the brightness-dependent click
# interval. Therefore column X did NOT have a fixed temporal location. Bright
# images were scanned faster, columns could wrap and repeat, and two images
# with the same geometry could have different X->time mappings.
#
# v0.4 fixes this by assigning every horizontal image bin a fixed onset time.
# Brightness no longer changes the scan clock.
#
# 2-D FEATURE EXTRACTION
# ----------------------
# The Photo is reduced to Horizontal_bins x Vertical_bands cells. RGB integral
# images provide O(1) mean colour per cell after two cumulative Matrix passes.
#
# Luminance uses the standard linear-RGB weighting:
#
#   Y = 0.2126 R + 0.7152 G + 0.0722 B
#
# Here it is used as a transparent perceptual weighting of the normalized Photo
# channels; this is not a colour-managed photometric conversion.
#
# Local edge energy is the normalized magnitude of differences to the previous
# horizontal and vertical cells:
#
#   E = sqrt(DeltaX(Y)^2 + DeltaY(Y)^2)
#
# It is a coarse cell-grid contrast descriptor, not an edge detector claiming
# pixel-level computer-vision accuracy.
#
# EVENT TRIGGER
# -------------
# A cell becomes audible if:
#
#   activity = max(luminance, Edge_emphasis * normalizedEdge)
#
# exceeds Activity_threshold.
#
# Thus dark but strong boundaries can remain audible while a black/featureless
# image remains silent.
#
# PERCUSSIVE SOURCE
# -----------------
# Every active cell creates one deterministic decaying inharmonic hit. Edge
# energy increases upper-partial strength; it does NOT move the onset time.
# Simultaneous active vertical bands in one scan column are energy-compensated
# by 1/sqrt(number of active bands), preventing image height/density from
# becoming an accidental master-volume control.
#
# FREQUENCY / SAMPLING
# --------------------
# Vertical position maps logarithmically from Min_pitch_Hz to Max_pitch_Hz.
# The source contains partial ratios up to 3.11, so one common frequency scale
# is applied when required to keep the complete source below 0.45*Fs.
#
# VISUALIZATION
# -------------
#   A binned image luminance map used by the sonification
#   B actual audible event field (time x frequency, colour indicates pan)
#   C scan descriptors: mean luminance / edge / pan by X bin
#   D measured output spectrogram + sampled event-frequency guides
#   mapping / activity / sampling / output QC
#
# v0.4.1 runtime fix
# ------------------
#   - Corrected Praat form syntax for numeric fields: initial values are string
#     arguments (e.g. positive: "Duration (s)", "4.0").
#   - Boolean initial values remain numeric, as allowed by Praat.
#   - No sonification mapping, event logic, DSP or visualization changed.
#
# v0.4.2 runtime fixes
# --------------------
#   - Renamed illegal variable e (Euler constant in Praat) to edgeMagnitude.
#   - No mapping, DSP or visualization semantics changed.
#
# v0.4 changes
# ------------
#   - fixed X->time mapping; brightness no longer changes scan speed
#   - preserves vertical image structure instead of collapsing each column to
#     one mean value
#   - perceptual luminance weighting instead of unweighted RGB mean
#   - 2-D local contrast drives percussive spectral sharpness
#   - conventional equal-power pan: red left, blue right
#   - deterministic sound; no random noise source
#   - RGB integral images for efficient regional means
#   - direct stereo Formula(part) rendering, one pass per active X bin
#   - polyphony energy compensation per scan column
#   - Nyquist-aware common pitch scaling
#   - master amplitude semantics preserved; final peak protection is down-only
#   - visualization rebuilt from the actual extracted image features/events
#
# Sonification principle:
#   transformation of data relations into audible relations should preserve
#   interpretable correspondences rather than only produce image-conditioned
#   musical material.
# ============================================================

form: "Percussive Image Sonification v0.4.1"
    comment: "Select one Photo object before running."

    positive: "Duration (s)", "4.0"
    integer: "Sample rate (Hz)", "44100"

    integer: "Horizontal scan bins", "72"
    integer: "Vertical bands", "12"

    positive: "Minimum pitch (Hz)", "180"
    positive: "Maximum pitch (Hz)", "3600"
    positive: "Hit duration (s)", "0.055"

    real: "Activity threshold (0..1)", "0.14"
    real: "Edge emphasis (0..1)", "0.65"
    real: "Colour pan strength (0..1)", "0.90"
    real: "Master amplitude", "0.58"

    boolean: "Invert vertical pitch", 0
    boolean: "Peak protection", 1
    boolean: "Draw visualization", 1
    boolean: "Play result", 1
endform

# ---------------------------------------------------------------------------
# PHOTO SELECTION / VALIDATION
# ---------------------------------------------------------------------------
nPhotos = numberOfSelected("Photo")
if nPhotos = 0
    exitScript: "Please select one Photo object first."
endif

photoID = selected("Photo")
photoName$ = selected$("Photo")

if duration <= 0 or duration > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if sample_rate < 8000 or sample_rate > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if horizontal_scan_bins < 1 or horizontal_scan_bins > 256
    exitScript: "Horizontal scan bins must be between 1 and 256."
endif
if vertical_bands < 1 or vertical_bands > 32
    exitScript: "Vertical bands must be between 1 and 32."
endif
if minimum_pitch <= 0 or maximum_pitch <= minimum_pitch
    exitScript: "Pitch range must satisfy 0 < minimum < maximum."
endif
if hit_duration <= 0 or hit_duration > duration
    exitScript: "Hit duration must be > 0 and <= total duration."
endif
if activity_threshold < 0 or activity_threshold > 1
    exitScript: "Activity threshold must be between 0 and 1."
endif
if edge_emphasis < 0 or edge_emphasis > 1
    exitScript: "Edge emphasis must be between 0 and 1."
endif
if colour_pan_strength < 0 or colour_pan_strength > 1
    exitScript: "Colour pan strength must be between 0 and 1."
endif
if master_amplitude <= 0 or master_amplitude > 2
    exitScript: "Master amplitude must be > 0 and <= 2."
endif

sr = sample_rate
safeTop = 0.45*sr
partialRatioMax = 3.11

frequencyScale =
    ... min(1,safeTop/(partialRatioMax*maximum_pitch))

effectiveMinPitch = minimum_pitch*frequencyScale
effectiveMaxPitch = maximum_pitch*frequencyScale

if effectiveMinPitch < 20
    exitScript: "Nyquist scaling would move the minimum pitch below 20 Hz. Reduce Maximum pitch or raise Minimum pitch."
endif

uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# EXTRACT RGB MATRICES
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  PERCUSSIVE IMAGE SONIFICATION v0.4.1"
writeInfoLine: "=============================================="
appendInfoLine: "Photo: ", photoName$
appendInfoLine: "Extracting RGB matrices..."

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
nrows = Get number of rows
ncols = Get number of columns

if nrows < 1 or ncols < 1
    removeObject: redID,greenID,blueID
    exitScript: "Invalid Photo dimensions."
endif

nXBins = min(horizontal_scan_bins,ncols)
nYBands = min(vertical_bands,nrows)
numCells = nXBins*nYBands

appendInfoLine: "Photo dimensions: ", ncols, " x ", nrows
appendInfoLine: "Analysis grid: ", nXBins, " x ", nYBands

# ---------------------------------------------------------------------------
# RAW CHANNEL SCALE BEFORE INTEGRATION
# ---------------------------------------------------------------------------
selectObject: redID
minRed = Get minimum
maxRed = Get maximum

selectObject: greenID
minGreen = Get minimum
maxGreen = Get maximum

selectObject: blueID
minBlue = Get minimum
maxBlue = Get maximum

channelBlack = min(minRed,min(minGreen,minBlue))
channelWhite = max(maxRed,max(maxGreen,maxBlue))
channelRange = channelWhite-channelBlack

if channelRange <= 1e-15
    channelRange = 1
endif

appendInfoLine: "Raw channel range: ",
    ... fixed$(channelBlack,4), " to ",
    ... fixed$(channelWhite,4)

# ---------------------------------------------------------------------------
# 2-D INTEGRAL IMAGES
# ---------------------------------------------------------------------------
# Praat Matrix Formula modification is row-major: each row is processed
# left-to-right. First integrate across columns, then down rows.
selectObject: redID
Formula: "if col>1 then self+self[row,col-1] else self fi"
Formula: "if row>1 then self+self[row-1,col] else self fi"

selectObject: greenID
Formula: "if col>1 then self+self[row,col-1] else self fi"
Formula: "if row>1 then self+self[row-1,col] else self fi"

selectObject: blueID
Formula: "if col>1 then self+self[row,col-1] else self fi"
Formula: "if row>1 then self+self[row-1,col] else self fi"

# ---------------------------------------------------------------------------
# CELL FEATURES
# ---------------------------------------------------------------------------
cellLuminance# = zero#(numCells)
cellRed# = zero#(numCells)
cellBlue# = zero#(numCells)
cellPan# = zero#(numCells)
cellEdgeRaw# = zero#(numCells)
cellEdge# = zero#(numCells)
cellActivity# = zero#(numCells)
cellActive# = zero#(numCells)
cellFrequency# = zero#(numCells)

columnMeanLuminance# = zero#(nXBins)
columnMeanEdge# = zero#(nXBins)
columnMeanPan# = zero#(nXBins)
activePerColumn# = zero#(nXBins)

sumLuminance = 0
sumPan = 0

# Regional means from four integral-image corners.
for xb from 1 to nXBins
    c1 = floor((xb-1)*ncols/nXBins)+1
    c2 = floor(xb*ncols/nXBins)
    c2 = max(c1,c2)

    for yb from 1 to nYBands
        r1 = floor((yb-1)*nrows/nYBands)+1
        r2 = floor(yb*nrows/nYBands)
        r2 = max(r1,r2)

        area = (r2-r1+1)*(c2-c1+1)

        sumR = object[redID,r2,c2]
        sumG = object[greenID,r2,c2]
        sumB = object[blueID,r2,c2]

        if c1 > 1
            sumR = sumR-object[redID,r2,c1-1]
            sumG = sumG-object[greenID,r2,c1-1]
            sumB = sumB-object[blueID,r2,c1-1]
        endif

        if r1 > 1
            sumR = sumR-object[redID,r1-1,c2]
            sumG = sumG-object[greenID,r1-1,c2]
            sumB = sumB-object[blueID,r1-1,c2]
        endif

        if c1 > 1 and r1 > 1
            sumR = sumR+object[redID,r1-1,c1-1]
            sumG = sumG+object[greenID,r1-1,c1-1]
            sumB = sumB+object[blueID,r1-1,c1-1]
        endif

        rMean = sumR/area
        gMean = sumG/area
        bMean = sumB/area

        rNorm = max(0,min(1,(rMean-channelBlack)/channelRange))
        gNorm = max(0,min(1,(gMean-channelBlack)/channelRange))
        bNorm = max(0,min(1,(bMean-channelBlack)/channelRange))

        luminance =
            ... 0.2126*rNorm+0.7152*gNorm+0.0722*bNorm

        # Conventional pan coordinate:
        # 0 = left, 0.5 = centre, 1 = right.
        # Relative R/B balance avoids forcing neutral greys away from centre.
        rbDen = max(0.08,rNorm+bNorm)
        blueMinusRed = (bNorm-rNorm)/rbDen
        pan =
            ... 0.5+0.48*colour_pan_strength*blueMinusRed
        pan = max(0.02,min(0.98,pan))

        idx = (xb-1)*nYBands+yb

        cellLuminance#[idx] = luminance
        cellRed#[idx] = rNorm
        cellBlue#[idx] = bNorm
        cellPan#[idx] = pan

        sumLuminance = sumLuminance+luminance
        sumPan = sumPan+pan
    endfor
endfor

meanLuminance = sumLuminance/numCells
meanPan = sumPan/numCells

# ---------------------------------------------------------------------------
# 2-D CELL-GRID CONTRAST
# ---------------------------------------------------------------------------
maxEdgeRaw = 0

for xb from 1 to nXBins
    for yb from 1 to nYBands
        idx = (xb-1)*nYBands+yb
        lum = cellLuminance#[idx]

        dxLum = 0
        dyLum = 0

        if xb > 1
            leftIdx = (xb-2)*nYBands+yb
            dxLum = lum-cellLuminance#[leftIdx]
        endif

        if yb > 1
            belowIdx = (xb-1)*nYBands+yb-1
            dyLum = lum-cellLuminance#[belowIdx]
        endif

        edgeMagnitude = sqrt(dxLum*dxLum+dyLum*dyLum)
        cellEdgeRaw#[idx] = edgeMagnitude
        maxEdgeRaw = max(maxEdgeRaw,edgeMagnitude)
    endfor
endfor

if maxEdgeRaw < 1e-12
    maxEdgeRaw = 1
endif

# ---------------------------------------------------------------------------
# ACTIVITY / PITCH / COLUMN SUMMARY
# ---------------------------------------------------------------------------
eventCount = 0
activeColumns = 0
sumEdge = 0

for xb from 1 to nXBins
    colLumSum = 0
    colEdgeSum = 0
    colPanSum = 0
    activeThisColumn = 0

    for yb from 1 to nYBands
        idx = (xb-1)*nYBands+yb

        edge = min(1,cellEdgeRaw#[idx]/maxEdgeRaw)
        lum = cellLuminance#[idx]
        activity = max(lum,edge_emphasis*edge)

        if nYBands = 1
            verticalPos = 0.5
        else
            verticalPos = (yb-1)/(nYBands-1)
        endif

        if invert_vertical_pitch
            verticalPos = 1-verticalPos
        endif

        f =
            ... effectiveMinPitch*
            ... (effectiveMaxPitch/effectiveMinPitch)^verticalPos

        cellEdge#[idx] = edge
        cellActivity#[idx] = activity
        cellFrequency#[idx] = f

        if activity >= activity_threshold
            cellActive#[idx] = 1
            activeThisColumn = activeThisColumn+1
            eventCount = eventCount+1
        endif

        colLumSum = colLumSum+lum
        colEdgeSum = colEdgeSum+edge
        colPanSum = colPanSum+cellPan#[idx]
        sumEdge = sumEdge+edge
    endfor

    activePerColumn#[xb] = activeThisColumn
    columnMeanLuminance#[xb] = colLumSum/nYBands
    columnMeanEdge#[xb] = colEdgeSum/nYBands
    columnMeanPan#[xb] = colPanSum/nYBands

    if activeThisColumn > 0
        activeColumns = activeColumns+1
    endif
endfor

meanEdge = sumEdge/numCells
activeCellFraction = eventCount/numCells

# ---------------------------------------------------------------------------
# FIXED X -> TIME MAPPING
# ---------------------------------------------------------------------------
if nXBins = 1
    scanStep = 0
    scanSpan = 0
else
    scanSpan = max(0,duration-hit_duration)
    scanStep = scanSpan/(nXBins-1)
endif

# ---------------------------------------------------------------------------
# CREATE STEREO OUTPUT
# ---------------------------------------------------------------------------
outputSound = Create Sound from formula:
    ... "PercussiveImage_" + uid$,
    ... 2,0,duration,sr,"0"

# ---------------------------------------------------------------------------
# RENDER ONE LOCAL FORMULA PASS PER ACTIVE X BIN
# ---------------------------------------------------------------------------
for xb from 1 to nXBins
    activeBands = activePerColumn#[xb]

    if activeBands > 0
        if nXBins = 1
            t0 = 0
        else
            t0 = (xb-1)*scanStep
        endif

        t1 = min(duration,t0+hit_duration)
        eventDur = max(1/sr,t1-t0)

        attack = min(0.003,0.18*eventDur)

        t0$ = fixed$(t0,9)
        dur$ = fixed$(eventDur,9)
        attack$ = fixed$(max(1/sr,attack),9)
        age$ = "(x-" + t0$ + ")"

        # Fast rise, exponential decay, cosine terminal taper.
        env$ =
            ... "((1-exp(-" + age$ + "/" + attack$ + "))"
            ... + "*exp(-4.5*" + age$ + "/" + dur$ + ")"
            ... + "*(0.5+0.5*cos(pi*" + age$ + "/" + dur$ + ")))"

        leftTerms$ = "0"
        rightTerms$ = "0"

        polyphonyGain = 1/sqrt(activeBands)

        for yb from 1 to nYBands
            idx = (xb-1)*nYBands+yb

            if cellActive#[idx]
                f = cellFrequency#[idx]
                edge = cellEdge#[idx]
                strength = cellActivity#[idx]
                pan = cellPan#[idx]

                a2 = 0.38
                a3 = 0.10+0.28*edge
                a4 = 0.03+0.19*edge

                sourceNorm =
                    ... sqrt(2)/
                    ... sqrt(1+a2*a2+a3*a3+a4*a4)

                phase2 = 0.37*pi
                phase3 = 0.61*pi
                phase4 = 0.83*pi

                wave$ =
                    ... "(" + fixed$(sourceNorm,9)
                    ... + "*sin(2*pi*" + fixed$(f,6)
                    ... + "*" + age$ + ")"
                    ... + "+" + fixed$(sourceNorm*a2,9)
                    ... + "*sin(2*pi*" + fixed$(1.73*f,6)
                    ... + "*" + age$ + "+" + fixed$(phase2,9) + ")"
                    ... + "+" + fixed$(sourceNorm*a3,9)
                    ... + "*sin(2*pi*" + fixed$(2.37*f,6)
                    ... + "*" + age$ + "+" + fixed$(phase3,9) + ")"
                    ... + "+" + fixed$(sourceNorm*a4,9)
                    ... + "*sin(2*pi*" + fixed$(3.11*f,6)
                    ... + "*" + age$ + "+" + fixed$(phase4,9) + "))"

                amp =
                    ... master_amplitude*polyphonyGain*
                    ... strength

                gL = sqrt(1-pan)
                gR = sqrt(pan)

                leftTerms$ =
                    ... leftTerms$ + "+"
                    ... + fixed$(amp*gL,9)
                    ... + "*" + wave$ + "*" + env$

                rightTerms$ =
                    ... rightTerms$ + "+"
                    ... + fixed$(amp*gR,9)
                    ... + "*" + wave$ + "*" + env$
            endif
        endfor

        selectObject: outputSound
        Formula (part): t0,t1,1,2,
            ... "self+if row=1 then (" + leftTerms$
            ... + ") else (" + rightTerms$ + ") fi"
    endif
endfor

# ---------------------------------------------------------------------------
# SHORT COMMON FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
edgeFade = min(0.015,0.10*duration)
if edgeFade > 0
    fadeOutStart = duration-edgeFade

    selectObject: outputSound
    Formula:
        ... "if x<edgeFade then self*(x/edgeFade)"
        ... + " else if x>fadeOutStart then "
        ... + "self*((duration-x)/edgeFade)"
        ... + " else self fi fi"
endif

selectObject: outputSound
preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if peak_protection and preProtectPeak > 0.92
    Scale peak: 0.92
    protectionApplied = 1
endif

Rename: "Percussive_Image_" + uid$
outputSound = selected("Sound")

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0

# ---------------------------------------------------------------------------
# INFO / QC
# ---------------------------------------------------------------------------
appendInfoLine: ""
appendInfoLine: "=== MAPPING / REALIZATION ==="
appendInfoLine: "X bins -> fixed linear scan time: ", nXBins
appendInfoLine: "Vertical bands -> logarithmic pitch: ", nYBands
appendInfoLine: "Requested/effective pitch range: ",
    ... fixed$(minimum_pitch,1), "-", fixed$(maximum_pitch,1),
    ... " / ", fixed$(effectiveMinPitch,1), "-",
    ... fixed$(effectiveMaxPitch,1), " Hz"
appendInfoLine: "Common frequency scale: ",
    ... fixed$(frequencyScale,6)
appendInfoLine: "Mean luminance / normalized edge: ",
    ... fixed$(meanLuminance,4), " / ",
    ... fixed$(meanEdge,4)
appendInfoLine: "Audible cells: ", eventCount, " / ", numCells,
    ... " (", fixed$(100*activeCellFraction,1), "%)"
appendInfoLine: "Active X bins: ", activeColumns, " / ", nXBins
appendInfoLine: "Mean stereo pan coordinate: ",
    ... fixed$(meanPan,4), " (0=left, 1=right)"
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ",
    ... fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ",
    ... fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied

if eventCount = 0
    appendInfoLine: "QC: no cells exceeded Activity threshold; output is silent."
endif

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# RGB integral matrices no longer needed.
removeObject: redID,greenID,blueID

# ---------------------------------------------------------------------------
# PLAY / FINAL SELECTION
# ---------------------------------------------------------------------------
selectObject: outputSound
if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.82
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.82,0.82,0.84}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER / PROCESS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.34
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.56,"half",
        ... "PERCUSSIVE IMAGE SONIFICATION | " + photoName$

    Select inner viewport: 0.30,7.70,0.38,0.72
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.36}"
    Text: 0.5,"centre",0.70,"half",
        ... "Photo -> RGB integral grid -> luminance / contrast / R-B balance -> percussive events"
    Text: 0.5,"centre",0.20,"half",
        ... "X -> fixed time | vertical band -> log pitch | luminance -> strength | edge -> attack spectrum | R/B -> pan"

    # -----------------------------------------------------------------------
    # PANEL A: BINNED IMAGE LUMINANCE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.82,1.03
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "A  BINNED IMAGE DATA | luminance values actually used by the sonification"

    Select inner viewport: .left,.right,1.10,2.33
    Axes: 0,nXBins,0,nYBands

    for .xb from 1 to nXBins
        for .yb from 1 to nYBands
            .idx = (.xb-1)*nYBands+.yb
            .lum = cellLuminance#[.idx]
            .col$ =
                ... "{" + fixed$(.lum,3) + ","
                ... + fixed$(.lum,3) + ","
                ... + fixed$(.lum,3) + "}"

            Paint rectangle:
                ... .col$,
                ... .xb-1,.xb,.yb-1,.yb
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Marks left: min(6,nYBands),"yes","yes","no"
    Font size: 6
    Text left: "yes","Vertical image band"
    Text bottom: "yes","Horizontal scan bin"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL AUDIBLE EVENT FIELD
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.49,2.70
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "B  ACTUAL AUDIBLE EVENTS | time x pitch; colour shows red-left / blue-right pan"

    .logLo = ln(max(20,0.92*effectiveMinPitch))
    .logHi = ln(1.08*effectiveMaxPitch)

    Select inner viewport: .left,.right,2.77,3.82
    Axes: 0,duration,.logLo,.logHi
    Paint rectangle:
        ... "{0.055,0.055,0.065}",
        ... 0,duration,.logLo,.logHi

    .eventDrawStep =
        ... max(1,ceiling(max(1,eventCount)/1500))
    .drawn = 0

    for .xb from 1 to nXBins
        if nXBins = 1
            .t = 0
        else
            .t = (.xb-1)*scanStep
        endif

        for .yb from 1 to nYBands
            .idx = (.xb-1)*nYBands+.yb

            if cellActive#[.idx]
                .drawn = .drawn+1

                if ((.drawn-1) mod .eventDrawStep)=0
                    .pan = cellPan#[.idx]
                    .strength = cellActivity#[.idx]
                    .red = 0.15+0.78*(1-.pan)
                    .blue = 0.15+0.78*.pan
                    .green = 0.18

                    .col$ =
                        ... "{" + fixed$(.red,3) + ","
                        ... + fixed$(.green,3) + ","
                        ... + fixed$(.blue,3) + "}"

                    .size = 0.45+1.15*.strength

                    Paint circle (mm):
                        ... .col$,.t,
                        ... ln(cellFrequency#[.idx]),.size
                endif
            endif
        endfor
    endfor

    Colour: "White"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"

    .tick# = {50,100,200,500,1000,2000,5000,10000}
    Font size: 5
    for .k from 1 to 8
        .ff = .tick#[.k]

        if .ff >= exp(.logLo) and .ff <= exp(.logHi)
            Colour: "{0.55,0.55,0.58}"
            Draw line:
                ... 0,ln(.ff),0.012*duration,ln(.ff)

            Colour: "White"
            if .ff >= 1000
                .lab$ = fixed$(.ff/1000,0) + "k"
            else
                .lab$ = fixed$(.ff,0)
            endif

            Text:
                ... -0.012*duration,"right",
                ... ln(.ff),"half",.lab$
        endif
    endfor

    # -----------------------------------------------------------------------
    # PANEL C: X-SCAN DESCRIPTORS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.98,4.19
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "C  X-SCAN DESCRIPTORS | mean luminance, contrast and pan by horizontal bin"

    Select inner viewport: .left,.right,4.26,5.14
    Axes: 1,max(2,nXBins),0,1
    Paint rectangle:
        ... .bg$,1,max(2,nXBins),0,1

    .xDrawStep = max(1,ceiling(nXBins/1000))

    for .xb from 2 to nXBins
        if ((.xb-1) mod .xDrawStep)=0
            Colour: "{0.18,0.18,0.20}"
            Draw line:
                ... .xb-1,columnMeanLuminance#[.xb-1],
                ... .xb,columnMeanLuminance#[.xb]

            Colour: "{0.88,0.50,0.12}"
            Draw line:
                ... .xb-1,columnMeanEdge#[.xb-1],
                ... .xb,columnMeanEdge#[.xb]

            Colour: "{0.25,0.45,0.82}"
            Draw line:
                ... .xb-1,columnMeanPan#[.xb-1],
                ... .xb,columnMeanPan#[.xb]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Normalized value"
    Text: 1.02,"left",0.89,"half",
        ... "black luminance  |  orange edge  |  blue pan"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    selectObject: outputSound
    Extract one channel: 1
    .leftDisp = selected("Sound")
    .leftRms = Get root-mean-square: 0,0

    selectObject: outputSound
    Extract one channel: 2
    .rightDisp = selected("Sound")
    .rightRms = Get root-mean-square: 0,0

    if .rightRms > .leftRms
        removeObject: .leftDisp
        .disp = .rightDisp
    else
        removeObject: .rightDisp
        .disp = .leftDisp
    endif

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.30,5.51
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "D  MODEL -> MEASUREMENT | measured spectrogram + sampled actual event pitches"

    .specMax =
        ... min(safeTop,max(2500,
        ... 3.20*effectiveMaxPitch))
    .specStep = max(0.002,duration/1200)

    selectObject: .disp
    To Spectrogram:
        ... 0.020,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.58,6.53
    selectObject: .spec
    Paint:
        ... 0,0,0,.specMax,
        ... 100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration,0,.specMax
    Colour: "{0.10,0.72,0.90}"
    Line width: 0.55

    .guideStep =
        ... max(1,ceiling(max(1,eventCount)/220))
    .guideCount = 0

    for .xb from 1 to nXBins
        if nXBins = 1
            .t = 0
        else
            .t = (.xb-1)*scanStep
        endif

        for .yb from 1 to nYBands
            .idx = (.xb-1)*nYBands+.yb

            if cellActive#[.idx]
                .guideCount = .guideCount+1

                if ((.guideCount-1) mod .guideStep)=0
                    .f = cellFrequency#[.idx]
                    if .f <= .specMax
                        Draw line:
                            ... .t,.f,
                            ... min(duration,.t+hit_duration),
                            ... .f
                    endif
                endif
            endif
        endfor
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.72,7.84
    Axes: 0,1,0,1
    Paint rectangle:
        ... "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "MAPPING  |  X=time | Y=log pitch | luminance=strength | 2-D edge=upper partials | R/B=pan"

    Text: 0.02,"left",0.58,"half",
        ... "ACTIVITY  |  audible cells "
        ... + string$(eventCount) + "/" + string$(numCells)
        ... + " (" + fixed$(100*activeCellFraction,1) + "%)"
        ... + "  |  active X bins " + string$(activeColumns)
        ... + "/" + string$(nXBins)

    Text: 0.02,"left",0.36,"half",
        ... "SAMPLING  |  F " + fixed$(effectiveMinPitch,0)
        ... + "-" + fixed$(effectiveMaxPitch,0) + " Hz"
        ... + "  |  highest modeled partial "
        ... + fixed$(partialRatioMax*effectiveMaxPitch,0) + " Hz"
        ... + "  |  scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + "  |  RMS " + fixed$(preProtectRMS,4)
        ... + "  |  " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
