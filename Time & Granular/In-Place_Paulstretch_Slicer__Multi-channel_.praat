# ============================================================
# Praat AudioTools - In-Place_Paulstretch_Slicer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
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

form In-Place Paulstretch Slicer v0.5
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
writeInfoLine: "=== In-Place Paulstretch Slicer v0.5 ==="
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
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Mono copy of original and result for waveform panels
    selectObject: original
    if numChannels > 1
        vizOriginal = Convert to mono
    else
        vizOriginal = Copy: "viz_original"
    endif
    selectObject: vizOriginal
    Shift times to: "start time", 0
    
    selectObject: result
    resNumCh = Get number of channels
    vizResultL = Extract one channel: 1
    selectObject: result
    if resNumCh >= 2
        vizResultR = Extract one channel: 2
    else
        vizResultR = Copy: "viz_resultR"
    endif
    
    # SHARED y-axis from original and both result channels
    selectObject: vizOriginal
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResultL
    rlPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResultR
    rrPeak = Get absolute extremum: 0, 0, "None"
    
    sharedPeak = oPeak
    if rlPeak > sharedPeak
        sharedPeak = rlPeak
    endif
    if rrPeak > sharedPeak
        sharedPeak = rrPeak
    endif
    if sharedPeak < 0.01
        sharedPeak = 0.01
    endif
    sharedAmp = sharedPeak * 1.15
    
    # Result max time for slice diagram (use the longest one shown)
    maxTime = totalDuration
    if finalDuration > maxTime
        maxTime = finalDuration
    endif
    for i to number_of_slices
        endT = sliceTargetStart[i] + sliceStretchedDur[i]
        if endT > maxTime
            maxTime = endT
        endif
    endfor
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##IN-PLACE PAULSTRETCH SLICER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... original_name$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(number_of_slices) + " slices (" + channelSummary$ + ")"
        ... + "  |  " + fixed$(stretch_factor, 1) + "x stretch"
        ... + "  |  " + fixed$(ps_effectiveWinSize * 1000, 0) + " ms effective win"
        ... + "  |  " + fixed$(overlap_percent, 0) + "% overlap"
        ... + "  |  " + fixed$(dry_wet_mix * 100, 0) + "% wet"
    
    # ----------------------------------------------------------
    # PANEL A: SLICE MAPPING DIAGRAM  (left, headline)
    # Preserved from v0.2 concept: each slice row shows the
    # original position (lighter, outer rect) and stretched
    # position (darker, inner rect), color-coded by channel.
    # Center marker shows where the original midpoint is.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, maxTime * 1.02, 0, number_of_slices + 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, maxTime * 1.02, 0, number_of_slices + 1
    
    # Grid lines at integer time values
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    gridStep = 1
    if maxTime > 20
        gridStep = 5
    elsif maxTime > 10
        gridStep = 2
    endif
    gx = gridStep
    while gx < maxTime
        Draw line: gx, 0, gx, number_of_slices + 1
        gx = gx + gridStep
    endwhile
    Solid line
    
    for i to number_of_slices
        y = number_of_slices - i + 1
        
        # Determine colors by channel
        if sliceChannel[i] = 1
            outerColor$ = "{1.00, 0.78, 0.78}"
            innerColor$ = "{0.85, 0.40, 0.40}"
            borderColor$ = "{0.65, 0.20, 0.20}"
        else
            outerColor$ = "{0.78, 0.85, 1.00}"
            innerColor$ = "{0.40, 0.55, 0.85}"
            borderColor$ = "{0.20, 0.30, 0.65}"
        endif
        
        # Original slice (outer, lighter)
        Paint rectangle: outerColor$, sliceStart[i], sliceEnd[i], y - 0.35, y + 0.35
        Colour: borderColor$
        Line width: 1
        Draw rectangle: sliceStart[i], sliceEnd[i], y - 0.35, y + 0.35
        
        # Stretched slice (inner, darker)
        stretchedEnd = sliceTargetStart[i] + sliceStretchedDur[i]
        Paint rectangle: innerColor$, sliceTargetStart[i], stretchedEnd, y - 0.22, y + 0.22
        Colour: borderColor$
        Line width: 1.2
        Draw rectangle: sliceTargetStart[i], stretchedEnd, y - 0.22, y + 0.22
        
        # Center marker (original midpoint)
        originalCenter = (sliceStart[i] + sliceEnd[i]) / 2
        Colour: "{0.20, 0.20, 0.20}"
        Line width: 1.5
        Draw line: originalCenter, y - 0.42, originalCenter, y + 0.42
        
        # Slice number + channel label inside the row
        Font size: 5
        Colour: borderColor$
        if outputChannels = 2
            if sliceChannel[i] = 1
                chLabel$ = "L"
            else
                chLabel$ = "R"
            endif
        else
            chLabel$ = "Ch" + string$(sliceChannel[i])
        endif
        labelX = sliceTargetStart[i] - maxTime * 0.005
        if labelX < maxTime * 0.005
            labelX = stretchedEnd + maxTime * 0.005
        endif
        Text: maxTime * 0.005, "left", y + 0.30, "half", "#" + string$(i) + " " + chLabel$
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Slice number"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.94, "half", "Algorithm:"
    Font size: 7
    Text: 0.10, "left", 0.88, "half", "Paulstretch (phase-randomized OLA time stretch)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.80, "half", "Slices:"
    Font size: 9
    Colour: "{0.20, 0.50, 0.82}"
    Text: 0.10, "left", 0.74, "half", string$(number_of_slices) + " total | " + channelSummary$
    Text: 0.10, "left", 0.68, "half", "Duration: " + fixed$(min_duration_s * 1000, 0) + " - " + fixed$(max_duration_s * 1000, 0) + " ms (random)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.60, "half", "Paulstretch:"
    Font size: 9
    Colour: "{0.55, 0.30, 0.78}"
    Text: 0.10, "left", 0.54, "half", fixed$(stretch_factor, 1) + "x stretch | effective window " + fixed$(ps_effectiveWinSize * 1000, 0) + " ms"
    Text: 0.10, "left", 0.48, "half", "Overlap: " + fixed$(overlap_percent, 0) + "% | hop in/out by stretch"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.40, "half", "Slice envelope:"
    Font size: 9
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.34, "half", "Fade in " + fixed$(fade_in_s * 1000, 0) + " ms / out " + fixed$(fade_out_s * 1000, 0) + " ms (v0.3: rect extract)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.26, "half", "Mix:"
    Font size: 9
    Colour: "{0.20, 0.50, 0.30}"
    Text: 0.10, "left", 0.20, "half", "Dry " + fixed$((1 - dry_wet_mix) * 100, 0) + "% | Wet " + fixed$(dry_wet_mix * 100, 0) + "%"
    Text: 0.10, "left", 0.14, "half", "Output: " + string$(outputChannels) + " ch; dry preserved, wet round-robin"
    
    Font size: 9
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.05, "left", 0.05, "half", "Out: " + fixed$(finalDuration, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Slice mapping  (outer = original, inner = stretched; colour families alternate by channel)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ORIGINAL WAVEFORM WITH SLICE MARKERS
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    Axes: 0, totalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, totalDuration, 0
    
    # Slice region shaded backgrounds (faint)
    for i to number_of_slices
        if sliceChannel[i] = 1
            sliceBg$ = "{1.00, 0.92, 0.92}"
        else
            sliceBg$ = "{0.92, 0.94, 1.00}"
        endif
        Paint rectangle: sliceBg$, sliceStart[i], sliceEnd[i], -sharedAmp, sharedAmp
    endfor
    
    # Original waveform
    selectObject: vizOriginal
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1
    Draw: 0, totalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Vertical slice boundary lines
    for i to number_of_slices
        if sliceChannel[i] = 1
            Colour: "{0.85, 0.25, 0.25}"
        else
            Colour: "{0.20, 0.40, 0.85}"
        endif
        Line width: 1.2
        Draw line: sliceStart[i], -sharedAmp, sliceStart[i], sharedAmp
        Draw line: sliceEnd[i], -sharedAmp, sliceEnd[i], sharedAmp
    endfor
    Line width: 1
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform with slice regions  (colour families alternate by wet channel)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: RESULT L AND R WAVEFORMS (SPLIT TOP/BOTTOM)
    # Shows directly which slices got which channel.
    # Shared y-axis with Panel C.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    
    # L channel (top half of panel)
    Select inner viewport: 0.55, 7.72, 5.69, 6.075
    
    Axes: 0, finalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.99, 0.95, 0.95}", 0, finalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDuration, 0
    
    selectObject: vizResultL
    Colour: "{0.85, 0.25, 0.25}"
    Line width: 1
    Draw: 0, finalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Text left: "yes", "L"
    
    # R channel (bottom half of panel)
    Select inner viewport: 0.55, 7.72, 6.085, 6.48
    
    Axes: 0, finalDuration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.95, 0.95, 0.99}", 0, finalDuration, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDuration, 0
    
    selectObject: vizResultR
    Colour: "{0.20, 0.40, 0.85}"
    Line width: 1
    Draw: 0, finalDuration, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Text left: "yes", "R"
    Text bottom: "yes", "Time (s)"
    
    # Panel D title (in the inner area above the L sub-panel)
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    Font size: 7
    Colour: "Black"
    Text: 4.0, "centre", 7.95, "half", "Result channels 1/2 (top/bottom)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + original_name$
        ... + "  |  Slices: " + string$(number_of_slices) + " (" + channelSummary$ + ")"
        ... + "  |  Dur range: " + fixed$(min_duration_s * 1000, 0) + "-" + fixed$(max_duration_s * 1000, 0) + " ms"
        ... + "  |  Stretch: " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  Window: " + fixed$(ps_effectiveWinSize * 1000, 0) + " ms eff. / " + fixed$(overlap_percent, 0) + "%"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Fades: in " + fixed$(fade_in_s * 1000, 0) + " ms / out " + fixed$(fade_out_s * 1000, 0) + " ms"
        ... + "  |  Mix: " + fixed$((1 - dry_wet_mix) * 100, 0) + "% dry / " + fixed$(dry_wet_mix * 100, 0) + "% wet"
        ... + "  |  In: " + fixed$(totalDuration, 2) + " s"
        ... + "  |  Out: " + fixed$(finalDuration, 2) + " s (" + string$(resultChannels) + " ch)"
        ... + "  |  Peak: " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOriginal, vizResultL, vizResultR
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
