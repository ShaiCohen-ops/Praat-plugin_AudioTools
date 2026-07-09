# ============================================================
# Praat AudioTools - AcousticDNAResonator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2.2 (2026)
#
# Changelog v0.2.2:
#   - FIX: multichannel inputs were reduced to CHANNEL 1 ONLY at
#     export (channels 2..N silently discarded -- not even a
#     mixdown). The full file is now exported; the engine trains on
#     the mixdown and, when out channels == in channels, excites
#     each output channel with its own input channel through its own
#     decorrelated tap. All inputs processed, spatial image (wet and
#     dry) preserved.
#
# Changelog v0.2:
#   - THE FREEZE FIX (with engine v0.2). The Python engine's transfer
#     function now uses a Sherman-Morrison closed form instead of a
#     batched complex LU solve: the default run drops from ~4.5 min to
#     ~35 s, and the DarkLongDecay preset no longer allocates ~4 GB
#     (v0.1 was OOM-killed / swap-thrashed at that preset -- that WAS
#     the freeze). Identical model, verified to 1e-15.
#   - Subprocess calls switched from runSystem (shell, quote-fragile,
#     especially on Windows paths with spaces) to nocheck runSubprocess
#     with separate arguments -- the house no-shell pattern.
#   - showPyLog: Python mirrors all output (and any traceback) to a
#     log file; on failure Praat prints its tail instead of the old
#     blind "check terminal" message.
#   - Liveness: Python overwrites a progress file ("epoch=I/N loss=...")
#     throughout training; its path is printed before the call so a
#     long run can be watched from any text editor / tail.
#   - Per-stage timings (analyze/train/render) shown in the report.
#
# Changelog v0.1:
#   - Initial release. Implements the minimal-prototype scope from the
#     Acoustic DNA Resonator implementation plan: 8-32 line FDN,
#     Householder-parameterized orthogonal feedback matrix, one-pole shelf
#     damping filters, fixed prime delay lengths, stft_decay loss,
#     self-excitation only.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Acoustic DNA Resonator (Differentiable FDN)
#
#   Analyzes the selected Sound's spectral envelope, per-band decay rates,
#   and modal peaks - its "acoustic DNA" - then trains a small differentiable
#   Feedback Delay Network (PyTorch) whose impulse response approximates
#   those features. The same input sound is then passed through the trained
#   FDN as a self-derived resonator / spectral feedback chamber, dry/wet
#   mixed, and returned as a new (optionally multichannel) Sound.
#
#   Optionally, if a TextGrid is also selected, non-empty intervals on its
#   first tier are exported as analysis-window hints (events.csv) for the
#   Python backend; this is informational only in v0.1 (not yet used to
#   drive a time-varying target).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

hasTextGrid = 0
if numberOfSelected("TextGrid") = 1
    textgrid = selected("TextGrid")
    hasTextGrid = 1
endif

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/acoustic_dna_resonator.py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

tempInput$   = temporaryDirectory$ + "/temp_dnares_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_dnares_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_dnares_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_dnares_stats.txt"
tempLog$     = temporaryDirectory$ + "/temp_dnares_log.txt"
tempProg$    = temporaryDirectory$ + "/temp_dnares_progress.txt"
probeMarker$ = temporaryDirectory$ + "/temp_dnares_probe.ok"

probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(tempLog$)
        deleteFile: tempLog$
    endif
    if fileReadable(tempProg$)
        deleteFile: tempProg$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form Acoustic DNA Resonator v0.2.2
    optionmenu Preset: 1
        option Custom
        option Bright shimmer chamber
        option Dark long decay
        option Subtle enhancement
    integer Fdn_size 16
    real Ir_duration 4.0
    integer Epochs 800
    real Dry_wet 0.35
    optionmenu Normalize_mode: 3
        option none
        option peak
        option rms
        option loudness
    optionmenu Out_channels: 1
        option match input
        option mono
        option stereo
        option 4 channels
        option 6 channels
        option 8 channels
    integer Seed 42
    boolean Use_textgrid_events 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESET APPLICATION ----
if preset = 2
    # Bright shimmer chamber - small FDN, short IR, more wet, favors upper
    # partials because damping cutoffs have less time to close in
    fdn_size = 10
    ir_duration = 2.0
    epochs = 600
    dry_wet = 0.55
    presetName$ = "BrightShimmerChamber"
elsif preset = 3
    # Dark long decay - larger FDN, long IR, moderate wet mix
    fdn_size = 24
    ir_duration = 6.0
    epochs = 1000
    dry_wet = 0.45
    presetName$ = "DarkLongDecay"
elsif preset = 4
    # Subtle enhancement - light touch, mostly dry
    fdn_size = 12
    ir_duration = 2.5
    epochs = 500
    dry_wet = 0.18
    presetName$ = "SubtleEnhancement"
else
    presetName$ = "Custom"
endif

# ---- CLAMP VALUES ----
if fdn_size < 4
    fdn_size = 4
endif
if fdn_size > 32
    fdn_size = 32
endif
if ir_duration < 0.25
    ir_duration = 0.25
endif
if ir_duration > 15
    ir_duration = 15
endif
if epochs < 10
    epochs = 10
endif
if epochs > 5000
    epochs = 5000
endif
if dry_wet < 0
    dry_wet = 0
endif
if dry_wet > 1
    dry_wet = 1
endif

if out_channels = 2
    outModeStr$ = "mono"
elsif out_channels = 3
    outModeStr$ = "stereo"
elsif out_channels = 4
    outModeStr$ = "4 channels"
elsif out_channels = 5
    outModeStr$ = "6 channels"
elsif out_channels = 6
    outModeStr$ = "8 channels"
else
    outModeStr$ = "match input"
endif

if normalize_mode = 1
    normModeStr$ = "none"
elsif normalize_mode = 2
    normModeStr$ = "peak"
elsif normalize_mode = 3
    normModeStr$ = "rms"
else
    normModeStr$ = "loudness"
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Acoustic DNA Resonator v0.2.2 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "FDN size:     ", fdn_size
appendInfoLine: "IR duration:  ", fixed$(ir_duration, 2), " s"
appendInfoLine: "Epochs:       ", epochs
appendInfoLine: "Dry/wet:      ", fixed$(dry_wet, 2)
appendInfoLine: "Normalize:    ", normModeStr$
appendInfoLine: "Out channels: ", outModeStr$
appendInfoLine: "Seed:         ", seed
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

# v0.2.1: out_channels resolved from the menu. The old integer field
# silently defaulted to 2, so mono inputs always came back stereo
# ("match input" is now the default).
if out_channels = 2
    outChannelsN = 1
elsif out_channels = 3
    outChannelsN = 2
elsif out_channels = 4
    outChannelsN = 4
elsif out_channels = 5
    outChannelsN = 6
elsif out_channels = 6
    outChannelsN = 8
else
    # match input (engine supports up to 8 decorrelated taps)
    outChannelsN = nChannels
    if outChannelsN > 8
        outChannelsN = 8
    endif
endif

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels, " -> out: ", outChannelsN
if nChannels = outChannelsN and nChannels > 1
    appendInfoLine: "Per-channel excitation: each output channel processes its own input channel"
endif
appendInfoLine: ""

# ===========================================================================
# Stage 1 - Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

# v0.2: no-shell probe (runSystem shell quoting was fragile on Windows
# paths with spaces)
probeCode$ = "import numpy, scipy, soundfile, torch; open('" + probeMarkerJ$ + "', 'w').write('ok')"
nocheck runSubprocess: pythonCmd$, "-c", probeCode$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile torch"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 - Export Sound (+ optional TextGrid events)
# ===========================================================================
appendInfoLine: "[2/5] Exporting temp files..."

# v0.2.2: export ALL channels. The old code extracted channel 1 only,
# silently discarding channels 2..N of multichannel inputs. The engine
# now analyzes/trains on the mixdown and, when output channels match
# input channels, excites each output channel with its OWN input
# channel through its own decorrelated tap.
selectObject: sound
Save as WAV file: tempInput$

haveEvents = 0
if use_textgrid_events and hasTextGrid
    selectObject: textgrid
    nTiers = Get number of tiers
    if nTiers >= 1
        eventTable = Create Table with column names: "events", 0, "start_time end_time label"
        selectObject: textgrid
        isInterval = Is interval tier: 1
        if isInterval
            nInt = Get number of intervals: 1
            for iInt from 1 to nInt
                selectObject: textgrid
                lab$ = Get label of interval: 1, iInt
                if lab$ <> ""
                    t1 = Get start time of interval: 1, iInt
                    t2 = Get end time of interval: 1, iInt
                    selectObject: eventTable
                    Append row
                    r = Get number of rows
                    Set numeric value: r, "start_time", t1
                    Set numeric value: r, "end_time", t2
                    Set string value: r, "label", lab$
                endif
            endfor
        endif
        selectObject: eventTable
        nRows = Get number of rows
        if nRows > 0
            Save as comma-separated file: tempCSV$
            haveEvents = 1
        endif
        removeObject: eventTable
    endif
endif

if haveEvents
    csvArg$ = tempCSV$
    appendInfoLine: "  Events exported from TextGrid."
else
    csvArg$ = "none"
endif

# ===========================================================================
# Stage 3 - Call Python
# ===========================================================================
appendInfoLine: "[3/5] Training + rendering..."
appendInfoLine: "  Praat will be busy until the engine finishes."
appendInfoLine: "  Live progress is written to:"
appendInfoLine: "    ", tempProg$
appendInfoLine: "  (open it in any editor / tail it to watch epochs tick)"

# Remove any stale output/stats from a PREVIOUS run before calling Python.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

# v0.2: no-shell call with separate arguments (house pattern); the old
# runSystem shell string broke on Windows paths containing spaces.
nocheck runSubprocess: pythonCmd$, pythonScript$,
    ... tempInput$, csvArg$, tempOutput$, tempStats$,
    ... "--fdn_size", string$(fdn_size),
    ... "--ir_duration", fixed$(ir_duration, 4),
    ... "--epochs", string$(epochs),
    ... "--loss", "stft_decay",
    ... "--excitation_mode", "self",
    ... "--delay_set", "prime",
    ... "--feedback_param", "householder",
    ... "--damping_mode", "shelf",
    ... "--dry_wet", fixed$(dry_wet, 4),
    ... "--normalize_mode", normModeStr$,
    ... "--out_channels", string$(outChannelsN),
    ... "--seed", string$(seed),
    ... "--device", "auto",
    ... "--log_file", tempLog$,
    ... "--progress_file", tempProg$,
    ... "--cleanup"

if not fileReadable(tempOutput$)
    # showPyLog: surface the engine's own account of what went wrong
    if fileReadable(tempLog$)
        logText$ = readFile$(tempLog$)
        appendInfoLine: ""
        appendInfoLine: "--- Python engine log ---"
        appendInfoLine: logText$
        appendInfoLine: "-------------------------"
    endif
    @cleanUpTempFiles
    exitScript: "Python Acoustic DNA Resonator engine failed." + newline$ + "See the engine log above (Info window)."
endif

# ===========================================================================
# Stage 4 - Import Result
# ===========================================================================
appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_dnares"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================
fdnSizeStat$    = "?"
trainSecStat$   = "?"
renderSecStat$  = "?"
delayLengths$   = "?"
epochsStat$     = "?"
initialLoss$    = "?"
finalLoss$      = "?"
decayEstMs$     = "?"
warningStat$    = ""
excModeStat$    = "?"
dryWetStat$     = "?"
normModeStat$   = "?"
rmsInputStat$   = "?"
rmsOutputStat$  = "?"
outDurStat$     = "?"
outChanStat$    = "?"

nLossPts = 0
nModePts = 0
nBandPts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "fdn_size="
    fdnSizeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "delay_lengths="
    delayLengths$ = parseStatLine.result$
    @parseStatLine: statsText$, "epochs="
    epochsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "decay_estimate_ms="
    decayEstMs$ = parseStatLine.result$
    @parseStatLine: statsText$, "stability_warning="
    warningStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "excitation_mode="
    excModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "dry_wet="
    dryWetStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_input="
    rmsInputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_output="
    rmsOutputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "out_channels="
    outChanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "train_seconds="
    trainSecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "render_seconds="
    renderSecStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "n_loss_pts="
    if parseStatLine.result$ <> "?"
        nLossPts = number(parseStatLine.result$)
    endif
    for iL from 0 to nLossPts - 1
        @parseStatLine: statsText$, "loss_" + string$(iL) + "="
        lp_'iL' = number(parseStatLine.result$)
    endfor

    @parseStatLine: statsText$, "n_modes_pts="
    if parseStatLine.result$ <> "?"
        nModePts = number(parseStatLine.result$)
    endif
    for iM from 0 to nModePts - 1
        @parseStatLine: statsText$, "mode_" + string$(iM) + "="
        row$ = parseStatLine.result$
        c1 = index(row$, ",")
        mm_'iM'_freq = number(left$(row$, c1 - 1))
    endfor

    @parseStatLine: statsText$, "n_band_decay_pts="
    if parseStatLine.result$ <> "?"
        nBandPts = number(parseStatLine.result$)
    endif
    for iB from 0 to nBandPts - 1
        @parseStatLine: statsText$, "band_" + string$(iB) + "="
        row$ = parseStatLine.result$
        c1 = index(row$, ",")
        bd_'iB'_freq = number(left$(row$, c1 - 1))
        bd_'iB'_ms   = number(mid$(row$, c1 + 1, length(row$) - c1))
    endfor
endif

# ===========================================================================
# Visualization
# ===========================================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Font size: 10

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "{0.2, 0.2, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Acoustic DNA Resonator v0.2.2 - " + soundName$
    Font size: 10
    Colour: "Black"

    # === Input waveform ===
    Select outer viewport: 0, 8, 0.7, 2.6
    Select inner viewport: 0.6, 7.7, 0.8, 2.5
    selectObject: sound
    Draw: 0, 0, 0, 0, "no", "curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Input waveform"
    Text bottom: "yes", "Time (s)"

    # === Output spectrogram ===
    Select outer viewport: 0, 8, 2.7, 4.6
    Select inner viewport: 0.6, 7.7, 2.8, 4.5
    selectObject: resultSound
    outNChan = Get number of channels
    if outNChan > 1
        Extract one channel: 1
        specSrc = selected("Sound")
    else
        Copy: "dnaresSpecSrc"
        specSrc = selected("Sound")
    endif
    selectObject: specSrc
    To Spectrogram: 0.03, 8000, 0.002, 20, "Gaussian"
    specObj = selected("Spectrogram")
    Paint: 0, 0, 0, 8000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Rendered output spectrogram (ch. 1)"
    removeObject: specObj, specSrc

    # === Loss curve panel ===
    Select outer viewport: 0, 4, 4.7, 6.6
    Select inner viewport: 0.7, 3.8, 4.9, 6.5
    if nLossPts > 1
        lMin = lp_0
        lMax = lp_0
        for iL from 1 to nLossPts - 1
            if lp_'iL' < lMin
                lMin = lp_'iL'
            endif
            if lp_'iL' > lMax
                lMax = lp_'iL'
            endif
        endfor
        lRange = lMax - lMin
        if lRange < 1e-6
            lRange = 1
        endif
        Axes: 0, nLossPts - 1, lMin - lRange * 0.08, lMax + lRange * 0.08
        Colour: "{0.75, 0.75, 0.85}"
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, nLossPts - 1, lMin - lRange * 0.08, lMax + lRange * 0.08
        Colour: "{0.2, 0.4, 0.75}"
        Line width: 2
        for iL from 1 to nLossPts - 1
            iPrev = iL - 1
            Draw line: iPrev, lp_'iPrev', iL, lp_'iL'
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Loss"
        Text bottom: "yes", "Epoch (sampled)"
        Text top: "no", "Training loss"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(loss curve not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Band decay bar chart ===
    Select outer viewport: 4, 8, 4.7, 6.6
    Select inner viewport: 4.7, 7.8, 4.9, 6.5
    if nBandPts > 0
        bMax = bd_0_ms
        for iB from 1 to nBandPts - 1
            if bd_'iB'_ms > bMax
                bMax = bd_'iB'_ms
            endif
        endfor
        if bMax < 1
            bMax = 1
        endif
        Axes: 0, nBandPts, 0, bMax * 1.1
        Colour: "{0.97, 0.97, 0.99}"
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, nBandPts, 0, bMax * 1.1
        Colour: "{0.55, 0.35, 0.65}"
        for iB from 0 to nBandPts - 1
            Paint rectangle: "{0.55, 0.35, 0.65}", iB + 0.1, iB + 0.9, 0, bd_'iB'_ms
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Decay (ms)"
        Text bottom: "yes", "Band index (low -> high Hz)"
        Text top: "no", "Per-band decay estimate"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(band decay data not available)"
        Colour: "Black"
        Draw rectangle: 0, 1, 0, 1
    endif

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.7, 8.0
    Select inner viewport: 0.6, 7.7, 6.8, 7.9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.74, "half", "FDN size: " + fdnSizeStat$ + " | Epochs: " + epochsStat$ + " | Loss: " + initialLoss$ + " -> " + finalLoss$
    Text: 0.02, "left", 0.58, "half", "Decay estimate: " + decayEstMs$ + " ms | Excitation: " + excModeStat$ + " | Dry/wet: " + dryWetStat$
    Text: 0.02, "left", 0.42, "half", "Duration: " + fixed$(dur, 2) + "s -> " + outDurStat$ + "s | Channels: " + outChanStat$ + " | Normalize: " + normModeStat$
    Text: 0.02, "left", 0.26, "half", "RMS: " + rmsInputStat$ + " -> " + rmsOutputStat$ + " | Delays (samples): " + delayLengths$
    if warningStat$ <> "?" and warningStat$ <> "" and warningStat$ <> "none"
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.08, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_dnares"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "FDN size:      ", fdnSizeStat$
appendInfoLine: "Delays (smp):  ", delayLengths$
appendInfoLine: "Epochs:        ", epochsStat$
appendInfoLine: "Loss:          ", initialLoss$, " -> ", finalLoss$
appendInfoLine: "Decay est.:    ", decayEstMs$, " ms"
appendInfoLine: "Excitation:    ", excModeStat$
appendInfoLine: "Dry/wet:       ", dryWetStat$
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "Channels out:  ", outChanStat$
appendInfoLine: "Normalize:     ", normModeStat$
appendInfoLine: "RMS input:     ", rmsInputStat$
appendInfoLine: "RMS output:    ", rmsOutputStat$
appendInfoLine: "Engine time:   train ", trainSecStat$, " s | render ", renderSecStat$, " s"

if warningStat$ <> "?" and warningStat$ <> "" and warningStat$ <> "none"
    appendInfoLine: "WARNING:       ", warningStat$
endif

selectObject: resultSound
if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
