# ============================================================
# Praat AudioTools - Phase_History_Swap.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026) - original-rate processing only
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral phase/magnitude swap. Splits the sound at a chosen point;
#   takes the PHASE from the early segment and the MAGNITUDE from the
#   late segment, recombining them into a new spectrum. Creates time-
#   smeared, "history-swapped" textures. Stereo is synthesized by a small
#   split offset between L/R. Two phase mappings are available: the v0.3
#   duration-warp character and a frequency-aligned mapping that follows the
#   actual zero-padded FFT grids.
#
# Changelog v0.4.1 (2026):
#   - PERFORMANCE/QUALITY: removed Balanced/Fast resampling modes. Full-rate
#     processing is both faster in practice on the tested material and preserves
#     the complete source bandwidth. DSP is identical to v0.4 Full Quality.
#
# Changelog v0.4 (2026):
#   - MUSICAL PRIORITY: v0.3 duration-ratio phase warp remains available and
#     is the default character; exact physical-frequency alignment is added
#     as an alternate rather than silently replacing the sound.
#   - FIX: exact mode maps bins using the ACTUAL early/late FFT bin widths.
#     Fast FFT zero-padding means segment-duration ratio is not generally the
#     correct frequency-bin ratio.
#   - FIX: stereo/multichannel input is no longer averaged to mono before
#     analysis; the strongest-RMS channel drives the intentionally synthetic
#     stereo output, avoiding anti-phase cancellation.
#   - FORM/ROBUSTNESS: split/offset/tail/fade/output validation; zero stereo
#     offset and zero tail/fade are legal. Silent output scaling is safe.
#   - CLARITY: tail is explicitly the maximum retained FFT-generated tail;
#     actual retained tail depends on available zero-padding and is reported.
#   - VIZ: only corrected where misleading: shared waveform scale, analysis-
#     driver spectrogram, Nyquist-safe plot range, and actual retained-tail
#     proportion rather than a fixed decorative 70/30 split.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
# ============================================================

form Phase History Swap v0.4.1
    optionmenu Preset: 1
        option Custom
        option Subtle Swap (50%)
        option Early Swap (30%)
        option Late Swap (70%)
        option Extreme Early (20%)
        option Extreme Late (80%)
        option Ghost Echo (10%)
        option Time Smear (90%)
        option Wide Stereo (50% + 5%)
        option Narrow Focus (50% + 0.5%)
        option Asymmetric (40% + 3%)
    comment === Phase Mapping ===
    optionmenu Phase_mapping: 1
        option Warped history (v0.3 character)
        option Frequency-aligned swap
    comment === Custom Settings ===
    real Split_at_percent 50
    real Stereo_offset_percent 1.0
    comment (Left = Split; Right = Split + Offset; 0 offset is allowed)
    comment === Tail & Fade ===
    real Tail_duration_seconds 0.5
    comment (Maximum retained FFT-generated tail; actual tail is reported)
    real Fade_out_seconds 0.3
    comment (0 = off; otherwise fade to zero at the end)
    comment === Output ===
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply presets
if preset = 2
    split_at_percent = 50
    stereo_offset_percent = 1.0
    presetName$ = "Subtle"
elsif preset = 3
    split_at_percent = 30
    stereo_offset_percent = 1.5
    presetName$ = "Early"
elsif preset = 4
    split_at_percent = 70
    stereo_offset_percent = 1.5
    presetName$ = "Late"
elsif preset = 5
    split_at_percent = 20
    stereo_offset_percent = 2.0
    presetName$ = "ExtremeEarly"
elsif preset = 6
    split_at_percent = 80
    stereo_offset_percent = 2.0
    presetName$ = "ExtremeLate"
elsif preset = 7
    split_at_percent = 10
    stereo_offset_percent = 3.0
    presetName$ = "Ghost"
elsif preset = 8
    split_at_percent = 90
    stereo_offset_percent = 2.0
    presetName$ = "Smear"
elsif preset = 9
    split_at_percent = 50
    stereo_offset_percent = 5.0
    presetName$ = "WideStereo"
elsif preset = 10
    split_at_percent = 50
    stereo_offset_percent = 0.5
    presetName$ = "Narrow"
elsif preset = 11
    split_at_percent = 40
    stereo_offset_percent = 3.0
    presetName$ = "Asymmetric"
else
    presetName$ = "Custom"
endif

if phase_mapping = 1
    mappingName$ = "Warped history (v0.3)"
else
    mappingName$ = "Frequency-aligned"
endif

# === SETUP ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
numChannels = Get number of channels
orig_sr = Get sampling frequency
orig_dur = Get total duration

if split_at_percent <= 0 or split_at_percent >= 100
    exitScript: "Split percent must be greater than 0 and less than 100."
endif
if stereo_offset_percent < 0
    exitScript: "Stereo offset percent must be 0 or greater."
endif
if tail_duration_seconds < 0
    exitScript: "Tail duration must be 0 seconds or greater."
endif
if fade_out_seconds < 0
    exitScript: "Fade-out duration must be 0 seconds or greater."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and at most 1."
endif

offset_split = split_at_percent + stereo_offset_percent
offset_split = max(1, min(99, offset_split))

startTime = stopwatch

clearinfo
writeInfoLine: "╔══════════════════════════════════════════════════════════════╗"
writeInfoLine: "║    PHASE HISTORY SWAP v0.4.1                                ║"
writeInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Processing: original sample rate (full bandwidth)"
appendInfoLine: "Phase mapping: ", mappingName$
appendInfoLine: "Duration: ", fixed$(orig_dur, 2), " s"
appendInfoLine: "Requested max tail: ", fixed$(tail_duration_seconds, 2), " s"
appendInfoLine: "Fade: ", fixed$(fade_out_seconds, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Left split: ", split_at_percent, "%"
appendInfoLine: "Right split: ", offset_split, "%"
appendInfoLine: ""

# Prepare one mono analysis driver. The effect intentionally creates a new
# synthetic stereo image; for multichannel input choose the strongest-RMS
# channel instead of averaging, so anti-phase material cannot disappear.
analysisChannel = 1
if numChannels > 1
    workingID = 0
    bestRms = -1
    for ch from 1 to numChannels
        selectObject: originalID
        tempCh = Extract one channel: ch
        selectObject: tempCh
        tempRms = Get root-mean-square: 0, 0
        if tempRms > bestRms
            if workingID <> 0
                removeObject: workingID
            endif
            workingID = tempCh
            bestRms = tempRms
            analysisChannel = ch
        else
            removeObject: tempCh
        endif
    endfor
    selectObject: workingID
    Rename: "phase_history_driver_ch" + string$(analysisChannel)
    appendInfoLine: "Analysis driver: channel ", analysisChannel,
        ... " (highest RMS ", fixed$(bestRms, 4), ")"
else
    selectObject: originalID
    Copy: "working"
    workingID = selected("Sound")
endif

# Always process at the original sample rate.
workingSR = orig_sr

# Process LEFT channel
appendInfo: "Processing left channel..."
@FastPhaseSwap: workingID, split_at_percent, workingSR, tail_duration_seconds, phase_mapping
leftID = selected("Sound")
leftTail = retainedTailFromProc
appendInfoLine: " done"

# Process RIGHT channel
appendInfo: "Processing right channel..."
@FastPhaseSwap: workingID, offset_split, workingSR, tail_duration_seconds, phase_mapping
rightID = selected("Sound")
rightTail = retainedTailFromProc
appendInfoLine: " done"
appendInfoLine: "Retained FFT tail L/R: ", fixed$(leftTail, 3), "/", fixed$(rightTail, 3), " s"

# Match durations
selectObject: leftID
leftDur = Get total duration
selectObject: rightID
rightDur = Get total duration

maxDur = max(leftDur, rightDur)

# Pad shorter to match
if leftDur < maxDur
    selectObject: leftID
    Create Sound from formula: "pad", 1, 0, maxDur - leftDur, orig_sr, "0"
    silencePad = selected("Sound")
    selectObject: leftID, silencePad
    Concatenate
    leftID_new = selected("Sound")
    removeObject: leftID, silencePad
    leftID = leftID_new
endif

if rightDur < maxDur
    selectObject: rightID
    Create Sound from formula: "pad", 1, 0, maxDur - rightDur, orig_sr, "0"
    silencePad = selected("Sound")
    selectObject: rightID, silencePad
    Concatenate
    rightID_new = selected("Sound")
    removeObject: rightID, silencePad
    rightID = rightID_new
endif

# Combine to stereo
selectObject: leftID
plusObject: rightID
Combine to stereo
resultID = selected("Sound")
Rename: originalName$ + "_phaseswap_" + presetName$

# Apply fadeout to zero at the END
if fade_out_seconds > 0
    selectObject: resultID
    curr_dur = Get total duration
    
    fade_start = curr_dur - fade_out_seconds
    
    if fade_start < 0
        fade_start = 0
    endif
    
    actual_fade = curr_dur - fade_start
    
    s_start$ = fixed$(fade_start, 6)
    s_dur$ = fixed$(actual_fade, 6)
    
    Formula: "if x > " + s_start$ + " then self * 0.5 * (1 + cos(pi * (x - " + s_start$ + ") / " + s_dur$ + ")) else self endif"
endif

# Finalize
selectObject: resultID
resultPeakBefore = Get absolute extremum: 0, 0, "None"
if resultPeakBefore > 1e-15
    Scale peak: scale_peak
endif

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Phase History Swap: " + originalName$ + " [" + presetName$ + "]"
    
    # Analysis driver and result waveform use one amplitude scale.
    selectObject: workingID
    driverPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: resultID
    resultPeakViz = Get absolute extremum: 0, 0, "None"
    wavePeakViz = 1.05 * max(driverPeakViz, resultPeakViz)
    if wavePeakViz < 1e-12
        wavePeakViz = 1
    endif

    # Analysis-driver waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: workingID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, -wavePeakViz, wavePeakViz, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Analysis driver"
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, -wavePeakViz, wavePeakViz, "no", "Curve"
    
    # Mark fade start
    selectObject: resultID
    result_dur = Get total duration
    fade_start_mark = result_dur - fade_out_seconds
    if fade_start_mark > 0
        Colour: "{0.9, 0.7, 0.3}"
        Line width: 1
        Draw line: fade_start_mark, -wavePeakViz, fade_start_mark, wavePeakViz
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Phase Swapped (orange = fade)"
    
    vizFreqMax = min(5000, workingSR / 2)

    # Analysis-driver spectrogram
    Select outer viewport: 0, 4, 2.0, 3.8
    Select inner viewport: 0.5, 3.7, 2.15, 3.65
    selectObject: workingID
    To Spectrogram: 0.01, vizFreqMax, 0.002, 20, "Gaussian"
    origSpecID = selected("Spectrogram")
    Paint: 0, 0, 0, vizFreqMax, 100, "yes", 50, 6, 0, "no"
    
    # Mark split point
    split_time = orig_dur * (split_at_percent / 100)
    Colour: "{0.9, 0.3, 0.3}"
    Line width: 2
    Draw line: split_time, 0, split_time, vizFreqMax
    Line width: 1
    
    Font size: 8
    Colour: "Black"
    Text top: "no", "Analysis driver (red = split)"
    removeObject: origSpecID
    
    # Processed spectrogram
    Select outer viewport: 4, 8, 2.0, 3.8
    Select inner viewport: 4.5, 7.7, 2.15, 3.65
    selectObject: resultID
    To Spectrogram: 0.01, vizFreqMax, 0.002, 20, "Gaussian"
    resSpecID = selected("Spectrogram")
    Paint: 0, 0, 0, vizFreqMax, 100, "yes", 50, 6, 0, "no"
    
    if fade_start_mark > 0
        Colour: "{0.9, 0.7, 0.3}"
        Line width: 2
        Draw line: fade_start_mark, 0, fade_start_mark, vizFreqMax
        Line width: 1
    endif
    
    Font size: 8
    Colour: "Black"
    Text top: "no", "Phase Swapped (orange = fade)"
    removeObject: resSpecID
    
    # Phase swap diagram
    Select outer viewport: 0, 8, 4.0, 5.2
    Select inner viewport: 0.6, 7.6, 4.15, 5.05
    
    Axes: 0, 1, 0, 1
    
    split_ratio = split_at_percent / 100
    
    # Early segment
    Paint rectangle: "{0.8, 0.9, 0.8}", 0, split_ratio, 0.55, 0.95
    Colour: "{0.2, 0.5, 0.2}"
    Draw rectangle: 0, split_ratio, 0.55, 0.95
    
    # Late segment
    Paint rectangle: "{0.9, 0.85, 0.8}", split_ratio, 1, 0.55, 0.95
    Colour: "{0.6, 0.4, 0.2}"
    Draw rectangle: split_ratio, 1, 0.55, 0.95
    
    # Result core + ACTUAL retained FFT tail (left-channel reference).
    leftCoreDur = orig_dur * (1 - split_ratio)
    result_ratio = leftCoreDur / max(result_dur, 1e-12)
    result_ratio = max(0, min(1, result_ratio))
    Paint rectangle: "{0.8, 0.85, 0.95}", 0, result_ratio, 0.05, 0.45
    Colour: "{0.2, 0.4, 0.7}"
    Draw rectangle: 0, result_ratio, 0.05, 0.45
    
    Paint rectangle: "{0.95, 0.9, 0.85}", result_ratio, 1, 0.05, 0.45
    Colour: "{0.8, 0.6, 0.3}"
    Draw rectangle: result_ratio, 1, 0.05, 0.45
    
    # Labels
    Font size: 9
    Colour: "Black"
    Text: split_ratio / 2, "centre", 0.75, "half", "EARLY"
    Text: split_ratio / 2, "centre", 0.65, "half", "(Phase)"
    Text: (1 + split_ratio) / 2, "centre", 0.75, "half", "LATE"
    Text: (1 + split_ratio) / 2, "centre", 0.65, "half", "(Magnitude)"
    Text: result_ratio / 2, "centre", 0.25, "half", "OUTPUT"
    Text: (1 + result_ratio) / 2, "centre", 0.25, "half", "FFT TAIL+FADE"
    
    Colour: "{0.5, 0.5, 0.5}"
    Draw arrow: 0.5, 0.52, 0.5, 0.48
    
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Phase Swap Process — " + mappingName$
    
    # Info panel
    Select outer viewport: 0, 8, 5.3, 5.9
    Select inner viewport: 0.5, 7.7, 5.35, 5.85
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "Split L/R: " + fixed$(split_at_percent, 1) + "/" + fixed$(offset_split, 1) + "%"
    Text: 0.30, "left", 0.5, "half", mappingName$
    Text: 0.58, "left", 0.5, "half", "Full-rate " + fixed$(orig_sr,0) + " Hz"
    Text: 0.78, "left", 0.5, "half", "Tail L/R: " + fixed$(leftTail, 2) + "/" + fixed$(rightTail, 2) + " s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# Cleanup
removeObject: workingID, leftID, rightID

appendInfoLine: ""
appendInfoLine: "╔══════════════════════════════════════════════════════════════╗"
appendInfoLine: "║                      COMPLETE                                ║"
appendInfoLine: "╚══════════════════════════════════════════════════════════════╝"
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Output: ", originalName$, "_phaseswap_", presetName$

selectObject: originalID
plusObject: resultID

if play_result
    selectObject: resultID
    Play
endif
selectObject: resultID

# =======================================================
# PROCEDURE: Phase Swap with Tail
# =======================================================
procedure FastPhaseSwap: .src_id, .split_pct, .target_sr, .tail_dur, .mapping
    selectObject: .src_id
    .tot_dur = Get total duration
    .split_time = .tot_dur * (.split_pct / 100)
    .late_dur = .tot_dur - .split_time
    
    # Split into early and late
    selectObject: .src_id
    Extract part: 0, .split_time, "rectangular", 1, "no"
    .early = selected("Sound")
    
    selectObject: .src_id
    Extract part: .split_time, .tot_dur, "rectangular", 1, "no"
    .late = selected("Sound")
    
    # Convert early to matrix (for phase)
    selectObject: .early
    To Spectrum: "yes"
    .spec_e = selected("Spectrum")
    .bw_e = Get bin width
    To Matrix
    .mat_e = selected("Matrix")
    .id_e = .mat_e
    .nc_e = Get number of columns
    removeObject: .early, .spec_e
    
    # Convert late to matrix (for magnitude)
    selectObject: .late
    To Spectrum: "yes"
    .spec_l = selected("Spectrum")
    .bw_l = Get bin width
    To Matrix
    .mat_l = selected("Matrix")
    .id_l = .mat_l
    removeObject: .late, .spec_l
    
    # Phase-bin mapping. Legacy preserves the v0.3 duration-ratio warp.
    # Exact mode uses the actual FFT bin widths after fast zero-padding:
    # (earlyCol-1)*bw_e = (lateCol-1)*bw_l.
    if .mapping = 1
        .map_ratio = .split_time / .late_dur
        .s_ratio$ = fixed$(.map_ratio, 10)
        .c_raw$ = "round(col * " + .s_ratio$ + ")"
    else
        .map_ratio = .bw_l / .bw_e
        .s_ratio$ = fixed$(.map_ratio, 12)
        .c_raw$ = "round((col - 1) * " + .s_ratio$ + ") + 1"
    endif

    .s_nc_e$ = fixed$(.nc_e, 0)
    .s_id_e$ = fixed$(.id_e, 0)
    .s_id_l$ = fixed$(.id_l, 0)
    .c_safe$ = "(if " + .c_raw$ + " < 1 then 1 else (if " + .c_raw$ + " > " + .s_nc_e$ + " then " + .s_nc_e$ + " else " + .c_raw$ + " endif) endif)"
    
    # Lookup early real/imag
    .early_re$ = "object[" + .s_id_e$ + ", 1, " + .c_safe$ + "]"
    .early_im$ = "object[" + .s_id_e$ + ", 2, " + .c_safe$ + "]"
    
    # Phase from early, magnitude from the late spectrum.
    .target_phase$ = "arctan2(" + .early_im$ + ", " + .early_re$ + ")"

    # BUG FIX: capture the late magnitude into its OWN matrix FIRST. If we
    # read sqrt(self[1,col]^2 + self[2,col]^2) inside the main formula,
    # Praat evaluates row 1 before row 2, so by the time row 2 (imag) is
    # computed, self[1,col] has already been overwritten by the row-1
    # branch -> the imaginary part would get a corrupted magnitude. A
    # separate, untouched magnitude matrix avoids that.
    selectObject: .mat_l
    .mag_l = Copy: "mag_late"
    Formula: "sqrt(object[" + .s_id_l$ + ", 1, col]^2 + object[" + .s_id_l$ + ", 2, col]^2)"
    .s_id_mag$ = fixed$(.mag_l, 0)
    .mag_ref$ = "object[" + .s_id_mag$ + ", 1, col]"

    # Apply magnitude from late + phase from early. Keep the legacy formula
    # bit-for-bit in mapping mode 1. In exact mode force DC/Nyquist imaginary
    # components to zero, as required by a real time-domain signal.
    selectObject: .mat_l
    if .mapping = 1
        Formula: "if row = 1 then " + .mag_ref$ + " * cos(" + .target_phase$ + ") else " + .mag_ref$ + " * sin(" + .target_phase$ + ") endif"
    else
        Formula: "if row = 1 then " + .mag_ref$ + " * cos(" + .target_phase$ + ") else if col=1 or col=ncol then 0 else " + .mag_ref$ + " * sin(" + .target_phase$ + ") fi fi"
    endif

    # Reconstruct
    To Spectrum
    .spec_out = selected("Spectrum")
    To Sound
    .snd_out = selected("Sound")
    
    # Fix sample rate if needed
    selectObject: .snd_out
    .actual_sr = Get sampling frequency
    if .actual_sr <> .target_sr
        Resample: .target_sr, 50
        .resampled = selected("Sound")
        removeObject: .snd_out
        .snd_out = .resampled
    endif
    
    # Preserve tail
    selectObject: .snd_out
    .actual_dur = Get total duration
    .target_dur = .late_dur + .tail_dur
    
    if .actual_dur > .target_dur
        Extract part: 0, .target_dur, "rectangular", 1, "no"
        .final_id = selected("Sound")
        removeObject: .snd_out
    else
        .final_id = .snd_out
    endif

    selectObject: .final_id
    .final_dur = Get total duration
    .retained_tail = max(0, .final_dur - .late_dur)
    retainedTailFromProc = .retained_tail
    
    # Cleanup
    removeObject: .mat_e, .mat_l, .spec_out, .mag_l
    
    selectObject: .final_id
endproc