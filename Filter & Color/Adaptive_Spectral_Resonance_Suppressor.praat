# ============================================================
# Praat AudioTools - Adaptive Spectral Resonance Suppressor.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.6 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Adaptive multiband spectral attenuator, inspired by the idea
#   behind Oeksound Soothe2. It detects bands whose power protrudes
#   above the local spectral envelope and attenuates them dynamically
#   across time and frequency.
#
#   Resolution, stated plainly: at the default 24 log-spaced bands
#   from 60 Hz to 16 kHz this is about 3 bands per octave, i.e. a
#   third of an octave each. A resonance at 4.2 kHz is attenuated by
#   pulling down a band roughly 3959-4997 Hz wide. That is multiband
#   attenuation, NOT a narrow notch: nothing here changes filter Q or
#   narrows a band. Sharpness redistributes reduction toward the
#   strongest peak in a frame; it does not narrow anything. For
#   genuinely narrowband work, raise Number_of_bands substantially.
#
#   This is NOT hum removal — does NOT assume harmonic series.
#
#   Pipeline:
#     1. Filter signal into N log-spaced frequency bands
#     2. Measure time-varying power per band (Intensity)
#     3. For each time frame, smooth power across bands to
#        estimate the local spectral envelope (baseline)
#     4. Detect resonances: excess above baseline > threshold
#     5. Compute gain reduction map with sharpness, LF protect,
#        HF softness, and depth limiting
#     6. Temporal smoothing via attack/release envelope follower
#     7. Apply time-varying gain envelopes per band and sum
#        (filterbank resynthesis)
#     8. Wet/dry mix and output gain
#
#   Handles mono and stereo (channels processed independently).
#
#   Soothe2 parameter mapping:
#     Depth       -> maxReduction_dB (how much to cut)
#     Sharpness   -> sharpness (narrow vs broad suppression)
#     Selectivity -> threshold_dB (how prominent a peak must be)
#     Attack      -> attack_ms (how fast suppression engages)
#     Release     -> release_ms (how fast suppression releases)
#
# Changelog v1.6 (2026):
#   - The main form is compacted; technical analysis/render controls
#     moved to an optional Advanced settings dialog with identical defaults.
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v1.5 (from v1.4) — reviewed by running the script under
# Parselmouth, so these are measurements. Identity reconstruction now
# returns 74.2 dB SNR mono and 74.7 dB over four channels, and the
# frame grid, attack/release, statistics and Nyquist ordering all
# passed. What was still broken:
#   - A Sound not starting at time 0 was reported as suppressed and
#     returned UNCHANGED. Measured: the same signal at t=0 gave -5.93 dB
#     RMS change, and at t=5 s gave 0.00 dB with correlation 1.000000,
#     while both reported 6.0 dB of peak reduction. frameX1 from the
#     Intensity object is ABSOLUTE time, so for a Sound at 5.0-6.2 s
#     envOffset pointed far past the end of the 1.2 s envelope buffer,
#     "if c2 >= c1" never held, and every gain stayed at 1. Fixed at the
#     root: all analysis and processing now run on a work copy shifted
#     to 0, and the source time domain is restored at the end.
#   - The multichannel assembly created its buffer over 0..duration, so
#     a four-channel file at 2.0-3.2 s kept its channels but came back
#     at 0.0-1.2 s. Covered by the same restore.
#   - The visualization crashed for non-zero xmin: panels query fixed
#     ranges like "Get absolute extremum: 0, zoomDur", which returned
#     undefined and then broke Axes. Both display copies are shifted
#     to 0.
#   - Short files: v1.4 shrank the window but not the time step, so a
#     50 ms file stopped with one frame at the default 10 ms step. The
#     window now takes a quarter of the file and the step is sized to
#     fit at least four frames in what remains; the real minimum is
#     40 ms and the message says so.
#   - Smoothing_span added. In Hz mode the label still cannot mean much
#     on a log band layout - above about 1 kHz the band spacing exceeds
#     400 Hz, so a "400 Hz" setting yields a 3.52-5.61 kHz baseline at
#     4.45 kHz. Octaves mode holds a constant span in every register and
#     is the natural model for a third-octave bank. Hz stays the default
#     because the presets are tuned in it, and the report now prints the
#     baseline actually used at the bottom, middle and top of the range.
#   - The full-waveform panel scales from max(original, processed) peak;
#     v1.4 used the original alone and clipped a louder result at the
#     panel edge.
#
# Changelog v1.4 (from v1.3) — static review, no Praat run on either side:
#   - RESIDUAL RECONSTRUCTION. The filterbank only covered
#     Min_band_Hz..Max_frequency_Hz, and the output was built from
#     "0" plus the bands, so everything below 60 Hz and above 16 kHz
#     was discarded even at 0 dB of reduction: the result was a fixed
#     bandpass of the source, never the source. The output is now
#     residual + sum(band x gain), where residual = original minus the
#     unmodified band sum. With every gain at 1 the output is the
#     input, and crossover mismatch is preserved rather than lost.
#   - TIME MAP TAKEN FROM THE INTENSITY OBJECT. v1.3 invented its own
#     grid with floor(duration / time_step) and wrote frame 1 at the
#     start of the file. Praat places Intensity frames at
#     x1 + (n-1)*dx with x1 at the centre of the first window, and
#     produces floor((duration - physicalWindow)/step) + 1 of them.
#     At the defaults that is 95 frames for a 1 s file, not 100: five
#     frames were filled with -80 dB (releasing suppression early),
#     the active-frame percentage was computed against the wrong
#     total, and the whole reduction map sat about 25 ms early.
#     nFrames, dx and x1 now come from a probe Intensity.
#   - envRate = round(1 / time_step) removed. At time_step 0.033 the
#     true rate is 30.303 Hz and the rounded 30 Hz lost the last 18
#     frames of a 60 s file into a single sample. The envelope grid
#     now uses 1/dx exactly, with the frame times Praat reports.
#   - Short-file guard. To Intensity needs duration >= 6.4/pitchFloor,
#     which with pitchFloor = 3.2/window is duration >= 2 x window.
#     A 50 ms file passed the 0.05 s check and then failed inside
#     To Intensity. The window is now reduced to fit, or the file is
#     refused with the reason.
#   - Smoothing_bandwidth_Hz is measured in Hz. v1.3 converted it to a
#     neighbour COUNT via the local band width, so 400 Hz meant about
#     +/-1 band everywhere, spanning 60-776 Hz at the bottom and
#     7959-16000 Hz at the top. Neighbours are now chosen by actual
#     distance between band centres.
#   - Statistics come from the smoothed map sm[], not the target map
#     rd[]. v1.3 reported the reduction it wanted, not the one it
#     applied: attack lowered it and release added active frames that
#     went uncounted.
#   - Attack applies to the first frame. v1.3 seeded sm[first] =
#     rd[first], so a resonance present at the start was suppressed
#     instantly however long Attack was set.
#   - Every channel is kept. v1.3 looped over all channels but
#     recombined only 1 and 2, so channels 3+ were computed, orphaned
#     and dropped without a word.
#   - Frequency validation order fixed: clamping Max to Nyquist-100
#     and then raising it to a 2000 Hz floor could leave it ABOVE
#     Nyquist (3 kHz sample rate gave 2000 Hz against a 1500 Hz
#     Nyquist). Min < Max is now required too.
#   - The difference panel is labelled "Difference signal". It is not
#     only removed resonance: it also carries band-edge losses, the
#     wet/dry mix, output gain and any clip scaling.
#
# Changelog v1.3 (from v1.2):
#   - Audio pipeline UNCHANGED. Output is bit-identical to v1.2
#     for the same form parameters. Same 9-phase processing
#     (filter -> intensity -> spectral smoothing -> detection ->
#     sharpness -> reduction -> temporal smoothing -> envelope
#     build -> filterbank resynthesis). Same 5 presets with
#     same values. Same parameter clamping. Same mono/stereo
#     handling. Same wet/dry mix and output gain logic.
#   - NEW: Show_spectrum boolean form toggle (default 1, ON).
#     v1.2 always computed `To Spectrum` calls for the
#     visualization. Default ON because the spectrum IS the
#     primary diagnostic for a spectral processor; OFF skips
#     the spectrum calls and replaces Panel A with a parameter
#     report.
#   - NEW: Play_result boolean form toggle (default 1, ON).
#     v1.2 unconditionally `Play`d at the end; v1.3 makes it
#     optional for batch processing.
#   - Output filename now includes preset name: e.g.
#     `originalName_SootheLike_Moderate` (was just
#     `originalName_SootheLike`). Each preset case now assigns
#     a `presetName$` variable used both in the filename and
#     in the visualization metadata.
#   - Visualization rewritten to suite 8x8 standard (v1.2 was
#     8x7.35 with 4 audio panels + legend strip):
#       Title bar + metadata subtitle (preset, bands, depth,
#         sharpness, threshold)
#       Panel A (left, headline): spectrum comparison (original
#         blue vs processed green) OR parameter report (when
#         Show_spectrum = OFF). The spectral processor's
#         signature output.
#       Panel B (right, headline): difference signal time-series
#         (the "what was removed" diagnostic) — preserved from
#         v1.2 in red, now positioned as headline
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         blue = processed) — consolidates v1.2's two separate
#         waveform panels into one
#       Panel D: full waveform comparison (gray = original,
#         blue = processed, overlaid)
#       Panel E: light-grey summary stats bar (suite standard)
#         with peak reduction, average reduction, active-frame
#         percentage, mix/gain settings, output stats. Replaces
#         v1.2's legend strip with a stats line.
#   - Cross-channel statistics tracking: v1.2 tracked
#     peakReduction/totalReduction/reductionCount per channel
#     but the variables were script-level, so only the LAST
#     channel's values persisted. v1.3 explicitly accumulates
#     across channels for the summary bar.
#
# Changelog v1.2 (from v1.1):
#   - Default bands reduced to 24 (was 32): 25% less work
#   - Eliminated Extract part on band Sounds: chOut bounds
#     the Formula evaluation so FFT padding is ignored
#   - Batch size increased to 8 bands per Formula call
#   - Pre-computed combined band scale (LF x HF) per band
#   - Restored Resample: object[] in Formula is column-based
#     (same sample index), NOT time-based — low-rate envelopes
#     must be resampled to audio rate for correct alignment
#
# Changelog v1.1 (from v1.0):
#   - Single filter pass (was: filter twice)
#   - Intensity read via Down to Matrix + Get value in cell
#   - selectObject removed from all inner loops
#   - Batched multiply+accumulate Formula
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Spectral & Frequency Domain
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
originalDur = Get total duration
originalXmin = Get start time
originalXmax = Get end time
sampleRate = Get sampling frequency
nyquist = sampleRate / 2
nChannels = Get number of channels

if originalDur < 0.040
    exitScript: "Sound too short: " + fixed$(originalDur * 1000, 1) + " ms. The Intensity " +
    ... "window needs four times its own length in audio and the shortest usable window " +
    ... "is 10 ms, so at least 40 ms is required. Between 40 and roughly 200 ms the " +
    ... "window and time step are reduced automatically."
endif

# ============================================================
# FORM
# ============================================================
form Spectral Soothe v1.6
    optionmenu Preset: 1
        option Custom
        option Gentle
        option Moderate
        option Aggressive
        option Vocal Clarity
        option De-Harsh
    comment === Musical controls ===
    positive Threshold_dB 3.0
    positive Max_reduction_dB 6.0
    real Sharpness 0.5
    positive Attack_ms 10
    positive Release_ms 80
    positive Protect_Hz 150
    real Protect_amount 0.7
    real Mix 1.0
    real Output_gain_dB 0.0
    boolean Advanced_settings 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Advanced defaults are identical to the original v1.5 form.
window_length_s = 0.030
time_step_s = 0.010
smoothing_span = 1
smoothing_bandwidth_Hz = 400
smoothing_width_octaves = 1.0
hF_soft_Hz = 10000
number_of_bands = 24
min_band_Hz = 60
max_frequency_Hz = 16000
show_spectrum = 1
if advanced_settings
    form Spectral Soothe - Advanced settings
        positive Window_length_s 0.030
        positive Time_step_s 0.010
        optionmenu Smoothing_span: 1
            option Hz (Smoothing_bandwidth_Hz below)
            option Octaves (Smoothing_width_octaves below)
        positive Smoothing_bandwidth_Hz 400
        positive Smoothing_width_octaves 1.0
        positive HF_soft_Hz 10000
        integer Number_of_bands 24
        positive Min_band_Hz 60
        positive Max_frequency_Hz 16000
        boolean Show_spectrum 1
    endform
endif
# ============================================================
# PRESETS
# ============================================================
if preset = 2
    # Gentle
    threshold_dB = 4.0
    max_reduction_dB = 4.0
    sharpness = 0.3
    attack_ms = 15
    release_ms = 120
    smoothing_bandwidth_Hz = 500
    protect_Hz = 200
    protect_amount = 0.8
    presetName$ = "Gentle"
elsif preset = 3
    # Moderate
    threshold_dB = 3.0
    max_reduction_dB = 6.0
    sharpness = 0.5
    attack_ms = 10
    release_ms = 80
    smoothing_bandwidth_Hz = 400
    protect_Hz = 150
    protect_amount = 0.7
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive
    threshold_dB = 1.5
    max_reduction_dB = 12.0
    sharpness = 0.6
    attack_ms = 5
    release_ms = 60
    smoothing_bandwidth_Hz = 300
    protect_Hz = 120
    protect_amount = 0.5
    presetName$ = "Aggressive"
elsif preset = 5
    # Vocal Clarity
    threshold_dB = 2.5
    max_reduction_dB = 8.0
    sharpness = 0.7
    attack_ms = 8
    release_ms = 70
    smoothing_bandwidth_Hz = 350
    protect_Hz = 250
    protect_amount = 0.9
    hF_soft_Hz = 12000
    presetName$ = "VocalClarity"
elsif preset = 6
    # De-Harsh
    threshold_dB = 2.0
    max_reduction_dB = 10.0
    sharpness = 0.5
    attack_ms = 8
    release_ms = 90
    smoothing_bandwidth_Hz = 400
    protect_Hz = 200
    protect_amount = 0.8
    hF_soft_Hz = 8000
    presetName$ = "DeHarsh"
else
    presetName$ = "Custom"
endif

# ============================================================
# CLAMP PARAMETERS
# ============================================================
if window_length_s < 0.010
    window_length_s = 0.010
endif
if window_length_s > 0.100
    window_length_s = 0.100
endif
if time_step_s < 0.002
    time_step_s = 0.002
endif
if time_step_s > 0.050
    time_step_s = 0.050
endif
if smoothing_bandwidth_Hz < 50
    smoothing_bandwidth_Hz = 50
endif
if smoothing_bandwidth_Hz > 2000
    smoothing_bandwidth_Hz = 2000
endif
if threshold_dB < 0.5
    threshold_dB = 0.5
endif
if threshold_dB > 12
    threshold_dB = 12
endif
if max_reduction_dB < 1
    max_reduction_dB = 1
endif
if max_reduction_dB > 24
    max_reduction_dB = 24
endif
if sharpness < 0
    sharpness = 0
endif
if sharpness > 1
    sharpness = 1
endif
if attack_ms < 1
    attack_ms = 1
endif
if release_ms < 10
    release_ms = 10
endif
if protect_amount < 0
    protect_amount = 0
endif
if protect_amount > 1
    protect_amount = 1
endif
if number_of_bands < 8
    number_of_bands = 8
endif
if number_of_bands > 64
    number_of_bands = 64
endif
if min_band_Hz < 20
    min_band_Hz = 20
endif
# Order matters. v1.3 capped Max at Nyquist-100 and THEN raised it to a
# 2000 Hz floor, so a 3000 Hz file (Nyquist 1500) ended up asking for
# 2000 Hz of band coverage above its own Nyquist.
if max_frequency_Hz < 2000
    max_frequency_Hz = 2000
endif
if max_frequency_Hz > nyquist - 100
    max_frequency_Hz = nyquist - 100
endif
if max_frequency_Hz <= min_band_Hz
    exitScript: "Max_frequency_Hz (" + fixed$(max_frequency_Hz, 0) +
    ... " Hz after clamping to Nyquist) must be above Min_band_Hz (" +
    ... fixed$(min_band_Hz, 0) + " Hz). With Max below Min the band ratio falls under 1 " +
    ... "and the bands run backwards."
endif
if max_frequency_Hz / min_band_Hz < 2
    exitScript: "The band range " + fixed$(min_band_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) +
    ... " Hz is under one octave; " + string$(number_of_bands) + " bands cannot be spread " +
    ... "across it usefully."
endif

# To Intensity needs duration >= 6.4 / pitchFloor, and pitchFloor here is
# 3.2 / window, so it needs duration >= 2 x window. v1.3 accepted any
# file of 0.05 s and then failed inside To Intensity for a 30 ms window.
# To Intensity needs duration >= 6.4 / pitchFloor, and pitchFloor here is
# 3.2 / window, so the physical window is 2 x window_length_s. Fitting
# the window is not enough on its own: the frame count is
# floor((duration - 2*window) / step) + 1, so the STEP has to fit in
# what is left. v1.4 shrank only the window, so a 50 ms file stopped
# with "only 1 frame" at the default 10 ms step even though the message
# implied 50 ms was supported. Take a quarter of the file for the
# window, which leaves half the file for frames, and size the step to
# put at least four frames in it.
windowRequested_s = window_length_s
stepRequested_s = time_step_s

maxWindowForDur = originalDur / 4
if window_length_s > maxWindowForDur
    window_length_s = maxWindowForDur
endif
if window_length_s < 0.010
    exitScript: "Sound is too short for this analysis: " + fixed$(originalDur * 1000, 1) +
    ... " ms. The Intensity window needs four times its own length in audio and the " +
    ... "shortest usable window is 10 ms, so at least 40 ms is required."
endif

maxStepForDur = (originalDur - 2 * window_length_s) / 4
if time_step_s > maxStepForDur
    time_step_s = maxStepForDur
endif
if time_step_s < 0.002
    time_step_s = 0.002
endif
if mix < 0
    mix = 0
endif
if mix > 1
    mix = 1
endif

numBands = number_of_bands

# ============================================================
# BAND FREQUENCY COMPUTATION (log-spaced)
# ============================================================
bandRatio = (max_frequency_Hz / min_band_Hz) ^ (1 / numBands)
for b from 1 to numBands
    bandLow[b] = min_band_Hz * bandRatio ^ (b - 1)
    bandHigh[b] = min_band_Hz * bandRatio ^ b
    bandCenter[b] = sqrt(bandLow[b] * bandHigh[b])
    bandWidth[b] = bandHigh[b] - bandLow[b]
    bandSmooth[b] = bandWidth[b] * 0.4
endfor

# Pre-compute per-band scalars
for b from 1 to numBands
    localBW = bandWidth[b]
    if localBW < 1
        localBW = 1
    endif
    # Neighbours by actual distance between band centres.
    #
    # Hz mode does what the label says, but on a log band layout the
    # label cannot mean much: above about 1 kHz the spacing between
    # 24 bands already exceeds 400 Hz, so the minimum of one band each
    # way takes over and the baseline at 4.45 kHz spans 3.52-5.61 kHz
    # from a "400 Hz" setting. Octave mode is the natural model for a
    # third-octave bank and holds a constant span in every register.
    # Hz remains the default because the presets are tuned in Hz.
    smoothLo[b] = b
    smoothHi[b] = b
    if smoothing_span = 1
        for nb from 1 to numBands
            if abs(bandCenter[nb] - bandCenter[b]) <= smoothing_bandwidth_Hz / 2
                if nb < smoothLo[b]
                    smoothLo[b] = nb
                endif
                if nb > smoothHi[b]
                    smoothHi[b] = nb
                endif
            endif
        endfor
    else
        octHalf = smoothing_width_octaves / 2
        for nb from 1 to numBands
            if abs(ln(bandCenter[nb] / bandCenter[b]) / ln(2)) <= octHalf
                if nb < smoothLo[b]
                    smoothLo[b] = nb
                endif
                if nb > smoothHi[b]
                    smoothHi[b] = nb
                endif
            endif
        endfor
    endif
    # A baseline of one band is the band itself, which makes the excess
    # identically zero; always take at least one neighbour each way.
    if smoothLo[b] = b and smoothHi[b] = b
        smoothLo[b] = max(1, b - 1)
        smoothHi[b] = min(numBands, b + 1)
    endif
    smoothN[b] = smoothHi[b] - smoothLo[b] + 1

    # Combined LF protect × HF softness (single multiply in hot loop)
    bandScale[b] = 1.0
    if bandCenter[b] < protect_Hz and protect_Hz > 0
        bandScale[b] = 1 - protect_amount
            ... + protect_amount * (bandCenter[b] / protect_Hz)
    endif
    if bandCenter[b] > hF_soft_Hz and hF_soft_Hz < max_frequency_Hz
        hfRange = max_frequency_Hz - hF_soft_Hz
        if hfRange > 0
            hfs = 1 - 0.5 * ((bandCenter[b] - hF_soft_Hz) / hfRange)
            if hfs < 0.3
                hfs = 0.3
            endif
            bandScale[b] = bandScale[b] * hfs
        endif
    endif
endfor

# Intensity analysis pitch
intMinPitch = 3.2 / window_length_s
if intMinPitch < 30
    intMinPitch = 30
endif

# ============================================================
# WORK COPY — time domain normalized to 0
# ============================================================
# Every buffer in this script (envelopes, per-channel outputs, the
# multichannel assembly) is created over 0..originalDur, and every
# column offset is computed as time x sampleRate. v1.4 took frameX1
# straight from the Intensity object, which reports ABSOLUTE time: for
# a Sound living in 5.0-6.2 s the first frame is at about 5.039 s, so
# envOffset pointed hundreds of thousands of samples past the end of a
# 1.2 s buffer, "if c2 >= c1" never held, every gain envelope stayed at
# 1, and the script reported 6 dB of suppression while returning the
# input untouched. Shifting a work copy to 0 removes the whole class of
# problem instead of patching each offset; the source domain is restored
# at the very end.
selectObject: originalID
workID = Copy: "soothe_work"
Shift times to: "start time", 0

# ============================================================
# FRAME GRID — taken from a real Intensity object
# ============================================================
# v1.3 invented nFrames = floor(duration / time_step) and then wrote
# frame 1 at the start of the file. Praat produces
# floor((duration - physicalWindow) / step) + 1 frames, centred at
# x1 + (n-1)*dx with x1 in the middle of the first window. At the
# defaults that is 95 frames for a 1 s file rather than 100: five were
# padded with -80 dB, releasing suppression before the file ended, and
# the entire map sat about 25 ms early. Filtering does not change the
# duration or the rate, so one probe fixes the grid for every band and
# every channel.
selectObject: workID
if nChannels > 1
    probeSnd = Extract one channel: 1
else
    probeSnd = Copy: "grid_probe"
endif
selectObject: probeSnd
probeInt = To Intensity: intMinPitch, time_step_s, "yes"
selectObject: probeInt
nFrames = Get number of frames
frameDx = Get time step
frameX1 = Get time from frame number: 1
removeObject: probeInt, probeSnd

if nFrames < 2
    exitScript: "The analysis produced only " + string$(nFrames) + " frame(s). Use a shorter " +
    ... "Window_length_s or Time_step_s, or a longer Sound."
endif

# Attack/release coefficients
attackTime = attack_ms / 1000
releaseTime = release_ms / 1000
if attackTime < time_step_s
    attackTime = time_step_s
endif
# The coefficients follow the REAL frame spacing Praat used
attackCoeff = 1 - exp(-frameDx / attackTime)
releaseCoeff = 1 - exp(-frameDx / releaseTime)

# Sharpness exponent
sharpExp = 1 + sharpness * 4

# ============================================================
# ENVELOPE GRID
# ============================================================
# The low-rate envelope carries the exact frame times: sample i sits at
# frameX1 + (i-1)*frameDx. v1.3 used round(1 / time_step) as a rate and
# wrote frame f into sample f of a buffer starting at 0, so with
# time_step 0.033 (true rate 30.303 Hz, rounded to 30) the last 18
# frames of a 60 s file all collapsed into the final sample.
envRateExact = 1 / frameDx
envXmin = frameX1 - frameDx / 2
envXmax = frameX1 + (nFrames - 0.5) * frameDx
envOffset = round(envXmin * sampleRate)

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: "  SPECTRAL SOOTHE v1.6"
writeInfoLine: "  Resonance suppression pipeline"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source:  ", originalName$, " | ",
    ... fixed$(originalDur, 2), " s | ", sampleRate, " Hz | ",
    ... nChannels, " ch"
appendInfoLine: "Preset:  ", presetName$
appendInfoLine: "Bands:   ", numBands, " (",
    ... round(min_band_Hz), "-", round(max_frequency_Hz), " Hz, log)"
appendInfoLine: "Frames:  ", nFrames, " @ ", fixed$(frameDx * 1000, 2), " ms",
    ... " (first at ", fixed$(frameX1 * 1000, 1), " ms)"
bandsPerOctave = numBands / (ln(max_frequency_Hz / min_band_Hz) / ln(2))
appendInfoLine: "Resolution: ", fixed$(bandsPerOctave, 2), " bands/octave",
    ... " -> band at 4 kHz spans about ", round(4000 / sqrt(bandRatio)), "-",
    ... round(4000 * sqrt(bandRatio)), " Hz"
appendInfoLine: "  This is multiband attenuation, not a narrow notch."
if window_length_s <> windowRequested_s
    appendInfoLine: "  Window shortened to fit the file: ",
    ... fixed$(windowRequested_s * 1000, 1), " -> ", fixed$(window_length_s * 1000, 1), " ms"
endif
if time_step_s <> stepRequested_s
    appendInfoLine: "  Time step shortened to fit the file: ",
    ... fixed$(stepRequested_s * 1000, 2), " -> ", fixed$(time_step_s * 1000, 2), " ms"
endif
appendInfoLine: ""
if smoothing_span = 1
    appendInfoLine: "Detection:  smooth ", round(smoothing_bandwidth_Hz),
        ... " Hz (requested) | thresh ", fixed$(threshold_dB, 1), " dB"
else
    appendInfoLine: "Detection:  smooth ", fixed$(smoothing_width_octaves, 2),
        ... " octaves | thresh ", fixed$(threshold_dB, 1), " dB"
endif
# What the baseline window really spans, so the parameter cannot mislead
bMid = round(numBands / 2)
if bMid < 1
    bMid = 1
endif
appendInfoLine: "  Baseline at ", round(bandCenter[1]), " Hz: ",
    ... round(bandLow[smoothLo[1]]), "-", round(bandHigh[smoothHi[1]]), " Hz (",
    ... smoothN[1], " bands)"
appendInfoLine: "  Baseline at ", round(bandCenter[bMid]), " Hz: ",
    ... round(bandLow[smoothLo[bMid]]), "-", round(bandHigh[smoothHi[bMid]]), " Hz (",
    ... smoothN[bMid], " bands)"
appendInfoLine: "  Baseline at ", round(bandCenter[numBands]), " Hz: ",
    ... round(bandLow[smoothLo[numBands]]), "-", round(bandHigh[smoothHi[numBands]]),
    ... " Hz (", smoothN[numBands], " bands)"
appendInfoLine: "Suppress:   depth ", fixed$(max_reduction_dB, 1),
    ... " dB | sharp ", fixed$(sharpness, 2)
appendInfoLine: "Dynamics:   atk ", round(attack_ms),
    ... " ms | rel ", round(release_ms), " ms"
appendInfoLine: "Protect:    < ", round(protect_Hz),
    ... " Hz @ ", fixed$(protect_amount, 1),
    ... " | soft > ", round(hF_soft_Hz), " Hz"
appendInfoLine: ""

# ============================================================
# Cross-channel statistics accumulators (v1.3)
# v1.2 tracked these per channel but only the last channel's
# values survived to the summary. v1.3 aggregates across channels.
# ============================================================
xc_peakReduction = 0
xc_totalReductionSum = 0
xc_totalReductionCount = 0

# ============================================================
# MAIN PROCESSING LOOP (per channel)
# ============================================================

for ch from 1 to nChannels
    appendInfoLine: "-- Channel ", ch, " --"

    if nChannels = 1
        selectObject: workID
        chSnd = Copy: "ch_proc"
    else
        selectObject: workID
        chSnd = Extract one channel: ch
    endif

    # ========================================================
    # PHASE A: Filter all bands ONCE
    # ========================================================
    # No Extract part — chOut limits Formula evaluation,
    # so FFT padding beyond originalDur is ignored.

    appendInfoLine: "  Filtering ", numBands, " bands..."

    for b from 1 to numBands
        selectObject: chSnd
        bandSnd[b] = Filter (pass Hann band): bandLow[b], bandHigh[b], bandSmooth[b]
    endfor

    # ========================================================
    # PHASE B: Measure power per band via Intensity -> Matrix
    # ========================================================

    appendInfoLine: "  Measuring band power..."

    for b from 1 to numBands
        selectObject: bandSnd[b]
        bInt = To Intensity: intMinPitch, time_step_s, "yes"
        selectObject: bInt
        bMat = Down to Matrix
        removeObject: bInt

        selectObject: bMat
        nIntCols = Get number of columns
        useFrames = nIntCols
        if nFrames < useFrames
            useFrames = nFrames
        endif

        for f from 1 to useFrames
            val = Get value in cell: 1, f
            if val = undefined
                val = -80
            endif
            if val < -80
                val = -80
            endif
            pw[(b - 1) * nFrames + f] = val
        endfor
        for f from useFrames + 1 to nFrames
            pw[(b - 1) * nFrames + f] = -80
        endfor

        removeObject: bMat
    endfor

    # ========================================================
    # PHASE C: Resonance detection & gain map
    # ========================================================

    appendInfoLine: "  Computing resonance map..."

    peakReduction = 0
    totalReduction = 0
    reductionCount = 0

    for f from 1 to nFrames
        # Spectral smoothing: baseline
        for b from 1 to numBands
            sumVal = 0
            for nb from smoothLo[b] to smoothHi[b]
                sumVal += pw[(nb - 1) * nFrames + f]
            endfor
            bl[(b - 1) * nFrames + f] = sumVal / smoothN[b]
        endfor

        # Excess and resonance score
        maxR = 0
        for b from 1 to numBands
            idx = (b - 1) * nFrames + f
            excess = pw[idx] - bl[idx]
            if excess < 0
                excess = 0
            endif
            rScore = excess - threshold_dB
            if rScore < 0
                rScore = 0
            endif
            rs[idx] = rScore
            if rScore > maxR
                maxR = rScore
            endif
        endfor

        # Sharpness concentration
        if maxR > 0 and sharpness > 0.01
            for b from 1 to numBands
                idx = (b - 1) * nFrames + f
                if rs[idx] > 0
                    rNorm = rs[idx] / maxR
                    rs[idx] = rNorm ^ sharpExp * maxR
                endif
            endfor
        endif

        # Reduction with combined band scale
        for b from 1 to numBands
            idx = (b - 1) * nFrames + f
            redDB = rs[idx]
            if redDB > max_reduction_dB
                redDB = max_reduction_dB
            endif
            redDB = redDB * bandScale[b]
            rd[idx] = redDB
        endfor
    endfor

    # ========================================================
    # PHASE D: Temporal smoothing
    # ========================================================

    for b from 1 to numBands
        idx1 = (b - 1) * nFrames + 1
        # The envelope starts closed and the first frame goes through the
        # attack like any other. v1.3 seeded sm[first] = rd[first], so a
        # resonance sitting in frame 1 was suppressed instantly no matter
        # what Attack was set to.
        prev = 0
        target = rd[idx1]
        if target > prev
            sm[idx1] = prev + attackCoeff * (target - prev)
        else
            sm[idx1] = prev + releaseCoeff * (target - prev)
        endif
        for f from 2 to nFrames
            idx = (b - 1) * nFrames + f
            idxPrev = idx - 1
            target = rd[idx]
            prev = sm[idxPrev]
            if target > prev
                sm[idx] = prev + attackCoeff * (target - prev)
            else
                sm[idx] = prev + releaseCoeff * (target - prev)
            endif
        endfor
    endfor

    # Statistics from the map that is actually applied. v1.3 measured
    # rd[], the target before attack and release, so it reported
    # reduction the audio never received and missed the active frames
    # that release adds on the way down.
    for b from 1 to numBands
        for f from 1 to nFrames
            idx = (b - 1) * nFrames + f
            redDB = sm[idx]
            if redDB > peakReduction
                peakReduction = redDB
            endif
            if redDB > 0.01
                totalReduction += redDB
                reductionCount += 1
            endif
        endfor
    endfor

    # Convert to linear gain
    for b from 1 to numBands
        for f from 1 to nFrames
            idx = (b - 1) * nFrames + f
            redDB = sm[idx]
            if redDB < 0.001
                gn[idx] = 1.0
            else
                gn[idx] = 10 ^ (-redDB / 20)
            endif
        endfor
    endfor

    # ========================================================
    # PHASE E: Build gain envelopes, resample to audio rate
    # ========================================================
    # object [id] in Formula is COLUMN-based (same sample index),
    # NOT time-based. A 100 Hz envelope referenced from a 44100 Hz
    # Formula would only cover the first 533/44100 = 0.012 s.
    # Resample to audio rate so columns align 1:1.

    appendInfoLine: "  Building envelopes..."

    for b from 1 to numBands
        # Low-rate envelope whose sample i sits at frameX1 + (i-1)*frameDx,
        # i.e. exactly where Praat put Intensity frame i.
        envSnd = Create Sound from formula: "env_lo", 1, envXmin,
            ... envXmax, envRateExact, "1"
        for f from 1 to nFrames
            Set value at sample number: 1, f, gn[(b - 1) * nFrames + f]
        endfor
        envUp = Resample: sampleRate, 50
        removeObject: envSnd

        selectObject: envUp
        envUpNs = Get number of samples
        envFirst = Get value at sample number: 1, 1
        envLast = Get value at sample number: 1, envUpNs

        # The analysed span starts a little after the file does and ends a
        # little before it. Copy it into a full-length buffer at the right
        # column offset and hold the edge gains outside, so the head and
        # tail are not silently released to unity.
        envFull = Create Sound from formula: "env_full", 1, 0,
            ... originalDur, sampleRate, "1"
        fullNs = Get number of samples
        c1 = envOffset + 1
        c2 = envOffset + envUpNs
        if c1 < 1
            c1 = 1
        endif
        if c2 > fullNs
            c2 = fullNs
        endif
        if c2 >= c1
            selectObject: envFull
            Formula (part): (c1 - 0.75) / sampleRate, (c2 - 0.25) / sampleRate, 1, 1,
                ... "object [" + string$(envUp) + ", 1, col - " + string$(envOffset) + "]"
            if c1 > 1
                Formula (part): 0, (c1 - 0.75) / sampleRate, 1, 1, string$(envFirst)
            endif
            if c2 < fullNs
                Formula (part): (c2 - 0.25) / sampleRate, originalDur, 1, 1, string$(envLast)
            endif
        endif
        removeObject: envUp
        envHR[b] = envFull
    endfor

    # ========================================================
    # PHASE F: Batched multiply+accumulate (8 bands per call)
    # ========================================================
    # Formula: "self + band1*env1 + band2*env2 + ... + band8*env8"
    # 3 calls for 24 bands.

    appendInfoLine: "  Applying filterbank..."

    # Residual reconstruction. v1.3 started the output at "0" and summed
    # only the bands, so everything outside Min_band_Hz..Max_frequency_Hz
    # was thrown away even with zero reduction - at 44.1 kHz that is
    # below 60 Hz and above 16 kHz, so the "unprocessed" result was a
    # fixed bandpass of the source. Starting from
    #   residual = original - sum(bands)
    # and adding sum(band x gain) means every gain at 1 reproduces the
    # input exactly, and any crossover mismatch stays in the residual.
    selectObject: chSnd
    chOut = Copy: "ch_out"

    batchSize = 8
    b = 1
    while b <= numBands
        bEnd = b + batchSize - 1
        if bEnd > numBands
            bEnd = numBands
        endif
        fStr$ = "self"
        for bb from b to bEnd
            fStr$ = fStr$ + " - object [" + string$(bandSnd[bb]) + "]"
        endfor
        selectObject: chOut
        Formula: fStr$
        b += batchSize
    endwhile

    b = 1
    while b <= numBands
        bEnd = b + batchSize - 1
        if bEnd > numBands
            bEnd = numBands
        endif
        fStr$ = "self"
        for bb from b to bEnd
            fStr$ = fStr$ + " + object ["
                ... + string$(bandSnd[bb])
                ... + "] * object ["
                ... + string$(envHR[bb]) + "]"
        endfor
        selectObject: chOut
        Formula: fStr$
        b += batchSize
    endwhile

    # Cleanup bands and envelopes
    for b from 1 to numBands
        removeObject: bandSnd[b], envHR[b]
    endfor

    processedCh[ch] = chOut
    removeObject: chSnd

    # Report
    if reductionCount > 0
        avgRed = totalReduction / reductionCount
    else
        avgRed = 0
    endif
    appendInfoLine: "  Peak reduction: ", fixed$(peakReduction, 1), " dB"
    appendInfoLine: "  Avg reduction (active): ", fixed$(avgRed, 1), " dB"
    appendInfoLine: "  Active frames: ",
        ... fixed$(reductionCount / (numBands * nFrames) * 100, 1), "%"
    appendInfoLine: ""

    # Aggregate to cross-channel totals
    if peakReduction > xc_peakReduction
        xc_peakReduction = peakReduction
    endif
    xc_totalReductionSum = xc_totalReductionSum + totalReduction
    xc_totalReductionCount = xc_totalReductionCount + reductionCount
endfor

# ============================================================
# RECOMBINE STEREO
# ============================================================
# Every channel that was processed is kept. v1.3 looped over all
# channels but recombined only 1 and 2, so a 4- or 6-channel file had
# its remaining channels computed, orphaned and dropped in silence.
if nChannels = 1
    processed = processedCh[1]
else
    selectObject: processedCh[1]
    outDurCh = Get total duration
    Create Sound from formula: "soothe_multi", nChannels, 0, outDurCh, sampleRate, "0"
    processed = selected("Sound")
    for ch from 1 to nChannels
        selectObject: processed
        Formula (part): 0, outDurCh, ch, ch,
            ... "object [" + string$(processedCh[ch]) + ", 1, col]"
    endfor
    for ch from 1 to nChannels
        removeObject: processedCh[ch]
    endfor
endif

# ============================================================
# WET/DRY MIX
# ============================================================
if mix < 0.999
    mixStr$ = fixed$(mix, 6)
    dryStr$ = fixed$(1 - mix, 6)
    selectObject: processed
    Formula: "self * " + mixStr$ + " + object [" + string$(workID)
        ... + "] * " + dryStr$
endif

# ============================================================
# OUTPUT GAIN
# ============================================================
if output_gain_dB <> 0
    outGainLin = 10 ^ (output_gain_dB / 20)
    outGainStr$ = fixed$(outGainLin, 6)
    selectObject: processed
    Formula: "self * " + outGainStr$
endif

# Prevent clipping
selectObject: processed
peakVal = Get absolute extremum: 0, 0, "None"
clipScaled = 0
if peakVal > 1.0
    Scale peak: 0.95
    clipScaled = 1
endif

# Put the result back where the source lived. The multichannel assembly
# below creates its buffer over 0..duration, so v1.4 also flattened a
# 2.0-3.2 s four-channel file to 0.0-1.2 s even when it had processed
# every channel correctly.
selectObject: processed
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif

selectObject: processed
Rename: originalName$ + "_SootheLike_" + presetName$

# Capture final stats for visualization
selectObject: processed
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

if xc_totalReductionCount > 0
    xc_avgRed = xc_totalReductionSum / xc_totalReductionCount
else
    xc_avgRed = 0
endif
xc_activePct = xc_totalReductionCount / (numBands * nFrames * nChannels) * 100

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization

    # Prepare mono copies of original and processed for display
    # Both display copies are put at time 0. The panels query fixed
    # ranges like "Get absolute extremum: 0, zoomDur", which returned
    # undefined for a Sound living at 5-6.2 s and then crashed Axes with
    # "left Bottom and top has the value undefined".
    selectObject: workID
    if nChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    selectObject: vizOrig
    Shift times to: "start time", 0

    selectObject: processed
    if nChannels > 1
        vizProc = Convert to mono
    else
        vizProc = Copy: "viz_proc"
    endif
    selectObject: vizProc
    Shift times to: "start time", 0

    selectObject: vizOrig
    oMax = Get absolute extremum: 0, 0, "None"
    selectObject: vizProc
    pMax = Get absolute extremum: 0, 0, "None"
    # v1.4 scaled the full-waveform panel from the ORIGINAL peak alone,
    # so a processed signal that ended up louder was clipped at the panel
    # edge. The zoom panel already took both.
    if pMax > oMax
        oMax = pMax
    endif
    if oMax < 0.001
        oMax = 0.001
    endif
    ampMax = oMax * 1.15

    # Compute difference signal once
    selectObject: vizOrig
    vizDiff = Copy: "viz_diff"
    selectObject: vizDiff
    Formula: "self - object [" + string$(vizProc) + "]"

    selectObject: vizDiff
    dMax = Get absolute extremum: 0, 0, "None"
    diffMax = dMax * 1.15
    if diffMax < 0.0001
        diffMax = ampMax * 0.3
    endif

    # Spectra (only if user opted in)
    if show_spectrum
        selectObject: vizOrig
        specOrig = To Spectrum: "yes"
        selectObject: vizProc
        specProc = To Spectrum: "yes"
    endif

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Spectral Soothe v1.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    if show_spectrum
        specMaxF = max_frequency_Hz
        if specMaxF > nyquist - 500
            specMaxF = nyquist - 500
        endif
        Axes: 0, specMaxF, -60, 10

        Paint rectangle: "{0.97, 0.97, 0.99}", 0, specMaxF, -60, 10

        # Reference grid
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        Dotted line
        gdb = -50
        while gdb <= 0
            Draw line: 0, gdb, specMaxF, gdb
            gdb += 10
        endwhile
        Solid line
        Line width: 1

        # Original spectrum (blue)
        selectObject: specOrig
        Colour: "{0.30, 0.45, 0.78}"
        Line width: 1.5
        Draw: 0, specMaxF, -60, 10, "no"

        # Processed spectrum (green)
        selectObject: specProc
        Colour: "{0.20, 0.65, 0.30}"
        Line width: 1.5
        Draw: 0, specMaxF, -60, 10, "no"
        Line width: 1

        # Inline legend
        Font size: 6
        Colour: "{0.30, 0.45, 0.78}"
        Text: specMaxF * 0.02, "left", 6, "half", "original"
        Colour: "{0.20, 0.65, 0.30}"
        Text: specMaxF * 0.14, "left", 6, "half", "processed"

        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 6
        Text left: "yes", "dB"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # Parameter report panel when spectrum is disabled
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.93, "half", "Detection:"

        Font size: 10
        Colour: "{0.20, 0.50, 0.80}"
        Text: 0.10, "left", 0.85, "half", "Threshold:    " + fixed$(threshold_dB, 1) + " dB"
        Text: 0.10, "left", 0.78, "half", "Smoothing BW: " + fixed$(smoothing_bandwidth_Hz, 0) + " Hz"
        Text: 0.10, "left", 0.71, "half", "Bands:        " + string$(numBands) + " (" + fixed$(min_band_Hz, 0) + "-" + fixed$(max_frequency_Hz, 0) + " Hz log)"

        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.62, "half", "Suppression:"

        Font size: 10
        Colour: "{0.85, 0.30, 0.30}"
        Text: 0.10, "left", 0.54, "half", "Max depth:    " + fixed$(max_reduction_dB, 1) + " dB"
        Text: 0.10, "left", 0.47, "half", "Sharpness:    " + fixed$(sharpness, 2)
        Text: 0.10, "left", 0.40, "half", "Attack:       " + fixed$(attack_ms, 0) + " ms"
        Text: 0.10, "left", 0.33, "half", "Release:      " + fixed$(release_ms, 0) + " ms"

        Font size: 9
        Colour: "{0.30, 0.30, 0.30}"
        Text: 0.05, "left", 0.24, "half", "Protection:"

        Font size: 10
        Colour: "{0.30, 0.62, 0.30}"
        Text: 0.10, "left", 0.16, "half", "LF protect:   < " + fixed$(protect_Hz, 0) + " Hz @ " + fixed$(protect_amount, 2)
        Text: 0.10, "left", 0.09, "half", "HF soft:      > " + fixed$(hF_soft_Hz, 0) + " Hz"
        Text: 0.10, "left", 0.02, "half", "Mix:          " + fixed$(mix * 100, 0) + "% wet"

        Colour: "Black"
        Draw inner box
    endif

    # ----------------------------------------------------------
    # PANEL B: DIFFERENCE SIGNAL  (right, headline)
    # Just the difference. It is not purely removed resonance: it also
    # carries the wet/dry mix, the output gain and any clip scaling.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    Axes: 0, originalDur, -diffMax, diffMax
    Paint rectangle: "{1.00, 0.96, 0.94}", 0, originalDur, -diffMax, diffMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, originalDur, 0

    selectObject: vizDiff
    Colour: "{0.85, 0.28, 0.22}"
    Line width: 1
    Draw: 0, originalDur, -diffMax, diffMax, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    if show_spectrum
        Text: 2.10, "centre", 7.30, "half", "Spectrum: original (blue) vs processed (green)"
    else
        Text: 2.10, "centre", 7.30, "half", "Parameter report (spectrum disabled)"
    endif
    Text: 6.10, "centre", 7.30, "half", "Difference signal (original - processed)"

    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # Gray = original, blue = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    zoomDur = 0.5
    if zoomDur > originalDur
        zoomDur = originalDur
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif

    selectObject: vizOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizProc
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15

    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0

    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"

    # Processed on top
    selectObject: vizProc
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = processed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (overlaid)
    # Gray = original, blue = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    Axes: 0, originalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, originalDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, originalDur, 0

    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, originalDur, -ampMax, ampMax, "no", "Curve"

    selectObject: vizProc
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, originalDur, -ampMax, ampMax, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full waveform  (gray = original, blue = processed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if show_spectrum
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Bands: " + string$(numBands)
        ... + "  |  Depth: " + fixed$(max_reduction_dB, 1) + " dB max"
        ... + "  |  Sharp: " + fixed$(sharpness, 2)
        ... + "  |  Thresh: " + fixed$(threshold_dB, 1) + " dB"
        ... + "  |  Atk/Rel: " + fixed$(attack_ms, 0) + "/" + fixed$(release_ms, 0) + " ms"

    Text: 0.02, "left", 0.28, "half",
        ... "Peak reduction: " + fixed$(xc_peakReduction, 1) + " dB"
        ... + "  |  Avg (active): " + fixed$(xc_avgRed, 1) + " dB"
        ... + "  |  Active: " + fixed$(xc_activePct, 1) + "%"
        ... + "  |  Mix: " + fixed$(mix * 100, 0) + "% wet"
        ... + "  |  Gain: " + fixed$(output_gain_dB, 1) + " dB"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Spec: " + specStr$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

    # Cleanup viz objects
    removeObject: vizOrig, vizProc, vizDiff
    if show_spectrum
        removeObject: specOrig, specProc
    endif
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# FINAL REPORT
# ============================================================
appendInfoLine: "-- Output --"
appendInfoLine: "  Peak reduction (all channels): ", fixed$(xc_peakReduction, 1), " dB"
appendInfoLine: "  Avg (active):                  ", fixed$(xc_avgRed, 1), " dB"
appendInfoLine: "  Active frame ratio:            ", fixed$(xc_activePct, 1), "%"
appendInfoLine: "  (measured on the smoothed map that was applied)"
appendInfoLine: "  Mix:    ", fixed$(mix * 100, 0), "% wet"
if clipScaled
    appendInfoLine: "  Clip guard: peak exceeded 1.0, scaled to 0.95"
endif
appendInfoLine: "  Gain:   ", fixed$(output_gain_dB, 1), " dB"
appendInfoLine: "  Result: ", originalName$ + "_SootheLike_" + presetName$
appendInfoLine: ""
appendInfoLine: "=================================================="

removeObject: workID

selectObject: processed
if play_result
    Play
endif