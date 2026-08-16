# ============================================================
# Praat AudioTools - Acoustic Pedagogy.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.5.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fifteen interactive demonstrations for musical acoustics and
#   psychoacoustics. v0.5 aligns the sound generation, wording, and
#   visualization so that each panel demonstrates the phenomenon that
#   is actually being heard.
#
# Changelog v0.5.1:
#   - Visualization layout only: dedicated panel title/legend strips.
#   - Larger summary bar and type; DSP and pedagogy unchanged.
#
# Changelog v0.5:
#   - Same-ear two-tone demonstrations now use a centred mono mixture;
#     only binaural beats place different tones in the two ears.
#   - Critical-band demo uses a frequency-dependent ERB estimate and a
#     separation of one quarter ERB instead of a fixed 25 Hz claim.
#   - Wolf fifth corrected to a Pythagorean wolf (pure fifth divided by
#     the Pythagorean comma) and demonstrated with harmonic-rich dyads.
#   - Difference-tone demo explicitly keeps the difference tone absent
#     from the physical source spectrum; combination-tone demo now uses
#     an explicit nonlinear model that really generates sum/difference
#     components.
#   - Shepard demo replaced by a one-octave Shepard-Risset glissando
#     cycle with octave-spaced components moving through a fixed
#     spectral envelope. Repeating or crossfading cycles extends the continuous-ascent
#     illusion; the script no longer claims that a single non-cyclic
#     chirp is literally infinite.
#   - Fourier square-wave demo now uses seven odd harmonics when allowed
#     by Nyquist; harmonic/formant demos also respect Nyquist.
#   - Formant demo now compares a harmonic source with a formant-shaped
#     version of that same source rather than a sine labelled as a buzz.
#   - FM example uses beta = 1 at 5 Hz (about +/-5 Hz deviation), which
#     is a vibrato-scale FM example rather than wideband FM.
#   - New AudioTools 2x2 mechanism-first visualization: TIME, SPECTRUM,
#     MECHANISM, and a phenomenon-specific PROOF panel.
# ============================================================

form Acoustic Pedagogy v0.5.1
    comment === SELECT PHENOMENON ===
    optionmenu Phenomenon: 1
        option 1. Just Intonation (Perfect Fifth)
        option 2. Pythagorean Comma
        option 3. Syntonic Comma
        option 4. Pythagorean Wolf Fifth
        option 5. Critical-Band Roughness
        option 6. Tartini Difference Tone
        option 7. Missing Fundamental (Phantom)
        option 8. Binaural Beats (Headphones!)
        option 9. Fourier Square Wave
        option 10. Shepard-Risset Cyclic Ascent
        option 11. Harmonic Series
        option 12. Nonlinear Combination Tones
        option 13. Formant Synthesis (Vowel /a/)
        option 14. AM vs FM (Tremolo / Vibrato)
        option 15. Phase Cancellation
    comment === PLAYBACK CONTROLS ===
    positive Duration_s 2.0
    positive Base_frequency_Hz 220
    positive Amplitude 0.5
    comment === OPTIONS ===
    boolean Show_info_window 1
    boolean Save_sounds_to_list 0
    boolean Show_visualization 1
    boolean Show_help 0
endform

# ----------------------------
# Help
# ----------------------------
if show_help
    clearinfo
    appendInfoLine: "========================================"
    appendInfoLine: "   ACOUSTIC PEDAGOGY v0.5 - HELP"
    appendInfoLine: "========================================"
    appendInfoLine: ""
    appendInfoLine: "TUNING AND INTERVALS"
    appendInfoLine: "1  Just 3:2 fifth"
    appendInfoLine: "2  Pythagorean comma: 12 fifths versus 7 octaves"
    appendInfoLine: "3  Syntonic comma: 5:4 versus 81:64 major third"
    appendInfoLine: "4  Pythagorean wolf fifth compared with a pure fifth"
    appendInfoLine: ""
    appendInfoLine: "PSYCHOACOUSTICS"
    appendInfoLine: "5  Roughness for two tones inside one auditory filter"
    appendInfoLine: "6  Difference-tone perception: physical source has only f1 and f2"
    appendInfoLine: "7  Missing fundamental: pitch at f0 with f0 absent from spectrum"
    appendInfoLine: "8  Binaural beat: one tone per ear; headphones required"
    appendInfoLine: ""
    appendInfoLine: "SYNTHESIS AND TIMBRE"
    appendInfoLine: "9  Odd-harmonic Fourier approximation of a square wave"
    appendInfoLine: "10 Shepard-Risset one-octave ascent cycle; loop for continuity"
    appendInfoLine: "11 Harmonic series with 1/n amplitudes"
    appendInfoLine: "12 Explicit quadratic nonlinearity generates combination tones"
    appendInfoLine: "13 Harmonic source shaped by three formant resonances"
    appendInfoLine: ""
    appendInfoLine: "MODULATION AND INTERFERENCE"
    appendInfoLine: "14 AM tremolo versus small-deviation FM vibrato"
    appendInfoLine: "15 Equal and opposite signals sum to zero"
    exitScript: ""
endif

# ----------------------------
# Global setup
# ----------------------------
if show_visualization
    Erase all
endif
if show_info_window
    clearinfo
endif
srate = 44100
nyquist = srate / 2
f_base = base_frequency_Hz
amp = amplitude
dur = duration_s
if amp > 0.95
    amp = 0.95
endif
if dur < 0.05
    exitScript: "Duration must be at least 0.05 s."
endif
if f_base >= nyquist * 0.9
    exitScript: "Base frequency is too close to Nyquist for these demonstrations."
endif

# House-style visualization globals
viz_window = min(0.04, dur)
viz_fmax = min(5000, nyquist)
proof_mode$ = "lissajous"
law1$ = ""
law2$ = ""
law3$ = ""
summary$ = ""
proof_f1 = 0
proof_f2 = 0
proof_f3 = 0
proof_f4 = 0
proof_n = 0

if show_info_window
    writeInfoLine: "=== Acoustic Pedagogy v0.5.1 ==="
    appendInfoLine: "Phenomenon: ", phenomenon
    appendInfoLine: "Duration: ", fixed$(dur, 2), " s | base: ", fixed$(f_base, 2), " Hz"
    appendInfoLine: ""
endif

# ============================================================
# PHENOMENA
# ============================================================

if phenomenon = 1
    f1 = f_base
    f2 = f_base * 3/2
    cents = 1200 * log2(f2 / f1)
    law1$ = "Pure fifth law: f2 / f1 = 3 / 2"
    law2$ = "Measured interval = " + fixed$(cents, 2) + " cents"
    law3$ = "Both tones are mixed to the same acoustic channel"
    summary$ = "3:2 fifth | " + fixed$(f1, 1) + " Hz + " + fixed$(f2, 1) + " Hz | ratio " + fixed$(f2/f1, 4)
    proof_mode$ = "lissajous"
    @pair_demo: f1, f2, dur, amp, "Just Intonation - Pure 3:2 Fifth", "sameear"

elsif phenomenon = 2
    comma = (1.5 ^ 12) / (2 ^ 7)
    f1 = f_base
    f2 = f_base * comma
    comma_cents = 1200 * log2(comma)
    beat = abs(f2 - f1)
    law1$ = "Pythagorean comma = (3/2)^12 / 2^7"
    law2$ = "Closure error = " + fixed$(comma_cents, 2) + " cents"
    law3$ = "Same-ear sum exposes the slow beat at " + fixed$(beat, 2) + " Hz"
    summary$ = "Pythagorean comma | " + fixed$(comma_cents, 2) + " cents | beat " + fixed$(beat, 2) + " Hz"
    proof_mode$ = "lissajous"
    @pair_demo: f1, f2, dur, amp, "Pythagorean Comma - Closure Error", "sameear"

elsif phenomenon = 3
    f1 = f_base * 5/4
    f2 = f_base * 81/64
    ratio = f2 / f1
    comma_cents = 1200 * log2(ratio)
    beat = abs(f2 - f1)
    law1$ = "Just M3 = 5/4; Pythagorean M3 = 81/64"
    law2$ = "Their ratio is 81/80 = " + fixed$(comma_cents, 2) + " cents"
    law3$ = "Same-ear mixture makes the tuning discrepancy audible"
    summary$ = "Syntonic comma | " + fixed$(comma_cents, 2) + " cents | beat " + fixed$(beat, 2) + " Hz"
    proof_mode$ = "lissajous"
    @pair_demo: f1, f2, dur, amp, "Syntonic Comma - 5:4 vs 81:64", "sameear"

elsif phenomenon = 4
    # Pythagorean wolf = pure fifth narrowed by the Pythagorean comma.
    pyth_comma = (1.5 ^ 12) / (2 ^ 7)
    pure_ratio = 3/2
    wolf_ratio = pure_ratio / pyth_comma
    pure_cents = 1200 * log2(pure_ratio)
    wolf_cents = 1200 * log2(wolf_ratio)
    law1$ = "Pure fifth = 3/2 = " + fixed$(pure_cents, 2) + " cents"
    law2$ = "Pythagorean wolf = (3/2) / comma = " + fixed$(wolf_cents, 2) + " cents"
    law3$ = "Harmonic-rich dyads expose beating partials"
    summary$ = "Pure fifth " + fixed$(pure_cents, 2) + " c | wolf " + fixed$(wolf_cents, 2) + " c | error " + fixed$(pure_cents-wolf_cents, 2) + " c"
    proof_mode$ = "wolf"
    proof_f1 = pure_cents
    proof_f2 = wolf_cents
    @wolf_demo: f_base, pure_ratio, wolf_ratio, dur, amp

elsif phenomenon = 5
    # Glasberg-Moore style ERB estimate; roughness maximum is not fixed in Hz.
    erb = 24.7 * (4.37 * f_base / 1000 + 1)
    separation = 0.25 * erb
    if f_base + separation >= nyquist
        separation = max(1, nyquist - f_base - 1)
    endif
    f1 = f_base
    f2 = f_base + separation
    law1$ = "ERB estimate = 24.7 * (4.37*f/1000 + 1)"
    law2$ = "Demo spacing = 0.25 ERB = " + fixed$(separation, 2) + " Hz"
    law3$ = "Same-ear routing; roughness varies with centre frequency"
    summary$ = "Critical-band roughness | ERB " + fixed$(erb, 1) + " Hz | spacing " + fixed$(separation, 1) + " Hz"
    proof_mode$ = "critical"
    proof_f1 = f_base
    proof_f2 = f2
    proof_f3 = erb
    @pair_demo: f1, f2, dur, amp, "Critical-Band Roughness", "sameear"

elsif phenomenon = 6
    f1 = 440
    f2 = 660
    f_diff = f2 - f1
    law1$ = "Physical source = sin(2*pi*f1*t) + sin(2*pi*f2*t)"
    law2$ = "No " + fixed$(f_diff, 0) + " Hz component is synthesized"
    law3$ = "Perceived difference tone can arise from auditory nonlinearity"
    summary$ = "Tartini difference tone | primaries 440 and 660 Hz | perceived candidate 220 Hz"
    proof_mode$ = "difference_absent"
    proof_f1 = f1
    proof_f2 = f2
    proof_f3 = f_diff
    viz_fmax = 900
    @pair_demo: f1, f2, dur, amp, "Tartini Difference Tone", "sameear"

elsif phenomenon = 7
    f0 = 220
    ampStr$ = string$(amp)
    Create Sound from formula: "MissingFundamental", 1, 0, dur, srate,
        ... ampStr$ + " * (sin(2*pi*660*x) + sin(2*pi*880*x) + sin(2*pi*1100*x))/3"
    id_complex = selected("Sound")
    Create Sound from formula: "Reference220", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*220*x)"
    id_ref = selected("Sound")
    law1$ = "Present partials: 3f0, 4f0, 5f0 = 660, 880, 1100 Hz"
    law2$ = "Fundamental f0 = 220 Hz is physically absent"
    law3$ = "Pitch can follow the missing 220-Hz periodicity"
    summary$ = "Missing fundamental | f0 220 Hz absent | harmonics 3, 4, 5 present"
    proof_mode$ = "missing"
    proof_f1 = 220
    proof_f2 = 660
    proof_f3 = 880
    proof_f4 = 1100
    viz_fmax = 1400
    if show_info_window
        appendInfoLine: "[7] Missing Fundamental: 660, 880, 1100 Hz; reference f0 = 220 Hz is absent from the complex."
    endif
    if show_visualization
        @draw_demo: id_complex, id_ref, 0, "Missing Fundamental", "complex", "220-Hz reference", ""
    endif
    selectObject: id_complex
    Play
    selectObject: id_ref
    Play
    if not save_sounds_to_list
        removeObject: id_complex, id_ref
    endif

elsif phenomenon = 8
    f1 = f_base
    f2 = f_base + 4
    law1$ = "Left ear receives fL; right ear receives fR"
    law2$ = "No 4-Hz acoustic amplitude beat exists in either channel"
    law3$ = "Percept comes from neural comparison across ears"
    summary$ = "Binaural beat | L " + fixed$(f1, 1) + " Hz | R " + fixed$(f2, 1) + " Hz | delta 4 Hz | headphones"
    proof_mode$ = "binaural"
    proof_f1 = f1
    proof_f2 = f2
    @pair_demo: f1, f2, dur, amp, "Binaural Beats - Headphones", "binaural"

elsif phenomenon = 9
    # Seven odd harmonics: 1,3,5,7,9,11,13 when Nyquist permits.
    max_terms = 7
    norm = 0
    n_used = 0
    for k from 1 to max_terms
        h = 2*k - 1
        if h * f_base < nyquist * 0.98
            norm = norm + 1/h
            n_used = n_used + 1
        endif
    endfor
    if n_used < 1
        exitScript: "Base frequency is too high for the square-wave demonstration."
    endif
    formula$ = "0"
    for k from 1 to max_terms
        h = 2*k - 1
        if h * f_base < nyquist * 0.98
            coeff = amp * (1/h) / norm
            formula$ = formula$ + " + " + string$(coeff) + "*sin(2*pi*" + string$(h*f_base) + "*x)"
        endif
    endfor
    Create Sound from formula: "SquareApprox", 1, 0, dur, srate, formula$
    id_square = selected("Sound")
    Create Sound from formula: "Fundamental", 1, 0, dur, srate,
        ... string$(amp) + "*sin(2*pi*" + string$(f_base) + "*x)"
    id_ref = selected("Sound")
    law1$ = "Square-wave Fourier law: odd harmonics only"
    law2$ = "Amplitude of harmonic n is proportional to 1/n"
    law3$ = string$(n_used) + " odd harmonics are below Nyquist in this run"
    summary$ = "Fourier square | f0 " + fixed$(f_base, 1) + " Hz | odd terms used " + string$(n_used)
    proof_mode$ = "square"
    proof_n = n_used
    viz_window = min(4/f_base, dur)
    viz_fmax = min((2*max_terms+1)*f_base, nyquist)
    if show_visualization
        @draw_demo: id_square, id_ref, 0, "Fourier Square-Wave Approximation", "odd-harmonic sum", "fundamental", ""
    endif
    selectObject: id_square
    Play
    if not save_sounds_to_list
        removeObject: id_square, id_ref
    endif

elsif phenomenon = 10
    # One Shepard-Risset ascent cycle: octave-spaced components rise one
    # octave over the duration while a fixed log-frequency envelope makes
    # components emerge and disappear. Looping the cycle extends the illusion.
    center_hz = max(440, f_base * 4)
    sigma_oct = 1.35
    formula$ = "0"
    n_comp = 0
    phase0 = 0
    have_previous = 0
    previous_fstart = 0
    for k from -4 to 4
        fstart = f_base * (2 ^ k)
        fend = 2 * fstart
        if fstart >= 20 and fend < nyquist * 0.98
            if have_previous
                phase0 = phase0 + 2*pi*previous_fstart*dur/ln(2)
                phase0 = phase0 - floor(phase0/(2*pi))*2*pi
            endif
            n_comp = n_comp + 1
            weight$ = "exp(-0.5*(log2((" + string$(fstart) + "*2^(x/" + string$(dur) + "))/" + string$(center_hz) + ")/" + string$(sigma_oct) + ")^2)"
            phase$ = "(" + string$(phase0) + "+" + string$(2*pi*fstart*dur/ln(2)) + "*(2^(x/" + string$(dur) + ")-1))"
            formula$ = formula$ + " + " + weight$ + "*sin(" + phase$ + ")"
            previous_fstart = fstart
            have_previous = 1
        endif
    endfor
    if n_comp < 2
        exitScript: "Base frequency leaves too few octave components for the Shepard demonstration."
    endif
    formula$ = "(" + string$(amp/n_comp) + ")*(" + formula$ + ")"
    Create Sound from formula: "ShepardRisset", 1, 0, dur, srate, formula$
    id_shepard = selected("Sound")
    Scale peak: amp
    Create Sound from formula: "Reference", 1, 0, dur, srate,
        ... string$(amp) + "*sin(2*pi*" + string$(f_base) + "*x)"
    id_ref = selected("Sound")
    law1$ = "Each component rises exponentially by exactly one octave"
    law2$ = "Octave components move through a fixed spectral envelope"
    law3$ = "Repeat or crossfade cycles to extend the ascent illusion"
    summary$ = "Shepard-Risset cycle | " + string$(n_comp) + " octave components | one octave per " + fixed$(dur, 2) + " s"
    proof_mode$ = "shepard"
    proof_n = n_comp
    viz_window = min(0.5, dur)
    viz_fmax = min(6000, nyquist)
    if show_visualization
        @draw_demo: id_shepard, id_ref, 0, "Shepard-Risset Cyclic Ascent", "Shepard-Risset", "reference", ""
    endif
    selectObject: id_shepard
    Play
    if not save_sounds_to_list
        removeObject: id_shepard, id_ref
    endif

elsif phenomenon = 11
    n_harm = floor((nyquist * 0.98) / f_base)
    if n_harm > 16
        n_harm = 16
    endif
    if n_harm < 1
        exitScript: "Base frequency is too high for the harmonic-series demonstration."
    endif
    norm = 0
    for i from 1 to n_harm
        norm = norm + 1/i
    endfor
    formula$ = "0"
    for i from 1 to n_harm
        coeff = amp * (1/i) / norm
        formula$ = formula$ + " + " + string$(coeff) + "*sin(2*pi*" + string$(f_base*i) + "*x)"
    endfor
    Create Sound from formula: "HarmonicSeries", 1, 0, dur, srate, formula$
    id_harm = selected("Sound")
    Create Sound from formula: "Fundamental", 1, 0, dur, srate,
        ... string$(amp) + "*sin(2*pi*" + string$(f_base) + "*x)"
    id_ref = selected("Sound")
    law1$ = "Harmonics occur at n*f0"
    law2$ = "Amplitude law in this demo: 1/n"
    law3$ = string$(n_harm) + " harmonics are rendered below Nyquist"
    summary$ = "Harmonic series | f0 " + fixed$(f_base, 1) + " Hz | harmonics " + string$(n_harm)
    proof_mode$ = "harmonic"
    proof_n = n_harm
    viz_window = min(4/f_base, dur)
    viz_fmax = min(f_base*n_harm*1.1, nyquist)
    if show_visualization
        @draw_demo: id_harm, id_ref, 0, "Harmonic Series", "harmonic sum", "fundamental", ""
    endif
    selectObject: id_harm
    Play
    if not save_sounds_to_list
        removeObject: id_harm, id_ref
    endif

elsif phenomenon = 12
    f1 = 400
    f2 = 600
    fdiff = f2 - f1
    fsum = f1 + f2
    a = amp * 0.35
    q = 0.60
    pair$ = "(sin(2*pi*400*x)+sin(2*pi*600*x))"
    Create Sound from formula: "LinearPrimaries", 1, 0, dur, srate,
        ... string$(a) + "*" + pair$
    id_linear = selected("Sound")
    Scale peak: amp
    Create Sound from formula: "NonlinearModel", 1, 0, dur, srate,
        ... string$(a) + "*" + pair$ + " + " + string$(q*a) + "*(" + pair$ + "^2-1)"
    id_nonlinear = selected("Sound")
    Scale peak: amp
    law1$ = "Model: y = a*x + q*a*(x^2 - mean(x^2))"
    law2$ = "Squaring creates f2-f1 and f1+f2 terms physically"
    law3$ = "Unlike Tartini, these extra components exist in the signal"
    summary$ = "Nonlinear combination tones | 400 and 600 Hz | generated 200 and 1000 Hz"
    proof_mode$ = "combination"
    proof_f1 = fdiff
    proof_f2 = f1
    proof_f3 = f2
    proof_f4 = fsum
    viz_fmax = 1300
    if show_visualization
        @draw_demo: id_linear, id_nonlinear, 0, "Nonlinear Combination Tones", "linear source", "nonlinear output", ""
    endif
    selectObject: id_linear
    Play
    selectObject: id_nonlinear
    Play
    if not save_sounds_to_list
        removeObject: id_linear, id_nonlinear
    endif

elsif phenomenon = 13
    f0 = f_base
    f_form1 = 700
    f_form2 = 1220
    f_form3 = 2600
    n_harm = floor((nyquist * 0.98) / f0)
    if n_harm > 40
        n_harm = 40
    endif
    if n_harm < 3
        exitScript: "Base frequency is too high for the formant demonstration."
    endif
    source$ = "0"
    vowel$ = "0"
    for i from 1 to n_harm
        freq = f0 * i
        source_coeff = 1/i
        w1 = exp(-((freq-f_form1)^2)/(2*100^2))
        w2 = 0.85*exp(-((freq-f_form2)^2)/(2*180^2))
        w3 = 0.55*exp(-((freq-f_form3)^2)/(2*280^2))
        weight = 0.03 + w1 + w2 + w3
        source$ = source$ + " + " + string$(source_coeff) + "*sin(2*pi*" + string$(freq) + "*x)"
        vowel$ = vowel$ + " + " + string$(source_coeff*weight) + "*sin(2*pi*" + string$(freq) + "*x)"
    endfor
    Create Sound from formula: "HarmonicSource", 1, 0, dur, srate, source$
    id_source = selected("Sound")
    Scale peak: amp
    Create Sound from formula: "VowelA", 1, 0, dur, srate, vowel$
    id_vowel = selected("Sound")
    Scale peak: amp
    law1$ = "Source-filter model: harmonic source at n*f0"
    law2$ = "Spectral envelope peaks near 700, 1220, and 2600 Hz"
    law3$ = "Harmonic frequencies stay fixed; amplitudes are reshaped"
    summary$ = "Formant synthesis /a/ | F1 700 | F2 1220 | F3 2600 Hz | f0 " + fixed$(f0, 1)
    proof_mode$ = "formant"
    proof_f1 = f_form1
    proof_f2 = f_form2
    proof_f3 = f_form3
    viz_window = min(4/f0, dur)
    viz_fmax = 4000
    if show_visualization
        @draw_demo: id_source, id_vowel, 0, "Formant Synthesis - Vowel /a/", "harmonic source", "formant-shaped", ""
    endif
    selectObject: id_source
    Play
    selectObject: id_vowel
    Play
    if not save_sounds_to_list
        removeObject: id_source, id_vowel
    endif

elsif phenomenon = 14
    f_carrier = f_base * 2
    if f_carrier >= nyquist * 0.9
        f_carrier = f_base
    endif
    f_mod = 5
    am_depth = 0.8
    beta = 1.0
    Create Sound from formula: "AM_Tremolo", 1, 0, dur, srate,
        ... string$(amp*0.55) + "*(1+" + string$(am_depth) + "*sin(2*pi*" + string$(f_mod) + "*x))*sin(2*pi*" + string$(f_carrier) + "*x)"
    id_am = selected("Sound")
    Create Sound from formula: "FM_Vibrato", 1, 0, dur, srate,
        ... string$(amp*0.95) + "*sin(2*pi*" + string$(f_carrier) + "*x+" + string$(beta) + "*sin(2*pi*" + string$(f_mod) + "*x))"
    id_fm = selected("Sound")
    law1$ = "AM: amplitude(t) = 1 + 0.8*sin(2*pi*5*t)"
    law2$ = "FM: phase index beta = 1; deviation beta*fm = +/-5 Hz"
    law3$ = "AM changes level; small FM changes instantaneous pitch"
    summary$ = "AM vs FM | carrier " + fixed$(f_carrier, 1) + " Hz | modulator 5 Hz | FM deviation +/-5 Hz"
    proof_mode$ = "modulation"
    proof_f1 = f_carrier
    proof_f2 = f_mod
    viz_window = min(0.45, dur)
    viz_fmax = min(f_carrier + 80, nyquist)
    if show_visualization
        @draw_demo: id_am, id_fm, 0, "AM Tremolo vs FM Vibrato", "AM", "FM", ""
    endif
    selectObject: id_am
    Play
    selectObject: id_fm
    Play
    if not save_sounds_to_list
        removeObject: id_am, id_fm
    endif

elsif phenomenon = 15
    f1 = f_base
    Create Sound from formula: "InPhase", 1, 0, dur, srate,
        ... string$(amp) + "*sin(2*pi*" + string$(f1) + "*x)"
    id_in = selected("Sound")
    Create Sound from formula: "Inverted180", 1, 0, dur, srate,
        ... "-" + string$(amp) + "*sin(2*pi*" + string$(f1) + "*x)"
    id_out = selected("Sound")
    selectObject: id_in
    id_sum = Copy: "Sum"
    Formula: "self + object[" + string$(id_out) + ", col]"
    law1$ = "x2(t) = -x1(t)"
    law2$ = "sum(t) = x1(t) + x2(t) = 0"
    law3$ = "Needs equal amplitude and exact 180-deg phase"
    summary$ = "Phase cancellation | " + fixed$(f1, 1) + " Hz | 180-deg inversion | theoretical sum zero"
    proof_mode$ = "cancellation"
    proof_f1 = f1
    viz_window = min(4/f1, dur)
    viz_fmax = min(f1*4, nyquist)
    if show_visualization
        @draw_demo: id_in, id_out, id_sum, "Phase Cancellation", "normal", "inverted", "sum"
    endif
    selectObject: id_in
    Play
    selectObject: id_out
    Play
    selectObject: id_sum
    Play
    if not save_sounds_to_list
        removeObject: id_in, id_out, id_sum
    endif

else
    exitScript: "Invalid phenomenon selection."
endif

if show_info_window
    appendInfoLine: ""
    appendInfoLine: "=== Demonstration Complete ==="
endif

# ============================================================
# PROCEDURES
# ============================================================

procedure pair_demo: .f1, .f2, .dur, .amp, .title$, .mode$
    if .mode$ = "binaural"
        .toneAmp = .amp
    else
        .toneAmp = .amp / 2
    endif
    Create Sound from formula: "Tone_A", 1, 0, .dur, srate,
        ... string$(.toneAmp) + "*sin(2*pi*" + string$(.f1) + "*x)"
    .idA = selected("Sound")
    Create Sound from formula: "Tone_B", 1, 0, .dur, srate,
        ... string$(.toneAmp) + "*sin(2*pi*" + string$(.f2) + "*x)"
    .idB = selected("Sound")

    if .mode$ = "binaural"
        selectObject: .idA
        plusObject: .idB
        .playID = Combine to stereo
        Rename: "Binaural_LR"
        .mixID = 0
    else
        selectObject: .idA
        .mixID = Copy: "SameEar_Mix"
        Formula: "self + object[" + string$(.idB) + ", col]"
        .playID = .mixID
    endif

    if show_info_window
        appendInfoLine: .title$
        appendInfoLine: "  f1 = ", fixed$(.f1, 3), " Hz"
        appendInfoLine: "  f2 = ", fixed$(.f2, 3), " Hz"
        appendInfoLine: "  delta = ", fixed$(abs(.f2-.f1), 3), " Hz"
        if .mode$ = "binaural"
            appendInfoLine: "  routing = separate ears (stereo)"
        else
            appendInfoLine: "  routing = same-ear centred mixture"
        endif
    endif

    if show_visualization
        if .mode$ = "binaural"
            @draw_demo: .idA, .idB, 0, .title$, "left ear", "right ear", ""
        else
            @draw_demo: .idA, .idB, .mixID, .title$, "tone A", "tone B", "same-ear mix"
        endif
    endif

    selectObject: .playID
    Play

    if not save_sounds_to_list
        if .mode$ = "binaural"
            removeObject: .idA, .idB, .playID
        else
            removeObject: .idA, .idB, .mixID
        endif
    endif
endproc

procedure wolf_demo: .root, .pureRatio, .wolfRatio, .dur, .amp
    .nH = 8
    .norm = 0
    for .i from 1 to .nH
        .norm = .norm + 1/.i
    endfor
    .pure$ = "0"
    .wolf$ = "0"
    for .i from 1 to .nH
        .fr1 = .root * .i
        .frPure = .root * .pureRatio * .i
        .frWolf = .root * .wolfRatio * .i
        .c = .amp * (1/.i) / (2*.norm)
        if .fr1 < nyquist*0.98
            .pure$ = .pure$ + " + " + string$(.c) + "*sin(2*pi*" + string$(.fr1) + "*x)"
            .wolf$ = .wolf$ + " + " + string$(.c) + "*sin(2*pi*" + string$(.fr1) + "*x)"
        endif
        if .frPure < nyquist*0.98
            .pure$ = .pure$ + " + " + string$(.c) + "*sin(2*pi*" + string$(.frPure) + "*x)"
        endif
        if .frWolf < nyquist*0.98
            .wolf$ = .wolf$ + " + " + string$(.c) + "*sin(2*pi*" + string$(.frWolf) + "*x)"
        endif
    endfor
    Create Sound from formula: "PureFifth_Dyad", 1, 0, .dur, srate, .pure$
    .idPure = selected("Sound")
    Create Sound from formula: "WolfFifth_Dyad", 1, 0, .dur, srate, .wolf$
    .idWolf = selected("Sound")
    viz_window = min(0.08, dur)
    viz_fmax = min(.root*8, nyquist)
    if show_visualization
        @draw_demo: .idPure, .idWolf, 0, "Pythagorean Wolf Fifth", "pure fifth", "wolf fifth", ""
    endif
    if show_info_window
        appendInfoLine: "[4] Pure fifth then Pythagorean wolf fifth."
        appendInfoLine: "  pure ratio = ", fixed$(.pureRatio, 6)
        appendInfoLine: "  wolf ratio = ", fixed$(.wolfRatio, 6)
    endif
    selectObject: .idPure
    Play
    selectObject: .idWolf
    Play
    if not save_sounds_to_list
        removeObject: .idPure, .idWolf
    endif
endproc

procedure draw_demo: .id1, .id2, .id3, .title$, .label1$, .label2$, .label3$
    Erase all

    # ----- Title strip -----
    Select outer viewport: 0, 8, 0.00, 0.42
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.56, "half", .title$

    Select outer viewport: 0.25, 7.75, 0.44, 0.76
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.55, "half", "Acoustic Pedagogy v0.5.1 | measured sound + explicit acoustic law"

    # ----- A: time domain -----
    # Dedicated title and legend strips prevent overlap with the plot.
    Select outer viewport: 0.25, 3.88, 0.90, 1.12
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.52, "half", "A  TIME DOMAIN"

    Select outer viewport: 0.25, 3.88, 1.12, 1.31
    Axes: 0, 1, 0, 1
    Font size: 5
    Colour: "{0.20,0.45,0.75}"
    Draw line: 0.05, 0.50, 0.09, 0.50
    Colour: "Black"
    Text: 0.10, "left", 0.50, "half", .label1$
    Colour: "{0.80,0.35,0.25}"
    Draw line: 0.38, 0.50, 0.42, 0.50
    Colour: "Black"
    Text: 0.43, "left", 0.50, "half", .label2$
    if .id3 <> 0
        Colour: "{0.15,0.15,0.15}"
        Draw line: 0.70, 0.50, 0.74, 0.50
        Colour: "Black"
        Text: 0.75, "left", 0.50, "half", .label3$
    endif
    Select inner viewport: 0.58, 3.72, 1.36, 2.55
    selectObject: .id1
    Colour: "{0.20,0.45,0.75}"
    Draw: 0, viz_window, -1, 1, "no", "Curve"
    selectObject: .id2
    Colour: "{0.80,0.35,0.25}"
    Draw: 0, viz_window, -1, 1, "no", "Curve"
    if .id3 <> 0
        selectObject: .id3
        Colour: "{0.15,0.15,0.15}"
        Line width: 1.3
        Draw: 0, viz_window, -1, 1, "no", "Curve"
        Line width: 1
    endif
    Select inner viewport: 0.58, 3.72, 1.36, 2.55
    Axes: 0, viz_window, -1, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"

    # ----- B: measured spectrum -----
    Select outer viewport: 4.12, 7.75, 0.90, 1.12
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.52, "half", "B  MEASURED SPECTRUM"
    Select inner viewport: 4.48, 7.58, 1.36, 2.55
    selectObject: .id1
    To Spectrum: "yes"
    .sp1 = selected("Spectrum")
    Colour: "{0.20,0.45,0.75}"
    Draw: 0, viz_fmax, 0, 100, "no"
    selectObject: .id2
    To Spectrum: "yes"
    .sp2 = selected("Spectrum")
    Colour: "{0.80,0.35,0.25}"
    Draw: 0, viz_fmax, 0, 100, "no"
    .sp3 = 0
    if .id3 <> 0
        selectObject: .id3
        .nch = Get number of channels
        if .nch > 1
            .tmpMono = Convert to mono
        else
            .tmpMono = Copy: "viz_mono"
        endif
        To Spectrum: "yes"
        .sp3 = selected("Spectrum")
        Colour: "{0.15,0.15,0.15}"
        Line width: 1.3
        Draw: 0, viz_fmax, 0, 100, "no"
        Line width: 1
        removeObject: .tmpMono
    endif
    Select inner viewport: 4.48, 7.58, 1.36, 2.55
    Axes: 0, viz_fmax, 0, 100
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Level (dB)"

    # ----- C: mechanism -----
    Select outer viewport: 0.25, 3.88, 2.95, 3.18
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 9
    Text: 0.02, "left", 0.52, "half", "C  MECHANISM"

    Select outer viewport: 0.25, 3.88, 3.18, 4.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96,0.96,0.96}", 0, 1, 0, 1
    Colour: "Black"
    Font size: 7
    Text: 0.06, "left", 0.76, "half", law1$
    Text: 0.06, "left", 0.50, "half", law2$
    Text: 0.06, "left", 0.24, "half", law3$
    Colour: "{0.75,0.75,0.75}"
    Draw rectangle: 0, 1, 0, 1

    # ----- D: phenomenon-specific proof -----
    Select outer viewport: 4.12, 7.75, 2.95, 3.18
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Font size: 9
    Text: 0.02, "left", 0.52, "half", "D  PROOF"
    @draw_proof: .id1, .id2, .id3

    # ----- Summary bar -----
    Select outer viewport: 0.35, 7.65, 4.88, 5.42
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95,0.95,0.95}", 0, 1, 0.10, 0.90
    Colour: "{0.20,0.20,0.20}"
    Font size: 7
    Text: 0.5, "centre", 0.50, "half", summary$

    # Cleanup spectra
    if .sp3 <> 0
        removeObject: .sp1, .sp2, .sp3
    else
        removeObject: .sp1, .sp2
    endif
    Font size: 10
    Colour: "Black"
endproc

procedure draw_proof: .id1, .id2, .id3
    if proof_mode$ = "lissajous"
        Select inner viewport: 4.50, 7.55, 3.28, 4.52
        selectObject: .id1
        .d1 = Get total duration
        .ld = min(0.08, .d1)
        Extract part: 0, .ld, "rectangular", 1, "no"
        .e1 = selected("Sound")
        selectObject: .id2
        Extract part: 0, .ld, "rectangular", 1, "no"
        .e2 = selected("Sound")
        selectObject: .e1
        plusObject: .e2
        To ParamCurve
        .pc = selected("ParamCurve")
        Colour: "{0.25,0.55,0.45}"
        Draw: 0, 0, 0, 0, 0, 0, 0, "no"
        Select inner viewport: 4.50, 7.55, 3.28, 4.52
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Tone A"
        Text left: "yes", "Tone B"
        removeObject: .e1, .e2, .pc

    elsif proof_mode$ = "wolf"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 665, 710, 0, 1
        Colour: "{0.85,0.85,0.85}"
        Draw line: 665, 0.5, 710, 0.5
        Colour: "{0.20,0.45,0.75}"
        Line width: 1.5
        Draw line: proof_f1, 0.18, proof_f1, 0.82
        Colour: "{0.80,0.35,0.25}"
        Draw line: proof_f2, 0.18, proof_f2, 0.82
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Interval size (cents)"
        Text: proof_f1, "centre", 0.88, "half", "pure"
        Text: proof_f2, "centre", 0.10, "half", "wolf"

    elsif proof_mode$ = "critical"
        .lo = proof_f1 - proof_f3/2
        .hi = proof_f1 + proof_f3/2
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: .lo, .hi, 0, 1
        Paint rectangle: "{0.92,0.92,0.92}", .lo, .hi, 0.25, 0.75
        Colour: "{0.20,0.45,0.75}"
        Draw line: proof_f1, 0.18, proof_f1, 0.82
        Colour: "{0.80,0.35,0.25}"
        Draw line: proof_f2, 0.18, proof_f2, 0.82
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Frequency (Hz)"
        Text: (.lo+.hi)/2, "centre", 0.90, "half", "one ERB"

    elsif proof_mode$ = "difference_absent"
        .mx = max(proof_f2*1.25, proof_f3*1.5)
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, .mx, 0, 1
        Colour: "{0.85,0.85,0.85}"
        Draw line: 0, 0.5, .mx, 0.5
        Colour: "{0.80,0.35,0.25}"
        Line width: 1.5
        Draw line: proof_f3, 0.18, proof_f3, 0.82
        Colour: "{0.20,0.45,0.75}"
        Draw line: proof_f1, 0.18, proof_f1, 0.82
        Draw line: proof_f2, 0.18, proof_f2, 0.82
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Frequency (Hz)"
        Text: proof_f3, "centre", 0.10, "half", "perceived; absent"
        Text: (proof_f1+proof_f2)/2, "centre", 0.90, "half", "physical primaries"

    elsif proof_mode$ = "missing"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, proof_f4*1.2, 0, 1
        Colour: "{0.85,0.85,0.85}"
        Draw line: 0, 0.5, proof_f4*1.2, 0.5
        Colour: "{0.80,0.35,0.25}"
        Draw line: proof_f1, 0.18, proof_f1, 0.82
        Colour: "{0.20,0.45,0.75}"
        Draw line: proof_f2, 0.18, proof_f2, 0.82
        Draw line: proof_f3, 0.18, proof_f3, 0.82
        Draw line: proof_f4, 0.18, proof_f4, 0.82
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Frequency (Hz)"
        Text: proof_f1, "centre", 0.10, "half", "missing f0"
        Text: proof_f3, "centre", 0.90, "half", "3f0  4f0  5f0"

    elsif proof_mode$ = "binaural"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        .lo = min(proof_f1,proof_f2) - 8
        .hi = max(proof_f1,proof_f2) + 8
        Axes: .lo, .hi, 0, 2
        Colour: "{0.20,0.45,0.75}"
        Draw line: proof_f1, 1.10, proof_f1, 1.80
        Colour: "{0.80,0.35,0.25}"
        Draw line: proof_f2, 0.20, proof_f2, 0.90
        Colour: "Black"
        Font size: 6
        Text: .lo, "left", 1.45, "half", "Left ear"
        Text: .lo, "left", 0.55, "half", "Right ear"
        Text: (.lo+.hi)/2, "centre", 1.95, "top", "delta f = " + fixed$(abs(proof_f2-proof_f1),1) + " Hz"
        Draw inner box
        Text bottom: "yes", "Frequency (Hz)"

    elsif proof_mode$ = "square"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, 2*proof_n+1, 0, 1.05
        Colour: "{0.20,0.45,0.75}"
        for .k from 1 to proof_n
            .h = 2*.k - 1
            Draw line: .h, 0, .h, 1/.h
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Harmonic number"
        Text left: "yes", "1/n"

    elsif proof_mode$ = "shepard"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, dur, 0, 8
        Colour: "{0.20,0.45,0.75}"
        for .k from 0 to 6
            Draw line: 0, .k+0.25, dur, .k+1.25
        endfor
        Colour: "{0.85,0.85,0.85}"
        Draw line: 0, 4, dur, 4
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Octave position"

    elsif proof_mode$ = "harmonic"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, proof_n+1, 0, 1.05
        Colour: "{0.20,0.45,0.75}"
        for .i from 1 to proof_n
            Draw line: .i, 0, .i, 1/.i
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Harmonic number"
        Text left: "yes", "Relative amplitude"

    elsif proof_mode$ = "combination"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, proof_f4*1.15, 0, 1
        Colour: "{0.85,0.85,0.85}"
        Draw line: 0, 0.5, proof_f4*1.15, 0.5
        Colour: "{0.80,0.35,0.25}"
        Draw line: proof_f1, 0.18, proof_f1, 0.82
        Draw line: proof_f4, 0.18, proof_f4, 0.82
        Colour: "{0.20,0.45,0.75}"
        Draw line: proof_f2, 0.18, proof_f2, 0.82
        Draw line: proof_f3, 0.18, proof_f3, 0.82
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Frequency (Hz)"
        Text: proof_f1, "centre", 0.10, "half", "difference"
        Text: proof_f4, "centre", 0.10, "half", "sum"
        Text: (proof_f2+proof_f3)/2, "centre", 0.90, "half", "primaries"

    elsif proof_mode$ = "formant"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, 4000, 0, 1.15
        Colour: "{0.20,0.45,0.75}"
        .nP = 240
        for .i from 1 to .nP
            .f = (.i-1)/(.nP-1)*4000
            .v = 0.03 + exp(-((.f-proof_f1)^2)/(2*100^2)) + 0.85*exp(-((.f-proof_f2)^2)/(2*180^2)) + 0.55*exp(-((.f-proof_f3)^2)/(2*280^2))
            .v = min(.v,1.15)
            if .i > 1
                Draw line: .pf, .pv, .f, .v
            endif
            .pf = .f
            .pv = .v
        endfor
        Colour: "{0.75,0.75,0.75}"
        Draw line: proof_f1, 0, proof_f1, 1.15
        Draw line: proof_f2, 0, proof_f2, 1.15
        Draw line: proof_f3, 0, proof_f3, 1.15
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Frequency (Hz)"
        Text left: "yes", "Envelope"

    elsif proof_mode$ = "modulation"
        .tmax = min(0.5,dur)
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, .tmax, -1.1, 1.1
        Colour: "{0.20,0.45,0.75}"
        .nP = 200
        for .i from 1 to .nP
            .t = (.i-1)/(.nP-1)*.tmax
            .am = 0.8*sin(2*pi*proof_f2*.t)
            .fm = cos(2*pi*proof_f2*.t)
            if .i > 1
                Draw line: .pt, .pam, .t, .am
            endif
            .pt = .t
            .pam = .am
        endfor
        Colour: "{0.80,0.35,0.25}"
        for .i from 1 to .nP
            .t = (.i-1)/(.nP-1)*.tmax
            .fm = cos(2*pi*proof_f2*.t)
            if .i > 1
                Draw line: .pt2, .pfm, .t, .fm
            endif
            .pt2 = .t
            .pfm = .fm
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Normalized modulation"

    elsif proof_mode$ = "cancellation"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        selectObject: .id3
        Colour: "{0.15,0.15,0.15}"
        Draw: 0, viz_window, -0.05, 0.05, "no", "Curve"
        Select inner viewport: 4.50, 7.55, 3.30, 4.50
        Axes: 0, viz_window, -0.05, 0.05
        Colour: "Black"
        Draw inner box
        Font size: 6
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Sum"
    endif
endproc
