# ============================================================
# Praat AudioTools - In-Place_Paulstretch_Slicer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   In-Place Paulstretch Slicer - extracts random segments,
#   applies Paulstretch (phase-randomized time stretching),
#   and places them back at original positions. Creates
#   ethereal, frozen texture effects. Slices alternate L-R
#   to produce a stereo result (dry mono on both channels,
#   wet slices split into the alternating channel).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
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

form In-Place Paulstretch Slicer v0.4
    optionmenu Preset: 1
        option Custom
        option Subtle Shimmer
        option Frozen Texture
        option Extreme Stretch
        option Glitch Clouds
        option Ambient Wash
    positive Number_of_slices 4
    real Min_duration_s 0.1
    real Max_duration_s 0.5
    positive Stretch_factor 4.0
    positive Window_size_s 0.25
    positive Overlap_percent 50
    positive Fade_in_s 0.05
    positive Fade_out_s 0.1
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
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Validate ===
if min_duration_s <= 0 or max_duration_s <= 0
    exitScript: "Durations must be positive"
endif
if min_duration_s > max_duration_s
    exitScript: "Min duration cannot exceed max duration"
endif
if max_duration_s > totalDuration
    exitScript: "Max duration cannot exceed sound duration"
endif

# Clamp dry/wet
if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

# === Info ===
writeInfoLine: "=== In-Place Paulstretch Slicer v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(totalDuration, 2), " s)"
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
if abs(ps_effectiveWinSize - window_size_s) > 0.0005
    appendInfoLine: "Window: ", fixed$(ps_effectiveWinSize, 4), " s (", ps_effectiveSamples,
        ... " samples; pow2-rounded up from request of ", fixed$(window_size_s, 4), " s)"
else
    appendInfoLine: "Window: ", fixed$(window_size_s, 4), " s (", ps_effectiveSamples, " samples)"
endif

appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
appendInfoLine: ""

# === Calculate Padding ===
maxStretchedDuration = max_duration_s * stretch_factor
paddingDuration = maxStretchedDuration
paddedDuration = totalDuration + paddingDuration

# === Convert to Mono for Processing ===
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "source_mono"
    sourceSound = selected("Sound")
endif

# === Create Dry Channel (padded original) ===
Create Sound from formula: "pad", 1, 0, paddingDuration, sampleRate, "0"
padSound = selected("Sound")

selectObject: sourceSound, padSound
Concatenate
dryMono = selected("Sound")
Rename: "dry_mono"

removeObject: padSound

# === Create Wet Channels (L and R, empty) ===
Create Sound from formula: "wet_L", 1, 0, paddedDuration, sampleRate, "0"
wetL = selected("Sound")

Create Sound from formula: "wet_R", 1, 0, paddedDuration, sampleRate, "0"
wetR = selected("Sound")

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
    
    # v0.4 Fix A: round .winSamples UP to next pow2 so that
    # `To Spectrum: "yes"` doesn't auto-pad the FFT input.
    # With pow2 input, IFFT roundtrip preserves duration, so the
    # synthesis Hann window applied via `Multiply by window`
    # zeros the edges of the actually-used overlap-add range
    # (Fix A: see header changelog).
    .requestedWinSize = .winSize
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
    .nFrames = ceiling(.outDur / .hopOut) + 1
    
    # Output buffer
    .outID = Create Sound from formula: "ps_out", 1, 0, .outDur + .winSize, .sr, "0"
    
    # Process frames
    for .i from 0 to .nFrames - 1
        .tIn = .i * .hopIn
        .tMidStart = .tIn - .winSize / 2
        .tMidEnd = .tIn + .winSize / 2
        
        selectObject: .inputID
        .exStart = max(0, .tMidStart)
        .exEnd = min(.dur, .tMidEnd)
        
        if .exEnd > .exStart
            .frame = Extract part: .exStart, .exEnd, "rectangular", 1, "no"
            
            # Pad frame if needed
            .durFrame = Get total duration
            if abs(.durFrame - .winSize) > 0.00001
                .padded = Create Sound from formula: "pad", 1, 0, .winSize, .sr, "0"
                .offset = 0
                if .tMidStart < 0
                    .offset = abs(.tMidStart)
                endif
                .sOff$ = fixed$(.offset, 6)
                .fid = .frame
                # v0.3: Formula (part) avoids iterating over
                # the rest of the padded buffer that just
                # returns self.
                Formula (part): .offset, .offset + .durFrame, 1, 1, "self + object(" + string$(.fid) + ", x - " + .sOff$ + ")"
                removeObject: .frame
                .frame = .padded
            endif
            
            # Window
            selectObject: .frame
            Multiply by window: "Hanning"
            
            # Phase Randomization
            .spec = To Spectrum: "yes"
            selectObject: .spec
            .matC = To Matrix
            selectObject: .matC
            .matP = Copy: "phases"
            Formula: "randomUniform(-pi, pi)"
            
            # v0.4 Fix B: precompute magnitudes into a separate
            # Matrix BEFORE running the in-place randomization on
            # .matC. v0.3 used `sqrt(self[1,col]^2 + self[2,col]^2)`
            # inside the .matC Formula, which was corrupted by the
            # in-place evaluation order: when row=2 was processed,
            # `self[1,col]` had already been overwritten by the
            # row=1 branch (with mag*cos(phase)). So the magnitude
            # used for the imag part was wrong.
            # v0.4 reads `object[.mid, 1, col]` for both rows --
            # .matM is never modified during the .matC Formula, so
            # row 2 sees the correct ORIGINAL magnitude.
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
            
            # Window again
            selectObject: .proc
            Multiply by window: "Hanning"
            
            # Overlap Add
            .tOut = .i * .hopOut
            Shift times to: "start time", .tOut
            
            selectObject: .outID
            .procID = .proc
            # v0.3: Formula (part) over [tOut, tOut + winSize]
            # only — the hot loop inside the inner loop. Was
            # iterating over the entire .outID per frame
            # (~88% wasted iterations).
            Formula (part): .tOut, .tOut + .winSize, 1, 1, "self + object(" + string$(.procID) + ", x)"
            
            removeObject: .frame, .spec, .matC, .matP, .matM, .specMod, .proc
        endif
    endfor
    
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
    
    # Determine channel (alternate L-R)
    if i mod 2 = 1
        sliceChannel[i] = 1
        chanLabel$ = "L"
    else
        sliceChannel[i] = 2
        chanLabel$ = "R"
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
    
    # Apply fade in/out to slice
    if fade_in_s > 0 and fade_in_s < stretchedDur / 2
        Formula (part): 0, fade_in_s, 1, 1, "self * (0.5 - 0.5 * cos(pi * x / fade_in_s))"
    endif
    if fade_out_s > 0 and fade_out_s < stretchedDur / 2
        fadeOutStart = stretchedDur - fade_out_s
        Formula (part): fadeOutStart, stretchedDur, 1, 1, "self * (0.5 + 0.5 * cos(pi * (x - fadeOutStart) / fade_out_s))"
    endif
    
    # Normalize slice
    Scale peak: 0.95
    
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
    
    if sliceChannel[i] = 1
        selectObject: wetL
    else
        selectObject: wetR
    endif
    # v0.3: Formula (part) — only [targetStart, targetStart +
    # stretchedDur] is written. wetL/wetR are paddedDuration
    # long; placement occupies a small fraction.
    Formula (part): targetStart, targetStart + stretchedDur, 1, 1, "self + object(" + psStr$ + ", x)"
    
    # Cleanup
    removeObject: segID, psID
endfor

# === Normalize Wet Channels ===
selectObject: wetL
Scale peak: 0.95

selectObject: wetR
Scale peak: 0.95

# ===================================================================
# MIX OUTPUT (Stereo: dry on both + wet L-R)
# ===================================================================

appendInfoLine: ""
appendInfoLine: "Mixing stereo output..."

dryAmp = 1 - dry_wet_mix
wetAmp = dry_wet_mix

# Create Left channel: dry + wetL
Create Sound from formula: "outL", 1, 0, paddedDuration, sampleRate, "0"
outL = selected("Sound")

dryStr$ = string$(dryMono)
wetLStr$ = string$(wetL)
Formula: "object(" + dryStr$ + ", x) * dryAmp + object(" + wetLStr$ + ", x) * wetAmp"

# Create Right channel: dry + wetR
Create Sound from formula: "outR", 1, 0, paddedDuration, sampleRate, "0"
outR = selected("Sound")

wetRStr$ = string$(wetR)
Formula: "object(" + dryStr$ + ", x) * dryAmp + object(" + wetRStr$ + ", x) * wetAmp"

# Combine to stereo
selectObject: outL, outR
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: original_name$ + "_PSslice_" + presetName$

# Cleanup mono channels
removeObject: outL, outR

# === Trim to reasonable length ===
selectObject: result
resultDur = Get total duration
if resultDur > totalDuration + 2
    Extract part: 0, totalDuration + 2, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: result
    result = trimmed
    selectObject: result
    Rename: original_name$ + "_PSslice_" + presetName$
endif

# === Cleanup ===
removeObject: sourceSound, dryMono, wetL, wetR

# Capture final stats
selectObject: result
finalDuration = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# Count channel distribution for summary
leftSliceCount = 0
rightSliceCount = 0
for i to number_of_slices
    if sliceChannel[i] = 1
        leftSliceCount += 1
    else
        rightSliceCount += 1
    endif
endfor

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
    
    selectObject: result
    resNumCh = Get number of channels
    if resNumCh = 2
        vizResultL = Extract one channel: 1
        selectObject: result
        vizResultR = Extract one channel: 2
    else
        vizResultL = Copy: "viz_resultL"
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
        ... + "  |  " + string$(number_of_slices) + " slices (" + string$(leftSliceCount) + " L / " + string$(rightSliceCount) + " R)"
        ... + "  |  " + fixed$(stretch_factor, 1) + "x stretch"
        ... + "  |  " + fixed$(window_size_s * 1000, 0) + " ms win"
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
        if sliceChannel[i] = 1
            chLabel$ = "L"
        else
            chLabel$ = "R"
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
    Text: 0.10, "left", 0.74, "half", string$(number_of_slices) + " total (" + string$(leftSliceCount) + " on L, " + string$(rightSliceCount) + " on R)"
    Text: 0.10, "left", 0.68, "half", "Duration: " + fixed$(min_duration_s * 1000, 0) + " - " + fixed$(max_duration_s * 1000, 0) + " ms (random)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.60, "half", "Paulstretch:"
    Font size: 9
    Colour: "{0.55, 0.30, 0.78}"
    Text: 0.10, "left", 0.54, "half", fixed$(stretch_factor, 1) + "x stretch | window " + fixed$(window_size_s * 1000, 0) + " ms"
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
    Text: 0.10, "left", 0.14, "half", "Output: stereo (dry on both, wet L/R alternating)"
    
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
    Text: 2.10, "centre", 7.30, "half", "Slice mapping  (outer = original, inner = stretched, red = L, blue = R)"
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
    Text top: "no", "Original waveform with slice regions  (red bands = L slices, blue = R)"
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
    Text: 4.0, "centre", 7.95, "half", "Result stereo (L top, R bottom)"
    
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
        ... + "  |  Slices: " + string$(number_of_slices) + " (" + string$(leftSliceCount) + " L / " + string$(rightSliceCount) + " R)"
        ... + "  |  Dur range: " + fixed$(min_duration_s * 1000, 0) + "-" + fixed$(max_duration_s * 1000, 0) + " ms"
        ... + "  |  Stretch: " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  Window: " + fixed$(window_size_s * 1000, 0) + " ms / " + fixed$(overlap_percent, 0) + "%"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Fades: in " + fixed$(fade_in_s * 1000, 0) + " ms / out " + fixed$(fade_out_s * 1000, 0) + " ms"
        ... + "  |  Mix: " + fixed$((1 - dry_wet_mix) * 100, 0) + "% dry / " + fixed$(dry_wet_mix * 100, 0) + "% wet"
        ... + "  |  In: " + fixed$(totalDuration, 2) + " s"
        ... + "  |  Out: " + fixed$(finalDuration, 2) + " s (stereo)"
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
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Dry/Wet: ", fixed$((1 - dry_wet_mix) * 100, 0), "% / ", fixed$(dry_wet_mix * 100, 0), "%"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
