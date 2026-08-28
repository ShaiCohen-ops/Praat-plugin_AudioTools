# ============================================================
# Praat AudioTools - RISSET'S MUTATIONS
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Risset-inspired timbre-mutation generator. Randomly scheduled sine events
#   pass through time-varying polynomial waveshapers. A separate amplitude
#   envelope closes every event smoothly; a mutation envelope swells the
#   waveshaping depth toward the event midpoint and returns to the sine source.
#
#   Mode 1 uses an odd polynomial (fundamental + 3rd + 5th components),
#   Mode 2 crossfades toward a fundamental + 2nd-harmonic Chebyshev shape,
#   and Mode 3 crossfades toward the 7th-order Chebyshev polynomial T7.
#
# Visualization is score-led and mechanism-faithful:
#   A. a large spectral-partitura view of the actual scheduled events. Each
#      event keeps its true onset/duration/f0. A curved arch is retained as an
#      expressive mutation gesture (explicitly symbolic, not a pitch bend),
#      while horizontal partial traces show the harmonics actually created by
#      the polynomial waveshaper through time; line weight follows partial
#      amplitude,
#   B. amplitude and mutation envelopes for a representative event,
#   C. analytical harmonic model versus a measured Praat spectral probe,
#      followed by compact QC.
#
# Changelog v0.5.3:
#   - Made the representative spectral validation probe Nyquist-safe.
#   - Harmonic bins are measured only when h*f0 is below Nyquist; bins above
#     Nyquist are assigned measured magnitude 0 (their analytical model value
#     is already 0 because all generated partials pass the synthesis guard).
#   - Prevents undefined LTAS values from contaminating spectral MAE / drawing.
#
# Changelog v0.5.2:
#   - Restored the characteristic per-event mutation arches in the score.
#   - The arches are explicitly treated as expressive notation, not literal
#     frequency trajectories; their height maps mutation depth on the score.
#   - Keeps the exact generated-harmonic traces underneath/alongside the arches,
#     so the score combines gestural character with acoustically true process data.
#
# Changelog v0.5.1:
#   - Restored the large score/partitura layout requested for this instrument.
#   - Replaced the old decorative frequency-bend curve with actual generated
#     harmonic traces (h1/h3/h5, h1/h2, or h1/h7 depending on mode).
#   - Uses logarithmic frequency so fundamentals and generated upper partials
#     remain readable in the same score.
#   - Keeps the v0.5 scheduler, synthesis, seed, Nyquist and QC corrections.
#   - Preserves separate Picture viewports for all titles, legends and QC text.
#
# Changelog v0.5:
#   - Added analytical-versus-measured harmonic validation for the waveshaper.
#   - Fixed event scheduling bias: duration is drawn first, then onset is drawn
#     only where that duration fits; events are no longer truncated at the end.
#   - Made event Sounds full-length and explicitly zero outside each event,
#     avoiding cross-object indexing beyond a shorter temporary Sound.
#   - Added deterministic seed, sample-rate/output-peak details, Nyquist checks,
#     output QC, and a compact main form.
# ============================================================

# ============================================================
# COMPACT FORM
# ============================================================
form Risset's Mutations v0.5.3
    optionmenu Preset 1
        option Full Composition (3-Part Arc)
        option Odd Harmonics (Woody/Hollow)
        option High Order (Glassy/Chime)
        option Density (Brassy/Chaos)

    positive Duration_s 30.0

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED DEFAULTS / OPTIONAL DETAILS
# ============================================================
sample_rate_Hz = 44100
output_peak = 0.95
random_seed = 0

if edit_details
    beginPause: "Risset's Mutations - Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        real: "Output peak (0..1]", output_peak
        integer: "Random seed (0 = unpredictable)", random_seed
    endPause: "Run", 1
endif

# ============================================================
# VALIDATION
# ============================================================
if sample_rate_Hz < 1000
    exitScript: "Sample rate must be at least 1000 Hz."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and at most 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (unpredictable) or a positive integer."
endif
if duration_s * sample_rate_Hz < 16
    exitScript: "Duration is too short for the selected sample rate (need at least 16 samples)."
endif

master_duration = duration_s
sample_rate = sample_rate_Hz
base_freq = 110.0
nyquist = sample_rate / 2

# A non-seeded UID keeps temporary object names distinct without consuming the
# deterministic scheduler sequence.
run_id = randomInteger(100000, 999999)

# ============================================================
# PRESET / SCHEDULER
# Draw duration first, then choose an onset that can contain it. This removes
# the end-of-piece duration truncation bias of v0.4.
# ============================================================
preset_name$ = "FullComposition"
if preset = 1
    n_events = 14
    preset_name$ = "FullComposition"
elsif preset = 2
    n_events = 8
    preset_name$ = "OddHarmonics"
elsif preset = 3
    n_events = 12
    preset_name$ = "HighOrder"
else
    n_events = 25
    preset_name$ = "Density"
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

compressed_duration_ranges = 0
mode_count[1] = 0
mode_count[2] = 0
mode_count[3] = 0
sum_pk = 0
min_event_dur = master_duration
max_event_dur = 0
min_event_freq = 1e30
max_event_freq = 0
highest_partial = 0

for i from 1 to n_events
    # Define the scheduler region and event parameter ranges.
    if preset = 1
        if i <= 4
            section[i] = 1
            t_min = 0.0
            t_max = master_duration * 0.30
            dur_lo = 8.0
            dur_hi = 14.0
            freq_lo = base_freq
            freq_hi = base_freq * 3
            mode[i] = 1
            pk_lo = 0.3
            pk_hi = 0.6
        elsif i <= 10
            section[i] = 2
            t_min = master_duration * 0.30
            t_max = master_duration * 0.70
            dur_lo = 4.0
            dur_hi = 8.0
            freq_lo = base_freq * 2
            freq_hi = base_freq * 8
            mode[i] = 2
            pk_lo = 0.7
            pk_hi = 1.0
        else
            section[i] = 3
            t_min = master_duration * 0.60
            t_max = master_duration * 0.90
            dur_lo = 6.0
            dur_hi = 10.0
            freq_lo = base_freq
            freq_hi = base_freq * 4
            mode[i] = 3
            pk_lo = 0.2
            pk_hi = 0.5
        endif
    elsif preset = 2
        section[i] = 1
        t_min = 0
        t_max = master_duration * 0.60
        dur_lo = 10.0
        dur_hi = 15.0
        freq_lo = 55.0
        freq_hi = 275.0
        mode[i] = 1
        pk_lo = 0.2
        pk_hi = 0.7
    elsif preset = 3
        section[i] = 1
        t_min = 0
        t_max = master_duration * 0.80
        dur_lo = 4.0
        dur_hi = 9.0
        freq_lo = 440.0
        freq_hi = 1100.0
        mode[i] = 3
        pk_lo = 0.3
        pk_hi = 0.8
    else
        section[i] = 1
        t_min = 0
        t_max = master_duration * 0.85
        dur_lo = 1.5
        dur_hi = 4.0
        freq_lo = 110.0
        freq_hi = 1320.0
        mode[i] = 2
        pk_lo = 0.6
        pk_hi = 1.0
    endif

    available_after_tmin = master_duration - t_min
    dur_hi_eff = min(dur_hi, available_after_tmin)
    dur_lo_eff = min(dur_lo, dur_hi_eff)
    if dur_hi_eff < dur_hi
        compressed_duration_ranges = compressed_duration_ranges + 1
    endif

    if dur_hi_eff <= 0
        exitScript: "Duration is too short for the selected preset scheduler."
    endif
    if dur_hi_eff * sample_rate < 8
        exitScript: "An event would contain fewer than 8 samples. Increase Duration or sample rate."
    endif

    if abs(dur_hi_eff - dur_lo_eff) < 1e-12
        dur[i] = dur_hi_eff
    else
        dur[i] = randomUniform(dur_lo_eff, dur_hi_eff)
    endif

    latest_start = min(t_max, master_duration - dur[i])
    if latest_start < t_min
        latest_start = t_min
    endif
    if abs(latest_start - t_min) < 1e-12
        start_t[i] = t_min
    else
        start_t[i] = randomUniform(t_min, latest_start)
    endif

    freq[i] = randomUniform(freq_lo, freq_hi)
    pk[i] = randomUniform(pk_lo, pk_hi)

    # Highest polynomial harmonic created by each waveshaper mode.
    if mode[i] = 1
        highest_harmonic = 5
    elsif mode[i] = 2
        highest_harmonic = 2
    else
        highest_harmonic = 7
    endif
    event_highest_partial = freq[i] * highest_harmonic
    if event_highest_partial > highest_partial
        highest_partial = event_highest_partial
    endif

    mode_count[mode[i]] = mode_count[mode[i]] + 1
    sum_pk = sum_pk + pk[i]
    if dur[i] < min_event_dur
        min_event_dur = dur[i]
    endif
    if dur[i] > max_event_dur
        max_event_dur = dur[i]
    endif
    if freq[i] < min_event_freq
        min_event_freq = freq[i]
    endif
    if freq[i] > max_event_freq
        max_event_freq = freq[i]
    endif
endfor

if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

if highest_partial >= 0.95 * nyquist
    exitScript: "The scheduled waveshaping partials approach/exceed Nyquist. Increase sample rate or use another preset. Highest partial = " + fixed$(highest_partial, 1) + " Hz; 95% Nyquist = " + fixed$(0.95 * nyquist, 1) + " Hz."
endif

mean_pk = sum_pk / n_events

# Representative event: choose the event with the greatest mutation depth.
rep_index = 1
for i from 2 to n_events
    if pk[i] > pk[rep_index]
        rep_index = i
    endif
endfor
rep_freq = freq[rep_index]
rep_dur = dur[rep_index]
rep_pk = pk[rep_index]
rep_mode = mode[rep_index]

# ============================================================
# SYNTHESIS
# ============================================================
clearinfo
writeInfoLine: "=== Risset's Mutations v0.5.3 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Events: ", n_events, " | Duration: ", fixed$(master_duration, 3), " s"
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible scheduler)"
else
    appendInfoLine: "Random seed: unpredictable"
endif
appendInfoLine: "Highest scheduled polynomial partial: ", fixed$(highest_partial, 1), " Hz"

master_name$ = "RissetMutations_" + preset_name$ + "_" + string$(run_id)
Create Sound from formula: master_name$, 1, 0, master_duration, sample_rate, "0"
master_id = selected("Sound")

appendInfoLine: "Synthesizing events..."

for i from 1 to n_events
    suffix$ = "_" + string$(i) + "_" + string$(run_id)
    t_start = start_t[i]
    dur_evt = dur[i]
    t_end = t_start + dur_evt
    frq = freq[i]
    m_pk = pk[i]
    md = mode[i]

    voice_name$ = "Voice" + suffix$
    env_morph$ = "EnvMorph" + suffix$
    env_amp$ = "EnvAmp" + suffix$

    # Full-duration temporary Sounds are explicit zeros outside the event.
    Create Sound from formula: voice_name$, 1, 0, master_duration, sample_rate,
        ... "if x < 't_start' or x > 't_end' then 0 else sin(2*pi*'frq'*(x-'t_start')) fi"

    Create Sound from formula: env_morph$, 1, 0, master_duration, sample_rate,
        ... "if x < 't_start' or x > 't_end' then 0 else 'm_pk' * (max(0, sin(pi*(x-'t_start')/'dur_evt')))^1.5 fi"

    Create Sound from formula: env_amp$, 1, 0, master_duration, sample_rate,
        ... "if x < 't_start' or x > 't_end' then 0 else (sin(pi*(x-'t_start')/'dur_evt'))^2 fi"

    selectObject: "Sound " + voice_name$
    if md = 1
        # Odd polynomial: at full mutation this contains h = 1, 3, 5.
        Formula: "(1-Sound_'env_morph$'[])*self + Sound_'env_morph$'[]*(-0.3*self + 2*self^3 - 0.7*self^5)"
    elsif md = 2
        # Fundamental + T2 component (second harmonic).
        Formula: "(1-Sound_'env_morph$'[])*self + Sound_'env_morph$'[]*(0.5*self + 0.5*(2*self^2 - 1))"
    else
        # T7(self): for a sine source this becomes the seventh harmonic in
        # opposite phase at full mutation.
        Formula: "(1-Sound_'env_morph$'[])*self + Sound_'env_morph$'[]*(64*self^7 - 112*self^5 + 56*self^3 - 7*self)"
    endif
    Formula: "self * Sound_'env_amp$'[]"

    selectObject: master_id
    Formula: "self + Sound_'voice_name$'[]"

    selectObject: "Sound " + voice_name$
    plusObject: "Sound " + env_morph$
    plusObject: "Sound " + env_amp$
    Remove
endfor

# ============================================================
# FINALIZE / QC
# ============================================================
selectObject: master_id
pre_norm_peak = Get absolute extremum: 0, 0, "None"
pre_norm_rms = Get root-mean-square: 0, 0
if pre_norm_peak > 0
    Scale peak: output_peak
endif
Rename: "risset_mutations_" + preset_name$
master_id = selected("Sound")
final_peak = Get absolute extremum: 0, 0, "None"
final_rms = Get root-mean-square: 0, 0

appendInfoLine: "Mutation depth mean/max: ", fixed$(mean_pk, 3), " / ", fixed$(rep_pk, 3)
appendInfoLine: "Event duration range: ", fixed$(min_event_dur, 3), "..", fixed$(max_event_dur, 3), " s"
appendInfoLine: "Fundamental range: ", fixed$(min_event_freq, 1), "..", fixed$(max_event_freq, 1), " Hz"
appendInfoLine: "Mode counts (odd/even/T7): ", mode_count[1], " / ", mode_count[2], " / ", mode_count[3]
appendInfoLine: "Preset duration ranges compressed by short master duration: ", compressed_duration_ranges, " events"
appendInfoLine: "Output peak/RMS: ", fixed$(final_peak, 4), " / ", fixed$(final_rms, 4)

if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: master_id
    Play
endif

selectObject: master_id
appendInfoLine: "Done. Created Sound: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    # --------------------------------------------------------------------------
    # Spectral validation probe for the representative event.
    # The probe freezes the mutation envelope at its peak value, applies the
    # same polynomial to a sine, and windows it with Hann. Measured harmonic
    # magnitudes are compared with the exact polynomial prediction.
    # --------------------------------------------------------------------------
    .probeCycles = 32
    .probeDur = .probeCycles / rep_freq
    .probeName$ = "MutationProbe_" + string$(run_id)

    if rep_mode = 1
        Create Sound from formula: .probeName$, 1, 0, .probeDur, sample_rate,
            ... "((1-'rep_pk')*sin(2*pi*'rep_freq'*x) + 'rep_pk'*(-0.3*sin(2*pi*'rep_freq'*x) + 2*sin(2*pi*'rep_freq'*x)^3 - 0.7*sin(2*pi*'rep_freq'*x)^5)) * (0.5 - 0.5*cos(2*pi*x/'.probeDur'))"
    elsif rep_mode = 2
        Create Sound from formula: .probeName$, 1, 0, .probeDur, sample_rate,
            ... "((1-'rep_pk')*sin(2*pi*'rep_freq'*x) + 'rep_pk'*(0.5*sin(2*pi*'rep_freq'*x) + 0.5*(2*sin(2*pi*'rep_freq'*x)^2 - 1))) * (0.5 - 0.5*cos(2*pi*x/'.probeDur'))"
    else
        Create Sound from formula: .probeName$, 1, 0, .probeDur, sample_rate,
            ... "((1-'rep_pk')*sin(2*pi*'rep_freq'*x) + 'rep_pk'*(64*sin(2*pi*'rep_freq'*x)^7 - 112*sin(2*pi*'rep_freq'*x)^5 + 56*sin(2*pi*'rep_freq'*x)^3 - 7*sin(2*pi*'rep_freq'*x))) * (0.5 - 0.5*cos(2*pi*x/'.probeDur'))"
    endif
    .probeSound = selected("Sound")
    To Spectrum: "yes"
    .probeSpectrum = selected("Spectrum")
    To Ltas (1-to-1)
    .probeLtas = selected("Ltas")

    .measMaxDb = -1e30
    for .h to 7
        .probeHz = .h * rep_freq
        .binInRange[.h] = 0
        if .probeHz < nyquist
            .measDb[.h] = Get value at frequency: .probeHz, "Cubic"
            .binInRange[.h] = 1
            if .measDb[.h] > .measMaxDb
                .measMaxDb = .measDb[.h]
            endif
        else
            .measDb[.h] = -1e30
        endif
    endfor
    for .h to 7
        if .binInRange[.h] = 1
            .measured[.h] = 10 ^ ((.measDb[.h] - .measMaxDb) / 20)
        else
            .measured[.h] = 0
        endif
        .model[.h] = 0
    endfor

    if rep_mode = 1
        .model[1] = abs(1 - 0.2375 * rep_pk)
        .model[3] = abs(0.28125 * rep_pk)
        .model[5] = abs(0.04375 * rep_pk)
    elsif rep_mode = 2
        .model[1] = abs(1 - 0.5 * rep_pk)
        .model[2] = abs(0.5 * rep_pk)
    else
        .model[1] = abs(1 - rep_pk)
        .model[7] = abs(rep_pk)
    endif

    .modelMax = 0
    for .h to 7
        if .model[.h] > .modelMax
            .modelMax = .model[.h]
        endif
    endfor
    if .modelMax <= 0
        .modelMax = 1
    endif
    .spectralMae = 0
    for .h to 7
        .model[.h] = .model[.h] / .modelMax
        .spectralMae = .spectralMae + abs(.model[.h] - .measured[.h])
    endfor
    .spectralMae = .spectralMae / 7

    selectObject: .probeSound
    plusObject: .probeSpectrum
    plusObject: .probeLtas
    Remove

    # --------------------------------------------------------------------------
    # Score-led Picture layout. Every text strip owns an explicit viewport.
    # --------------------------------------------------------------------------
    Erase all

    # ---------------- Title ----------------
    Select outer viewport: 0, 8, 0.04, 0.34
    Select inner viewport: 0.20, 7.80, 0.06, 0.31
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "Risset's Mutations: " + preset_name$

    # ---------------- Process strip ----------------
    Select outer viewport: 0, 8, 0.36, 0.62
    Select inner viewport: 0.20, 7.80, 0.39, 0.59
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.30,0.30,0.30}"
    Text: 0.5, "centre", 0.50, "half", "schedule  ->  sine f0  ->  mutation m(t) + polynomial waveshaper  ->  time-varying harmonics  ->  amplitude a(t)  ->  sum"

    # ---------------- Score title ----------------
    Select outer viewport: 0, 8, 0.66, 0.88
    Select inner viewport: 0.10, 7.90, 0.68, 0.86
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "A  Mutation score: expressive arches + actual generated partials (weight = instantaneous partial amplitude)"

    # ---------------- Large spectral-partitura score ----------------
    Select outer viewport: 0, 8, 0.90, 5.40
    Select inner viewport: 0.82, 7.62, 1.02, 5.18
    .scoreMinF = max(40, min_event_freq * 0.78)
    .scoreMaxF = min(0.95 * nyquist, highest_partial * 1.12)
    if .scoreMaxF <= .scoreMinF * 1.2
        .scoreMaxF = .scoreMinF * 1.2
    endif
    .logLo = log10(.scoreMinF)
    .logHi = log10(.scoreMaxF)
    Axes: 0, master_duration, .logLo, .logHi
    Paint rectangle: "{0.025,0.028,0.040}", 0, master_duration, .logLo, .logHi

    # Full-composition sections remain visible as subtle vertical regions.
    if preset = 1
        Paint rectangle: "{0.035,0.045,0.065}", 0, master_duration * 0.30, .logLo, .logHi
        Paint rectangle: "{0.050,0.047,0.033}", master_duration * 0.30, master_duration * 0.70, .logLo, .logHi
        Paint rectangle: "{0.055,0.035,0.040}", master_duration * 0.70, master_duration, .logLo, .logHi
    endif

    # Log-frequency grid and custom labels.
    Colour: "{0.16,0.17,0.21}"
    Line width: 0.5
    if 50 >= .scoreMinF and 50 <= .scoreMaxF
        Draw line: 0, log10(50), master_duration, log10(50)
    endif
    if 100 >= .scoreMinF and 100 <= .scoreMaxF
        Draw line: 0, log10(100), master_duration, log10(100)
    endif
    if 200 >= .scoreMinF and 200 <= .scoreMaxF
        Draw line: 0, log10(200), master_duration, log10(200)
    endif
    if 500 >= .scoreMinF and 500 <= .scoreMaxF
        Draw line: 0, log10(500), master_duration, log10(500)
    endif
    if 1000 >= .scoreMinF and 1000 <= .scoreMaxF
        Draw line: 0, log10(1000), master_duration, log10(1000)
    endif
    if 2000 >= .scoreMinF and 2000 <= .scoreMaxF
        Draw line: 0, log10(2000), master_duration, log10(2000)
    endif
    if 5000 >= .scoreMinF and 5000 <= .scoreMaxF
        Draw line: 0, log10(5000), master_duration, log10(5000)
    endif
    if 10000 >= .scoreMinF and 10000 <= .scoreMaxF
        Draw line: 0, log10(10000), master_duration, log10(10000)
    endif

    .timeStep = 5
    if master_duration <= 20
        .timeStep = 2
    elsif master_duration <= 45
        .timeStep = 5
    elsif master_duration <= 90
        .timeStep = 10
    else
        .timeStep = 20
    endif
    .gridT = .timeStep
    while .gridT < master_duration
        Colour: "{0.12,0.13,0.16}"
        Line width: 0.5
        Draw line: .gridT, .logLo, .gridT, .logHi
        .gridT = .gridT + .timeStep
    endwhile

    # Draw each scheduled event as an actual time-varying harmonic constellation.
    # The baseline is the event's f0/duration. Partial trace weights use the
    # square root of instantaneous magnitude for visibility, while the partial
    # frequencies themselves are exact integer multiples produced by the mode.
    .segments = 32
    for .i to n_events
        .t1 = start_t[.i]
        .durEvt = dur[.i]
        .f0 = freq[.i]
        .p = pk[.i]
        .md = mode[.i]

        # Keep the old score's blue->cyan->green->yellow->red temporal arc.
        .timeRatio = .t1 / master_duration
        if .timeRatio < 0.25
            .phaseC = .timeRatio / 0.25
            .r = 0.30
            .g = 0.50 + .phaseC * 0.30
            .b = 1.00
        elsif .timeRatio < 0.50
            .phaseC = (.timeRatio - 0.25) / 0.25
            .r = 0.30
            .g = 0.80 + .phaseC * 0.20
            .b = 1.00 - .phaseC * 0.40
        elsif .timeRatio < 0.75
            .phaseC = (.timeRatio - 0.50) / 0.25
            .r = 0.30 + .phaseC * 0.50
            .g = 1.00
            .b = 0.60 - .phaseC * 0.60
        else
            .phaseC = (.timeRatio - 0.75) / 0.25
            .r = 0.80 + .phaseC * 0.20
            .g = 1.00 - .phaseC * 0.30
            .b = 0.00
        endif

        # Expressive mutation arch. This is notation, not a literal frequency
        # trajectory: its vertical excursion is a fixed fraction of the score's
        # log-frequency span, scaled only by the event's mutation peak. The
        # actual generated frequencies are drawn separately as horizontal partials.
        .gestureHeight = 0.105 * (.logHi - .logLo) * .p
        .gxPrev = .t1
        .gyPrev = log10(.f0)
        Colour: "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"
        Line width: 1.45
        for .gs from 1 to .segments
            .gu = .gs / .segments
            .gx = .t1 + .gu * .durEvt
            .gshape = max(0, sin(pi * .gu))^1.5
            .gy = log10(.f0) + .gestureHeight * .gshape
            Draw line: .gxPrev, .gyPrev, .gx, .gy
            .gxPrev = .gx
            .gyPrev = .gy
        endfor

        # Duration baseline at f0, intentionally dimmer than sounding traces.
        .dimR = .r * 0.42
        .dimG = .g * 0.42
        .dimB = .b * 0.42
        Colour: "{" + fixed$(.dimR,3) + "," + fixed$(.dimG,3) + "," + fixed$(.dimB,3) + "}"
        Line width: 0.5
        Draw line: .t1, log10(.f0), .t1 + .durEvt, log10(.f0)

        for .s from 1 to .segments
            .u0 = (.s - 1) / .segments
            .u1 = .s / .segments
            .x0 = .t1 + .u0 * .durEvt
            .x1 = .t1 + .u1 * .durEvt
            .um = 0.5 * (.u0 + .u1)
            .ampEnv = sin(pi * .um)^2
            .morph = .p * max(0, sin(pi * .um))^1.5

            if .md = 1
                .a1 = .ampEnv * abs(1 - 0.2375 * .morph)
                .a3 = .ampEnv * abs(0.28125 * .morph)
                .a5 = .ampEnv * abs(0.04375 * .morph)

                Colour: "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"
                if .a1 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a1)
                    Draw line: .x0, log10(.f0), .x1, log10(.f0)
                endif
                if 3*.f0 <= .scoreMaxF and .a3 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a3)
                    Draw line: .x0, log10(3*.f0), .x1, log10(3*.f0)
                endif
                if 5*.f0 <= .scoreMaxF and .a5 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a5)
                    Draw line: .x0, log10(5*.f0), .x1, log10(5*.f0)
                endif
            elsif .md = 2
                .a1 = .ampEnv * abs(1 - 0.5 * .morph)
                .a2 = .ampEnv * abs(0.5 * .morph)

                Colour: "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"
                if .a1 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a1)
                    Draw line: .x0, log10(.f0), .x1, log10(.f0)
                endif
                if 2*.f0 <= .scoreMaxF and .a2 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a2)
                    Draw line: .x0, log10(2*.f0), .x1, log10(2*.f0)
                endif
            else
                .a1 = .ampEnv * abs(1 - .morph)
                .a7 = .ampEnv * abs(.morph)

                Colour: "{" + fixed$(.r,3) + "," + fixed$(.g,3) + "," + fixed$(.b,3) + "}"
                if .a1 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a1)
                    Draw line: .x0, log10(.f0), .x1, log10(.f0)
                endif
                if 7*.f0 <= .scoreMaxF and .a7 > 0.002
                    Line width: 0.35 + 2.5 * sqrt(.a7)
                    Draw line: .x0, log10(7*.f0), .x1, log10(7*.f0)
                endif
            endif
        endfor
    endfor

    # Frame and explicit axes after all score drawing.
    Line width: 1
    Colour: "{0.72,0.72,0.76}"
    Draw inner box
    Select inner viewport: 0.82, 7.62, 1.02, 5.18
    Axes: 0, master_duration, .logLo, .logHi
    Font size: 7
    Colour: "White"
    Marks bottom every: 1, .timeStep, "yes", "yes", "no"
    if 50 >= .scoreMinF and 50 <= .scoreMaxF
        One mark left: log10(50), "yes", "yes", "no", "50"
    endif
    if 100 >= .scoreMinF and 100 <= .scoreMaxF
        One mark left: log10(100), "yes", "yes", "no", "100"
    endif
    if 200 >= .scoreMinF and 200 <= .scoreMaxF
        One mark left: log10(200), "yes", "yes", "no", "200"
    endif
    if 500 >= .scoreMinF and 500 <= .scoreMaxF
        One mark left: log10(500), "yes", "yes", "no", "500"
    endif
    if 1000 >= .scoreMinF and 1000 <= .scoreMaxF
        One mark left: log10(1000), "yes", "yes", "no", "1k"
    endif
    if 2000 >= .scoreMinF and 2000 <= .scoreMaxF
        One mark left: log10(2000), "yes", "yes", "no", "2k"
    endif
    if 5000 >= .scoreMinF and 5000 <= .scoreMaxF
        One mark left: log10(5000), "yes", "yes", "no", "5k"
    endif
    if 10000 >= .scoreMinF and 10000 <= .scoreMaxF
        One mark left: log10(10000), "yes", "yes", "no", "10k"
    endif
    Font size: 9
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz, log)"

    # ---------------- Score legend ----------------
    Select outer viewport: 0, 8, 5.42, 5.62
    Select inner viewport: 0.28, 7.72, 5.44, 5.60
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.28,0.28,0.28}"
    Text: 0.5, "centre", 0.5, "half", "curved arch = symbolic mutation gesture (not pitch)   |   horizontal traces = generated harmonics   |   colour = event onset"

    # ---------------- Mechanism-check title ----------------
    Select outer viewport: 0, 8, 5.66, 5.86
    Select inner viewport: 0.10, 7.90, 5.68, 5.84
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.50, "half", "B  Representative event and spectral validation"

    # ---------------- Left mini-panel: envelopes ----------------
    Select outer viewport: 0, 4.15, 5.88, 6.78
    Select inner viewport: 0.72, 3.92, 5.98, 6.58
    Axes: 0, rep_dur, 0, 1.05
    Paint rectangle: "{0.96,0.96,0.96}", 0, rep_dur, 0, 1.05
    .envSegments = 120
    .prevT = 0
    .prevAmp = 0
    .prevMorph = 0
    for .k from 1 to .envSegments
        .tt = .k * rep_dur / .envSegments
        .ph = pi * .tt / rep_dur
        .amp = sin(.ph)^2
        .morph = rep_pk * max(0, sin(.ph))^1.5
        Colour: "{0.18,0.48,0.76}"
        Line width: 1.3
        Draw line: .prevT, .prevAmp, .tt, .amp
        Colour: "{0.78,0.38,0.20}"
        Draw line: .prevT, .prevMorph, .tt, .morph
        .prevT = .tt
        .prevAmp = .amp
        .prevMorph = .morph
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Select inner viewport: 0.72, 3.92, 5.98, 6.58
    Axes: 0, rep_dur, 0, 1.05
    Font size: 7
    Marks bottom: 3, "yes", "yes", "no"
    Marks left: 2, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Local event time (s)"
    Text left: "yes", "Envelope"

    # ---------------- Right mini-panel: model vs measurement ----------------
    Select outer viewport: 4.15, 8, 5.88, 6.78
    Select inner viewport: 4.55, 7.62, 5.98, 6.58
    Axes: 0.5, 7.5, 0, 1.08
    Paint rectangle: "{0.96,0.96,0.96}", 0.5, 7.5, 0, 1.08
    for .h to 7
        .xModel = .h - 0.13
        .xMeas = .h + 0.13
        Colour: "{0.18,0.48,0.76}"
        Line width: 1
        Draw line: .xModel, 0, .xModel, .model[.h]
        Paint circle (mm): "{0.18,0.48,0.76}", .xModel, .model[.h], 1.0
        Colour: "{0.78,0.38,0.20}"
        Draw line: .xMeas, 0, .xMeas, .measured[.h]
        Paint circle (mm): "{0.78,0.38,0.20}", .xMeas, .measured[.h], 1.0
    endfor
    Colour: "Black"
    Draw inner box
    Select inner viewport: 4.55, 7.62, 5.98, 6.58
    Axes: 0.5, 7.5, 0, 1.08
    Font size: 7
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Marks left: 2, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Harmonic number"
    Text left: "yes", "Normalized magnitude"

    # ---------------- Mini-panel legend/formula strip ----------------
    Select outer viewport: 0, 8, 6.82, 6.99
    Select inner viewport: 0.20, 7.80, 6.84, 6.97
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30,0.30,0.30}"
    if rep_mode = 1
        .shape$ = "mode 1 P(s)=-0.3s+2s^3-0.7s^5"
    elsif rep_mode = 2
        .shape$ = "mode 2 P(s)=0.5s+0.5(2s^2-1)"
    else
        .shape$ = "mode 3 P(s)=T7(s)"
    endif
    Text: 0.5, "centre", 0.5, "half", "blue a(t)/model, orange m(t)/measured   |   " + .shape$ + "   |   spectral MAE " + fixed$(.spectralMae,3)

    # ---------------- Compact QC: two rows, three fields ----------------
    Select outer viewport: 0, 8, 7.08, 7.78
    Select inner viewport: 0.20, 7.80, 7.11, 7.75
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.94,0.94,0.94}", 0, 3, 0, 2
    Colour: "{0.78,0.78,0.78}"
    Draw line: 1, 0, 1, 2
    Draw line: 2, 0, 2, 2
    Draw line: 0, 1, 3, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Colour: "{0.25,0.25,0.25}"
    Text: 0.5, "centre", 1.5, "half", "Events " + string$(n_events) + " | D " + fixed$(min_event_dur,2) + ".." + fixed$(max_event_dur,2) + " s"
    Text: 1.5, "centre", 1.5, "half", "f0 " + fixed$(min_event_freq,0) + ".." + fixed$(max_event_freq,0) + " Hz"
    Text: 2.5, "centre", 1.5, "half", "Modes " + string$(mode_count[1]) + "/" + string$(mode_count[2]) + "/" + string$(mode_count[3])
    Text: 0.5, "centre", 0.5, "half", "Mutation mean/max " + fixed$(mean_pk,2) + "/" + fixed$(rep_pk,2)
    Text: 1.5, "centre", 0.5, "half", "Max partial " + fixed$(highest_partial,0) + " | Nyq " + fixed$(nyquist,0) + " Hz"
    Text: 2.5, "centre", 0.5, "half", "Peak/RMS " + fixed$(final_peak,3) + "/" + fixed$(final_rms,3) + " | MAE " + fixed$(.spectralMae,3)

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
