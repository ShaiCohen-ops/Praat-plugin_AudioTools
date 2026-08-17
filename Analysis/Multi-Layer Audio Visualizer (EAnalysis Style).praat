# ============================================================
# Praat AudioTools - Multi-Layer_Audio_Visualizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.4 (2025) - EAnalysis-style visualization
#   v3.2: waveform now drawn as a filled min/max envelope (solid blue
#   "blob" shape) instead of a thin outline curve, to match the target
#   EAnalysis-style mockup.
#   v3.3: removed the reserved "Graphic events" strip entirely (no
#   annotation placeholder layer, no related form parameters).
#   v3.4: layout/typography pass to match the reference mockup.
#     - Helvetica throughout (was Praat's default serif).
#     - Optional "Events" strip restored as a dashed placeholder band
#       (Draw_events_strip, default on); it is explicitly NOT signal-
#       derived - it is empty space reserved for hand-drawn annotation.
#     - Layer name / unit sub-label now stack vertically in the left
#       gutter instead of colliding on one line (the old x = 1.95
#       "right" hack wrote the sub-label past the panel edge).
#     - Track panels are flush (no inter-panel gap), so the stack reads
#       as one continuous score.
#     - Underscores in the Sound name are escaped (\_ ); a bare "_" is
#       SUBSCRIPT markup in the Picture window, so "oiseau_moqueur"
#       previously rendered as "oiseau" + subscript m + "oqueur".
#     - Waveform envelope painted as contiguous columns rather than
#       hairline strokes, which left white gaps at print resolution.
#     - Intensity fill clamped to the panel's dB ceiling; it previously
#       overflowed upward into the waveform track.
#     - Scale ticks formatted as in the mockup (5k / 2.5k / 0, +1 / 0 / -1).
#     - Layer names set bold; the italic "F%0%" style markup dropped in
#       favour of plain F0 / F1 / F2 / F3.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multi-Layer Audio Visualizer (EAnalysis Style)
#   Displays multiple synchronized analysis streams in horizontal layers,
#   styled after Pierre Couprie's EAnalysis on a plain white canvas
#   (confirmed against an actual EAnalysis screenshot: white background,
#   blue waveform, sonogram on white, bright saturated accent colours for
#   analytical curves - green/orange/magenta/blue, echoing the colours
#   Couprie's software uses for hand-drawn graphic events).
#
#   What this script reproduces:
#   - Waveform, sonogram, pitch, intensity, formants, centroid, pulses are
#     all derived directly from the audio, so they're drawn faithfully.
#   - EAnalysis's signature "graphic events" layer (hand-drawn annotations
#     a musicologist adds by ear) is not signal-derived, so this script
#     does not attempt to reproduce or reserve space for it.
#
#   A Dark_theme toggle is kept below for anyone who prefers a dark-canvas
#   variant, but it defaults OFF - white is the accurate EAnalysis look.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
sound$ = selected$("Sound")

form Multi-Layer Audio Visualizer v3.4 (EAnalysis style)
    comment === Layers to Display ===
    boolean Draw_events_strip 1
    boolean Draw_spectrogram 1
    boolean Draw_waveform 1
    boolean Draw_intensity 1
    boolean Draw_pitch 1
    boolean Draw_spectral_centroid 1
    boolean Draw_formants 1
    boolean Draw_pulses 1
    comment === Formant Options ===
    boolean Draw_F1 1
    boolean Draw_F2 1
    boolean Draw_F3 1
    comment === Analysis Parameters ===
    positive Time_step 0.01
    positive Pitch_floor 75
    positive Pitch_ceiling 1200
    positive Spectrogram_max_freq 5000
    comment === Intensity Range ===
    positive Intensity_min_dB 40
    positive Intensity_max_dB 80
    comment === EAnalysis Look ===
    boolean Dark_theme 0
    boolean Invert_spectrogram 0
    positive Spectrogram_dynamic_range 55
endform

selectObject: soundID
sMin = Get minimum: 0, 0, "None"
sMax = Get maximum: 0, 0, "None"
wavePeak = abs(sMin)
if abs(sMax) > wavePeak
    wavePeak = abs(sMax)
endif
if wavePeak = undefined or wavePeak = 0
    wavePeak = 1
endif
waveAxisMax = wavePeak * 1.08

# The reference figure labels the waveform axis +1 / 0 / -1, which is only
# honest for a near-full-scale file; anything quieter keeps its real value.
if wavePeak >= 0.95
    wavePeakLabel$ = "1"
else
    wavePeakLabel$ = fixed$(wavePeak, 2)
endif

# === Setup ===
selectObject: soundID
duration = Get total duration
startTime = Get start time
endTime = Get end time
sampleRate = Get sampling frequency

clearinfo
writeInfoLine: "=== Multi-Layer Audio Visualizer v3.0 (EAnalysis style) ==="
appendInfoLine: "Sound: ", sound$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""

# ============================================================
# CREATE ANALYSIS OBJECTS
# ============================================================

appendInfoLine: "Creating analysis objects..."

if draw_spectrogram or draw_spectral_centroid
    selectObject: soundID
    spectrogramID = To Spectrogram: 0.005, spectrogram_max_freq, 0.002, 20, "Gaussian"
endif

# --- Inverted spectrogram for the EAnalysis-style bright-on-dark sonogram ---
# Praat's Spectrogram: Paint... always paints the loudest point black and the
# quietest point white, with no invert option. To get "loud = bright, on a
# dark field" (the look EAnalysis and most electroacoustic sonogram displays
# use), we paint a reciprocal copy of the power values instead: quiet frames
# (power near 0) become huge, so they become the new "black" majority
# background; loud frames become small, so they land near "white" and read
# as bright energy against that background.
if draw_spectrogram and dark_theme and invert_spectrogram
    selectObject: spectrogramID
    spectrogramDrawID = Copy: "inverted"
    Formula: "if self > 0 then 1 / self else 1e12 fi"
else
    spectrogramDrawID = spectrogramID
endif

if draw_intensity
    selectObject: soundID
    intensityID = To Intensity: 75, time_step, "yes"
endif

if draw_pitch or draw_pulses
    selectObject: soundID
    pitchID_raw = To Pitch: time_step, pitch_floor, pitch_ceiling
    selectObject: pitchID_raw
    pitchID = Smooth: 10
    removeObject: pitchID_raw
endif

if draw_pulses
    selectObject: soundID
    plusObject: pitchID
    pulsesID = To PointProcess (cc)
endif

if draw_formants
    selectObject: soundID
    formantID = To Formant (burg): time_step, 5, 5500, 0.025, 50
endif

appendInfoLine: "Drawing layers..."

# ============================================================
# LAYOUT CALCULATION
# ============================================================

numLayers = 0
if draw_events_strip
    numLayers += 1
endif
if draw_spectrogram
    numLayers += 1
endif
if draw_waveform
    numLayers += 1
endif
if draw_intensity
    numLayers += 1
endif
if draw_pitch
    numLayers += 1
endif
if draw_spectral_centroid
    numLayers += 1
endif
if draw_formants
    numLayers += 1
endif
if draw_pulses
    numLayers += 1
endif

if numLayers = 0
    exitScript: "Please select at least one layer to draw."
endif

# --- VIEWPORT SETTINGS ---
# Proportions taken from the reference figure: 8 in wide, title band and
# time axis roughly 0.6 / 0.85 in, leaving equal-height tracks between.
totalWidth = 8.0
titleHeight = 0.6
timeAxisHeight = 0.85
labelWidth = 1.2
scaleWidth = 0.5
dataLeft = labelWidth
dataRight = totalWidth - scaleWidth

totalHeight = 7.8

availableHeight = totalHeight - titleHeight - timeAxisHeight
layerHeight = availableHeight / numLayers

# Minimum layer height for readability
if layerHeight < 0.5
    layerHeight = 0.5
endif

# ============================================================
# DRAWING
# ============================================================

# --- EAnalysis-style palette ---
# canvas$/panel colours are dark tints of each layer's original pastel hue,
# so the colour-coding of tracks is preserved but reads correctly on black.
canvas$ = "White"
titleText$ = "{0.1, 0.1, 0.12}"
borderLine$ = "{0.75, 0.75, 0.78}"
gridSoft$ = "{0.92, 0.92, 0.94}"
labelDim$ = "{0.5, 0.5, 0.55}"
scaleText$ = "{0.45, 0.45, 0.5}"
sepLine$ = "{0.85, 0.85, 0.88}"

panelSpectrogram$ = "White"
panelWaveform$ = "White"
panelIntensity$ = "White"
panelPitch$ = "White"
panelCentroid$ = "White"
panelFormants$ = "White"
panelPulses$ = "White"

# Bright, saturated accents - matched to the colours EAnalysis itself uses
# for waveform and hand-drawn graphic events (blue / green / orange / magenta),
# so the tracks read clearly against the plain white canvas.
curveWaveform$ = "{0.1, 0.35, 0.85}"
curveIntensityFill$ = "{0.75, 0.85, 0.98}"
curveIntensityLine$ = "{0.1, 0.35, 0.85}"
curvePitch$ = "{0.85, 0.15, 0.65}"
curveCentroid$ = "{0.95, 0.55, 0.05}"
curveF1$ = "{0.85, 0.15, 0.15}"
curveF2$ = "{0.15, 0.65, 0.2}"
curveF3$ = "{0.15, 0.4, 0.85}"
curvePulses$ = "{0.85, 0.15, 0.15}"

eventsBox$ = "{0.60, 0.60, 0.63}"
eventsHint$ = "{0.55, 0.55, 0.58}"
axisLine$ = "{0.35, 0.35, 0.38}"

if dark_theme = 1
    canvas$ = "{0.07, 0.07, 0.09}"
    titleText$ = "{0.92, 0.92, 0.94}"
    borderLine$ = "{0.5, 0.5, 0.56}"
    gridSoft$ = "{0.22, 0.22, 0.26}"
    labelDim$ = "{0.55, 0.55, 0.6}"
    scaleText$ = "{0.65, 0.65, 0.7}"
    sepLine$ = "{0.3, 0.3, 0.35}"
    panelSpectrogram$ = "{0.07, 0.07, 0.09}"
    panelWaveform$ = "{0.09, 0.10, 0.13}"
    panelIntensity$ = "{0.06, 0.09, 0.14}"
    panelPitch$ = "{0.13, 0.06, 0.12}"
    panelCentroid$ = "{0.14, 0.09, 0.05}"
    panelFormants$ = "{0.05, 0.12, 0.08}"
    panelPulses$ = "{0.14, 0.06, 0.07}"
    curveWaveform$ = "{0.45, 0.85, 0.95}"
    curveIntensityFill$ = "{0.15, 0.28, 0.45}"
    curveIntensityLine$ = "{0.4, 0.75, 1}"
    curvePitch$ = "{1, 0.35, 0.85}"
    curveCentroid$ = "{1, 0.65, 0.25}"
    curveF1$ = "{1, 0.4, 0.4}"
    curveF2$ = "{0.4, 0.95, 0.55}"
    curveF3$ = "{0.5, 0.7, 1}"
    curvePulses$ = "{1, 0.4, 0.4}"
    eventsBox$ = "{0.45, 0.45, 0.5}"
    eventsHint$ = "{0.55, 0.55, 0.6}"
    axisLine$ = "{0.6, 0.6, 0.65}"
endif

# ============================================================
# SHARED DRAWING HELPERS
# ============================================================

# Left gutter: bold layer name with a dim unit sub-label BELOW it.
# (Both are right-aligned to a common edge just short of the panel.)
procedure layerLabel: .name$, .sub$, .colour$, .top, .bottom
    Select inner viewport: 0, labelWidth - 0.08, .top, .bottom
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: .colour$
    Text: 1, "right", 0.62, "half", "##" + .name$ + "##"
    if .sub$ <> ""
        Font size: 7
        Colour: labelDim$
        Text: 1, "right", 0.26, "half", .sub$
    endif
endproc

# Right gutter: three tick labels. Callers pass the TRUE axis values; the
# outer two are then nudged inward by a fixed fraction of the panel span
# before drawing. That nudge is what stops the bottom tick of one track
# printing over the top tick of the next now that the panels are flush.
# (Anchoring the text with "top"/"bottom" instead does not do it - Praat
# still centres the glyphs on the value, so the labels overlapped anyway.)
procedure layerScale: .top, .bottom, .vmin, .vmax, .t1$, .v1, .t2$, .v2, .t3$, .v3
    .pad = (.vmax - .vmin) * 0.12
    if .v1 > .vmax - .pad
        .v1 = .vmax - .pad
    endif
    if .v3 < .vmin + .pad
        .v3 = .vmin + .pad
    endif
    Select inner viewport: dataRight + 0.10, totalWidth, .top, .bottom
    Axes: 0, 1, .vmin, .vmax
    Font size: 6
    Colour: scaleText$
    Text: 0, "left", .v1, "half", .t1$
    Text: 0, "left", .v2, "half", .t2$
    Text: 0, "left", .v3, "half", .t3$
endproc

# 5000 -> "5k", 2500 -> "2.5k", 500 -> "500"
procedure hzLabel: .hz
    if .hz >= 1000
        .k = .hz / 1000
        if .k = round(.k)
            hzLabel$ = string$(round(.k)) + "k"
        else
            hzLabel$ = fixed$(.k, 1) + "k"
        endif
    else
        hzLabel$ = string$(round(.hz))
    endif
endproc

Erase all
Helvetica
Font size: 10
Line width: 1

# --- Full-canvas background ---
# Inner, not outer: Axes maps to the INNER viewport, so painting via
# "Select outer viewport" left Praat's ~0.4 in margins unpainted - which
# is invisible on the white theme but put the title, the left gutter and
# the time-axis caption on a white border under Dark_theme.
Select inner viewport: 0, totalWidth, 0, totalHeight
Axes: 0, 1, 0, 1
Paint rectangle: canvas$, 0, 1, 0, 1

# --- Title Bar ---
# "_" is SUBSCRIPT markup in the Picture window, so a raw object name
# like oiseau_moqueur renders as "oiseau" + subscript m + "oqueur".
soundLabel$ = replace$(sound$, "_", "\_ ", 0)

Select inner viewport: 0, totalWidth, 0, titleHeight
Axes: 0, 1, 0, 1

Colour: titleText$
Font size: 13
Text: 0.5, "centre", 0.35, "half", "##Multi-Layer Audio Visualizer: " + soundLabel$ + "##"

currentY = titleHeight
layerNum = 0

# ============================================================
# LAYER: EVENTS (placeholder strip)
# ============================================================
# Deliberately empty. EAnalysis's "graphic events" are hand-drawn by a
# musicologist listening to the piece - they are an interpretation, not a
# measurement - so nothing here is derived from the audio. The strip only
# reserves the band, time-aligned with every track below it.

if draw_events_strip
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight

    appendInfoLine: "  [", layerNum, "] Events (empty placeholder)"

    Select inner viewport: dataLeft, dataRight, layerTop + 0.04, layerBottom - 0.04
    Axes: 0, 1, 0, 1

    Colour: eventsBox$
    Line width: 1.5
    Dashed line
    Draw line: 0, 0, 1, 0
    Draw line: 1, 0, 1, 1
    Draw line: 1, 1, 0, 1
    Draw line: 0, 1, 0, 0
    Solid line

    Select inner viewport: dataLeft, dataRight, layerTop + 0.04, layerBottom - 0.04
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: eventsHint$
    Text: 0.5, "centre", 0.5, "half", "%%Graphic events (draw by hand)%"

    @layerLabel: "Events", "", titleText$, layerTop, layerBottom

    currentY = layerBottom
endif

# ============================================================
# LAYER: SPECTROGRAM
# ============================================================

if draw_spectrogram
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Spectrogram"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    selectObject: spectrogramDrawID
    Paint: startTime, endTime, 0, spectrogram_max_freq, 100, "yes", spectrogram_dynamic_range, 6, 0, "no"
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, 0, spectrogram_max_freq
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane ---
    @hzLabel: spectrogram_max_freq
    topHz$ = hzLabel$
    @hzLabel: spectrogram_max_freq / 2
    midHz$ = hzLabel$
    
    @layerLabel: "Spectrogram", "0-" + string$(spectrogram_max_freq) + " Hz", titleText$, layerTop, layerBottom
    
    # --- Scale pane ---
    @layerScale: layerTop, layerBottom, 0, spectrogram_max_freq,
    ... topHz$, spectrogram_max_freq,
    ... midHz$, spectrogram_max_freq * 0.5,
    ... "0", 0
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: WAVEFORM
# ============================================================

if draw_waveform
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Waveform"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    Axes: startTime, endTime, -waveAxisMax, waveAxisMax
    
    # Background
    Colour: panelWaveform$
    Paint rectangle: panelWaveform$, startTime, endTime, -waveAxisMax, waveAxisMax
    
    # Zero line
    Colour: gridSoft$
    Line width: 0.5
    Dotted line
    Draw line: startTime, 0, endTime, 0
    Solid line
    
    # Waveform - filled min/max envelope. Painted as CONTIGUOUS columns
    # (each column spans wt0..wt1, so neighbours share an edge) rather
    # than as vertical strokes: at print resolution a 1-px stroke leaves
    # white gaps between columns, whereas an area fill always covers at
    # least one device pixel. The result is the solid blue "blob"
    # silhouette of the reference figure, with no stripe artefacts.
    selectObject: soundID
    numWaveCols = 1400
    waveColWidth = duration / numWaveCols
    minBlob = waveAxisMax * 0.004
    for i from 1 to numWaveCols
        wt0 = startTime + (i - 1) * waveColWidth
        wt1 = wt0 + waveColWidth
        if wt1 > endTime
            wt1 = endTime
        endif
        if wt1 > wt0
            selectObject: soundID
            wMin = Get minimum: wt0, wt1, "Sinc70"
            wMax = Get maximum: wt0, wt1, "Sinc70"
            if wMin <> undefined and wMax <> undefined
                if wMin > -minBlob
                    wMin = -minBlob
                endif
                if wMax < minBlob
                    wMax = minBlob
                endif
                Paint rectangle: curveWaveform$, wt0, wt1, wMin, wMax
            endif
        endif
    endfor
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, -waveAxisMax, waveAxisMax
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane ---
    @layerLabel: "Waveform", "Amplitude", curveWaveform$, layerTop, layerBottom
    
    # --- Scale pane ---
    @layerScale: layerTop, layerBottom, -waveAxisMax, waveAxisMax,
    ... "+" + wavePeakLabel$, wavePeak,
    ... "0", 0,
    ... "-" + wavePeakLabel$, -wavePeak
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: INTENSITY
# ============================================================

if draw_intensity
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Intensity"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    Axes: startTime, endTime, intensity_min_dB, intensity_max_dB
    
    # Background
    Colour: panelIntensity$
    Paint rectangle: panelIntensity$, startTime, endTime, intensity_min_dB, intensity_max_dB
    
    # Grid lines
    Colour: gridSoft$
    Line width: 0.5
    gridDB = intensity_min_dB + 10
    while gridDB < intensity_max_dB
        Draw line: startTime, gridDB, endTime, gridDB
        gridDB = gridDB + 10
    endwhile
    
    # Intensity curve with fill
    selectObject: intensityID
    
    # Fill area under curve
    Colour: curveIntensityFill$
    numFrames = floor(duration / time_step)
    for i from 1 to numFrames
        t = startTime + (i - 1) * time_step
        if t <= endTime
            selectObject: intensityID
            val = Get value at time: t, "Cubic"
            if val <> undefined and val > intensity_min_dB
                # Clamp: Praat does not clip a Paint rectangle to the
                # viewport, so an unclamped loud frame spilled the fill
                # up into the waveform track above.
                if val > intensity_max_dB
                    val = intensity_max_dB
                endif
                tEnd = t + time_step
                if tEnd > endTime
                    tEnd = endTime
                endif
                Paint rectangle: curveIntensityFill$, t, tEnd, intensity_min_dB, val
            endif
        endif
    endfor
    
    # Curve line
    selectObject: intensityID
    Colour: curveIntensityLine$
    Line width: 2
    Draw: startTime, endTime, intensity_min_dB, intensity_max_dB, "no"
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, intensity_min_dB, intensity_max_dB
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane ---
    @layerLabel: "Intensity", "dB SPL", curveIntensityLine$, layerTop, layerBottom
    
    # --- Scale pane ---
    midDB = (intensity_min_dB + intensity_max_dB) / 2
    @layerScale: layerTop, layerBottom, intensity_min_dB, intensity_max_dB,
    ... string$(intensity_max_dB), intensity_max_dB,
    ... string$(midDB), midDB,
    ... string$(intensity_min_dB), intensity_min_dB
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: PITCH (F0)
# ============================================================

if draw_pitch
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Pitch (F0)"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    Axes: startTime, endTime, pitch_floor, pitch_ceiling
    
    # Background
    Colour: panelPitch$
    Paint rectangle: panelPitch$, startTime, endTime, pitch_floor, pitch_ceiling
    
    # Musical reference lines (octaves from A=110)
    Colour: gridSoft$
    Line width: 0.5
    Dotted line
    refPitch = 110
    while refPitch <= pitch_ceiling
        if refPitch >= pitch_floor
            Draw line: startTime, refPitch, endTime, refPitch
        endif
        refPitch = refPitch * 2
    endwhile
    Solid line
    
    # Pitch contour
    selectObject: pitchID
    Colour: curvePitch$
    Line width: 2.5
    
    numFrames = floor(duration / time_step)
    prevVoiced = 0
    prevT = 0
    prevP = 0
    
    for i from 1 to numFrames
        t = startTime + (i - 1) * time_step
        if t <= endTime
            selectObject: pitchID
            p = Get value at time: t, "Hertz", "Linear"
            if p <> undefined and p >= pitch_floor and p <= pitch_ceiling
                if prevVoiced = 1
                    Draw line: prevT, prevP, t, p
                endif
                prevVoiced = 1
                prevT = t
                prevP = p
            else
                prevVoiced = 0
            endif
        endif
    endfor
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, pitch_floor, pitch_ceiling
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane ---
    @layerLabel: "Pitch (F0)", "Hz", curvePitch$, layerTop, layerBottom
    
    # --- Scale pane ---
    midP = (pitch_floor + pitch_ceiling) / 2
    @layerScale: layerTop, layerBottom, pitch_floor, pitch_ceiling,
    ... string$(pitch_ceiling), pitch_ceiling,
    ... string$(round(midP)), midP,
    ... string$(pitch_floor), pitch_floor
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: SPECTRAL CENTROID
# ============================================================

if draw_spectral_centroid
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Spectral Centroid"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    centroidMin = 500
    centroidMax = 4000
    
    Axes: startTime, endTime, centroidMin, centroidMax
    
    # Background
    Colour: panelCentroid$
    Paint rectangle: panelCentroid$, startTime, endTime, centroidMin, centroidMax
    
    # Grid lines
    Colour: gridSoft$
    Line width: 0.5
    gridHz = 1000
    while gridHz <= 3500
        Draw line: startTime, gridHz, endTime, gridHz
        gridHz = gridHz + 1000
    endwhile
    
    # Centroid curve
    selectObject: spectrogramID
    Colour: curveCentroid$
    Line width: 2.5
    
    prevCentroid = undefined
    prevT = undefined
    numFrames = floor(duration / time_step)
    
    for i from 1 to numFrames
        t = startTime + (i - 1) * time_step
        if t <= endTime
            selectObject: spectrogramID
            totalPower = 0
            weightedSum = 0
            freq = 100
            while freq <= spectrogram_max_freq
                power = Get power at: t, freq
                if power <> undefined and power > 0
                    totalPower = totalPower + power
                    weightedSum = weightedSum + freq * power
                endif
                freq = freq + 100
            endwhile
            
            if totalPower > 0
                centroid = weightedSum / totalPower
                if centroid < centroidMin
                    centroid = centroidMin
                endif
                if centroid > centroidMax
                    centroid = centroidMax
                endif
                
                if prevCentroid <> undefined
                    Draw line: prevT, prevCentroid, t, centroid
                endif
                prevCentroid = centroid
                prevT = t
            else
                prevCentroid = undefined
            endif
        endif
    endfor
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, centroidMin, centroidMax
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane ---
    @layerLabel: "Centroid", "Hz", curveCentroid$, layerTop, layerBottom
    
    # --- Scale pane ---
    @layerScale: layerTop, layerBottom, centroidMin, centroidMax,
    ... "4k", centroidMax,
    ... "2k", 2000,
    ... "500", centroidMin
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: FORMANTS (F1, F2, F3)
# ============================================================

if draw_formants
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Formants"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    formantMin = 0
    formantMax = 4000
    
    Axes: startTime, endTime, formantMin, formantMax
    
    # Background
    Colour: panelFormants$
    Paint rectangle: panelFormants$, startTime, endTime, formantMin, formantMax
    
    # Grid lines
    Colour: gridSoft$
    Line width: 0.5
    gridHz = 1000
    while gridHz <= 3500
        Draw line: startTime, gridHz, endTime, gridHz
        gridHz = gridHz + 1000
    endwhile
    
    selectObject: formantID
    numFrames = floor(duration / time_step)
    
    # F3 (draw first - back layer)
    if draw_F3
        Colour: curveF3$
        Line width: 1.8
        prevVoiced = 0
        prevT = 0
        prevF = 0
        for i from 1 to numFrames
            t = startTime + (i - 1) * time_step
            if t <= endTime
                selectObject: formantID
                f = Get value at time: 3, t, "hertz", "Linear"
                if f <> undefined and f >= formantMin and f <= formantMax
                    if prevVoiced = 1
                        Draw line: prevT, prevF, t, f
                    endif
                    prevVoiced = 1
                    prevT = t
                    prevF = f
                else
                    prevVoiced = 0
                endif
            endif
        endfor
    endif
    
    # F2 (middle layer)
    if draw_F2
        Colour: curveF2$
        Line width: 2.2
        prevVoiced = 0
        prevT = 0
        prevF = 0
        for i from 1 to numFrames
            t = startTime + (i - 1) * time_step
            if t <= endTime
                selectObject: formantID
                f = Get value at time: 2, t, "hertz", "Linear"
                if f <> undefined and f >= formantMin and f <= formantMax
                    if prevVoiced = 1
                        Draw line: prevT, prevF, t, f
                    endif
                    prevVoiced = 1
                    prevT = t
                    prevF = f
                else
                    prevVoiced = 0
                endif
            endif
        endfor
    endif
    
    # F1 (front layer - thickest)
    if draw_F1
        Colour: curveF1$
        Line width: 2.8
        prevVoiced = 0
        prevT = 0
        prevF = 0
        for i from 1 to numFrames
            t = startTime + (i - 1) * time_step
            if t <= endTime
                selectObject: formantID
                f = Get value at time: 1, t, "hertz", "Linear"
                if f <> undefined and f >= formantMin and f <= formantMax
                    if prevVoiced = 1
                        Draw line: prevT, prevF, t, f
                    endif
                    prevVoiced = 1
                    prevT = t
                    prevF = f
                else
                    prevVoiced = 0
                endif
            endif
        endfor
    endif
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, formantMin, formantMax
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane (name plus a colour key for the three tracks) ---
    Select inner viewport: 0, labelWidth - 0.08, layerTop, layerBottom
    Axes: 0, 1, 0, 1
    
    Font size: 9
    Colour: titleText$
    Text: 1, "right", 0.84, "half", "##Formants##"
    
    Font size: 7
    if draw_F1
        Colour: curveF1$
        Text: 1, "right", 0.58, "half", "F1"
    endif
    if draw_F2
        Colour: curveF2$
        Text: 1, "right", 0.38, "half", "F2"
    endif
    if draw_F3
        Colour: curveF3$
        Text: 1, "right", 0.18, "half", "F3"
    endif
    
    # --- Scale pane ---
    @layerScale: layerTop, layerBottom, formantMin, formantMax,
    ... "4k", formantMax,
    ... "2k", 2000,
    ... "0", formantMin
    
    currentY = layerBottom
endif

# ============================================================
# LAYER: PULSES
# ============================================================

if draw_pulses
    layerNum += 1
    layerTop = currentY
    layerBottom = currentY + layerHeight
    
    appendInfoLine: "  [", layerNum, "] Glottal Pulses"
    
    # --- Data pane ---
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    
    Axes: startTime, endTime, 0, 1
    
    # Background
    Colour: panelPulses$
    Paint rectangle: panelPulses$, startTime, endTime, 0, 1
    
    # Pulses
    selectObject: pulsesID
    numPulses = Get number of points
    Colour: curvePulses$
    Line width: 1
    
    for p from 1 to numPulses
        selectObject: pulsesID
        t = Get time from index: p
        if t >= startTime and t <= endTime
            Draw line: t, 0.1, t, 0.9
        endif
    endfor
    
    Select inner viewport: dataLeft, dataRight, layerTop, layerBottom
    Axes: startTime, endTime, 0, 1
    Colour: borderLine$
    Line width: 0.5
    Draw inner box
    
    # --- Label pane ---
    @layerLabel: "Pulses", "Glottal", curvePulses$, layerTop, layerBottom
    
    currentY = layerBottom
endif

# Track separators are no longer drawn: the panels are now flush, so each
# panel's own inner box already supplies the dividing rule.

# ============================================================
# TIME AXIS
# ============================================================

timeAxisTop = totalHeight - timeAxisHeight
timeAxisBottom = totalHeight

# Time axis
Select inner viewport: dataLeft, dataRight, timeAxisTop, timeAxisBottom - 0.28

Axes: startTime, endTime, 0, 1

# Axis line
Colour: axisLine$
Line width: 1
Draw line: startTime, 1, endTime, 1

# Calculate nice tick interval
if duration <= 1
    tickInterval = 0.1
elsif duration <= 5
    tickInterval = 0.5
elsif duration <= 10
    tickInterval = 1
elsif duration <= 30
    tickInterval = 2
else
    tickInterval = 5
endif

# Draw ticks and labels
t = 0
while t <= endTime
    if t >= startTime
        Colour: axisLine$
        Line width: 1
        Draw line: t, 1, t, 0.80
        Font size: 8
        Colour: scaleText$
        # fixed$ returns a bare "0" for exactly zero whatever the
        # precision, which would print "0" beside "0.5", "1.0", ...
        if t = 0
            tick$ = "0.0"
        else
            tick$ = fixed$(t, 1)
        endif
        Text: t, "centre", 0.22, "half", tick$
    endif
    t = t + tickInterval
endwhile

# Axis title
Select inner viewport: dataLeft, dataRight, timeAxisBottom - 0.30, timeAxisBottom
Axes: 0, 1, 0, 1
Font size: 10
Colour: titleText$
Text: 0.5, "centre", 0.4, "half", "##Time (s)##"

# ============================================================
# CLEANUP
# ============================================================

Colour: "Black"
Line width: 1
Font size: 10

if draw_spectrogram and dark_theme and invert_spectrogram
    removeObject: spectrogramDrawID
endif
if draw_spectrogram or draw_spectral_centroid
    removeObject: spectrogramID
endif
if draw_intensity
    removeObject: intensityID
endif
if draw_pitch or draw_pulses
    removeObject: pitchID
endif
if draw_formants
    removeObject: formantID
endif
if draw_pulses
    removeObject: pulsesID
endif

selectObject: soundID

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Layers drawn: ", numLayers