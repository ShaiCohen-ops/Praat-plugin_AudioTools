# ============================================================
# Praat AudioTools - Dynamic_Formant_Sweeper.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   LPC source-filter resynthesis with an LFO-controlled F1
#   trajectory. The input is analysed into an excitation and up to
#   five formants; only F1's frequency and bandwidth are replaced by
#   the LFO, F2-F5 keep their measured values, and the excitation is
#   refiltered through the whole set.
#
#   It is NOT a single resonant bandpass. For that, the Formant object
#   would have to be reduced to one track. Vowel morphing, robot
#   voices and talking-synth effects come from moving F1 against the
#   material's own upper formants.
#
# Changelog v0.3:
#   - Fixed Formula variable interpolation; fixed dry/wet object reference
#
# Changelog v0.4:
#   - Rebuilt the visualization in the AudioTools house style.
#
# Changelog v0.6 - Parselmouth-verified again. Everything v0.5 changed
# passed: Filter (no scale) and the restored dynamics, relative time
# (correlation 0.999999997 between the same signal at 0 s and at
# 5.137 s), stereo and 4-channel preservation, the split analysis
# fields, the optional Nyquist-clamped high cut, RMS matching, the
# safety ceiling, and all eight presets on sine, noise, impulse and
# chirp with no undefined samples. Four things remained:
#   - THE FADES WERE CUTTING THE DRY PATH. They ran after the dry/wet
#     mix, so at Dry/Wet = 1% - where the output should be almost
#     entirely the source - the start of a 0.3-peak file still deviated
#     from the source by up to 0.206, because the dry signal was being
#     faded up from zero too. Fades now apply to the wet channel before
#     the mix, so the dry path is untouched.
#   - ANTI-PHASE STEREO IS SUPPORTED, NOT REFUSED. v0.5 always summed to
#     mono for the formant measurement and then stopped when the sum
#     cancelled. Analysis_source now offers Channel 1, Loudest channel
#     (the default) or Mono sum. A single channel cannot cancel, and on
#     wide stereo it also avoids the weak, smeared formants a sum gives.
#   - Dry/Wet = 0 is a FULL bypass. v0.5 skipped the effect but still
#     ran the output level stage, so a 1.2-peak input came back at 0.95
#     under the default mode, and Peak normalize altered a quiet input.
#     The level stage is skipped at Dry/Wet = 0 and the report says so.
#   - Rate_Hz: 0 and negative values are allowed deliberately, and the
#     report now states what each does per LFO shape. v0.5's changelog
#     claimed validation that was never written.
#
# Changelog v0.5 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - Filter (no scale) REPLACES Filter. Sound & Formant: Filter
#     normalizes its result to peak 0.99 on its own, and the script
#     then ran Scale peak: 0.95 as well. The wet path therefore had no
#     dynamics at all: the same vowel at input peaks of 0.300, 0.030,
#     0.003 and 0.0003 - a 60 dB range - all came out at RMS 0.1766,
#     and a sine peaking at 1e-9 produced RMS 0.083, a gain above
#     150 dB. Level is now decided once, at the end, by
#     Output_level_mode.
#   - Stereo survives. Exactly the nChannels = 2 case was folded to
#     mono and re-expanded with Convert to stereo, so two different
#     channels came back identical (maximum channel difference 0), and
#     anti-phase stereo cancelled to nothing and stopped the run with
#     "No formants available". Four-channel input was untouched by
#     that branch and came through intact, which is the giveaway. Only
#     the FORMANT ANALYSIS uses a mono fold now; every channel keeps
#     its own excitation and gets the same F1 trajectory.
#   - Relative time. The LFO formulas used x, which in Praat is
#     absolute time in the object's own domain, so the same Sound at
#     0-1 s and at 5.137-6.137 s gave results correlating at -0.20.
#     The fades were worse: with a Sound starting at 5 s every sample
#     satisfied the fade-out test and (duration - x) / 0.02 went large
#     and negative, so a Dry/Wet = 0 run came back at correlation
#     -0.991 with the source. All processing now happens on a copy
#     shifted to 0, and the source domain is restored at the end.
#   - Dry/Wet = 0 is a hard bypass. v0.4 still applied the fades and
#     the normalization: a 0.300-peak input returned peak 0.950, RMS
#     amplified 5.86x, maximum error 0.790.
#   - Silence is handled. A silent input reached Formula (frequencies)
#     with no formant frames and stopped with "No formants available";
#     a near-silent one ran and was normalized up into a loud result.
#   - Frame_duration_ms was the TIME STEP, not the window. It was
#     passed as the first argument of To Formant (burg) while the
#     analysis window stayed fixed at 25 ms. There are now two fields,
#     Formant_time_step_ms and Formant_window_ms.
#   - The 8 kHz high cut is optional and clamped to Nyquist. It ran
#     unconditionally, removing everything above 8 kHz at 44.1/48 kHz,
#     which is not "gentle artifact smoothing".
#   - Fades are optional and their length is a parameter.
#   - Validation on the frequency range, the formant ceiling against
#     Nyquist, bandwidth, mix and rate.
#   - Version strings synchronized, the Output line reports the result
#     rather than the source, and the plots follow the work copy.
# ============================================================

# === Check for Sound selection ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object first."
endif

inputSound = selected("Sound")
originalName$ = selected$("Sound")

form Dynamic Formant Sweeper v0.6
    optionmenu Preset: 1
        option Manual
        option Gentle Vowel Morph
        option Robot Voice
        option Talking Synth
        option Underwater
        option Alien Speech
        option Fast Wobble
        option Slow Sweep
    comment === LFO Parameters ===
    real Rate_Hz 1.0
    positive Min_freq_Hz 500
    positive Max_freq_Hz 3500
    comment === Filter Shape ===
    positive Bandwidth_Hz 100
    optionmenu Lfo_shape: 1
        option Sine
        option Triangle
        option Square (Chopper)
        option Sawtooth
        option Reverse Sawtooth
    comment === Analysis ===
    optionmenu Analysis_source: 2
        option Channel 1
        option Loudest channel
        option Mono sum (cancels anti-phase)
    positive Formant_time_step_ms 25
    positive Formant_window_ms 25
    comment (in v0.4 the single Frame duration field was the time step; the window was fixed at 25 ms)
    positive Formant_ceiling_Hz 5500
    comment === Processing ===
    real Dry_wet_mix 1.0
    boolean Apply_high_cut 1
    positive High_cut_Hz 8000
    boolean Apply_fades 1
    positive Fade_ms 10
    comment === Output ===
    optionmenu Output_level_mode: 2
        option None (natural level)
        option Match input RMS + safety ceiling
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    rate_Hz = 0.3
    min_freq_Hz = 700
    max_freq_Hz = 1200
    bandwidth_Hz = 80
    lfo_shape = 1
    formant_time_step_ms = 40
    dry_wet_mix = 0.6
    presetName$ = "GentleVowelMorph"
elsif preset = 3
    rate_Hz = 2.0
    min_freq_Hz = 400
    max_freq_Hz = 2000
    bandwidth_Hz = 150
    lfo_shape = 3
    formant_time_step_ms = 15
    dry_wet_mix = 0.85
    presetName$ = "RobotVoice"
elsif preset = 4
    rate_Hz = 0.5
    min_freq_Hz = 600
    max_freq_Hz = 1800
    bandwidth_Hz = 120
    lfo_shape = 2
    formant_time_step_ms = 30
    dry_wet_mix = 0.75
    presetName$ = "TalkingSynth"
elsif preset = 5
    rate_Hz = 0.2
    min_freq_Hz = 300
    max_freq_Hz = 800
    bandwidth_Hz = 200
    lfo_shape = 1
    formant_time_step_ms = 50
    dry_wet_mix = 0.9
    presetName$ = "Underwater"
elsif preset = 6
    rate_Hz = 1.5
    min_freq_Hz = 800
    max_freq_Hz = 3000
    bandwidth_Hz = 90
    lfo_shape = 4
    formant_time_step_ms = 20
    dry_wet_mix = 0.8
    presetName$ = "AlienSpeech"
elsif preset = 7
    rate_Hz = 4.0
    min_freq_Hz = 500
    max_freq_Hz = 2500
    bandwidth_Hz = 100
    lfo_shape = 1
    formant_time_step_ms = 10
    dry_wet_mix = 0.7
    presetName$ = "FastWobble"
elsif preset = 8
    rate_Hz = 0.1
    min_freq_Hz = 400
    max_freq_Hz = 3500
    bandwidth_Hz = 100
    lfo_shape = 4
    formant_time_step_ms = 35
    dry_wet_mix = 1.0
    presetName$ = "SlowSweep"
else
    presetName$ = "Manual"
endif

# === Input info ===
twoPi = 2 * pi

selectObject: inputSound
duration = Get total duration
sampleRate = Get sampling frequency
nChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2
inputPeak = Get absolute extremum: 0, 0, "None"
inputRMS = Get root-mean-square: 0, 0

nPoles = round(sampleRate / 1000) + 2
timeStepSec = formant_time_step_ms / 1000
windowSec = formant_window_ms / 1000

# === Validation ===
if min_freq_Hz >= max_freq_Hz
    exitScript: "Min_freq_Hz (" + fixed$(min_freq_Hz, 0) + ") must be below Max_freq_Hz (" +
    ... fixed$(max_freq_Hz, 0) + "). v0.4 accepted this and silently reversed the sweep."
endif
if formant_ceiling_Hz >= nyquist
    exitScript: "Formant_ceiling_Hz (" + fixed$(formant_ceiling_Hz, 0) +
    ... ") must be below Nyquist (" + fixed$(nyquist, 0) + " Hz)."
endif
if max_freq_Hz >= formant_ceiling_Hz
    exitScript: "Max_freq_Hz (" + fixed$(max_freq_Hz, 0) + ") must be below " +
    ... "Formant_ceiling_Hz (" + fixed$(formant_ceiling_Hz, 0) + "): F1 cannot be swept " +
    ... "above the ceiling the analysis was made with."
endif
if bandwidth_Hz >= max_freq_Hz
    exitScript: "Bandwidth_Hz (" + fixed$(bandwidth_Hz, 0) + ") is not sensible next to a " +
    ... "sweep top of " + fixed$(max_freq_Hz, 0) + " Hz; use a bandwidth well below it."
endif
# Rate 0 and negative rates are allowed on purpose - they are usable
# creatively - but v0.5's changelog claimed validation that did not
# exist, so what they do is stated instead.
if rate_Hz = 0
    if lfo_shape = 1 or lfo_shape = 2
        staticF1 = min_freq_Hz + (max_freq_Hz - min_freq_Hz) / 2
    elsif lfo_shape = 5
        staticF1 = max_freq_Hz
    else
        staticF1 = min_freq_Hz
    endif
    appendInfoLine: "NOTE: Rate_Hz is 0, so F1 is held at a constant ",
        ... fixed$(staticF1, 0), " Hz. Which constant depends on the LFO shape:"
    appendInfoLine: "      Sine and Triangle rest at the midpoint, Square and Sawtooth at"
    appendInfoLine: "      the minimum, Reverse Sawtooth at the maximum."
elsif rate_Hz < 0
    appendInfoLine: "NOTE: Rate_Hz is negative. Sine and Triangle simply run backwards;"
    appendInfoLine: "      Square inverts its phase, and the Sawtooth shapes reverse their"
    appendInfoLine: "      ramp direction. This is allowed, not an error."
endif

if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1 (got " + fixed$(dry_wet_mix, 3) + ")."
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1 (got " +
    ... fixed$(ceiling_peak, 3) + ")."
endif
if duration < windowSec * 3
    exitScript: "Sound is too short: " + fixed$(duration * 1000, 1) + " ms. The " +
    ... fixed$(formant_window_ms, 0) + " ms analysis window needs at least " +
    ... fixed$(windowSec * 3000, 0) + " ms."
endif

highCut = high_cut_Hz
if highCut > nyquist - 100
    highCut = nyquist - 100
endif

# A silent input has no formant frames at all: v0.4 reached
# Formula (frequencies) and stopped with "No formants available", while
# a near-silent one ran and was normalized up into a loud result.
if inputRMS < 0.0000001
    exitScript: "The input is silent (RMS " + fixed$(inputRMS, 10) + "). There are no " +
    ... "formants to sweep."
endif

# === Info ===
clearinfo
writeInfoLine: "=== Dynamic Formant Sweeper v0.6 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 2), " s, ", nChannels,
    ... " ch, ", sampleRate, " Hz)"
appendInfoLine: "  Peak ", fixed$(inputPeak, 4), " | RMS ", fixed$(inputRMS, 5)
appendInfoLine: "LFO: ", rate_Hz, " Hz | F1 range: ", min_freq_Hz, "-", max_freq_Hz, " Hz"
appendInfoLine: "Formant analysis: step ", formant_time_step_ms, " ms, window ",
    ... formant_window_ms, " ms, ceiling ", formant_ceiling_Hz, " Hz"
appendInfoLine: "Mix: ", fixed$(dry_wet_mix * 100, 0), "% wet"
if inputRMS < 0.001
    appendInfoLine: "  NOTE: the input is very quiet. With Peak normalize this would be"
    appendInfoLine: "        amplified heavily; the default level mode will not do that."
endif
appendInfoLine: ""

# ============================================================
# Work copy at time 0
# ============================================================
# x in a Praat Formula is absolute time in the object's own domain, so
# every LFO and fade formula here was tied to where the Sound sits on
# the timeline: the same signal at 0-1 s and at 5.137-6.137 s gave
# results correlating at -0.20.
selectObject: inputSound
workSound = Copy: "dfs_work"
Shift times to: "start time", 0

# ============================================================
# Hard bypass
# ============================================================
if dry_wet_mix = 0
    appendInfoLine: "Dry/Wet is 0: returning the input unprocessed."
    selectObject: workSound
    finalOutput = Copy: "dfs_out"
    bypassed = 1
else
    bypassed = 0
endif

if bypassed = 0
    # ============================================================
    # Formant analysis: one channel, chosen (analysis only)
    # ============================================================
    # v0.4 folded the AUDIO to mono for nChannels = 2 and re-expanded
    # with Convert to stereo, so two different channels came back
    # identical and anti-phase stereo cancelled entirely. Only the
    # formant measurement needs a single channel, and it reads a real
    # channel rather than a sum, so it cannot cancel.
    if nChannels = 1
        selectObject: workSound
        analysisSound = Copy: "dfs_analysis"
        analysisSource$ = "the single channel"
    elsif analysis_source = 3
        selectObject: workSound
        analysisSound = Convert to mono
        analysisSource$ = "mono sum"
    else
        # A single real channel, never a fold. v0.5 always summed to
        # mono and then refused to run when the sum cancelled, so
        # anti-phase stereo was reported rather than supported. Picking
        # a channel cannot cancel, and on wide stereo it also avoids the
        # weak, smeared formants a sum produces.
        pickCh = 1
        if analysis_source = 2
            bestRms = -1
            for ch from 1 to nChannels
                selectObject: workSound
                probeCh = Extract one channel: ch
                probeRms = Get root-mean-square: 0, 0
                removeObject: probeCh
                if probeRms > bestRms
                    bestRms = probeRms
                    pickCh = ch
                endif
            endfor
        endif
        selectObject: workSound
        analysisSound = Extract one channel: pickCh
        analysisSource$ = "channel " + string$(pickCh)
    endif

    selectObject: analysisSound
    analysisRMS = Get root-mean-square: 0, 0
    if analysisRMS < 0.0000001
        removeObject: analysisSound, workSound
        if analysis_source = 3 and nChannels > 1
            exitScript: "The mono sum used for the formant analysis cancelled to " +
            ... "silence (the channels are close to anti-phase). Set Analysis_source " +
            ... "to Loudest channel or Channel 1."
        else
            exitScript: "The channel chosen for the formant analysis is silent."
        endif
    endif
    appendInfoLine: "  Formant analysis reads ", analysisSource$

    appendInfoLine: "[1/4] Measuring formants..."
    selectObject: analysisSound
    filterObject = To Formant (burg): timeStepSec, 5, formant_ceiling_Hz, windowSec, 50

    selectObject: filterObject
    nFormantFrames = Get number of frames
    if nFormantFrames < 1
        removeObject: filterObject, analysisSound, workSound
        exitScript: "No formant frames were produced. Try a longer Sound or a larger " +
        ... "Formant_window_ms."
    endif
    appendInfoLine: "  Frames: ", nFormantFrames

    # ============================================================
    # Replace the F1 trajectory with the LFO
    # ============================================================
    appendInfoLine: "[2/4] Writing the LFO into F1..."

    freqRange = max_freq_Hz - min_freq_Hz
    freqMid = min_freq_Hz + freqRange / 2

    minF$ = string$(min_freq_Hz)
    maxF$ = string$(max_freq_Hz)
    range$ = string$(freqRange)
    mid$ = string$(freqMid)
    rate$ = string$(rate_Hz)
    halfRange$ = string$(freqRange / 2)

    if lfo_shape = 1
        freqFormula$ = minF$ + " + " + range$ + " * 0.5 * (1 + sin(2*pi*" + rate$ + "*x))"
    elsif lfo_shape = 2
        freqFormula$ = mid$ + " + " + halfRange$ + " * (2/pi) * arcsin(sin(2*pi*" + rate$ + "*x))"
    elsif lfo_shape = 3
        freqFormula$ = "if sin(2*pi*" + rate$ + "*x) > 0 then " + maxF$ + " else " + minF$ + " endif"
    elsif lfo_shape = 4
        freqFormula$ = minF$ + " + " + range$ + " * ((" + rate$ + "*x) mod 1)"
    elsif lfo_shape = 5
        freqFormula$ = maxF$ + " - " + range$ + " * ((" + rate$ + "*x) mod 1)"
    endif

    selectObject: filterObject
    Formula (frequencies): "if row = 1 then " + freqFormula$ + " else self endif"
    Formula (bandwidths): "if row = 1 then " + string$(bandwidth_Hz) + " else self endif"

    # ============================================================
    # Per-channel resynthesis
    # ============================================================
    appendInfoLine: "[3/4] Resynthesizing ", nChannels, " channel(s)..."

    for ch from 1 to nChannels
        if nChannels = 1
            selectObject: workSound
            dryCh[ch] = Copy: "dfs_dry_ch"
        else
            selectObject: workSound
            dryCh[ch] = Extract one channel: ch
        endif

        selectObject: dryCh[ch]
        lpcCh = To LPC (burg): nPoles, windowSec, 0.005, 50
        selectObject: lpcCh
        plusObject: dryCh[ch]
        excCh = Filter (inverse)
        removeObject: lpcCh

        # Filter (no scale), not Filter. Sound & Formant: Filter
        # normalizes to peak 0.99 by itself, which is what flattened a
        # 60 dB input range to a single output RMS of 0.1766.
        selectObject: excCh
        plusObject: filterObject
        wetCh[ch] = Filter (no scale)
        removeObject: excCh

        if apply_high_cut
            selectObject: wetCh[ch]
            hc = Filter (pass Hann band): 0, highCut, 100
            removeObject: wetCh[ch]
            wetCh[ch] = hc
        endif

        # Fade the WET signal, then mix. v0.5 faded after mixing, so the
        # fade attenuated the dry path too: at Dry/Wet = 1% - where the
        # output should be almost entirely the source - the start of a
        # 0.3-peak file still deviated from the source by up to 0.206,
        # because the dry was being faded from zero as well.
        if apply_fades
            fadeSec = fade_ms / 1000
            if fadeSec > duration / 4
                fadeSec = duration / 4
            endif
            selectObject: wetCh[ch]
            wetDurCh = Get total duration
            Formula: "if x < " + string$(fadeSec) + " then self * (x / " + string$(fadeSec) +
                ... ") else self endif"
            Formula: "if x > " + string$(wetDurCh - fadeSec) + " then self * ((" +
                ... string$(wetDurCh) + " - x) / " + string$(fadeSec) + ") else self endif"
        endif

        if dry_wet_mix < 1
            selectObject: wetCh[ch]
            Formula: "self * " + string$(dry_wet_mix) + " + object(" +
                ... string$(dryCh[ch]) + ", x) * " + string$(1 - dry_wet_mix)
        endif

        appendInfo: "."
    endfor
    appendInfoLine: ""

    removeObject: filterObject, analysisSound

    # --- Assemble ---
    if nChannels = 1
        selectObject: wetCh[1]
        finalOutput = Copy: "dfs_out"
        removeObject: wetCh[1]
    else
        selectObject: wetCh[1]
        outDurCh = Get total duration
        Create Sound from formula: "dfs_out", nChannels, 0, outDurCh, sampleRate, "0"
        finalOutput = selected("Sound")
        for ch from 1 to nChannels
            selectObject: finalOutput
            Formula (part): 0, outDurCh, ch, ch,
                ... "object[" + string$(wetCh[ch]) + ", 1, col]"
        endfor
        for ch from 1 to nChannels
            removeObject: wetCh[ch]
        endfor
    endif

    for ch from 1 to nChannels
        removeObject: dryCh[ch]
    endfor

endif

# ============================================================
# Output level stage
# ============================================================
selectObject: finalOutput
pre_level_peak = Get absolute extremum: 0, 0, "None"
pre_level_rms = Get root-mean-square: 0, 0
level_gain = 1
level_action$ = "none"

if bypassed
    # Full bypass, not just effect bypass. v0.5 skipped the processing
    # but still ran the level stage, so a 1.2-peak input came back at
    # 0.95 under the default mode and Peak normalize changed a quiet
    # input as well. At Dry/Wet = 0 the output is now numerically the
    # input.
    appendInfoLine: "[4/4] Output level: skipped (full bypass)"
    level_action$ = "skipped - Dry/Wet is 0, output is the input unchanged"
else
    appendInfoLine: "[4/4] Output level..."
endif

if bypassed = 0
if output_level_mode = 2
    if pre_level_rms > 0.0000001 and inputRMS > 0.0000001
        level_gain = inputRMS / pre_level_rms
        selectObject: finalOutput
        Formula: "self * " + string$(level_gain)
        level_action$ = "matched to input RMS"
        selectObject: finalOutput
        rmsPeak = Get absolute extremum: 0, 0, "None"
        if rmsPeak > ceiling_peak and rmsPeak > 0
            Scale peak: ceiling_peak
            level_gain = level_gain * (ceiling_peak / rmsPeak)
            level_action$ = "RMS matched, then ceiling applied"
        endif
    endif
elsif output_level_mode = 3
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 4
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif
endif

selectObject: finalOutput
out_peak = Get absolute extremum: 0, 0, "None"
out_rms = Get root-mean-square: 0, 0

# ============================================================
# Visualization (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    freqRange = max_freq_Hz - min_freq_Hz
    freqMid = min_freq_Hz + freqRange / 2
    specCeil = min(5000, nyquist)

    Erase all

    # --- Title ---
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Dynamic Formant Sweeper##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.0, "half",
        ... originalName$ + "  |  " + presetName$
        ... + "  |  F1 " + string$(min_freq_Hz) + "-" + string$(max_freq_Hz) + " Hz"
        ... + "  |  " + fixed$(rate_Hz, 2) + " Hz LFO"
        ... + "  |  " + string$(nChannels) + " ch"

    # --- Panel 1: LFO trajectory (F1 over time) ---
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    Axes: 0, duration, min_freq_Hz - 100, max_freq_Hz + 100
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration, min_freq_Hz - 100, max_freq_Hz + 100

    Colour: "{0.80, 0.50, 0.20}"
    Line width: 2
    nPoints = 200
    for i from 2 to nPoints
        t1 = (i - 2) / (nPoints - 1) * duration
        t2 = (i - 1) / (nPoints - 1) * duration
        if lfo_shape = 1
            y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t1))
            y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 2
            y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t1))
            y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 3
            if sin(twoPi * rate_Hz * t1) > 0
                y1 = max_freq_Hz
            else
                y1 = min_freq_Hz
            endif
            if sin(twoPi * rate_Hz * t2) > 0
                y2 = max_freq_Hz
            else
                y2 = min_freq_Hz
            endif
        elsif lfo_shape = 4
            y1 = min_freq_Hz + freqRange * ((rate_Hz * t1) mod 1)
            y2 = min_freq_Hz + freqRange * ((rate_Hz * t2) mod 1)
        elsif lfo_shape = 5
            y1 = max_freq_Hz - freqRange * ((rate_Hz * t1) mod 1)
            y2 = max_freq_Hz - freqRange * ((rate_Hz * t2) mod 1)
        endif
        Draw line: t1, y1, t2, y2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "F1 (Hz)"
    if bypassed
        Text bottom: "yes", "LFO trajectory (NOT APPLIED: Dry/Wet is 0)"
    else
        Text bottom: "yes", "LFO trajectory"
    endif

    # --- Panel 2: Output spectrogram with the F1 overlay ---
    Select outer viewport: 0, 8, 2.0, 4.8
    Select inner viewport: 0.6, 7.6, 2.1, 4.7

    selectObject: finalOutput
    vizCh = Get number of channels
    if vizCh > 1
        specSound = Convert to mono
    else
        specSound = Copy: "temp_spec"
    endif
    selectObject: specSound
    spec = To Spectrogram: 0.005, specCeil, 0.002, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: specSound, spec

    Select inner viewport: 0.6, 7.6, 2.1, 4.7
    Axes: 0, duration, 0, specCeil
    Colour: "Yellow"
    Line width: 3
    for i from 2 to nPoints
        t1 = (i - 2) / (nPoints - 1) * duration
        t2 = (i - 1) / (nPoints - 1) * duration
        if lfo_shape = 1
            y1 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t1))
            y2 = min_freq_Hz + freqRange * 0.5 * (1 + sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 2
            y1 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t1))
            y2 = freqMid + (freqRange/2) * (2/pi) * arcsin(sin(twoPi * rate_Hz * t2))
        elsif lfo_shape = 3
            if sin(twoPi * rate_Hz * t1) > 0
                y1 = max_freq_Hz
            else
                y1 = min_freq_Hz
            endif
            if sin(twoPi * rate_Hz * t2) > 0
                y2 = max_freq_Hz
            else
                y2 = min_freq_Hz
            endif
        elsif lfo_shape = 4
            y1 = min_freq_Hz + freqRange * ((rate_Hz * t1) mod 1)
            y2 = min_freq_Hz + freqRange * ((rate_Hz * t2) mod 1)
        elsif lfo_shape = 5
            y1 = max_freq_Hz - freqRange * ((rate_Hz * t1) mod 1)
            y2 = max_freq_Hz - freqRange * ((rate_Hz * t2) mod 1)
        endif
        Draw line: t1, y1, t2, y2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # --- Summary panel ---
    Select outer viewport: 0, 8, 4.9, 5.7
    Select inner viewport: 0.6, 7.6, 5.0, 5.6
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if output_level_mode = 1
        levelStr$ = "natural"
    elsif output_level_mode = 2
        levelStr$ = "input RMS (x" + fixed$(level_gain, 3) + ")"
    elsif output_level_mode = 3
        levelStr$ = "ceiling " + fixed$(ceiling_peak, 2) + " (" + level_action$ + ")"
    else
        levelStr$ = "normalized to " + fixed$(ceiling_peak, 2)
    endif
    if apply_high_cut
        hcStr$ = "high cut " + fixed$(highCut, 0) + " Hz"
    else
        hcStr$ = "no high cut"
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.50, "half",
        ... "LFO: " + fixed$(rate_Hz, 2) + " Hz"
        ... + "  |  F1: " + string$(min_freq_Hz) + "-" + string$(max_freq_Hz) + " Hz"
        ... + "  |  BW: " + string$(bandwidth_Hz) + " Hz"
        ... + "  |  Step/window: " + fixed$(formant_time_step_ms, 0) + "/"
        ... + fixed$(formant_window_ms, 0) + " ms"
        ... + "  |  Mix: " + fixed$(dry_wet_mix * 100, 0) + "%"
        ... + "  |  " + hcStr$
    Text: 0.02, "left", 0.18, "half",
        ... "Peak in: " + fixed$(inputPeak, 3) + "  RMS in: " + fixed$(inputRMS, 4)
        ... + "  |  Peak out: " + fixed$(out_peak, 3) + "  RMS out: " + fixed$(out_rms, 4)
        ... + "  |  Level: " + levelStr$
        ... + "  |  Yellow = F1 sweep"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: finalOutput
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_swept_" + presetName$
finalName$ = selected$("Sound")

removeObject: workSound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
# v0.4 selected the input and the result together and then read
# selected$("Sound"), which reported the INPUT name.
appendInfoLine: "Output: ", finalName$
appendInfoLine: "  Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(out_peak, 4)
appendInfoLine: "  RMS:  ", fixed$(inputRMS, 5), " -> ", fixed$(out_rms, 5)
appendInfoLine: "  Output stage: ", level_action$
if output_level_mode <> 4 and out_peak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

if play_result
    if out_peak > 1
        appendInfoLine: "Playing a scaled copy (peak ", fixed$(out_peak, 3), " exceeds 1.0)..."
        selectObject: finalOutput
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        selectObject: finalOutput
        Play
    endif
endif

selectObject: finalOutput
