# ============================================================
# Praat AudioTools - Partial_Panner.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Harmonic Spray / Partial Panner. Splits the spectrum into N
#   logarithmic bands and pans each band to a different azimuth
#   in a 2 / 4 / 6 / 8-channel field. Creates spatial width by
#   distributing spectral content around the listener.
#
#   Design choices:
#     - Logarithmic band spacing
#     - Q-based proportional bandwidth (constant in octaves)
#     - S-curve mapping for perceptually smoother spatial spread
#     - Frequency-dependent pan width (low-freq stays near center)
#     - LF protection (mono-safe bass)
#     - VBAP-style 2-speaker activation for N>2 (constant power)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - HEADLINE: multichannel output. Number_of_channels form
#     parameter takes 2, 4, 6, or 8. At N=2, behavior matches v0.2
#     exactly (cosine/sine pan to L/R). At N>2, speakers are placed
#     on a ring at evenly-spaced azimuths starting at 0° (front),
#     and each band's pan position maps to an azimuth on a
#     user-controlled arc. Gains use VBAP-style 2-speaker
#     activation: each band activates the two adjacent ring
#     speakers with cos/sin weights — constant power, no phantom
#     image collapse.
#   - NEW: Spread_arc_degrees form parameter. Replaces the
#     fixed L/R interpretation of pan_width. Default 180°
#     = full front-to-back arc. 90° = front quadrant only.
#     360° = full ring (bands wrap around the listener).
#     For N=2 (stereo), arc is forced to 180° internally;
#     pan_width still scales the arc usage [0..1].
#   - Fix: removed redundant `Formula: "self * 0.668"` pan-law
#     scaling. It was a fixed -3.5 dB attenuation followed by
#     `Scale peak: 0.99` which overrode it. Pure waste of work.
#   - Fix: dry signal now built via Convert to stereo (or
#     Create Sound from formula for N>2). v0.2 made two copies
#     of the mono sound and combined them — same result, twice
#     the work and twice the cleanup.
#   - Fix: formula syntax modernized — Object_<id>[col] replaced
#     with object[<id>, col] throughout. Channel/sample ordering
#     fixed in the dry-mix formula (was [col, row], now
#     [row, col] which is the correct convention).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (headline): speaker layout (polar for N>=4,
#         horizontal bar for N=2) with bands placed at azimuths
#       Panel B: gain matrix per band per channel (heatmap)
#       Panel C: frequency-dependent pan-width curve, showing
#         how the effective spread varies across frequency
#       Panel D: output waveform (Ch1 blue, Ch2 orange)
#       Panel E: summary stats bar
# Changelog v0.2:
#   - Efficient accumulation via Formula
#   - Modern selectObject: syntax
#   - Fixed undefined preset$, division-by-zero, visualization
# ============================================================

clearinfo

form Partial Panner v0.3 (Multichannel)
    comment ─────────────────────────────────────────
    comment Preset
    optionmenu Preset: 3
        option Custom
        option Subtle Widening
        option Standard Spread
        option Extreme Spray
        option Reverse (High->L, Low->R)
        option Dense Shimmer
        option Coarse Texture
        option Quad Surround (4ch)
        option Octagon Spray (8ch)
    comment ─────────────────────────────────────────
    optionmenu Number_of_channels: 1
        option 2 (stereo)
        option 4 (quad)
        option 6 (hex)
        option 8 (octagon)
    positive Number_of_bands 8
    real Pan_width 0.8
    comment (0 = mono, 1 = full spread along the arc, neg = reverse)
    real Bandwidth_octaves 0.5
    comment (0.25 = narrow, 1.0 = wide)
    real Spread_arc_degrees 180
    comment (180 = full front, 360 = full ring around listener)
    comment ─────────────────────────────────────────
    positive LF_protection_Hz 150
    positive Min_frequency_Hz 80
    positive Max_frequency_Hz 16000
    comment ─────────────────────────────────────────
    real Dry_wet_mix 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESET SYSTEM
# ============================================================

if preset = 2
    number_of_channels = 1
    number_of_bands = 6
    pan_width = 0.5
    bandwidth_octaves = 0.5
    spread_arc_degrees = 180
    presetName$ = "Subtle"
elsif preset = 3
    number_of_channels = 1
    number_of_bands = 8
    pan_width = 0.8
    bandwidth_octaves = 0.5
    spread_arc_degrees = 180
    presetName$ = "Standard"
elsif preset = 4
    number_of_channels = 1
    number_of_bands = 16
    pan_width = 1.0
    bandwidth_octaves = 0.33
    spread_arc_degrees = 180
    presetName$ = "Extreme"
elsif preset = 5
    number_of_channels = 1
    number_of_bands = 10
    pan_width = -0.9
    bandwidth_octaves = 0.5
    spread_arc_degrees = 180
    presetName$ = "Reverse"
elsif preset = 6
    number_of_channels = 1
    number_of_bands = 20
    pan_width = 0.7
    bandwidth_octaves = 0.33
    spread_arc_degrees = 180
    presetName$ = "Dense"
elsif preset = 7
    number_of_channels = 1
    number_of_bands = 4
    pan_width = 1.0
    bandwidth_octaves = 1.0
    spread_arc_degrees = 180
    presetName$ = "Coarse"
elsif preset = 8
    number_of_channels = 2
    number_of_bands = 12
    pan_width = 1.0
    bandwidth_octaves = 0.5
    spread_arc_degrees = 360
    presetName$ = "Quad360"
elsif preset = 9
    number_of_channels = 4
    number_of_bands = 16
    pan_width = 1.0
    bandwidth_octaves = 0.33
    spread_arc_degrees = 360
    presetName$ = "Octagon360"
else
    presetName$ = "Custom"
endif

# Decode the optionmenu index to actual channel count
if number_of_channels = 1
    nCh = 2
elsif number_of_channels = 2
    nCh = 4
elsif number_of_channels = 3
    nCh = 6
else
    nCh = 8
endif

# ============================================================
# VALIDATION
# ============================================================

if numberOfSelected("Sound") = 0
    exitScript: "Please select a Sound object first."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
nInputCh = Get number of channels

# Clamp parameters
if number_of_bands < 1
    number_of_bands = 1
endif
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif
if spread_arc_degrees < 10
    spread_arc_degrees = 10
endif
if spread_arc_degrees > 360
    spread_arc_degrees = 360
endif

maxFreq = min(max_frequency_Hz, sr / 2 * 0.95)
minFreq = min_frequency_Hz

# ============================================================
# COMPUTE SPEAKER ANGLES (azimuths in radians)
# Convention: 0° = front (+y), 90° = right (+x), measured clockwise
# ============================================================

for s from 1 to nCh
    if nCh = 2
        # Stereo: speakers at -90 and +90 (left, right)
        if s = 1
            spkAzDeg[s] = 270
        else
            spkAzDeg[s] = 90
        endif
    else
        spkAzDeg[s] = (s - 1) * 360 / nCh
    endif
    spkAzRad[s] = spkAzDeg[s] * pi / 180
endfor

# ============================================================
# INFO OUTPUT
# ============================================================

writeInfoLine: "============================================"
appendInfoLine: "Partial Panner v0.3"
appendInfoLine: "============================================"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: "Output channels: ", nCh
appendInfoLine: "--------------------------------------------"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Bands: ", number_of_bands
appendInfoLine: "Pan width: ", fixed$(pan_width, 2)
appendInfoLine: "Bandwidth: ", fixed$(bandwidth_octaves, 2), " octaves"
appendInfoLine: "Spread arc: ", fixed$(spread_arc_degrees, 0), " degrees"
appendInfoLine: "LF protection: ", lF_protection_Hz, " Hz"
appendInfoLine: "Frequency range: ", minFreq, " - ", fixed$(maxFreq, 0), " Hz"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "%"
appendInfoLine: "--------------------------------------------"
appendInfoLine: ""

# ============================================================
# CONVERT INPUT TO MONO
# ============================================================

selectObject: original
if nInputCh > 1
    monoSound = Convert to mono
else
    monoSound = Copy: "mono_temp"
endif

# ============================================================
# CALCULATE BAND PARAMETERS
# Per-band:
#   bandCenter, bandLow, bandHigh — in Hz
#   bandAzDeg                     — target azimuth (degrees, 0=front, 90=right)
#   bandGain[s]                   — gain into speaker s (constant power)
# ============================================================

appendInfoLine: "Calculating band parameters..."

# Build a 2D-as-1D array bandGain[band, speaker] = bandGainFlat[(band-1)*nCh + speaker]
totalSlots = number_of_bands * nCh
bandGainFlat# = zero# (totalSlots)

for i from 1 to number_of_bands
    # Logarithmic band center
    bandCenter[i] = minFreq * (maxFreq / minFreq) ^ ((i - 0.5) / number_of_bands)
    
    # Q-based bandwidth
    bwMultiplier = 2 ^ bandwidth_octaves
    bandLow[i] = bandCenter[i] / sqrt(bwMultiplier)
    bandHigh[i] = bandCenter[i] * sqrt(bwMultiplier)
    
    # Normalized position [0, 1] across bands
    if number_of_bands > 1
        normPos = (i - 1) / (number_of_bands - 1)
    else
        normPos = 0.5
    endif
    
    # S-curve mapping for smoother distribution
    sCurveInput = (normPos * 2 - 1) * 2.5
    sCurveOutput = (exp(2 * sCurveInput) - 1) / (exp(2 * sCurveInput) + 1)
    
    # Frequency-dependent width scaling
    freqNorm = ln(bandCenter[i] / minFreq) / ln(maxFreq / minFreq)
    freqScale = 0.3 + 0.7 * (freqNorm ^ 0.7)
    
    # LF protection
    if bandCenter[i] < lF_protection_Hz
        lfScale = (bandCenter[i] / lF_protection_Hz) ^ 2
        freqScale = freqScale * (0.2 + 0.8 * lfScale)
    endif
    
    # Effective pan position in [-1, +1] range
    effectiveWidth = pan_width * freqScale
    panNorm = sCurveOutput * effectiveWidth
    
    # Map [-1, +1] to azimuth degrees over the spread arc
    # Center of arc is at 0° (front). Half the arc goes left (negative azimuth)
    # half goes right (positive). For arc=360, we wrap fully.
    halfArc = spread_arc_degrees / 2
    azDeg = panNorm * halfArc
    # Normalize to [0, 360)
    azDeg = azDeg + 360
    azDeg = azDeg - 360 * floor(azDeg / 360)
    bandAzDeg[i] = azDeg
    
    # ---- Compute per-speaker gains (VBAP-style 2-speaker activation) ----
    # Find the two adjacent ring speakers and use cos/sin weighting.
    if nCh = 2
        # Stereo: classic constant-power L/R
        # Map azimuth to pan angle in [0, pi/2]:
        #   azDeg=270 (left) -> panAngle=0  -> gainL=1, gainR=0
        #   azDeg=90  (right) -> panAngle=pi/2 -> gainL=0, gainR=1
        # Convert: panAngle = (panNorm + 1) / 2 * pi/2 — same as v0.2
        panAngle = (panNorm + 1) / 2 * pi / 2
        gainL = cos(panAngle)
        gainR = sin(panAngle)
        bandGainFlat#[(i - 1) * nCh + 1] = gainL
        bandGainFlat#[(i - 1) * nCh + 2] = gainR
    else
        # Multichannel: find two adjacent speakers bracketing azDeg
        # Speakers are at evenly-spaced angles 0, 360/nCh, 2*360/nCh, ...
        seg = 360 / nCh
        idx_floor = floor(azDeg / seg)  ; 0..nCh-1
        idx_next  = (idx_floor + 1) mod nCh
        local_az = azDeg - idx_floor * seg  ; 0..seg
        local_norm = local_az / seg          ; 0..1
        
        # Constant-power between adjacent speakers
        local_angle = local_norm * pi / 2
        gain_low  = cos(local_angle)
        gain_high = sin(local_angle)
        
        # All other speakers get 0
        for s from 1 to nCh
            bandGainFlat#[(i - 1) * nCh + s] = 0
        endfor
        bandGainFlat#[(i - 1) * nCh + idx_floor + 1] = gain_low
        bandGainFlat#[(i - 1) * nCh + idx_next + 1]  = gain_high
    endif
endfor

# ============================================================
# CREATE OUTPUT — N-CHANNEL CANVAS  (single-allocate-and-fill)
# ============================================================

wetMulti = Create Sound from formula: "wet_multi", nCh, 0, duration, sr, "0"

# ============================================================
# PROCESS EACH BAND
# Filter the mono source into the band, then add to each
# output channel scaled by that channel's gain for this band.
# ============================================================

appendInfoLine: "Processing ", number_of_bands, " bands into ", nCh, " channels..."

for i from 1 to number_of_bands
    # Progress
    if i mod 4 = 0 or i = number_of_bands
        appendInfoLine: "  Band ", i, "/", number_of_bands,
            ... ":  ", fixed$(bandCenter[i], 0), " Hz",
            ... "  -> az=", fixed$(bandAzDeg[i], 1), "°"
    endif
    
    # Filter the mono source for this band
    smoothHz = (bandHigh[i] - bandLow[i]) / 6
    
    selectObject: monoSound
    filtered = Filter (pass Hann band): bandLow[i], bandHigh[i], smoothHz
    filteredIdStr$ = string$(filtered)
    
    # Add this band into each output channel scaled by its gain
    for s from 1 to nCh
        gainV = bandGainFlat#[(i - 1) * nCh + s]
        if gainV <> 0
            gainStr$ = fixed$(gainV, 10)
            selectObject: wetMulti
            Formula (part): 0, duration, s, s,
                ... "self + " + gainStr$ + " * object[" + filteredIdStr$ + ", col]"
        endif
    endfor
    
    removeObject: filtered
endfor

# ============================================================
# DRY SIGNAL  (centered, replicated across all output channels)
# Replaces v0.2's two-copy + Combine to stereo dance.
# ============================================================

if dry_wet_mix < 1.0
    dryMulti = Create Sound from formula: "dry_multi", nCh, 0, duration, sr, "0"
    monoIdStr$ = string$(monoSound)
    
    selectObject: dryMulti
    # Each output channel gets the mono source content
    for s from 1 to nCh
        Formula (part): 0, duration, s, s,
            ... "object[" + monoIdStr$ + ", col]"
    endfor
endif

# ============================================================
# MIX DRY/WET
# ============================================================

wetLevel = dry_wet_mix
dryLevel = 1 - dry_wet_mix
wetStr$ = fixed$(wetLevel, 10)
dryStr$ = fixed$(dryLevel, 10)

selectObject: wetMulti
result = Copy: originalName$ + "_spray_" + presetName$ + "_" + string$(nCh) + "ch"

if dry_wet_mix < 1.0
    dryIdStr$ = string$(dryMulti)
    selectObject: result
    Formula: "self * " + wetStr$ + " + object[" + dryIdStr$ + ", row, col] * " + dryStr$
endif

selectObject: result
Scale peak: 0.99

# ============================================================
# CLEANUP
# ============================================================

removeObject: wetMulti, monoSound
if dry_wet_mix < 1.0
    removeObject: dryMulti
endif

# ============================================================
# FINAL STATS
# ============================================================

selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # Per-band perceptual color gradient (cool blue -> warm red)
    bandColR# = zero# (number_of_bands)
    bandColG# = zero# (number_of_bands)
    bandColB# = zero# (number_of_bands)
    for i from 1 to number_of_bands
        progress = (i - 1) / max(1, number_of_bands - 1)
        if progress < 0.5
            t = progress * 2
            bandColR#[i] = 0.20 + t * 0.55
            bandColG#[i] = 0.45 + t * 0.30
            bandColB#[i] = 0.80 - t * 0.45
        else
            t = (progress - 0.5) * 2
            bandColR#[i] = 0.75 + t * 0.15
            if bandColR#[i] > 1
                bandColR#[i] = 1
            endif
            bandColG#[i] = 0.75 - t * 0.45
            bandColB#[i] = 0.35 - t * 0.20
            if bandColB#[i] < 0
                bandColB#[i] = 0
            endif
        endif
    endfor
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PARTIAL PANNER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(number_of_bands) + " bands"
        ... + "  |  " + string$(nCh) + "ch"
        ... + "  |  Width: " + fixed$(pan_width, 2)
        ... + "  |  Arc: " + fixed$(spread_arc_degrees, 0) + "°"
        ... + "  |  Mix: " + fixed$(dry_wet_mix * 100, 0) + "%"
    
    # ----------------------------------------------------------
    # PANEL A: SPEAKER LAYOUT WITH BAND PLACEMENTS  (left, headline)
    # Stereo (N=2): horizontal pan-vs-frequency line.
    # Multichannel (N>=4): polar plot with speakers at ring positions
    # and band markers placed at their azimuths, sized by frequency.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    if nCh = 2
        # ---- STEREO horizontal layout ----
        minLogF = ln(minFreq)
        maxLogF = ln(maxFreq)
        
        Axes: minLogF, maxLogF, -1.2, 1.2
        Paint rectangle: "{0.96, 0.96, 0.96}", minLogF, maxLogF, -1.2, 1.2
        
        # Centerline + L/R reference
        Colour: "{0.78, 0.78, 0.85}"
        Line width: 1
        Draw line: minLogF, 0, maxLogF, 0
        Draw line: minLogF, -1, maxLogF, -1
        Draw line: minLogF, 1, maxLogF, 1
        
        # LF protection zone
        if lF_protection_Hz > minFreq
            lfLogF = ln(lF_protection_Hz)
            Paint rectangle: "{0.94, 0.88, 0.88}", minLogF, lfLogF, -1.2, 1.2
        endif
        
        # L/C/R labels
        Font size: 6
        Colour: "{0.45, 0.45, 0.50}"
        Text: minLogF + (maxLogF - minLogF) * 0.01, "left", -1, "half", "L"
        Text: minLogF + (maxLogF - minLogF) * 0.01, "left", 0, "half", "C"
        Text: minLogF + (maxLogF - minLogF) * 0.01, "left", 1, "half", "R"
        
        # Plot bands
        for i from 1 to number_of_bands
            logCenter = ln(bandCenter[i])
            logLow = ln(bandLow[i])
            logHigh = ln(bandHigh[i])
            # Convert azimuth back to pan position [-1, +1]
            # azDeg=270 -> -1, azDeg=90 -> +1
            azD = bandAzDeg[i]
            if azD > 180
                azD = azD - 360
            endif
            panPos = azD / 90
            
            rgb$ = "{" + fixed$(bandColR#[i], 2) + ","
                ... + fixed$(bandColG#[i], 2) + ","
                ... + fixed$(bandColB#[i], 2) + "}"
            Paint rectangle: rgb$, logLow, logHigh, panPos - 0.05, panPos + 0.05
            Line width: 1.5
            Colour: rgb$
            Draw line: logCenter, 0, logCenter, panPos
            Paint circle (mm): rgb$, logCenter, panPos, 1.6
        endfor
        
        # Frequency markers
        Font size: 5
        Colour: "{0.45, 0.45, 0.45}"
        fLabels# = { 100, 200, 500, 1000, 2000, 5000, 10000 }
        for k from 1 to size(fLabels#)
            fL = fLabels#[k]
            if fL >= minFreq and fL <= maxFreq
                logFL = ln(fL)
                Colour: "{0.85, 0.85, 0.88}"
                Draw line: logFL, -1.18, logFL, -1.10
                Colour: "{0.45, 0.45, 0.45}"
                if fL < 1000
                    Text: logFL, "centre", -1.30, "half", string$(fL)
                else
                    Text: logFL, "centre", -1.30, "half", fixed$(fL/1000, 0) + "k"
                endif
            endif
        endfor
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Text left: "yes", "Pan position"
        Text bottom: "yes", "Frequency (Hz, log)"
    else
        # ---- MULTICHANNEL polar layout ----
        Axes: -1.4, 1.4, -1.4, 1.4
        Paint rectangle: "{0.96, 0.96, 0.96}", -1.4, 1.4, -1.4, 1.4
        
        # Concentric guides
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        rGuide# = { 0.40, 0.80, 1.10 }
        for k from 1 to 3
            rg = rGuide#[k]
            prevX = rg
            prevY = 0
            for h from 1 to 64
                a = 2 * pi * h / 64
                cx = rg * cos(a)
                cy = rg * sin(a)
                Draw line: prevX, prevY, cx, cy
                prevX = cx
                prevY = cy
            endfor
        endfor
        
        # Crosshairs
        Colour: "{0.78, 0.78, 0.82}"
        Dotted line
        Draw line: -1.30, 0, 1.30, 0
        Draw line: 0, -1.30, 0, 1.30
        Solid line
        
        # Speaker positions (compass: 0°=front=+y, 90°=right=+x)
        for s from 1 to nCh
            sx = 1.10 * sin(spkAzRad[s])
            sy = 1.10 * cos(spkAzRad[s])
            Paint circle (mm): "{0.45, 0.45, 0.55}", sx, sy, 3.5
            Colour: "White"
            Font size: 6
            Text: sx, "centre", sy, "half", string$(s)
        endfor
        
        # Listener
        Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 3.5
        Colour: "White"
        Font size: 6
        Text: 0, "centre", 0, "half", "L"
        
        # Band positions (radial position scales with band index/freq)
        for i from 1 to number_of_bands
            azR = bandAzDeg[i] * pi / 180
            # Distance from center scales with frequency: low = closer to center
            freqNorm = ln(bandCenter[i] / minFreq) / ln(maxFreq / minFreq)
            r = 0.40 + 0.60 * freqNorm
            bx = r * sin(azR)
            by = r * cos(azR)
            
            rgb$ = "{" + fixed$(bandColR#[i], 2) + ","
                ... + fixed$(bandColG#[i], 2) + ","
                ... + fixed$(bandColB#[i], 2) + "}"
            Paint circle (mm): rgb$, bx, by, 1.4
        endfor
        
        # Cardinal labels
        Font size: 5
        Colour: "{0.45, 0.45, 0.50}"
        Text: 0, "centre", 1.32, "half", "FRONT 0°"
        Text: 0, "centre", -1.32, "half", "BACK 180°"
        Text: 1.32, "centre", 0, "half", "R"
        Text: -1.32, "centre", 0, "half", "L"
        
        Colour: "Black"
        Line width: 1
        Draw inner box
    endif
    
    # ----------------------------------------------------------
    # PANEL B: GAIN MATRIX  (right, upper)
    # Heatmap: rows = bands, columns = output channels.
    # Color intensity = gain. Empty cells = 0 (band silent on that ch).
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.95, 2.85
    
    Axes: 0, nCh, 0, number_of_bands
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, nCh, 0, number_of_bands
    
    # Cells
    for i from 1 to number_of_bands
        for s from 1 to nCh
            g = bandGainFlat#[(i - 1) * nCh + s]
            if g > 0.01
                # Color: green-ish hot for high gain, fade to background for low
                cR = 0.94 - g * 0.50
                cG = 0.94 - g * 0.20
                cB = 0.94 - g * 0.50
                clr$ = "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}"
                Paint rectangle: clr$, s - 1, s, number_of_bands - i, number_of_bands - i + 1
            endif
        endfor
    endfor
    
    # Grid lines
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    for s from 0 to nCh
        Draw line: s, 0, s, number_of_bands
    endfor
    for i from 0 to number_of_bands
        Draw line: 0, i, nCh, i
    endfor
    
    # Channel labels
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    for s from 1 to nCh
        Text: s - 0.5, "centre", -number_of_bands * 0.04, "half", "C" + string$(s)
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Band (high -> low)"
    Text bottom: "yes", "Channel"
    
    # ----------------------------------------------------------
    # PANEL C: FREQUENCY-DEPENDENT WIDTH CURVE  (right, lower)
    # Shows the effective pan-width as a function of frequency.
    # Reveals how the LF-protection and frequency-scaling
    # combine to limit low-freq spread.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.20, 4.50
    
    minLogF = ln(minFreq)
    maxLogF = ln(maxFreq)
    
    Axes: minLogF, maxLogF, 0, 1.05
    Paint rectangle: "{0.96, 0.96, 0.96}", minLogF, maxLogF, 0, 1.05
    
    # 1.0 reference
    Colour: "{0.78, 0.65, 0.78}"
    Dotted line
    Draw line: minLogF, 1.0, maxLogF, 1.0
    Solid line
    
    # LF protection line
    if lF_protection_Hz > minFreq
        lfLogF = ln(lF_protection_Hz)
        Colour: "{0.85, 0.55, 0.55}"
        Dotted line
        Draw line: lfLogF, 0, lfLogF, 1.05
        Solid line
        Font size: 5
        Colour: "{0.65, 0.45, 0.45}"
        Text: lfLogF, "left", 0.10, "half", " LF protect"
    endif
    
    # Sample the freqScale curve at the band centers
    Colour: "{0.30, 0.55, 0.50}"
    Line width: 1.5
    prevLogF = minLogF
    prevScale = 0
    nSamples = 80
    for k from 1 to nSamples
        progress = (k - 0.5) / nSamples
        logF = minLogF + progress * (maxLogF - minLogF)
        f = exp(logF)
        freqNorm = (logF - minLogF) / (maxLogF - minLogF)
        fScale = 0.3 + 0.7 * (freqNorm ^ 0.7)
        if f < lF_protection_Hz
            lfS = (f / lF_protection_Hz) ^ 2
            fScale = fScale * (0.2 + 0.8 * lfS)
        endif
        if k > 1
            Draw line: prevLogF, prevScale, logF, fScale
        endif
        prevLogF = logF
        prevScale = fScale
    endfor
    Line width: 1
    
    # Mark the band centers as dots on the curve
    for i from 1 to number_of_bands
        logCenter = ln(bandCenter[i])
        freqNorm = (logCenter - minLogF) / (maxLogF - minLogF)
        fScale = 0.3 + 0.7 * (freqNorm ^ 0.7)
        if bandCenter[i] < lF_protection_Hz
            lfS = (bandCenter[i] / lF_protection_Hz) ^ 2
            fScale = fScale * (0.2 + 0.8 * lfS)
        endif
        rgb$ = "{" + fixed$(bandColR#[i], 2) + ","
            ... + fixed$(bandColG#[i], 2) + ","
            ... + fixed$(bandColB#[i], 2) + "}"
        Paint circle (mm): rgb$, logCenter, fScale, 1.2
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Effective width"
    Text bottom: "yes", "Frequency (Hz)"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    if nCh = 2
        Text: 2.10, "centre", 7.30, "half", "Stereo pan layout"
    else
        Text: 2.10, "centre", 7.30, "half", string$(nCh) + "-channel ring layout"
    endif
    Text: 6.10, "centre", 7.30, "half", "Gain matrix (upper) & freq-dependent width (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: result
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    Extract one channel: 1
    vCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh1
    
    if nResultCh >= 2
        selectObject: result
        Extract one channel: 2
        vCh2 = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh2
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh = 2
        Text top: "no", "Output  (blue=L  orange=R)"
    else
        Text top: "no", "Output  (Ch1 blue, Ch2 orange — " + string$(nResultCh) + " channels total)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Channels: " + string$(nCh)
        ... + "  |  Bands: " + string$(number_of_bands)
        ... + "  |  Width: " + fixed$(pan_width, 2)
        ... + "  |  Arc: " + fixed$(spread_arc_degrees, 0) + "°"
        ... + "  |  BW: " + fixed$(bandwidth_octaves, 2) + " oct"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Range: " + string$(minFreq) + "-" + fixed$(maxFreq, 0) + " Hz"
        ... + "  |  LF protect: " + string$(lF_protection_Hz) + " Hz"
        ... + "  |  Mix: " + fixed$(dry_wet_mix * 100, 0) + "%"
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# DONE
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "PROCESSING COMPLETE"
appendInfoLine: "============================================"
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Channels: ", nResultCh
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
