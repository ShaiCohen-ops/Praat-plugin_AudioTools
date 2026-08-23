# ============================================================
# Praat AudioTools - In-Place_Paulstretch_Slicer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   In-Place Paulstretch Slicer - extracts random segments,
#   applies Paulstretch (phase-randomized time stretching),
#   and places them back at original positions. Creates
#   ethereal, frozen texture effects. Wet slices are distributed
#   round-robin across output channels. Stereo/multichannel sources
#   preserve their original dry channel layout; mono sources retain
#   the historical stereo L-R alternating output.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.6 (visualization only; DSP unchanged):
#   - Library-standard title/subtitle geometry, panel greys, fonts and summary.
#   - FIX: end on full-page viewport so Picture export saves the whole figure.
#   - FIX: removed misplaced output-panel title that could render above main title.
#   - TRUE MULTICHANNEL VISUALIZATION: all output channels are shown, not only 1/2.
#   - Channel identity now uses one consistent muted palette in slice map, source
#     markers and output lanes. Colours cycle only after channel 8.
#   - Right headline panel rewritten as a user-facing process explanation rather
#     than a decorative multi-colour parameter report.
#   - Original and all output channels use one shared amplitude scale.
#
# Changelog v0.5:
#   - TRUE MULTICHANNEL OUTPUT. v0.4 collapsed every source to mono and
#     always rebuilt stereo. v0.5 preserves the original dry channel layout;
#     wet Paulstretch slices are mono textures distributed round-robin across
#     all source channels. Mono sources retain the historical stereo output.
#   - FIXED non-zero input time domains by creating a zero-based source copy
#     before all slice extraction and visualization.
#   - Paulstretch OLA now accumulates a synthesis-window normalization buffer
#     and divides by it after overlap-add, preventing overlap-percent-dependent
#     amplitude pumping.
#   - paulstretchFast now returns exactly segmentDuration * stretchFactor; the
#     previous internal +window buffer leaked into slice duration, placement,
#     fades and visualization.
#   - Removed per-slice and per-wet-channel peak normalization. Those stages
#     boosted quiet source regions and altered L/R balance. Peak control is now
#     downward-only safety limiting, so Dry_wet_mix remains meaningful.
#   - Final output is trimmed to the actual latest wet-slice end (or original
#     duration), replacing the arbitrary original+2-second truncation.
#   - Fades are clamped to half the stretched slice instead of silently doing
#     nothing when a requested fade is too long.
#   - Added guards for overlap, slice count, fades and effective FFT window.
#
# Changelog v0.4 (audio CHANGES from v0.3 -- both fixes intentional):
#
#   FIX A -- "clicks" eliminated (same fix as Paulstretch.praat v1.1).
#     v0.3's `paulstretchFast` procedure rounded `.winSamples` to
#     even but NOT to a power of 2. Praat's `To Spectrum: "yes"`
#     uses the fast FFT path, which silently zero-pads the input
#     up to the next power of 2. The resulting Spectrum has
#     frequency step dx = 1/paddedDuration, so when `Spectrum:
#     To Sound` IFFTs back, the output Sound has duration
#     `paddedDuration = nextPow2(.winSamples)/.sr`, LONGER than
#     `.winSize`. The subsequent `Multiply by window: "Hanning"`
#     then spanned [0, paddedDuration] rather than [0, .winSize],
#     so when overlap-add used only the first .winSize of the
#     processed frame, the Hann value at that cutoff was
#     Hann(.winSize/paddedDuration) which is non-zero (~0.74 for
#     0.25 s / 0.371 s). Each frame ended with a step
#     discontinuity, audible as clicks at 1/hopOut Hz.
#     v0.4: round `.winSamples` UP to next pow2 inside the
#     procedure. The FFT input is then already pow2 so no
#     auto-padding occurs, IFFT roundtrip preserves duration,
#     synthesis Hann zeros the edges of the actually-used range,
#     overlap-add is clean.
#     Side effect: effective `.winSize` inside the Paulstretch
#     procedure may be larger than the caller's
#     `window_size_s`. The caller's `window_size_s` is the
#     REQUEST; the procedure rounds it up internally. Reported
#     in the info log when rounding occurs.
#
#   FIX B -- magnitude term in phase-randomization formula.
#     v0.3 already correctly used a single random phase per bin
#     (cos and sin both read `object[.pid, 1, col]`, the same
#     value -- the cos/sin half of Fix B was not needed here).
#     BUT the magnitude computation `sqrt(self[1,col]^2 +
#     self[2,col]^2)` was still corrupted by in-place Formula
#     evaluation: when row 2 is processed, `self[1, col]` reads
#     the row-1 cell that was JUST overwritten by
#     `mag * cos(phase)` in the previous iteration of the same
#     Formula pass. So the magnitude used for the imaginary
#     part was sqrt((mag*cos(phase))^2 + orig_imag^2), not the
#     original sqrt(orig_real^2 + orig_imag^2). This broke
#     Paulstretch's "preserve magnitudes" property and added
#     graininess.
#     v0.4: precompute magnitudes into a separate Matrix
#     `.matM` from .matC (while .matC is still untouched), then
#     the main Formula on .matC reads `object[.mid, 1, col]`
#     for both rows. Row 2 sees the correct original magnitude,
#     not a value derived from the modified row 1.
#
#   Changelog v0.3 (preserved, no further changes):
#     AUDIO CHANGE: slice Extract now uses rectangular window
#     (was Hanning, full-segment). v0.2 applied a Hann window
#     to the input segment BEFORE Paulstretch and then applied
#     explicit fade_in_s / fade_out_s to the stretched slice
#     AFTER — two separate fades stacked. v0.3 lets the explicit
#     fades be the only envelope shaping. Stretched slices have
#     more body, slightly brighter Paulstretch character, sharper
#     attack/release before the explicit fades take effect. For
#     the prior softer character, set fade_in_s and fade_out_s
#     to larger values (e.g., 0.15 / 0.3 s).
#
#     PERFORMANCE (audio bit-identical apart from the Hann->rect
#     change above): three Formula calls converted to
#     Formula (part) to skip wasted iterations:
#       - Line 246 v0.2 (frame padding inside Paulstretch)
#       - Line 284 v0.2 (overlap-add inside Paulstretch — the
#         hot inner loop)
#       - Line 370 v0.2 (final wet-channel placement)
#     v0.2 evaluated `if x >= start and x <= end then self + ...
#     else self fi` for every sample in the WHOLE destination
#     buffer, including ~88% of samples that just returned self.
#     v0.3 uses Formula (part) which only iterates over the
#     relevant range. Same arithmetic, same destination samples,
#     no wasted else-branch iterations. Typical speedup of
#     Paulstretch operations: 2-5x. Total script wallclock:
#     ~30-60% faster depending on slice count and stretch.
#
#     POLISH:
#     - optionmenu Preset: (added colon)
#     - Dropped 9 decorative form rows (1 instructional comment,
#       6 `comment === ... ===` section dividers, 1 inline
#       parenthetical, 1 implicit section grouping). Form went
#       from 19 effective rows to 10.
#     - presetName$ added; output filename now includes preset
#       name: <input>_PSslice_<presetName> (was just _PSslice).
#     - Visualization rewritten to suite 8x8 standard (v0.2 was
#       8x5.4 custom):
#         Title bar (suite light) + metadata subtitle
#         Panel A (left, headline): slice mapping diagram
#         Panel B (right, headline): parameter report
#         Panel C: original waveform with vertical markers
#         Panel D: result L/R waveforms split top/bottom
#         Panel E: light-grey summary stats bar
#
# Changelog v0.2:
#   - Added fade in/out on slices
#   - Added dry/wet mix
#   - Stereo output: dry on both channels, slices alternate L-R
#   - Added visualization
#   - Added presets
# ============================================================

form In-Place Paulstretch Slicer v0.6
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Frozen Texture
        option Extreme Stretch
        option Glitch Clouds
        option Ambient Wash
    natural Number_of_slices 4
    real Min_duration_s 0.1
    real Max_duration_s 0.5
    positive Stretch_factor 4.0
    positive Window_size_s 0.25
    real Overlap_percent 50
    real Fade_in_s 0.05
    real Fade_out_s 0.1
    real Dry_wet_mix 0.5
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
presetName$ = "Custom"

if preset = 2
    # Subtle Shimmer
    number_of_slices = 3
    min_duration_s = 0.15
    max_duration_s = 0.4
    stretch_factor = 3.0
    window_size_s = 0.2
    overlap_percent = 60
    fade_in_s = 0.08
    fade_out_s = 0.15
    dry_wet_mix = 0.3
    presetName$ = "SubtleShimmer"
elsif preset = 3
    # Frozen Texture
    number_of_slices = 5
    min_duration_s = 0.2
    max_duration_s = 0.6
    stretch_factor = 6.0
    window_size_s = 0.3
    overlap_percent = 50
    fade_in_s = 0.1
    fade_out_s = 0.2
    dry_wet_mix = 0.5
    presetName$ = "FrozenTexture"
elsif preset = 4
    # Extreme Stretch
    number_of_slices = 3
    min_duration_s = 0.3
    max_duration_s = 0.8
    stretch_factor = 10.0
    window_size_s = 0.4
    overlap_percent = 70
    fade_in_s = 0.15
    fade_out_s = 0.3
    dry_wet_mix = 0.6
    presetName$ = "ExtremeStretch"
elsif preset = 5
    # Glitch Clouds
    number_of_slices = 8
    min_duration_s = 0.05
    max_duration_s = 0.2
    stretch_factor = 4.0
    window_size_s = 0.15
    overlap_percent = 40
    fade_in_s = 0.02
    fade_out_s = 0.05
    dry_wet_mix = 0.7
    presetName$ = "GlitchClouds"
elsif preset = 6
    # Ambient Wash
    number_of_slices = 4
    min_duration_s = 0.4
    max_duration_s = 1.0
    stretch_factor = 8.0
    window_size_s = 0.35
    overlap_percent = 65
    fade_in_s = 0.2
    fade_out_s = 0.4
    dry_wet_mix = 0.4
    presetName$ = "AmbientWash"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sourceStart = Get start time
sourceEnd = Get end time
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Validate ===
if number_of_slices < 1 or number_of_slices > 256
    exitScript: "Number of slices must be 1-256"
endif
if min_duration_s <= 0 or max_duration_s <= 0
    exitScript: "Durations must be positive"
endif
if min_duration_s > max_duration_s
    exitScript: "Min duration cannot exceed max duration"
endif
if max_duration_s > totalDuration
    exitScript: "Max duration cannot exceed sound duration"
endif
if stretch_factor <= 0
    exitScript: "Stretch factor must be > 0"
endif
if window_size_s <= 0
    exitScript: "Window size must be > 0"
endif
if overlap_percent < 0 or overlap_percent >= 100
    exitScript: "Overlap percent must be >= 0 and < 100"
endif
if fade_in_s < 0 or fade_out_s < 0
    exitScript: "Fade durations must be >= 0"
endif

# Clamp dry/wet
if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

# Preserve source geometry. Mono keeps the historical stereo output.
if numChannels = 1
    outputChannels = 2
else
    outputChannels = numChannels
endif

# Zero-based source copy. All structural times below are offsets from 0.
selectObject: original
sourceZero = Copy: "ps_source_zero"
Shift times to: "start time", 0

# Wet texture analysis is mono, while the dry path remains multichannel.
selectObject: sourceZero
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "source_mono"
    sourceSound = selected("Sound")
endif

# === Info ===
writeInfoLine: "=== In-Place Paulstretch Slicer v0.6 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(totalDuration, 2), " s; ", numChannels, " ch -> ", outputChannels, " ch output)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Slices: ", number_of_slices
appendInfoLine: "Duration: ", fixed$(min_duration_s, 2), " - ", fixed$(max_duration_s, 2), " s"
appendInfoLine: "Stretch: ", stretch_factor, "x"

# v0.4: report effective Paulstretch window after pow2 rounding so the
# user can see if their request was adjusted (see Fix A in header).
ps_requestedSamples = round(window_size_s * sampleRate)
ps_effectiveSamples = 1
while ps_effectiveSamples < ps_requestedSamples
    ps_effectiveSamples = ps_effectiveSamples * 2
endwhile
ps_effectiveWinSize = ps_effectiveSamples / sampleRate
if ps_effectiveSamples < 4
    exitScript: "Effective Paulstretch window must contain at least 4 samples"
endif
if abs(ps_effectiveWinSize - window_size_s) > 0.0005
    appendInfoLine: "Window: ", fixed$(ps_effectiveWinSize, 4), " s (", ps_effectiveSamples,
        ... " samples; pow2-rounded up from request of ", fixed$(window_size_s, 4), " s)"
else
    appendInfoLine: "Window: ", fixed$(window_size_s, 4), " s (", ps_effectiveSamples, " samples)"
endif

appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
appendInfoLine: ""

# === Calculate Render Buffer ===
maxStretchedDuration = max_duration_s * stretch_factor
# Conservative workspace; final result is trimmed to the actual latest slice.
paddingDuration = max(maxStretchedDuration, ps_effectiveWinSize)
paddedDuration = totalDuration + paddingDuration

# === Create multichannel wet buffer ===
Create Sound from formula: "wet_multi", outputChannels, 0, paddedDuration, sampleRate, "0"
wetMulti = selected("Sound")

maxRenderedEnd = totalDuration

# === Store slice info for visualization ===
for i to number_of_slices
    sliceStart[i] = 0
    sliceEnd[i] = 0
    sliceTargetStart[i] = 0
    sliceStretchedDur[i] = 0
    sliceChannel[i] = 0
endfor

# ===================================================================
# PROCEDURE: FAST PAULSTRETCH
# Two Formula -> Formula (part) speedups vs v0.2:
#   * Frame padding (line 246 in v0.2): only the actual frame
#     range is written into the padded buffer.
#   * Overlap-add into output (line 284 in v0.2): only the
#     [tOut, tOut + winSize] range is touched per frame.
# Audio output is bit-identical to v0.2 for these two changes.
# ===================================================================
procedure paulstretchFast: .inputID, .stretch, .winSize, .overlapPct
    selectObject: .inputID
    .dur = Get total duration
    .sr = Get sampling frequency

    # Pow2 FFT window (v0.4 correctness fix retained).
    .requestedWinSamples = round(.winSize * .sr)
    .winSamples = 1
    while .winSamples < .requestedWinSamples
        .winSamples = .winSamples * 2
    endwhile
    .winSize = .winSamples / .sr

    .overlapFrac = .overlapPct / 100
    .hopOut = .winSize * (1 - .overlapFrac)
    .hopIn = .hopOut / .stretch
    .outDur = .dur * .stretch
    .bufferDur = .outDur + .winSize
    .nFrames = ceiling(.outDur / .hopOut) + 1

    # Audio accumulator + synthesis-window normalization accumulator.
    .outID = Create Sound from formula: "ps_out", 1, 0, .bufferDur, .sr, "0"
    .normID = Create Sound from formula: "ps_norm", 1, 0, .bufferDur, .sr, "0"

    for .i from 0 to .nFrames - 1
        .tIn = .i * .hopIn
        .tMidStart = .tIn - .winSize / 2
        .tMidEnd = .tIn + .winSize / 2

        selectObject: .inputID
        .exStart = max(0, .tMidStart)
        .exEnd = min(.dur, .tMidEnd)

        if .exEnd > .exStart
            .frame = Extract part: .exStart, .exEnd, "rectangular", 1, "no"

            # Center-pad partial boundary frames to the FFT window.
            .durFrame = Get total duration
            if abs(.durFrame - .winSize) > 0.00001
                .padded = Create Sound from formula: "pad", 1, 0, .winSize, .sr, "0"
                .offset = 0
                if .tMidStart < 0
                    .offset = abs(.tMidStart)
                endif
                .sOff$ = fixed$(.offset, 9)
                .fid = .frame
                Formula (part): .offset, min(.winSize, .offset + .durFrame), 1, 1, "self + object(" + string$(.fid) + ", x - " + .sOff$ + ")"
                removeObject: .frame
                .frame = .padded
            endif

            # Analysis window.
            selectObject: .frame
            Multiply by window: "Hanning"

            # Randomize phase while preserving the ORIGINAL magnitude spectrum.
            .spec = To Spectrum: "yes"
            selectObject: .spec
            .matC = To Matrix
            selectObject: .matC
            .matP = Copy: "phases"
            Formula: "randomUniform(-pi, pi)"

            selectObject: .matC
            .matM = Copy: "mags"
            .cid = .matC
            Formula: "if row = 1 then sqrt(object[.cid, 1, col]^2 + object[.cid, 2, col]^2) else self fi"

            selectObject: .matC
            .pid = .matP
            .mid = .matM
            Formula: "if (col=1 or col=ncol) then self else (if row=1 then object[.mid,1,col] * cos(object[.pid,1,col]) else object[.mid,1,col] * sin(object[.pid,1,col]) fi) fi"

            .specMod = To Spectrum
            selectObject: .specMod
            .proc = To Sound

            # Synthesis window.
            selectObject: .proc
            Multiply by window: "Hanning"

            .tOut = .i * .hopOut
            Shift times to: "start time", .tOut
            .writeEnd = min(.bufferDur, .tOut + .winSize)

            if .writeEnd > .tOut
                .procID = .proc
                selectObject: .outID
                Formula (part): .tOut, .writeEnd, 1, 1, "self + object(" + string$(.procID) + ", x)"

                # Accumulate the same synthesis Hann used above. Dividing by
                # this after OLA makes overlap percentage gain-neutral.
                .tOut$ = fixed$(.tOut, 12)
                .win$ = fixed$(.winSize, 12)
                selectObject: .normID
                Formula (part): .tOut, .writeEnd, 1, 1, "self + 0.5 - 0.5*cos(2*pi*(x-" + .tOut$ + ")/" + .win$ + ")"
            endif

            removeObject: .frame, .spec, .matC, .matP, .matM, .specMod, .proc
        endif
    endfor

    # OLA normalization.
    .normStr$ = string$(.normID)
    selectObject: .outID
    Formula: "if object[" + .normStr$ + ",1,col] > 1e-9 then self / object[" + .normStr$ + ",1,col] else 0 fi"
    removeObject: .normID

    # Internal OLA workspace includes one extra window. Return the requested
    # musical duration exactly, not duration+window.
    selectObject: .outID
    if .outDur < .bufferDur
        .trimmed = Extract part: 0, .outDur, "rectangular", 1, "no"
        removeObject: .outID
        .outID = .trimmed
    endif

    selectObject: .outID
endproc

# ===================================================================
# MAIN PROCESSING LOOP
# ===================================================================

appendInfoLine: "Processing slices..."

for i to number_of_slices
    selectObject: sourceSound
    srcDur = Get total duration
    
    # Random slice position
    segLen = randomUniform(min_duration_s, max_duration_s)
    maxStart = srcDur - segLen
    winStart = randomUniform(0, maxStart)
    winEnd = winStart + segLen
    
    # Store for visualization
    sliceStart[i] = winStart
    sliceEnd[i] = winEnd
    
    # Round-robin wet channel assignment. Stereo remains L/R alternating.
    sliceChannel[i] = ((i - 1) mod outputChannels) + 1
    if outputChannels = 2
        if sliceChannel[i] = 1
            chanLabel$ = "L"
        else
            chanLabel$ = "R"
        endif
    else
        chanLabel$ = "Ch" + string$(sliceChannel[i])
    endif
    
    appendInfoLine: "  Slice ", i, " [", chanLabel$, "]: ", fixed$(winStart, 2), "s - ", fixed$(winEnd, 2), "s (", fixed$(segLen, 2), "s)"
    
    # v0.3: rectangular extract (was Hanning in v0.2). The
    # explicit fade_in_s / fade_out_s applied after Paulstretch
    # is now the only envelope shaping.
    selectObject: sourceSound
    segID = Extract part: winStart, winEnd, "rectangular", 1, "no"
    
    # Paulstretch
    @paulstretchFast: segID, stretch_factor, window_size_s, overlap_percent
    psID = selected("Sound")
    
    # Get stretched duration
    selectObject: psID
    stretchedDur = Get total duration
    sliceStretchedDur[i] = stretchedDur
    
    # Apply requested fades, clamped safely to half the stretched slice.
    effectiveFadeIn = min(fade_in_s, stretchedDur / 2)
    effectiveFadeOut = min(fade_out_s, stretchedDur / 2)
    if effectiveFadeIn > 0
        Formula (part): 0, effectiveFadeIn, 1, 1, "self * (0.5 - 0.5 * cos(pi * x / effectiveFadeIn))"
    endif
    if effectiveFadeOut > 0
        fadeOutStart = stretchedDur - effectiveFadeOut
        Formula (part): fadeOutStart, stretchedDur, 1, 1, "self * (0.5 + 0.5 * cos(pi * (x - fadeOutStart) / effectiveFadeOut))"
    endif

    # Safety ceiling only: never boost a quiet source slice.
    slicePeak = Get absolute extremum: 0, 0, "Sinc70"
    if slicePeak > 0.95
        Formula: "self * 0.95 / slicePeak"
    endif
    
    # Calculate placement (centered on original position)
    originalCenter = winStart + (segLen / 2)
    targetStart = originalCenter - (stretchedDur / 2)
    if targetStart < 0
        targetStart = 0
    endif
    sliceTargetStart[i] = targetStart
    
    # Place into appropriate wet channel (L or R)
    selectObject: psID
    Shift times to: "start time", targetStart
    
    psStr$ = string$(psID)
    
    writeEnd = min(paddedDuration, targetStart + stretchedDur)
    selectObject: wetMulti
    if writeEnd > targetStart
        Formula (part): targetStart, writeEnd, sliceChannel[i], sliceChannel[i], "self + object(" + psStr$ + ", x)"
    endif
    if targetStart + stretchedDur > maxRenderedEnd
        maxRenderedEnd = targetStart + stretchedDur
    endif

    # Cleanup
    removeObject: segID, psID
endfor

# ===================================================================
# MIX OUTPUT (preserve source channels; mono source -> historical stereo)
# ===================================================================
appendInfoLine: ""
appendInfoLine: "Mixing ", outputChannels, "-channel output..."

dryAmp = 1 - dry_wet_mix
wetAmp = dry_wet_mix
sourceZeroStr$ = string$(sourceZero)
wetStr$ = string$(wetMulti)

if numChannels = 1
    result = Create Sound from formula: original_name$ + "_PSslice_" + presetName$,
        ... outputChannels, 0, paddedDuration, sampleRate,
        ... "object[" + sourceZeroStr$ + ",1,col] * dryAmp + object[" + wetStr$ + ",row,col] * wetAmp"
else
    result = Create Sound from formula: original_name$ + "_PSslice_" + presetName$,
        ... outputChannels, 0, paddedDuration, sampleRate,
        ... "object[" + sourceZeroStr$ + ",row,col] * dryAmp + object[" + wetStr$ + ",row,col] * wetAmp"
endif

# Downward-only safety ceiling preserves Dry_wet_mix and source dynamics.
selectObject: result
mixPeak = Get absolute extremum: 0, 0, "Sinc70"
if mixPeak > 0.95
    Formula: "self * 0.95 / mixPeak"
endif

# Trim to actual content end, not an arbitrary original+2 seconds.
actualEnd = max(totalDuration, maxRenderedEnd)
if actualEnd > paddedDuration
    actualEnd = paddedDuration
endif
selectObject: result
resultDur = Get total duration
if actualEnd < resultDur - 1 / sampleRate
    trimmed = Extract part: 0, actualEnd, "rectangular", 1, "no"
    removeObject: result
    result = trimmed
    selectObject: result
    Rename: original_name$ + "_PSslice_" + presetName$
endif

# === Cleanup ===
removeObject: sourceSound, sourceZero, wetMulti

# Capture final stats
selectObject: result
finalDuration = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
resultChannels = Get number of channels

# Count first two channels for stereo-style visualization labels.
leftSliceCount = 0
rightSliceCount = 0
for i to number_of_slices
    if sliceChannel[i] = 1
        leftSliceCount += 1
    elsif sliceChannel[i] = 2
        rightSliceCount += 1
    endif
endfor
if outputChannels = 2
    channelSummary$ = string$(leftSliceCount) + " L / " + string$(rightSliceCount) + " R"
else
    channelSummary$ = string$(outputChannels) + " output channels (wet round-robin)"
endif

# ============================================================
# VISUALIZATION  (library-standard explanatory layout)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Black
    Plain line

    # Display names: output filenames keep compact presetName$, but the Picture
    # uses human-readable labels and escapes underscores in Sound names.
    vizName$ = replace$(original_name$, "_", "\_ ", 0)
    vizPreset$ = "Custom"
    if preset = 2
        vizPreset$ = "Subtle Shimmer"
    elsif preset = 3
        vizPreset$ = "Frozen Texture"
    elsif preset = 4
        vizPreset$ = "Extreme Stretch"
    elsif preset = 5
        vizPreset$ = "Glitch Clouds"
    elsif preset = 6
        vizPreset$ = "Ambient Wash"
    endif

    # Mono source for the source panel; every output channel gets its own lane.
    selectObject: original
    if numChannels > 1
        vizOriginal = Convert to mono
    else
        vizOriginal = Copy: "viz_original"
    endif
    selectObject: vizOriginal
    Shift times to: "start time", 0

    for ch to resultChannels
        selectObject: result
        vizResultCh[ch] = Extract one channel: ch
    endfor

    # Shared amplitude scale makes level changes visually meaningful.
    selectObject: vizOriginal
    sharedPeak = Get absolute extremum: 0, 0, "None"
    for ch to resultChannels
        selectObject: vizResultCh[ch]
        chPeak = Get absolute extremum: 0, 0, "None"
        if chPeak > sharedPeak
            sharedPeak = chPeak
        endif
    endfor
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.15

    # Result max time for slice diagram.
    maxTime = max(totalDuration, finalDuration)
    for i to number_of_slices
        endT = sliceTargetStart[i] + sliceStretchedDur[i]
        if endT > maxTime
            maxTime = endT
        endif
    endfor
    if maxTime <= 0
        maxTime = 1
    endif

    # Dynamic page height: all output channels remain visible at a useful lane
    # height. This is preferable to pretending a multichannel result is stereo.
    laneHeight = 0.30
    if resultChannels > 8
        laneHeight = 0.26
    endif
    outputTitleH = 0.18
    outputY0 = 5.48
    outputY1 = outputY0 + outputTitleH + resultChannels * laneHeight + 0.10
    summaryY0 = outputY1 + 0.12
    summaryY1 = summaryY0 + 0.62
    pageHeight = summaryY1 + 0.10
    if pageHeight < 7.60
        pageHeight = 7.60
    endif

    # ----------------------------------------------------------
    # TITLE BAR -- library standard
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##In-Place Paulstretch Slicer v0.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$ + " | " + vizPreset$
        ... + " | " + string$(number_of_slices) + " slices"
        ... + " | " + string$(numChannels) + " -> " + string$(resultChannels) + " ch"
        ... + " | stretch " + fixed$(stretch_factor, 1) + "x"
        ... + " | " + fixed$(dry_wet_mix * 100, 0) + "% wet"

    # ----------------------------------------------------------
    # PANEL A: SLICE MAPPING -- transformation embodied directly
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.65, 4.32
    Select inner viewport: 0.60, 3.85, 0.82, 4.18
    Axes: 0, maxTime * 1.02, 0, number_of_slices + 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxTime * 1.02, 0, number_of_slices + 1

    gridStep = 1
    if maxTime > 20
        gridStep = 5
    elsif maxTime > 10
        gridStep = 2
    endif
    Colour: "{0.88, 0.88, 0.90}"
    Dotted line
    gx = gridStep
    while gx < maxTime
        Draw line: gx, 0, gx, number_of_slices + 1
        gx += gridStep
    endwhile
    Solid line

    for i to number_of_slices
        y = number_of_slices - i + 1
        paletteIndex = ((sliceChannel[i] - 1) mod 8) + 1
        if paletteIndex = 1
            outerColor$ = "{0.96, 0.84, 0.82}"
            innerColor$ = "{0.78, 0.28, 0.22}"
            borderColor$ = "{0.65, 0.18, 0.16}"
        elsif paletteIndex = 2
            outerColor$ = "{0.84, 0.89, 0.96}"
            innerColor$ = "{0.25, 0.45, 0.75}"
            borderColor$ = "{0.18, 0.32, 0.60}"
        elsif paletteIndex = 3
            outerColor$ = "{0.86, 0.93, 0.87}"
            innerColor$ = "{0.35, 0.60, 0.40}"
            borderColor$ = "{0.22, 0.48, 0.28}"
        elsif paletteIndex = 4
            outerColor$ = "{0.96, 0.91, 0.80}"
            innerColor$ = "{0.80, 0.60, 0.20}"
            borderColor$ = "{0.65, 0.47, 0.12}"
        elsif paletteIndex = 5
            outerColor$ = "{0.91, 0.86, 0.94}"
            innerColor$ = "{0.55, 0.35, 0.70}"
            borderColor$ = "{0.44, 0.26, 0.58}"
        elsif paletteIndex = 6
            outerColor$ = "{0.84, 0.93, 0.93}"
            innerColor$ = "{0.20, 0.60, 0.60}"
            borderColor$ = "{0.12, 0.48, 0.48}"
        elsif paletteIndex = 7
            outerColor$ = "{0.95, 0.87, 0.90}"
            innerColor$ = "{0.75, 0.40, 0.55}"
            borderColor$ = "{0.62, 0.28, 0.42}"
        else
            outerColor$ = "{0.91, 0.93, 0.84}"
            innerColor$ = "{0.55, 0.60, 0.25}"
            borderColor$ = "{0.42, 0.48, 0.18}"
        endif

        # Light full-height rectangle = selected source slice.
        Paint rectangle: outerColor$, sliceStart[i], sliceEnd[i], y - 0.35, y + 0.35
        Colour: borderColor$
        Line width: 1
        Draw rectangle: sliceStart[i], sliceEnd[i], y - 0.35, y + 0.35

        # Darker, vertically narrower rectangle = stretched slice placed back.
        stretchedEnd = sliceTargetStart[i] + sliceStretchedDur[i]
        Paint rectangle: innerColor$, sliceTargetStart[i], stretchedEnd, y - 0.22, y + 0.22
        Colour: borderColor$
        Line width: 1.2
        Draw rectangle: sliceTargetStart[i], stretchedEnd, y - 0.22, y + 0.22

        # True source midpoint: the anchor around which placement is attempted.
        originalCenter = (sliceStart[i] + sliceEnd[i]) / 2
        Colour: "{0.25, 0.25, 0.35}"
        Line width: 1.2
        Draw line: originalCenter, y - 0.42, originalCenter, y + 0.42

        if number_of_slices <= 24
            Font size: 5
            Colour: borderColor$
            if resultChannels = 2
                if sliceChannel[i] = 1
                    chLabel$ = "L"
                else
                    chLabel$ = "R"
                endif
            else
                chLabel$ = "Ch" + string$(sliceChannel[i])
            endif
            Text: maxTime * 0.012, "left", y + 0.30, "half", "#" + string$(i) + " " + chLabel$
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Slice"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Marks bottom every: 1, gridStep, "yes", "yes", "no"

    # Title in its own band, lifted clear of the panel frame.
    Select outer viewport: 0, 4, 0.61, 0.78
    Select inner viewport: 0.60, 3.85, 0.62, 0.76
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "Slice map - light = source span, solid = stretched placement"

    # ----------------------------------------------------------
    # PANEL B: WHAT HAPPENS -- concise user-facing process explanation
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.65, 4.32
    Select inner viewport: 4.45, 7.70, 0.82, 4.18
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "What the slicer does"

    Font size: 7
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.06, "left", 0.90, "half", "##1  Pick##   " + string$(number_of_slices) + " random source slices"
    Text: 0.06, "left", 0.72, "half", "##2  Stretch##   phase-randomized OLA"
    Text: 0.06, "left", 0.54, "half", "##3  Place back##   around each original midpoint"
    Text: 0.06, "left", 0.36, "half", "##4  Route wet##   round-robin across " + string$(resultChannels) + " channels"
    Text: 0.06, "left", 0.18, "half", "##5  Mix##   preserve the dry channel layout"

    # Secondary lines carry details without competing with the process steps.
    Font size: 6
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.10, "left", 0.83, "half",
        ... fixed$(min_duration_s * 1000, 0) + "-" + fixed$(max_duration_s * 1000, 0) + " ms each"
    Text: 0.10, "left", 0.65, "half",
        ... fixed$(stretch_factor, 1) + "x | win " + fixed$(ps_effectiveWinSize * 1000, 0) + " ms | overlap " + fixed$(overlap_percent, 0) + "%"
    Text: 0.10, "left", 0.47, "half",
        ... "fade in/out " + fixed$(fade_in_s * 1000, 0) + "/" + fixed$(fade_out_s * 1000, 0) + " ms"
    Text: 0.10, "left", 0.29, "half", "channel colour follows each wet slice to its output lane"
    Text: 0.10, "left", 0.11, "half",
        ... fixed$((1 - dry_wet_mix) * 100, 0) + "% dry + " + fixed$(dry_wet_mix * 100, 0) + "% wet"

    # ----------------------------------------------------------
    # PANEL C: SOURCE WAVEFORM WITH SELECTED SLICE REGIONS
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.45, 5.32
    Select inner viewport: 0.60, 7.70, 4.55, 5.23
    Axes: 0, totalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDuration, 0

    for i to number_of_slices
        paletteIndex = ((sliceChannel[i] - 1) mod 8) + 1
        if paletteIndex = 1
            sliceBg$ = "{0.96, 0.84, 0.82}"
            baseColor$ = "{0.78, 0.28, 0.22}"
        elsif paletteIndex = 2
            sliceBg$ = "{0.84, 0.89, 0.96}"
            baseColor$ = "{0.25, 0.45, 0.75}"
        elsif paletteIndex = 3
            sliceBg$ = "{0.86, 0.93, 0.87}"
            baseColor$ = "{0.35, 0.60, 0.40}"
        elsif paletteIndex = 4
            sliceBg$ = "{0.96, 0.91, 0.80}"
            baseColor$ = "{0.80, 0.60, 0.20}"
        elsif paletteIndex = 5
            sliceBg$ = "{0.91, 0.86, 0.94}"
            baseColor$ = "{0.55, 0.35, 0.70}"
        elsif paletteIndex = 6
            sliceBg$ = "{0.84, 0.93, 0.93}"
            baseColor$ = "{0.20, 0.60, 0.60}"
        elsif paletteIndex = 7
            sliceBg$ = "{0.95, 0.87, 0.90}"
            baseColor$ = "{0.75, 0.40, 0.55}"
        else
            sliceBg$ = "{0.91, 0.93, 0.84}"
            baseColor$ = "{0.55, 0.60, 0.25}"
        endif
        Paint rectangle: sliceBg$, sliceStart[i], sliceEnd[i], -sharedAmp, sharedAmp
        Colour: baseColor$
        Line width: 1.0
        Draw line: sliceStart[i], -sharedAmp, sliceStart[i], sharedAmp
        Draw line: sliceEnd[i], -sharedAmp, sliceEnd[i], sharedAmp
    endfor

    selectObject: vizOriginal
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, totalDuration, -sharedAmp, sharedAmp, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"

    # Source title lifted into the gap above the waveform frame.
    Select outer viewport: 0, 8, 4.37, 4.51
    Select inner viewport: 0.60, 7.70, 4.38, 4.49
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.55, "half", "Source - coloured regions are the slices sent to Paulstretch"

    # ----------------------------------------------------------
    # PANEL D: ALL OUTPUT CHANNELS -- one lane per channel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, outputY0, outputY0 + outputTitleH
    Select inner viewport: 0.60, 7.70, outputY0 + 0.01, outputY0 + outputTitleH - 0.01
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    if resultChannels = 2
        Text: 0.5, "centre", 0.5, "half", "Output - dry layout preserved, wet slices alternate L/R"
    else
        Text: 0.5, "centre", 0.5, "half", "Output - dry layout preserved, wet slices routed round-robin by channel colour"
    endif

    for ch to resultChannels
        laneTop = outputY0 + outputTitleH + (ch - 1) * laneHeight
        laneBottom = laneTop + laneHeight - 0.025
        Select outer viewport: 0, 8, laneTop, laneBottom
        Select inner viewport: 0.60, 7.70, laneTop + 0.015, laneBottom - 0.015
        Axes: 0, finalDuration, -sharedAmp, sharedAmp

        paletteIndex = ((ch - 1) mod 8) + 1
        if paletteIndex = 1
            laneBg$ = "{0.98, 0.94, 0.93}"
            baseColor$ = "{0.78, 0.28, 0.22}"
        elsif paletteIndex = 2
            laneBg$ = "{0.94, 0.96, 0.99}"
            baseColor$ = "{0.25, 0.45, 0.75}"
        elsif paletteIndex = 3
            laneBg$ = "{0.95, 0.98, 0.95}"
            baseColor$ = "{0.35, 0.60, 0.40}"
        elsif paletteIndex = 4
            laneBg$ = "{0.99, 0.97, 0.93}"
            baseColor$ = "{0.80, 0.60, 0.20}"
        elsif paletteIndex = 5
            laneBg$ = "{0.97, 0.95, 0.98}"
            baseColor$ = "{0.55, 0.35, 0.70}"
        elsif paletteIndex = 6
            laneBg$ = "{0.94, 0.98, 0.98}"
            baseColor$ = "{0.20, 0.60, 0.60}"
        elsif paletteIndex = 7
            laneBg$ = "{0.98, 0.95, 0.96}"
            baseColor$ = "{0.75, 0.40, 0.55}"
        else
            laneBg$ = "{0.97, 0.98, 0.94}"
            baseColor$ = "{0.55, 0.60, 0.25}"
        endif

        # Tint is deliberately very light; the waveform carries channel colour.
        Paint rectangle: laneBg$, 0, finalDuration, -sharedAmp, sharedAmp
        Colour: "{0.86, 0.86, 0.86}"
        Draw line: 0, 0, finalDuration, 0
        selectObject: vizResultCh[ch]
        Colour: baseColor$
        Line width: 1
        Draw: 0, finalDuration, -sharedAmp, sharedAmp, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 5
        if resultChannels = 2
            if ch = 1
                laneLabel$ = "L"
            else
                laneLabel$ = "R"
            endif
        else
            laneLabel$ = "Ch" + string$(ch)
        endif
        Text left: "yes", laneLabel$
        if ch = resultChannels
            Text bottom: "yes", "Time (s)"
            Marks bottom every: 1, gridStep, "yes", "yes", "no"
        endif
    endfor

    # ----------------------------------------------------------
    # SUMMARY STRIP -- library standard
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, summaryY0, summaryY1
    Select inner viewport: 0.60, 7.70, summaryY0 + 0.06, summaryY1 - 0.06
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + vizPreset$ + "##  |  " + string$(number_of_slices) + " slices, "
        ... + fixed$(min_duration_s * 1000, 0) + "-" + fixed$(max_duration_s * 1000, 0) + " ms"
        ... + "  |  stretch " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  effective window " + fixed$(ps_effectiveWinSize * 1000, 0) + " ms / " + fixed$(overlap_percent, 0) + "% overlap"
    Text: 0.02, "left", 0.28, "half",
        ... "Dry/wet " + fixed$((1 - dry_wet_mix) * 100, 0) + "/" + fixed$(dry_wet_mix * 100, 0) + "%"
        ... + "  |  " + string$(numChannels) + " input -> " + string$(resultChannels) + " output ch"
        ... + "  |  in " + fixed$(totalDuration, 2) + " s -> out " + fixed$(finalDuration, 2) + " s"
        ... + "  |  peak " + fixed$(finalPeak, 3)
    if resultChannels > 8
        Colour: "{0.35, 0.35, 0.50}"
        Text: 0.98, "right", 0.28, "half", "channel colours repeat after Ch8"
    endif
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Cleanup visualization objects.
    removeObject: vizOriginal
    for ch to resultChannels
        removeObject: vizResultCh[ch]
    endfor

    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

    # Critical export fix: Praat exports only the last selected viewport.
    Select outer viewport: 0, 8, 0, pageHeight
    Select inner viewport: 0, 8, 0, pageHeight
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s | Channels: ", resultChannels
appendInfoLine: "Dry/Wet: ", fixed$((1 - dry_wet_mix) * 100, 0), "% / ", fixed$(dry_wet_mix * 100, 0), "%"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
