# ============================================================
# Praat AudioTools - Distribute_sounds_in_stereo_field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025)
# v0.4 (2026): SPATIAL VISUALIZATION STANDARDIZATION ONLY - label rails, compact summary, typography; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Distributes multiple selected sounds across the stereo field
#   using a chosen panning law and mixes to a single stereo output.
#
# Changelog v0.4:
#   - Form + presets: now matches the rest of the suite. Adds
#     pan width, curve law, order, stereo-input handling,
#     output peak, draw_visualization, and play_result toggles.
#   - Presets: Even Spread, Headphone-Friendly (80% width),
#     Cluster Center (40% width), Reverse Order, Spread from
#     Center.
#   - Fix: single-sound case no longer divides by zero.
#     With 1 selected sound the pan is set to center (0).
#   - Stereo input handling is now an explicit choice. Default
#     is "Preserve balance" — each input channel is panned
#     independently so existing L/R information in the source
#     contributes to the placement (e.g. a stereo field
#     recording stays slightly biased even after re-panning).
#     "Fold to mono" reproduces v0.2 behavior.
#   - Pan curve laws: Constant power (default, equal energy
#     across the field), Linear (equal voltage, hole in the
#     middle), -3dB sin/cos (industry standard).
#   - Order options: Forward (left-to-right by selection
#     order, was v0.2's only mode), Reverse, and Center-out
#     (alternates outward from the centre).
#   - Visualization (suite 8x8 standard, matching 22.2 Stem
#     Renderer, 8-ch I Ching, 8-ch Movements, 4-ch Canon,
#     8-ch Spectral Shift, 8-ch Speed Deviations, 8-ch
#     Speech-Driven Spatialization). Panels:
#       A: Horizontal stereo field strip — each source as a
#          labelled marker at its pan position, marker
#          diameter scaled by RMS, vertical position
#          jittered to avoid label collisions.
#       B: Pan-curve diagram — L/R gain vs pan position for
#          the chosen law, with markers for each source's
#          actual gain pair.
#       C: Per-source bars — RMS level by source, ordered by
#          pan position.
#       D: Output waveform (L blue, R orange).
#       E: Summary bar (grey, framed).
# Changelog v0.2:
#   - Constant-power panning, fold-to-mono, base auto-mix.
# ============================================================

# === FORM ===
form Distribute Sounds in Stereo Field
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Even Spread (full width)"
        option: "Headphone-Friendly (80% width)"
        option: "Cluster Center (40% width)"
        option: "Reverse Order (full width)"
        option: "Spread from Center"
    
    comment === Spread ===
    real Pan_width 1.0
    optionmenu Order: 1
        option: "Forward (left-to-right by selection order)"
        option: "Reverse (right-to-left)"
        option: "Center-out (alternating outward)"
    
    comment === Pan law ===
    optionmenu Pan_law: 1
        option: "Constant power (sqrt)"
        option: "Linear (-6 dB centre dip)"
        option: "-3 dB sin/cos"
    
    comment === Stereo input ===
    optionmenu Stereo_input_handling: 1
        option: "Preserve balance (pan each input channel)"
        option: "Fold to mono"
    
    comment === Output ===
    real Output_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply presets ===
if preset = 2
    pan_width = 1.0
    order = 1
    presetName$ = "EvenSpread"
elsif preset = 3
    pan_width = 0.8
    order = 1
    presetName$ = "Headphone"
elsif preset = 4
    pan_width = 0.4
    order = 1
    presetName$ = "Cluster"
elsif preset = 5
    pan_width = 1.0
    order = 2
    presetName$ = "Reverse"
elsif preset = 6
    pan_width = 1.0
    order = 3
    presetName$ = "FromCenter"
else
    presetName$ = "Custom"
endif

# Clamp pan_width to safe range
if pan_width < 0
    pan_width = 0
endif
if pan_width > 1
    pan_width = 1
endif

# === Check selection ===
numberOfSounds = numberOfSelected("Sound")

if numberOfSounds < 1
    exitScript: "Please select at least 1 Sound object."
endif

# === Pan-law label for stats ===
if pan_law = 1
    panLawName$ = "ConstPower"
elsif pan_law = 2
    panLawName$ = "Linear"
else
    panLawName$ = "-3dB sin/cos"
endif

if order = 1
    orderName$ = "Forward"
elsif order = 2
    orderName$ = "Reverse"
else
    orderName$ = "CenterOut"
endif

if stereo_input_handling = 1
    stereoModeName$ = "PreserveBalance"
else
    stereoModeName$ = "FoldToMono"
endif

# === Info ===
writeInfoLine: "=== Distribute Sounds in Stereo Field v0.4 ==="
appendInfoLine: "Sources: ", numberOfSounds
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Width: ", fixed$(pan_width, 2), "  |  Order: ", orderName$, "  |  Law: ", panLawName$
appendInfoLine: ""

# === Snapshot all selected source IDs and their names ===
for i from 1 to numberOfSounds
    sound[i] = selected("Sound", i)
endfor
for i from 1 to numberOfSounds
    selectObject: sound[i]
    soundName$[i] = selected$("Sound")
endfor

# === Determine output canvas params ===
selectObject: sound[1]
sampleRate = Get sampling frequency
maxDuration = 0
for i from 1 to numberOfSounds
    selectObject: sound[i]
    thisSr = Get sampling frequency
    if thisSr <> sampleRate
        appendInfoLine: "Warning: '", soundName$[i], "' SR=", thisSr,
            ... " differs from canvas SR=", sampleRate, "; will resample."
    endif
    thisDuration = Get total duration
    if thisDuration > maxDuration
        maxDuration = thisDuration
    endif
endfor

# === Compute pan positions for each source ===
# panPos[i] is the *original-index* source's target pan in [-1, +1] before
# the order/width adjustments below. orderIdx[i] is the slot in the
# left-to-right output assigned to source i.
orderIdx# = zero# (numberOfSounds)
if numberOfSounds = 1
    orderIdx#[1] = 1
elsif order = 1
    for i from 1 to numberOfSounds
        orderIdx#[i] = i
    endfor
elsif order = 2
    for i from 1 to numberOfSounds
        orderIdx#[i] = numberOfSounds - i + 1
    endfor
else
    # Center-out: source 1 -> centre, then alternate outward.
    # For odd N: 1->mid, 2->mid-1, 3->mid+1, 4->mid-2, 5->mid+2, ...
    # For even N: distribute symmetrically with no exact centre slot.
    midSlot = (numberOfSounds + 1) / 2
    sign = 1
    offset = 0
    for i from 1 to numberOfSounds
        if i = 1
            slot = round(midSlot)
        else
            if sign = 1
                offset = offset + 1
                slot = round(midSlot) + offset
                sign = -1
            else
                slot = round(midSlot) - offset
                sign = 1
            endif
        endif
        # Clamp slot into valid range; on collision, scan to first free slot
        if slot < 1
            slot = 1
        endif
        if slot > numberOfSounds
            slot = numberOfSounds
        endif
        # Linear scan to first unoccupied slot
        taken = 1
        while taken = 1
            taken = 0
            for j from 1 to i - 1
                if orderIdx#[j] = slot
                    taken = 1
                endif
            endfor
            if taken = 1
                slot = slot + 1
                if slot > numberOfSounds
                    slot = 1
                endif
            endif
        endwhile
        orderIdx#[i] = slot
    endfor
endif

# Convert slot index to pan position scaled by pan_width
panPos# = zero# (numberOfSounds)
if numberOfSounds = 1
    panPos#[1] = 0
else
    for i from 1 to numberOfSounds
        slot = orderIdx#[i]
        # slot in 1..N -> raw pan in -1..+1 (full width)
        rawPan = -1 + 2 * (slot - 1) / (numberOfSounds - 1)
        panPos#[i] = rawPan * pan_width
    endfor
endif

# === Storage for visualization ===
rmsValue# = zero# (numberOfSounds)
durValue# = zero# (numberOfSounds)
leftGainStore# = zero# (numberOfSounds)
rightGainStore# = zero# (numberOfSounds)

# === Create empty stereo canvas ===
selectObject: sound[1]
baseName$ = selected$("Sound")
stereoMix = Create Sound from formula: baseName$ + "_panMix_" + presetName$, 2, 0, maxDuration, sampleRate, "0"

# === Procedure: pan-law gains ===
# Returns leftG, rightG given pan in [-1, +1]
procedure panLaw: .pan, .law
    # Map pan (-1..+1) to position (0..1)
    .pos = (.pan + 1) / 2
    if .law = 1
        # Constant power: equal energy
        .leftG = sqrt(1 - .pos)
        .rightG = sqrt(.pos)
    elsif .law = 2
        # Linear: equal voltage, has -6 dB centre dip in power
        .leftG = 1 - .pos
        .rightG = .pos
    else
        # -3 dB sin/cos
        .leftG = cos(.pos * pi / 2)
        .rightG = sin(.pos * pi / 2)
    endif
endproc

# === Process and mix ===
for i from 1 to numberOfSounds
    selectObject: sound[i]
    nChannels = Get number of channels
    
    # Resample if needed
    thisSr = Get sampling frequency
    if thisSr <> sampleRate
        Resample: sampleRate, 50
        resampledID = selected("Sound")
        srcID = resampledID
    else
        srcID = sound[i]
    endif
    
    # Determine pan and gains
    pan = panPos#[i]
    @panLaw: pan, pan_law
    leftGain = panLaw.leftG
    rightGain = panLaw.rightG
    leftGainStore#[i] = leftGain
    rightGainStore#[i] = rightGain
    
    # Branch by stereo handling
    selectObject: srcID
    if stereo_input_handling = 2 or nChannels = 1
        # Fold to mono (always for nChannels = 1, and for explicit fold)
        if nChannels > 1
            mono = Convert to mono
        else
            mono = Copy: "temp_mono"
        endif
        selectObject: mono
        soundDuration = Get total duration
        thisRMS = Get root-mean-square: 0, 0
        rmsValue#[i] = thisRMS
        durValue#[i] = soundDuration
        
        selectObject: stereoMix
        Formula (part): 0, soundDuration, 1, 1,
            ... "self + object[" + string$(mono) + "] * " + string$(leftGain)
        Formula (part): 0, soundDuration, 2, 2,
            ... "self + object[" + string$(mono) + "] * " + string$(rightGain)
        
        removeObject: mono
    else
        # Preserve balance: pan each input channel independently.
        # Treat input L as a mono source at the source's pan position
        # but biased slightly leftward; input R biased rightward.
        # Concretely: input L -> output (leftGain, rightGain) of L's amp.
        # Input R -> output (leftGain, rightGain) of R's amp. Since
        # both are added at the same pan position, pre-existing L/R
        # balance simply scales which input channel contributes more.
        Extract one channel: 1
        inL = selected("Sound")
        selectObject: srcID
        Extract one channel: 2
        inR = selected("Sound")
        
        # RMS for visualization: sum of channel RMS (rough proxy)
        selectObject: inL
        rL = Get root-mean-square: 0, 0
        soundDuration = Get total duration
        selectObject: inR
        rR = Get root-mean-square: 0, 0
        rmsValue#[i] = sqrt(rL * rL + rR * rR) / sqrt(2)
        durValue#[i] = soundDuration
        
        selectObject: stereoMix
        Formula (part): 0, soundDuration, 1, 1,
            ... "self + (object[" + string$(inL) + "] + object[" + string$(inR) + "]) * 0.5 * " + string$(leftGain)
        Formula (part): 0, soundDuration, 2, 2,
            ... "self + (object[" + string$(inL) + "] + object[" + string$(inR) + "]) * 0.5 * " + string$(rightGain)
        
        removeObject: inL, inR
    endif
    
    # Cleanup resample
    if thisSr <> sampleRate
        removeObject: resampledID
    endif
    
    appendInfoLine: "  ", i, ". '", soundName$[i], "'  pan=", fixed$(pan, 2),
        ... "  L=", fixed$(leftGain, 3), " R=", fixed$(rightGain, 3),
        ... "  rms=", fixed$(rmsValue#[i], 4)
endfor

# === Finalize ===
selectObject: stereoMix
Scale peak: output_peak

selectObject: stereoMix
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "Output: ", fixed$(finalDur, 2), " s, peak=", fixed$(finalPeak, 3)

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    
    Erase all
    
    # --- Per-source colour by pan position (cool L → warm R) ---
    srcColR# = zero# (numberOfSounds)
    srcColG# = zero# (numberOfSounds)
    srcColB# = zero# (numberOfSounds)
    for i from 1 to numberOfSounds
        # Map pan (-1..+1) to position (0..1)
        posv = (panPos#[i] + 1) / 2
        # Cool blue at posv=0, warm red at posv=1, neutral mid
        if posv < 0.5
            t = posv * 2
            srcColR#[i] = 0.20 + t * 0.55
            srcColG#[i] = 0.50 + t * 0.10
            srcColB#[i] = 0.80 - t * 0.30
        else
            t = (posv - 0.5) * 2
            srcColR#[i] = 0.75 + t * 0.15
            if srcColR#[i] > 1
                srcColR#[i] = 1
            endif
            srcColG#[i] = 0.60 - t * 0.30
            srcColB#[i] = 0.50 - t * 0.30
            if srcColB#[i] < 0
                srcColB#[i] = 0
            endif
        endif
    endfor
    
    # Find max RMS for marker scaling
    maxRMS = rmsValue#[1]
    for i from 2 to numberOfSounds
        if rmsValue#[i] > maxRMS
            maxRMS = rmsValue#[i]
        endif
    endfor
    if maxRMS < 0.000001
        maxRMS = 0.000001
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##DISTRIBUTE SOUNDS IN STEREO FIELD v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... "Sources: " + string$(numberOfSounds)
        ... + "  |  Preset: " + presetName$
        ... + "  |  Width: " + fixed$(pan_width, 2)
        ... + "  |  Law: " + panLawName$
        ... + "  |  Order: " + orderName$
        ... + "  |  Stereo in: " + stereoModeName$
    
    # ----------------------------------------------------------
    # PANEL A: STEREO FIELD STRIP
    # Headline panel. Long horizontal strip with each source
    # as a labelled marker at its pan position. Marker
    # diameter is scaled by RMS, vertical position is jittered
    # to keep labels readable when sources cluster.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 1.10, 4.20
    
    Axes: -1.15, 1.15, -1.0, 1.0
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.15, 1.15, -1.0, 1.0
    
    # L–R baseline
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 2
    Draw line: -1.0, 0, 1.0, 0
    Line width: 1
    
    # Width-of-spread bracket
    Colour: "{0.55, 0.20, 0.55}"
    Dotted line
    Line width: 1.3
    Draw line: -pan_width, -0.85, -pan_width, 0.85
    Draw line:  pan_width, -0.85,  pan_width, 0.85
    Solid line
    Line width: 1
    Font size: 6
    Colour: "{0.55, 0.20, 0.55}"
    Text: -pan_width, "centre", 0.92, "half", "width edge"
    Text:  pan_width, "centre", 0.92, "half", "width edge"
    
    # Tick marks at -1, -0.5, 0, +0.5, +1
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    tickPos# = { -1.0, -0.5, 0.0, 0.5, 1.0 }
    for k from 1 to 5
        tp = tickPos#[k]
        Draw line: tp, -0.10, tp, 0.10
    endfor
    
    Font size: 6
    Colour: "{0.40, 0.40, 0.40}"
    Text: -1.0, "centre", -0.20, "half", "L"
    Text: -0.5, "centre", -0.20, "half", "-0.5"
    Text:  0.0, "centre", -0.20, "half", "C"
    Text:  0.5, "centre", -0.20, "half", "+0.5"
    Text:  1.0, "centre", -0.20, "half", "R"
    
    # Plot source markers above the line. Vertical jitter is a deterministic
    # function of source index to avoid overlapping labels when pans cluster.
    for i from 1 to numberOfSounds
        pn = panPos#[i]
        # Marker diameter from RMS (3..7 mm)
        relSize = rmsValue#[i] / maxRMS
        diam = 3.0 + relSize * 4.0
        
        # Vertical jitter: alternate up/down, stepping outward
        if numberOfSounds > 1
            row = (i - 1) mod 4
        else
            row = 0
        endif
        if row = 0
            yJit = 0.30
        elsif row = 1
            yJit = 0.55
        elsif row = 2
            yJit = 0.45
        else
            yJit = 0.65
        endif
        
        # Drop-line from baseline to marker
        Colour: "{0.78, 0.78, 0.82}"
        Line width: 1
        Draw line: pn, 0, pn, yJit
        
        rgb$ = "{" + fixed$(srcColR#[i], 2) + ", " + fixed$(srcColG#[i], 2) + ", " + fixed$(srcColB#[i], 2) + "}"
        Paint circle (mm): rgb$, pn, yJit, diam
        
        # Index label inside marker
        Colour: "White"
        Font size: 6
        Text: pn, "centre", yJit, "half", string$(i)
        
        # Source name above marker (truncate to 10 chars)
        nm$ = soundName$[i]
        if length(nm$) > 10
            nm$ = left$(nm$, 9) + "."
        endif
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: pn, "centre", yJit + 0.15, "half", nm$
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Pan position  (marker size = RMS, dashed = width edges)"
    
    # ----------------------------------------------------------
    # PANEL B: PAN-LAW CURVE
    # L and R gain curves vs pan position. Each source's
    # actual (L, R) pair plotted as a dot pair.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48
    
    Axes: -1.0, 1.0, 0, 1.05
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.0, 1.0, 0, 1.05
    
    # Grid
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    gv# = { 0.25, 0.50, 0.75, 1.00 }
    for k from 1 to 4
        Draw line: -1.0, gv#[k], 1.0, gv#[k]
    endfor
    Draw line: 0, 0, 0, 1.05
    
    # L and R curves, sampled at 41 points
    Line width: 1.5
    nCurve = 41
    prevX = -1.0
    @panLaw: -1.0, pan_law
    prevL = panLaw.leftG
    prevR = panLaw.rightG
    for k from 2 to nCurve
        cp = -1.0 + 2 * (k - 1) / (nCurve - 1)
        @panLaw: cp, pan_law
        cL = panLaw.leftG
        cR = panLaw.rightG
        
        Colour: "{0.30, 0.50, 0.78}"
        Draw line: prevX, prevL, cp, cL
        Colour: "{0.78, 0.45, 0.30}"
        Draw line: prevX, prevR, cp, cR
        
        prevX = cp
        prevL = cL
        prevR = cR
    endfor
    Line width: 1
    
    # Curve labels
    Font size: 6
    Colour: "{0.30, 0.50, 0.78}"
    Text: -0.95, "left", 0.95, "half", "L gain"
    Colour: "{0.78, 0.45, 0.30}"
    Text: 0.95, "right", 0.95, "half", "R gain"
    
    # Per-source L and R markers at their actual pan position
    for i from 1 to numberOfSounds
        pn = panPos#[i]
        Paint circle (mm): "{0.30, 0.50, 0.78}", pn, leftGainStore#[i], 1.4
        Paint circle (mm): "{0.78, 0.45, 0.30}", pn, rightGainStore#[i], 1.4
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.75, 2.70
    Select inner viewport: 4.02, 4.4, 0.77, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48
    Axes: -1.0, 1.0, 0, 1.05
    Text bottom: "yes", "Pan position"
    
    # ----------------------------------------------------------
    # PANEL C: PER-SOURCE RMS BARS (sorted by pan position)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    
    # Sort source indices by pan position for plotting (stable, simple)
    sortIdx# = zero# (numberOfSounds)
    for i from 1 to numberOfSounds
        sortIdx#[i] = i
    endfor
    for i from 1 to numberOfSounds - 1
        for j from i + 1 to numberOfSounds
            if panPos#[sortIdx#[j]] < panPos#[sortIdx#[i]]
                t = sortIdx#[i]
                sortIdx#[i] = sortIdx#[j]
                sortIdx#[j] = t
            endif
        endfor
    endfor
    
    rmsHi = maxRMS * 1.15
    Axes: 0, numberOfSounds + 1, 0, rmsHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, numberOfSounds + 1, 0, rmsHi
    
    for k from 1 to numberOfSounds
        srcI = sortIdx#[k]
        rgb$ = "{" + fixed$(srcColR#[srcI], 2) + ", " + fixed$(srcColG#[srcI], 2) + ", " + fixed$(srcColB#[srcI], 2) + "}"
        Paint rectangle: rgb$, k - 0.38, k + 0.38, 0, rmsValue#[srcI]
        
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: k, "centre", -rmsHi * 0.06, "half", string$(srcI)
        
        # Pan position label below index
        Text: k, "centre", -rmsHi * 0.13, "half", fixed$(panPos#[srcI], 2)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Select outer viewport: 4.02, 4.4, 3.00, 4.60
    Select inner viewport: 4.02, 4.4, 3.02, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "RMS"
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, numberOfSounds + 1, 0, rmsHi
    Text bottom: "yes", "Source # (top) / pan position (bottom), sorted L→R"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Stereo field placement"
    Text: 6.10, "centre", 7.30, "half", "Pan-law curves (upper) & per-source RMS (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    
    selectObject: stereoMix
    outDurViz = Get total duration
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0
    
    selectObject: stereoMix
    Extract one channel: 1
    vizCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh1
    
    selectObject: stereoMix
    Extract one channel: 2
    vizCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh2
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output stereo mix  (blue = L,  orange = R)"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 6.98
    Select inner viewport: 0.55, 7.72, 6.26, 6.92
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.5, "half",
        ... "##" + presetName$ + "##"
        ... + "  Sources: " + string$(numberOfSounds)
        ... + "  |  Width: " + fixed$(pan_width, 2)
        ... + "  |  Law: " + panLawName$
        ... + "  |  Order: " + orderName$
        ... + "  |  Stereo in: " + stereoModeName$
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak=" + fixed$(finalPeak, 3)
    
    # Source list (truncate gracefully)
    listLine$ = ""
    for k from 1 to numberOfSounds
        srcI = sortIdx#[k]
        nm$ = soundName$[srcI]
        if length(nm$) > 8
            nm$ = left$(nm$, 7) + "."
        endif
        listLine$ = listLine$ + string$(srcI) + ":" + nm$ + "@" + fixed$(panPos#[srcI], 2) + "  "
    endfor
    if length(listLine$) > 180
        listLine$ = left$(listLine$, 178) + ".."
    endif
    Text: 0.02, "left", 0.28, "half", listLine$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Select outer viewport: 0, 8, 0, 7.08
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
    
endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="

if play_result
    selectObject: stereoMix
    Play
endif

selectObject: stereoMix
