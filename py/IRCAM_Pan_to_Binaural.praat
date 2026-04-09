# ============================================================
# Praat AudioTools - IRCAM_Pan_to_Binaural.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9 (2026) - Python Bridge Edition
# License: MIT License
#
# Description:
#   Mono/stereo → HOA encode → HOA decode → binaural (3-stage pipeline).
#   Stage 1: spat5.hoa.encoder~    source + position → HOA WAV
#   Stage 2: spat5.hoa.decoder~    HOA WAV → speaker-layout WAV
#   Stage 3: spat5.virtualspeakers~ speaker WAV → stereo binaural WAV
#
# Movement mode:
#   When movement_enabled = ON the source position is animated over
#   the duration of the sound. The audio is sliced into chunks
#   (movement_chunk_dur seconds each); each chunk is encoded at its
#   own azimuth, rendered through the full HOA pipeline, then all
#   chunks are concatenated.
#
#   Trajectory types (ported from DBAP_with_Movement_Control.praat):
#     1. Linear    — straight sweep from start_az to end_az
#     2. Circular  — full rotation around the listener
#     3. Figure-8  — horizontal figure-of-eight
#     4. Spiral In — inward spiral (fades to centre)
#     5. Spiral Out— outward spiral (grows from centre)
#     6. Pendulum  — swinging arc
#     7. Zigzag    — back-and-forth lateral sweeps
#     8. Random Walk — quasi-random golden-angle path
#     9. Ellipse   — wide horizontal, narrow depth ellipse
#    10. Square    — four-sided path
#
#   Coordinate convention (matches Spat5 AE):
#     azimuth 0° = front, +90° = right, ±180° = back
#     elevation fixed to the form value (all trajectories are 2D)
#     XY → azimuth: az = arctan2 (srcX, srcY) × 180/π
#       srcY+ = front, srcX+ = right
#
# HOA channel counts (3D):
#   order 1→4ch  order 2→9ch  order 3→16ch
#   order 4→25ch  order 5→36ch
#
# Pre-gain calibration (order 1, N3D, 4.0):
#   HOA chain adds ~+7 dB. Default pre_gain_db = -9 dB.
# ============================================================

form IRCAM Pan to Binaural

    comment === POSITION / MOVEMENT ===
    boolean movement_enabled 0
    real azimuth 0
    real elevation 0
    optionmenu movement_type: 2
        option "1. Linear  (start_az -> end_az)"
        option "2. Circular"
        option "3. Figure-8"
        option "4. Spiral In"
        option "5. Spiral Out"
        option "6. Pendulum"
        option "7. Zigzag"
        option "8. Random Walk"
        option "9. Ellipse"
        option "10. Square"
    real start_az -90
    real end_az 90
    real trajectory_radius 0.8
    real trajectory_speed 1.0
    positive movement_chunk_dur 0.5
    real xfade_dur 0.1

    comment === SOURCE / HOA ===
    real stereo_spread_deg 60
    optionmenu hoa_order: 1
        option "1  (4 ch)"
        option "2  (9 ch)"
        option "3  (16 ch)"
        option "4  (25 ch)"
        option "5  (36 ch)"
    optionmenu hoa_norm: 2
        option "SN3D"
        option "N3D"
        option "FuMa"
    optionmenu decode_layout: 2
        option "2.0  (2 ch)"
        option "4.0  (4 ch)"
        option "5.0  (5 ch)"
        option "7.0  (7 ch)"
        option "7.1  (8 ch)"
    real pre_gain_db -9

    comment === HRTF / ROOM ===
    optionmenu preset_management: 1
        option "Manual"
        option "KEMAR / neutral"
        option "KEMAR / hall"
        option "SOFA custom / none"
    sentence sofa_file kemar
    real itd_percent 100
    optionmenu room_preset: 1
        option "1. none"
        option "2. hall"
        option "3. living_room"
        option "4. studio"
        option "5. preset1"
        option "6. preset2"
        option "7. preset3"
        option "8. preset4"
        option "9. legacy1"
        option "10. legacy2"
        option "11. legacy3"

endform

# ============================================================
# Hardcoded / Internal Variables
# ============================================================
sum_to_mono = 1
play_output = 1
delete_temp_files = 1
verbose_log = 0

tools_folder$   = "C:/Users/User/Documents/Max 9/Packages/spat5-x64/media/tools/"
helper_py$      = defaultDirectory$ + "/spat_bridge.py"
working_folder$ = defaultDirectory$ + "/"

# ============================================================
# Guards
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
if not fileReadable (helper_py$)
    exitScript: "Python helper script not found exactly next to this script:" + newline$ + helper_py$
endif

# ============================================================
# Sound metadata
# ============================================================
sound      = selected ("Sound")
soundName$ = selected$ ("Sound")
selectObject: sound
duration  = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels

if nChannels <> 1 and nChannels <> 2
    exitScript: "Pan pipeline requires mono or stereo (" +
        ... string$ (nChannels) + " channels found)."
endif

# ============================================================
# Validate inputs
# ============================================================
if azimuth < -180 or azimuth > 180
    exitScript: "Azimuth out of range (" + fixed$ (azimuth, 1) + "). Expected -180..180."
endif
if elevation < -90 or elevation > 90
    exitScript: "Elevation out of range (" + fixed$ (elevation, 1) + "). Expected -90..90."
endif
if itd_percent < 0 or itd_percent > 200
    exitScript: "ITD% out of range (" + fixed$ (itd_percent, 1) + "). Expected 0-200."
endif

# ============================================================
# Resolve HOA order and channel count
# ============================================================
if hoa_order = 1
    actualOrder = 1
    hoaChannels = 4
elsif hoa_order = 2
    actualOrder = 2
    hoaChannels = 9
elsif hoa_order = 3
    actualOrder = 3
    hoaChannels = 16
elsif hoa_order = 4
    actualOrder = 4
    hoaChannels = 25
else
    actualOrder = 5
    hoaChannels = 36
endif

# ============================================================
# Resolve normalisation token
# ============================================================
if hoa_norm = 1
    normToken$ = "SN3D"
elsif hoa_norm = 2
    normToken$ = "N3D"
else
    normToken$ = "FuMa"
endif

# ============================================================
# Resolve decode layout & array for Plotting
# ============================================================
if decode_layout = 1
    layoutToken$ = "2.0"
    layoutChannels = 2
    numSpk = 2
    spkAz[1] = -30
    spkAz[2] = 30
elsif decode_layout = 2
    layoutToken$ = "4.0"
    layoutChannels = 4
    numSpk = 4
    spkAz[1] = -30
    spkAz[2] = 30
    spkAz[3] = -110
    spkAz[4] = 110
elsif decode_layout = 3
    layoutToken$ = "5.0"
    layoutChannels = 5
    numSpk = 5
    spkAz[1] = -30
    spkAz[2] = 30
    spkAz[3] = 0
    spkAz[4] = -110
    spkAz[5] = 110
elsif decode_layout = 4
    layoutToken$ = "7.0"
    layoutChannels = 7
    numSpk = 7
    spkAz[1] = -30
    spkAz[2] = 30
    spkAz[3] = 0
    spkAz[4] = -90
    spkAz[5] = 90
    spkAz[6] = -150
    spkAz[7] = 150
else
    layoutToken$ = "7.1"
    layoutChannels = 8
    numSpk = 8
    spkAz[1] = -30
    spkAz[2] = 30
    spkAz[3] = 0
    spkAz[4] = 0
    spkAz[5] = -90
    spkAz[6] = 90
    spkAz[7] = -150
    spkAz[8] = 150
endif

# ============================================================
# Resolve room token
# ============================================================
if room_preset = 1
    roomName$ = "none"
elsif room_preset = 2
    roomName$ = "hall"
elsif room_preset = 3
    roomName$ = "livingroom"
elsif room_preset = 4
    roomName$ = "studio"
elsif room_preset = 5
    roomName$ = "preset1"
elsif room_preset = 6
    roomName$ = "preset2"
elsif room_preset = 7
    roomName$ = "preset3"
elsif room_preset = 8
    roomName$ = "preset4"
elsif room_preset = 9
    roomName$ = "legacy1"
elsif room_preset = 10
    roomName$ = "legacy2"
else
    roomName$ = "legacy3"
endif

# ============================================================
# Apply HRTF preset
# ============================================================
actualSOFA$  = sofa_file$
actualITD    = itd_percent
presetName$  = "Manual"

if preset_management = 2
    actualSOFA$ = "kemar"
    actualITD = 100
    roomName$ = "none"
    presetName$ = "KEMAR / neutral"
elsif preset_management = 3
    actualSOFA$ = "kemar"
    actualITD = 100
    roomName$ = "hall"
    presetName$ = "KEMAR / hall"
elsif preset_management = 4
    actualSOFA$ = sofa_file$
    actualITD = 100
    roomName$ = "none"
    presetName$ = "SOFA custom / none"
endif

# ============================================================
# Normalise folder paths
# ============================================================
backslash$ = left$ ("/\", 2)
backslash$ = right$ (backslash$, 1)
if right$ (tools_folder$, 1) <> "/" and right$ (tools_folder$, 1) <> backslash$
    tools_folder$ = tools_folder$ + "/"
endif
if right$ (working_folder$, 1) <> "/" and right$ (working_folder$, 1) <> backslash$
    working_folder$ = working_folder$ + "/"
endif

# ============================================================
# Build HOA header and decoder preset (static — same for every chunk)
# ============================================================
hoaHeader$ = "/order " + string$ (actualOrder) + ", /dimension 3" + ", /norm " + normToken$

if decode_layout = 1
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0"
elsif decode_layout = 2
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae -110 0, /speaker/4/ae 110 0"
elsif decode_layout = 3
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -110 0, /speaker/5/ae 110 0"
elsif decode_layout = 4
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -90 0, /speaker/5/ae 90 0, /speaker/6/ae -150 0, /speaker/7/ae 150 0"
else
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae 0 -30, /speaker/5/ae -90 0, /speaker/6/ae 90 0, /speaker/7/ae -150 0, /speaker/8/ae 150 0"
endif

decoderPreset$ = hoaHeader$ + ", /speaker/number " + string$ (layoutChannels) + spkPos$

# ============================================================
# Determine source mode (for info and encoder preset building)
# ============================================================
if nChannels = 1 or sum_to_mono = 1
    sourceMode$ = "mono-sum"
else
    sourceMode$ = "stereo-spread"
endif

# ============================================================
# Temp file paths
# ============================================================
inputWav$   = working_folder$ + "pan_input.wav"
hoaWav$     = working_folder$ + "pan_hoa.wav"
speakerWav$ = working_folder$ + "pan_speakers.wav"
outputWav$  = working_folder$ + "pan_binaural.wav"
logTxt$     = working_folder$ + "pan_binaural_log.txt"

# ============================================================
# Movement: resolve trajectory name
# ============================================================
movementNames$[1]  = "Linear"
movementNames$[2]  = "Circular"
movementNames$[3]  = "Figure8"
movementNames$[4]  = "SpiralIn"
movementNames$[5]  = "SpiralOut"
movementNames$[6]  = "Pendulum"
movementNames$[7]  = "Zigzag"
movementNames$[8]  = "RandomWalk"
movementNames$[9]  = "Ellipse"
movementNames$[10] = "Square"

if movement_enabled
    movementName$ = movementNames$[movement_type]
else
    movementName$ = "Static"
endif

# ============================================================
# Info panel header
# ============================================================
writeInfoLine:  "=== IRCAM Pan to Binaural v0.9 (Python Bridge) ==="
appendInfoLine: "Source   : ", soundName$, "  (", nChannels, " ch  /  ",
    ... fixed$ (duration, 2), " s  @  ", sr, " Hz)"
appendInfoLine: "Mode     : ", sourceMode$
if movement_enabled
    appendInfoLine: "Movement : ", movementName$,
        ...  "  radius=", fixed$ (trajectory_radius, 2),
        ...  "  speed=", fixed$ (trajectory_speed, 2),
        ...  "  chunk=", fixed$ (movement_chunk_dur, 3), " s"
else
    appendInfoLine: "Position : az=", fixed$ (azimuth, 1),
        ...  "  el=", fixed$ (elevation, 1)
endif
appendInfoLine: "HOA      : order ", actualOrder, "  norm ", normToken$,
    ... "  layout ", layoutToken$
appendInfoLine: "HRTF     : ", presetName$, "  sofa=", actualSOFA$,
    ... "  itd=", fixed$ (actualITD, 1), "%  room=", roomName$
appendInfoLine: "Pre-gain : ", fixed$ (pre_gain_db, 1), " dB"

if verbose_log
    appendInfoLine: ""
    appendInfoLine: "[Verbose] DEC_PRESET: ", decoderPreset$
endif

appendInfoLine: ""

# ============================================================
# Prepare pre-gained working sound
# ============================================================
selectObject: sound

if nChannels = 2 and sum_to_mono = 1
    Convert to mono
    workID = selected ("Sound")
else
    Copy: "__pan_work"
    workID = selected ("Sound")
endif

if pre_gain_db <> 0
    selectObject: workID
    Multiply: 10 ^ (pre_gain_db / 20)
endif

selectObject: sound  ; restore selection

# ============================================================
# Helper procedure: build encoder preset
# ============================================================
procedure buildEncoderPreset: .az, .el
    if nChannels = 1 or sum_to_mono = 1
        encoderPreset$ = hoaHeader$ + ", /source/1/ae " + string$ (.az) + " " + string$ (.el)
    else
        .half = stereo_spread_deg / 2
        .azL  = .az + .half
        .azR  = .az - .half
        if .azL > 180
            .azL = .azL - 360
        endif
        if .azR < -180
            .azR = .azR + 360
        endif
        encoderPreset$ = hoaHeader$ + ", /source/1/ae " + string$ (.azL) + " " + string$ (.el) + ", /source/2/ae " + string$ (.azR) + " " + string$ (.el)
    endif
endproc

# ============================================================
# Helper procedure: render one chunk via Python Bridge
# ============================================================
procedure renderChunk: .tStart, .tEnd, .az, .el, .chunkNum
    @buildEncoderPreset: .az, .el

    if verbose_log
        appendInfoLine: "  [chunk ", .chunkNum, "]  az=", fixed$ (.az, 1),
            ...  "  t=", fixed$ (.tStart, 3), "-", fixed$ (.tEnd, 3)
    endif

    deleteFile: inputWav$
    deleteFile: hoaWav$
    deleteFile: speakerWav$
    deleteFile: outputWav$
    deleteFile: logTxt$

    .fetchEnd = min (.tEnd + xfade_dur, duration)
    selectObject: workID
    Extract part: .tStart, .fetchEnd, "rectangular", 1, "no"
    chunkInputID = selected ("Sound")
    Save as WAV file: inputWav$
    removeObject: chunkInputID

    # Determine Python command based on OS
    if macintosh or unix
        pythonCmd$ = "python3"
    else
        pythonCmd$ = "python"
    endif

    runSubprocess: pythonCmd$, helper_py$,
        ... inputWav$, hoaWav$, speakerWav$, outputWav$, logTxt$,
        ... tools_folder$, encoderPreset$, decoderPreset$, layoutToken$,
        ... actualSOFA$, string$ (actualITD), roomName$

    if not fileReadable (outputWav$)
        if fileReadable (logTxt$)
            msg$ = readFile$ (logTxt$)
        else
            msg$ = "(no log written)"
        endif
        removeObject: workID
        exitScript: "Render failed at chunk " + string$ (.chunkNum) +
            ... " (az=" + fixed$ (.az, 1) + ")" + newline$ + newline$ + msg$
    endif

    Read from file: outputWav$
    chunkBinID = selected ("Sound")

    if delete_temp_files
        deleteFile: inputWav$
        deleteFile: hoaWav$
        deleteFile: speakerWav$
        deleteFile: outputWav$
        deleteFile: logTxt$
    endif
endproc

# ============================================================
# STATIC MODE
# ============================================================
if not movement_enabled

    appendInfoLine: "Rendering..."

    @renderChunk: 0, duration, azimuth, elevation, 1

    result = chunkBinID
    selectObject: result
    Rename: soundName$ + "_panBinaural"
    removeObject: workID
    
    # Visualisation Data
    plotNum = 1
    plotX[1] = sin(azimuth * pi / 180)
    plotY[1] = cos(azimuth * pi / 180)
    actual_dur = duration

    appendInfoLine: "Done. Output: ", soundName$ + "_panBinaural"

# ============================================================
# MOVEMENT MODE
# ============================================================
else

    numChunks = ceiling (duration / movement_chunk_dur)
    appendInfoLine: "Rendering ", numChunks, " chunks  (", movement_chunk_dur, " s each)..."
    appendInfoLine: ""

    startRad = start_az * pi / 180
    endRad   = end_az   * pi / 180
    startX = sin (startRad)
    startY = cos (startRad)
    endX   = sin (endRad)
    endY   = cos (endRad)

    plotNum = numChunks

    for chunk from 1 to numChunks

        chunkStart = (chunk - 1) * movement_chunk_dur
        chunkEnd   = min (chunkStart + movement_chunk_dur, duration)
        chunkMid   = (chunkStart + chunkEnd) / 2
        progress   = chunkMid / duration

        if movement_type = 1
            srcX = startX + (endX - startX) * progress
            srcY = startY + (endY - startY) * progress
        elsif movement_type = 2
            angle = progress * 2 * pi * trajectory_speed
            srcX = trajectory_radius * sin (angle)
            srcY = trajectory_radius * cos (angle)
        elsif movement_type = 3
            angle = progress * 4 * pi * trajectory_speed
            srcX = trajectory_radius * sin (angle)
            srcY = trajectory_radius * sin (2 * angle) / 2
        elsif movement_type = 4
            angle = progress * 4 * pi * trajectory_speed
            curR  = trajectory_radius * (1 - progress)
            srcX = curR * sin (angle)
            srcY = curR * cos (angle)
        elsif movement_type = 5
            angle = progress * 4 * pi * trajectory_speed
            curR  = trajectory_radius * progress
            srcX = curR * sin (angle)
            srcY = curR * cos (angle)
        elsif movement_type = 6
            swingAngle = sin (progress * pi * trajectory_speed * 4) * pi / 3
            srcX = trajectory_radius * sin (swingAngle)
            srcY = trajectory_radius * cos (swingAngle)
        elsif movement_type = 7
            numZigs    = 4 * trajectory_speed
            zigProgress = (progress * numZigs) mod 1
            zigNum      = floor (progress * numZigs)
            if (zigNum mod 2) = 0
                srcX = -trajectory_radius + 2 * trajectory_radius * zigProgress
            else
                srcX = trajectory_radius - 2 * trajectory_radius * zigProgress
            endif
            srcY = -trajectory_radius + 2 * trajectory_radius * progress
        elsif movement_type = 8
            angle1 = progress * 137.5 * trajectory_speed
            angle2 = progress * 97.3 * trajectory_speed
            srcX = trajectory_radius * sin (angle1) * 0.7
            srcY = trajectory_radius * cos (angle2) * 0.7
        elsif movement_type = 9
            angle = progress * 2 * pi * trajectory_speed
            srcX = trajectory_radius * 1.4 * sin (angle)
            srcY = trajectory_radius * 0.7 * cos (angle)
        else
            sideProgress = (progress * 4 * trajectory_speed) mod 1
            sideNum      = floor ((progress * 4 * trajectory_speed) mod 4)
            if sideNum = 0
                srcX = -trajectory_radius + 2 * trajectory_radius * sideProgress
                srcY =  trajectory_radius
            elsif sideNum = 1
                srcX =  trajectory_radius
                srcY =  trajectory_radius - 2 * trajectory_radius * sideProgress
            elsif sideNum = 2
                srcX =  trajectory_radius - 2 * trajectory_radius * sideProgress
                srcY = -trajectory_radius
            else
                srcX = -trajectory_radius
                srcY = -trajectory_radius + 2 * trajectory_radius * sideProgress
            endif
        endif

        if srcX = 0 and srcY = 0
            chunkAz = 0
        else
            chunkAz = arctan2 (srcX, srcY) * 180 / pi
        endif

        # Save coordinate for visualization
        plotX[chunk] = srcX
        plotY[chunk] = srcY

        @renderChunk: chunkStart, chunkEnd, chunkAz, elevation, chunk
        chunkResult[chunk] = chunkBinID

        if (chunk mod 10) = 0 or chunk = numChunks
            pct = chunk / numChunks * 100
            appendInfoLine: "  ", fixed$ (pct, 0), "%  (chunk ", chunk, "/", numChunks, "  az=", fixed$ (chunkAz, 1), "°)"
        endif

    endfor

    appendInfoLine: ""
    appendInfoLine: "Crossfading ", numChunks, " chunks..."

    totalDur = duration + xfade_dur
    Create Sound from formula: "result", 2, 0, totalDur, sr, "0"
    result = selected ("Sound")

    for ch from 1 to numChunks
        srcID   = chunkResult[ch]
        chStart = (ch - 1) * movement_chunk_dur

        selectObject: srcID
        chDurThis = Get total duration

        if xfade_dur > 0 and chDurThis > xfade_dur
            if ch > 1
                Formula (part): 0, xfade_dur, 1, 2, "self * (x / xfade_dur)"
            endif
            .fadeStart = chDurThis - xfade_dur
            if .fadeStart > 0
                Formula (part): .fadeStart, chDurThis, 1, 2, "self * ((chDurThis - x) / xfade_dur)"
            endif
        endif

        Scale times to: chStart, chStart + chDurThis
        .regionEnd = min (chStart + chDurThis, totalDur)
        .startSamp = round(chStart * sr)

        selectObject: result
        Formula (part): chStart, .regionEnd, 1, 2, "self + object[" + string$(srcID) + ", row, col - " + string$(.startSamp) + "]"

        removeObject: srcID
    endfor

    selectObject: result
    actual_dur = Get total duration
    Extract part: 0, min (duration + xfade_dur, actual_dur), "rectangular", 1, "no"
    trimResult = selected ("Sound")
    removeObject: result
    result = trimResult

    selectObject: result
    actual_dur = Get total duration
    Scale peak: 0.95
    Rename: soundName$ + "_panBinaural_" + movementName$

    removeObject: workID

    appendInfoLine: "Done.  Output: ", soundName$ + "_panBinaural_" + movementName$

endif  ; movement_enabled

# ============================================================
# Visualization Canvas
# ============================================================
Erase all

# --- 1. Title Strip ---
Select outer viewport: 0, 8, 0, 0.75
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"

if movement_enabled
    Text: 0.5, "centre", 0.7, "half", "##IRCAM Pan to Binaural: " + soundName$ + " (" + movementName$ + ")##"
else
    Text: 0.5, "centre", 0.7, "half", "##IRCAM Pan to Binaural: " + soundName$ + " (Static)##"
endif

Font size: 7
Colour: "{0.35, 0.35, 0.52}"
Text: 0.5, "centre", 0.025, "half", "3-Stage Pipeline: Source → HOA " + string$(actualOrder) + " → Speaker Layout " + layoutToken$ + " → Binaural"

# --- 2. Diagram / Spatial Panel ---
Select outer viewport: 0, 4.0, 0.75, 4.0
Select inner viewport: 0.4, 3.6, 0.9, 3.8
Axes: -1.4, 1.4, -1.4, 1.4
Paint rectangle: "{0.96, 0.96, 0.96}", -1.4, 1.4, -1.4, 1.4

Colour: "{0.88, 0.88, 0.88}"
Draw line: -1.4, 0, 1.4, 0
Draw line: 0, -1.4, 0, 1.4
Draw circle (mm): 0, 0, 20
Draw circle (mm): 0, 0, 40

for s from 1 to numSpk
    sAz = spkAz[s] * pi / 180
    sX = sin(sAz)
    sY = cos(sAz)
    Paint circle (mm): "{0.25, 0.50, 0.72}", sX, sY, 3.5
    Font size: 6
    Colour: "{0.20, 0.40, 0.60}"
    Text: sX * 1.25, "centre", sY * 1.25, "half", string$(s)
endfor

Colour: "{0.82, 0.28, 0.28}"
if movement_enabled
    Line width: 2
    for p from 1 to plotNum - 1
        Draw line: plotX[p], plotY[p], plotX[p+1], plotY[p+1]
    endfor
    Line width: 1
    Paint circle (mm): "{0.82, 0.28, 0.28}", plotX[plotNum], plotY[plotNum], 3
else
    Paint circle (mm): "{0.82, 0.28, 0.28}", plotX[1], plotY[1], 4
    Font size: 6
    Text: plotX[1] + 0.1, "left", plotY[1], "half", fixed$(azimuth, 1) + "°"
endif

Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 4
Font size: 5
Colour: "Black"
Text: 0, "centre", -0.15, "half", "Listener"

Colour: "Black"
Draw inner box
Font size: 7
Text: 0, "centre", 1.52, "half", "Spatial Map (Top-Down)"

# --- 3. Parameter / Info Bars ---
Select outer viewport: 4.1, 8.0, 0.75, 4.0
Select inner viewport: 4.3, 7.7, 0.9, 3.8
Axes: 0, 1, 0, 1
Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

Font size: 6
cBlue$   = "{0.50, 0.65, 0.80}"
cPurple$ = "{0.65, 0.55, 0.75}"
cBrown$  = "{0.72, 0.55, 0.38}"
cGreen$  = "{0.45, 0.70, 0.55}"

Paint rectangle: cBlue$, 0.05, 0.95, 0.85, 0.92
Colour: "{0.30, 0.30, 0.30}"
Text: 0.05, "left", 0.88, "top", "Mode: " + sourceMode$

Paint rectangle: cPurple$, 0.05, 0.95, 0.70, 0.77
Colour: "{0.30, 0.30, 0.30}"
Text: 0.05, "left", 0.73, "top", "HOA Order: " + string$(actualOrder) + " (" + normToken$ + ")"

Paint rectangle: cBrown$, 0.05, 0.95, 0.55, 0.62
Colour: "{0.30, 0.30, 0.30}"
Text: 0.05, "left", 0.58, "top", "Layout: " + layoutToken$ + " (" + string$(layoutChannels) + " ch)"

if movement_enabled
    Paint rectangle: cGreen$, 0.05, 0.95, 0.40, 0.47
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.43, "top", "Path: " + movementName$ + " | Spd: " + fixed$(trajectory_speed, 2)
else
    Paint rectangle: cGreen$, 0.05, 0.95, 0.40, 0.47
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.43, "top", "Pos: Az " + fixed$(azimuth, 1) + "° | El " + fixed$(elevation, 1) + "°"
endif

Colour: "Black"
Draw inner box
Font size: 7
Text top: "no", "Processing Parameters"

# --- 4. Waveform ---
Select outer viewport: 0, 8, 4.1, 5.4
Select inner viewport: 0.4, 7.7, 4.3, 5.3
Axes: 0, actual_dur, -1, 1
Paint rectangle: "{0.97, 0.97, 0.97}", 0, actual_dur, -1, 1

selectObject: sound
Colour: "{0.6, 0.6, 0.6}"
Draw: 0, actual_dur, -1, 1, "no", "curve"

selectObject: result
extL = Extract one channel: 1
Colour: "{0.25, 0.50, 0.82}"
Draw: 0, actual_dur, -1, 1, "no", "curve"
removeObject: extL

selectObject: result
extR = Extract one channel: 2
Colour: "{0.82, 0.45, 0.25}"
Draw: 0, actual_dur, -1, 1, "no", "curve"
removeObject: extR

Colour: "Black"
Draw inner box
Font size: 7
Text top: "no", "Waveforms (Grey: Input | Blue: Binaural L | Orange: Binaural R)"

# --- 5. Summary Bar ---
Select outer viewport: 0, 8, 5.45, 6.20
Select inner viewport: 0.4, 7.7, 5.5, 6.1
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
Font size: 7
Colour: "{0.28, 0.28, 0.28}"

if movement_enabled
    Text: 0.02, "left", 0.7, "half", "##" + soundName$ + "_panBinaural_" + movementName$ + "##"
else
    Text: 0.02, "left", 0.7, "half", "##" + soundName$ + "_panBinaural##"
endif

Font size: 6
Text: 0.02, "left", 0.3, "half", "HRTF: " + presetName$ + " | Room: " + roomName$ + " | Output Length: " + fixed$(actual_dur, 2) + "s"

Colour: "Black"
Draw inner box

# --- Reset ---
Font size: 10
Colour: "Black"
Line width: 1

# ============================================================
# Play
# ============================================================
if play_output
    selectObject: result
    asynchronous Play
endif

selectObject: result