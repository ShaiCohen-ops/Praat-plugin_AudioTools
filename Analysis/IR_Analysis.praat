# ============================================================
# Praat AudioTools - IR Analysis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Impulse-response analysis, preparation, and controlled creative sculpting.
#   The script measures a recorded IR, reports room-acoustic decay and clarity
#   descriptors, and can derive convolution-ready and compositional IR objects.
#   Measurement is always completed on the original selected Sound before any
#   preparation or artistic transformation is applied.
#
# Input:
#   One selected Sound containing a measured impulse response or impulse-like
#   room capture. Multichannel Sounds are analysed by a user-selected channel;
#   channel 0 explicitly requests a mono sum.
#
# Output:
#   - Acoustic report: EDT, T20, T30, C50, C80, D50, Ts, noise/truncation data
#   - Optional comparative octave-band results and Praat Table objects
#   - Optional Praat Picture visualization
#   - Optional <name>_IRprepared convolution-ready kernel
#   - Optional <name>_IRearly and <name>_IRlate decomposition
#   - Optional <name>_IRart creative IR
#   - Optional <dry>_through_<IR> convolution audition
#
# Processing summary:
#   Analysis     Lundeby noise/truncation, Chu compensation, Schroeder EDC,
#                regression-based EDT/T20/T30, clarity/definition/centre time
#   Preparation  direct-sound alignment or preserved timing, measured-tail
#                truncation, short final fade, optional early/late split
#   Creative     editable starting-point presets, early/late gain, tail-decay
#                shaping, spectral tilt, reverse late field, additional pre-delay
#   Audition     convolution with another open Sound, optional wet/dry RMS level
#                matching for preview only, wet/dry mix, attenuate-only protection
#
# Usage:
#   Select the impulse-response Sound in Praat and run this script.
#   Enable preparation, creative processing, audition, tables, or visualization
#   only as needed. Derived creative objects never alter the reported measurement.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v2.1 (2026):
#   - Added editable creative starting-point presets: Natural, Close / percussive,
#     Distant bloom, Dark resonance, Reverse bloom, plus Custom.
#   - Corrected reverse-late-tail ordering so reversal precedes complementary
#     boundary windowing and the new tail end receives an explicit fade-out.
#   - Added optional wet-to-dry RMS level matching for convolution audition;
#     matching affects the preview only and never changes prepared/creative IRs.
#
# Changelog v2.0 (2026):
#   - Added convolution-ready IR preparation and early/late decomposition.
#   - Added controlled creative IR sculpting and standalone creative IR output.
#   - Added direct convolution audition and optional research Table output.
#   - Added prepared-vs-sculpted visualization while preserving the analyser.
# ============================================================
#
# Technical / methodological notes
# ------------------------------------------------------------
# Impulse-response decay analysis, ISO 3382-1 style, entirely in Praat.
# No Python, no temporary files, no subprocess, so no Praat 7.0 trust gate.
#
# Select an impulse response Sound and run.
#
# Method
#   start point         first sample above -20 dB re peak (ISO 3382-1 A.1)
#   noise / truncation  Lundeby et al. (1995) iterative crosspoint
#   noise handling      Chu (1978): subtract the estimated noise energy
#                       from each block, then add the analytic integral of
#                       the fitted late decay beyond the truncation point
#   decay curve         Schroeder (1965) backward energy integration
#   EDT / T20 / T30     least squares over 0..-10, -5..-25, -5..-35 dB
#   C50 C80 D50 Ts      exact energy queries, not read off the block grid
#                       (Ts by sample-domain integration of (t-t0)*h^2)
#
# SCOPE OF THE ISO REFERENCE. The broadband procedure follows ISO 3382-1:
# start point, T20/T30 evaluation ranges, curvature, and the requirement
# that the decay stay clear of the noise floor. The OCTAVE BANDS DO NOT:
# they use Praat's zero-phase Hann band filter, which is not an IEC 61260
# octave filter and has no specified attenuation limits. Two consequences.
# Its stopband rejection is finite, so a band holding no real content
# returns leakage carrying another band's decay - caught here by the band
# level column and a -60 dB refusal. And it is acausal, so its pre-ringing
# moves a little energy earlier in time; measured at under 0.001 % of band
# energy ahead of an impulse, which is negligible for RT but is a bias on
# per-band C50 in the direction of higher clarity. Band figures are for
# comparative and compositional work, not for standards-conformant
# reporting. Each filter's own decay is measured at run time and a band RT
# not clear of it by a factor of ten is refused.
#
# HEADLESS / BATCH USE. The preparation, sculpting and audition stages ask
# for their settings through beginPause dialogs. In headless builds from
# Praat 6.4.63 onward beginPause TERMINATES the script silently - exit code
# 0, no message, no output. (6.3.09 and 6.4.06 skip it and carry on.) So a
# batch run must leave those three boxes unticked: analysis, octave bands,
# report, table and figure all work headless on every version tested
# (6.3.09, 6.4.06, 6.4.63, 7.0) and give identical numbers. Interactive use
# is unaffected. To drive the creative stages from a batch script, set the
# defaults in the block below and delete the beginPause/endPause lines.
#
# v2.0 adds a second identity on top of the analyser: a measured response
# can be PREPARED as a convolution kernel and SCULPTED into compositional
# material. Those stages never feed back into the measurement - every
# acoustic figure reported below refers to the original selected Sound.
# --------------------------------------------------------------------------

form: "IR Analysis"
    comment: "Select an impulse response Sound, then run."
    comment: "Channel to analyse - 0 sums all channels to mono."
    integer: "Channel", "1"
    optionmenu: "Bands", 2
        option: "Broadband only"
        option: "Broadband + octave bands"
    optionmenu: "Truncation", 1
        option: "Lundeby (recommended)"
        option: "None - integrate to end"
    boolean: "Prepare_convolution_ready_IR", 0
    boolean: "Creative_IR_processing", 0
    boolean: "Audition_on_another_Sound", 0
    boolean: "Draw_visualization", 1
    comment: "Play auditions the last Sound this run produced."
    boolean: "Play", 0
    boolean: "Advanced_settings", 0
endform

# --------------------------------------------------------------------------
# Every value a beginPause stage collects is given its default HERE, before
# the pause. In batch or headless use beginPause runs but never assigns its
# fields, so without this the script would fail on an unknown variable.
# --------------------------------------------------------------------------
adv_lowBand = 125
adv_highBand = 8000
adv_blockMs = 1.0
adv_compensate = 1
adv_startRule = 1
adv_trimTailDb = 5
adv_table = 0

prep_align = 1
prep_fadeMs = 5
split_mode = 2
split_customMs = 80
xfadeMs = 4
make_early_late = 0

cre_earlyGain = 0
cre_lateGain = 0
cre_decayShape = 0
cre_tilt = 0
cre_reverse = 0
cre_predelayMs = 0
cre_preset = 1
presetName$ = "Custom"

aud_dryName$ = ""
aud_wet = 100
aud_useCreative = 1
aud_levelMatch = 1
audMatchDb = 0

# --------------------------------------------------------------------------
# Input identification happens before any dialog, so a wrong selection is
# reported immediately and the audition stage has the object list it needs.
# --------------------------------------------------------------------------
if numberOfSelected ("Sound") <> 1
    exitScript: "Select exactly one Sound (the impulse response) and run again."
endif
inSound = selected ("Sound")
inName$ = selected$ ("Sound")

# Candidate dry Sounds for the audition stage. Gathered now, before the run
# creates any objects of its own. selected() and selected$() both read the
# current selection, so both are collected in a single pass - reselecting
# inside the loop would collapse the selection and lose the rest.
select all
nOpen = numberOfSelected ("Sound")
openIds# = zero# (nOpen)
openNames$# = empty$# (nOpen)
for i to nOpen
    openIds# [i] = selected ("Sound", i)
    openNames$# [i] = selected$ ("Sound", i)
endfor
for i to nOpen
    if openIds# [i] <> inSound
        if aud_dryName$ = ""
            aud_dryName$ = openNames$# [i]
        endif
    endif
endfor
selectObject: inSound

adv_lowBand = 125
adv_highBand = 8000
adv_blockMs = 1.0
adv_compensate = 1
adv_startRule = 1
adv_trimTailDb = 5

if advanced_settings
    lowest_band = adv_lowBand
    highest_band = adv_highBand
    block_length_ms = adv_blockMs
    noise_subtraction_and_tail_compensation = adv_compensate
    start_point = adv_startRule
    tail_margin_dB = adv_trimTailDb
    results_table = adv_table
    beginPause: "IR Analysis - details"
        comment: "Octave band range (nominal centre frequencies, Hz)"
        positive: "Lowest_band", string$ (adv_lowBand)
        positive: "Highest_band", string$ (adv_highBand)
        comment: "Decay curve"
        positive: "Block_length_ms", string$ (adv_blockMs)
        boolean: "Noise_subtraction_and_tail_compensation", adv_compensate
        choice: "Start_point", adv_startRule
            option: "ISO 3382-1  (-20 dB re peak)"
            option: "Peak sample"
            option: "Start of the Sound"
        comment: "Prepared IR ends this far above the noise floor (dB)"
        positive: "Tail_margin_dB", string$ (adv_trimTailDb)
        boolean: "Results_table", adv_table
    endPause: "Continue", 1
    adv_lowBand = lowest_band
    adv_highBand = highest_band
    adv_blockMs = block_length_ms
    adv_compensate = noise_subtraction_and_tail_compensation
    adv_startRule = start_point
    adv_trimTailDb = tail_margin_dB
    adv_table = results_table
endif

# --------------------------------------------------------------------------
# Stage 2: IR preparation. Only shown when something downstream needs it.
# --------------------------------------------------------------------------
needPrep = 0
if prepare_convolution_ready_IR
    needPrep = 1
endif
if creative_IR_processing
    needPrep = 1
endif
if audition_on_another_Sound
    needPrep = 1
endif

if needPrep = 1
    start_alignment = prep_align
    final_fade_ms = prep_fadeMs
    early_late_split = split_mode
    custom_split_ms = split_customMs
    crossfade_ms = xfadeMs
    create_early_and_late_Sounds = make_early_late
    beginPause: "IR preparation"
        comment: "The measured Sound is analysed first and is never modified."
        choice: "Start_alignment", prep_align
            option: "Align direct sound to zero"
            option: "Preserve measured timing"
        positive: "Final_fade_ms", string$ (prep_fadeMs)
        comment: "Early / late boundary, measured from the direct sound"
        choice: "Early_late_split", split_mode
            option: "50 ms"
            option: "80 ms"
            option: "Custom"
        positive: "Custom_split_ms", string$ (split_customMs)
        positive: "Crossfade_ms", string$ (xfadeMs)
        boolean: "Create_early_and_late_Sounds", make_early_late
    endPause: "Continue", 1
    prep_align = start_alignment
    prep_fadeMs = final_fade_ms
    split_mode = early_late_split
    split_customMs = custom_split_ms
    xfadeMs = crossfade_ms
    make_early_late = create_early_and_late_Sounds
endif

# --------------------------------------------------------------------------
# Stage 3: creative sculpting. Artistic controls only - nothing here feeds
# back into the acoustic measurement.
# --------------------------------------------------------------------------
if creative_IR_processing
    # A preset only SEEDS the six controls; the next dialog shows the values
    # it chose and they stay editable. Nothing is hidden behind a name, and
    # the names describe an action on the recorded space, not a space.
    creative_starting_point = cre_preset
    beginPause: "Creative starting point"
        comment: "A preset just fills in the controls on the next page."
        optionmenu: "Creative_starting_point", cre_preset
            option: "Custom - keep current values"
            option: "Natural - no change"
            option: "Close / percussive"
            option: "Distant bloom"
            option: "Dark resonance"
            option: "Reverse bloom"
    endPause: "Continue", 1
    cre_preset = creative_starting_point
    @applyPreset: cre_preset

    early_gain_dB = cre_earlyGain
    late_gain_dB = cre_lateGain
    tail_decay_shaping_dB_per_s = cre_decayShape
    spectral_tilt_dB_per_octave = cre_tilt
    reverse_late_tail = cre_reverse
    additional_predelay_ms = cre_predelayMs
    beginPause: "Creative IR sculpting"
        comment: "Artistic shaping. Does not change any reported measurement."
        real: "Early_gain_dB", string$ (cre_earlyGain)
        real: "Late_gain_dB", string$ (cre_lateGain)
        real: "Tail_decay_shaping_dB_per_s", string$ (cre_decayShape)
        real: "Spectral_tilt_dB_per_octave", string$ (cre_tilt)
        boolean: "Reverse_late_tail", cre_reverse
        real: "Additional_predelay_ms", string$ (cre_predelayMs)
    endPause: "Continue", 1
    cre_earlyGain = early_gain_dB
    cre_lateGain = late_gain_dB
    cre_decayShape = tail_decay_shaping_dB_per_s
    cre_tilt = spectral_tilt_dB_per_octave
    cre_reverse = reverse_late_tail
    cre_predelayMs = additional_predelay_ms
endif

# --------------------------------------------------------------------------
# Stage 4: audition source. The dry Sound is named rather than picked from a
# menu so the choice survives batch use; the default is the first other
# Sound already open.
# --------------------------------------------------------------------------
if audition_on_another_Sound
    if nOpen < 2
        exitScript: "Audition needs a second Sound. Open the dry Sound you " +
        ... "want to hear through this IR, then run again."
    endif
    dry_Sound_name$ = aud_dryName$
    wet_percent = aud_wet
    use_creative_IR_if_available = aud_useCreative
    match_wet_level_to_dry = aud_levelMatch
    beginPause: "Audition"
        comment: "Dry Sound to hear through this IR:"
        sentence: "Dry_Sound_name", aud_dryName$
        positive: "Wet_percent", string$ (aud_wet)
        boolean: "Use_creative_IR_if_available", aud_useCreative
        comment: "An IR from a clap carries the recording's gain, so raw wet"
        comment: "level is arbitrary. Matching affects the preview only."
        boolean: "Match_wet_level_to_dry", aud_levelMatch
    endPause: "Continue", 1
    aud_dryName$ = dry_Sound_name$
    aud_wet = wet_percent
    aud_useCreative = use_creative_IR_if_available
    aud_levelMatch = match_wet_level_to_dry
endif

# ---- validate the creative ranges before any audio is touched ----
if cre_earlyGain < -24 or cre_earlyGain > 12
    exitScript: "Early gain must be between -24 and +12 dB."
endif
if cre_lateGain < -24 or cre_lateGain > 12
    exitScript: "Late gain must be between -24 and +12 dB."
endif
if cre_decayShape < -30 or cre_decayShape > 30
    exitScript: "Tail decay shaping must be between -30 and +30 dB/s."
endif
if cre_tilt < -6 or cre_tilt > 6
    exitScript: "Spectral tilt must be between -6 and +6 dB/octave. Even -3 " +
    ... "is a large change of colour; the control is a tilt, not an equaliser."
endif
if cre_predelayMs < 0 or cre_predelayMs > 2000
    exitScript: "Additional pre-delay must be between 0 and 2000 ms."
endif
if aud_wet <= 0 or aud_wet > 100
    exitScript: "Wet percentage must be between 0 and 100."
endif
if xfadeMs <= 0 or xfadeMs > 200
    exitScript: "Crossfade must be between 0 and 200 ms."
endif
if prep_fadeMs <= 0 or prep_fadeMs > 500
    exitScript: "Final fade must be between 0 and 500 ms."
endif

# ==========================================================================
#  1.  input
# ==========================================================================
selectObject: inSound
srate = Get sampling frequency
nchan = Get number of channels
totalDur = Get total duration

if totalDur < 0.05
    exitScript: "This Sound is only " + fixed$ (1000 * totalDur, 1) +
    ... " ms long. An impulse response needs at least about 50 ms to analyse."
endif

if channel < 0 or channel > nchan
    exitScript: "Channel " + fixed$ (channel, 0) + " does not exist. This " +
    ... "Sound has " + fixed$ (nchan, 0) + " channel(s); use 0 to sum to mono."
endif

# Channels of a real IR are separate measurements. Summing them can comb
# out whole frequency regions, so a channel is chosen, not averaged by
# default. When the user does ask for a sum, the loss is measured.
cancelDb = undefined
selectObject: inSound
xminIn = Get start time
xmaxIn = Get end time
eMulti = Get energy: xminIn, xmaxIn
selectObject: inSound
if nchan = 1
    work = Copy: "work"
    chanNote$ = "1 (mono)"
elsif channel = 0
    work = Convert to mono
    chanNote$ = "sum of " + fixed$ (nchan, 0) + " channels"
else
    work = Extract one channel: channel
    chanNote$ = "channel " + fixed$ (channel, 0) + " of " + fixed$ (nchan, 0)
endif
Shift times to: "start time", 0
workDur = Get total duration
if nchan > 1 and channel = 0
    eMono = Get energy: 0, workDur
    # Get energy on a multichannel Sound returns the MEAN across channels,
    # so a coherent sum matches it and a cancelling one falls below it
    if eMulti > 0 and eMono > 0
        cancelDb = 10 * log10 (eMono / eMulti)
    endif
endif
pkHi = Get maximum: 0, workDur, "None"
pkLo = Get minimum: 0, workDur, "None"
absPeak = max (abs (pkHi), abs (pkLo))
if absPeak <= 0
    removeObject: work
    exitScript: "This Sound is silent - there is nothing to analyse."
endif
totalEnergy = Get energy: 0, workDur
if totalEnergy <= 0
    removeObject: work
    exitScript: "This Sound carries no energy."
endif

# ==========================================================================
#  2.  small helpers
# ==========================================================================
procedure niceStep: .span, .target
    ns_v = 1
    if .span > 0 and .target > 0
        .raw = .span / .target
        .ex = floor (log10 (.raw))
        .m = .raw / 10 ^ .ex
        if .m < 1.5
            .m = 1
        elsif .m < 3.5
            .m = 2
        elsif .m < 7.5
            .m = 5
        else
            .m = 10
        endif
        ns_v = .m * 10 ^ .ex
    endif
endproc

procedure fmt: .v, .d
    if .v = undefined
        fmt$ = "n/a"
    else
        fmt$ = fixed$ (.v, .d)
        # fixed$ special-cases zero and very small values, ignoring the
        # requested precision, which breaks column alignment
        if .v = 0
            fmt$ = fixed$ (0, 0)
            if .d > 0
                fmt$ = fmt$ + "."
                for .z to .d
                    fmt$ = fmt$ + "0"
                endfor
            endif
        endif
    endif
endproc

# Praat has no pad primitive and right$ truncates instead of padding
# a refused value carries no unit
procedure withUnit: .v$, .u$
    if .v$ = "n/a"
        withUnit$ = .v$
    else
        withUnit$ = .v$ + .u$
    endif
endproc

procedure applyPreset: .p
    if .p = 2
        presetName$ = "Natural"
        cre_earlyGain = 0
        cre_lateGain = 0
        cre_decayShape = 0
        cre_tilt = 0
        cre_reverse = 0
        cre_predelayMs = 0
    elsif .p = 3
        presetName$ = "Close / percussive"
        cre_earlyGain = 3
        cre_lateGain = -8
        cre_decayShape = -8
        cre_tilt = 1
        cre_reverse = 0
        cre_predelayMs = 0
    elsif .p = 4
        presetName$ = "Distant bloom"
        cre_earlyGain = -6
        cre_lateGain = 5
        cre_decayShape = 5
        cre_tilt = -1
        cre_reverse = 0
        cre_predelayMs = 40
    elsif .p = 5
        presetName$ = "Dark resonance"
        cre_earlyGain = -3
        cre_lateGain = 6
        cre_decayShape = 3
        cre_tilt = -3
        cre_reverse = 0
        cre_predelayMs = 20
    elsif .p = 6
        presetName$ = "Reverse bloom"
        cre_earlyGain = -4
        cre_lateGain = 5
        cre_decayShape = 2
        cre_tilt = -1
        cre_reverse = 1
        cre_predelayMs = 30
    endif
endproc

procedure validity: .ok
    if .ok = 1
        validity$ = "yes"
    else
        validity$ = "refused"
    endif
endproc

procedure pad: .s$, .w
    pad$ = .s$
    while length (pad$) < .w
        pad$ = " " + pad$
    endwhile
endproc

# ==========================================================================
#  3.  block energies
# ==========================================================================
g_dt = adv_blockMs / 1000
if g_dt < 4 / srate
    g_dt = 4 / srate
endif

procedure blockEnergies: .id, .dur
    selectObject: .id
    g_n = floor (.dur / g_dt)
    if g_n < 8
        g_n = 0
    else
        g_be# = zero# (g_n)
        g_bt# = zero# (g_n)
        for .i to g_n
            .t1 = (.i - 1) * g_dt
            .t2 = .t1 + g_dt
            .en = Get energy: .t1, .t2
            g_be# [.i] = .en
            g_bt# [.i] = .t1 + g_dt / 2
        endfor
    endif
endproc

procedure blockLevels
    if g_n >= 1
        g_bl# = zero# (g_n)
        .mx = 0
        for .i to g_n
            if g_be# [.i] > .mx
                .mx = g_be# [.i]
            endif
        endfor
        .floorE = .mx * 1e-12
        if .floorE <= 0
            .floorE = 1e-30
        endif
        for .i to g_n
            .v = g_be# [.i]
            if .v < .floorE
                .v = .floorE
            endif
            g_bl# [.i] = 10 * log10 (.v / g_dt)
        endfor
    endif
endproc

# ==========================================================================
#  4.  start point
# ==========================================================================
procedure findStart: .id, .dur, .rule
    selectObject: .id
    .vp = Get maximum: 0, .dur, "None"
    .vm = Get minimum: 0, .dur, "None"
    if abs (.vm) > abs (.vp)
        .tpk = Get time of minimum: 0, .dur, "None"
        .amp = abs (.vm)
    else
        .tpk = Get time of maximum: 0, .dur, "None"
        .amp = abs (.vp)
    endif
    if .rule = 3
        startT = 0
    elsif .rule = 2
        startT = .tpk
    else
        .thr = .amp * 10 ^ (-20 / 20)
        .rawIpk = Get sample number from time: .tpk
        .ipk = round (.rawIpk)
        if .ipk < 1
            .ipk = 1
        endif
        .maxd = 0
        for .i to g_n
            if g_be# [.i] > .maxd
                .maxd = g_be# [.i]
            endif
        endfor
        .lim = .maxd * 10 ^ (-40 / 10)
        .first = 1
        .got = 0
        for .i to g_n
            if .got = 0
                if g_be# [.i] >= .lim
                    .first = .i
                    .got = 1
                endif
            endif
        endfor
        .from = round ((.first - 1) * g_dt * srate) - round (g_dt * srate)
        if .from < 1
            .from = 1
        endif
        .found = 0
        .k = .from
        .go = 1
        while .go = 1
            if .k > .ipk
                .go = 0
            else
                .v = Get value at sample number: 1, .k
                if abs (.v) >= .thr
                    .found = .k
                    .go = 0
                endif
                .k = .k + 1
            endif
        endwhile
        if .found = 0
            .found = .ipk
        endif
        startT = Get time from sample number: .found
        if startT < 0
            startT = 0
        endif
    endif
endproc

# ==========================================================================
#  5.  least squares on the block levels
# ==========================================================================
procedure regress: .a, .b
    reg_ok = 0
    reg_slope = undefined
    reg_icpt = undefined
    reg_r2 = undefined
    if .b > .a + 1
        .n = 0
        .sx = 0
        .sy = 0
        .sxx = 0
        .sxy = 0
        .syy = 0
        for .i from .a to .b
            .x = g_bt# [.i]
            .y = g_sm# [.i]
            .n = .n + 1
            .sx = .sx + .x
            .sy = .sy + .y
            .sxx = .sxx + .x * .x
            .sxy = .sxy + .x * .y
            .syy = .syy + .y * .y
        endfor
        .den = .n * .sxx - .sx * .sx
        if .den <> 0
            reg_slope = (.n * .sxy - .sx * .sy) / .den
            reg_icpt = (.sy - reg_slope * .sx) / .n
            .vy = .n * .syy - .sy * .sy
            if .vy > 0
                .r = (.n * .sxy - .sx * .sy) / sqrt (.den * .vy)
                reg_r2 = .r * .r
            endif
            reg_ok = 1
        endif
    endif
endproc

# moving average over .win blocks, then to dB. Lundeby's adaptive averaging
# interval: crossing searches must not be driven by single-block noise.
procedure smoothLevels: .win
    if .win < 1
        .win = 1
    endif
    g_sm# = zero# (g_n)
    .h = floor (.win / 2)
    .mx = 0
    for .i to g_n
        if g_be# [.i] > .mx
            .mx = g_be# [.i]
        endif
    endfor
    .floorE = .mx * 1e-12
    if .floorE <= 0
        .floorE = 1e-30
    endif
    # running window sum: O(n), not O(n * window)
    .a = 1
    .b = 0
    .s = 0
    for .i to g_n
        .na = .i - .h
        .nb = .i + .h
        if .na < 1
            .na = 1
        endif
        if .nb > g_n
            .nb = g_n
        endif
        while .a < .na
            .s = .s - g_be# [.a]
            .a = .a + 1
        endwhile
        while .b < .nb
            .b = .b + 1
            .s = .s + g_be# [.b]
        endwhile
        .v = .s / (.b - .a + 1)
        if .v < .floorE
            .v = .floorE
        endif
        g_sm# [.i] = 10 * log10 (.v / g_dt)
    endfor
endproc

# first block at or after .from whose smoothed level has fallen to .level
procedure firstBelow: .from, .level
    fb_i = 0
    if .from < 1
        .from = 1
    endif
    .i = .from
    .go = 1
    while .go = 1
        if .i > g_n
            .go = 0
        elsif g_sm# [.i] <= .level
            fb_i = .i
            .go = 0
        else
            .i = .i + 1
        endif
    endwhile
endproc

# ==========================================================================
#  6.  Lundeby noise floor and truncation crosspoint
# ==========================================================================
procedure lundeby: .dur
    lu_ok = 0
    lu_noise = undefined
    lu_cross = .dur
    lu_slope = undefined
    lu_snr = undefined
    lu_peak = undefined
    lu_ipk = 1
    lu_why$ = ""
    @blockLevels
    .w0 = round (0.02 / g_dt)
    if .w0 < 1
        .w0 = 1
    endif
    @smoothLevels: .w0
    .bail = 0
    if g_n < 20
        .bail = 1
        lu_why$ = "too few blocks"
    endif

    # ---- baseline noise from the last 10 % of the response ----
    if .bail = 0
        .i0 = floor (0.9 * g_n) + 1
        if .i0 > g_n - 2
            .i0 = g_n - 2
        endif
        if .i0 < 2
            .bail = 1
            lu_why$ = "too few blocks"
        endif
    endif
    if .bail = 0
        .sum = 0
        .cnt = 0
        for .i from .i0 to g_n
            .sum = .sum + g_be# [.i]
            .cnt = .cnt + 1
        endfor
        if .sum > 0
            lu_noise = 10 * log10 (.sum / (.cnt * g_dt))
        endif
        .ipk = 1
        .lpk = -1e30
        for .i to g_n
            if g_bl# [.i] > .lpk
                .lpk = g_bl# [.i]
                .ipk = .i
            endif
        endfor
        lu_peak = .lpk
        lu_ipk = .ipk
        if lu_noise = undefined
            .bail = 1
            lu_why$ = "no noise estimate"
        else
            lu_snr = .lpk - lu_noise
            .noise = lu_noise
        endif
    endif

    # ---- first slope: peak down to 10 dB above the noise ----
    if .bail = 0
        @firstBelow: .ipk, .noise + 10
        .iend = fb_i
        if .iend = 0
            .iend = g_n
        endif
        if .iend <= .ipk + 3
            .bail = 1
            lu_why$ = "no usable decay above the noise floor"
        endif
    endif
    if .bail = 0
        @regress: .ipk, .iend
        if reg_ok = 0
            .bail = 1
            lu_why$ = "first slope estimate failed"
        elsif reg_slope >= 0
            .bail = 1
            lu_why$ = "no downward slope"
        endif
    endif

    # ---- iterate the crosspoint ----
    if .bail = 0
        .slope = reg_slope
        .cross = (.noise - reg_icpt) / .slope
        # Lundeby step (e): about five averaging intervals per 10 dB of decay
        .win = round ((10 / abs (.slope)) / g_dt / 5)
        if .win < 1
            .win = 1
        endif
        .wcap = round (g_n / 10)
        if .wcap < 1
            .wcap = 1
        endif
        if .win > .wcap
            .win = .wcap
        endif
        @smoothLevels: .win
        .have = 0
        .done = 0
        for .iter to 5
            if .done = 0
                .tn = .cross + 5 / abs (.slope)
                .in = floor (.tn / g_dt) + 1
                .cap = g_n - round (0.1 * g_n)
                if .in > .cap
                    .in = .cap
                endif
                if .in < 2
                    .in = 2
                endif
                .sum = 0
                .cnt = 0
                for .i from .in to g_n
                    .sum = .sum + g_be# [.i]
                    .cnt = .cnt + 1
                endfor
                if .cnt < 2
                    .done = 1
                elsif .sum <= 0
                    .done = 1
                endif
            endif
            if .done = 0
                .noise = 10 * log10 (.sum / (.cnt * g_dt))
                @firstBelow: .ipk, .noise + 25
                .ia = fb_i
                @firstBelow: .ipk, .noise + 5
                .ib = fb_i
                if .ia = 0
                    .done = 1
                elsif .ib = 0
                    .done = 1
                elsif .ib <= .ia + 3
                    .done = 1
                endif
            endif
            if .done = 0
                @regress: .ia, .ib
                if reg_ok = 0
                    .done = 1
                elsif reg_slope >= 0
                    .done = 1
                endif
            endif
            if .done = 0
                .prev = .cross
                .slope = reg_slope
                .cross = (.noise - reg_icpt) / .slope
                if .cross > .dur
                    .cross = .dur
                endif
                if .cross > 0
                    lu_cross = .cross
                    lu_slope = .slope
                    lu_noise = .noise
                    lu_snr = lu_peak - .noise
                    .have = 1
                endif
                if abs (.cross - .prev) < 0.01 * abs (.prev)
                    .done = 1
                endif
            endif
        endfor
        if .have = 1
            lu_ok = 1
        else
            lu_why$ = "crosspoint did not converge"
        endif
    endif

    # ---- fallback truncation when the crosspoint search failed ----
    if lu_ok = 0
        if lu_noise <> undefined
            .fw = round (0.02 / g_dt)
            if .fw < 1
                .fw = 1
            endif
            @smoothLevels: .fw
            @firstBelow: lu_ipk, lu_noise + 5
            if fb_i > 0
                lu_cross = g_bt# [fb_i]
            endif
        endif
    endif
endproc

# ==========================================================================
#  7.  Schroeder decay curve
# ==========================================================================
procedure schroeder: .i0, .iEnd, .compensate, .slope, .noise
    ec_ok = 0
    g_ec# = zero# (g_n)
    .tail = 0
    .nsub = 0
    if .compensate = 1
        if .slope <> undefined
            if .slope < 0
                .pd = 10 ^ (.noise / 10)
                .tail = .pd * 10 / (abs (.slope) * ln (10))
                .nsub = .pd * g_dt
            endif
        endif
    endif
    .acc = .tail
    .span = .iEnd - .i0 + 1
    for .j to .span
        .i = .iEnd - .j + 1
        .v = g_be# [.i] - .nsub
        if .v < 0
            .v = 0
        endif
        .acc = .acc + .v
        g_ec# [.i] = .acc
    endfor
    .e0 = g_ec# [.i0]
    if .e0 > 0
        .floorV = .e0 * 1e-10
        for .i from .i0 to .iEnd
            .v = g_ec# [.i]
            if .v < .floorV
                .v = .floorV
            endif
            g_ec# [.i] = 10 * log10 (.v / .e0)
        endfor
        ec_i0 = .i0
        ec_iEnd = .iEnd
        ec_ok = 1
    endif
endproc

procedure edcTime: .level
    edct = undefined
    for .i from ec_i0 + 1 to ec_iEnd
        if edct = undefined
            if g_ec# [.i] <= .level
                .y1 = g_ec# [.i - 1]
                .y2 = g_ec# [.i]
                if .y1 = .y2
                    edct = g_bt# [.i]
                else
                    .f = (.level - .y1) / (.y2 - .y1)
                    edct = g_bt# [.i - 1] + .f * (g_bt# [.i] - g_bt# [.i - 1])
                endif
            endif
        endif
    endfor
endproc

procedure fitDecay: .upper, .lower
    fit_ok = 0
    fit_T = undefined
    fit_r2 = undefined
    fit_t1 = undefined
    fit_t2 = undefined
    fit_slope = undefined
    fit_icpt = undefined
    .bail = 0
    @edcTime: .upper
    .ta = edct
    @edcTime: .lower
    .tb = edct
    if .ta = undefined
        .bail = 1
    elsif .tb = undefined
        .bail = 1
    endif
    if .bail = 0
        .ia = floor (.ta / g_dt) + 1
        .ib = floor (.tb / g_dt) + 1
        if .ia < ec_i0
            .ia = ec_i0
        endif
        if .ib > ec_iEnd
            .ib = ec_iEnd
        endif
        if .ib <= .ia + 2
            .bail = 1
        endif
    endif
    if .bail = 0
        .n = 0
        .sx = 0
        .sy = 0
        .sxx = 0
        .sxy = 0
        .syy = 0
        for .i from .ia to .ib
            .x = g_bt# [.i]
            .y = g_ec# [.i]
            .n = .n + 1
            .sx = .sx + .x
            .sy = .sy + .y
            .sxx = .sxx + .x * .x
            .sxy = .sxy + .x * .y
            .syy = .syy + .y * .y
        endfor
        .den = .n * .sxx - .sx * .sx
        if .den = 0
            .bail = 1
        endif
    endif
    if .bail = 0
        .slope = (.n * .sxy - .sx * .sy) / .den
        if .slope >= 0
            .bail = 1
        endif
    endif
    if .bail = 0
        .vy = .n * .syy - .sy * .sy
        if .vy > 0
            .r = (.n * .sxy - .sx * .sy) / sqrt (.den * .vy)
            fit_r2 = .r * .r
        endif
        fit_T = 60 / abs (.slope)
        fit_t1 = .ta
        fit_t2 = .tb
        fit_slope = .slope
        fit_icpt = (.sy - .slope * .sx) / .n
        fit_ok = 1
    endif
endproc

# ==========================================================================
#  8.  full decay analysis of one Sound
# ==========================================================================
force_no_trunc = 0

procedure analyse: .id, .dur, .t0
    an_ok = 0
    an_edt = undefined
    an_t20 = undefined
    an_t30 = undefined
    an_r2edt = undefined
    an_r2t20 = undefined
    an_r2t30 = undefined
    an_snr = undefined
    an_noise = undefined
    an_curv = undefined
    an_edt_ok = 0
    an_t20_ok = 0
    an_t30_ok = 0
    an_cross = .dur
    .bail = 0
    @blockEnergies: .id, .dur
    if g_n < 20
        .bail = 1
    endif
    if .bail = 0
        @lundeby: .dur
        an_noise = lu_noise
        .useTrunc = 1
        if truncation <> 1
            .useTrunc = 0
        endif
        if force_no_trunc = 1
            .useTrunc = 0
        endif
        if .useTrunc = 1
            an_cross = lu_cross
        else
            an_cross = .dur
        endif
        .i0 = floor (.t0 / g_dt) + 1
        if .i0 < 1
            .i0 = 1
        endif
        .iEnd = floor (an_cross / g_dt)
        if .iEnd > g_n
            .iEnd = g_n
        endif
        if .iEnd <= .i0 + 8
            .bail = 1
        endif
    endif
    if .bail = 0
        .comp = adv_compensate
        if lu_ok = 0
            .comp = 0
        endif
        if force_no_trunc = 1
            .comp = 0
        endif
        @schroeder: .i0, .iEnd, .comp, lu_slope, lu_noise
        if ec_ok = 0
            .bail = 1
        endif
    endif
    if .bail = 0
        @blockLevels
        an_snr = lu_snr
        @fitDecay: 0, -10
        an_edt = fit_T
        an_r2edt = fit_r2
        an_edt_t1 = fit_t1
        an_edt_t2 = fit_t2
        an_edt_slope = fit_slope
        an_edt_icpt = fit_icpt
        an_edt_ok = fit_ok
        @fitDecay: -5, -25
        an_t20 = fit_T
        an_r2t20 = fit_r2
        an_t20_t1 = fit_t1
        an_t20_t2 = fit_t2
        an_t20_slope = fit_slope
        an_t20_icpt = fit_icpt
        an_t20_ok = fit_ok
        @fitDecay: -5, -35
        an_t30 = fit_T
        an_r2t30 = fit_r2
        an_t30_t1 = fit_t1
        an_t30_t2 = fit_t2
        an_t30_slope = fit_slope
        an_t30_icpt = fit_icpt
        an_t30_ok = fit_ok
        # ISO 3382-1: the decay must stay clear of the noise floor over the
        # whole evaluation range. A fit that converged is not the same as a
        # fit the measurement can support.
        if an_snr <> undefined
            if an_snr < 35
                an_t30_ok = 0
            endif
            if an_snr < 25
                an_t20_ok = 0
            endif
            if an_snr < 20
                an_edt_ok = 0
            endif
        endif
        if an_t20_ok = 1 and an_t30_ok = 1
            an_curv = 100 * (an_t30 / an_t20 - 1)
        endif
        an_ok = 1
    endif
endproc

# ==========================================================================
#  9.  broadband run
# ==========================================================================
@blockEnergies: work, workDur
@findStart: work, workDur, adv_startRule
t0 = startT
# Snap the analysis start to a sample edge. The direct sound sits at t0 and
# can carry several percent of the total energy, so a window boundary that
# falls mid-sample makes Ts depend on how partial edge samples are resolved -
# which differs between Praat versions (6.3.09 and 6.4.63 disagreed by 1.5 %).
selectObject: work
iT0raw = Get sample number from time: t0
iT0 = round (iT0raw)
if iT0 < 1
    iT0 = 1
endif
t0 = (iT0 - 1) / srate

@analyse: work, workDur, t0
bb_ok = an_ok
bb_edt = an_edt
bb_t20 = an_t20
bb_t30 = an_t30
bb_r2edt = an_r2edt
bb_r2t20 = an_r2t20
bb_r2t30 = an_r2t30
bb_snr = an_snr
bb_cross = an_cross
bb_noise = an_noise
bb_curv = an_curv
bb_edtok = an_edt_ok
bb_t20ok = an_t20_ok
bb_t30ok = an_t30_ok
bb_slope = lu_slope
bb_luok = lu_ok
bb_why$ = lu_why$

if bb_ok = 0
    removeObject: work
    exitScript: "The decay could not be measured. The response is either too " +
    ... "short, has no usable decay, or is dominated by noise."
endif

d_n = g_n
d_ec# = g_ec#
d_bt# = g_bt#
d_bl# = g_bl#
d_be# = g_be#
d_i0 = ec_i0
d_iEnd = ec_iEnd
d_t20_slope = an_t20_slope
d_t20_icpt = an_t20_icpt
d_t30_slope = an_t30_slope
d_t30_icpt = an_t30_icpt
d_t20_t1 = an_t20_t1
d_t20_t2 = an_t20_t2
d_t30_t1 = an_t30_t1
d_t30_t2 = an_t30_t2

# ---- clarity, from exact energy queries ---------------------------------
selectObject: work
c_end = bb_cross
if c_end <= t0 + 0.1
    c_end = workDur
endif
c_end = round (c_end * srate) / srate
if c_end > workDur
    c_end = workDur
endif
c50 = undefined
c80 = undefined
d50 = undefined
ts = undefined
if t0 + 0.05 < c_end
    eA = Get energy: t0, t0 + 0.05
    eB = Get energy: t0 + 0.05, c_end
    eT = Get energy: t0, c_end
    if eA > 0 and eB > 0
        c50 = 10 * log10 (eA / eB)
    endif
    if eT > 0
        d50 = 100 * eA / eT
    endif
endif
if t0 + 0.08 < c_end
    eA = Get energy: t0, t0 + 0.08
    eB = Get energy: t0 + 0.08, c_end
    if eA > 0 and eB > 0
        c80 = 10 * log10 (eA / eB)
    endif
endif
# Ts by sample-domain integration: energy of h(t)*sqrt(t-t0) is exactly
# the first moment of h^2, so no block grid is involved
selectObject: work
tsDen = Get energy: t0, c_end
if tsDen > 0
    tsCopy = Copy: "tsw"
    Formula (part): t0, c_end, 1, 1, "self * sqrt (x - t0)"
    tsNum = Get energy: t0, c_end
    removeObject: tsCopy
    ts = 1000 * tsNum / tsDen
endif

# ==========================================================================
# 10.  octave bands
# ==========================================================================
nBands = 0
if bands = 2
    nyq = srate / 2
    nb = 0
    fc = adv_lowBand
    while fc <= adv_highBand * 1.001
        if fc * sqrt (2) < 0.95 * nyq
            nb = nb + 1
        endif
        fc = fc * 2
    endwhile
    if nb > 0
        nBands = nb
        bd_fc# = zero# (nb)
        bd_t30# = zero# (nb)
        bd_t20# = zero# (nb)
        bd_edt# = zero# (nb)
        bd_c50# = zero# (nb)
        bd_self# = zero# (nb)
        bd_ok30# = zero# (nb)
        bd_ok20# = zero# (nb)
        bd_okedt# = zero# (nb)
        bd_okc50# = zero# (nb)
        bd_lvl# = zero# (nb)
        bd_haslvl# = zero# (nb)

        probe = Create Sound from formula: "probe", 1, 0, 0.3, srate, "0"
        ip = round (0.06 * srate)
        Set value at sample number: 1, ip, 1
        probeT0 = (ip - 0.5) / srate

        keepDt = g_dt
        k = 0
        fc = adv_lowBand
        while fc <= adv_highBand * 1.001
            if fc * sqrt (2) < 0.95 * nyq
                k = k + 1
                bLo = fc / sqrt (2)
                bHi = fc * sqrt (2)
                bSm = (bHi - bLo) / 2
                bd_fc# [k] = fc

                # --- the filter's own decay, measured on a unit impulse ---
                selectObject: probe
                pf = Filter (pass Hann band): bLo, bHi, bSm
                pdur = Get total duration
                g_dt = 0.0002
                if g_dt < 4 / srate
                    g_dt = 4 / srate
                endif
                force_no_trunc = 1
                @analyse: pf, pdur, probeT0
                force_no_trunc = 0
                g_dt = keepDt
                if an_t30_ok = 1
                    bd_self# [k] = an_t30
                elsif an_t20_ok = 1
                    bd_self# [k] = an_t20
                else
                    bd_self# [k] = 0
                endif
                removeObject: pf

                # --- the band itself ---
                selectObject: work
                bf = Filter (pass Hann band): bLo, bHi, bSm
                bdur = Get total duration
                @analyse: bf, bdur, t0
                sep = 10 * bd_self# [k]
                if an_t30_ok = 1
                    if an_t30 > sep
                        bd_t30# [k] = an_t30
                        bd_ok30# [k] = 1
                    endif
                endif
                if an_t20_ok = 1
                    if an_t20 > sep
                        bd_t20# [k] = an_t20
                        bd_ok20# [k] = 1
                    endif
                endif
                if an_edt_ok = 1
                    if an_edt > sep
                        bd_edt# [k] = an_edt
                        bd_okedt# [k] = 1
                    endif
                endif
                bcross = an_cross
                if bcross <= t0 + 0.06
                    bcross = bdur
                endif
                selectObject: bf
                if t0 + 0.05 < bcross
                    eA = Get energy: t0, t0 + 0.05
                    eB = Get energy: t0 + 0.05, bcross
                    if eA > 0 and eB > 0
                        bd_c50# [k] = 10 * log10 (eA / eB)
                        bd_okc50# [k] = 1
                    endif
                endif
                if t0 < bcross
                    eL = Get energy: t0, bcross
                    if eL > 0
                        bd_lvl# [k] = 10 * log10 (eL)
                        bd_haslvl# [k] = 1
                    endif
                endif
                removeObject: bf
            endif
            fc = fc * 2
        endwhile
        removeObject: probe
        g_dt = keepDt

        # A band well below every other one holds no measured content - what
        # is left is leakage through the filter's stopband, and it carries
        # the decay of whichever band it leaked from, not its own.
        bandRefMax = -1e30
        for k to nBands
            if bd_haslvl# [k] = 1
                if bd_lvl# [k] > bandRefMax
                    bandRefMax = bd_lvl# [k]
                endif
            endif
        endfor
        for k to nBands
            if bd_haslvl# [k] = 1
                bd_lvl# [k] = bd_lvl# [k] - bandRefMax
            else
                bd_lvl# [k] = undefined
            endif
            if bd_haslvl# [k] = 1
                if bd_lvl# [k] < -60
                    bd_ok30# [k] = 0
                    bd_ok20# [k] = 0
                    bd_okedt# [k] = 0
                    bd_okc50# [k] = 0
                endif
            endif
        endfor
    endif
endif

# ==========================================================================
# 11.  IR preparation and creative processing
#
#      Everything below works on COPIES. The measured Sound is never
#      modified and every acoustic figure reported above was computed
#      before this section ran. A creative IR is compositional material,
#      not a measurement of anything.
#
#      Gain policy for generated IRs: never normalised upward. If a peak
#      exceeds 0.99 the whole Sound is scaled by ONE scalar, so early/late
#      energy relationships survive exactly. Any such scaling is reported.
# ==========================================================================
prepId = 0
creId = 0
earlyId = 0
lateId = 0
audId = 0
prepPeakDb = 0
crePeakDb = 0
audPeakDb = 0
prepEndT = undefined
prepDur = 0
audResampled = 0
audMsg$ = ""
elDelivered = 0

splitSec = 0.05
if split_mode = 2
    splitSec = 0.08
elsif split_mode = 3
    splitSec = split_customMs / 1000
endif
xfSec = xfadeMs / 1000

if needPrep = 1
    @prepareIR
    if prepId <> 0
        if make_early_late = 1
            @makeEarlyLate: prepId
            if el_ok = 1
                selectObject: earlyId
                Rename: inName$ + "_IRearly"
                selectObject: lateId
                Rename: inName$ + "_IRlate"
                elDelivered = 1
            endif
        endif
        if creative_IR_processing = 1
            @creativeIR
        endif
        if audition_on_another_Sound = 1
            @auditionConvolution
        endif
    endif
endif

# ---- peak protection -----------------------------------------------------
procedure protectPeak: .id, .limit
    pp_db = 0
    selectObject: .id
    .d = Get total duration
    .hi = Get maximum: 0, .d, "None"
    .lo = Get minimum: 0, .d, "None"
    .pk = max (abs (.hi), abs (.lo))
    if .pk > .limit
        if .pk > 0
            ppG = .limit / .pk
            Formula: "self * ppG"
            pp_db = 20 * log10 (ppG)
        endif
    endif
endproc

# ---- convolution-ready IR ------------------------------------------------
# Reuses the measured truncation rather than a blind fixed-length cut: the
# end is the Lundeby crosspoint backed off by the user's tail margin along
# the fitted decay, so the kernel stops where the room stops, not where the
# recording does.
procedure prepareIR
    .tEnd = bb_cross
    if bb_slope <> undefined
        if bb_slope < 0
            .tEnd = bb_cross - adv_trimTailDb / abs (bb_slope)
        endif
    endif
    if .tEnd <= t0 + 0.02
        .tEnd = min (workDur, t0 + 0.05)
    endif
    if .tEnd > workDur
        .tEnd = workDur
    endif
    .tEnd = round (.tEnd * srate) / srate
    .tStart = t0
    if prep_align = 2
        .tStart = 0
    endif
    if .tEnd - .tStart < 0.005
        .tEnd = min (workDur, .tStart + 0.005)
    endif
    if .tEnd - .tStart >= 0.002
        selectObject: work
        prepId = Extract part: .tStart, .tEnd, "rectangular", 1, "no"
        Shift times to: "start time", 0
        prepDur = Get total duration
        prepEndT = .tEnd
        # raised-cosine fade at the very end only, so the measured decay
        # ahead of it is untouched
        fadeLen = prep_fadeMs / 1000
        if fadeLen > prepDur / 4
            fadeLen = prepDur / 4
        endif
        fadeStart = prepDur - fadeLen
        if fadeLen > 0
            Formula (part): fadeStart, prepDur, 1, 1,
            ... "self * (0.5 + 0.5 * cos (pi * (x - fadeStart) / fadeLen))"
        endif
        @protectPeak: prepId, 0.99
        prepPeakDb = pp_db
        selectObject: prepId
        Rename: inName$ + "_IRprepared"
    endif
endproc

# ---- early / late boundary geometry --------------------------------------
# Complementary raised-cosine windows, w and 1-w, which sum to exactly 1.
# Early and late therefore recombine into the prepared IR with no level
# bump and no discontinuity at the join.
procedure splitGeometry: .dur
    sg_ok = 0
    .base = 0
    if prep_align = 2
        .base = t0
    endif
    .half = xfSec / 2
    splitT = .base + splitSec
    if splitT - .half <= 0
        splitT = .half + 2 / srate
    endif
    if splitT + .half >= .dur
        splitT = .dur - .half - 2 / srate
    endif
    xfA = splitT - .half
    xfB = splitT + .half
    if xfA > 0
        if xfB < .dur
            if xfB - xfA > 1 / srate
                sg_ok = 1
            endif
        endif
    endif
endproc

procedure makeEarlyLate: .srcId
    el_ok = 0
    selectObject: .srcId
    .d = Get total duration
    @splitGeometry: .d
    if sg_ok = 1
        selectObject: .srcId
        earlyId = Copy: "elEarly"
        Formula (part): xfA, xfB, 1, 1,
        ... "self * (0.5 + 0.5 * cos (pi * (x - xfA) / (xfB - xfA)))"
        Formula (part): xfB, .d, 1, 1, "0"
        selectObject: .srcId
        lateId = Copy: "elLate"
        Formula (part): 0, xfA, 1, 1, "0"
        Formula (part): xfA, xfB, 1, 1,
        ... "self * (0.5 - 0.5 * cos (pi * (x - xfA) / (xfB - xfA)))"
        el_ok = 1
    endif
endproc

# ---- creative sculpting --------------------------------------------------
procedure creativeIR
    selectObject: prepId
    creId = Copy: "creWork"
    .d = Get total duration
    @splitGeometry: .d
    if sg_ok = 1
        gE = 10 ^ (cre_earlyGain / 20)
        gL = 10 ^ (cre_lateGain / 20)
        if cre_earlyGain <> 0 or cre_lateGain <> 0
            selectObject: creId
            Formula (part): 0, xfA, 1, 1, "self * gE"
            Formula (part): xfA, xfB, 1, 1,
            ... "self * (gE * (0.5 + 0.5 * cos (pi * (x - xfA) / (xfB - xfA)))" +
            ... " + gL * (0.5 - 0.5 * cos (pi * (x - xfA) / (xfB - xfA))))"
            Formula (part): xfB, .d, 1, 1, "self * gL"
        endif
        # Artistic amplitude envelope on the tail. This does NOT mean the
        # room has a different reverberation time - it reshapes the measured
        # tail. Clamped to +12 dB so a long tail cannot blow up the noise
        # floor, and to -80 dB so it cannot underflow.
        if cre_decayShape <> 0
            dShape = cre_decayShape
            selectObject: creId
            Formula (part): splitT, .d, 1, 1,
            ... "self * 10 ^ (min (12, max (-80, dShape * (x - splitT))) / 20)"
        endif
        if cre_reverse = 1
            @reverseLateTail: creId, .d
        endif
    endif
    if cre_tilt <> 0
        @applySpectralColor: creId, cre_tilt
    endif
    if cre_predelayMs > 0
        @addPredelay: creId, cre_predelayMs
        creId = pd_newId
    endif
    @protectPeak: creId, 0.99
    crePeakDb = pp_db
    selectObject: creId
    Rename: inName$ + "_IRart"
endproc

# Reverses only the late field, so the causal onset and early reflections
# keep their normal orientation and the gesture still reads as an attack.
#
# Order matters here. Windowing the late part BEFORE reversing puts the
# fade at the wrong end: measured on a shoebox IR it left a 93 dB hole at
# the join (-24 dB, then -36, then -117 dB across the boundary) while the
# new end stayed tapered only by accident, because the pre-reversal fade-in
# happened to land there. So the content is reversed first and windowed
# after - a complementary fade-in at the boundary, and a fade-out at the
# new end, which after reversal holds the loudest material in the tail.
procedure reverseLateTail: .id, .dur
    selectObject: .id
    rvEarly = Copy: "rvEarly"
    Formula (part): xfA, xfB, 1, 1,
    ... "self * (0.5 + 0.5 * cos (pi * (x - xfA) / (xfB - xfA)))"
    Formula (part): xfB, .dur, 1, 1, "0"

    selectObject: .id
    rvSeg = Extract part: xfA, .dur, "rectangular", 1, "yes"
    Reverse
    Rename: "rvSeg"
    revDur = .dur
    # complementary to the early fade-out, so the two sum to unity again
    Formula (part): xfA, xfB, 1, 1,
    ... "self * (0.5 - 0.5 * cos (pi * (x - xfA) / (xfB - xfA)))"
    # the reversed tail now ends loud; without this it would click
    revFade = prep_fadeMs / 1000
    if revFade > (revDur - xfB) / 4
        revFade = (revDur - xfB) / 4
    endif
    revFadeA = revDur - revFade
    if revFadeA > xfB
        if revFade > 0
            Formula (part): revFadeA, revDur, 1, 1,
            ... "self * (0.5 + 0.5 * cos (pi * (x - revFadeA) / revFade))"
        endif
    endif

    selectObject: .id
    rvLate = Copy: "rvLate"
    Formula: "0"
    Formula (part): xfA, .dur, 1, 1, "Sound_rvSeg (x)"
    selectObject: .id
    Formula: "Sound_rvEarly (x) + Sound_rvLate (x)"
    removeObject: rvEarly, rvLate, rvSeg
endproc

# One broad tilt about a 1 kHz pivot, not an equaliser. Per-bin gain is
# clamped to +-12 dB so the extremes of the spectrum cannot explode.
procedure applySpectralColor: .id, .tiltDb
    selectObject: .id
    .d = Get total duration
    cTilt = .tiltDb
    scSp = To Spectrum: "yes"
    Formula: "self * 10 ^ (min (12, max (-12, cTilt * log2 (max (x, 20) / 1000))) / 20)"
    scBk = To Sound
    # To Spectrum zero-pads to a power of two, so the round trip comes back
    # longer than it went in and has to be cut back to the original length
    scCut = Extract part: 0, .d, "rectangular", 1, "no"
    Rename: "scCut"
    selectObject: .id
    Formula: "Sound_scCut (x)"
    removeObject: scSp, scBk, scCut
endproc

procedure addPredelay: .id, .ms
    pd_newId = .id
    .pre = round (.ms / 1000 * srate) / srate
    if .pre > 0
        selectObject: .id
        .d = Get total duration
        Rename: "pdSrc"
        pdPre = .pre
        pd_newId = Create Sound from formula: "pdOut", 1, 0, .pre + .d, srate, "0"
        Formula (part): .pre, .pre + .d, 1, 1, "Sound_pdSrc (x - pdPre)"
        removeObject: .id
    endif
endproc

# ---- audition ------------------------------------------------------------
procedure auditionConvolution
    .dryId = 0
    for .i to nOpen
        if .dryId = 0
            if openNames$# [.i] = aud_dryName$
                if openIds# [.i] <> inSound
                    .dryId = openIds# [.i]
                endif
            endif
        endif
    endfor
    if .dryId = 0
        audMsg$ = "no other open Sound is named " + aud_dryName$
    else
        irUse = prepId
        audIrKind$ = "prepared IR"
        if creId <> 0
            if aud_useCreative = 1
                irUse = creId
                audIrKind$ = "creative IR"
            endif
        endif
        selectObject: .dryId
        audDryName$ = selected$ ("Sound")
        .dsr = Get sampling frequency
        .dch = Get number of channels
        if .dch > 1
            audDry = Extract one channel: 1
            audMsg$ = "dry Sound is multichannel; channel 1 used"
        else
            audDry = Copy: "audDry"
        endif
        Rename: "audDry"
        Shift times to: "start time", 0
        audDryDur = Get total duration
        selectObject: irUse
        .isr = Get sampling frequency
        if .isr <> .dsr
            audIr = Resample: .dsr, 50
            audResampled = 1
        else
            audIr = Copy: "audIr"
        endif
        Rename: "audIr"
        selectObject: audDry, audIr
        audId = Convolve: "sum", "zero"
        # The absolute level of a convolution depends entirely on the gain
        # the IR happened to be recorded at, so a raw wet/dry percentage is
        # not perceptually meaningful. This matches wet RMS to dry RMS over
        # the dry Sound's own span. It touches the preview only - neither
        # the prepared nor the creative IR is changed.
        if aud_levelMatch = 1
            selectObject: audId
            .rw = Get root-mean-square: 0, audDryDur
            selectObject: audDry
            .rd = Get root-mean-square: 0, audDryDur
            if .rw > 0
                if .rd > 0
                    audMatchDb = 20 * log10 (.rd / .rw)
                    if audMatchDb > 36
                        audMatchDb = 36
                    endif
                    if audMatchDb < -36
                        audMatchDb = -36
                    endif
                    amG = 10 ^ (audMatchDb / 20)
                    selectObject: audId
                    Formula: "self * amG"
                endif
            endif
        endif
        wetG = aud_wet / 100
        dryG = 1 - wetG
        selectObject: audId
        if wetG <> 1
            Formula: "self * wetG"
        endif
        if dryG > 0
            Formula (part): 0, audDryDur, 1, 1, "self + Sound_audDry (x) * dryG"
        endif
        @protectPeak: audId, 0.99
        audPeakDb = pp_db
        selectObject: audId
        Rename: audDryName$ + "_through_" + inName$
        removeObject: audDry, audIr
    endif
endproc

# ==========================================================================
# 12.  report
# ==========================================================================
writeInfoLine: "IR Analysis  -  ", inName$
appendInfoLine: "-------------------------------------------------------------"
appendInfoLine: "sample rate        ", fixed$ (srate, 0), " Hz"
appendInfoLine: "duration           ", fixed$ (totalDur, 3), " s"
appendInfoLine: "analysed           ", chanNote$
if cancelDb <> undefined
    appendInfoLine: "channel sum        ", fixed$ (cancelDb, 2),
    ... " dB re the channel mean"
    if cancelDb < -1
        appendInfoLine: "  WARNING: summing these channels cancels energy."
        appendInfoLine: "  The channels are not time-aligned. Analyse one channel"
        appendInfoLine: "  at a time instead - the decay of a comb-filtered sum is"
        appendInfoLine: "  not the decay of the room."
    endif
endif
appendInfoLine: "start point        ", fixed$ (1000 * t0, 2), " ms"
appendInfoLine: "EDC resolution     ", fixed$ (1000 * g_dt, 2), " ms per block"
@fmt: bb_noise, 1
appendInfoLine: "noise floor        ", fmt$, " dB (energy density)"
@fmt: bb_snr, 1
appendInfoLine: "peak-to-noise      ", fmt$, " dB (available decay range)"
if truncation = 1
    if bb_luok = 1
        appendInfoLine: "truncation         ", fixed$ (1000 * bb_cross, 1),
        ... " ms  (Lundeby crosspoint)"
    else
        appendInfoLine: "truncation         ", fixed$ (1000 * bb_cross, 1),
        ... " ms  (fallback: crosspoint search failed - ", bb_why$, ")"
    endif
    if adv_compensate
        appendInfoLine: "noise handling     Chu subtraction + tail extrapolation"
    else
        appendInfoLine: "noise handling     off (raw backward integration)"
    endif
else
    appendInfoLine: "truncation         none - integrated to the end"
endif
appendInfoLine: ""
appendInfoLine: "Broadband"

procedure rep: .name$, .v, .ok, .r2
    if .ok = 0
        .s$ = "REFUSED - decay range insufficient"
        @fmt: undefined, 3
        .v$ = fmt$
        @fmt: undefined, 4
        .r$ = fmt$
    else
        .s$ = ""
        @fmt: .v, 3
        .v$ = fmt$
        @fmt: .r2, 4
        .r$ = fmt$
    endif
    appendInfoLine: "  ", .name$, "  ", .v$, " s    r2 ", .r$, "   ", .s$
endproc

@rep: "EDT", bb_edt, bb_edtok, bb_r2edt
@rep: "T20", bb_t20, bb_t20ok, bb_r2t20
@rep: "T30", bb_t30, bb_t30ok, bb_r2t30
if bb_curv <> undefined
    appendInfoLine: "  curvature C = 100*(T30/T20-1) = ",
    ... fixed$ (bb_curv, 1), " \%  "
endif
appendInfoLine: ""
@fmt: c50, 2
appendInfoLine: "  C50   ", fmt$, " dB"
@fmt: c80, 2
appendInfoLine: "  C80   ", fmt$, " dB"
@fmt: d50, 1
appendInfoLine: "  D50   ", fmt$, " \%  "
@fmt: ts, 1
appendInfoLine: "  Ts    ", fmt$, " ms"

if nBands > 0
    appendInfoLine: ""
    appendInfoLine: "Octave bands"
    appendInfoLine: "     Hz      T30      T20      EDT      C50    level    filter"
    for k to nBands
        if bd_ok30# [k] = 1
            @fmt: bd_t30# [k], 3
        else
            @fmt: undefined, 3
        endif
        s30$ = fmt$
        if bd_ok20# [k] = 1
            @fmt: bd_t20# [k], 3
        else
            @fmt: undefined, 3
        endif
        s20$ = fmt$
        if bd_okedt# [k] = 1
            @fmt: bd_edt# [k], 3
        else
            @fmt: undefined, 3
        endif
        sed$ = fmt$
        if bd_okc50# [k] = 1
            @fmt: bd_c50# [k], 2
        else
            @fmt: undefined, 2
        endif
        sc$ = fmt$
        if bd_haslvl# [k] = 1
            @fmt: bd_lvl# [k], 1
        else
            @fmt: undefined, 1
        endif
        sl$ = fmt$
        if bd_self# [k] > 0
            sf$ = fixed$ (1000 * bd_self# [k], 2) + " ms"
        else
            sf$ = "<0.2 ms"
        endif
        @pad: fixed$ (bd_fc# [k], 0), 5
        f$ = pad$
        @pad: s30$, 9
        s30$ = pad$
        @pad: s20$, 9
        s20$ = pad$
        @pad: sed$, 9
        sed$ = pad$
        @pad: sc$, 9
        sc$ = pad$
        @pad: sl$, 9
        sl$ = pad$
        @pad: sf$, 10
        sf$ = pad$
        appendInfoLine: "  ", f$, s30$, s20$, sed$, sc$, sl$, sf$
    endfor
    appendInfoLine: ""
    appendInfoLine: "  n/a = fit refused: either the decay did not span the"
    appendInfoLine: "  required dB range before the noise floor, or it was not"
    appendInfoLine: "  clear of the filter's own decay by a factor of ten, or the"
    appendInfoLine: "  band held no measured content (level column, dB re the"
    appendInfoLine: "  strongest band; below -60 dB it is filter leakage)."
endif

# ==========================================================================
# 12b.  processing report - deliberately fenced off from the measurement
# ==========================================================================
if needPrep = 1
    appendInfoLine: ""
    appendInfoLine: "============================================================="
    appendInfoLine: "IR preparation / creative processing"
    appendInfoLine: "  Derived Sounds. Every acoustic figure above describes the"
    appendInfoLine: "  original ", inName$, " and nothing below changed it."
    appendInfoLine: "============================================================="
endif
if prepId <> 0
    appendInfoLine: ""
    if prepare_convolution_ready_IR = 1
        appendInfoLine: "Prepared IR        ", inName$, "_IRprepared"
    else
        appendInfoLine: "Prepared base      (internal - not kept, since it was not requested)"
    endif
    if prep_align = 1
        appendInfoLine: "  start            direct sound aligned to zero"
    else
        appendInfoLine: "  start            measured timing preserved"
    endif
    appendInfoLine: "  end              ", fixed$ (1000 * prepEndT, 1),
    ... " ms  (measured truncation, backed off ", fixed$ (adv_trimTailDb, 0),
    ... " dB along the fitted decay)"
    appendInfoLine: "  length           ", fixed$ (1000 * prepDur, 1), " ms"
    appendInfoLine: "  final fade       ", fixed$ (1000 * fadeLen, 1), " ms"
    if prepPeakDb <> 0
        appendInfoLine: "  peak protection  ", fixed$ (prepPeakDb, 2), " dB"
    endif
endif
if elDelivered = 1
    appendInfoLine: ""
    appendInfoLine: "Early / late       ", inName$, "_IRearly  +  ", inName$, "_IRlate"
    appendInfoLine: "  split            ", fixed$ (1000 * splitSec, 1),
    ... " ms after the direct sound"
    appendInfoLine: "  crossfade        ", fixed$ (1000 * xfSec, 1),
    ... " ms, complementary - the two sum back to the prepared IR exactly"
    appendInfoLine: "  both Sounds keep the prepared IR's full length and timing"
endif
if creId <> 0
    appendInfoLine: ""
    appendInfoLine: "Creative IR        ", inName$, "_IRart"
    appendInfoLine: "  starting point   ", presetName$
    appendInfoLine: "  early/late split ", fixed$ (1000 * splitSec, 1), " ms"
    if cre_earlyGain <> 0
        appendInfoLine: "  early gain       ", fixed$ (cre_earlyGain, 1), " dB"
    endif
    if cre_lateGain <> 0
        appendInfoLine: "  late gain        ", fixed$ (cre_lateGain, 1), " dB"
    endif
    if cre_decayShape <> 0
        appendInfoLine: "  decay shaping    ", fixed$ (cre_decayShape, 1),
        ... " dB/s on the tail (artistic envelope, not a change of RT)"
    endif
    if cre_tilt <> 0
        appendInfoLine: "  spectral tilt    ", fixed$ (cre_tilt, 1),
        ... " dB/octave about 1 kHz"
    endif
    if cre_reverse = 1
        appendInfoLine: "  late tail        reversed (onset kept forward)"
    endif
    if cre_predelayMs > 0
        appendInfoLine: "  pre-delay        ", fixed$ (cre_predelayMs, 1), " ms added"
    endif
    if crePeakDb <> 0
        appendInfoLine: "  peak protection  ", fixed$ (crePeakDb, 2), " dB"
    endif
    appendInfoLine: "  This Sound can be analysed again as an independent IR, but"
    appendInfoLine: "  its figures would describe the sculpture, not the room."
endif
if audId <> 0
    appendInfoLine: ""
    appendInfoLine: "Audition           ", audDryName$, "_through_", inName$
    appendInfoLine: "  convolved with   ", audIrKind$
    appendInfoLine: "  wet              ", fixed$ (aud_wet, 0), " \%  "
    if aud_levelMatch = 1
        appendInfoLine: "  level matching   ", fixed$ (audMatchDb, 2),
        ... " dB applied to the preview only"
    endif
    if audResampled = 1
        appendInfoLine: "  IR resampled to the dry Sound's rate"
    endif
    if audPeakDb <> 0
        appendInfoLine: "  peak protection  ", fixed$ (audPeakDb, 2), " dB"
    endif
endif
if audId = 0
    if audition_on_another_Sound = 1
        appendInfoLine: ""
        appendInfoLine: "Audition skipped:  ", audMsg$
    endif
endif

# ==========================================================================
# 12c.  results table
# ==========================================================================
tblId = 0
tblBandId = 0
if adv_table = 1
    tblId = Create Table with column names: inName$ + "_IRresults", 1,
    ... "sound channel sample_rate t0_ms peak_to_noise_dB noise_floor_dB " +
    ... "truncation_ms EDT EDT_valid T20 T20_valid T30 T30_valid " +
    ... "curvature_pct C50_dB C80_dB D50_pct Ts_ms"
    Set string value: 1, "sound", inName$
    Set string value: 1, "channel", chanNote$
    Set numeric value: 1, "sample_rate", srate
    Set numeric value: 1, "t0_ms", 1000 * t0
    if bb_snr <> undefined
        Set numeric value: 1, "peak_to_noise_dB", bb_snr
    endif
    if bb_noise <> undefined
        Set numeric value: 1, "noise_floor_dB", bb_noise
    endif
    Set numeric value: 1, "truncation_ms", 1000 * bb_cross
    if bb_edtok = 1
        Set numeric value: 1, "EDT", bb_edt
    endif
    @validity: bb_edtok
    Set string value: 1, "EDT_valid", validity$
    if bb_t20ok = 1
        Set numeric value: 1, "T20", bb_t20
    endif
    @validity: bb_t20ok
    Set string value: 1, "T20_valid", validity$
    if bb_t30ok = 1
        Set numeric value: 1, "T30", bb_t30
    endif
    @validity: bb_t30ok
    Set string value: 1, "T30_valid", validity$
    if bb_curv <> undefined
        Set numeric value: 1, "curvature_pct", bb_curv
    endif
    if c50 <> undefined
        Set numeric value: 1, "C50_dB", c50
    endif
    if c80 <> undefined
        Set numeric value: 1, "C80_dB", c80
    endif
    if d50 <> undefined
        Set numeric value: 1, "D50_pct", d50
    endif
    if ts <> undefined
        Set numeric value: 1, "Ts_ms", ts
    endif
    if nBands > 0
        tblBandId = Create Table with column names: inName$ + "_IRbands",
        ... nBands, "band_Hz T30 T30_valid T20 T20_valid EDT EDT_valid " +
        ... "C50_dB level_dB filter_selfdecay_ms"
        for k to nBands
            Set numeric value: k, "band_Hz", bd_fc# [k]
            if bd_ok30# [k] = 1
                Set numeric value: k, "T30", bd_t30# [k]
            endif
            @validity: bd_ok30# [k]
            Set string value: k, "T30_valid", validity$
            if bd_ok20# [k] = 1
                Set numeric value: k, "T20", bd_t20# [k]
            endif
            @validity: bd_ok20# [k]
            Set string value: k, "T20_valid", validity$
            if bd_okedt# [k] = 1
                Set numeric value: k, "EDT", bd_edt# [k]
            endif
            @validity: bd_okedt# [k]
            Set string value: k, "EDT_valid", validity$
            if bd_okc50# [k] = 1
                Set numeric value: k, "C50_dB", bd_c50# [k]
            endif
            if bd_haslvl# [k] = 1
                Set numeric value: k, "level_dB", bd_lvl# [k]
            endif
            Set numeric value: k, "filter_selfdecay_ms", 1000 * bd_self# [k]
        endfor
    endif
endif

# ==========================================================================
# 13.  visualization
# ==========================================================================
if draw_visualization
    canvasW = 8
    canvasH = 9.0
    showCompare = 0
    if creId <> 0
        showCompare = 1
        canvasH = 10.6
    endif
    Erase all
    Font size: 10
    Select inner viewport: 0, canvasW, 0, canvasH
    Axes: 0, 1, 0, 1
    Paint rectangle: {1.00, 1.00, 1.00}, 0, 1, 0, 1
    Colour: {0.00, 0.00, 0.00}
    Line width: 1
    Solid line

    # x range follows the decay itself, not the file length: a long silent
    # or numerically-empty tail must not squash the part being measured
    tShow = 0
    for i from d_i0 to d_iEnd
        if d_ec# [i] > -65
            tShow = d_bt# [i]
        endif
    endfor
    tShow = tShow * 1.25
    if bb_luok = 1
        if bb_cross > tShow
            if bb_cross < tShow * 1.6
                tShow = bb_cross * 1.1
            endif
        endif
    endif
    aTmax = min (workDur, tShow)
    if aTmax <= t0 + 0.02
        aTmax = workDur
    endif
    @niceStep: aTmax, 6
    tickStep = ns_v

    # ---- title ----
    Font size: 13
    Select inner viewport: 0.6, 7.7, 0.15, 0.55
    Axes: 0, 1, 0, 1
    ttl$ = replace$ (inName$, "_", "\_ ", 0)
    Text: 0, "left", 0.62, "half", "##IR Analysis##   " + ttl$
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.15, 0.55
    Axes: 0, 1, 0, 1
    sub$ = fixed$ (srate, 0) + " Hz     " + fixed$ (totalDur, 3) +
    ... " s     start " + fixed$ (1000 * t0, 1) + " ms     blocks " +
    ... fixed$ (1000 * g_dt, 2) + " ms"
    Text: 0, "left", 0.16, "half", sub$

    # ---- panel A: energy-time curve ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 2.35
    aLmax = -1e30
    for i to d_n
        if d_bt# [i] <= aTmax
            if d_bl# [i] > aLmax
                aLmax = d_bl# [i]
            endif
        endif
    endfor
    aTop = aLmax + 5
    aLmin = aLmax - 80
    if bb_noise <> undefined
        aLmin = bb_noise - 15
    endif
    if aLmin > aLmax - 25
        aLmin = aLmax - 25
    endif
    if aLmin < aLmax - 100
        aLmin = aLmax - 100
    endif
    Axes: 0, aTmax, aLmin, aTop
    Paint rectangle: {0.97, 0.97, 0.97}, 0, aTmax, aLmin, aTop
    Colour: {0.35, 0.35, 0.35}
    started = 0
    for i to d_n
        xx = d_bt# [i]
        if xx <= aTmax
            yy = d_bl# [i]
            if yy < aLmin
                yy = aLmin
            endif
            if yy > aTop
                yy = aTop
            endif
            if started = 1
                Draw line: prevx, prevy, xx, yy
            endif
            prevx = xx
            prevy = yy
            started = 1
        endif
    endfor
    if bb_noise <> undefined
        if bb_noise > aLmin
            if bb_noise < aTop
                Colour: {0.85, 0.20, 0.20}
                Dashed line
                Draw line: 0, bb_noise, aTmax, bb_noise
                Solid line
            endif
        endif
    endif
    if bb_cross < aTmax
        Colour: {0.20, 0.40, 0.80}
        Dotted line
        Draw line: bb_cross, aLmin, bb_cross, aTop
        Solid line
    endif
    Colour: {0.00, 0.00, 0.00}
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.95, 2.35
    Axes: 0, aTmax, aLmin, aTop
    Draw inner box
    Select inner viewport: 0.6, 7.7, 0.95, 2.35
    Axes: 0, aTmax, aLmin, aTop
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    Marks left every: 1, 20, "yes", "yes", "no"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 2.35
    Axes: 0, 1, 0, 1
    Text: 0, "left", 1.05, "bottom", "##Energy-time curve##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.95, 2.35
    Axes: 0, 1, 0, 1
    Text: 1, "right", 1.05, "bottom",
    ... "red = noise floor      blue = truncation point"

    # ---- panel B: Schroeder decay ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.95, 4.75
    Axes: 0, aTmax, -70, 5
    Paint rectangle: {0.97, 0.97, 0.97}, 0, aTmax, -70, 5
    Colour: {0.75, 0.75, 0.75}
    Dotted line
    Draw line: 0, -5, aTmax, -5
    Draw line: 0, -25, aTmax, -25
    Draw line: 0, -35, aTmax, -35
    Solid line
    Colour: {0.20, 0.40, 0.80}
    Line width: 1.5
    started = 0
    for i from d_i0 to d_iEnd
        xx = d_bt# [i]
        if xx <= aTmax
            yy = d_ec# [i]
            if yy < -70
                yy = -70
            endif
            if yy > 5
                yy = 5
            endif
            if started = 1
                Draw line: prevx, prevy, xx, yy
            endif
            prevx = xx
            prevy = yy
            started = 1
        endif
    endfor
    Line width: 1
    if bb_t30ok = 1
        Colour: {0.85, 0.20, 0.20}
        @drawFit: d_t30_slope, d_t30_icpt, d_t30_t1, d_t30_t2, aTmax
    endif
    if bb_t20ok = 1
        Colour: {0.10, 0.60, 0.30}
        @drawFit: d_t20_slope, d_t20_icpt, d_t20_t1, d_t20_t2, aTmax
    endif
    Colour: {0.00, 0.00, 0.00}
    Line width: 1
    Font size: 6
    Select inner viewport: 0.6, 7.7, 2.95, 4.75
    Axes: 0, aTmax, -70, 5
    Draw inner box
    Select inner viewport: 0.6, 7.7, 2.95, 4.75
    Axes: 0, aTmax, -70, 5
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    Marks left every: 1, 10, "yes", "yes", "no"
    Text bottom: "yes", "time (s)"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.95, 4.75
    Axes: 0, 1, 0, 1
    Text: 0, "left", 1.04, "bottom", "##Schroeder decay curve (dB)##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, 2.95, 4.75
    Axes: 0, 1, 0, 1
    Text: 1, "right", 1.04, "bottom",
    ... "green = T20 fit      red = T30 fit"

    # ---- panel C: octave bands ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 5.35, 6.85
    if nBands > 0
        cmax = 0
        for k to nBands
            if bd_ok30# [k] = 1
                if bd_t30# [k] > cmax
                    cmax = bd_t30# [k]
                endif
            endif
            if bd_okedt# [k] = 1
                if bd_edt# [k] > cmax
                    cmax = bd_edt# [k]
                endif
            endif
        endfor
        if cmax <= 0
            cmax = 1
        endif
        cmax = cmax * 1.3
        Axes: 0.5, nBands + 0.5, 0, cmax
        Paint rectangle: {0.97, 0.97, 0.97}, 0.5, nBands + 0.5, 0, cmax
        for k to nBands
            if bd_ok30# [k] = 1
                Paint rectangle: {0.20, 0.40, 0.80}, k - 0.34, k - 0.03,
                ... 0, bd_t30# [k]
            endif
            if bd_okedt# [k] = 1
                Paint rectangle: {0.90, 0.60, 0.20}, k + 0.03, k + 0.34,
                ... 0, bd_edt# [k]
            endif
        endfor
        Colour: {0.00, 0.00, 0.00}
        Font size: 6
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0.5, nBands + 0.5, 0, cmax
        Draw inner box
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0.5, nBands + 0.5, 0, cmax
        @niceStep: cmax, 4
        Marks left every: 1, ns_v, "yes", "yes", "no"
        for k to nBands
            fcv = bd_fc# [k]
            if fcv >= 1000
                lb$ = fixed$ (fcv / 1000, 0) + "k"
            else
                lb$ = fixed$ (fcv, 0)
            endif
            One mark bottom: k, "no", "yes", "no", lb$
        endfor
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0.5, nBands + 0.5, 0, cmax
        for k to nBands
            if bd_ok30# [k] = 0
                Text: k, "centre", 0.05 * cmax, "bottom", "n/a"
            endif
        endfor
        Font size: 7
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0, 1, 0, 1
        Text: 0, "left", 1.05, "bottom",
        ... "##Reverberation time by octave band (s)##"
        Font size: 6
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0, 1, 0, 1
        Text: 1, "right", 1.05, "bottom",
        ... "blue = T30      orange = EDT      not IEC 61260 filters"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: {0.97, 0.97, 0.97}, 0, 1, 0, 1
        Colour: {0.00, 0.00, 0.00}
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0, 1, 0, 1
        Draw inner box
        Select inner viewport: 0.6, 7.7, 5.35, 6.85
        Axes: 0, 1, 0, 1
        Text: 0.5, "centre", 0.5, "half", "octave band analysis not requested"
    endif

    # ---- panel D: summary ----
    Font size: 7
    Select inner viewport: 0.6, 7.7, 7.30, 8.80
    Axes: 0, 1, 0, 1
    Paint rectangle: {0.94, 0.94, 0.94}, 0, 1, 0, 1
    Colour: {0.00, 0.00, 0.00}
    Select inner viewport: 0.6, 7.7, 7.30, 8.80
    Axes: 0, 1, 0, 1
    Draw inner box
    Select inner viewport: 0.6, 7.7, 7.30, 8.80
    Axes: 0, 1, 0, 1
    if bb_t30ok = 1
        @fmt: bb_t30, 3
    else
        @fmt: undefined, 3
    endif
    @withUnit: fmt$, " s"
    sT30$ = "T30   " + withUnit$
    if bb_t20ok = 1
        @fmt: bb_t20, 3
    else
        @fmt: undefined, 3
    endif
    @withUnit: fmt$, " s"
    sT20$ = "T20   " + withUnit$
    if bb_edtok = 1
        @fmt: bb_edt, 3
    else
        @fmt: undefined, 3
    endif
    @withUnit: fmt$, " s"
    sEDT$ = "EDT   " + withUnit$
    @fmt: bb_snr, 1
    sSNR$ = "peak-to-noise  " + fmt$ + " dB"
    @fmt: c50, 2
    @withUnit: fmt$, " dB"
    sC50$ = "C50   " + withUnit$
    @fmt: c80, 2
    @withUnit: fmt$, " dB"
    sC80$ = "C80   " + withUnit$
    @fmt: d50, 1
    @withUnit: fmt$, " \%  "
    sD50$ = "D50   " + withUnit$
    @fmt: ts, 1
    @withUnit: fmt$, " ms"
    sTs$ = "Ts    " + withUnit$
    @fmt: bb_noise, 1
    sNF$ = "noise floor   " + fmt$ + " dB"
    sTR$ = "truncation    " + fixed$ (1000 * bb_cross, 0) + " ms"
    Text: 0.03, "left", 0.87, "half", "##Summary##"
    Text: 0.03, "left", 0.66, "half", sT30$
    Text: 0.03, "left", 0.50, "half", sT20$
    Text: 0.03, "left", 0.34, "half", sEDT$
    Text: 0.03, "left", 0.16, "half", sSNR$
    Text: 0.38, "left", 0.66, "half", sC50$
    Text: 0.38, "left", 0.50, "half", sC80$
    Text: 0.38, "left", 0.34, "half", sD50$
    Text: 0.38, "left", 0.16, "half", sTs$
    Text: 0.72, "left", 0.66, "half", sNF$
    Text: 0.72, "left", 0.50, "half", sTR$
    if bb_curv <> undefined
        Text: 0.72, "left", 0.34, "half",
        ... "curvature   " + fixed$ (bb_curv, 1) + " \%  "
    endif
    Text: 0.72, "left", 0.16, "half", "analysed  " + chanNote$

    # ---- panel E: measured vs sculpted envelope (only when both exist) ----
    if showCompare = 1
        selectObject: prepId
        pDur = Get total duration
        selectObject: creId
        cDur = Get total duration
        cmpT = max (pDur, cDur)
        keepDt2 = g_dt
        g_dt = cmpT / 350
        if g_dt < 4 / srate
            g_dt = 4 / srate
        endif
        @blockEnergies: prepId, pDur
        nP = g_n
        cmpP# = zero# (nP)
        cmpPT# = zero# (nP)
        cmpRef = 0
        for i to nP
            cmpP# [i] = g_be# [i]
            cmpPT# [i] = g_bt# [i]
            if g_be# [i] > cmpRef
                cmpRef = g_be# [i]
            endif
        endfor
        @blockEnergies: creId, cDur
        nC = g_n
        cmpC# = zero# (nC)
        cmpCT# = zero# (nC)
        for i to nC
            cmpC# [i] = g_be# [i]
            cmpCT# [i] = g_bt# [i]
        endfor
        g_dt = keepDt2
        if cmpRef <= 0
            cmpRef = 1
        endif
        Font size: 7
        Select inner viewport: 0.6, 7.7, 9.10, 10.40
        Axes: 0, cmpT, -70, 5
        Paint rectangle: {0.97, 0.97, 0.97}, 0, cmpT, -70, 5
        # grey = measured, orange = sculpted; the same two colours the rest
        # of the figure already uses for measured and derived quantities
        Colour: {0.35, 0.35, 0.35}
        started = 0
        for i to nP
            xx = cmpPT# [i]
            yy = -70
            if cmpP# [i] > 0
                yy = 10 * log10 (cmpP# [i] / cmpRef)
            endif
            if yy < -70
                yy = -70
            endif
            if yy > 5
                yy = 5
            endif
            if started = 1
                Draw line: prevx, prevy, xx, yy
            endif
            prevx = xx
            prevy = yy
            started = 1
        endfor
        Colour: {0.90, 0.60, 0.20}
        started = 0
        for i to nC
            xx = cmpCT# [i]
            yy = -70
            if cmpC# [i] > 0
                yy = 10 * log10 (cmpC# [i] / cmpRef)
            endif
            if yy < -70
                yy = -70
            endif
            if yy > 5
                yy = 5
            endif
            if started = 1
                Draw line: prevx, prevy, xx, yy
            endif
            prevx = xx
            prevy = yy
            started = 1
        endfor
        Colour: {0.00, 0.00, 0.00}
        Font size: 6
        Select inner viewport: 0.6, 7.7, 9.10, 10.40
        Axes: 0, cmpT, -70, 5
        Draw inner box
        Select inner viewport: 0.6, 7.7, 9.10, 10.40
        Axes: 0, cmpT, -70, 5
        @niceStep: cmpT, 6
        Marks bottom every: 1, ns_v, "yes", "yes", "no"
        Marks left every: 1, 20, "yes", "yes", "no"
        Text bottom: "yes", "time (s)"
        Font size: 7
        Select inner viewport: 0.6, 7.7, 9.10, 10.40
        Axes: 0, 1, 0, 1
        Text: 0, "left", 1.04, "bottom", "##Prepared vs sculpted IR (dB)##"
        Font size: 6
        Select inner viewport: 0.6, 7.7, 9.10, 10.40
        Axes: 0, 1, 0, 1
        Text: 1, "right", 1.04, "bottom",
        ... "grey = prepared      orange = creative"
    endif

    Select outer viewport: 0, canvasW, 0, canvasH
endif

procedure drawFit: .slope, .icpt, .t1, .t2, .tmax
    if .slope <> undefined
        .a = .t1
        .b = .t2
        if .b > .tmax
            .b = .tmax
        endif
        .ya = .icpt + .slope * .a
        .yb = .icpt + .slope * .b
        if .ya > 5
            .ya = 5
        endif
        if .yb < -70
            .yb = -70
        endif
        Line width: 1.5
        Draw line: .a, .ya, .b, .yb
        Line width: 1
    endif
endproc

# ==========================================================================
# 14.  finish - remove only internal temporaries, keep every requested output
# ==========================================================================
removeObject: work
if prepId <> 0
    if prepare_convolution_ready_IR = 0
        # it was only ever an internal base for sculpting or audition
        removeObject: prepId
        prepId = 0
    endif
endif
if elDelivered = 0
    if earlyId <> 0
        removeObject: earlyId
        earlyId = 0
    endif
    if lateId <> 0
        removeObject: lateId
        lateId = 0
    endif
endif

lastId = inSound
if prepId <> 0
    lastId = prepId
endif
if elDelivered = 1
    lastId = lateId
endif
if creId <> 0
    lastId = creId
endif
if audId <> 0
    lastId = audId
endif
selectObject: lastId
if play
    Play
endif
