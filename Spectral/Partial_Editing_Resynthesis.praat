# ============================================================
# Praat AudioTools - Partial_Editing_Resynthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#
# Changelog v0.6 (2026):
#   - MUSICAL FIX: frame-random frequency/amplitude jitter was the main source of
#     the visible and audible grain segmentation on sustained tones. Even with
#     FFT-bin-locked peaks, each overlapping frame received a new detuning, so
#     neighbouring grains beat/cancelled against one another.
#   - New Jitter behaviour control. The default Stable per-frequency mode assigns
#     a deterministic offset to each detected FFT bin, preserving detuned/chorused
#     colour while keeping the same partial phase-coherent across overlapping
#     frames. Frame-random retains the v0.5.1/v0.4 grainy character explicitly.
#   - Clean Resynth therefore keeps its small 0.5-Hz spectral spread without
#     producing hop/grain-rate dropouts on a sustained tone.
#   - Visualization structure retained; summary now reports jitter behaviour.
#
# Changelog v0.5.1 (2026):
#   - MUSICAL FIX: restored v0.4-style FFT-bin-locked peak frequencies for
#     resynthesis. The v0.5 parabolic sub-bin estimates changed slightly from
#     frame to frame; because this texture engine deliberately has no partial
#     phase tracking, those small frequency changes accumulated large phase
#     offsets in overlapping grains and could create audible dips/cutouts on
#     sustained tones and vibrato. Bin locking restores the stable sustain
#     behaviour while keeping the v0.5 tail-coverage and stereo-analysis fixes.
#   - No visualization redesign: the existing figure already tells the process.
#
# Changelog v0.5 (2026):
#   - FIX: frame scheduling now covers the complete source. v0.4 omitted
#     the final frame (and up to almost one hop of audio), leaving a silent tail.
#   - EXPERIMENT (superseded in v0.5.1): parabolic peak interpolation reduced
#     bin quantisation but proved musically worse without phase tracking.
#   - FIX: stereo analysis no longer averages channels to mono. The strongest-RMS
#     channel drives the inherently mono resynthesis, avoiding anti-phase loss.
#   - CLARITY: the old "Formant shift ratio" was mathematically only an additional
#     global frequency multiplier. It is renamed Additional_frequency_scale;
#     existing preset ratios and sound are retained.
#   - ROBUSTNESS: analysis frequency limits are validated/clamped to Nyquist;
#     short sounds receive one valid frame; peak amplitude calibration uses the
#     actual frame duration; silence remains safe.
#   - VIZ: layout retained; original/result waveforms now share one amplitude
#     scale, and spectrogram frequency range respects Nyquist.
#
# Changelog v0.4 (2026):
#   - FIX (crash): STEREO inputs crashed at the first frame's
#     To Spectrum (the ledger's confirmed stereo-analysis crash).
#     The input is now converted to mono upfront; resynthesis is
#     inherently mono.
#   - FIX: grain overlap-add is normalized by the exact analytic
#     window-sum envelope. The default 60/15 ms window/hop is
#     Hann-COLA (sum constant), but the parameters are free: any
#     non-integer window/hop ratio (e.g. 60/25) previously
#     stamped hop-rate tremolo across the output. Defaults sound
#     unchanged (constant division, re-normalized by the final
#     Scale intensity).
#   - FIX: Freq_jitter was a "positive" form field, but the
#     Robotic preset's documented value is 0.0 -- typing 0 in
#     Custom was rejected by Praat. Now real, clamped at 0;
#     Amp_jitter clamped to [0, 1].
#   - FIX: an all-silent result (no partials found) crashed the
#     final Scale intensity; now guarded.
#   - FIX: the final original+result selection was clobbered by
#     the Play branch; the visualization's original spectrogram
#     extracts channel 1 of stereo inputs.
#
# Description:
#   Framewise sinusoidal texture resynthesis. Each analysis frame finds the
#   strongest spectral peaks and resynthesizes them as sine grains.
#
#   This is partial-inspired rather than a tracked-partial model: peaks are not
#   linked across frames and original analysis phase is not carried into the
#   grains. Frequency motion therefore creates the characteristic chorus/shimmer
#   in overlaps. The Hann peak picker and its 40-Hz suppression are intentionally
#   retained from v0.4 because their residual leakage is part of that texture.
#   v0.5.1 keeps the v0.4 bin-locked frequency character for sustain continuity,
#   while retaining the v0.5 boundary/stereo fixes without adding phase tracking.
# ============================================================

form Sinusoidal Texture Resynthesis v0.6
    optionmenu Preset: 1
        option Custom
        option Clean Texture Resynth (minimal jitter)
        option Diffuse Texture (jittery)
        option Sparse Partials (hollow)
        option Dense Partials (rich)
        option Pitch Up Octave
        option Pitch Down Octave
        option Spectral Scale Up (1.5x)
        option Spectral Scale Down (0.7x)
        option Glassy Shimmer
        option Robotic (precise)
        option Whisper Ghost
    comment === Synthesis Parameters ===
    positive Window_length 0.060
    positive Hop_size 0.015
    positive Min_frequency 60
    positive Max_frequency 8000
    integer Max_partials_per_frame 15
    comment === Diffusion & Texture ===
    real Freq_jitter 3.0
    real Amp_jitter 0.1
    optionmenu Jitter_behaviour: 1
        option Stable per-frequency (continuous)
        option Frame-random (legacy grain texture)
    comment === Frequency Editing ===
    real Transpose_semitones 0
    real Additional_frequency_scale 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === APPLY PRESETS ===
if preset = 2
    freq_jitter = 0.5
    amp_jitter = 0.02
    max_partials_per_frame = 20
    presetName$ = "CleanResynth"
elsif preset = 3
    freq_jitter = 8.0
    amp_jitter = 0.3
    max_partials_per_frame = 15
    presetName$ = "DiffuseTexture"
elsif preset = 4
    max_partials_per_frame = 5
    freq_jitter = 2.0
    amp_jitter = 0.1
    presetName$ = "SparsePartials"
elsif preset = 5
    max_partials_per_frame = 30
    freq_jitter = 1.0
    amp_jitter = 0.05
    presetName$ = "DensePartials"
elsif preset = 6
    transpose_semitones = 12
    freq_jitter = 1.0
    amp_jitter = 0.05
    presetName$ = "PitchUpOctave"
elsif preset = 7
    transpose_semitones = -12
    freq_jitter = 1.0
    amp_jitter = 0.05
    presetName$ = "PitchDownOctave"
elsif preset = 8
    additional_frequency_scale = 1.5
    freq_jitter = 2.0
    amp_jitter = 0.1
    presetName$ = "SpectralScaleUp"
elsif preset = 9
    additional_frequency_scale = 0.7
    freq_jitter = 2.0
    amp_jitter = 0.1
    presetName$ = "SpectralScaleDown"
elsif preset = 10
    freq_jitter = 15.0
    amp_jitter = 0.4
    max_partials_per_frame = 20
    max_frequency = 12000
    presetName$ = "GlassyShimmer"
elsif preset = 11
    freq_jitter = 0.0
    amp_jitter = 0.0
    max_partials_per_frame = 12
    presetName$ = "Robotic"
elsif preset = 12
    max_partials_per_frame = 4
    freq_jitter = 10.0
    amp_jitter = 0.5
    max_frequency = 6000
    presetName$ = "WhisperGhost"
else
    presetName$ = "Custom"
endif

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound."
endif

orig_id = selected("Sound")
orig_name$ = selected$("Sound")
selectObject: orig_id
orig_sr = Get sampling frequency
t1 = Get start time
t2 = Get end time
dur = t2 - t1
nyqOrig = orig_sr / 2

if window_length <= 0
    exitScript: "Window length must be greater than 0."
endif
if hop_size <= 0
    exitScript: "Hop size must be greater than 0."
endif
if min_frequency < 0
    min_frequency = 0
endif
if min_frequency >= nyqOrig
    exitScript: "Minimum frequency must be below Nyquist."
endif
if max_frequency > nyqOrig
    max_frequency = nyqOrig
endif
if max_frequency <= min_frequency
    exitScript: "Maximum frequency must be greater than minimum frequency."
endif
if max_partials_per_frame < 1
    exitScript: "Max partials per frame must be at least 1."
endif
if additional_frequency_scale <= 0
    exitScript: "Additional frequency scale must be greater than 0."
endif

clearinfo
writeInfoLine: "=== Sinusoidal Texture Resynthesis v0.6 ==="
appendInfoLine: "Input: ", orig_name$
appendInfoLine: "Duration: ", fixed$(dur, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Partials: ", max_partials_per_frame
appendInfoLine: "Freq jitter: ", freq_jitter, " Hz"
appendInfoLine: "Amp jitter: ", amp_jitter
if jitter_behaviour = 1
    jitterMode$ = "stable per-frequency"
else
    jitterMode$ = "frame-random legacy"
endif
appendInfoLine: "Jitter behaviour: ", jitterMode$
appendInfoLine: "Transpose: ", transpose_semitones, " semitones"
appendInfoLine: "Additional frequency scale: ", additional_frequency_scale
appendInfoLine: ""

if freq_jitter < 0
    freq_jitter = 0
endif
if amp_jitter < 0
    amp_jitter = 0
elsif amp_jitter > 1
    amp_jitter = 1
endif

# Prepare analysis driver.
# Resynthesis is intentionally mono, but do not average stereo channels:
# anti-phase material could cancel before analysis. Use the strongest-RMS channel.
selectObject: orig_id
origCh = Get number of channels
analysisChannel = 1
if origCh > 1
    input_id = 0
    bestRms = -1
    for ch from 1 to origCh
        selectObject: orig_id
        tempCh = Extract one channel: ch
        selectObject: tempCh
        tempRms = Get root-mean-square: 0, 0
        if tempRms > bestRms
            if input_id <> 0
                removeObject: input_id
            endif
            input_id = tempCh
            bestRms = tempRms
            analysisChannel = ch
        else
            removeObject: tempCh
        endif
    endfor
    selectObject: input_id
    Rename: "partial_analysis_ch" + string$(analysisChannel)
    appendInfoLine: "Analysis driver: channel ", analysisChannel,
        ... " (highest RMS ", fixed$(bestRms, 4), "); output is mono."
else
    input_id = Copy: "input"
endif

# Use original sample rate (no downsampling needed — fast enough now)
selectObject: input_id
work_sr = Get sampling frequency
nyq = work_sr / 2
totdur = Get total duration

# Create output buffer
output_id = Create Sound from formula: "resynth", 1, 0, totdur, work_sr, "0"

# v0.4: window-sum envelope (analytic Hann per frame). The default
# 60/15 window/hop is COLA, but free parameters are not -- dividing
# by the exact sum makes any ratio artifact-free.
envsum_id = Create Sound from formula: "envsum", 1, 0, totdur, work_sr, "0"

# Constants
tr = 2 ^ (transpose_semitones / 12)
fr = additional_frequency_scale

# Cover the complete source. v0.4 used floor(...) with no +1 and could
# leave the final hop silent. The last frame is anchored to the source end.
if totdur <= window_length
    nframes = 1
else
    nframes = ceiling((totdur - window_length) / hop_size) + 1
endif

# Suppression width (Hz). Kept at the v0.4 value deliberately: broadening it
# or changing the analysis window removes part of the characteristic texture.
suppress_hz = 40

appendInfoLine: "Processing ", nframes, " frames..."

# === FRAME LOOP ===
for i from 0 to nframes - 1
    if (i mod 50) = 0
        perc = i / nframes * 100
        appendInfoLine: "Progress: ", fixed$(perc, 0), "%"
    endif

    # Time calculations. Final frame is shifted left if necessary so its
    # right edge reaches the source end instead of leaving an uncovered tail.
    if totdur <= window_length
        t_start = 0
        t_end = totdur
    else
        t_start = i * hop_size
        if t_start + window_length > totdur
            t_start = totdur - window_length
        endif
        t_end = t_start + window_length
    endif
    current_win_dur = t_end - t_start

    # A. EXTRACT FRAME
    selectObject: input_id
    frame_id = Extract part: t_start, t_end, "hanning", 1, "yes"
    
    # B. ANALYZE — Spectrum → Ltas for C-level peak queries
    spec_id = To Spectrum: "yes"

    # Ltas gives dB power spectrum with Get frequency of maximum (C-level)
    selectObject: spec_id
    ltas_id = To Ltas (1-to-1)

    # Also need magnitude matrix for reading amplitudes
    selectObject: spec_id
    mat_id = To Matrix
    Formula: "if row = 1 then sqrt(self^2 + self[2,col]^2) else 0 endif"
    nc = Get number of columns
    freq_step = nyq / (nc - 1)

    # D. FIND ALL PEAKS using Ltas C-level queries (no per-bin loop)
    # v0.5.1: keep peak frequencies locked to FFT-bin centres. In this deliberately
    # untracked engine, parabolic sub-bin motion causes phase cancellation between
    # overlapping grains even on a sustained note with modest vibrato.
    nFound = 0
    for k from 1 to max_partials_per_frame
        selectObject: ltas_id
        current_max_dB = Get maximum: min_frequency, max_frequency, "None"

        if current_max_dB > -80
            freq_hz = Get frequency of maximum: min_frequency, max_frequency, "None"
            nFound = nFound + 1

            # Read linear amplitude from magnitude matrix
            peakCol = round(freq_hz / freq_step) + 1
            if peakCol < 1
                peakCol = 1
            endif
            if peakCol > nc
                peakCol = nc
            endif
            selectObject: mat_id
            current_max_val = Get value in cell: 1, peakCol

            # Apply texture offsets. Stable mode maps each FFT bin to a fixed
            # detune/gain offset, so overlapping grains of a sustained partial do
            # not acquire a new frequency/phase relation every hop. Legacy mode
            # retains the original independent random offsets per analysis frame.
            if jitter_behaviour = 1
                freq_rand = freq_jitter * sin(peakCol * 12.9898 + 78.233)
                amp_rand = 1 + amp_jitter * sin(peakCol * 4.898 + 11.317)
            else
                freq_rand = randomUniform(-freq_jitter, freq_jitter)
                amp_rand = randomUniform(1.0 - amp_jitter, 1.0 + amp_jitter)
            endif
            peakAmp[nFound] = (current_max_val * amp_rand) / (current_win_dur * work_sr / 4)
            peakFreq[nFound] = (freq_hz + freq_rand) * tr * fr

            # Suppress peak in Ltas (set to -100 dB)
            sup_low = max(0, freq_hz - suppress_hz)
            sup_high = min(nyq, freq_hz + suppress_hz)
            selectObject: ltas_id
            Formula: "if x >= sup_low and x <= sup_high then -100 else self endif"
        else
            k = max_partials_per_frame
        endif
    endfor

    removeObject: frame_id, spec_id, mat_id, ltas_id

    # v0.4: accumulate this frame's analytic Hann into the
    # window-sum envelope (every frame, found partials or not --
    # the OLA gain is a property of the grid, not of detection)
    selectObject: envsum_id
    Formula (part): t_start, t_end, 1, 1,
        ... "self + 0.5 * (1 - cos(2*pi*(x - " + fixed$(t_start, 8)
        ... + ") / " + fixed$(current_win_dur, 8) + "))"

    # E. BUILD SINGLE FORMULA for all sines + Hann window
    if nFound > 0
        # Build formula string: sum of all sines × Hann window
        # Hann: 0.5 * (1 - cos(2*pi*(x-t_start)/dur))
        sineFormula$ = ""
        for p from 1 to nFound
            if peakFreq[p] > 20 and peakFreq[p] < nyq
                if sineFormula$ <> ""
                    sineFormula$ = sineFormula$ + " + "
                endif
                sineFormula$ = sineFormula$
                    ... + fixed$(peakAmp[p], 8)
                    ... + "*sin(2*pi*" + fixed$(peakFreq[p], 2) + "*x)"
            endif
        endfor

        if sineFormula$ <> ""
            # Create grain with all sines in one Formula call
            Create Sound from formula: "grain", 1, t_start, t_end, work_sr,
                ... "(" + sineFormula$ + ") * 0.5 * (1 - cos(2*pi*(x - "
                ... + fixed$(t_start, 8) + ") / " + fixed$(current_win_dur, 8) + "))"
            grain_id = selected("Sound")

            # OLA into output using Formula (part) + col-indexed access
            selectObject: output_id
            s1 = Get sample number from time: t_start
            if s1 < 1
                s1 = 1
            endif
            sOff = s1 - 1

            Formula (part): t_start, t_end, 1, 1,
                ... "self + object[" + string$(grain_id) + ", col - " + string$(sOff) + "]"

            removeObject: grain_id
        endif
    endif
endfor

# === FINALIZE ===
# v0.4: exact OLA normalization
envStr$ = string$(envsum_id)
selectObject: output_id
Formula: "self / (object[" + envStr$ + ", 1, col] + 1e-6)"
removeObject: envsum_id

selectObject: output_id
Rename: orig_name$ + "_resynth_" + presetName$
outPeakChk = Get absolute extremum: 0, 0, "None"
if outPeakChk > 1e-9
    Scale intensity: 70
else
    appendInfoLine: "NOTE: no partials found anywhere -- output is silent."
endif

removeObject: input_id

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Sinusoidal Resynthesis: " + orig_name$ + " [" + presetName$ + "]"
    
    selectObject: orig_id
    origVizPeak = Get absolute extremum: 0, 0, "None"
    selectObject: output_id
    outVizPeak = Get absolute extremum: 0, 0, "None"
    waveVizPeak = 1.05 * max(origVizPeak, outVizPeak)
    if waveVizPeak < 1e-12
        waveVizPeak = 1
    endif

    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: orig_id
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, -waveVizPeak, waveVizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original"
    
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: output_id
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, -waveVizPeak, waveVizPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Resynthesized"
    
    vizSpecMax = min(5000, nyq)

    Select outer viewport: 0, 4, 2.0, 3.8
    selectObject: orig_id
    if origCh > 1
        vizOrig = Extract one channel: 1
    else
        vizOrig = Copy: "vizOrig"
    endif
    origSpecID = To Spectrogram: 0.01, vizSpecMax, 0.002, 20, "Gaussian"
    removeObject: vizOrig
    selectObject: origSpecID
    Paint: 0, 0, 0, vizSpecMax, 100, "yes", 50, 6, 0, "no"
    Font size: 8
    Text top: "no", "Original Spectrogram"
    removeObject: origSpecID
    
    Select outer viewport: 4, 8, 2.0, 3.8
    selectObject: output_id
    resSpecID = To Spectrogram: 0.01, vizSpecMax, 0.002, 20, "Gaussian"
    selectObject: resSpecID
    Paint: 0, 0, 0, vizSpecMax, 100, "yes", 50, 6, 0, "no"
    Text top: "no", "Resynthesized Spectrogram"
    removeObject: resSpecID
    
    Select outer viewport: 0, 8, 4.0, 4.6
    Select inner viewport: 0.5, 7.7, 4.05, 4.55
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Partials: " + string$(max_partials_per_frame)
    Text: 0.18, "left", 0.5, "half", "Jitter: " + fixed$(freq_jitter, 1) + " Hz (" + if jitter_behaviour=1 then "stable" else "frame-random" fi + ")"
    Text: 0.38, "left", 0.5, "half", "Transpose: " + fixed$(transpose_semitones, 0)
    Text: 0.55, "left", 0.5, "half", "Freq scale: " + fixed$(additional_frequency_scale, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", orig_name$, "_resynth_", presetName$

if play_result
    selectObject: output_id
    Play
endif

# Keep original + result selected consistently after optional playback.
selectObject: orig_id
plusObject: output_id