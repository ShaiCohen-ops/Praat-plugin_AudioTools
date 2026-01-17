# ============================================================
# Praat AudioTools - Acoustic Pedagogy.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed and enhanced
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Acoustic Pedagogy - 15 interactive acoustic demonstrations
#   for teaching psychoacoustics and musical acoustics.
#
# Usage:
#   Run this script and select a phenomenon from the menu.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed procedure call syntax (call -> @)
#   - Fixed string interpolation issues
#   - Fixed procedure variable scope
#   - Replaced printline with appendInfoLine
#   - Improved visualization labels
#   - Added phenomenon descriptions to form
# ============================================================

form Acoustic Pedagogy v0.2
    comment === SELECT PHENOMENON ===
    optionmenu Phenomenon: 1
        option 1. Just Intonation (Perfect Fifth)
        option 2. Pythagorean Comma
        option 3. Syntonic Comma
        option 4. The Wolf Fifth
        option 5. Critical Bands (Roughness)
        option 6. Tartini Tones (Difference Tone)
        option 7. Missing Fundamental (Phantom)
        option 8. Binaural Beats (Headphones!)
        option 9. Fourier Square Wave
        option 10. Shepard Tone (Infinite Ascent)
        option 11. Harmonic Series
        option 12. Combination Tones
        option 13. Formant Synthesis (Vowels)
        option 14. AM vs FM Modulation
        option 15. Phase Cancellation
    comment === PLAYBACK CONTROLS ===
    real Duration_s 2.0
    real Base_frequency_Hz 220
    positive Amplitude 0.5
    comment === OPTIONS ===
    boolean Show_info_window 1
    boolean Save_sounds_to_list 0
    boolean Show_help 0
endform

# --- Help Logic ---
if show_help
    clearinfo
    appendInfoLine: "========================================"
    appendInfoLine: "   ACOUSTIC PEDAGOGY - HELP MANUAL"
    appendInfoLine: "========================================"
    appendInfoLine: ""
    appendInfoLine: "This script provides 15 interactive acoustic demonstrations."
    appendInfoLine: ""
    appendInfoLine: "--- TUNING & INTERVALS ---"
    appendInfoLine: "1. Just Intonation: Pure 3:2 ratio perfect fifth"
    appendInfoLine: "2. Pythagorean Comma: 12 fifths vs 7 octaves (~23.5 cents)"
    appendInfoLine: "3. Syntonic Comma: Just vs Pythagorean major third"
    appendInfoLine: "4. Wolf Fifth: Impure fifth that 'howls'"
    appendInfoLine: ""
    appendInfoLine: "--- PSYCHOACOUSTICS ---"
    appendInfoLine: "5. Critical Bands: Maximum roughness demo"
    appendInfoLine: "6. Tartini Tones: Difference tone perception"
    appendInfoLine: "7. Missing Fundamental: Phantom pitch"
    appendInfoLine: "8. Binaural Beats: REQUIRES HEADPHONES"
    appendInfoLine: ""
    appendInfoLine: "--- SYNTHESIS & TIMBRE ---"
    appendInfoLine: "9. Fourier Square Wave: Odd harmonic synthesis"
    appendInfoLine: "10. Shepard Tone: Infinite pitch ascent illusion"
    appendInfoLine: "11. Harmonic Series: Natural overtone series"
    appendInfoLine: "12. Combination Tones: Sum/difference tones"
    appendInfoLine: "13. Formant Synthesis: Vowel /a/ simulation"
    appendInfoLine: ""
    appendInfoLine: "--- MODULATION ---"
    appendInfoLine: "14. AM vs FM: Tremolo vs Vibrato"
    appendInfoLine: "15. Phase Cancellation: Destructive interference"
    appendInfoLine: ""
    appendInfoLine: "Uncheck 'Show help' and run again to use."
    exitScript: ""
endif

# --- Setup ---
Erase all
clearinfo

srate = 44100
f_base = base_frequency_Hz
amp = amplitude
dur = duration_s

writeInfoLine: "=== Acoustic Pedagogy v0.2 ==="
appendInfoLine: ""

# ==========================================
# MAIN LOGIC - PHENOMENON SELECTION
# ==========================================

if phenomenon = 1
    # === Just Intonation (Perfect Fifth) ===
    appendInfoLine: "[1] Just Intonation - Perfect Fifth"
    f1 = f_base
    f2 = f_base * 3/2
    @show_info: "Just Intonation (Perfect Fifth)", f1, f2
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Just Fifth (3:2 ratio) - Perfect Consonance"

elsif phenomenon = 2
    # === Pythagorean Comma ===
    appendInfoLine: "[2] Pythagorean Comma"
    f1 = f_base
    f2 = f_base * ((1.5 ^ 12) / (2 ^ 7))
    @show_info: "Pythagorean Comma", f1, f2
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Pythagorean Comma - 12 fifths vs 7 octaves (~23.5 cents)"

elsif phenomenon = 3
    # === Syntonic Comma ===
    appendInfoLine: "[3] Syntonic Comma"
    f1 = f_base * 5/4
    f2 = f_base * 81/64
    @show_info: "Syntonic Comma (Didymus)", f1, f2
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Syntonic Comma - Just M3 vs Pythagorean M3 (~21.5 cents)"

elsif phenomenon = 4
    # === Wolf Fifth ===
    appendInfoLine: "[4] The Wolf Fifth"
    f1 = f_base * 1.5
    f2 = f_base * 1.5 / (81/80)
    @show_info: "Wolf Fifth", f1, f2
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Wolf Fifth - Impure fifth that howls with beats"

elsif phenomenon = 5
    # === Critical Bands ===
    appendInfoLine: "[5] Critical Bands - Roughness"
    f1 = f_base
    f2 = f_base + 25
    @show_info: "Critical Band Roughness", f1, f2
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Critical Band - Maximum roughness at ~25Hz separation"

elsif phenomenon = 6
    # === Tartini Tones (Difference Tones) ===
    appendInfoLine: "[6] Tartini Tones"
    f1 = 440
    f2 = 660
    f_diff = f2 - f1
    @show_info: "Tartini Tones (Difference: " + string$(f_diff) + "Hz)", f1, f2
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Tartini: " + string$(f1) + "Hz + " + string$(f2) + "Hz -> Hear " + string$(f_diff) + "Hz"

elsif phenomenon = 7
    # === Missing Fundamental ===
    appendInfoLine: "[7] Missing Fundamental"
    
    ampStr$ = string$(amp)
    Create Sound from formula: "Complex", 1, 0, dur, srate,
        ... ampStr$ + " * (sin(2*pi*660*x) + sin(2*pi*880*x) + sin(2*pi*1100*x))/3"
    id_complex = selected("Sound")
    
    Create Sound from formula: "Ghost", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*220*x)/2"
    id_ghost = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Missing Fundamental (Phantom Pitch) ==="
        appendInfoLine: "Harmonics present: 660, 880, 1100 Hz"
        appendInfoLine: "These are harmonics 3, 4, 5 of 220Hz"
        appendInfoLine: "Brain perceives: 220Hz (NOT present in signal!)"
        appendInfoLine: ""
    endif
    
    selectObject: id_complex, id_ghost
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "Missing Fundamental - Complex vs Ghost 220Hz"
    
    selectObject: id_complex
    Play
    
    if not save_sounds_to_list
        selectObject: id_complex, id_ghost, id_param
        Remove
    endif

elsif phenomenon = 8
    # === Binaural Beats ===
    appendInfoLine: "[8] Binaural Beats (USE HEADPHONES!)"
    f_left = f_base
    f_right = f_base + 4
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Binaural Beats (STEREO - USE HEADPHONES) ==="
        appendInfoLine: "Left ear: ", fixed$(f_left, 2), " Hz"
        appendInfoLine: "Right ear: ", fixed$(f_right, 2), " Hz"
        appendInfoLine: "Beat frequency: ", fixed$(f_right - f_left, 2), " Hz"
        appendInfoLine: "Brain perceives: Rotating phantom beat"
        appendInfoLine: ""
    endif
    
    @create_and_play: f_left, f_right, dur, amp
    Text top: "no", "Binaural Beats - L=" + string$(f_left) + "Hz, R=" + string$(f_right) + "Hz (Headphones!)"

elsif phenomenon = 9
    # === Fourier Square Wave ===
    appendInfoLine: "[9] Fourier Synthesis - Square Wave"
    n_harmonics = 7
    
    ampStr$ = string$(amp)
    f_baseStr$ = string$(f_base)
    
    formula$ = ampStr$ + " * ("
    firstTerm = 1
    for i from 1 to n_harmonics
        if i mod 2 = 1
            if firstTerm = 0
                formula$ = formula$ + " + "
            endif
            firstTerm = 0
            formula$ = formula$ + "(1/" + string$(i) + ")*sin(2*pi*" + string$(i * f_base) + "*x)"
        endif
    endfor
    formula$ = formula$ + ")"
    
    Create Sound from formula: "Sine", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*" + f_baseStr$ + "*x)/2"
    id_sine = selected("Sound")
    
    Create Sound from formula: "Square_Approx", 1, 0, dur, srate, formula$
    id_square = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Fourier Synthesis - Square Wave ==="
        appendInfoLine: "Fundamental: ", f_base, " Hz"
        appendInfoLine: "Harmonics: Odd only (1, 3, 5, 7...)"
        appendInfoLine: "Amplitudes: 1/n (1, 1/3, 1/5, 1/7...)"
        appendInfoLine: "Sum approximates square wave"
        appendInfoLine: ""
    endif
    
    selectObject: id_sine, id_square
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "Timbre: Pure Sine vs Square Wave Approximation"
    
    selectObject: id_square
    Play
    
    if not save_sounds_to_list
        selectObject: id_sine, id_square, id_param
        Remove
    endif

elsif phenomenon = 10
    # === Shepard Tone (Infinite Ascent) ===
    appendInfoLine: "[10] Shepard Tone - Infinite Ascent"
    n_octaves = 6
    
    formula$ = "0"
    for octave from 1 to n_octaves
        freq = f_base * (2 ^ (octave - 3))
        octave_center = (n_octaves + 1) / 2
        envelope = exp(-((octave - octave_center)^2) / 2)
        formula$ = formula$ + " + " + string$(envelope * amp / n_octaves) + 
            ... "*sin(2*pi*" + string$(freq) + "*(1 + 0.5*x/" + string$(dur) + ")*x)"
    endfor
    
    Create Sound from formula: "Shepard", 1, 0, dur, srate, formula$
    id_shepard = selected("Sound")
    
    ampStr$ = string$(amp)
    f_baseStr$ = string$(f_base)
    Create Sound from formula: "Reference", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*" + f_baseStr$ + "*x)/2"
    id_ref = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Shepard Tone - Auditory Illusion ==="
        appendInfoLine: "Multiple octaves rising simultaneously"
        appendInfoLine: "Gaussian envelope fades in/out each octave"
        appendInfoLine: "Pitch seems to rise forever!"
        appendInfoLine: ""
    endif
    
    selectObject: id_shepard, id_ref
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "Shepard Tone - Endless Rising Pitch Illusion"
    
    selectObject: id_shepard
    Play
    
    if not save_sounds_to_list
        selectObject: id_shepard, id_ref, id_param
        Remove
    endif

elsif phenomenon = 11
    # === Harmonic Series ===
    appendInfoLine: "[11] Harmonic Series"
    n_harmonics = 16
    
    formula$ = "0"
    for i from 1 to n_harmonics
        formula$ = formula$ + " + (" + string$(amp) + "/" + string$(i) + ")*sin(2*pi*" + 
            ... string$(f_base * i) + "*x)"
    endfor
    
    Create Sound from formula: "Harmonics", 1, 0, dur, srate, formula$
    id_harm = selected("Sound")
    Scale intensity: 70
    
    ampStr$ = string$(amp)
    f_baseStr$ = string$(f_base)
    Create Sound from formula: "Fundamental", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*" + f_baseStr$ + "*x)/2"
    id_fund = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Harmonic Series ==="
        appendInfoLine: "Fundamental: ", f_base, " Hz"
        appendInfoLine: "Harmonics: f, 2f, 3f, 4f, 5f..."
        appendInfoLine: "Amplitudes: 1, 1/2, 1/3, 1/4, 1/5..."
        appendInfoLine: "This creates a sawtooth-like timbre"
        appendInfoLine: ""
        appendInfoLine: "Frequencies present:"
        for i from 1 to 8
            appendInfoLine: "  H", i, ": ", fixed$(f_base * i, 1), " Hz"
        endfor
    endif
    
    selectObject: id_harm, id_fund
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "Harmonic Series vs Pure Fundamental"
    
    selectObject: id_harm
    Play
    
    if not save_sounds_to_list
        selectObject: id_harm, id_fund, id_param
        Remove
    endif

elsif phenomenon = 12
    # === Combination Tones (Sum and Difference) ===
    appendInfoLine: "[12] Combination Tones"
    f1 = 400
    f2 = 600
    f_diff = f2 - f1
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Combination Tones ==="
        appendInfoLine: "Primary tones: ", f1, "Hz + ", f2, "Hz"
        appendInfoLine: "Difference tone: ", f_diff, "Hz (you may hear this)"
        appendInfoLine: "Created by nonlinear distortion in ear"
        appendInfoLine: ""
    endif
    
    @create_and_play: f1, f2, dur, amp
    Text top: "no", "Combination Tones: " + string$(f1) + "Hz + " + string$(f2) + "Hz -> hear " + string$(f_diff) + "Hz"

elsif phenomenon = 13
    # === Formant Synthesis (Vowels) ===
    appendInfoLine: "[13] Formant Synthesis - Vowel /a/"
    f0 = f_base
    f1_formant = 700
    f2_formant = 1220
    f3_formant = 2600
    
    n_harmonics = 40
    formula$ = "0"
    for i from 1 to n_harmonics
        freq = f0 * i
        amp1 = exp(-((freq - f1_formant)^2) / (2 * 100^2))
        amp2 = exp(-((freq - f2_formant)^2) / (2 * 200^2))
        amp3 = exp(-((freq - f3_formant)^2) / (2 * 300^2))
        total_amp = amp1 + amp2 + amp3
        formula$ = formula$ + " + (" + string$(total_amp * amp / n_harmonics) + 
            ... ")*sin(2*pi*" + string$(freq) + "*x)"
    endfor
    
    Create Sound from formula: "Vowel_A", 1, 0, dur, srate, formula$
    id_vowel = selected("Sound")
    Scale intensity: 70
    
    ampStr$ = string$(amp)
    f0Str$ = string$(f0)
    Create Sound from formula: "Buzz", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*" + f0Str$ + "*x)/2"
    id_buzz = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Formant Synthesis - Vowel /a/ ==="
        appendInfoLine: "Fundamental (F0): ", f0, " Hz"
        appendInfoLine: "Formant 1: ", f1_formant, " Hz"
        appendInfoLine: "Formant 2: ", f2_formant, " Hz"
        appendInfoLine: "Formant 3: ", f3_formant, " Hz"
        appendInfoLine: "Vowel quality comes from formant positions"
        appendInfoLine: ""
    endif
    
    selectObject: id_vowel, id_buzz
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "Vowel /a/ vs Simple Buzz"
    
    selectObject: id_vowel
    Play
    
    if not save_sounds_to_list
        selectObject: id_vowel, id_buzz, id_param
        Remove
    endif

elsif phenomenon = 14
    # === AM vs FM Modulation ===
    appendInfoLine: "[14] AM vs FM Modulation"
    f_carrier = f_base * 2
    f_mod = 5
    mod_index = 50
    
    ampStr$ = string$(amp)
    f_carrierStr$ = string$(f_carrier)
    f_modStr$ = string$(f_mod)
    modIndexStr$ = string$(mod_index)
    
    Create Sound from formula: "AM", 1, 0, dur, srate,
        ... ampStr$ + " * (1 + 0.8*sin(2*pi*" + f_modStr$ + "*x)) * sin(2*pi*" + f_carrierStr$ + "*x)"
    id_am = selected("Sound")
    
    Create Sound from formula: "FM", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*" + f_carrierStr$ + "*x + " + modIndexStr$ + "*sin(2*pi*" + f_modStr$ + "*x))"
    id_fm = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== AM vs FM Modulation ==="
        appendInfoLine: "Carrier: ", f_carrier, " Hz"
        appendInfoLine: "Modulator: ", f_mod, " Hz"
        appendInfoLine: ""
        appendInfoLine: "AM: Volume fluctuates (tremolo)"
        appendInfoLine: "FM: Pitch fluctuates (vibrato)"
        appendInfoLine: ""
        appendInfoLine: "Playing AM first, then FM..."
    endif
    
    selectObject: id_am, id_fm
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "AM (tremolo) vs FM (vibrato)"
    
    selectObject: id_am
    Play
    selectObject: id_fm
    Play
    
    if not save_sounds_to_list
        selectObject: id_am, id_fm, id_param
        Remove
    endif

elsif phenomenon = 15
    # === Phase Cancellation ===
    appendInfoLine: "[15] Phase Cancellation"
    f1 = f_base
    
    ampStr$ = string$(amp)
    f1Str$ = string$(f1)
    
    Create Sound from formula: "InPhase", 1, 0, dur, srate,
        ... ampStr$ + " * sin(2*pi*" + f1Str$ + "*x)"
    id_in = selected("Sound")
    
    Create Sound from formula: "OutPhase", 1, 0, dur, srate,
        ... "-" + ampStr$ + " * sin(2*pi*" + f1Str$ + "*x)"
    id_out = selected("Sound")
    
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== Phase Cancellation ==="
        appendInfoLine: "Frequency: ", f1, " Hz"
        appendInfoLine: "Signal 1: Normal phase"
        appendInfoLine: "Signal 2: Inverted (180 deg phase)"
        appendInfoLine: ""
        appendInfoLine: "When added together: Complete cancellation"
        appendInfoLine: "Result: Silence (theoretically)"
        appendInfoLine: ""
    endif
    
    selectObject: id_in, id_out
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    id_param = selected("ParamCurve")
    Text top: "no", "Phase Cancellation - Normal (X) vs Inverted (Y)"
    
    # Create the sum (cancellation)
    selectObject: id_in, id_out
    Combine to stereo
    id_stereo = selected("Sound")
    Convert to mono
    id_cancelled = selected("Sound")
    
    appendInfoLine: "Playing: Normal phase..."
    selectObject: id_in
    Play
    
    appendInfoLine: "Playing: Inverted phase..."
    selectObject: id_out
    Play
    
    appendInfoLine: "Playing: Sum (should be silent)..."
    selectObject: id_cancelled
    Play
    
    if not save_sounds_to_list
        selectObject: id_in, id_out, id_param, id_stereo, id_cancelled
        Remove
    endif

else
    exitScript: "Invalid phenomenon selection."
endif

appendInfoLine: ""
appendInfoLine: "=== Demonstration Complete ==="

# ==========================================
# PROCEDURES
# ==========================================

procedure show_info: .title$, .f1, .f2
    if show_info_window
        appendInfoLine: ""
        appendInfoLine: "=== ", .title$, " ==="
        appendInfoLine: "Frequency 1: ", fixed$(.f1, 2), " Hz"
        appendInfoLine: "Frequency 2: ", fixed$(.f2, 2), " Hz"
        .beat = abs(.f2 - .f1)
        appendInfoLine: "Beat frequency: ", fixed$(.beat, 2), " Hz"
        .ratio = .f2 / .f1
        appendInfoLine: "Frequency ratio: ", fixed$(.ratio, 6), ":1"
        .cents = 1200 * log2(.ratio)
        appendInfoLine: "Interval: ", fixed$(.cents, 2), " cents"
        appendInfoLine: ""
    endif
endproc

procedure create_and_play: .f1, .f2, .dur, .amp
    .ampStr$ = string$(.amp)
    .f1Str$ = string$(.f1)
    .f2Str$ = string$(.f2)
    
    Create Sound from formula: "Sound_A", 1, 0, .dur, srate,
        ... .ampStr$ + " * sin(2*pi*" + .f1Str$ + "*x)"
    .id_A = selected("Sound")
     
    Create Sound from formula: "Sound_B", 1, 0, .dur, srate,
        ... .ampStr$ + " * sin(2*pi*" + .f2Str$ + "*x)"
    .id_B = selected("Sound")
    
    selectObject: .id_A, .id_B
    To ParamCurve
    Draw: 0, 0, 0, 0, 0, 0, 0, "yes"
    .id_param = selected("ParamCurve")
    
    selectObject: .id_A, .id_B
    Combine to stereo
    .id_stereo = selected("Sound")
    Play
    
    if not save_sounds_to_list
        selectObject: .id_A, .id_B, .id_param, .id_stereo
        Remove
    endif
endproc