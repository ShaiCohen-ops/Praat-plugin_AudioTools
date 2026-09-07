# ============================================================
# Praat AudioTools - AcousticDNAResonator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2.9 (2026)
#
# Changelog v0.2.9:
#   - New form field "Spectral dna" (0-1, default 0.4). The wet signal is the
#     source convolved with the resonator, so fitting the resonator to the
#     source's spectral shape applies that shape TWICE and the result is much
#     darker than the source. This controls how much of the source tilt the
#     resonator takes on. 1.0 = the v0.2.8 behaviour; 0 = spectrally flat
#     resonator whose DNA is purely its frequency-dependent decay times.
#
# Changelog v0.2.8:
#   - Info window cleaned up. The settings block was printed once before the
#     run and then largely repeated after it (preset, FDN size, epochs,
#     dry/wet, normalize, out channels), and the engine timings appeared
#     twice. Header 17 lines -> 2, completion block 22 lines -> 8, engine
#     path 5 lines -> 1, and the progress-file hint now appears only when
#     epochs >= 2000, since a normal run finishes in a few seconds.

#   - New form field "Early reflections (ms)", default 40, 0 = off. The engine
#     fades its FDN impulse response in over that window and hands the energy
#     the fade removes to a synthetic velvet-noise early pattern. This is the
#     early/late split: parametric early events, learned FDN late field.
#   - One field only; the pattern's density and decay live as engine defaults
#     rather than growing the form.
#
# Changelog v0.2.7:
#   - FIX: engine lookup order. acoustic_dna_resonator.py sitting next to this
#     script now takes precedence over the installed plugin_AudioTools/py/
#     copy. Previously the installed copy was checked first, so testing a new
#     .praat + .py pair from a separate folder silently kept using the OLD
#     installed engine - and nothing printed which file was loaded.
#   - The resolved engine path and its version are now printed at the top of
#     every run, with a loud warning on mismatch. The engine is searched for
#     in TWO locations (plugin py/ folder, then next to this script), so it
#     is easy to update one copy while Praat keeps loading the other.
#   - Stats parsing was quadratic: one full scan + full-remainder string copy
#     per indexed value, ~460 times over a 9 kB file. Replaced by a single
#     sequential pass. Measured on a real run: 0.02 s.
#   - Removed the "Praat export + Python engine total" stopwatch. Praat's
#     stopwatch is CPU time, so it reported 0 while blocked in runSubprocess.
#     The engine's own wall clock is reported instead.
#
# Changelog v0.2.6:
#   - Version-skew safety: if the Python engine rejects the new fast
#     "descriptor" loss (i.e. acoustic_dna_resonator.py is older than this
#     script), the run is retried automatically with "stft_decay" and a
#     NOTE explains what to update. Previously that mismatch killed the run
#     with an empty engine log, because argparse exits before the engine
#     opens its log file. The engine's own v0.2.6 also logs the mismatch.
#   - MUCH faster training. The backend now defaults to --loss descriptor:
#     it fits the per-band decay and spectral envelope directly from the
#     model parameters instead of rendering a full impulse response every
#     epoch. Measured on a 2 s stereo source, one CPU core:
#       default preset  (n=16, 2 s IR,  600 ep):  46.5 s -> 3.1 s   (15x)
#       long-tail preset(n=24, 6 s IR, 1000 ep): 114.1 s -> 5.5 s   (21x)
#     Training time is now independent of IR duration and nearly
#     independent of FDN size.
#   - Both QC figures improved on the same test, using the SAME estimators
#     as before: decay_match_log_mae 0.955 -> 0.829, spectral_match_mae
#     0.661 -> 0.511. Note that initial_loss / final_loss are a DIFFERENT
#     objective now and are not comparable to v0.2.5 numbers; the two
#     match errors are.
#   - To restore the old behaviour exactly, change "descriptor" back to
#     "stft_decay" in the runSubprocess --loss argument below. The old
#     training path is retained unchanged in the backend.
#
# Changelog v0.2.5:
#   - FIX: Python discovery was a single OS-based guess (bare "python" on
#     Windows) never verified until Stage 1, so it failed with a generic
#     "Python not found or dependencies missing" message on any machine
#     whose working venv wasn't on PATH - even with a perfectly good venv
#     elsewhere. Replaced with the same verified cascade used in
#     DDSPNeuralRevoicing.praat v0.6: a configured venv (pyCandidate1$)
#     tried first, then an OS-appropriate fallback list, with EACH
#     candidate actually probed for numpy/scipy/soundfile/torch before
#     being accepted. On failure the error now lists every path tried.
#
# Changelog v0.2.4:
#   - Faster backend: exact block-vectorized FDN render; lighter training FFT grids.
#   - Input waveform drawn in AudioTools blue instead of black.
#
# Changelog v0.2.3:
#   - Engine/model consistency pass: physical-Hz damping cutoffs now
#     remain the same between 8 kHz training and native-rate render.
#   - Native decay-band frequency mapping fixed; full-band spectral-DNA
#     matching added in the backend.
#   - Final IR uses exact time-domain FDN recursion (no long-tail FFT
#     time aliasing).
#   - Robust multichannel analysis reference avoids catastrophic
#     anti-phase cancellation; RMS normalization uses multichannel RMS.
#   - Post-peak decay estimation and stability-margin regularization now
#     preserve genuinely long decays instead of forcing -60 dB in 1.5 s.
#   - Backend interchange WAV is now 32-bit float, avoiding hidden PCM-16
#     clipping before Praat re-imports the processed Sound.
#   - Visualization/QC now compares input decay DNA with the exact trained
#     IR on the same bands and reports spectral/decay match errors.
#   - Short-input analysis fixed; final_loss now means best checkpoint.
#   - The old "loudness" menu item was only RMS normalization and has
#     been removed from the Praat form rather than mislabeled as LUFS.
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

# ---- Python interpreter candidates (verified cascade) ----
# v0.2.5: previously this picked ONE name per OS (bare "python" on Windows)
# and never checked it had numpy/scipy/soundfile/torch until Stage 1 - if
# that guess was wrong (e.g. your working venv isn't on PATH), the run
# failed with a generic "not found" message even on machines with a
# perfectly good venv elsewhere. Now mirrors DDSPNeuralRevoicing.praat's
# verified cascade: #1 is your known-good venv (edit THAT ONE LINE if yours
# lives elsewhere), then an OS-appropriate fallback list. EACH candidate is
# actually probed at Stage 1 - it must successfully import numpy, scipy,
# soundfile, and torch - before being accepted.
nPyCand = 1
pyCandidate1$ = "C:/Users/user/praat_ddsp_env/Scripts/python.exe"

if macintosh
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/opt/homebrew/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "/usr/local/bin/python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
elsif windows
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "py"
else
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python3"
    nPyCand = nPyCand + 1
    pyCandidate'nPyCand'$ = "python"
endif

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
installedPy$  = pluginDir$ + "py/acoustic_dna_resonator.py"
localPy$      = defaultDirectory$ + "/acoustic_dna_resonator.py"

# v0.2.7 FIX: a copy sitting NEXT TO THIS SCRIPT now wins over the installed
# plugin copy. The order used to be the other way round, which made
# side-by-side testing silently impossible: running a new .praat from a test
# folder with a matching new .py beside it still loaded the OLD engine from
# plugin_AudioTools/py/, because that path was checked first and existed.
# Nothing announced which file had been chosen, so the run just looked broken.
# Installed use is unaffected - when the plugin runs from plugin_AudioTools/
# there is no .py beside the .praat, so it falls through to py/ as before.
engineSource$ = ""
if fileReadable(localPy$)
    pythonScript$ = localPy$
    engineSource$ = "local copy beside this script"
elsif fileReadable(installedPy$)
    pythonScript$ = installedPy$
    engineSource$ = "installed plugin copy"
else
    pythonScript$ = installedPy$
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: acoustic_dna_resonator.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

# v0.2.7: report the engine file ACTUALLY loaded, and check its version.
# The engine is searched for in two places, so it is entirely possible to
# update one copy while Praat keeps loading the other. Reading the file's
# own version header costs nothing and catches that immediately - a
# subprocess probe would cost a whole Python startup.
engineExpected$ = "0.2.9"
engineText$ = readFile$(pythonScript$)
engineVersion$ = "unknown"
vPos = index(engineText$, "Version: ")
if vPos > 0
    vRest$ = mid$(engineText$, vPos + 9, 12)
    vSp = index(vRest$, " ")
    if vSp > 1
        engineVersion$ = left$(vRest$, vSp - 1)
    endif
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
form Acoustic DNA Resonator v0.2.9
    optionmenu Preset: 1
        option Custom
        option Bright shimmer chamber
        option Dark long decay
        option Subtle enhancement
    integer Fdn_size 16
    real Ir_duration 4.0
    integer Epochs 800
    real Dry_wet 0.35
    real Early_reflections_ms 40
    real Spectral_dna 0.4
    optionmenu Normalize_mode: 3
        option none
        option peak
        option rms
    optionmenu Out_channels: 1
        option match input
        option mono
        option stereo
        option 4 channels
        option 6 channels
        option 8 channels
    integer Seed 42
    boolean Export_textgrid_events_metadata 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESET APPLICATION ----
if preset = 2
    # Bright shimmer chamber - small FDN, short IR, more wet. The name is a
    # musical preset label; no artificial high-shelf tilt is imposed.
    fdn_size = 10
    ir_duration = 2.0
    epochs = 600
    dry_wet = 0.55
    presetName$ = "BrightShimmerChamber"
elsif preset = 3
    # Dark long decay - larger FDN, long IR, moderate wet mix. The long
    # chamber behavior is literal; tonal darkness still follows source DNA.
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

if early_reflections_ms < 0
    early_reflections_ms = 0
endif
if early_reflections_ms > 250
    early_reflections_ms = 250
endif

if spectral_dna < 0
    spectral_dna = 0
endif
if spectral_dna > 1
    spectral_dna = 1
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
else
    normModeStr$ = "rms"
endif

# ---- INFO ----
clearinfo
if early_reflections_ms > 0
    earlyStr$ = "early " + fixed$(early_reflections_ms, 0) + " ms"
else
    earlyStr$ = "early off"
endif
writeInfoLine:  "=== Acoustic DNA Resonator v0.2.9 ===  ", soundName$, "  [", presetName$, "]"
appendInfoLine: "FDN ", fdn_size, " | IR ", fixed$(ir_duration, 2), " s | ", epochs,
    ... " epochs | dry/wet ", fixed$(dry_wet, 2), " | ", earlyStr$,
    ... " | dna ", fixed$(spectral_dna, 2),
    ... " | ", normModeStr$, " | ", outModeStr$, " | seed ", seed

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

# v0.2.5: no-shell probe (runSystem shell quoting was fragile on Windows
# paths with spaces), now run against each candidate in turn until one
# actually has numpy/scipy/soundfile/torch, instead of trusting a single
# OS-based guess.
probeCode$ = "import numpy, scipy, soundfile, torch; open('" + probeMarkerJ$ + "', 'w').write('ok')"

pythonCmd$ = ""
pySource$  = ""
pyTried$   = ""

for iPyCand to nPyCand
    thisPyCand$ = pyCandidate'iPyCand'$
    pyTried$ = pyTried$ + "  - " + thisPyCand$ + newline$
    if pythonCmd$ = ""
        # Bare command names (python3 / python / py) can't be
        # fileReadable-checked, so only pre-filter absolute paths.
        isBarePyCmd = (thisPyCand$ = "python3") or (thisPyCand$ = "python") or (thisPyCand$ = "py")
        if isBarePyCmd or fileReadable(thisPyCand$)
            if fileReadable(probeMarker$)
                deleteFile: probeMarker$
            endif
            nocheck runSubprocess: thisPyCand$, "-c", probeCode$
            if fileReadable(probeMarker$)
                pythonCmd$ = thisPyCand$
                if iPyCand = 1
                    pySource$ = "configured venv"
                else
                    pySource$ = "auto-detected"
                endif
            endif
        endif
    endif
endfor

if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + newline$
        ... + "Tried:" + newline$ + pyTried$ + newline$
        ... + "Fix: point pyCandidate1$ (near the top of the PYTHON" + newline$
        ... + "interpreter candidates section) at a venv that has them, or" + newline$
        ... + "install into one of the paths above, e.g.:" + newline$
        ... + "  pip install numpy scipy soundfile torch"
endif

appendInfoLine: "  Python found: ", pythonCmd$, " (", pySource$, ")"

# ===========================================================================
# Stage 2 - Export Sound (+ optional TextGrid events)
# ===========================================================================
shadowStr$ = ""
if engineSource$ = "local copy beside this script" and fileReadable(installedPy$)
    shadowStr$ = " - shadows the installed plugin copy"
endif
appendInfoLine: "  Engine v", engineVersion$, ": ", pythonScript$, shadowStr$
if engineVersion$ <> engineExpected$
    appendInfoLine: ""
    appendInfoLine: "  *** ENGINE VERSION MISMATCH ***"
    appendInfoLine: "  This Praat script is v", engineExpected$, " but the engine above is v", engineVersion$, "."
    appendInfoLine: "  Replace THAT EXACT FILE - the path is printed above."
    appendInfoLine: "  Updating a copy in another folder will not take effect."
    appendInfoLine: "  Until then the run falls back to the slow legacy loss."
    appendInfoLine: ""
endif

appendInfoLine: "[2/5] Exporting temp files..."

# v0.2.2: export ALL channels. The old code extracted channel 1 only,
# silently discarding channels 2..N of multichannel inputs. The engine
# now analyzes/trains on the mixdown and, when output channels match
# input channels, excites each output channel with its OWN input
# channel through its own decorrelated tap.
selectObject: sound
Save as WAV file: tempInput$

haveEvents = 0
if export_textgrid_events_metadata and hasTextGrid
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
    appendInfoLine: "  TextGrid events exported as metadata (not a sonic control yet)."
else
    csvArg$ = "none"
endif

# ===========================================================================
# Stage 3 - Call Python
# ===========================================================================
appendInfoLine: "[3/5] Training + rendering (Praat is blocked until this returns)..."
if epochs >= 2000
    appendInfoLine: "  Live progress: ", tempProg$
endif

# Remove any stale output/stats from a PREVIOUS run before calling Python.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

# v0.2: no-shell call with separate arguments (house pattern); the old
# runSystem shell string broke on Windows paths containing spaces.
lossMode$ = "descriptor"
@callEngine: lossMode$

# Version-skew safety net. --loss descriptor exists only in engine v0.2.5+.
# An older engine rejects it in argparse and exits(2) BEFORE writing any log,
# so the failure is completely silent. If the fast path produced nothing,
# retry once on the loss every engine version understands rather than
# stopping the user's session.
if not fileReadable(tempOutput$)
    appendInfoLine: ""
    appendInfoLine: "  NOTE: the engine did not accept the fast 'descriptor' loss."
    appendInfoLine: "        Retrying with the legacy 'stft_decay' loss (slower)."
    appendInfoLine: "        If this succeeds, your acoustic_dna_resonator.py is"
    appendInfoLine: "        older than this Praat script - update it to v0.2.6."
    lossMode$ = "stft_decay"
    @callEngine: lossMode$
endif

procedure callEngine: .lossMode$
nocheck runSubprocess: pythonCmd$, pythonScript$,
    ... tempInput$, csvArg$, tempOutput$, tempStats$,
    ... "--fdn_size", string$(fdn_size),
    ... "--ir_duration", fixed$(ir_duration, 4),
    ... "--epochs", string$(epochs),
    ... "--loss", .lossMode$,
    ... "--excitation_mode", "self",
    ... "--delay_set", "prime",
    ... "--feedback_param", "householder",
    ... "--damping_mode", "shelf",
    ... "--dry_wet", fixed$(dry_wet, 4),
    ... "--early_ms", fixed$(early_reflections_ms, 2),
    ... "--spectral_dna", fixed$(spectral_dna, 3),
    ... "--normalize_mode", normModeStr$,
    ... "--out_channels", string$(outChannelsN),
    ... "--seed", string$(seed),
    ... "--device", "auto",
    ... "--log_file", tempLog$,
    ... "--progress_file", tempProg$,
    ... "--cleanup"
endproc

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
bestEpochStat$  = "?"
analysisMixStat$ = "?"
spectralMatchStat$ = "?"
decayMatchStat$ = "?"

nLossPts = 0
nModePts = 0
nBandPts = 0
analyzeSecStat$  = "?"
startupSecStat$  = "?"
totalSecStat$    = "?"
tDraw = 0
tParse = 0

tStage = stopwatch
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
    @parseStatLine: statsText$, "best_epoch="
    bestEpochStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_mix_mode="
    analysisMixStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "spectral_match_mae="
    spectralMatchStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "decay_match_log_mae="
    decayMatchStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "train_seconds="
    trainSecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "render_seconds="
    renderSecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "analyze_seconds="
    analyzeSecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "startup_seconds="
    startupSecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "total_seconds="
    totalSecStat$ = parseStatLine.result$

    @parseStatLine: statsText$, "n_loss_pts="
    if parseStatLine.result$ <> "?"
        nLossPts = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_modes_pts="
    if parseStatLine.result$ <> "?"
        nModePts = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "n_band_decay_pts="
    if parseStatLine.result$ <> "?"
        nBandPts = number(parseStatLine.result$)
    endif

    # v0.2.7 SPEED FIX. This used to call @parseStatLine once per indexed
    # entry: 400 loss points + 12 modes + 48 band rows = ~460 calls. Each call
    # does index() over the WHOLE stats text and then mid$() copies the entire
    # remainder into a new string. On a 9 kB / 493-line stats file that is
    # ~460 full scans and megabytes of string copying inside the interpreter -
    # quadratic in the number of points, and entirely invisible to the Python
    # timings. One sequential pass over the lines replaces all of it.
    for iB from 0 to nBandPts - 1
        bdModel_'iB'_ms = -1
    endfor

    statsStrings = Read Strings from raw text file: tempStats$
    nStatLines = Get number of strings
    for iLine to nStatLines
        line$ = Get string: iLine
        eqPos = index(line$, "=")
        if eqPos > 0
            key$ = left$(line$, eqPos - 1)
            val$ = mid$(line$, eqPos + 1, length(line$) - eqPos)
            # "model_band_" is tested via its own 5-char prefix "model",
            # which cannot collide with "band_" or "mode_".
            if left$(key$, 5) = "loss_"
                idx = number(mid$(key$, 6, length(key$) - 5))
                if idx >= 0 and idx < nLossPts
                    lp_'idx' = number(val$)
                endif
            elsif left$(key$, 5) = "mode_"
                idx = number(mid$(key$, 6, length(key$) - 5))
                if idx >= 0 and idx < nModePts
                    c1 = index(val$, ",")
                    mm_'idx'_freq = number(left$(val$, c1 - 1))
                endif
            elsif left$(key$, 11) = "model_band_"
                idx = number(mid$(key$, 12, length(key$) - 11))
                if idx >= 0 and idx < nBandPts
                    mc1 = index(val$, ",")
                    bdModel_'idx'_ms = number(mid$(val$, mc1 + 1, length(val$) - mc1))
                endif
            elsif left$(key$, 5) = "band_"
                idx = number(mid$(key$, 6, length(key$) - 5))
                if idx >= 0 and idx < nBandPts
                    c1 = index(val$, ",")
                    bd_'idx'_freq = number(left$(val$, c1 - 1))
                    bd_'idx'_ms   = number(mid$(val$, c1 + 1, length(val$) - c1))
                endif
            endif
        endif
    endfor
    removeObject: statsStrings

    # model_band_ rows are optional; fall back to the source value.
    for iB from 0 to nBandPts - 1
        if bdModel_'iB'_ms < 0
            bdModel_'iB'_ms = bd_'iB'_ms
        endif
    endfor
endif

tParse = stopwatch

# ===========================================================================
# Visualization
# ===========================================================================
tStage = stopwatch
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8
    Font size: 10

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "{0.2, 0.2, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Acoustic DNA Resonator v0.2.9 - " + soundName$
    Font size: 10
    Colour: "Black"

    # === Input waveform ===
    Select outer viewport: 0, 8, 0.7, 2.6
    Select inner viewport: 0.6, 7.7, 0.8, 2.5
    selectObject: sound
    Colour: "{0.2, 0.4, 0.75}"
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
    specMaxHz = sr / 2
    if specMaxHz > 20000
        specMaxHz = 20000
    endif
    selectObject: specSrc
    To Spectrogram: 0.03, specMaxHz, 0.002, 20, "Gaussian"
    specObj = selected("Spectrogram")
    Paint: 0, 0, 0, specMaxHz, 100, "yes", 50, 6, 0, "no"
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

    # === Band decay DNA: input vs exact trained IR ===
    Select outer viewport: 4, 8, 4.7, 6.6
    Select inner viewport: 4.7, 7.8, 4.9, 6.5
    if nBandPts > 0
        bMax = bd_0_ms
        if bdModel_0_ms > bMax
            bMax = bdModel_0_ms
        endif
        for iB from 1 to nBandPts - 1
            if bd_'iB'_ms > bMax
                bMax = bd_'iB'_ms
            endif
            if bdModel_'iB'_ms > bMax
                bMax = bdModel_'iB'_ms
            endif
        endfor
        if bMax < 1
            bMax = 1
        endif
        Axes: 0, nBandPts, 0, bMax * 1.16
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, nBandPts, 0, bMax * 1.16
        for iB from 0 to nBandPts - 1
            Paint rectangle: "{0.58, 0.42, 0.68}", iB + 0.08, iB + 0.47, 0, bd_'iB'_ms
            Paint rectangle: "{0.28, 0.50, 0.72}", iB + 0.53, iB + 0.92, 0, bdModel_'iB'_ms
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Decay (ms)"
        Text bottom: "yes", "Band index (low -> high Hz)"
        Text top: "no", "Decay DNA: input (purple) vs trained IR (blue)"
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
    Text: 0.02, "left", 0.74, "half", "FDN size: " + fdnSizeStat$ + " | Epochs: " + epochsStat$ + " | Best epoch: " + bestEpochStat$ + " | Loss: " + initialLoss$ + " -> " + finalLoss$
    Text: 0.02, "left", 0.58, "half", "Decay est.: " + decayEstMs$ + " ms | Spectral MAE: " + spectralMatchStat$ + " | Decay log-MAE: " + decayMatchStat$
    Text: 0.02, "left", 0.42, "half", "Duration: " + fixed$(dur, 2) + "s -> " + outDurStat$ + "s | Ch: " + outChanStat$ + " | Dry/wet: " + dryWetStat$ + " | Norm: " + normModeStat$
    Text: 0.02, "left", 0.26, "half", "RMS: " + rmsInputStat$ + " -> " + rmsOutputStat$ + " | Analysis: " + analysisMixStat$ + " | Delays: " + delayLengths$
    if warningStat$ <> "?" and warningStat$ <> "" and warningStat$ <> "none"
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.08, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif
tDraw = stopwatch

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ===  ", soundName$, "_dnares"
appendInfoLine: "Loss:      ", initialLoss$, " -> ", finalLoss$, "  (best epoch ", bestEpochStat$, " of ", epochsStat$, ")"
appendInfoLine: "Match:     decay log-MAE ", decayMatchStat$, " | spectral MAE ", spectralMatchStat$
appendInfoLine: "Output:    ", outDurStat$, " s | RMS ", rmsInputStat$, " -> ", rmsOutputStat$, " | decay est. ", decayEstMs$, " ms"
appendInfoLine: "Delays:    ", delayLengths$
appendInfoLine: "Analysis:  ", analysisMixStat$, " | loss ", lossMode$
appendInfoLine: "Time:      ", totalSecStat$, " s engine = ", startupSecStat$, " startup + ", analyzeSecStat$,
    ... " analyze + ", trainSecStat$, " train + ", renderSecStat$, " render"
appendInfoLine: "           Praat: ", fixed$(tParse, 2), " parse + ", fixed$(tDraw, 2), " draw"

if warningStat$ <> "?" and warningStat$ <> "" and warningStat$ <> "none"
    appendInfoLine: "WARNING:   ", warningStat$
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
