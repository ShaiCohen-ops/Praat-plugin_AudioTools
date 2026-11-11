# ============================================================
# Praat AudioTools - Undertone Field.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 4.0 (2026)
# License: MIT License
#
# Description:
#   Builds a field of voices BELOW the source by sample-rate
#   reinterpretation. Every voice plays the source at one constant
#   playback rate between 0 and 1, so it is slower AND lower.
#
#   UNDERTONE ANCHORS (the mathematical skeleton):
#     rate(n) = 1 / (n+1)^(1 + stretch)        Integer series
#     stretch = 0 -> 1/2, 1/3, 1/4, 1/5 ...
#   Odd, Even, Custom and Geometric series as before.
#
#   SYNTHESIS
#     Pure undertones     one voice per anchor (the v3.x behaviour).
#     Deviated undertones each anchor becomes a GROUP: the anchor voice
#                         itself plus companions at small, fixed pitch
#                         deviations (cents). Each voice keeps ONE rate
#                         for its whole duration; the texture evolves
#                         because voices of slightly different rates
#                         drift apart in time, as in MAX_MC_Deviate.
#                         Deviations never lift a voice above -50 cents
#                         and, optionally, never let groups overlap.
#
#   SIGNAL FLOW (v4.0)
#     source window -> per voice: filter (spectral balance, subsonic
#     guard) -> RMS match -> group balance (gain curve + optional
#     low-register compensation) x anchor/companion weight -> pan ->
#     undertone bed.  Bed levelled ONCE to Undertone_level_dB.
#     Dry original added separately, in its own stereo image, at
#     Dry_level_dB.  Peak safety: one measured, reported gain.
#
#   DURATION
#     Natural   every voice plays to its natural end (window / rate).
#     Fixed     the output is cut at Fixed_duration_s with a fade;
#               the report lists which voices were cut and by how much.
#
# Changelog v4.0:
#   MIXING
#   - Monitor: Undertones only / Original + Undertones / Original only,
#     plus "Preset default". Separate Dry_level_dB and Undertone_level_dB.
#     A preset fixes both levels; Monitor only chooses what is heard, so
#     switching it never changes the preset's dry/undertone balance.
#   - Stereo sources keep their own L/R image in the dry signal (v3.5
#     folded the dry to centred mono). The undertones are still built
#     from a mono mix; if the channels cancel in that mix, the stronger
#     channel is used instead and this is reported.
#   - Presence tilt removed from the default chain: it raised deep layers
#     by up to 7 dB and largely cancelled the gain curves. It survives as
#     Low_register_comp_dB (default 0) and the report flags any case
#     where it reverses the selected curve.
#   - Undertone_level_dB is the measured RMS of the whole undertone bed,
#     relative to the source, over the span where the dry plays (or, with
#     staggered entries, the first window-length after the last entry).
#     The bed is levelled once, after the gain curve, so the curve keeps
#     its shape. How much the voices reinforce each other there is
#     reported separately.
#   - Peak safety: one global gain, reported with the dry-only and
#     undertones-only peaks so the cause is visible.
#   DURATION
#   - Natural duration replaces "source + tail": a 1/5 voice now plays
#     5x the window instead of being cut at source + 1.5 s.
#   - Fixed length mode with an explicit fade and a truncation report.
#   - Source window (start/end) for long sources; render limit
#     Max_output_s with a memory estimate.
#   SYNTHESIS
#   - Deviated undertones, voices per anchor, deviation in cents,
#     reproducible seed (0 = new seed each run, reported), anchor
#     emphasis, optional group-order preservation, staggered entries.
#   - Exact playback rates (v3.5 rounded the reinterpreted rate to 1 Hz).
#   - Filtering is applied before transposition at scaled frequencies
#     (mathematically the same filter, far less work on long voices).
#   SPECTRAL BALANCE
#   - Natural / Warm / Dark / Adaptive / Fixed low-pass (v3.5). The
#     v3.5 3 kHz low-pass put every layer in the same band; Natural and
#     Adaptive keep each voice's own transposed bandwidth.
#   - 30 Hz subsonic guard on every voice (deep transpositions otherwise
#     carry inaudible energy that inflates RMS matching and peaks).
#   SPACE
#   - Arc (v3.5) or Balanced clusters: groups placed by predicted energy
#     around the centre, voices of a group spread around their group
#     position according to their deviation.
#   PRESETS
#   - Seven v3.5 presets kept (structure, curve, low-pass, spread, level);
#     four new: Deviated Harmonic Field, Deep Polyphonic Undertones,
#     Microtonal Undertone Cloud, Expanding Undertone Field.
#   REPORT AND PICTURE
#   - Per-voice table: anchor, rate, cents, deviation, natural and
#     rendered duration, cut, cutoff, level. Dry-only, undertones-only
#     and combined RMS and peaks; L/R balance; mono fold-down.
#   - New voice-map panel (each voice as a line: pitch vs time).
#
# Category: Synthesis / Spectral / Composition
# ============================================================

utVersion$ = "4.0"

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

srcID    = selected("Sound")
srcName$ = selected$("Sound")
selectObject: srcID
origDur   = Get total duration
origFs    = Get sampling frequency
nCh       = Get number of channels
srcXmin   = Get start time

if origDur < 0.05
    exitScript: "Sound must be at least 50 ms."
endif

# ============================================================
# FORM
# ============================================================

form Undertone Field v4.0
    optionmenu Preset: 1
        option Custom
        option Pure Harmonic        (integer series, linear rolloff)
        option Stretched Cloud      (wider intervals, Gaussian)
        option Compressed Cluster   (narrower, exponential decay)
        option Bass Spectral        (6 partials, inverse, spectralist)
        option Spectral Haze        (5 partials, micro-stretch, soft)
        option Dark Undertow        (heavy low, fast rolloff, tight LP)
        option Microtonal Dense     (7 partials, tiny stretch, flat)
        option Deviated Harmonic Field   (3 voices per undertone)
        option Deep Polyphonic Undertones (odd series, low register)
        option Microtonal Undertone Cloud (two dense clusters)
        option Expanding Undertone Field  (groups enter in turn)
    comment Presets set structure, dry and undertone levels, colour. Monitor, Duration, seed always apply.
    optionmenu Synthesis: 1
        option Pure undertones      (one voice per undertone)
        option Deviated undertones  (several voices around each undertone)
    integer Number_of_undertones 4
    optionmenu Series_mode: 1
        option Integer          (1/2  1/3  1/4  ... standard undertone)
        option Odd denominators (1/3  1/5  1/7  ... odd series)
        option Even denominators (1/2  1/4  1/6  ... even/octave series)
        option Custom list      (denominators are set under Advanced)
        option Geometric        (1/2  1/2.5  1/3.1  ... microtonal)
    optionmenu Gain_curve: 2
        option Flat             (all undertones equal)
        option Linear           (linear rolloff per undertone)
        option Exponential      (fast rolloff, warm body)
        option Gaussian         (peak at middle undertone)
        option Inverse          (deeper = louder, spectralist build)
    integer Voices_per_undertone 3
    real Deviation_cents 25
    integer Random_seed_(0_=_new_each_run) 0
    optionmenu Monitor: 1
        option Preset default
        option Undertones only
        option Original + Undertones
        option Original only
    real Dry_level_dB 0.0
    real Undertone_level_dB -3.0
    optionmenu Duration: 1
        option Natural (every voice plays to its end)
        option Fixed length (cut and fade at Fixed_duration_s)
    positive Fixed_duration_s 20
    optionmenu Spectral_balance: 4
        option Natural   (no low-pass)
        option Warm      (gentle low-pass at 4.5 kHz)
        option Dark      (low-pass at 1.8 kHz)
        option Adaptive  (cutoff follows each voice's bandwidth)
        option Fixed low-pass (Lowpass_Hz, v3.5 behaviour)
    boolean Show_advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS (Custom)
# ============================================================
# Presets may override these; the optional Advanced dialogs open
# pre-filled with the current values, so a preset stays inspectable.

stretch_factor        = 0.0
custom_denominators$  = "2,3,5,7"
rolloff_dB            = 3.0
anchor_emphasis_dB    = 3.0
keep_groups_in_order  = 1
normalise_layers      = 1
low_register_comp_dB  = 0.0
lowpass_Hz            = 3000.0
spatial_layout        = 1
stereo_spread_pct     = 80.0
cluster_width_pct     = 25.0
micro_delay_ms        = 1.2
entry_spacing_pct     = 0.0
fade_s                = 1.5
source_start_s        = 0.0
source_end_s          = 0.0
max_output_s          = 300.0

presetMonitor = 2
presetDry_dB  = dry_level_dB

# ============================================================
# PRESETS
# ============================================================
# v3.5 presets keep their series, curve, low-pass, spread and level.
# Their presence tilt is not carried over (see changelog); the old
# Input_gain_dB becomes the preset's dry level.

if preset >= 2 and preset <= 8
    synthesis         = 1
    spectral_balance  = 5
    spatial_layout    = 1
    presetMonitor     = 2
    entry_spacing_pct = 0
    micro_delay_ms    = 1.2
endif

if preset = 2
    number_of_undertones = 4
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 2
    rolloff_dB           = 2.5
    undertone_level_dB   = -3.0
    presetDry_dB         = 0.0
    stereo_spread_pct    = 80.0
    lowpass_Hz           = 3000.0
elsif preset = 3
    number_of_undertones = 5
    stretch_factor       = 0.20
    series_mode          = 1
    gain_curve           = 4
    rolloff_dB           = 3.0
    undertone_level_dB   = -2.0
    presetDry_dB         = 0.0
    stereo_spread_pct    = 85.0
    lowpass_Hz           = 2600.0
elsif preset = 4
    number_of_undertones = 4
    stretch_factor       = -0.20
    series_mode          = 1
    gain_curve           = 3
    rolloff_dB           = 4.0
    undertone_level_dB   = -4.0
    presetDry_dB         = 0.0
    stereo_spread_pct    = 75.0
    lowpass_Hz           = 3200.0
elsif preset = 5
    number_of_undertones = 6
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 5
    rolloff_dB           = 2.5
    undertone_level_dB   = 0.0
    presetDry_dB         = -3.0
    stereo_spread_pct    = 85.0
    lowpass_Hz           = 2200.0
elsif preset = 6
    number_of_undertones = 5
    stretch_factor       = 0.12
    series_mode          = 5
    gain_curve           = 4
    rolloff_dB           = 2.0
    undertone_level_dB   = -4.0
    presetDry_dB         = 0.0
    stereo_spread_pct    = 90.0
    lowpass_Hz           = 3600.0
elsif preset = 7
    number_of_undertones = 4
    stretch_factor       = -0.10
    series_mode          = 1
    gain_curve           = 3
    rolloff_dB           = 6.0
    undertone_level_dB   = 1.0
    presetDry_dB         = -4.0
    stereo_spread_pct    = 70.0
    lowpass_Hz           = 1600.0
elsif preset = 8
    number_of_undertones = 7
    stretch_factor       = 0.05
    series_mode          = 5
    gain_curve           = 1
    rolloff_dB           = 0.0
    undertone_level_dB   = -5.0
    presetDry_dB         = 0.0
    stereo_spread_pct    = 100.0
    lowpass_Hz           = 3000.0
elsif preset = 9
    # Deviated Harmonic Field: clear integer skeleton, three voices per
    # anchor, anchor voice slightly forward.
    synthesis            = 2
    number_of_undertones = 4
    voices_per_undertone = 3
    deviation_cents      = 30
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 2
    rolloff_dB           = 2.0
    anchor_emphasis_dB   = 3.0
    keep_groups_in_order = 1
    undertone_level_dB   = 0.0
    presetMonitor        = 1
    presetDry_dB         = 0.0
    spectral_balance     = 4
    spatial_layout       = 2
    stereo_spread_pct    = 80.0
    cluster_width_pct    = 30.0
    micro_delay_ms       = 1.2
    entry_spacing_pct    = 0
elsif preset = 10
    # Deep Polyphonic Undertones: odd series (1/3 .. 1/9), deeper voices
    # louder, two independent voices per anchor, dry kept low.
    synthesis            = 2
    number_of_undertones = 4
    voices_per_undertone = 2
    deviation_cents      = 20
    stretch_factor       = 0.0
    series_mode          = 2
    gain_curve           = 5
    rolloff_dB           = 1.5
    anchor_emphasis_dB   = 0.0
    keep_groups_in_order = 1
    undertone_level_dB   = 0.0
    presetMonitor        = 2
    presetDry_dB         = -12.0
    spectral_balance     = 2
    spatial_layout       = 2
    stereo_spread_pct    = 90.0
    cluster_width_pct    = 40.0
    micro_delay_ms       = 0.0
    entry_spacing_pct    = 0
elsif preset = 11
    # Microtonal Undertone Cloud: two anchors, seven voices each within
    # +/-15 cents; the voices separate slowly in time.
    synthesis            = 2
    number_of_undertones = 2
    voices_per_undertone = 7
    deviation_cents      = 15
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 1
    rolloff_dB           = 0.0
    anchor_emphasis_dB   = 0.0
    keep_groups_in_order = 1
    undertone_level_dB   = 0.0
    presetMonitor        = 1
    presetDry_dB         = 0.0
    spectral_balance     = 1
    spatial_layout       = 2
    stereo_spread_pct    = 90.0
    cluster_width_pct    = 60.0
    micro_delay_ms       = 0.0
    entry_spacing_pct    = 0
elsif preset = 12
    # Expanding Undertone Field: five groups enter one after another,
    # each 60 % of the source window after the previous one, descending.
    synthesis            = 2
    number_of_undertones = 5
    voices_per_undertone = 3
    deviation_cents      = 12
    stretch_factor       = 0.0
    series_mode          = 1
    gain_curve           = 2
    rolloff_dB           = 1.0
    anchor_emphasis_dB   = 2.0
    keep_groups_in_order = 1
    undertone_level_dB   = 0.0
    presetMonitor        = 1
    presetDry_dB         = 0.0
    spectral_balance     = 4
    spatial_layout       = 2
    stereo_spread_pct    = 85.0
    cluster_width_pct    = 30.0
    micro_delay_ms       = 1.2
    entry_spacing_pct    = 60
endif

# ============================================================
# ADVANCED SETTINGS (optional, two short dialogs)
# ============================================================

if show_advanced_settings = 1
    beginPause: "Undertone Field — advanced 1/2: series and level"
        comment: "Series and voices"
        real: "Stretch_factor", string$(stretch_factor)
        sentence: "Custom_denominators", custom_denominators$
        real: "Rolloff_dB", string$(rolloff_dB)
        real: "Anchor_emphasis_dB", string$(anchor_emphasis_dB)
        boolean: "Keep_groups_in_order", keep_groups_in_order
        comment: "Level and colour"
        boolean: "Normalise_layers", normalise_layers
        real: "Low_register_comp_dB", string$(low_register_comp_dB)
        comment: "(dB per octave below the source, 0 = off)"
        real: "Lowpass_Hz", string$(lowpass_Hz)
    advClicked = endPause: "Cancel", "Continue", 2, 1
    if advClicked = 1
        exitScript: ""
    endif

    beginPause: "Undertone Field — advanced 2/2: space and time"
        optionMenu: "Spatial_layout", spatial_layout
            option: "Arc (v3.5: first undertone left, last right)"
            option: "Balanced clusters (groups placed by energy)"
        real: "Stereo_spread_pct", string$(stereo_spread_pct)
        real: "Cluster_width_pct", string$(cluster_width_pct)
        real: "Micro_delay_ms", string$(micro_delay_ms)
        real: "Entry_spacing_pct", string$(entry_spacing_pct)
        comment: "(% of the source window between group entries)"
        real: "Fade_s", string$(fade_s)
        comment: "Source window (0 and 0 = whole sound) and render limit"
        real: "Source_start_s", string$(source_start_s)
        real: "Source_end_s", string$(source_end_s)
        real: "Max_output_s", string$(max_output_s)
    advClicked = endPause: "Cancel", "Continue", 2, 1
    if advClicked = 1
        exitScript: ""
    endif
endif

# ============================================================
# MONITOR RESOLUTION
# ============================================================
# monitorMode: 1 = Undertones only, 2 = Original + Undertones,
#              3 = Original only

# A preset owns its dry level just as it owns the undertone level, so
# choosing a monitor mode never changes the preset's balance. With Custom,
# Dry_level_dB from the form applies.
if preset > 1
    dry_level_dB = presetDry_dB
endif
if monitor = 1
    monitorMode = presetMonitor
else
    monitorMode = monitor - 1
endif

if synthesis = 1
    voicesPerGroup = 1
else
    voicesPerGroup = voices_per_undertone
endif

# ============================================================
# VALIDATION (before any object is created)
# ============================================================

if number_of_undertones < 1 or number_of_undertones > 8
    exitScript: "Number_of_undertones must be between 1 and 8."
endif
if synthesis = 2
    if voices_per_undertone < 1 or voices_per_undertone > 8
        exitScript: "Voices_per_undertone must be between 1 and 8."
    endif
    if deviation_cents < 0 or deviation_cents > 600
        exitScript: "Deviation_cents must be between 0 and 600."
    endif
endif
if random_seed < 0
    exitScript: "Random_seed must be 0 (new seed each run) or a positive whole number."
endif
if stretch_factor < -0.5 or stretch_factor > 0.5
    exitScript: "Stretch_factor must be between -0.5 and +0.5."
endif
if rolloff_dB < 0 or rolloff_dB > 24
    exitScript: "Rolloff_dB must be between 0 and 24."
endif
if anchor_emphasis_dB < -12 or anchor_emphasis_dB > 12
    exitScript: "Anchor_emphasis_dB must be between -12 and +12."
endif
if low_register_comp_dB < 0 or low_register_comp_dB > 12
    exitScript: "Low_register_comp_dB must be between 0 and 12 dB per octave."
endif
if micro_delay_ms < 0 or micro_delay_ms > 20
    exitScript: "Micro_delay_ms must be between 0 and 20 ms."
endif
if undertone_level_dB < -40 or undertone_level_dB > 12
    exitScript: "Undertone_level_dB must be between -40 and +12 dB."
endif
if dry_level_dB < -60 or dry_level_dB > 12
    exitScript: "Dry_level_dB must be between -60 and +12 dB."
endif
if stereo_spread_pct < 0 or stereo_spread_pct > 100
    exitScript: "Stereo_spread_pct must be between 0 and 100."
endif
if cluster_width_pct < 0 or cluster_width_pct > 100
    exitScript: "Cluster_width_pct must be between 0 and 100."
endif
if entry_spacing_pct < 0 or entry_spacing_pct > 400
    exitScript: "Entry_spacing_pct must be between 0 and 400."
endif
if max_output_s < 1 or max_output_s > 1800
    exitScript: "Max_output_s must be between 1 and 1800 seconds."
endif
if duration = 2
    if fixed_duration_s < 0.1 or fixed_duration_s > max_output_s
        exitScript: "Fixed_duration_s must be between 0.1 s and Max_output_s ("
            ... + fixed$(max_output_s, 0) + " s)."
    endif
    if fade_s < 0 or fade_s > fixed_duration_s
        exitScript: "Fade_s must be between 0 and Fixed_duration_s."
    endif
endif

nyquistSafe = origFs / 2 - 100
if nyquistSafe < 50
    exitScript: "Sampling frequency is too low for this effect."
endif
if spectral_balance = 5
    if lowpass_Hz < 50 or lowpass_Hz > nyquistSafe
        exitScript: "Lowpass_Hz must be between 50 Hz and Nyquist minus 100 Hz ("
            ... + fixed$(nyquistSafe, 0) + " Hz)."
    endif
endif

# Source window
winStart = source_start_s
winEnd   = source_end_s
if winEnd <= 0
    winEnd = origDur
endif
if winStart < 0 or winStart >= origDur
    exitScript: "Source_start_s must be at least 0 and before the end of the sound ("
        ... + fixed$(origDur, 3) + " s)."
endif
if winEnd > origDur + 1e-9
    exitScript: "Source_end_s is beyond the end of the sound (" + fixed$(origDur, 3)
        ... + " s). Use 0 for the end of the sound."
endif
if winEnd - winStart < 0.05
    exitScript: "The source window must be at least 50 ms long."
endif
cutStart = 0
cutEnd   = 0
if winStart > 1e-9
    cutStart = 1
endif
if winEnd < origDur - 1e-9
    cutEnd = 1
endif
winDur = winEnd - winStart

# ============================================================
# ANCHORS — the mathematical undertone series
# ============================================================

nG = number_of_undertones
denom# = zero#(nG)

if series_mode = 4
    parseStr$ = custom_denominators$ + ","
    numBuf$ = ""
    parsedN = 0
    digitCount = 0
    dotCount = 0
    strLen = length(parseStr$)
    for ci from 1 to strLen
        ch$ = mid$(parseStr$, ci, 1)
        if ch$ = "," or ch$ = ";" or ch$ = " "
            if length(numBuf$) > 0
                if digitCount = 0 or dotCount > 1
                    exitScript: "Malformed Custom_denominators token: " + numBuf$
                endif
                parsedN += 1
                if parsedN > nG
                    exitScript: "Custom_denominators contains more values than Number_of_undertones."
                endif
                dv = number(numBuf$)
                if dv <= 1
                    exitScript: "Every custom denominator must be greater than 1 (got "
                        ... + numBuf$ + "): undertones must lie below the source."
                endif
                denom#[parsedN] = dv
                numBuf$ = ""
                digitCount = 0
                dotCount = 0
            endif
        elsif ch$ >= "0" and ch$ <= "9"
            numBuf$ += ch$
            digitCount += 1
        elsif ch$ = "."
            numBuf$ += ch$
            dotCount += 1
            if dotCount > 1
                exitScript: "Malformed Custom_denominators token: " + numBuf$
            endif
        else
            exitScript: "Unsupported character in Custom_denominators: " + ch$
        endif
    endfor
    if parsedN < 1
        exitScript: "Custom_denominators must contain at least one value."
    endif
    for n from parsedN + 1 to nG
        denom#[n] = denom#[n - 1] + 1
    endfor
elsif series_mode = 5
    geoR = 1.25 ^ (1 + stretch_factor)
    for n from 1 to nG
        denom#[n] = 2 * (geoR ^ (n - 1))
    endfor
else
    for n from 1 to nG
        if series_mode = 1
            rawD = n + 1
        elsif series_mode = 2
            rawD = 2 * n + 1
        else
            rawD = 2 * n
        endif
        denom#[n] = rawD ^ (1 + stretch_factor)
    endfor
endif

# Lowest usable rate: the reinterpreted clock may not fall below 100 Hz
# (as in v3.x). Highest: no voice may reach the source pitch.
minRate = 100 / origFs
ceilCents = -50

anchorRate#  = zero#(nG)
anchorCents# = zero#(nG)
anchorClamped# = zero#(nG)
rateClampCount = 0
for n from 1 to nG
    ar = 1 / denom#[n]
    if ar < minRate
        ar = minRate
        anchorClamped#[n] = 1
        rateClampCount += 1
    endif
    anchorRate#[n]  = ar
    anchorCents#[n] = 1200 * log2(ar)
endfor

# ---- Deviation range per group (cents relative to its anchor) ----
devLo# = zero#(nG)
devHi# = zero#(nG)
devLimited# = zero#(nG)
devLimit$ = ""
dReq = 0
if synthesis = 2 and voicesPerGroup > 1
    dReq = deviation_cents
endif
for n from 1 to nG
    lo = -dReq
    hi = dReq
    why$ = ""
    # ceiling: stay at least 50 cents below the source
    hiMax = ceilCents - anchorCents#[n]
    if hiMax < 0
        hiMax = 0
    endif
    if hi > hiMax
        hi = hiMax
        why$ = "stays below source"
    endif
    # floor: the 100 Hz reinterpreted-clock limit
    loMin = 1200 * log2(minRate) - anchorCents#[n]
    if lo < loMin
        lo = loMin
        why$ = "rate floor"
    endif
    # optional: groups never cross their pitch neighbours
    if keep_groups_in_order = 1 and nG > 1
        gapUp = 1e9
        gapDn = 1e9
        for m from 1 to nG
            dc = anchorCents#[m] - anchorCents#[n]
            if dc > 0.5 and dc < gapUp
                gapUp = dc
            endif
            if dc < -0.5 and -dc < gapDn
                gapDn = -dc
            endif
        endfor
        if gapUp < 1e9 and hi > 0.45 * gapUp
            hi = 0.45 * gapUp
            why$ = "keeps group order"
        endif
        if gapDn < 1e9 and lo < -0.45 * gapDn
            lo = -0.45 * gapDn
            why$ = "keeps group order"
        endif
    endif
    if lo > 0
        lo = 0
    endif
    devLo#[n] = lo
    devHi#[n] = hi
    if dReq > 0 and (hi < dReq - 0.05 or lo > -dReq + 0.05)
        devLimited#[n] = 1
        devLimit$[n] = why$
    endif
endfor

# ---- Random seed ----
if random_seed = 0
    random_initializeSafelyAndUnpredictably ()
    seedUsed = randomInteger (1, 999999)
    seedNote$ = "new this run"
else
    seedUsed = random_seed
    seedNote$ = "as entered"
endif
random_initializeWithSeedUnsafelyButPredictably (seedUsed)

# ---- Voices ----
nV = nG * voicesPerGroup
vGroup#  = zero#(nV)
vIdx#    = zero#(nV)
vAnchor# = zero#(nV)
vDev#    = zero#(nV)
vRate#   = zero#(nV)
vCents#  = zero#(nV)

j = 0
for n from 1 to nG
    for k from 1 to voicesPerGroup
        j += 1
        vGroup#[j] = n
        vIdx#[j] = k
        if k = 1
            vAnchor#[j] = 1
            dv = 0
        else
            # Stratified draw (one companion per sub-range, so values are
            # spread and distinct) over [lo, -gap] + [gap, hi]: companions
            # keep at least 20 % of the deviation away from the anchor,
            # otherwise a near-unison would take minutes to drift audibly.
            u = ((k - 2) + randomUniform (0, 1)) / (voicesPerGroup - 1)
            gap = 0.2 * dReq
            negLen = max(0, -gap - devLo#[n])
            posLen = max(0, devHi#[n] - gap)
            if negLen + posLen > 0.5
                pos = u * (negLen + posLen)
                if pos < negLen
                    dv = devLo#[n] + pos
                else
                    dv = gap + (pos - negLen)
                endif
            else
                dv = devLo#[n] + u * (devHi#[n] - devLo#[n])
            endif
        endif
        vDev#[j]   = dv
        vCents#[j] = anchorCents#[n] + dv
        vRate#[j]  = 2 ^ (vCents#[j] / 1200)
    endfor
endfor

# Leave Praat's random generator unpredictable for other scripts.
random_initializeSafelyAndUnpredictably ()

# Hard guarantee: every rate strictly between 0 and 1.
highestCents = -1e9
for j from 1 to nV
    if vRate#[j] <= 0 or vRate#[j] >= 1
        exitScript: "Internal check failed: voice " + string$(j) + " has playback rate "
            ... + fixed$(vRate#[j], 6) + ". Please report this."
    endif
    if vCents#[j] > highestCents
        highestCents = vCents#[j]
    endif
endfor

# ============================================================
# GROUP BALANCE — gain curve, optional low-register compensation
# ============================================================

curveDb# = zero#(nG)
compDb#  = zero#(nG)
netDb#   = zero#(nG)

gaussMid   = (nG + 1) / 2
gaussSigma = nG / (rolloff_dB + 0.5)
if gaussSigma < 0.3
    gaussSigma = 0.3
endif
for n from 1 to nG
    db = 0
    if gain_curve = 2
        db = -(n - 1) * rolloff_dB
    elsif gain_curve = 3
        db = -rolloff_dB * 2.2 * (1 - exp(-0.85 * (n - 1)))
    elsif gain_curve = 4
        gaussVal = exp(-((n - gaussMid) ^ 2) / (2 * gaussSigma ^ 2))
        db = 20 * log10(gaussVal + 1e-6)
    elsif gain_curve = 5
        db = (n - 1) * rolloff_dB
    endif
    curveDb#[n] = db
endfor
curveMax = max(curveDb#)
for n from 1 to nG
    curveDb#[n] = curveDb#[n] - curveMax
    compDb#[n]  = low_register_comp_dB * (-anchorCents#[n] / 1200)
    netDb#[n]   = curveDb#[n] + compDb#[n]
endfor
netMax = max(netDb#)
for n from 1 to nG
    netDb#[n] = netDb#[n] - netMax
endfor

# Does the compensation reverse the curve anywhere?
compReversals = 0
compRev$ = ""
for n from 1 to nG - 1
    if curveDb#[n] > curveDb#[n + 1] + 0.01 and netDb#[n] < netDb#[n + 1] - 0.01
        compReversals += 1
        compRev$ = compRev$ + " " + string$(n) + "/" + string$(n + 1)
    elsif curveDb#[n] < curveDb#[n + 1] - 0.01 and netDb#[n] > netDb#[n + 1] + 0.01
        compReversals += 1
        compRev$ = compRev$ + " " + string$(n) + "/" + string$(n + 1)
    endif
endfor

# Requested level of each group: the bed level target is shared out in
# proportion to the group balance (each group has unit internal power).
netPowSum = 0
for n from 1 to nG
    netPowSum += 10 ^ (netDb#[n] / 10)
endfor
reqGroupDb# = zero#(nG)
for n from 1 to nG
    reqGroupDb#[n] = undertone_level_dB + netDb#[n] - 10 * log10(netPowSum)
endfor

# Weights inside a group: the anchor voice versus its companions.
if voicesPerGroup > 1
    aLin = 10 ^ (anchor_emphasis_dB / 20)
    wNorm = sqrt(aLin ^ 2 + (voicesPerGroup - 1))
    wAnchor = aLin / wNorm
    wComp   = 1 / wNorm
else
    wAnchor = 1
    wComp   = 1
endif

vWeight# = zero#(nV)
for j from 1 to nV
    if vAnchor#[j] = 1
        wIn = wAnchor
    else
        wIn = wComp
    endif
    vWeight#[j] = 10 ^ (netDb#[vGroup#[j]] / 20) * wIn
endfor

# ============================================================
# TIMING — entries, micro-delays, natural and output durations
# ============================================================

vStart#   = zero#(nV)
vNatural# = zero#(nV)
vEnd#     = zero#(nV)
entry#    = zero#(nG)
for n from 1 to nG
    entry#[n] = (n - 1) * entry_spacing_pct / 100 * winDur
endfor
naturalEnd = winDur
longestVoice = 0
for j from 1 to nV
    n = vGroup#[j]
    k = vIdx#[j]
    vStart#[j]   = entry#[n] + ((n - 1) + (k - 1) / voicesPerGroup) * micro_delay_ms / 1000
    vNatural#[j] = winDur / vRate#[j]
    vEnd#[j]     = vStart#[j] + vNatural#[j]
    if vEnd#[j] > naturalEnd
        naturalEnd = vEnd#[j]
    endif
    if vNatural#[j] > longestVoice
        longestVoice = vNatural#[j]
    endif
endfor

releasePad = 0.05
if duration = 1
    outDur = naturalEnd + releasePad
    if outDur > max_output_s
        exitScript: "Natural duration would be " + fixed$(outDur, 1) + " s (deepest voice "
            ... + "plays the " + fixed$(winDur, 2) + " s window " + fixed$(longestVoice / winDur, 1)
            ... + " times slower), above Max_output_s = " + fixed$(max_output_s, 0) + " s."
            ... + newline$ + "Use Fixed length, a shorter source window (Advanced), fewer or "
            ... + "higher undertones, or raise Max_output_s."
    endif
else
    outDur = fixed_duration_s
endif

# Rendered span of each voice (Fixed length may cut voices).
vRendered# = zero#(nV)
cutCount = 0
for j from 1 to nV
    rr = outDur - vStart#[j]
    if rr > vNatural#[j]
        rr = vNatural#[j]
    endif
    if rr < 0
        rr = 0
    endif
    vRendered#[j] = rr
    if rr < vNatural#[j] - 1e-6
        cutCount += 1
    endif
endfor

# Memory estimate: stereo bed + transient stereo copies for measurement
# + the longest voice in flight (pre- and post-resampling).
longestRendered = max(vRendered#)
memMB = 8 * origFs * (4 * outDur + 2.5 * longestRendered + 3 * winDur) / 1e6

# ============================================================
# NAMES
# ============================================================

presetName$ = "Custom"
if preset = 2
    presetName$ = "PureHarmonic"
elsif preset = 3
    presetName$ = "StretchedCloud"
elsif preset = 4
    presetName$ = "CompressedCluster"
elsif preset = 5
    presetName$ = "BassSpectral"
elsif preset = 6
    presetName$ = "SpectralHaze"
elsif preset = 7
    presetName$ = "DarkUndertow"
elsif preset = 8
    presetName$ = "MicrotonalDense"
elsif preset = 9
    presetName$ = "DeviatedHarmonicField"
elsif preset = 10
    presetName$ = "DeepPolyphonic"
elsif preset = 11
    presetName$ = "MicrotonalCloud"
elsif preset = 12
    presetName$ = "ExpandingField"
endif

gainCurveName$ = "Flat"
if gain_curve = 2
    gainCurveName$ = "Linear"
elsif gain_curve = 3
    gainCurveName$ = "Exponential"
elsif gain_curve = 4
    gainCurveName$ = "Gaussian"
elsif gain_curve = 5
    gainCurveName$ = "Inverse"
endif

seriesModeName$ = "Integer"
if series_mode = 2
    seriesModeName$ = "Odd"
elsif series_mode = 3
    seriesModeName$ = "Even"
elsif series_mode = 4
    seriesModeName$ = "Custom[" + custom_denominators$ + "]"
elsif series_mode = 5
    seriesModeName$ = "Geometric"
endif

monitorName$ = "Undertones only"
if monitorMode = 2
    monitorName$ = "Original + Undertones"
elsif monitorMode = 3
    monitorName$ = "Original only"
endif

spectralName$ = "Natural"
if spectral_balance = 2
    spectralName$ = "Warm"
elsif spectral_balance = 3
    spectralName$ = "Dark"
elsif spectral_balance = 4
    spectralName$ = "Adaptive"
elsif spectral_balance = 5
    spectralName$ = "Fixed LP " + fixed$(lowpass_Hz, 0) + " Hz"
endif

spatialName$ = "Arc"
if spatial_layout = 2
    spatialName$ = "Balanced clusters"
endif

synthName$ = "Pure"
if synthesis = 2
    synthName$ = "Deviated"
endif

durName$ = "Natural"
if duration = 2
    durName$ = "Fixed " + fixed$(outDur, 2) + " s"
endif

# ============================================================
# SPECTRAL BALANCE — per-voice filter settings (output-domain Hz)
# ============================================================
# Filters are applied to the source window BEFORE transposition, at
# frequencies divided by the playback rate. Transposition is an exact
# time scaling, so this is the same filter as applying it afterwards,
# at a fraction of the cost for long, slow voices.

hpHz = 30
hpSmooth = 20
vLp#  = zero#(nV)
vLpS# = zero#(nV)
vBand# = zero#(nV)
for j from 1 to nV
    band = origFs / 2 * vRate#[j]
    vBand#[j] = band
    lp = 0
    lps = 0
    if spectral_balance = 2
        lp = 4500
        lps = 2000
    elsif spectral_balance = 3
        lp = 1800
        lps = 800
    elsif spectral_balance = 4
        # Halfway (on a log axis) between the voice's own bandwidth and
        # 2.5 kHz, applied only where the voice reaches above 2.5 kHz.
        if band > 2500
            lp = sqrt(2500 * band)
            lps = 0.35 * lp
        endif
    elsif spectral_balance = 5
        lp = lowpass_Hz
        lps = 100
    endif
    # A low-pass at or above the voice's own bandwidth does nothing.
    if lp >= band * 0.98
        lp = 0
        lps = 0
    endif
    vLp#[j]  = lp
    vLpS#[j] = lps
endfor

# ============================================================
# SPATIAL PLAN
# ============================================================

spreadLin = stereo_spread_pct / 100
groupPos# = zero#(nG)
groupEnergy# = zero#(nG)
for n from 1 to nG
    groupEnergy#[n] = 10 ^ (netDb#[n] / 10) * (winDur / anchorRate#[n])
endfor

if spatial_layout = 1 or nG = 1
    for n from 1 to nG
        if nG = 1
            rawNorm = 0.5
        else
            rawNorm = (n - 1) / (nG - 1)
        endif
        groupPos#[n] = (rawNorm - 0.5) * 2 * spreadLin
    endfor
else
    # Order groups by register: the deepest groups take the inner slots,
    # so low material stays near the centre (better mono compatibility,
    # no deep group pinned to one side).
    gOrd# = zero#(nG)
    used# = zero#(nG)
    for r from 1 to nG
        best = 0
        bestC = 1e9
        for n from 1 to nG
            if used#[n] = 0 and anchorCents#[n] < bestC
                bestC = anchorCents#[n]
                best = n
            endif
        endfor
        gOrd#[r] = best
        used#[best] = 1
    endfor
    # Symmetric slots, filled inner to outer. Within each pair, the group
    # with more predicted energy (level x natural duration) goes to the
    # side that currently carries less, keeping L and R balanced.
    slotStep = 2 * spreadLin / (nG - 1)
    cumL = 0
    cumR = 0
    r = 1
    if nG mod 2 = 1
        groupPos#[gOrd#[1]] = 0
        r = 2
        mag = slotStep
    else
        mag = slotStep / 2
    endif
    while r <= nG
        gA = gOrd#[r]
        if r + 1 <= nG
            gB = gOrd#[r + 1]
            if groupEnergy#[gB] > groupEnergy#[gA]
                gTmp = gA
                gA = gB
                gB = gTmp
            endif
        else
            gB = 0
        endif
        if cumL <= cumR
            groupPos#[gA] = -mag
            cumL += groupEnergy#[gA]
            if gB > 0
                groupPos#[gB] = mag
                cumR += groupEnergy#[gB]
            endif
        else
            groupPos#[gA] = mag
            cumR += groupEnergy#[gA]
            if gB > 0
                groupPos#[gB] = -mag
                cumL += groupEnergy#[gB]
            endif
        endif
        r += 2
        mag += slotStep
    endwhile
endif

vPos# = zero#(nV)
vGainL# = zero#(nV)
vGainR# = zero#(nV)
halfCluster = cluster_width_pct / 100
for j from 1 to nV
    off = 0
    if dReq > 0
        off = vDev#[j] / dReq * halfCluster
    endif
    pp = groupPos#[vGroup#[j]] + off
    if pp < -1
        pp = -1
    endif
    if pp > 1
        pp = 1
    endif
    vPos#[j] = pp
    ang = (pp + 1) / 2 * pi / 2
    vGainL#[j] = cos(ang)
    vGainR#[j] = sin(ang)
endfor

# ============================================================
# INFO HEADER
# ============================================================

clearinfo
writeInfoLine:  "=================================================="
appendInfoLine: "  Undertone Field v", utVersion$
appendInfoLine: "=================================================="
appendInfoLine: ""
chanDesc$ = "mono"
if nCh = 2
    chanDesc$ = "stereo"
elsif nCh > 2
    chanDesc$ = string$(nCh) + " channels (dry folded to mono)"
endif
appendInfoLine: "Source     : ", srcName$, "  (", fixed$(origDur, 3), " s, ", chanDesc$, ", ",
    ... origFs, " Hz)"
if cutStart = 1 or cutEnd = 1
    appendInfoLine: "Window     : ", fixed$(winStart, 3), " - ", fixed$(winEnd, 3), " s  (",
        ... fixed$(winDur, 3), " s, 5 ms edge fades at the cut)"
else
    appendInfoLine: "Window     : whole sound (", fixed$(winDur, 3), " s)"
endif
appendInfoLine: "Preset     : ", presetName$
appendInfoLine: "Synthesis  : ", synthName$, "  (", nG, " undertone(s) x ", voicesPerGroup,
    ... " voice(s) = ", nV, " voices)"
appendInfoLine: "Series     : ", seriesModeName$, "   stretch ", fixed$(stretch_factor, 3)
if synthesis = 2
    appendInfoLine: "Deviation  : +/-", fixed$(deviation_cents, 1), " cents   anchor emphasis ",
        ... fixed$(anchor_emphasis_dB, 1), " dB   group order ",
        ... if keep_groups_in_order then "kept" else "free" fi
    appendInfoLine: "Seed       : ", seedUsed, "  (", seedNote$, "; enter it to reproduce this run)"
endif
appendInfoLine: "Gain curve : ", gainCurveName$, "  (depth ", fixed$(rolloff_dB, 1),
    ... " dB)   low-register comp ", fixed$(low_register_comp_dB, 1), " dB/oct"
appendInfoLine: "Monitor    : ", monitorName$
appendInfoLine: "Levels     : dry ", fixed$(dry_level_dB, 1), " dB, undertones ",
    ... fixed$(undertone_level_dB, 1), " dB  (relative to the source window's RMS)"
appendInfoLine: "Duration   : ", durName$
appendInfoLine: "Spectral   : ", spectralName$, "  (+ 30 Hz subsonic guard on every voice)"
appendInfoLine: "Space      : ", spatialName$, ", spread ", fixed$(stereo_spread_pct, 0),
    ... " %, cluster width ", fixed$(cluster_width_pct, 0), " %"
if entry_spacing_pct > 0
    appendInfoLine: "Entries    : every ", fixed$(entry_spacing_pct, 0), " % of the window (",
        ... fixed$(entry_spacing_pct / 100 * winDur, 2), " s)"
endif
appendInfoLine: "Output     : ", fixed$(outDur, 2), " s stereo; estimated peak memory ",
    ... fixed$(memMB, 0), " MB"
appendInfoLine: ""
if rateClampCount > 0
    appendInfoLine: "NOTE: ", rateClampCount, " anchor(s) raised to the lowest usable rate (",
        ... fixed$(minRate, 5), ", a 100 Hz reinterpreted clock)."
endif
for n from 1 to nG
    if devLimited#[n] = 1
        appendInfoLine: "NOTE: undertone ", n, " deviation limited to ",
            ... fixed$(devLo#[n], 1), " .. +", fixed$(devHi#[n], 1), " cents (",
            ... devLimit$[n], ")."
    endif
endfor
if compReversals > 0
    appendInfoLine: "NOTE: low-register compensation reverses the ", gainCurveName$,
        ... " curve between undertones", compRev$, "."
endif

# ============================================================
# SOURCE PREPARATION
# ============================================================

renderClock = stopwatch

selectObject: srcID
dryWin = Extract part: srcXmin + winStart, srcXmin + winEnd, "rectangular", 1, "no"
Rename: "UT_dry"
winDur = Get total duration
if cutStart = 1
    Formula: "if x < 0.005 then self * (0.5 - 0.5 * cos(pi * x / 0.005)) else self fi"
endif
if cutEnd = 1
    Formula: "if x > " + fixed$(winDur - 0.005, 9) + " then self * (0.5 - 0.5 * cos(pi * ("
        ... + fixed$(winDur, 9) + " - x) / 0.005)) else self fi"
endif

dryCh = nCh
if nCh > 2
    tmpD = Convert to mono
    removeObject: dryWin
    dryWin = tmpD
    dryCh = 1
endif

# Mono material for the undertones, with a cancellation guard.
monoNote$ = ""
selectObject: dryWin
if dryCh = 2
    utSrc = Convert to mono
    rmsMono = Get root-mean-square: 0, 0
    selectObject: dryWin
    tmpC = Extract one channel: 1
    rmsC1 = Get root-mean-square: 0, 0
    selectObject: dryWin
    tmpC2 = Extract one channel: 2
    rmsC2 = Get root-mean-square: 0, 0
    if rmsMono = undefined
        rmsMono = 0
    endif
    if rmsC1 = undefined
        rmsC1 = 0
    endif
    if rmsC2 = undefined
        rmsC2 = 0
    endif
    meanCh = sqrt((rmsC1 ^ 2 + rmsC2 ^ 2) / 2)
    if meanCh > 0 and rmsMono < 0.25 * meanCh
        removeObject: utSrc
        if rmsC1 >= rmsC2
            utSrc = tmpC
            removeObject: tmpC2
            monoNote$ = "left channel (the L+R mix cancels by "
        else
            utSrc = tmpC2
            removeObject: tmpC
            monoNote$ = "right channel (the L+R mix cancels by "
        endif
        monoNote$ = monoNote$ + fixed$(20 * log10(meanCh / max(rmsMono, 1e-12)), 1) + " dB)"
    else
        removeObject: tmpC, tmpC2
    endif
    srcRef = sqrt(rmsC1 ^ 2 + rmsC2 ^ 2)
    dryChanGain = 1
else
    utSrc = Copy: "UT_src"
    srcRef = Get root-mean-square: 0, 0
    if srcRef = undefined
        srcRef = 0
    endif
    dryChanGain = 1 / sqrt(2)
endif
selectObject: utSrc
Rename: "UT_src"

if srcRef < 1e-7
    removeObject: dryWin, utSrc
    exitScript: "The source window is silent (RMS below -140 dB); nothing to transpose."
endif
srcRefDb = 20 * log10(srcRef)

if monoNote$ <> ""
    appendInfoLine: "NOTE: undertones built from the ", monoNote$, "."
endif

# ============================================================
# UNDERTONE RENDERING
# ============================================================

appendInfoLine: ""
appendInfoLine: "Rendering ", nV, " voice(s)..."

bed = Create Sound from formula: "UT_bed", 2, 0, outDur, origFs, "0"

vRawDb#  = zero#(nV)
vNormDb# = zero#(nV)
vLevelLin# = zero#(nV)
normClampCount = 0
normMaxLin = 10 ^ (18 / 20)
normMinLin = 10 ^ (-18 / 20)

for j from 1 to nV
    rate = vRate#[j]

    # 1. Filter in the source domain (frequencies divided by the rate).
    selectObject: utSrc
    hpSrc = hpHz / rate
    if hpSrc < origFs / 2 - 50
        vf = Filter (pass Hann band): hpSrc, 0, hpSmooth / rate
    else
        vf = Copy: "UT_v"
    endif
    if vLp#[j] > 0
        lpSrc = vLp#[j] / rate
        if lpSrc < origFs / 2 - 10
            selectObject: vf
            vf2 = Filter (pass Hann band): 0, lpSrc, vLpS#[j] / rate
            removeObject: vf
            vf = vf2
        endif
    endif

    # 2. Level of the whole voice. Time-stretching keeps the RMS, so this
    #    is the RMS of the complete natural voice even when it is cut.
    selectObject: vf
    rawRms = Get root-mean-square: 0, 0
    if rawRms = undefined
        rawRms = 0
    endif
    normK = 1
    if normalise_layers = 1 and rawRms > 1e-9
        normK = srcRef / rawRms
        if normK > normMaxLin
            normK = normMaxLin
            normClampCount += 1
        elsif normK < normMinLin
            normK = normMinLin
            normClampCount += 1
        endif
    endif
    if rawRms > 1e-12
        vRawDb#[j] = 20 * log10(rawRms / srcRef)
    else
        vRawDb#[j] = -120
    endif
    vNormDb#[j] = 20 * log10(normK)
    vLevelLin#[j] = vWeight#[j] * normK * rawRms / srcRef

    if vRendered#[j] > 0
        # 3. Only the part of the window that sounds before the end.
        needSrc = vRendered#[j] * rate
        if needSrc < winDur - 1e-9
            selectObject: vf
            needSrc = min(winDur, needSrc + 0.05)
            vp = Extract part: 0, needSrc, "rectangular", 1, "no"
            removeObject: vf
            vf = vp
        endif

        # 4. Reinterpret the clock and resample: one constant rate.
        selectObject: vf
        Override sampling frequency: origFs * rate
        voice = Resample: origFs, 50
        removeObject: vf

        # 5. 10 ms declick at the natural end of a complete voice.
        selectObject: voice
        vT1 = Get start time
        vT2 = Get end time
        if vRendered#[j] >= vNatural#[j] - 1e-6 and vT2 - vT1 > 0.05
            Formula: "if x > " + fixed$(vT2 - 0.01, 9) + " then self * (0.5 + 0.5 * cos(pi * (x - "
                ... + fixed$(vT2 - 0.01, 9) + ") / 0.01)) else self fi"
        endif
        nvs = Get number of samples

        # 6. Add to the bed with pan and weight (the field gain comes later).
        offS = round(vStart#[j] * origFs)
        gTot = vWeight#[j] * normK
        gL$ = fixed$(gTot * vGainL#[j], 10)
        gR$ = fixed$(gTot * vGainR#[j], 10)
        tFrom = offS / origFs
        tTo = (offS + nvs) / origFs
        if tTo > outDur
            tTo = outDur
        endif
        if tFrom < tTo
            selectObject: bed
            Formula (part): tFrom, tTo, 1, 2, "self + object[" + string$(voice) + ", 1, col - "
                ... + string$(offS) + "] * (if row = 1 then " + gL$ + " else " + gR$ + " fi)"
        endif
        removeObject: voice
    else
        removeObject: vf
    endif
endfor
removeObject: utSrc

# ============================================================
# BED LEVEL — one gain for the whole undertone field
# ============================================================

# The bed is levelled by MEASUREMENT over the level span: the span the
# dry window occupies or, with staggered entries, the first window-length
# after the last group has entered (the complete field). Measured rather
# than predicted, because voices that start together reinforce each other
# (most strongly in Deviated mode, where companions are near-unisons).

levelA = 0
levelB = min(winDur, outDur)
if entry_spacing_pct > 0 and nG > 1
    levelA = entry#[nG]
    levelB = min(levelA + winDur, outDur)
endif
if levelB - levelA < 0.05
    levelA = 0
    levelB = outDur
endif

predSum = 0
for j from 1 to nV
    predSum += vLevelLin#[j] ^ 2
endfor
if predSum > 1e-24
    predDb = 10 * log10(predSum)
else
    predDb = -240
endif

selectObject: bed
spanRms = Get root-mean-square: levelA, levelB
if spanRms = undefined
    spanRms = 0
endif
spanTot = spanRms * sqrt(2)
fieldClamped = 0
if spanTot > 1e-12
    measuredRawDb = 20 * log10(spanTot) - srcRefDb
    fieldDb = undertone_level_dB - measuredRawDb
    if fieldDb > 60
        fieldDb = 60
        fieldClamped = 1
    elsif fieldDb < -60
        fieldDb = -60
        fieldClamped = 1
    endif
else
    measuredRawDb = -240
    fieldDb = 0
    fieldClamped = 1
endif
fieldLin = 10 ^ (fieldDb / 20)
selectObject: bed
Multiply: fieldLin
# Positive = voices reinforce each other in the level span.
coherenceDb = measuredRawDb - predDb

vFinalDb# = zero#(nV)
for j from 1 to nV
    if vLevelLin#[j] > 1e-12
        vFinalDb#[j] = 20 * log10(vLevelLin#[j] * fieldLin)
    else
        vFinalDb#[j] = -120
    endif
endfor
groupDb# = zero#(nG)
groupPowAll = 0
for n from 1 to nG
    gp = 0
    for j from 1 to nV
        if vGroup#[j] = n
            gp += (vLevelLin#[j] * fieldLin) ^ 2
        endif
    endfor
    groupPowAll += gp
    if gp > 1e-24
        groupDb#[n] = 10 * log10(gp)
    else
        groupDb#[n] = -120
    endif
endfor
# Requested group levels: the requested balance, carrying the same total
# power as the achieved groups. Bar vs tick differences therefore show
# only where the balance was not achieved (RMS-matching limits).
for n from 1 to nG
    reqGroupDb#[n] = 10 * log10(max(groupPowAll, 1e-24)) + netDb#[n] - 10 * log10(netPowSum)
endfor

# ---- Bed measurements (undertones only, before peak safety) ----
@stereoStats: bed, levelA, levelB
bedLevelDb = stereoStats.totDb - srcRefDb
coreEnd = min(winDur, outDur)
@stereoStats: bed, 0, coreEnd
bedCoreDb = stereoStats.totDb - srcRefDb
@stereoStats: bed, 0, 0
bedAllDb  = stereoStats.totDb - srcRefDb
bedPeak   = stereoStats.peak
bedBalDb  = stereoStats.balDb
bedCorr   = stereoStats.corr
bedFoldDb = stereoStats.foldDb

# ---- Dry measurements (dry only) ----
dryLin = 10 ^ (dry_level_dB / 20)
selectObject: dryWin
dryPeak = Get absolute extremum: 0, 0, "None"
dryPeak = dryPeak * dryLin * dryChanGain
dryDb = dry_level_dB
dryEnd = min(winDur, outDur)

# ---- Combined (dry + undertones) over the dry span ----
selectObject: bed
combCore = Extract part: 0, dryEnd, "rectangular", 1, "no"
@addDry: combCore
@stereoStats: combCore, 0, 0
combCorePow = stereoStats.totRms ^ 2
combPeak = stereoStats.peak
removeObject: combCore
# Outside the dry span the combination is the bed alone.
selectObject: bed
if outDur > dryEnd + 1 / origFs
    restRms = Get root-mean-square: dryEnd, outDur
    restPeak = Get absolute extremum: dryEnd, outDur, "None"
    if restRms = undefined
        restRms = 0
    endif
    restPow = 2 * restRms ^ 2
else
    restPow = 0
    restPeak = 0
endif
combAllPow = (combCorePow * dryEnd + restPow * (outDur - dryEnd)) / outDur
combCoreDb = 10 * log10(max(combCorePow, 1e-24)) - srcRefDb
combAllDb  = 10 * log10(max(combAllPow, 1e-24)) - srcRefDb
combPeak = max(combPeak, restPeak)

# ---- Visualization material from the bed, before it is mixed ----
if draw_visualization = 1
    selectObject: bed
    vizBedMono = Convert to mono
    ltasBed = To Ltas: 10
    removeObject: vizBedMono
endif

# ============================================================
# OUTPUT ASSEMBLY according to Monitor
# ============================================================

if monitorMode = 1
    outID = bed
elsif monitorMode = 2
    outID = bed
    @addDry: outID
else
    removeObject: bed
    outID = Create Sound from formula: "UT_out", 2, 0, outDur, origFs, "0"
    @addDry: outID
endif

# Fixed length: intentional cut with a raised-cosine fade.
fadeApplied = 0
if duration = 2 and fade_s > 0.001
    selectObject: outID
    fadeT0 = outDur - fade_s
    Formula (part): fadeT0, outDur, 1, 2, "self * (0.5 + 0.5 * cos(pi * (x - "
        ... + fixed$(fadeT0, 9) + ") / " + fixed$(fade_s, 9) + "))"
    fadeApplied = 1
endif

# ---- Peak safety: one global gain, measured and reported ----
selectObject: outID
outPeakPre = Get absolute extremum: 0, 0, "None"
ceilingLin = 0.99
safetyDb = 0
if outPeakPre > ceilingLin
    safetyLin = ceilingLin / outPeakPre
    Multiply: safetyLin
    safetyDb = 20 * log10(safetyLin)
else
    safetyLin = 1
endif

@stereoStats: outID, 0, 0
outAllDb  = stereoStats.totDb - srcRefDb
outPeak   = stereoStats.peak
outBalDb  = stereoStats.balDb
outCorr   = stereoStats.corr
outFoldDb = stereoStats.foldDb
@stereoStats: outID, 0, coreEnd
outCoreDb = stereoStats.totDb - srcRefDb

renderTime = stopwatch

outputName$ = srcName$ + "_undertones_" + presetName$
selectObject: outID
Rename: outputName$
mixDur = Get total duration

# ============================================================
# REPORT
# ============================================================

bedInOut = 1
if monitorMode = 3
    bedInOut = 0
endif
dryInOut = 1
if monitorMode = 1
    dryInOut = 0
endif

appendInfoLine: ""
appendInfoLine: "UNDERTONE ANCHORS (mathematical series)"
appendInfoLine: "grp  anchor    rate      cents   curve  comp   balance  requested  achieved  dev range (cents)   entry s   pan"
appendInfoLine: "----------------------------------------------------------------------------------------------------------------"
for n from 1 to nG
    @padL: "1/" + fixed$(denom#[n], 3), 9
    c1$ = padL$
    @fmt: anchorRate#[n], 5
    @padL: fmt$, 9
    c2$ = padL$
    @fmt: anchorCents#[n], 1
    @padL: fmt$, 8
    c3$ = padL$
    @fmt: curveDb#[n], 1
    @padL: fmt$, 7
    c4$ = padL$
    @fmt: compDb#[n], 1
    @padL: fmt$, 6
    c5$ = padL$
    @fmt: netDb#[n], 1
    @padL: fmt$, 8
    c6$ = padL$
    @fmt: reqGroupDb#[n], 1
    @padL: fmt$, 10
    c7$ = padL$
    @fmt: groupDb#[n], 1
    @padL: fmt$, 9
    c8$ = padL$
    if dReq > 0
        @fmt: devLo#[n], 1
        devA$ = fmt$
        @fmt: devHi#[n], 1
        devB$ = devA$ + " .. +" + fmt$
        @padL: devB$, 19
    else
        @padL: "-", 19
    endif
    c9$ = padL$
    @fmt: entry#[n], 2
    @padL: fmt$, 9
    c10$ = padL$
    @fmt: groupPos#[n], 2
    @padL: fmt$, 7
    c11$ = padL$
    appendInfoLine: " ", n, c1$, c2$, c3$, c4$, c5$, c6$, c7$, c8$, c9$, c10$, c11$
endfor
appendInfoLine: "(dB: curve/comp/balance are relative. requested/achieved: each group's voices summed in"
appendInfoLine: " power, vs source RMS, before peak safety. pan: -1 = left, 0 = centre, +1 = right)"

appendInfoLine: ""
appendInfoLine: "VOICES (each keeps one constant playback rate)"
appendInfoLine: "  v grp  role    rate      1/rate    cents   dev c   natural s  start s  rendered s  cut %   LP Hz   norm dB  level dB   pan"
appendInfoLine: "--------------------------------------------------------------------------------------------------------------------------"
for j from 1 to nV
    @padL: string$(j), 3
    c0$ = padL$
    @padL: string$(vGroup#[j]), 4
    c1$ = padL$
    if vAnchor#[j] = 1
        role$ = "  anchor"
    else
        role$ = "  compan"
    endif
    @fmt: vRate#[j], 5
    @padL: fmt$, 8
    c2$ = padL$
    @fmt: 1 / vRate#[j], 4
    @padL: fmt$, 10
    c3$ = padL$
    @fmt: vCents#[j], 1
    @padL: fmt$, 9
    c4$ = padL$
    @fmt: vDev#[j], 1
    @padL: fmt$, 8
    c5$ = padL$
    @fmt: vNatural#[j], 2
    @padL: fmt$, 11
    c6$ = padL$
    @fmt: vStart#[j], 4
    @padL: fmt$, 9
    c7$ = padL$
    @fmt: vRendered#[j], 2
    @padL: fmt$, 12
    c8$ = padL$
    @fmt: 100 * (1 - vRendered#[j] / vNatural#[j]), 1
    @padL: fmt$, 7
    c9$ = padL$
    if vLp#[j] > 0
        @fmt: vLp#[j], 0
        @padL: fmt$, 8
    else
        @padL: "none", 8
    endif
    c10$ = padL$
    @fmt: vNormDb#[j], 1
    @padL: fmt$, 9
    c11$ = padL$
    @fmt: vFinalDb#[j] + safetyDb * bedInOut, 1
    @padL: fmt$, 10
    c12$ = padL$
    @fmt: vPos#[j], 2
    @padL: fmt$, 7
    c13$ = padL$
    appendInfoLine: c0$, c1$, role$, c2$, c3$, c4$, c5$, c6$, c7$, c8$, c9$, c10$, c11$, c12$, c13$
endfor
appendInfoLine: "(dev c = deviation from the anchor; norm dB = RMS match; level dB = voice RMS while it plays,"
appendInfoLine: " vs source RMS, after field gain", if bedInOut then " and peak safety)" else ")" fi
appendInfoLine: "All ", nV, " voices are below the source: highest voice at ", fixed$(highestCents, 1),
    ... " cents (", fixed$(2 ^ (highestCents / 1200), 4), " x source rate)."
if normClampCount > 0
    appendInfoLine: "NOTE: RMS matching hit its +/-18 dB limit on ", normClampCount,
        ... " voice(s); their level is lower or higher than requested (see level dB)."
endif
if normalise_layers = 0
    appendInfoLine: "NOTE: RMS matching is off: voice levels follow what the filters leave."
endif
if fieldClamped = 1
    appendInfoLine: "NOTE: the field gain hit its +/-60 dB limit; the undertone level target was NOT reached."
endif

appendInfoLine: ""
appendInfoLine: "DURATION"
appendInfoLine: "  natural end of the field : ", fixed$(round((naturalEnd) * 100) / 100 + 0, 2), " s  (longest voice ",
    ... fixed$(round((longestVoice) * 100) / 100 + 0, 2), " s)"
appendInfoLine: "  rendered output          : ", fixed$(round((mixDur) * 100) / 100 + 0, 2), " s  (", durName$, ")"
if cutCount > 0
    appendInfoLine: "  CUT on purpose           : ", cutCount, " of ", nV,
        ... " voice(s) end after the fixed length; see 'cut %'. Fade ", fixed$(round((fade_s) * 100) / 100 + 0, 2), " s."
else
    appendInfoLine: "  every voice plays to its natural end"
endif
appendInfoLine: "  render time              : ", fixed$(round((renderTime) * 10) / 10 + 0, 1), " s"

appendInfoLine: ""
appendInfoLine: "LEVELS (dB relative to the source window RMS; peaks in dBFS)"
appendInfoLine: "  dry only        : RMS ", fixed$(round((dryDb) * 10) / 10 + 0, 1), " dB   peak ",
    ... fixed$(round((20 * log10(max(dryPeak, 1e-9))) * 10) / 10 + 0, 1), " dBFS"
appendInfoLine: "  undertones only : RMS ", fixed$(round((bedLevelDb) * 10) / 10 + 0, 1), " dB over the level span (",
    ... fixed$(round((levelA) * 100) / 100 + 0, 2), " - ", fixed$(round((levelB) * 100) / 100 + 0, 2), " s; target ", fixed$(round((undertone_level_dB) * 10) / 10 + 0, 1),
    ... "),  ", fixed$(round((bedCoreDb) * 10) / 10 + 0, 1), " dB over the dry span,  ", fixed$(round((bedAllDb) * 10) / 10 + 0, 1),
    ... " dB over the whole output   peak ", fixed$(round((20 * log10(max(bedPeak, 1e-9))) * 10) / 10 + 0, 1), " dBFS"
@fmt: coherenceDb, 1
appendInfoLine: "                    voices reinforce each other by ", fmt$,
    ... " dB in the level span (0 = independent; they start together)"
appendInfoLine: "  combined        : RMS ", fixed$(round((combCoreDb) * 10) / 10 + 0, 1), " dB over the window span, ",
    ... fixed$(round((combAllDb) * 10) / 10 + 0, 1), " dB over the whole output   peak ",
    ... fixed$(round((20 * log10(max(combPeak, 1e-9))) * 10) / 10 + 0, 1), " dBFS"
appendInfoLine: "  delivered (", monitorName$, "): RMS ", fixed$(round((outAllDb) * 10) / 10 + 0, 1), " dB   peak ",
    ... fixed$(round((20 * log10(max(outPeak, 1e-9))) * 10) / 10 + 0, 1), " dBFS"
if safetyDb < 0
    appendInfoLine: "  PEAK SAFETY      : whole output lowered by ", fixed$(round((-safetyDb) * 100) / 100 + 0, 2),
        ... " dB (peak was ", fixed$(round((outPeakPre) * 1000) / 1000 + 0, 3), ", ceiling 0.99)"
    if dryInOut = 1 and dryPeak > ceilingLin
        appendInfoLine: "                     cause: the dry signal alone exceeds the ceiling (lower Dry_level_dB)."
    elsif bedInOut = 1 and bedPeak > ceilingLin
        appendInfoLine: "                     cause: the undertones alone peak at ", fixed$(round((bedPeak) * 1000) / 1000 + 0, 3),
            ... "; lowering Undertone_level_dB by ",
            ... fixed$(round((20 * log10(bedPeak / ceilingLin)) * 10) / 10 + 0, 1), " dB avoids it."
    else
        appendInfoLine: "                     cause: dry and undertone peaks coincide; neither alone exceeds the ceiling."
    endif
else
    appendInfoLine: "  peak safety      : none needed (no gain change)"
endif

appendInfoLine: ""
appendInfoLine: "STEREO"
appendInfoLine: "  undertones : L/R balance ", fixed$(round((bedBalDb) * 10) / 10 + 0, 1), " dB   correlation ",
    ... fixed$(round((bedCorr) * 100) / 100 + 0, 2), "   mono fold-down ", fixed$(round((bedFoldDb) * 10) / 10 + 0, 1), " dB"
appendInfoLine: "  delivered  : L/R balance ", fixed$(round((outBalDb) * 10) / 10 + 0, 1), " dB   correlation ",
    ... fixed$(round((outCorr) * 100) / 100 + 0, 2), "   mono fold-down ", fixed$(round((outFoldDb) * 10) / 10 + 0, 1), " dB"
appendInfoLine: "  (fold-down: 0 dB = identical channels, about -3 dB = unrelated channels,"
appendInfoLine: "   below -6 dB = cancellation in mono)"
if dryCh = 2
    appendInfoLine: "  dry signal keeps the source's own left and right channels"
else
    appendInfoLine: "  dry signal is mono, centred (equal power)"
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization = 1
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    @vizSafe: srcName$
    srcLabel$ = vizSafe$
    @vizSafe: outputName$
    outLabel$ = vizSafe$

    bgCol$    = "{0.970, 0.970, 0.970}"
    gridCol$  = "{0.860, 0.860, 0.880}"
    axisCol$  = "{0.200, 0.200, 0.280}"
    dimCol$   = "{0.480, 0.480, 0.550}"
    inCol$    = "{0.420, 0.480, 0.580}"
    outCol$   = "{0.180, 0.280, 0.640}"
    bedCol$   = "{0.850, 0.450, 0.120}"
    leftCol$  = "{0.250, 0.420, 0.720}"
    rightCol$ = "{0.820, 0.450, 0.180}"
    srcCol$   = "{0.900, 0.650, 0.150}"
    markCol$  = "{0.800, 0.400, 0.200}"
    panelBg$  = "{0.940, 0.940, 0.940}"

    vL = 0.60
    vR = 7.70
    halfL1 = 0.60
    halfR1 = 3.85
    halfL2 = 4.45
    halfR2 = 7.70
    railX  = -0.035
    pageHeight = 7.55

    # Group colours
    for n from 1 to nG
        cFrac = (n - 1) / max(nG - 1, 1)
        gCol$[n] = "{" + fixed$(0.85 - cFrac * 0.70, 3) + ", " + fixed$(0.30 - cFrac * 0.05, 3)
            ... + ", " + fixed$(0.15 + cFrac * 0.50, 3) + "}"
        gDark$[n] = "{" + fixed$((0.85 - cFrac * 0.70) * 0.55, 3) + ", "
            ... + fixed$((0.30 - cFrac * 0.05) * 0.55, 3) + ", "
            ... + fixed$((0.15 + cFrac * 0.50) * 0.55, 3) + "}"
    endfor

    # Mono source on the output time axis (unity gain reference)
    selectObject: dryWin
    if dryCh = 2
        vizMonoIn = Convert to mono
    else
        vizMonoIn = Copy: "UT_vizsrc"
    endif
    vizIn = Create Sound from formula: "UT_vizin", 1, 0, mixDur, origFs, "0"
    Formula: "object[" + string$(vizMonoIn) + ", 1, col]"
    removeObject: vizMonoIn

    selectObject: outID
    vizMonoOut = Convert to mono
    selectObject: outID
    vizL = Extract one channel: 1
    selectObject: outID
    vizR = Extract one channel: 2

    selectObject: vizIn
    srcPeakViz = Get absolute extremum: 0, 0, "None"
    ampBase = max(srcPeakViz, outPeak)
    if ampBase < 0.001
        ampBase = 0.001
    endif
    ampMax = ampBase * 1.15

    tickRaw = mixDur / 8
    tickPow = 10 ^ floor(log10(tickRaw))
    tickNorm = tickRaw / tickPow
    if tickNorm < 1.5
        tickStep = 1 * tickPow
    elsif tickNorm < 3.5
        tickStep = 2 * tickPow
    elsif tickNorm < 7.5
        tickStep = 5 * tickPow
    else
        tickStep = 10 * tickPow
    endif

    Erase all
    Line width: 1
    Solid line

    # ---------------- TITLE ----------------
    Font size: 13
    Select inner viewport: vL, vR, 0.10, 0.30
    Axes: 0, 1, 0, 1
    Colour: "{0.100, 0.100, 0.160}"
    Text: 0.5, "centre", 0.5, "half", "##Undertone Field v" + utVersion$ + "##"

    Font size: 7
    Select inner viewport: vL, vR, 0.32, 0.46
    Axes: 0, 1, 0, 1
    Colour: "{0.350, 0.350, 0.450}"
    sub$ = "[" + presetName$ + "]  " + srcLabel$ + "   " + synthName$ + " "
        ... + string$(nG) + " x " + string$(voicesPerGroup) + " voices   "
        ... + seriesModeName$ + "   " + gainCurveName$ + "   " + spectralName$
        ... + "   " + spatialName$ + "   " + monitorName$
    if synthesis = 2
        sub$ = sub$ + "   +/-" + fixed$(deviation_cents, 0) + " c  seed " + string$(seedUsed)
    endif
    Text: 0.5, "centre", 0.5, "half", sub$

    # ---------------- PANEL 1: source window ----------------
    p1T = 0.66
    p1B = 1.06
    Font size: 6
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: bgCol$, 0, mixDur, -ampMax, ampMax
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    selectObject: vizIn
    Colour: inCol$
    Draw: 0, mixDur, -ampMax, ampMax, "no", "Curve"
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: gridCol$
    Draw line: 0, 0, mixDur, 0
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, 1, 0, 1
    Colour: dimCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Source"
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: "Black"
    Draw inner box
    Select inner viewport: vL, vR, p1T, p1B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Source window## — " + srcLabel$ + " (" + fixed$(winDur, 2)
        ... + " s, unity gain, on the output time axis)"

    # ---------------- PANEL 2: output L / R ----------------
    p2aT = 1.34
    p2aB = 1.70
    p2bT = 1.72
    p2bB = 2.08
    Font size: 6
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: bgCol$, 0, mixDur, -ampMax, ampMax
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    selectObject: vizL
    Colour: leftCol$
    Draw: 0, mixDur, -ampMax, ampMax, "no", "Curve"
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: gridCol$
    Draw line: 0, 0, mixDur, 0
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, 1, 0, 1
    Colour: leftCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "L"
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: "Black"
    Draw inner box
    Select inner viewport: vL, vR, p2aT, p2aB
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Output## — " + outLabel$ + "   (" + monitorName$ + ")"

    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    Paint rectangle: bgCol$, 0, mixDur, -ampMax, ampMax
    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    selectObject: vizR
    Colour: rightCol$
    Draw: 0, mixDur, -ampMax, ampMax, "no", "Curve"
    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: gridCol$
    Draw line: 0, 0, mixDur, 0
    if fadeApplied = 1
        Colour: markCol$
        Dashed line
        Draw line: mixDur - fade_s, -ampMax, mixDur - fade_s, ampMax
        Solid line
    endif
    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, 1, 0, 1
    Colour: rightCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "R"
    Select inner viewport: vL, vR, p2bT, p2bB
    Axes: 0, mixDur, -ampMax, ampMax
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tickStep, "yes", "yes", "no"

    # ---------------- PANEL 3: voice map ----------------
    p3T = 2.52
    p3B = 3.62
    minC = min(vCents#)
    yTop = 150
    yBot = minC - 150
    Font size: 6
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, mixDur, yBot, yTop
    Paint rectangle: bgCol$, 0, mixDur, yBot, yTop

    # Anchor guide lines
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, mixDur, yBot, yTop
    Colour: gridCol$
    Dotted line
    for n from 1 to nG
        Draw line: 0, anchorCents#[n], mixDur, anchorCents#[n]
    endfor
    Solid line

    # Source (dry) at 0 cents
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, mixDur, yBot, yTop
    Colour: srcCol$
    Line width: 3
    Draw line: 0, 0, min(winDur, mixDur), 0
    Line width: 1

    # Fixed-length fade start
    if fadeApplied = 1
        Select inner viewport: vL, vR, p3T, p3B
        Axes: 0, mixDur, yBot, yTop
        Colour: markCol$
        Dashed line
        Draw line: mixDur - fade_s, yBot, mixDur - fade_s, yTop
        Solid line
    endif

    # Voices: one line each, start to natural end
    for j from 1 to nV
        Select inner viewport: vL, vR, p3T, p3B
        Axes: 0, mixDur, yBot, yTop
        Colour: gCol$[vGroup#[j]]
        if vAnchor#[j] = 1
            Line width: 2.5
        else
            Line width: 1.2
        endif
        t2v = min(vEnd#[j], mixDur)
        if vStart#[j] < mixDur
            Draw line: vStart#[j], vCents#[j], t2v, vCents#[j]
        endif
        if vEnd#[j] > mixDur + 1e-6
            Colour: markCol$
            Line width: 1.5
            Draw line: mixDur - mixDur * 0.006, vCents#[j] - 40, mixDur, vCents#[j]
            Draw line: mixDur - mixDur * 0.006, vCents#[j] + 40, mixDur, vCents#[j]
        endif
    endfor
    Line width: 1

    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, mixDur, yBot, yTop
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    One mark left: 0, "no", "yes", "no", "src"
    lastMark = 1e9
    for n from 1 to nG
        if abs(anchorCents#[n] - lastMark) > (yTop - yBot) * 0.07
            Select inner viewport: vL, vR, p3T, p3B
            Axes: 0, mixDur, yBot, yTop
            Colour: gDark$[n]
            dLab = denom#[n]
            if abs(dLab - round(dLab)) < 0.005
                lab$ = "1/" + string$(round(dLab))
            else
                lab$ = "1/" + fixed$(dLab, 2)
            endif
            One mark left: anchorCents#[n], "no", "yes", "no", lab$
            lastMark = anchorCents#[n]
        endif
    endfor
    Select inner viewport: vL, vR, p3T, p3B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Voice map## — one line per voice: height = pitch below the source, "
        ... + "length = natural duration (thick = anchor, arrow = cut)"

    # ---------------- PANEL 4: spectral balance ----------------
    p4T = 4.02
    p4B = 4.92
    selectObject: vizIn
    ltasIn = To Ltas: 10
    selectObject: vizMonoOut
    ltasOut = To Ltas: 10

    selectObject: dryWin
    if dryCh = 2
        tmpS = Convert to mono
        vizSpec = To Spectrum: "yes"
        removeObject: tmpS
    else
        vizSpec = To Spectrum: "yes"
    endif
    cogIn = Get centre of gravity: 2
    removeObject: vizSpec
    if cogIn = undefined or cogIn <= 0
        cogIn = 500
    endif

    fLo = 20
    fHi = min(origFs / 2, 12000)
    logLo = log10(fLo)
    logHi = log10(fHi)
    nSpecPts = 240
    lf# = zero#(nSpecPts)
    yIn# = zero#(nSpecPts)
    yOut# = zero#(nSpecPts)
    yBed# = zero#(nSpecPts)
    bedShift = 0
    if bedInOut = 1
        bedShift = safetyDb
    endif
    specTop = -400
    for k from 1 to nSpecPts
        lfk = logLo + (k - 1) / (nSpecPts - 1) * (logHi - logLo)
        lf#[k] = lfk
        fq = 10 ^ lfk
        selectObject: ltasIn
        vi = Get value at frequency: fq, "Cubic"
        selectObject: ltasOut
        vo = Get value at frequency: fq, "Cubic"
        selectObject: ltasBed
        vb = Get value at frequency: fq, "Cubic"
        if vi = undefined
            vi = -200
        endif
        if vo = undefined
            vo = -200
        endif
        if vb = undefined
            vb = -200
        else
            vb = vb + bedShift
        endif
        yIn#[k] = vi
        yOut#[k] = vo
        yBed#[k] = vb
        specTop = max(specTop, vi, vo, vb)
    endfor
    removeObject: ltasIn, ltasOut, ltasBed
    gMax = 10 * ceiling(specTop / 10) + 5
    gMin = gMax - 75
    for k from 1 to nSpecPts
        yIn#[k] = min(max(yIn#[k], gMin), gMax)
        yOut#[k] = min(max(yOut#[k], gMin), gMax)
        yBed#[k] = min(max(yBed#[k], gMin), gMax)
    endfor

    Font size: 6
    Select inner viewport: vL, vR, p4T, p4B
    Axes: logLo, logHi, gMin, gMax
    Paint rectangle: bgCol$, logLo, logHi, gMin, gMax

    Select inner viewport: vL, vR, p4T, p4B
    Axes: logLo, logHi, gMin, gMax
    Colour: inCol$
    Line width: 1
    for k from 2 to nSpecPts
        Draw line: lf#[k - 1], yIn#[k - 1], lf#[k], yIn#[k]
    endfor
    Colour: bedCol$
    Line width: 1.2
    for k from 2 to nSpecPts
        Draw line: lf#[k - 1], yBed#[k - 1], lf#[k], yBed#[k]
    endfor
    if monitorMode = 2
        Colour: outCol$
        Line width: 1.5
        for k from 2 to nSpecPts
            Draw line: lf#[k - 1], yOut#[k - 1], lf#[k], yOut#[k]
        endfor
    endif
    Line width: 1

    # Register stubs: the source centroid transposed to each anchor
    Select inner viewport: vL, vR, p4T, p4B
    Axes: logLo, logHi, gMin, gMax
    stubTop = gMin + (gMax - gMin) * 0.14
    Line width: 2
    for n from 1 to nG
        fPart = cogIn * anchorRate#[n]
        if fPart > fLo and fPart < fHi
            Colour: gCol$[n]
            Draw line: log10(fPart), gMin, log10(fPart), stubTop
        endif
    endfor
    if cogIn > fLo and cogIn < fHi
        Colour: srcCol$
        Draw line: log10(cogIn), gMin, log10(cogIn), stubTop
    endif
    Line width: 1

    Select inner viewport: vL, vR, p4T, p4B
    Axes: logLo, logHi, gMin, gMax
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 15, "yes", "yes", "no"
    Select inner viewport: vL, vR, p4T, p4B
    Axes: logLo, logHi, gMin, gMax
    One mark bottom: log10(50), "no", "yes", "no", "50"
    One mark bottom: log10(100), "no", "yes", "no", "100"
    One mark bottom: log10(200), "no", "yes", "no", "200"
    One mark bottom: log10(500), "no", "yes", "no", "500"
    One mark bottom: log10(1000), "no", "yes", "no", "1k"
    One mark bottom: log10(2000), "no", "yes", "no", "2k"
    if fHi >= 5000
        One mark bottom: log10(5000), "no", "yes", "no", "5k"
    endif
    if fHi >= 10000
        One mark bottom: log10(10000), "no", "yes", "no", "10k"
    endif

    Select inner viewport: vL, vR, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: inCol$
    Text: 0.70, "left", 0.93, "half", "source"
    Select inner viewport: vL, vR, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: bedCol$
    Text: 0.78, "left", 0.93, "half", "undertones"
    if monitorMode = 2
        Select inner viewport: vL, vR, p4T, p4B
        Axes: 0, 1, 0, 1
        Colour: outCol$
        Text: 0.89, "left", 0.93, "half", "output"
    endif
    Select inner viewport: vL, vR, p4T, p4B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Spectral balance## — long-term spectrum over the whole output, dB vs Hz (log);"
        ... + " stubs = source centroid transposed to each undertone"

    # ---------------- PANEL 5: group levels ----------------
    p5T = 5.36
    p5B = 6.36
    dbLo = min(0, dryDb, bedLevelDb + bedShift)
    dbHi = max(3, dryDb + 3, bedLevelDb + bedShift + 3)
    for n from 1 to nG
        gv = groupDb#[n] + bedShift
        dbLo = min(dbLo, gv, reqGroupDb#[n])
        dbHi = max(dbHi, gv + 3, reqGroupDb#[n] + 3)
    endfor
    dbLo = 5 * floor(dbLo / 5) - 3
    if dbLo < -60
        dbLo = -60
    endif
    dbHi = 5 * ceiling(dbHi / 5)
    dbTick = 10
    if dbHi - dbLo <= 25
        dbTick = 5
    endif
    rowTop = 0.35
    rowBot = nG + 0.65

    Select inner viewport: halfL1, halfR1, p5T, p5B
    Axes: dbLo, dbHi, rowBot, rowTop
    Paint rectangle: bgCol$, dbLo, dbHi, rowBot, rowTop
    for n from 1 to nG
        bv = min(max(groupDb#[n] + bedShift, dbLo), dbHi)
        Paint rectangle: gCol$[n], dbLo, bv, n - 0.32, n + 0.32
    endfor
    Colour: "{0.150, 0.150, 0.200}"
    Line width: 1.5
    for n from 1 to nG
        rv = reqGroupDb#[n]
        if rv >= dbLo and rv <= dbHi
            Draw line: rv, n - 0.36, rv, n + 0.36
        endif
    endfor
    Line width: 1
    # Reference lines: source, dry as delivered, whole bed
    Colour: srcCol$
    Dotted line
    Draw line: 0, rowBot, 0, rowTop
    if dryInOut = 1
        Colour: inCol$
        Dashed line
        Line width: 1.5
        dv = min(max(dryDb + safetyDb, dbLo), dbHi)
        Draw line: dv, rowBot, dv, rowTop
    endif
    Colour: bedCol$
    Dashed line
    Line width: 1.5
    bvTot = min(max(bedLevelDb + bedShift, dbLo), dbHi)
    Draw line: bvTot, rowBot, bvTot, rowTop
    Solid line
    Line width: 1

    Select inner viewport: halfL1, halfR1, p5T, p5B
    Axes: dbLo, dbHi, rowBot, rowTop
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, dbTick, "yes", "yes", "no"
    for n from 1 to nG
        Select inner viewport: halfL1, halfR1, p5T, p5B
        Axes: dbLo, dbHi, rowBot, rowTop
        Colour: "{1.000, 1.000, 1.000}"
        dLab = denom#[n]
        if abs(dLab - round(dLab)) < 0.005
            lab$ = "1/" + string$(round(dLab))
        else
            lab$ = "1/" + fixed$(dLab, 2)
        endif
        Text: dbLo + (dbHi - dbLo) * 0.02, "left", n, "half", lab$
        Select inner viewport: halfL1, halfR1, p5T, p5B
        Axes: dbLo, dbHi, rowBot, rowTop
        Colour: axisCol$
        bv = min(max(groupDb#[n] + bedShift, dbLo), dbHi)
        if bv > dbLo + (dbHi - dbLo) * 0.84
            Text: bv - (dbHi - dbLo) * 0.02, "right", n, "half", fixed$(groupDb#[n] + bedShift, 1)
        else
            Text: bv + (dbHi - dbLo) * 0.02, "left", n, "half", fixed$(groupDb#[n] + bedShift, 1)
        endif
    endfor
    Select inner viewport: halfL1, halfR1, p5T, p5B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Group levels## — dB vs source RMS (bar = achieved, tick = requested)"
    Select inner viewport: halfL1, halfR1, p5T, p5B
    Axes: 0, 1, 0, 1
    Colour: bedCol$
    Text: 0.985, "right", 0.06, "half", "-- undertones, measured"
    if dryInOut = 1
        Select inner viewport: halfL1, halfR1, p5T, p5B
        Axes: 0, 1, 0, 1
        Colour: inCol$
        Text: 0.985, "right", 0.16, "half", "-- dry"
    endif

    # ---------------- PANEL 6: stereo field ----------------
    Select inner viewport: halfL2, halfR2, p5T, p5B
    Axes: -1.35, 1.35, -0.20, 1.30
    Paint rectangle: bgCol$, -1.35, 1.35, -0.20, 1.30
    rInner = (-12 + 36) / 36
    nArcPts = 48
    Colour: "{0.720, 0.720, 0.780}"
    for ai from 2 to nArcPts
        a1 = (ai - 2) / (nArcPts - 1) * pi
        a2 = (ai - 1) / (nArcPts - 1) * pi
        Draw line: -cos(a1), sin(a1), -cos(a2), sin(a2)
    endfor
    Colour: "{0.840, 0.840, 0.880}"
    Dotted line
    for ai from 2 to nArcPts
        a1 = (ai - 2) / (nArcPts - 1) * pi
        a2 = (ai - 1) / (nArcPts - 1) * pi
        Draw line: -cos(a1) * rInner, sin(a1) * rInner, -cos(a2) * rInner, sin(a2) * rInner
    endfor
    Solid line
    Paint circle (mm): srcCol$, 0.0, 1.0, 1.6
    for j from 1 to nV
        aa = (vPos#[j] + 1) / 2 * pi
        rn = (vFinalDb#[j] + bedShift + 36) / 36
        rn = min(max(rn, 0.12), 1.22)
        xp = -cos(aa) * rn
        yp = sin(aa) * rn
        Colour: gCol$[vGroup#[j]]
        Line width: 1
        Draw line: 0, 0, xp, yp
        if vAnchor#[j] = 1
            Paint circle (mm): gCol$[vGroup#[j]], xp, yp, 1.5
        else
            Paint circle (mm): gCol$[vGroup#[j]], xp, yp, 0.9
        endif
    endfor
    Select inner viewport: halfL2, halfR2, p5T, p5B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: "Black"
    Draw inner box
    for n from 1 to nG
        Select inner viewport: halfL2, halfR2, p5T, p5B
        Axes: -1.35, 1.35, -0.20, 1.30
        for j from 1 to nV
            if vGroup#[j] = n and vAnchor#[j] = 1
                aa = (vPos#[j] + 1) / 2 * pi
                rn = min(max((vFinalDb#[j] + bedShift + 36) / 36, 0.12), 1.10) + 0.13
                labX = -cos(aa) * rn
                labY = sin(aa) * rn
                if abs(labX) < 0.16 and labY > 0.70
                    labX = labX - 0.18
                endif
                Colour: gDark$[n]
                Text: labX, "centre", labY, "half", string$(n)
            endif
        endfor
    endfor
    Select inner viewport: halfL2, halfR2, p5T, p5B
    Axes: -1.35, 1.35, -0.20, 1.30
    Colour: dimCol$
    Text: -1.30, "left", 0.09, "half", "L"
    Text: 1.30, "right", 0.09, "half", "R"
    Colour: srcCol$
    Text: 0, "centre", 1.14, "half", "src"
    Select inner viewport: halfL2, halfR2, p5T, p5B
    Axes: 0, 1, 0, 1
    Colour: dimCol$
    Text: 0.5, "centre", 0.05, "half", "L/R " + fixed$(bedBalDb, 1) + " dB   mono fold-down "
        ... + fixed$(bedFoldDb, 1) + " dB   (outer arc = source level)"
    Select inner viewport: halfL2, halfR2, p5T, p5B
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Stereo field## — one dot per voice: angle = pan, radius = level"

    # ---------------- SUMMARY ----------------
    sT = 6.78
    sB = 7.42
    Font size: 7
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Paint rectangle: panelBg$, 0, 1, 0, 1
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.83, "half", "##Summary##"
    peakLine$ = "none"
    if safetyDb < 0
        peakLine$ = fixed$(round((safetyDb) * 10) / 10 + 0, 1) + " dB on the whole output"
    endif
    cutLine$ = "every voice complete"
    if cutCount > 0
        cutLine$ = string$(cutCount) + " of " + string$(nV) + " voices cut (fade "
            ... + fixed$(round((fade_s) * 10) / 10 + 0, 1) + " s)"
    endif
    Font size: 6
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "{0.250, 0.250, 0.350}"
    Text: 0.012, "left", 0.58, "half",
        ... "Dry only " + fixed$(round((dryDb) * 10) / 10 + 0, 1) + " dB     undertones only "
        ... + fixed$(round((bedLevelDb) * 10) / 10 + 0, 1) + " dB (target " + fixed$(round((undertone_level_dB) * 10) / 10 + 0, 1)
        ... + ")     combined " + fixed$(round((combCoreDb) * 10) / 10 + 0, 1)
        ... + " dB over the dry span     (RMS vs source)     peak safety " + peakLine$
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "{0.250, 0.250, 0.350}"
    Text: 0.012, "left", 0.36, "half",
        ... "Output " + fixed$(round((mixDur) * 100) / 100 + 0, 2) + " s stereo, " + durName$ + ", " + cutLine$
        ... + "     natural end " + fixed$(round((naturalEnd) * 100) / 100 + 0, 2) + " s     peak "
        ... + fixed$(round((20 * log10(max(outPeak, 1e-9))) * 10) / 10 + 0, 1) + " dBFS"
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "{0.250, 0.250, 0.350}"
    Text: 0.012, "left", 0.14, "half",
        ... string$(nV) + " voices, all below the source (highest " + fixed$(round((highestCents) * 1) / 1 + 0, 0)
        ... + " cents)     rates " + fixed$(round((min(vRate#)) * 10000) / 10000 + 0, 4) + " - " + fixed$(round((max(vRate#)) * 10000) / 10000 + 0, 4)
        ... + "     full voice table in the Info window"
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    removeObject: vizIn, vizL, vizR, vizMonoOut
    Font size: 10
    Select outer viewport: 0, 8, 0, pageHeight
    Colour: "Black"
    Line width: 1
    Solid line
endif

removeObject: dryWin

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  COMPLETE: ", outputName$, "  (", fixed$(mixDur, 2), " s stereo, ", monitorName$, ")"
appendInfoLine: "=================================================="

selectObject: outID
if play_result = 1
    Play
endif

# ============================================================
# HELPERS
# ============================================================

# Adds the dry window to a stereo Sound starting at time 0, at the dry
# level, keeping a stereo source's own channels; mono is centred.
procedure addDry: .target
    .g$ = fixed$(dryLin * dryChanGain, 10)
    selectObject: .target
    .tEnd = Get end time
    .tTo = min(winDur, .tEnd)
    if dryCh = 2
        Formula (part): 0, .tTo, 1, 2, "self + object[" + string$(dryWin) + ", row, col] * " + .g$
    else
        Formula (part): 0, .tTo, 1, 2, "self + object[" + string$(dryWin) + ", 1, col] * " + .g$
    endif
endproc

# Level, balance and mono compatibility of a stereo Sound between t1 and
# t2 (0, 0 = all). totRms is the total power of both channels.
procedure stereoStats: .sid, .t1, .t2
    selectObject: .sid
    .peak = Get absolute extremum: .t1, .t2, "None"
    .cL = Extract one channel: 1
    .rmsL = Get root-mean-square: .t1, .t2
    selectObject: .sid
    .cR = Extract one channel: 2
    .rmsR = Get root-mean-square: .t1, .t2
    selectObject: .sid
    .cM = Convert to mono
    .rmsM = Get root-mean-square: .t1, .t2
    removeObject: .cL, .cR, .cM
    if .rmsL = undefined
        .rmsL = 0
    endif
    if .rmsR = undefined
        .rmsR = 0
    endif
    if .rmsM = undefined
        .rmsM = 0
    endif
    .totRms = sqrt(.rmsL ^ 2 + .rmsR ^ 2)
    .totDb = 20 * log10(max(.totRms, 1e-12))
    .meanSq = (.rmsL ^ 2 + .rmsR ^ 2) / 2
    if .rmsL > 1e-12 and .rmsR > 1e-12
        .corr = (2 * .rmsM ^ 2 - .meanSq) / (.rmsL * .rmsR)
        .balDb = 20 * log10(.rmsL / .rmsR)
    else
        .corr = 0
        .balDb = 0
    endif
    if .meanSq > 1e-24
        .foldDb = 20 * log10(max(.rmsM, 1e-12) / sqrt(.meanSq))
    else
        .foldDb = 0
    endif
endproc

# Rounded fixed-point text: no "0.000000008", no "-0", always d decimals.
procedure fmt: .v, .d
    .m = 10 ^ .d
    .r = round(.v * .m) / .m
    if abs(.r) < 0.5 / .m
        .r = 0
    endif
    fmt$ = fixed$(.r, .d)
    if .d > 0 and index(fmt$, ".") = 0
        fmt$ = fmt$ + "." + left$("000000", .d)
    endif
endproc

procedure padL: .s$, .w
    padL$ = .s$
    while length(padL$) < .w
        padL$ = " " + padL$
    endwhile
endproc

# Escape Picture-window markup in machine-generated names.
procedure vizSafe: .s$
    vizSafe$ = replace$(.s$, "#", "\# ", 0)
    vizSafe$ = replace$(vizSafe$, "%", "\% ", 0)
    vizSafe$ = replace$(vizSafe$, "^", "\^ ", 0)
    vizSafe$ = replace$(vizSafe$, "_", "\_ ", 0)
endproc
