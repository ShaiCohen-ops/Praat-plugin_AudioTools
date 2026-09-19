# ============================================================
# Praat AudioTools - IRCAM_Pan_to_Binaural.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SPATIALIZER + RENDERER: places a mono or stereo source in space (static
#   or moving) and renders it for headphones through a 3-stage Spat5 chain:
#     spat5.hoa.encoder~      source + azimuth/elevation -> HOA
#     spat5.hoa.decoder~      HOA -> virtual loudspeaker feeds
#     spat5.virtualspeakers~  loudspeaker feeds -> binaural (HRTF)
#   Companion of IRCAM_Multichannel_to_Binaural (which starts from feeds
#   that are already loudspeaker signals). For a few sources IRCAM note that
#   native binaural is usually more accurate in timbre and localization;
#   the HOA path is an approximation through a virtual loudspeaker array.
#
#   QUALITY (order and array chosen together - no weak combinations):
#     Horizontal  HOA order 1 -> 7 virtual speakers (7.0), elevation = 0
#     3D          HOA order 2 -> 11 full-range virtual speakers + silent LFE
#                 -> virtualspeakers 7.1.4 (height ring at +45 deg), so
#                 elevation reaches genuinely elevated HRTFs
#   Virtual speaker positions (azimuth, elevation; +azimuth = right):
#     bed   L -30, R +30, C 0, Lss -90, Rss +90, Lrs -150, Rrs +150 (el 0)
#     top   TpFL -45, TpFR +45, TpBL -135, TpBR +135 (el +45)
#   These must match Spat5's own 7.0 / 7.1.4 layouts (7.0 is v1.0's
#   layout; the 7.1.4 top ring is an assumption - verify with the
#   channel-order test of IRCAM_Multichannel_to_Binaural).
#
#   MOVEMENT is defined in azimuth / elevation, the only coordinates the
#   HOA encoder uses (it has no distance). The sound is cut into chunks,
#   each rendered at its own position, and crossfaded.
#     Linear sweep  Azimuth -> End azimuth, linear in degrees (use e.g.
#                   90 -> 270 to pass behind; values are not wrapped first)
#     Rotation      Cycles full turns starting at Azimuth (negative = left)
#     Pendulum      Azimuth <-> End azimuth, sinusoidal, Cycles swings
#     Zigzag        Azimuth <-> End azimuth, linear back and forth
#     Wander        quasi-random, two incommensurate sines (golden-angle
#                   phase) of amplitude |End - Azimuth| around Azimuth
#     Rising arc    3D: linear sweep, elevation 0 -> Elevation -> 0
#     Figure-8      3D: azimuth swings, elevation at twice the rate
#
#   SAFE RENDER: every stage output is checked for clipping; a clipped
#   render (any chunk, any stage) is discarded and ALL chunks re-render
#   6 dB lower, so the level stays continuous across the movement. Only a
#   clean render is normalised (Output peak). Same system as
#   IRCAM_Multichannel_to_Binaural v1.4.1 (24-bit intermediate WAV).
#
# Changelog v2.0 (revision after review):
#   - Safe render (auto headroom, per-stage clipping detection, whole-pass
#     re-render, normalisation only after a clean render). v1.0 applied a
#     fixed -9 dB, checked nothing, and ran "Scale peak: 0.95" on the
#     already-rendered movement result.
#   - Stereo really works: v1.0 hardcoded sum_to_mono = 1, so the stereo
#     spread was never used - and its L/R were mirrored (L at az + spread/2,
#     which is the right side with +az = right). Now Source mode chooses.
#   - Trajectories in azimuth/elevation. v1.0 built XY paths and took
#     atan2, so trajectory_radius cancelled exactly (radius 0.4 / 0.8 / 1.2
#     all gave az 108.000 deg), Spiral In/Out had no audible in/out, and
#     Linear -90 -> +90 held -90 for half the sound, then jumped through 0
#     to +90. Random Walk used 137.5 as radians. Removed: radius, Spiral
#     In/Out, Ellipse, Square (they differed only in the fake radius).
#   - 7.1 decode removed: v1.0 decoded a full-band speaker at 0/-30 deg into
#     channel 4, which virtualspeakers 7.1 treats as LFE. 3D now decodes 11
#     full-range speakers and inserts a silent LFE for 7.1.4.
#   - HOA order tied to the array (order 1 horizontal, order 2 3D); v1.0
#     allowed e.g. order 5 (36 ch) decoded to 2 speakers.
#   - Horizontal quality states that elevation is ignored (horizontal
#     speakers cannot reproduce it) instead of silently flattening it.
#   - Movement output length = source length (+ genuine room tail of the
#     last chunk); v1.0 appended xfade_dur of silence and faded out the
#     last chunk's ending.
#   - Python bridge v2.0: pre-flight, per-stage analysis, stats file.
#   - House-style visualization: spatial map, azimuth/elevation over time,
#     output at true level, safe-render attempts and level ledger.
# ============================================================

form IRCAM Pan to Binaural v2.0
    comment Folder containing spat5.hoa.encoder~, hoa.decoder~, virtualspeakers~
    sentence Tools_folder C:/Users/User/Documents/Max 9/Packages/spat5-x64/media/tools/
    optionmenu Source_mode: 1
        option "Mono (a stereo input is summed)"
        option "Stereo: keep L/R, spread around the position"
    real Stereo_spread_deg 60
    optionmenu Quality: 1
        option "Horizontal: HOA 1 -> 7 virtual speakers (7.0)"
        option "3D: HOA 2 -> 11 virtual speakers (7.1.4)"
    optionmenu Movement: 1
        option "Static"
        option "Linear sweep (Azimuth -> End azimuth)"
        option "Rotation (Cycles turns from Azimuth)"
        option "Pendulum (Azimuth <-> End azimuth)"
        option "Zigzag (Azimuth <-> End azimuth)"
        option "Wander (quasi-random around Azimuth)"
        option "Rising arc (3D)"
        option "Figure-8 (3D)"
    real Azimuth 0
    real End_azimuth 90
    real Elevation 0
    real Cycles 1
    optionmenu Hrtf_preset: 1
        option "KEMAR / neutral"
        option "KEMAR / hall"
        option "KEMAR / studio"
        option "SOFA custom (Room preset applies)"
    sentence Sofa_file kemar
    real Itd_percent 100
    optionmenu Room_preset: 1
        option "none"
        option "hall"
        option "living room"
        option "studio"
        option "preset1"
        option "preset2"
        option "preset3"
        option "preset4"
        option "legacy1"
        option "legacy2"
        option "legacy3"
    optionmenu Headroom: 1
        option "Auto safe render (re-render until clean)"
        option "Manual pre-gain (one pass, still checked)"
    real Manual_pre_gain_dB -9
    boolean Normalise_output 1
    real Output_peak_dBFS -1
    boolean Advanced_movement_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- movement details (second page) ----
chunk_duration = 0.25
crossfade = 0.05
if advanced_movement_settings
    beginPause: "Pan to Binaural - movement details"
        comment: "Each chunk is rendered at one position; chunks are crossfaded."
        positive: "Chunk duration", string$ (chunk_duration)
        real: "Crossfade", string$ (crossfade)
    clickedAdv = endPause: "Cancel", "Continue", 2, 1
    if clickedAdv = 1
        exitScript: "Cancelled."
    endif
endif

# ============================================================
# INPUT + GUARDS
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif
sound      = selected ("Sound")
soundName$ = selected$ ("Sound")
selectObject: sound
duration  = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
if nChannels <> 1 and nChannels <> 2
    exitScript: "Pan to Binaural takes a mono or stereo source (" + string$ (nChannels) + " channels found)."
endif

helper_py$      = defaultDirectory$ + "/spat_bridge.py"
working_folder$ = defaultDirectory$ + "/"
if not fileReadable (helper_py$)
    exitScript: "Python helper not found next to this script:" + newline$ + helper_py$
endif
if right$ (tools_folder$, 1) <> "/" and right$ (tools_folder$, 1) <> "\"
    tools_folder$ = tools_folder$ + "/"
endif

notes$ = ""
if azimuth < -360 or azimuth > 360 or end_azimuth < -720 or end_azimuth > 720
    exitScript: "Azimuth must be within -360..360 and End azimuth within -720..720 degrees."
endif
if elevation < -90 or elevation > 90
    exitScript: "Elevation must be within -90..90 degrees."
endif
if itd_percent < 0 or itd_percent > 200
    notes$ = notes$ + "Note: Itd_percent " + fixed$ (itd_percent, 1) + " outside 0..200, clamped." + newline$
    itd_percent = max (0, min (200, itd_percent))
endif
if output_peak_dBFS > 0 or output_peak_dBFS < -24
    notes$ = notes$ + "Note: Output_peak_dBFS " + fixed$ (output_peak_dBFS, 1) + " outside -24..0, clamped." + newline$
    output_peak_dBFS = max (-24, min (0, output_peak_dBFS))
endif
chunk_duration = max (0.05, chunk_duration)
crossfade = max (0, min (crossfade, chunk_duration / 2))
if cycles = 0
    cycles = 1
endif

# ============================================================
# SOURCE MODE
# ============================================================
stereoIn = nChannels = 2 and source_mode = 2
if nChannels = 2 and source_mode = 1
    sourceMode$ = "stereo summed to mono"
elsif stereoIn
    sourceMode$ = "stereo kept, spread " + fixed$ (stereo_spread_deg, 0) + " deg"
else
    sourceMode$ = "mono"
endif
if source_mode = 2 and nChannels = 1
    notes$ = notes$ + "Note: Source mode Stereo ignored - the input is mono." + newline$
endif

# ============================================================
# QUALITY: HOA order + virtual loudspeaker array
# ============================================================
normToken$ = "N3D"
if quality = 1
    hoaOrder = 1
    layoutToken$ = "7.0"
    lfeInsert = 0
    numSpk = 7
else
    hoaOrder = 2
    layoutToken$ = "7.1.4"
    lfeInsert = 4
    numSpk = 11
endif
hoaChannels = (hoaOrder + 1) ^ 2
spkAz[1] = -30
spkAz[2] = 30
spkAz[3] = 0
spkAz[4] = -90
spkAz[5] = 90
spkAz[6] = -150
spkAz[7] = 150
spkAz[8] = -45
spkAz[9] = 45
spkAz[10] = -135
spkAz[11] = 135
for s from 1 to 11
    spkEl[s] = if s <= 7 then 0 else 45 fi
endfor
hoaHeader$ = "/order " + string$ (hoaOrder) + ", /dimension 3, /norm " + normToken$
decoderPreset$ = hoaHeader$ + ", /speaker/number " + string$ (numSpk)
for s from 1 to numSpk
    decoderPreset$ = decoderPreset$ + ", /speaker/" + string$ (s) + "/ae " + string$ (spkAz[s]) + " " + string$ (spkEl[s])
endfor

is3Dmove = movement = 7 or movement = 8
if quality = 1
    if elevation <> 0
        notes$ = notes$ + "Note: Horizontal quality - Elevation " + fixed$ (elevation, 0) + " deg ignored (horizontal virtual speakers cannot reproduce it; choose 3D)." + newline$
    endif
    if is3Dmove
        notes$ = notes$ + "Note: " + if movement = 7 then "Rising arc" else "Figure-8" fi + " needs 3D quality for its elevation; rendering its azimuth path only." + newline$
    endif
    useEl = 0
else
    useEl = 1
endif

# ============================================================
# HRTF / ROOM
# ============================================================
roomTok$[1] = "none"
roomTok$[2] = "hall"
roomTok$[3] = "living room"
roomTok$[4] = "studio"
roomTok$[5] = "preset1"
roomTok$[6] = "preset2"
roomTok$[7] = "preset3"
roomTok$[8] = "preset4"
roomTok$[9] = "legacy1"
roomTok$[10] = "legacy2"
roomTok$[11] = "legacy3"
if hrtf_preset = 1
    actualSOFA$ = "kemar"
    roomName$ = "none"
elsif hrtf_preset = 2
    actualSOFA$ = "kemar"
    roomName$ = "hall"
elsif hrtf_preset = 3
    actualSOFA$ = "kemar"
    roomName$ = "studio"
else
    actualSOFA$ = sofa_file$
    roomName$ = roomTok$[room_preset]
endif

# ============================================================
# TRAJECTORY (azimuth / elevation per chunk)
# ============================================================
movementName$[1] = "Static"
movementName$[2] = "Linear"
movementName$[3] = "Rotation"
movementName$[4] = "Pendulum"
movementName$[5] = "Zigzag"
movementName$[6] = "Wander"
movementName$[7] = "RisingArc"
movementName$[8] = "Figure8"
moveName$ = movementName$[movement]
if movement = 1
    numChunks = 1
else
    numChunks = ceiling (duration / chunk_duration)
endif
golden = 137.50776 * pi / 180
for k from 1 to numChunks
    if movement = 1
        cStart[k] = 0
        cEnd[k] = duration
    else
        cStart[k] = (k - 1) * chunk_duration
        cEnd[k] = min (k * chunk_duration, duration)
    endif
    p = ((cStart[k] + cEnd[k]) / 2) / duration
    az = azimuth
    el = elevation
    if movement = 2
        az = azimuth + (end_azimuth - azimuth) * p
    elsif movement = 3
        az = azimuth + 360 * cycles * p
    elsif movement = 4
        az = azimuth + (end_azimuth - azimuth) * (0.5 - 0.5 * cos (2 * pi * cycles * p))
    elsif movement = 5
        zz = (cycles * p) - floor (cycles * p)
        tri = if zz < 0.5 then 2 * zz else 2 - 2 * zz fi
        az = azimuth + (end_azimuth - azimuth) * tri
    elsif movement = 6
        amp = abs (end_azimuth - azimuth)
        az = azimuth + amp * (0.6 * sin (2 * pi * cycles * p + golden) + 0.4 * sin (2 * pi * 1.618034 * cycles * p + 2 * golden))
    elsif movement = 7
        az = azimuth + (end_azimuth - azimuth) * p
        el = elevation * sin (pi * p)
    elsif movement = 8
        az = azimuth + (end_azimuth - azimuth) / 2 * sin (2 * pi * cycles * p)
        el = elevation * sin (4 * pi * cycles * p)
    endif
    # wrap to (-180, 180]
    az = az - 360 * floor ((az + 180) / 360)
    if az = -180
        az = 180
    endif
    cAz[k] = az
    cEl[k] = if useEl then el else 0 fi
endfor

# encoder preset for one position (stereo: two sources, L left of centre)
procedure encoderPreset: .az, .el
    if stereoIn
        .azL = .az - stereo_spread_deg / 2
        .azR = .az + stereo_spread_deg / 2
        .azL = .azL - 360 * floor ((.azL + 180) / 360)
        .azR = .azR - 360 * floor ((.azR + 180) / 360)
        .result$ = hoaHeader$ + ", /source/number 2, /source/1/ae " + string$ (.azL) + " " + string$ (.el)
            ... + ", /source/2/ae " + string$ (.azR) + " " + string$ (.el)
    else
        .result$ = hoaHeader$ + ", /source/1/ae " + string$ (.az) + " " + string$ (.el)
    endif
endproc

# ============================================================
# WORKING SOURCE + START GAIN
# ============================================================
selectObject: sound
if nChannels = 2 and stereoIn = 0
    workID = Convert to mono
else
    workID = Copy: "__pan_work"
endif
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak <= 0
    removeObject: workID
    exitScript: "The Sound is silent (peak 0)."
endif
srcPeakDb = 20 * log10 (srcPeak)
exportSafeDb = -1 - srcPeakDb
# HOA chain gain: v1.0 measured about +7 dB (order 1, N3D); start 3 dB
# below that, 2 dB more for order 2, 3 dB more for two sources
chainEst = 10 + if quality = 2 then 2 else 0 fi + if stereoIn then 3 else 0 fi
if headroom = 1
    gainDb = min (exportSafeDb, -srcPeakDb - chainEst)
    maxPasses = 5
else
    gainDb = manual_pre_gain_dB
    maxPasses = 1
    if gainDb > exportSafeDb
        notes$ = notes$ + "Note: manual pre-gain " + fixed$ (manual_pre_gain_dB, 1) + " dB would clip the exported WAV; capped at " + fixed$ (exportSafeDb, 1) + " dB." + newline$
        gainDb = exportSafeDb
    endif
endif

# ============================================================
# INFO HEADER
# ============================================================
if windows
    platform$ = "Windows"
elsif macintosh
    platform$ = "macOS"
else
    platform$ = "Linux"
endif
writeInfoLine:  "=== IRCAM Pan to Binaural v2.0 (safe render) ==="
appendInfoLine: "Platform : ", platform$
appendInfoLine: "Source   : ", soundName$, "  (", nChannels, " ch, ", fixed$ (duration, 2), " s @ ", sr, " Hz), ", sourceMode$, ", peak ", fixed$ (srcPeakDb, 1), " dBFS"
appendInfoLine: "Quality  : HOA order ", hoaOrder, " (", hoaChannels, " ch, ", normToken$, ") -> ", numSpk, " virtual speakers -> ", layoutToken$
if movement = 1
    appendInfoLine: "Position : static, az ", fixed$ (cAz[1], 1), ", el ", fixed$ (cEl[1], 1)
else
    appendInfoLine: "Movement : ", moveName$, ", ", numChunks, " chunks of ", fixed$ (chunk_duration, 3), " s, crossfade ", fixed$ (crossfade, 3), " s"
endif
appendInfoLine: "HRTF     : ", actualSOFA$, "  ITD ", fixed$ (itd_percent, 0), "%  room ", roomName$
appendInfoLine: "Headroom : ", if headroom = 1 then "auto safe render" else "manual pre-gain" fi, ", start ", fixed$ (gainDb, 1), " dB"
if notes$ <> ""
    appendInfo: notes$
endif
appendInfoLine: ""

# ============================================================
# DETECT PYTHON (3-candidate probe, runs once before any render)
# ============================================================
probeMarker$ = working_folder$ + "pan_probe.ok"

if windows
    nPyCandidates = 3
    pyCandidate1$ = "python"
    pyCandidate2$ = "py"
    pyCandidate3$ = "python3"
else
    nPyCandidates = 3
    pyCandidate1$ = "python3"
    pyCandidate2$ = "python"
    pyCandidate3$ = "py"
endif

pythonCmd$ = ""
for iCand from 1 to nPyCandidates
    if iCand = 1
        tryCmd$ = pyCandidate1$
    elsif iCand = 2
        tryCmd$ = pyCandidate2$
    else
        tryCmd$ = pyCandidate3$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    probeCode$ = "import sys,os,subprocess,struct,math; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
    endif
    if pythonCmd$ <> ""
        iCand = nPyCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find a working Python installation." + newline$
        ... + "" + newline$
        ... + "Tried: " + pyCandidate1$ + ", " + pyCandidate2$ + ", " + pyCandidate3$ + newline$
        ... + "" + newline$
        ... + "Please install Python 3 and ensure it is on your PATH."
endif


appendInfoLine: "Python   : ", pythonCmd$
appendInfoLine: ""

# ============================================================
# RENDER ONE CHUNK (at the current pass gain)
# ============================================================
inputWav$   = working_folder$ + "pan_input.wav"
hoaWav$     = working_folder$ + "pan_hoa.wav"
speakerWav$ = working_folder$ + "pan_speakers.wav"
outputWav$  = working_folder$ + "pan_binaural.wav"
logTxt$     = working_folder$ + "pan_binaural_log.txt"
statsTxt$   = working_folder$ + "pan_stats.txt"
exportBits = 24

procedure renderChunk: .k
    .t0 = cStart[.k]
    if .k < numChunks
        .t1 = min (cEnd[.k] + crossfade, duration)
    else
        .t1 = cEnd[.k]
    endif
    @encoderPreset: cAz[.k], cEl[.k]
    .ok = 0
    .try = 1
    while .ok = 0 and .try <= 2
        if fileReadable (inputWav$)
            deleteFile: inputWav$
        endif
        selectObject: workID
        .part = Extract part: .t0, .t1, "rectangular", 1, "no"
        Multiply: 10 ^ (gainDb / 20)
        if exportBits = 24
            Save as 24-bit WAV file: inputWav$
        else
            Save as WAV file: inputWav$
        endif
        removeObject: .part
        nocheck runSubprocess: pythonCmd$, helper_py$,
            ... inputWav$, hoaWav$, speakerWav$, outputWav$, logTxt$,
            ... tools_folder$, encoderPreset.result$, decoderPreset$, layoutToken$,
            ... actualSOFA$, string$ (itd_percent), roomName$, statsTxt$, string$ (lfeInsert)
        if fileReadable (statsTxt$) and fileReadable (outputWav$)
            .ok = 1
        elsif exportBits = 24 and renderedAny = 0
            appendInfoLine: "  first render with a 24-bit intermediate failed; retrying with 16-bit"
            exportBits = 16
            .try += 1
        else
            .try = 3
        endif
    endwhile
    if .ok = 0
        appendInfoLine: "ERROR: render failed at chunk ", .k, " (az ", fixed$ (cAz[.k], 1), ")."
        appendInfoLine: "Log preserved at: ", logTxt$
        if fileReadable (logTxt$)
            appendInfoLine: ""
            appendInfoLine: "=== Spat5 log ==="
            appendInfoLine: readFile$ (logTxt$)
        endif
        @cleanupChunks
        removeObject: workID
        exitScript: "Render failed - see the Info window."
    endif
    renderedAny = 1
    .stats$ = readFile$ (statsTxt$)
    chunkClipped = extractNumber (.stats$, "clipped=")
    chunkStage$ = extractWord$ (.stats$, "clip_stage=")
    outFormat$ = extractWord$ (.stats$, "format=")
    outCorr = extractNumber (.stats$, "correlation=")
    chunkPeak = max (extractNumber (.stats$, "peak_l="), extractNumber (.stats$, "peak_r="))
    chunkIn[.k] = .t1 - .t0
    chunkID[.k] = Read from file: outputWav$
    .csr = Get sampling frequency
    if .csr <> sr
        .rs = Resample: sr, 50
        removeObject: chunkID[.k]
        chunkID[.k] = .rs
    endif
    nHeld = .k
endproc

procedure cleanupChunks
    for .j from 1 to nHeld
        if chunkID[.j] > 0
            removeObject: chunkID[.j]
            chunkID[.j] = 0
        endif
    endfor
    nHeld = 0
endproc

# ============================================================
# SAFE RENDER: whole passes; any clipped chunk -> all chunks 6 dB lower
# ============================================================
appendInfoLine: "Rendering ", numChunks, " chunk", if numChunks > 1 then "s" else "" fi, "..."
renderedAny = 0
nHeld = 0
pass = 0
accepted = 0
while pass < maxPasses and accepted = 0
    pass += 1
    passGain[pass] = gainDb
    passPeak[pass] = 0
    passClipped[pass] = 0
    k = 1
    while k <= numChunks and passClipped[pass] = 0
        @renderChunk: k
        passPeak[pass] = max (passPeak[pass], chunkPeak)
        if chunkClipped
            passClipped[pass] = 1
            passStage$[pass] = chunkStage$
            passAtChunk[pass] = k
        endif
        k += 1
    endwhile
    if passClipped[pass]
        appendInfoLine: "  pass ", pass, ": input ", fixed$ (gainDb, 1), " dB -> CLIPPED at the ", passStage$[pass], " stage (chunk ", passAtChunk[pass], ")"
        if pass < maxPasses
            @cleanupChunks
            gainDb = gainDb - 6
        endif
    else
        accepted = 1
        appendInfoLine: "  pass ", pass, ": input ", fixed$ (gainDb, 1), " dB -> clean, render peak ", fixed$ (20 * log10 (max (passPeak[pass], 1e-12)), 2), " dBFS (", outFormat$, ", ", exportBits, "-bit intermediate)"
    endif
endwhile
if accepted = 0
    appendInfoLine: ""
    if headroom = 1
        appendInfoLine: "ERROR: still clipping after ", maxPasses, " passes (input down to ", fixed$ (gainDb, 1), " dB)."
        appendInfoLine: "This is no longer a headroom problem - check the Spat5 tools, the SOFA file and the log."
    else
        appendInfoLine: "The manual pre-gain pass CLIPPED. Use Headroom = Auto safe render, or lower the gain."
    endif
    appendInfoLine: "Chunks rendered so far are assembled for inspection only; log: ", logTxt$
endif

# ============================================================
# ASSEMBLE: output length = source length (+ last chunk's real tail)
# ============================================================
nAsm = nHeld
selectObject: chunkID[nAsm]
lastOut = Get total duration
tail = max (0, lastOut - chunkIn[nAsm])
if nAsm < numChunks
    tail = 0
endif
totalDur = cStart[nAsm] + chunkIn[nAsm] + tail
if nAsm = numChunks
    totalDur = duration + tail
endif
result = Create Sound from formula: soundName$ + "_panBinaural", 2, 0, totalDur, sr, "0"
for k from 1 to nAsm
    selectObject: chunkID[k]
    asmLen = Get total duration
    asmIn = chunkIn[k]
    if numChunks > 1 and crossfade > 0
        if k > 1
            Formula (part): 0, crossfade, 1, 2, "self * x / " + string$ (crossfade)
        endif
        if k < numChunks
            # fade out across the overlap, and drop this chunk's tail after
            # its own input (the next chunk takes over)
            Formula (part): asmIn - crossfade, asmLen, 1, 2, "if x < " + string$ (asmIn) + " then self * (" + string$ (asmIn) + " - x) / " + string$ (crossfade) + " else 0 fi"
        endif
    endif
    asmStart = round (cStart[k] * sr)
    selectObject: result
    Formula (part): cStart[k], min (cStart[k] + asmLen, totalDur), 1, 2, "self + object[" + string$ (chunkID[k]) + ", row, col - " + string$ (asmStart) + "]"
endfor
@cleanupChunks
removeObject: workID
if movement > 1
    selectObject: result
    Rename: soundName$ + "_panBinaural_" + moveName$
endif

selectObject: result
renderPeak = Get absolute extremum: 0, 0, "None"
renderPeakDb = 20 * log10 (max (renderPeak, 1e-12))
normDb = 0
if accepted
    if normalise_output and renderPeak > 0
        normDb = output_peak_dBFS - renderPeakDb
        Scale peak: 10 ^ (output_peak_dBFS / 20)
    elsif renderPeak > 0.99
        normDb = 20 * log10 (0.99 / renderPeak)
        Scale peak: 0.99
    endif
endif
finalPeak = Get absolute extremum: 0, 0, "None"
finalPeakDb = round (20 * log10 (max (finalPeak, 1e-12)) * 1000) / 1000
actual_dur = Get total duration
netDb = passGain[pass] + normDb

appendInfoLine: ""
appendInfoLine: "=== Level ledger ==="
appendInfoLine: "  source peak          ", fixed$ (srcPeakDb, 2), " dBFS"
appendInfoLine: "  input attenuation    ", fixed$ (passGain[pass], 2), " dB   (", pass, " pass", if pass > 1 then "es" else "" fi, ", ", exportBits, "-bit intermediate)"
appendInfoLine: "  render peak          ", fixed$ (renderPeakDb, 2), " dBFS  (", outFormat$, ")"
appendInfoLine: "  normalisation        ", if normDb = 0 then "none" else fixed$ (normDb, 2) + " dB" fi
appendInfoLine: "  output peak          ", fixed$ (finalPeakDb, 2), " dBFS"
appendInfoLine: "  net source->output   ", fixed$ (netDb, 2), " dB"
appendInfoLine: "  output length        ", fixed$ (actual_dur, 3), " s  (source ", fixed$ (duration, 3), " s", if actual_dur > duration + 0.0005 then ", + room tail" else "" fi, ")"
appendInfoLine: "  L/R correlation      ", fixed$ (outCorr, 3), "  (descriptive only)"
appendInfoLine: ""
if accepted
    appendInfoLine: "Done. Output: ", selected$ ("Sound")
    deleteFile: inputWav$
    deleteFile: hoaWav$
    deleteFile: speakerWav$
    deleteFile: outputWav$
    deleteFile: logTxt$
    deleteFile: statsTxt$
endif

# ============================================================
# VISUALIZATION (house style, 8 x 8.1 in)
# ============================================================
if draw_visualization
    cPrim$ = "{0.20, 0.48, 0.75}"
    cSec$ = "{0.85, 0.38, 0.18}"
    cGrey$ = "{0.55, 0.55, 0.60}"
    cGround$ = "{0.97, 0.97, 0.97}"
    cGrid$ = "{0.80, 0.80, 0.80}"
    cSub$ = "{0.35, 0.35, 0.50}"
    cSum$ = "{0.25, 0.25, 0.35}"
    nm$ = replace$ (soundName$, "_", "\_ ", 0)
    Erase all

    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##IRCAM Pan to Binaural v2.0##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: cSub$
    Text: 0.5, "centre", 0.22, "half", nm$ + "   |   " + sourceMode$ + "   |   HOA " + string$ (hoaOrder) + " -> " + string$ (numSpk)
        ... + " speakers (" + layoutToken$ + ")   |   " + if movement = 1 then "static" else moveName$ fi + "   |   " + if accepted then "clean render" else "CLIPPED render" fi

    # ---- A: top-down map; radius = cos(elevation) ----
    Font size: 7
    Select inner viewport: 0.60, 3.60, 0.95, 3.95
    Axes: -1.35, 1.35, -1.35, 1.35
    Paint rectangle: cGround$, -1.35, 1.35, -1.35, 1.35
    Colour: cGrid$
    Draw circle: 0, 0, 1
    Dotted line
    Draw circle: 0, 0, cos (45 * pi / 180)
    Draw line: -1.3, 0, 1.3, 0
    Draw line: 0, -1.3, 0, 1.3
    Solid line
    for s from 1 to numSpk
        rr = cos (spkEl[s] * pi / 180)
        sx = rr * sin (spkAz[s] * pi / 180)
        sy = rr * cos (spkAz[s] * pi / 180)
        if spkEl[s] = 0
            Paint circle (mm): cGrey$, sx, sy, 2.4
        else
            Colour: cGrey$
            Line width: 1.5
            Draw circle (mm): sx, sy, 2.4
            Line width: 1
        endif
    endfor
    # path of the source (per chunk)
    Colour: cPrim$
    Line width: 2
    for k from 1 to numChunks - 1
        r1 = cos (cEl[k] * pi / 180)
        r2 = cos (cEl[k + 1] * pi / 180)
        x1 = r1 * sin (cAz[k] * pi / 180)
        y1 = r1 * cos (cAz[k] * pi / 180)
        x2 = r2 * sin (cAz[k + 1] * pi / 180)
        y2 = r2 * cos (cAz[k + 1] * pi / 180)
        if abs (cAz[k + 1] - cAz[k]) < 90
            Draw line: x1, y1, x2, y2
        endif
    endfor
    Line width: 1
    r1 = cos (cEl[1] * pi / 180)
    Paint circle (mm): cSec$, r1 * sin (cAz[1] * pi / 180), r1 * cos (cAz[1] * pi / 180), 2.2
    rN = cos (cEl[numChunks] * pi / 180)
    Paint circle (mm): cPrim$, rN * sin (cAz[numChunks] * pi / 180), rN * cos (cAz[numChunks] * pi / 180), 2.2
    # listener
    Paint circle (mm): "{0.25, 0.25, 0.35}", 0, 0, 2.5
    Colour: "{0.25, 0.25, 0.35}"
    Draw line: 0, 0, 0, 0.12
    Font size: 6
    Select inner viewport: 0.60, 3.60, 0.95, 3.95
    Axes: -1.35, 1.35, -1.35, 1.35
    Colour: cSub$
    Text: 0, "centre", 1.22, "half", "front"
    Text: 1.22, "centre", 0, "half", "R"
    Text: -1.22, "centre", 0, "half", "L"
    Text: 0, "centre", -1.22, "half", "back"
    Colour: cSec$
    Text: -1.3, "left", -1.28, "bottom", "orange = start"
    Font size: 7
    Select inner viewport: 0.60, 3.60, 0.95, 3.95
    Axes: -1.35, 1.35, -1.35, 1.35
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select inner viewport: 0.60, 3.60, 0.95, 3.95
    Text top: "no", "##A   Map (top-down)##   rings = height speakers"

    # ---- B1: azimuth over time ----
    Font size: 7
    Select inner viewport: 4.45, 7.70, 0.95, 2.30
    Axes: 0, duration, -180, 180
    Paint rectangle: cGround$, 0, duration, -180, 180
    Colour: cGrid$
    Dotted line
    Draw line: 0, 0, duration, 0
    Draw line: 0, 90, duration, 90
    Draw line: 0, -90, duration, -90
    Solid line
    Colour: cPrim$
    Line width: 2
    for k from 1 to numChunks
        Draw line: cStart[k], cAz[k], cEnd[k], cAz[k]
        if k < numChunks
            if abs (cAz[k + 1] - cAz[k]) < 90
                Draw line: cEnd[k], cAz[k], cEnd[k], cAz[k + 1]
            endif
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 90, "yes", "yes", "no"
    Text left: "yes", "Azimuth (deg)"
    Font size: 8
    Select inner viewport: 4.45, 7.70, 0.95, 2.30
    Text top: "no", "##B   Position per chunk##   +az = right, 0 = front"

    # ---- B2: elevation over time ----
    Font size: 7
    Select inner viewport: 4.45, 7.70, 2.75, 3.95
    Axes: 0, duration, -90, 90
    Paint rectangle: cGround$, 0, duration, -90, 90
    Colour: cGrid$
    Dotted line
    Draw line: 0, 0, duration, 0
    Draw line: 0, 45, duration, 45
    Solid line
    Colour: cSec$
    Line width: 2
    for k from 1 to numChunks
        Draw line: cStart[k], cEl[k], cEnd[k], cEl[k]
        if k < numChunks
            Draw line: cEnd[k], cEl[k], cEnd[k], cEl[k + 1]
        endif
    endfor
    Line width: 1
    if quality = 1
        Font size: 6
        Select inner viewport: 4.45, 7.70, 2.75, 3.95
        Axes: 0, 1, 0, 1
        Colour: cSub$
        Text: 0.5, "centre", 0.78, "half", "horizontal quality: elevation fixed at 0"
    endif
    Font size: 7
    Select inner viewport: 4.45, 7.70, 2.75, 3.95
    Axes: 0, duration, -90, 90
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 45, "yes", "yes", "no"
    @niceStep: duration, 6
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "Elevation (deg)"

    # ---- C: binaural output, true level ----
    Font size: 7
    Select inner viewport: 0.60, 7.70, 4.45, 5.55
    Axes: 0, actual_dur, -1.1, 1.1
    Paint rectangle: cGround$, 0, actual_dur, -1.1, 1.1
    selectObject: result
    vR = Extract one channel: 2
    Colour: cSec$
    Draw: 0, 0, -1.1, 1.1, "no", "Curve"
    removeObject: vR
    Select inner viewport: 0.60, 7.70, 4.45, 5.55
    selectObject: result
    vL = Extract one channel: 1
    Colour: cPrim$
    Draw: 0, 0, -1.1, 1.1, "no", "Curve"
    removeObject: vL
    Select inner viewport: 0.60, 7.70, 4.45, 5.55
    Axes: 0, actual_dur, -1.1, 1.1
    Colour: cGrid$
    Dotted line
    Draw line: 0, 1, actual_dur, 1
    Draw line: 0, -1, actual_dur, -1
    Solid line
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    @niceStep: actual_dur, 8
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "Output"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 4.45, 5.55
    Text top: "no", "##C   Binaural output##   blue = L ear, orange = R ear; dotted = full scale; peak " + fixed$ (finalPeakDb, 1) + " dBFS"

    # ---- D1: safe-render passes ----
    yLo = min (-30, floor (min (passGain[pass], renderPeakDb) / 6) * 6 - 6)
    Font size: 7
    Select inner viewport: 0.60, 3.85, 6.05, 7.05
    Axes: 0.4, pass + 0.6, yLo, 6
    Paint rectangle: cGround$, 0.4, pass + 0.6, yLo, 6
    Colour: cSec$
    Dotted line
    Draw line: 0.4, 0, pass + 0.6, 0
    Solid line
    for a from 1 to pass
        pk = 20 * log10 (max (passPeak[a], 1e-12))
        if passClipped[a]
            Paint rectangle: cSec$, a - 0.3, a + 0.3, yLo, max (pk, 0)
        else
            Paint rectangle: cPrim$, a - 0.3, a + 0.3, yLo, pk
        endif
    endfor
    Font size: 6
    Select inner viewport: 0.60, 3.85, 6.05, 7.05
    Axes: 0.4, pass + 0.6, yLo, 6
    for a from 1 to pass
        pk = 20 * log10 (max (passPeak[a], 1e-12))
        Colour: cSum$
        Text: a, "centre", max (pk, 0) + 0.8, "bottom", if passClipped[a] then "clipped (" + passStage$[a] + ")" else fixed$ (pk, 1) fi
        Text: a, "centre", yLo + 1.5, "bottom", "in " + fixed$ (passGain[a], 1)
    endfor
    Font size: 7
    Select inner viewport: 0.60, 3.85, 6.05, 7.05
    Axes: 0.4, pass + 0.6, yLo, 6
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 6, "yes", "yes", "no"
    for a from 1 to pass
        One mark bottom: a, "no", "yes", "no", string$ (a)
    endfor
    Text left: "yes", "Render peak (dBFS)"
    Text bottom: "yes", "Render pass"
    Font size: 8
    Select inner viewport: 0.60, 3.85, 6.05, 7.05
    Text top: "no", "##D   Safe render##   orange = clipped, all chunks re-rendered"

    # ---- D2: level ledger ----
    Font size: 7
    Select inner viewport: 4.45, 7.70, 6.05, 7.05
    Axes: 0, 1, 0, 1
    Paint rectangle: cGround$, 0, 1, 0, 1
    Colour: cSum$
    Text: 0.04, "left", 0.88, "half", "Source peak"
    Text: 0.96, "right", 0.88, "half", fixed$ (srcPeakDb, 1) + " dBFS"
    Text: 0.04, "left", 0.72, "half", "Input attenuation"
    Text: 0.96, "right", 0.72, "half", fixed$ (passGain[pass], 1) + " dB"
    Text: 0.04, "left", 0.56, "half", "Render peak"
    Text: 0.96, "right", 0.56, "half", fixed$ (renderPeakDb, 1) + " dBFS"
    Text: 0.04, "left", 0.40, "half", "Normalisation"
    Text: 0.96, "right", 0.40, "half", if normDb = 0 then "none" else fixed$ (normDb, 1) + " dB" fi
    Text: 0.04, "left", 0.24, "half", "##Output peak##"
    Text: 0.96, "right", 0.24, "half", "##" + fixed$ (finalPeakDb, 1) + " dBFS##"
    Text: 0.04, "left", 0.08, "half", "Output length"
    Text: 0.96, "right", 0.08, "half", fixed$ (actual_dur, 2) + " s (source " + fixed$ (duration, 2) + " s)"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select inner viewport: 4.45, 7.70, 6.05, 7.05
    Text top: "no", "##Level ledger##"

    # ---- summary strip ----
    Font size: 6
    Select inner viewport: 0.60, 7.70, 7.55, 8.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: cSum$
    Text: 0.01, "left", 0.72, "half", "##Chain:## HOA order " + string$ (hoaOrder) + " (" + normToken$ + ") -> " + string$ (numSpk) + " virtual speakers -> virtualspeakers " + layoutToken$
        ... + if lfeInsert > 0 then " (silent LFE inserted)" else "" fi + "   ##HRTF:## " + actualSOFA$ + ", ITD " + fixed$ (itd_percent, 0) + " \% , room " + roomName$
    Text: 0.01, "left", 0.28, "half", "##Movement:## " + if movement = 1 then "static" else moveName$ + ", " + string$ (numChunks) + " chunks x " + fixed$ (chunk_duration, 2) + " s, crossfade " + fixed$ (crossfade, 3) + " s" fi
        ... + "   ##Headroom:## " + string$ (pass) + " pass(es), " + string$ (exportBits) + "-bit intermediate   ##L/R correlation:## " + fixed$ (outCorr, 2) + " (descriptive)"
    Select inner viewport: 0.60, 7.70, 7.55, 8.05
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Line width: 1
    Select outer viewport: 0, 8, 0, 8.1
endif

# ============================================================
# PLAY
# ============================================================
if play_result and accepted
    selectObject: result
    asynchronous Play
endif
selectObject: result

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc
