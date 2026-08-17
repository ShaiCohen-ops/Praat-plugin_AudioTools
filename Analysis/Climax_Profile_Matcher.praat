# ============================================================
# Praat AudioTools - Climax_Profile_Matcher.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Climax Profile Matcher - detects high-energy / high-register /
#   bright / harmonic regions in a Source, measures their acoustic
#   profile, then transfers selected GLOBAL characteristics to a
#   Target: RMS level, spectral balance, and harmonicity colour.
#
#   IMPORTANT: this is profile-guided global matching, not temporal
#   envelope cloning. Pitch and formants are measured as diagnostics
#   but are not transformed (to avoid formant/pitch-structure damage).
#
#   Pipeline:
#   1. Frame-by-frame Source analysis: intensity, pitch, brightness, HNR
#   2. Detect climax regions using robust thresholds and duration
#   3. Measure climax RMS level, spectral centroid/LTAS shape, HNR
#      plus diagnostic pitch/formants
#   4. Analyze Target with the same measurements
#   5. Transfer global level, spectral tilt/LTAS shape, harmonicity colour
#   6. Measure the actual output and visualize requested vs achieved change
#
#   Output: one new Sound object named
#   "Target_matched_to_Source_Climax"
#
# Category: AI & Adaptive
#
#
# Changelog v1.3 (2026):
#   - PROMISE FIX: documents the real operation: global profile transfer,
#     not intensity-envelope cloning or pitch/formant transfer.
#   - FIX: LTAS EQ now preserves the SIGN of the selected spectral-shape
#     delta. v1.2 used abs(delta) and therefore always BOOSTED, even when
#     the Source climax required a cut.
#   - FIX: LTAS matching is mean-removed before EQ, so loudness differences
#     are not mistaken for timbral EQ differences.
#   - FIX: level transfer is now a direct dB gain on every channel, preserving
#     stereo balance and matching the representative analysis channel.
#   - FIX: Source-climax F1/F2/F3 and HNR averages use their own valid-frame
#     counts instead of dividing sparse measurements by all climax frames.
#   - FIX: Pitch upper-percent threshold is now an actual voiced-pitch
#     percentile rather than a linear fraction of min..max range.
#   - FIX: undefined HNR frames no longer become 0 dB and bias climax scores.
#   - STEREO: analysis uses the strongest RMS channel rather than phase-
#     cancelling mono fold-down; processing still preserves every channel.
#   - FORM: removed the unused Processing_chunk_s / Crossfade_ms controls.
#   - VIZ: AudioTools 2x2 house layout; shows detection law, requested vs
#     achieved profile transfer, mean-removed LTAS proof, and target/output
#     waveforms on the same scale.
# Changelog v1.2 (2026):
#   - FIX (critical): the intensity transfer -- the headline
#     feature of a climax matcher -- was destroyed before output.
#     Step 6A's Scale intensity ran FIRST, then 6C/6D/6E each
#     ended with Scale peak 0.99 and the final output did too, so
#     the result always peaked at 0.99 regardless of
#     Intensity_transfer. The intensity match now runs LAST, with
#     a headroom-aware clamp: if the blended level would push the
#     peak past 0.99 the output is limited and the shortfall
#     reported, otherwise the level is exact.
#   - FIX: the v1.1 wet/dry blends hardcoded channel 1
#     (object[id, 1, col]) -- on STEREO targets the right channel
#     was blended with the LEFT channel's filtered signal, in all
#     four sites (tilt x2, EQ add, harmonicity). Now object[id,
#     row, col].
#   - FIX: with zero detected climaxes the script printed "output
#     will be unmodified" but then ran every transform against an
#     all-zero profile: deltaIntensity = -tgtAvg, and the
#     intensity stage scaled the output toward silence. The
#     transforms are now actually skipped.
#   - FIX: info header erased itself (repeated writeInfoLine).
#   - FORM: Processing_chunk_s and Crossfade_ms were never read
#     by any code path -- marked "(reserved)" pending a chunked
#     long-file mode; values are accepted and ignored.
#   - VIZ: title strip uses an explicit inner viewport (the
#     outer-only form compresses the mapping via font margins and
#     collides the two text lines).
#
# Changelog v1.1 (2026):
#   - FIX (critical): Four Formula sites used the
#     "Sound_'name$'(x)" syntax to read time-interpolated
#     samples from a filtered band Sound. This is name-based
#     resolution at parse time and is fragile across Praat
#     versions and Sound names containing unusual characters.
#     All four sites collapsed into single-Formula wet/dry
#     blends using "object[<id>, 1, col]" indexed reads. Each
#     fix replaces three Formula calls with one — same math,
#     faster, no name lookup.
#   - SPEED: Climax-LTAS extraction was Concatenate-in-loop
#     (O(n^2)). Now uses a pre-allocated buffer + Formula (part)
#     writes. Significant on Sources with many short climaxes.
#   - PORTABILITY: findPercentile procedure used the loop-var
#     mutation pattern (.b = .nBins + 1) to break early. Replaced
#     with a "found" flag for portability across Praat versions.
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly TWO Sound objects." + newline$ + "Sound 1 = Source, Sound 2 = Target."
endif

sourceSound = selected("Sound", 1)
targetSound = selected("Sound", 2)
sourceName$ = selected$("Sound", 1)
targetName$ = selected$("Sound", 2)

form Climax Profile Matcher v1.3
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Subtle Match (gentle transfer)
        option Full Transfer (strong matching)
        option Spectral Focus (tilt + EQ only)
        option Broadcast Match (loudness + brightness)
    comment === Analysis ===
    positive Frame_step_ms 15
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    positive Max_formant_Hz 5500
    comment === Climax Detection Thresholds ===
    positive Intensity_percentile 87
    positive Pitch_upper_percent 25
    real Brightness_threshold 0.6
    real Harmonicity_threshold 0.5
    positive Min_climax_duration_ms 200
    comment === Transfer Weights (0..1) ===
    real Intensity_transfer 0.8
    real Spectral_tilt_transfer 0.6
    real Eq_transfer 0.5
    real Harmonicity_transfer 0.3
    comment (heuristic periodic/noisy colour, not exact HNR matching)
    comment === Diagnostics ===
    comment (Pitch/formants are measured, not transformed)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_output 1
endform

# ============================================================
# Apply Presets
# ============================================================

if preset = 2
    # Subtle Match
    intensity_transfer = 0.4
    spectral_tilt_transfer = 0.3
    eq_transfer = 0.25
    harmonicity_transfer = 0.15
    presetName$ = "SubtleMatch"
elsif preset = 3
    # Full Transfer
    intensity_transfer = 0.9
    spectral_tilt_transfer = 0.8
    eq_transfer = 0.7
    harmonicity_transfer = 0.5
    presetName$ = "FullTransfer"
elsif preset = 4
    # Spectral Focus
    intensity_transfer = 0.2
    spectral_tilt_transfer = 0.9
    eq_transfer = 0.85
    harmonicity_transfer = 0.4
    presetName$ = "SpectralFocus"
elsif preset = 5
    # Broadcast Match
    intensity_transfer = 0.9
    spectral_tilt_transfer = 0.7
    eq_transfer = 0.6
    harmonicity_transfer = 0.3
    presetName$ = "BroadcastMatch"
else
    presetName$ = "Custom"
endif

# Clamp weights
# Clamp weights
if intensity_transfer > 1
    intensity_transfer = 1
elsif intensity_transfer < 0
    intensity_transfer = 0
endif

if spectral_tilt_transfer > 1
    spectral_tilt_transfer = 1
elsif spectral_tilt_transfer < 0
    spectral_tilt_transfer = 0
endif

if eq_transfer > 1
    eq_transfer = 1
elsif eq_transfer < 0
    eq_transfer = 0
endif

if harmonicity_transfer > 1
    harmonicity_transfer = 1
elsif harmonicity_transfer < 0
    harmonicity_transfer = 0
endif

# Clamp analysis thresholds to meaningful ranges.
intensity_percentile = max(1, min(99, intensity_percentile))
pitch_upper_percent = max(1, min(100, pitch_upper_percent))
brightness_threshold = max(0, min(1, brightness_threshold))
harmonicity_threshold = max(0, min(1, harmonicity_threshold))

# ============================================================
# Global Parameters
# ============================================================

frameStep = frame_step_ms / 1000
minClimaxDur = min_climax_duration_ms / 1000

selectObject: sourceSound
srcDuration = Get total duration
srcChannels = Get number of channels
srcSR = Get sampling frequency

selectObject: targetSound
tgtDuration = Get total duration
tgtChannels = Get number of channels
tgtSR = Get sampling frequency

clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  Climax Profile Matcher v1.3"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Source: ", sourceName$, " (", fixed$(srcDuration, 2), " s, ", srcSR, " Hz, ", srcChannels, " ch)"
appendInfoLine: "Target: ", targetName$, " (", fixed$(tgtDuration, 2), " s, ", tgtSR, " Hz, ", tgtChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# Prepare representative analysis channels
# ============================================================
# Preserve multichannel processing, but avoid phase-cancelling fold-down
# during analysis. Choose the strongest RMS channel once for Source/Target.

selectObject: sourceSound
if srcChannels > 1
    srcBestChannel = 1
    srcBestRMS = -1
    for ch from 1 to srcChannels
        selectObject: sourceSound
        Extract one channel: ch
        tmpCh = selected("Sound")
        rms = Get root-mean-square: 0, 0
        if rms > srcBestRMS
            srcBestRMS = rms
            srcBestChannel = ch
        endif
        removeObject: tmpCh
    endfor
    selectObject: sourceSound
    Extract one channel: srcBestChannel
    srcMono = selected("Sound")
    Rename: "src_analysis"
else
    srcBestChannel = 1
    srcMono = Copy: "src_analysis"
endif

selectObject: targetSound
if tgtChannels > 1
    tgtBestChannel = 1
    tgtBestRMS = -1
    for ch from 1 to tgtChannels
        selectObject: targetSound
        Extract one channel: ch
        tmpCh = selected("Sound")
        rms = Get root-mean-square: 0, 0
        if rms > tgtBestRMS
            tgtBestRMS = rms
            tgtBestChannel = ch
        endif
        removeObject: tmpCh
    endfor
    selectObject: targetSound
    Extract one channel: tgtBestChannel
    tgtMono = selected("Sound")
    Rename: "tgt_analysis"
else
    tgtBestChannel = 1
    tgtMono = Copy: "tgt_analysis"
endif

selectObject: srcMono
srcAnalysisRMS = Get root-mean-square: 0, 0
sourceSilent = srcAnalysisRMS < 1e-10
appendInfoLine: "Analysis channels: Source ch ", srcBestChannel, " | Target ch ", tgtBestChannel
appendInfoLine: ""

# ============================================================
# STEP 1: ANALYZE SOURCE (frame-by-frame)
# ============================================================
appendInfoLine: "[1/7] Analyzing Source..."

srcNumFrames = floor((srcDuration - frameStep) / frameStep)
if srcNumFrames < 10
    exitScript: "Source too short for analysis."
endif

# --- Create analysis objects ---
selectObject: srcMono
srcIntensityObj = To Intensity: 70, frameStep, "yes"

selectObject: srcMono
srcPitchObj = To Pitch: frameStep, pitch_floor_Hz, pitch_ceiling_Hz

selectObject: srcMono
srcHarmonicityObj = To Harmonicity (cc): frameStep, pitch_floor_Hz, 0.1, 1.0

srcFormantMaxHz = min(max_formant_Hz, srcSR * 0.48)
selectObject: srcMono
srcFormantObj = To Formant (burg): frameStep, 5, srcFormantMaxHz, 0.025, 50

srcSpecMaxHz = min(8000, srcSR * 0.48)
selectObject: srcMono
srcSpectrogramObj = To Spectrogram: 0.025, srcSpecMaxHz, frameStep, 20, "Gaussian"

# --- Extract features per frame ---
srcTime# = zero# (srcNumFrames)
srcIntensity# = zero# (srcNumFrames)
srcPitch# = zero# (srcNumFrames)
srcHNR# = zero# (srcNumFrames)
srcCentroid# = zero# (srcNumFrames)
srcF1# = zero# (srcNumFrames)
srcF2# = zero# (srcNumFrames)
srcF3# = zero# (srcNumFrames)

for i from 1 to srcNumFrames
    t = (i - 0.5) * frameStep
    if t > srcDuration
        t = srcDuration - 0.001
    endif
    srcTime#[i] = t
    
    # Intensity
    selectObject: srcIntensityObj
    val = Get value at time: t, "Cubic"
    srcIntensity#[i] = if val <> undefined then val else 0 fi
    
    # Pitch
    selectObject: srcPitchObj
    p = Get value at time: t, "Hertz", "Linear"
    srcPitch#[i] = if p <> undefined then p else 0 fi
    
    # Harmonicity
    selectObject: srcHarmonicityObj
    h = Get value at time: t, "Cubic"
    srcHNR#[i] = if h <> undefined then h else -200 fi
    
    # Formants
    selectObject: srcFormantObj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    srcF1#[i] = if f1 <> undefined then f1 else 0 fi
    srcF2#[i] = if f2 <> undefined then f2 else 0 fi
    srcF3#[i] = if f3 <> undefined then f3 else 0 fi
    
    # Spectral centroid (from spectrogram)
    selectObject: srcSpectrogramObj
    totalPower = 0
    weightedSum = 0
    freq = 100
    while freq <= srcSpecMaxHz
        pw = Get power at: t, freq
        if pw <> undefined and pw > 0
            totalPower = totalPower + pw
            weightedSum = weightedSum + freq * pw
        endif
        freq = freq + 200
    endwhile
    if totalPower > 0
        srcCentroid#[i] = weightedSum / totalPower
    else
        srcCentroid#[i] = 1000
    endif
endfor

appendInfoLine: "  Extracted ", srcNumFrames, " frames"

# ============================================================
# STEP 2: DETECT CLIMAX REGIONS
# ============================================================
appendInfoLine: "[2/7] Detecting climax regions..."

# --- Compute percentiles for thresholding ---

# Sort intensity values to find percentile
# (Use histogram-based approach for efficiency with long files)
procedure findPercentile: .values#, .n, .pct, .result
    # Find min/max
    .min = .values#[1]
    .max = .values#[1]
    for .i from 2 to .n
        if .values#[.i] > 0
            if .values#[.i] < .min or .min = 0
                .min = .values#[.i]
            endif
            if .values#[.i] > .max
                .max = .values#[.i]
            endif
        endif
    endfor
    .range = .max - .min
    if .range < 0.001
        .result = .min
    else
        # Histogram with 200 bins
        .nBins = 200
        for .b from 1 to .nBins
            histBin_'.b' = 0
        endfor
        .nValid = 0
        for .i from 1 to .n
            if .values#[.i] > 0
                .bin = floor((.values#[.i] - .min) / .range * (.nBins - 1)) + 1
                .bin = max(1, min(.nBins, .bin))
                histBin_'.bin' = histBin_'.bin' + 1
                .nValid = .nValid + 1
            endif
        endfor
        
        .target = floor(.nValid * .pct / 100)
        .cumul = 0
        .result = .max
        # v1.1: replaced ".b = .nBins + 1" loop-var mutation early-break
        # with the standard "found" flag pattern for portability.
        .found = 0
        for .b from 1 to .nBins
            if .found = 0
                .cumul = .cumul + histBin_'.b'
                if .cumul >= .target
                    .result = .min + (.b - 0.5) / .nBins * .range
                    .found = 1
                endif
            endif
        endfor
    endif
endproc

# Intensity threshold
@findPercentile: srcIntensity#, srcNumFrames, intensity_percentile, 0
intThreshold = findPercentile.result
appendInfoLine: "  Intensity threshold (P", intensity_percentile, "): ", fixed$(intThreshold, 1), " dB"

# Pitch threshold: TRUE upper-N-percent voiced-pitch percentile
pitchMin = 9999
pitchMax = 0
nVoiced = 0
for i from 1 to srcNumFrames
    if srcPitch#[i] > 0
        nVoiced = nVoiced + 1
        if srcPitch#[i] < pitchMin
            pitchMin = srcPitch#[i]
        endif
        if srcPitch#[i] > pitchMax
            pitchMax = srcPitch#[i]
        endif
    endif
endfor
if nVoiced > 0
    pitchPct = max(0, min(100, 100 - pitch_upper_percent))
    @findPercentile: srcPitch#, srcNumFrames, pitchPct, 0
    pitchThreshold = findPercentile.result
else
    pitchMin = 0
    pitchMax = 0
    pitchThreshold = 1e30
endif
appendInfoLine: "  Voiced pitch: ", fixed$(pitchMin, 0), " - ", fixed$(pitchMax, 0), " Hz | top ", fixed$(pitch_upper_percent, 0), "% threshold: ", fixed$(pitchThreshold, 0), " Hz"

# Normalize centroid and HNR for thresholding
centroidMin = 99999
centroidMax = 0
hnrMin = 99999
hnrMax = 0
for i from 1 to srcNumFrames
    if srcCentroid#[i] > centroidMax
        centroidMax = srcCentroid#[i]
    endif
    if srcCentroid#[i] < centroidMin
        centroidMin = srcCentroid#[i]
    endif
    if srcHNR#[i] > -199
        if srcHNR#[i] > hnrMax
            hnrMax = srcHNR#[i]
        endif
        if srcHNR#[i] < hnrMin
            hnrMin = srcHNR#[i]
        endif
    endif
endfor
centroidRange = centroidMax - centroidMin + 0.001
if hnrMin = 99999 or hnrMax <= hnrMin
    hnrMin = -20
    hnrMax = 20
endif
hnrRange = hnrMax - hnrMin + 0.001

# --- Scan for climax frames ---
# A frame is "climax-eligible" if it meets multiple criteria
climaxScore# = zero# (srcNumFrames)

for i from 1 to srcNumFrames
    score = 0
    
    # Intensity above percentile
    if srcIntensity#[i] >= intThreshold
        score = score + 1
    endif
    
    # Pitch in upper range (only if voiced)
    if srcPitch#[i] >= pitchThreshold
        score = score + 1
    endif
    
    # Brightness (normalized centroid above threshold)
    normCent = (srcCentroid#[i] - centroidMin) / centroidRange
    if normCent >= brightness_threshold
        score = score + 1
    endif
    
    # Harmonicity above threshold (normalized; only when HNR is defined)
    if srcHNR#[i] > -199
        normHNR = (srcHNR#[i] - hnrMin) / hnrRange
        if normHNR >= harmonicity_threshold
            score = score + 1
        endif
    endif
    
    climaxScore#[i] = score
endfor

# --- Segment climax regions (need >= 3 of 4 criteria met) ---
minClimaxFrames = max(1, floor(minClimaxDur / frameStep))
climaxMinScore = 3

numClimax = 0
inClimax = 0
climaxStart = 0

for i from 1 to srcNumFrames
    if climaxScore#[i] >= climaxMinScore
        if inClimax = 0
            climaxStart = i
            inClimax = 1
        endif
    else
        if inClimax = 1
            climaxLen = i - climaxStart
            if climaxLen >= minClimaxFrames
                numClimax = numClimax + 1
                clxStartFrame_'numClimax' = climaxStart
                clxEndFrame_'numClimax' = i - 1
                clxStartTime_'numClimax' = max(0, srcTime#[climaxStart] - frameStep / 2)
                clxEndTime_'numClimax' = min(srcDuration, srcTime#[i - 1] + frameStep / 2)
            endif
            inClimax = 0
        endif
    endif
endfor
# Final segment
if inClimax = 1
    climaxLen = srcNumFrames - climaxStart + 1
    if climaxLen >= minClimaxFrames
        numClimax = numClimax + 1
        clxStartFrame_'numClimax' = climaxStart
        clxEndFrame_'numClimax' = srcNumFrames
        clxStartTime_'numClimax' = max(0, srcTime#[climaxStart] - frameStep / 2)
        clxEndTime_'numClimax' = min(srcDuration, srcTime#[srcNumFrames] + frameStep / 2)
    endif
endif

appendInfoLine: "  Detected ", numClimax, " climax regions:"
for c from 1 to numClimax
    dur_c = clxEndTime_'c' - clxStartTime_'c'
    appendInfoLine: "    Climax ", c, ": ", fixed$(clxStartTime_'c', 3), " - ", fixed$(clxEndTime_'c', 3), " s (", fixed$(dur_c, 3), " s)"
endfor

# Fallback: if no climaxes found, use top 10% intensity frames
if numClimax = 0 and not sourceSilent
    appendInfoLine: "  WARNING: No climaxes detected. Using top-intensity fallback."
    @findPercentile: srcIntensity#, srcNumFrames, 90, 0
    fallbackThreshold = findPercentile.result
    
    inClimax = 0
    for i from 1 to srcNumFrames
        if srcIntensity#[i] >= fallbackThreshold
            if inClimax = 0
                climaxStart = i
                inClimax = 1
            endif
        else
            if inClimax = 1
                climaxLen = i - climaxStart
                if climaxLen >= minClimaxFrames
                    numClimax = numClimax + 1
                    clxStartFrame_'numClimax' = climaxStart
                    clxEndFrame_'numClimax' = i - 1
                    clxStartTime_'numClimax' = max(0, srcTime#[climaxStart] - frameStep / 2)
                    clxEndTime_'numClimax' = min(srcDuration, srcTime#[i - 1] + frameStep / 2)
                endif
                inClimax = 0
            endif
        endif
    endfor
    if inClimax = 1
        climaxLen = srcNumFrames - climaxStart + 1
        if climaxLen >= minClimaxFrames
            numClimax = numClimax + 1
            clxStartFrame_'numClimax' = climaxStart
            clxEndFrame_'numClimax' = srcNumFrames
            clxStartTime_'numClimax' = max(0, srcTime#[climaxStart] - frameStep / 2)
            clxEndTime_'numClimax' = min(srcDuration, srcTime#[srcNumFrames] + frameStep / 2)
        endif
    endif
    appendInfoLine: "  Fallback found ", numClimax, " regions"
endif

if sourceSilent
    numClimax = 0
    appendInfoLine: "  Source is digital silence: no climax profile can be measured."
endif
if numClimax = 0
    appendInfoLine: "  No usable climax regions found — output will be unmodified."
endif

# ============================================================
# STEP 3: COMPUTE CLIMAX ACOUSTIC PROFILE
# ============================================================
appendInfoLine: ""
appendInfoLine: "[3/7] Computing climax profile..."

clxAvgIntensity = 0
clxAvgPitch = 0
clxPitchMin = 9999
clxPitchMax = 0
clxAvgCentroid = 0
clxAvgHNR = 0
clxAvgF1 = 0
clxAvgF2 = 0
clxAvgF3 = 0
clxTotalFrames = 0
clxHNRCount = 0
clxF1Count = 0
clxF2Count = 0
clxF3Count = 0

for c from 1 to numClimax
    sf = clxStartFrame_'c'
    ef = clxEndFrame_'c'
    for i from sf to ef
        clxTotalFrames = clxTotalFrames + 1
        clxAvgIntensity = clxAvgIntensity + srcIntensity#[i]
        clxAvgCentroid = clxAvgCentroid + srcCentroid#[i]
        if srcHNR#[i] > -199
            clxAvgHNR = clxAvgHNR + srcHNR#[i]
            clxHNRCount = clxHNRCount + 1
        endif
        
        if srcPitch#[i] > 0
            clxAvgPitch = clxAvgPitch + srcPitch#[i]
            if srcPitch#[i] < clxPitchMin
                clxPitchMin = srcPitch#[i]
            endif
            if srcPitch#[i] > clxPitchMax
                clxPitchMax = srcPitch#[i]
            endif
        endif
        
        if srcF1#[i] > 0
            clxAvgF1 = clxAvgF1 + srcF1#[i]
            clxF1Count = clxF1Count + 1
        endif
        if srcF2#[i] > 0
            clxAvgF2 = clxAvgF2 + srcF2#[i]
            clxF2Count = clxF2Count + 1
        endif
        if srcF3#[i] > 0
            clxAvgF3 = clxAvgF3 + srcF3#[i]
            clxF3Count = clxF3Count + 1
        endif
    endfor
endfor

if clxTotalFrames > 0
    clxAvgIntensity = clxAvgIntensity / clxTotalFrames
    clxAvgCentroid = clxAvgCentroid / clxTotalFrames
    clxAvgHNR = if clxHNRCount > 0 then clxAvgHNR / clxHNRCount else 0 fi
    clxAvgF1 = if clxF1Count > 0 then clxAvgF1 / clxF1Count else 0 fi
    clxAvgF2 = if clxF2Count > 0 then clxAvgF2 / clxF2Count else 0 fi
    clxAvgF3 = if clxF3Count > 0 then clxAvgF3 / clxF3Count else 0 fi
endif

# Count voiced climax frames for pitch average
clxVoicedCount = 0
for c from 1 to numClimax
    sf = clxStartFrame_'c'
    ef = clxEndFrame_'c'
    for i from sf to ef
        if srcPitch#[i] > 0
            clxVoicedCount = clxVoicedCount + 1
        endif
    endfor
endfor
if clxVoicedCount > 0
    clxAvgPitch = clxAvgPitch / clxVoicedCount
endif

clxPitchRange = clxPitchMax - clxPitchMin
if clxPitchMin = 9999
    clxPitchMin = 0
    clxPitchRange = 0
endif

# --- Compute Source climax LTAS ---
# v1.1: Pre-allocated buffer + Formula (part) writes instead of
# Concatenate-in-loop. v1.0's Concatenate per iteration rebuilt the
# entire growing buffer (O(n^2)). For Sources with many short climaxes
# this becomes the dominant cost. Now linear.
if numClimax > 0
    # Pass 1: compute total climax duration to pre-allocate.
    totalClxDur = 0
    for c from 1 to numClimax
        totalClxDur = totalClxDur + (clxEndTime_'c' - clxStartTime_'c')
    endfor

    # Pre-allocate destination buffer.
    clxConcat = Create Sound from formula: "clx_concat",
        ... 1, 0, totalClxDur, srcSR, "0"

    # Pass 2: extract each climax part and write into the buffer
    # at its running offset using indexed-column reads.
    writePos = 0
    for c from 1 to numClimax
        selectObject: srcMono
        Extract part: clxStartTime_'c', clxEndTime_'c',
            ... "rectangular", 1, "no"
        clxPart = selected("Sound")
        partDur = Get total duration

        # The extract has xmin=0, sr=srcSR. The destination buffer
        # also has xmin=0, sr=srcSR. So writing destination col k
        # is reading part col (k - offset) where offset = floor(writePos*sr).
        partID_str$ = string$(clxPart)
        offsetCol = round(writePos * srcSR)
        offsetCol_str$ = string$(offsetCol)

        selectObject: clxConcat
        Formula (part): writePos, writePos + partDur, 1, 1,
            ... "object[" + partID_str$
            ... + ", 1, col - " + offsetCol_str$ + "]"

        removeObject: clxPart
        writePos = writePos + partDur
    endfor

    selectObject: clxConcat
    clxLevel_dB = Get intensity (dB)
    clxSpecForCOG = To Spectrum: "yes"
    clxCOG_Hz = Get centre of gravity: 2
    removeObject: clxSpecForCOG
    selectObject: clxConcat
    srcClimaxLTAS = To Ltas: 100
    removeObject: clxConcat
else
    # No usable climax profile: diagnostics use entire source, transforms skip later.
    selectObject: srcMono
    clxLevel_dB = Get intensity (dB)
    clxSpecForCOG = To Spectrum: "yes"
    clxCOG_Hz = Get centre of gravity: 2
    removeObject: clxSpecForCOG
    selectObject: srcMono
    srcClimaxLTAS = To Ltas: 100
endif

if clxLevel_dB = undefined
    clxLevel_dB = 0
endif
if clxCOG_Hz = undefined
    clxCOG_Hz = 0
endif
appendInfoLine: "  Climax Profile:"
appendInfoLine: "    RMS level: ", fixed$(clxLevel_dB, 1), " dB | mean frame intensity: ", fixed$(clxAvgIntensity, 1), " dB"
appendInfoLine: "    Pitch: ", fixed$(clxAvgPitch, 1), " Hz (range: ", fixed$(clxPitchMin, 0), "-", fixed$(clxPitchMax, 0), " Hz)"
appendInfoLine: "    Spectral COG: ", fixed$(clxCOG_Hz, 0), " Hz | mean frame centroid: ", fixed$(clxAvgCentroid, 0), " Hz"
appendInfoLine: "    HNR: ", fixed$(clxAvgHNR, 1), " dB"
appendInfoLine: "    Formants: F1=", fixed$(clxAvgF1, 0), " F2=", fixed$(clxAvgF2, 0), " F3=", fixed$(clxAvgF3, 0), " Hz"

# ============================================================
# STEP 4: ANALYZE TARGET (global descriptors)
# ============================================================
appendInfoLine: ""
appendInfoLine: "[4/7] Analyzing Target..."

tgtNumFrames = floor((tgtDuration - frameStep) / frameStep)
if tgtNumFrames < 10
    exitScript: "Target too short for analysis."
endif

# Create analysis objects
selectObject: tgtMono
tgtIntensityObj = To Intensity: 70, frameStep, "yes"

selectObject: tgtMono
tgtPitchObj = To Pitch: frameStep, pitch_floor_Hz, pitch_ceiling_Hz

selectObject: tgtMono
tgtHarmonicityObj = To Harmonicity (cc): frameStep, pitch_floor_Hz, 0.1, 1.0

tgtFormantMaxHz = min(max_formant_Hz, tgtSR * 0.48)
selectObject: tgtMono
tgtFormantObj = To Formant (burg): frameStep, 5, tgtFormantMaxHz, 0.025, 50

tgtSpecMaxHz = min(8000, tgtSR * 0.48)
selectObject: tgtMono
tgtSpectrogramObj = To Spectrogram: 0.025, tgtSpecMaxHz, frameStep, 20, "Gaussian"

# Extract frame-by-frame features
tgtTime# = zero# (tgtNumFrames)
tgtIntensity# = zero# (tgtNumFrames)
tgtPitch# = zero# (tgtNumFrames)
tgtHNR# = zero# (tgtNumFrames)
tgtCentroid# = zero# (tgtNumFrames)

tgtSumInt = 0
tgtSumPitch = 0
tgtSumCentroid = 0
tgtSumHNR = 0
tgtSumF1 = 0
tgtSumF2 = 0
tgtSumF3 = 0
tgtVoicedCount = 0
tgtHNRCount = 0
tgtF1Count = 0
tgtF2Count = 0
tgtF3Count = 0

for i from 1 to tgtNumFrames
    t = (i - 0.5) * frameStep
    if t > tgtDuration
        t = tgtDuration - 0.001
    endif
    tgtTime#[i] = t
    
    selectObject: tgtIntensityObj
    val = Get value at time: t, "Cubic"
    tgtIntensity#[i] = if val <> undefined then val else 0 fi
    tgtSumInt = tgtSumInt + tgtIntensity#[i]
    
    selectObject: tgtPitchObj
    p = Get value at time: t, "Hertz", "Linear"
    tgtPitch#[i] = if p <> undefined then p else 0 fi
    if tgtPitch#[i] > 0
        tgtSumPitch = tgtSumPitch + tgtPitch#[i]
        tgtVoicedCount = tgtVoicedCount + 1
    endif
    
    selectObject: tgtHarmonicityObj
    h = Get value at time: t, "Cubic"
    tgtHNR#[i] = if h <> undefined then h else -200 fi
    if tgtHNR#[i] > -199
        tgtSumHNR = tgtSumHNR + tgtHNR#[i]
        tgtHNRCount = tgtHNRCount + 1
    endif
    
    selectObject: tgtFormantObj
    f1 = Get value at time: 1, t, "Hertz", "Linear"
    f2 = Get value at time: 2, t, "Hertz", "Linear"
    f3 = Get value at time: 3, t, "Hertz", "Linear"
    if f1 <> undefined and f1 > 0
        tgtSumF1 = tgtSumF1 + f1
        tgtF1Count = tgtF1Count + 1
    endif
    if f2 <> undefined and f2 > 0
        tgtSumF2 = tgtSumF2 + f2
        tgtF2Count = tgtF2Count + 1
    endif
    if f3 <> undefined and f3 > 0
        tgtSumF3 = tgtSumF3 + f3
        tgtF3Count = tgtF3Count + 1
    endif
    
    selectObject: tgtSpectrogramObj
    totalPower = 0
    weightedSum = 0
    freq = 100
    while freq <= tgtSpecMaxHz
        pw = Get power at: t, freq
        if pw <> undefined and pw > 0
            totalPower = totalPower + pw
            weightedSum = weightedSum + freq * pw
        endif
        freq = freq + 200
    endwhile
    if totalPower > 0
        tgtCentroid#[i] = weightedSum / totalPower
    else
        tgtCentroid#[i] = 1000
    endif
    tgtSumCentroid = tgtSumCentroid + tgtCentroid#[i]
endfor

# Compute target averages
tgtAvgIntensity = tgtSumInt / tgtNumFrames
tgtAvgPitch = if tgtVoicedCount > 0 then tgtSumPitch / tgtVoicedCount else 150 fi
tgtAvgCentroid = tgtSumCentroid / tgtNumFrames
tgtAvgHNR = if tgtHNRCount > 0 then tgtSumHNR / tgtHNRCount else 0 fi
tgtAvgF1 = if tgtF1Count > 0 then tgtSumF1 / tgtF1Count else 0 fi
tgtAvgF2 = if tgtF2Count > 0 then tgtSumF2 / tgtF2Count else 0 fi
tgtAvgF3 = if tgtF3Count > 0 then tgtSumF3 / tgtF3Count else 0 fi

# Target pitch range
tgtPitchMin = 9999
tgtPitchMax = 0
for i from 1 to tgtNumFrames
    if tgtPitch#[i] > 0
        if tgtPitch#[i] < tgtPitchMin
            tgtPitchMin = tgtPitch#[i]
        endif
        if tgtPitch#[i] > tgtPitchMax
            tgtPitchMax = tgtPitch#[i]
        endif
    endif
endfor
if tgtPitchMin = 9999
    tgtPitchMin = 100
    tgtPitchMax = 200
endif
tgtPitchRange = tgtPitchMax - tgtPitchMin

# Target whole-file level, spectral COG and LTAS
selectObject: tgtMono
tgtLevel_dB = Get intensity (dB)
tgtSpecForCOG = To Spectrum: "yes"
tgtCOG_Hz = Get centre of gravity: 2
removeObject: tgtSpecForCOG
selectObject: tgtMono
tgtLTAS = To Ltas: 100

appendInfoLine: "  Target Profile:"
appendInfoLine: "    RMS level: ", fixed$(tgtLevel_dB, 1), " dB | mean frame intensity: ", fixed$(tgtAvgIntensity, 1), " dB"
appendInfoLine: "    Pitch: ", fixed$(tgtAvgPitch, 1), " Hz (range: ", fixed$(tgtPitchMin, 0), "-", fixed$(tgtPitchMax, 0), " Hz)"
appendInfoLine: "    Spectral COG: ", fixed$(tgtCOG_Hz, 0), " Hz | mean frame centroid: ", fixed$(tgtAvgCentroid, 0), " Hz"
appendInfoLine: "    HNR: ", fixed$(tgtAvgHNR, 1), " dB"
appendInfoLine: "    Formants: F1=", fixed$(tgtAvgF1, 0), " F2=", fixed$(tgtAvgF2, 0), " F3=", fixed$(tgtAvgF3, 0), " Hz"

# ============================================================
# STEP 5: COMPUTE DELTAS
# ============================================================
appendInfoLine: ""
appendInfoLine: "[5/7] Computing acoustic deltas..."

deltaIntensity_dB = clxLevel_dB - tgtLevel_dB
deltaPitch_Hz = clxAvgPitch - tgtAvgPitch
deltaPitchRange = clxPitchRange - tgtPitchRange
deltaCentroid_Hz = clxCOG_Hz - tgtCOG_Hz
deltaHNR_dB = clxAvgHNR - tgtAvgHNR
deltaF1 = clxAvgF1 - tgtAvgF1
deltaF2 = clxAvgF2 - tgtAvgF2
deltaF3 = clxAvgF3 - tgtAvgF3

# Pitch shift in semitones
if tgtAvgPitch > 0 and clxAvgPitch > 0
    pitchShift_st = 12 * ln(clxAvgPitch / tgtAvgPitch) / ln(2)
else
    pitchShift_st = 0
endif

# Spectral tilt direction: positive = brighter climax
if deltaCentroid_Hz > 0
    tiltDirection$ = "brighter"
elsif deltaCentroid_Hz < 0
    tiltDirection$ = "darker"
else
    tiltDirection$ = "none"
endif

# No climax profile => no meaningful deltas. Keep diagnostics clean; Step 6 bypasses.
if numClimax = 0
    deltaIntensity_dB = 0
    deltaPitch_Hz = 0
    deltaPitchRange = 0
    deltaCentroid_Hz = 0
    deltaHNR_dB = 0
    deltaF1 = 0
    deltaF2 = 0
    deltaF3 = 0
    pitchShift_st = 0
    tiltDirection$ = "none"
endif

# LTAS SHAPE difference at key bands (mean-removed to separate timbre from level)
nBands = 6
bandFreq# = zero# (nBands)
bandFreq#[1] = 250
bandFreq#[2] = 500
bandFreq#[3] = 1000
bandFreq#[4] = 2000
bandFreq#[5] = 4000
bandFreq#[6] = 8000
srcBand# = zero# (nBands)
tgtBand# = zero# (nBands)
bandValid# = zero# (nBands)
commonLtasMax = min(srcSR / 2, tgtSR / 2)
validBandCount = 0
srcBandMean = 0
tgtBandMean = 0
for b from 1 to nBands
    fBand = bandFreq#[b]
    if fBand <= commonLtasMax
        selectObject: srcClimaxLTAS
        binNum = Get bin number from frequency: fBand
        binNum = round(binNum)
        nLtasBins = Get number of bins
        binNum = max(1, min(nLtasBins, binNum))
        srcBand#[b] = Get value in bin: binNum
        selectObject: tgtLTAS
        binNum = Get bin number from frequency: fBand
        binNum = round(binNum)
        nLtasBins = Get number of bins
        binNum = max(1, min(nLtasBins, binNum))
        tgtBand#[b] = Get value in bin: binNum
        if srcBand#[b] <> undefined and tgtBand#[b] <> undefined
            bandValid#[b] = 1
            validBandCount = validBandCount + 1
            srcBandMean = srcBandMean + srcBand#[b]
            tgtBandMean = tgtBandMean + tgtBand#[b]
        endif
    endif
endfor
if validBandCount > 0
    srcBandMean = srcBandMean / validBandCount
    tgtBandMean = tgtBandMean / validBandCount
endif
dLtasShape# = zero# (nBands)
for b from 1 to nBands
    if bandValid#[b] and numClimax > 0
        dLtasShape#[b] = (srcBand#[b] - srcBandMean) - (tgtBand#[b] - tgtBandMean)
    else
        dLtasShape#[b] = 0
    endif
endfor

appendInfoLine: "  Deltas (Source climax - Target):"
appendInfoLine: "    RMS level: ", fixed$(deltaIntensity_dB, 1), " dB"
appendInfoLine: "    Pitch diagnostic: ", fixed$(deltaPitch_Hz, 1), " Hz (", fixed$(pitchShift_st, 2), " st; NOT transferred)"
appendInfoLine: "    Spectral COG: ", fixed$(deltaCentroid_Hz, 0), " Hz (", tiltDirection$, ")"
appendInfoLine: "    HNR: ", fixed$(deltaHNR_dB, 1), " dB (heuristic transfer)"
appendInfoLine: "    LTAS shape deltas are mean-removed before EQ (level handled separately)."

# ============================================================
# STEP 6: APPLY TRANSFORMATIONS TO TARGET
# ============================================================
appendInfoLine: ""
appendInfoLine: "[6/7] Applying transformations..."

# Start with a copy of the target
selectObject: targetSound
result = Copy: "working"

# v1.2: honor the "output will be unmodified" promise. With zero
# climaxes the profile is all zeros and every delta is garbage
# (deltaIntensity = -tgtAvg scaled the output toward silence).
if numClimax = 0
    appendInfoLine: "  No climax profile: all transforms skipped (output = unmodified copy)."
    intensity_transfer = 0
    spectral_tilt_transfer = 0
    eq_transfer = 0
    harmonicity_transfer = 0
endif

# v1.2: intensity matching (6A) moved to run LAST -- see below.
# It used to run first, and the Scale peak 0.99 calls in 6C/6D/6E
# plus the final one overwrote it completely: the output always
# peaked at 0.99 regardless of Intensity_transfer.

appendInfoLine: "  [B] Pitch/formants: diagnostics only; no transformation"

# --- 6C: SPECTRAL TILT CORRECTION ---
if spectral_tilt_transfer > 0 and abs(deltaCentroid_Hz) > 50
    # Apply bandpass emphasis to shift spectral center of gravity
    selectObject: result
    
    if deltaCentroid_Hz > 0
        # Need to brighten: boost high band
        emphLow = 500 + (1 - spectral_tilt_transfer) * 1500
        emphHigh = min(tgtSR * 0.48, 5000 + spectral_tilt_transfer * 7000)
        emphLow = min(emphLow, max(80, emphHigh - 200))
        
        # Create blended version: partial filter application
        selectObject: result
        resultCopy = Copy: "tilt_dry"
        
        selectObject: result
        Filter (pass Hann band): emphLow, emphHigh, 300
        tiltWet = selected("Sound")
        
        # v1.1: Single Formula wet/dry blend using object[<id>, col]
        # indexed read instead of three-step Sound_'name$'(x) pattern.
        # Same math: dry * (1-w) + wet * w, where w = blendW.
        blendW = spectral_tilt_transfer * 0.5
        wetID_str$ = string$(tiltWet)
        blendW_str$ = fixed$(blendW, 6)
        oneMinusW_str$ = fixed$(1 - blendW, 6)
        selectObject: resultCopy
        Formula: "self * " + oneMinusW_str$
            ... + " + object[" + wetID_str$
            ... + ", row, col] * " + blendW_str$
        
        removeObject: tiltWet, result
        result = resultCopy
        
        appendInfoLine: "  [C] Spectral tilt: brightened (emphasis ", fixed$(emphLow, 0), "-", fixed$(emphHigh, 0), " Hz)"
    else
        # Need to darken: emphasize low band
        emphLow = max(80, 100 * (1 - spectral_tilt_transfer))
        emphHigh = min(tgtSR * 0.48, 3000 - spectral_tilt_transfer * 1500)
        
        selectObject: result
        resultCopy = Copy: "tilt_dry"
        
        selectObject: result
        Filter (pass Hann band): emphLow, emphHigh, 300
        tiltWet = selected("Sound")
        
        # v1.1: same single-Formula pattern as the brighten branch above.
        blendW = spectral_tilt_transfer * 0.5
        wetID_str$ = string$(tiltWet)
        blendW_str$ = fixed$(blendW, 6)
        oneMinusW_str$ = fixed$(1 - blendW, 6)
        selectObject: resultCopy
        Formula: "self * " + oneMinusW_str$
            ... + " + object[" + wetID_str$
            ... + ", row, col] * " + blendW_str$
        
        removeObject: tiltWet, result
        result = resultCopy
        
        appendInfoLine: "  [C] Spectral tilt: darkened (emphasis ", fixed$(emphLow, 0), "-", fixed$(emphHigh, 0), " Hz)"
    endif
    
else
    appendInfoLine: "  [C] Spectral tilt: no change needed"
endif

# --- 6D: LTAS-SHAPE EQ SHAPING ---
eqAppliedBand = 0
eqAppliedDelta = 0
eqGain = 0
if eq_transfer > 0 and validBandCount > 0
    # Pick the strongest MEAN-REMOVED shape mismatch, preserving its sign.
    maxDeltaAbs = 0
    selectedDelta = 0
    maxBand = 0
    for b from 1 to nBands
        if bandValid#[b] and abs(dLtasShape#[b]) > maxDeltaAbs
            maxDeltaAbs = abs(dLtasShape#[b])
            selectedDelta = dLtasShape#[b]
            maxBand = bandFreq#[b]
        endif
    endfor

    if maxBand > 0 and maxDeltaAbs > 2
        bandwidth = max(200, maxBand * 0.5)
        lowFreq = max(80, maxBand - bandwidth)
        highFreq = min(tgtSR * 0.48, maxBand + bandwidth)

        selectObject: result
        resultCopy = Copy: "eq_dry"
        selectObject: result
        Filter (pass Hann band): lowFreq, highFreq, bandwidth * 0.3
        eqBand = selected("Sound")

        # Signed additive band correction. Positive delta -> boost; negative -> cut.
        eqGain = eq_transfer * selectedDelta / 40
        eqGain = max(-0.4, min(0.4, eqGain))
        bandID_str$ = string$(eqBand)
        eqGain_str$ = fixed$(eqGain, 6)
        selectObject: resultCopy
        Formula: "self + object[" + bandID_str$ + ", row, col] * " + eqGain_str$

        removeObject: eqBand, result
        result = resultCopy
        eqAppliedBand = maxBand
        eqAppliedDelta = selectedDelta
        if eqGain >= 0
            eqAction$ = "boost"
        else
            eqAction$ = "cut"
        endif
        appendInfoLine: "  [D] EQ: ", eqAction$, " near ", maxBand, " Hz | shape delta ", fixed$(selectedDelta, 1), " dB | gain ", fixed$(eqGain, 3)
    else
        appendInfoLine: "  [D] EQ: mean-removed shape differences too small, skipped"
    endif
else
    appendInfoLine: "  [D] EQ: disabled or no common LTAS bands"
endif

# --- 6E: HARMONICITY SHAPING ---
if harmonicity_transfer > 0 and deltaHNR_dB > 1
    # Increase harmonicity: mild low-pass to reduce noise, plus gentle saturation
    selectObject: result
    
    # Gentle high-frequency attenuation to reduce noisiness
    cutoff = min(tgtSR * 0.48, 8000 + (1 - harmonicity_transfer) * 4000)
    
    resultCopy = Copy: "hnr_dry"
    
    selectObject: result
    Filter (pass Hann band): 20, cutoff, 500
    harmFiltered = selected("Sound")
    
    # v1.1: Single Formula wet/dry blend using object[<id>, col].
    # Same math as before: dry * (1-w) + wet * w.
    harmW = harmonicity_transfer * 0.3
    hfID_str$ = string$(harmFiltered)
    harmW_str$ = fixed$(harmW, 6)
    oneMinusHarmW_str$ = fixed$(1 - harmW, 6)
    selectObject: resultCopy
    Formula: "self * " + oneMinusHarmW_str$
        ... + " + object[" + hfID_str$
        ... + ", row, col] * " + harmW_str$
    
    removeObject: harmFiltered, result
    result = resultCopy
    
    # Mild soft saturation to increase harmonics
    selectObject: result
    satAmount = harmonicity_transfer * 0.3
    Formula: "self * (1 - satAmount) + tanh(self * 3) / 3 * satAmount"
    
    appendInfoLine: "  [E] Harmonicity colour: more periodic (filter + mild saturation; heuristic, not an exact HNR match)"
elsif harmonicity_transfer > 0 and deltaHNR_dB < -1
    # Decrease harmonicity: add subtle noise
    selectObject: result
    noiseAmount = harmonicity_transfer * abs(deltaHNR_dB) / 40
    noiseAmount = min(0.15, noiseAmount)
    Formula: "self * (1 - noiseAmount) + randomGauss(0, 0.1) * noiseAmount"
    appendInfoLine: "  [E] Harmonicity colour: noisier (added ", fixed$(noiseAmount * 100, 1), "% noise; heuristic)"
else
    appendInfoLine: "  [E] Harmonicity: no change needed"
endif

# --- 6A (v1.3: runs LAST): RMS LEVEL SHIFT ---
# Apply the requested dB shift directly to every channel. This preserves
# stereo balance and keeps the representative analysis channel coherent.
requestedLevelShift_dB = 0
if intensity_transfer > 0 and abs(deltaIntensity_dB) > 0.5
    requestedLevelShift_dB = deltaIntensity_dB * intensity_transfer
    levelGain = 10 ^ (requestedLevelShift_dB / 20)
    levelGain_str$ = fixed$(levelGain, 10)
    selectObject: result
    Formula: "self * " + levelGain_str$
    peakNow = Get absolute extremum: 0, 0, "None"
    if peakNow > 0.99
        Scale peak: 0.99
        appendInfoLine: "  [A] RMS level: requested ", fixed$(requestedLevelShift_dB, 1), " dB; headroom clamp applied"
    else
        appendInfoLine: "  [A] RMS level: applied ", fixed$(requestedLevelShift_dB, 1), " dB"
    endif
else
    appendInfoLine: "  [A] RMS level: no change needed"
endif

# --- Final output ---
# v1.2: no blanket Scale peak here -- it destroyed the intensity
# match. Safety clamp only.
selectObject: result
Rename: "Target_matched_to_Source_Climax"
finalPeakChk = Get absolute extremum: 0, 0, "None"
if numClimax > 0 and finalPeakChk > 0.99
    Scale peak: 0.99
endif
finalOutput = selected("Sound")
outputDuration = Get total duration
# Measure output level on the SAME representative Target channel used for analysis.
if tgtChannels > 1
    selectObject: finalOutput
    Extract one channel: tgtBestChannel
    finalLevelTmp = selected("Sound")
    finalLevel_dB = Get intensity (dB)
    removeObject: finalLevelTmp
else
    selectObject: finalOutput
    finalLevel_dB = Get intensity (dB)
endif

appendInfoLine: ""
appendInfoLine: "  Output: Target_matched_to_Source_Climax (", fixed$(outputDuration, 2), " s)"
appendInfoLine: "  Measured output RMS level (analysis ch): ", fixed$(finalLevel_dB, 1), " dB"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[7/7] Measuring output + creating visualization..."

    # Representative output channel corresponding to Target analysis channel.
    selectObject: finalOutput
    if tgtChannels > 1
        Extract one channel: tgtBestChannel
        outVizMono = selected("Sound")
    else
        outVizMono = Copy: "out_viz"
    endif

    # Output spectral COG / LTAS.
    selectObject: outVizMono
    outSpecForCOG = To Spectrum: "yes"
    outCOG_Hz = Get centre of gravity: 2
    removeObject: outSpecForCOG
    selectObject: outVizMono
    outLTAS = To Ltas: 100

    # Output HNR measured with the same analysis family (coarser query loop is enough for QC).
    selectObject: outVizMono
    outHnrObj = To Harmonicity (cc): frameStep, pitch_floor_Hz, 0.1, 1.0
    outHnrSum = 0
    outHnrCount = 0
    outFrames = max(1, floor(tgtDuration / frameStep))
    for i from 1 to outFrames
        t = min(tgtDuration - 0.001, (i - 0.5) * frameStep)
        selectObject: outHnrObj
        h = Get value at time: t, "Cubic"
        if h <> undefined and h > -199
            outHnrSum = outHnrSum + h
            outHnrCount = outHnrCount + 1
        endif
    endfor
    outAvgHNR = if outHnrCount > 0 then outHnrSum / outHnrCount else 0 fi
    removeObject: outHnrObj

    # Output LTAS at the same bands, then mean-remove.
    outBand# = zero# (nBands)
    outBandMean = 0
    outValidCount = 0
    for b from 1 to nBands
        if bandValid#[b]
            fBand = bandFreq#[b]
            selectObject: outLTAS
            binNum = Get bin number from frequency: fBand
        binNum = round(binNum)
            nLtasBins = Get number of bins
            binNum = max(1, min(nLtasBins, binNum))
            outBand#[b] = Get value in bin: binNum
            if outBand#[b] <> undefined
                outBandMean = outBandMean + outBand#[b]
                outValidCount = outValidCount + 1
            endif
        endif
    endfor
    if outValidCount > 0
        outBandMean = outBandMean / outValidCount
    endif
    outShapeDelta# = zero# (nBands)
    for b from 1 to nBands
        if bandValid#[b]
            outShapeDelta#[b] = (outBand#[b] - outBandMean) - (tgtBand#[b] - tgtBandMean)
        endif
    endfor

    # Requested/achieved profile fractions (0 = original Target, 1 = full Source-climax delta).
    levelReqFrac = if numClimax > 0 and abs(deltaIntensity_dB) > 0.5 then intensity_transfer else 0 fi
    cogReqFrac = if numClimax > 0 and abs(deltaCentroid_Hz) > 50 then spectral_tilt_transfer else 0 fi
    hnrReqFrac = if numClimax > 0 and abs(deltaHNR_dB) > 1 then harmonicity_transfer else 0 fi
    levelFrac = 0
    if abs(deltaIntensity_dB) > 0.1
        levelFrac = (finalLevel_dB - tgtLevel_dB) / deltaIntensity_dB
    endif
    cogFrac = 0
    if abs(deltaCentroid_Hz) > 1
        cogFrac = (outCOG_Hz - tgtCOG_Hz) / deltaCentroid_Hz
    endif
    hnrFrac = 0
    if abs(deltaHNR_dB) > 0.1
        hnrFrac = (outAvgHNR - tgtAvgHNR) / deltaHNR_dB
    endif
    fracMin = min(-0.25, min(min(levelReqFrac, levelFrac), min(min(cogReqFrac, cogFrac), min(hnrReqFrac, hnrFrac))) - 0.15)
    fracMax = max(1.25, max(max(levelReqFrac, levelFrac), max(max(cogReqFrac, cogFrac), max(hnrReqFrac, hnrFrac))) + 0.15)
    fracMin = max(-1.0, fracMin)
    fracMax = min(2.0, fracMax)

    # Common waveform scale for Target / final output.
    selectObject: tgtMono
    tMax = Get maximum: 0, 0, "Sinc70"
    tMin = Get minimum: 0, 0, "Sinc70"
    selectObject: outVizMono
    oMax = Get maximum: 0, 0, "Sinc70"
    oMin = Get minimum: 0, 0, "Sinc70"
    waveY = max(0.001, 1.08 * max(max(abs(tMax), abs(tMin)), max(abs(oMax), abs(oMin))))

    Erase all

    # House title strip.
    Select outer viewport: 0, 8, 0.00, 0.38
    Select inner viewport: 0, 8, 0.00, 0.38
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.58, "half", "Climax Profile Matcher v1.3"
    Font size: 7
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.5, "centre", 0.14, "half", sourceName$ + " -> " + targetName$ + " | " + presetName$ + " | " + string$(numClimax) + " climax region(s)"

    # Process strip.
    Select outer viewport: 0, 8, 0.40, 0.72
    Select inner viewport: 0, 8, 0.40, 0.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    Font size: 7
    Colour: "{0.25, 0.25, 0.30}"
    Text: 0.5, "centre", 0.52, "half", "detect Source climax -> measure level / COG / LTAS shape / HNR -> transform Target -> re-measure output"

    # ===== A: DETECTION LAW =====
    Select outer viewport: 0.0, 4.0, 0.78, 2.78
    Select inner viewport: 0.48, 3.78, 1.08, 2.52
    Axes: 0, srcDuration, 0, 1.05
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, srcDuration, 0, 1.05
    for c from 1 to numClimax
        Paint rectangle: "{1.0, 0.90, 0.84}", clxStartTime_'c', clxEndTime_'c', 0, 1.05
    endfor
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, climaxMinScore / 4, srcDuration, climaxMinScore / 4
    Solid line
    Colour: "{0.78, 0.20, 0.20}"
    Line width: 1.5
    for i from 2 to srcNumFrames
        Draw line: srcTime#[i-1], climaxScore#[i-1] / 4, srcTime#[i], climaxScore#[i] / 4
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.25, "yes", "yes", "no"
    Marks bottom every: 1, max(0.5, srcDuration / 4), "yes", "yes", "no"
    Text left: "yes", "criteria fraction"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0.0, 4.0, 0.78, 1.02
    Select inner viewport: 0.0, 4.0, 0.78, 1.02
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "A  CLIMAX DETECTION"

    # ===== B: PROFILE TRANSFER FRACTION =====
    Select outer viewport: 4.0, 8.0, 0.78, 2.78
    Select inner viewport: 4.48, 7.78, 1.08, 2.52
    Axes: 0, 4, fracMin, fracMax
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, 4, fracMin, fracMax
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0, 0, 4, 0
    Dotted line
    Draw line: 0, 1, 4, 1
    Solid line
    # Orange = requested weight; blue = measured fraction actually achieved.
    Paint rectangle: "{0.90, 0.55, 0.32}", 0.62, 0.90, 0, levelReqFrac
    Paint rectangle: "{0.30, 0.52, 0.78}", 0.92, 1.20, 0, levelFrac
    Paint rectangle: "{0.90, 0.55, 0.32}", 1.62, 1.90, 0, cogReqFrac
    Paint rectangle: "{0.30, 0.52, 0.78}", 1.92, 2.20, 0, cogFrac
    Paint rectangle: "{0.90, 0.55, 0.32}", 2.62, 2.90, 0, hnrReqFrac
    Paint rectangle: "{0.30, 0.52, 0.78}", 2.92, 3.20, 0, hnrFrac
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Font size: 7
    Text: 0.91, "centre", fracMin + 0.05 * (fracMax-fracMin), "bottom", "Level"
    Text: 1.91, "centre", fracMin + 0.05 * (fracMax-fracMin), "bottom", "COG"
    Text: 2.91, "centre", fracMin + 0.05 * (fracMax-fracMin), "bottom", "HNR"
    Select outer viewport: 4.0, 8.0, 0.78, 1.02
    Select inner viewport: 4.0, 8.0, 0.78, 1.02
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "B  REQUESTED vs ACHIEVED"

    # ===== C: SPECTRAL-SHAPE PROOF =====
    Select outer viewport: 0.0, 4.0, 2.90, 4.90
    Select inner viewport: 0.48, 3.78, 3.20, 4.64
    maxShape = 3
    for b from 1 to nBands
        if bandValid#[b]
            maxShape = max(maxShape, abs(dLtasShape#[b]))
            maxShape = max(maxShape, abs(outShapeDelta#[b]))
        endif
    endfor
    maxShape = min(18, maxShape * 1.15)
    Axes: 0.5, 6.5, -maxShape, maxShape
    Paint rectangle: "{0.985, 0.985, 0.985}", 0.5, 6.5, -maxShape, maxShape
    Colour: "{0.72, 0.72, 0.72}"
    Draw line: 0.5, 0, 6.5, 0
    # Desired Source-climax minus Target shape.
    Colour: "{0.90, 0.55, 0.32}"
    Line width: 1.5
    prevSet = 0
    for b from 1 to nBands
        if bandValid#[b]
            if prevSet
                Draw line: prevB, prevV, b, dLtasShape#[b]
            endif
            Paint circle (mm): "{0.90, 0.55, 0.32}", b, dLtasShape#[b], 1.2
            prevB = b
            prevV = dLtasShape#[b]
            prevSet = 1
        endif
    endfor
    # Measured Output minus Target shape.
    Colour: "{0.30, 0.52, 0.78}"
    prevSet = 0
    for b from 1 to nBands
        if bandValid#[b]
            if prevSet
                Draw line: prevB, prevV, b, outShapeDelta#[b]
            endif
            Paint circle (mm): "{0.30, 0.52, 0.78}", b, outShapeDelta#[b], 1.2
            prevB = b
            prevV = outShapeDelta#[b]
            prevSet = 1
        endif
    endfor
    Line width: 1
    Select inner viewport: 0.48, 3.78, 3.20, 4.64
    Axes: 0.5, 6.5, -maxShape, maxShape
    Colour: "Black"
    Draw inner box
    Marks left every: 1, max(2, round(maxShape/3)), "yes", "yes", "no"
    Font size: 7
    Text: 1, "centre", -maxShape * 0.93, "half", "250"
    Text: 2, "centre", -maxShape * 0.93, "half", "500"
    Text: 3, "centre", -maxShape * 0.93, "half", "1k"
    Text: 4, "centre", -maxShape * 0.93, "half", "2k"
    Text: 5, "centre", -maxShape * 0.93, "half", "4k"
    Text: 6, "centre", -maxShape * 0.93, "half", "8k"
    Text left: "yes", "shape dB"
    Select outer viewport: 0.0, 4.0, 2.90, 3.14
    Select inner viewport: 0.0, 4.0, 2.90, 3.14
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "C  MEAN-REMOVED LTAS PROOF"

    # ===== D: TARGET / OUTPUT SAME-SCALE WAVEFORMS =====
    Select outer viewport: 4.0, 8.0, 2.90, 4.90
    # top waveform
    Select inner viewport: 4.48, 7.78, 3.20, 3.78
    selectObject: tgtMono
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, tgtDuration, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    # bottom waveform
    Select inner viewport: 4.48, 7.78, 3.94, 4.52
    selectObject: outVizMono
    Colour: "{0.30, 0.52, 0.78}"
    Draw: 0, tgtDuration, -waveY, waveY, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, max(0.5, tgtDuration / 4), "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    # labels in separate narrow strip to avoid collisions
    Select outer viewport: 4.0, 8.0, 2.90, 3.14
    Select inner viewport: 4.0, 8.0, 2.90, 3.14
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.55, "half", "D  TARGET / MATCHED (same amplitude scale)"
    Select outer viewport: 4.05, 4.46, 3.20, 4.52
    Select inner viewport: 4.05, 4.46, 3.20, 4.52
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.95, "right", 0.78, "half", "Tgt"
    Colour: "{0.30, 0.52, 0.78}"
    Text: 0.95, "right", 0.22, "half", "Out"

    # Footer summary.
    Select outer viewport: 0, 8, 4.98, 5.30
    Select inner viewport: 0, 8, 4.98, 5.30
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.30, 0.30, 0.35}"
    eqText$ = if eqAppliedBand > 0 then "EQ " + string$(eqAppliedBand) + "Hz g=" + fixed$(eqGain, 2) else "EQ skipped" fi
    Text: 0.5, "centre", 0.52, "half", "Level " + fixed$(tgtLevel_dB,1) + " -> " + fixed$(finalLevel_dB,1) + " dB | COG " + fixed$(tgtCOG_Hz,0) + " -> " + fixed$(outCOG_Hz,0) + " Hz | HNR " + fixed$(tgtAvgHNR,1) + " -> " + fixed$(outAvgHNR,1) + " dB | " + eqText$

    removeObject: outLTAS, outVizMono
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: srcMono, tgtMono
removeObject: srcIntensityObj, srcPitchObj, srcHarmonicityObj, srcFormantObj, srcSpectrogramObj
removeObject: tgtIntensityObj, tgtPitchObj, tgtHarmonicityObj, tgtFormantObj, tgtSpectrogramObj
removeObject: srcClimaxLTAS, tgtLTAS

selectObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="

if play_output
    Play
endif
