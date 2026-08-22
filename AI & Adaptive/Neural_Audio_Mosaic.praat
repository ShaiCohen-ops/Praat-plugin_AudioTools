# ============================================================
# Praat AudioTools - Neural_Audio_Mosaic.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2026) - Unified time grid, exact duration, honest name
#
# Changelog v0.7 (2026):
#
#   AUDIO CHANGES everywhere: the analysis grid, the rendered grains
#   and the output length were three different things and are now one.
#
#   CRITICAL 1 - the features described a different instant from the
#     grain that got played, by a whole hop. The script read MFCC by
#     FRAME NUMBER (Get value in frame: i) while reading pitch and
#     intensity at a hand-computed time t = (i - 0.5) * hop, and those
#     are not the same instant. Measured on a 1 s source at a 50 ms
#     grain and 25 ms hop: MFCC frame 1 is centred at 0.03750 s, while
#     the script assumed 0.01250 s - a 25 ms error, one full hop and
#     half a grain. The rendered grain's own centre was a third value
#     again (0.02500 s). v0.7 defines ONE grid,
#       centre[i] = grainSec/2 + (i-1)*hop,
#     and queries pitch, intensity, MFCC and the grain extraction all
#     at that time - the MFCC frame index is now derived from the
#     object's own x1 and dx instead of being assumed equal to i.
#
#   CRITICAL 2 - one valid grain was dropped at each end. The count
#     used floor((dur - grain) / hop) without the +1: 37 instead of 38
#     on a 1 s target, and the same omission cost the last usable
#     grain of the source pool.
#
#   CRITICAL 3 - the output ended with a silent hop. outputDur was
#     nTarget * hop + grain, but N grains starting at 0, H, 2H ...
#     only cover (N-1) * H + G. Measured: a 1 s target gave a 0.9750 s
#     buffer whose last grain ended at 0.9500 s, leaving 25 ms of
#     silence that the window-sum division could not fill because the
#     window sum is zero there too. v0.7 renders into a buffer of the
#     target's own length, places a final grain so the coverage
#     reaches the end, and trims to durTarget exactly.
#
#   4 - A global fade at both ends. Dividing by the window sum very
#     nearly CANCELS the Hann taper of the first and last grain -
#     source x Hann / Hann is source - so the output could start or
#     stop at an arbitrary sample value. The internal window is not a
#     substitute for a global fade once you divide by the window sum.
#
#   5 - "Neural" is gone. There is no network, no layer, no weight, no
#     training and no inference anywhere in this script: the search is
#     a weighted Euclidean nearest neighbour over 12 MFCCs, energy and
#     a voiced-aware pitch distance, run either exhaustively or over
#     random probes. It is now Feature-Matched Audio Mosaic, and the
#     progress and panel titles match.
#
#   6 - The stochastic "second best" could be the SAME grain. Probes
#     were drawn with replacement, so one index could be tested twice
#     and become both best_idx and second_best_idx - the right channel
#     then rendered the identical grain. With Search_probes = 1,
#     second_best_idx stayed at its initial value of 1 even though
#     source grain 1 was never examined. Probes are now distinct, and
#     second_best is never allowed to equal best; with a single source
#     grain the script says so and uses it for both channels.
#
#   7 - Random_seed added (0 = unpredictable), with the generator
#     returned to its safe state afterwards.
#
#   8 - Validation: overlap in [0, 0.95], probes >= 2 for stereo
#     stochastic, stereo variation in [0, 1], and a grain size at
#     least as long as the 25 ms MFCC window.
#
#   9 - Silent Source (and silent Target) are rejected rather than
#     producing arbitrary matches and a silent file handed to peak
#     normalisation.
#
#   10 - Naming and documentation:
#     - Normalize_volume renamed Normalize_peak: it scales every
#       result to 0.99 whether or not anything was clipping.
#     - Praat counts selected objects TOP-DOWN in the object list, not
#       in click order, so "#1 = Target" means the higher one in the
#       list. Stated explicitly.
#     - Both inputs are downmixed to mono; the stereo output is
#       synthesised by choosing a different source grain per channel.
#
# Version: 0.9 (2026) - Suite-standard visualization
#
# Changelog v0.9 (2026):
#
#   VISUALIZATION STANDARDIZATION ONLY; feature extraction, weighted
#   nearest-neighbour search, stochastic/exhaustive matching, exact
#   window-sum OLA, end-grain placement and stereo variation are
#   unchanged from v0.8.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, suite-standard title/subtitle, typography,
#     neutral panel backgrounds, summary strip and full-page export.
#   - Preserved the script-specific visual idea: Source waveform ->
#     target/source grain trajectory map -> Mosaic output.
#   - Replaced the dark stats bar with the shared three-line summary and
#     added draw-safe Target/Source names plus search/output details.
#
# Changelog v0.8 (2026):
#
#   1 - The FINAL grain was placed 12 ms from the window it analysed.
#     v0.7 unified the analysis grid but left placement at
#     (i-1)*stepSec. For every regular grain those agree, but the extra
#     end event's analysis centre is clamped to durTarget - grainSec/2,
#     so the two diverge exactly once - at the end of every render.
#     Measured on a 1.013 s target at a 50 ms grain and 25 ms hop:
#       grain 39  analysed 0.9750, placed centre 0.9750, offset 0
#       grain 40  analysed 0.9880, placed centre 1.0000, offset -12 ms
#                 and only 38 ms of its 50 ms survived the trim
#     So v0.7's "ONE grid" claim held for all but the last grain.
#     Placement is now tTime#[i] - grainSec/2 in both the window-sum
#     pass and the render pass, which covers all three uses (the render
#     loop serves both channels). The last grain now starts at
#     durTarget - grainSec and ends exactly on the target edge.
#
#   2 - The RNG is seeded only after every path that can exitScript.
#     v0.7 seeded near the top, so a sample-rate mismatch, a too-short
#     input or a silent Source exited leaving Praat globally
#     predictable. Those exits also leaked the mono working copies,
#     which are now removed on the way out.
#
#   3 - Version strings and one stale comment reference to the old
#     "NEURAL SEARCH" block heading.
#
# Version: 0.6 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Feature-Matched Audio Mosaic - Reconstructs 'Target' using 'Source' grains
#   via feature matching (concatenative synthesis / musaicing).
#
# Changelog v0.6 (2026):
#   - FIX (audible): OLA gain was only correct at Overlap_ratio 0.5.
#     Full-length Hanning grains placed at grain*(1-overlap) sum to
#     a constant ONLY at 50% overlap: the Rhythmic preset (0.25)
#     left deep inter-grain dips, and CreativeLoose/HybridTexture
#     (0.6/0.65) produced a rippling over-overlapped sum. The crude
#     constant 1/(1+overlap) compensation could fix neither. v0.6
#     normalizes by the EXACT window-sum envelope: the bare Hanning
#     window is overlap-added once on the same grid, and each
#     channel is divided by it. Flat unity gain at ANY overlap
#     ratio (the knob becomes a pure grain-density/texture control),
#     output edges recover full level, gain_comp removed.
#     Measured on DC grains (isolating windowing from grain phase):
#     overlap 0.25: 10.7 dB dips -> 0.00002 dB; overlap 0.65:
#     0.26 dB ripple -> flat; overlap 0.5 was v0.5's only correct
#     case and stays flat. Note: phase interference between
#     overlapping grains from different source positions remains --
#     that is the granular texture itself, not a gain artifact.
#   - FIX: unvoiced frames contributed logF0 = 0 to the pitch
#     feature's min/max normalization pool, stretching the range
#     and compressing voiced pitch discrimination (e.g. all-high
#     voices squeezed into the upper half). Feature 13 is now
#     normalized over VOICED frames only (unvoiced values are never
#     read by the voicing-aware distance).
#
# Changelog v0.4:
#   - Fixed preset comparison (number not string)
#   - Fixed Formula object references
#   - Added preset name to output
#
# Changelog v0.5 (2026):
#   - SPEED/PORTABILITY: OLA synthesis Formula replaced object(<id>, t)
#     time-interpolated reads with object[<id>, 1, col - offsetCol]
#     indexed-column reads. The grain and destination Sound share
#     the same sample rate (fs), so time interpolation was wasteful
#     two-sample linear interpolation per output sample (also a mild
#     low-pass filter at frequencies near Nyquist). Indexed reads
#     are direct sample-aligned copies — same math, faster, more
#     portable across Praat versions.
#   - QUALITY: Voiced/unvoiced tracking. v0.4 set logF0=0 for
#     unvoiced frames, which the distance metric then treated as
#     "100 Hz pitch" — indistinguishable from a real 100 Hz voiced
#     frame. Speech inputs with mixed voicing got nonsensical
#     pitch matches as a result. v0.5 tracks tValid_# and sValid_#
#     flags. The pitch term is included in the distance only if
#     BOTH the target and source frames are voiced. A small
#     voicing-mismatch penalty (0.25 * pitch_weight) discourages
#     voiced↔unvoiced cross-matches without forbidding them.
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 2
    exitScript: "Please select exactly TWO Sound objects. (1=Target, 2=Source)"
endif

id1 = selected("Sound", 1)
id2 = selected("Sound", 2)

form Feature-Matched Audio Mosaic v0.9
    comment Top selected Sound = Target, lower one = Source (list order)
    optionmenu Preset: 1
        option Manual
        option Tight Match
        option Creative Loose
        option Rhythmic
        option Spectral Only
        option Pitch Priority
        option Hybrid Texture
    positive Grain_size_ms 50
    real Overlap_ratio 0.5
    optionmenu Search_mode: 1
        option Stochastic (fast)
        option Exhaustive (accurate)
    integer Search_probes 50
    positive Pitch_weight 1.0
    positive Spectral_weight 1.0
    positive Energy_weight 0.5
    boolean Stereo_output 1
    real Stereo_variation 0.3
    integer Random_seed 0
    boolean Normalize_peak 1
    boolean Play_result 1
endform

# Praat numbers selected objects by their position in the object list,
# top to bottom - NOT by the order you clicked them. So "#1 = Target"
# means the Target must sit HIGHER in the list than the Source.
# Both inputs are downmixed to mono; the stereo output is synthesised
# by picking a different source grain for each channel.
# Normalize_peak scales the result to 0.99 whether or not it clipped.
normalize_volume = normalize_peak

# ============================================
# VALIDATION  (v0.7 fix 8)
# ============================================
warnLines$ = ""
if overlap_ratio < 0
    overlap_ratio = 0
    warnLines$ = warnLines$ + "  ! Overlap_ratio < 0 leaves gaps -> 0" + newline$
endif
if overlap_ratio > 0.95
    overlap_ratio = 0.95
    warnLines$ = warnLines$ + "  ! Overlap_ratio >= 1 gives a zero or negative hop -> 0.95" + newline$
endif
if stereo_variation < 0
    stereo_variation = 0
    warnLines$ = warnLines$ + "  ! Stereo_variation < 0 -> 0" + newline$
endif
if stereo_variation > 1
    stereo_variation = 1
    warnLines$ = warnLines$ + "  ! Stereo_variation > 1 -> 1" + newline$
endif
if search_probes < 2
    search_probes = 2
    warnLines$ = warnLines$ + "  ! Search_probes < 2 cannot yield a distinct second" +
        ... " candidate -> 2" + newline$
endif
# The MFCC analysis window is 25 ms; a shorter grain cannot be
# described by it.
if grain_size_ms < 25
    grain_size_ms = 25
    warnLines$ = warnLines$ + "  ! Grain_size_ms below the 25 ms MFCC window -> 25" + newline$
endif



# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Tight Match
    grain_size_ms = 40
    overlap_ratio = 0.5
    search_mode = 2
    pitch_weight = 1.2
    spectral_weight = 1.5
    energy_weight = 0.8
    stereo_variation = 0.15
    presetName$ = "TightMatch"
elsif preset = 3
    # Creative Loose
    grain_size_ms = 80
    overlap_ratio = 0.6
    search_mode = 1
    search_probes = 20
    pitch_weight = 0.3
    spectral_weight = 0.5
    energy_weight = 0.2
    stereo_variation = 0.5
    presetName$ = "CreativeLoose"
elsif preset = 4
    # Rhythmic
    grain_size_ms = 30
    overlap_ratio = 0.25
    search_mode = 1
    search_probes = 80
    pitch_weight = 0.5
    spectral_weight = 1.0
    energy_weight = 1.5
    stereo_variation = 0.25
    presetName$ = "Rhythmic"
elsif preset = 5
    # Spectral Only
    grain_size_ms = 60
    overlap_ratio = 0.5
    search_mode = 2
    pitch_weight = 0.0
    spectral_weight = 2.0
    energy_weight = 0.3
    stereo_variation = 0.3
    presetName$ = "SpectralOnly"
elsif preset = 6
    # Pitch Priority
    grain_size_ms = 50
    overlap_ratio = 0.5
    search_mode = 2
    pitch_weight = 3.0
    spectral_weight = 0.5
    energy_weight = 0.5
    stereo_variation = 0.2
    presetName$ = "PitchPriority"
elsif preset = 7
    # Hybrid Texture
    grain_size_ms = 70
    overlap_ratio = 0.65
    search_mode = 1
    search_probes = 40
    pitch_weight = 1.0
    spectral_weight = 1.0
    energy_weight = 1.0
    stereo_variation = 0.4
    presetName$ = "HybridTexture"
else
    presetName$ = "Manual"
endif

# ============================================
# SETUP
# ============================================

selectObject: id1
targetName$ = selected$("Sound")
durTarget = Get total duration
fsTarget = Get sampling frequency

selectObject: id2
sourceName$ = selected$("Sound")
durSource = Get total duration
fsSource = Get sampling frequency

if fsTarget <> fsSource
    exitScript: "Error: Both sounds must have the same sampling frequency."
endif

fs = fsTarget
grainSec = grain_size_ms / 1000
stepSec = grainSec * (1 - overlap_ratio)

if stepSec < 0.001
    stepSec = 0.001
endif

if durTarget < grainSec or durSource < grainSec
    exitScript: "Sounds are too short for this grain size."
endif

clearinfo
writeInfoLine: "=== Feature-Matched Audio Mosaic v0.9 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target: ", targetName$, " (", fixed$(durTarget, 2), " s)"
appendInfoLine: "Source: ", sourceName$, " (", fixed$(durSource, 2), " s)"
appendInfoLine: "Grain: ", grain_size_ms, " ms | Overlap: ", fixed$(overlap_ratio * 100, 0), "%"
if search_mode = 1
    appendInfoLine: "Search: Stochastic (", search_probes, " probes)"
else
    appendInfoLine: "Search: Exhaustive"
endif
if stereo_output
    appendInfoLine: "Output: Stereo (variation ", fixed$(stereo_variation * 100, 0), "%)"
else
    appendInfoLine: "Output: Mono"
endif
appendInfoLine: ""

# Make mono working copies
selectObject: id1
targetSnd = Convert to mono
Rename: "Work_Target"

selectObject: id2
sourceSnd = Convert to mono

# v0.7 fix 9: silent inputs give zero or undefined MFCCs, no voicing
# and fallback intensity, so every match becomes arbitrary and the
# result is a silent file handed to peak normalisation.
selectObject: targetSnd
tgtPeak = Get absolute extremum: 0, 0, "None"
selectObject: sourceSnd
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak < 1e-6
    removeObject: targetSnd, sourceSnd
    exitScript: "The Source sound is silent (or near-silent); there is nothing to match against."
endif
if tgtPeak < 1e-6
    removeObject: targetSnd, sourceSnd
    exitScript: "The Target sound is silent (or near-silent); there is nothing to reconstruct."
endif

# v0.8: seed only AFTER every path that can exitScript. v0.7 seeded at
# the top, so a sample-rate mismatch, a too-short input or a silent
# Source exited with Praat's generator left globally predictable for
# whatever ran next - and the mono working copies leaked too.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedLabel$ = string$(random_seed)
else
    random_initializeSafelyAndUnpredictably ()
    seedLabel$ = "unpredictable"
endif

appendInfoLine: "Seed: ", seedLabel$
if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
    appendInfoLine: ""
endif
Rename: "Work_Source"

# ============================================
# FEATURE EXTRACTION
# ============================================

appendInfoLine: "Extracting features..."

# v0.7 CRITICAL 2: the +1 that was missing. floor((D-G)/H) gives 37
# full windows on a 1 s target at a 50 ms grain and 25 ms hop; there
# are 38, and the same omission cost the last usable Source grain.
nTarget = floor((durTarget - grainSec) / stepSec) + 1
nSource = floor((durSource - grainSec) / stepSec) + 1

# v0.7 CRITICAL 3: one more Target grain when the full windows stop
# short of the end, so the mosaic actually reaches durTarget instead
# of leaving a silent hop. Its centre is pinned to the last legal
# position rather than running past the source.
if (nTarget - 1) * stepSec + grainSec < durTarget - 1e-9
    nTarget = nTarget + 1
endif

if nTarget < 1
    nTarget = 1
endif
if nSource < 1
    nSource = 1
endif

appendInfoLine: "  Target frames: ", nTarget
appendInfoLine: "  Source frames: ", nSource

nFeatures = 14

# Allocate target feature arrays
for f from 1 to nFeatures
    tFeat_'f'# = zero#(nTarget)
endfor
tTime# = zero#(nTarget)
# v0.5: voicing flag — 1 if frame had a valid pitch, 0 if unvoiced.
# Used by the distance metric to exclude the pitch term for unvoiced
# frames (see the FEATURE-MATCHING SEARCH block below).
tValid# = zero#(nTarget)

# Allocate source feature arrays
for f from 1 to nFeatures
    sFeat_'f'# = zero#(nSource)
endfor
sTime# = zero#(nSource)
sValid# = zero#(nSource)

# Extract TARGET features
selectObject: targetSnd
tMfcc = To MFCC: 12, 0.025, stepSec, 100, 100, 0
selectObject: tMfcc
tMfccN = Get number of frames
selectObject: tMfcc
tMfccT1 = Get time from frame number: 1
if tMfccN > 1
    selectObject: tMfcc
    tMfccT2 = Get time from frame number: 2
    tMfccDx = tMfccT2 - tMfccT1
else
    tMfccDx = stepSec
endif
if tMfccDx <= 0
    tMfccDx = stepSec
endif

selectObject: targetSnd
tPitch = To Pitch: stepSec, 75, 600

selectObject: targetSnd
tIntensity = To Intensity: 75, stepSec, "yes"

for i from 1 to nTarget
    # v0.7 CRITICAL 1: ONE grid. The grain centre is grainSec/2 +
    # (i-1)*hop, and pitch, intensity, MFCC and the extraction all
    # use it. v0.6 read MFCC by frame NUMBER while querying pitch and
    # intensity at (i-0.5)*hop, and those are 25 ms apart at the
    # defaults - MFCC frame 1 is centred at 0.03750 s, not 0.01250 s.
    t = grainSec / 2 + (i - 1) * stepSec
    if t > durTarget - grainSec / 2
        t = durTarget - grainSec / 2
    endif
    if t < grainSec / 2
        t = grainSec / 2
    endif
    tTime#[i] = t

    # MFCC frame index derived from the object's own x1 and dx rather
    # than assumed equal to i
    fIdx = round((t - tMfccT1) / tMfccDx) + 1
    if fIdx < 1
        fIdx = 1
    endif
    if fIdx > tMfccN
        fIdx = tMfccN
    endif

    selectObject: tMfcc
    for c from 1 to 12
        val = Get value in frame: fIdx, c
        if val = undefined
            val = 0
        endif
        tFeat_'c'#[i] = val
    endfor
    
    selectObject: tPitch
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        logF0 = 0
        tValid#[i] = 0
    else
        logF0 = 12 * ln(f0 / 100) / ln(2)
        tValid#[i] = 1
    endif
    tFeat_13#[i] = logF0
    
    selectObject: tIntensity
    energy = Get value at time: t, "cubic"
    if energy = undefined
        energy = 50
    endif
    tFeat_14#[i] = energy
endfor

removeObject: tMfcc, tPitch, tIntensity

# Extract SOURCE features
selectObject: sourceSnd
sMfcc = To MFCC: 12, 0.025, stepSec, 100, 100, 0
selectObject: sMfcc
sMfccN = Get number of frames
selectObject: sMfcc
sMfccT1 = Get time from frame number: 1
if sMfccN > 1
    selectObject: sMfcc
    sMfccT2 = Get time from frame number: 2
    sMfccDx = sMfccT2 - sMfccT1
else
    sMfccDx = stepSec
endif
if sMfccDx <= 0
    sMfccDx = stepSec
endif

selectObject: sourceSnd
sPitch = To Pitch: stepSec, 75, 600

selectObject: sourceSnd
sIntensity = To Intensity: 75, stepSec, "yes"

for i from 1 to nSource
    t = grainSec / 2 + (i - 1) * stepSec
    if t > durSource - grainSec / 2
        t = durSource - grainSec / 2
    endif
    if t < grainSec / 2
        t = grainSec / 2
    endif
    sTime#[i] = t

    fIdx = round((t - sMfccT1) / sMfccDx) + 1
    if fIdx < 1
        fIdx = 1
    endif
    if fIdx > sMfccN
        fIdx = sMfccN
    endif

    selectObject: sMfcc
    for c from 1 to 12
        val = Get value in frame: fIdx, c
        if val = undefined
            val = 0
        endif
        sFeat_'c'#[i] = val
    endfor
    
    selectObject: sPitch
    f0 = Get value at time: t, "Hertz", "Linear"
    if f0 = undefined or f0 <= 0
        logF0 = 0
        sValid#[i] = 0
    else
        logF0 = 12 * ln(f0 / 100) / ln(2)
        sValid#[i] = 1
    endif
    sFeat_13#[i] = logF0
    
    selectObject: sIntensity
    energy = Get value at time: t, "cubic"
    if energy = undefined
        energy = 50
    endif
    sFeat_14#[i] = energy
endfor

removeObject: sMfcc, sPitch, sIntensity

appendInfoLine: "  Features extracted"

# v0.5: report voicing fraction
nTValid = 0
nSValid = 0
for i from 1 to nTarget
    nTValid = nTValid + tValid#[i]
endfor
for i from 1 to nSource
    nSValid = nSValid + sValid#[i]
endfor
appendInfoLine: "  Target voiced: ", nTValid, "/", nTarget,
    ... " (", fixed$(nTValid / nTarget * 100, 0), "%)"
appendInfoLine: "  Source voiced: ", nSValid, "/", nSource,
    ... " (", fixed$(nSValid / nSource * 100, 0), "%)"

# ============================================
# JOINT FEATURE NORMALIZATION
# ============================================

appendInfoLine: "Normalizing features..."

for f from 1 to nFeatures
    minV = 1e9
    maxV = -1e9
    
    # v0.6: feature 13 (pitch) pools min/max over VOICED frames only.
    # Unvoiced frames carry logF0 = 0, which stretched the range and
    # compressed voiced pitch discrimination; the voicing-aware
    # distance never reads unvoiced pitch values anyway.
    for i from 1 to nTarget
        if f <> 13 or tValid#[i] = 1
            v = tFeat_'f'#[i]
            if v < minV
                minV = v
            endif
            if v > maxV
                maxV = v
            endif
        endif
    endfor
    
    for i from 1 to nSource
        if f <> 13 or sValid#[i] = 1
            v = sFeat_'f'#[i]
            if v < minV
                minV = v
            endif
            if v > maxV
                maxV = v
            endif
        endif
    endfor
    
    # No voiced frames at all: leave feature 13 untouched
    if minV > maxV
        minV = 0
        maxV = 1
    endif
    
    range = maxV - minV
    if range < 1e-9
        range = 1
    endif
    
    for i from 1 to nTarget
        tFeat_'f'#[i] = (tFeat_'f'#[i] - minV) / range
    endfor
    
    for i from 1 to nSource
        sFeat_'f'#[i] = (sFeat_'f'#[i] - minV) / range
    endfor
endfor

# ============================================
# FEATURE WEIGHTS
# ============================================

totalWeight = spectral_weight * 12 + pitch_weight + energy_weight
if totalWeight < 0.001
    totalWeight = 1
endif

for c from 1 to 12
    w_'c' = spectral_weight * nFeatures / totalWeight
endfor
w_13 = pitch_weight * nFeatures / totalWeight
w_14 = energy_weight * nFeatures / totalWeight

# v0.7 fix 6: the pool the probe shuffle draws from.
nNoSecond = 0
probeIdx# = zero#(nSource)
for pIdx from 1 to nSource
    probeIdx#[pIdx] = pIdx
endfor

# ============================================
# FEATURE-MATCHING SEARCH
# ============================================

appendInfoLine: "Running nearest-neighbour search..."

matchIdx# = zero#(nTarget)

if stereo_output
    matchIdx_R# = zero#(nTarget)
endif

for i from 1 to nTarget
    best_dist = 1e9
    best_idx = 1
    second_best_dist = 1e9
    # v0.7 fix 6: 0 means "no distinct second candidate found yet",
    # so it can never silently render source grain 1 unexamined.
    second_best_idx = 0
    
    if search_mode = 2
        # Exhaustive
        # v0.5: distance is now split into "always include" (MFCC + energy)
        # and "voicing-aware" (pitch). Pitch term is added only if BOTH
        # frames are voiced. A small voicing-mismatch penalty discourages
        # voiced↔unvoiced cross-matches.
        tValid_i = tValid#[i]
        for j from 1 to nSource
            dist = 0
            # MFCC features 1..12
            for f from 1 to 12
                d = tFeat_'f'#[i] - sFeat_'f'#[j]
                dist += d * d * w_'f'
            endfor
            # Energy (feature 14)
            d14 = tFeat_14#[i] - sFeat_14#[j]
            dist += d14 * d14 * w_14
            # Pitch term — voicing-aware
            sValid_j = sValid#[j]
            if tValid_i = 1 and sValid_j = 1
                d13 = tFeat_13#[i] - sFeat_13#[j]
                dist += d13 * d13 * w_13
            elsif tValid_i <> sValid_j
                # Voicing mismatch penalty (small soft bias)
                dist += w_13 * 0.25
            endif
            
            if dist < best_dist
                second_best_dist = best_dist
                second_best_idx = best_idx
                best_dist = dist
                best_idx = j
            elsif dist < second_best_dist and j <> best_idx
                second_best_dist = dist
                second_best_idx = j
            endif
        endfor
    else
        # Stochastic — same voicing-aware distance as exhaustive
        tValid_i = tValid#[i]
        # v0.7 fix 6: probes WITHOUT replacement. v0.6 drew with
        # replacement, so one index could be tested twice and become
        # both best_idx and second_best_idx - the right channel then
        # rendered the identical grain. A partial Fisher-Yates shuffle
        # over the first nProbes positions guarantees distinct indices
        # at O(nProbes) cost.
        nProbes = search_probes
        if nProbes > nSource
            nProbes = nSource
        endif
        for pp from 1 to nProbes
            rr = randomInteger(pp, nSource)
            tmpv = probeIdx#[pp]
            probeIdx#[pp] = probeIdx#[rr]
            probeIdx#[rr] = tmpv
        endfor
        for probe from 1 to nProbes
            j = probeIdx#[probe]
            
            dist = 0
            for f from 1 to 12
                d = tFeat_'f'#[i] - sFeat_'f'#[j]
                dist += d * d * w_'f'
            endfor
            d14 = tFeat_14#[i] - sFeat_14#[j]
            dist += d14 * d14 * w_14
            sValid_j = sValid#[j]
            if tValid_i = 1 and sValid_j = 1
                d13 = tFeat_13#[i] - sFeat_13#[j]
                dist += d13 * d13 * w_13
            elsif tValid_i <> sValid_j
                dist += w_13 * 0.25
            endif
            
            if dist < best_dist
                second_best_dist = best_dist
                second_best_idx = best_idx
                best_dist = dist
                best_idx = j
            elsif dist < second_best_dist and j <> best_idx
                second_best_dist = dist
                second_best_idx = j
            endif
        endfor
    endif
    
    matchIdx#[i] = best_idx

    # v0.7 fix 6: with only one source grain, or if no DISTINCT runner
    # up was examined, fall back to the best for both channels rather
    # than rendering an unexamined grain. v0.6 left second_best_idx at
    # its initial value of 1, so with Search_probes = 1 the right
    # channel played source grain 1 even though it was never tested.
    if second_best_idx < 1 or second_best_idx = best_idx
        second_best_idx = best_idx
        nNoSecond = nNoSecond + 1
    endif

    if stereo_output
        if randomUniform(0, 1) < stereo_variation
            matchIdx_R#[i] = second_best_idx
        else
            matchIdx_R#[i] = best_idx
        endif
    endif
    
    if i mod 100 = 0
        perc = i / nTarget * 100
        appendInfoLine: "  Matching: ", fixed$(perc, 0), "%"
    endif
endfor

appendInfoLine: "  Search complete"

# ============================================
# OVERLAP-ADD SYNTHESIS
# ============================================

appendInfoLine: "Synthesizing mosaic..."

# v0.7 CRITICAL 3: the buffer is the TARGET's length. v0.6 used
# nTarget * hop + grain, but N grains starting at 0, H, 2H ... only
# reach (N-1)*H + G - measured on a 1 s target, a 0.9750 s buffer whose
# last grain ended at 0.9500 s, so 25 ms of silence that the window-sum
# division could not fill (the window sum is zero there too).
outputDur = (nTarget - 1) * stepSec + grainSec
if outputDur < durTarget
    outputDur = durTarget
endif

# v0.6: exact window-sum envelope for OLA normalization. Overlap-add
# the bare Hanning window (obtained by windowing a constant-1 sound,
# so it matches Praat's Extract-part window exactly) on the same
# placement grid, once, shared by both channels. Dividing each
# channel by this envelope gives flat unity gain at ANY overlap
# ratio -- the old constant 1/(1+overlap) was only ever correct-ish
# at 0.5, dipping at low overlaps and rippling at high ones.
onesSnd = Create Sound from formula: "ones", 1, 0, grainSec, fs, "1"
selectObject: onesSnd
hannWin = Extract part: 0, grainSec, "Hanning", 1, "no"
removeObject: onesSnd
hannIdStr$ = string$(hannWin)

winSum = Create Sound from formula: "winsum", 1, 0, outputDur, fs, "0"
for i from 1 to nTarget
    # v0.8: place the grain where it was ANALYSED. For every regular
    # grain this equals (i-1)*stepSec, but the final event's analysis
    # centre is clamped to durTarget - grainSec/2, so the old formula
    # put it 12 ms away from the window it measured and let the trim
    # eat 12 ms off its end. Measured on a 1.013 s target at a 50 ms
    # grain and 25 ms hop: grain 40 analysed 0.9880 but was placed at
    # centre 1.0000, and only 38 ms of its 50 ms survived. Now the
    # analysis, the selection and the placement share one time.
    destTime = tTime#[i] - grainSec / 2
    if destTime < 0
        destTime = 0
    endif
    offsetCol = round(destTime * fs)
    offsetCol_str$ = string$(offsetCol)
    selectObject: winSum
    Formula (part): destTime, destTime + grainSec, 1, 1,
        ... "self + object[" + hannIdStr$
        ... + ", 1, col - " + offsetCol_str$ + "]"
endfor
removeObject: hannWin
winSumIdStr$ = string$(winSum)

if stereo_output
    n_passes = 2
else
    n_passes = 1
endif

for pass from 1 to n_passes
    if stereo_output
        if pass = 1
            appendInfoLine: "  LEFT channel..."
        else
            appendInfoLine: "  RIGHT channel..."
        endif
    endif
    
    outputSnd = Create Sound from formula: "Output_" + string$(pass), 1, 0, outputDur, fs, "0"
    
    for i from 1 to nTarget
        if pass = 1
            srcIdx = matchIdx#[i]
        else
            srcIdx = matchIdx_R#[i]
        endif
        
        t_src = sTime#[srcIdx]
        t1 = t_src - (grainSec / 2)
        t2 = t_src + (grainSec / 2)
        
        if t1 < 0
            t1 = 0
            t2 = grainSec
        endif
        if t2 > durSource
            t2 = durSource
            t1 = durSource - grainSec
            if t1 < 0
                t1 = 0
            endif
        endif
        
        selectObject: sourceSnd
        grain = Extract part: t1, t2, "Hanning", 1, "no"
        
        # v0.8: same unified placement as the window-sum pass above.
        destTime = tTime#[i] - grainSec / 2
        if destTime < 0
            destTime = 0
        endif
        
        selectObject: grain
        grainDur = Get total duration
        grainIdStr$ = string$(grain)
        
        # v0.5: indexed-column read instead of object(<id>, t) time-
        # interpolated read. Both grain and outputSnd are at fs sample
        # rate, so a sample-aligned copy via indexed cols is correct
        # and faster than time interpolation.
        offsetCol = round(destTime * fs)
        offsetCol_str$ = string$(offsetCol)
        
        selectObject: outputSnd
        Formula (part): destTime, destTime + grainDur, 1, 1,
            ... "self + object[" + grainIdStr$
            ... + ", 1, col - " + offsetCol_str$ + "]"
        
        removeObject: grain
    endfor
    
    # v0.6: normalize by the exact Hann window-sum envelope
    # (replaces the constant 1/(1+overlap) compensation)
    selectObject: outputSnd
    Formula: "self / (object[" + winSumIdStr$ + ", 1, col] + 1e-6)"

    # v0.7 CRITICAL 3: land exactly on the Target duration.
    selectObject: outputSnd
    curDur = Get total duration
    if curDur > durTarget
        selectObject: outputSnd
        trimmedOut = Extract part: 0, durTarget, "rectangular", 1, "no"
        removeObject: outputSnd
        outputSnd = trimmedOut
    endif

    # v0.7 fix 4: a global fade. Dividing by the window sum very nearly
    # CANCELS the Hann taper of the first and last grain - source x
    # Hann / Hann is source - so without this the output can start or
    # stop at an arbitrary sample value.
    selectObject: outputSnd
    fDur = Get total duration
    edgeF = 0.004
    if edgeF > fDur * 0.1
        edgeF = fDur * 0.1
    endif
    if edgeF > 0.0002
        eF$ = fixed$(edgeF, 8)
        selectObject: outputSnd
        Formula: "if x - xmin < " + eF$ + " then self * ((x - xmin) / " + eF$ + ") else self fi"
        selectObject: outputSnd
        Formula: "if xmax - x < " + eF$ + " then self * ((xmax - x) / " + eF$ + ") else self fi"
    endif
    
    if pass = 1
        channel_left = outputSnd
        selectObject: channel_left
        Rename: "Channel_Left"
    else
        channel_right = outputSnd
        selectObject: channel_right
        Rename: "Channel_Right"
    endif
endfor

removeObject: winSum

if nNoSecond > 0
    appendInfoLine: "  ", nNoSecond, "/", nTarget,
        ... " target grains had no distinct second candidate;",
        ... " both channels use the best match there."
endif

# v0.7 fix 7: all random draws are done.
random_initializeSafelyAndUnpredictably ()

# ============================================
# COMBINE OUTPUT
# ============================================

if stereo_output
    appendInfoLine: "Combining to stereo..."
    
    selectObject: channel_left
    dur_L = Get total duration
    selectObject: channel_right
    dur_R = Get total duration
    
    if dur_L < dur_R
        selectObject: channel_right
        tmp = Extract part: 0, dur_L, "rectangular", 1, "no"
        removeObject: channel_right
        channel_right = tmp
    elsif dur_R < dur_L
        selectObject: channel_left
        tmp = Extract part: 0, dur_R, "rectangular", 1, "no"
        removeObject: channel_left
        channel_left = tmp
    endif
    
    selectObject: channel_left
    plusObject: channel_right
    finalOut = Combine to stereo
    Rename: targetName$ + "_Mosaic_" + presetName$
    
    removeObject: channel_left, channel_right
else
    finalOut = channel_left
    Rename: targetName$ + "_Mosaic_" + presetName$
endif

if normalize_volume
    selectObject: finalOut
    Scale peak: 0.99
endif

# ============================================================
# VISUALIZATION
# ============================================================

selectObject: finalOut
vizOutDur = Get total duration
vizOutPeak = Get absolute extremum: 0, 0, "None"
vizOutChannels = Get number of channels

if search_mode = 1
    searchDesc$ = "stochastic, " + string$(search_probes) + " probes"
else
    searchDesc$ = "exhaustive"
endif

if stereo_output
    outputDesc$ = "stereo variation " + fixed$(stereo_variation, 2)
else
    outputDesc$ = "mono"
endif

targetVizName$ = replace$(targetName$, "_", "\_ ", 0)
sourceVizName$ = replace$(sourceName$, "_", "\_ ", 0)

pageHeight = 7.15
Erase all
Line width: 1
Colour: "Black"
Solid line
Select outer viewport: 0, 8, 0, pageHeight

# === Header ===
Select outer viewport: 0, 8, 0, 0.52
Select inner viewport: 0.60, 7.70, 0.02, 0.50
Axes: 0, 1, 0, 1
Font size: 12
Colour: "Black"
Text: 0.5, "centre", 0.68, "half", "##Feature-Matched Audio Mosaic v0.9##"
Font size: 7
Colour: "{0.35, 0.35, 0.50}"
Text: 0.5, "centre", 0.22, "half", "Target " + targetVizName$ + " | Source " + sourceVizName$ + " | " + presetName$ + " | " + searchDesc$

# === Source waveform ===
Select outer viewport: 0, 8, 0.68, 1.60
Select inner viewport: 0.60, 7.70, 0.82, 1.42
selectObject: id2
Colour: "{0.55, 0.55, 0.55}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Source"
Text top: "no", "Source Corpus | " + sourceVizName$ + " | " + fixed$(durSource, 2) + " s"

# === Target -> source grain trajectory map ===
Select outer viewport: 0, 8, 1.82, 4.56
Select inner viewport: 0.60, 7.70, 2.08, 4.32
Axes: 0, durTarget, 0, durSource
Paint rectangle: "{0.97, 0.97, 0.97}", 0, durTarget, 0, durSource

# Connecting trajectory.
Colour: "{0.80, 0.80, 0.80}"
Line width: 1
for g from 2 to nTarget
    x1 = tTime#[g-1]
    y1 = sTime#[matchIdx#[g-1]]
    x2 = tTime#[g]
    y2 = sTime#[matchIdx#[g]]
    Draw line: x1, y1, x2, y2
endfor

# Mapping points; colour encodes source position.
for g from 1 to nTarget
    x_pos = tTime#[g]
    src_idx = matchIdx#[g]
    y_pos = sTime#[src_idx]

    if durSource > 0
        pos_ratio = y_pos / durSource
    else
        pos_ratio = 0
    endif
    if pos_ratio < 0
        pos_ratio = 0
    endif
    if pos_ratio > 1
        pos_ratio = 1
    endif

    cR = 0.75 - 0.45 * pos_ratio
    cG = 0.30 + 0.30 * pos_ratio
    cB = 0.60 + 0.20 * pos_ratio
    color$ = "{" + fixed$(cR, 3) + ", " + fixed$(cG, 3) + ", " + fixed$(cB, 3) + "}"

    Paint circle (mm): color$, x_pos, y_pos, 1.35
    Paint circle (mm): "White", x_pos, y_pos, 0.40
endfor

Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Source time (s)"
Text bottom: "no", "Target time (s)"
Text top: "no", "Grain Reconstruction Map | each point: target grain -> matched source grain"

# === Mosaic output waveform ===
Select outer viewport: 0, 8, 4.78, 5.84
Select inner viewport: 0.60, 7.70, 4.94, 5.64
selectObject: finalOut
Colour: "{0.25, 0.45, 0.75}"
Draw: 0, 0, 0, 0, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Mosaic"
Text bottom: "no", "Time (s)"
Text top: "no", "Reconstructed Target | " + fixed$(vizOutDur, 2) + " s | " + string$(vizOutChannels) + " ch | peak " + fixed$(vizOutPeak, 3)

# === Summary strip ===
Select outer viewport: 0, 8, 6.05, 7.10
Select inner viewport: 0.60, 7.70, 6.13, 7.02
Axes: 0, 1, 0, 1
Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

Font size: 6
Colour: "{0.25, 0.25, 0.35}"
summary1$ = "##Material##  target " + fixed$(durTarget, 2) + " s | source " + fixed$(durSource, 2) + " s | grain " + fixed$(grain_size_ms, 1) + " ms | overlap " + fixed$(100 * overlap_ratio, 0) + "\% | " + string$(nTarget) + " target grains"
summary2$ = "##Matching##  " + searchDesc$ + " | spectral " + fixed$(spectral_weight, 2) + " | pitch " + fixed$(pitch_weight, 2) + " | energy " + fixed$(energy_weight, 2) + " | exact target/source analysis grid"
summary3$ = "##Output##  " + outputDesc$ + " | no-distinct-second " + string$(nNoSecond) + "/" + string$(nTarget) + " | exact window-sum OLA | normalize peak " + string$(normalize_peak) + " | " + fixed$(vizOutDur, 2) + " s"
Text: 0.02, "left", 0.78, "half", summary1$
Text: 0.02, "left", 0.50, "half", summary2$
Text: 0.02, "left", 0.22, "half", summary3$

Colour: "Black"
Draw inner box

# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line

# ============================================
# CLEANUP
# ============================================

removeObject: targetSnd, sourceSnd

selectObject: id1
plusObject: id2
plusObject: finalOut

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
selectObject: finalOut
n_ch = Get number of channels
out_dur = Get total duration
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(out_dur, 2), " s"
appendInfoLine: "Channels: ", n_ch

if play_result
    appendInfoLine: "Playing..."
    selectObject: finalOut
    Play
endif

selectObject: finalOut