# ============================================================
# Praat AudioTools - CrossEntropy_Concatenative_Mosaicing.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.5 (2026)
#
#   v1.5 (2026) -- visualization uniformity pass; no change to analysis,
#   matching, the stereo chain or synthesis:
#   - FIX: three percent signs were written bare. In Praat drawn text a
#     bare % italicizes the character after it and prints nothing, so
#     the summary read "7 / 25 P-frames used (28.0)" with an italic
#     bracket instead of "(28.0%)", "R coverage=32.0" with no unit, and
#     "(95.2 of 2.50 s uncrossfaded)". All three now use \% plus a
#     spare space, since \% consumes the character that follows it.
#   - FIX: "max reuse=" printed string$(maxUsage), but v1.4 made
#     maxUsage a REAL (the R channel accumulates fractional
#     ambiguity weights rather than +1 per use), so the strip read
#     "max reuse=16.524415730204918x". Now fixed$(maxUsage, 1).
#   - FIX: Sound names were drawn raw, and Praat reads "_" as a
#     subscript marker -- a palette named "my_take_01" printed as
#     "my(sub t)ake(sub 0)1" with the underscores gone. Names are
#     escaped for display only; the objects are untouched.
#   - FIX: drawing ended inside the summary strip, so Save as PNG and
#     Copy to clipboard exported that strip alone (2375 x 343 px)
#     instead of the page. Drawing now ends on the full page.
#   - Half-width gutter widened from 0.45 to 0.60 in: the right
#     column's rotated y-labels ("H (bits)", "Centroid (kHz)", "Bin")
#     were touching the left panel's frame. Inner viewports are now
#     0.60, 3.85 and 4.45, 7.70; panels shift down 0.10 in to clear
#     the taller standard title band.
#   - Title band rebuilt to the library standard (0.52 in, explicit
#     inner viewport, title y = 0.68 / subtitle y = 0.22).
#   - Colour tuples normalized to the 2-decimal, spaced convention; the
#     identity-diagonal grey moves to the standard {0.80, 0.80, 0.80}.
#     The heatmap ramps now emit fixed$(g, 3) rather than string$(g),
#     which was producing 17-digit colour components.
#   - NOT changed, needs a decision: "L" is drawn blue in the
#     reordering map, red in the spectral-H panel, green in the usage
#     histogram and dark amber in the centroid panel, while "R" is
#     amber everywhere. The centroid panel therefore carries two
#     ambers at once. Hues are left as they are pending the palette.
#
#   v1.4 (2026) -- second review-driven correctness pass:
#   - FIX (ambiguity math): v1.3's gap = secondHval - bestHval compared
#     two continuity/variety-BIASED costs drawn from two INDEPENDENT
#     histories (prevBest vs prevSecond). Those are not a top-two
#     ranking of one list, so the gap could read near-zero (-> max
#     stereo width) even when the two chosen grains were spectrally
#     very different, or vice versa. Gap is now the unbiased spectral
#     distance between what L and R actually ended up playing:
#       gap = |secondSpectralH_j - spectralH_j|  (pure H, no bias)
#     "runner-up" is renamed "alternate chain" throughout comments/
#     labels to reflect that R is a genuinely separate search, not a
#     second-place finish in L's ranking.
#   - FIX (ambiguity mapping too aggressive): 2^-gap halves per bit,
#     so ordinary multi-bit gaps (typical with 60-200 bins) collapsed
#     the image almost to mono even at "wide" settings. Added
#     Ambiguity_scale_bits (softens the falloff: a = 2^(-gap/scale))
#     and an explicit Stereo_width 0-1 multiplier so image width is a
#     directly controllable parameter, not just an emergent side
#     effect of the corpus's cost distribution.
#   - FIX (silent P-frame PDF was not a real PDF): v1.3's "uniform-
#     tiny PDF" for a silent P-frame summed to nBins*eps/(1+nBins*eps),
#     not 1 -- not a valid probability distribution, so its cost
#     against a non-silent Q was smaller than intended. Silent
#     P-frames now get an explicit isSilentP# flag and a true uniform
#     PDF (1/nBins per bin, sums to 1) before any add-eps smoothing.
#     Optional Silent_P_penalty_bits (default 0) adds a further, fully
#     explicit search penalty for choosing a silent P-frame to explain
#     a non-silent Q-frame, on top of (not instead of) the now-correct
#     uniform-PDF cost.
#   - FIX (silent-Q visualization contamination): a held-over silent
#     Q-frame no longer copies the previous non-silent match's PDF
#     into matchedPdf#/secondPdf# for display -- it shows true silence
#     (all zeros), so the centroid overlay, PDF heatmap, usage counts,
#     and mean-H/mean-ambiguity in the summary strip no longer count
#     audio that was never actually heard. meanH/meanAmbiguity are now
#     averaged over non-silent Q-frames only.
#   - FIX (match-quality axis could clip R's trace): maxH now takes
#     the max over BOTH spectralH# and secondSpectralH# in stereo
#     mode, not spectralH# alone.
#   - FIX (usage histogram axis could clip stacked bars): maxUsage is
#     now the max of the per-P-frame SUM of L+R usage (matching how
#     the bars are actually stacked), not the max of each channel's
#     own individual max.
#   - FIX (R usage/centroid didn't represent the audible R signal):
#     R usage is now weighted by that frame's ambiguity (a fractional
#     "how much did the alternate grain actually contribute", not a
#     flat +1 for every alternate pick regardless of blend weight).
#     The R centroid trace now plots the ambiguity-blended estimate
#     (1-a)*L_centroid + a*alternate_centroid -- i.e. an approximation
#     of what R actually sounds like -- rather than the alternate
#     chain's own unblended centroid.
#
#   v1.3 (2026) -- review-driven correctness pass:
#   - FIX (stereo is now real): R is no longer a plain second-best
#     chain glued next to L. Each Q-slot keeps its two-minimum
#     search, but the two channels also run INDEPENDENT continuity
#     chains (prevBest for L, prevSecond for R) so R is not just a
#     shadow of L's history. The stereo image itself is built from
#     ambiguity = 2^-gap, gap = secondCost - bestCost (both in bits):
#       R_audio = (1 - ambiguity) * bestSlice + ambiguity * secondSlice
#     near-tied candidates (gap ~ 0) -> ambiguity ~ 1 -> R leans on
#     the runner-up and the image widens; one dominant candidate
#     (gap large) -> ambiguity ~ 0 -> R collapses onto L -> mono.
#   - FIX: the selection cost (spectral cross-entropy + continuity/
#     variety bias) is no longer conflated with cross-entropy
#     itself. `spectralH` = pure H(Q_j,P_i), always >= 0, is what
#     gets plotted and averaged; `selectionCost` (spectralH +
#     variety - continuity) is what argmin actually uses.
#   - FIX: silence is handled explicitly. A Q-frame below
#     Silence_threshold_dB (measured as time-domain RMS, not from
#     the normalized spectral PDF) is not searched at all -- it is
#     reproduced as true silence and the P-frame index simply holds
#     over, rather than being "matched" for free by a P-frame that
#     also happens to look silent.
#   - FIX: epsilon is validated (must be > 0, clamped to a sane
#     range) and used with proper add-and-renormalize smoothing,
#     P'[i,b] = (P[i,b] + eps) / (1 + nBins*eps), so smoothed rows
#     are true PDFs again. As a side effect this also fixes the
#     "silent P-frame looks like a perfect match" failure mode: a
#     silent P-frame smooths to a uniform-tiny PDF, which is a
#     large (not zero) cross-entropy cost against any non-silent Q.
#   - FIX: spectral analysis frames (both P and Q) are cut with a
#     Hann window, not rectangular, before "To Spectrum"; this only
#     affects the copy used to build the PDF -- the raw audio slice
#     later extracted from P for resynthesis is still a plain,
#     unwindowed cut, so no window is baked into the audible output.
#   - FIX: the visualization now surfaces the R channel: usage
#     histogram is stacked L/R, the centroid overlay adds an R
#     trace, the match-quality panel plots spectralH (not the
#     signed selection cost), and the summary strip reports mean
#     ambiguity and R-palette coverage separately.
#   - FIX (docs): the header formula below now matches what the
#     code and changelog actually compute, H(Q_j, P_i), not the
#     reversed H(P_frame, Q_j) that earlier text still described;
#     "magnitude spectrum" is corrected to "normalized band-energy
#     distribution" (the script calls `Get band energy`, not a
#     magnitude-spectrum bin average).
#   - NOTE (documented, not changed): `selected("Sound", 1)` /
#     `selected("Sound", 2)` pick P and Q by POSITION IN THE
#     OBJECTS LIST (top-to-bottom), not by click order -- see
#     Input validation below.
#   - NOTE (documented, not changed): `To Spectrum` on a stereo
#     Sound analyzes the channel-averaged (L+R)/2 signal; width/
#     phase information does not participate in matching even
#     though "Single mosaic" resynthesis still returns P's original
#     stereo grain. Anti-phase content can therefore be
#     under-weighted by the matcher.
#   - NOTE (documented, not changed): trailing material shorter
#     than one full frame at the end of P or Q is dropped (floor,
#     not ceiling, frame count) -- Q's output can end slightly
#     before Q's true ending. The actual output length is now
#     reported to the info window either way (see Step C / Report).
#
# v1.2 (2026):
#   - ADDED Stereo_mode "best + runner-up": the matching loop
#     already ranks every palette frame per slot; L takes the
#     best match, R the second-best (two-minimum tracking, no
#     extra search cost). Both channels track Q; the L/R
#     correlation follows match AMBIGUITY -- many near-equal
#     candidates widen the image, one dominant candidate narrows
#     it toward mono. Chains are crossfade-concatenated
#     separately and combined; stereo palettes are mixed to mono
#     per chain so the output is always true 2-channel in this
#     mode. "Single mosaic" preserves v1.1 behavior exactly.
#     [v1.3: this ambiguity link was declared but not implemented
#     in v1.2 -- L and R were independent argmin/second-argmin
#     chains with no gain or blend tied to gap. See v1.3 notes.]
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Cross-Entropy Concatenative Mosaicing.
#
#   Sound P (source palette) is sliced into equal-length frames and
#   each frame's spectrum is downsampled into nBins bands of band
#   energy and normalized into a probability density function (PDF).
#   Sound Q (target template) is sliced the same way. For every Q
#   frame, the script searches the entire P library and selects the
#   frame whose PDF minimizes the cross-entropy
#     H(Q_j, P_i) = -sum_x Q_j(x) * log2(P_i(x) + eps)
#   against Q_j's PDF -- i.e. the P-frame that best EXPLAINS the
#   target spectrum. The winning P-frame's raw audio is extracted
#   and the frames are concatenated in Q's temporal order, producing
#   a resequencing of P's timbral material that tracks Q's spectral
#   progression.
#
#   Complexity: O(numFramesQ * numFramesP * nBins) for the matching
#   stage. Keep Number_of_bins modest (60-100) for long sounds or
#   fine frame sizes; the Micro Grain preset trades bins for time
#   resolution accordingly.
#
#   v1.1 (2026):
#   - FIX (musical, structural): the divergence direction was
#     REVERSED -- v1.0 minimized H(P_i, Q_j) = -sum P_i log2(Q_j),
#     which is won by whichever palette frame concentrates its
#     mass on Q's single biggest bin. For speech/music that bin
#     is almost always the lowest band, so ONE bass-heavy P-frame
#     swept nearly every slot (observed: 9/185 frames used, max
#     reuse 156x, flat resynthesis centroid). v1.1 minimizes
#     H(Q_j, P_i) = KL(Q_j || P_i) + const: the frame that best
#     EXPLAINS the whole target spectrum, with every uncovered
#     bin costing ~-log2(eps) bits.
#   - ADDED musicality terms (both zeroable): Continuity_bits
#     rewards choosing the palette frame that FOLLOWS the
#     previous choice (source-order runs -> coherent phrases);
#     Variety_bits penalizes re-choosing the immediately previous
#     frame (no stuck notes). Presets carry tuned values.
#   - FIX (clicks): frames were rectangular butt-joints -- one
#     click per frame boundary. Now crossfaded concatenation
#     (min(5 ms, frame/4)).
#   - Presets re-voiced toward longer frames (Standard now
#     100 ms) per listening; Custom default frame 0.1 s.
#   - SPEED: the O(Q*P*bins) matching loop now uses vectorized
#     inner products (inner/row#, probe-verified on 6.4.42).
#   - VIZ: the title was drawn at y = -1.7 inside a 0..1 axis --
#     it escaped its strip and landed on the first panel row;
#     panel rows sat 0.05 in apart so every bottom label struck
#     the next row's title. House title geometry, real inter-row
#     gaps, heavier trace lines.
#
#   v1.0:
#   - Core cross-entropy matching engine (Steps A/B/C) per spec.
#   - ADDED: preset system (5 presets + Custom).
#   - ADDED: metadata header, suite-standard 8-wide visualization
#     (reordering map, entropy trace, P-frame usage, centroid
#     overlay, dual PDF heatmaps, summary strip).
#   - Strict cleanup: no per-frame objects survive the run; only
#     the two inputs and Mosaiced_Output remain in the list.
# ============================================================

####################################################################
# INPUT VALIDATION
####################################################################

if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly two Sound objects (Sound P and Sound Q) before running this script."
endif

# NOTE: selected("Sound", 1/2) are indexed by POSITION IN THE OBJECTS
# LIST (top-to-bottom), not by the order you clicked/ctrl-clicked them.
# Whichever of the two selected Sounds sits HIGHER in the list becomes
# P (source palette); the one below it becomes Q (target template).
soundP_id = selected("Sound", 1)
soundQ_id = selected("Sound", 2)

selectObject: soundP_id
nameP$ = selected$("Sound")
srP = Get sampling frequency
durP = Get total duration

selectObject: soundQ_id
nameQ$ = selected$("Sound")
srQ = Get sampling frequency
durQ = Get total duration

if srP <> srQ
    exitScript: "Sound P (", srP, " Hz) and Sound Q (", srQ, " Hz) must share the same sampling rate."
endif

####################################################################
# FORM
####################################################################

form Cross-Entropy Concatenative Mosaicing v1.5
    comment === Preset Selection ===
    optionmenu Preset 1
        option Custom
        option Fine Detail (30 ms, 120 bins)
        option Standard (100 ms, 100 bins)
        option Coarse Texture (150 ms, 60 bins)
        option Micro Grain (15 ms, 80 bins)
        option Spectral Precision (100 ms, 200 bins)
    comment === Frame & Spectral Analysis ===
    positive Frame_duration_s 0.1
    natural Number_of_bins 100
    real Epsilon 1e-12
    comment === Musicality (0 = pure per-frame argmin) ===
    real Continuity_bits 0.4
    real Variety_bits 0.8
    comment === Silence handling ===
    real Silence_threshold_dB -50
    real Silent_P_penalty_bits 0
    comment === Stereo image (v1.4) ===
    real Ambiguity_scale_bits 4
    real Stereo_width 1
    comment === Output ===
    optionmenu Stereo_mode 1
        option Single mosaic (best match only)
        option Stereo: ambiguity-blended alternate chain (R)
    boolean Draw_visualization 1
    boolean Show_info 1
    boolean Play_result 1
endform

####################################################################
# APPLY PRESETS
####################################################################

if preset = 2
    # Fine Detail
    frame_duration_s = 0.03
    number_of_bins = 120
    continuity_bits = 0.3
    variety_bits = 0.8
    presetName$ = "FineDetail"
elsif preset = 3
    # Standard
    frame_duration_s = 0.10
    number_of_bins = 100
    continuity_bits = 0.4
    variety_bits = 0.8
    presetName$ = "Standard"
elsif preset = 4
    # Coarse Texture
    frame_duration_s = 0.15
    number_of_bins = 60
    continuity_bits = 0.3
    variety_bits = 0.6
    presetName$ = "CoarseTexture"
elsif preset = 5
    # Micro Grain
    frame_duration_s = 0.015
    number_of_bins = 80
    continuity_bits = 0.5
    variety_bits = 1.2
    presetName$ = "MicroGrain"
elsif preset = 6
    # Spectral Precision
    frame_duration_s = 0.10
    number_of_bins = 200
    continuity_bits = 0.2
    variety_bits = 0.6
    presetName$ = "SpectralPrecision"
else
    presetName$ = "Custom"
endif
if continuity_bits < 0
    continuity_bits = 0
endif
if variety_bits < 0
    variety_bits = 0
endif

####################################################################
# PARAMETER VALIDATION
####################################################################

frameDur = frame_duration_s
nBins = number_of_bins

# v1.3: epsilon must be a small positive smoothing constant. A
# non-positive value produces log2(0) or log2(negative); a value
# that isn't small distorts the smoothed PDF (see Step A). Clamp
# rather than exit, so a bad form entry degrades gracefully.
eps = epsilon
if eps <= 0
    eps = 1e-12
endif
if eps > 0.01
    eps = 0.01
endif

# v1.3: silence gate, evaluated on time-domain RMS (dBFS, i.e.
# relative to a full-scale amplitude of 1), independent of the
# normalized spectral PDF scale.
silenceThresholdLinear = 10 ^ (silence_threshold_dB / 20)

# v1.4: explicit search penalty (bits, added to raw cross-entropy)
# for choosing a silent P-frame to explain a non-silent Q-frame, on
# top of the now-correct uniform-PDF cost (see Step A).
silentPPenaltyBits = silent_P_penalty_bits
if silentPPenaltyBits < 0
    silentPPenaltyBits = 0
endif

# v1.4: ambiguity scale (bits) softens 2^-gap so ordinary multi-bit
# gaps don't collapse the image to mono; must be > 0 to avoid a
# divide-by-zero in the exponent.
ambiguityScaleBits = ambiguity_scale_bits
if ambiguityScaleBits <= 0
    ambiguityScaleBits = 0.5
endif

# v1.4: direct 0-1 width multiplier on the final ambiguity blend.
stereoWidth = stereo_width
if stereoWidth < 0
    stereoWidth = 0
elsif stereoWidth > 1
    stereoWidth = 1
endif

numFramesP = floor(durP / frameDur)
numFramesQ = floor(durQ / frameDur)

if numFramesP < 1 or numFramesQ < 1
    exitScript: "Frame_duration_s is too long for the duration of one or both selected sounds."
endif

nyquist = srP / 2
binWidth = nyquist / nBins

selectObject: soundP_id
nChP = Get number of channels

clearinfo
writeInfoLine: "=== Cross-Entropy Concatenative Mosaicing v1.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Sound P (source palette): """, nameP$, """  — ", numFramesP, " frames"
appendInfoLine: "Sound Q (target template): """, nameQ$, """  — ", numFramesQ, " frames"
appendInfoLine: "Frame duration: ", frameDur, " s   |   Spectral bins: ", nBins
appendInfoLine: ""

####################################################################
# STEP A - PRE-ANALYZE SOUND P (build PDF library)
####################################################################

appendInfoLine: "Step A: analyzing spectral PDFs of Sound P..."
pdfP## = zero##(numFramesP, nBins)
# v1.4: true PDF flag. A silent P-frame's raw band energies sum to 0,
# so it cannot be normalized like a real frame -- it is given an
# explicit uniform PDF below (1/nBins per bin, sums to 1) instead of
# v1.3's pdfP/eps trick, which produced a row summing to nBins*eps
# (not 1) and therefore under-costed a silent P-frame as a match.
isSilentP# = zero#(numFramesP)

for i to numFramesP
    t1 = (i - 1) * frameDur
    t2 = t1 + frameDur

    selectObject: soundP_id
    # v1.3: Hann window for the ANALYSIS copy only -- this reduces
    # spectral leakage from frame-boundary discontinuities. The
    # separate rectangular cut used for resynthesis (Step B) is
    # untouched, so no window is baked into the audible output.
    Extract part: t1, t2, "Hanning", 1, "no"
    frameSnd = selected("Sound")
    To Spectrum: "yes"
    frameSpec = selected("Spectrum")

    rowSum = 0
    for b to nBins
        loF = (b - 1) * binWidth
        hiF = b * binWidth
        bandEnergy = Get band energy: loF, hiF
        if bandEnergy < 0
            bandEnergy = 0
        endif
        pdfP##[i, b] = bandEnergy
        rowSum += bandEnergy
    endfor

    if rowSum <= 0
        # v1.4: silent P-frame -- assign a true uniform PDF (each bin
        # = 1/nBins, sums exactly to 1) rather than dividing by eps,
        # which left the row summing to far less than 1.
        isSilentP#[i] = 1
        for b to nBins
            pdfP##[i, b] = 1 / nBins
        endfor
    else
        for b to nBins
            pdfP##[i, b] = pdfP##[i, b] / rowSum
        endfor
    endif

    # Strict memory cleanup - remove temp Sound/Spectrum immediately
    removeObject: frameSnd, frameSpec

    if show_info and (i mod 20 = 0 or i = numFramesP)
        appendInfoLine: "  ...analyzed ", i, " / ", numFramesP, " P-frames"
    endif
endfor

# v1.1: precompute the log-PDF library once -- the matching loop
# then needs a single vectorized inner product per (Q, P) pair
# v1.3: proper add-eps-then-renormalize smoothing, so each smoothed
# row is a true PDF again (sums to 1) rather than pdfP + eps (which
# sums to 1 + nBins*eps and can even go negative-costing on decode).
# v1.4: a P-frame that was true silence now already holds a genuine
# uniform PDF (1/nBins, set in Step A above) going into this step, so
# it costs the correct, non-degenerate log2(nBins)-ish cross-entropy
# against any non-silent Q-frame -- not the under-costed pdfP/eps row
# v1.3 smoothed here.
logP## = zero##(numFramesP, nBins)
smoothDenom = 1 + nBins * eps
for i to numFramesP
    for b to nBins
        logP##[i, b] = log2((pdfP##[i, b] + eps) / smoothDenom)
    endfor
endfor

appendInfoLine: "Step A complete: ", numFramesP, " PDFs stored in memory."
appendInfoLine: ""

####################################################################
# STEP B - TARGET MATCHING LOOP
####################################################################

appendInfoLine: "Step B: matching Sound Q frames against the Sound P library..."

# Per-Q-frame bookkeeping, kept for both resynthesis and viz:
bestFrameIDs#   = zero#(numFramesQ)
# Object ID of the winning (L) P-slice, or a generated silent slice
secondFrameIDs# = zero#(numFramesQ)
# Object ID of the R-channel slice (stereo mode): ambiguity blend
# of the best and alternate-chain slices, or a generated silent slice
matchIndexP#    = zero#(numFramesQ)
# Which P-frame index won for L
secondIndexP#   = zero#(numFramesQ)
# Which P-frame index won R's own independent chain
spectralH#      = zero#(numFramesQ)
# v1.3: pure H(Q_j, P_bestI), unbiased, always >= 0 -- for viz/report
selectionCost#  = zero#(numFramesQ)
# spectralH + variety - continuity -- what argmin actually used
secondSpectralH# = zero#(numFramesQ)
# pure H(Q_j, P_secondI) for R's own chain
ambiguity#      = zero#(numFramesQ)
# 2^-gap, gap = R's selectionCost - L's selectionCost, both bits
isSilentQ#      = zero#(numFramesQ)
# 1 if this Q-frame was below the silence threshold
qPdf##          = zero##(numFramesQ, nBins)
# Q's own PDF per frame (for viz heatmap)
matchedPdf##    = zero##(numFramesQ, nBins)
# PDF of the P-frame chosen for L
secondPdf##     = zero##(numFramesQ, nBins)
# PDF of the P-frame chosen for R's independent chain

prevBest = 0
prevSecond = 0
nSilentQ = 0
for j to numFramesQ
    qt1 = (j - 1) * frameDur
    qt2 = qt1 + frameDur

    # v1.3: silence gate measured on the RAW time-domain signal,
    # before any spectral windowing/normalization erases level info.
    selectObject: soundQ_id
    qRms = Get root-mean-square: qt1, qt2
    if qRms < silenceThresholdLinear
        isSilentQ#[j] = 1
        nSilentQ += 1
    endif

    selectObject: soundQ_id
    # v1.3: Hann window for the analysis copy (see Step A note)
    Extract part: qt1, qt2, "Hanning", 1, "no"
    qFrameSnd = selected("Sound")
    To Spectrum: "yes"
    qFrameSpec = selected("Spectrum")

    pdfQ# = zero#(nBins)
    qSum = 0
    for b to nBins
        loF = (b - 1) * binWidth
        hiF = b * binWidth
        bandEnergy = Get band energy: loF, hiF
        if bandEnergy < 0
            bandEnergy = 0
        endif
        pdfQ#[b] = bandEnergy
        qSum += bandEnergy
    endfor
    if qSum <= 0
        qSum = eps
    endif
    for b to nBins
        pdfQ#[b] = pdfQ#[b] / qSum
        qPdf##[j, b] = pdfQ#[b]
    endfor

    # Q-frame temp objects no longer needed once its PDF is extracted
    removeObject: qFrameSnd, qFrameSpec

    if isSilentQ#[j] = 1
        # v1.3: silent Q is reproduced as silence, not "matched" for
        # free by whatever P-frame happens to look silent too. The
        # reordering-map index just holds over so the L/R traces
        # don't jump around during a silent passage.
        if prevBest = 0
            prevBest = 1
        endif
        if prevSecond = 0
            prevSecond = 1
        endif
        bestI = prevBest
        secondI = prevSecond
        spectralH#[j] = 0
        selectionCost#[j] = 0
        secondSpectralH#[j] = 0
        ambiguity#[j] = 0
        matchIndexP#[j] = bestI
        secondIndexP#[j] = secondI
        # v1.4: the reordering-map index still holds over (so the L/R
        # trace lines don't jump), but the audible output here is
        # true silence, so the PDFs shown for it must be silence too
        # -- copying pdfP of the held-over index (v1.3) inflated the
        # centroid overlay, PDF heatmap, and usage/meanH stats with a
        # frame that was never actually heard.
        for b to nBins
            matchedPdf##[j, b] = 0
            secondPdf##[j, b] = 0
        endfor

        Create Sound from formula: "silentQFrame", nChP, 0, frameDur, srP, "0"
        bestFrameIDs#[j] = selected("Sound")
        if stereo_mode = 2
            Create Sound from formula: "silentQFrameR", nChP, 0, frameDur, srP, "0"
            secondFrameIDs#[j] = selected("Sound")
        endif
    else
        # Search the entire P library once for the raw (unbiased)
        # cross-entropy of every candidate -- v1.3 stores this so L
        # and R can each apply their OWN continuity/variety bias
        # against their OWN history (prevBest / prevSecond) without
        # a second full pass over the spectra.
        rawH# = zero#(numFramesP)
        for i to numFramesP
            rawH#[i] = -inner(pdfQ#, row#(logP##, i))
            # v1.4: this branch only runs for a non-silent Q-frame
            # (see the isSilentQ check above), so an optional extra
            # penalty for explaining it with a silent P-frame is
            # unambiguous here -- it never fires silent-vs-silent.
            if isSilentP#[i] = 1
                rawH#[i] += silentPPenaltyBits
            endif
        endfor

        # --- L: best match, biased by L's own running history ---
        bestI = 1
        bestHval = 1e308
        for i to numFramesP
            h = rawH#[i]
            if i = prevBest
                h += variety_bits
            elsif i = prevBest + 1
                h -= continuity_bits
            endif
            if h < bestHval
                bestHval = h
                bestI = i
            endif
        endfor
        prevBest = bestI

        if stereo_mode = 2 and numFramesP > 1
            # --- R: an INDEPENDENT chain, biased by R's own history,
            # forbidden from picking the same slice as L this slot
            # (so v1.3's ambiguity blend has two genuinely different
            # ingredients to work with) ---
            secondI = 1
            secondHval = 1e308
            for i to numFramesP
                if i <> bestI
                    h = rawH#[i]
                    if i = prevSecond
                        h += variety_bits
                    elsif i = prevSecond + 1
                        h -= continuity_bits
                    endif
                    if h < secondHval
                        secondHval = h
                        secondI = i
                    endif
                endif
            endfor
            prevSecond = secondI
        else
            secondI = bestI
            secondHval = bestHval
        endif

        matchIndexP#[j] = bestI
        secondIndexP#[j] = secondI
        spectralH#[j] = rawH#[bestI]
        selectionCost#[j] = bestHval
        secondSpectralH#[j] = rawH#[secondI]

        # v1.4: gap is now the UNBIASED spectral distance between
        # what L and R each actually chose (pure H, no continuity/
        # variety bias), not v1.3's secondHval - bestHval, which
        # compared two biased costs from two independent histories
        # and was not a real top-two ranking of one list -- that
        # could read gap ~ 0 (-> full stereo width) even when the two
        # picked grains sounded nothing alike, or the reverse.
        # Ambiguity_scale_bits softens the 2^-gap falloff (typical
        # multi-bit gaps no longer collapse the image near-mono by
        # default), and Stereo_width is a direct, final 0-1 multiplier.
        gap = abs(secondSpectralH#[j] - spectralH#[j])
        ambiguity#[j] = stereoWidth * 2 ^ (-gap / ambiguityScaleBits)

        for b to nBins
            matchedPdf##[j, b] = pdfP##[bestI, b]
            secondPdf##[j, b] = pdfP##[secondI, b]
        endfor

        # Extract the winning raw (unwindowed) audio slice from P
        pt1 = (bestI - 1) * frameDur
        pt2 = pt1 + frameDur
        selectObject: soundP_id
        Extract part: pt1, pt2, "rectangular", 1, "no"
        bestFrameIDs#[j] = selected("Sound")

        if stereo_mode = 2
            st1 = (secondI - 1) * frameDur
            st2 = st1 + frameDur
            selectObject: soundP_id
            Extract part: st1, st2, "rectangular", 1, "no"
            secondRaw = selected("Sound")

            # v1.3: R = (1-ambiguity)*L_audio + ambiguity*second_audio.
            # Built as: scale each slice by 2x its weight, average the
            # two channels of a stereo Combine (Convert to mono halves
            # the sum back down) -- avoids needing cross-object Formula
            # references, using only Copy / Formula / Combine to
            # stereo / Convert to mono, all already used elsewhere in
            # this script.
            ambVal = ambiguity#[j]
            selectObject: bestFrameIDs#[j]
            Copy: "blendL"
            blendL = selected("Sound")
            if nChP > 1
                mono1 = Convert to mono
                removeObject: blendL
                blendL = mono1
            endif
            selectObject: blendL
            Formula: "self * 2 * (1 - 'ambVal')"

            selectObject: secondRaw
            Copy: "blendR"
            blendR = selected("Sound")
            if nChP > 1
                mono2 = Convert to mono
                removeObject: blendR
                blendR = mono2
            endif
            selectObject: blendR
            Formula: "self * 2 * 'ambVal'"
            removeObject: secondRaw

            selectObject: blendL
            plusObject: blendR
            Combine to stereo
            blendStereo = selected("Sound")
            Convert to mono
            secondFrameIDs#[j] = selected("Sound")
            removeObject: blendL, blendR, blendStereo
        endif
    endif

    if show_info and (j mod 20 = 0 or j = numFramesQ)
        appendInfoLine: "  ...matched Q-frame ", j, " / ", numFramesQ,
        ... "  (best P-frame = ", matchIndexP#[j], ", H = ", fixed$(spectralH#[j], 4), ")"
    endif
endfor

appendInfoLine: "Step B complete: ", numFramesQ, " matches found."
if nSilentQ > 0
    appendInfoLine: "  ", nSilentQ, " Q-frame(s) below ", silence_threshold_dB,
    ... " dBFS reproduced as true silence (not spectrally matched)."
endif
appendInfoLine: ""

####################################################################
# STEP C - RESYNTHESIS
####################################################################

appendInfoLine: "Step C: concatenating ", numFramesQ, " reordered frames..."

# v1.1: crossfaded joins -- rectangular butt-joints clicked at
# every frame boundary
xfadeDur = min(0.005, frameDur / 4)

selectObject: bestFrameIDs#[1]
for j from 2 to numFramesQ
    plusObject: bestFrameIDs#[j]
endfor
if numFramesQ > 1
    Concatenate with overlap: xfadeDur
else
    Concatenate
endif
chainL = selected("Sound")

if stereo_mode = 2
    # v1.3: right channel = ambiguity blend of best + alternate chain
    # (each frame was already reduced to mono when it was built,
    # see Step B), still concatenated with the same crossfade as L.
    selectObject: secondFrameIDs#[1]
    for j from 2 to numFramesQ
        plusObject: secondFrameIDs#[j]
    endfor
    if numFramesQ > 1
        Concatenate with overlap: xfadeDur
    else
        Concatenate
    endif
    chainR = selected("Sound")

    # chainL from a stereo palette is still stereo -- mix to mono so
    # the combined output is true 2-channel L/R. chainR is already
    # mono (built per-frame in Step B), so it's only converted if it
    # somehow isn't (e.g. mono palette also produced a mono chainL).
    selectObject: chainL
    chCkL = Get number of channels
    if chCkL > 1
        mL = Convert to mono
        removeObject: chainL
        chainL = mL
    endif
    selectObject: chainR
    chCkR = Get number of channels
    if chCkR > 1
        mR = Convert to mono
        removeObject: chainR
        chainR = mR
    endif
    selectObject: chainL
    plusObject: chainR
    Combine to stereo
    Rename: "Mosaiced_Output"
    output_sound = selected("Sound")
    removeObject: chainL, chainR
else
    selectObject: chainL
    Rename: "Mosaiced_Output"
    output_sound = selected("Sound")
endif

# Remove every individual extracted frame Sound - leaves only the
# two original inputs and Mosaiced_Output.
for j to numFramesQ
    removeObject: bestFrameIDs#[j]
    if stereo_mode = 2
        removeObject: secondFrameIDs#[j]
    endif
endfor

selectObject: output_sound

# v1.3: crossfaded concatenation is SHORTER than numFramesQ*frameDur
# (Praat's "Concatenate with overlap" removes one xfadeDur per join).
# Take the real duration from the finished Sound rather than
# estimating it, and derive the actual per-frame hop from it so the
# centroid-overlay time axis matches how fast the output really
# advances through Q's material.
totalDur = Get total duration
estimatedDurNoXfade = numFramesQ * frameDur
if numFramesQ > 1
    frameHop = (totalDur - frameDur) / (numFramesQ - 1)
else
    frameHop = frameDur
endif
timeCompressionPct = 100 * totalDur / estimatedDurNoXfade

####################################################################
# VISUALIZATION
####################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    # --- Derived viz quantities -------------------------------------
    # Spectral centroid per frame (Hz), computed from the stored PDFs.
    # Used to show whether the resynthesis tracks Q's brightness curve.
    # v1.3: also tracks R's own (independent) chain.
    qCentroid# = zero#(numFramesQ)
    matchedCentroid# = zero#(numFramesQ)
    secondCentroid# = zero#(numFramesQ)
    # v1.4: blendedRCentroid# approximates what R actually SOUNDS
    # like -- (1-ambiguity)*L + ambiguity*alternate -- rather than
    # plotting the alternate chain's own unblended centroid, which
    # v1.3 showed even when ambiguity ~ 0 and R was audibly ~ L.
    blendedRCentroid# = zero#(numFramesQ)
    for j to numFramesQ
        cQ = 0
        cM = 0
        cS = 0
        for b to nBins
            binFreq = (b - 0.5) * binWidth
            cQ += qPdf##[j, b] * binFreq
            cM += matchedPdf##[j, b] * binFreq
            cS += secondPdf##[j, b] * binFreq
        endfor
        qCentroid#[j] = cQ
        matchedCentroid#[j] = cM
        secondCentroid#[j] = cS
        blendedRCentroid#[j] = (1 - ambiguity#[j]) * cM + ambiguity#[j] * cS
    endfor
    maxCentroid = max(max(qCentroid#), max(max(matchedCentroid#), max(blendedRCentroid#)))
    if maxCentroid <= 0
        maxCentroid = nyquist
    endif

    # P-frame usage histogram (how many times each P-frame was chosen),
    # v1.3: L and R counted separately so palette coverage of the
    # alternate chain is visible too.
    usageCount# = zero#(numFramesP)
    usageCountR# = zero#(numFramesP)
    for j to numFramesQ
        if isSilentQ#[j] = 0
            # v1.4: silent Q-frames are excluded -- the held-over
            # index was never actually played, so it shouldn't count
            # as palette "usage".
            idx = matchIndexP#[j]
            usageCount#[idx] += 1
            if stereo_mode = 2
                idxR = secondIndexP#[j]
                # v1.4: weighted by this frame's ambiguity rather than
                # a flat +1 -- when ambiguity is near 0, R ~ L and the
                # alternate grain barely sounds, so it shouldn't count
                # as a full "use" of that P-frame.
                usageCountR#[idxR] += ambiguity#[j]
            endif
        endif
    endfor
    # v1.4: bars are drawn STACKED (L base + R cap below), so the axis
    # must fit the per-P-frame SUM of L+R, not the max of each
    # channel's own individual max (which could clip the tallest bar).
    maxUsage = 0
    for i to numFramesP
        stackedUsage = usageCount#[i] + usageCountR#[i]
        if stackedUsage > maxUsage
            maxUsage = stackedUsage
        endif
    endfor
    if maxUsage < 1
        maxUsage = 1
    endif

    # Match-quality trace range -- v1.3: plots pure spectralH, not
    # the signed (variety/continuity-biased) selection cost, which
    # can go negative and isn't cross-entropy anymore.
    # v1.4: in stereo mode the amber R trace (secondSpectralH#) is
    # also plotted on this axis and can run higher than spectralH#
    # alone -- include it in the range so it can't get cut off.
    if stereo_mode = 2
        maxH = max(max(spectralH#), max(secondSpectralH#))
    else
        maxH = max(spectralH#)
    endif
    if maxH <= 0
        maxH = 1
    endif

    # Heatmap downsampling strides (keep rendering fast on long sounds)
    maxVizCols = 80
    maxVizRows = 50
    strideJ = ceiling(numFramesQ / maxVizCols)
    if strideJ < 1
        strideJ = 1
    endif
    strideB = ceiling(nBins / maxVizRows)
    if strideB < 1
        strideB = 1
    endif

    # === TITLE ===
    # v1.1: explicit inner viewport + in-range y (the old y=-1.7
    # escaped the strip and landed on the first panel row)
    # v1.5: Praat reads "_" in drawn text as a subscript marker, so a
    # Sound named "my_take_01" printed as "my(sub t)ake(sub 0)1" and the
    # underscores vanished. Escape them for display only; the object
    # names themselves are untouched.
    vizNameP$ = replace$(nameP$, "_", "\_ ", 0)
    vizNameQ$ = replace$(nameQ$, "_", "\_ ", 0)

    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half",
        ... "##Cross-Entropy Concatenative Mosaicing v1.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizNameP$ + " -> " + vizNameQ$
        ... + " | " + presetName$
        ... + " | " + string$(numFramesP) + " P-frames, " + string$(numFramesQ) + " Q-frames"
        ... + " | frame " + fixed$(frameDur * 1000, 0) + " ms, bins " + string$(nBins)

    # === PANEL: REORDERING MAP ===
    Select outer viewport: 0, 4, 0.65, 2.20
    Select inner viewport: 0.60, 3.85, 0.77, 2.07

    Axes: 0, numFramesQ, 0, numFramesP
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numFramesQ, 0, numFramesP

    # Identity-mapping reference (Q-frame j == P-frame j), for scale
    Colour: "{0.80, 0.80, 0.80}"
    diagEnd = min(numFramesQ, numFramesP)
    Draw line: 0, 0, diagEnd, diagEnd

    if stereo_mode = 2
        Colour: "{0.90, 0.70, 0.40}"
        for j from 1 to numFramesQ - 1
            Draw line: j - 1, secondIndexP#[j], j, secondIndexP#[j + 1]
        endfor
    endif
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 1.5
    for j from 1 to numFramesQ - 1
        Draw line: j - 1, matchIndexP#[j], j, matchIndexP#[j + 1]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "P-frame index"
    if stereo_mode = 2
        Text top: "no", "Reordering map (blue = L/best, amber = R/alternate)"
    else
        Text top: "no", "Reordering map (which P-slice fills each Q-slot)"
    endif
    Text bottom: "yes", "Q-frame index"

    # === PANEL: CROSS-ENTROPY MATCH QUALITY ===
    # v1.3: plots pure spectralH (always >= 0), not the variety/
    # continuity-biased selectionCost that argmin actually used.
    Select outer viewport: 4, 8, 0.65, 2.20
    Select inner viewport: 4.45, 7.70, 0.77, 2.07

    Axes: 0, numFramesQ, 0, maxH * 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numFramesQ, 0, maxH * 1.05

    if stereo_mode = 2
        Colour: "{0.90, 0.70, 0.40}"
        for j from 1 to numFramesQ - 1
            Draw line: j - 1, secondSpectralH#[j], j, secondSpectralH#[j + 1]
        endfor
    endif
    Colour: "{0.80, 0.20, 0.40}"
    Line width: 1.5
    for j from 1 to numFramesQ - 1
        Draw line: j - 1, spectralH#[j], j, spectralH#[j + 1]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "H (bits)"
    if stereo_mode = 2
        Text top: "no", "Spectral H (red = L/best, amber = R/alternate, unblended)"
    else
        Text top: "no", "Match quality (lower = better fit)"
    endif
    Text bottom: "yes", "Q-frame index"

    # === PANEL: P-FRAME USAGE HISTOGRAM ===
    # v1.3: stacked bars -- green base = L (best) usage, amber cap
    # on top = R (alternate chain, ambiguity-weighted) usage, so
    # palette coverage of
    # both independent chains is visible.
    Select outer viewport: 0, 4, 2.55, 4.10
    Select inner viewport: 0.60, 3.85, 2.67, 3.97

    Axes: 0, numFramesP, 0, maxUsage * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, numFramesP, 0, maxUsage * 1.15

    for i to numFramesP
        if usageCount#[i] > 0
            Paint rectangle: "{0.20, 0.80, 0.40}", i - 1, i, 0, usageCount#[i]
        endif
        if stereo_mode = 2 and usageCountR#[i] > 0
            Paint rectangle: "{0.90, 0.70, 0.40}", i - 1, i, usageCount#[i], usageCount#[i] + usageCountR#[i]
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Times used"
    if stereo_mode = 2
        Text top: "no", "P-frame usage (green = L, amber = R, stacked)"
    else
        Text top: "no", "P-frame usage (palette coverage)"
    endif
    Text bottom: "yes", "P-frame index"

    # === PANEL: SPECTRAL CENTROID OVERLAY ===
    # v1.3: x-axis uses the ACTUAL per-frame hop in the finished,
    # crossfade-shortened output (frameHop), not the uncompressed
    # frameDur, so this trace lines up with real playback time.
    Select outer viewport: 4, 8, 2.55, 4.10
    Select inner viewport: 4.45, 7.70, 2.67, 3.97

    Axes: 0, totalDur, 0, maxCentroid / 1000 * 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDur, 0, maxCentroid / 1000 * 1.05

    Colour: "{0.60, 0.60, 0.60}"
    Line width: 1.5
    for j from 1 to numFramesQ - 1
        Draw line: (j - 1) * frameHop, qCentroid#[j] / 1000, j * frameHop, qCentroid#[j + 1] / 1000
    endfor
    if stereo_mode = 2
        Colour: "{0.90, 0.70, 0.40}"
        for j from 1 to numFramesQ - 1
            Draw line: (j - 1) * frameHop, blendedRCentroid#[j] / 1000, j * frameHop, blendedRCentroid#[j + 1] / 1000
        endfor
    endif
    Colour: "{0.80, 0.60, 0.20}"
    for j from 1 to numFramesQ - 1
        Draw line: (j - 1) * frameHop, matchedCentroid#[j] / 1000, j * frameHop, matchedCentroid#[j + 1] / 1000
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Centroid (kHz)"
    Text top: "no", "Spectral centroid: target vs. resynthesis"
    Text bottom: "yes", "Time (s)"
    Font size: 6
    Colour: "{0.60, 0.60, 0.60}"
    Text: totalDur * 0.02, "left", maxCentroid / 1000 * 0.95, "half", "Q (target)"
    Colour: "{0.80, 0.60, 0.20}"
    Text: totalDur * 0.02, "left", maxCentroid / 1000 * 0.86, "half", "L (resynthesis)"
    if stereo_mode = 2
        Colour: "{0.90, 0.70, 0.40}"
        Text: totalDur * 0.02, "left", maxCentroid / 1000 * 0.77, "half", "R (blended, audible estimate)"
    endif

    # === PANEL: Q TARGET PDF HEATMAP ===
    Select outer viewport: 0, 4, 4.45, 6.65
    Select inner viewport: 0.60, 3.85, 4.57, 6.52

    Axes: 0, numFramesQ, 0, nBins
    j = 1
    while j <= numFramesQ
        b = 1
        while b <= nBins
            v = qPdf##[j, b]
            g = 1 - min(v * 12, 1)
            colour$ = "{" + fixed$(g, 3) + ", " + fixed$(g * 0.7 + 0.3, 3)
                ... + ", " + fixed$(g, 3) + "}"
            jEnd = min(j + strideJ - 1, numFramesQ)
            bEnd = min(b + strideB - 1, nBins)
            Paint rectangle: colour$, j - 1, jEnd, b - 1, bEnd
            b += strideB
        endwhile
        j += strideJ
    endwhile

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Bin"
    Text top: "no", "Target PDF (Sound Q spectral progression)"
    Text bottom: "yes", "Q-frame index"

    # === PANEL: RECONSTRUCTED PDF HEATMAP ===
    Select outer viewport: 4, 8, 4.45, 6.65
    Select inner viewport: 4.45, 7.70, 4.57, 6.52

    Axes: 0, numFramesQ, 0, nBins
    j = 1
    while j <= numFramesQ
        b = 1
        while b <= nBins
            v = matchedPdf##[j, b]
            g = 1 - min(v * 12, 1)
            colour$ = "{" + fixed$(g, 3) + ", " + fixed$(g, 3)
                ... + ", " + fixed$(g * 0.7 + 0.3, 3) + "}"
            jEnd = min(j + strideJ - 1, numFramesQ)
            bEnd = min(b + strideB - 1, nBins)
            Paint rectangle: colour$, j - 1, jEnd, b - 1, bEnd
            b += strideB
        endwhile
        j += strideJ
    endwhile

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Bin"
    Text top: "no", "Resynthesized PDF (chosen P-slices)"
    Text bottom: "yes", "Q-frame index"

    # === SUMMARY STRIP ===
    Select outer viewport: 0, 8, 7.00, 7.70
    Select inner viewport: 0.60, 7.70, 7.05, 7.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    # v1.4: averaged over non-silent Q-frames only -- silent frames
    # contribute spectralH = ambiguity = 0 by construction (held-over,
    # never searched), so including them in the average diluted both
    # meanH and meanAmbiguity toward zero rather than reflecting the
    # actual matching quality on the material that was searched.
    meanH = 0
    meanAmbiguity = 0
    nNonSilentQ = numFramesQ - nSilentQ
    for j to numFramesQ
        if isSilentQ#[j] = 0
            meanH += spectralH#[j]
            meanAmbiguity += ambiguity#[j]
        endif
    endfor
    if nNonSilentQ > 0
        meanH = meanH / nNonSilentQ
        meanAmbiguity = meanAmbiguity / nNonSilentQ
    endif
    uniqueUsed = 0
    uniqueUsedR = 0
    for i to numFramesP
        if usageCount#[i] > 0
            uniqueUsed += 1
        endif
        if usageCountR#[i] > 0
            uniqueUsedR += 1
        endif
    endfor
    coveragePct = 100 * uniqueUsed / numFramesP
    coveragePctR = 100 * uniqueUsedR / numFramesP

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.78, "half",
        ... "##Analysis##  P=" + string$(numFramesP) + " frames"
        ... + "  Q=" + string$(numFramesQ) + " frames"
        ... + "  bins=" + string$(nBins)
        ... + "  mean spectral H=" + fixed$(meanH, 3) + " bits"
        ... + (if nSilentQ > 0 then "  silent Q-frames=" + string$(nSilentQ) else "" fi)
    Text: 0.02, "left", 0.48, "half",
        ... "##Palette coverage (L)##  " + string$(uniqueUsed) + " / " + string$(numFramesP)
        ... + " P-frames used (" + fixed$(coveragePct, 1) + "\% )"
        ... + "  max reuse=" + fixed$(maxUsage, 1) + "x"
        ... + (if stereo_mode = 2 then "  |  R coverage=" + fixed$(coveragePctR, 1) + "\%   mean ambiguity=" + fixed$(meanAmbiguity, 2) else "" fi)
    Text: 0.02, "left", 0.18, "half",
        ... "##Output##  " + fixed$(totalDur, 2) + " s"
        ... + " (" + fixed$(timeCompressionPct, 1) + "\%  of " + fixed$(estimatedDurNoXfade, 2) + " s uncrossfaded)"
        ... + "  preset=" + presetName$
        ... + "  frame=" + fixed$(frameDur * 1000, 0) + " ms"
        ... + "  continuity=" + fixed$(continuity_bits, 2)
        ... + "  variety=" + fixed$(variety_bits, 2)
        ... + "  |  H(Q||P) matching"
        ... + (if stereo_mode = 2 then "  |  stereo: ambiguity-blended alternate chain" else "" fi)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the full page as the last drawing action, so Save as PNG /
    # Copy to clipboard capture the whole figure rather than cropping to
    # the summary strip.
    Select outer viewport: 0, 8, 0, 7.70
    Font size: 10
    Colour: "Black"
    Line width: 1

    appendInfoLine: "  Visualization complete!"
endif

####################################################################
# FINAL REPORT
####################################################################

selectObject: output_sound

if show_info
    dur = Get total duration
    n_ch = Get number of channels
    appendInfoLine: ""
    appendInfoLine: "=== Complete ==="
    appendInfoLine: "Output: ", selected$("Sound")
    appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
    appendInfoLine: "Channels: ", n_ch
    appendInfoLine: "Frames processed and reordered: ", numFramesQ
endif

if play_result
    Play
endif