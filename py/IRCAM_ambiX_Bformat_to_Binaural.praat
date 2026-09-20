# ============================================================
# Praat AudioTools - IRCAM_ambiX_Bformat_to_Binaural.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.4.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   ambiX B-format -> binaural stereo via a TWO-STAGE Spat5 chain:
#     B-format --spat5.hoa.decoder~--> full-range virtual speakers
#       (7.1.4: silent LFE inserted; 22.2: 22 directional + 2 silent LFE at end)
#       --spat5.virtualspeakers~--> binaural
#   The input is ALREADY Ambisonic: it is decoded, never re-encoded.
#   Companion of IRCAM_Multichannel_to_Binaural (loudspeaker feeds) and
#   IRCAM_Pan_to_Binaural (mono/stereo sources).
#
#   Expected input (the samples cannot prove it): ambiX = ACN channel order,
#   SN3D normalisation, full 3D. Order from the channel count:
#   4 = 1st, 9 = 2nd, 16 = 3rd, 25 = 4th, 36 = 5th.
#
#   AUTO LAYOUT (Final) - chosen by RANK, not by speaker count: the matrix
#   of real spherical harmonics at the speaker directions must have rank
#   (order+1)^2, or some Ambisonic components cannot be reproduced at all.
#   Rank of the built-in arrays (computed from the exact positions below):
#              order 1   2      3      4      5
#     2.0          2/4   2/9    2/16   2/25   2/36
#     4.0          3/4   4/9    4/16   4/25   4/36
#     5.0          3/4   5/9    5/16   5/25   5/36
#     7.0          3/4   5/9    7/16   7/25   7/36   (no elevation: Z lost)
#     7.1.4        4/4   8/9   11/16  11/25  11/36
#     22.2         4/4   9/9   16/16  20/25  22/36
#   Auto (Final) = 22.2 for orders 1-3: full rank AND full sphere (three
#   speakers at -30 deg put the listener inside the array). 7.1.4 is full
#   rank for order 1 but has no speaker below ear level, so the listener
#   sits on the edge of the array; it stays a lighter manual choice.
#   Orders 4 and 5 are refused (no built-in array is full rank). Any other
#   choice is allowed, with the number of lost components stated.
#   Fast horizontal preview decodes any order to 4.0 (quick, loses all
#   vertical information).
#
#   ORIENTATION: standard ambiX has X = front, Y = left; IRCAM state that
#   Spat uses Y = front, X = right, so standard ambiX needs a 90-degree yaw
#   before Spat. The field is rotated about the vertical axis before
#   decoding (exact real-SH rotation, every order):
#     a'(l,m)  = a(l,m) cos(m th) - a(l,-m) sin(m th)
#     a'(l,-m) = a(l,-m) cos(m th) + a(l,m) sin(m th)
#   With th = +90: front (X=1) -> Y'=1 (Spat front), left (Y=1) -> X'=-1
#   (Spat left). Input orientation:
#     Standard ambiX  (default)  +90 deg   - e.g. Spatial Trajectory Painter
#     Spat-native                  0 deg   - files made in Spat
#     Custom                       Custom yaw (deg)
#   Verify once on your Spat5 with the orientation test (tick "Create
#   orientation test"): a standard-ambiX first-order Sound with bursts from
#   Front, Left, Back, Right in that order.
#
#   SAFE RENDER: the decoded speakers and the binaural output are checked
#   for clipping; a clipped render is discarded and re-rendered from the
#   source 6 dB lower (up to 5 attempts). Only a clean render is normalised.
#
# Dependencies: Spat5 (spat5.hoa.decoder~, spat5.virtualspeakers~),
#   Python 3 with spat_bformat_bridge.py v2.4.1 next to this script.
#
# Changelog:
#   v2.4.1 - FIX: 22.2 HRTF channel mapping. Direct channel-walk validation
#            showed that spat5.virtualspeakers~ -f 22.2 maps its first 22
#            inputs to directional feeds; it still requires 24 total channels.
#            The delivery adapter therefore appends two silent LFE channels.
#            External NHK/AES LFE slots
#            4 and 10 must not be inserted before HRTF rendering. The decoder
#            remains 22 full-range speakers; only the adapter between decoder
#            feeds and virtualspeakers changed. 7.1.4 handling is unchanged.
#   v2.3.3 - FLBR pre-HRTF diagnostic now reports a geometric orientation
#            PASS/FAIL using expected Spat azimuths 0/-90/180/+90 deg, with
#            a 20-deg azimuth tolerance and minimum energy-vector magnitude
#            0.10. Binaural ILD/ITD remains descriptive only. No decoder or
#            HRTF DSP changed.
#   v2.3.2 - Fixes Praat form-variable case mapping for the FLBR diagnostic.
#            No DSP or decoder logic changed.
#   v2.3 - Adds an optional pre-HRTF FLBR speaker-feed diagnostic. It reports
#          per-burst energy-vector azimuth/elevation and the two strongest
#          decoded feeds, and can retain the decoded speaker feeds as a Praat
#          Sound for direct inspection. No decoder or HRTF DSP is changed.
#   v2.2 - Final / Auto = 22.2 for orders 1-3 (full sphere, not only full
#          rank). Safe render is attenuate-only: the start gain is capped
#          at 0 dB, so a quiet source is never boosted before Spat5 (v2.1
#          raised a -20 dBFS source by 14 dB, even with normalisation off).
#          Bridge 2.2: NaN/Inf checked sample by sample at every stage.
#   v2.1 - Auto chooses a FULL-RANK array (rank table above): order 1 ->
#          7.1.4, orders 2-3 -> 22.2. v2.0 decoded order 1 to 7.0 (rank 3/4:
#          Z lost) and order 2 to 7.1.4 (rank 8/9). Warnings now state the
#          number of lost components for any layout; the old check
#          (speakers < channels) missed order 1 -> 7.0.
#          Input orientation: Standard ambiX (+90, default) / Spat-native /
#          Custom. Preview renamed "Fast horizontal preview".
#          Bridge 2.1: the decoded speakers are checked for sample rate,
#          length (no shortening) and NaN/Inf.
#   v2.0 - LFE: v1.8 decoded full-band speakers into LFE slots (7.1 ch 4;
#          22.2 ch 4 and 10, which also duplicated the directions of BtFL
#          and BtFR). Now full-range decoding + silent LFE insertion; 7.1
#          removed (use 7.0; the LFE carried nothing).
#          Safe render replaces the fixed -18 dB: per-stage clipping
#          detection, iterative re-render, normalisation only when clean.
#          v1.8 could report "Clipping: YES" and "Validation: PASS"
#          together, and its checker missed a file with 78 % of its samples
#          at full scale.
#          Output shorter than the input (> 2 samples) is a validation
#          failure, not a note. Correlation is descriptive only.
#          Auto policy: 7.0 / 7.1.4 / 22.2 by order; orders 4-5 refused in
#          Auto instead of being decoded to 8 feeds.
#          Yaw correction (exact, any order) + orientation test generator.
#          House-style visualization with safe-render passes and ledger.
#   v1.8 - stable bridge filename; compact Auto tokens expanded in Python.
#   v1.5 - processing headroom; version handshake; temp-file cleanup.
#   v1.2 - Spat5 -p semantics: complete OSC command list.
#   v1.0 - initial two-stage decode->binaural pipeline.
# ============================================================

scriptVersion$ = "2.4.1"

form ambiX B-format to Binaural v2.4.1
    comment Input = ambiX B-format (ACN / SN3D). Decoded, never re-encoded.
    sentence Tools_folder C:/Users/User/Documents/Max 9/Packages/spat5-x64/media/tools/
    optionmenu Render_mode: 2
        option "Fast horizontal preview  (4.0, loses elevation)"
        option "Final  (Auto: 22.2 full sphere, orders 1-3)"
    optionmenu Layout_preset: 1
        option "Auto"
        option "2.0"
        option "4.0"
        option "5.0"
        option "7.0"
        option "7.1.4  (11 speakers + silent LFE)"
        option "22.2  (22 directional + 2 silent LFE tail slots for Spat HRTF)"
    optionmenu Input_orientation: 1
        option "Standard ambiX  (X front, Y left: +90 deg for Spat)"
        option "Spat-native  (no rotation)"
        option "Custom  (Custom yaw below)"
    real Custom_yaw_deg 0
    sentence Sofa_file kemar
    real Itd_percent 100
    optionmenu Room_option: 1
        option "Direct  (none)"
        option "hall"
        option "livingroom"
        option "studio"
    boolean Normalise_output 1
    real Output_peak_dBFS -1
    boolean Create_orientation_test 0
    boolean Keep_decoded_speaker_feeds 0
    boolean Flbr_speaker_feed_diagnostic 0
    boolean Play_result 1
    boolean Draw_visualization 1
endform

# ---- advanced (edit here) ----
tail_handling = 1
show_log = 0

# ============================================================
# ORIENTATION TEST (no render)
# ============================================================
if create_orientation_test
    tsr = 48000
    test = Create Sound from formula: "ambiX_orientation_test_FLBR", 4, 0, 4, tsr, "0"
    burst = Create Sound from formula: "burst", 1, 0, 4, tsr, "if (x mod 1) >= 0.05 and (x mod 1) < 0.85 then randomGauss (0, 1) else 0 fi"
    Filter (formula): "if x > 20 then self / sqrt (x / 20) else 0 fi"
    Formula: "self * (if (x mod 1) >= 0.05 and (x mod 1) < 0.85 then min (1, ((x mod 1) - 0.05) / 0.01) * min (1, (0.85 - (x mod 1)) / 0.01) else 0 fi)"
    # directions per second (ambiX: +azimuth = left): Front 0, Left 90, Back 180, Right -90
    selectObject: test
    Formula: "object[burst, 1, col] * (if row = 1 then 1 else if row = 2 then sin (pi / 2 * floor (x)) else if row = 3 then 0 else cos (pi / 2 * floor (x)) fi fi fi)"
    Scale peak: 0.1
    removeObject: burst
    selectObject: test
    writeInfoLine: "=== ambiX orientation test ==="
    appendInfoLine: "4 channels (first order, ACN W Y Z X, SN3D), 4 s, pink-noise bursts at -20 dBFS peak:"
    appendInfoLine: "  0-1 s FRONT   1-2 s LEFT   2-3 s BACK   3-4 s RIGHT"
    appendInfoLine: "It is STANDARD ambiX. For the reference orientation check, render it with:"
    appendInfoLine: "  Input orientation = Standard ambiX; Room = Direct (none); FLBR speaker-feed diagnostic = ON."
    appendInfoLine: "Use the pre-HRTF Speaker-feed orientation PASS/FAIL as coordinate ground truth."
    appendInfoLine: "Headphone listening and ILD/ITD are secondary perceptual diagnostics only."
    exitScript ()
endif

# ============================================================
# INPUT
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object (an ambiX B-format master)."
endif
original    = selected ("Sound")
sourceName$ = selected$ ("Sound")
selectObject: original
numCh      = Get number of channels
duration   = Get total duration
sr         = Get sampling frequency
numSamples = Get number of samples
if numSamples <= 0
    exitScript: "Selected Sound has no samples."
endif
if numCh = 4
    order = 1
elsif numCh = 9
    order = 2
elsif numCh = 16
    order = 3
elsif numCh = 25
    order = 4
elsif numCh = 36
    order = 5
else
    exitScript: "The Sound has " + string$ (numCh) + " channels: not a Full-3D ambiX B-format." + newline$
        ... + "Valid: 4 (1st), 9 (2nd), 16 (3rd), 25 (4th), 36 (5th order)." + newline$
        ... + "These must be Ambisonic components (W, Y, Z, X ...). For loudspeaker feeds use IRCAM_Multichannel_to_Binaural."
endif

helper_py$      = defaultDirectory$ + "/spat_bformat_bridge.py"
working_folder$ = defaultDirectory$ + "/"
if right$ (tools_folder$, 1) <> "/" and right$ (tools_folder$, 1) <> "\"
    tools_folder$ = tools_folder$ + "/"
endif

notes$ = ""
if output_peak_dBFS > 0 or output_peak_dBFS < -24
    notes$ = notes$ + "Note: Output_peak_dBFS outside -24..0, clamped." + newline$
    output_peak_dBFS = max (-24, min (0, output_peak_dBFS))
endif
if itd_percent < 0 or itd_percent > 200
    notes$ = notes$ + "Note: Itd_percent outside 0..200, clamped." + newline$
    itd_percent = max (0, min (200, itd_percent))
endif

# ============================================================
# LAYOUT + MATCHED DECODER PRESET
# ============================================================
if layout_preset = 1
    if render_mode = 1
        layoutToken$ = "4.0"
    elsif order <= 3
        layoutToken$ = "22.2"
    else
        exitScript: "Final / Auto: no built-in array is full rank for order " + string$ (order) + " (" + string$ (numCh) + " components);" + newline$
            ... + "the best, 22.2, reaches rank " + if order = 4 then "20/25" else "22/36" fi + "." + newline$
            ... + "Choose Layout 22.2 manually to render anyway (components lost, stated), or use the preview."
    endif
else
    tok$[2] = "2.0"
    tok$[3] = "4.0"
    tok$[4] = "5.0"
    tok$[5] = "7.0"
    tok$[6] = "7.1.4"
    tok$[7] = "22.2"
    layoutToken$ = tok$[layout_preset]
endif

lfe$ = "0"
method$ = ""
if layoutToken$ = "2.0"
    nSpk = 2
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0"
elsif layoutToken$ = "4.0"
    nSpk = 4
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae -110 0, /speaker/4/ae 110 0"
elsif layoutToken$ = "5.0"
    nSpk = 5
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -110 0, /speaker/5/ae 110 0"
elsif layoutToken$ = "7.0"
    nSpk = 7
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -90 0, /speaker/5/ae 90 0, /speaker/6/ae -150 0, /speaker/7/ae 150 0"
elsif layoutToken$ = "7.1.4"
    nSpk = 11
    lfe$ = "4"
    method$ = ", /method energy-preserving"
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -90 0, /speaker/5/ae 90 0, /speaker/6/ae -150 0, /speaker/7/ae 150 0"
        ... + ", /speaker/8/ae -45 45, /speaker/9/ae 45 45, /speaker/10/ae -135 45, /speaker/11/ae 135 45"
else
    nSpk = 22
    # Decoder outputs the 22 directional speakers. The Python bridge appends
    # two silent LFE channels at positions 23/24 for Spat5 virtualspeakers.
    lfe$ = "0"
endif
if layoutToken$ = "22.2"
    decoderToken$ = "AUTO_22_2_FULLRANGE"
    decoderShow$ = "order " + string$ (order) + ", SN3D, EPAD, 22 directional speakers + silent LFE tail slots for 24ch Spat input"
else
    decoderToken$ = "/order " + string$ (order) + ", /dimension 3, /norm SN3D" + method$ + ", /speaker/number " + string$ (nSpk) + spkPos$
    decoderShow$ = "order " + string$ (order) + ", SN3D, " + string$ (nSpk) + " full-range speakers" + if lfe$ <> "0" then " + silent LFE" else "" fi
endif
# decoding-matrix rank of the built-in arrays (real SH at the exact speaker
# directions; see header), orders 1..5
if layoutToken$ = "2.0"
    rkRow$ = "2 2 2 2 2"
elsif layoutToken$ = "4.0"
    rkRow$ = "3 4 4 4 4"
elsif layoutToken$ = "5.0"
    rkRow$ = "3 5 5 5 5"
elsif layoutToken$ = "7.0"
    rkRow$ = "3 5 7 7 7"
elsif layoutToken$ = "7.1.4"
    rkRow$ = "4 8 11 11 11"
else
    rkRow$ = "4 9 16 20 22"
endif
rkWords$# = splitByWhitespace$# (rkRow$)
layoutRank = number (rkWords$# [order])
underDet = layoutRank < numCh
lostComp = numCh - layoutRank
horizontal = layoutToken$ = "2.0" or layoutToken$ = "4.0" or layoutToken$ = "5.0" or layoutToken$ = "7.0"

if room_option = 1
    roomName$ = "none"
elsif room_option = 2
    roomName$ = "hall"
elsif room_option = 3
    roomName$ = "livingroom"
else
    roomName$ = "studio"
endif
modeArg$ = if render_mode = 1 then "preview" else "final" fi
if flbr_speaker_feed_diagnostic
    modeArg$ = modeArg$ + "_diag"
endif

# ============================================================
# TEMP FILES
# ============================================================
runTag$    = string$ (randomInteger (100000, 999999))
inputWav$  = working_folder$ + "bformat_input_" + runTag$ + ".wav"
speakWav$  = working_folder$ + "decoded_speakers_" + runTag$ + ".wav"
outputWav$ = working_folder$ + "binaural_output_" + runTag$ + ".wav"
logTxt$    = working_folder$ + "bformat_log_" + runTag$ + ".txt"
statsTxt$  = working_folder$ + "bformat_stats_" + runTag$ + ".txt"
if windows
    platform$ = "Windows"
elsif macintosh
    platform$ = "macOS"
else
    platform$ = "Linux"
endif

# ============================================================
# WORKING COPY: yaw correction (exact real-SH rotation), then levels
# ============================================================
if input_orientation = 1
    yaw_correction_deg = 90
elsif input_orientation = 2
    yaw_correction_deg = 0
else
    yaw_correction_deg = custom_yaw_deg
endif
orientName$[1] = "standard ambiX (+90 deg for Spat)"
orientName$[2] = "Spat-native (no rotation)"
orientName$[3] = "custom yaw " + fixed$ (custom_yaw_deg, 1) + " deg"
selectObject: original
work = Copy: "__bformat_work"
if yaw_correction_deg <> 0
    th = yaw_correction_deg * pi / 180
    selectObject: work
    ref = Copy: "__bformat_ref"
    for l from 1 to order
        for m from 1 to l
            iPos = l * l + l + m + 1
            iNeg = l * l + l - m + 1
            c = cos (m * th)
            s = sin (m * th)
            selectObject: work
            Formula: "if row = " + string$ (iPos) + " then object[" + string$ (ref) + ", " + string$ (iPos) + ", col] * " + string$ (c)
                ... + " - object[" + string$ (ref) + ", " + string$ (iNeg) + ", col] * " + string$ (s)
                ... + " else if row = " + string$ (iNeg) + " then object[" + string$ (ref) + ", " + string$ (iNeg) + ", col] * " + string$ (c)
                ... + " + object[" + string$ (ref) + ", " + string$ (iPos) + ", col] * " + string$ (s) + " else self fi fi"
        endfor
    endfor
    removeObject: ref
endif
selectObject: work
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak <= 0
    removeObject: work
    exitScript: "The Sound is silent."
endif
srcPeakDb = 20 * log10 (srcPeak)
exportSafeDb = -1 - srcPeakDb
# attenuate-only: never boost before Spat5 (level is set by the optional
# normalisation after a clean render)
gainDb = min (0, min (exportSafeDb, -srcPeakDb - 6))
maxAttempts = 5

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine:  "=== ambiX B-format to Binaural v2.4.1 (safe render) ==="
appendInfoLine: "Platform:   ", platform$
appendInfoLine: "Source:     ", sourceName$, "  (", numCh, " ch = order ", order, ", ", fixed$ (duration, 3), " s @ ", sr, " Hz), peak ", fixed$ (srcPeakDb, 1), " dBFS"
appendInfoLine: "Orientation: ", orientName$[input_orientation], if yaw_correction_deg <> 0 then ", field rotated " + fixed$ (yaw_correction_deg, 1) + " deg before decoding" else "" fi
appendInfoLine: "Layout:     ", layoutToken$, if layout_preset = 1 then " (Auto for order " + string$ (order) + ")" else "" fi
appendInfoLine: "Decoder:    ", decoderShow$
appendInfoLine: "Rank:       ", layoutRank, " / ", numCh, if underDet then "" else "  (full rank)" fi
if underDet
    appendInfoLine: "WARNING:    decoding matrix rank ", layoutRank, " of ", numCh, ": ", lostComp, " Ambisonic component(s) cannot be reproduced."
    if horizontal
        appendInfoLine: "            Horizontal layout: all vertical information is lost."
    endif
endif
appendInfoLine: "HRTF:       ", sofa_file$, "  ITD ", fixed$ (itd_percent, 0), "%  room ", roomName$
appendInfoLine: "Headroom:   safe render, start ", fixed$ (gainDb, 1), " dB"
if notes$ <> ""
    appendInfo: notes$
endif
appendInfoLine: ""

if not fileReadable (helper_py$)
    removeObject: work
    exitScript: "Python bridge not found next to this script:" + newline$ + helper_py$
endif

# ============================================================
# DETECT PYTHON (3-candidate probe with a stdlib dependency check)
# ============================================================
# Candidates must be single-word commands: runSubprocess passes the executable
# name as one argument, so "py -3" would fail.
probeMarker$ = working_folder$ + "bformat_probe_" + runTag$ + ".ok"

if windows
    pyCandidate1$ = "python"
    pyCandidate2$ = "py"
    pyCandidate3$ = "python3"
else
    pyCandidate1$ = "python3"
    pyCandidate2$ = "python"
    pyCandidate3$ = "py"
endif

pythonCmd$ = ""
for iCand from 1 to 3
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
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = 4
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find a working Python 3 installation." + newline$
        ... + "Tried: " + pyCandidate1$ + ", " + pyCandidate2$ + ", " + pyCandidate3$ + newline$
        ... + "Install Python 3 and ensure it is on your PATH."
endif


# ============================================================
# SAFE RENDER LOOP
# ============================================================
attempt = 0
accepted = 0
hardFail = 0
while attempt < maxAttempts and accepted = 0 and hardFail = 0
    attempt += 1
    attGain[attempt] = gainDb
    selectObject: work
    expo = Copy: "__bformat_export"
    Multiply: 10 ^ (gainDb / 20)
    Save as 24-bit WAV file: inputWav$
    removeObject: expo
    nocheck runSubprocess: pythonCmd$, helper_py$,
        ... inputWav$, speakWav$, outputWav$, logTxt$,
        ... tools_folder$, decoderToken$, layoutToken$,
        ... sofa_file$, string$ (itd_percent), roomName$,
        ... string$ (nSpk), string$ (order), modeArg$, scriptVersion$, statsTxt$, lfe$
    if fileReadable (statsTxt$) and fileReadable (outputWav$)
        stats$ = readFile$ (statsTxt$)
        attClipped[attempt] = extractNumber (stats$, "clipped=")
        attStage$[attempt] = extractWord$ (stats$, "clip_stage=")
        attPeak[attempt] = max (extractNumber (stats$, "peak_l="), extractNumber (stats$, "peak_r="))
        shortFrames = extractNumber (stats$, "short_frames=")
        outFormat$ = extractWord$ (stats$, "format=")
        outCorr = extractNumber (stats$, "correlation=")
        if attClipped[attempt]
            appendInfoLine: "  attempt ", attempt, ": input ", fixed$ (gainDb, 1), " dB -> CLIPPED at the ", attStage$[attempt], " stage"
            gainDb = gainDb - 6
        else
            accepted = 1
            appendInfoLine: "  attempt ", attempt, ": input ", fixed$ (gainDb, 1), " dB -> clean, render peak ", fixed$ (20 * log10 (max (attPeak[attempt], 1e-12)), 2), " dBFS (", outFormat$, ")"
        endif
    else
        hardFail = 1
    endif
endwhile
removeObject: work

procedure dumpLogAndClean
    appendInfoLine: "Log: ", logTxt$
    if fileReadable (logTxt$)
        appendInfoLine: ""
        appendInfoLine: "=== Spat5 log ==="
        appendInfoLine: readFile$ (logTxt$)
    else
        appendInfoLine: "(no log - the bridge could not start; check Python and the Tools folder)"
    endif
    deleteFile: inputWav$
    deleteFile: speakWav$
    deleteFile: outputWav$
    deleteFile: logTxt$
    deleteFile: statsTxt$
endproc

if hardFail
    appendInfoLine: ""
    appendInfoLine: "ERROR: binaural render failed (attempt ", attempt, ")."
    @dumpLogAndClean
    exitScript: "Render failed - see the Info window."
endif

# ============================================================
# IMPORT + VALIDATE
# ============================================================
Read from file: outputWav$
fileBacked = selected ("Sound")
fbDur = Get total duration
result = Extract part: 0, fbDur, "rectangular", 1, "no"
removeObject: fileBacked
selectObject: result
outSamples = Get number of samples
validation$ = "PASS"
valNote$ = ""
if accepted = 0
    validation$ = "FAIL"
    valNote$ = valNote$ + " [still clipping after " + string$ (maxAttempts) + " renders, input down to " + fixed$ (attGain[attempt], 1) + " dB]"
endif
if shortFrames > 2
    validation$ = "FAIL"
    valNote$ = valNote$ + " [output " + string$ (shortFrames) + " samples SHORTER than the input]"
endif
tailSamples = outSamples - numSamples
if tailSamples > 0
    tail$ = "+" + string$ (tailSamples) + " samples (" + fixed$ (tailSamples / sr, 3) + " s) HRTF/room tail"
elsif tailSamples >= -2
    tail$ = "exact"
else
    tail$ = string$ (-tailSamples) + " samples SHORTER than the input"
endif
if tail_handling = 2 and tailSamples > 0
    trimmed = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: result
    result = trimmed
endif
selectObject: result
renderPeak = Get absolute extremum: 0, 0, "None"
renderPeakDb = 20 * log10 (max (renderPeak, 1e-12))
normDb = 0
if validation$ = "PASS"
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
outDur = Get total duration
Rename: sourceName$ + "_binaural"
resultName$ = sourceName$ + "_binaural"
netDb = attGain[attempt] + normDb

if flbr_speaker_feed_diagnostic
    diagValid = extractNumber (stats$, "diag_valid=")
    appendInfoLine: ""
    appendInfoLine: "=== FLBR SPEAKER-FEED DIAGNOSTIC (pre-HRTF) ==="
    appendInfoLine: "Spat azimuth here: negative = left, positive = right; 0 = front, +/-180 = back."
    if layoutToken$ = "4.0"
        appendInfoLine: "4.0 feeds: ch1=FL(-30), ch2=FR(+30), ch3=BL(-110), ch4=BR(+110)."
    endif
    if diagValid = 1
        diagLabel$[1] = "FRONT"
        diagLabel$[2] = "LEFT"
        diagLabel$[3] = "BACK"
        diagLabel$[4] = "RIGHT"
        for dburst from 1 to 4
            daz = extractNumber (stats$, "diag_b" + string$ (dburst) + "_az=")
            dexp = extractNumber (stats$, "diag_b" + string$ (dburst) + "_expected_az=")
            derr = extractNumber (stats$, "diag_b" + string$ (dburst) + "_az_error=")
            delv = extractNumber (stats$, "diag_b" + string$ (dburst) + "_el=")
            dmag = extractNumber (stats$, "diag_b" + string$ (dburst) + "_mag=")
            dtop1 = extractNumber (stats$, "diag_b" + string$ (dburst) + "_top1=")
            dtop2 = extractNumber (stats$, "diag_b" + string$ (dburst) + "_top2=")
            appendInfoLine: "  ", diagLabel$[dburst], ": energy-vector az ", fixed$ (daz, 1), " deg (expected ", fixed$ (dexp, 0), ", error ", fixed$ (derr, 1), "), el ", fixed$ (delv, 1), " deg, magnitude ", fixed$ (dmag, 3), "; strongest feeds ch", dtop1, " / ch", dtop2
        endfor
        diagPass = extractNumber (stats$, "diag_pass=")
        diagMaxErr = extractNumber (stats$, "diag_max_az_error=")
        diagMinMag = extractNumber (stats$, "diag_min_magnitude=")
        appendInfoLine: "  Speaker-feed orientation  ", if diagPass = 1 then "PASS" else "FAIL" fi, "  (max az error ", fixed$ (diagMaxErr, 1), " deg; min magnitude ", fixed$ (diagMinMag, 3), ")"
        appendInfoLine: "  This is the reference coordinate/decoder check; binaural ILD/ITD is secondary diagnostic evidence."
    else
        appendInfoLine: "  Diagnostic unavailable (the decoded feed must contain the complete 4 s FLBR test)."
    endif
endif

appendInfoLine: ""
appendInfoLine: "=== RESULT ==="
appendInfoLine: "  source peak          ", fixed$ (srcPeakDb, 2), " dBFS"
appendInfoLine: "  input attenuation    ", fixed$ (attGain[attempt], 2), " dB   (", attempt, " render", if attempt > 1 then "s" else "" fi, ", 24-bit intermediate)"
appendInfoLine: "  render peak          ", fixed$ (renderPeakDb, 2), " dBFS  (", outFormat$, ")"
appendInfoLine: "  normalisation        ", if normDb = 0 then "none" else fixed$ (normDb, 2) + " dB" fi
appendInfoLine: "  output peak          ", fixed$ (finalPeakDb, 2), " dBFS"
appendInfoLine: "  net source->output   ", fixed$ (netDb, 2), " dB"
appendInfoLine: "  duration / tail      ", fixed$ (outDur, 3), " s  (", tail$, ")"
appendInfoLine: "  L/R correlation      ", fixed$ (outCorr, 3), "  (descriptive only)"
appendInfoLine: "  Validation           ", validation$, valNote$
if validation$ = "FAIL"
    appendInfoLine: ""
    appendInfoLine: "ERROR: output validation FAILED - the Sound is kept for inspection only."
    @dumpLogAndClean
    selectObject: result
    exitScript: "Binaural output failed validation. See the Info window."
endif
if show_log and fileReadable (logTxt$)
    appendInfoLine: ""
    appendInfoLine: readFile$ (logTxt$)
endif
feedName$ = ""
if keep_decoded_speaker_feeds or flbr_speaker_feed_diagnostic
    if fileReadable (speakWav$)
        Read from file: speakWav$
        feedsObj = selected ("Sound")
        feedName$ = sourceName$ + "_decoded_" + replace$ (layoutToken$, ".", "_", 0)
        Rename: feedName$
        selectObject: result
    endif
endif
deleteFile: inputWav$
deleteFile: speakWav$
deleteFile: outputWav$
deleteFile: logTxt$
deleteFile: statsTxt$
appendInfoLine: ""
appendInfoLine: "Done. Binaural Sound: ", resultName$, "  (temporary files deleted)"
if feedName$ <> ""
    appendInfoLine: "Decoded speaker feeds kept as Sound: ", feedName$
endif

# ============================================================
# VISUALIZATION (house style, 8 x 6.5 in)
# ============================================================
if draw_visualization
    cPrim$ = "{0.20, 0.48, 0.75}"
    cSec$ = "{0.85, 0.38, 0.18}"
    cGrey$ = "{0.55, 0.55, 0.60}"
    cGround$ = "{0.97, 0.97, 0.97}"
    cGrid$ = "{0.80, 0.80, 0.80}"
    cSub$ = "{0.35, 0.35, 0.50}"
    cSum$ = "{0.25, 0.25, 0.35}"
    nm$ = replace$ (sourceName$, "_", "\_ ", 0)
    Erase all
    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##ambiX B-format to Binaural v2.4.1##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: cSub$
    Text: 0.5, "centre", 0.22, "half", nm$ + "   |   order " + string$ (order) + " (" + string$ (numCh) + " ch) -> " + string$ (nSpk) + " speakers (" + layoutToken$ + ") -> binaural   |   rank " + string$ (layoutRank) + "/" + string$ (numCh) + "   |   yaw " + fixed$ (yaw_correction_deg, 0) + " deg"

    # A: W component at its true level
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    Axes: 0, duration, -1, 1
    Paint rectangle: cGround$, 0, duration, -1, 1
    selectObject: original
    vizW = Extract one channel: 1
    Colour: cGrey$
    Draw: 0, 0, -1, 1, "no", "Curve"
    removeObject: vizW
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    Axes: 0, duration, -1, 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "W (ACN0)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    Text top: "no", "##A   Input##   omni component W, true level (full scale = frame)"

    # B: binaural output
    Font size: 7
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    Axes: 0, outDur, -1.1, 1.1
    Paint rectangle: cGround$, 0, outDur, -1.1, 1.1
    selectObject: result
    vR = Extract one channel: 2
    Colour: cSec$
    Draw: 0, 0, -1.1, 1.1, "no", "Curve"
    removeObject: vR
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    selectObject: result
    vL = Extract one channel: 1
    Colour: cPrim$
    Draw: 0, 0, -1.1, 1.1, "no", "Curve"
    removeObject: vL
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    Axes: 0, outDur, -1.1, 1.1
    Colour: cGrid$
    Dotted line
    Draw line: 0, 1, outDur, 1
    Draw line: 0, -1, outDur, -1
    Solid line
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    @niceStep: outDur, 8
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "Binaural"
    Text bottom: "yes", "Time (s)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    Text top: "no", "##B   Binaural output##   blue = L ear, orange = R ear; dotted = full scale; peak " + fixed$ (finalPeakDb, 1) + " dBFS"

    # C: safe-render attempts
    yLo = min (-30, floor (min (attGain[attempt], renderPeakDb) / 6) * 6 - 6)
    Font size: 7
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Axes: 0.4, attempt + 0.6, yLo, 6
    Paint rectangle: cGround$, 0.4, attempt + 0.6, yLo, 6
    Colour: cSec$
    Dotted line
    Draw line: 0.4, 0, attempt + 0.6, 0
    Solid line
    for a from 1 to attempt
        pk = 20 * log10 (max (attPeak[a], 1e-12))
        if attClipped[a]
            Paint rectangle: cSec$, a - 0.3, a + 0.3, yLo, max (pk, 0)
        else
            Paint rectangle: cPrim$, a - 0.3, a + 0.3, yLo, pk
        endif
    endfor
    Font size: 6
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Axes: 0.4, attempt + 0.6, yLo, 6
    for a from 1 to attempt
        pk = 20 * log10 (max (attPeak[a], 1e-12))
        Colour: cSum$
        Text: a, "centre", max (pk, 0) + 0.8, "bottom", if attClipped[a] then "clipped (" + attStage$[a] + ")" else fixed$ (pk, 1) fi
        Text: a, "centre", yLo + 1.5, "bottom", "in " + fixed$ (attGain[a], 1)
    endfor
    Font size: 7
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Axes: 0.4, attempt + 0.6, yLo, 6
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 6, "yes", "yes", "no"
    for a from 1 to attempt
        One mark bottom: a, "no", "yes", "no", string$ (a)
    endfor
    Text left: "yes", "Render peak (dBFS)"
    Text bottom: "yes", "Render attempt"
    Font size: 8
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Text top: "no", "##C   Safe render##   orange = clipped, re-rendered"

    # D: level ledger
    Font size: 7
    Select inner viewport: 4.45, 7.70, 4.30, 5.45
    Axes: 0, 1, 0, 1
    Paint rectangle: cGround$, 0, 1, 0, 1
    Colour: cSum$
    Text: 0.04, "left", 0.88, "half", "Source peak"
    Text: 0.96, "right", 0.88, "half", fixed$ (srcPeakDb, 1) + " dBFS"
    Text: 0.04, "left", 0.72, "half", "Input attenuation"
    Text: 0.96, "right", 0.72, "half", fixed$ (attGain[attempt], 1) + " dB"
    Text: 0.04, "left", 0.56, "half", "Render peak"
    Text: 0.96, "right", 0.56, "half", fixed$ (renderPeakDb, 1) + " dBFS"
    Text: 0.04, "left", 0.40, "half", "Normalisation"
    Text: 0.96, "right", 0.40, "half", if normDb = 0 then "none" else fixed$ (normDb, 1) + " dB" fi
    Text: 0.04, "left", 0.24, "half", "##Output peak##"
    Text: 0.96, "right", 0.24, "half", "##" + fixed$ (finalPeakDb, 1) + " dBFS##"
    Text: 0.04, "left", 0.08, "half", "Tail"
    Text: 0.96, "right", 0.08, "half", tail$
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select inner viewport: 4.45, 7.70, 4.30, 5.45
    Text top: "no", "##D   Level ledger##"

    Font size: 6
    Select inner viewport: 0.60, 7.70, 5.95, 6.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: cSum$
    Text: 0.01, "left", 0.72, "half", "##Decoder:## " + decoderShow$ + if underDet then "  (rank " + string$ (layoutRank) + "/" + string$ (numCh) + ": " + string$ (lostComp) + " component(s) lost" + if horizontal then ", no elevation" else "" fi + ")" else "  (full rank " + string$ (layoutRank) + ")" fi
    Text: 0.01, "left", 0.28, "half", "##HRTF:## " + sofa_file$ + ", ITD " + fixed$ (itd_percent, 0) + " \% , room " + roomName$
        ... + "   ##Validation:## " + validation$ + "   ##L/R correlation:## " + fixed$ (outCorr, 2) + " (descriptive)"
    Select inner viewport: 0.60, 7.70, 5.95, 6.45
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Line width: 1
    Select outer viewport: 0, 8, 0, 6.5
endif

if play_result
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
