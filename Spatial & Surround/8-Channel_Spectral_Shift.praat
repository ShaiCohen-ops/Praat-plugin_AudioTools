# ============================================================
# Praat AudioTools - 8-Channel_Spectral_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# v1.0 (2026): DYNAMIC SPECTRAL TRANSLATION - eight independently
#   evolving frequency trajectories. Static mode DSP unchanged from v0.9.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Eight parallel additive frequency translations of one source, from
#   one shared whole-file FFT. Output as octophonic, stems, or a downmix.
#
#   STATIC mode (v0.9, unchanged): each channel receives a constant
#   offset, applied by translating the FFT bins and inverse-transforming.
#   Truncation at DC and Nyquist; nothing wraps. Offsets are quantised
#   to whole bins.
#
#   DYNAMIC mode (new): each channel follows a frequency trajectory
#   df_i(t), applied as analytic-signal (single-sideband) modulation
#       y_i(t) = Re{ z_i(t) exp(j phi_i(t)) },
#       phi_i(t) = 2 pi * integral_0^t df_i,
#   where z_i is the analytic signal of the source, band-limited per
#   channel so that no component ever crosses DC or Nyquist at any point
#   of its trajectory (worst-case band guard). The phase integral is
#   closed-form for every motion, so the modulation is exactly
#   phase-continuous and the offsets are exact Hz, not whole bins.
#
#   Why this engine: a constant-offset bin translation IS analytic-signal
#   modulation by exp(j 2 pi df t) - the two give the same waveform to
#   -106 dB on a sine (measured). So the dynamic engine generalises the
#   static one rather than replacing it, and needs no frames, windows or
#   overlap-add. The source FFT and its Hilbert spectrum are shared by
#   all eight channels; per channel it costs two native band masks, two
#   inverse FFTs and one native vector modulation (cos#/sin#).
#
# Changelog v1.0 (2026):
#   - NEW: Processing mode Static / Dynamic. Static is the v0.9 code path
#     and gives bit-identical audio to v0.9 with default settings.
#   - NEW: five motions, all phase-continuous with closed-form phase:
#       Convergence   offsets glide from Shift_i to a common target
#       Divergence    offsets glide from a common target out to Shift_i
#       Crossing      offsets glide from Shift_i to their mirror image
#                     through the target, so up and down bands exchange
#       Oscillation   each offset swings +/- depth around Shift_i, with
#                     a per-channel phase step (rate, phase spread)
#       Cluster drift the whole group glides by depth while each voice
#                     wobbles at a slightly different rate
#     Motion shape (Linear / S-curve / Early / Late) sets the glide curve
#     of the first, second, third and fifth.
#   - NEW: five dynamic presets - Spectral Convergence, Spectral
#     Divergence, Crossing Streams, Spectral Orbit, Cluster Drift. The
#     nine v0.9 presets are unchanged and, in Dynamic mode, provide the
#     start offsets for whichever motion is chosen.
#   - NEW: optional second dialog for motion and mix parameters (keeps
#     the main form short), pre-filled with the preset's values.
#   - NEW: Wet (%) dry/wet mix in both modes. 100 (default) skips the mix
#     entirely, so the default output is unchanged.
#   - NEW: trajectory visualization (time x offset), per-channel offset
#     range panel and a dynamic summary line; drawn from the same
#     equations and parameters as the synthesis, no extra analysis.
#   - NEW: per-stage timing in the Info report (source prep and shared
#     analysis, trajectory planning, synthesis, assembly, visualization).
#   - FIX (visualization): in panels A, B and C, every bar after the first
#     was drawn after a Text call, which leaves the drawing frame on the
#     outer viewport - so Ch2-Ch8 were offset from Ch1 and from the axis.
#     Bars are now drawn first, labels after a fresh inner-viewport
#     selection. Font size is set before each viewport selection.
#   - FIX (visualization): the "%" in the panel C axis label was eaten
#     as italic markup; "_" in source names rendered as subscript.
#   - FIX (visualization): bin-offset axis ticks were placed at the axis
#     extremes (2972, 1486 ...); now round steps.
#   - FIX: a silent source no longer reports "keeps 0% of the energy".
#
# Changelog v0.9 (2026):
#   - RENAME: "8-voice frequency shift canons" -> 8-Channel Spectral Shift.
#   - FIX: shift amounts entered in Hertz (bins as an advanced unit).
#   - FIX: one shared gain instead of per-channel Scale peak.
#   - FIX: zero imaginary parts at DC and Nyquist after the shift.
#   - FIX: bin offset validated against the bin count.
#   - FIX: "Octave-like" renamed Doubling offsets (additive, not octaves).
#   - FIX: preset labels match their values.
#   - FIX: waveform panel renamed; string$() in the shift Formula.
#   - NEW: energy retention, Output_format menu, monitoring mix.
# Changelog v0.7:
#   - Forced exact sample rate after the roundtrip; trimmed the padded
#     IFFT output back to the source duration.
# Changelog v0.6:
#   - Source spectrum and Matrix computed once, shared across 8 shifts.
# Changelog v0.5:
#   - Negative shifts read from the unmodified source Matrix.
# ============================================================

# === Check Input (before the form) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Spectral Shift
    comment === PRESET AND MODE (dynamic presets also set the motion) ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Gentle Up (20-120 Hz)"
        option: "Moderate Up (100-600 Hz)"
        option: "Extreme Up (500-2600 Hz)"
        option: "Symmetrical (+400..+100 / -100..-400 Hz)"
        option: "All Down (-50 to -400 Hz)"
        option: "Spread (-400 to +400 Hz)"
        option: "Cluster Up (100-170 Hz)"
        option: "Doubling offsets (additive, NOT octaves)"
        option: "DYN Spectral Convergence (+/-700 Hz fuse to 0 Hz)"
        option: "DYN Spectral Divergence (0 Hz splits to +/-700 Hz)"
        option: "DYN Crossing Streams (+/-400 Hz exchange through 0)"
        option: "DYN Spectral Orbit (0 +/-200 Hz, 8 phases 45 deg apart)"
        option: "DYN Cluster Drift (100-170 Hz cluster glides +300 Hz)"
    optionmenu Processing_mode: 1
        option: "Static (constant offsets, v0.9 bin translation)"
        option: "Dynamic (time-varying trajectories)"
    optionmenu Motion: 1
        option: "Convergence (Shift_i -> target)"
        option: "Divergence (target -> Shift_i)"
        option: "Crossing (Shift_i -> mirror through target)"
        option: "Oscillation (swing around each Shift_i)"
        option: "Cluster drift (group glide + detuned wobble)"
    boolean Edit_motion_and_mix_parameters 0

    comment === Shifts / start offsets (positive = up, negative = down) ===
    optionmenu Shift_units: 1
        option: "Hertz (stable across files)"
        option: "FFT bins (advanced; depends on file length)"
    real Shift_1 100
    real Shift_2 200
    real Shift_3 300
    real Shift_4 400
    real Shift_5 -100
    real Shift_6 -200
    real Shift_7 -300
    real Shift_8 -400

    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 stereo pairs (Ch1|Ch2, Ch3|Ch4, Ch5|Ch6, Ch7|Ch8)"
        option: "2 quad groups (Ch1-Ch4, Ch5-Ch8)"
        option: "4-channel fold-down (Ch1+Ch5, Ch2+Ch6, Ch3+Ch7, Ch4+Ch8)"
        option: "Stereo mix (L: Ch1-Ch4, R: Ch5-Ch8)"
    real Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Scalar trajectory evaluation (used by the band-guard scan, the report
# and the drawing). Same equations as the synthesis phase below.
procedure shapeAt: .u
    if motion_shape = 1
        .v = .u
    elsif motion_shape = 2
        .v = (1 - cos(pi * .u)) / 2
    elsif motion_shape = 3
        .v = 2 * .u - .u * .u
    else
        .v = .u * .u
    endif
endproc

procedure dfAt: .ch, .t
    @shapeAt: .t / originalDur
    .v = trA[.ch] + trB[.ch] * shapeAt.v + trW[.ch] * sin(2 * pi * trR[.ch] * .t + trTh[.ch])
endproc

# Timing: stopwatch resets on every read, so each read below is the
# length of one stage.
stopwatch

# === Motion and mix defaults (the second dialog shows these) ===
motion_depth = 200
motion_rate = 0.25
phase_spread = 45
motion_shape = 2
target_Hz = 0
wet = 100

# === Apply Presets ===
# Preset values are Hertz. A preset therefore forces Hz units; bins
# remain available for Custom only, where the user chose them.
presetForcedHz = 0
dynPreset = 0
if preset = 2
    shift_1 = 20
    shift_2 = 30
    shift_3 = 40
    shift_4 = 50
    shift_5 = 65
    shift_6 = 80
    shift_7 = 100
    shift_8 = 120
    presetName$ = "GentleUp"
elsif preset = 3
    shift_1 = 100
    shift_2 = 150
    shift_3 = 200
    shift_4 = 250
    shift_5 = 300
    shift_6 = 400
    shift_7 = 500
    shift_8 = 600
    presetName$ = "ModerateUp"
elsif preset = 4
    shift_1 = 500
    shift_2 = 700
    shift_3 = 900
    shift_4 = 1200
    shift_5 = 1500
    shift_6 = 1800
    shift_7 = 2200
    shift_8 = 2600
    presetName$ = "ExtremeUp"
elsif preset = 5
    shift_1 = 400
    shift_2 = 300
    shift_3 = 200
    shift_4 = 100
    shift_5 = -100
    shift_6 = -200
    shift_7 = -300
    shift_8 = -400
    presetName$ = "Symmetrical"
elsif preset = 6
    shift_1 = -50
    shift_2 = -100
    shift_3 = -150
    shift_4 = -200
    shift_5 = -250
    shift_6 = -300
    shift_7 = -350
    shift_8 = -400
    presetName$ = "AllDown"
elsif preset = 7
    shift_1 = -400
    shift_2 = -250
    shift_3 = -100
    shift_4 = 0
    shift_5 = 0
    shift_6 = 100
    shift_7 = 250
    shift_8 = 400
    presetName$ = "Spread"
elsif preset = 8
    shift_1 = 100
    shift_2 = 110
    shift_3 = 120
    shift_4 = 130
    shift_5 = 140
    shift_6 = 150
    shift_7 = 160
    shift_8 = 170
    presetName$ = "ClusterUp"
elsif preset = 9
    shift_1 = 50
    shift_2 = 100
    shift_3 = 200
    shift_4 = 400
    shift_5 = -50
    shift_6 = -100
    shift_7 = -200
    shift_8 = -400
    presetName$ = "DoublingOffsets"
elsif preset = 10
    # Eight images, up-bank and down-bank, fuse into the source.
    shift_1 = 700
    shift_2 = 500
    shift_3 = 300
    shift_4 = 100
    shift_5 = -100
    shift_6 = -300
    shift_7 = -500
    shift_8 = -700
    presetName$ = "SpectralConvergence"
    dynPreset = 1
    pMotion = 1
    motion_shape = 2
    target_Hz = 0
elsif preset = 11
    # Unison splits into a fan; slow start, so the split is heard.
    shift_1 = 100
    shift_2 = 250
    shift_3 = 450
    shift_4 = 700
    shift_5 = -100
    shift_6 = -250
    shift_7 = -450
    shift_8 = -700
    presetName$ = "SpectralDivergence"
    dynPreset = 1
    pMotion = 2
    motion_shape = 4
    target_Hz = 0
elsif preset = 12
    # Each up-band becomes the matching down-band and vice versa.
    shift_1 = 400
    shift_2 = 300
    shift_3 = 200
    shift_4 = 100
    shift_5 = -100
    shift_6 = -200
    shift_7 = -300
    shift_8 = -400
    presetName$ = "CrossingStreams"
    dynPreset = 1
    pMotion = 3
    motion_shape = 2
    target_Hz = 0
elsif preset = 13
    # All eight centred on the source, swinging +/-200 Hz with phases a
    # 45-degree step apart: an 8 s rotation through the spectrum.
    shift_1 = 0
    shift_2 = 0
    shift_3 = 0
    shift_4 = 0
    shift_5 = 0
    shift_6 = 0
    shift_7 = 0
    shift_8 = 0
    presetName$ = "SpectralOrbit"
    dynPreset = 1
    pMotion = 4
    motion_depth = 200
    motion_rate = 0.125
    phase_spread = 45
elsif preset = 14
    # Tight 10 Hz cluster glides up 300 Hz together; each voice wobbles
    # at a slightly different rate, so the inner beating keeps changing.
    shift_1 = 100
    shift_2 = 110
    shift_3 = 120
    shift_4 = 130
    shift_5 = 140
    shift_6 = 150
    shift_7 = 160
    shift_8 = 170
    presetName$ = "ClusterDrift"
    dynPreset = 1
    pMotion = 5
    motion_depth = 300
    motion_rate = 0.2
    phase_spread = 45
    motion_shape = 2
else
    presetName$ = "Custom"
endif

if preset > 1 and shift_units = 2
    shift_units = 1
    presetForcedHz = 1
endif

modeForced = 0
if dynPreset = 1
    if processing_mode = 1
        modeForced = 1
    endif
    processing_mode = 2
    motion = pMotion
endif
isDynamic = 0
if processing_mode = 2
    isDynamic = 1
endif

# === Optional second dialog: motion and mix ===
if edit_motion_and_mix_parameters
    beginPause: "Motion and mix parameters"
        comment: "Depth: Oscillation swing / Cluster drift common glide (Hz)"
        real: "Motion_depth", string$(motion_depth)
        comment: "Rate: Oscillation and Cluster drift wobble (Hz, max 50)"
        positive: "Motion_rate", string$(motion_rate)
        real: "Phase_spread", string$(phase_spread)
        comment: "Glide shape (Convergence, Divergence, Crossing, Cluster drift)"
        choice: "Motion_shape", motion_shape
            option: "Linear"
            option: "S-curve (smooth start and arrival)"
            option: "Early (fast start, slow arrival)"
            option: "Late (slow start, fast arrival)"
        comment: "Target: meeting point of Convergence / Divergence / Crossing (Hz)"
        real: "Target_Hz", string$(target_Hz)
        comment: "Wet (%): 100 = processed only (default, as v0.9)"
        real: "Wet", string$(wet)
    endPause: "Continue", 1
endif

if motion_rate > 50
    motion_rate = 50
endif
if motion_rate < 0.001
    motion_rate = 0.001
endif
if wet > 100
    wet = 100
endif
if wet < 0
    wet = 0
endif
wetF = wet / 100
dryF = 1 - wetF

if shift_units = 1
    unitName$ = "Hz"
else
    unitName$ = "bins"
endif

if scale_peak <= 0
    scale_peak = 0.99
endif
if scale_peak > 1
    scale_peak = 1
endif

motionName$[1] = "Convergence"
motionName$[2] = "Divergence"
motionName$[3] = "Crossing"
motionName$[4] = "Oscillation"
motionName$[5] = "Cluster drift"
shapeName$[1] = "Linear"
shapeName$[2] = "S-curve"
shapeName$[3] = "Early"
shapeName$[4] = "Late"
if isDynamic
    modeName$ = "Dynamic - " + motionName$[motion]
else
    modeName$ = "Static"
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
safeName$ = replace$(originalName$, "_", "\_ ", 0)
selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency
nch = Get number of channels

requested[1] = shift_1
requested[2] = shift_2
requested[3] = shift_3
requested[4] = shift_4
requested[5] = shift_5
requested[6] = shift_6
requested[7] = shift_7
requested[8] = shift_8

# === Mono base ===
selectObject: originalID
if nch > 1
    Convert to mono
else
    Copy: "mono_work"
endif
monoID = selected("Sound")
selectObject: monoID
srcEnergy = Get energy: 0, 0
sourceSilent = 0
if srcEnergy <= 1e-20
    sourceSilent = 1
endif
if srcEnergy <= 0
    srcEnergy = 1e-30
endif

# ============================================================
# Shared forward FFT (once, not eight times)
# ============================================================
selectObject: monoID
To Spectrum: "yes"
sourceSpecID = selected("Spectrum")
binHz = Get bin width
nBins = Get number of bins
nyquist = Get highest frequency

To Matrix
sourceMatID = selected("Matrix")
Rename: "shiftsrc"

hilSpecID = 0
if isDynamic
    # Shared Hilbert spectrum: H{x} = -j sgn(f) X. Praat stores the
    # positive-frequency half, so (re, im) -> (im, -re). DC and Nyquist
    # have no quadrature component. Sign verified: cos -> sin.
    selectObject: sourceMatID
    Copy: "ss_hilbert"
    hilMatID = selected("Matrix")
    srcStr$ = string$(sourceMatID)
    Formula: "if row = 1 then object[" + srcStr$ + ", 2, col] else -object["
        ... + srcStr$ + ", 1, col] fi"
    Set value: 1, 1, 0
    Set value: 2, 1, 0
    Set value: 1, nBins, 0
    Set value: 2, nBins, 0
    To Spectrum
    hilSpecID = selected("Spectrum")
    removeObject: hilMatID
endif
fftElapsed = stopwatch
tPrep = fftElapsed

anyClamped = 0
nSilentCh = 0

if isDynamic = 0
    # ========================================================
    # STATIC MODE  (v0.9 code path)
    # ========================================================

    # --- Requested shift -> bin offset ---
    # The bin offset is the only thing the transform can actually apply,
    # so the achieved shift is a whole number of bins and the report
    # shows how far that lands from what was asked for.
    for ch from 1 to 8
        if shift_units = 1
            binOffset[ch] = round(requested[ch] / binHz)
        else
            binOffset[ch] = round(requested[ch])
        endif

        # An offset at or beyond the bin count empties the matrix and the
        # channel would come out silent with nothing said.
        if binOffset[ch] > nBins - 1
            binOffset[ch] = nBins - 1
            anyClamped = anyClamped + 1
        endif
        if binOffset[ch] < -(nBins - 1)
            binOffset[ch] = -(nBins - 1)
            anyClamped = anyClamped + 1
        endif

        actualHz[ch] = binOffset[ch] * binHz
        if shift_units = 1
            quantErr[ch] = actualHz[ch] - requested[ch]
        else
            quantErr[ch] = 0
        endif
        startHz[ch] = actualHz[ch]
        endHz[ch] = actualHz[ch]
        minHz[ch] = actualHz[ch]
        maxHz[ch] = actualHz[ch]
    endfor
    tTraj = stopwatch

    # --- Per-channel shift ---
    for ch from 1 to 8
        selectObject: sourceMatID
        Copy: "shiftdst"
        matDstID = selected("Matrix")

        s = binOffset[ch]
        sInt = abs(s)
        sIntStr$ = string$(sInt)

        # Read from the untouched source matrix, write to the destination,
        # so an in-place overlap cannot corrupt the read.
        selectObject: matDstID
        if s >= 0
            Formula: "if col - " + sIntStr$ + " >= 1 then Matrix_shiftsrc[row, col - "
                ... + sIntStr$ + "] else 0 fi"
        else
            Formula: "if col + " + sIntStr$ + " <= ncol then Matrix_shiftsrc[row, col + "
                ... + sIntStr$ + "] else 0 fi"
        endif

        # A valid spectrum of a real signal has a zero imaginary part at
        # DC and at Nyquist. Translating every column alike can move an
        # interior complex bin into either slot with its imaginary part
        # intact. Row 2 of the Matrix is the imaginary part.
        selectObject: matDstID
        Set value: 2, 1, 0
        Set value: 2, nBins, 0

        To Spectrum
        shiftedSpecID = selected("Spectrum")

        To Sound
        fullID = selected("Sound")

        # Force the exact sample rate: the roundtrip can leave sub-sample-
        # rate drift that Combine to stereo refuses to merge.
        Override sampling frequency: sr

        # To Sound returns the zero-padded FFT length; trim to the source.
        selectObject: fullID
        Extract part: 0, originalDur, "rectangular", 1, "no"
        shifted[ch] = selected("Sound")

        # No per-channel Scale peak. Measure instead, so the energy lost
        # past Nyquist or below DC stays visible and audible.
        selectObject: shifted[ch]
        chEnergy[ch] = Get energy: 0, 0
        retained[ch] = chEnergy[ch] / srcEnergy * 100
        if retained[ch] > 100
            retained[ch] = 100
        endif

        # v1.0: dry/wet. Skipped at 100% wet, so the default is v0.9.
        if wet < 100
            Formula: "self * " + fixed$(wetF, 10) + " + " + fixed$(dryF, 10)
                ... + " * object[" + string$(monoID) + ", 1, col]"
        endif

        removeObject: fullID, matDstID, shiftedSpecID
    endfor
    removeObject: sourceMatID, sourceSpecID
    tSynth = stopwatch
    shiftElapsed = tSynth

else
    # ========================================================
    # DYNAMIC MODE
    # ========================================================
    # Every motion is one instance of
    #   df_i(t) = A_i + B_i * s(u) + W_i * sin(2 pi R_i t + Th_i),
    #   u = t / duration,  s = glide shape (0 -> 1),
    # whose phase integral is closed-form:
    #   phi_i(t) = 2 pi (A_i t + B_i dur I(u))
    #              + (W_i / R_i)(cos Th_i - cos(2 pi R_i t + Th_i)),
    #   I(u) = integral_0^u s(v) dv.
    # The same A, B, W, R, Th and shape feed the synthesis, the band
    # guard, the report and the drawing.
    removeObject: sourceMatID

    for ch from 1 to 8
        if shift_units = 1
            refHz[ch] = requested[ch]
        else
            refHz[ch] = requested[ch] * binHz
        endif
        quantErr[ch] = 0
    endfor

    # Cluster drift: wobble amplitude is 45% of the mean spacing, so
    # neighbouring voices weave without routinely trading places.
    refMin = refHz[1]
    refMax = refHz[1]
    for ch from 2 to 8
        if refHz[ch] < refMin
            refMin = refHz[ch]
        endif
        if refHz[ch] > refMax
            refMax = refHz[ch]
        endif
    endfor
    wobble = 0.45 * (refMax - refMin) / 7
    if wobble < 0.5
        wobble = 0.05 * abs(motion_depth)
    endif

    for ch from 1 to 8
        trA[ch] = refHz[ch]
        trB[ch] = 0
        trW[ch] = 0
        trR[ch] = 1
        trTh[ch] = 0
        if motion = 1
            trA[ch] = refHz[ch]
            trB[ch] = target_Hz - refHz[ch]
        elsif motion = 2
            trA[ch] = target_Hz
            trB[ch] = refHz[ch] - target_Hz
        elsif motion = 3
            trA[ch] = refHz[ch]
            trB[ch] = 2 * (target_Hz - refHz[ch])
        elsif motion = 4
            trW[ch] = motion_depth
            trR[ch] = motion_rate
            trTh[ch] = (ch - 1) * phase_spread * pi / 180
        else
            trB[ch] = motion_depth
            trW[ch] = wobble
            trR[ch] = motion_rate * (1 + 0.13 * (ch - 1))
            trTh[ch] = (ch - 1) * phase_spread * pi / 180
            # Offset the wobble so every voice starts exactly on Shift_i.
            trA[ch] = refHz[ch] - trW[ch] * sin(trTh[ch])
        endif
    endfor

    # --- Trajectory scan: extremes for the band guard and the report ---
    # Extremes. Every glide shape is monotonic, so the ramp part
    # A + B s(u) peaks at its endpoints. A wobble that completes at least
    # one cycle reaches +/-W exactly; only a wobble of less than one cycle
    # needs scanning. (A fixed-point scan alone would miss the peaks of a
    # fast wobble on a long file and leave the band guard too narrow.)
    for ch from 1 to 8
        @dfAt: ch, 0
        firstV = dfAt.v
        @dfAt: ch, originalDur
        lastV = dfAt.v
        rampLo = min(trA[ch], trA[ch] + trB[ch])
        rampHi = max(trA[ch], trA[ch] + trB[ch])
        if trW[ch] = 0
            lo = rampLo
            hi = rampHi
        elsif trR[ch] * originalDur >= 1
            lo = rampLo - abs(trW[ch])
            hi = rampHi + abs(trW[ch])
        else
            nScan = 1001
            lo = firstV
            hi = firstV
            for k from 2 to nScan
                @dfAt: ch, (k - 1) * originalDur / (nScan - 1)
                lo = min(lo, dfAt.v)
                hi = max(hi, dfAt.v)
            endfor
        endif
        # Snap round-off (e.g. 200 sin(pi) = 2e-14) so reports read 0.
        if abs(lo) < 1e-9
            lo = 0
        endif
        if abs(hi) < 1e-9
            hi = 0
        endif
        minHz[ch] = lo
        maxHz[ch] = hi
        startHz[ch] = firstV
        endHz[ch] = lastV
        if abs(startHz[ch]) < 1e-9
            startHz[ch] = 0
        endif
        if abs(endHz[ch]) < 1e-9
            endHz[ch] = 0
        endif
        actualHz[ch] = startHz[ch]

        # Band guard. Anything that would cross DC or Nyquist at ANY time
        # along this trajectory is removed for the whole file - the
        # dynamic counterpart of v0.9's truncation, never a wrap or a
        # fold-over. Margin: 2 bins, plus 3x the wobble rate for the FM
        # sidebands of an oscillating offset.
        margin = 2 * binHz
        if trW[ch] <> 0
            margin = margin + 3 * trR[ch]
        endif
        lowEdge = -minHz[ch] + margin
        if lowEdge > 0
            kLo[ch] = ceiling(lowEdge / binHz) + 1
        else
            kLo[ch] = 1
        endif
        highEdge = maxHz[ch] + margin
        if highEdge > 0
            kHi[ch] = nBins - ceiling(highEdge / binHz)
        else
            kHi[ch] = nBins
        endif
        chSilent[ch] = 0
        if kHi[ch] < kLo[ch]
            chSilent[ch] = 1
            nSilentCh = nSilentCh + 1
        endif
        keptLoHz[ch] = (kLo[ch] - 1) * binHz
        keptHiHz[ch] = (kHi[ch] - 1) * binHz
        maskKey[ch] = kLo[ch] * 1e9 + kHi[ch]
    endfor

    # Process channels sorted by band guard, so channels that share a
    # guard (e.g. +400 -> -400 and -400 -> +400 in Crossing) share the
    # two inverse FFTs. Insertion sort with an explicit flag, because
    # Praat's 'and' does not short-circuit.
    for k from 1 to 8
        order[k] = k
    endfor
    for k from 2 to 8
        cur = order[k]
        j = k - 1
        moving = 1
        while moving = 1
            if j < 1
                moving = 0
            elsif maskKey[order[j]] > maskKey[cur]
                order[j + 1] = order[j]
                j = j - 1
            else
                moving = 0
            endif
        endwhile
        order[j + 1] = cur
    endfor
    tTraj = stopwatch

    # --- Synthesis ---
    # Praat 6.2+ has native vector cos#/sin#: the modulation runs as C
    # loops (about 2x faster than Formula). Older builds use an
    # interpreted Formula with the same closed-form phase.
    useVec = 0
    if praatVersion >= 6200
        useVec = 1
    endif
    selectObject: monoID
    nOut = Get number of samples
    if useVec
        tSyn# = (to#(nOut) - 1) / sr
        uSyn# = tSyn# / originalDur
        if motion_shape = 1
            iSyn# = uSyn# * uSyn# / 2
        elsif motion_shape = 2
            iSyn# = uSyn# / 2 - sin#(pi * uSyn#) / (2 * pi)
        elsif motion_shape = 3
            iSyn# = uSyn# * uSyn# - uSyn# * uSyn# * uSyn# / 3
        else
            iSyn# = uSyn# * uSyn# * uSyn# / 3
        endif
        uSyn# = zero#(1)
    else
        tS$ = "((col - 1) / " + string$(sr) + ")"
        uS$ = "(" + tS$ + " / " + string$(originalDur) + ")"
        if motion_shape = 1
            iS$ = "(" + uS$ + "^2 / 2)"
        elsif motion_shape = 2
            iS$ = "(" + uS$ + " / 2 - sin(pi * " + uS$ + ") / (2 * pi))"
        elsif motion_shape = 3
            iS$ = "(" + uS$ + "^2 - " + uS$ + "^3 / 3)"
        else
            iS$ = "(" + uS$ + "^3 / 3)"
        endif
    endif
    xKeepID = 0
    hKeepID = 0

    if wet < 100 and useVec
        selectObject: monoID
        Down to Matrix
        dryMatID = selected("Matrix")
        dry# = Get all values in row: 1
        removeObject: dryMatID
    endif

    # Create the eight output Sounds in CHANNEL order before the loop.
    # Combine to stereo merges the selected Sounds in Object-list order,
    # not in selectObject order, so creating them in band-guard order
    # would silently swap channels in every combined output.
    for ch from 1 to 8
        selectObject: monoID
        Copy: "ss_dyn_" + string$(ch)
        shifted[ch] = selected("Sound")
        Shift times to: "start time", 0
    endfor

    lastKey = -1
    nUniqueGuards = 0
    for oi from 1 to 8
        ch = order[oi]
        if chSilent[ch] = 1
            # written as zeros below
        else
            if maskKey[ch] <> lastKey
                nUniqueGuards = nUniqueGuards + 1
                fromF = (kLo[ch] - 1.5) * binHz
                if fromF < 0
                    fromF = 0
                endif
                toF = (kHi[ch] - 0.5) * binHz
                needMask = 1
                if kLo[ch] = 1 and kHi[ch] = nBins
                    needMask = 0
                endif

                # In-phase part: band-guarded source.
                selectObject: sourceSpecID
                Copy: "ss_x"
                xSpecID = selected("Spectrum")
                if needMask
                    Filter (pass Hann band): fromF, toF, binHz / 100
                endif
                To Sound
                xFullID = selected("Sound")
                Override sampling frequency: sr
                Extract part: 0, originalDur, "rectangular", 1, "no"
                xPartID = selected("Sound")
                removeObject: xSpecID, xFullID
                if useVec
                    Down to Matrix
                    xMatID = selected("Matrix")
                    cx# = Get all values in row: 1
                    removeObject: xPartID, xMatID
                else
                    if xKeepID <> 0
                        removeObject: xKeepID
                    endif
                    xKeepID = xPartID
                endif

                # Quadrature part: band-guarded Hilbert transform.
                selectObject: hilSpecID
                Copy: "ss_h"
                hSpecID = selected("Spectrum")
                if needMask
                    Filter (pass Hann band): fromF, toF, binHz / 100
                endif
                To Sound
                hFullID = selected("Sound")
                Override sampling frequency: sr
                Extract part: 0, originalDur, "rectangular", 1, "no"
                hPartID = selected("Sound")
                nPart = Get number of samples
                removeObject: hSpecID, hFullID
                if useVec
                    Down to Matrix
                    hMatID = selected("Matrix")
                    hx# = Get all values in row: 1
                    removeObject: hPartID, hMatID
                else
                    if hKeepID <> 0
                        removeObject: hKeepID
                    endif
                    hKeepID = hPartID
                endif
                if nPart <> nOut
                    exitScript: "Internal length mismatch (" + string$(nPart)
                        ... + " vs " + string$(nOut) + " samples). Please report."
                endif
                lastKey = maskKey[ch]
            endif

            # Modulation: y = x cos(phi) - H{x} sin(phi).
            if useVec
                ph# = 2 * pi * (trA[ch] * tSyn# + (trB[ch] * originalDur) * iSyn#)
                if trW[ch] <> 0
                    ph# = ph# + (trW[ch] / trR[ch]) * (cos(trTh[ch])
                        ... - cos#(2 * pi * trR[ch] * tSyn# + trTh[ch]))
                endif
                y# = cx# * cos#(ph#) - hx# * sin#(ph#)
            else
                phi$ = "(2 * pi * (" + string$(trA[ch]) + " * " + tS$ + " + "
                    ... + string$(trB[ch] * originalDur) + " * " + iS$ + ")"
                if trW[ch] <> 0
                    phi$ = phi$ + " + " + string$(trW[ch] / trR[ch]) + " * ("
                        ... + string$(cos(trTh[ch])) + " - cos(2 * pi * " + string$(trR[ch])
                        ... + " * " + tS$ + " + " + string$(trTh[ch]) + "))"
                endif
                phi$ = phi$ + ")"
            endif
        endif

        selectObject: shifted[ch]
        if chSilent[ch] = 1
            Formula: "0"
        elsif useVec
            Formula: "y#[col]"
        else
            Formula: "object[" + string$(xKeepID) + ", 1, col] * cos(" + phi$ + ") - object["
                ... + string$(hKeepID) + ", 1, col] * sin(" + phi$ + ")"
        endif
        chEnergy[ch] = Get energy: 0, 0
        retained[ch] = chEnergy[ch] / srcEnergy * 100
        if retained[ch] > 100
            retained[ch] = 100
        endif
        if wet < 100
            if useVec
                Formula: "self * " + fixed$(wetF, 10) + " + " + fixed$(dryF, 10) + " * dry#[col]"
            else
                Formula: "self * " + fixed$(wetF, 10) + " + " + fixed$(dryF, 10)
                    ... + " * object[" + string$(monoID) + ", 1, col]"
            endif
        endif
    endfor
    if xKeepID <> 0
        removeObject: xKeepID
    endif
    if hKeepID <> 0
        removeObject: hKeepID
    endif

    # Release the big shared vectors before assembly.
    cx# = zero#(1)
    hx# = zero#(1)
    y# = zero#(1)
    ph# = zero#(1)
    tSyn# = zero#(1)
    uSyn# = zero#(1)
    iSyn# = zero#(1)
    dry# = zero#(1)
    removeObject: sourceSpecID, hilSpecID
    tSynth = stopwatch
    shiftElapsed = tSynth
endif

# ============================================================
# SHARED-GAIN NORMALISATION  (stage 1)
# ============================================================
peakAll = 0
for ch from 1 to 8
    selectObject: shifted[ch]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
if peakAll < 1e-9
    peakAll = 1e-9
endif
sharedGain = scale_peak / peakAll
sharedGain$ = fixed$(sharedGain, 10)
# v1.0: native Multiply instead of an interpreted Formula (8x faster on
# long files). The factor is the same 10-decimal value v0.9 used, so the
# result is bit-identical.
gainExact = number(sharedGain$)
for ch from 1 to 8
    selectObject: shifted[ch]
    Multiply: gainExact
endfor
tGain = stopwatch

# ============================================================
# FORMAT LABELS AND BANK FOLD
# ============================================================
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 stereo pairs"
    mapLine$ = "Ch1|Ch2   Ch3|Ch4   Ch5|Ch6   Ch7|Ch8"
elsif output_format = 3
    formatName$ = "2 quad groups"
    mapLine$ = "quad 1 = Ch1-Ch4    quad 2 = Ch5-Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "1=Ch1+Ch5  2=Ch2+Ch6  3=Ch3+Ch7  4=Ch4+Ch8"
else
    formatName$ = "Stereo mix (L bank 1 / R bank 2)"
    mapLine$ = "L = Ch1+Ch2+Ch3+Ch4    R = Ch5+Ch6+Ch7+Ch8"
endif

needFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needFold = 1
endif

# Bank fold: Ch1-4 to the left, Ch5-8 to the right (positional: the
# channels are normally laid out as two spectral banks).
if needFold
    selectObject: shifted[1], shifted[2], shifted[3], shifted[4]
    Combine to stereo
    bank1 = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "ss_mixL"
    removeObject: bank1

    selectObject: shifted[5], shifted[6], shifted[7], shifted[8]
    Combine to stereo
    bank2 = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "ss_mixR"
    removeObject: bank2
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
downmixNorm = 0
monitorID = 0
if isDynamic
    tag$ = presetName$ + "_dyn"
else
    tag$ = presetName$
endif

if output_format = 1
    selectObject: shifted[1], shifted[2]
    Combine to stereo
    pair12 = selected("Sound")
    selectObject: shifted[3], shifted[4]
    Combine to stereo
    pair34 = selected("Sound")
    selectObject: shifted[5], shifted[6]
    Combine to stereo
    pair56 = selected("Sound")
    selectObject: shifted[7], shifted[8]
    Combine to stereo
    pair78 = selected("Sound")
    selectObject: pair12, pair34
    Combine to stereo
    quad1234 = selected("Sound")
    selectObject: pair56, pair78
    Combine to stereo
    quad5678 = selected("Sound")
    selectObject: quad1234, quad5678
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_8chSpectral_" + tag$
    outCount = 1
    outChannels = 8
    removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

elsif output_format = 2
    for k from 1 to 4
        selectObject: shifted[2 * k - 1], shifted[2 * k]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: originalName$ + "_spectral_pair_" + string$(2 * k - 1)
            ... + string$(2 * k) + "_" + tag$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    selectObject: shifted[1], shifted[2], shifted[3], shifted[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_spectral_quad_1to4_" + tag$
    selectObject: shifted[5], shifted[6], shifted[7], shifted[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: originalName$ + "_spectral_quad_5to8_" + tag$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for k from 1 to 4
        selectObject: shifted[k], shifted[k + 4]
        Combine to stereo
        foldPair = selected("Sound")
        Convert to mono
        fold[k] = selected("Sound")
        Rename: "ss_fold" + string$(k)
        removeObject: foldPair
    endfor
    selectObject: fold[1], fold[2], fold[3], fold[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_spectral_fold4_" + tag$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: fold[1], fold[2], fold[3], fold[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: originalName$ + "_spectral_stereo_" + tag$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "ss_monitor"
    Scale peak: scale_peak
endif

if needFold
    removeObject: mixL, mixR
endif

combineElapsed = stopwatch
tAssembly = combineElapsed

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel Spectral Shift v1.0 ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(originalDur, 2), " s @ ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$, "   input units: ", unitName$, "   mode: ", modeName$
if presetForcedHz = 1
    appendInfoLine: "  (preset values are in Hz, so the bins option was ignored)"
endif
if modeForced = 1
    appendInfoLine: "  (dynamic preset, so Processing mode was switched to Dynamic)"
endif
appendInfoLine: "FFT: ", nBins, " bins, ", fixed$(binHz, 4), " Hz per bin, Nyquist ",
    ... fixed$(nyquist, 0), " Hz"
appendInfoLine: ""

if isDynamic = 0
    appendInfoLine: "Static: one whole-file transform, each shift constant for the whole"
    appendInfoLine: "duration, quantised to whole bins (bin width = sampling rate over"
    appendInfoLine: "FFT length, so it depends on the file length - hence Hz input)."
    appendInfoLine: "Translation truncates at DC and Nyquist - nothing wraps."
    appendInfoLine: ""
    appendInfoLine: "Channel shifts:"
    for ch from 1 to 8
        if shift_units = 1
            appendInfoLine: "  Ch", ch, ": requested ", fixed$(requested[ch], 1),
                ... " Hz  ->  ", binOffset[ch], " bins = ", fixed$(actualHz[ch], 2),
                ... " Hz  (error ", fixed$(quantErr[ch], 3), " Hz)   energy kept ",
                ... fixed$(retained[ch], 1), "%"
        else
            appendInfoLine: "  Ch", ch, ": ", binOffset[ch], " bins = ",
                ... fixed$(actualHz[ch], 2), " Hz   energy kept ",
                ... fixed$(retained[ch], 1), "%"
        endif
    endfor
    if anyClamped > 0
        appendInfoLine: ""
        appendInfoLine: "  NOTE: ", anyClamped, " shift(s) exceeded the bin count and were"
        appendInfoLine: "        clamped. An offset at or beyond ", nBins,
            ... " bins empties the whole"
        appendInfoLine: "        spectrum and the channel would be silent."
    endif
else
    appendInfoLine: "Dynamic: analytic-signal modulation, phase-continuous, exact Hz"
    appendInfoLine: "(no bin quantisation). Motion: ", motionName$[motion]
    if motion = 4
        appendInfoLine: "  depth +/-", fixed$(motion_depth, 1), " Hz   rate ",
            ... fixed$(motion_rate, 3), " Hz   phase spread ", fixed$(phase_spread, 1), " deg"
    elsif motion = 5
        appendInfoLine: "  glide ", fixed$(motion_depth, 1), " Hz (", shapeName$[motion_shape],
            ... ")   wobble +/-", fixed$(wobble, 2), " Hz at ", fixed$(motion_rate, 3),
            ... "-", fixed$(motion_rate * 1.91, 3), " Hz   phase spread ",
            ... fixed$(phase_spread, 1), " deg"
    else
        appendInfoLine: "  target ", fixed$(target_Hz, 1), " Hz   shape ", shapeName$[motion_shape]
    endif
    appendInfoLine: ""
    appendInfoLine: "Band guard: content that would cross DC or Nyquist at ANY point of a"
    appendInfoLine: "channel's trajectory is removed for the whole file (never wrapped or"
    appendInfoLine: "folded). It is wider than v0.9's truncation whenever a trajectory"
    appendInfoLine: "visits both signs or moves - that is the price of no fold-over."
    appendInfoLine: ""
    appendInfoLine: "Channel trajectories (Hz):"
    for ch from 1 to 8
        if chSilent[ch] = 1
            band$ = "SILENT - excursion exceeds the band"
        else
            band$ = "band kept " + fixed$(keptLoHz[ch], 0) + "-" + fixed$(keptHiHz[ch], 0) + " Hz"
        endif
        @f1: startHz[ch]
        a1$ = f1.s$
        @f1: endHz[ch]
        a2$ = f1.s$
        @f1: minHz[ch]
        a3$ = f1.s$
        @f1: maxHz[ch]
        a4$ = f1.s$
        appendInfoLine: "  Ch", ch, ": ", a1$, " -> ", a2$,
            ... "   range [", a3$, ", ", a4$, "]   ",
            ... band$, "   energy kept ", fixed$(retained[ch], 1), "%"
    endfor
    appendInfoLine: "  (", nUniqueGuards, " distinct band guard(s) -> ", 2 * nUniqueGuards,
        ... " inverse FFTs)"
    if nSilentCh > 0
        appendInfoLine: ""
        appendInfoLine: "  NOTE: ", nSilentCh, " channel(s) silent: the trajectory spans more"
        appendInfoLine: "        than the whole band, so nothing can be kept."
    endif
endif

if sourceSilent = 1
    appendInfoLine: ""
    appendInfoLine: "  NOTE: the source is silent, so the output is silent and the"
    appendInfoLine: "        energy percentages are meaningless."
else
    worstKeep = 100
    for ch from 1 to 8
        if retained[ch] < worstKeep
            worstKeep = retained[ch]
        endif
    endfor
    if worstKeep < 50
        appendInfoLine: ""
        appendInfoLine: "  NOTE: the weakest channel keeps only ", fixed$(worstKeep, 1),
            ... "% of the source energy."
        appendInfoLine: "        Components pushed past Nyquist or below DC are discarded."
        appendInfoLine: "        The shared gain keeps that loss audible."
    endif
endif

appendInfoLine: ""
appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
appendInfoLine: "  ", mapLine$
appendInfoLine: ""
appendInfoLine: "Normalisation:"
appendInfoLine: "  Shared gain across all eight channels: x", fixed$(sharedGain, 4),
    ... " (from peak ", fixed$(peakAll, 4), ")"
if wet < 100
    appendInfoLine: "  Wet ", fixed$(wet, 0), "% (dry = mono source, mixed before the shared gain)"
endif
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas - suite standard)
# ============================================================
# Drawn from the working channels and the trajectory parameters only;
# no extra analysis. Frame rule: bars and curves first, then a fresh
# Select inner viewport for text, then again for the box and marks.
# Font size is always set BEFORE the viewport selection.

procedure f1: .v
    # fixed$(0, 1) returns a bare "0"; keep the column format.
    if .v = 0
        .s$ = "0.0"
    else
        .s$ = fixed$(.v, 1)
    endif
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .result = .p
    elsif .m < 3.5
        .result = 2 * .p
    elsif .m < 7.5
        .result = 5 * .p
    else
        .result = 10 * .p
    endif
endproc

if draw_visualization

    Erase all

    if isDynamic = 0
        # Static colours (v0.9): blue = up, orange/red = down, grey = zero
        maxAbsHz = 1
        for ch from 1 to 8
            if abs(actualHz[ch]) > maxAbsHz
                maxAbsHz = abs(actualHz[ch])
            endif
        endfor
        for ch from 1 to 8
            s = binOffset[ch]
            intensity = abs(actualHz[ch]) / maxAbsHz
            if s > 0
                chR[ch] = 0.22 + intensity * 0.08
                chG[ch] = 0.42 + intensity * 0.08
                chB[ch] = 0.80 + intensity * 0.15
                if chB[ch] > 1
                    chB[ch] = 1
                endif
            elsif s < 0
                chR[ch] = 0.78 + intensity * 0.18
                if chR[ch] > 1
                    chR[ch] = 1
                endif
                chG[ch] = 0.42 - intensity * 0.28
                if chG[ch] < 0
                    chG[ch] = 0
                endif
                chB[ch] = 0.20 - intensity * 0.10
                if chB[ch] < 0
                    chB[ch] = 0
                endif
            else
                chR[ch] = 0.60
                chG[ch] = 0.60
                chB[ch] = 0.60
            endif
        endfor
    else
        # Dynamic colours: eight distinguishable trajectories.
        chR[1] = 0.12
        chG[1] = 0.47
        chB[1] = 0.71
        chR[2] = 1.00
        chG[2] = 0.50
        chB[2] = 0.05
        chR[3] = 0.17
        chG[3] = 0.63
        chB[3] = 0.17
        chR[4] = 0.84
        chG[4] = 0.15
        chB[4] = 0.16
        chR[5] = 0.58
        chG[5] = 0.40
        chB[5] = 0.74
        chR[6] = 0.55
        chG[6] = 0.34
        chB[6] = 0.29
        chR[7] = 0.89
        chG[7] = 0.47
        chB[7] = 0.76
        chR[8] = 0.09
        chG[8] = 0.75
        chB[8] = 0.81
    endif
    for ch from 1 to 8
        col$[ch] = "{" + fixed$(chR[ch], 2) + ", " + fixed$(chG[ch], 2)
            ... + ", " + fixed$(chB[ch], 2) + "}"
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Font size: 12
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPECTRAL SHIFT v1.0##"
    Font size: 7
    Select inner viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... safeName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  Mode: " + modeName$
        ... + "  |  " + fixed$(originalDur, 2) + " s @ " + string$(sr) + " Hz"
        ... + "  |  Format: " + formatName$

    if isDynamic = 0
        # ------------------------------------------------------
        # PANEL A (static): BIN OFFSET BAR CHART
        # ------------------------------------------------------
        minShift = binOffset[1]
        maxShift = binOffset[1]
        for ch from 2 to 8
            if binOffset[ch] < minShift
                minShift = binOffset[ch]
            endif
            if binOffset[ch] > maxShift
                maxShift = binOffset[ch]
            endif
        endfor
        range = maxShift - minShift
        if range < 10
            range = 10
        endif
        plotMin = minShift - range * 0.18
        plotMax = maxShift + range * 0.18
        if plotMin > 0
            plotMin = -range * 0.10
        endif
        if plotMax < 0
            plotMax = range * 0.10
        endif

        Font size: 6
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0.5, 8.5, plotMin, plotMax
        Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, 8.5, plotMin, plotMax
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 2
        Draw line: 0.5, 0, 8.5, 0
        Line width: 1
        for ch from 1 to 8
            s = binOffset[ch]
            xL = ch - 0.38
            xR = ch + 0.38
            Paint rectangle: col$[ch], xL, xR, min(0, s), max(0, s)
            Colour: "{0.30, 0.30, 0.30}"
            Draw rectangle: xL, xR, min(0, s), max(0, s)
        endfor
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0.5, 8.5, plotMin, plotMax
        for ch from 1 to 8
            s = binOffset[ch]
            Colour: "White"
            if abs(s) > (plotMax - plotMin) * 0.12
                Text: ch, "centre", s / 2, "half", string$(s)
            endif
            Colour: "{0.30, 0.30, 0.30}"
            Text: ch, "centre", plotMin + (plotMax - plotMin) * 0.05, "half",
                ... "Ch" + string$(ch)
        endfor
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0.5, 8.5, plotMin, plotMax
        Colour: "Black"
        Draw inner box
        @niceStep: plotMax - plotMin, 5
        Marks left every: 1, niceStep.result, "yes", "yes", "no"
        Font size: 7
        Select inner viewport: 0.08, 0.52, 0.77, 4.58
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Bin offset"
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0.5, 8.5, plotMin, plotMax
        Text bottom: "yes", "Channel  (blue = up,  orange = down)"

        # ------------------------------------------------------
        # PANEL B (static): ACHIEVED FREQUENCY SHIFT (Hz)
        # ------------------------------------------------------
        hzAbs = maxAbsHz * 1.15
        if hzAbs < 5
            hzAbs = 5
        endif
        hzMin = -hzAbs
        hzMax = hzAbs

        Font size: 6
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Paint rectangle: "{0.96, 0.96, 0.96}", hzMin, hzMax, 0.5, 8.5
        Colour: "{0.75, 0.75, 0.75}"
        Dotted line
        Draw line: 0, 0.5, 0, 8.5
        Solid line
        for ch from 1 to 8
            y = 9 - ch
            hz = actualHz[ch]
            Paint rectangle: col$[ch], min(0, hz), max(0, hz), y - 0.38, y + 0.38
        endfor
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        for ch from 1 to 8
            y = 9 - ch
            hz = actualHz[ch]
            Colour: "{0.30, 0.30, 0.30}"
            Text: hzMin - (hzMax - hzMin) * 0.015, "right", y, "half", "Ch" + string$(ch)
            Colour: "White"
            if abs(hz) > (hzMax - hzMin) * 0.08
                Text: hz / 2, "centre", y, "half", fixed$(hz, 0) + " Hz"
            endif
        endfor
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Colour: "Black"
        Draw inner box
        Font size: 7
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Text bottom: "yes", "Achieved shift (Hz)  - quantised to whole bins"
    else
        # ------------------------------------------------------
        # PANEL A (dynamic): FREQUENCY TRAJECTORIES
        # ------------------------------------------------------
        nViz = 241

        hzLo = 0
        hzHi = 0
        for ch from 1 to 8
            if minHz[ch] < hzLo
                hzLo = minHz[ch]
            endif
            if maxHz[ch] > hzHi
                hzHi = maxHz[ch]
            endif
        endfor
        hzSpan = hzHi - hzLo
        if hzSpan < 10
            hzSpan = 10
        endif
        hzMin = hzLo - hzSpan * 0.08
        hzMax = hzHi + hzSpan * 0.08
        # Legend strip above the curves.
        hzTop = hzMax + (hzMax - hzMin) * 0.14

        Font size: 6
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0, originalDur, hzMin, hzTop
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, originalDur, hzMin, hzMax
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, originalDur, hzMax, hzTop
        Colour: "{0.70, 0.70, 0.70}"
        Draw line: 0, hzMax, originalDur, hzMax
        Dotted line
        Draw line: 0, 0, originalDur, 0
        Solid line
        Line width: 2
        for ch from 1 to 8
            Colour: col$[ch]
            @dfAt: ch, 0
            tPrev = 0
            vPrev = dfAt.v
            for k from 2 to nViz
                tNow = (k - 1) * originalDur / (nViz - 1)
                @dfAt: ch, tNow
                Draw line: tPrev, vPrev, tNow, dfAt.v
                tPrev = tNow
                vPrev = dfAt.v
            endfor
        endfor
        Line width: 1
        legY = hzMax + (hzTop - hzMax) * 0.5
        legH = (hzTop - hzMax) * 0.18
        for ch from 1 to 8
            lx = originalDur * (0.03 + (ch - 1) * 0.12)
            Paint rectangle: col$[ch], lx, lx + originalDur * 0.035, legY - legH, legY + legH
        endfor
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0, originalDur, hzMin, hzTop
        Colour: "{0.30, 0.30, 0.30}"
        for ch from 1 to 8
            lx = originalDur * (0.03 + (ch - 1) * 0.12)
            Text: lx + originalDur * 0.045, "left", legY, "half", "Ch" + string$(ch)
        endfor
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0, originalDur, hzMin, hzTop
        Colour: "Black"
        Draw inner box
        # Ticks only over the plotted range, not into the legend strip.
        @niceStep: hzMax - hzMin, 5
        tickStep = niceStep.result
        for kt from ceiling(hzMin / tickStep) to floor(hzMax / tickStep)
            One mark left: kt * tickStep, "yes", "yes", "no", ""
        endfor
        @niceStep: originalDur, 5
        Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
        Font size: 7
        Select inner viewport: 0.08, 0.52, 0.77, 4.58
        Axes: 0, 1, 0, 1
        Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Offset (Hz)"
        Select inner viewport: 0.55, 4.00, 0.85, 4.34
        Axes: 0, originalDur, hzMin, hzTop
        Text bottom: "yes", "Time (s)  - " + motionName$[motion] + " trajectories, as synthesised"

        # ------------------------------------------------------
        # PANEL B (dynamic): OFFSET RANGE PER CHANNEL
        # ------------------------------------------------------
        Font size: 6
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Paint rectangle: "{0.96, 0.96, 0.96}", hzMin, hzMax, 0.5, 8.5
        Colour: "{0.75, 0.75, 0.75}"
        Dotted line
        Draw line: 0, 0.5, 0, 8.5
        Solid line
        minW = (hzMax - hzMin) * 0.004
        for ch from 1 to 8
            y = 9 - ch
            bL = minHz[ch]
            bR = maxHz[ch]
            if bR - bL < minW
                bL = bL - minW / 2
                bR = bR + minW / 2
            endif
            Paint rectangle: col$[ch], bL, bR, y - 0.16, y + 0.16
        endfor
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Colour: "Black"
        Line width: 1
        for ch from 1 to 8
            y = 9 - ch
            Paint circle (mm): "White", startHz[ch], y, 1.6
            Draw circle (mm): startHz[ch], y, 1.6
            Paint circle (mm): "Black", endHz[ch], y, 1.1
        endfor
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Colour: "{0.30, 0.30, 0.30}"
        for ch from 1 to 8
            Text: hzMin - (hzMax - hzMin) * 0.015, "right", 9 - ch, "half", "Ch" + string$(ch)
        endfor
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Colour: "Black"
        Draw inner box
        @niceStep: hzMax - hzMin, 5
        Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
        Font size: 7
        Select inner viewport: 4.52, 7.75, 0.85, 2.48
        Axes: hzMin, hzMax, 0.5, 8.5
        Text bottom: "yes", "Offset range (Hz): bar = min-max, open dot = start, filled = end"
    endif

    # ----------------------------------------------------------
    # PANEL C: SPECTRAL ENERGY RETAINED  (right col, lower)
    # ----------------------------------------------------------
    Font size: 6
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, 105, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 105, 0.5, 8.5
    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 100, 0.5, 100, 8.5
    Draw line: 50, 0.5, 50, 8.5
    Solid line
    for ch from 1 to 8
        y = 9 - ch
        Paint rectangle: col$[ch], 0, retained[ch], y - 0.38, y + 0.38
        Colour: "{0.30, 0.30, 0.30}"
        Draw rectangle: 0, retained[ch], y - 0.38, y + 0.38
    endfor
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, 105, 0.5, 8.5
    for ch from 1 to 8
        y = 9 - ch
        Colour: "{0.30, 0.30, 0.30}"
        Text: -2, "right", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if retained[ch] > 14
            Text: retained[ch] / 2, "centre", y, "half", fixed$(retained[ch], 0) + "\%  "
        endif
    endfor
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, 105, 0.5, 8.5
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, 105, 0.5, 8.5
    if isDynamic
        Text bottom: "yes", "Energy kept after the band guard (\% )"
    else
        Text bottom: "yes", "Energy kept after truncation at DC / Nyquist (\% )"
    endif

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES AND RAILS
    # ----------------------------------------------------------
    Font size: 7
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Colour: "Black"
    if isDynamic
        Text: 2.27, "centre", 7.30, "half", "Frequency offset trajectories"
        Text: 6.13, "centre", 7.30, "half", "Offset range (upper) & energy retained (lower)"
    else
        Text: 2.27, "centre", 7.30, "half", "Bin offset per channel"
        Text: 6.13, "centre", 7.30, "half", "Achieved Hz (upper) & energy retained (lower)"
    endif

    # ----------------------------------------------------------
    # PANEL D: TWO CHANNEL EXAMPLES (full width)
    # ----------------------------------------------------------
    selectObject: shifted[1]
    outDurViz = Get total duration
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: shifted[8]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Font size: 7
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    selectObject: shifted[1]
    Colour: col$[1]
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    selectObject: shifted[8]
    Colour: col$[8]
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Colour: "{0.70, 0.70, 0.70}"
    Draw line: 0, 0, outDurViz, 0
    Colour: "Black"
    Draw inner box
    if isDynamic
        dTitle$ = "Channel examples  (Ch1 " + fixed$(startHz[1], 0) + " -> " + fixed$(endHz[1], 0)
            ... + " Hz,  Ch8 " + fixed$(startHz[8], 0) + " -> " + fixed$(endHz[8], 0)
            ... + " Hz)  - shared gain, so levels are comparable"
    else
        dTitle$ = "Channel examples  (blue = Ch1 " + fixed$(actualHz[1], 0)
            ... + " Hz,  orange = Ch8 " + fixed$(actualHz[8], 0)
            ... + " Hz)  - shared gain, so levels are comparable"
    endif
    Text top: "no", dTitle$
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Text bottom: "no", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Font size: 6
    Select inner viewport: 0.55, 7.72, 6.26, 7.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.78, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + safeName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  @" + string$(sr) + " Hz"
        ... + "  |  " + string$(nBins) + " bins x " + fixed$(binHz, 3) + " Hz"
        ... + "  |  input in " + unitName$
        ... + "  |  wet " + fixed$(wet, 0) + "\% "

    if isDynamic
        if motion = 4
            mLine$ = "depth +/-" + fixed$(motion_depth, 0) + " Hz  |  rate "
                ... + fixed$(motion_rate, 3) + " Hz  |  phase spread " + fixed$(phase_spread, 0) + " deg"
        elsif motion = 5
            mLine$ = "glide " + fixed$(motion_depth, 0) + " Hz (" + shapeName$[motion_shape]
                ... + ")  |  wobble +/-" + fixed$(wobble, 1) + " Hz at " + fixed$(motion_rate, 3)
                ... + "-" + fixed$(motion_rate * 1.91, 3) + " Hz  |  spread " + fixed$(phase_spread, 0) + " deg"
        else
            mLine$ = "target " + fixed$(target_Hz, 0) + " Hz  |  shape " + shapeName$[motion_shape]
        endif
        Text: 0.02, "left", 0.50, "half", "##Dynamic: " + motionName$[motion] + "##  |  " + mLine$
        Text: 0.02, "left", 0.22, "half",
            ... "Start Hz:  "
            ... + fixed$(startHz[1], 0) + "  " + fixed$(startHz[2], 0)
            ... + "  " + fixed$(startHz[3], 0) + "  " + fixed$(startHz[4], 0)
            ... + "  " + fixed$(startHz[5], 0) + "  " + fixed$(startHz[6], 0)
            ... + "  " + fixed$(startHz[7], 0) + "  " + fixed$(startHz[8], 0)
            ... + "   End Hz:  "
            ... + fixed$(endHz[1], 0) + "  " + fixed$(endHz[2], 0)
            ... + "  " + fixed$(endHz[3], 0) + "  " + fixed$(endHz[4], 0)
            ... + "  " + fixed$(endHz[5], 0) + "  " + fixed$(endHz[6], 0)
            ... + "  " + fixed$(endHz[7], 0) + "  " + fixed$(endHz[8], 0)
            ... + "   |  " + formatName$ + "  |  " + mapLine$
    else
        Text: 0.02, "left", 0.50, "half",
            ... "##Static##  |  Achieved Hz:  "
            ... + fixed$(actualHz[1], 0) + "  " + fixed$(actualHz[2], 0)
            ... + "  " + fixed$(actualHz[3], 0) + "  " + fixed$(actualHz[4], 0)
            ... + "  " + fixed$(actualHz[5], 0) + "  " + fixed$(actualHz[6], 0)
            ... + "  " + fixed$(actualHz[7], 0) + "  " + fixed$(actualHz[8], 0)
            ... + "   [Ch1-Ch8]"
        Text: 0.02, "left", 0.22, "half",
            ... "Format: " + formatName$
            ... + "  |  " + string$(outCount) + objWord$
            ... + " x " + string$(outChannels) + " ch"
            ... + "  |  " + mapLine$
    endif
    Select inner viewport: 0.55, 7.72, 6.26, 7.02
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Leave the whole canvas selected, so Save / Copy exports all of it.
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Select outer viewport: 0, 8, 0, 7.18
endif
tViz = stopwatch

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoID
for ch from 1 to 8
    removeObject: shifted[ch]
endfor

tTotal = tPrep + tTraj + tSynth + tGain + tAssembly + tViz
appendInfoLine: ""
appendInfoLine: "Performance (s, this run):"
appendInfoLine: "  source prep + shared analysis    ", fixed$(tPrep, 3)
appendInfoLine: "  trajectory / shift planning      ", fixed$(tTraj, 3)
appendInfoLine: "  8-channel synthesis              ", fixed$(tSynth, 3)
appendInfoLine: "  shared gain                      ", fixed$(tGain, 3)
appendInfoLine: "  output assembly                  ", fixed$(tAssembly, 3)
appendInfoLine: "  visualization                    ", fixed$(tViz, 3)
appendInfoLine: "  total (before playback)          ", fixed$(tTotal, 3)

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel spectral translation"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels, "-channel each"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview, L = Ch1-Ch4, R = Ch5-Ch8."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

if monitorID <> 0
    removeObject: monitorID
endif

# === Select the output object(s) ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
