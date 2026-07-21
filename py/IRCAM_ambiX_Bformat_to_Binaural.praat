# ============================================================
# Praat AudioTools - ambiX_Bformat_to_Binaural.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.8 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   ambiX B-format -> binaural stereo via a TWO-STAGE Spat5 chain.
#
#     Ambisonic B-format
#       -> spat5.hoa.decoder~        (decode to virtual loudspeaker feeds)
#       -> spat5.virtualspeakers~    (HRTF/SOFA convolution)
#       -> binaural stereo WAV
#
#   The selected Sound is ALREADY encoded Ambisonic. It is NOT a set of
#   loudspeaker feeds. This script therefore DECODES it first and NEVER
#   re-encodes it (the bridge never calls spat5.hoa.encoder~).
#
#   *** This is NOT the loudspeaker-feed tool. ***
#     Loudspeaker tool : speaker feeds ->                virtualspeakers -> binaural
#     THIS tool        : B-format      -> HOA decoder -> virtualspeakers -> binaural
#
#   Expected input (assumptions the audio samples cannot prove):
#     * ambiX format
#     * ACN channel ordering  (ch1=W/ACN0, ch2=Y/ACN1, ch3=Z/ACN2, ch4=X/ACN3, ...)
#     * SN3D normalization
#     * Full 3D spherical harmonics
#
#   Order is auto-detected from the channel count:
#      4 ch = 1st order    9 ch = 2nd order    16 ch = 3rd order
#     25 ch = 4th order   36 ch = 5th order    (any other count is rejected)
#
# Dependencies:
#   Spat5 (IRCAM) — spat5.hoa.decoder~ AND spat5.virtualspeakers~ CLI tools
#   Python 3      — spat_bformat_bridge.py (must sit next to this script)
#
# Changelog:
#   v1.0 — Initial release. Two-stage decode->binaural pipeline.
#   v1.1 — Added decoder/order diagnostics.
#   v1.2 — Corrected Spat5 -p semantics: complete OSC command list.
#   v1.5 — Real processing headroom before Spat5; no post-normalisation; no
#          final WAV save; all temporary files are deleted; version handshake
#          prevents an old Python bridge from running silently.
#   v1.6 — Third-order Auto introduced a 24-point full-sphere design.
#   v1.7 — Uses Spat5's built-in 22.2 24-channel 3-D layout.
#   v1.8 — Uses the stable original Python filename; compact Auto tokens are
#          expanded before OSC validation.
# ============================================================

# ---- INPUT CHECK: exactly one Sound ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object (an ambiX B-format master)."
endif

original     = selected("Sound")
sourceName$  = selected$("Sound")
selectObject: original
numCh        = Get number of channels
duration     = Get total duration
sr           = Get sampling frequency
numSamples   = Get number of samples

# ---- VALIDATE BASIC PROPERTIES (fail fast, before the form) ----
if sr <= 0
    exitScript: "Invalid sampling rate (" + string$(sr) + " Hz)."
endif
if numSamples <= 0
    exitScript: "Selected Sound has no samples."
endif

# ---- DETECT AMBISONIC ORDER FROM CHANNEL COUNT ----
# 4=(1+1)^2, 9=(2+1)^2, 16=(3+1)^2, 25=(4+1)^2, 36=(5+1)^2
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
    exitScript: "The selected Sound has " + string$(numCh) + " channels, which is"
        ... + " not a valid Full-3D ambiX B-format." + newline$
        ... + "Valid counts: 4 (1st), 9 (2nd), 16 (3rd), 25 (4th), 36 (5th) order."
        ... + newline$ + newline$
        ... + "NOTE: these channels are Ambisonic components (W, Y, Z, X, ...),"
        ... + " NOT loudspeaker feeds. If you have loudspeaker feeds, use"
        ... + " Multichannel_to_Binaural.praat instead."
endif

# ---- FIXED PATHS (bridge + working folder live next to this script) ----
helper_py$      = defaultDirectory$ + "/spat_bformat_bridge.py"
working_folder$ = defaultDirectory$ + "/"

# ---- FORM (kept short to fit on screen; advanced options default below) ----
form ambiX B-format to Binaural v1.8 — 24-speaker 3D Auto
    comment Input = ambiX B-format (W,Y,Z,X... ACN/SN3D). Decoded, never re-encoded.
    sentence Tools_folder C:/Users/User/Documents/Max 9/Packages/spat5-x64/media/tools/
    comment Decoder OSC preset is built automatically from order + layout.
    optionmenu Render_mode: 2
        option "Fast preview  (4.0; 3rd order Auto uses 22.2)"
        option "Final  (Auto; 3rd order uses 22.2)"
    optionmenu Layout_preset: 1
        option "Auto  (3rd order -> 22.2 / 24 speakers)"
        option "2.0  (2 speakers)"
        option "4.0  (4 speakers)"
        option "5.0  (5 speakers)"
        option "7.0  (7 speakers)"
        option "7.1  (8 feeds)"
        option "3D 22.2  (24 speakers)"
    sentence Sofa_file kemar
    real Itd_percent 100
    optionmenu Room_option: 1
        option "Direct  (none)"
        option "hall"
        option "livingroom"
        option "studio"
    boolean Open_result 1
    boolean Draw_visualization 1
endform

# ---- Advanced options (edit here if needed; kept out of the form for space) ----
# custom_layout$: advanced override for virtualspeakers -f ("" = use menu)
# custom_decoder_preset$: matching complete OSC command list for -p.
# processing_headroom_dB is applied BEFORE Spat5 to prevent intermediate overload.
# It is deliberately NOT restored after rendering and there is NO normalisation.
# tail_handling: 1 = preserve HRTF/room tail, 2 = trim to input duration.
custom_layout$           = ""
custom_decoder_preset$   = ""
custom_expected_speakers = 0
processing_headroom_dB   = 18.0
tail_handling            = 1
show_log                 = 1
diagnostic_selftest      = 0
scriptVersion$           = "1.8"

# ============================================================
# BUILD THE MATCHED DECODER OSC PRESET + VIRTUAL-SPEAKER LAYOUT
# ============================================================
# IMPORTANT: spat5.hoa.decoder~ -p does NOT take a symbolic name such as
# "hoa1_cube". It receives ONE comma-separated OSC command list. The stable
# Praat/Spat5 pipeline uses this exact structure:
#   /order N, /dimension 3, /norm SN3D,
#   /speaker/number M, /speaker/1/ae az el, ...
# Short presets are passed directly. The 24-speaker preset uses a compact marker
# expanded inside Python, preventing a long Windows command-line argument.
#
# The conventional 2.0/4.0/5.0/7.0/7.1 layouts reproduce the definitions
# used by the established IRCAM Pan-to-Binaural tool. For third-order input,
# Auto instead selects the built-in 22.2 full-sphere layout.
# A different custom 3-D array remains possible through the advanced variables.

if layout_preset = 1
    # Auto mode: third-order input always receives a genuinely 3-D 24-point
    # 22.2 full-sphere layout. This avoids the under-determined 7.1 decode.
    if order = 3
        layoutToken$ = "22.2"
        expectedSpk = 24
    elsif render_mode = 1
        layoutToken$ = "4.0"
        expectedSpk = 4
    else
        layoutToken$ = "7.1"
        expectedSpk = 8
    endif
elsif layout_preset = 2
    layoutToken$ = "2.0"
    expectedSpk = 2
elsif layout_preset = 3
    layoutToken$ = "4.0"
    expectedSpk = 4
elsif layout_preset = 4
    layoutToken$ = "5.0"
    expectedSpk = 5
elsif layout_preset = 5
    layoutToken$ = "7.0"
    expectedSpk = 7
elsif layout_preset = 6
    layoutToken$ = "7.1"
    expectedSpk = 8
else
    layoutToken$ = "22.2"
    expectedSpk = 24
endif

# Speaker positions must correspond exactly to the format passed later to
# spat5.virtualspeakers~. Coordinates are azimuth/elevation in degrees.
if layoutToken$ = "2.0"
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0"
elsif layoutToken$ = "4.0"
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae -110 0, /speaker/4/ae 110 0"
elsif layoutToken$ = "5.0"
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -110 0, /speaker/5/ae 110 0"
elsif layoutToken$ = "7.0"
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae -90 0, /speaker/5/ae 90 0, /speaker/6/ae -150 0, /speaker/7/ae 150 0"
elsif layoutToken$ = "7.1"
    spkPos$ = ", /speaker/1/ae -30 0, /speaker/2/ae 30 0, /speaker/3/ae 0 0, /speaker/4/ae 0 -30, /speaker/5/ae -90 0, /speaker/6/ae 90 0, /speaker/7/ae -150 0, /speaker/8/ae 150 0"
else
    # For the 24-channel 22.2 layout, do NOT pass the full OSC command list
    # through Praat's runSubprocess. On Windows that long single argument can
    # prevent the bridge from launching before it can create its log.
    # Python expands this compact marker to the complete matched 22.2 preset.
    spkPos$ = ""
endif

hoaHeader$ = "/order " + string$(order) + ", /dimension 3, /norm SN3D"
if layoutToken$ = "22.2" and expectedSpk = 24
    # Compact bridge marker. Python expands it to the complete 24-position
    # energy-preserving decoder preset matching virtualspeakers -f 22.2.
    decoderToken$ = "AUTO_3D24_22_2_SN3D"
else
    decoderToken$ = hoaHeader$ + ", /speaker/number " + string$(expectedSpk) + spkPos$
endif

# Advanced custom layout: require a matching full OSC decoder preset.
if custom_layout$ <> ""
    if custom_decoder_preset$ = "" or custom_expected_speakers <= 0
        exitScript: "A custom layout requires custom_decoder_preset$ and"
            ... + " custom_expected_speakers in the Advanced options."
    endif
    layoutToken$ = custom_layout$
    expectedSpk = custom_expected_speakers
    decoderToken$ = custom_decoder_preset$
endif

if decoderToken$ = "AUTO_3D24_22_2_SN3D"
    decoderShow$ = "Auto OSC preset: order 3, SN3D, EPAD, matched 22.2 / 24 speakers"
else
    decoderShow$ = "OSC preset: order " + string$(order) + ", SN3D, "
        ... + string$(expectedSpk) + " speakers"
endif

# --- Room / direct sound ---
if room_option = 1
    roomName$ = "none"
elsif room_option = 2
    roomName$ = "hall"
elsif room_option = 3
    roomName$ = "livingroom"
else
    roomName$ = "studio"
endif

# --- Diagnostic mode string passed to the bridge ---
if diagnostic_selftest
    modeArg$ = "selftest"
elsif render_mode = 1
    modeArg$ = "preview"
else
    modeArg$ = "final"
endif

# ============================================================
# NORMALISE FOLDERS
# ============================================================
if right$(tools_folder$, 1) <> "/" and right$(tools_folder$, 1) <> "\"
    tools_folder$ = tools_folder$ + "/"
endif
if right$(working_folder$, 1) <> "/" and right$(working_folder$, 1) <> "\"
    working_folder$ = working_folder$ + "/"
endif

# No final output path is created. Spat5 still requires temporary WAV files,
# but they are deleted immediately after the rendered Sound is copied into
# Praat memory.
resultName$ = sourceName$ + "_binaural"

# ============================================================
# TEMP FILES (collision-avoiding tag per run)
# ============================================================
runTag$    = string$(randomInteger(100000, 999999))
inputWav$  = working_folder$ + "bformat_input_"    + runTag$ + ".wav"
speakWav$  = working_folder$ + "decoded_speakers_" + runTag$ + ".wav"
outputWav$ = working_folder$ + "binaural_output_"  + runTag$ + ".wav"
logTxt$    = working_folder$ + "bformat_log_"      + runTag$ + ".txt"

# ============================================================
# PLATFORM + EXECUTABLE PATHS
# ============================================================
if windows
    platform$ = "Windows"
    exeExt$   = ".exe"
elsif macintosh
    platform$ = "macOS"
    exeExt$   = ""
else
    platform$ = "Linux"
    exeExt$   = ""
endif
decoderExe$ = tools_folder$ + "spat5.hoa.decoder~"      + exeExt$
vsExe$      = tools_folder$ + "spat5.virtualspeakers~"  + exeExt$

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine:  "=== ambiX B-format to Binaural v1.8 — UNIQUE-BRIDGE 24-SPEAKER 3D BUILD ==="
appendInfoLine: "Platform:      ", platform$
appendInfoLine: "Source:        ", sourceName$
appendInfoLine: "Input:         ", numCh, " ch  (Ambisonic order ", order, ")  /  ",
    ... fixed$(duration, 3), " s  @  ", sr, " Hz  /  ", numSamples, " samples"
appendInfoLine: "Render mode:   ", modeArg$
appendInfoLine: "Decoder:       ", decoderShow$
appendInfoLine: "Layout:        ", layoutToken$, "   (expected speakers: ",
    ... if expectedSpk > 0 then string$(expectedSpk) else "auto" fi, ")"
if order = 3 and layout_preset = 1
    appendInfoLine: "Auto policy:   16-channel third order -> Spat5 built-in 22.2 full-sphere 24-speaker layout"
endif
appendInfoLine: "HRTF/SOFA:     ", sofa_file$, "   ITD=", fixed$(itd_percent, 1), "%"
appendInfoLine: "Room:          ", roomName$
appendInfoLine: "Tools:         ", tools_folder$
appendInfoLine: "Script folder: ", defaultDirectory$
appendInfoLine: "Bridge file:   spat_bformat_bridge.py (required)"
appendInfoLine: "Output:        in-memory Praat Sound only (no final WAV save)"
appendInfoLine: "Headroom:      -", fixed$(processing_headroom_dB, 1), " dB before Spat5; no gain restoration"
appendInfoLine: ""
if expectedSpk < numCh
    appendInfoLine: "WARNING: ", expectedSpk, " speaker feeds for order ", order,
        ... " (", numCh, " Ambisonic channels) is under-determined."
    appendInfoLine: "         The render will work, but higher-order/vertical detail may be reduced."
    appendInfoLine: ""
endif
appendInfoLine: "NOTE: the ", numCh, " input channels are Ambisonic components"
appendInfoLine: "      (W, Y, Z, X ...), NOT loudspeaker feeds. They will be"
appendInfoLine: "      HOA-decoded first and never re-encoded."
appendInfoLine: ""

# ============================================================
# GUARDS
# ============================================================
if not fileReadable(helper_py$)
    exitScript: "Python bridge not found next to this script:" + newline$ + helper_py$
endif
if not fileReadable(decoderExe$)
    exitScript: "spat5.hoa.decoder~ not found at:" + newline$ + decoderExe$
        ... + newline$ + "Check the Tools Folder in the form."
endif
if not fileReadable(vsExe$)
    exitScript: "spat5.virtualspeakers~ not found at:" + newline$ + vsExe$
        ... + newline$ + "Check the Tools Folder in the form."
endif

# SOFA: only checked if it looks like a path (token like "kemar" is skipped).
sofaLooksPath = index(sofa_file$, "/") > 0 or index(sofa_file$, "\") > 0
    ... or endsWith(sofa_file$, ".sofa")
if sofaLooksPath and not fileReadable(sofa_file$)
    exitScript: "SOFA file not found:" + newline$ + sofa_file$
endif

# Layout token: only checked if it looks like a file path.
# decoderToken$ is an OSC command list and is intentionally not path-checked.
layLooksPath = index(layoutToken$, "/") > 0 or index(layoutToken$, "\") > 0
if layLooksPath and not fileReadable(layoutToken$)
    exitScript: "Layout file not found:" + newline$ + layoutToken$
endif

# ============================================================
# EXPORT A HEADROOM-PROTECTED WORKING COPY
# ============================================================
# One shared gain factor is applied to every Ambisonic channel, so ACN/SN3D
# spatial relationships are unchanged. The gain is NOT restored later.
deleteFile: inputWav$
deleteFile: speakWav$
deleteFile: outputWav$
deleteFile: logTxt$

preGainFactor = 10 ^ (-processing_headroom_dB / 20)
selectObject: original
Copy: "__bformat_headroom_v1_8"
headroomObject = selected("Sound")
Multiply: preGainFactor
Save as 24-bit WAV file: inputWav$
removeObject: headroomObject
selectObject: original

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
# RUN THE TWO-STAGE BRIDGE  (decoder -> virtualspeakers)
# ============================================================
# runSubprocess launches without a shell, so paths with spaces are safe as
# single arguments (no manual quoting required).
if diagnostic_selftest
    appendInfoLine: "Running DIAGNOSTIC self-test (real render + extra checks)..."
else
    appendInfoLine: "Building matched decoder OSC preset and rendering binaural..."
endif

# nocheck: a non-zero exit from the bridge must NOT abort the script here —
# otherwise Praat shows its own terse error and the bridge's log (which holds
# the real reason: the exact Spat5 command and the tool's stderr) is never
# displayed. We continue and let the failure branch below read out the log.
nocheck runSubprocess: pythonCmd$, helper_py$,
    ... inputWav$, speakWav$, outputWav$, logTxt$,
    ... tools_folder$, decoderToken$, layoutToken$,
    ... sofa_file$, string$(itd_percent), roomName$,
    ... string$(expectedSpk), string$(order), modeArg$, scriptVersion$

# ============================================================
# IMPORT + VALIDATE + REPORT
# ============================================================
if fileReadable(outputWav$)
    # Read the temporary file, then create an independent in-memory Sound.
    # The file-backed object is removed before the temporary WAV is deleted.
    Read from file: outputWav$
    fileBackedResult = selected("Sound")
    fileBackedDuration = Get total duration
    # Extracting the full sample domain creates a fresh Sound object rather
    # than retaining the source WAV association shown by Praat's Info command.
    Extract part: 0, fileBackedDuration, "rectangular", 1, "no"
    result = selected("Sound")
    removeObject: fileBackedResult
    deleteFile: outputWav$
    if fileReadable(outputWav$)
        appendInfoLine: "WARNING: temporary binaural WAV could not be deleted: ", outputWav$
    endif
    selectObject: result

    outCh      = Get number of channels
    outSr      = Get sampling frequency
    outSamples = Get number of samples
    outDur     = Get total duration

    # ---- Validation flags ----
    validation$ = "PASS"
    valNote$    = ""

    # 1) exactly two channels
    if outCh <> 2
        validation$ = "FAIL"
        valNote$ = valNote$ + " [channels=" + string$(outCh) + " not 2]"
    endif
    # 2) sample rate identical to the input
    if outSr <> sr
        validation$ = "FAIL"
        valNote$ = valNote$ + " [sr " + string$(outSr) + "!=" + string$(sr) + "]"
    endif

    # ---- Peak / RMS (raw samples, no interpolation) ----
    selectObject: result
    mx = Get maximum: 0, 0, "None"
    mn = Get minimum: 0, 0, "None"
    if abs(mx) > abs(mn)
        outPeak = abs(mx)
    else
        outPeak = abs(mn)
    endif
    outRms = Get root-mean-square: 0, 0

    # 3) not entirely silent
    if outPeak < 1e-6
        validation$ = "FAIL"
        valNote$ = valNote$ + " [silent]"
    endif
    # 4) finite peak (guards against runaway values; bridge already blocks NaN/Inf)
    if outPeak > 1e6
        validation$ = "FAIL"
        valNote$ = valNote$ + " [peak not finite]"
    endif
    # 5) clipping check (soft — reported, not fatal)
    clip$ = "no"
    if outPeak >= 0.999
        clip$ = "YES"
    endif

    # ---- Convolution-tail accounting ----
    tailSamples = outSamples - numSamples
    if tailSamples > 0
        tail$ = "+" + string$(tailSamples) + " samples ("
            ... + fixed$(tailSamples / sr, 3) + " s) HRTF/room tail"
    elsif tailSamples = 0
        tail$ = "exact (no added tail)"
    else
        tail$ = string$(-tailSamples) + " samples shorter than input"
    endif

    # ---- Optional: trim tail to original duration ----
    trimmed = 0
    if tail_handling = 2 and tailSamples > 0
        selectObject: result
        Extract part: 0, duration, "rectangular", 1, "no"
        trimmedObj = selected("Sound")
        removeObject: result
        result = trimmedObj
        selectObject: result
        outSamples = Get number of samples
        outDur     = Get total duration
        mx = Get maximum: 0, 0, "None"
        mn = Get minimum: 0, 0, "None"
        if abs(mx) > abs(mn)
            outPeak = abs(mx)
        else
            outPeak = abs(mn)
        endif
        outRms = Get root-mean-square: 0, 0
        trimmed = 1
    endif

    # ---- No post gain and no normalisation ----
    # The processing headroom remains in the result so that clipping cannot be
    # hidden by a later attenuation or recreated by gain restoration.
    attenFactor = 1.0

    # ---- Silence-safe peak in dBFS (avoids log10(0)) ----
    if outPeak > 0
        peakDb = 20 * log10(outPeak)
    else
        peakDb = -999
    endif

    # ---- Name the in-memory result; do not save a final file ----
    selectObject: result
    Rename: resultName$

    # ============================================================
    # REPORT
    # ============================================================
    appendInfoLine: ""
    appendInfoLine: "=== RESULT ==="
    appendInfoLine: "Input object:      ", sourceName$
    appendInfoLine: "Ambisonic order:   ", order
    appendInfoLine: "Input channels:    ", numCh
    appendInfoLine: "Sample rate:       ", sr, " Hz"
    appendInfoLine: "Input samples:     ", numSamples
    appendInfoLine: "Input duration:    ", fixed$(duration, 3), " s"
    appendInfoLine: "Decoder preset:    ", decoderShow$
    appendInfoLine: "Virtual layout:    ", layoutToken$
    appendInfoLine: "SOFA / HRTF:       ", sofa_file$
    appendInfoLine: "Output channels:   ", outCh
    appendInfoLine: "Output samples:    ", outSamples
    appendInfoLine: "Output duration:   ", fixed$(outDur, 3), " s"
    appendInfoLine: "Duration/tail:     ", tail$
    if trimmed
        appendInfoLine: "                   (trimmed to input duration)"
    endif
    appendInfoLine: "Output peak:       ", fixed$(outPeak, 6),
        ... "  (", fixed$(peakDb, 1), " dBFS)"
    appendInfoLine: "Output RMS:        ", fixed$(outRms, 6)
    appendInfoLine: "Pre-Spat headroom: -", fixed$(processing_headroom_dB, 1), " dB (not restored)"
    appendInfoLine: "Post processing:   no gain, no normalisation"
    appendInfoLine: "Clipping:          ", clip$
    appendInfoLine: "Validation:        ", validation$, valNote$
    appendInfoLine: "Output storage:    Praat memory only"

    # ---- Fail hard on validation failure: do NOT report success ----
    if validation$ = "FAIL"
        appendInfoLine: ""
        appendInfoLine: "ERROR: output validation FAILED.", valNote$
        appendInfoLine: "Log contents:  ", logTxt$
        # Always show the log on failure (independent of the Show-log toggle).
        if fileReadable(logTxt$)
            appendInfoLine: ""
            appendInfoLine: "=== Spat5 log ==="
            appendInfoLine: readFile$(logTxt$)
        else
            appendInfoLine: "(Log file not found — the bridge exited before writing it.)"
        endif
        # The log has already been copied into the Info window. Remove all files.
        deleteFile: inputWav$
        deleteFile: speakWav$
        deleteFile: outputWav$
        deleteFile: logTxt$
        selectObject: result
        exitScript: "Binaural output failed validation. See the Info window and log."
    endif

    appendInfoLine: ""
    appendInfoLine: "Done. Binaural Sound: ", resultName$

    if show_log and fileReadable(logTxt$)
        appendInfoLine: ""
        appendInfoLine: "=== Spat5 log ==="
        appendInfoLine: readFile$(logTxt$)
    endif

    # ---- Always remove every temporary file on success ----
    deleteFile: inputWav$
    deleteFile: speakWav$
    deleteFile: outputWav$
    deleteFile: logTxt$
    if fileReadable(inputWav$) or fileReadable(speakWav$) or fileReadable(outputWav$) or fileReadable(logTxt$)
        appendInfoLine: "WARNING: at least one temporary file could not be deleted."
    else
        appendInfoLine: "Temporary files:   deleted"
    endif

    # ============================================================
    # VISUALIZATION
    # ============================================================
    if draw_visualization
        Erase all
        Select outer viewport: 0, 8, 0, 8

        # ---- Title ----
        Select outer viewport: 0, 8, 0, 0.65
        Axes: 0, 1, 0, 1
        Font size: 13
        Colour: "Black"
        Text: 0.5, "centre", 0.65, "half", "##ambiX B-format to Binaural##"
        Font size: 7
        Colour: "{0.35, 0.35, 0.52}"
        Text: 0.5, "centre", -0.25, "half",
            ... sourceName$
            ... + "  |  order " + string$(order) + " (" + string$(numCh) + " ch)"
            ... + " -> decode -> " + layoutToken$
            ... + " -> binaural"

        # ---- Input B-format: W component (ch1 / ACN0) ----
        Select outer viewport: 0, 8, 0.70, 2.00
        Select inner viewport: 0.6, 7.7, 0.78, 1.92
        selectObject: original
        Extract one channel: 1
        vizW = selected("Sound")
        Colour: "{0.55, 0.55, 0.55}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizW
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "W (ACN0)"
        Text top: "no", "Input B-format - W / omni component (ch 1 of " + string$(numCh) + ")"

        # ---- Output binaural (L blue, R orange) ----
        Select outer viewport: 0, 8, 2.05, 3.50
        Select inner viewport: 0.6, 7.7, 2.15, 3.42
        selectObject: result
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.20, 0.40, 0.80}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizL
        selectObject: result
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizR
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Binaural"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Binaural output  (blue = L ear,  orange = R ear)"

        # ---- Parameters panel ----
        Select outer viewport: 0, 8, 3.60, 4.80
        Select inner viewport: 0.6, 7.7, 3.68, 4.72
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.84, "half", "##Processing Parameters##"
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.62, "half",
            ... "Order " + string$(order) + "  |  decoder: " + decoderShow$
            ... + "  |  layout: " + layoutToken$
        Text: 0.05, "left", 0.40, "half",
            ... "SOFA: " + sofa_file$ + "  |  ITD: " + fixed$(itd_percent, 0)
            ... + "%  |  room: " + roomName$ + "  |  mode: " + modeArg$
        Text: 0.05, "left", 0.18, "half",
            ... "Tail: " + tail$
            ... + "  |  pre-headroom: -" + fixed$(processing_headroom_dB, 1) + " dB"
        Colour: "Black"
        Draw inner box

        # ---- Summary bar ----
        Select outer viewport: 0, 8, 4.90, 5.55
        Select inner viewport: 0.6, 7.7, 4.96, 5.49
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
        Font size: 7
        Colour: "Black"
        Text: 0.02, "left", 0.72, "half", "##" + resultName$ + "##"
        Font size: 6
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.02, "left", 0.28, "half",
            ... string$(numCh) + " ch B-format -> 2 ch binaural"
            ... + "  |  " + fixed$(outDur, 2) + " s"
            ... + "  |  peak " + fixed$(peakDb, 1) + " dBFS"
            ... + "  |  " + validation$
        Colour: "Black"
        Draw inner box

        Font size: 10
        Line width: 1
        Colour: "Black"
    endif

    # ============================================================
    # PLAY
    # ============================================================
    if open_result
        selectObject: result
        asynchronous Play
    endif

    selectObject: result

else
    # ============================================================
    # RENDER FAILED — preserve diagnostics, do not fake success
    # ============================================================
    appendInfoLine: ""
    appendInfoLine: "ERROR: binaural render failed (no output produced)."
    appendInfoLine: "Log contents:  ", logTxt$
    # Always show the log on failure (independent of the Show-log toggle).
    if fileReadable(logTxt$)
        appendInfoLine: ""
        appendInfoLine: "=== Spat5 log ==="
        appendInfoLine: readFile$(logTxt$)
    else
        appendInfoLine: "(Log file not found — the bridge could not start;"
        appendInfoLine: " check that Python ran and the Tools folder is correct.)"
    endif
    # The log has already been copied into the Info window; leave no files behind.
    deleteFile: inputWav$
    deleteFile: speakWav$
    deleteFile: outputWav$
    deleteFile: logTxt$
    exitScript: "Render failed. See the Info window. Temporary files were deleted."
endif
