# ============================================================
# Praat AudioTools - SpectralPermute.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.2 (2026)
#
# Description:
#   Spectral Permutation.
#
#   Slices a user-defined time region of the selected Sound in the
#   short-time Fourier domain and permutes it along a chosen axis, then
#   resynthesises. The result - just that permuted region - is returned
#   to Praat's Object List as one or more new Sounds.
#
#   Permutation axes:
#   - time        Global time-block permutation. This is the v1 behaviour.
#                 A contiguous run of STFT columns overlap-adds back to its
#                 original time segment, so this axis is mathematically a
#                 time-domain splice with Hann crossfades. Kept because it
#                 is musically useful, and as a reference point.
#   - band_time   The bin axis is split into Num_bands bands and EACH BAND
#                 GETS ITS OWN PERMUTATION of the time blocks. The time
#                 axis is unglued across frequency: the low band may be
#                 playing block 3 while the high band plays block 1. Not
#                 reachable by any time-domain rearrangement of the source.
#   - freq        Permutation along the FREQUENCY axis, time held fixed.
#                 Band contents are transplanted between bands; the source
#                 magnitude envelope is resampled onto the destination's bin
#                 grid and the destination's own phase is kept, which
#                 preserves temporal coherence.
#   - time_freq   Both axes at once.
#   - mag_phase   Magnitude blocks are permuted while phase runs
#                 continuously in its original order. No seams at all.
#
#   Decorrelation (0-1) is the probability that a band receives its own
#   order rather than the shared one. At 0, band_time collapses to time
#   (verified bit-identical with Phase_mode off); at 1 every band is
#   independent.
#
#   Num_variants renders that many differently-seeded results in a single
#   Python process, so a permutation idea can be auditioned as a set.
#
# Changelog v2.0:
#   - NEW: band_time, freq, time_freq and mag_phase axes. v1 only did
#     time-block permutation, which despite the name never touched the
#     frequency axis.
#   - FIXED: v1 analysed with boundary="zeros", which put analysis-window
#     ramp frames at the head and tail of the region. Permuting the first
#     or last block into the interior dragged its fade-to-zero along.
#     Measured on a steady 440 Hz tone, where a block permutation should be
#     inaudible: v1 envelope minimum 0.0522 against a 0.40 peak (about
#     -18 dB of dropout); v2 gives 0.3854 against a source figure of 0.3999.
#     v2 analyses a context-extended segment and permutes only frames whose
#     whole window support lies inside the region.
#   - FIXED: the v1 "phase realignment" applied one constant angle to every
#     bin, which is not a time alignment (a time offset is linear phase, not
#     constant phase). Measured with and without it: envelope minima 0.3844
#     vs 0.3854, i.e. no effect, while the report claimed N seams corrected.
#     Replaced by Phase_mode: off, or lock (per-bin phase continuation with
#     identity phase locking around spectral peaks). Measured on
#     harmonically rich material, lock raises the seam envelope minimum from
#     0.1567 to 0.2294 against a source figure of 0.2252, and drops the
#     maximum sample step from 0.984 to 0.746. On a steady sine it makes no
#     difference, because overlap-add already handles that case.
#   - FIXED: Hop_size fallback was fft_size / 4, a REAL in Praat. The old
#     default Window_ms 46.4 at 44.1 kHz gave fft_size 2046, so the fallback
#     produced 511.5 and argparse raised on "511.5". Window sizes are now
#     snapped to a power of two (2046 also factors as 2*3*11*31, a poor FFT
#     length), and the fallback uses floor().
#   - FIXED: Custom_order was a `word` field, so "3, 1, 4, 2" with spaces was
#     truncated at the first space and the token check then reported a
#     confusing count mismatch. It is now a `sentence`, whitespace is
#     stripped, and the value is quoted on the command line.
#   - FIXED: temp WAV was written with `Save as WAV file` (16-bit), so the
#     input was quantised on the way in while the output was 32-bit float.
#     Now `Save as 32-bit WAV file`.
#   - The applied permutation never reached Praat in v1: Python wrote it to
#     stats and printed it to a terminal nobody sees, and the front end
#     parsed only phase_realignments and warning. Both the master order and
#     the per-band orders are now parsed and reported, so a result you like
#     can be reproduced.
#   - The reported seam figure is now a MEASURED metric (maximum
#     sample-to-sample step, input and output) rather than a count of
#     corrections applied. The v1 counter used a threshold of 1e-3 radians,
#     which fired on essentially every seam, so it always read
#     Num_segments - 1.
#   - Blocks are now equal length. v1 gave remainder frames to the earliest
#     blocks, so a permuted block landed at a shifted time. Leftover frames
#     stay in place as a tail and are reported.
#   - NEW: Draw_visualization panel - region spectrogram before and after
#     with the band grid, plus a bands-by-blocks permutation map.
#   - Praat 7.0: writing the temp WAV is trust-gated, so askForTrust() is
#     requested on 7.0 and above.
#
# Changelog v2.1:
#   - NEW: Preset field with six presets plus Custom. Each preset sets EVERY
#     parameter that determines the sound, Window_ms and Seed included.
#     Partial coverage is the Multiband_Distortion v0.4 defect, where a
#     preset that left some fields alone inherited the previous run's values
#     and gave a different result each time. Custom sets nothing, so every
#     field stays live - the missing-Custom-option defect from
#     Adaptive_Wave_Shaper and Timbral_Similarity_Browser.
#   - FIXED: Num_blocks was a near-dead control on the freq axis. Time is
#     held fixed there, so the block grid only decided how many frames fell
#     into the untouched tail. The engine now uses the whole interior frame
#     range on freq; verified bit-identical output at Num_blocks 2, 6 and 32.
#     The form and the report both say the control is unused on that axis.
#   - FIXED: custom_order was silently substituted on freq and time_freq. A
#     custom order carries num_blocks entries while the band permutation
#     needs num_bands, so the engine fell back to random_shuffle without
#     saying so and the report displayed a band order that had never been
#     asked for - the same silent-substitution class as the MFCC
#     argument-order bug. There is now a separate Custom_band_order field,
#     validated against num_bands, and the engine errors out rather than
#     substituting. Each order is required only on the axes that use it.
#   - Panel C now labels its cells per axis: source BLOCK on the time-bearing
#     axes, source BAND on freq, where there are no time blocks to show.
#
# Changelog v2.2:
#   - The v2.1 form rendered about 31 rows and did not fit on a laptop
#     screen. The main form is now 9 rows: region, preset, variants, show
#     advanced, draw, play. The thirteen detail parameters moved into a
#     beginPause dialog that opens PRE-FILLED with whatever the preset just
#     set, so a preset stays inspectable and the fields are never dead.
#   - Preset changed from `choice` to `optionmenu`: a choice renders one
#     radio row per option, so seven presets cost eight rows on their own.
#   - Choosing Custom forces the advanced dialog open. Custom starts from the
#     Band shuffle values, and without the dialog those would be a hidden set
#     of defaults masquerading as a user choice.
#   - The advanced dialog needs Praat 6.3 or newer, because `optionmenu:`
#     inside beginPause does not exist before then. The version is checked up
#     front with a clear message instead of aborting mid-dialog.
#   - SCRIPTABILITY NOTE: under `runScript` and `praat --run` a beginPause
#     block auto-continues with its pre-filled defaults, so automated callers
#     drive this script through the Preset menu, not the detail parameters.
#     The Info report prints every value actually used, so what a run did is
#     always recoverable from its output.
#   - Measured on 6.4.06 headless while building this: an auto-continued
#     beginPause block creates NO variables, for any field type, so reading
#     one afterwards raises "Unknown variable". Every field name in the
#     dialog is therefore pre-initialised from the preset beforehand.
#
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected ("Sound")
soundName$ = selected$ ("Sound")

# ---- PRAAT 7.0 TRUST GATE ----
# Saving the temp WAV and deleting temp files are both trust-gated from 7.0.
# askForTrust() is inert on 6.x, so guard the call by version.
if praatVersion >= 7000
    trustGranted = askForTrust ()
endif

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable ("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable ("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable ("/usr/local/bin/python3")
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
pythonScript$ = pluginDir$ + "py/spectral_permute.py"

if not fileReadable (pythonScript$)
    pythonScript$ = defaultDirectory$ + "/spectral_permute.py"
endif

if not fileReadable (pythonScript$)
    exitScript: "Cannot find Python script: spectral_permute.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_specperm_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_specperm_output.wav"
tempBase$    = temporaryDirectory$ + "/temp_specperm_output"
tempStats$   = temporaryDirectory$ + "/temp_specperm_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_specperm_probe.ok"

probeMarkerJ$ = replace_regex$ (probeMarker$, "\\", "/", 0)

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur       = Get total duration
tmin      = Get start time
sr        = Get sampling frequency
nChannels = Get number of channels

# ---- FORM ----
form Spectral Permutation v2.2
    comment ── Region (seconds; End = 0 means "to end") ──
    real Start_time 0.0
    real End_time 0.0
    optionmenu Preset: 1
        option Band shuffle
        option Gentle drift
        option Spectral smear
        option Timbre transplant
        option Phase mosaic
        option Retrograde (reference)
        option Custom
    integer Num_variants 1
    boolean Show_advanced 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
# Every preset sets EVERY parameter that determines the sound. Partial
# coverage is the Multiband_Distortion v0.4 defect: a preset that leaves
# some fields alone inherits whatever the last run left in them, so the same
# preset gives a different result run to run. That includes Window_ms and
# Seed - "it depends on the source" is a reason to open the advanced dialog,
# not a reason to leave a gap.
#
# Custom starts from the Band shuffle values and forces the advanced dialog
# open, so it is never a hidden set of defaults.
presetApplied = 1
if preset = 1
    # Band shuffle - the reference spectral permutation
    axis$ = "band_time"
    num_blocks = 6
    num_bands = 12
    spacing$ = "bark"
    decorrelation = 1.0
    kind$ = "random_shuffle"
    seed = 42
    window_ms = 46.4
    hop_size = 512
    phase$ = "lock"
    edge_fade_ms = 15.0
elsif preset = 2
    # Gentle drift - long window, few blocks, partial decorrelation
    axis$ = "band_time"
    num_blocks = 4
    num_bands = 8
    spacing$ = "erb"
    decorrelation = 0.4
    kind$ = "rotate"
    seed = 42
    window_ms = 92.9
    hop_size = 1024
    phase$ = "lock"
    edge_fade_ms = 15.0
elsif preset = 3
    # Spectral smear - many small blocks, many bands, fully decorrelated
    axis$ = "band_time"
    num_blocks = 12
    num_bands = 24
    spacing$ = "erb"
    decorrelation = 1.0
    kind$ = "random_shuffle"
    seed = 42
    window_ms = 46.4
    hop_size = 256
    phase$ = "lock"
    edge_fade_ms = 15.0
elsif preset = 4
    # Timbre transplant - frequency axis, time untouched
    axis$ = "freq"
    num_blocks = 2
    num_bands = 8
    spacing$ = "log"
    decorrelation = 0
    kind$ = "reverse"
    seed = 42
    window_ms = 46.4
    hop_size = 512
    phase$ = "off"
    edge_fade_ms = 15.0
elsif preset = 5
    # Phase mosaic - magnitude rearranged onto the original phase trajectory
    axis$ = "mag_phase"
    num_blocks = 8
    num_bands = 12
    spacing$ = "bark"
    decorrelation = 1.0
    kind$ = "random_shuffle"
    seed = 42
    window_ms = 46.4
    hop_size = 512
    phase$ = "off"
    edge_fade_ms = 15.0
elsif preset = 6
    # Retrograde - the time axis, kept as an audible reference point for
    # what the spectral axes are being compared against
    axis$ = "time"
    num_blocks = 4
    num_bands = 1
    spacing$ = "bark"
    decorrelation = 0
    kind$ = "reverse"
    seed = 42
    window_ms = 46.4
    hop_size = 512
    phase$ = "lock"
    edge_fade_ms = 15.0
else
    # Custom - start from Band shuffle and hand every field to the user
    presetApplied = 0
    axis$ = "band_time"
    num_blocks = 6
    num_bands = 12
    spacing$ = "bark"
    decorrelation = 1.0
    kind$ = "random_shuffle"
    seed = 42
    window_ms = 46.4
    hop_size = 512
    phase$ = "lock"
    edge_fade_ms = 15.0
    show_advanced = 1
endif

custom_order$ = "1,2,3,4"
custom_band_order$ = "1,2,3,4"

if preset = 1
    presetName$ = "Band shuffle"
elsif preset = 2
    presetName$ = "Gentle drift"
elsif preset = 3
    presetName$ = "Spectral smear"
elsif preset = 4
    presetName$ = "Timbre transplant"
elsif preset = 5
    presetName$ = "Phase mosaic"
elsif preset = 6
    presetName$ = "Retrograde (reference)"
else
    presetName$ = "Custom"
endif

# ---- STRINGS -> MENU INDICES, so the advanced dialog opens pre-filled ----
axisIdx = 2
if axis$ = "time"
    axisIdx = 1
elsif axis$ = "band_time"
    axisIdx = 2
elsif axis$ = "freq"
    axisIdx = 3
elsif axis$ = "time_freq"
    axisIdx = 4
else
    axisIdx = 5
endif

spacingIdx = 4
if spacing$ = "linear"
    spacingIdx = 1
elsif spacing$ = "log"
    spacingIdx = 2
elsif spacing$ = "mel"
    spacingIdx = 3
elsif spacing$ = "bark"
    spacingIdx = 4
else
    spacingIdx = 5
endif

kindIdx = 3
if kind$ = "reverse"
    kindIdx = 1
elsif kind$ = "rotate"
    kindIdx = 2
elsif kind$ = "random_shuffle"
    kindIdx = 3
else
    kindIdx = 4
endif

phaseIdx = 2
if phase$ = "off"
    phaseIdx = 1
else
    phaseIdx = 2
endif

# ---- ADVANCED DIALOG ----
# Kept out of the main form so the form fits on a laptop screen. It opens
# pre-filled with whatever the preset just set, so the preset stays
# inspectable rather than being a black box.
#
# `optionmenu:` inside beginPause does not exist before Praat 6.3 (it fails
# with "Unknown function «optionmenu» in formula"), so guard the version
# rather than letting it abort mid-dialog.
#
# TRAP, measured on 6.4.06 headless: under `praat --run` the pause block
# auto-continues, but it creates NO variables - not even for `integer:` or
# `real:` fields. Reading one afterwards gives "Unknown variable". So every
# field name used here must ALREADY hold the preset's value before
# beginPause, and the dialog then overwrites it only when a GUI is present.
# The preset block above covers the numeric and string fields; these four
# carry the menu indices under the names the dialog will use.
axis = axisIdx
band_spacing = spacingIdx
ordering = kindIdx
phase_mode = phaseIdx
if show_advanced and praatVersion < 6300
    exitScript: "The advanced dialog needs Praat 6.3 or newer (this is "
        ... + praatVersion$ + ")." + newline$
        ... + "Choose a preset instead, or untick Show advanced."
endif

if show_advanced
    beginPause: "Spectral Permutation - advanced"
        comment: "Axis: time / band_time / freq / time_freq / mag_phase"
        optionmenu: "Axis", axisIdx
            option: "time"
            option: "band_time"
            option: "freq"
            option: "time_freq"
            option: "mag_phase"
        integer: "Num_blocks", string$ (num_blocks)
        integer: "Num_bands", string$ (num_bands)
        optionmenu: "Band_spacing", spacingIdx
            option: "linear"
            option: "log"
            option: "mel"
            option: "bark"
            option: "erb"
        real: "Decorrelation", fixed$ (decorrelation, 2)
        comment: "Ordering within each band"
        optionmenu: "Ordering", kindIdx
            option: "reverse"
            option: "rotate"
            option: "random_shuffle"
            option: "custom_order"
        sentence: "Custom_order", custom_order$
        sentence: "Custom_band_order", custom_band_order$
        integer: "Seed", string$ (seed)
        comment: "STFT"
        real: "Window_ms", fixed$ (window_ms, 2)
        integer: "Hop_size", string$ (hop_size)
        optionmenu: "Phase_mode", phaseIdx
            option: "off"
            option: "lock"
        real: "Edge_fade_ms", fixed$ (edge_fade_ms, 1)
    endPause: "Continue", 1
    axisIdx = axis
    spacingIdx = band_spacing
    kindIdx = ordering
    phaseIdx = phase_mode
endif

# ---- MENU INDICES -> STRINGS ----
if axisIdx = 1
    axis$ = "time"
elsif axisIdx = 2
    axis$ = "band_time"
elsif axisIdx = 3
    axis$ = "freq"
elsif axisIdx = 4
    axis$ = "time_freq"
else
    axis$ = "mag_phase"
endif

if spacingIdx = 1
    spacing$ = "linear"
elsif spacingIdx = 2
    spacing$ = "log"
elsif spacingIdx = 3
    spacing$ = "mel"
elsif spacingIdx = 4
    spacing$ = "bark"
else
    spacing$ = "erb"
endif

if kindIdx = 1
    kind$ = "reverse"
elsif kindIdx = 2
    kind$ = "rotate"
elsif kindIdx = 3
    kind$ = "random_shuffle"
else
    kind$ = "custom_order"
endif

if phaseIdx = 1
    phase$ = "off"
else
    phase$ = "lock"
endif

# ---- WINDOW SIZE: ms -> SAMPLES, SNAPPED TO A POWER OF TWO ----
# A raw ms-to-samples conversion gives arbitrary lengths: 46.4 ms at
# 44.1 kHz is 2046 = 2*3*11*31, a bad FFT length, and 2046/4 is not an
# integer so the hop fallback produced a non-integer argument.
if window_ms <= 0
    window_ms = 1
endif
requestedWindowMs = window_ms
rawFft = window_ms / 1000 * sr
fftPow = round (log2 (rawFft))
if fftPow < 8
    fftPow = 8
endif
if fftPow > 14
    fftPow = 14
endif
fftSize = 2 ^ fftPow
effectiveWindowMs = fftSize / sr * 1000

# ---- CLAMP / VALIDATE ----
if num_blocks < 2
    num_blocks = 2
endif
if num_blocks > 64
    num_blocks = 64
endif
if num_bands < 1
    num_bands = 1
endif
if num_bands > 64
    num_bands = 64
endif
if axis$ = "time"
    num_bands = 1
endif
if (axis$ = "freq" or axis$ = "time_freq") and num_bands < 2
    num_bands = 2
endif
if decorrelation < 0
    decorrelation = 0
endif
if decorrelation > 1
    decorrelation = 1
endif
if axis$ = "time"
    decorrelation = 0
endif
if hop_size < 32
    hop_size = 32
endif
if hop_size >= fftSize
    hop_size = floor (fftSize / 4)
endif
if edge_fade_ms < 0
    edge_fade_ms = 0
endif
if edge_fade_ms > 200
    edge_fade_ms = 200
endif
if num_variants < 1
    num_variants = 1
endif
if num_variants > 16
    num_variants = 16
endif
if seed < 0
    seed = 0
endif

# Region is given relative to the sound's own start time.
if start_time < 0
    start_time = 0
endif
if end_time <= 0 or end_time > dur
    end_time = dur
endif
if start_time >= end_time
    exitScript: "Start_time must be less than End_time (and End_time must be within the sound's duration)."
endif

# ---- CUSTOM ORDER: strip whitespace, then validate ----
custom_order$ = replace$ (custom_order$, " ", "", 0)
custom_order$ = replace$ (custom_order$, tab$, "", 0)
if custom_order$ = ""
    custom_order$ = "1"
endif
if custom_band_order$ = ""
    custom_band_order$ = "1"
endif

custom_band_order$ = replace$ (custom_band_order$, " ", "", 0)
custom_band_order$ = replace$ (custom_band_order$, tab$, "", 0)

# The TIME order is unused on the freq axis (time is held fixed there), and
# the BAND order only exists on freq / time_freq. v2.0 demanded the time
# order everywhere and then silently substituted a random band order,
# because a custom order has num_blocks entries while the band permutation
# needs num_bands - so the report showed a band order that was never asked
# for. Each is now validated only where it is actually used.
needTimeOrder = 0
needBandOrder = 0
if kind$ = "custom_order"
    if axis$ <> "freq"
        needTimeOrder = 1
    endif
    if axis$ = "freq" or axis$ = "time_freq"
        needBandOrder = 1
    endif
endif

if needTimeOrder
    tokStrings = Create Strings from tokens: "customOrderTokens", custom_order$, ","
    nTok = Get number of strings
    removeObject: tokStrings
    if nTok <> num_blocks
        exitScript: "Custom_order must list exactly " + string$ (num_blocks)
            ... + " comma-separated 1-based block indices (got " + string$ (nTok)
            ... + ": " + custom_order$ + ")."
    endif
endif

if needBandOrder
    tokStrings2 = Create Strings from tokens: "customBandTokens", custom_band_order$, ","
    nTok2 = Get number of strings
    removeObject: tokStrings2
    if nTok2 <> num_bands
        exitScript: "Custom_band_order must list exactly " + string$ (num_bands)
            ... + " comma-separated 1-based band indices for the " + axis$
            ... + " axis (got " + string$ (nTok2) + ": " + custom_band_order$ + ")."
    endif
endif

# ---- CLEANUP PROCEDURE (defined after num_variants is known) ----
procedure cleanUpTempFiles
    if fileReadable (tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable (tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable (tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable (probeMarker$)
        deleteFile: probeMarker$
    endif
    for .v to 16
        .f$ = tempBase$ + "_v" + string$ (.v) + ".wav"
        if fileReadable (.f$)
            deleteFile: .f$
        endif
    endfor
endproc

@cleanUpTempFiles

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Spectral Permutation v2.0 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$ (dur, 3), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""
appendInfoLine: "Preset:       ", presetName$
if presetApplied and not show_advanced
    appendInfoLine: "  (preset set axis, blocks, bands, spacing, decorrelation,"
    appendInfoLine: "   ordering, seed, window, hop, phase and edge fade)"
elsif presetApplied
    appendInfoLine: "  (preset values, then edited in the advanced dialog)"
endif
appendInfoLine: "Region:       ", fixed$ (start_time, 3), " -> ", fixed$ (end_time, 3), " s"
appendInfoLine: "(output contains ONLY this region, not the rest of the sound)"
appendInfoLine: "Axis:         ", axis$
if axis$ = "freq"
    appendInfoLine: "Blocks:       not used on the freq axis (time is held fixed)"
else
    appendInfoLine: "Blocks:       ", num_blocks
endif
if axis$ <> "time"
    appendInfoLine: "Bands:        ", num_bands, "  (", spacing$, " spacing)"
    appendInfoLine: "Decorrelation: ", fixed$ (decorrelation, 2)
endif
appendInfoLine: "Ordering:     ", kind$
if needTimeOrder
    appendInfoLine: "Custom order: ", custom_order$
endif
if needBandOrder
    appendInfoLine: "Custom bands: ", custom_band_order$
endif
if kind$ <> "custom_order"
    appendInfoLine: "Seed:         ", seed
endif
appendInfoLine: "Window:       ", fixed$ (effectiveWindowMs, 2), " ms  (", fftSize, " samples @ ", sr, " Hz)"
if abs (effectiveWindowMs - requestedWindowMs) > 0.01
    appendInfoLine: "  (requested ", fixed$ (requestedWindowMs, 2), " ms; snapped to the nearest power of two)"
endif
appendInfoLine: "Hop:          ", hop_size, " samples"
appendInfoLine: "Phase mode:   ", phase$
appendInfoLine: "Edge fade:    ", fixed$ (edge_fade_ms, 1), " ms"
appendInfoLine: "Variants:     ", num_variants
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable (probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$
        ... + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Export Temp WAV (32-bit float; 16-bit would quantise the input)
# ===========================================================================
appendInfoLine: "[2/5] Exporting temp WAV..."

selectObject: sound
Save as 32-bit WAV file: tempInput$

# ===========================================================================
# Stage 3 — Call Python
# ===========================================================================
appendInfoLine: "[3/5] Running Python spectral-permutation engine..."

# Python indexes from the file start, so shift the region by the Sound's xmin.
pyStart = start_time - tmin
pyEnd   = end_time - tmin
if pyStart < 0
    pyStart = 0
endif

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " --start "         + fixed$ (pyStart, 6)
    ... + " --end "           + fixed$ (pyEnd, 6)
    ... + " --axis "          + axis$
    ... + " --num_blocks "    + string$ (num_blocks)
    ... + " --num_bands "     + string$ (num_bands)
    ... + " --band_spacing "  + spacing$
    ... + " --decorrelation " + fixed$ (decorrelation, 4)
    ... + " --kind "          + kind$
    ... + " --seed "          + string$ (seed)
    ... + " --phase_mode "    + phase$
    ... + " --fft_size "      + string$ (fftSize)
    ... + " --hop_size "      + string$ (hop_size)
    ... + " --edge_fade_ms "  + fixed$ (edge_fade_ms, 3)
    ... + " --num_variants "  + string$ (num_variants)
    ... + " --cleanup"

if needTimeOrder
    pythonCall$ = pythonCall$ + " --custom_order """ + custom_order$ + """"
endif
if needBandOrder
    pythonCall$ = pythonCall$ + " --custom_band_order """ + custom_band_order$ + """"
endif

# Temp filenames are fixed, so a crashed run would otherwise leave old files
# in place and the fileReadable() check below would pass on stale data,
# silently importing a previous result as if it were new.
if fileReadable (tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable (tempStats$)
    deleteFile: tempStats$
endif
for v to 16
    f$ = tempBase$ + "_v" + string$ (v) + ".wav"
    if fileReadable (f$)
        deleteFile: f$
    endif
endfor

runSystem_nocheck: pythonCall$

if num_variants = 1
    firstOut$ = tempOutput$
else
    firstOut$ = tempBase$ + "_v1.wav"
endif

if not fileReadable (firstOut$)
    @cleanUpTempFiles
    exitScript: "Python spectral-permutation engine failed." + newline$
        ... + "Check terminal for error details."
endif

# ===========================================================================
# Stage 4 — Read Stats
# ===========================================================================
appendInfoLine: "[4/5] Reading stats and importing result..."

statsText$ = ""
if fileReadable (tempStats$)
    statsText$ = newline$ + readFile$ (tempStats$)
endif

@statStr: "master_order"
masterOrder$ = statStr.out$
@statStr: "band_order"
bandOrder$ = statStr.out$
@statStr: "warning"
warning$ = statStr.out$
@statStr: "blocks_used"
blocksUsed$ = statStr.out$
if blocksUsed$ = ""
    blocksUsed$ = "yes"
endif
@statNum: "max_step_in"
stepIn = statNum.out
@statNum: "max_step_out"
stepOut = statNum.out
@statNum: "peak_out"
peakOut = statNum.out
@statNum: "interior_frames"
interiorFrames = statNum.out
@statNum: "block_frames"
blockFrames = statNum.out
@statNum: "tail_frames"
tailFrames = statNum.out
@statNum: "independent_bands"
indepBands = statNum.out
@statNum: "map_bands"
mapBands = statNum.out
@statNum: "map_blocks"
mapBlocks = statNum.out
@statNum: "map_ramp"
mapRamp = statNum.out
@statStr: "map_value"
mapValue$ = statStr.out$
if mapValue$ = ""
    mapValue$ = "block"
endif

if mapBands = undefined or mapBands < 1
    mapBands = num_bands
endif
if mapBlocks = undefined or mapBlocks < 1
    mapBlocks = num_blocks
endif
if mapRamp = undefined or mapRamp < 1
    mapRamp = mapBlocks
endif

# Per-band orders and band edge frequencies, into plain global arrays.
# Procedure-local (dotted) names cannot be reached by 'x' interpolation,
# so these are deliberately plain globals with a distinguishing prefix.
for b to mapBands
    @statStr: "map_row_" + string$ (b)
    row$ = statStr.out$
    spRow_'b'$ = row$
    for i to mapBlocks
        @nthToken: row$, i
        spMap_'b'_'i' = nthToken.out
    endfor
    @statStr: "band_" + string$ (b) + "_hz"
    hz$ = statStr.out$
    @nthToken: hz$, 1
    spBandLo_'b' = nthToken.out
    @nthToken: hz$, 2
    spBandHi_'b' = nthToken.out
endfor

# ===========================================================================
# Stage 5 — Import Results
# ===========================================================================
for v to num_variants
    if num_variants = 1
        f$ = tempOutput$
        suffix$ = "_permspec"
    else
        f$ = tempBase$ + "_v" + string$ (v) + ".wav"
        suffix$ = "_permspec_v" + string$ (v)
    endif
    if fileReadable (f$)
        Read from file: f$
        Rename: soundName$ + suffix$
        spResult_'v' = selected ("Sound")
    endif
endfor

resultSound = spResult_1
selectObject: resultSound
durOut = Get total duration
regionDur = end_time - start_time

# ===========================================================================
# Visualization
# ===========================================================================
if draw_visualization
    canvasW = 8
    canvasH = 9.4
    drawMaxHz = sr / 2
    if drawMaxHz > 10000
        drawMaxHz = 10000
    endif

    # Region of the ORIGINAL, mono, for the "before" spectrogram.
    # To Spectrogram needs mono; stereo input is a known crash in this family.
    selectObject: sound
    origRegion = Extract part: start_time, end_time, "rectangular", 1, "no"
    if nChannels > 1
        selectObject: origRegion
        origMono = Convert to mono
        removeObject: origRegion
        origRegion = origMono
    endif
    selectObject: origRegion
    Shift times to: "start time", 0
    specA = To Spectrogram: 0.01, drawMaxHz, 0.002, 20, "Gaussian"

    selectObject: resultSound
    resNCh = Get number of channels
    if resNCh > 1
        resMono = Convert to mono
    else
        resMono = Copy: "specperm_drawcopy"
    endif
    selectObject: resMono
    Shift times to: "start time", 0
    specB = To Spectrogram: 0.01, drawMaxHz, 0.002, 20, "Gaussian"

    Erase all
    Black
    Solid line
    Line width: 1

    # ---- TITLE STRIP ----
    # Axes maps to the INNER viewport, so a text strip must use
    # Select inner viewport or the two lines collapse onto each other.
    Font size: 14
    Select inner viewport: 0.60, 7.70, 0.15, 0.60
    Axes: 0, 1, 0, 1
    Text: 0, "left", 0.72, "half", "##Spectral Permutation##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.15, 0.60
    Axes: 0, 1, 0, 1
    @clean: soundName$
    nm$ = clean.out$
    @clean: axis$
    axLabel$ = clean.out$
    Text: 0, "left", 0.18, "half", nm$ + "   axis " + axLabel$
        ... + "   blocks " + string$ (num_blocks)
        ... + "   bands " + string$ (mapBands)
        ... + "   " + spacing$
    Text: 1, "right", 0.18, "half", fixed$ (start_time, 3) + " - "
        ... + fixed$ (end_time, 3) + " s"

    # ---- PANEL A: ORIGINAL REGION ----
    # Font size BEFORE Select inner viewport: Praat derives the inner
    # margins from the current font size, so a later change shifts the frame.
    Font size: 6
    Select inner viewport: 0.60, 7.70, 0.90, 2.60
    selectObject: specA
    Paint: 0, 0, 0, drawMaxHz, 100, "yes", 50, 6, 0, "no"

    Select inner viewport: 0.60, 7.70, 0.90, 2.60
    Axes: 0, regionDur, 0, drawMaxHz
    @drawBandGrid: mapBands, drawMaxHz, regionDur
    @drawBlockGrid: num_blocks, regionDur, drawMaxHz

    Select inner viewport: 0.60, 7.70, 0.90, 2.60
    Axes: 0, regionDur, 0, drawMaxHz
    Draw inner box
    Select inner viewport: 0.60, 7.70, 0.90, 2.60
    Axes: 0, regionDur, 0, drawMaxHz
    Marks left every: 1000, 2, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "no", "yes", "no"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.90, 2.60
    Axes: 0, 1, 0, 1
    Text: 0, "left", 1.04, "half", "##A. Source region##   (kHz vs s)"

    # ---- PANEL B: PERMUTED RESULT ----
    Font size: 6
    Select inner viewport: 0.60, 7.70, 3.10, 4.80
    selectObject: specB
    Paint: 0, 0, 0, drawMaxHz, 100, "yes", 50, 6, 0, "no"

    Select inner viewport: 0.60, 7.70, 3.10, 4.80
    Axes: 0, regionDur, 0, drawMaxHz
    @drawBandGrid: mapBands, drawMaxHz, regionDur
    @drawBlockGrid: num_blocks, regionDur, drawMaxHz

    Select inner viewport: 0.60, 7.70, 3.10, 4.80
    Axes: 0, regionDur, 0, drawMaxHz
    Draw inner box
    Select inner viewport: 0.60, 7.70, 3.10, 4.80
    Axes: 0, regionDur, 0, drawMaxHz
    Marks left every: 1000, 2, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 3.10, 4.80
    Axes: 0, 1, 0, 1
    Text: 0, "left", 1.04, "half", "##B. Permuted result##   (kHz vs s)"

    # ---- PANEL C: PERMUTATION MAP ----
    # Each cell is one (band, destination block). Its colour and number give
    # the SOURCE block it was taken from. Rows that differ from one another
    # are exactly what makes this a spectral rather than a temporal operation.
    Font size: 6
    Select inner viewport: 0.60, 7.70, 5.30, 7.00
    Axes: 0, mapBlocks, 0, mapBands
    for b to mapBands
        for i to mapBlocks
            src = spMap_'b'_'i'
            @blockColour: src, mapRamp
            Paint rectangle: {blockColour.r, blockColour.g, blockColour.b},
                ... i - 1, i, mapBands - b, mapBands - b + 1
        endfor
    endfor

    Select inner viewport: 0.60, 7.70, 5.30, 7.00
    Axes: 0, mapBlocks, 0, mapBands
    Black
    Line width: 1
    for i from 1 to mapBlocks - 1
        Draw line: i, 0, i, mapBands
    endfor
    if mapBands <= 20
        for b from 1 to mapBands - 1
            Draw line: 0, b, mapBlocks, b
        endfor
    endif

    # Cell numbers only where they will fit and be legible.
    if mapBands <= 16 and mapBlocks <= 12
        Select inner viewport: 0.60, 7.70, 5.30, 7.00
        Axes: 0, mapBlocks, 0, mapBands
        Font size: 6
        Select inner viewport: 0.60, 7.70, 5.30, 7.00
        Axes: 0, mapBlocks, 0, mapBands
        for b to mapBands
            for i to mapBlocks
                Text: i - 0.5, "centre", mapBands - b + 0.5, "half",
                    ... string$ (spMap_'b'_'i')
            endfor
        endfor
    endif

    Select inner viewport: 0.60, 7.70, 5.30, 7.00
    Axes: 0, mapBlocks, 0, mapBands
    Draw inner box

    # Band labels down the left. One mark takes WRITE NUMBER first, then
    # DRAW TICK, then DRAW DOTTED LINE - so a labelled tick is "no","yes","no"
    # or the numeric position prints on top of the label.
    Select inner viewport: 0.60, 7.70, 5.30, 7.00
    Axes: 0, mapBlocks, 0, mapBands
    bandStep = 1
    if mapBands > 16
        bandStep = ceiling (mapBands / 12)
    endif
    for b to mapBands
        if (b - 1) mod bandStep = 0
            One mark left: mapBands - b + 0.5, "no", "yes", "no",
                ... string$ (round (spBandLo_'b'))
        endif
    endfor
    if mapValue$ = "block"
        for i to mapBlocks
            One mark bottom: i - 0.5, "no", "yes", "no", string$ (i)
        endfor
    endif
    Font size: 7
    Select inner viewport: 0.60, 7.70, 5.30, 7.00
    Axes: 0, 1, 0, 1
    if mapValue$ = "band"
        Text: 0, "left", 1.04, "half",
            ... "##C. Permutation map##   cell = source band; rows = destination bands (band low edge, Hz); time is held fixed"
    else
        Text: 0, "left", 1.04, "half",
            ... "##C. Permutation map##   cell = source block; rows = bands (band low edge, Hz); columns = destination block"
    endif

    # ---- PANEL D: SUMMARY ----
    Font size: 7
    Select inner viewport: 0.60, 7.70, 7.50, 9.15
    Axes: 0, 1, 0, 1
    Paint rectangle: {0.94, 0.94, 0.94}, 0, 1, 0, 1

    Select inner viewport: 0.60, 7.70, 7.50, 9.15
    Axes: 0, 1, 0, 1
    Black
    yy = 0.90
    Text: 0.02, "left", yy, "half", "##Summary##"
    yy = yy - 0.11
    Text: 0.02, "left", yy, "half", "Preset: " + presetName$ + "     Axis: " + axLabel$
        ... + "     Ordering: " + replace$ (kind$, "_", "-", 0)
        ... + "     Phase: " + phase$
        ... + "     Decorrelation: " + fixed$ (decorrelation, 2)
    yy = yy - 0.10
    Text: 0.02, "left", yy, "half", "Window: " + fixed$ (effectiveWindowMs, 2)
        ... + " ms (" + string$ (fftSize) + " samples)     Hop: " + string$ (hop_size)
        ... + "     Interior frames: " + string$ (interiorFrames)
        ... + "     Block: " + string$ (blockFrames) + " frames"
        ... + "     Tail: " + string$ (tailFrames)
        ... + "     Blocks used: " + blocksUsed$
    yy = yy - 0.10
    Text: 0.02, "left", yy, "half", "Independent bands: " + string$ (indepBands)
        ... + " of " + string$ (mapBands)
        ... + "     Master order: " + masterOrder$
    yy = yy - 0.10
    Text: 0.02, "left", yy, "half", "Max sample step - source " + fixed$ (stepIn, 5)
        ... + " , result " + fixed$ (stepOut, 5)
        ... + "     Output peak: " + fixed$ (peakOut, 4)
    yy = yy - 0.10
    Text: 0.02, "left", yy, "half", "Region: " + fixed$ (start_time, 3) + " - "
        ... + fixed$ (end_time, 3) + " s     Output: " + fixed$ (durOut, 3)
        ... + " s     Variants: " + string$ (num_variants)
        ... + "     Seed: " + string$ (seed)
    yy = yy - 0.10
    if warning$ <> "none" and warning$ <> "" and warning$ <> "?"
        @clean: warning$
        Text: 0.02, "left", yy, "half", "WARNING: " + clean.out$
    else
        if axis$ = "time"
            Text: 0.02, "left", yy, "half",
                ... "Note: the time axis is equivalent to a time-domain splice. Use band"
                ... + "\_ time or freq for a genuinely spectral result."
        else
            Text: 0.02, "left", yy, "half",
                ... "Rows of panel C that differ from one another are the spectral content of this operation."
        endif
    endif

    Select inner viewport: 0.60, 7.70, 7.50, 9.15
    Axes: 0, 1, 0, 1
    Draw inner box

    removeObject: specA, specB, origRegion, resMono

    # Save as / Copy exports the CURRENT viewport selection, so end on the
    # full canvas or the export is silently cropped to the last panel.
    Select outer viewport: 0, canvasW, 0, canvasH
endif

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: "[5/5] Done."
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
if num_variants = 1
    appendInfoLine: "Output:              ", soundName$, "_permspec"
else
    appendInfoLine: "Outputs:             ", soundName$, "_permspec_v1 .. _v", num_variants
endif
appendInfoLine: "Selected region:     ", fixed$ (regionDur, 3), " s"
appendInfoLine: "Output duration:     ", fixed$ (durOut, 3), " s"
appendInfoLine: "Interior frames:     ", interiorFrames, "  (", blockFrames, " per block, ", tailFrames, " left as tail)"
if masterOrder$ = "n/a"
    appendInfoLine: "Master order:        not used on the freq axis"
else
    appendInfoLine: "Master order:        ", masterOrder$
endif
if axis$ = "freq" or axis$ = "time_freq"
    appendInfoLine: "Band order:          ", bandOrder$
endif
if mapBands > 1 and axis$ <> "freq"
    appendInfoLine: "Independent bands:   ", indepBands, " of ", mapBands
    appendInfoLine: "Per-band orders:"
    for b to mapBands
        appendInfoLine: "  band ", b, "  ", fixed$ (spBandLo_'b', 0), "-",
            ... fixed$ (spBandHi_'b', 0), " Hz   ", spRow_'b'$
    endfor
endif
appendInfoLine: "Max sample step:     source ", fixed$ (stepIn, 5), " -> result ", fixed$ (stepOut, 5)
appendInfoLine: "Output peak:         ", fixed$ (peakOut, 4)

if warning$ <> "?" and warning$ <> "none" and warning$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warning$
endif

selectObject: resultSound
for v from 2 to num_variants
    plusObject: spResult_'v'
endfor

if play_result
    selectObject: resultSound
    Play
endif

selectObject: resultSound
for v from 2 to num_variants
    plusObject: spResult_'v'
endfor

# ===========================================================================
# Procedures
# ===========================================================================

# Read a key=value line from the stats text. Keys are newline-anchored so
# that "seed=" does not match inside "variant_1_seed=".
procedure statStr: .key$
    .out$ = ""
    .pos = index (statsText$, newline$ + .key$ + "=")
    if .pos > 0
        .start = .pos + length (newline$) + length (.key$) + 1
        .rest$ = mid$ (statsText$, .start, length (statsText$) - .start + 1)
        .nl = index (.rest$, newline$)
        if .nl > 0
            .out$ = left$ (.rest$, .nl - 1)
        else
            .out$ = .rest$
        endif
    endif
endproc

procedure statNum: .key$
    @statStr: .key$
    if statStr.out$ = ""
        .out = undefined
    else
        .out = number (statStr.out$)
    endif
endproc

# nth comma-separated token of a string, as a number.
# mid$ MUST be called with three arguments: the two-argument form returns
# exactly one character, which silently truncates any tokenizer loop.
procedure nthToken: .s$, .n
    .out = undefined
    .rem$ = .s$
    .k = 0
    .done = 0
    while .done = 0
        .k = .k + 1
        .c = index (.rem$, ",")
        if .c > 0
            .tok$ = left$ (.rem$, .c - 1)
            .rem$ = mid$ (.rem$, .c + 1, length (.rem$) - .c)
        else
            .tok$ = .rem$
            .rem$ = ""
        endif
        if .k = .n
            .out = number (.tok$)
            .done = 1
        endif
        if .rem$ = "" and .done = 0
            .done = 1
        endif
    endwhile
endproc

# Distinguishable colour per source-block index.
procedure blockColour: .i, .n
    .h = (.i - 1) / .n
    .r = 0.63 + 0.31 * cos (2 * pi * (.h + 0.00))
    .g = 0.63 + 0.31 * cos (2 * pi * (.h + 0.33))
    .b = 0.63 + 0.31 * cos (2 * pi * (.h + 0.67))
endproc

# Horizontal band edges over a spectrogram panel.
procedure drawBandGrid: .nb, .maxHz, .t1
    if .nb > 1
        Line width: 1
        Colour: {0.20, 0.40, 0.80}
        .step = 1
        if .nb > 12
            .step = ceiling (.nb / 12)
        endif
        for .b from 2 to .nb
            if (.b - 1) mod .step = 0
                .f = spBandLo_'.b'
                if .f > 0 and .f < .maxHz
                    Draw line: 0, .f, .t1, .f
                endif
            endif
        endfor
        Black
    endif
endproc

# Vertical block boundaries over a spectrogram panel.
procedure drawBlockGrid: .nbk, .t1, .maxHz
    Line width: 2
    Colour: {0.85, 0.30, 0.10}
    Dotted line
    for .i from 1 to .nbk - 1
        .x = .t1 * .i / .nbk
        Draw line: .x, 0, .x, .maxHz
    endfor
    Solid line
    Black
endproc

# Picture-window text markup sanitizer. In Picture text `_` is subscript,
# `%` italic, `#` bold, `^` superscript, and each is SWALLOWED rather than
# printed. Escapes need exactly one trailing space.
procedure clean: .s$
    .out$ = replace$ (.s$, "\", "\bs", 0)
    .out$ = replace$ (.out$, "_", "\_ ", 0)
    .out$ = replace$ (.out$, "%", "\% ", 0)
    .out$ = replace$ (.out$, "#", "\# ", 0)
    .out$ = replace$ (.out$, "^", "\^ ", 0)
endproc
