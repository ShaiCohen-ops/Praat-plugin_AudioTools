# ============================================================
# Praat AudioTools - Photo_Brightness-Controlled_Pitch_Sonification.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 runtime fix (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# PHOTO BRIGHTNESS-CONTROLLED PITCH SONIFICATION
#
# CONCEPTUAL SCOPE
# ----------------
# This engine is intentionally a MONOPHONIC COLUMN-PROJECTION sonification.
# The image horizontal axis is preserved as time. The vertical axis is
# intentionally collapsed by averaging the complete height of each horizontal
# analysis bin. It therefore does not claim to preserve full 2-D geometry.
#
# Mapping:
#
#   image X position               -> time
#   full-height RGB column average -> weighted brightness + colour balance
#   weighted brightness            -> instantaneous pitch
#   red-vs-blue balance            -> equal-power stereo pan
#
# BRIGHTNESS
# ----------
# v0.3 normalized every image by its own RGB minimum and maximum. As a result,
# a spatially uniform white/grey image had zero normalized contrast and could
# map to the minimum pitch. v0.4 preserves an absolute black/white reference
# whenever the extracted Photo channels are in their expected normalized range.
# A clearly reported fallback scaling is used only for nonstandard values.
#
# Weighted brightness proxy:
#
#   B = 0.2126 R + 0.7152 G + 0.0722 B_blue
#
# This is a transparent Rec.709-like weighting of the extracted channel values;
# it is not claimed as a colour-managed photometric luminance measurement.
#
# PITCH MAPPING
# -------------
# The default is logarithmic frequency mapping:
#
#   f = f_min * (f_max/f_min)^B
#
# so equal brightness increments correspond to equal musical intervals.
# Optional linear-Hz mapping is retained for experiments where literal Hz
# proportionality is preferred.
#
# TEMPORAL CONTINUITY
# -------------------
# Each image bin is stored as one sample in a low-rate control Sound. Praat's
# time-based Sound access linearly interpolates between adjacent control samples.
# The interpolated brightness is mapped to instantaneous frequency, then phase is
# integrated sample-by-sample at the audio sampling rate:
#
#   phi[n] = phi[n-1] + 2*pi*f[n]/Fs
#
# This is true phase-continuous variable-frequency synthesis. No smoothing filter
# is required and the requested endpoint mapping is not blurred by a low-pass.
#
# IMAGE ANALYSIS
# --------------
# RGB matrices are converted to 2-D integral images. Each horizontal analysis
# bin then averages EVERY pixel over its complete height and X extent using two
# bottom-row cumulative values. This avoids centre-column / sparse-row sampling.
#
# LEVEL SEMANTICS
# ---------------
# Brightness controls pitch only. It does not also control amplitude. Output
# amplitude is set by Master_amplitude, preserving a one-parameter/one-dimension
# mapping. Final peak protection is down-only and therefore does not erase the
# user's level setting.
#
# v0.4.1 runtime fix
# ------------------
#   - Fixed object lifecycle after phaseSound is renamed to the mono
#     oscillator. Rename preserves the object ID, so deleting phaseSound
#     at that point also deleted monoSound before stereo rendering.
#   - The mono oscillator now remains alive until the normal cleanup.
#   - No mapping, synthesis or visualization semantics changed.
#
# v0.4 changes
# ------------
#   - absolute brightness reference instead of per-image contrast normalization
#   - exact full-height horizontal-bin averages via integral images
#   - logarithmic pitch mapping by default; optional linear-Hz mapping
#   - control interpolation rather than stepped lookup + Hann smoothing
#   - true audio-rate phase integration using object IDs
#   - corrected Formula control syntax uses if ... then ... else ... fi
#   - conventional red-left / blue-right equal-power pan
#   - common Nyquist headroom scaling of min/max pitch
#   - added Master amplitude and down-only peak protection
#   - visualization rebuilt around actual mapping and measured audio
# ============================================================

form: "Photo Brightness-Controlled Pitch Sonification v0.4.1"
    comment: "=== Timing ==="
    positive: "Duration (s)", "3.0"
    integer: "Sample rate (Hz)", "44100"

    comment: "=== Pitch Mapping ==="
    positive: "Minimum pitch (Hz)", "100"
    positive: "Maximum pitch (Hz)", "1000"
    boolean: "Logarithmic pitch mapping", 1

    comment: "=== Image Analysis ==="
    integer: "Analysis columns", "200"

    comment: "=== Output ==="
    real: "Master amplitude", "0.55"
    real: "Colour pan strength (0..1)", "0.90"
    boolean: "Peak protection", 1
    boolean: "Draw visualization", 1
    boolean: "Play result", 1
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

if duration <= 0 or duration > 180
    exitScript: "Duration must be > 0 and <= 180 seconds."
endif
if sample_rate < 8000 or sample_rate > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if minimum_pitch < 20 or maximum_pitch <= minimum_pitch
    exitScript: "Pitch range must satisfy 20 Hz <= minimum < maximum."
endif
if analysis_columns < 2 or analysis_columns > 2000
    exitScript: "Analysis columns must be between 2 and 2000."
endif
if master_amplitude <= 0 or master_amplitude > 2
    exitScript: "Master amplitude must be > 0 and <= 2."
endif
if colour_pan_strength < 0 or colour_pan_strength > 1
    exitScript: "Colour pan strength must be between 0 and 1."
endif

sr = sample_rate
safeTop = 0.45*sr
frequencyScale = min(1,safeTop/maximum_pitch)
effectiveMinPitch = minimum_pitch*frequencyScale
effectiveMaxPitch = maximum_pitch*frequencyScale

if effectiveMinPitch < 20
    exitScript: "Nyquist scaling would move the minimum pitch below 20 Hz. Reduce Maximum pitch or raise Minimum pitch."
endif

if logarithmic_pitch_mapping
    mappingName$ = "Logarithmic pitch interval"
else
    mappingName$ = "Linear Hz"
endif

pitchSpanSemitones = 12*ln(effectiveMaxPitch/effectiveMinPitch)/ln(2)
uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# EXTRACT RGB MATRICES
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
# INPUT CHANNEL SCALE
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
# 2-D INTEGRAL IMAGES
# ---------------------------------------------------------------------------
# Formula modification proceeds through already-modified previous cells, so
# these two passes create cumulative sums in X and then Y.
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
# EXACT FULL-HEIGHT HORIZONTAL-BIN FEATURES
# ---------------------------------------------------------------------------
redCol# = zero#(analysisColumns)
greenCol# = zero#(analysisColumns)
blueCol# = zero#(analysisColumns)
brightness# = zero#(analysisColumns)
pan# = zero#(analysisColumns)
freq# = zero#(analysisColumns)

minBrightness = 1e12
maxBrightness = -1e12
meanBrightness = 0
meanPan = 0
minFreq = 1e12
maxFreq = 0

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

    weightedBrightness = 0.2126*r+0.7152*g+0.0722*b

    rbDen = max(0.08,r+b)
    redBlueBalance = (b-r)/rbDen
    stereoPan = 0.5+0.48*colour_pan_strength*redBlueBalance
    stereoPan = max(0.02,min(0.98,stereoPan))

    if logarithmic_pitch_mapping
        mappedFreq = effectiveMinPitch*
            ... (effectiveMaxPitch/effectiveMinPitch)^weightedBrightness
    else
        mappedFreq = effectiveMinPitch+
            ... weightedBrightness*(effectiveMaxPitch-effectiveMinPitch)
    endif

    redCol#[aCol] = r
    greenCol#[aCol] = g
    blueCol#[aCol] = b
    brightness#[aCol] = weightedBrightness
    pan#[aCol] = stereoPan
    freq#[aCol] = mappedFreq

    minBrightness = min(minBrightness,weightedBrightness)
    maxBrightness = max(maxBrightness,weightedBrightness)
    meanBrightness = meanBrightness+weightedBrightness/analysisColumns
    meanPan = meanPan+stereoPan/analysisColumns
    minFreq = min(minFreq,mappedFreq)
    maxFreq = max(maxFreq,mappedFreq)
endfor

# ---------------------------------------------------------------------------
# LOW-RATE CONTROL SOUNDS
# ---------------------------------------------------------------------------
# One control sample per image bin. Their sample centres are 0.5, 1.5, ...;
# output time is mapped exactly between first and last control sample centres.
brightnessControl = Create Sound from formula:
    ... "photo_pitch_brightness_" + uid$,
    ... 1,0,analysisColumns,1,"0"

panControl = Create Sound from formula:
    ... "photo_pitch_pan_" + uid$,
    ... 1,0,analysisColumns,1,"0"

for aCol from 1 to analysisColumns
    selectObject: brightnessControl
    Set value at sample number: 1,aCol,brightness#[aCol]

    selectObject: panControl
    Set value at sample number: 1,aCol,pan#[aCol]
endfor

controlSlope = (analysisColumns-1)/duration
controlTimeExpr$ = "(0.5+x*" + fixed$(controlSlope,12) + ")"
brightnessId$ = string$(brightnessControl)
panId$ = string$(panControl)

# ---------------------------------------------------------------------------
# AUDIO-RATE INSTANTANEOUS FREQUENCY
# ---------------------------------------------------------------------------
if logarithmic_pitch_mapping
    frequencyFormula$ = fixed$(effectiveMinPitch,12)
        ... + "*(" + fixed$(effectiveMaxPitch/effectiveMinPitch,12)
        ... + ")^object(" + brightnessId$ + ","
        ... + controlTimeExpr$ + ",1)"
else
    frequencyFormula$ = fixed$(effectiveMinPitch,12)
        ... + "+" + fixed$(effectiveMaxPitch-effectiveMinPitch,12)
        ... + "*object(" + brightnessId$ + ","
        ... + controlTimeExpr$ + ",1)"
endif

frequencyAudio = Create Sound from formula:
    ... "photo_pitch_frequency_" + uid$,
    ... 1,0,duration,sr,frequencyFormula$

frequencyId$ = string$(frequencyAudio)

# ---------------------------------------------------------------------------
# TRUE AUDIO-RATE PHASE INTEGRATION
# ---------------------------------------------------------------------------
phaseSound = Create Sound from formula:
    ... "photo_pitch_phase_" + uid$,
    ... 1,0,duration,sr,"0"

phaseIncrement = 2*pi/sr
selectObject: phaseSound
Formula:
    ... "if col=1 then " + fixed$(phaseIncrement,16)
    ... + "*object[" + frequencyId$ + ",1,col]"
    ... + " else self[col-1]+" + fixed$(phaseIncrement,16)
    ... + "*object[" + frequencyId$ + ",1,col] fi"

Formula: fixed$(master_amplitude,12) + "*sin(self)"
Rename: "photo_pitch_mono_" + uid$
# Rename keeps the same Praat object ID: phaseSound and monoSound therefore
# refer to the same Sound object here. Do NOT delete phaseSound at this point.
monoSound = selected("Sound")
monoId$ = string$(monoSound)

# ---------------------------------------------------------------------------
# EQUAL-POWER STEREO PAN
# ---------------------------------------------------------------------------
leftSound = Create Sound from formula:
    ... "photo_pitch_left_" + uid$,
    ... 1,0,duration,sr,
    ... "sqrt(max(0,1-object(" + panId$ + ","
    ... + controlTimeExpr$ + ",1)))*object["
    ... + monoId$ + ",1,col]"

rightSound = Create Sound from formula:
    ... "photo_pitch_right_" + uid$,
    ... 1,0,duration,sr,
    ... "sqrt(max(0,object(" + panId$ + ","
    ... + controlTimeExpr$ + ",1)))*object["
    ... + monoId$ + ",1,col]"

selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "Brightness_Pitch_" + photoName$
outputSound = selected("Sound")

# ---------------------------------------------------------------------------
# SHORT COMMON EDGE FADE / FINAL LEVEL
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

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0

# ---------------------------------------------------------------------------
# INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  PHOTO BRIGHTNESS-CONTROLLED PITCH v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Photo: ", photoName$
appendInfoLine: "Scope: monophonic column projection; full image height intentionally averaged"
appendInfoLine: "Image dimensions: ", imgCols, " x ", imgRows
appendInfoLine: "Analysis columns: ", analysisColumns
appendInfoLine: "Input scaling: ", inputScaling$
appendInfoLine: "Raw RGB range: ", fixed$(rawMin,6), " to ", fixed$(rawMax,6)
appendInfoLine: "Weighted brightness min/mean/max: ",
    ... fixed$(minBrightness,4), " / ", fixed$(meanBrightness,4),
    ... " / ", fixed$(maxBrightness,4)
appendInfoLine: "Pitch mapping: ", mappingName$
appendInfoLine: "Requested/effective pitch range: ",
    ... fixed$(minimum_pitch,2), "-", fixed$(maximum_pitch,2),
    ... " / ", fixed$(effectiveMinPitch,2), "-", fixed$(effectiveMaxPitch,2), " Hz"
appendInfoLine: "Realized pitch range: ",
    ... fixed$(minFreq,2), " - ", fixed$(maxFreq,2), " Hz"
appendInfoLine: "Pitch span: ", fixed$(pitchSpanSemitones,2), " semitones"
appendInfoLine: "Frequency scale: ", fixed$(frequencyScale,6)
appendInfoLine: "Mean pan: ", fixed$(meanPan,4), " (0=left, 1=right)"
appendInfoLine: "Master amplitude: ", fixed$(master_amplitude,4)
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
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
removeObject: brightnessControl,panControl,frequencyAudio
removeObject: monoSound,leftSound,rightSound

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
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.88,0.43,0.14}"
    .red$ = "{0.82,0.20,0.20}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "PHOTO BRIGHTNESS -> PITCH | " + photoName$

    Select inner viewport: 0.30,7.70,0.37,0.72
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.36}"
    Text: 0.5,"centre",0.70,"half",
        ... "full-height X-bin average -> weighted brightness -> instantaneous pitch -> phase integration"
    Text: 0.5,"centre",0.20,"half",
        ... mappingName$ + " | brightness affects pitch only | R/B balance affects equal-power pan"

    # -----------------------------------------------------------------------
    # PANEL A: ACTUAL COLUMN PROJECTION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.83,1.04
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "A  ACTUAL IMAGE PROJECTION | weighted brightness and stereo pan"

    Select inner viewport: .left,.right,1.11,2.18
    Axes: 0,duration,0,1
    Paint rectangle: .bg$,0,duration,0,1

    Colour: .grid$
    Dotted line
    Draw line: 0,0.25,duration,0.25
    Draw line: 0,0.50,duration,0.50
    Draw line: 0,0.75,duration,0.75
    Plain line

    for .c from 2 to analysisColumns
        .ta = duration*(.c-2)/(analysisColumns-1)
        .tb = duration*(.c-1)/(analysisColumns-1)

        Colour: "{0.18,0.18,0.20}"
        Line width: 1.4
        Draw line:
            ... .ta,brightness#[.c-1],
            ... .tb,brightness#[.c]

        Colour: .red$
        Line width: 1
        Draw line:
            ... .ta,pan#[.c-1],
            ... .tb,pan#[.c]
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Normalized value"
    Text: 0.02*duration,"left",0.94,"half",
        ... "black brightness | red pan (0 left, 1 right)"

    # -----------------------------------------------------------------------
    # PANEL B: TRANSFER FUNCTION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.34,2.55
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "B  BRIGHTNESS -> PITCH TRANSFER | vertical axis is musical interval above minimum"

    Select inner viewport: .left,.right,2.62,3.56
    Axes: 0,1,0,max(1,pitchSpanSemitones)
    Paint rectangle: .bg$,0,1,0,max(1,pitchSpanSemitones)

    Colour: .grid$
    Dotted line
    Draw line: 0,0.5*pitchSpanSemitones,1,0.5*pitchSpanSemitones
    Plain line

    .prevB = 0
    if logarithmic_pitch_mapping
        .prevF = effectiveMinPitch
    else
        .prevF = effectiveMinPitch
    endif
    .prevSemi = 0

    Colour: .blue$
    Line width: 1.5
    for .j from 1 to 100
        .bb = .j/100
        if logarithmic_pitch_mapping
            .ff = effectiveMinPitch*
                ... (effectiveMaxPitch/effectiveMinPitch)^.bb
        else
            .ff = effectiveMinPitch+
                ... .bb*(effectiveMaxPitch-effectiveMinPitch)
        endif
        .semi = 12*ln(.ff/effectiveMinPitch)/ln(2)
        Draw line: .prevB,.prevSemi,.bb,.semi
        .prevB = .bb
        .prevSemi = .semi
    endfor

    .pointStep = max(1,ceiling(analysisColumns/120))
    for .c from 1 to analysisColumns
        if ((.c-1) mod .pointStep)=0
            .semi = 12*ln(freq#[.c]/effectiveMinPitch)/ln(2)
            Paint circle (mm): .orange$,brightness#[.c],.semi,0.55
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Semitones above minimum"
    Text bottom: "yes","Weighted brightness"

    # -----------------------------------------------------------------------
    # PANEL C: ACTUAL TARGET PITCH THROUGH TIME
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.72,3.93
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "C  ACTUAL TARGET PITCH | interpolated image control before phase integration"

    Select inner viewport: .left,.right,4.00,4.95
    Axes: 0,duration,0,max(1,pitchSpanSemitones)
    Paint rectangle: .bg$,0,duration,0,max(1,pitchSpanSemitones)

    Colour: .grid$
    Dotted line
    Draw line: 0,0.5*pitchSpanSemitones,duration,0.5*pitchSpanSemitones
    Plain line

    Colour: .orange$
    Line width: 1.3

    # Four subsegments per image-bin interval accurately follow either mapping.
    for .c from 2 to analysisColumns
        .baseT = duration*(.c-2)/(analysisColumns-1)
        .nextT = duration*(.c-1)/(analysisColumns-1)
        .b0 = brightness#[.c-1]
        .b1 = brightness#[.c]

        .prevT = .baseT
        if logarithmic_pitch_mapping
            .prevF = effectiveMinPitch*
                ... (effectiveMaxPitch/effectiveMinPitch)^.b0
        else
            .prevF = effectiveMinPitch+
                ... .b0*(effectiveMaxPitch-effectiveMinPitch)
        endif
        .prevSemi = 12*ln(.prevF/effectiveMinPitch)/ln(2)

        for .s from 1 to 4
            .alpha = .s/4
            .tt = .baseT+.alpha*(.nextT-.baseT)
            .bb = .b0+.alpha*(.b1-.b0)

            if logarithmic_pitch_mapping
                .ff = effectiveMinPitch*
                    ... (effectiveMaxPitch/effectiveMinPitch)^.bb
            else
                .ff = effectiveMinPitch+
                    ... .bb*(effectiveMaxPitch-effectiveMinPitch)
            endif

            .semi = 12*ln(.ff/effectiveMinPitch)/ln(2)
            Draw line: .prevT,.prevSemi,.tt,.semi
            .prevT = .tt
            .prevSemi = .semi
        endfor
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Pitch (semitones above min)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTROGRAM + TARGET GUIDE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.11,5.32
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.50,"half",
        ... "D  MODEL -> MEASUREMENT | measured output spectrogram + target instantaneous pitch"

    selectObject: outputSound
    Extract one channel: 1
    .disp = selected("Sound")

    .specMax = min(safeTop,max(1200,1.35*effectiveMaxPitch))
    .specStep = max(0.002,duration/1200)

    selectObject: .disp
    To Spectrogram: 0.030,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,5.39,6.55
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration,0,.specMax
    Colour: "{0.10,0.72,0.90}"
    Line width: 0.8

    for .c from 2 to analysisColumns
        .baseT = duration*(.c-2)/(analysisColumns-1)
        .nextT = duration*(.c-1)/(analysisColumns-1)
        .b0 = brightness#[.c-1]
        .b1 = brightness#[.c]

        .prevT = .baseT
        if logarithmic_pitch_mapping
            .prevF = effectiveMinPitch*
                ... (effectiveMaxPitch/effectiveMinPitch)^.b0
        else
            .prevF = effectiveMinPitch+
                ... .b0*(effectiveMaxPitch-effectiveMinPitch)
        endif

        for .s from 1 to 4
            .alpha = .s/4
            .tt = .baseT+.alpha*(.nextT-.baseT)
            .bb = .b0+.alpha*(.b1-.b0)

            if logarithmic_pitch_mapping
                .ff = effectiveMinPitch*
                    ... (effectiveMaxPitch/effectiveMinPitch)^.bb
            else
                .ff = effectiveMinPitch+
                    ... .bb*(effectiveMaxPitch-effectiveMinPitch)
            endif

            Draw line: .prevT,.prevF,.tt,.ff
            .prevT = .tt
            .prevF = .ff
        endfor
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 5
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # SUMMARY / QC
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.76,7.84
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.79,"half",
        ... "SCOPE  |  X preserved as time; full image height intentionally averaged per horizontal bin"

    Text: 0.02,"left",0.55,"half",
        ... "MAPPING  |  brightness " + fixed$(minBrightness,3)
        ... + "-" + fixed$(maxBrightness,3)
        ... + " -> " + mappingName$
        ... + " | realized F " + fixed$(minFreq,1)
        ... + "-" + fixed$(maxFreq,1) + " Hz"

    Text: 0.02,"left",0.31,"half",
        ... "SAMPLING  |  Fs " + string$(sr)
        ... + " Hz | safe top " + fixed$(safeTop,0)
        ... + " Hz | frequency scale " + fixed$(frequencyScale,4)

    if protectionApplied
        .level$ = "down-only protection applied"
    else
        .level$ = "level preserved"
    endif

    Text: 0.02,"left",0.08,"half",
        ... "OUTPUT  |  master " + fixed$(master_amplitude,3)
        ... + " | pre-peak " + fixed$(preProtectPeak,3)
        ... + " | RMS " + fixed$(preProtectRMS,4)
        ... + " | " + .level$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Font size: 10
    Line width: 1
endproc
