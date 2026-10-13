# ============================================================
# Praat AudioTools - Intelligent Mastering Maximizer
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# Category: Dynamics & Envelope
#
# Description:
#   Offline, two-pass, program-dependent mastering maximizer in pure Praat.
#   Pass 1 analyses the whole file (sample peak, oversampled true peak,
#   BS.1770 integrated / short-term loudness and LRA, RMS, crest factor,
#   transient density, local crest, stereo correlation and channel peaks).
#   Pass 2 renders a stereo-linked lookahead peak limiter whose release time
#   and knee are driven, sample by sample, by the analysis, optionally inside
#   a bounded search for the drive that reaches a LUFS target, followed by
#   oversampled true-peak verification and correction.
#
# DSP architecture (at a CONTROL RATE of sr / B, B a power of two giving
# 4-8 kHz, except where noted):
#   1. True-peak sidechain. The input is oversampled 4x/8x/16x in chunks by
#      ideal band-limited interpolation (zero-stuffing + FFT brick-wall; see
#      osScan for why not Praat's windowed-sinc Resample), rectified, maxed
#      across channels (stereo LINK) and reduced to one value per control
#      block by a max-pyramid over the block's oversampled cell. Computed
#      once; scaling by the drive is exact.
#   2. Static gain computer in dB with a soft knee CENTRED on the ceiling:
#      the knee output never exceeds the ceiling at any level, so the knee is
#      a shape choice and never a safety compromise.
#   3. Lookahead = symmetric minimum-hold (radius Lh) followed by two cascaded
#      box averages (radii b1 + b2 <= Lh). Because every value inside the
#      final averaging window is already <= the gain required at the peak,
#      the gain at the peak is guaranteed to be <= the required gain
#      (an average of values that are each below a bound is below it).
#      The cascade gives a quadratic S-shaped attack spanning the lookahead
#      instead of a step, which is what removes clicks and attack splatter.
#   4. Program-dependent release in the dB domain, between the hold and the
#      boxes: r[n] = min(h[n], r[n-1] * alpha[n]) (instant attack, exponential
#      recovery of gain reduction). alpha[n] comes from a per-sample time
#      constant tau[n] in [Min release, Max release] (see ADAPTIVE RELEASE).
#   5. Gain is converted to linear and applied to both channels with linear
#      interpolation between control samples. Interpolating two values that
#      are each below a bound stays below it, so the guarantee survives.
#   6. Verification: the rendered output is oversampled again (same factor)
#      and its reconstructed peak measured. If it exceeds the ceiling, the
#      limiter is re-rendered with an internal ceiling lowered by the excess
#      (local correction, up to 3 times); only if that still fails is a
#      global gain trim applied. All values reported come from measurements.
#
# ADAPTIVE RELEASE (log-interpolation between Min and Max release):
#   local crest factor CF (oversampled peak / RMS over +-25 ms) is mapped to
#   x = clamp((CF - 4 dB) / 12 dB, 0, 1)  [sine = 3 dB -> 0, sparse hits -> 1]
#   tau = sqrt(Rmin*Rmax) * (Rmax/Rmin) ^ (S * (0.5 - x))
#   S = Adaptive release strength. S = 0: fixed geometric-mean release.
#   S = 1: sustained material releases at Rmax (no waveform-following
#   modulation distortion on bass / sines), impulsive material at Rmin (the
#   gain is back before the next hit). S < 0 inverts the mapping (used by the
#   Experimental mode). Two further terms, both clamped to [Rmin, Rmax]:
#   - gain-reduction history: tau * (1 + |S| * clamp(GRslow / 6 dB, 0, 1)),
#     GRslow = mean required reduction over +-200 ms (sustained limiting ->
#     slower release -> less pumping on dense textures);
#   - transient shortening: tau * (1 - 0.6 * P * Wpast), Wpast = transient
#     index held over the past 60 ms, P = Transient preservation.
#
# TRANSIENT PRESERVATION (P, 0..100 %):
#   Transient index W = clamp((onset_dB - 4) / 8, 0, 1), onset_dB = 5 ms
#   energy over the preceding 10-300 ms energy. P acts in three places:
#   (a) knee width is reduced on transients: K * (1 - P * W) - a transient is
#       allowed up to the ceiling instead of being softened below it;
#   (b) release after a transient is shortened (above) so a hit's reduction
#       does not spill onto the following hits;
#   (c) in automatic targeting, the mean reduction ON transients is limited
#       to Budget * (1 - 0.8 * P). This is the honest trade-off: with a fixed
#       ceiling, protecting transients means accepting less loudness.
#   No stage ever boosts a transient; preservation only withholds reduction,
#   and the ceiling guarantee (steps 3-6) is independent of P.
#
# MEASUREMENT NOTES / LIMITATIONS:
#   - Integrated loudness, short-term loudness and LRA reported for the input
#     and the final output use the exact BS.1770 recursive K-weighting
#     biquads (coefficients as in LUFS_Tool v4.3), 400 ms / 75 % blocks with
#     -70 LUFS absolute and -10 LU relative gates, channel weights 1 (mono /
#     stereo only). LRA follows EBU Tech 3342 (3 s windows, 10 Hz, -20 LU
#     relative gate, 10th-95th percentile) without trailing padding.
#   - INSIDE the drive search only, loudness is measured with a zero-phase
#     FFT implementation of the same K-weighting magnitude response, which
#     is ~10x faster; its offset to the exact meter is measured on the input
#     and subtracted. The final reported figure is always the exact meter.
#   - True peak: max |sample| of the ideally interpolated, oversampled signal
#     (the BS.1770 Annex 2 principle with a brick-wall instead of a 48-tap
#     FIR). Remaining error is grid granularity only, worst case for content
#     at Nyquist -0.69 / -0.17 / -0.04 dB at 4x / 8x / 16x; real programme
#     with little energy above ~16 kHz reads far closer. Use 8x or 16x when
#     the ceiling must hold for full-band material. It is an ESTIMATE of the
#     reconstructed peak: a real DAC's reconstruction filter attenuates the
#     band near Nyquist and will usually read LOWER, never higher.
#   - The peak guarantee of steps 3-5 is exact on the control-rate sidechain;
#     the product of a smooth gain and the signal can still overshoot by a
#     few hundredths of a dB between cells, which is why step 6 exists.
#   - Mono and stereo only. >2 channels are refused rather than mis-weighted.
#
# Notes:
#   - "Show dynamics settings" (and the Custom mode) opens a second dialog
#     pre-filled with the selected mode. On headless Praat 6.4.63 / 7.0 a
#     pause dialog terminates a --run script silently: keep it off in batch.
#   - Processing cost is dominated by the oversampled sidechain and the final
#     exact loudness measurement, both O(N); the search runs at control rate
#     plus one FFT per evaluation.
# ============================================================

# Changelog v1.0 (2026):
#   - Initial release.
#
# Validation (Intelligent_Mastering_Maximizer_Validation.praat, run headless
# on Praat 6.4.06 / 6.4.63 / 7.0, identical results across builds):
#   - Ceiling, all 6 modes x 12 synthetic cases, against an independent
#     ideal 32x reconstruction (64 silent samples either side): worst
#     -0.978 -> after the per-factor internal margin -1.003 dBTP at 4x
#     (ceiling -1.0); 8x worst -1.017.
#   - Stereo link error (max |gain L - gain R|): 4e-15 dB.
#   - Max sample-to-sample gain step: 0.03-0.09 dB (no clicks).
#   - 40 Hz sine under 3 dB of limiting, THD: Transparent 0.09 %, Dense
#     0.11 %, Balanced 0.29 %, Punch 0.61 %, Aggressive 0.71 %,
#     Experimental 6.7 % (intended).
#   - Recovery after an isolated hit (to within 0.5 dB): Punch 15 ms,
#     Aggressive 195, Balanced 345, Transparent 540, Dense 1015 ms.
#   - Loudness search: within 0.01 LU of target in 2 evaluations when the
#     budget allows; otherwise the loudest valid drive plus a warning.
#   - Speed: ~1.1x real time for 48 kHz stereo at 4x, ~1.8x at 8x.
#
form Intelligent Mastering Maximizer v1.0
    optionmenu Mode 2
        option Transparent
        option Balanced
        option Punch
        option Dense
        option Aggressive
        option Experimental
        option Custom
    comment === Loudness ===
    boolean Automatic_loudness_targeting 1
    optionmenu Target 3
        option -18 LUFS Dynamic
        option -16 LUFS Gentle
        option -14 LUFS Streaming
        option -12 LUFS Loud
        option -10 LUFS Aggressive
        option Custom target
    real Custom_target_LUFS -14.0
    real Manual_drive_dB 0.0
    comment === Peak Control & Output ===
    real True_peak_ceiling_dBTP -1.0
    optionmenu Oversampling 1
        option 4x Standard
        option 8x High
        option 16x Very high
    real Output_trim_dB 0.0
    boolean Show_dynamics_settings 0
    boolean Generate_analysis_report 1
    boolean Visualize 1
    boolean Play 1
endform

# ============================================================
# INPUT SELECTION CHECK
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: sound
sr = Get sampling frequency
start_time = Get start time
end_time = Get end time
dur = end_time - start_time
nChannels = Get number of channels
nBase = Get number of samples
bx1 = Get time from sample number: 1

if nChannels > 2
    exitScript: "Validation Error: mono or stereo Sound required (input has " + string$(nChannels) + " channels)."
endif
if dur < 0.01
    exitScript: "Validation Error: Sound is shorter than 10 ms."
endif

# ============================================================
# MODE PRESETS (meaningful algorithmic configurations)
#   la   = lookahead (ms)            rmin/rmax = release limits (ms)
#   ars  = adaptive release strength (-1..1)
#   tpp  = transient preservation (%) knee = knee width (dB)
#   grb  = gain-reduction budget (dB) used by automatic targeting
# ============================================================
if mode = 1
    la = 5.0
    rmin = 40
    rmax = 400
    ars = 0.7
    tpp = 80
    knee = 3.0
    grb = 4.0
    modeName$ = "Transparent"
elsif mode = 2 or mode = 7
    la = 3.0
    rmin = 25
    rmax = 300
    ars = 0.6
    tpp = 50
    knee = 2.0
    grb = 7.0
    modeName$ = "Balanced"
elsif mode = 3
    la = 1.5
    rmin = 10
    rmax = 150
    ars = 0.8
    tpp = 85
    knee = 1.0
    grb = 8.0
    modeName$ = "Punch"
elsif mode = 4
    la = 4.0
    rmin = 60
    rmax = 800
    ars = 0.5
    tpp = 20
    knee = 4.0
    grb = 10.0
    modeName$ = "Dense"
elsif mode = 5
    la = 2.0
    rmin = 15
    rmax = 200
    ars = 0.5
    tpp = 15
    knee = 1.0
    grb = 16.0
    modeName$ = "Aggressive"
else
    # Experimental: inverted program dependence. Impulsive material gets the
    # LONG release (each hit ducks and swells back - breathing), sustained
    # material the SHORT one (waveform-following reduction - density / grit).
    # Hard knee, no transient protection, no reduction budget. Still peak-safe.
    la = 1.0
    rmin = 5
    rmax = 1500
    ars = -1.0
    tpp = 0
    knee = 0.0
    grb = 60.0
    modeName$ = "Experimental"
endif

if mode = 7
    modeName$ = "Custom"
endif

# Pause-field variables initialised before the dialog (some builds skip
# field assignment when a pause auto-continues).
lookahead_ms = la
minimum_release_ms = rmin
maximum_release_ms = rmax
adaptive_release_strength = ars
transient_preservation = tpp
knee_dB = knee
gain_reduction_budget_dB = grb

if show_dynamics_settings or mode = 7
    beginPause: "Dynamics settings (" + modeName$ + ")"
        comment: "Pre-filled from the selected mode."
        real: "Lookahead ms", string$(la)
        real: "Minimum release ms", string$(rmin)
        real: "Maximum release ms", string$(rmax)
        real: "Adaptive release strength", string$(ars)
        real: "Transient preservation", string$(tpp)
        real: "Knee dB", string$(knee)
        real: "Gain reduction budget dB", string$(grb)
    endPause: "Continue", 1
    if lookahead_ms <> la or minimum_release_ms <> rmin or maximum_release_ms <> rmax or adaptive_release_strength <> ars or transient_preservation <> tpp or knee_dB <> knee or gain_reduction_budget_dB <> grb
        if mode <> 7
            modeName$ = modeName$ + " (edited)"
        endif
    endif
    la = lookahead_ms
    rmin = minimum_release_ms
    rmax = maximum_release_ms
    ars = adaptive_release_strength
    tpp = transient_preservation
    knee = knee_dB
    grb = gain_reduction_budget_dB
endif

# ============================================================
# PARAMETER VALIDATION GUARDRAILS
# ============================================================
if true_peak_ceiling_dBTP > 0 or true_peak_ceiling_dBTP < -20
    exitScript: "Validation Error: True_peak_ceiling_dBTP must be between -20 and 0 dBTP."
endif
if output_trim_dB > 0
    exitScript: "Validation Error: Output_trim_dB must be <= 0 dB (a positive trim would break the ceiling; raise the ceiling instead)."
endif
if output_trim_dB < -40
    exitScript: "Validation Error: Output_trim_dB must be >= -40 dB."
endif
if la < 0.5 or la > 20
    exitScript: "Validation Error: Lookahead must be between 0.5 and 20 ms."
endif
if rmin < 1 or rmax > 5000 or rmin > rmax
    exitScript: "Validation Error: releases must satisfy 1 <= Minimum <= Maximum <= 5000 ms."
endif
if ars < -1 or ars > 1
    exitScript: "Validation Error: Adaptive release strength must be between -1 and 1."
endif
if tpp < 0 or tpp > 100
    exitScript: "Validation Error: Transient preservation must be between 0 and 100 %."
endif
if knee < 0 or knee > 12
    exitScript: "Validation Error: Knee must be between 0 and 12 dB."
endif
if grb < 0.5
    exitScript: "Validation Error: Gain reduction budget must be >= 0.5 dB."
endif
if manual_drive_dB < -40 or manual_drive_dB > 36
    exitScript: "Validation Error: Manual_drive_dB must be between -40 and +36 dB."
endif

if target = 1
    target_LUFS = -18
elsif target = 2
    target_LUFS = -16
elsif target = 3
    target_LUFS = -14
elsif target = 4
    target_LUFS = -12
elsif target = 5
    target_LUFS = -10
else
    target_LUFS = custom_target_LUFS
endif
if target_LUFS > -3 or target_LUFS < -60
    exitScript: "Validation Error: target loudness must be between -60 and -3 LUFS."
endif

if oversampling = 1
    osf = 4
elsif oversampling = 2
    osf = 8
else
    osf = 16
endif

ceilDb = true_peak_ceiling_dBTP
tpP = tpp / 100
tauMid = sqrt(rmin * rmax) / 1000
tauLo = rmin / 1000
tauHi = rmax / 1000
lnRatio = ln(rmax / rmin)
warnCount = 0

stopwatch

# ============================================================
# INFO HEADER
# ============================================================
if generate_analysis_report
    clearinfo
    appendInfoLine: "=============================================="
    appendInfoLine: "  INTELLIGENT MASTERING MAXIMIZER v1.0"
    appendInfoLine: "=============================================="
    appendInfoLine: ""
    appendInfoLine: "Input: ", sound_name$, " (", fixed$(dur, 2), " s, ", sr, " Hz, ", nChannels, " ch)"
    appendInfoLine: "Mode: ", modeName$
    appendInfoLine: "Lookahead ", fixed$(la, 1), " ms | release ", fixed$(rmin, 0), "-", fixed$(rmax, 0), " ms | adaptive ", fixed$(ars, 2), " | transient ", fixed$(tpp, 0), " % | knee ", fixed$(knee, 1), " dB | budget ", fixed$(grb, 1), " dB"
    appendInfoLine: "Ceiling: ", fixed$(ceilDb, 2), " dBTP | true-peak oversampling ", osf, "x (ideal band-limited)"
    if automatic_loudness_targeting
        appendInfoLine: "Loudness: automatic, target ", fixed$(target_LUFS, 1), " LUFS"
    else
        appendInfoLine: "Loudness: manual drive ", fixed$(manual_drive_dB, 2), " dB"
    endif
    appendInfoLine: ""
endif

# ============================================================
# HELPER PROCEDURES
# ============================================================

# Running max (kind = 1) or min (kind = -1) over a FORWARD window of .w
# samples, in place: out[k] = extremum(in[k .. k + .w - 1]). Log-doubling:
# each pass reads only not-yet-overwritten future samples.
procedure runExtreme: .obj, .w, .kind
    selectObject: .obj
    .c = 1
    while .c < .w
        .s = min(.c, .w - .c)
        if .kind > 0
            Formula: ~ max(self, self[min(ncol, col + .s)])
        else
            Formula: ~ min(self, self[min(ncol, col + .s)])
        endif
        .c = .c + .s
    endwhile
endproc

# Centred running extremum of radius .r (window 2r + 1), in place.
procedure centredExtreme: .obj, .r, .kind
    if .r > 0
        @runExtreme: .obj, 2 * .r + 1, .kind
        selectObject: .obj
        .tmp = Copy: "tmp_extreme"
        selectObject: .obj
        Formula: ~ object[.tmp, 1, max(1, col - .r)]
        removeObject: .tmp
    endif
endproc

# Past-window extremum over the previous .w samples (inclusive), in place.
procedure pastExtreme: .obj, .w, .kind
    if .w > 0
        @runExtreme: .obj, .w + 1, .kind
        selectObject: .obj
        .tmp = Copy: "tmp_extreme"
        selectObject: .obj
        Formula: ~ object[.tmp, 1, max(1, col - .w)]
        removeObject: .tmp
    endif
endproc

# Centred box average of radius .r via a prefix sum; edge windows truncated.
procedure boxMean: .obj, .r
    if .r > 0
        selectObject: .obj
        .cs = Copy: "tmp_prefix"
        Formula: ~ if col = 1 then self else self + self[col - 1] fi
        selectObject: .obj
        Formula: ~ 0 + (object[.cs, 1, min(ncol, col + .r)] - (if col - .r - 1 >= 1 then object[.cs, 1, col - .r - 1] else 0 fi)) / (min(ncol, col + .r) - max(1, col - .r) + 1)
        removeObject: .cs
    endif
endproc

# Mean of the base-rate prefix sum .pp over the time window [x - .wa, x + .wb],
# written into the control-rate Sound .obj (window clamped to the file).
procedure windowMean: .obj, .pp, .wa, .wb
    selectObject: .obj
    Formula: ~ 0 + (object[.pp, 1, min(nBase, max(1, round((x + .wb - bx1) * sr) + 1))] - (if min(nBase, max(1, round((x - .wa - bx1) * sr) + 1)) > 1 then object[.pp, 1, min(nBase, max(1, round((x - .wa - bx1) * sr) + 1)) - 1] else 0 fi)) / (min(nBase, max(1, round((x + .wb - bx1) * sr) + 1)) - min(nBase, max(1, round((x - .wa - bx1) * sr) + 1)) + 1)
endproc

# Chunked oversampled peak scan of .snd at osf x.
#   Interpolation is IDEAL band-limited (zero-stuffing + FFT brick-wall at the
#   original Nyquist via Filter (pass Hann band), 10 Hz transition), not
#   Praat's windowed-sinc Resample: a windowed sinc of finite depth attenuates
#   the band just below Nyquist, and limiter output driven by full-band
#   material has energy there - measured: depth 24 read -1.00 dBTP where a
#   sinc700 evaluation read -0.75 at the same instant.
#   .tp : max |oversampled sample|. Each chunk's first oversampled sample is an
#   original sample instant, so every osf-th oversampled sample IS an original
#   sample and the estimate never reads below the sample peak. The remaining
#   error is grid granularity: a peak between oversampled points, worst case
#   cos(pi / (2 osf)) for content at Nyquist = -0.69 / -0.17 / -0.04 dB at
#   4x / 8x / 16x WITHOUT refinement; a 3-point parabolic vertex through each
#   oversampled extremum removes most of it (see validation numbers).
#   Chunks start on control-block boundaries, so a halving max-pyramid over
#   the oversampled stream (cost ~1 pass) yields one value per control block
#   cell (osf * ctrlB oversampled samples = the block's own samples plus the
#   reconstruction up to the next block). If .ctrl > 0 these cell maxima
#   (across channels = stereo link) are written into .ctrl.
procedure osScan: .snd, .ctrl
    selectObject: .snd
    .nch = Get number of channels
    .cb = ceiling(8 * sr / ctrlB)
    # margin (blocks) absorbs the circular-FFT / truncation transient at the
    # chunk edges: the brick-wall's impulse response decays as 1/t, so a few
    # thousand samples keep the edge error far below 0.001 dB
    .mg = ceiling(2048 / ctrlB)
    .nChunks = ceiling(nbk / .cb)
    .grp = osf * ctrlB
    .pad = ctrlB * ceiling(64 / ctrlB)
    .tp = 0
    for .ic from 1 to .nChunks
        # core control blocks (block m <-> base samples (m-2)B+1 .. (m-1)B)
        .mA = 2 + (.ic - 1) * .cb
        .mB = min(nbk + 1, .mA + .cb - 1)
        .jE0 = max(1, (.mA - 2 - .mg) * ctrlB + 1)
        .jE1 = min(nBase, (.mB - 1 + .mg) * ctrlB)
        if .ic = 1
            .mA = 1
        endif
        if .ic = .nChunks
            .mB = nbk + 2
        endif
        # the stream extends .pad samples of virtual silence beyond each file
        # edge: a signal that starts or stops abruptly rings in reconstruction
        # around its first / last sample (measured: +0.14 dB on a hard-gated
        # full-scale fs/4 tone), and those cells map onto the control grid's
        # pad blocks 1 and nbk + 2, so the limiter acts on them too
        .jZ0 = .jE0 - .pad
        .jZ1 = .jE1 + .pad
        .mE0 = (.jZ0 - 1) / ctrlB + 2
        .nOs = osf * (.jZ1 - .jZ0 + 1)
        .t0 = bx1 + (.jZ0 - 1) / sr - 0.5 / (osf * sr)
        # zero-stuffed stream: oversampled sample (j - jZ0) * osf + 1 = osf * x[j]
        .zs = Create Sound from formula: "tmp_zs", .nch, .t0, .t0 + .nOs / (osf * sr), osf * sr, ~ if (col - 1) mod osf = 0 then (if .jZ0 + (col - 1) div osf >= 1 and .jZ0 + (col - 1) div osf <= nBase then osf * object[.snd, row, .jZ0 + (col - 1) div osf] else 0 fi) else 0 fi
        .ip = Filter (pass Hann band): 0, sr / 2, 10
        removeObject: .zs
        # parabolic vertex through each oversampled local extremum (3 points):
        # recovers most of the grid-granularity loss and errs high, never low,
        # for a peak whose neighbourhood is locally concave. A grid sample can
        # understate its local peak by at most 1 / cos(pi / (2 osf)), so in
        # verification samples below (running max) * cos(...) cannot change
        # the result and are skipped exactly; in the sidechain every sample
        # within 20 dB of the chunk maximum is refined (lower cells could only
        # matter beyond 20 dB of reduction, which the verification still guards).
        selectObject: .ip
        .m0 = Get absolute extremum: 0, 0, "None"
        if .ctrl > 0
            .thr = .m0 * 0.1
        else
            .thr = max(.tp, .m0) * cos(pi / (2 * osf)) * 0.999
        endif
        .os = Copy: "tmp_vertex"
        # in place, left to right: self and self[col + 1] are still original,
        # only col - 1 has been overwritten, so it is read from .ip
        Formula: ~ if abs(self) < .thr or col = 1 or col = ncol then abs(self) else (if ((self >= object[.ip, row, col - 1] and self >= self[col + 1]) or (self <= object[.ip, row, col - 1] and self <= self[col + 1])) and abs(object[.ip, row, col - 1] - 2 * self + self[col + 1]) > 1e-15 then abs(self - (self[col + 1] - object[.ip, row, col - 1]) ^ 2 / (8 * (object[.ip, row, col - 1] - 2 * self + self[col + 1]))) else abs(self) fi) fi
        removeObject: .ip
        selectObject: .os
        # level 1: |x| maxed over channel(s) and over sample pairs
        .n = ceiling(.nOs / 2)
        if .nch = 1
            .lv = Create Sound from formula: "tmp_pyr", 1, 0, .n, 1, ~ max(object[.os, 1, 2 * col - 1], object[.os, 1, min(.nOs, 2 * col)])
        else
            .lv = Create Sound from formula: "tmp_pyr", 1, 0, .n, 1, ~ max(object[.os, 1, 2 * col - 1], object[.os, 1, min(.nOs, 2 * col)], object[.os, 2, 2 * col - 1], object[.os, 2, min(.nOs, 2 * col)])
        endif
        removeObject: .os
        .size = 2
        while .size < .grp
            .prev = .lv
            .np = .n
            .n = ceiling(.np / 2)
            .lv = Create Sound from formula: "tmp_pyr", 1, 0, .n, 1, ~ max(object[.prev, 1, 2 * col - 1], object[.prev, 1, min(.np, 2 * col)])
            removeObject: .prev
            .size = .size * 2
        endwhile
        # sample g of .lv (time g - 0.5) = cell of control block .mE0 + g - 1
        .gA = .mA - .mE0 + 1
        .gB = min(.n, .mB - .mE0 + 1)
        selectObject: .lv
        .m = Get maximum: .gA - 1, .gB, "None"
        if .m > .tp
            .tp = .m
        endif
        if .ctrl > 0
            selectObject: .ctrl
            .cx1 = Get time from sample number: 1
            Formula (part): .cx1 + (.mA - 1.5) / rc, .cx1 + (.mB - 0.5) / rc, 1, 1, ~ object[.lv, 1, max(1, min(.n, col - .mE0 + 1))]
        endif
        removeObject: .lv
    endfor
endproc

# Exact BS.1770 K-weighting biquads (recursive), coefficients for sr.
procedure kCoefficients
    hs_f0 = 1681.974450955533
    hs_Q = 0.7071752369554196
    hs_K = tan(pi * hs_f0 / sr)
    hs_Vh = 10 ^ (3.999843853973347 / 20)
    hs_Vb = hs_Vh ^ 0.4996667741545416
    hs_a0 = 1 + hs_K / hs_Q + hs_K * hs_K
    hs_b0 = (hs_Vh + hs_Vb * hs_K / hs_Q + hs_K * hs_K) / hs_a0
    hs_b1 = 2 * (hs_K * hs_K - hs_Vh) / hs_a0
    hs_b2 = (hs_Vh - hs_Vb * hs_K / hs_Q + hs_K * hs_K) / hs_a0
    hs_a1 = 2 * (hs_K * hs_K - 1) / hs_a0
    hs_a2 = (1 - hs_K / hs_Q + hs_K * hs_K) / hs_a0
    hp_f0 = 38.13547087602444
    hp_Q = 0.5003270373238773
    hp_K = tan(pi * hp_f0 / sr)
    hp_a0 = 1 + hp_K / hp_Q + hp_K * hp_K
    hp_b0 = 1.0
    hp_b1 = -2.0
    hp_b2 = 1.0
    hp_a1 = 2 * (hp_K * hp_K - 1) / hp_a0
    hp_a2 = (1 - hp_K / hp_Q + hp_K * hp_K) / hp_a0
    # |H_shelf(f)| * |H_highpass(f)| tabulated every 1 Hz (sample centres at
    # -0.5 .. nyquist + 0.5 Hz) for the FFT meter: linear interpolation of
    # this smooth response replaces ~1 trig evaluation per FFT bin.
    kTab = Create Sound from formula: "tmp_kmag", 1, -1, sr / 2 + 1, 1, ~ sqrt((((hs_b0 + hs_b1 * cos(2*pi*x/sr) + hs_b2 * cos(4*pi*x/sr)) ^ 2 + (hs_b1 * sin(2*pi*x/sr) + hs_b2 * sin(4*pi*x/sr)) ^ 2) / ((1 + hs_a1 * cos(2*pi*x/sr) + hs_a2 * cos(4*pi*x/sr)) ^ 2 + (hs_a1 * sin(2*pi*x/sr) + hs_a2 * sin(4*pi*x/sr)) ^ 2)) * (((hp_b0 + hp_b1 * cos(2*pi*x/sr) + hp_b2 * cos(4*pi*x/sr)) ^ 2 + (hp_b1 * sin(2*pi*x/sr) + hp_b2 * sin(4*pi*x/sr)) ^ 2) / ((1 + hp_a1 * cos(2*pi*x/sr) + hp_a2 * cos(4*pi*x/sr)) ^ 2 + (hp_a1 * sin(2*pi*x/sr) + hp_a2 * sin(4*pi*x/sr)) ^ 2)))
endproc

procedure biquad: .sig, .b0, .b1, .b2, .a1, .a2
    selectObject: .sig
    .xc = Copy: "tmp_biquad_x"
    selectObject: .sig
    Formula: ~ if col > 2 then .b0 * object[.xc, row, col] + .b1 * object[.xc, row, col - 1] + .b2 * object[.xc, row, col - 2] - .a1 * self[col - 1] - .a2 * self[col - 2] else self fi
    removeObject: .xc
endproc

# Channel-summed K-weighted power -> prefix-sum Sound (mono, base rate).
#   .method = 1 exact recursive biquads, 2 zero-phase FFT magnitude response.
procedure kPowerPrefix: .snd, .method
    selectObject: .snd
    .nch = Get number of channels
    if .method = 1
        .k = Copy: "tmp_k"
        @biquad: .k, hs_b0, hs_b1, hs_b2, hs_a1, hs_a2
        @biquad: .k, hp_b0, hp_b1, hp_b2, hp_a1, hp_a2
    else
        .k = Filter (formula): ~ self * object(kTab, x)
    endif
    selectObject: .k
    if .nch = 1
        .pp = Copy: "tmp_kprefix"
        Formula: ~ self * self
    else
        .pp = Extract one channel: 1
        Formula: ~ self * self + object[.k, 2, col] ^ 2
    endif
    Formula: ~ if col = 1 then self else self + self[col - 1] fi
    removeObject: .k
    kPowerPrefix.result = .pp
endproc

# Gated integrated loudness from a K-power prefix Sound (BS.1770).
procedure integratedFromPrefix: .pp
    .lb = round(0.4 * sr)
    .hb = round(0.1 * sr)
    .lufs = undefined
    .nBlk = 0
    if nBase >= .lb
        .nBlk = floor((nBase - .lb) / .hb) + 1
        .ms# = zero# (.nBlk)
        selectObject: .pp
        for .i to .nBlk
            .n0 = (.i - 1) * .hb + 1
            .n1 = .n0 + .lb - 1
            .v1 = Get value at sample number: 1, .n1
            if .n0 > 1
                .v0 = Get value at sample number: 1, .n0 - 1
            else
                .v0 = 0
            endif
            .ms#[.i] = max(0, (.v1 - .v0) / .lb)
        endfor
        .sa = 0
        .ca = 0
        for .i to .nBlk
            if .ms#[.i] > 0
                if -0.691 + 10 * log10(.ms#[.i]) > -70
                    .sa = .sa + .ms#[.i]
                    .ca = .ca + 1
                endif
            endif
        endfor
        if .ca > 0
            .rel = -0.691 + 10 * log10(.sa / .ca) - 10
            .sr2 = 0
            .cr = 0
            for .i to .nBlk
                if .ms#[.i] > 0
                    .bl = -0.691 + 10 * log10(.ms#[.i])
                    if .bl > -70 and .bl > .rel
                        .sr2 = .sr2 + .ms#[.i]
                        .cr = .cr + 1
                    endif
                endif
            endfor
            if .cr > 0
                .lufs = -0.691 + 10 * log10(.sr2 / .cr)
            endif
        endif
    endif
endproc

# Short-term loudness (3 s, 10 Hz) and EBU Tech 3342 LRA from a prefix.
# Results in globals stN, stT#, stL#, lraVal, maxST (or undefined).
procedure shortTermFromPrefix: .pp
    .lw = round(3 * sr)
    .hb = round(0.1 * sr)
    stN = 0
    lraVal = undefined
    maxST = undefined
    if nBase >= .lw
        stN = floor((nBase - .lw) / .hb) + 1
        stT# = zero# (stN)
        stL# = zero# (stN)
        .ms# = zero# (stN)
        selectObject: .pp
        maxST = -200
        for .i to stN
            .n0 = (.i - 1) * .hb + 1
            .n1 = .n0 + .lw - 1
            .v1 = Get value at sample number: 1, .n1
            if .n0 > 1
                .v0 = Get value at sample number: 1, .n0 - 1
            else
                .v0 = 0
            endif
            .ms#[.i] = max(0, (.v1 - .v0) / .lw)
            if .ms#[.i] > 0
                stL#[.i] = -0.691 + 10 * log10(.ms#[.i])
            else
                stL#[.i] = -200
            endif
            stT#[.i] = bx1 + ((.n0 + .n1) / 2 - 1) / sr
            if stL#[.i] > maxST
                maxST = stL#[.i]
            endif
        endfor
        .sa = 0
        .ca = 0
        for .i to stN
            if stL#[.i] > -70
                .sa = .sa + .ms#[.i]
                .ca = .ca + 1
            endif
        endfor
        if .ca > 0
            .rel = -0.691 + 10 * log10(.sa / .ca) - 20
            .ng = 0
            for .i to stN
                if stL#[.i] > -70 and stL#[.i] > .rel
                    .ng = .ng + 1
                endif
            endfor
            if .ng >= 2
                .g# = zero# (.ng)
                .j = 0
                for .i to stN
                    if stL#[.i] > -70 and stL#[.i] > .rel
                        .j = .j + 1
                        .g#[.j] = stL#[.i]
                    endif
                endfor
                .sorted# = sort# (.g#)
                .lo = round((.ng - 1) * 0.10 + 1)
                .hi = round((.ng - 1) * 0.95 + 1)
                lraVal = max(0, .sorted#[.hi] - .sorted#[.lo])
            elsif .ng = 1
                lraVal = 0
            endif
        endif
    endif
endproc

# Level / crest / balance statistics of a Sound (linear values + dB).
procedure levelStats: .snd
    selectObject: .snd
    .mx = Get maximum: 0, 0, "None"
    .mn = Get minimum: 0, 0, "None"
    .peak = max(abs(.mx), abs(.mn))
    .nch = Get number of channels
    .pw = 0
    for .c to .nch
        selectObject: .snd
        .ch = Extract one channel: .c
        .r = Get root-mean-square: 0, 0
        .chMx = Get maximum: 0, 0, "None"
        .chMn = Get minimum: 0, 0, "None"
        .chPeak[.c] = max(abs(.chMx), abs(.chMn))
        .dc[.c] = Get mean: 1, 0, 0
        .pw = .pw + .r * .r / .nch
        if .c = 1
            .first = .ch
        else
            selectObject: .ch
            Formula: ~ self * object[.first, 1, col]
            .lr = Get mean: 1, 0, 0
            removeObject: .ch
        endif
    endfor
    .corr = undefined
    if .nch = 2
        .p1 = .chPeak[1]
        selectObject: .first
        .r1 = Get root-mean-square: 0, 0
        selectObject: .snd
        .ch2 = Extract one channel: 2
        .r2 = Get root-mean-square: 0, 0
        removeObject: .ch2
        if .r1 > 1e-12 and .r2 > 1e-12
            .corr = .lr / (.r1 * .r2)
        endif
    endif
    removeObject: .first
    .rms = sqrt(.pw)
    .peakDb = 20 * log10(.peak + 1e-12)
    .rmsDb = 20 * log10(.rms + 1e-12)
    .crestDb = .peakDb - .rmsDb
endproc

# ============================================================
# PASS 1 - ANALYSIS
# ============================================================
if generate_analysis_report
    appendInfoLine: "PASS 1 - ANALYSIS"
endif

@kCoefficients

@levelStats: sound
inPeak = levelStats.peak
inPeakDb = levelStats.peakDb
inRmsDb = levelStats.rmsDb
inCrestDb = levelStats.crestDb
inCorr = levelStats.corr
inPw = levelStats.pw
# Relative activity threshold: 40 dB below the file's mean power.
nsThresh = max(1e-14, inPw * 1e-4)
for c to nChannels
    inChPeak[c] = levelStats.chPeak[c]
    inDc[c] = levelStats.dc[c]
    if abs(inDc[c]) > 0.001
        warnCount = warnCount + 1
        warn$[warnCount] = "Channel " + string$(c) + " DC offset " + fixed$(inDc[c], 4) + " (" + fixed$(20 * log10(abs(inDc[c])), 1) + " dBFS): DC uses headroom and is amplified with the drive; consider a high-pass first."
    endif
endfor

bypass = 0
bypassReason$ = ""
if inPeak < 1e-9
    bypass = 1
    bypassReason$ = "Input is digitally silent (peak < -180 dBFS); output is an unprocessed copy."
endif

# Control grid (~4-8 kHz, power-of-two block of ctrlB samples). Block m covers base samples [(m-2)B+1, (m-1)B];
# one empty pad block either side keeps linear interpolation inside domain.
ctrlB = max(1, 2 ^ round(log2(sr / 6000)))
rc = sr / ctrlB
nbk = ceiling(nBase / ctrlB)
ctrlStart = bx1 - 0.5 / sr - ctrlB / sr
ctrlDur = (nbk + 2) * ctrlB / sr

inTp = inPeak
inTpDb = inPeakDb
inLufs = undefined
inLra = undefined
inMaxST = undefined
inStN = 0
transientRate = 0
meanTau = undefined

if bypass = 0
    # --- Exact input loudness (BS.1770, recursive K-weighting) ---
    @kPowerPrefix: sound, 1
    kpIn = kPowerPrefix.result
    @integratedFromPrefix: kpIn
    inLufs = integratedFromPrefix.lufs
    @shortTermFromPrefix: kpIn
    inLra = lraVal
    inMaxST = maxST
    inStN = stN
    if inStN > 0
        inStT# = stT#
        inStL# = stL#
    endif
    removeObject: kpIn

    # --- FFT-meter calibration offset (used only inside the search) ---
    fftOffset = 0
    if inLufs <> undefined
        @kPowerPrefix: sound, 2
        kpF = kPowerPrefix.result
        @integratedFromPrefix: kpF
        if integratedFromPrefix.lufs <> undefined
            fftOffset = inLufs - integratedFromPrefix.lufs
        endif
        removeObject: kpF
    endif

    # --- True-peak sidechain (control rate) + input true peak ---
    pk = Create Sound from formula: "tmp_sidechain", 1, ctrlStart, ctrlStart + ctrlDur, rc, "0"
    @osScan: sound, pk
    inTp = osScan.tp
    inTpDb = 20 * log10(inTp + 1e-12)

    # --- Base-rate channel-mean power prefix (for envelope features) ---
    selectObject: sound
    if nChannels = 1
        powPre = Copy: "tmp_powprefix"
        Formula: ~ self * self
    else
        powPre = Extract one channel: 1
        Formula: ~ (self * self + object[sound, 2, col] ^ 2) / 2
    endif
    Formula: ~ if col = 1 then self else self + self[col - 1] fi

    selectObject: pk
    pwF = Copy: "tmp_pwF"
    @windowMean: pwF, powPre, 0.0025, 0.0025
    selectObject: pk
    pwM = Copy: "tmp_pwM"
    @windowMean: pwM, powPre, 0.025, 0.025
    selectObject: pk
    pwP = Copy: "tmp_pwP"
    @windowMean: pwP, powPre, 0.300, -0.010
    removeObject: powPre

    # Local crest -> x in [0,1] (0 = sustained/sine-like, 1 = impulsive)
    selectObject: pk
    cfx = Copy: "tmp_crest"
    @centredExtreme: cfx, round(0.025 * rc), 1
    selectObject: cfx
    Formula: ~ if object[pwM, 1, col] < nsThresh * 0.01 then 0.5 else max(0, min(1, (10 * log10((self * self + 1e-20) / object[pwM, 1, col]) - 4) / 12)) fi
    @boxMean: cfx, round(0.025 * rc)

    # Transient index W and its 60 ms past hold
    selectObject: pwF
    wTr = Copy: "tmp_transient"
    Formula: ~ if self < nsThresh * 0.1 then 0 else max(0, min(1, (10 * log10((self + 1e-12) / (object[pwP, 1, col] + 1e-12)) - 4) / 8)) fi
    selectObject: wTr
    wHold = Copy: "tmp_transient_hold"
    @pastExtreme: wHold, round(0.060 * rc), 1

    # Non-silent mask (block power within 40 dB of the file mean power)
    selectObject: pwM
    nsMask = Copy: "tmp_nonsilent"
    Formula: ~ if self > nsThresh then 1 else 0 fi
    nsMean = Get mean: 1, 0, 0

    # Base release constant per sample (seconds), before history term
    selectObject: cfx
    tau0 = Copy: "tmp_tau0"
    Formula: ~ tauMid * exp(ars * (0.5 - self) * lnRatio) * (1 - 0.6 * tpP * object[wHold, 1, col])

    # Knee per sample
    selectObject: wTr
    kneeS = Copy: "tmp_knee"
    Formula: ~ knee * (1 - tpP * self)

    # Transient density: rising edges of the held index through 0.5
    selectObject: wHold
    edges = Copy: "tmp_edges"
    Formula: ~ if col > 1 then (if object[wHold, 1, col] >= 0.5 and object[wHold, 1, col - 1] < 0.5 then 1 else 0 fi) else 0 fi
    nEdges = Get mean: 1, 0, 0
    selectObject: edges
    nCtl = Get number of samples
    nEdges = round(nEdges * nCtl)
    removeObject: edges
    activeDur = nsMean * nCtl / rc
    if activeDur > 0.05
        transientRate = nEdges / activeDur
    endif

    selectObject: pwM
    stat = Copy: "tmp_stat"
    Formula: ~ self * 0 + object[cfx, 1, col] * object[nsMask, 1, col]
    meanCfx = Get mean: 1, 0, 0
    if nsMean > 0
        meanCfx = meanCfx / nsMean
    endif
    removeObject: stat, pwF, pwP, pwM, cfx

    if generate_analysis_report
        appendInfoLine: "  Sample peak:        ", fixed$(inPeakDb, 2), " dBFS"
        appendInfoLine: "  True peak (", osf, "x):     ", fixed$(inTpDb, 2), " dBTP"
        appendInfoLine: "  RMS:                ", fixed$(inRmsDb, 2), " dBFS | crest ", fixed$(inCrestDb, 2), " dB"
        if inLufs <> undefined
            appendInfoLine: "  Integrated:         ", fixed$(inLufs, 2), " LUFS"
        else
            appendInfoLine: "  Integrated:         N/A (shorter than 0.4 s or below the -70 LUFS gate)"
        endif
        if inLra <> undefined
            appendInfoLine: "  LRA / max ST:       ", fixed$(inLra, 1), " LU / ", fixed$(inMaxST, 1), " LUFS"
        else
            appendInfoLine: "  LRA:                N/A (needs >= 3 s of gated material)"
        endif
        appendInfoLine: "  Transient density:  ", fixed$(transientRate, 2), " onsets/s (non-silent time)"
        appendInfoLine: "  Mean local crest x: ", fixed$(meanCfx, 2), " (0 sustained .. 1 impulsive)"
        if nChannels = 2
            appendInfoLine: "  Channel peaks L/R:  ", fixed$(20 * log10(inChPeak[1] + 1e-12), 2), " / ", fixed$(20 * log10(inChPeak[2] + 1e-12), 2), " dBFS"
            if inCorr <> undefined
                appendInfoLine: "  L/R correlation:    ", fixed$(inCorr, 3)
            endif
        endif
        appendInfoLine: "  FFT meter offset:   ", fixed$(fftOffset, 3), " LU (search-only calibration)"
    endif
endif

# ============================================================
# PASS 2 - LIMITER RENDER
# ============================================================

# Lookahead geometry in control samples (see header, step 3)
laC = max(2, round(la / 1000 * rc))
boxR1 = ceiling(laC / 4)
boxR2 = ceiling(laC / 4)
holdR = boxR1 + boxR2 + 1
grSlowR = round(0.200 * rc)

# Renders the gain envelope for a drive (dB) and internal ceiling (dB).
# Leaves: rGain (ctrl, linear total gain incl. drive), rGrDb (ctrl, dB),
# rTau (ctrl, effective release ms), metrics, and if .audio, rOut (Sound).
rGain = 0
rGrDb = 0
rTau = 0
rOut = 0
procedure render: .drive, .ci, .audio
    if rGain > 0
        removeObject: rGain, rGrDb, rTau
    endif
    if rOut > 0
        removeObject: rOut
        rOut = 0
    endif
    .dl = 10 ^ (.drive / 20)
    # 1-2. static soft-knee gain computer (dB), knee centred on the ceiling
    selectObject: pk
    .h = Copy: "tmp_gr"
    Formula: ~ if 20 * log10(.dl * self + 1e-12) <= .ci - object[kneeS, 1, col] / 2 then 0 else if 20 * log10(.dl * self + 1e-12) >= .ci + object[kneeS, 1, col] / 2 then .ci - 20 * log10(.dl * self + 1e-12) else -((20 * log10(.dl * self + 1e-12) - .ci + object[kneeS, 1, col] / 2) ^ 2) / (2 * object[kneeS, 1, col]) fi fi
    # 3a. symmetric minimum hold
    @centredExtreme: .h, holdR, -1
    # history term: mean required reduction over +-200 ms
    selectObject: .h
    .gs = Copy: "tmp_grslow"
    @boxMean: .gs, grSlowR
    # 4. effective release tau (s) and dB-domain recursion
    selectObject: tau0
    rTau = Copy: "tmp_tau"
    Formula: ~ max(tauLo, min(tauHi, self * (1 + abs(ars) * min(1, max(0, -object[.gs, 1, col] / 6)))))
    selectObject: .h
    Formula: ~ if col = 1 then self else min(self, self[col - 1] * exp(-1 / (rc * object[rTau, 1, col]))) fi
    removeObject: .gs
    # 3b. two cascaded box averages -> S-shaped attack, smoothed release
    @boxMean: .h, boxR1
    @boxMean: .h, boxR2
    rGrDb = .h
    selectObject: rGrDb
    Rename: "tmp_gr_db"
    selectObject: rTau
    Formula: ~ self * 1000
    # 5. linear total gain (drive x reduction)
    selectObject: rGrDb
    rGain = Copy: "tmp_gain"
    Formula: ~ .dl * 10 ^ (self / 20)
    # metrics over non-silent blocks
    selectObject: rGrDb
    .t = Copy: "tmp_metric"
    Formula: ~ object[nsMask, 1, col] * (if object[rGrDb, 1, col] < -grb then 1 else 0 fi)
    .over = Get mean: 1, 0, 0
    selectObject: .t
    Formula: ~ object[wTr, 1, col] * (if object[wTr, 1, col] >= 0.5 then 1 else 0 fi)
    .wSum = Get mean: 1, 0, 0
    Formula: ~ self * 0 + object[wTr, 1, col] * (if object[wTr, 1, col] >= 0.5 then 1 else 0 fi) * (-object[rGrDb, 1, col])
    .wgr = Get mean: 1, 0, 0
    Formula: ~ self * 0 + (if object[rGrDb, 1, col] < -0.1 then 1 else 0 fi)
    .act = Get mean: 1, 0, 0
    Formula: ~ self * 0 + (if object[rGrDb, 1, col] < -0.1 then -object[rGrDb, 1, col] else 0 fi)
    .actSum = Get mean: 1, 0, 0
    removeObject: .t
    selectObject: rGrDb
    .minGr = Get minimum: 0, 0, "None"
    render.maxGr = -.minGr
    if nsMean > 0
        render.overFrac = .over / nsMean
    else
        render.overFrac = 0
    endif
    if .wSum > 0
        render.trGr = .wgr / .wSum
    else
        render.trGr = 0
    endif
    if .act > 0
        render.avgActive = .actSum / .act
        render.activeFrac = .act
    else
        render.avgActive = 0
        render.activeFrac = 0
    endif
    render.feasible = 1
    if render.overFrac > 0.01
        render.feasible = 0
    endif
    if render.trGr > max(0.5, grb * (1 - 0.8 * tpP))
        render.feasible = 0
    endif
    if .audio
        selectObject: sound
        rOut = Copy: sound_name$ + "_mastered"
        Formula: ~ self * object(rGain, x)
    endif
endproc

# Fast (FFT-K, calibrated) integrated loudness of the current render.
procedure renderLoudness
    @kPowerPrefix: rOut, 2
    .pp = kPowerPrefix.result
    @integratedFromPrefix: .pp
    removeObject: .pp
    renderLoudness.lufs = integratedFromPrefix.lufs
    if renderLoudness.lufs <> undefined
        renderLoudness.lufs = renderLoudness.lufs + fftOffset
    endif
endproc

drive = manual_drive_dB
# Internal ceiling margin, by meter resolution: measured worst residual of
# the vertex-refined meter against an ideal 32x reconstruction (full-band
# white noise, the hardest case) was +0.022 dB at 4x and +0.003 dB at 8x.
if osf = 4
    margin = 0.05
elsif osf = 8
    margin = 0.02
else
    margin = 0.01
endif
searchEvals = 0
searchNote$ = ""
autoUsed = 0

if bypass = 0
    if automatic_loudness_targeting and inLufs = undefined
        warnCount = warnCount + 1
        warn$[warnCount] = "Automatic targeting needs a measurable integrated loudness (>= 0.4 s above the gates); manual drive " + fixed$(manual_drive_dB, 1) + " dB used instead."
    endif
    if automatic_loudness_targeting and inLufs <> undefined
        autoUsed = 1
        if generate_analysis_report
            appendInfoLine: ""
            appendInfoLine: "PASS 2 - DRIVE SEARCH (target ", fixed$(target_LUFS, 1), " LUFS, tolerance 0.1 LU)"
        endif
        tol = 0.1
        driveMax = 36
        driveMin = -40
        haveLo = 0
        haveHi = 0
        hiFeasible = 0
        bestIdx = 0
        done = 0
        d = max(driveMin, min(driveMax, target_LUFS - inLufs))
        while done = 0 and searchEvals < 10
            searchEvals = searchEvals + 1
            @render: d, ceilDb - margin, 1
            @renderLoudness
            lv = renderLoudness.lufs
            if lv = undefined
                lv = -70
            endif
            err = lv - target_LUFS
            evD[searchEvals] = d
            evL[searchEvals] = lv
            evF[searchEvals] = render.feasible
            evOver[searchEvals] = render.overFrac
            evTr[searchEvals] = render.trGr
            if generate_analysis_report
                fs$ = if render.feasible then "ok" else "over budget" fi
                appendInfoLine: "  eval ", searchEvals, ": drive ", fixed$(d, 2), " dB -> ", fixed$(lv, 2), " LUFS | max GR ", fixed$(render.maxGr, 1), " dB | >budget ", fixed$(100 * render.overFrac, 2), " % | transient GR ", fixed$(render.trGr, 2), " dB | ", fs$
            endif
            if render.feasible and abs(err) <= tol
                done = 1
            else
                if render.feasible and err < 0
                    haveLo = 1
                    loD = d
                    loE = err
                else
                    haveHi = 1
                    hiD = d
                    hiE = err
                    hiFeasible = render.feasible
                endif
                if haveLo and haveHi
                    if hiD - loD < 0.15
                        done = 1
                    elsif hiFeasible and hiE > loE
                        d = loD + (hiD - loD) * (-loE) / (hiE - loE)
                        d = max(loD + 0.1 * (hiD - loD), min(hiD - 0.1 * (hiD - loD), d))
                    else
                        d = (loD + hiD) / 2
                    endif
                elsif haveLo
                    if loD >= driveMax
                        done = 1
                    else
                        d = min(driveMax, loD + max(0.5, -loE * 1.5))
                    endif
                else
                    if hiD <= driveMin
                        done = 1
                    elsif hiFeasible
                        d = max(driveMin, hiD - max(0.2, hiE))
                    else
                        d = max(driveMin, hiD - 3)
                    endif
                endif
            endif
        endwhile
        # Choose the best FEASIBLE evaluation: loudest at or below target+tol,
        # else (all overshoot) the closest.
        bestIdx = 0
        for i to searchEvals
            if evF[i] and evL[i] <= target_LUFS + tol
                if bestIdx = 0
                    bestIdx = i
                elsif evL[i] > evL[bestIdx]
                    bestIdx = i
                endif
            endif
        endfor
        if bestIdx = 0
            for i to searchEvals
                if evF[i]
                    if bestIdx = 0
                        bestIdx = i
                    elsif abs(evL[i] - target_LUFS) < abs(evL[bestIdx] - target_LUFS)
                        bestIdx = i
                    endif
                endif
            endfor
        endif
        if bestIdx = 0
            # nothing satisfied the budget: fall back to the gentlest drive tried
            bestIdx = 1
            for i to searchEvals
                if evD[i] < evD[bestIdx]
                    bestIdx = i
                endif
            endfor
            warnCount = warnCount + 1
            warn$[warnCount] = "No evaluated drive met the gain-reduction budget; the gentlest drive tried was used."
        endif
        drive = evD[bestIdx]
        if evL[bestIdx] < target_LUFS - tol
            if evD[bestIdx] >= driveMax - 0.01
                searchNote$ = "Target not reached: drive limit (+" + fixed$(driveMax, 0) + " dB) hit."
            else
                searchNote$ = "Target not reached within the " + modeName$ + " gain-reduction budget (" + fixed$(grb, 1) + " dB, transient " + fixed$(max(0.5, grb * (1 - 0.8 * tpP)), 1) + " dB); best valid result returned."
            endif
            warnCount = warnCount + 1
            warn$[warnCount] = searchNote$
        endif
    endif

    # --- Final render + oversampled true-peak verification / correction ---
    @render: drive, ceilDb - margin, 1
    corrections = 0
    @osScan: rOut, 0
    outTp = osScan.tp
    while 20 * log10(outTp + 1e-12) > ceilDb and corrections < 3
        corrections = corrections + 1
        margin = margin + (20 * log10(outTp + 1e-12) - ceilDb) + 0.02
        @render: drive, ceilDb - margin, 1
        @osScan: rOut, 0
        outTp = osScan.tp
    endwhile
    globalSafety = 0
    if 20 * log10(outTp + 1e-12) > ceilDb
        globalSafety = 20 * log10(outTp + 1e-12) - ceilDb + 0.01
        gsl = 10 ^ (-globalSafety / 20)
        selectObject: rOut
        Formula: ~ self * gsl
        outTp = outTp * gsl
        warnCount = warnCount + 1
        warn$[warnCount] = "Local correction did not converge in 3 passes; a global safety trim of -" + fixed$(globalSafety, 3) + " dB was applied."
    endif
    finalMaxGr = render.maxGr
    finalAvgActive = render.avgActive
    finalActiveFrac = render.activeFrac
    finalOverFrac = render.overFrac
    finalTrGr = render.trGr
    finalFeasible = render.feasible
    if autoUsed = 0 and finalFeasible = 0
        warnCount = warnCount + 1
        warn$[warnCount] = "Manual drive exceeds the " + modeName$ + " gain-reduction budget (" + fixed$(100 * finalOverFrac, 2) + " % of time above " + fixed$(grb, 1) + " dB, transient GR " + fixed$(finalTrGr, 2) + " dB)."
    endif
    result = rOut
    rOut = 0
else
    selectObject: sound
    result = Copy: sound_name$ + "_mastered"
    outTp = inTp
    corrections = 0
    globalSafety = 0
    finalMaxGr = 0
    finalAvgActive = 0
    finalActiveFrac = 0
    finalOverFrac = 0
    finalTrGr = 0
    drive = 0
endif

# Output trim (<= 0 dB, so it can only increase the true-peak margin)
if output_trim_dB < 0
    trl = 10 ^ (output_trim_dB / 20)
    selectObject: result
    Formula: ~ self * trl
    outTp = outTp * trl
endif
outTpDb = 20 * log10(outTp + 1e-12)

# ============================================================
# OUTPUT MEASUREMENT (exact meter) & NUMERICAL CHECKS
# ============================================================
@levelStats: result
outPeak = levelStats.peak
if outPeak = undefined
    exitScript: "Numerical error: output contains undefined samples."
endif
outPeakDb = levelStats.peakDb
outRmsDb = levelStats.rmsDb
outCrestDb = levelStats.crestDb
outCorr = levelStats.corr
for c to nChannels
    outChPeak[c] = levelStats.chPeak[c]
endfor

outLufs = undefined
outLra = undefined
outStN = 0
if bypass = 0
    @kPowerPrefix: result, 1
    kpOut = kPowerPrefix.result
    @integratedFromPrefix: kpOut
    outLufs = integratedFromPrefix.lufs
    @shortTermFromPrefix: kpOut
    outLra = lraVal
    outStN = stN
    if outStN > 0
        outStL# = stL#
    endif
    removeObject: kpOut
else
    outLufs = inLufs
endif

if bypass = 0 and rTau > 0
    selectObject: rTau
    Formula: ~ self * 0 + object[rTau, 1, col] * object[nsMask, 1, col]
    meanTau = Get mean: 1, 0, 0
    if nsMean > 0
        meanTau = meanTau / nsMean
    endif
endif

elapsed = stopwatch

# ============================================================
# MASTERING ANALYSIS REPORT
# ============================================================
if generate_analysis_report
    appendInfoLine: ""
    appendInfoLine: "=============================================="
    appendInfoLine: "  MASTERING REPORT (", modeName$, ")"
    appendInfoLine: "=============================================="
    if bypass
        appendInfoLine: "  BYPASS: ", bypassReason$
    endif
    if inLufs <> undefined
        appendInfoLine: "  Integrated loudness: ", fixed$(inLufs, 2), " -> ", fixed$(outLufs, 2), " LUFS (exact BS.1770 meter)"
    else
        appendInfoLine: "  Integrated loudness: N/A"
    endif
    if autoUsed
        appendInfoLine: "  Requested / achieved: ", fixed$(target_LUFS, 2), " / ", fixed$(outLufs, 2), " LUFS (", fixed$(outLufs - target_LUFS, 2), " LU) after ", searchEvals, " evaluations"
    endif
    if inLra <> undefined and outLra <> undefined
        appendInfoLine: "  LRA:                 ", fixed$(inLra, 1), " -> ", fixed$(outLra, 1), " LU"
    endif
    appendInfoLine: "  Sample peak:         ", fixed$(inPeakDb, 2), " -> ", fixed$(outPeakDb, 2), " dBFS"
    appendInfoLine: "  True peak (", osf, "x est.): ", fixed$(inTpDb, 2), " -> ", fixed$(outTpDb, 2), " dBTP (ceiling ", fixed$(ceilDb, 2), ")"
    appendInfoLine: "  Crest factor:        ", fixed$(inCrestDb, 2), " -> ", fixed$(outCrestDb, 2), " dB (sample peak / RMS)"
    appendInfoLine: "  Drive:               ", fixed$(drive, 2), " dB | output trim ", fixed$(output_trim_dB, 2), " dB"
    appendInfoLine: "  Max gain reduction:  ", fixed$(finalMaxGr, 2), " dB"
    appendInfoLine: "  Avg GR while active: ", fixed$(finalAvgActive, 2), " dB (active ", fixed$(100 * finalActiveFrac, 1), " % of time, GR > 0.1 dB)"
    appendInfoLine: "  Transient GR (mean): ", fixed$(finalTrGr, 2), " dB | time over budget ", fixed$(100 * finalOverFrac, 2), " %"
    if meanTau <> undefined
        appendInfoLine: "  Mean effective release: ", fixed$(meanTau, 1), " ms"
    endif
    appendInfoLine: "  Ceiling corrections: ", corrections, " local pass(es), internal margin ", fixed$(margin, 3), " dB, global trim ", fixed$(globalSafety, 3), " dB"
    if nChannels = 2
        appendInfoLine: "  L/R peak balance:    ", fixed$(20 * log10((inChPeak[1] + 1e-12) / (inChPeak[2] + 1e-12)), 2), " -> ", fixed$(20 * log10((outChPeak[1] + 1e-12) / (outChPeak[2] + 1e-12)), 2), " dB"
        if inCorr <> undefined and outCorr <> undefined
            appendInfoLine: "  L/R correlation:     ", fixed$(inCorr, 3), " -> ", fixed$(outCorr, 3)
        endif
    endif
    appendInfoLine: "  Processing time:     ", fixed$(elapsed, 2), " s"
    if warnCount > 0
        appendInfoLine: ""
        appendInfoLine: "  WARNINGS:"
        for i to warnCount
            appendInfoLine: "  - ", warn$[i]
        endfor
    endif
endif

# ============================================================
# VISUALIZATION
# ============================================================
if visualize
    Erase all
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)
    vizMode$ = replace$(modeName$, "_", "\_ ", 0)
    pageWidth = 8

    # === Header ===
    Font size: 12
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Intelligent Mastering Maximizer v1.0##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    if autoUsed
        sub$ = vizName$ + " | " + vizMode$ + " | target " + fixed$(target_LUFS, 1) + " LUFS | ceiling " + fixed$(ceilDb, 1) + " dBTP"
    else
        sub$ = vizName$ + " | " + vizMode$ + " | drive " + fixed$(drive, 1) + " dB | ceiling " + fixed$(ceilDb, 1) + " dBTP"
    endif
    Text: 0.5, "centre", 0.22, "half", sub$

    # Shared waveform scale
    waveAmp = max(inPeak, outPeak)
    ceilLin = 10 ^ (ceilDb / 20)
    if ceilLin > waveAmp
        waveAmp = ceilLin
    endif
    if waveAmp < 0.001
        waveAmp = 0.001
    endif
    waveAmp = waveAmp * 1.10

    # Ceiling lines. A stereo Sound is drawn as two lanes (channel 1 on top),
    # each spanning -waveAmp..waveAmp in half the panel height, so the lines
    # are placed per lane in the panel's full-height world coordinates.
    procedure ceilingLines
        if nChannels = 1
            Draw line: start_time, ceilLin, end_time, ceilLin
            Draw line: start_time, -ceilLin, end_time, -ceilLin
        else
            for .lane to 2
                .mid = if .lane = 1 then waveAmp / 2 else -waveAmp / 2 fi
                Draw line: start_time, .mid + ceilLin / 2, end_time, .mid + ceilLin / 2
                Draw line: start_time, .mid - ceilLin / 2, end_time, .mid - ceilLin / 2
            endfor
        endif
    endproc

    # --- Input waveform ---
    Font size: 7
    Select inner viewport: 0.8, 7.6, 0.70, 1.80
    selectObject: sound
    Colour: "{0.50, 0.50, 0.50}"
    Draw: start_time, end_time, -waveAmp, waveAmp, "no", "Curve"
    Select inner viewport: 0.8, 7.6, 0.70, 1.80
    Axes: start_time, end_time, -waveAmp, waveAmp
    Colour: "{0.30, 0.30, 0.80}"
    Dashed line
    @ceilingLines
    Solid line
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0.15, 8, 0.40, 2.10
    Text left: "yes", "Input"

    # --- Output waveform ---
    Font size: 7
    Select inner viewport: 0.8, 7.6, 1.95, 3.05
    selectObject: result
    Colour: "{0.20, 0.50, 0.30}"
    Draw: start_time, end_time, -waveAmp, waveAmp, "no", "Curve"
    Select inner viewport: 0.8, 7.6, 1.95, 3.05
    Axes: start_time, end_time, -waveAmp, waveAmp
    Colour: "{0.30, 0.30, 0.80}"
    Dashed line
    @ceilingLines
    Solid line
    Colour: "Black"
    Draw inner box
    Select outer viewport: 0.15, 8, 1.65, 3.35
    Text left: "yes", "Output"

    # --- Gain reduction (dB) ---
    grFloor = -1
    if bypass = 0
        grFloor = -max(1, ceiling(finalMaxGr + 0.5))
    endif
    Font size: 7
    Select inner viewport: 0.8, 7.6, 3.20, 4.30
    Axes: start_time, end_time, grFloor, 0.3
    Paint rectangle: "{0.97, 0.97, 0.97}", start_time, end_time, grFloor, 0.3
    if bypass = 0
        Select inner viewport: 0.8, 7.6, 3.20, 4.30
        selectObject: rGrDb
        Colour: "{0.80, 0.20, 0.20}"
        Draw: start_time, end_time, grFloor, 0.3, "no", "Curve"
        Select inner viewport: 0.8, 7.6, 3.20, 4.30
        Axes: start_time, end_time, grFloor, 0.3
        Colour: "{0.60, 0.60, 0.60}"
        Dotted line
        Draw line: start_time, -grb, end_time, -grb
        Solid line
    endif
    Select inner viewport: 0.8, 7.6, 3.20, 4.30
    Axes: start_time, end_time, grFloor, 0.3
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max(1, round(-grFloor / 4)), "yes", "yes", "no"
    Select outer viewport: 0.15, 8, 2.90, 4.60
    Text left: "yes", "GR (dB)"

    # --- Effective release time constant (ms) ---
    Font size: 7
    Select inner viewport: 0.8, 7.6, 4.45, 5.25
    Axes: start_time, end_time, 0, rmax * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", start_time, end_time, 0, rmax * 1.1
    if bypass = 0
        Select inner viewport: 0.8, 7.6, 4.45, 5.25
        selectObject: rTau
        Colour: "{0.55, 0.30, 0.65}"
        Draw: start_time, end_time, 0, rmax * 1.1, "no", "Curve"
    endif
    Select inner viewport: 0.8, 7.6, 4.45, 5.25
    Axes: start_time, end_time, 0, rmax * 1.1
    Colour: "Black"
    Draw inner box
    One mark left: rmin, "yes", "yes", "yes", ""
    One mark left: rmax, "yes", "yes", "yes", ""
    Select outer viewport: 0.15, 8, 4.15, 5.55
    Text left: "yes", "Release (ms)"

    # --- Short-term loudness in vs out ---
    Font size: 7
    Select inner viewport: 0.8, 7.6, 5.40, 6.50
    Axes: start_time, end_time, -50, 0
    Paint rectangle: "{0.97, 0.97, 0.97}", start_time, end_time, -50, 0
    if inStN >= 2
        Colour: "{0.60, 0.60, 0.60}"
        Line width: 1
        for w from 2 to inStN
            if inStL#[w - 1] > -50 and inStL#[w] > -50
                Draw line: inStT#[w - 1], inStL#[w - 1], inStT#[w], inStL#[w]
            endif
        endfor
        if outStN >= 2
            Colour: "{0.20, 0.50, 0.80}"
            Line width: 2
            for w from 2 to outStN
                if outStL#[w - 1] > -50 and outStL#[w] > -50
                    Draw line: inStT#[w - 1], outStL#[w - 1], inStT#[w], outStL#[w]
                endif
            endfor
            Line width: 1
        endif
        if autoUsed
            Colour: "{0.80, 0.30, 0.30}"
            Dashed line
            Draw line: start_time, target_LUFS, end_time, target_LUFS
            Solid line
        endif
    else
        Colour: "{0.80, 0.20, 0.20}"
        Text: (start_time + end_time) / 2, "centre", -25, "half", "Short-term loudness unavailable (< 3 s)"
    endif
    Select inner viewport: 0.8, 7.6, 5.40, 6.50
    Axes: start_time, end_time, -50, 0
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 10, "yes", "yes", "no"
    Marks bottom: 6, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.15, 8, 5.10, 6.80
    Text left: "yes", "Short-term (LUFS)"

    # --- Summary panel ---
    Font size: 7
    Select inner viewport: 0.60, 7.70, 6.95, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.20, 0.20, 0.25}"
    Text: 0.02, "left", 0.90, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.60, 7.70, 6.95, 7.95
    Axes: 0, 1, 0, 1
    if inLufs <> undefined
        lufsIn$ = fixed$(inLufs, 1)
        lufsOut$ = fixed$(outLufs, 1)
    else
        lufsIn$ = "N/A"
        lufsOut$ = "N/A"
    endif
    if inLra <> undefined and outLra <> undefined
        lraIn$ = fixed$(inLra, 1) + " LU"
        lraOut$ = fixed$(outLra, 1) + " LU"
    else
        lraIn$ = "N/A"
        lraOut$ = "N/A"
    endif
    Text: 0.02, "left", 0.68, "half", "Input:  " + lufsIn$ + " LUFS | " + fixed$(inTpDb, 2) + " dBTP | crest " + fixed$(inCrestDb, 1) + " dB | LRA " + lraIn$
    Text: 0.02, "left", 0.48, "half", "Output: " + lufsOut$ + " LUFS | " + fixed$(outTpDb, 2) + " dBTP | crest " + fixed$(outCrestDb, 1) + " dB | LRA " + lraOut$
    Text: 0.02, "left", 0.28, "half", "Drive " + fixed$(drive, 2) + " dB | max GR " + fixed$(finalMaxGr, 1) + " dB | avg GR active " + fixed$(finalAvgActive, 1) + " dB | transient GR " + fixed$(finalTrGr, 1) + " dB"
    if bypass
        line4$ = "BYPASS: input is digitally silent"
    elsif warnCount > 0
        line4$ = "Warnings: " + string$(warnCount) + " (see Info window)"
    else
        line4$ = "True peak verified at " + string$(osf) + "x | corrections " + string$(corrections) + " | " + fixed$(transientRate, 1) + " onsets/s"
    endif
    Text: 0.02, "left", 0.10, "half", line4$
    Select inner viewport: 0.60, 7.70, 6.95, 7.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # Restore complete page for Picture export / clipboard.
    pageHeight = 8.10
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# CLEAN-UP & OUTPUT
# ============================================================
if bypass = 0
    removeObject: pk, wTr, wHold, nsMask, tau0, kneeS
    if rGain > 0
        removeObject: rGain, rGrDb, rTau
    endif
endif

removeObject: kTab
selectObject: result
if generate_analysis_report
    appendInfoLine: ""
    appendInfoLine: "=============================================="
    appendInfoLine: "  COMPLETE: ", selected$("Sound")
    appendInfoLine: "=============================================="
endif

if play
    Play
endif

selectObject: result
