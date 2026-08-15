# ============================================================
# Praat AudioTools - Photo_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 conceptual + DSP review (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# PHOTO SONIFICATION: RGB SPECTRAL COLUMN SCAN
#
# CONCEPTUAL SCOPE
# ----------------
# This engine is intentionally a 1-D COLUMN-PROJECTION sonification of a 2-D
# Photo. Horizontal image position is preserved as musical time. The vertical
# dimension is deliberately collapsed by averaging a configurable set of
# vertical samples in each analyzed column.
#
# It therefore does NOT claim to preserve full 2-D image geometry. For a
# spatially explicit X/Y event mapping, use Percussive Image Sonification.
#
# Mapping:
#
#   image X position              -> time
#   vertical column projection    -> RGB + brightness control at that time
#   weighted RGB brightness       -> overall amplitude, ONCE
#   normalized RGB proportions    -> low/mid/high spectral energy distribution
#   red-vs-blue chromatic balance -> equal-power stereo pan
#
# BRIGHTNESS SEMANTICS
# --------------------
# v0.4 normalized every image with its own overall min/max and then multiplied
# the RGB-modulated signal by a second brightness envelope. Consequences:
#   - a spatially constant grey/white image could collapse toward silence
#   - neutral intensity k was approximately mapped to k^2 in amplitude
#
# v0.5 keeps an absolute black/white reference when the extracted Photo channels
# are in their expected normalized range. If a nonstandard range is detected,
# a clearly reported fallback input scaling is used.
#
# Weighted brightness proxy:
#
#   L = 0.2126 R + 0.7152 G + 0.0722 B
#
# This is used as a transparent Rec.709-like brightness weighting on the
# extracted Photo channels, not as a colour-managed photometric measurement.
#
# RGB controls spectral BALANCE rather than multiplying brightness a second time:
#
#   wR = sqrt(R / (R+G+B))
#   wG = sqrt(G / (R+G+B))
#   wB = sqrt(B / (R+G+B))
#
# With independently normalized noise bands, wR^2+wG^2+wB^2 ~= 1, so spectral
# colour changes do not automatically become large level changes. Overall
# amplitude is applied once through L.
#
# TEMPORAL INTERPOLATION
# ----------------------
# Every analyzed image column is stored as one sample in a low-rate control
# Sound. Audio-rate control is obtained with Praat's time-based object access,
# which linearly interpolates between adjacent Sound samples:
#
#   controlTime = 0.5 + (x/duration)*(analysisColumns-1)
#
# This removes the artificial hard steps/clicks created by v0.4's nearest-column
# lookup while preserving the exact first and last image-column controls.
#
# SPECTRAL SOURCE
# ---------------
# Low, mid and high bands use independent noise realizations. After Hann-band
# filtering, each is normalized to the SAME reference RMS before modulation.
# This prevents a wider frequency band from becoming louder simply because it
# contains more noise bandwidth.
#
# All six requested band edges receive one common frequency scale if the highest
# edge would exceed 0.45*Fs. Relative band geometry is therefore preserved.
#
# RANDOMNESS
# ----------
# Random_seed > 0 makes the noise realization reproducible. The image mapping
# itself is deterministic regardless of seed.
#
# VISUALIZATION
# -------------
#   A actual RGB column projections + luminance
#   B actual low/mid/high energy weights + pan
#   C measured spectrogram of the realized mono spectral mixture
#   D measured short-time RMS shape vs target luminance
#   mapping / spectral geometry / sampling / level QC
#
# v0.5 changes
# ------------
#   - explicit column-projection scope; no false claim of full 2-D sonification
#   - absolute brightness preserved for normalized Photo channel values
#   - brightness applied once, not squared by RGB x amplitude double modulation
#   - RGB becomes energy-normalized spectral balance
#   - independent, equal-RMS low/mid/high noise bands
#   - linear interpolation between analyzed columns
#   - conventional red-left / blue-right equal-power pan
#   - Random_seed for reproducible noise realization
#   - Nyquist-aware common scaling of all band edges
#   - short common edge fade
#   - final normalization replaced by down-only peak protection
#   - visualization rebuilt around actual controls and measured audio
# ============================================================

form Photo Sonification v0.5 - RGB Spectral Column Scan
    comment === Timing ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100

    comment === Column Projection ===
    integer Analysis_columns 160

    comment === Frequency Bands ===
    integer Low_band_min_Hz 100
    integer Low_band_max_Hz 800
    integer Mid_band_min_Hz 800
    integer Mid_band_max_Hz 3000
    integer High_band_min_Hz 3000
    integer High_band_max_Hz 9000

    comment === Mapping / Output ===
    real Master_amplitude 0.80
    real Colour_pan_strength 0.90
    integer Random_seed 0
    boolean Peak_protection 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# PHOTO / VALIDATION
# ---------------------------------------------------------------------------
nPhotos = numberOfSelected("Photo")
if nPhotos = 0
    exitScript: "Please select one Photo object first."
endif

photoID = selected("Photo")
photoName$ = selected$("Photo")

if duration_s <= 0 or duration_s > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if analysis_columns < 2 or analysis_columns > 1000
    exitScript: "Analysis columns must be between 2 and 1000."
endif
if low_band_min_Hz < 20 or low_band_max_Hz <= low_band_min_Hz
    exitScript: "Low band must satisfy 20 Hz <= minimum < maximum."
endif
if mid_band_min_Hz < 20 or mid_band_max_Hz <= mid_band_min_Hz
    exitScript: "Mid band must satisfy 20 Hz <= minimum < maximum."
endif
if high_band_min_Hz < 20 or high_band_max_Hz <= high_band_min_Hz
    exitScript: "High band must satisfy 20 Hz <= minimum < maximum."
endif
if master_amplitude <= 0 or master_amplitude > 2
    exitScript: "Master amplitude must be > 0 and <= 2."
endif
if colour_pan_strength < 0 or colour_pan_strength > 1
    exitScript: "Colour pan strength must be between 0 and 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif

sr = sample_rate_Hz
safeTop = 0.45*sr
requestedTop = max(low_band_max_Hz,max(mid_band_max_Hz,high_band_max_Hz))
frequencyScale = min(1,safeTop/requestedTop)

lowMin = low_band_min_Hz*frequencyScale
lowMax = low_band_max_Hz*frequencyScale
midMin = mid_band_min_Hz*frequencyScale
midMax = mid_band_max_Hz*frequencyScale
highMin = high_band_min_Hz*frequencyScale
highMax = high_band_max_Hz*frequencyScale

if min(lowMin,min(midMin,highMin)) < 20
    exitScript: "Nyquist scaling would move a band edge below 20 Hz. Lower the requested upper band edge or raise the lower edges."
endif

lowSmooth = max(5,min(100,0.20*(lowMax-lowMin)))
midSmooth = max(5,min(100,0.20*(midMax-midMin)))
highSmooth = max(5,min(100,0.20*(highMax-highMin)))

# ---------------------------------------------------------------------------
# RANDOMNESS
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# RGB MATRICES
# ---------------------------------------------------------------------------
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

if imgRows < 1 or imgCols < 1
    removeObject: redID,greenID,blueID
    exitScript: "Invalid Photo dimensions."
endif

analysisColumns = min(analysis_columns,imgCols)

# ---------------------------------------------------------------------------
# DETECT INPUT CHANNEL SCALE
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

rawMin = min(minRed,min(minGreen,minBlue))
rawMax = max(maxRed,max(maxGreen,maxBlue))

if rawMin >= -0.000001 and rawMax <= 1.000001
    inputBlack = 0
    inputWhite = 1
    inputScaling$ = "fixed normalized 0..1"

elsif rawMin >= -0.000001 and rawMax <= 255.000001
    inputBlack = 0
    inputWhite = 255
    inputScaling$ = "fixed byte-like 0..255 fallback"

else
    inputBlack = rawMin
    inputWhite = rawMax
    if inputWhite <= inputBlack
        inputWhite = inputBlack+1
    endif
    inputScaling$ = "observed-range fallback (nonstandard Photo values)"
endif

inputRange = inputWhite-inputBlack

# ---------------------------------------------------------------------------
# EXACT HORIZONTAL-BIN PROJECTION VIA 2-D INTEGRAL IMAGES
# ---------------------------------------------------------------------------
# The original matrices are converted in place to cumulative sums. First each
# row is integrated left-to-right, then rows are accumulated top-to-bottom.
# A full-height horizontal-bin sum can then be obtained from two bottom-row
# integral values. This replaces sparse vertical sampling and centre-column
# picking with an exact average over every pixel in each horizontal bin.
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
# COLUMN-PROJECTION FEATURES
# ---------------------------------------------------------------------------
redCol# = zero#(analysisColumns)
greenCol# = zero#(analysisColumns)
blueCol# = zero#(analysisColumns)
luminanceCol# = zero#(analysisColumns)
redWeight# = zero#(analysisColumns)
greenWeight# = zero#(analysisColumns)
blueWeight# = zero#(analysisColumns)
panCol# = zero#(analysisColumns)

meanLum = 0
meanPan = 0
minLum = 1e12
maxLum = -1e12

for aCol from 1 to analysisColumns
    c1 = floor((aCol-1)*imgCols/analysisColumns)+1
    c2 = floor(aCol*imgCols/analysisColumns)
    c2 = max(c1,c2)

    area = imgRows*(c2-c1+1)

    redSum = object[redID,imgRows,c2]
    greenSum = object[greenID,imgRows,c2]
    blueSum = object[blueID,imgRows,c2]

    if c1 > 1
        redSum = redSum-object[redID,imgRows,c1-1]
        greenSum = greenSum-object[greenID,imgRows,c1-1]
        blueSum = blueSum-object[blueID,imgRows,c1-1]
    endif

    rRaw = redSum/area
    gRaw = greenSum/area
    bRaw = blueSum/area

    r = max(0,min(1,(rRaw-inputBlack)/inputRange))
    g = max(0,min(1,(gRaw-inputBlack)/inputRange))
    b = max(0,min(1,(bRaw-inputBlack)/inputRange))

    lum = 0.2126*r+0.7152*g+0.0722*b

    colourSum = r+g+b
    if colourSum > 1e-12
        wR = sqrt(r/colourSum)
        wG = sqrt(g/colourSum)
        wB = sqrt(b/colourSum)
    else
        wR = 0
        wG = 0
        wB = 0
    endif

    rbDen = max(0.08,r+b)
    redBlueBalance = (b-r)/rbDen
    pan =
        ... 0.5+0.48*colour_pan_strength*redBlueBalance
    pan = max(0.02,min(0.98,pan))

    redCol#[aCol] = r
    greenCol#[aCol] = g
    blueCol#[aCol] = b
    luminanceCol#[aCol] = lum
    redWeight#[aCol] = wR
    greenWeight#[aCol] = wG
    blueWeight#[aCol] = wB
    panCol#[aCol] = pan

    meanLum = meanLum+lum/analysisColumns
    meanPan = meanPan+pan/analysisColumns
    minLum = min(minLum,lum)
    maxLum = max(maxLum,lum)
endfor

# ---------------------------------------------------------------------------
# CONTROL SOUNDS: ONE SAMPLE PER IMAGE COLUMN
# ---------------------------------------------------------------------------
# Their time domain is analysisColumns seconds at 1 Hz; sample centres are
# 0.5, 1.5, ... analysisColumns-0.5. Output time x is mapped exactly between
# the first and last centres, and function-style object access interpolates.
redControl = Create Sound from formula:
    ... "photo_red_control_" + uid$,
    ... 1,0,analysisColumns,1,"0"

greenControl = Create Sound from formula:
    ... "photo_green_control_" + uid$,
    ... 1,0,analysisColumns,1,"0"

blueControl = Create Sound from formula:
    ... "photo_blue_control_" + uid$,
    ... 1,0,analysisColumns,1,"0"

lumControl = Create Sound from formula:
    ... "photo_luminance_control_" + uid$,
    ... 1,0,analysisColumns,1,"0"

redWeightControl = Create Sound from formula:
    ... "photo_red_weight_" + uid$,
    ... 1,0,analysisColumns,1,"0"

greenWeightControl = Create Sound from formula:
    ... "photo_green_weight_" + uid$,
    ... 1,0,analysisColumns,1,"0"

blueWeightControl = Create Sound from formula:
    ... "photo_blue_weight_" + uid$,
    ... 1,0,analysisColumns,1,"0"

panControl = Create Sound from formula:
    ... "photo_pan_control_" + uid$,
    ... 1,0,analysisColumns,1,"0"

for aCol from 1 to analysisColumns
    selectObject: redControl
    Set value at sample number: 1,aCol,redCol#[aCol]

    selectObject: greenControl
    Set value at sample number: 1,aCol,greenCol#[aCol]

    selectObject: blueControl
    Set value at sample number: 1,aCol,blueCol#[aCol]

    selectObject: lumControl
    Set value at sample number: 1,aCol,luminanceCol#[aCol]

    selectObject: redWeightControl
    Set value at sample number: 1,aCol,redWeight#[aCol]

    selectObject: greenWeightControl
    Set value at sample number: 1,aCol,greenWeight#[aCol]

    selectObject: blueWeightControl
    Set value at sample number: 1,aCol,blueWeight#[aCol]

    selectObject: panControl
    Set value at sample number: 1,aCol,panCol#[aCol]
endfor

# Exact output-time -> control-time map.
if analysisColumns > 1
    controlSlope = (analysisColumns-1)/duration_s
else
    controlSlope = 0
endif

controlTimeExpr$ =
    ... "(0.5+x*" + fixed$(controlSlope,12) + ")"

redWeightId$ = string$(redWeightControl)
greenWeightId$ = string$(greenWeightControl)
blueWeightId$ = string$(blueWeightControl)
lumId$ = string$(lumControl)
panId$ = string$(panControl)

# ---------------------------------------------------------------------------
# INDEPENDENT, EQUAL-RMS FILTERED NOISE BANDS
# ---------------------------------------------------------------------------
bandReferenceRMS = 0.18

lowSource = Create Sound from formula:
    ... "photo_low_source_" + uid$,
    ... 1,0,duration_s,sr,"randomUniform(-1,1)"

selectObject: lowSource
Filter (pass Hann band): lowMin,lowMax,lowSmooth
lowNoise = selected("Sound")
Rename: "photo_low_band_" + uid$
removeObject: lowSource

lowRms = Get root-mean-square: 0,0
if lowRms > 1e-12
    Formula: "self*" + fixed$(bandReferenceRMS/lowRms,12)
endif

midSource = Create Sound from formula:
    ... "photo_mid_source_" + uid$,
    ... 1,0,duration_s,sr,"randomUniform(-1,1)"

selectObject: midSource
Filter (pass Hann band): midMin,midMax,midSmooth
midNoise = selected("Sound")
Rename: "photo_mid_band_" + uid$
removeObject: midSource

midRms = Get root-mean-square: 0,0
if midRms > 1e-12
    Formula: "self*" + fixed$(bandReferenceRMS/midRms,12)
endif

highSource = Create Sound from formula:
    ... "photo_high_source_" + uid$,
    ... 1,0,duration_s,sr,"randomUniform(-1,1)"

selectObject: highSource
Filter (pass Hann band): highMin,highMax,highSmooth
highNoise = selected("Sound")
Rename: "photo_high_band_" + uid$
removeObject: highSource

highRms = Get root-mean-square: 0,0
if highRms > 1e-12
    Formula: "self*" + fixed$(bandReferenceRMS/highRms,12)
endif

lowId$ = string$(lowNoise)
midId$ = string$(midNoise)
highId$ = string$(highNoise)

# Random realization is now fully generated.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# MONO SPECTRAL MIXTURE
# ---------------------------------------------------------------------------
# Brightness is applied ONCE through luminance. RGB controls only the
# energy-normalized spectral distribution.
combinedMono = Create Sound from formula:
    ... "photo_spectral_mix_" + uid$,
    ... 1,0,duration_s,sr,
    ... fixed$(master_amplitude,9)
    ... + "*object(" + lumId$ + "," + controlTimeExpr$ + ",1)"
    ... + "*(object(" + redWeightId$ + "," + controlTimeExpr$ + ",1)"
    ... + "*object[" + lowId$ + ",1,col]"
    ... + "+object(" + greenWeightId$ + "," + controlTimeExpr$ + ",1)"
    ... + "*object[" + midId$ + ",1,col]"
    ... + "+object(" + blueWeightId$ + "," + controlTimeExpr$ + ",1)"
    ... + "*object[" + highId$ + ",1,col])"

combinedId$ = string$(combinedMono)

# ---------------------------------------------------------------------------
# EQUAL-POWER STEREO PAN
# ---------------------------------------------------------------------------
leftSound = Create Sound from formula:
    ... "photo_left_" + uid$,
    ... 1,0,duration_s,sr,
    ... "sqrt(max(0,1-object(" + panId$ + ","
    ... + controlTimeExpr$ + ",1)))*object["
    ... + combinedId$ + ",1,col]"

rightSound = Create Sound from formula:
    ... "photo_right_" + uid$,
    ... 1,0,duration_s,sr,
    ... "sqrt(max(0,object(" + panId$ + ","
    ... + controlTimeExpr$ + ",1)))*object["
    ... + combinedId$ + ",1,col]"

selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "Photo_Sonification_" + photoName$
outputSound = selected("Sound")

# ---------------------------------------------------------------------------
# SHORT COMMON EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
edgeFade = min(0.02,0.10*duration_s)
if edgeFade > 0
    fadeOutStart = duration_s-edgeFade

    selectObject: outputSound
    Formula:
        ... "if x<edgeFade then self*(x/edgeFade)"
        ... + " else if x>fadeOutStart then "
        ... + "self*((duration_s-x)/edgeFade)"
        ... + " else self fi fi"

    selectObject: combinedMono
    Formula:
        ... "if x<edgeFade then self*(x/edgeFade)"
        ... + " else if x>fadeOutStart then "
        ... + "self*((duration_s-x)/edgeFade)"
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

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0

# ---------------------------------------------------------------------------
# INFO / QC
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  PHOTO SONIFICATION v0.5"
writeInfoLine: "=============================================="
appendInfoLine: "Photo: ", photoName$
appendInfoLine: "Scope: 1-D column projection; full image height intentionally averaged within each horizontal bin"
appendInfoLine: "Image: ", imgCols, " x ", imgRows
appendInfoLine: "Analysis: ", analysisColumns,
    ... " horizontal bins; each bin averages the full image height"
appendInfoLine: "Input scaling: ", inputScaling$
appendInfoLine: "Raw RGB range: ",
    ... fixed$(rawMin,6), " to ", fixed$(rawMax,6)
appendInfoLine: "Luminance range / mean: ",
    ... fixed$(minLum,4), " - ", fixed$(maxLum,4),
    ... " / ", fixed$(meanLum,4)
appendInfoLine: "Mean pan coordinate: ",
    ... fixed$(meanPan,4), " (0=left, 1=right)"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: ""
appendInfoLine: "Requested frequency scale: ",
    ... fixed$(frequencyScale,6)
appendInfoLine: "Low band: ",
    ... fixed$(lowMin,1), "-", fixed$(lowMax,1), " Hz"
appendInfoLine: "Mid band: ",
    ... fixed$(midMin,1), "-", fixed$(midMax,1), " Hz"
appendInfoLine: "High band: ",
    ... fixed$(highMin,1), "-", fixed$(highMax,1), " Hz"
appendInfoLine: "Band source reference RMS: ",
    ... fixed$(bandReferenceRMS,4)
appendInfoLine: "Brightness mapping: perceptual brightness applied once"
appendInfoLine: "RGB mapping: sqrt energy weights; wR^2+wG^2+wB^2 = 1 for nonblack columns"
appendInfoLine: "Temporal control: linear interpolation between analyzed columns"
appendInfoLine: ""
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ",
    ... fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ",
    ... fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied

# ---------------------------------------------------------------------------
# VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------------------------
removeObject: redID,greenID,blueID
removeObject:
    ... redControl,greenControl,blueControl,lumControl,
    ... redWeightControl,greenWeightControl,blueWeightControl,panControl
removeObject: lowNoise,midNoise,highNoise
removeObject: combinedMono,leftSound,rightSound

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
    .red$ = "{0.82,0.20,0.20}"
    .green$ = "{0.15,0.62,0.24}"
    .blue$ = "{0.18,0.34,0.84}"
    .dark$ = "{0.15,0.15,0.17}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "PHOTO SONIFICATION | RGB spectral column scan | " + photoName$

    Select inner viewport: 0.32,7.68,0.37,0.72
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.36}"
    Text: 0.5,"centre",0.70,"half",
        ... "image X -> time | full-height projection -> RGB/L | L -> amplitude | RGB proportions -> spectrum | R/B -> pan"
    Text: 0.5,"centre",0.20,"half",
        ... "continuous spectral scan; this engine intentionally averages the image Y dimension"

    # -----------------------------------------------------------------------
    # PANEL A: RGB + LUMINANCE COLUMN PROJECTIONS
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.83,1.04
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "A  ACTUAL COLUMN PROJECTION | full-height RGB means and weighted brightness"

    Select inner viewport: .left,.right,1.11,2.26
    Axes: 0,duration_s,0,1
    Paint rectangle: .bg$,0,duration_s,0,1

    Colour: .grid$
    Dotted line
    Draw line: 0,0.25,duration_s,0.25
    Draw line: 0,0.50,duration_s,0.50
    Draw line: 0,0.75,duration_s,0.75
    Plain line

    for .c from 2 to analysisColumns
        .ta = duration_s*(.c-2)/(analysisColumns-1)
        .tb = duration_s*(.c-1)/(analysisColumns-1)

        Colour: .red$
        Draw line:
            ... .ta,redCol#[.c-1],
            ... .tb,redCol#[.c]

        Colour: .green$
        Draw line:
            ... .ta,greenCol#[.c-1],
            ... .tb,greenCol#[.c]

        Colour: .blue$
        Draw line:
            ... .ta,blueCol#[.c-1],
            ... .tb,blueCol#[.c]

        Colour: .dark$
        Line width: 1.4
        Draw line:
            ... .ta,luminanceCol#[.c-1],
            ... .tb,luminanceCol#[.c]
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Normalized value"
    Text: 0.02*duration_s,"left",0.94,"half",
        ... "red R | green G | blue B | black weighted brightness"

    # -----------------------------------------------------------------------
    # PANEL B: ENERGY WEIGHTS + PAN
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.42,2.63
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "B  AUDIO CONTROL | RGB energy weights and red-left / blue-right pan"

    Select inner viewport: .left,.right,2.70,3.72
    Axes: 0,duration_s,0,1
    Paint rectangle: .bg$,0,duration_s,0,1

    Colour: .grid$
    Dotted line
    Draw line: 0,0.5,duration_s,0.5
    Plain line

    for .c from 2 to analysisColumns
        .ta = duration_s*(.c-2)/(analysisColumns-1)
        .tb = duration_s*(.c-1)/(analysisColumns-1)

        Colour: .red$
        Draw line:
            ... .ta,redWeight#[.c-1],
            ... .tb,redWeight#[.c]

        Colour: .green$
        Draw line:
            ... .ta,greenWeight#[.c-1],
            ... .tb,greenWeight#[.c]

        Colour: .blue$
        Draw line:
            ... .ta,blueWeight#[.c-1],
            ... .tb,blueWeight#[.c]

        Colour: .dark$
        Line width: 1.4
        Draw line:
            ... .ta,panCol#[.c-1],
            ... .tb,panCol#[.c]
        Line width: 1
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Weight / pan"
    Text: 0.02*duration_s,"left",0.94,"half",
        ... "R/G/B sqrt-energy weights | black pan (0 left, 1 right)"

    # -----------------------------------------------------------------------
    # PANEL C: MEASURED SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.88,4.09
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "C  MODEL -> MEASUREMENT | measured mono spectral mixture + requested band geometry"

    .specMax = min(safeTop,max(1200,1.10*highMax))
    .specStep = max(0.002,duration_s/1200)

    selectObject: combinedMono
    To Spectrogram: 0.030,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,4.16,5.38
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Dotted line
    Line width: 0.65

    Colour: "{0.95,0.40,0.40}"
    Draw line: 0,lowMin,duration_s,lowMin
    Draw line: 0,lowMax,duration_s,lowMax

    Colour: "{0.45,0.95,0.50}"
    Draw line: 0,midMin,duration_s,midMin
    Draw line: 0,midMax,duration_s,midMax

    Colour: "{0.45,0.60,1.00}"
    Draw line: 0,highMin,duration_s,highMin
    Draw line: 0,highMax,duration_s,highMax

    Plain line
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Frequency (Hz)"

    # -----------------------------------------------------------------------
    # PANEL D: TARGET LUMINANCE VS MEASURED RMS SHAPE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.54,5.75
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "D  BRIGHTNESS VALIDATION | target weighted brightness vs measured mono RMS shape"

    .rms# = zero#(analysisColumns)
    .rmsMax = 0

    selectObject: combinedMono
    for .c from 1 to analysisColumns
        .t0 = duration_s*(.c-1)/analysisColumns
        .t1 = duration_s*.c/analysisColumns
        .rv = Get root-mean-square: .t0,.t1
        .rms#[.c] = .rv
        .rmsMax = max(.rmsMax,.rv)
    endfor

    Select inner viewport: .left,.right,5.82,6.72
    Axes: 0,duration_s,0,1
    Paint rectangle: .bg$,0,duration_s,0,1

    Colour: .grid$
    Dotted line
    Draw line: 0,0.5,duration_s,0.5
    Plain line

    for .c from 2 to analysisColumns
        .ta = duration_s*(.c-1.5)/analysisColumns
        .tb = duration_s*(.c-0.5)/analysisColumns

        Colour: .dark$
        .targetA = luminanceCol#[.c-1]
        .targetB = luminanceCol#[.c]
        Draw line: .ta,.targetA,.tb,.targetB

        if .rmsMax > 1e-12
            .measuredA = .rms#[.c-1]/.rmsMax
            .measuredB = .rms#[.c]/.rmsMax

            Colour: "{0.86,0.42,0.14}"
            Draw line:
                ... .ta,.measuredA,
                ... .tb,.measuredB
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Normalized shape"
    Text bottom: "yes","Time (s)"
    Text: 0.02*duration_s,"left",0.93,"half",
        ... "black target brightness | orange measured RMS (shape-normalized)"

    # -----------------------------------------------------------------------
    # SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.94,7.84
    Axes: 0,1,0,1
    Paint rectangle:
        ... "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.77,"half",
        ... "SCOPE  |  1-D column projection: X preserved as time; Y intentionally averaged"

    Text: 0.02,"left",0.53,"half",
        ... "MAPPING  |  brightness " + fixed$(minLum,3)
        ... + "-" + fixed$(maxLum,3)
        ... + " -> amplitude once | RGB -> energy-normalized bands | mean pan "
        ... + fixed$(meanPan,3)

    Text: 0.02,"left",0.29,"half",
        ... "BANDS  |  low " + fixed$(lowMin,0) + "-"
        ... + fixed$(lowMax,0) + " | mid " + fixed$(midMin,0) + "-"
        ... + fixed$(midMax,0) + " | high " + fixed$(highMin,0)
        ... + "-" + fixed$(highMax,0) + " Hz | scale "
        ... + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.08,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preProtectPeak,3)
        ... + " | RMS " + fixed$(preProtectRMS,4)
        ... + " | " + seedLabel$ + " | " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
