# ============================================================
# Praat AudioTools - Spectral_Inharmonicity_Analyzer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026) - Bell Analysis and Resynthesis (Stage 3)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   SPECTRAL INHARMONICITY ANALYZER
#   Measures the partial frequencies of one selected Sound and compares
#   them with a harmonic series (String mode, with the stiff-string
#   coefficient B) or lists frequency ratios to a reference (General
#   mode, for bells, membranes, percussion). Native Praat only: no
#   Python, no external programs.
#
# ============================================================
# HELP
# ============================================================
# GETTING STARTED
#   1. Select ONE Sound (mono or stereo; stereo is mixed to mono, or the
#      loudest channel is used if the channels cancel in the mix).
#   2. For a piano / guitar note keep Analysis_mode = String
#      Inharmonicity and choose a SUSTAIN interval: start ~0.1-0.3 s
#      after the attack, 0.5-2 s long. The attack contains noise and
#      transient (non-modal) components.
#   3. Fundamental = Automatic detection, or Manual entry if the
#      automatic estimate is wrong or the sound is strongly inharmonic.
#   4. Read the Info window (table, B, warnings) and the Picture report.
#
# PARAMETERS
#   Analysis_mode      String Inharmonicity: harmonic numbers n are
#                      assigned, f_n is compared with n*f1 and B is
#                      fitted. General Spectral Inharmonicity: the
#                      strongest peaks are listed with their ratio to a
#                      reference frequency; B is NOT computed.
#                      Bell Analysis: modes, doublets, decays (Stage 2).
#                      Bell Synthesis / Resynthesis: see BELL SYNTHESIS.
#   Fundamental        Automatic: Praat pitch (ac) + a harmonic-pattern
#                      score of the spectral peaks (the strongest peak
#                      is NOT assumed to be the fundamental).
#                      General mode, Automatic: the lowest significant
#                      peak is the reference.
#   Manual_frequency_Hz  Reference f1 used when Fundamental = Manual.
#   Start_time_s / End_time_s  Analysis interval (End 0 = end of Sound).
#   Maximum_partials   Highest harmonic number (String) or number of
#                      strongest peaks (General).
#   Peak_threshold_dB  Peaks weaker than (strongest peak + this) are
#                      ignored, e.g. -60.
#   Search_tolerance   Half-width of the harmonic search window as a
#                      fraction of f1 (0.05-0.45). The window is
#                      centred on the PREDICTION of the fitted string
#                      model and widened by the model's extrapolation
#                      uncertainty, so stretched high partials are
#                      followed instead of lost.
#   Window             Blackman-Harris 4-term (sidelobes -92 dB, main
#                      lobe +-4 bins): default, best dynamic range.
#                      Hann (-31 dB, +-2 bins): better for short
#                      excerpts or closely spaced partials.
#   Zero_padding       FFT length factor (power of two). Interpolates
#                      the frequency grid only; it does NOT increase the
#                      resolving power, which is 1 / interval duration.
#   Draw_report        Picture-window report (4 graphs + summary).
#   Export_files       Writes <name>_SIA_partials.csv,
#                      <name>_SIA_summary.txt, <name>_SIA_report.png.
#   Output_directory   Folder for the exports; "default" = home folder.
#
# BELL SYNTHESIS (Analysis_mode = Bell Synthesis / Resynthesis)
#   A second dialog opens (Standards = defaults). The result is a NEW
#   Sound (the source is untouched), peak-normalised, played, and - with
#   Analyze_result - re-analysed by Bell Analysis and compared with the
#   requested frequencies, levels, T60 and envelopes (Info + Table
#   SIA_synthesis_<name>; CSV with Export_files).
#   Synthesis_source   Resynthesis of the selected Sound (Bell Analysis
#                      runs first, with the main-form settings) /
#                      Traditional Tuned Bell (0.25 0.5 0.6 0.75 1 +
#                      optional upper partials) / Inharmonic Bell (the
#                      ratios 0.28 ... 4.08 of the original synthesizer).
#   Nominal_Hz         Presets: Nominal (0 = 440). Resynthesis: 0 = as
#                      measured, otherwise the reference (Nominal, or the
#                      strongest component) is transposed to this value.
#   Duration_s         0 = analysed interval (resynthesis) / 6 s.
#   Number_of_partials Presets: the first N; resynthesis: the N strongest
#                      tracked components (+ resolved doublet partners).
#   Envelopes          Resynthesis: Automatic = fitted exponential where
#                      the decay fit is "reliable", MEASURED trajectory
#                      where it is non-exponential / beating / two-stage.
#   Decay_time_factor  All T60 x factor.  Decay_tilt_per_octave: T60 x
#                      tilt^octaves above the reference (< 1 shortens high,
#                      lengthens low partials).  Ratio_stretch: ratio r to
#                      the reference -> r^stretch.  Spectral_tilt: dB per
#                      octave above the reference.
#   Mode_edits         "target op op; target op ..."  target = Hum Prime
#                      Tierce Quint Nominal, a partial number (frequency
#                      order) or all.  ops: f<factor> c<cents> a<dB>
#                      t<T60 factor> i<% toward the ideal ratio, negative =
#                      away> s<Hz: split into a doublet f -+ s/2, each -3 dB>.
#                      Example: Hum t1.5; Tierce c-20 a3; 4 s1.2
#   Attack / Attack_ms Raised-cosine onset; optional strike noise (8 ms,
#                      band 2 x reference .. 0.9 x Nyquist, -18 dB).
#   Output_peak_dB     Peak level of the result (always normalised, so no
#                      clipping). Partials above 0.95 x Nyquist, at <= 0 Hz
#                      or without a positive decay are removed (reported).
#   Save_WAV           <name>.wav in Output_directory.
#
# DEFINITIONS (String mode)
#   ideal       f_n^ideal = n * f1        (f1 = reference frequency)
#   deviation   dHz_n = f_n - n * f1
#   cents       dc_n  = 1200 * log2(f_n / (n * f1))
#   model       f_n = n * F0 * sqrt(1 + B n^2), F0 = unstretched
#               fundamental; the model's own first partial is
#               f1model = F0 * sqrt(1 + B). Written with f1model this is
#               f_n = n * f1model * sqrt((1 + B n^2) / (1 + B)).
#   fit         y_n = (f_n / n)^2 = F0^2 + F0^2 B n^2  is LINEAR in
#               x_n = n^2: weighted least squares gives intercept
#               a = F0^2 and slope b = F0^2 B, so B = b / a,
#               F0 = sqrt(a). Weights w_n = n^4 / f_n^2 (equal Hz
#               precision per partial). F0 is FREE, so the measured
#               first partial is not assumed to be unstretched.
#               One robust pass removes partials whose residual
#               exceeds max(4 x 1.4826 x MAD, 1 cent) and refits.
#   Reference f1: Manual value; else the measured first partial; if
#               partial 1 is not detected, f1model from the fit.
#
# PEAK INTERPOLATION (three-point parabola on dB magnitude)
#   a, b, c = dB at bins k-1, k, k+1 (b a local maximum)
#   p   = 0.5 (a - c) / (a - 2b + c),  -0.5 <= p <= 0.5
#   f   = (k - 1 + p) * binWidth      (Praat bin 1 = 0 Hz)
#   dB  = b - 0.25 (a - c) p
#   Edge cases: peaks at the first/last bin or with a non-negative
#   denominator are kept at the bin centre (p = 0) and counted.
#
# LIMITATIONS
#   One interval = one spectrum: decaying, beating or gliding partials
#   (two-stage piano decay, unison detuning, vibrato) are averaged over
#   the interval. Unresolved partial pairs give one biased peak.
#   Resolution is limited by the interval duration (reported).
#   The string model ignores bridge coupling and longitudinal modes.
#
# CHANGES
#   v1.3  Bell Synthesis / Resynthesis (Stage 3): preset synthesis
#         (Traditional Tuned Bell, Inharmonic Bell) and additive
#         resynthesis from Bell Analysis - fitted exponentials where
#         reliable, measured level trajectories otherwise; resolved
#         doublets kept as two partials (beats from interference, no
#         amplitude modulation); global and per-mode transforms; strike
#         noise; peak normalisation; WAV export; re-analysis of the result
#         with a requested-vs-measured comparison.
#         Decay table: amplitude_at_strike_db renamed
#         fitted_level_at_strike_db (an extrapolated model value) and
#         MEASURED levels added (measured_level_db / _time_s = first fitted
#         frame, measured_peak_db / _time_s = maximum after the strike).
#         Bell Analysis results are otherwise unchanged.
#   v1.2  Bell mode, after the bell6 review:
#         - stereo: if the mono mix loses > 6 dB (anti-phase channels),
#           the loudest channel is analysed and the loss is reported
#         - peaks within 50 cents of a >= 25 dB stronger peak are flagged
#           as sidebands/leakage and excluded from identification,
#           doublets and tracking
#         - decay window capped at Duration/6 and independent of the
#           doublet resolution; doublet partners are tracked separately
#         - strike time taken from the Sound (Intensity maximum), not
#           from the spectrogram window
#         - doublets confirmed by the beat rate of the band envelope
#           (measured_beat_hz)
#         - ratio_to_nominal is NA without a Nominal; ratio_to_reference
#           names its reference explicitly
#         - non-exponential test relative to the fitted decay range
#         - tracked components coloured and labelled in the figure
#   v1.1  Bell Analysis mode (Stage 2)
#   v1.0  String and General modes
# ============================================================

form Spectral Inharmonicity Analyzer
    comment Selected Sound: partials vs. a harmonic series (stereo is mixed to mono). End 0 = end of Sound.
    optionmenu Analysis_mode: 1
        option String Inharmonicity
        option General Spectral Inharmonicity
        option Bell Analysis
        option Bell Synthesis / Resynthesis
    optionmenu Fundamental: 1
        option Automatic detection
        option Manual frequency entry
    positive Manual_frequency_Hz 440
    real Start_time_s 0
    real End_time_s 0
    natural Maximum_partials 25
    real Peak_threshold_dB -60
    positive Search_tolerance 0.3
    optionmenu Window: 1
        option Blackman-Harris (4-term)
        option Hann
    optionmenu Zero_padding: 2
        option x2
        option x4
        option x8
        option x16
    boolean Draw_report 1
    boolean Export_files 0
    sentence Output_directory default
    comment Bell modes: a Manual frequency is the Nominal. Options = mode overrides, tracking. Synthesis opens its own dialog.
    boolean Bell_options_dialog 0
endform

# explicit mode names (v1.2: three modes - never infer a mode from "else")
if analysis_mode = 1
    modeLabel$ = "String Inharmonicity"
    modeKey$ = "string"
elsif analysis_mode = 2
    modeLabel$ = "General Spectral Inharmonicity"
    modeKey$ = "general"
elsif analysis_mode = 3
    modeLabel$ = "Bell Analysis"
    modeKey$ = "bell"
else
    # Bell Synthesis / Resynthesis: the analysis passes run as Bell Analysis
    modeLabel$ = "Bell Analysis"
    modeKey$ = "bell"
endif

# ------------------------------------------------------------
# Fixed analysis constants (documented, not in the form)
# ------------------------------------------------------------
minProminence = 10
f0SearchMin = 20
f0SearchMax = 5000

# ============================================================
# HELPERS
# ============================================================
procedure siaFmt: .x, .d
    if .x = undefined
        .out$ = "--"
    else
        .r = round(.x * 10 ^ .d) / 10 ^ .d
        if abs(.r) < 0.5 * 10 ^ (-.d)
            .r = 0
        endif
        if .r = 0
            .out$ = "0"
            if .d > 0
                .out$ = "0."
                for .i to .d
                    .out$ = .out$ + "0"
                endfor
            endif
        else
            .out$ = fixed$(.r, .d)
        endif
    endif
endproc

procedure siaSci: .x, .d
    if .x = undefined
        .out$ = "--"
    elsif .x = 0
        .out$ = "0"
    else
        .e = floor(log10(abs(.x)))
        .m = .x / 10 ^ .e
        if abs(.m) >= 9.9995
            .e = .e + 1
            .m = .x / 10 ^ .e
        endif
        .out$ = fixed$(.m, .d) + "e" + string$(.e)
    endif
endproc

procedure siaPad: .s$, .w
    .out$ = .s$
    while length(.out$) < .w
        .out$ = " " + .out$
    endwhile
endproc

procedure siaSafe: .s$
    .out$ = replace$(.s$, "\", "/", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

procedure siaStep: .range, .target
    .raw = .range / .target
    .mag = 10 ^ floor(log10(max(1e-12, .raw)))
    .nn = .raw / .mag
    if .nn < 1.5
        .step = .mag
    elsif .nn < 3.5
        .step = 2 * .mag
    elsif .nn < 7.5
        .step = 5 * .mag
    else
        .step = 10 * .mag
    endif
endproc

procedure siaPanelName: .x1, .x2, .top, .bottom, .name$
    Font size: 7
    Select inner viewport: .x1, .x2, .top, .bottom
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.035 * 7.1 / (.x2 - .x1), "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure siaWarn: .s$
    nWarn = nWarn + 1
    warn$[nWarn] = .s$
endproc

# ============================================================
# BELL SYNTHESIS / RESYNTHESIS (Analysis_mode = 4)
# ============================================================
# Additive model, one sinusoid per partial i:
#   s(t) = sum_i a_i(t) sin(2 pi f_i (t - tS)),  t >= tS (strike time)
# a_i(t) is EITHER the fitted exponential  L0_i - 8.686 alpha_i (t - tS) dB
# OR (resynthesis only) the MEASURED level trajectory of that partial
# (Bell Analysis tracks, frames after strike + one window, down to 15 dB
# above the noise floor), extended before its first frame and after its
# last frame with the fitted slope. Initial phases are 0 (the source
# phases are not measured). Resolved doublets are two partials at their
# own measured frequencies, so beating arises from their interference;
# no amplitude modulation is added.
# Levels L0 are dB relative to the strongest tracked level of the source.
# NOTE: the level at the strike is an EXTRAPOLATION of the fit (the
# window smears the attack); it is not a measured attack amplitude.
# Output: peak-normalised to Output_peak_dB (never clips), 50 ms (max
# 10%) raised-cosine fade at the end, raised-cosine onset of Attack_ms.

# ---------- synthesis dialog defaults ("Standards") ----------
procedure siaSynDefaults
    synthesis_source = 1
    nominal_Hz = 0
    duration_s = 0
    number_of_partials = 12
    envelopes = 1
    decay_time_factor = 1
    decay_tilt_per_octave = 1
    ratio_stretch = 1
    spectral_tilt_dB_per_octave = 0
    mode_edits$ = ""
    attack = 1
    attack_ms = 3
    output_peak_dB = -1
    play_result = 1
    analyze_result = 1
    save_WAV = 0
endproc

# ---------- preset modal data (ratio to Nominal, dB, T60 s) ----------
# Preset A (Traditional Tuned Bell): the five characteristic modes at the
# ideal ratios; partials 6-11 are OPTIONAL upper partials (Number_of_partials
# > 5), illustrative values, not universal properties of tuned bells.
# Preset B (Inharmonic Bell): the ratios of the original experimental Praat
# bell synthesizer, unchanged; individual levels and decays (the original
# gave all partials the same envelope).
procedure siaSynPreset: .which, .fNom, .nMax
    if .which = 2
        .n = 11
        .r$ = "0.25 0.5 0.6 0.75 1 1.25 1.335 1.5 2 2.5 3"
        .l$ = "-6 -4 -3 -12 0 -10 -16 -12 -14 -20 -24"
        .t$ = "24 16 12 9 8 6 5.5 4.5 3.5 2.8 2.2"
    else
        .n = 10
        .r$ = "0.28 0.45 0.59 0.78 1 1.51 2.08 2.71 3.38 4.08"
        .l$ = "-8 -5 -6 -10 0 -6 -9 -12 -15 -18"
        .t$ = "20 15 12 9 8 6 4.5 3.5 2.8 2.2"
    endif
    @siaWords: .r$
    for .i to .n
        .rr[.i] = siaWords.v[.i]
    endfor
    @siaWords: .l$
    for .i to .n
        .ll[.i] = siaWords.v[.i]
    endfor
    @siaWords: .t$
    for .i to .n
        .tt[.i] = siaWords.v[.i]
    endfor
    nSyn = min(.n, .nMax)
    for .i to nSyn
        synF[.i] = .rr[.i] * .fNom
        synL[.i] = .ll[.i]
        synAl[.i] = 6.908 / .tt[.i]
        synEnvT[.i] = 1
        synMode[.i] = if .i <= 5 then .i else 0 fi
        synIdealR[.i] = if .i <= 5 then bmTpl[.i] else 0 fi
        synSplit[.i] = 0
        synNote$[.i] = "preset"
        synSrcStat$[.i] = "preset"
        if .which = 2
            synName$[.i] = if .i <= 5 then bmTplName$[.i] else "Upper " + fixed$(.rr[.i], 3) fi
        else
            synName$[.i] = "P" + string$(.i) + " (" + fixed$(.rr[.i], 2) + ")"
        endif
    endfor
endproc

# ---------- level offset dL (dB) and decay-time factor q on partial i ----------
# exponential: alpha / q. trajectory: every level re the strike level is
# divided by q (same shape, slower or faster), the slopes before/after the
# measured range too. dL shifts the whole envelope.
procedure siaSynScale: .i, .dL, .q
    if synEnvT[.i] = 2
        for .j to synTrN[.i]
            synTrL[.i, .j] = synL[.i] + (synTrL[.i, .j] - synL[.i]) / .q + .dL
        endfor
        synPre[.i] = synPre[.i] / .q
        synPost[.i] = synPost[.i] / .q
    endif
    if synAl[.i] <> undefined
        synAl[.i] = synAl[.i] / .q
    endif
    synL[.i] = synL[.i] + .dL
endproc

# ---------- requested level (dB) of partial i at synthesis time t ----------
procedure siaReqDb: .i, .t
    if synEnvT[.i] = 1
        .db = synL[.i] - 8.6859 * synAl[.i] * (.t - synTs)
    else
        .tA = synTrA[.i]
        .tB = synTrA[.i] + (synTrN[.i] - 1) * synTrDt
        if .t <= .tA
            .db = synTrL[.i, 1] + synPre[.i] * (.t - .tA)
        elsif .t >= .tB
            .db = synTrL[.i, synTrN[.i]] + synPost[.i] * (.t - .tB)
        else
            .u = (.t - .tA) / synTrDt + 1
            .j = floor(.u)
            .w = .u - .j
            .db = (1 - .w) * synTrL[.i, .j] + .w * synTrL[.i, .j + 1]
        endif
    endif
endproc

# ---------- Mode_edits ----------
# "target op op; target op ..."  target = Hum Prime Tierce Quint Nominal
# (identified/characteristic modes), a partial number (synthesis table
# order) or all. ops: f<x> frequency x; c<cents>; a<dB>; t<x> decay time
# (T60) x; i<%> toward the ideal ratio (100 = ideal, negative = away);
# s<Hz> split into a doublet f +- s/2 (each -3 dB).
procedure siaSynEdits: .s$
    .s$ = replace_regex$(.s$, "[,]", ";", 0)
    .rest$ = .s$ + ";"
    nEditOps = 0
    while index(.rest$, ";") > 0
        .p = index(.rest$, ";")
        .cl$ = replace_regex$(left$(.rest$, .p - 1), "^ +| +$", "", 0)
        .rest$ = mid$(.rest$, .p + 1, length(.rest$) - .p)
        if .cl$ <> ""
            .cl$ = .cl$ + " "
            .sp = index(.cl$, " ")
            .tg$ = left$(.cl$, .sp - 1)
            .ops$ = mid$(.cl$, .sp + 1, length(.cl$) - .sp)
            .tl$ = replace_regex$(.tg$, "(.*)", "\L\1", 0)
            .nT = 0
            for .i to nSyn
                .hit = 0
                if .tl$ = "all"
                    .hit = 1
                elsif .tl$ = string$(.i)
                    .hit = 1
                elsif synMode[.i] > 0
                    if .tl$ = replace_regex$(bmTplName$[synMode[.i]], "(.*)", "\L\1", 0)
                        .hit = 1
                    endif
                endif
                if .hit
                    .nT = .nT + 1
                    .tgI[.nT] = .i
                endif
            endfor
            if .nT = 0
                exitScript: "Mode_edits: no partial matches """ + .tg$ + """ (use Hum, Prime, Tierce, Quint, Nominal, a partial number 1-" + string$(nSyn) + " or all)."
            endif
            .ops$ = replace_regex$(.ops$, "^ +| +$", "", 0)
            while .ops$ <> ""
                .sp = index(.ops$ + " ", " ")
                .op$ = left$(.ops$ + " ", .sp - 1)
                .ops$ = replace_regex$(mid$(.ops$ + " ", .sp + 1, length(.ops$) + 1 - .sp), "^ +| +$", "", 0)
                .c$ = replace_regex$(left$(.op$, 1), "(.)", "\L\1", 0)
                .v = number(mid$(.op$, 2, length(.op$) - 1))
                if index("fcatis", .c$) = 0 or .v = undefined
                    exitScript: "Mode_edits: cannot read """ + .op$ + """ (ops: f<factor> c<cents> a<dB> t<T60 factor> i<% to ideal> s<split Hz>)."
                endif
                if (.c$ = "f" or .c$ = "t") and .v <= 0
                    exitScript: "Mode_edits: " + .op$ + " - factors must be positive."
                endif
                if .c$ = "s" and .v < 0
                    exitScript: "Mode_edits: " + .op$ + " - the split must be >= 0 Hz."
                endif
                nEditOps = nEditOps + 1
                for .k to .nT
                    .i = .tgI[.k]
                    if .c$ = "f"
                        synF[.i] = synF[.i] * .v
                    elsif .c$ = "c"
                        synF[.i] = synF[.i] * 2 ^ (.v / 1200)
                    elsif .c$ = "a"
                        @siaSynScale: .i, .v, 1
                    elsif .c$ = "t"
                        @siaSynScale: .i, 0, .v
                    elsif .c$ = "i"
                        if synIdealR[.i] > 0
                            .fi = synIdealR[.i] * synRef
                            synF[.i] = .fi * (synF[.i] / .fi) ^ (1 - .v / 100)
                        else
                            synNote$[.i] = synNote$[.i] + "; i ignored (no ideal ratio)"
                        endif
                    else
                        synSplit[.i] = .v
                    endif
                endfor
            endwhile
        endif
    endwhile
endproc

# ---------- global transformations, edits, doublet splits, validity ----------
# frequency: f -> fRef (f / fRef)^Ratio_stretch; level: + tilt log2(f / fRef);
# decay time x Decay_time_factor x Decay_tilt^log2(f / fRef). Then Mode_edits.
procedure siaSynTransform
    # frequency order first: partial numbers in Mode_edits refer to it
    @siaSynSort
    for .i to nSyn
        .oct = log2(synF[.i] / synRef)
        synF[.i] = synRef * (synF[.i] / synRef) ^ ratio_stretch
        @siaSynScale: .i, spectral_tilt_dB_per_octave * .oct, decay_time_factor * decay_tilt_per_octave ^ .oct
    endfor
    if mode_edits$ <> ""
        @siaSynEdits: mode_edits$
    endif
    # doublet splits: partial i -> two partials f -+ s/2, each 3 dB lower
    .n0 = nSyn
    for .i to .n0
        if synSplit[.i] > 0
            nSyn = nSyn + 1
            .j = nSyn
            synName$[.j] = synName$[.i] + " b"
            synName$[.i] = synName$[.i] + " a"
            synF[.j] = synF[.i] + synSplit[.i] / 2
            synF[.i] = synF[.i] - synSplit[.i] / 2
            @siaSynScale: .i, -3.0103, 1
            synL[.j] = synL[.i]
            synAl[.j] = synAl[.i]
            synEnvT[.j] = synEnvT[.i]
            synMode[.j] = synMode[.i]
            synIdealR[.j] = synIdealR[.i]
            synSplit[.j] = 0
            synSrcStat$[.j] = synSrcStat$[.i]
            synNote$[.j] = synNote$[.i] + "; doublet " + fixed$(synSplit[.i], 2) + " Hz"
            synNote$[.i] = synNote$[.j]
            if synEnvT[.i] = 2
                synTrN[.j] = synTrN[.i]
                synTrA[.j] = synTrA[.i]
                synPre[.j] = synPre[.i]
                synPost[.j] = synPost[.i]
                for .q to synTrN[.i]
                    synTrL[.j, .q] = synTrL[.i, .q]
                endfor
            endif
        endif
    endfor
    # validity: Nyquist, frequency > 0, finite level, positive decay
    nSynDrop = 0
    .k = 0
    for .i to nSyn
        .why$ = ""
        if synF[.i] = undefined or synF[.i] <= 0
            .why$ = "frequency <= 0"
        elsif synF[.i] >= 0.95 * synFs / 2
            .why$ = "above 0.95 x Nyquist (" + fixed$(0.95 * synFs / 2, 0) + " Hz)"
        elsif synL[.i] = undefined
            .why$ = "level undefined"
        elsif synEnvT[.i] = 1 and (synAl[.i] = undefined or synAl[.i] <= 0)
            .why$ = "no positive decay rate"
        endif
        if .why$ <> ""
            nSynDrop = nSynDrop + 1
            synDrop$[nSynDrop] = synName$[.i] + " (" + fixed$(synF[.i], 1) + " Hz): " + .why$
        else
            .k = .k + 1
            if .k < .i
                @siaSynCopy: .i, .k
            endif
        endif
    endfor
    nSyn = .k
    # alpha limits: T60 between 0.01 s and 600 s
    for .i to nSyn
        if synAl[.i] <> undefined
            synAl[.i] = min(690.8, max(6.908 / 600, synAl[.i]))
        endif
    endfor
    @siaSynSort
endproc

# sort by frequency (insertion sort through a spare slot)
procedure siaSynSort
    for .i from 2 to nSyn
        .j = .i
        while .j > 1
            if synF[.j] < synF[.j - 1]
                @siaSynCopy: .j, nSyn + 1
                @siaSynCopy: .j - 1, .j
                @siaSynCopy: nSyn + 1, .j - 1
                .j = .j - 1
            else
                .j = 1
            endif
        endwhile
    endfor
endproc

procedure siaSynCopy: .a, .b
    synName$[.b] = synName$[.a]
    synF[.b] = synF[.a]
    synL[.b] = synL[.a]
    synAl[.b] = synAl[.a]
    synEnvT[.b] = synEnvT[.a]
    synMode[.b] = synMode[.a]
    synIdealR[.b] = synIdealR[.a]
    synSplit[.b] = synSplit[.a]
    synNote$[.b] = synNote$[.a]
    synSrcStat$[.b] = synSrcStat$[.a]
    if synEnvT[.a] = 2
        synTrN[.b] = synTrN[.a]
        synTrA[.b] = synTrA[.a]
        synPre[.b] = synPre[.a]
        synPost[.b] = synPost[.a]
        for .q to synTrN[.a]
            synTrL[.b, .q] = synTrL[.a, .q]
        endfor
    endif
endproc

# ---------- render the additive sum into a new Sound ----------
procedure siaSynRender: .name$
    synSnd = Create Sound from formula: .name$, 1, 0, synDur, synFs, "0"
    synAtt = attack_ms / 1000
    for .i to nSyn
        synCurF = synF[.i]
        synCurA = 10 ^ (synL[.i] / 20)
        if synEnvT[.i] = 1
            synCurAl = synAl[.i]
            selectObject: synSnd
            if synAtt > 0
                Formula: "self + if x < synTs then 0 else synCurA * exp(-synCurAl * (x - synTs)) * sin(2 * pi * synCurF * (x - synTs)) * (if x - synTs < synAtt then 0.5 - 0.5 * cos(pi * (x - synTs) / synAtt) else 1 fi) fi"
            else
                Formula: "self + if x < synTs then 0 else synCurA * exp(-synCurAl * (x - synTs)) * sin(2 * pi * synCurF * (x - synTs)) fi"
            endif
        else
            # measured trajectory: dB samples on the frame grid, linear
            # interpolation in dB inside, fitted slopes outside
            synEnvSnd = Create Sound from formula: "sia_env", 1, synTrA[.i] - synTrDt / 2,
                ... synTrA[.i] + (synTrN[.i] - 0.5) * synTrDt, 1 / synTrDt, "0"
            for .j to synTrN[.i]
                Set value at sample number: 1, .j, synTrL[.i, .j]
            endfor
            synCurTA = synTrA[.i]
            synCurTB = synTrA[.i] + (synTrN[.i] - 1) * synTrDt
            synCurLA = synTrL[.i, 1]
            synCurLB = synTrL[.i, synTrN[.i]]
            synCurPre = synPre[.i]
            synCurPost = synPost[.i]
            synCurAtt = max(synAtt, 1e-9)
            selectObject: synSnd
            Formula: "self + if x < synTs then 0 else 10 ^ ((if x <= synCurTA then synCurLA + synCurPre * (x - synCurTA) else if x >= synCurTB then synCurLB + synCurPost * (x - synCurTB) else object(synEnvSnd, x) fi fi) / 20) * sin(2 * pi * synCurF * (x - synTs)) * (if x - synTs < synCurAtt then 0.5 - 0.5 * cos(pi * (x - synTs) / synCurAtt) else 1 fi) fi"
            removeObject: synEnvSnd
        endif
    endfor
    # optional strike noise: Gaussian noise, 8 ms exponential decay, Hann
    # band 2 x reference .. 0.9 x Nyquist, RMS of its first 10 ms 18 dB below
    # the strongest partial's RMS
    synNoise = 0
    if attack = 2
        .lMax = -1e9
        for .i to nSyn
            .lMax = max(.lMax, synL[.i])
        endfor
        .fLo = min(2 * synRef, 0.3 * synFs / 2)
        .nz = Create Sound from formula: "sia_noise", 1, 0, synDur, synFs, "if x < synTs then 0 else randomGauss(0, 1) * exp(-(x - synTs) / 0.008) fi"
        synNzf = Filter (pass Hann band): .fLo, 0.9 * synFs / 2, min(100, .fLo / 2)
        .r = Get root-mean-square: synTs, min(synDur, synTs + 0.01)
        removeObject: .nz
        if .r > 0 and .r <> undefined
            synCurG = 10 ^ ((.lMax - 18) / 20) / sqrt(2) / .r
            selectObject: synSnd
            Formula: "self + synCurG * object[synNzf, col]"
            synNoise = 1
        endif
        removeObject: synNzf
    endif
    # end fade (no discontinuity), peak normalisation (no clipping)
    synFade = min(0.05, 0.1 * synDur)
    selectObject: synSnd
    Formula: "self * (if x > synDur - synFade then 0.5 + 0.5 * cos(pi * (x - (synDur - synFade)) / synFade) else 1 fi)"
    synPeakRaw = Get absolute extremum: 0, 0, "None"
    synRms = Get root-mean-square: 0, 0
    if synPeakRaw = undefined or synRms = undefined
        exitScript: "Synthesis produced undefined samples - please report the parameters."
    endif
    if synPeakRaw <= 0
        exitScript: "Synthesis produced silence (no partial left after the validity checks)."
    endif
    synGain = 10 ^ (output_peak_dB / 20) / synPeakRaw
    Formula: "self * synGain"
    synPeak = Get absolute extremum: 0, 0, "None"
endproc


# ---------- resynthesis: synthesis partials from a Bell Analysis pass ----------
# One partial per tracked component. Envelope per partial:
#   Automatic: fitted exponential if the fit is "reliable", otherwise the
#     measured trajectory (non-exponential, beating, two-stage, uncertain);
#   Fitted exponential / Measured trajectory: forced where possible.
# A resolved doublet partner that is NOT tracked separately (closer than
# the tracking resolution) is added as its own partial at its measured
# frequency, with the decay of its tracked partner; the partner's band
# level is split between the two by their spectral amplitude ratio, and
# the tracked partner uses its exponential fit (its band trajectory
# contains the beats of the pair, which now arise from the two partials).
procedure siaSynFromAnalysis
    synRef = if bellOK then fN else fRefB fi
    synRefName$ = if bellOK then "Nominal" else refBName$ fi
    synTs = tStrike - t1
    synTrDt = dxT
    nSyn = 0
    nSynSkip = 0
    for .k to nTr
        .nF = trC2[.k] - trC1[.k] + 1
        .hasTr = 0
        if left$(trStat$[.k], 13) <> "not estimated" and .nF >= 6
            .hasTr = 1
        endif
        .hasFit = 0
        if trAlpha[.k] <> undefined and trA0[.k] <> undefined
            if trAlpha[.k] > 0
                .hasFit = 1
            endif
        endif
        .env = 0
        if envelopes = 2
            .env = if .hasFit then 1 else if .hasTr then 2 else 0 fi fi
        elsif envelopes = 3
            .env = if .hasTr then 2 else if .hasFit then 1 else 0 fi fi
        else
            .env = if .hasFit and trStat$[.k] = "reliable" then 1 else if .hasTr then 2 else if .hasFit then 1 else 0 fi fi fi
        endif
        if .env = 0
            nSynSkip = nSynSkip + 1
            synSkip$[nSynSkip] = trName$[.k] + " (" + fixed$(trF[.k], 1) + " Hz): " + trStat$[.k]
        else
            nSyn = nSyn + 1
            .i = nSyn
            synName$[.i] = trName$[.k]
            if nominal_Hz > 0 and trMode[.k] = 0
                synName$[.i] = "src " + trName$[.k]
            endif
            synF[.i] = trF[.k]
            synMode[.i] = trMode[.k]
            synIdealR[.i] = if trMode[.k] > 0 then bmR[trMode[.k]] else 0 fi
            synSplit[.i] = 0
            synEnvT[.i] = .env
            synSrcStat$[.i] = trStat$[.k]
            synTrk[.i] = .k
            synAl[.i] = if .hasFit then trAlpha[.k] else undefined fi
            if .env = 1
                synL[.i] = trA0[.k]
                synNote$[.i] = "fitted exponential"
            else
                .sl = if .hasFit then -8.6859 * trAlpha[.k] else -10 fi
                synPre[.i] = .sl
                synPost[.i] = .sl
                synTrN[.i] = .nF
                synTrA[.i] = frT[trC1[.k]] - t1
                for .j to .nF
                    synTrL[.i, .j] = trDb[.k, trC1[.k] + .j - 1]
                endfor
                synL[.i] = synTrL[.i, 1] + .sl * (synTs - synTrA[.i])
                synNote$[.i] = "measured trajectory " + fixed$(frT[trC1[.k]] - t1, 2) + "-" + fixed$(frT[trC2[.k]] - t1, 2)
                    ... + " s, fitted slope " + (if .hasFit then "" else "(none: -10 dB/s) " fi) + "outside"
            endif
        endif
    endfor
    # untracked doublet partners: a resolved doublet (Stage 2 doublet list)
    # whose partner is not tracked separately (closer than the tracking
    # resolution, or beyond the tracking count). The partner is synthesised
    # as its own partial at its measured frequency with the decay of the
    # tracked partial, which then uses its exponential fit; the beats arise
    # from the two partials and no amplitude modulation is synthesised.
    # Levels keep the spectral amplitude ratio. Band level lb: if the beat is
    # slow against the tracking window (df x window <= 1) the dB fit follows
    # the beats and its mean is the level of the STRONGER partial (mean of
    # dB |a + b e^(i w t)| = dB max(a, b)); otherwise the window averages the
    # beats and lb is the summed power. Peaks Stage 2 does not accept as a
    # doublet (e.g. modulation sidebands) are not added.
    nSynPartner = 0
    nSyn0 = nSyn
    for .i to nSyn0
        .k = synTrk[.i]
        .pm = trPk[.k]
        .nP = 0
        .rSum = 0
        for .p to nPk
            .cand = 0
            if .p <> .pm and pkSide[.p] = 0
                .isTr = 0
                for .k2 to nTr
                    if trPk[.k2] = .p
                        .isTr = 1
                    endif
                endfor
                if .isTr = 0
                    for .d to nDbl
                        if (dbA[.d] = .pm and dbB[.d] = .p) or (dbB[.d] = .pm and dbA[.d] = .p)
                            .cand = 1
                        endif
                    endfor
                    # a peak paired with two tracked partials goes to the nearer one
                    if .cand
                        for .i2 to nSyn0
                            if .i2 <> .i
                                .k2 = synTrk[.i2]
                                .pm2 = trPk[.k2]
                                .rel = 0
                                for .d to nDbl
                                    if (dbA[.d] = .pm2 and dbB[.d] = .p) or (dbB[.d] = .pm2 and dbA[.d] = .p)
                                        .rel = 1
                                    endif
                                endfor
                                if .rel
                                    .dO = abs(pkF[.p] - trF[.k2])
                                    .dM = abs(pkF[.p] - trF[.k])
                                    if .dO < .dM or (.dO = .dM and .i2 < .i)
                                        .cand = 0
                                    endif
                                endif
                            endif
                        endfor
                    endif
                endif
            endif
            if .cand
                .nP = .nP + 1
                .pp[.nP] = .p
                .rSum = .rSum + 10 ^ ((pkA[.p] - pkA[.pm]) / 10)
                .dfMin = abs(pkF[.p] - trF[.k])
            endif
        endfor
        if .nP > 0
            .ok = 0
            if trAlpha[.k] <> undefined and trA0[.k] <> undefined
                if trAlpha[.k] > 0
                    .ok = 1
                endif
            endif
            if .ok = 0
                synNote$[.i] = synNote$[.i] + "; resolved partner(s) NOT synthesised separately (no decay fit)"
            else
                .lb = trA0[.k]
                .slow = .dfMin * trackWinEff <= 1
                if .slow
                    # Jensen: the band dB mean = level of the strongest member
                    .aMax = pkA[.pm]
                    for .q to .nP
                        .aMax = max(.aMax, pkA[.pp[.q]])
                    endfor
                    .off = .lb - .aMax
                else
                    # power sum: lb = 10 log10(sum of member powers)
                    .off = .lb - pkA[.pm] - 10 * log10(1 + .rSum)
                endif
                synEnvT[.i] = 1
                synAl[.i] = trAlpha[.k]
                synL[.i] = pkA[.pm] + .off
                synNote$[.i] = "fitted exponential; resolved doublet partner synthesised separately (" + (if .slow then "slow beats: band level = stronger member" else "fast beats: band power shared" fi) + ")"
                for .q to .nP
                    .p = .pp[.q]
                    nSyn = nSyn + 1
                    nSynPartner = nSynPartner + 1
                    synName$[nSyn] = (if nominal_Hz > 0 then "src " else "" fi) + fixed$(pkF[.p], 1) + " Hz"
                    synF[nSyn] = pkF[.p]
                    synMode[nSyn] = 0
                    synIdealR[nSyn] = 0
                    synSplit[nSyn] = 0
                    synEnvT[nSyn] = 1
                    synAl[nSyn] = trAlpha[.k]
                    synL[nSyn] = pkA[.p] + .off
                    synTrk[nSyn] = 0
                    synSrcStat$[nSyn] = "resolved partner (spectral peak, not tracked separately)"
                    synNote$[nSyn] = "resolved doublet partner of " + fixed$(trF[.k], 2) + " Hz: spectral level ratio, decay of that partial"
                endfor
            endif
        endif
    endfor
    # Number_of_partials: keep the strongest
    nSynCap = 0
    while nSyn > number_of_partials
        .w = 1
        for .i to nSyn
            if synL[.i] < synL[.w]
                .w = .i
            endif
        endfor
        nSynCap = nSynCap + 1
        for .i from .w to nSyn - 1
            @siaSynCopy: .i + 1, .i
            synTrk[.i] = synTrk[.i + 1]
        endfor
        nSyn = nSyn - 1
    endwhile
    # optional transposition: the reference (Nominal or strongest) -> Nominal_Hz
    synTransp = 1
    if nominal_Hz > 0
        synTransp = nominal_Hz / synRef
        for .i to nSyn
            synF[.i] = synF[.i] * synTransp
        endfor
        synRef = nominal_Hz
    endif
endproc

# ---------- compare a re-analysed synthesis with the requested values ----------
# Matching by frequency: a synthesised partial is "found" if a spectral
# peak lies within tol = max(0.25 Hz, min(0.4 x spacing to the nearest
# other synthesised partial, 1% of f)). Level: see below (re the
# strongest requested partial). Decay: fitted T60 vs
# requested T60 (exponential partials). Trajectory: RMS (dB) of measured
# minus requested level over the fitted frames after removing the mean
# offset (shape error), for every partial. Level error: that mean offset
# minus the reference partial's mean offset.
procedure siaSynCompare
    .iR = 1
    for .i to nSyn
        if synL[.i] > synL[.iR]
            .iR = .i
        endif
    endfor
    synCmpRef = .iR
    nSynFound = 0
    for .i to nSyn
        .sp = 1e9
        for .j to nSyn
            if .j <> .i
                .sp = min(.sp, abs(synF[.j] - synF[.i]))
            endif
        endfor
        synTol[.i] = max(0.25, min(0.4 * .sp, 0.01 * synF[.i]))
        .bp = 0
        for .p to nPk
            if abs(pkF[.p] - synF[.i]) <= synTol[.i]
                if .bp = 0
                    .bp = .p
                elsif abs(pkF[.p] - synF[.i]) < abs(pkF[.bp] - synF[.i])
                    .bp = .p
                endif
            endif
        endfor
        synMF[.i] = if .bp > 0 then pkF[.bp] else undefined fi
        if .bp > 0
            nSynFound = nSynFound + 1
        endif
        .bk = 0
        for .k to nTr
            if abs(trF[.k] - synF[.i]) <= synTol[.i]
                if .bk = 0
                    .bk = .k
                elsif abs(trF[.k] - synF[.i]) < abs(trF[.bk] - synF[.i])
                    .bk = .k
                endif
            endif
        endfor
        synMk[.i] = .bk
    endfor
    .kR = synMk[.iR]
    for .i to nSyn
        .k = synMk[.i]
        synMCents[.i] = if synMF[.i] = undefined then undefined else 1200 * log2(synMF[.i] / synF[.i]) fi
        synMLrel[.i] = undefined
        synMLerr[.i] = undefined
        synMT60[.i] = undefined
        synMT60err[.i] = undefined
        synMRms[.i] = undefined
        synMStat$[.i] = if .k = 0 then "not tracked" else trStat$[.k] fi
        synReqT60[.i] = if synEnvT[.i] = 1 then 6.908 / synAl[.i] else undefined fi
        synMMu[.i] = undefined
        if .k > 0
            if trAlpha[.k] <> undefined
                if trAlpha[.k] > 0
                    synMT60[.i] = 6.908 / trAlpha[.k]
                    if synReqT60[.i] <> undefined
                        synMT60err[.i] = 100 * (synMT60[.i] / synReqT60[.i] - 1)
                    endif
                endif
            endif
            if trC2[.k] - trC1[.k] >= 5 and left$(trStat$[.k], 13) <> "not estimated"
                .n = 0
                .s = 0
                for .c from trC1[.k] to trC2[.k]
                    @siaReqDb: .i, frT[.c] - t1
                    .n = .n + 1
                    .dv[.n] = trDb[.k, .c] - siaReqDb.db
                    .s = .s + .dv[.n]
                endfor
                .mu = .s / .n
                synMMu[.i] = .mu
                .ss = 0
                for .q to .n
                    .ss = .ss + (.dv[.q] - .mu) ^ 2
                endfor
                synMRms[.i] = sqrt(.ss / .n)
            endif
        endif
    endfor
    # level: mean (measured - requested) over the fitted frames, re the
    # reference partial - valid for exponential AND trajectory partials
    for .i to nSyn
        if synMMu[.i] <> undefined and synMMu[.iR] <> undefined
            synMLerr[.i] = synMMu[.i] - synMMu[.iR]
            synMLrel[.i] = synL[.i] - synL[.iR] + synMLerr[.i]
        endif
    endfor
    # strongest component that was NOT requested (sidebands excluded)
    synSpurDb = undefined
    synSpurF = undefined
    for .p to nPk
        if pkSide[.p] = 0
            .near = 0
            for .i to nSyn
                if abs(pkF[.p] - synF[.i]) <= max(synTol[.i], 3 * lobeHz)
                    .near = 1
                endif
            endfor
            if .near = 0
                if synSpurDb = undefined
                    synSpurDb = pkA[.p]
                    synSpurF = pkF[.p]
                elsif pkA[.p] > synSpurDb
                    synSpurDb = pkA[.p]
                    synSpurF = pkF[.p]
                endif
            endif
        endif
    endfor
    synCmpDur = durT
    synCmpName$ = name$
endproc

synthMode = analysis_mode = 4
synRefName$ = "Nominal"
synTransp = 1
nSynSkip = 0
nSyn = 0
nSynCap = 0
synNoise = 0
nPass = 1
synDone = 0
synCmp = 0
nSynDrop = 0
nEditOps = 0
infoStart = 0
bmTpl[1] = 0.25
bmTpl[2] = 0.5
bmTpl[3] = 0.6
bmTpl[4] = 0.75
bmTpl[5] = 1
bmTplName$[1] = "Hum"
bmTplName$[2] = "Prime"
bmTplName$[3] = "Tierce"
bmTplName$[4] = "Quint"
bmTplName$[5] = "Nominal"
if synthMode
    @siaSynDefaults
    # batch hook: SIA_SYNTH = 15 numbers (source nominal duration partials
    # envelopes decayFactor decayTilt stretch spectralTilt attack attackMs
    # peakDb play analyze saveWav); SIA_EDITS = Mode_edits text
    synEnvStr$ = environment$("SIA_SYNTH")
    if synEnvStr$ <> ""
        @siaWords: synEnvStr$
        if siaWords.n <> 15
            exitScript: "SIA_SYNTH needs 15 numbers."
        endif
        synthesis_source = siaWords.v[1]
        nominal_Hz = siaWords.v[2]
        duration_s = siaWords.v[3]
        number_of_partials = siaWords.v[4]
        envelopes = siaWords.v[5]
        decay_time_factor = siaWords.v[6]
        decay_tilt_per_octave = siaWords.v[7]
        ratio_stretch = siaWords.v[8]
        spectral_tilt_dB_per_octave = siaWords.v[9]
        attack = siaWords.v[10]
        attack_ms = siaWords.v[11]
        output_peak_dB = siaWords.v[12]
        play_result = siaWords.v[13]
        analyze_result = siaWords.v[14]
        save_WAV = siaWords.v[15]
        mode_edits$ = environment$("SIA_EDITS")
    else
        clicked = 2
        while clicked = 2
            beginPause: "Bell Synthesis / Resynthesis"
                comment: "Resynthesis runs Bell Analysis on the selected Sound first; presets need no Sound."
                optionMenu: "Synthesis_source", synthesis_source
                    option: "Resynthesis of the selected Sound"
                    option: "Traditional Tuned Bell"
                    option: "Inharmonic Bell"
                real: "Nominal_Hz", string$(nominal_Hz)
                real: "Duration_s", string$(duration_s)
                natural: "Number_of_partials", string$(number_of_partials)
                comment: "Nominal 0 = as measured / 440 Hz; Duration 0 = as analysed / 6 s."
                optionMenu: "Envelopes", envelopes
                    option: "Automatic (fit if reliable, else measured)"
                    option: "Fitted exponential"
                    option: "Measured trajectory"
                positive: "Decay_time_factor", string$(decay_time_factor)
                positive: "Decay_tilt_per_octave", string$(decay_tilt_per_octave)
                positive: "Ratio_stretch", string$(ratio_stretch)
                real: "Spectral_tilt_dB_per_octave", string$(spectral_tilt_dB_per_octave)
                sentence: "Mode_edits", mode_edits$
                comment: "e.g. Hum t1.5; Tierce c-20 a3; 4 s1.2   (f c a t i s; see script header)"
                optionMenu: "Attack", attack
                    option: "Smooth onset"
                    option: "Smooth onset + strike noise"
                real: "Attack_ms", string$(attack_ms)
                real: "Output_peak_dB", string$(output_peak_dB)
                boolean: "Play_result", play_result
                boolean: "Analyze_result", analyze_result
                boolean: "Save_WAV", save_WAV
            clicked = endPause: "Cancel", "Standards", "OK", 3, 1
            if clicked = 2
                @siaSynDefaults
            endif
        endwhile
    endif
    if synthesis_source < 1 or synthesis_source > 3
        exitScript: "Synthesis source must be 1, 2 or 3."
    endif
    if nominal_Hz < 0 or nominal_Hz > 10000
        exitScript: "Nominal_Hz must be 0 (as measured / 440 Hz) or up to 10000 Hz."
    endif
    if duration_s < 0 or (duration_s > 0 and duration_s < 0.2) or duration_s > 120
        exitScript: "Duration_s must be 0 (automatic) or between 0.2 and 120 s."
    endif
    if number_of_partials < 1 or number_of_partials > 40
        exitScript: "Number_of_partials must be between 1 and 40."
    endif
    if decay_time_factor < 0.05 or decay_time_factor > 20 or decay_tilt_per_octave < 0.25 or decay_tilt_per_octave > 4
        exitScript: "Decay_time_factor must be 0.05 - 20 and Decay_tilt_per_octave 0.25 - 4."
    endif
    if ratio_stretch < 0.5 or ratio_stretch > 2
        exitScript: "Ratio_stretch must be between 0.5 and 2 (1 = unchanged)."
    endif
    if abs(spectral_tilt_dB_per_octave) > 24
        exitScript: "Spectral_tilt_dB_per_octave must be between -24 and 24."
    endif
    if attack_ms < 0 or attack_ms > 200
        exitScript: "Attack_ms must be between 0 and 200 ms."
    endif
    if output_peak_dB > -0.1 or output_peak_dB < -60
        exitScript: "Output_peak_dB must be between -60 and -0.1 dB (the result is peak-normalised)."
    endif
    synSource = synthesis_source
    analysis_mode = 3
    if synSource > 1
        # preset: synthesise now; the analysis pass (if any) analyses the result
        synRef = if nominal_Hz > 0 then nominal_Hz else 440 fi
        synFs = 44100
        synDur = if duration_s > 0 then duration_s else 6 fi
        synTs = 0.05
        if synRef >= 0.95 * synFs / 2
            exitScript: "Nominal_Hz is above the Nyquist frequency."
        endif
        @siaSynPreset: synSource, synRef, number_of_partials
        nSynIn = nSyn
        @siaSynTransform
        if nSyn = 0
            exitScript: "No partial left after the validity checks (all above Nyquist or invalid)."
        endif
        synLabel$ = if synSource = 2 then "Traditional Tuned Bell" else "Inharmonic Bell" fi
        synName$ = "bell_" + (if synSource = 2 then "traditional" else "inharmonic" fi) + "_" + fixed$(synRef, 0) + "Hz"
        @siaSynRender: synName$
        synDone = 1
        nPass = analyze_result
        if nPass
            selectObject: synSnd
            synCmp = 1
            start_time_s = 0
            end_time_s = 0
            fundamental = 1
        endif
    else
        nPass = 1 + analyze_result
    endif
endif

# ============================================================
# ANALYSIS PASS LOOP. Modes 1-3: one pass. Bell Synthesis: resynthesis =
# pass 1 analyses the source, pass 2 (Analyze_result) the result; presets
# = one pass on the result (or none). The body below is not indented.
# ============================================================
pass = 1
while pass <= nPass

# ============================================================
# SELECTION AND VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object."
endif
sound = selected("Sound")
name$ = selected$("Sound")
safeName$ = replace_regex$(name$, "[^A-Za-z0-9_\-]", "_", 0)
selectObject: sound
xmin = Get start time
xmax = Get end time
sr = Get sampling frequency
nCh = Get number of channels
nyq = sr / 2
nWarn = 0

t1 = start_time_s
t2 = end_time_s
if t2 <= 0
    t2 = xmax
endif
if t1 < xmin
    t1 = xmin
endif
if t2 > xmax
    t2 = xmax
endif
if t2 <= t1
    exitScript: "Invalid analysis interval: start " + fixed$(start_time_s, 3) + " s, end " + fixed$(end_time_s, 3)
        ... + " s (Sound domain " + fixed$(xmin, 3) + " - " + fixed$(xmax, 3) + " s)."
endif
durT = t2 - t1
if durT < 0.05
    exitScript: "The analysis interval is " + fixed$(durT * 1000, 1) + " ms. At least 50 ms are needed "
        ... + "(frequency resolution is about 1 / duration)."
endif
if maximum_partials < 2 or maximum_partials > 200
    exitScript: "Maximum_partials must be between 2 and 200."
endif
if peak_threshold_dB >= -6 or peak_threshold_dB < -140
    exitScript: "Peak_threshold_dB must be between -140 and -6 dB (relative to the strongest peak)."
endif
if search_tolerance < 0.05 or search_tolerance > 0.45
    exitScript: "Search_tolerance must be between 0.05 and 0.45 (fraction of f1)."
endif
manualF = 0
if fundamental = 2
    manualF = manual_frequency_Hz
    if manualF < f0SearchMin or manualF >= nyq / 2
        exitScript: "Manual_frequency_Hz must be between " + string$(f0SearchMin) + " Hz and " + fixed$(nyq / 2, 0)
            ... + " Hz (half the Nyquist frequency of this Sound)."
    endif
endif
# ------------------------------------------------------------
# Bell options (Bell Analysis only). Mode overrides are APPROXIMATE
# frequencies: the analyzer searches for a measured peak within +-50
# cents of them; it never inserts the override value as a measurement.
# Batch use: SIA_BELL = "hum prime tierce quint window step doublets".
# ------------------------------------------------------------
procedure siaWords: .s$
    .n = 0
    .rest$ = replace_regex$(.s$, "^ +| +$", "", 0) + " "
    while length(.rest$) > 1
        .sp = index(.rest$, " ")
        .n = .n + 1
        .v[.n] = number(left$(.rest$, .sp - 1))
        .rest$ = replace_regex$(mid$(.rest$, .sp + 1, length(.rest$) - .sp), "^ +", "", 0)
        if .rest$ = ""
            .rest$ = " "
        endif
    endwhile
endproc
for m to 4
    bellOv[m] = 0
endfor
if pass = 1
    trackWin = 0.1
    trackStep = 0.02
    detectDoublets = 1
endif
if analysis_mode = 3
    bellEnv$ = environment$("SIA_BELL")
    if bellEnv$ <> ""
        @siaWords: bellEnv$
        if siaWords.n <> 7
            exitScript: "SIA_BELL needs 7 numbers: hum prime tierce quint window step doublets."
        endif
        for m to 4
            bellOv[m] = siaWords.v[m]
        endfor
        trackWin = siaWords.v[5]
        trackStep = siaWords.v[6]
        detectDoublets = siaWords.v[7]
    elsif bell_options_dialog and pass = 1
        hum_Hz = 0
        prime_Hz = 0
        tierce_Hz = 0
        quint_Hz = 0
        tracking_window_s = trackWin
        tracking_step_s = trackStep
        detect_doublets = detectDoublets
        beginPause: "Bell Analysis options"
            comment: "Approximate mode frequencies to search around (0 = automatic; +-50 cents)."
            comment: "The Nominal is set with Fundamental = Manual frequency entry."
            real: "Hum_Hz", "0"
            real: "Prime_Hz", "0"
            real: "Tierce_Hz", "0"
            real: "Quint_Hz", "0"
            comment: "Time-resolved tracking (Gaussian-window spectrogram)."
            positive: "Tracking_window_s", string$(trackWin)
            positive: "Tracking_step_s", string$(trackStep)
            boolean: "Detect_doublets", detectDoublets
        clicked = endPause: "Cancel", "OK", 2, 1
        bellOv[1] = hum_Hz
        bellOv[2] = prime_Hz
        bellOv[3] = tierce_Hz
        bellOv[4] = quint_Hz
        trackWin = tracking_window_s
        trackStep = tracking_step_s
        detectDoublets = detect_doublets
    endif
    for m to 4
        if bellOv[m] < 0 or bellOv[m] >= nyq
            exitScript: "Bell mode override frequencies must be 0 (automatic) or between 0 and " + fixed$(nyq, 0) + " Hz."
        endif
    endfor
    if trackWin < 0.01 or trackWin > 2
        exitScript: "Tracking_window_s must be between 0.01 and 2 s."
    endif
    if trackStep < 0.002 or trackStep > 0.5
        exitScript: "Tracking_step_s must be between 0.002 and 0.5 s."
    endif
endif

if start_time_s < xmin or (end_time_s > 0 and end_time_s > xmax)
    @siaWarn: "Interval limited to the Sound domain: " + fixed$(t1, 3) + " - " + fixed$(t2, 3) + " s."
endif

# ============================================================
# PREPROCESSING: interval, mono, DC removal, window, zero padding
# ============================================================
# v1.2: multichannel -> mono. Averaging channels cancels anti-phase content
# (bell6.wav: channel correlation -0.90, the average was 13 dB below each
# channel). If the average keeps less than a quarter (-6 dB) of the mean
# channel power, the loudest single channel is analysed instead.
procedure siaToMono: .src
    selectObject: .src
    .n = Get number of channels
    .out = .src
    if .n > 1
        .pMean = Get power: 0, 0
        .mono = Convert to mono
        .pMono = Get power: 0, 0
        if .pMono < 0.25 * .pMean
            .best = 1
            .bestP = -1
            for .c to .n
                selectObject: .src
                .ch = Extract one channel: .c
                .pc = Get power: 0, 0
                removeObject: .ch
                if .pc > .bestP
                    .bestP = .pc
                    .best = .c
                endif
            endfor
            removeObject: .mono
            selectObject: .src
            .mono = Extract one channel: .best
            monoChannel = .best
            monoLossDb = 10 * log10(max(1e-30, .pMono) / .pMean)
        endif
        removeObject: .src
        .out = .mono
    endif
endproc
monoChannel = 0
monoLossDb = 0
selectObject: sound
part = Extract part: t1, t2, "rectangular", 1, "no"
@siaToMono: part
part = siaToMono.out
selectObject: part
Rename: "sia_part"
dcBefore = Get mean: 0, 0, 0
Subtract mean
nSamp = Get number of samples
rmsPart = Get root-mean-square: 0, 0
peakPart = Get absolute extremum: 0, 0, "None"
if peakPart < 1e-6 or rmsPart < 1e-7
    removeObject: part
    exitScript: "The analysis interval is silent (peak " + fixed$(20 * log10(max(peakPart, 1e-12)), 1) + " dBFS)."
endif

# Praat pitch (ac) on the unwindowed interval - used in Automatic mode
pitchFloor = max(25, 3.5 / durT)
pitchCeil = min(f0SearchMax, nyq * 0.45)
praatF0 = undefined
pitchSpread = undefined
voicedFrac = 0
if pitchFloor < pitchCeil
    selectObject: part
    pitch = To Pitch (ac): 0, pitchFloor, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeil
    nFr = Get number of frames
    nVo = Count voiced frames
    voicedFrac = nVo / max(1, nFr)
    if nVo > 0
        praatF0 = Get quantile: 0, 0, 0.5, "Hertz"
        q10 = Get quantile: 0, 0, 0.1, "Hertz"
        q90 = Get quantile: 0, 0, 0.9, "Hertz"
        if q10 <> undefined and q90 <> undefined and q10 > 0
            pitchSpread = 1200 * log2(q90 / q10)
        endif
    endif
    removeObject: pitch
endif

# window (formula on the sample index, exact over the N samples)
if window = 1
    winName$ = "Blackman-Harris 4-term"
    hw = 4
    sideDb = 85
    selectObject: part
    Formula: "self * (0.35875 - 0.48829 * cos(2 * pi * (col - 0.5) / nSamp) + 0.14128 * cos(4 * pi * (col - 0.5) / nSamp) - 0.01168 * cos(6 * pi * (col - 0.5) / nSamp))"
else
    winName$ = "Hann"
    hw = 2
    sideDb = 28
    selectObject: part
    Formula: "self * (0.5 - 0.5 * cos(2 * pi * (col - 0.5) / nSamp))"
endif
padFactor = 2 ^ zero_padding
nFft = 2 ^ ceiling(log2(nSamp * padFactor))
padded = Create Sound from formula: "sia_padded", 1, 0, nFft / sr, sr, "if col <= nSamp then object[part, 1, col] else 0 fi"
spectrum = To Spectrum: "yes"
df = Get bin width
nBins = Get number of bins
resHz = 1 / durT
lobeHz = hw / durT
mag = Create Sound from formula: "sia_mag_dB", 1, -0.5 * df, (nBins - 0.5) * df, 1 / df,
    ... "10 * log10(object[spectrum, 1, col] ^ 2 + object[spectrum, 2, col] ^ 2 + 1e-300)"
removeObject: padded

# ============================================================
# SPECTRAL PEAK DETECTION
# ============================================================
# Local maxima of the dB magnitude above the relative threshold, with
#   - prominence >= minProminence dB against the deepest dip on each
#     side before a higher value (rejects noise ripple),
#   - window-sidelobe rejection: a peak within 8 / T Hz of a peak more
#     than sideDb stronger is a sidelobe, not a partial,
#   - duplicate merging within one main-lobe half-width (hw / T Hz),
#   - three-point parabolic interpolation on dB.
selectObject: mag
maxDb = Get maximum: 0, 0, "None"
thrDb = maxDb + peak_threshold_dB
clip = Copy: "sia_clip"
Formula: "if self < thrDb then thrDb - 1 else self fi"
pp = To PointProcess (extrema): 1, "yes", "no", "None"
nExt = Get number of points
fLow = max(15, 1.5 * lobeHz)
fHigh = 0.98 * nyq
promBins = ceiling(2 * hw * nFft / nSamp) + 2
nPk = 0
nEdge = 0
for i to nExt
    selectObject: pp
    fx = Get time from index: i
    k = round(fx / df) + 1
    if fx >= fLow and fx <= fHigh and k > 2 and k < nBins - 1
        b = object[mag, 1, k]
        a = object[mag, 1, k - 1]
        c = object[mag, 1, k + 1]
        # prominence
        minL = b
        j = k - 1
        goOn = 1
        while goOn
            if j < 1 or j < k - promBins
                goOn = 0
            else
                v = object[mag, 1, j]
                if v > b
                    goOn = 0
                else
                    minL = min(minL, v)
                    j = j - 1
                endif
            endif
        endwhile
        minR = b
        j = k + 1
        goOn = 1
        while goOn
            if j > nBins or j > k + promBins
                goOn = 0
            else
                v = object[mag, 1, j]
                if v > b
                    goOn = 0
                else
                    minR = min(minR, v)
                    j = j + 1
                endif
            endif
        endwhile
        prom = b - max(minL, minR)
        if prom >= minProminence
            den = a - 2 * b + c
            p = 0
            if den < 0
                p = 0.5 * (a - c) / den
                if abs(p) > 0.5
                    p = 0
                    nEdge = nEdge + 1
                endif
            else
                nEdge = nEdge + 1
            endif
            nPk = nPk + 1
            pkF[nPk] = (k - 1 + p) * df
            pkA[nPk] = b - 0.25 * (a - c) * p
            pkK[nPk] = k
        endif
    endif
endfor
removeObject: clip, pp

# merge duplicates and reject sidelobes (peaks are in ascending frequency)
nP2 = 0
# v1.1: both tests only concern peaks closer than 8 / T Hz (lobeHz = hw / T
# <= 4 / T), so only neighbours inside that distance are scanned - same
# result as the full pairwise loop, O(n) instead of O(n^2) on dense spectra.
for i to nPk
    keep = 1
    for side to 2
        j = if side = 1 then i - 1 else i + 1 fi
        scan = 1
        while scan
            if j < 1 or j > nPk
                scan = 0
            else
                dfr = abs(pkF[j] - pkF[i])
                if dfr >= 8 / durT
                    scan = 0
                else
                    if dfr < lobeHz and pkA[j] > pkA[i]
                        keep = 0
                    endif
                    if pkA[j] - pkA[i] > sideDb
                        keep = 0
                    endif
                    j = if side = 1 then j - 1 else j + 1 fi
                endif
            endif
        endwhile
    endfor
    if keep
        nP2 = nP2 + 1
        qF[nP2] = pkF[i]
        qA[nP2] = pkA[i]
    endif
endfor
nPk = nP2
for i to nPk
    pkF[i] = qF[i]
    pkA[i] = qA[i] - maxDb
    pkUsed[i] = 0
endfor
if nPk < 2
    removeObject: part, spectrum, mag
    exitScript: "Only " + string$(nPk) + " spectral peak(s) above " + fixed$(peak_threshold_dB, 0)
        ... + " dB were found. Lower Peak_threshold_dB, choose a louder/longer interval, or check the selection."
endif

# noise floor: median dB over the analysed band (every 4th bin)
selectObject: mag
kLo = max(2, round(fLow / df) + 1)
kHi = min(nBins - 1, round(fHigh / df) + 1)
kStep = max(1, floor((kHi - kLo) / 4000))
nfTab = Create Table with column names: "sia_nf", 0, "db"
for k from kLo to kHi
    if (k - kLo) mod kStep = 0
        Append row
        r = Get number of rows
        Set numeric value: r, "db", object[mag, 1, k]
    endif
endfor
noiseDb = Get quantile: "db", 0.5
removeObject: nfTab
snrDb = maxDb - noiseDb

# ============================================================
# FUNDAMENTAL / REFERENCE ESTIMATION
# ============================================================
# Harmonic-pattern score for a candidate c (string-tolerant):
#   for B in a grid, expected n*c*sqrt((1+B n^2)/(1+B)), n = 1..nS,
#   explained = sum of weights of matched peaks, matchedFrac = matched/nS,
#   unexplained = weights of unmatched peaks in [0.75 c, (nS+0.5) c],
#   score = explained * matchedFrac - unexplained.
# Weights: linear amplitude 10^(dB/20) relative to the strongest peak, so
# the many weak noise peaks of a real recording cannot outweigh the partials.
procedure siaScore: .c
    .best = -1e30
    .fTop = 0
    for .i to nPk
        .fTop = max(.fTop, pkF[.i])
    endfor
    .nS = min(8, floor(.fTop / .c + 0.5))
    if .nS < 1
        .nS = 1
    endif
    for .g to 8
        if .g = 1
            .bc = 0
        elsif .g = 2
            .bc = 0.0001
        elsif .g = 3
            .bc = 0.0003
        elsif .g = 4
            .bc = 0.0006
        elsif .g = 5
            .bc = 0.001
        elsif .g = 6
            .bc = 0.0015
        elsif .g = 7
            .bc = 0.0025
        else
            .bc = 0.004
        endif
        for .i to nPk
            .m[.i] = 0
        endfor
        .expl = 0
        .nm = 0
        for .n to .nS
            .fe = .n * .c * sqrt((1 + .bc * .n ^ 2) / (1 + .bc))
            .tol = 0.12 * .c + lobeHz
            .bi = 0
            .bd = .tol
            for .i to nPk
                .d = abs(pkF[.i] - .fe)
                if .d <= .bd and .m[.i] = 0
                    .bd = .d
                    .bi = .i
                endif
            endfor
            if .bi > 0
                .m[.bi] = 1
                .nm = .nm + 1
                .expl = .expl + 10 ^ (pkA[.bi] / 20)
            endif
        endfor
        .unex = 0
        .fEnd = (.nS + 0.5) * .c * sqrt((1 + .bc * .nS ^ 2) / (1 + .bc))
        for .i to nPk
            if .m[.i] = 0 and pkF[.i] >= 0.75 * .c and pkF[.i] <= .fEnd
                .unex = .unex + 10 ^ (pkA[.i] / 20)
            endif
        endfor
        .s = .expl * .nm / .nS - .unex
        if .s > .best
            .best = .s
            .bestB = .bc
        endif
    endfor
    .score = .best
endproc

specF0 = undefined
specScore = undefined
praatScore = undefined
f0Source$ = ""
if analysis_mode = 1 and fundamental = 1
    # candidates: strongest peaks divided by 1..8, plus Praat's pitch
    for i to nPk
        ord[i] = i
    endfor
    nTop = min(10, nPk)
    for i to nTop
        for j from i + 1 to nPk
            if pkA[ord[j]] > pkA[ord[i]]
                tmp = ord[i]
                ord[i] = ord[j]
                ord[j] = tmp
            endif
        endfor
    endfor
    bestS = -1e30
    for i to nTop
        for d to 8
            cand = pkF[ord[i]] / d
            if cand >= f0SearchMin and cand <= f0SearchMax and cand >= 2 * lobeHz
                @siaScore: cand
                if siaScore.score > bestS * (1 + 1e-9) + 1e-12
                    bestS = siaScore.score
                    specF0 = cand
                endif
            endif
        endfor
    endfor
    specScore = bestS
    seedF = specF0
    f0Source$ = "spectral harmonic-pattern score"
    if praatF0 <> undefined
        @siaScore: praatF0
        praatScore = siaScore.score
        if praatScore >= 0.9 * bestS and abs(1200 * log2(praatF0 / specF0)) > 50
            seedF = praatF0
            f0Source$ = "Praat pitch (spectral score within 10% of best)"
        elsif abs(1200 * log2(praatF0 / specF0)) <= 50
            f0Source$ = "spectral harmonic-pattern score (agrees with Praat pitch)"
        else
            f0Source$ = "spectral harmonic-pattern score (Praat pitch " + fixed$(praatF0, 1) + " Hz scored lower)"
        endif
    endif
    if seedF = undefined
        removeObject: part, spectrum, mag
        exitScript: "No fundamental could be estimated from the spectrum. Use Fundamental = Manual frequency entry."
    endif
elsif analysis_mode = 1
    seedF = manualF
    f0Source$ = "manual"
endif

# ============================================================
# STRING MODE: ITERATIVE HARMONIC ASSIGNMENT + B FIT
# ============================================================
# Assignment for n = 1..nMax around the model prediction
#   fe_n = n F0 sqrt(1 + B n^2), window = tol * f1 + 3 * sigma_n
#   (sigma_n = propagated uncertainty of the fitted model), capped at
#   0.45 f1. Each peak can be used once; the nearest free peak wins.
procedure siaAssign: .nMax, .f0, .bc, .seB, .seF0
    for .i to nPk
        pkUsed[.i] = 0
    endfor
    .f1 = .f0 * sqrt(max(0.01, 1 + .bc))
    for .n to .nMax
        parF[.n] = undefined
        parA[.n] = undefined
        parFit[.n] = 0
        # v1.1: a fitted negative B can make 1 + B n^2 <= 0 (no real model
        # frequency); the search is then centred on the harmonic n F0.
        .q = 1 + .bc * .n ^ 2
        if .q > 0.01
            .fe = .n * .f0 * sqrt(.q)
        else
            .fe = .n * .f0
            .q = 1
        endif
        parExp[.n] = .fe
        .sig = 0
        if .seB <> undefined
            .sig = sqrt((.n * .f0 * .n ^ 2 / (2 * sqrt(.q)) * .seB) ^ 2 + (.n * sqrt(.q) * .seF0) ^ 2)
        endif
        .win = min(0.45 * .f1, search_tolerance * .f1 + 3 * .sig)
        parWin[.n] = .win
        if .fe > fHigh
            parStat$[.n] = "above Nyquist"
        elsif .fe < fLow
            parStat$[.n] = "below analysis range"
        else
            .bi = 0
            .bd = .win
            for .i to nPk
                .d = abs(pkF[.i] - .fe)
                if .d <= .bd and pkUsed[.i] = 0
                    .bd = .d
                    .bi = .i
                endif
            endfor
            if .bi > 0
                pkUsed[.bi] = .n
                parF[.n] = pkF[.bi]
                parA[.n] = pkA[.bi]
                parStat$[.n] = "measured"
                parFit[.n] = 1
            else
                parStat$[.n] = "not detected"
            endif
        endif
    endfor
endproc

# Weighted least squares of y = (f_n / n)^2 on x = n^2 (see header)
procedure siaFit: .nMax
    .sw = 0
    .swx = 0
    .swy = 0
    .swxx = 0
    .swxy = 0
    .m = 0
    for .n to .nMax
        if parFit[.n]
            .x = .n ^ 2
            .y = (parF[.n] / .n) ^ 2
            .w = .n ^ 4 / parF[.n] ^ 2
            .sw = .sw + .w
            .swx = .swx + .w * .x
            .swy = .swy + .w * .y
            .swxx = .swxx + .w * .x ^ 2
            .swxy = .swxy + .w * .x * .y
            .m = .m + 1
        endif
    endfor
    .ok = 0
    .bc = 0
    .seB = undefined
    .seF0 = undefined
    .f0 = undefined
    .dd = .sw * .swxx - .swx ^ 2
    if .m >= 3 and .dd > 0
        .bb = (.sw * .swxy - .swx * .swy) / .dd
        .aa = (.swxx * .swy - .swx * .swxy) / .dd
        if .aa > 0
            .ok = 1
            .f0 = sqrt(.aa)
            .bc = .bb / .aa
            .ss = 0
            for .n to .nMax
                if parFit[.n]
                    .ss = .ss + .n ^ 4 / parF[.n] ^ 2 * ((parF[.n] / .n) ^ 2 - .aa - .bb * .n ^ 2) ^ 2
                endif
            endfor
            .s2 = .ss / max(1, .m - 2)
            .vb = .s2 * .sw / .dd
            .va = .s2 * .swxx / .dd
            .cab = -.s2 * .swx / .dd
            .vB = .vb / .aa ^ 2 + .bb ^ 2 * .va / .aa ^ 4 - 2 * .bb * .cab / .aa ^ 3
            .seB = sqrt(max(0, .vB))
            .seF0 = sqrt(max(0, .va)) / (2 * .f0)
        endif
    endif
    if .ok = 0 and .m >= 1
        .sum = 0
        for .n to .nMax
            if parFit[.n]
                .sum = .sum + parF[.n] / .n
            endif
        endfor
        .f0 = .sum / .m
        .bc = 0
    endif
endproc

if analysis_mode = 1
    nMaxAll = maximum_partials
    curF0 = seedF
    curB = 0
    curSeB = undefined
    curSeF0 = undefined
    stage = min(nMaxAll, 6)
    goOn = 1
    while goOn
        @siaAssign: stage, curF0, curB, curSeB, curSeF0
        @siaFit: stage
        if siaFit.ok
            curF0 = siaFit.f0
            curB = siaFit.bc
            curSeB = siaFit.seB
            curSeF0 = siaFit.seF0
        elsif siaFit.f0 <> undefined
            curF0 = siaFit.f0
        endif
        if stage >= nMaxAll
            goOn = 0
        else
            stage = min(nMaxAll, stage * 2)
        endif
    endwhile
    # final assignment with the converged model, then one robust pass
    @siaAssign: nMaxAll, curF0, curB, curSeB, curSeF0
    @siaFit: nMaxAll
    nRejected = 0
    if siaFit.ok and siaFit.m >= 5
        resTab = Create Table with column names: "sia_res", 0, "r"
        for n to nMaxAll
            if parFit[n]
                fh = n * siaFit.f0 * sqrt(max(0.01, 1 + siaFit.bc * n ^ 2))
                Append row
                rr = Get number of rows
                Set numeric value: rr, "r", abs(1200 * log2(parF[n] / fh))
            endif
        endfor
        madC = Get quantile: "r", 0.5
        removeObject: resTab
        limC = max(4 * 1.4826 * madC, 1)
        maxRej = floor(0.2 * siaFit.m)
        for n to nMaxAll
            if parFit[n] and nRejected < maxRej
                fh = n * siaFit.f0 * sqrt(max(0.01, 1 + siaFit.bc * n ^ 2))
                if abs(1200 * log2(parF[n] / fh)) > limC
                    parFit[n] = 0
                    nRejected = nRejected + 1
                endif
            endif
        endfor
        if nRejected > 0
            @siaFit: nMaxAll
        endif
    endif
    fitOK = siaFit.ok
    fitM = siaFit.m
    bCoef = siaFit.bc
    seB = siaFit.seB
    f0u = siaFit.f0
    seF0 = siaFit.seF0
    f1model = undefined
    if fitOK
        if 1 + bCoef > 0
            f1model = f0u * sqrt(1 + bCoef)
        endif
    endif
    # reference frequency f1
    if fundamental = 2
        f1ref = manualF
        refSource$ = "manual entry"
    elsif parF[1] <> undefined
        f1ref = parF[1]
        refSource$ = "measured first partial"
    elsif fitOK
        f1ref = f1model
        refSource$ = "model f1 = F0 sqrt(1+B) (partial 1 not detected)"
    else
        f1ref = seedF
        refSource$ = "spectral estimate (partial 1 not detected, no fit)"
    endif
    # derived quantities and fit errors
    nMeas = 0
    nModelInvalid = 0
    nRes = 0
    sse = 0
    ssc = 0
    for n to nMaxAll
        parTheo[n] = n * f1ref
        parDevHz[n] = undefined
        parDevC[n] = undefined
        parModel[n] = undefined
        parResHz[n] = undefined
        parResC[n] = undefined
        if fitOK
            if 1 + bCoef * n ^ 2 > 0
                parModel[n] = n * f0u * sqrt(1 + bCoef * n ^ 2)
            else
                nModelInvalid = nModelInvalid + 1
            endif
        endif
        if parF[n] <> undefined
            nMeas = nMeas + 1
            parDevHz[n] = parF[n] - parTheo[n]
            parDevC[n] = 1200 * log2(parF[n] / parTheo[n])
            if parModel[n] <> undefined
                parResHz[n] = parF[n] - parModel[n]
                parResC[n] = 1200 * log2(parF[n] / parModel[n])
                if parFit[n]
                    nRes = nRes + 1
                    sse = sse + parResHz[n] ^ 2
                    ssc = ssc + parResC[n] ^ 2
                endif
            endif
        endif
    endfor
    rmseHz = undefined
    rmseC = undefined
    if fitOK
        rmseHz = sqrt(sse / max(1, nRes))
        rmseC = sqrt(ssc / max(1, nRes))
    endif
    # Peaks that the harmonic series does not explain: every significant
    # peak up to the highest assigned partial that was NOT assigned. A
    # spectrum whose strong components are not on the series (bell,
    # membrane, wrong f1) must not receive a confident B.
    fAssignedMax = 0
    powAssigned = 0
    for n to nMaxAll
        if parF[n] <> undefined
            fAssignedMax = max(fAssignedMax, parF[n])
            powAssigned = powAssigned + 10 ^ (parA[n] / 10)
        endif
    endfor
    nUnassigned = 0
    powUnassigned = 0
    strongestUnassigned = -999
    unassigned$ = ""
    for i to nPk
        if pkUsed[i] = 0 and pkF[i] <= fAssignedMax * 1.02 + lobeHz
            nUnassigned = nUnassigned + 1
            powUnassigned = powUnassigned + 10 ^ (pkA[i] / 10)
            if pkA[i] > strongestUnassigned
                strongestUnassigned = pkA[i]
            endif
            if nUnassigned <= 8
                unassigned$ = unassigned$ + " " + fixed$(pkF[i], 1) + " Hz (" + fixed$(pkA[i], 0) + " dB)"
            endif
        endif
    endfor
    unassignedShare = powUnassigned / max(1e-300, powAssigned + powUnassigned)
    # reliability verdict on B
    if fitOK and unassignedShare >= 0.10
        bVerdict$ = "INCOMPATIBLE WITH THE STRING MODEL - " + fixed$(100 * unassignedShare, 0) + "% of the peak power lies on peaks that are not on the harmonic series (use General mode or check f1)"
    elsif fitOK = 0
        bVerdict$ = "NOT ESTIMATED - fewer than 3 usable partials or data incompatible with the string model"
    elsif fitM < 5
        bVerdict$ = "UNRELIABLE - only " + string$(fitM) + " partials in the fit (5 or more recommended)"
    elsif rmseC > 5
        bVerdict$ = "POOR FIT - RMS residual " + fixed$(rmseC, 1) + " cents; the spectrum does not follow the stiff-string model"
    elsif abs(bCoef) < 2 * seB
        bVerdict$ = "NOT DISTINGUISHABLE FROM ZERO (|B| < 2 standard errors) - harmonic within measurement precision"
    elsif bCoef < 0
        bVerdict$ = "NEGATIVE - partials are compressed, which the stiff-string model does not predict"
    else
        bVerdict$ = "ESTIMATED"
    endif
    # v1.1: reliability flag carried into every exported row and the summary
    if fitOK = 0
        modelStatus$ = "no_fit"
    elsif bVerdict$ = "ESTIMATED" or left$(bVerdict$, 19) = "NOT DISTINGUISHABLE"
        modelStatus$ = "reliable"
    else
        modelStatus$ = "unreliable"
    endif
    if nModelInvalid > 0
        bVerdict$ = bVerdict$ + " | model undefined (1 + B n^2 <= 0) for " + string$(nModelInvalid) + " partial(s)"
    endif
endif

# ============================================================
# GENERAL MODE: strongest peaks, ratios to a reference
# ============================================================
if analysis_mode = 2
    gTab = Create Table with column names: "sia_g", nPk, "f a"
    for i to nPk
        Set numeric value: i, "f", pkF[i]
        Set numeric value: i, "a", pkA[i]
    endfor
    Sort rows: "a"
    nG = min(maximum_partials, nPk)
    for g to nG
        gF[g] = Get value: nPk - nG + g, "f"
        gA[g] = Get value: nPk - nG + g, "a"
    endfor
    removeObject: gTab
    # ascending frequency
    for i to nG - 1
        for j from i + 1 to nG
            if gF[j] < gF[i]
                tmp = gF[i]
                gF[i] = gF[j]
                gF[j] = tmp
                tmp = gA[i]
                gA[i] = gA[j]
                gA[j] = tmp
            endif
        endfor
    endfor
    # v1.1: the automatic reference is the lowest significant peak of ALL
    # detected peaks (peaks are in ascending frequency), not only of the N
    # strongest; if it is not among them it replaces the weakest listed one.
    lowestMissing = 0
    if fundamental = 1
        inList = 0
        for g to nG
            if abs(gF[g] - pkF[1]) < 1e-9
                inList = 1
            endif
        endfor
        if inList = 0
            lowestMissing = 1
            gw = 1
            for g from 2 to nG
                if gA[g] < gA[gw]
                    gw = g
                endif
            endfor
            gF[gw] = pkF[1]
            gA[gw] = pkA[1]
            for i to nG - 1
                for j from i + 1 to nG
                    if gF[j] < gF[i]
                        tmp = gF[i]
                        gF[i] = gF[j]
                        gF[j] = tmp
                        tmp = gA[i]
                        gA[i] = gA[j]
                        gA[j] = tmp
                    endif
                endfor
            endfor
        endif
    endif
    if fundamental = 2
        fRef = manualF
        refSource$ = "manual entry"
    else
        fRef = gF[1]
        refSource$ = "lowest significant peak; not a pitch claim"
    endif
    for g to nG
        gRatio[g] = gF[g] / fRef
        gK[g] = max(1, round(gRatio[g]))
        gMult[g] = gK[g] * fRef
        gDevHz[g] = gF[g] - gMult[g]
        gDevC[g] = 1200 * log2(gF[g] / gMult[g])
    endfor
endif

# ============================================================
# BELL ANALYSIS (Analysis_mode = 3)
# ============================================================
# Five characteristic modes of a Western church bell, ideal ratios to the
# Nominal: Hum 0.25, Prime 0.50, Tierce 0.60 (just minor third above the
# Prime), Quint 0.75, Nominal 1.00.
#
# Template identification: every significant peak (within 30 dB of the
# strongest) is tried as Nominal N. For each of the four lower modes the
# best free peak within the mode tolerance (Hum/Prime +-150 cents,
# Tierce/Quint +-120 cents; +-50 cents around a manual override) is
#   q = (1 - (dev / tol)^2) * 10^(dB / 40)
# (closeness x compressed amplitude). Score = Nominal weight + sum of q
# - 0.5 x weight of significant peaks (>= -30 dB and no more than 20 dB
# below the candidate) in 0.22 N .. 1.04 N that the template does NOT
# explain (doublet partners within 50 cents of a matched mode excepted).
# Weak peaks are not counted: a real recording has hundreds of them
# (background, other bells) and their sum would favour the narrow
# template range of a too-low Nominal. A candidate Nominal must be within
# 30 dB of the strongest peak and needs >= 2 of the 4 lower modes. The penalty
# rejects octave errors: a candidate at 2N leaves the true Hum and Quint
# unexplained inside its own template range.
# No mode is ever filled with a theoretical value: unmatched = not detected.
#
# Tracking: Gaussian-window spectrogram (Praat To Spectrogram); for each
# tracked partial the maximum power inside a band around its frequency
# (half-width <= half the distance to the nearest other tracked partial)
# per frame. The window is lengthened automatically until the bands can
# be separated (>= 3 / smallest spacing).
# Decay: least squares of level (dB) on time from the strike + one window
# to the last frame >= 15 dB above the frame's noise floor:
#   A(t) = A0 exp(-alpha t)  <=>  dB(t) = dB0 - 8.686 alpha t,
#   T60 = 60 / (8.686 alpha) = 6.908 / alpha.
# Checks before a fit is called reliable: >= 6 frames and >= 10 dB of
# decay, R^2 >= 0.95, RMS residual <= max(2 dB, 6% of the fitted decay
# range), no two-stage decay (slopes of
# the two halves differ by > 2x), no beating (residual spectrum peak
# >= 1.5 dB and >= 3x its median).
# Doublets: two resolved peaks (spacing >= 2 main-lobe half-widths of the
# analysis window) within 50 cents; reported with |fa - fb| as the
# expected beat; "confirmed" only if the tracked trajectory beats at
# that rate (+-25%), otherwise "spectral only (unconfirmed)". Beating
# found in a trajectory without a resolved pair is reported as a
# possible unresolved doublet.

procedure siaBellMatch: .cIdx, .fn
    for .i to nPk
        .used[.i] = 0
    endfor
    .score = 0
    bmIdx[5] = .cIdx
    if .cIdx > 0
        .used[.cIdx] = 1
        .score = 10 ^ (pkA[.cIdx] / 40)
    endif
    .nMatched = 0
    for .m to 4
        bmIdx[.m] = 0
        bmQ[.m] = 0
        if bellOv[.m] > 0
            .e = bellOv[.m]
            .tol = 50
        else
            .e = bmR[.m] * .fn
            .tol = bmTol[.m]
        endif
        .best = 0
        for .i to nPk
            if .used[.i] = 0 and pkSide[.i] = 0
                .dc = 1200 * log2(pkF[.i] / .e)
                if abs(.dc) <= .tol
                    .cl = 1 - (.dc / .tol) ^ 2
                    .q = .cl * 10 ^ (pkA[.i] / 40)
                    if .q > .best
                        .best = .q
                        bmIdx[.m] = .i
                        bmQ[.m] = .cl
                    endif
                endif
            endif
        endfor
        if bmIdx[.m] > 0
            .used[bmIdx[.m]] = 1
            .score = .score + .best
            .nMatched = .nMatched + 1
        endif
    endfor
    .unex = 0
    .sigLevel = -30
    if .cIdx > 0
        .sigLevel = max(-30, pkA[.cIdx] - 20)
    endif
    for .i to nPk
        if .used[.i] = 0 and pkSide[.i] = 0 and pkA[.i] >= .sigLevel and pkF[.i] >= 0.22 * .fn and pkF[.i] <= 1.04 * .fn
            .partner = 0
            for .m to 5
                if bmIdx[.m] > 0
                    if abs(1200 * log2(pkF[.i] / pkF[bmIdx[.m]])) <= 50
                        .partner = 1
                    endif
                endif
            endfor
            if .partner = 0
                .unex = .unex + 10 ^ (pkA[.i] / 40)
            endif
        endif
    endfor
    .score = .score - 0.5 * .unex
endproc

procedure siaInterval: .ratio
    .c = 1200 * log2(.ratio)
    .st = round(.c / 100)
    .rem = .c - 100 * .st
    @siaFmt: .rem, 0
    .out$ = (if .st >= 0 then "+" else "" fi) + string$(.st) + " st " + (if .rem >= 0 then "+" else "" fi) + siaFmt.out$ + "c"
endproc

# v1.2 doublet confirmation, independent of the tracking window: band-pass
# the pair (fa - df .. fb + df), take its intensity envelope with a window
# short against the beat period (minimum pitch 20 df, i.e. 3.2 / (20 df) s,
# and still >= 4 carrier periods), detrend the dB envelope from 0.1 s after
# the strike to 45 dB below its maximum, and look for the strongest
# periodicity between 0.2 df and 2.5 df. Confirmed if it lies within 25% of
# df with >= 1 dB amplitude and >= 3x the median of that range, over at
# least 3 beat periods.
procedure siaBeat: .fa, .fb
    .df = .fb - .fa
    .ok = 0
    .beat = undefined
    .amp = undefined
    .why$ = ""
    .minPitch = max(60, 20 * .df)
    if .minPitch > 0.8 * .fa
        .why$ = "pair too wide for an envelope test at this frequency"
    else
        selectObject: trkSnd
        .band = Filter (pass Hann band): .fa - .df, .fb + .df, max(0.5, .df / 2)
        .step = min(0.05, max(0.005, 1 / (8 * .df)))
        .int = To Intensity: .minPitch, .step, "yes"
        .nf = Get number of frames
        .mx = Get maximum: 0, 0, "Parabolic"
        .n = 0
        for .k to .nf
            .t = Get time from frame number: .k
            .v = Get value in frame: .k
            if .t + t1 >= tStrike + 0.1 and .v <> undefined
                if .v >= .mx - 45
                    .n = .n + 1
                    .tt[.n] = .t
                    .vv[.n] = .v
                endif
            endif
        endfor
        removeObject: .band, .int
        if .n < 20
            .why$ = "band too weak after the strike"
        elsif .tt[.n] - .tt[1] < 3 / .df
            .why$ = "fewer than 3 beat periods (" + fixed$(.tt[.n] - .tt[1], 2) + " s) in the recording"
        else
            .sx = 0
            .sy = 0
            .sxx = 0
            .sxy = 0
            for .k to .n
                .sx = .sx + .tt[.k]
                .sy = .sy + .vv[.k]
                .sxx = .sxx + .tt[.k] ^ 2
                .sxy = .sxy + .tt[.k] * .vv[.k]
            endfor
            .sl = (.n * .sxy - .sx * .sy) / (.n * .sxx - .sx ^ 2)
            .ic = (.sy - .sl * .sx) / .n
            for .k to .n
                .rr[.k] = .vv[.k] - .ic - .sl * .tt[.k]
            endfor
            .nb = 0
            .bestA = 0
            .f = 0.2 * .df
            while .f <= 2.5 * .df
                .re = 0
                .im = 0
                for .k to .n
                    .re = .re + .rr[.k] * cos(2 * pi * .f * .tt[.k])
                    .im = .im + .rr[.k] * sin(2 * pi * .f * .tt[.k])
                endfor
                .nb = .nb + 1
                .aa[.nb] = 2 * sqrt(.re ^ 2 + .im ^ 2) / .n
                if .aa[.nb] > .bestA
                    .bestA = .aa[.nb]
                    .beat = .f
                endif
                .f = .f + .df / 40
            endwhile
            .bt = Create Table with column names: "sia_beat", .nb, "a"
            for .k to .nb
                Set numeric value: .k, "a", .aa[.k]
            endfor
            .med = Get quantile: "a", 0.5
            removeObject: .bt
            .amp = .bestA
            if abs(.beat - .df) <= 0.25 * .df and .bestA >= 1 and .bestA >= 3 * .med
                .ok = 1
            else
                .why$ = "no beat at " + fixed$(.df, 2) + " Hz in the band envelope (strongest periodicity " + fixed$(.beat, 2) + " Hz, " + fixed$(.bestA, 1) + " dB)"
            endif
        endif
    endif
endproc

procedure siaLinFit: .k, .c1, .c2
    .n = 0
    .sx = 0
    .sy = 0
    .sxx = 0
    .sxy = 0
    for .c from .c1 to .c2
        .x = frT[.c]
        .y = trDb[.k, .c]
        .n = .n + 1
        .sx = .sx + .x
        .sy = .sy + .y
        .sxx = .sxx + .x ^ 2
        .sxy = .sxy + .x * .y
    endfor
    .slope = undefined
    .icpt = undefined
    if .n >= 3
        .den = .n * .sxx - .sx ^ 2
        if .den > 0
            .slope = (.n * .sxy - .sx * .sy) / .den
            .icpt = (.sy - .slope * .sx) / .n
        endif
    endif
endproc

if analysis_mode = 3
    bmName$[1] = "Hum"
    bmName$[2] = "Prime"
    bmName$[3] = "Tierce"
    bmName$[4] = "Quint"
    bmName$[5] = "Nominal"
    bmR[1] = 0.25
    bmR[2] = 0.5
    bmR[3] = 0.6
    bmR[4] = 0.75
    bmR[5] = 1
    bmTol[1] = 150
    bmTol[2] = 150
    bmTol[3] = 120
    bmTol[4] = 120
    # ---------- sidebands / leakage (v1.2) ----------
    # A peak >= 25 dB weaker than a neighbour within 50 cents is not
    # treated as an independent mode: on real
    # bells these are modulation sidebands (bell6.wav: the 426.5 Hz partial
    # wanders +-0.23 Hz with a ~5 s period, giving side peaks at +-0.23 Hz,
    # -30 dB) or leakage skirts. They stay listed, labelled, but are excluded
    # from the template, the doublets and the tracking.
    for i to nPk
        pkSide[i] = 0
        lim = pkF[i] * (2 ^ (50 / 1200) - 1)
        for side to 2
            j = if side = 1 then i - 1 else i + 1 fi
            scan = 1
            while scan
                if j < 1 or j > nPk
                    scan = 0
                elsif abs(pkF[j] - pkF[i]) > lim
                    scan = 0
                else
                    if pkA[j] >= pkA[i] + 25
                        if pkSide[i] = 0
                            pkSide[i] = j
                        elsif pkA[j] > pkA[pkSide[i]]
                            pkSide[i] = j
                        endif
                    endif
                    j = if side = 1 then j - 1 else j + 1 fi
                endif
            endwhile
        endfor
    endfor
    bellOK = 0
    bellAmbig = 0
    # a noise-like spectrum (strongest peak < 25 dB above the median floor)
    # contains thousands of peaks among which ANY template finds matches:
    # no automatic identification is attempted then.
    noiseLike = snrDb < 25
    altNominal = undefined
    altShare = undefined
    # ---------- Nominal ----------
    if fundamental = 2
        cBest = 0
        dBest = 50
        for i to nPk
            d = abs(1200 * log2(pkF[i] / manualF))
            if d <= dBest and pkSide[i] = 0
                dBest = d
                cBest = i
            endif
        endfor
        fN = manualF
        nomSource$ = "manual entry"
        @siaBellMatch: cBest, fN
        bellOK = 1
        bellScore = siaBellMatch.score
    elsif noiseLike
        nomSource$ = "none (noise-like spectrum)"
        fN = undefined
    else
        nomSource$ = "template identification"
        # candidates: the (at most 40) strongest peaks within 30 dB of the maximum
        nCand = 0
        for i to nPk
            if pkA[i] >= -30 and pkF[i] >= 4 * fLow and pkSide[i] = 0
                nCand = nCand + 1
                cand[nCand] = i
            endif
        endfor
        if nCand > 40
            for a to 40
                for b from a + 1 to nCand
                    if pkA[cand[b]] > pkA[cand[a]]
                        tmp = cand[a]
                        cand[a] = cand[b]
                        cand[b] = tmp
                    endif
                endfor
            endfor
            nCand = 40
        endif
        bestS = -1e30
        cBest = 0
        for ci to nCand
            c = cand[ci]
            if 1
                @siaBellMatch: c, pkF[c]
                if siaBellMatch.nMatched >= 2 and siaBellMatch.score > bestS
                    bestS = siaBellMatch.score
                    cBest = c
                endif
            endif
        endfor
        if cBest > 0
            # runner-up with a different Nominal (more than 50 cents away)
            secS = -1e30
            for ci to nCand
                c = cand[ci]
                if c <> cBest
                    if abs(1200 * log2(pkF[c] / pkF[cBest])) > 50
                        @siaBellMatch: c, pkF[c]
                        if siaBellMatch.nMatched >= 2 and siaBellMatch.score > secS
                            secS = siaBellMatch.score
                            altNominal = pkF[c]
                        endif
                    endif
                endif
            endfor
            if secS > -1e30 and bestS > 0
                altShare = secS / bestS
                if altShare >= 0.9
                    bellAmbig = 1
                endif
            endif
            fN = pkF[cBest]
            @siaBellMatch: cBest, fN
            bellOK = 1
            bellScore = bestS
        else
            fN = undefined
        endif
    endif
    # ---------- the five modes ----------
    nModesFound = 0
    for m to 5
        bmF[m] = undefined
        bmA[m] = undefined
        bmIdeal[m] = undefined
        bmRatio[m] = undefined
        bmDevHz[m] = undefined
        bmDevC[m] = undefined
        bmConf[m] = undefined
        if bellOK
            bmIdeal[m] = bmR[m] * fN
        endif
        if bellOK = 0
            bmStat$[m] = "not identified (no bell pattern)"
        elsif bmIdx[m] = 0
            bmStat$[m] = "not detected"
            if m = 5
                bmStat$[m] = "not detected near the manual Nominal"
            endif
        else
            nModesFound = nModesFound + 1
            bmF[m] = pkF[bmIdx[m]]
            bmA[m] = pkA[bmIdx[m]]
            bmRatio[m] = bmF[m] / fN
            bmDevHz[m] = bmF[m] - bmIdeal[m]
            bmDevC[m] = 1200 * log2(bmF[m] / bmIdeal[m])
            if m = 5
                bmConf[m] = 1
                bmStat$[m] = if fundamental = 2 then "measured (manual reference)" else "identified (reference)" fi
                if fundamental = 2
                    bmConf[m] = max(0, 1 - (abs(bmDevC[m]) / 50) ^ 2)
                endif
            else
                bmConf[m] = bmQ[m]
                if bmQ[m] >= 0.5 and bmA[m] >= -50
                    bmStat$[m] = "identified"
                else
                    bmStat$[m] = "uncertain"
                endif
                if bellOv[m] > 0
                    bmStat$[m] = bmStat$[m] + " (near manual " + fixed$(bellOv[m], 1) + " Hz)"
                endif
            endif
        endif
    endfor
    # ---------- harmonicity check ----------
    # A harmonic tone matches Hum/Prime/Quint/Nominal = harmonics 1-4 exactly,
    # so the template alone cannot exclude it. If >= 80% of the strong peaks
    # (>= -40 dB, at least 6, up to the 20th multiple - beyond it the integer
    # grid is denser than the tolerance) lie within 15 cents of integer
    # multiples of the lowest strong peak, the identification is doubtful.
    harmonicSpec = 0
    nStrong = 0
    nOnGrid = 0
    fBase = 0
    for i to nPk
        if pkA[i] >= -40 and fBase = 0
            fBase = pkF[i]
        endif
    endfor
    if fBase > 0
        for i to nPk
            if pkA[i] >= -40 and pkF[i] <= 20.5 * fBase
                nStrong = nStrong + 1
                kk = max(1, round(pkF[i] / fBase))
                if abs(1200 * log2(pkF[i] / (kk * fBase))) <= 15
                    nOnGrid = nOnGrid + 1
                endif
            endif
        endfor
        if nStrong >= 6 and nOnGrid >= 0.8 * nStrong
            harmonicSpec = 1
        endif
    endif

    # ---------- doublets (resolved pairs within 50 cents) ----------
    nDbl = 0
    for i to nPk
        pkMode[i] = 0
        pkPartner[i] = 0
    endfor
    for m to 5
        if bmF[m] <> undefined
            pkMode[bmIdx[m]] = m
        endif
    endfor
    if detectDoublets
        # (a) around each identified mode: the strongest free peak within 50 cents
        for m to 5
            if bmF[m] <> undefined
                im = bmIdx[m]
                jb = 0
                for j to nPk
                    if pkMode[j] = 0 and pkPartner[j] = 0 and pkSide[j] = 0 and j <> im
                        if abs(1200 * log2(pkF[j] / pkF[im])) <= 50 and abs(pkF[j] - pkF[im]) >= 2 * lobeHz and pkA[j] >= pkA[im] - 40
                            if jb = 0
                                jb = j
                            elsif pkA[j] > pkA[jb]
                                jb = j
                            endif
                        endif
                    endif
                endfor
                if jb > 0
                    nDbl = nDbl + 1
                    dbA[nDbl] = min(im, jb)
                    dbB[nDbl] = max(im, jb)
                    dbStat$[nDbl] = "spectral only (unconfirmed)"
                    pkPartner[jb] = im
                endif
            endif
        endfor
        # (b) other strong pairs (both >= -40 dB) within 50 cents
        for i to nPk - 1
            if pkMode[i] = 0 and pkPartner[i] = 0 and pkSide[i] = 0 and pkA[i] >= -40
                j = i + 1
                scan = 1
                while scan
                    if j > nPk
                        scan = 0
                    elsif 1200 * log2(pkF[j] / pkF[i]) > 50
                        scan = 0
                    else
                        if pkMode[j] = 0 and pkPartner[j] = 0 and pkSide[j] = 0 and pkA[j] >= -40 and pkPartner[i] = 0
                            if pkF[j] - pkF[i] >= 2 * lobeHz
                                nDbl = nDbl + 1
                                dbA[nDbl] = i
                                dbB[nDbl] = j
                                dbStat$[nDbl] = "spectral only (unconfirmed)"
                                if pkA[i] >= pkA[j]
                                    pkPartner[j] = -i
                                else
                                    pkPartner[i] = -j
                                endif
                            endif
                        endif
                        j = j + 1
                    endif
                endwhile
            endif
        endfor
    endif
    # ---------- other components (not one of the five modes) ----------
    nOthAll = 0
    for i to nPk
        if pkMode[i] = 0
            nOthAll = nOthAll + 1
            othI[nOthAll] = i
        endif
    endfor
    # strongest Maximum_partials of them, then ascending frequency
    nOth = min(maximum_partials, nOthAll)
    for a to nOth
        for b from a + 1 to nOthAll
            if pkA[othI[b]] > pkA[othI[a]]
                tmp = othI[a]
                othI[a] = othI[b]
                othI[b] = tmp
            endif
        endfor
    endfor
    for a to nOth - 1
        for b from a + 1 to nOth
            if pkF[othI[b]] < pkF[othI[a]]
                tmp = othI[a]
                othI[a] = othI[b]
                othI[b] = tmp
            endif
        endfor
    endfor
    for a to nOth
        i = othI[a]
        if pkSide[i] > 0
            othType$[a] = "sideband or leakage of " + fixed$(pkF[pkSide[i]], 1) + " Hz (not an independent mode)"
        elsif pkPartner[i] > 0
            othType$[a] = "doublet partner of " + bmName$[pkMode[pkPartner[i]]]
        elsif pkPartner[i] < 0
            othType$[a] = "doublet partner of " + fixed$(pkF[-pkPartner[i]], 1) + " Hz"
        elsif bellOK = 0
            othType$[a] = "component"
        elsif pkF[i] > fN
            othType$[a] = "upper partial"
        else
            othType$[a] = "unassigned (below Nominal)"
        endif
    endfor
    # reference for ratios (v1.2): the Nominal when identified; otherwise
    # the strongest component (a 15 Hz rumble is no musical reference), and
    # ratio_to_nominal is then NA
    if bellOK
        fRefB = fN
        refBName$ = "Nominal"
    else
        iS = 1
        for i to nPk
            if pkA[i] > pkA[iS]
                iS = i
            endif
        endfor
        fRefB = pkF[iS]
        refBName$ = "strongest component"
    endif

    # ---------- partials to track ----------
    # v1.2: the tracking window is capped at wCap = min(1 s, interval / 6),
    # so decays keep a usable time resolution. Components closer than
    # 3 / wCap Hz to an already tracked stronger one cannot be separated at
    # that resolution and are not tracked separately (they stay in its band).
    # Doublets are confirmed separately (band envelope, see below), so a
    # close pair never forces a long window any more (bell6.wav: 6.69 s).
    wCap = min(1, durT / 6)
    mergeHz = 3 / wCap
    nTr = 0
    if bellOK
        for m to 5
            if bmF[m] <> undefined
                nTr = nTr + 1
                trName$[nTr] = bmName$[m]
                trKey$[nTr] = replace_regex$(bmName$[m], "([A-Z])", "\L\1", 0)
                trF[nTr] = bmF[m]
                trPk[nTr] = bmIdx[m]
                trMode[nTr] = m
            endif
        endfor
    endif
    # other components: up to 6 (pattern found) or 8 (no pattern), strongest
    # first; sidebands and neighbours closer than mergeHz excluded (a doublet
    # partner far enough away is tracked separately)
    maxOther = if bellOK then 6 else 8 fi
    # Bell Synthesis: track as many components as will be synthesised
    if synthMode
        maxOther = max(0, min(40, if synCmp then nSyn else number_of_partials fi) - nTr)
    endif
    for b to nOthAll
        othTaken[b] = 0
    endfor
    nUp = 0
    goPick = 1
    while goPick and nUp < maxOther
        bBest = 0
        for b to nOthAll
            i = othI[b]
            if othTaken[b] = 0 and pkSide[i] = 0 and pkA[i] >= -50
                near = 0
                for k2 to nTr
                    if abs(pkF[i] - trF[k2]) < mergeHz
                        near = 1
                    endif
                endfor
                if near = 0
                    if bBest = 0
                        bBest = b
                    elsif pkA[i] > pkA[othI[bBest]]
                        bBest = b
                    endif
                endif
            endif
        endfor
        if bBest = 0
            goPick = 0
        else
            othTaken[bBest] = 1
            i = othI[bBest]
            nUp = nUp + 1
            nTr = nTr + 1
            trName$[nTr] = fixed$(pkF[i], 0) + " Hz"
            trKey$[nTr] = (if bellOK then "u" else "p" fi) + string$(nUp)
            trF[nTr] = pkF[i]
            trPk[nTr] = i
            trMode[nTr] = 0
        endif
    endwhile
    # Bell Synthesis, analysis of the result: every requested partial that
    # is not already tracked (and not within mergeHz of a tracked one) is
    # tracked at its REQUESTED frequency, so weak / fast-decaying partials
    # (strongly attenuated in the long windowed spectrum) are still measured
    if synthMode and synCmp
        nReq = 0
        for iS to nSyn
            near = 0
            for k2 to nTr
                if abs(synF[iS] - trF[k2]) < mergeHz
                    near = 1
                endif
            endfor
            if near = 0 and nTr < 60
                nReq = nReq + 1
                nTr = nTr + 1
                trName$[nTr] = fixed$(synF[iS], 0) + " Hz"
                trKey$[nTr] = "r" + string$(nReq)
                trF[nTr] = synF[iS]
                trPk[nTr] = 0
                trMode[nTr] = 0
            endif
        endfor
    endif
    # band half-widths: half the distance to the nearest other tracked partial
    dMin = 1e9
    for k to nTr
        trNear[k] = 1e9
        for k2 to nTr
            if k2 <> k
                trNear[k] = min(trNear[k], abs(trF[k2] - trF[k]))
            endif
        endfor
        dMin = min(dMin, trNear[k])
    endfor
    trackWinEff = min(trackWin, wCap)
    winRaised = 0
    winCapped = 0
    if nTr > 1 and trackWinEff < 3 / dMin
        trackWinEff = 3 / dMin
        winRaised = 1
        if trackWinEff > wCap
            trackWinEff = wCap
            winCapped = 1
        endif
    endif
    fMaxTr = 0
    for k to nTr
        fMaxTr = max(fMaxTr, trF[k])
    endfor
    selectObject: sound
    trkSnd = Extract part: t1, t2, "rectangular", 1, "no"
    @siaToMono: trkSnd
    trkSnd = siaToMono.out
    fMaxSpg = min(nyq, 1.15 * fMaxTr + 100)
    selectObject: trkSnd
    spg = To Spectrogram: trackWinEff, fMaxSpg, trackStep, 0.25 / trackWinEff, "Gaussian"
    spgMat = To Matrix
    nFr = Get number of columns
    xT1 = Get x of column: 1
    dxT = Get column distance
    nRowS = Get number of rows
    yT1 = Get y of row: 1
    dyT = Get row distance
    for k to nTr
        hb = min(0.5 * trNear[k], max(2 / trackWinEff, 0.006 * trF[k]))
        # a doublet partner that is NOT tracked separately (closer than
        # mergeHz) is included in this band; tracked partners keep their own
        for d to nDbl
            if dbA[d] = trPk[k] or dbB[d] = trPk[k]
                other = if dbA[d] = trPk[k] then dbB[d] else dbA[d] fi
                tracked = 0
                for k2 to nTr
                    if trPk[k2] = other
                        tracked = 1
                    endif
                endfor
                if tracked = 0
                    hb = min(0.5 * trNear[k], max(hb, abs(pkF[dbB[d]] - pkF[dbA[d]]) + 1.5 / trackWinEff))
                endif
            endif
        endfor
        trHb[k] = hb
        trR1[k] = max(1, round((trF[k] - hb - yT1) / dyT) + 1)
        trR2[k] = min(nRowS, round((trF[k] + hb - yT1) / dyT) + 1)
    endfor
    # noise floor per frame: mean dB of every 4th row outside all bands
    for r to nRowS
        rowFree[r] = 1
    endfor
    for k to nTr
        for r from trR1[k] to trR2[k]
            rowFree[r] = 0
        endfor
    endfor
    trMax = -1e30
    for c to nFr
        # absolute time on the Sound's own axis (the extracted copy starts at 0)
        frT[c] = t1 + xT1 + (c - 1) * dxT
        tot = 0
        for k to nTr
            pmax = 0
            for r from trR1[k] to trR2[k]
                pmax = max(pmax, object[spgMat, r, c])
            endfor
            trDb[k, c] = 10 * log10(pmax + 1e-30)
            tot = tot + pmax
            trMax = max(trMax, trDb[k, c])
        endfor
        frTot[c] = tot
        sf = 0
        nf = 0
        for r to nRowS
            if rowFree[r] and r mod 4 = 0
                sf = sf + 10 * log10(object[spgMat, r, c] + 1e-30)
                nf = nf + 1
            endif
        endfor
        floorDb[c] = if nf > 0 then sf / nf else -300 fi
    endfor
    # relative to the strongest tracked level
    for c to nFr
        for k to nTr
            trDb[k, c] = trDb[k, c] - trMax
        endfor
        floorDb[c] = floorDb[c] - trMax
    endfor
    # strike (v1.2): taken from the AUDIO - time of maximum intensity (10 ms
    # resolution) - not from the spectrogram, whose window can be long.
    selectObject: trkSnd
    strInt = To Intensity: 100, 0, "yes"
    tStrike = Get time of maximum: 0, 0, "Parabolic"
    tStrike = t1 + tStrike
    removeObject: strInt
    cStrike = 1
    for c to nFr
        if frT[c] <= tStrike
            cStrike = c
        endif
    endfor
    # ---------- decay fits ----------
    # a Gaussian-window frame at time t spans t - W .. t + W (Praat's window
    # length W is the effective length): fits start at the first frame whose
    # whole window lies after the strike
    cFit1 = nFr
    for c to nFr
        if frT[c] >= tStrike + max(trackWinEff, 0.03) and cFit1 = nFr
            cFit1 = c
        endif
    endfor
    for k to nTr
        trStat$[k] = ""
        trA0[k] = undefined
        trAlpha[k] = undefined
        trT60[k] = undefined
        trR2fit[k] = undefined
        trRms[k] = undefined
        trRange[k] = undefined
        trBeat[k] = undefined
        trSlope1[k] = undefined
        trSlope2[k] = undefined
        trC1[k] = cFit1
        # end: the last frame before 3 consecutive frames < floor + 15 dB
        c2 = cFit1
        lowRun = 0
        c = cFit1
        goOn = 1
        while goOn
            if c > nFr
                goOn = 0
            elsif trDb[k, c] - floorDb[c] >= 15
                c2 = c
                lowRun = 0
                c = c + 1
            else
                lowRun = lowRun + 1
                if lowRun >= 3
                    goOn = 0
                else
                    c = c + 1
                endif
            endif
        endwhile
        trC2[k] = c2
        nFit = c2 - cFit1 + 1
        if nFit < 6
            trStat$[k] = "not estimated - fewer than 6 frames above the noise floor after the strike"
        else
            @siaLinFit: k, cFit1, c2
            s = siaLinFit.slope
            b0 = siaLinFit.icpt
            trA0[k] = b0 + s * tStrike
            trRange[k] = -s * (frT[c2] - frT[cFit1])
            ssr = 0
            sst = 0
            my = 0
            for c from cFit1 to c2
                my = my + trDb[k, c]
            endfor
            my = my / nFit
            for c from cFit1 to c2
                res[c] = trDb[k, c] - (b0 + s * frT[c])
                ssr = ssr + res[c] ^ 2
                sst = sst + (trDb[k, c] - my) ^ 2
            endfor
            trRms[k] = sqrt(ssr / nFit)
            trR2fit[k] = if sst > 0 then 1 - ssr / sst else 0 fi
            # two halves
            cm = floor((cFit1 + c2) / 2)
            if cm - cFit1 + 1 >= 4 and c2 - cm >= 4
                @siaLinFit: k, cFit1, cm
                trSlope1[k] = siaLinFit.slope
                @siaLinFit: k, cm + 1, c2
                trSlope2[k] = siaLinFit.slope
            endif
            # beating: spectrum of the residual, 0.1 Hz grid
            fbLo = max(0.2, 2 / (frT[c2] - frT[cFit1]))
            fbHi = min(15, 0.45 / dxT)
            nb = 0
            bestAmp = 0
            bestFb = undefined
            if fbHi > fbLo
                fb = fbLo
                while fb <= fbHi
                    re = 0
                    im = 0
                    for c from cFit1 to c2
                        re = re + res[c] * cos(2 * pi * fb * frT[c])
                        im = im + res[c] * sin(2 * pi * fb * frT[c])
                    endfor
                    nb = nb + 1
                    bAmp[nb] = 2 * sqrt(re ^ 2 + im ^ 2) / nFit
                    if bAmp[nb] > bestAmp
                        bestAmp = bAmp[nb]
                        bestFb = fb
                    endif
                    fb = fb + 0.1
                endwhile
            endif
            beating = 0
            if nb >= 5
                bTab = Create Table with column names: "sia_b", nb, "a"
                for i to nb
                    Set numeric value: i, "a", bAmp[i]
                endfor
                medAmp = Get quantile: "a", 0.5
                removeObject: bTab
                if bestAmp >= 1.5 and bestAmp >= 3 * medAmp
                    beating = 1
                    trBeat[k] = bestFb
                endif
            endif
            if s >= 0
                trStat$[k] = "no decay measured (level does not fall)"
            elsif trRange[k] < 10
                trStat$[k] = "uncertain - only " + fixed$(trRange[k], 1) + " dB of decay above the noise floor"
                trAlpha[k] = -s * ln(10) / 20
            else
                trAlpha[k] = -s * ln(10) / 20
                twoStage = 0
                if trSlope1[k] <> undefined and trSlope2[k] <> undefined
                    if trSlope1[k] < 0 and trSlope2[k] < 0
                        rs = trSlope1[k] / trSlope2[k]
                        if rs > 2 or rs < 0.5
                            twoStage = 1
                        endif
                    endif
                endif
                if beating
                    trStat$[k] = "beating at " + fixed$(trBeat[k], 1) + " Hz - single exponential approximate"
                    trT60[k] = 6.908 / trAlpha[k]
                elsif twoStage
                    trStat$[k] = "two-stage decay (" + fixed$(trSlope1[k], 1) + " then " + fixed$(trSlope2[k], 1) + " dB/s) - single exponential not adequate"
                elsif trRms[k] > max(2, 0.06 * trRange[k]) or trR2fit[k] < 0.95
                    trStat$[k] = "non-exponential (RMS residual " + fixed$(trRms[k], 1) + " dB over " + fixed$(trRange[k], 0) + " dB, R2 " + fixed$(trR2fit[k], 3) + ")"
                else
                    trStat$[k] = "reliable"
                    trT60[k] = 6.908 / trAlpha[k]
                endif
            endif
        endif
    endfor
    # doublet confirmation: beat in the band envelope of the pair (v1.2)
    for d to nDbl
        @siaBeat: pkF[dbA[d]], pkF[dbB[d]]
        dbBeat[d] = siaBeat.beat
        dbBeatAmp[d] = siaBeat.amp
        if siaBeat.ok
            dbStat$[d] = "confirmed (band envelope beats at " + fixed$(siaBeat.beat, 2) + " Hz, " + fixed$(siaBeat.amp, 1) + " dB)"
        else
            dbStat$[d] = "unconfirmed - " + siaBeat.why$
        endif
    endfor
    removeObject: spgMat, trkSnd
endif

# ============================================================
# WARNINGS AND RELIABILITY NOTES
# ============================================================
if durT < 0.25
    @siaWarn: "Short interval (" + fixed$(durT, 3) + " s): frequency resolution about " + fixed$(resHz, 1) + " Hz; partial frequencies and B are imprecise."
endif
if monoChannel > 0
    @siaWarn: "The channels largely cancel when averaged (the mono mix is " + fixed$(-monoLossDb, 1) + " dB below the mean channel power - anti-phase recording), so channel " + string$(monoChannel) + " alone was analysed."
endif
if abs(dcBefore) > 0.001
    @siaWarn: "DC offset of " + fixed$(dcBefore, 4) + " removed before analysis."
endif
if snrDb < 30
    @siaWarn: "Low spectral dynamic range: strongest peak only " + fixed$(snrDb, 1) + " dB above the median noise floor; weak partials may be missing or noise peaks accepted."
endif
if nEdge > 0
    @siaWarn: string$(nEdge) + " peak(s) could not be parabolically interpolated (edge or flat top) and were kept at the bin centre."
endif
if pitchSpread <> undefined and pitchSpread > 20 and analysis_mode <> 3
    @siaWarn: "Pitch is not stable over the interval (Praat pitch 10-90% spread " + fixed$(pitchSpread, 0) + " cents): partials are averaged over a changing frequency; choose a shorter, steadier interval."
endif
if analysis_mode = 1
    if fundamental = 1 and voicedFrac < 0.5
        @siaWarn: "Praat pitch found voicing in only " + fixed$(100 * voicedFrac, 0) + "% of frames; the fundamental relies on spectral evidence."
    endif
    if f1ref < 4 * lobeHz
        @siaWarn: "f1 (" + fixed$(f1ref, 1) + " Hz) is less than 4 main-lobe widths (" + fixed$(4 * lobeHz, 1) + " Hz): neighbouring partials may not be resolved. Use a longer interval or the Hann window."
    endif
    nAboveNyq = 0
    missing$ = ""
    nMissing = 0
    for n to nMaxAll
        if parStat$[n] = "above Nyquist"
            nAboveNyq = nAboveNyq + 1
        elsif parStat$[n] = "not detected" or parStat$[n] = "below analysis range"
            nMissing = nMissing + 1
            missing$ = missing$ + " " + string$(n)
        endif
    endfor
    if nAboveNyq > 0
        @siaWarn: string$(nAboveNyq) + " partial(s) lie above " + fixed$(fHigh, 0) + " Hz (98% of Nyquist) and cannot be measured."
    endif
    if nMissing > 0
        @siaWarn: "Not detected (no peak in the search window):" + missing$ + "."
    endif
    if nRejected > 0
        @siaWarn: string$(nRejected) + " measured partial(s) excluded from the B fit as outliers (see in_fit)."
    endif
    if nUnassigned > 0
        @siaFmt: strongestUnassigned, 0
        strongestU$ = siaFmt.out$
        @siaWarn: string$(nUnassigned) + " significant peak(s) below the highest assigned partial are not on the harmonic series (" + fixed$(100 * unassignedShare, 1) + "% of the peak power; strongest " + strongestU$ + " dB):" + unassigned$ + if nUnassigned > 8 then " ..." else "" fi + ". On a real string these can be phantom/longitudinal partials, sympathetic strings or noise."
    endif
    if fundamental = 2 and parF[1] <> undefined
        if abs(1200 * log2(parF[1] / manualF)) > 50
            @siaWarn: "Manual f1 (" + fixed$(manualF, 2) + " Hz) differs from the measured first partial (" + fixed$(parF[1], 2) + " Hz) by more than 50 cents; deviations are relative to the manual value."
        endif
    endif
    if fundamental = 1 and praatF0 <> undefined and f1ref <> undefined
        if abs(1200 * log2(praatF0 / f1ref)) > 50
            @siaWarn: "Praat pitch (" + fixed$(praatF0, 1) + " Hz) and the reference f1 (" + fixed$(f1ref, 1) + " Hz) differ by more than 50 cents - check the fundamental."
        endif
    endif
elsif analysis_mode = 2
    @siaWarn: "General mode: no harmonic numbers are assumed and no string coefficient B is computed."
    if lowestMissing
        @siaWarn: "The lowest significant peak (" + fixed$(pkF[1], 2) + " Hz, " + fixed$(pkA[1], 1) + " dB) is not among the " + string$(nG) + " strongest; it is kept as the reference and listed in place of the weakest peak."
    endif
    if nPk > nG
        @siaWarn: string$(nPk - nG) + " further significant peak(s) not listed (Maximum_partials = " + string$(maximum_partials) + ")."
    endif
endif
if analysis_mode = 3
    if noiseLike and fundamental = 1
        @siaWarn: "Noise-like spectrum: the strongest peak is only " + fixed$(snrDb, 1) + " dB above the median floor (25 dB needed), so no automatic bell identification is attempted."
    elsif bellOK = 0
        @siaWarn: "No consistent bell modal pattern (Hum-Prime-Tierce-Quint-Nominal) was found: no modes are named. The strongest components (up to 8) are tracked unnamed. Set the Nominal manually if the bell is known."
    endif
    if harmonicSpec and bellOK
        @siaWarn: "DOUBTFUL BELL PATTERN: " + string$(nOnGrid) + " of " + string$(nStrong) + " strong peaks lie on integer multiples of " + fixed$(fBase, 1) + " Hz - this is a harmonic spectrum, which matches Hum/Prime/Quint/Nominal as harmonics 1-4 without being a bell."
    endif
    if bellAmbig
        @siaWarn: "Ambiguous Nominal: an alternative at " + fixed$(altNominal, 1) + " Hz scores " + fixed$(100 * altShare, 0) + "% of the chosen one. Check with Fundamental = Manual frequency entry."
    endif
    if bellOK
        miss$ = ""
        unc$ = ""
        for m to 5
            if bmF[m] = undefined
                miss$ = miss$ + " " + bmName$[m]
            elsif left$(bmStat$[m], 9) = "uncertain"
                unc$ = unc$ + " " + bmName$[m]
            endif
        endfor
        if miss$ <> ""
            @siaWarn: "Not detected (no peak within the mode tolerance; not replaced by an ideal value):" + miss$ + "."
        endif
        if unc$ <> ""
            @siaWarn: "Uncertain identification (weak peak or near the edge of the tolerance):" + unc$ + "."
        endif
        if bmF[1] <> undefined
            if pkF[1] < 0.97 * bmF[1]
                @siaWarn: "The lowest detected component (" + fixed$(pkF[1], 1) + " Hz) lies below the Hum: lowest component and Hum are not the same."
            endif
        endif
    endif
    if winRaised
        @siaWarn: "Tracking window raised from " + fixed$(trackWin, 3) + " to " + fixed$(trackWinEff, 3) + " s so that partials " + fixed$(dMin, 1) + " Hz apart are separated."
    endif
    if winCapped
        @siaWarn: "Tracking window limited to " + fixed$(trackWinEff, 3) + " s (min(1 s, interval/6)): two characteristic modes only " + fixed$(dMin, 2) + " Hz apart may leak into each other's tracks."
    endif
    if tStrike - t1 < 0.02
        @siaWarn: "The strike lies within 20 ms of the interval start: the attack may be cut - start the interval a little earlier."
    endif
    for k to nTr
        if trBeat[k] <> undefined
            inDbl = 0
            for d to nDbl
                if trPk[k] = dbA[d] or trPk[k] = dbB[d]
                    inDbl = 1
                endif
            endfor
            if inDbl = 0
                @siaWarn: "The " + trName$[k] + " trajectory beats at about " + fixed$(trBeat[k], 1) + " Hz without a resolved spectral pair: possible unresolved doublet (uncertain)."
            endif
        endif
    endfor
    for d to nDbl
        if left$(dbStat$[d], 8) <> "confirme"
            @siaWarn: "Frequency pair " + fixed$(pkF[dbA[d]], 2) + " / " + fixed$(pkF[dbB[d]], 2) + " Hz is resolved in the spectrum but is NOT confirmed as a modal doublet (" + mid$(dbStat$[d], 15, length(dbStat$[d]) - 14) + ")."
        endif
    endfor
    @siaWarn: "Strike pitch is a perceptual (virtual) pitch and is NOT measured here; the Nominal is a measured partial, not the strike pitch."
    @siaWarn: "Modal frequencies come from one spectrum over " + fixed$(durT, 3) + " s; levels and decays come from the time-resolved tracks."
else
    @siaWarn: "A single interval is analysed: decaying, beating or gliding partials are averaged over " + fixed$(durT, 3) + " s."
endif

# display precision follows the resolution (no false precision)
hzDec = max(1, min(3, ceiling(log10(durT * 100))))

# ============================================================
# RESULT TABLES
# ============================================================
if analysis_mode = 1
    partTab = Create Table with column names: "SIA_partials_" + safeName$, nMaxAll,
        ... "partial status theoretical_hz measured_hz ratio deviation_hz deviation_cents amplitude_db model_hz residual_hz residual_cents in_fit model_status"
    for n to nMaxAll
        Set numeric value: n, "partial", n
        Set string value: n, "status", replace$(parStat$[n], " ", "_", 0)
        Set numeric value: n, "theoretical_hz", round(parTheo[n] * 10 ^ hzDec) / 10 ^ hzDec
        if parF[n] <> undefined
            Set numeric value: n, "measured_hz", round(parF[n] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: n, "ratio", round(parF[n] / f1ref * 1e5) / 1e5
            Set numeric value: n, "deviation_hz", round(parDevHz[n] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: n, "deviation_cents", round(parDevC[n] * 100) / 100
            Set numeric value: n, "amplitude_db", round(parA[n] * 10) / 10
            Set numeric value: n, "in_fit", parFit[n]
        else
            Set string value: n, "measured_hz", "NA"
            Set string value: n, "ratio", "NA"
            Set string value: n, "deviation_hz", "NA"
            Set string value: n, "deviation_cents", "NA"
            Set string value: n, "amplitude_db", "NA"
            Set numeric value: n, "in_fit", 0
        endif
        if parModel[n] <> undefined
            Set numeric value: n, "model_hz", round(parModel[n] * 10 ^ hzDec) / 10 ^ hzDec
        else
            Set string value: n, "model_hz", "NA"
        endif
        Set string value: n, "model_status", modelStatus$
        if parResHz[n] <> undefined
            Set numeric value: n, "residual_hz", round(parResHz[n] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: n, "residual_cents", round(parResC[n] * 100) / 100
        else
            Set string value: n, "residual_hz", "NA"
            Set string value: n, "residual_cents", "NA"
        endif
    endfor
elsif analysis_mode = 2
    partTab = Create Table with column names: "SIA_peaks_" + safeName$, nG,
        ... "peak measured_hz ratio nearest_integer integer_multiple_hz deviation_hz deviation_cents amplitude_db"
    for g to nG
        Set numeric value: g, "peak", g
        Set numeric value: g, "measured_hz", round(gF[g] * 10 ^ hzDec) / 10 ^ hzDec
        Set numeric value: g, "ratio", round(gRatio[g] * 1e5) / 1e5
        Set numeric value: g, "nearest_integer", gK[g]
        Set numeric value: g, "integer_multiple_hz", round(gMult[g] * 10 ^ hzDec) / 10 ^ hzDec
        Set numeric value: g, "deviation_hz", round(gDevHz[g] * 10 ^ hzDec) / 10 ^ hzDec
        Set numeric value: g, "deviation_cents", round(gDevC[g] * 100) / 100
        Set numeric value: g, "amplitude_db", round(gA[g] * 10) / 10
    endfor
endif

if analysis_mode = 3
    nRowsB = 5 + nOth
    partTab = Create Table with column names: "SIA_bell_modes_" + safeName$, nRowsB,
        ... "partial type measured_hz ideal_ratio ratio_to_nominal ratio_to_reference ideal_hz deviation_hz deviation_cents amplitude_db interval_re_reference confidence status"
    for m to 5
        Set string value: m, "partial", bmName$[m]
        Set string value: m, "type", "characteristic mode"
        Set numeric value: m, "ideal_ratio", bmR[m]
        if bmIdeal[m] <> undefined
            Set numeric value: m, "ideal_hz", round(bmIdeal[m] * 10 ^ hzDec) / 10 ^ hzDec
        else
            Set string value: m, "ideal_hz", "NA"
        endif
        if bmF[m] <> undefined
            Set numeric value: m, "measured_hz", round(bmF[m] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: m, "ratio_to_nominal", round(bmRatio[m] * 1e5) / 1e5
            Set numeric value: m, "ratio_to_reference", round(bmRatio[m] * 1e5) / 1e5
            Set numeric value: m, "deviation_hz", round(bmDevHz[m] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: m, "deviation_cents", round(bmDevC[m] * 100) / 100
            Set numeric value: m, "amplitude_db", round(bmA[m] * 10) / 10
            @siaInterval: bmRatio[m]
            Set string value: m, "interval_re_reference", replace$(siaInterval.out$, " ", "_", 0)
            Set numeric value: m, "confidence", round(bmConf[m] * 100) / 100
        else
            for cI to 7
                col$ = if cI = 1 then "measured_hz" else if cI = 2 then "ratio_to_nominal" else if cI = 3 then "deviation_hz" else if cI = 4 then "deviation_cents" else if cI = 5 then "amplitude_db" else if cI = 6 then "ratio_to_reference" else "confidence" fi fi fi fi fi fi
                Set string value: m, col$, "NA"
            endfor
            Set string value: m, "interval_re_reference", "NA"
        endif
        Set string value: m, "status", replace$(bmStat$[m], " ", "_", 0)
    endfor
    for a to nOth
        r = 5 + a
        i = othI[a]
        Set string value: r, "partial", "component_" + string$(a)
        Set string value: r, "type", replace$(othType$[a], " ", "_", 0)
        Set numeric value: r, "measured_hz", round(pkF[i] * 10 ^ hzDec) / 10 ^ hzDec
        Set string value: r, "ideal_ratio", "NA"
        Set string value: r, "ideal_hz", "NA"
        Set string value: r, "deviation_hz", "NA"
        Set string value: r, "deviation_cents", "NA"
        if bellOK
            Set numeric value: r, "ratio_to_nominal", round(pkF[i] / fN * 1e5) / 1e5
        else
            Set string value: r, "ratio_to_nominal", "NA"
        endif
        Set numeric value: r, "ratio_to_reference", round(pkF[i] / fRefB * 1e5) / 1e5
        Set numeric value: r, "amplitude_db", round(pkA[i] * 10) / 10
        @siaInterval: pkF[i] / fRefB
        Set string value: r, "interval_re_reference", replace$(siaInterval.out$, " ", "_", 0)
        Set string value: r, "confidence", "NA"
        Set string value: r, "status", "measured"
    endfor
    decayTab = Create Table with column names: "SIA_bell_decay_" + safeName$, nTr,
        ... "partial frequency_hz fitted_level_at_strike_db measured_level_db measured_level_time_s measured_peak_db measured_peak_time_s alpha_per_s decay_db_per_s t60_s r2 rms_residual_db fit_from_s fit_to_s decay_range_db beating_hz status"
    for k to nTr
        Set string value: k, "partial", replace$(trName$[k], " ", "_", 0)
        Set numeric value: k, "frequency_hz", round(trF[k] * 10 ^ hzDec) / 10 ^ hzDec
        for cI to 9
            if cI = 1
                col$ = "fitted_level_at_strike_db"
                v = trA0[k]
                dd = 1
            elsif cI = 2
                col$ = "alpha_per_s"
                v = trAlpha[k]
                dd = 3
            elsif cI = 3
                col$ = "decay_db_per_s"
                v = if trAlpha[k] = undefined then undefined else -trAlpha[k] * 20 / ln(10) fi
                dd = 2
            elsif cI = 4
                col$ = "t60_s"
                v = trT60[k]
                dd = 2
            elsif cI = 5
                col$ = "r2"
                v = trR2fit[k]
                dd = 3
            elsif cI = 6
                col$ = "rms_residual_db"
                v = trRms[k]
                dd = 2
            elsif cI = 7
                col$ = "decay_range_db"
                v = trRange[k]
                dd = 1
            elsif cI = 8
                col$ = "beating_hz"
                v = trBeat[k]
                dd = 1
            else
                col$ = "fit_to_s"
                v = if trStat$[k] = "" or left$(trStat$[k], 13) = "not estimated" then undefined else frT[trC2[k]] fi
                dd = 3
            endif
            if v = undefined
                Set string value: k, col$, "NA"
            else
                Set numeric value: k, col$, round(v * 10 ^ dd) / 10 ^ dd
            endif
        endfor
        if left$(trStat$[k], 13) = "not estimated"
            Set string value: k, "fit_from_s", "NA"
        else
            Set numeric value: k, "fit_from_s", round(frT[trC1[k]] * 1000) / 1000
        endif
        Set string value: k, "status", replace$(trStat$[k], " ", "_", 0)
        # v1.3: MEASURED levels (dB re strongest tracked level) next to the
        # fitted (extrapolated) level at the strike: the first fitted frame,
        # and the maximum after the strike (window-smeared attack)
        if left$(trStat$[k], 13) = "not estimated"
            Set string value: k, "measured_level_db", "NA"
            Set string value: k, "measured_level_time_s", "NA"
        else
            Set numeric value: k, "measured_level_db", round(trDb[k, trC1[k]] * 10) / 10
            Set numeric value: k, "measured_level_time_s", round(frT[trC1[k]] * 1000) / 1000
        endif
        cPk = cStrike
        for c from cStrike to nFr
            if trDb[k, c] > trDb[k, cPk]
                cPk = c
            endif
        endfor
        Set numeric value: k, "measured_peak_db", round(trDb[k, cPk] * 10) / 10
        Set numeric value: k, "measured_peak_time_s", round(frT[cPk] * 1000) / 1000
    endfor
    cols$ = "time_s floor_db"
    for k to nTr
        cols$ = cols$ + " " + trKey$[k] + "_db"
    endfor
    trackTab = Create Table with column names: "SIA_bell_tracks_" + safeName$, nFr, cols$
    for c to nFr
        Set numeric value: c, "time_s", round(frT[c] * 10000) / 10000
        Set numeric value: c, "floor_db", round(floorDb[c] * 100) / 100
        for k to nTr
            Set numeric value: c, trKey$[k] + "_db", round(trDb[k, c] * 100) / 100
        endfor
    endfor
    dblTab = 0
    if nDbl > 0
        dblTab = Create Table with column names: "SIA_bell_doublets_" + safeName$, nDbl, "f_a_hz f_b_hz difference_hz expected_beat_hz measured_beat_hz amplitude_a_db amplitude_b_db status"
        for d to nDbl
            Set numeric value: d, "f_a_hz", round(pkF[dbA[d]] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: d, "f_b_hz", round(pkF[dbB[d]] * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: d, "difference_hz", round((pkF[dbB[d]] - pkF[dbA[d]]) * 10 ^ hzDec) / 10 ^ hzDec
            Set numeric value: d, "expected_beat_hz", round((pkF[dbB[d]] - pkF[dbA[d]]) * 10 ^ hzDec) / 10 ^ hzDec
            if dbBeat[d] = undefined
                Set string value: d, "measured_beat_hz", "NA"
            else
                Set numeric value: d, "measured_beat_hz", round(dbBeat[d] * 1000) / 1000
            endif
            Set numeric value: d, "amplitude_a_db", round(pkA[dbA[d]] * 10) / 10
            Set numeric value: d, "amplitude_b_db", round(pkA[dbB[d]] * 10) / 10
            Set string value: d, "status", replace$(dbStat$[d], " ", "_", 0)
        endfor
    endif
endif

sumTab = Create Table with column names: "SIA_summary_" + safeName$, 0, "key value"
procedure siaKV: .k$, .v$
    selectObject: sumTab
    Append row
    .r = Get number of rows
    Set string value: .r, "key", .k$
    Set string value: .r, "value", .v$
endproc
@siaKV: "sound", name$
@siaKV: "mode", modeKey$
@siaKV: "interval_start_s", fixed$(t1, 4)
@siaKV: "interval_end_s", fixed$(t2, 4)
@siaKV: "sampling_hz", string$(sr)
@siaKV: "window", winName$
@siaKV: "fft_points", string$(nFft)
@siaKV: "bin_width_hz", fixed$(df, 5)
@siaKV: "resolution_hz", fixed$(resHz, 4)
@siaKV: "peaks_detected", string$(nPk)
@siaKV: "praat_pitch_hz", if praatF0 = undefined then "NA" else fixed$(praatF0, 3) fi
if analysis_mode = 1
    @siaKV: "spectral_f0_hz", if specF0 = undefined then "NA" else fixed$(specF0, 3) fi
    @siaKV: "first_partial_hz", if parF[1] = undefined then "NA" else fixed$(parF[1], 4) fi
    @siaKV: "reference_f1_hz", fixed$(f1ref, 4)
    @siaKV: "reference_source", refSource$
    @siaKV: "partials_measured", string$(nMeas)
    @siaKV: "partials_in_fit", string$(if fitOK then fitM else 0 fi)
    @siaKV: "B", if fitOK then fixed$(bCoef, 10) else "NA" fi
    @siaKV: "B_se", if fitOK then fixed$(seB, 10) else "NA" fi
    @siaKV: "F0_unstretched_hz", if fitOK then fixed$(f0u, 4) else "NA" fi
    @siaKV: "f1_model_hz", if fitOK then fixed$(f1model, 4) else "NA" fi
    @siaKV: "rmse_hz", if fitOK then fixed$(rmseHz, 5) else "NA" fi
    @siaKV: "rmse_cents", if fitOK then fixed$(rmseC, 4) else "NA" fi
    @siaKV: "B_verdict", bVerdict$
    @siaKV: "B_reliable", modelStatus$
    @siaKV: "unassigned_peaks", string$(nUnassigned)
    @siaKV: "unassigned_power_share", fixed$(unassignedShare, 4)
elsif analysis_mode = 2
    @siaKV: "reference_hz", fixed$(fRef, 4)
    @siaKV: "reference_source", refSource$
    @siaKV: "peaks_listed", string$(nG)
    @siaKV: "B", "not computed (general mode)"
elsif analysis_mode = 3
    @siaKV: "bell_pattern", if bellOK = 0 then "none" else if harmonicSpec then "doubtful (harmonic spectrum)" else "identified" fi fi
    @siaKV: "nominal_hz", if bellOK = 0 then "NA" else fixed$(fN, 4) fi
    @siaKV: "nominal_source", if bellOK = 0 then "NA" else nomSource$ fi
    @siaKV: "nominal_ambiguous", if bellAmbig then "yes" else "no" fi
    @siaKV: "modes_found", string$(if bellOK then nModesFound else 0 fi)
    for m to 5
        @siaKV: replace_regex$(bmName$[m], "([A-Z])", "\L\1", 0) + "_hz", if bmF[m] = undefined then "NA" else fixed$(bmF[m], 4) fi
        @siaKV: replace_regex$(bmName$[m], "([A-Z])", "\L\1", 0) + "_cents", if bmDevC[m] = undefined then "NA" else fixed$(bmDevC[m], 3) fi
    endfor
    @siaKV: "lowest_component_hz", fixed$(pkF[1], 4)
    @siaKV: "ratio_reference_hz", fixed$(fRefB, 4)
    @siaKV: "ratio_reference", refBName$
    @siaKV: "strike_pitch", "not measured (perceptual)"
    @siaKV: "strike_time_s", fixed$(tStrike, 4)
    @siaKV: "tracking_window_s", fixed$(trackWinEff, 4)
    @siaKV: "tracking_step_s", fixed$(dxT, 4)
    @siaKV: "tracked_partials", string$(nTr)
    @siaKV: "doublets", string$(nDbl)
    @siaKV: "B", "not computed (bell mode)"
endif
@siaKV: "warnings", string$(nWarn)

# ============================================================
# INFO REPORT
# ============================================================
if pass = 1
    clearinfo
    writeInfoLine: "=== Spectral Inharmonicity Analyzer v1.3 ==="
    infoStart = 0
else
    appendInfoLine: ""
    infoStart = length(info$ ())
    appendInfoLine: "=== Spectral Inharmonicity Analyzer v1.3 - analysis of the synthesised result ==="
endif
appendInfoLine: "Sound: ", name$, " | ", nCh, " ch (", if nCh = 1 then "mono" else if monoChannel > 0 then "channel " + string$(monoChannel) + " only - channels cancel in a mix" else "mixed to mono" fi fi, ") | ", sr, " Hz"
appendInfoLine: "Interval: ", fixed$(t1, 3), " - ", fixed$(t2, 3), " s (", fixed$(durT, 3), " s, ", nSamp, " samples)"
appendInfoLine: "FFT: ", winName$, " window | ", nFft, " points (zero padding ", padFactor, "x) | bin width ", fixed$(df, 4),
    ... " Hz | resolution 1/T = ", fixed$(resHz, 3), " Hz, main-lobe half-width ", fixed$(lobeHz, 2), " Hz"
appendInfoLine: "Peaks: ", nPk, " above ", fixed$(peak_threshold_dB, 0), " dB (prominence >= ", minProminence, " dB) | median noise floor ",
    ... fixed$(noiseDb - maxDb, 1), " dB re strongest peak"
appendInfoLine: "Mode: ", modeLabel$
appendInfoLine: ""
if analysis_mode = 1
    @siaFmt: pitchSpread, 1
    spread$ = siaFmt.out$
    appendInfoLine: "--- fundamental and reference ---"
    appendInfoLine: "Praat pitch (ac, median):     ", if praatF0 = undefined then "none (unvoiced)" else fixed$(praatF0, 2) + " Hz" fi,
        ... if pitchSpread = undefined then "" else " (10-90% spread " + spread$ + " cents)" fi
    if fundamental = 1
        appendInfoLine: "Spectral estimate:            ", fixed$(specF0, 2), " Hz  -> seed from ", f0Source$
    endif
    appendInfoLine: "First measured partial:       ", if parF[1] = undefined then "not detected" else fixed$(parF[1], hzDec) + " Hz" fi
    appendInfoLine: "Reference f1 (calculations):  ", fixed$(f1ref, hzDec), " Hz  (", refSource$, ")"
    appendInfoLine: ""
    appendInfoLine: "--- stiff-string model  f_n = n F0 sqrt(1 + B n^2) ---"
    if fitOK
        @siaSci: bCoef, 3
        b$ = siaSci.out$
        @siaSci: seB, 2
        appendInfoLine: "B = ", b$, "  (standard error ", siaSci.out$, ")"
        appendInfoLine: "F0 (unstretched) = ", fixed$(f0u, hzDec), " Hz | model f1 = F0 sqrt(1+B) = ", fixed$(f1model, hzDec), " Hz"
        @siaFmt: rmseHz, hzDec
        rmseHz$ = siaFmt.out$
        @siaFmt: rmseC, 3
        appendInfoLine: "Partials in fit: ", fitM, " of ", nMeas, " measured | RMSE ", rmseHz$, " Hz = ", siaFmt.out$, " cents"
    endif
    appendInfoLine: "Verdict: ", bVerdict$
    appendInfoLine: ""
    appendInfoLine: "--- partials (deviation = measured - n * f1; cents = 1200 log2(measured / (n f1))) ---"
    @siaPad: "n", 3
    h$ = siaPad.out$
    @siaPad: "ideal Hz", 11
    h$ = h$ + siaPad.out$
    @siaPad: "measured Hz", 13
    h$ = h$ + siaPad.out$
    @siaPad: "dev Hz", 10
    h$ = h$ + siaPad.out$
    @siaPad: "dev cents", 11
    h$ = h$ + siaPad.out$
    @siaPad: "ampl dB", 9
    h$ = h$ + siaPad.out$
    @siaPad: "model Hz", 12
    h$ = h$ + siaPad.out$
    @siaPad: "resid c", 9
    appendInfoLine: h$, siaPad.out$, "  status"
    for n to nMaxAll
        @siaPad: string$(n), 3
        l$ = siaPad.out$
        @siaFmt: parTheo[n], hzDec
        @siaPad: siaFmt.out$, 11
        l$ = l$ + siaPad.out$
        @siaFmt: parF[n], hzDec
        @siaPad: siaFmt.out$, 13
        l$ = l$ + siaPad.out$
        @siaFmt: parDevHz[n], hzDec
        @siaPad: siaFmt.out$, 10
        l$ = l$ + siaPad.out$
        @siaFmt: parDevC[n], 2
        @siaPad: siaFmt.out$, 11
        l$ = l$ + siaPad.out$
        @siaFmt: parA[n], 1
        @siaPad: siaFmt.out$, 9
        l$ = l$ + siaPad.out$
        @siaFmt: parModel[n], hzDec
        @siaPad: siaFmt.out$, 12
        l$ = l$ + siaPad.out$
        @siaFmt: parResC[n], 2
        @siaPad: siaFmt.out$, 9
        l$ = l$ + siaPad.out$
        st$ = parStat$[n]
        if parStat$[n] = "measured" and parFit[n] = 0 and fitOK
            st$ = "measured (excluded from fit)"
        endif
        appendInfoLine: l$, "  ", st$
    endfor
elsif analysis_mode = 2
    appendInfoLine: "--- reference ---"
    appendInfoLine: "Reference frequency: ", fixed$(fRef, hzDec), " Hz (", refSource$, ")"
    appendInfoLine: "Praat pitch (ac, median, for information only): ", if praatF0 = undefined then "none" else fixed$(praatF0, 2) + " Hz" fi
    appendInfoLine: ""
    appendInfoLine: "--- peaks (ratio = f / f_ref; k = nearest integer >= 1; deviation = f - k f_ref; cents = 1200 log2(f / (k f_ref))) ---"
    @siaPad: "#", 3
    h$ = siaPad.out$
    @siaPad: "measured Hz", 13
    h$ = h$ + siaPad.out$
    @siaPad: "ratio", 10
    h$ = h$ + siaPad.out$
    @siaPad: "k", 4
    h$ = h$ + siaPad.out$
    @siaPad: "k f_ref Hz", 12
    h$ = h$ + siaPad.out$
    @siaPad: "dev Hz", 10
    h$ = h$ + siaPad.out$
    @siaPad: "dev cents", 11
    h$ = h$ + siaPad.out$
    @siaPad: "ampl dB", 9
    appendInfoLine: h$, siaPad.out$
    for g to nG
        @siaPad: string$(g), 3
        l$ = siaPad.out$
        @siaFmt: gF[g], hzDec
        @siaPad: siaFmt.out$, 13
        l$ = l$ + siaPad.out$
        @siaFmt: gRatio[g], 4
        @siaPad: siaFmt.out$, 10
        l$ = l$ + siaPad.out$
        @siaPad: string$(gK[g]), 4
        l$ = l$ + siaPad.out$
        @siaFmt: gMult[g], hzDec
        @siaPad: siaFmt.out$, 12
        l$ = l$ + siaPad.out$
        @siaFmt: gDevHz[g], hzDec
        @siaPad: siaFmt.out$, 10
        l$ = l$ + siaPad.out$
        @siaFmt: gDevC[g], 2
        @siaPad: siaFmt.out$, 11
        l$ = l$ + siaPad.out$
        @siaFmt: gA[g], 1
        @siaPad: siaFmt.out$, 9
        appendInfoLine: l$, siaPad.out$
    endfor
endif
if analysis_mode = 3
    appendInfoLine: "--- bell reference quantities (deliberately kept apart) ---"
    appendInfoLine: "Lowest detected component:  ", fixed$(pkF[1], hzDec), " Hz (", fixed$(pkA[1], 1), " dB)"
    appendInfoLine: "Hum:                        ", if bmF[1] = undefined then "not detected" else fixed$(bmF[1], hzDec) + " Hz" fi
    appendInfoLine: "Prime:                      ", if bmF[2] = undefined then "not detected" else fixed$(bmF[2], hzDec) + " Hz" fi
    appendInfoLine: "Nominal (reference f_N):    ", if bellOK = 0 then "not identified" else fixed$(fN, hzDec) + " Hz (" + nomSource$ + ")" fi
    appendInfoLine: "Strike pitch:               not measured - a perceptual (virtual) pitch, not a spectral peak"
    if bellAmbig
        appendInfoLine: "Nominal is AMBIGUOUS: alternative ", fixed$(altNominal, hzDec), " Hz scores ", fixed$(100 * altShare, 0), "% of the chosen template score"
    endif
    appendInfoLine: ""
    appendInfoLine: "--- characteristic modes (ideal ratio r to Nominal; cents = 1200 log2(f / (r f_N))) ---"
    @siaPad: "mode", 8
    h$ = siaPad.out$
    @siaPad: "ideal r", 8
    h$ = h$ + siaPad.out$
    @siaPad: "ideal Hz", 11
    h$ = h$ + siaPad.out$
    @siaPad: "measured Hz", 13
    h$ = h$ + siaPad.out$
    @siaPad: "ratio", 8
    h$ = h$ + siaPad.out$
    @siaPad: "dev Hz", 9
    h$ = h$ + siaPad.out$
    @siaPad: "dev cents", 10
    h$ = h$ + siaPad.out$
    @siaPad: "ampl dB", 8
    h$ = h$ + siaPad.out$
    @siaPad: "conf", 6
    appendInfoLine: h$, siaPad.out$, "  status"
    for m to 5
        @siaPad: bmName$[m], 8
        l$ = siaPad.out$
        @siaFmt: bmR[m], 2
        @siaPad: siaFmt.out$, 8
        l$ = l$ + siaPad.out$
        @siaFmt: bmIdeal[m], hzDec
        @siaPad: siaFmt.out$, 11
        l$ = l$ + siaPad.out$
        @siaFmt: bmF[m], hzDec
        @siaPad: siaFmt.out$, 13
        l$ = l$ + siaPad.out$
        @siaFmt: bmRatio[m], 4
        @siaPad: siaFmt.out$, 8
        l$ = l$ + siaPad.out$
        @siaFmt: bmDevHz[m], hzDec
        @siaPad: siaFmt.out$, 9
        l$ = l$ + siaPad.out$
        @siaFmt: bmDevC[m], 1
        @siaPad: siaFmt.out$, 10
        l$ = l$ + siaPad.out$
        @siaFmt: bmA[m], 1
        @siaPad: siaFmt.out$, 8
        l$ = l$ + siaPad.out$
        @siaFmt: bmConf[m], 2
        @siaPad: siaFmt.out$, 6
        appendInfoLine: l$, siaPad.out$, "  ", bmStat$[m]
    endfor
    appendInfoLine: ""
    appendInfoLine: "--- other components (", nOth, " strongest of ", nOthAll, "; ratio and interval relative to the ", refBName$, ", ", fixed$(fRefB, hzDec), " Hz) ---"
    for a to nOth
        i = othI[a]
        @siaFmt: pkF[i], hzDec
        @siaPad: siaFmt.out$, 12
        l$ = siaPad.out$
        @siaFmt: pkF[i] / fRefB, 4
        @siaPad: siaFmt.out$, 9
        l$ = l$ + siaPad.out$
        @siaInterval: pkF[i] / fRefB
        @siaPad: siaInterval.out$, 14
        l$ = l$ + siaPad.out$
        @siaFmt: pkA[i], 1
        @siaPad: siaFmt.out$, 8
        appendInfoLine: l$, siaPad.out$, " dB  ", othType$[a]
    endfor
    appendInfoLine: ""
    appendInfoLine: "--- frequency pairs within 50 cents (beat = |fa - fb|); 'confirmed' = the band envelope beats at that rate ---"
    if nDbl = 0
        appendInfoLine: if detectDoublets then "none resolved (minimum resolvable spacing " + fixed$(2 * lobeHz, 2) + " Hz at this interval length)" else "doublet detection off" fi
    endif
    for d to nDbl
        appendInfoLine: fixed$(pkF[dbA[d]], hzDec), " / ", fixed$(pkF[dbB[d]], hzDec), " Hz | difference = expected beat ", fixed$(pkF[dbB[d]] - pkF[dbA[d]], 2),
            ... " Hz | ", fixed$(pkA[dbA[d]], 1), " / ", fixed$(pkA[dbB[d]], 1), " dB | ", dbStat$[d]
    endfor
    appendInfoLine: ""
    appendInfoLine: "--- temporal tracking and decay  A(t) = A0 exp(-alpha t), T60 = 6.908 / alpha ---"
    appendInfoLine: "Gaussian-window spectrogram: window ", fixed$(trackWinEff, 3), " s, step ", fixed$(dxT, 4), " s, ", nFr, " frames | strike at ",
        ... fixed$(tStrike, 3), " s; fits start ", fixed$(frT[cFit1], 3), " s (strike excluded)"
    appendInfoLine: "L0fit = level of the fit EXTRAPOLATED to the strike (model value, dB re the strongest tracked level); measured levels: decay table"
    @siaPad: "partial", 10
    h$ = siaPad.out$
    @siaPad: "Hz", 10
    h$ = h$ + siaPad.out$
    @siaPad: "L0fit dB", 9
    h$ = h$ + siaPad.out$
    @siaPad: "alpha 1/s", 10
    h$ = h$ + siaPad.out$
    @siaPad: "T60 s", 8
    h$ = h$ + siaPad.out$
    @siaPad: "range dB", 9
    h$ = h$ + siaPad.out$
    @siaPad: "R2", 7
    h$ = h$ + siaPad.out$
    @siaPad: "rms dB", 7
    appendInfoLine: h$, siaPad.out$, "  status"
    for k to nTr
        @siaPad: trName$[k], 10
        l$ = siaPad.out$
        @siaFmt: trF[k], 1
        @siaPad: siaFmt.out$, 10
        l$ = l$ + siaPad.out$
        @siaFmt: trA0[k], 1
        @siaPad: siaFmt.out$, 9
        l$ = l$ + siaPad.out$
        @siaFmt: trAlpha[k], 3
        @siaPad: siaFmt.out$, 10
        l$ = l$ + siaPad.out$
        @siaFmt: trT60[k], 2
        @siaPad: siaFmt.out$, 8
        l$ = l$ + siaPad.out$
        @siaFmt: trRange[k], 1
        @siaPad: siaFmt.out$, 9
        l$ = l$ + siaPad.out$
        @siaFmt: trR2fit[k], 3
        @siaPad: siaFmt.out$, 7
        l$ = l$ + siaPad.out$
        @siaFmt: trRms[k], 2
        @siaPad: siaFmt.out$, 7
        appendInfoLine: l$, siaPad.out$, "  ", trStat$[k]
    endfor
endif
appendInfoLine: ""
appendInfoLine: "--- warnings and reliability notes ---"
for w to nWarn
    appendInfoLine: "  - ", warn$[w]
endfor

# ============================================================
# PICTURE REPORT
# ============================================================
# Layout (inches): title 0.05-0.60 | spectrum 0.85-2.55 |
# graph A (left) + graph B (right) 3.10-4.90 | graph C 5.45-7.05 |
# summary 7.65-8.65; canvas 8 x 8.8.
procedure siaPartialAxisMarks: .nMax
    if .nMax <= 25
        .st = 1
    elsif .nMax <= 50
        .st = 2
    elsif .nMax <= 125
        .st = 5
    else
        .st = 10
    endif
    Marks bottom every: 1, .st, "yes", "yes", "no"
endproc

# Labelled marks with round values; values >= 10000 are written in
# thousands (the caller switches the unit to k... when .div = 1000).
procedure siaMarks: .side$, .lo, .hi, .target
    @siaStep: .hi - .lo, .target
    .st = siaStep.step
    .div = 1
    if max(abs(.lo), abs(.hi)) >= 10000
        .div = 1000
    endif
    .dec = max(0, ceiling(-log10(.st / .div) - 1e-9))
    for .v from ceiling(.lo / .st - 1e-9) to floor(.hi / .st + 1e-9)
        .val = .v * .st
        @siaFmt: .val / .div, .dec
        if .side$ = "left"
            One mark left: .val, "no", "yes", "no", siaFmt.out$
        else
            One mark bottom: .val, "no", "yes", "no", siaFmt.out$
        endif
    endfor
endproc

# y range of a set of values stored in vals[1..nVals] (undefined skipped)
procedure siaRange: .nVals, .includeZero
    .lo = undefined
    .hi = undefined
    for .i to .nVals
        if vals[.i] <> undefined
            if .lo = undefined
                .lo = vals[.i]
                .hi = vals[.i]
            else
                .lo = min(.lo, vals[.i])
                .hi = max(.hi, vals[.i])
            endif
        endif
    endfor
    if .lo = undefined
        .lo = -1
        .hi = 1
    endif
    if .includeZero
        .lo = min(.lo, 0)
        .hi = max(.hi, 0)
    endif
    .span = .hi - .lo
    if .span <= 0
        .span = max(1, abs(.hi))
    endif
    .lo = .lo - 0.12 * .span
    .hi = .hi + 0.22 * .span
endproc

if draw_report and analysis_mode <> 3
    canvasH = 8.8
    Erase all
    Line width: 1
    Solid line
    Colour: "Black"
    @siaSafe: name$
    safeTitle$ = siaSafe.out$
    Font size: 13
    Select inner viewport: 0, 8, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.72, "half", "##Spectral Inharmonicity Analyzer##"
    Font size: 7
    Select inner viewport: 0, 8, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.18, "half", safeTitle$ + "   |   " + fixed$(t1, 2) + "-" + fixed$(t2, 2) + " s   |   "
        ... + modeLabel$ + "   |   " + winName$ + ", resolution " + fixed$(resHz, 2) + " Hz"
    Colour: "Black"

    # ---------- spectrum ----------
    if analysis_mode = 1
        fShow = 0
        for n to nMaxAll
            if parF[n] <> undefined
                fShow = max(fShow, parF[n])
            endif
            if parStat$[n] <> "above Nyquist"
                fShow = max(fShow, parExp[n])
            endif
        endfor
    else
        fShow = gF[nG]
    endif
    fShow = min(nyq, fShow * 1.06 + 2 * lobeHz)
    yLo = maxDb + peak_threshold_dB - 10
    yHi = maxDb + 20
    sTop = 0.85
    sBot = 2.55
    Font size: 6
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, fShow, yLo, yHi
    Paint rectangle: "{0.985, 0.985, 0.99}", 0, fShow, yLo, yHi
    selectObject: mag
    Colour: "{0.40, 0.42, 0.50}"
    Draw: 0, fShow, yLo, yHi, "no", "Curve"
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, fShow, yLo, yHi
    Colour: "{0.55, 0.55, 0.60}"
    Line width: 1
    Dotted line
    Draw line: 0, thrDb, fShow, thrDb
    Solid line
    if analysis_mode = 1
        for n to nMaxAll
            if parTheo[n] <= fShow
                Colour: "{0.60, 0.60, 0.60}"
                Draw line: parTheo[n], yHi - 0.06 * (yHi - yLo), parTheo[n], yHi
            endif
        endfor
        for n to nMaxAll
            if parF[n] <> undefined
                Paint circle (mm): "{0.85, 0.30, 0.20}", parF[n], parA[n] + maxDb, 0.75
                if n <= 10 or n mod 5 = 0
                    Colour: "{0.70, 0.20, 0.15}"
                    Text: parF[n], "centre", min(yHi - 0.2 * (yHi - yLo), parA[n] + maxDb + 2.5), "bottom", string$(n)
                endif
            endif
        endfor
    else
        for g to nG
            Paint circle (mm): "{0.85, 0.30, 0.20}", gF[g], gA[g] + maxDb, 0.75
            if g <= 14
                Colour: "{0.70, 0.20, 0.15}"
                Text: gF[g], "centre", min(yHi - 0.2 * (yHi - yLo), gA[g] + maxDb + 2.5), "bottom", fixed$(gRatio[g], 2)
            endif
        endfor
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, fShow, yLo, yHi
    Draw inner box
    @siaMarks: "bottom", 0, fShow, 10
    @siaStep: yHi - yLo, 4
    Marks left every: 1, siaStep.step, "yes", "yes", "no"
    Text bottom: "yes", if siaMarks.div = 1000 then "Frequency (kHz)" else "Frequency (Hz)" fi
    Font size: 6
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, 1, 0, 1
    Colour: "{0.85, 0.30, 0.20}"
    if analysis_mode = 1
        Text: 0.008, "left", 0.93, "half", "assigned partial (number = n)"
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.25, "left", 0.93, "half", "top ticks = ideal n f1;  dotted = threshold"
    else
        Text: 0.008, "left", 0.93, "half", "listed peak (label = ratio to reference)"
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.30, "left", 0.93, "half", "dotted = threshold"
    endif
    Colour: "Black"
    @siaPanelName: 0.6, 7.7, sTop, sBot, "Spectrum (dB)"

    # ---------- common x axis for A, B, C ----------
    if analysis_mode = 1
        nX = nMaxAll
    else
        nX = nG
    endif
    xLo = 0.4
    xHi = nX + 0.6

    # ---------- graph A ----------
    aTop = 3.10
    aBot = 4.90
    if analysis_mode = 1
        for n to nX
            vals[n] = max(parTheo[n], if parF[n] = undefined then 0 else parF[n] fi)
            if fitOK
                if parModel[n] <> undefined
                    vals[n] = max(vals[n], parModel[n])
                endif
            endif
        endfor
        vals[nX + 1] = 0
        @siaRange: nX + 1, 1
        ayLo = 0
        ayHi = siaRange.hi
    else
        for g to nX
            vals[g] = gRatio[g]
        endfor
        vals[nX + 1] = 0
        @siaRange: nX + 1, 1
        ayLo = 0
        ayHi = siaRange.hi
    endif
    Font size: 6
    Select inner viewport: 0.6, 3.95, aTop, aBot
    Axes: xLo, xHi, ayLo, ayHi
    Paint rectangle: "{0.985, 0.985, 0.99}", xLo, xHi, ayLo, ayHi
    if analysis_mode = 1
        Colour: "{0.60, 0.60, 0.60}"
        for n to nX - 1
            Draw line: n, parTheo[n], n + 1, parTheo[n + 1]
        endfor
        for n to nX
            Draw circle (mm): n, parTheo[n], 0.6
        endfor
        Colour: "{0.20, 0.40, 0.80}"
        for n to nX - 1
            if parF[n] <> undefined and parF[n + 1] <> undefined
                Draw line: n, parF[n], n + 1, parF[n + 1]
            endif
        endfor
        for n to nX
            if parF[n] <> undefined
                Paint circle (mm): "{0.20, 0.40, 0.80}", n, parF[n], 0.55
            endif
        endfor
        if fitOK
            Colour: "{0.90, 0.55, 0.10}"
            Dashed line
            for n to nX - 1
                if parModel[n] <> undefined and parModel[n + 1] <> undefined
                    Draw line: n, parModel[n], n + 1, parModel[n + 1]
                endif
            endfor
            Solid line
        endif
    else
        Colour: "{0.75, 0.75, 0.78}"
        Dotted line
        for k to floor(ayHi)
            Draw line: xLo, k, xHi, k
        endfor
        Solid line
        for g to nX
            Paint circle (mm): "{0.20, 0.40, 0.80}", g, gRatio[g], 0.6
        endfor
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 3.95, aTop, aBot
    Axes: xLo, xHi, ayLo, ayHi
    Draw inner box
    @siaPartialAxisMarks: nX
    @siaMarks: "left", ayLo, ayHi, 4
    Text bottom: "yes", if analysis_mode = 1 then "Partial number n" else "Peak number (ascending frequency)" fi
    Font size: 6
    Select inner viewport: 0.6, 3.95, aTop, aBot
    Axes: 0, 1, 0, 1
    if analysis_mode = 1
        Colour: "{0.20, 0.40, 0.80}"
        Text: 0.02, "left", 0.90, "half", "measured"
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.02, "left", 0.80, "half", "ideal n f1"
        if fitOK
            Colour: "{0.90, 0.55, 0.10}"
            Text: 0.02, "left", 0.70, "half", "string model (B fit)"
        endif
    else
        Colour: "{0.20, 0.40, 0.80}"
        Text: 0.02, "left", 0.90, "half", "ratio f / f_r_e_f"
        Colour: "{0.50, 0.50, 0.50}"
        Text: 0.02, "left", 0.80, "half", "dotted = integer ratios"
    endif
    Colour: "Black"
    @siaPanelName: 0.6, 3.95, aTop, aBot, if analysis_mode = 2 then "A  Ratio" else if siaMarks.div = 1000 then "A  Frequency (kHz)" else "A  Frequency (Hz)" fi fi

    # ---------- graph B: deviation in Hz ----------
    for i to nX
        if analysis_mode = 1
            vals[i] = parDevHz[i]
            if parModel[i] <> undefined
                vals[nX + i] = parModel[i] - parTheo[i]
            else
                vals[nX + i] = undefined
            endif
        else
            vals[i] = gDevHz[i]
            vals[nX + i] = undefined
        endif
    endfor
    @siaRange: 2 * nX, 1
    byLo = siaRange.lo
    byHi = siaRange.hi
    Font size: 6
    Select inner viewport: 4.35, 7.7, aTop, aBot
    Axes: xLo, xHi, byLo, byHi
    Paint rectangle: "{0.985, 0.985, 0.99}", xLo, xHi, byLo, byHi
    Colour: "{0.45, 0.45, 0.45}"
    Draw line: xLo, 0, xHi, 0
    if analysis_mode = 1
        Colour: "{0.20, 0.40, 0.80}"
        for n to nX - 1
            if parF[n] <> undefined and parF[n + 1] <> undefined
                Draw line: n, parDevHz[n], n + 1, parDevHz[n + 1]
            endif
        endfor
        for n to nX
            if parF[n] <> undefined
                Paint circle (mm): "{0.20, 0.40, 0.80}", n, parDevHz[n], 0.55
            else
                Colour: "{0.55, 0.55, 0.55}"
                Draw line: n, byLo, n, byLo + 0.06 * (byHi - byLo)
            endif
        endfor
        if fitOK
            Colour: "{0.90, 0.55, 0.10}"
            Dashed line
            for n to nX - 1
                if parModel[n] <> undefined and parModel[n + 1] <> undefined
                    Draw line: n, parModel[n] - parTheo[n], n + 1, parModel[n + 1] - parTheo[n + 1]
                endif
            endfor
            Solid line
        endif
    else
        Colour: "{0.20, 0.40, 0.80}"
        for g to nX
            Draw line: g, 0, g, gDevHz[g]
            Paint circle (mm): "{0.20, 0.40, 0.80}", g, gDevHz[g], 0.55
        endfor
    endif
    Colour: "Black"
    Select inner viewport: 4.35, 7.7, aTop, aBot
    Axes: xLo, xHi, byLo, byHi
    Draw inner box
    @siaPartialAxisMarks: nX
    @siaMarks: "left", byLo, byHi, 4
    Text bottom: "yes", if analysis_mode = 1 then "Partial number n" else "Peak number" fi
    Font size: 6
    Select inner viewport: 4.35, 7.7, aTop, aBot
    Axes: 0, 1, 0, 1
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.02, "left", 0.90, "half", if analysis_mode = 1 then "f_n - n f1 (grey tick = not detected)" else "f - k f_r_e_f, k = nearest integer" fi
    Colour: "Black"
    @siaPanelName: 4.35, 7.7, aTop, aBot, "B  Deviation (Hz)"

    # ---------- graph C: deviation in cents ----------
    cTop = 5.45
    cBot = 7.05
    for i to nX
        if analysis_mode = 1
            vals[i] = parDevC[i]
            if parModel[i] <> undefined
                vals[nX + i] = 1200 * log2(parModel[i] / parTheo[i])
            else
                vals[nX + i] = undefined
            endif
        else
            vals[i] = gDevC[i]
            vals[nX + i] = undefined
        endif
    endfor
    @siaRange: 2 * nX, 1
    cyLo = siaRange.lo
    cyHi = siaRange.hi
    Font size: 6
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: xLo, xHi, cyLo, cyHi
    Paint rectangle: "{0.985, 0.985, 0.99}", xLo, xHi, cyLo, cyHi
    Colour: "{0.45, 0.45, 0.45}"
    Draw line: xLo, 0, xHi, 0
    if analysis_mode = 1
        Colour: "{0.20, 0.40, 0.80}"
        for n to nX - 1
            if parF[n] <> undefined and parF[n + 1] <> undefined
                Draw line: n, parDevC[n], n + 1, parDevC[n + 1]
            endif
        endfor
        for n to nX
            if parF[n] <> undefined
                if parFit[n] = 0 and fitOK
                    Draw circle (mm): n, parDevC[n], 0.75
                endif
                Paint circle (mm): "{0.20, 0.40, 0.80}", n, parDevC[n], 0.55
            else
                Colour: "{0.55, 0.55, 0.55}"
                Draw line: n, cyLo, n, cyLo + 0.06 * (cyHi - cyLo)
                Colour: "{0.20, 0.40, 0.80}"
            endif
        endfor
        if fitOK
            Colour: "{0.90, 0.55, 0.10}"
            Dashed line
            for n to nX - 1
                if parModel[n] <> undefined and parModel[n + 1] <> undefined
                    Draw line: n, 1200 * log2(parModel[n] / parTheo[n]), n + 1, 1200 * log2(parModel[n + 1] / parTheo[n + 1])
                endif
            endfor
            Solid line
        endif
    else
        Colour: "{0.20, 0.40, 0.80}"
        for g to nX
            Draw line: g, 0, g, gDevC[g]
            Paint circle (mm): "{0.20, 0.40, 0.80}", g, gDevC[g], 0.55
        endfor
    endif
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: xLo, xHi, cyLo, cyHi
    Draw inner box
    @siaPartialAxisMarks: nX
    @siaMarks: "left", cyLo, cyHi, 4
    Text bottom: "yes", if analysis_mode = 1 then "Partial number n" else "Peak number" fi
    Font size: 6
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, 1, 0, 1
    if analysis_mode = 1
        Colour: "{0.20, 0.40, 0.80}"
        Text: 0.008, "left", 0.90, "half", "measured: 1200 log2(f_n / n f1)"
        if fitOK
            Colour: "{0.90, 0.55, 0.10}"
            Text: 0.22, "left", 0.90, "half", "model-predicted deviation (B fit)"
        endif
        Colour: "{0.45, 0.45, 0.50}"
        Text: 0.45, "left", 0.90, "half", "ringed = excluded from fit;  grey tick = not detected"
    else
        Colour: "{0.45, 0.45, 0.50}"
        Text: 0.008, "left", 0.90, "half", "1200 log2(f / k f_r_e_f): distance to the nearest integer multiple of the reference"
    endif
    Colour: "Black"
    @siaPanelName: 0.6, 7.7, cTop, cBot, "C  Deviation (cents)"

    # ---------- summary ----------
    Font size: 7
    Select inner viewport: 0.6, 7.7, 7.65, 8.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.6, 7.7, 7.65, 8.65
    Axes: 0, 1, 0, 1
    Draw inner box
    Select inner viewport: 0.6, 7.7, 7.65, 8.65
    Axes: 0, 1, 0, 1
    Colour: "Black"
    if analysis_mode = 1
        if fitOK
            @siaFmt: rmseHz, hzDec
            rmseHz$ = siaFmt.out$
            @siaFmt: rmseC, 3
            rmseC$ = siaFmt.out$
            @siaSci: bCoef, 3
            bTxt$ = "B = " + siaSci.out$
            @siaSci: seB, 2
            bTxt$ = bTxt$ + " +- " + siaSci.out$ + "   |   F0 " + fixed$(f0u, 2) + " Hz   |   RMSE " + rmseHz$ + " Hz (" + rmseC$ + " cents)   |   " + string$(fitM) + " partials in fit"
        else
            bTxt$ = "B not estimated"
        endif
        Text: 0.015, "left", 0.80, "half", "Reference f1 " + fixed$(f1ref, hzDec) + " Hz (" + refSource$ + ")   |   measured " + string$(nMeas) + " of " + string$(nMaxAll) + " partials   |   Praat pitch " + (if praatF0 = undefined then "none" else fixed$(praatF0, 1) + " Hz" fi)
        Text: 0.015, "left", 0.50, "half", bTxt$
        @siaSafe: bVerdict$
        Text: 0.015, "left", 0.20, "half", "Verdict: " + siaSafe.out$ + "   |   warnings " + string$(nWarn) + " (see Info)"
    else
        Text: 0.015, "left", 0.80, "half", "Reference " + fixed$(fRef, hzDec) + " Hz (" + refSource$ + ")   |   " + string$(nG) + " strongest of " + string$(nPk) + " significant peaks listed"
        Text: 0.015, "left", 0.50, "half", "No harmonic numbers assumed; the string coefficient B is not computed in this mode."
        Text: 0.015, "left", 0.20, "half", "Peak threshold " + fixed$(peak_threshold_dB, 0) + " dB   |   prominence >= " + string$(minProminence) + " dB   |   warnings " + string$(nWarn) + " (see Info)"
    endif
    Select outer viewport: 0, 8, 0, canvasH
    Font size: 10
endif


# ============================================================
# BELL PICTURE REPORT (Analysis_mode = 3)
# ============================================================
# Layout (inches): title 0.05-0.60 | spectrum 0.85-2.45 |
# A modal structure (left) + B tuning deviations (right) 2.95-4.55 |
# C modal decay 5.05-6.75 | D spectral evolution 7.25-8.95 |
# summary 9.55-10.55; canvas 8 x 10.7.
if draw_report and analysis_mode = 3
    canvasH = 10.7
    bCol$[1] = "{0.15, 0.25, 0.65}"
    bCol$[2] = "{0.10, 0.55, 0.30}"
    bCol$[3] = "{0.80, 0.20, 0.20}"
    bCol$[4] = "{0.85, 0.55, 0.05}"
    bCol$[5] = "{0.50, 0.20, 0.65}"
    pal$[1] = "{0.15, 0.25, 0.65}"
    pal$[2] = "{0.80, 0.20, 0.20}"
    pal$[3] = "{0.10, 0.55, 0.30}"
    pal$[4] = "{0.85, 0.55, 0.05}"
    pal$[5] = "{0.50, 0.20, 0.65}"
    pal$[6] = "{0.10, 0.60, 0.70}"
    pal$[7] = "{0.55, 0.35, 0.15}"
    pal$[8] = "{0.40, 0.40, 0.45}"
    nShowTr = 0
    for k to nTr
        trShow[k] = trMode[k] > 0 or (bellOK = 0 and nShowTr < 8)
        if trShow[k]
            nShowTr = nShowTr + 1
            trCol$[k] = if trMode[k] > 0 then bCol$[trMode[k]] else pal$[min(8, nShowTr)] fi
        endif
    endfor
    bAbbr$[1] = "H"
    bAbbr$[2] = "P"
    bAbbr$[3] = "T"
    bAbbr$[4] = "Q"
    bAbbr$[5] = "N"
    Erase all
    Line width: 1
    Solid line
    Colour: "Black"
    @siaSafe: name$
    safeTitle$ = siaSafe.out$
    Font size: 13
    Select inner viewport: 0, 8, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Text: 0.5, "centre", 0.72, "half", "##Spectral Inharmonicity Analyzer - Bell Analysis##"
    Font size: 7
    Select inner viewport: 0, 8, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.18, "half", safeTitle$ + "   |   " + fixed$(t1, 2) + "-" + fixed$(t2, 2) + " s   |   " + winName$ + ", resolution " + fixed$(resHz, 2)
        ... + " Hz   |   tracking window " + fixed$(trackWinEff, 3) + " s, step " + fixed$(dxT, 3) + " s"
    Colour: "Black"

    # ---------- spectrum ----------
    fShowB = 0
    for m to 5
        if bmF[m] <> undefined
            fShowB = max(fShowB, bmF[m])
        endif
    endfor
    for a to nOth
        fShowB = max(fShowB, pkF[othI[a]])
    endfor
    if bellOK
        fShowB = max(fShowB, fN)
    endif
    for k to nTr
        fShowB = max(fShowB, trF[k])
    endfor
    fShowB = min(nyq, fShowB * 1.06 + 2 * lobeHz)
    yLo = maxDb + peak_threshold_dB - 10
    yHi = maxDb + 25
    sTop = 0.85
    sBot = 2.45
    Font size: 6
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, fShowB, yLo, yHi
    Paint rectangle: "{0.985, 0.985, 0.99}", 0, fShowB, yLo, yHi
    selectObject: mag
    Colour: "{0.40, 0.42, 0.50}"
    Draw: 0, fShowB, yLo, yHi, "no", "Curve"
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, fShowB, yLo, yHi
    Colour: "{0.55, 0.55, 0.60}"
    Dotted line
    Draw line: 0, thrDb, fShowB, thrDb
    Solid line
    if bellOK
        for m to 5
            Colour: bCol$[m]
            Draw line: bmIdeal[m], yHi - 0.07 * (yHi - yLo), bmIdeal[m], yHi
        endfor
    endif
    for a to nOth
        Paint circle (mm): "{0.55, 0.55, 0.60}", pkF[othI[a]], pkA[othI[a]] + maxDb, 0.5
    endfor
    for m to 5
        if bmF[m] <> undefined
            Paint circle (mm): bCol$[m], bmF[m], bmA[m] + maxDb, 0.8
            Colour: bCol$[m]
            Text: bmF[m], "centre", min(yHi - 0.27 * (yHi - yLo), bmA[m] + maxDb + 2.5), "bottom", bAbbr$[m]
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, fShowB, yLo, yHi
    Draw inner box
    @siaMarks: "bottom", 0, fShowB, 10
    @siaStep: yHi - yLo, 4
    Marks left every: 1, siaStep.step, "yes", "yes", "no"
    Text bottom: "yes", if siaMarks.div = 1000 then "Frequency (kHz)" else "Frequency (Hz)" fi
    Font size: 6
    Select inner viewport: 0.6, 7.7, sTop, sBot
    Axes: 0, 1, 0, 1
    for m to 5
        Colour: bCol$[m]
        Text: 0.008 + 0.075 * (m - 1), "left", 0.85, "half", bAbbr$[m] + " = " + bmName$[m]
    endfor
    Colour: "{0.50, 0.50, 0.50}"
    Text: 0.40, "left", 0.85, "half", "grey dots = other components;  top ticks = ideal r f_N;  dotted = threshold"
    Colour: "Black"
    @siaPanelName: 0.6, 7.7, sTop, sBot, "Spectrum (dB)"

    # ---------- A: modal frequency structure ----------
    aTop = 2.95
    aBot = 4.55
    Font size: 6
    Select inner viewport: 0.6, 3.95, aTop, aBot
    Axes: 0.4, 5.6, 0, 1.2
    Paint rectangle: "{0.985, 0.985, 0.99}", 0.4, 5.6, 0, 1.2
    Colour: "{0.75, 0.75, 0.78}"
    Dotted line
    for m to 5
        Draw line: 0.4, bmR[m], 5.6, bmR[m]
    endfor
    Solid line
    for m to 5
        Colour: "{0.45, 0.45, 0.45}"
        Draw circle (mm): m, bmR[m], 1.0
        if bmRatio[m] <> undefined
            Paint circle (mm): bCol$[m], m, bmRatio[m], 0.75
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 3.95, aTop, aBot
    Axes: 0.4, 5.6, 0, 1.2
    Draw inner box
    for m to 5
        One mark bottom: m, "no", "yes", "no", bmName$[m]
    endfor
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Text bottom: "yes", "Characteristic mode"
    Font size: 6
    Select inner viewport: 0.6, 3.95, aTop, aBot
    Axes: 0, 1, 0, 1
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.03, "left", 0.92, "half", "open = ideal ratio,  filled = measured f / f_N"
    Colour: "Black"
    @siaPanelName: 0.6, 3.95, aTop, aBot, "A  Ratio to Nominal"

    # ---------- B: tuning deviations ----------
    for m to 5
        vals[m] = bmDevC[m]
    endfor
    vals[6] = 20
    vals[7] = -20
    @siaRange: 7, 1
    byLo = siaRange.lo
    byHi = siaRange.hi
    Font size: 6
    Select inner viewport: 4.35, 7.7, aTop, aBot
    Axes: 0.4, 5.6, byLo, byHi
    Paint rectangle: "{0.985, 0.985, 0.99}", 0.4, 5.6, byLo, byHi
    Colour: "{0.45, 0.45, 0.45}"
    Draw line: 0.4, 0, 5.6, 0
    for m to 5
        if bmDevC[m] <> undefined
            Colour: bCol$[m]
            Line width: 2
            Draw line: m, 0, m, bmDevC[m]
            Line width: 1
            Paint circle (mm): bCol$[m], m, bmDevC[m], 0.8
        else
            Colour: "{0.55, 0.55, 0.55}"
            Text: m, "centre", 0, "bottom", "n.d."
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 4.35, 7.7, aTop, aBot
    Axes: 0.4, 5.6, byLo, byHi
    Draw inner box
    for m to 5
        One mark bottom: m, "no", "yes", "no", bmName$[m]
    endfor
    @siaMarks: "left", byLo, byHi, 4
    Text bottom: "yes", "Characteristic mode"
    Font size: 6
    Select inner viewport: 4.35, 7.7, aTop, aBot
    Axes: 0, 1, 0, 1
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.03, "left", 0.92, "half", "1200 log2(f / r f_N);  n.d. = not detected"
    Colour: "Black"
    @siaPanelName: 4.35, 7.7, aTop, aBot, "B  Deviation (cents)"

    # ---------- C: modal decay ----------
    cTop = 5.05
    cBot = 6.75
    cyHi = 4
    cyLo = 0
    for k to nTr
        for c to nFr
            cyLo = min(cyLo, trDb[k, c])
        endfor
    endfor
    cyLo = max(-80, cyLo - 3)
    tA = t1
    tB = t2
    Font size: 6
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: tA, tB, cyLo, cyHi
    Paint rectangle: "{0.985, 0.985, 0.99}", tA, tB, cyLo, cyHi
    Colour: "{0.80, 0.80, 0.82}"
    for c to nFr - 1
        Draw line: frT[c], max(cyLo, floorDb[c]), frT[c + 1], max(cyLo, floorDb[c + 1])
    endfor
    Colour: "{0.55, 0.20, 0.20}"
    Dotted line
    Draw line: tStrike, cyLo, tStrike, cyHi
    Solid line
    for k to nTr
        if trShow[k]
            Colour: trCol$[k]
            for c to nFr - 1
                Draw line: frT[c], max(cyLo, trDb[k, c]), frT[c + 1], max(cyLo, trDb[k, c + 1])
            endfor
            if trAlpha[k] <> undefined and trA0[k] <> undefined
                sl = -trAlpha[k] * 20 / ln(10)
                Dashed line
                Line width: 1.5
                Draw line: frT[trC1[k]], trA0[k] + sl * (frT[trC1[k]] - tStrike), frT[trC2[k]], max(cyLo, trA0[k] + sl * (frT[trC2[k]] - tStrike))
                Line width: 1
                Solid line
            endif
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: tA, tB, cyLo, cyHi
    Draw inner box
    @siaMarks: "bottom", tA, tB, 10
    @siaMarks: "left", cyLo, cyHi, 4
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Select inner viewport: 0.6, 7.7, cTop, cBot
    Axes: 0, 1, 0, 1
    xl = 0.008
    for k to nTr
        if trShow[k]
            Colour: trCol$[k]
            Text: xl, "left", 0.93, "half", trName$[k]
            xl = xl + (if trMode[k] > 0 then 0.065 else 0.06 fi)
        endif
    endfor
    Colour: "{0.45, 0.45, 0.50}"
    Text: max(xl, 0.35), "left", 0.93, "half", "dashed = exponential fit;  dotted = strike;  grey = noise floor"
    Colour: "Black"
    @siaPanelName: 0.6, 7.7, cTop, cBot, "C  Level (dB re max)"

    # ---------- D: spectral evolution ----------
    dTop = 7.25
    dBot = 8.95
    fShowD = fMaxSpg
    Font size: 6
    Select inner viewport: 0.6, 7.7, dTop, dBot
    selectObject: spg
    # the spectrogram's own domain (0 .. duration) is the interval t1 .. t2
    Paint: 0, 0, 0, fShowD, 100, "yes", 60, 0, 0, "no"
    Select inner viewport: 0.6, 7.7, dTop, dBot
    Axes: tA, tB, 0, fShowD
    for k to nTr
        if trShow[k]
            Colour: trCol$[k]
            Line width: 2
            Draw line: tB - 0.02 * (tB - tA), trF[k], tB, trF[k]
            Line width: 1
        endif
    endfor
    Colour: "Black"
    Select inner viewport: 0.6, 7.7, dTop, dBot
    Axes: tA, tB, 0, fShowD
    Draw inner box
    @siaMarks: "bottom", tA, tB, 10
    @siaMarks: "left", 0, fShowD, 4
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Select inner viewport: 0.6, 7.7, dTop, dBot
    Axes: 0, 1, 0, 1
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.008, "left", 0.95, "half", "Gaussian-window spectrogram, 60 dB range;  coloured ticks at right = tracked partials (colours as in C)"
    Colour: "Black"
    @siaPanelName: 0.6, 7.7, dTop, dBot, if siaMarks.div = 1000 then "D  Frequency (kHz)" else "D  Frequency (Hz)" fi

    # ---------- summary ----------
    Font size: 7
    Select inner viewport: 0.6, 7.7, 9.55, 10.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.6, 7.7, 9.55, 10.55
    Axes: 0, 1, 0, 1
    Draw inner box
    Select inner viewport: 0.6, 7.7, 9.55, 10.55
    Axes: 0, 1, 0, 1
    Colour: "Black"
    if bellOK
        l1$ = (if harmonicSpec then "DOUBTFUL (harmonic spectrum) - " else "" fi) + "Nominal " + fixed$(fN, hzDec) + " Hz (" + nomSource$ + ")   |   modes found " + string$(nModesFound) + " of 5   |   lowest component " + fixed$(pkF[1], 1) + " Hz   |   strike pitch not measured"
        l2$ = ""
        for m to 5
            @siaFmt: bmDevC[m], 0
            l2$ = l2$ + bmName$[m] + " " + siaFmt.out$ + (if m < 5 then " c  |  " else " c" fi)
        endfor
    else
        l1$ = "No consistent bell modal pattern found - no modes named; the strongest components are tracked unnamed"
        l2$ = "Set the Nominal with Fundamental = Manual frequency entry if the bell is known"
    endif
    l3$ = "Doublets " + string$(nDbl) + "   |   reliable decay fits " 
    nRel = 0
    for k to nTr
        if trStat$[k] = "reliable"
            nRel = nRel + 1
        endif
    endfor
    l3$ = l3$ + string$(nRel) + " of " + string$(nTr) + "   |   strike at " + fixed$(tStrike, 2) + " s   |   warnings " + string$(nWarn) + " (see Info)"
    Text: 0.015, "left", 0.80, "half", l1$
    Text: 0.015, "left", 0.50, "half", (if bellOK then "Deviations: " else "" fi) + l2$
    Text: 0.015, "left", 0.20, "half", l3$
    Select outer viewport: 0, 8, 0, canvasH
    Font size: 10
endif

# ============================================================
# EXPORT
# ============================================================
if export_files
    outDir$ = output_directory$
    if outDir$ = "" or outDir$ = "default"
        outDir$ = homeDirectory$
    endif
    outDir$ = replace_regex$(outDir$, "[/\\]+$", "", 0)
    if praatVersion >= 7000
        trustGranted = askForTrust()
        if trustGranted = 0
            exitScript: "Export needs permission to write files."
        endif
    endif
    createDirectory: outDir$
    base$ = outDir$ + "/" + safeName$
    selectObject: partTab
    if analysis_mode = 3
        Save as comma-separated file: base$ + "_SIA_bell_modes.csv"
        selectObject: decayTab
        Save as comma-separated file: base$ + "_SIA_bell_decay.csv"
        selectObject: trackTab
        Save as comma-separated file: base$ + "_SIA_bell_tracks.csv"
        if dblTab
            selectObject: dblTab
            Save as comma-separated file: base$ + "_SIA_bell_doublets.csv"
        endif
    else
        Save as comma-separated file: base$ + "_SIA_partials.csv"
    endif
    writeFile: base$ + "_SIA_summary.txt", mid$(info$ (), infoStart + 1, length(info$ ()) - infoStart)
    if draw_report
        Select outer viewport: 0, 8, 0, canvasH
        Save as 300-dpi PNG file: base$ + "_SIA_report.png"
    endif
    appendInfoLine: ""
    appendInfoLine: "Exported: ", base$, if analysis_mode = 3 then "_SIA_bell_modes.csv, _SIA_bell_decay.csv, _SIA_bell_tracks.csv" + (if dblTab then ", _SIA_bell_doublets.csv" else "" fi) else "_SIA_partials.csv" fi, ", _SIA_summary.txt", if draw_report then ", _SIA_report.png" else "" fi
endif

# ============================================================
# CLEANUP (the original Sound is untouched)
# ============================================================
removeObject: part, spectrum, mag
selectObject: partTab
if analysis_mode = 3
    removeObject: spg
    selectObject: partTab
    plusObject: decayTab
    plusObject: trackTab
    if dblTab
        plusObject: dblTab
    endif
endif
plusObject: sumTab

# ============================================================
# BELL SYNTHESIS: after each analysis pass
# ============================================================
if synthMode
    if synSource = 1 and pass = 1
        synFs = sr
        synDur = if duration_s > 0 then duration_s else durT fi
        synSrcName$ = name$
        synSrcWarn = nWarn
        @siaSynFromAnalysis
        nSynIn = nSyn
        @siaSynTransform
        if nSyn = 0
            exitScript: "No partial could be resynthesised (no tracked component has a decay fit or a measured trajectory)."
        endif
        synLabel$ = "Resynthesis of " + name$
        synName$ = safeName$ + "_resynth"
        @siaSynRender: synName$
        synDone = 1
        if nPass >= 2
            selectObject: synSnd
            synCmp = 1
            start_time_s = 0
            end_time_s = 0
            draw_report = 0
            if fundamental = 2
                manual_frequency_Hz = manual_frequency_Hz * synTransp
            endif
        endif
    elsif synCmp
        @siaSynCompare
        synCmpDone = 1
    endif
endif
pass = pass + 1
endwhile

# ============================================================
# BELL SYNTHESIS REPORT, PLAYBACK, WAV
# ============================================================
if synDone
    if nPass = 0
        writeInfoLine: "=== Spectral Inharmonicity Analyzer v1.3 - Bell Synthesis ==="
    else
        appendInfoLine: ""
        appendInfoLine: "=== Bell Synthesis ==="
    endif
    appendInfoLine: "Source: ", synLabel$, " | result: Sound ", synName$, " | ", synFs, " Hz, ", fixed$(synDur, 3), " s, strike at ", fixed$(synTs, 3), " s"
    appendInfoLine: "Model: sum of sinusoids, initial phase 0, levels in dB re the strongest partial at the strike; "
        ... + (if synSource = 1 then "reference " + synRefName$ + " " else "Nominal " fi), fixed$(synRef, 3), " Hz", if synSource = 1 and synTransp <> 1 then " (transposed x " + fixed$(synTransp, 5) + ")" else "" fi
    appendInfoLine: "Transforms: decay time x ", fixed$(decay_time_factor, 3), ", decay tilt x ", fixed$(decay_tilt_per_octave, 3), "/oct, ratio stretch ",
        ... fixed$(ratio_stretch, 3), ", spectral tilt ", fixed$(spectral_tilt_dB_per_octave, 1), " dB/oct, edits: ", if mode_edits$ = "" then "none" else mode_edits$ fi
    appendInfoLine: "Attack: ", fixed$(attack_ms, 1), " ms raised-cosine onset", if synNoise then " + strike noise (8 ms decay, 18 dB below the strongest partial)" else "" fi,
        ... " | end fade ", fixed$(synFade * 1000, 0), " ms | peak before scaling ", fixed$(synPeakRaw, 4), ", gain ", fixed$(20 * log10(synGain), 2), " dB, output peak ",
        ... fixed$(20 * log10(synPeak), 2), " dBFS"
    if synSource = 1
        appendInfoLine: "Envelopes: ", if envelopes = 1 then "Automatic (fitted exponential where the fit is reliable, measured trajectory otherwise)" else if envelopes = 2 then "Fitted exponential where possible" else "Measured trajectory where possible" fi fi
        appendInfoLine: "NOT an exact reconstruction: phases, attack noise and frequency drift of the source are not reproduced; levels before the first"
            ... + " fitted frame are extrapolated (the analysis window smears the attack)."
    endif
    appendInfoLine: ""
    appendInfoLine: "--- synthesised partials (", nSyn, ") ---"
    @siaPad: "#", 3
    h$ = siaPad.out$
    @siaPad: "partial", 18
    h$ = h$ + siaPad.out$
    @siaPad: "Hz", 11
    h$ = h$ + siaPad.out$
    @siaPad: "ratio", 8
    h$ = h$ + siaPad.out$
    @siaPad: "dB", 7
    h$ = h$ + siaPad.out$
    @siaPad: "T60 s", 8
    appendInfoLine: h$, siaPad.out$, "  envelope / note"
    synLmax = -1e9
    for i to nSyn
        synLmax = max(synLmax, synL[i])
    endfor
    for i to nSyn
        @siaPad: string$(i), 3
        l$ = siaPad.out$
        @siaPad: synName$[i], 18
        l$ = l$ + siaPad.out$
        @siaFmt: synF[i], 3
        @siaPad: siaFmt.out$, 11
        l$ = l$ + siaPad.out$
        @siaFmt: synF[i] / synRef, 4
        @siaPad: siaFmt.out$, 8
        l$ = l$ + siaPad.out$
        @siaFmt: synL[i] - synLmax, 1
        @siaPad: siaFmt.out$, 7
        l$ = l$ + siaPad.out$
        @siaFmt: if synAl[i] = undefined then undefined else 6.908 / synAl[i] fi, 2
        @siaPad: siaFmt.out$, 8
        appendInfoLine: l$, siaPad.out$, "  ", if synEnvT[i] = 1 then "exponential" else "TRAJECTORY" fi, " | ", synNote$[i]
    endfor
    if synSource = 1
        for i to nSynSkip
            appendInfoLine: "  not resynthesised: ", synSkip$[i]
        endfor
        if nSynCap > 0
            appendInfoLine: "  ", nSynCap, " weaker component(s) left out (Number_of_partials = ", number_of_partials, ")"
        elsif nSynIn < number_of_partials
            appendInfoLine: "  only ", nSynIn, " component(s) qualify (tracked: not a sideband, >= -50 dB re the strongest peak, >= 3 / window Hz from a stronger one); Number_of_partials = ", number_of_partials
        endif
    endif
    for i to nSynDrop
        appendInfoLine: "  removed: ", synDrop$[i]
    endfor
    if synCmp
        appendInfoLine: ""
        appendInfoLine: "--- re-analysis of the result (Bell Analysis of ", synCmpName$, ") vs requested ---"
        appendInfoLine: "dB = level at the strike re ", synName$[synCmpRef], " (meas = req + mean level difference over the fitted frames); T60 compared for exponential partials; traj = RMS shape error (dB)"
        @siaPad: "#", 3
        h$ = siaPad.out$
        @siaPad: "req Hz", 11
        h$ = h$ + siaPad.out$
        @siaPad: "meas Hz", 11
        h$ = h$ + siaPad.out$
        @siaPad: "cents", 7
        h$ = h$ + siaPad.out$
        @siaPad: "req dB", 7
        h$ = h$ + siaPad.out$
        @siaPad: "meas dB", 8
        h$ = h$ + siaPad.out$
        @siaPad: "req T60", 8
        h$ = h$ + siaPad.out$
        @siaPad: "meas T60", 9
        h$ = h$ + siaPad.out$
        @siaPad: "err %", 7
        h$ = h$ + siaPad.out$
        @siaPad: "traj", 6
        appendInfoLine: h$, siaPad.out$, "  measured status"
        maxCents = undefined
        maxDb = undefined
        maxT60 = undefined
        maxRms = undefined
        for i to nSyn
            @siaPad: string$(i), 3
            l$ = siaPad.out$
            @siaFmt: synF[i], 3
            @siaPad: siaFmt.out$, 11
            l$ = l$ + siaPad.out$
            @siaFmt: synMF[i], 3
            @siaPad: siaFmt.out$, 11
            l$ = l$ + siaPad.out$
            @siaFmt: synMCents[i], 2
            @siaPad: siaFmt.out$, 7
            l$ = l$ + siaPad.out$
            @siaFmt: synL[i] - synL[synCmpRef], 1
            @siaPad: siaFmt.out$, 7
            l$ = l$ + siaPad.out$
            @siaFmt: synMLrel[i], 1
            @siaPad: siaFmt.out$, 8
            l$ = l$ + siaPad.out$
            @siaFmt: synReqT60[i], 2
            @siaPad: siaFmt.out$, 8
            l$ = l$ + siaPad.out$
            @siaFmt: synMT60[i], 2
            @siaPad: siaFmt.out$, 9
            l$ = l$ + siaPad.out$
            @siaFmt: synMT60err[i], 1
            @siaPad: siaFmt.out$, 7
            l$ = l$ + siaPad.out$
            @siaFmt: synMRms[i], 2
            @siaPad: siaFmt.out$, 6
            appendInfoLine: l$, siaPad.out$, "  ", synMStat$[i]
            if synMCents[i] <> undefined
                maxCents = if maxCents = undefined then abs(synMCents[i]) else max(maxCents, abs(synMCents[i])) fi
            endif
            if synMLerr[i] <> undefined
                maxDb = if maxDb = undefined then abs(synMLerr[i]) else max(maxDb, abs(synMLerr[i])) fi
            endif
            if synMT60err[i] <> undefined and synMStat$[i] = "reliable"
                maxT60 = if maxT60 = undefined then abs(synMT60err[i]) else max(maxT60, abs(synMT60err[i])) fi
            endif
            if synMRms[i] <> undefined
                maxRms = if maxRms = undefined then synMRms[i] else max(maxRms, synMRms[i]) fi
            endif
        endfor
        @siaFmt: maxCents, 3
        m1$ = siaFmt.out$
        @siaFmt: maxDb, 2
        m2$ = siaFmt.out$
        @siaFmt: maxT60, 2
        m3$ = siaFmt.out$
        @siaFmt: maxRms, 2
        appendInfoLine: "Found ", nSynFound, " of ", nSyn, " partials in the spectrum | max |error| over measured partials: ", m1$, " cents, ", m2$, " dB level, ",
            ... m3$, " % T60 (reliable fits), ", siaFmt.out$, " dB trajectory shape | strongest unrequested component: ",
            ... if synSpurDb = undefined then "none" else fixed$(synSpurDb, 1) + " dB at " + fixed$(synSpurF, 1) + " Hz" fi
        appendInfoLine: "(Errors include the analyzer's own limits: decays near the noise floor, beats of close partials inside one band, window smearing.)"
    endif

    # table (+ CSV when Export_files)
    synTab = Create Table with column names: "SIA_synthesis_" + replace_regex$(synName$, "[^A-Za-z0-9_\-]", "_", 0), nSyn,
        ... "partial frequency_hz ratio_to_reference level_db t60_s envelope source_status note measured_hz error_cents measured_level_db level_error_db measured_t60_s t60_error_pct trajectory_rms_db measured_status"
    for i to nSyn
        Set string value: i, "partial", replace$(synName$[i], " ", "_", 0)
        Set numeric value: i, "frequency_hz", round(synF[i] * 1000) / 1000
        Set numeric value: i, "ratio_to_reference", round(synF[i] / synRef * 1e5) / 1e5
        Set numeric value: i, "level_db", round((synL[i] - synLmax) * 100) / 100
        if synAl[i] = undefined
            Set string value: i, "t60_s", "NA"
        else
            Set numeric value: i, "t60_s", round(6.908 / synAl[i] * 1000) / 1000
        endif
        Set string value: i, "envelope", if synEnvT[i] = 1 then "exponential" else "measured_trajectory" fi
        Set string value: i, "source_status", replace$(synSrcStat$[i], " ", "_", 0)
        Set string value: i, "note", replace$(synNote$[i], " ", "_", 0)
        for cI to 7
            if synCmp = 0
                v = undefined
            elsif cI = 1
                v = synMF[i]
            elsif cI = 2
                v = synMCents[i]
            elsif cI = 3
                v = synMLrel[i]
            elsif cI = 4
                v = synMLerr[i]
            elsif cI = 5
                v = synMT60[i]
            elsif cI = 6
                v = synMT60err[i]
            else
                v = synMRms[i]
            endif
            col$ = if cI = 1 then "measured_hz" else if cI = 2 then "error_cents" else if cI = 3 then "measured_level_db" else if cI = 4 then "level_error_db" else if cI = 5 then "measured_t60_s" else if cI = 6 then "t60_error_pct" else "trajectory_rms_db" fi fi fi fi fi fi
            if v = undefined
                Set string value: i, col$, "NA"
            else
                Set numeric value: i, col$, round(v * 1000) / 1000
            endif
        endfor
        Set string value: i, "measured_status", if synCmp then replace$(synMStat$[i], " ", "_", 0) else "NA" fi
    endfor
    if export_files or save_WAV
        outDir$ = output_directory$
        if outDir$ = "" or outDir$ = "default"
            outDir$ = homeDirectory$
        endif
        outDir$ = replace_regex$(outDir$, "[/\\]+$", "", 0)
        if praatVersion >= 7000
            trustGranted = askForTrust()
            if trustGranted = 0
                exitScript: "Saving needs permission to write files."
            endif
        endif
        createDirectory: outDir$
        synBase$ = outDir$ + "/" + replace_regex$(synName$, "[^A-Za-z0-9_\-]", "_", 0)
        if export_files
            selectObject: synTab
            Save as comma-separated file: synBase$ + "_SIA_synthesis.csv"
            appendInfoLine: "Exported: ", synBase$, "_SIA_synthesis.csv"
        endif
        if save_WAV
            selectObject: synSnd
            Save as WAV file: synBase$ + ".wav"
            appendInfoLine: "Saved: ", synBase$, ".wav"
        endif
    endif
    selectObject: synSnd
    if play_result
        Play
    endif
    plusObject: synTab
endif
