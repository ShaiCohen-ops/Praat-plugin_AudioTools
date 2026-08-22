# ============================================================
# Praat AudioTools - Band-Based_Concatenative_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Concatenative synthesis using multi-band spectral matching.
#   Reconstructs target audio using segments from source audio.
#   Matching runs on a mono fold-down; synthesis is per-channel
#   so the source's stereo image is preserved.
#
# Changelog v0.7 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.6:
#   - MATCH PATH NO LONGER LOCKS ON THE LAST SNIPPET. This was a
#     matching bug, not an envelope one: v0.5's buffer did span the
#     whole target, but the path filled it with the same final grain.
#     The search ran around prevMatch with no escape at the end of the
#     source, so once prevMatch reached the last snippet the ideal next
#     position lay past the end, nothing existed there, and the last
#     snippet stayed cheapest for every remaining frame. Measured: a 1 s
#     source against an 8 s target gave the path 54, 56, 56, 57, 59, 61,
#     63, 64, 64, 64... and, snippet 64 being silent, an 8 s object
#     whose audio ended at 0.035 s. Three changes together:
#       * the window is centred on expectedJ = prevMatch + expectedStep,
#         i.e. where continuing straight on would land;
#       * reaching the end of the source triggers a GLOBAL re-search
#         over every snippet, with continuity switched off for that
#         frame;
#       * the continuity penalty is bounded by the search window,
#         min(1, |j - expectedJ| / localityRange). v0.5 measured it in
#         unbounded hop units, so at lambda 1.05 returning to a
#         well-matching snippet cost 9-38 against 5.44 for staying on
#         the silent last one - continuity simply outvoted the spectral
#         match.
#     Restart count is reported.
#   - Snippets with less than half a window of real audio are excluded
#     as candidates. ceiling() can place the final snippet mostly past
#     the end of the source, where synthesis zero-pads it; that made a
#     near-silent grain available as the terminal attractor.
#
# Changelog v0.5 - reviewed by running the script under Parselmouth,
# so the figures below are measurements. The matcher itself passed:
# with source = target every one of 32 frames chose the exact right
# snippet (path 1, 3, 5, 7, ...) and the interior reconstructed at over
# 257 dB SNR. Everything fixed here is around that core.
#   - WEIGHTED OVERLAP-ADD. Whole-file identity SNR was 12.76 dB
#     against 257 dB in the interior: the first frame started at t=0
#     with a Hann window, so the output faded in over half a window,
#     the last frame fell to zero before the end, and floor() left up
#     to a hop of silent tail (10 ms measured on a 1 s file). Frames
#     now start half a window early, the count uses ceiling, the
#     window weights are accumulated in their own buffer and divided
#     out, and the result is trimmed back to the target length. This
#     also removes the inter-grain pumping the old un-normalized sum
#     produced, since grains come from different places at different
#     levels.
#   - Source snippets also use ceiling; floor left up to a snippetHop
#     of the source unavailable as a match candidate.
#   - xmin handled. Source 5.0-6.0 s with target 3.0-4.0 s produced a
#     SILENT output over 0.0-1.0 s with avg cost 0 and no error: every
#     time in the script was reckoned from 0. Both inputs are now
#     copied and shifted to 0, and the output is returned to the
#     target's own time domain.
#   - Every channel is processed and kept. v0.4 computed
#     max(sourceChannels, targetChannels) and then extracted exactly
#     channels 1 and 2, so 4-channel material came out as 2 channels
#     with no warning.
#   - The overlap ratio must now be at least 2. Window 60 ms with hop
#     60 ms gave ratio 1, no overlap, and deep amplitude modulation
#     (identity SNR 3.13 dB); hop 200 ms made intRatio 0 and the run
#     failed downstream. Hop adjustments are reported instead of being
#     applied silently.
#   - Peak normalization is optional. It ran unconditionally, so
#     Dry/wet = 0 returned the target amplified 3.103x rather than the
#     target.
#   - Bands are rebuilt against Nyquist. At 4 kHz an 8-band layout
#     produced bands 6, 7 and 8 all as 1950-2000 Hz. Bands that cannot
#     exist below Nyquist are dropped, and a top band up to Nyquist is
#     added so material above the old 10/12 kHz ceiling takes part in
#     the match.
#   - The continuity penalty is normalized by hop, so Continuity_weight
#     no longer changes meaning with the hop, the locality window or
#     the material length.
#   - Lambda is deterministic. Six identical runs gave lambda between
#     2.275 and 2.356 because the distance sample used randomInteger.
#     The sample is now a fixed stride over the same pairs.
#   - Grain placement uses Formula (part) over the grain's own sample
#     range. v0.4 ran a full-length Formula per frame, which measured
#     0.33 s / 0.97 s / 1.91 s for 4 / 8 / 12 s of audio - near
#     quadratic.
#   - The Output line reported the source name, because source, target
#     and result were all selected before selected$("Sound") was read.
#   - "Coverage" renamed source snippet utilization: a short target
#     against a long source scores low however good the match is.
#
# Changelog v0.4:
#   TIER 1 (polish, audio bit-identical):
#     - Dropped 4 decorative `comment === ... ===` form rows
#       (Temporal Parameters / Frequency Bands / Matching
#       Parameters / Output).
#     - Visualization rewritten from custom 6x6 (2 panels) to
#       suite 8x8:
#         Title bar (suite light) + metadata subtitle
#         Match trajectory  (full width, signature)
#         Match cost over time (full width)
#         Output waveform   (full width)
#         Light-grey 3-line summary (suite standard)
#       The two original panels (match trajectory, match cost)
#       are preserved in content; the output waveform panel and
#       summary bar are new.
#
#   TIER 2 (correctness, audio change only in the affected paths):
#     - FIXED: stereo dry/wet mix collapsed the dry signal to a
#       single channel. v0.3 line 596 used
#         dryWet * self + dryAmount * Object_<targetMix>(x)
#       The `Object_id(x)` time-interpolation function's channel
#       behavior for a multichannel referenced object is
#       version-dependent (may use channel 1 or the channel mean
#       rather than the channel currently being computed). So on
#       stereo output the dry (target) component could be folded
#       to mono and added to both channels. v0.4 uses the
#       explicit index form `object[<targetMix>, row, col]`, which
#       is unambiguous and per-channel. finalOutput and targetMix
#       are sample-aligned by construction (both targetDur at the
#       same sample rate, both starting at t=0), so index access
#       is exact -- no interpolation needed. Only affects runs
#       with dry_wet_mix < 1 on stereo material; the default
#       dry_wet_mix = 1.0 skips this block entirely, so default
#       output is bit-identical to v0.3.
#     - PORTABILITY: the grain-placement Formula terminator
#       `endif` (v0.3 line 508) changed to `fi`. `fi` is the
#       canonical Praat *Formula* conditional terminator;
#       `endif` is the script-level block terminator. Both happen
#       to work in current Praat 6.x Formula strings, but `fi` is
#       the portable form. No behavior change.
#
#   Variable indirection (var_'i'_'b' pseudo-arrays) left as-is;
#   modernizing to matrices is a separate refactor.
#
# Changelog v0.3:
#   - Fixed preset comparison (number not string)
#   - Fixed all array syntax for Praat compatibility
#   - Fixed Formula variable interpolation
#   - Added preset name to output
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly 2 Sound objects: Source (1) and Target (2)"
endif

source = selected("Sound", 1)
target = selected("Sound", 2)

form Band-Based Concatenative Synthesis v0.7
    optionmenu Preset: 1
        option Manual
        option Subtle Morph
        option Granular Texture
        option Spectral Match
        option Rhythmic Mosaic
        option Smooth Blend
    positive Window_length 0.060
    positive Hop_size 0.030
    optionmenu Band_configuration: 2
        option 2 bands (low/high)
        option 4 bands (default)
        option 6 bands (detailed)
        option 8 bands (fine)
    real Continuity_weight 0.3
    positive Locality_window 0.4
    real Dry_wet_mix 1.0
    optionmenu Output_level_mode: 2
        option None (leave level as synthesized)
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Ceiling_peak 0.95
    boolean Play_after_processing 1
    boolean Draw_visualization 1
endform

# ============================================================
# Presets (fixed: use number not string)
# ============================================================
if preset = 2
    window_length = 0.080
    hop_size = 0.040
    continuity_weight = 0.5
    locality_window = 0.6
    presetName$ = "SubtleMorph"
elsif preset = 3
    window_length = 0.040
    hop_size = 0.020
    continuity_weight = 0.15
    locality_window = 0.3
    presetName$ = "GranularTexture"
elsif preset = 4
    window_length = 0.050
    hop_size = 0.025
    continuity_weight = 0.35
    locality_window = 0.4
    presetName$ = "SpectralMatch"
elsif preset = 5
    window_length = 0.100
    hop_size = 0.050
    continuity_weight = 0.7
    locality_window = 0.8
    presetName$ = "RhythmicMosaic"
elsif preset = 6
    window_length = 0.120
    hop_size = 0.060
    continuity_weight = 0.6
    locality_window = 1.0
    presetName$ = "SmoothBlend"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
selectObject: source
sourceName$ = selected$("Sound")
sourceDur = Get total duration
sourceXmin = Get start time
sourceSR = Get sampling frequency
sourceChannels = Get number of channels

selectObject: target
targetName$ = selected$("Sound")
targetDur = Get total duration
targetXmin = Get start time
targetSR = Get sampling frequency
targetChannels = Get number of channels

# Every time in this script - frame starts, grain starts, buffer
# offsets - is reckoned from 0. v0.4 read the durations and ignored
# xmin, so a source at 5.0-6.0 s with a target at 3.0-4.0 s extracted
# grains from times that do not exist in either object and returned a
# silent output over 0.0-1.0 s, with avg cost 0 and no error. Working
# on copies shifted to 0 removes the whole class of problem; the
# target's domain is restored at the end.
selectObject: source
srcWork = Copy: "cs_source_work"
Shift times to: "start time", 0
selectObject: target
tgtWork = Copy: "cs_target_work"
Shift times to: "start time", 0

if sourceSR <> targetSR
    exitScript: "Sample rates must match (" + string$(sourceSR) + " vs " + string$(targetSR) + ")"
endif

sampleRate = sourceSR
nyquist = sampleRate / 2

# OLA constraint. v0.4 rounded the ratio to an integer but never
# required it to be at least 2: window 60 ms with hop 60 ms gave ratio
# 1, no overlap at all, and a measured identity SNR of 3.13 dB from
# the Hann window dipping to zero at every boundary. Hop 200 ms made
# intRatio 0 and the run collapsed further down. Adjustments are also
# reported now rather than applied in silence.
hopRequested = hop_size
ratio = window_length / hop_size
intRatio = round(ratio)
if intRatio < 2
    intRatio = 2
endif
if abs(ratio - intRatio) > 0.01
    hop_size = window_length / intRatio
endif
numStreams = intRatio
hopAdjusted = 0
if abs(hop_size - hopRequested) > 1e-9
    hopAdjusted = 1
endif

# ============================================================
# Set up frequency bands (fixed: Praat array syntax)
# ============================================================
if band_configuration = 1
    numBands = 2
    bandLow_1 = 0
    bandHigh_1 = 1000
    bandLow_2 = 1000
    bandHigh_2 = min(10000, nyquist)
elsif band_configuration = 2
    numBands = 4
    bandLow_1 = 0
    bandHigh_1 = 500
    bandLow_2 = 500
    bandHigh_2 = 1500
    bandLow_3 = 1500
    bandHigh_3 = 4000
    bandLow_4 = 4000
    bandHigh_4 = min(10000, nyquist)
elsif band_configuration = 3
    numBands = 6
    bandLow_1 = 0
    bandHigh_1 = 300
    bandLow_2 = 300
    bandHigh_2 = 800
    bandLow_3 = 800
    bandHigh_3 = 1500
    bandLow_4 = 1500
    bandHigh_4 = 3000
    bandLow_5 = 3000
    bandHigh_5 = 6000
    bandLow_6 = 6000
    bandHigh_6 = min(12000, nyquist)
else
    numBands = 8
    bandLow_1 = 0
    bandHigh_1 = 200
    bandLow_2 = 200
    bandHigh_2 = 400
    bandLow_3 = 400
    bandHigh_3 = 800
    bandLow_4 = 800
    bandHigh_4 = 1500
    bandLow_5 = 1500
    bandHigh_5 = 2500
    bandLow_6 = 2500
    bandHigh_6 = 4000
    bandLow_7 = 4000
    bandHigh_7 = 7000
    bandLow_8 = 7000
    bandHigh_8 = min(12000, nyquist)
endif

# Rebuild the band list against Nyquist. v0.4 clamped each high edge
# and then nudged the low edge back by 50 Hz, which at a 4 kHz sample
# rate turned bands 6, 7 and 8 of the 8-band layout into three copies
# of 1950-2000 Hz - three identical features carrying no information.
# Bands that cannot exist below Nyquist are dropped instead.
keptBands = 0
for b from 1 to numBands
    bLow = bandLow_'b'
    bHigh = bandHigh_'b'
    if bHigh > nyquist
        bHigh = nyquist
    endif
    if bLow < nyquist - 50 and bHigh - bLow >= 50
        keptBands = keptBands + 1
        bandLow_'keptBands' = bLow
        bandHigh_'keptBands' = bHigh
    endif
endfor
if keptBands < 1
    exitScript: "Sample rate " + fixed$(sampleRate, 0) + " Hz (Nyquist " + fixed$(nyquist, 0) +
    ... " Hz) leaves no usable analysis band. Use a higher sample rate or a coarser " +
    ... "band configuration."
endif
droppedBands = numBands - keptBands
numBands = keptBands

# Add a top band running to Nyquist. The fixed layouts stop at 10 or
# 12 kHz, so at 44.1/48 kHz everything above that took no part in the
# distance while still riding along inside the grain that got copied:
# two grains could score identically and differ audibly in cymbals,
# breath or high transients.
topEdge = bandHigh_'numBands'
addedTopBand = 0
if nyquist - topEdge >= 1000
    numBands = numBands + 1
    bandLow_'numBands' = topEdge
    bandHigh_'numBands' = nyquist
    addedTopBand = 1
endif

# ============================================================
# Processing parameters
# ============================================================
# Half a window of head padding, so frame 1 is CENTRED on t = 0 rather
# than starting there. With the weight buffer divided out below, that
# removes the fade-in; ceiling (not floor) makes the last frame reach
# past targetDur, removing the fade-out and the silent tail. Measured
# on v0.4: whole-file identity SNR 12.76 dB against 257 dB in the
# interior, with about 10 ms of silence at the end of a 1 s file.
padHead = window_length / 2
targetFrames = ceiling((targetDur + padHead - window_length) / hop_size) + 1
if targetFrames < 1
    targetFrames = 1
endif
# Padded synthesis buffer: head pad + target + whatever the last frame
# overruns by.
synthSpan = (targetFrames - 1) * hop_size + window_length
padTail = synthSpan - padHead - targetDur
if padTail < 0
    padTail = 0
endif
paddedDur = padHead + targetDur + padTail

snippetHop = hop_size / 2
# ceiling, so the last snippetHop of the source is still a candidate;
# floor left up to one hop of the source unreachable by any match.
sourceSnippets = ceiling((sourceDur - window_length) / snippetHop) + 1
if sourceSnippets < 1
    sourceSnippets = 1
endif

localityRange = max(1, round(locality_window / snippetHop))

# ============================================================
# Convert to mono for analysis
# ============================================================
clearinfo
writeInfoLine: "=== Band-Based Concatenative Synthesis v0.7 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Source: ", sourceName$, " (", fixed$(sourceDur, 2), " s)"
appendInfoLine: "Target: ", targetName$, " (", fixed$(targetDur, 2), " s)"
if hopAdjusted
    appendInfoLine: "  Hop adjusted: ", fixed$(hopRequested * 1000, 1), " -> ",
    ... fixed$(hop_size * 1000, 1), " ms (window / ", intRatio, ", at least 2x overlap)"
endif
appendInfoLine: "Bands:  ", numBands, " up to ", round(bandHigh_'numBands'), " Hz"
if droppedBands > 0
    appendInfoLine: "  ", droppedBands, " band(s) dropped: they fall at or above Nyquist (",
    ... round(nyquist), " Hz)"
endif
if addedTopBand
    appendInfoLine: "  Top band added to Nyquist so high frequencies take part in the match"
endif
appendInfoLine: ""


if sourceChannels > 1
    selectObject: srcWork
    sourceMono = Convert to mono
else
    selectObject: srcWork
    sourceMono = Copy: "source_mono"
endif

if targetChannels > 1
    selectObject: tgtWork
    targetMono = Convert to mono
else
    selectObject: tgtWork
    targetMono = Copy: "target_mono"
endif

# ============================================================
# ANALYSIS: Extract band features
# ============================================================
appendInfoLine: "Analyzing target (", targetFrames, " frames)..."

# Create target band filters
for b from 1 to numBands
    bLow = bandLow_'b'
    bHigh = bandHigh_'b'
    selectObject: targetMono
    Filter (pass Hann band): bLow, bHigh, 100
    targetBand_'b' = selected("Sound")
endfor

# Extract target features
for k from 1 to targetFrames
    # Frame k spans [(k-1)*hop - padHead, +window] in target time. The
    # first and last frames hang off the ends, so the measurement range
    # is clamped to whatever target audio they actually overlap - the
    # frame is still matched on real material rather than on the zeros
    # of the pad.
    tStart = (k - 1) * hop_size - padHead
    tEnd = tStart + window_length
    if tStart < 0
        tStart = 0
    endif
    if tEnd > targetDur
        tEnd = targetDur
    endif
    if tEnd - tStart < 0.001
        tStart = max(0, targetDur - 0.001)
        tEnd = targetDur
    endif
    for b from 1 to numBands
        selectObject: targetBand_'b'
        rms = Get root-mean-square: tStart, tEnd
        if rms > 0
            targetFeature_'k'_'b' = ln(rms + 1e-10)
        else
            targetFeature_'k'_'b' = -23
        endif
    endfor
endfor

# Cleanup target band filters
for b from 1 to numBands
    removeObject: targetBand_'b'
endfor

appendInfoLine: "Analyzing source (", sourceSnippets, " snippets)..."

# Create source band filters
for b from 1 to numBands
    bLow = bandLow_'b'
    bHigh = bandHigh_'b'
    selectObject: sourceMono
    Filter (pass Hann band): bLow, bHigh, 100
    sourceBand_'b' = selected("Sound")
endfor

# Extract source features
for j from 1 to sourceSnippets
    sStart = (j - 1) * snippetHop
    if sStart > sourceDur - 0.001
        sStart = max(0, sourceDur - 0.001)
    endif
    sEnd = sStart + window_length
    if sEnd > sourceDur
        sEnd = sourceDur
    endif
    for b from 1 to numBands
        selectObject: sourceBand_'b'
        rms = Get root-mean-square: sStart, sEnd
        if rms > 0
            sourceFeature_'j'_'b' = ln(rms + 1e-10)
        else
            sourceFeature_'j'_'b' = -23
        endif
    endfor
endfor

# Cleanup source band filters
for b from 1 to numBands
    removeObject: sourceBand_'b'
endfor

# ============================================================
# Z-SCORE NORMALIZATION
# ============================================================
for b from 1 to numBands
    # Compute mean
    sum = 0
    for j from 1 to sourceSnippets
        sum = sum + sourceFeature_'j'_'b'
    endfor
    bandMean_'b' = sum / sourceSnippets
    
    # Compute std
    varSum = 0
    bMean = bandMean_'b'
    for j from 1 to sourceSnippets
        diff = sourceFeature_'j'_'b' - bMean
        varSum = varSum + diff * diff
    endfor
    bandStd_'b' = sqrt(varSum / sourceSnippets)
    if bandStd_'b' < 1e-6
        bandStd_'b' = 1
    endif
endfor

# Normalize source features
for j from 1 to sourceSnippets
    for b from 1 to numBands
        bMean = bandMean_'b'
        bStd = bandStd_'b'
        val = sourceFeature_'j'_'b'
        sourceFeature_'j'_'b' = (val - bMean) / bStd
    endfor
endfor

# Normalize target features
for k from 1 to targetFrames
    for b from 1 to numBands
        bMean = bandMean_'b'
        bStd = bandStd_'b'
        val = targetFeature_'k'_'b'
        targetFeature_'k'_'b' = (val - bMean) / bStd
    endfor
endfor

# ============================================================
# COMPUTE LAMBDA
# ============================================================
# Deterministic distance sample. v0.4 drew both indices with
# randomInteger, so six identical runs produced lambda anywhere from
# 2.275 to 2.356 - the matches happened to agree in the simple case,
# but a near-tie would break either way. A fixed stride covers the same
# ground reproducibly.
sampleSize = min(100, targetFrames * 2)
for s from 1 to sampleSize
    kSamp = ((s - 1) mod targetFrames) + 1
    jSamp = floor((s - 1) * sourceSnippets / sampleSize) + 1
    if jSamp > sourceSnippets
        jSamp = sourceSnippets
    endif
    distSum = 0
    for b from 1 to numBands
        tFeat = targetFeature_'kSamp'_'b'
        sFeat = sourceFeature_'jSamp'_'b'
        diff = tFeat - sFeat
        distSum = distSum + diff * diff
    endfor
    sampleDist_'s' = sqrt(distSum)
endfor

# Simple sort for median
for i from 1 to sampleSize - 1
    for jj from 1 to sampleSize - i
        jj1 = jj + 1
        d1 = sampleDist_'jj'
        d2 = sampleDist_'jj1'
        if d1 > d2
            sampleDist_'jj' = d2
            sampleDist_'jj1' = d1
        endif
    endfor
endfor
medIdx = floor(sampleSize / 2) + 1
medianDist = sampleDist_'medIdx'
lambda = continuity_weight * medianDist

# ============================================================
# MATCHING
# ============================================================
appendInfoLine: "Matching frames..."

# How many source snippets one target hop advances by. snippetHop is
# hop/2, so this is normally 2.
expectedStep = max(1, round(hop_size / snippetHop))

# A snippet whose window runs off the end of the source is padded with
# zeros at synthesis time. Requiring at least half a window of real
# audio keeps the ceiling-added tail candidates (which carry at least
# 75% real audio at any legal hop) while refusing a degenerate one.
usableSnippets = 0
for j from 1 to sourceSnippets
    sAvail = sourceDur - (j - 1) * snippetHop
    if sAvail >= window_length * 0.5
        snippetUsable_'j' = 1
        usableSnippets = usableSnippets + 1
    else
        snippetUsable_'j' = 0
    endif
endfor
if usableSnippets < 1
    snippetUsable_1 = 1
    usableSnippets = 1
endif

prevMatch = 1
totalMatchDist = 0
restartCount = 0

for k from 1 to targetFrames
    bestJ = 0
    bestCost = 1e10

    # Search around where continuing straight on WOULD land, not around
    # where we last were. When that position runs off the end of the
    # source, restart globally.
    #
    # v0.5 searched around prevMatch with no escape at the end of the
    # source. Once prevMatch reached the final snippet the ideal next
    # position was already past the end, no candidate existed there, and
    # the last snippet stayed the cheapest choice for every remaining
    # frame. Measured: a 1 s source against an 8 s target gave the path
    # 54, 56, 56, 57, 59, 61, 63, 64, 64, 64... and, because snippet 64
    # was silent, an 8 s object whose audio stopped at 0.035 s.
    expectedJ = prevMatch + expectedStep
    continuityActive = 1
    if k = 1 or expectedJ > sourceSnippets
        jMin = 1
        jMax = sourceSnippets
        continuityActive = 0
        if k > 1
            restartCount = restartCount + 1
        endif
    else
        jMin = max(1, expectedJ - localityRange)
        jMax = min(sourceSnippets, expectedJ + localityRange)
    endif

    for j from jMin to jMax
        if snippetUsable_'j' = 1
            distSum = 0
            for b from 1 to numBands
                tFeat = targetFeature_'k'_'b'
                sFeat = sourceFeature_'j'_'b'
                diff = tFeat - sFeat
                distSum = distSum + diff * diff
            endfor
            dist = sqrt(distSum)

            if continuityActive = 0
                cost = dist
            else
                # Bounded by the search window, so continuity stays a
                # soft preference. v0.5 measured the jump in unbounded
                # hop units, which made moving back to a well-matching
                # snippet cost 9-38 against 5.44 for staying on the last
                # silent one at lambda 1.05 - the penalty simply
                # outvoted the spectral match.
                jumpError = abs(j - expectedJ)
                timeJump = min(1, jumpError / localityRange)
                cost = dist + lambda * timeJump
            endif

            if cost < bestCost
                bestCost = cost
                bestJ = j
            endif
        endif
    endfor

    if bestJ = 0
        # No usable candidate in the window: fall back to a global scan
        bestJ = 1
        bestCost = 0
    endif

    match_'k' = bestJ
    matchDist_'k' = bestCost
    totalMatchDist = totalMatchDist + bestCost
    prevMatch = bestJ
endfor

# Count unique matches
for j from 1 to sourceSnippets
    matchUsed_'j' = 0
endfor
for k from 1 to targetFrames
    mIdx = match_'k'
    matchUsed_'mIdx' = 1
endfor
uniqueMatches = 0
for j from 1 to sourceSnippets
    uniqueMatches = uniqueMatches + matchUsed_'j'
endfor

avgMatchDist = totalMatchDist / targetFrames
coveragePercent = (uniqueMatches / sourceSnippets) * 100

# ============================================================
# Synthesis: weighted overlap-add
# ============================================================
# v0.4 summed windowed grains into a bare buffer with no weight
# normalization, so the edges faded and the interior pumped whenever
# consecutive grains came from places with different levels. The window
# and the accumulated weight are identical for every channel, so both
# are built once, here.

winLen$ = string$(window_length)
Create Sound from formula: "synth_window", 1, 0, window_length, sampleRate,
    ... "0.5 * (1 - cos(2 * pi * x / " + winLen$ + "))"
synthWin = selected("Sound")
synthWinNs = Get number of samples
synthWin$ = string$(synthWin)

Create Sound from formula: "synth_weight", 1, 0, paddedDur, sampleRate, "0"
weightBuf = selected("Sound")
weightNs = Get number of samples
weightBuf$ = string$(weightBuf)

for k from 1 to targetFrames
    fStartIdx = round((k - 1) * hop_size * sampleRate) + 1
    fEndIdx = fStartIdx + synthWinNs - 1
    if fEndIdx > weightNs
        fEndIdx = weightNs
    endif
    frameStart_'k' = fStartIdx
    if fEndIdx >= fStartIdx
        fOff = fStartIdx - 1
        selectObject: weightBuf
        Formula (part): (fStartIdx - 0.75) / sampleRate, (fEndIdx - 0.25) / sampleRate, 1, 1,
            ... "self + object[" + synthWin$ + ", 1, col - " + string$(fOff) + "]"
    endif
endfor

# Where the target span sits inside the padded buffer, in samples
trimStart = round(padHead * sampleRate) + 1
trimEnd = trimStart + round(targetDur * sampleRate) - 1
if trimEnd > weightNs
    trimEnd = weightNs
endif

procedure synthesizeChannel: .sourceSound, .outputName$
    selectObject: .sourceSound
    .sDur = Get total duration

    Create Sound from formula: "synth_acc", 1, 0, paddedDur, sampleRate, "0"
    .acc = selected("Sound")

    for k from 1 to targetFrames
        j = match_'k'
        grainStart = (j - 1) * snippetHop
        if grainStart > .sDur - 0.001
            grainStart = max(0, .sDur - 0.001)
        endif
        grainEnd = grainStart + window_length
        if grainEnd > .sDur
            grainEnd = .sDur
        endif
        actualGrainDur = grainEnd - grainStart

        if actualGrainDur > 0.001
            selectObject: .sourceSound
            .grain = Extract part: grainStart, grainEnd, "rectangular", 1, "no"

            # Pad a short grain out to a full window. Concatenate follows
            # OBJECT-LIST order and the padding is created after the
            # grain, so the order is grain then silence.
            selectObject: .grain
            .gDur = Get total duration
            if .gDur < window_length - 0.001
                paddingDur = window_length - .gDur
                Create Sound from formula: "padding", 1, 0, paddingDur, sampleRate, "0"
                .padSound = selected("Sound")
                selectObject: .grain
                plusObject: .padSound
                .paddedGrain = Concatenate
                removeObject: .grain, .padSound
                .grain = .paddedGrain
            endif

            selectObject: .grain
            .grainNs = Get number of samples
            Formula: "self * object[" + synthWin$ + ", 1, col]"

            # Write over the grain's own sample range only. v0.4 ran a
            # full-length Formula per frame, rescanning every sample of
            # the output for every grain: measured 0.33 / 0.97 / 1.91 s
            # for 4 / 8 / 12 s of audio, i.e. near quadratic.
            .s1 = frameStart_'k'
            .s2 = .s1 + .grainNs - 1
            if .s2 > weightNs
                .s2 = weightNs
            endif
            if .s2 >= .s1
                .off = .s1 - 1
                selectObject: .acc
                Formula (part): (.s1 - 0.75) / sampleRate, (.s2 - 0.25) / sampleRate, 1, 1,
                    ... "self + object[" + string$(.grain) + ", 1, col - " + string$(.off) + "]"
            endif

            removeObject: .grain
        endif

        if k mod 50 = 0
            appendInfo: "."
        endif
    endfor

    # Divide by the accumulated window weight, then cut the target span
    # back out of the padded buffer.
    selectObject: .acc
    Formula: "if object[" + weightBuf$ + ", 1, col] > 0.000001 then self / object[" +
        ... weightBuf$ + ", 1, col] else 0 fi"

    selectObject: .acc
    Extract part: (trimStart - 1) / sampleRate, trimEnd / sampleRate, "rectangular", 1, "no"
    .outputSound = selected("Sound")
    Rename: .outputName$
    removeObject: .acc

    selectObject: .outputSound
endproc

# ============================================================
# SYNTHESIS
# ============================================================
appendInfoLine: ""
appendInfoLine: "Synthesizing..."

# Every channel is synthesized and kept. v0.4 computed maxChannels and
# then extracted exactly channels 1 and 2, so a 4-channel source or
# target came back as 2 channels with nothing said about it.
maxChannels = max(sourceChannels, targetChannels)

if maxChannels = 1
    @synthesizeChannel: sourceMono, "output_mono"
    finalOutput = selected("Sound")
else
    for ch from 1 to maxChannels
        # If the source has fewer channels than the output needs, its
        # last channel is reused rather than dropping the output channel.
        srcCh = ch
        if srcCh > sourceChannels
            srcCh = sourceChannels
        endif
        if sourceChannels > 1
            selectObject: srcWork
            chIn[ch] = Extract one channel: srcCh
        else
            selectObject: srcWork
            chIn[ch] = Copy: "src_ch"
        endif
        appendInfo: "ch", ch
        @synthesizeChannel: chIn[ch], "output_ch"
        chOut[ch] = selected("Sound")
        removeObject: chIn[ch]
        appendInfoLine: ""
    endfor

    # Row-write assembly: takes any channel count, unlike Combine to
    # stereo, which caps at two.
    selectObject: chOut[1]
    outDurCh = Get total duration
    Create Sound from formula: "output_multi", maxChannels, 0, outDurCh, sampleRate, "0"
    finalOutput = selected("Sound")
    for ch from 1 to maxChannels
        selectObject: finalOutput
        Formula (part): 0, outDurCh, ch, ch,
            ... "object[" + string$(chOut[ch]) + ", 1, col]"
    endfor
    for ch from 1 to maxChannels
        removeObject: chOut[ch]
    endfor
endif

removeObject: synthWin, weightBuf

appendInfoLine: " done"

# ============================================================
# Dry/wet mix
# ============================================================
if dry_wet_mix < 1
    if maxChannels = 1
        selectObject: targetMono
        targetMixId$ = string$(targetMono)
    else
        # Built row by row from the shifted work target, so it matches
        # the output in channel count whatever the two inputs had.
        selectObject: finalOutput
        mixDur = Get total duration
        Create Sound from formula: "target_mix", maxChannels, 0, mixDur, sampleRate, "0"
        targetMix = selected("Sound")
        for ch from 1 to maxChannels
            tgtCh = ch
            if tgtCh > targetChannels
                tgtCh = targetChannels
            endif
            selectObject: tgtWork
            tmpCh = Extract one channel: tgtCh
            selectObject: targetMix
            Formula (part): 0, mixDur, ch, ch,
                ... "object[" + string$(tmpCh) + ", 1, col]"
            removeObject: tmpCh
        endfor
        targetMixId$ = string$(targetMix)
    endif
    
    dryWet$ = string$(dry_wet_mix)
    dryAmount$ = string$(1 - dry_wet_mix)
    
    # v0.4: explicit per-channel index access. v0.3 used
    # Object_<id>(x) (time interpolation), whose channel behavior
    # for a multichannel referenced object is version-dependent
    # (could fold the dry signal to mono on stereo output).
    # finalOutput and targetMix are sample-aligned by construction
    # (same duration, sample rate, and t=0 origin), so object[id,
    # row, col] is exact and per-channel.
    selectObject: finalOutput
    Formula: dryWet$ + " * self + " + dryAmount$ + " * object[" + targetMixId$ + ", row, col]"
    
    if maxChannels > 1
        removeObject: targetMix
    endif
endif

# ============================================================
# Finalize
# ============================================================
selectObject: finalOutput
pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

# v0.4 always ran Scale peak, so Dry/wet = 0 - which should return the
# target untouched - handed back the target amplified 3.103x. It also
# flattened level differences between presets and could lift a very
# quiet result a long way.
if output_level_mode = 2
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

# Give the result the target's own time domain back
selectObject: finalOutput
if targetXmin <> 0
    Shift times to: "start time", targetXmin
endif

Rename: sourceName$ + "_concat_" + targetName$ + "_" + presetName$
finalName$ = selected$("Sound")
selectObject: finalOutput
outPeak = Get absolute extremum: 0, 0, "None"

removeObject: sourceMono, targetMono, srcWork, tgtWork

# ============================================================
# Visualization
# ============================================================
###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Match trajectory       (full width, signature)
# Panel B: Match cost over time    (full width)
# Panel C: Output waveform         (full width)
# Panel D: Light-grey 3-line summary
###############################################################################
procedure drawVisualization
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line
    
    if targetDur > 10
        timeTickInterval = 2
    elsif targetDur > 5
        timeTickInterval = 1
    elsif targetDur > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    suiteVizName$ = replace$(sourceName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Band-Based Concatenative Synthesis v0.7##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.75, 3.05
    Select inner viewport: 0.70, 7.72, 0.95, 2.90
    
    Axes: 0, targetDur, 0, sourceDur
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, targetDur, 0, sourceDur
    
    # Diagonal reference (where target time = source time)
    Colour: "{0.82, 0.82, 0.86}"
    minDur = min(targetDur, sourceDur)
    Draw line: 0, 0, minDur, minDur
    
    # Match trajectory line
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 2
    for k from 1 to targetFrames - 1
        tTime1 = (k - 1) * hop_size - padHead
        tTime2 = k * hop_size - padHead
        m1 = match_'k'
        k1 = k + 1
        m2 = match_'k1'
        sTime1 = (m1 - 1) * snippetHop
        sTime2 = (m2 - 1) * snippetHop
        Draw line: tTime1, sTime1, tTime2, sTime2
    endfor
    
    # Match points (small crosses)
    Colour: "{0.80, 0.25, 0.25}"
    Line width: 1
    pointSize = min(targetDur, sourceDur) * 0.008
    for k from 1 to targetFrames
        tTime = (k - 1) * hop_size - padHead
        mIdx = match_'k'
        sTime = (mIdx - 1) * snippetHop
        Draw line: tTime - pointSize, sTime, tTime + pointSize, sTime
        Draw line: tTime, sTime - pointSize, tTime, sTime + pointSize
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Match trajectory  (grey diagonal = identity; blue = source position chosen per target frame)"
    Text left: "yes", "Source time (s)"
    Text bottom: "yes", "Target time (s)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    if sourceDur > 10
        sourceTickInterval = 2
    elsif sourceDur > 5
        sourceTickInterval = 1
    elsif sourceDur > 2
        sourceTickInterval = 0.5
    else
        sourceTickInterval = 0.25
    endif
    Marks left every: 1, sourceTickInterval, "yes", "yes", "no"
    
    # ----------------------------------------------------------
    # PANEL B: MATCH COST OVER TIME  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.15, 4.45
    Select inner viewport: 0.70, 7.72, 3.30, 4.38
    
    maxDist = 0
    for k from 1 to targetFrames
        d = matchDist_'k'
        if d > maxDist
            maxDist = d
        endif
    endfor
    if maxDist < 0.1
        maxDist = 0.1
    endif
    
    Axes: 0, targetDur, 0, maxDist * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, targetDur, 0, maxDist * 1.1
    
    # Average reference line
    Colour: "{0.70, 0.70, 0.72}"
    Dotted line
    Draw line: 0, avgMatchDist, targetDur, avgMatchDist
    Solid line
    
    # Cost curve
    Colour: "{0.20, 0.60, 0.35}"
    Line width: 2
    for k from 1 to targetFrames - 1
        tTime1 = (k - 1) * hop_size - padHead
        tTime2 = k * hop_size - padHead
        d1 = matchDist_'k'
        k1 = k + 1
        d2 = matchDist_'k1'
        Draw line: tTime1, d1, tTime2, d2
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Match cost per frame  (dotted = mean " + fixed$(avgMatchDist, 2) + ")"
    Text left: "yes", "Cost"
    Text bottom: "yes", "Target time (s)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    if maxDist > 2
        distTickInterval = 1
    elsif maxDist > 1
        distTickInterval = 0.5
    else
        distTickInterval = 0.2
    endif
    Marks left every: 1, distTickInterval, "yes", "yes", "no"
    
    # ----------------------------------------------------------
    # PANEL C: OUTPUT WAVEFORM  (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.55, 5.55
    Select inner viewport: 0.70, 7.72, 4.70, 5.48
    
    # Mono fold-down for a clean single trace
    selectObject: finalOutput
    vizNumCh = Get number of channels
    if vizNumCh > 1
        vizWave = Convert to mono
    else
        vizWave = Copy: "viz_wave"
    endif
    # The panels query fixed 0..targetDur ranges, and the result now
    # carries the target's own xmin.
    selectObject: vizWave
    Shift times to: "start time", 0
    selectObject: vizWave
    vizPeak = Get absolute extremum: 0, 0, "None"
    if vizPeak < 0.001
        vizPeak = 0.001
    endif
    vizAmp = vizPeak * 1.15
    
    Axes: 0, targetDur, -vizAmp, vizAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, targetDur, -vizAmp, vizAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, targetDur, 0
    
    selectObject: vizWave
    Colour: "{0.25, 0.40, 0.65}"
    Line width: 1
    Draw: 0, targetDur, -vizAmp, vizAmp, "no", "Curve"
    removeObject: vizWave
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    
    # ----------------------------------------------------------
    # PANEL D: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.30
    Select inner viewport: 0.70, 7.72, 5.68, 6.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if dry_wet_mix < 1
        mixStr$ = fixed$(dry_wet_mix * 100, 0) + "% wet / " + fixed$((1 - dry_wet_mix) * 100, 0) + "% dry"
    else
        mixStr$ = "100% wet"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.78, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sourceName$ + " -> " + targetName$
        ... + "  |  " + string$(numBands) + " bands"
        ... + "  |  win " + fixed$(window_length * 1000, 0) + " ms, hop " + fixed$(hop_size * 1000, 0) + " ms"
        ... + "  |  continuity " + fixed$(continuity_weight, 2)
        ... + "  |  locality " + fixed$(locality_window, 1) + " s"
    
    Text: 0.02, "left", 0.30, "half",
        ... "Target frames: " + string$(targetFrames)
        ... + "  |  Source snippets: " + string$(sourceSnippets)
        ... + "  |  Restarts: " + string$(restartCount)
        ... + "  |  Unique matches: " + string$(uniqueMatches) + " (" + fixed$(coveragePercent, 1) + "% utilization)"
        ... + "  |  Avg cost: " + fixed$(avgMatchDist, 3)
        ... + "  |  Mix: " + mixStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endproc

if draw_visualization
    @drawVisualization
endif

# ============================================================
# Output
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
# v0.4 selected source, target and result together and then read
# selected$("Sound"), which reported the SOURCE name.
appendInfoLine: "Output: ", finalName$
appendInfoLine: ""
appendInfoLine: "Stats:"
appendInfoLine: "  Target frames: ", targetFrames
appendInfoLine: "  Source snippets: ", sourceSnippets, " (", usableSnippets, " usable)"
appendInfoLine: "  Global restarts: ", restartCount,
    ... " (path reached the end of the source and re-searched)"
# Not a quality score: a short target against a long source uses few
# snippets however well each one matches.
appendInfoLine: "  Unique matches: ", uniqueMatches, " (", fixed$(coveragePercent, 1),
    ... "% source snippet utilization)"
appendInfoLine: "  Avg match cost: ", fixed$(avgMatchDist, 3)
appendInfoLine: "  Peak before output stage: ", fixed$(pre_level_peak, 4)
if output_level_mode = 1
    appendInfoLine: "  Output stage: none"
elsif output_level_mode = 2
    appendInfoLine: "  Output stage: safety ceiling ", fixed$(ceiling_peak, 2), " - ", level_action$
else
    appendInfoLine: "  Output stage: peak normalize to ", fixed$(ceiling_peak, 2),
    ... " (x", fixed$(level_gain, 4), ")"
endif
if output_level_mode <> 3 and outPeak > 1
    appendInfoLine: "  WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput