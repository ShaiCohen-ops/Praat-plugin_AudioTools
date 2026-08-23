# ============================================================
# Praat AudioTools - Harmonic_Tension_Sorted_Grains.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Set-Theory-Driven Harmonic Tension Granular Sorting.
#   Extracts grains from audio, analyses spectral peaks to
#   derive Pitch Class sets, computes an Interval-Class
#   Dissonance Score per grain, then re-assembles the grains
#   sorted from Chaos -> Clarity or Clarity -> Chaos.
#
#   The score is a compositional Pitch-Class interval-class tension metric,
#   not a psychoacoustic roughness/dissonance model. Spectral peaks are mapped
#   to UNIQUE pitch classes before the following IC weights are applied.
#
#   Tension weights (IC = Interval Class):
#     IC 1 (m2/M7) = 1.00  HIGH TENSION
#     IC 6 (TT)    = 1.00  HIGH TENSION
#     IC 2 (M2/m7) = 0.50  MEDIUM
#     IC 3 (m3/M6) = 0.50  MEDIUM
#     IC 4 (M3/m6) = 0.10  CONSONANT
#     IC 5 (P4/P5) = 0.10  CONSONANT
#
# Changelog v1.4:
#   - Visualization-only AudioTools uniformity pass; DSP and score computation unchanged.
#   - Title/subtitle, panel geometry, fonts, greys and summary strip aligned to
#     the library standard; Sound names are escaped for Praat Picture text.
#   - Original/output waveforms now share one amplitude scale.
#   - Output uses the library blue; tension classes use semantic green/amber/red
#     consistently in both the sorted curve and histogram (blue no longer has
#     two unrelated meanings).
#   - Tension panel uses the absolute 0..1 score scale so the fixed 0.35/0.75
#     class boundaries have a stable visual meaning across sources and presets.
#   - FIX: drawing ends by re-selecting the full page, so Picture export saves
#     the whole visualization rather than only the footer/last viewport.
#
# Changelog v1.3:
#   - FIX: visualization cleanup could leave no Sound selected; the Final Info
#     line then called selected$("Sound") and aborted after otherwise-successful
#     rendering. Result name is now stored explicitly and result is reselected
#     before final reporting/playback.
#
# Changelog v1.2:
#   - CRITICAL Set-Theory fix: spectral Pitch Classes are deduplicated before
#     interval-class scoring. v1.1 treated repeated PCs as a multiset; duplicate
#     unisons added zero-weight pairs and biased tension scores downward.
#   - CRITICAL assembly-order fix: v1.1 repeatedly selected an accumulated
#     output together with older grain objects. Praat concatenates in Object-list
#     order, not selection order, so later grains could be prepended. v1.2 makes
#     fresh grain/gap copies in the desired order and concatenates once.
#   - Spectral analysis upgraded from 100-Hz LTAS bins to Sound -> Spectrum ->
#     Ltas (1-to-1), preserving Fourier frequency resolution for Pitch-Class
#     classification.
#   - Peak bands are now non-overlapping logarithmic bands across the requested
#     analysis range; Number_of_peaks is validated to 2..12. v1.1's fifth band
#     overlapped bands 3/4, and values >5 simply repeated the same band.
#   - Added a relative peak threshold so noise-floor maxima are not promoted to
#     Pitch-Class set members.
#   - Stereo/multichannel audio is preserved: analysis uses a mono fold, while
#     rendered grains are extracted from the original Sound.
#   - Non-zero Sound time domains are handled explicitly with sourceStart.
#   - Grain_overlap renamed Sampling_overlap: it controls how many random
#     analysis/render grains are drawn, not overlap between output grains.
#   - Removed arbitrary 10-ms minimum grain; minimum is tied to sample period.
#   - Gap may be exactly zero; safe normalization skips silent output.
#   - Visualization clamps frequency to Nyquist and avoids zero mark spacing.
#
# Changelog v1.1:
#   - FAST: replaced bin-by-bin spectrum loop with
#     band-based Get frequency of maximum (built-in, O(1)/band)
#   - FAST: replaced OLA Formula buffer with Concatenate chain
#   - Added 8 presets
#   - Visualization: 5 panels matching AudioTools style
#     (waveforms, tension curve with zone shading,
#      distribution histogram, spectrogram, stats footer)
# ============================================================

form Harmonic Tension Sorted Grains v1.4
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Chaos Purge
        option Dawn Resolve
        option Tritone Hell
        option Perfect Fifth Cloud
        option Micro Tension
        option Slow Meditation
        option Reverse Resolve
        option Extreme Purge

    comment === Grain Parameters (Custom only) ===
    positive Grain_size_ms 100
    real Grain_size_variation_ms 20
    optionmenu Grain_size_mode 1
        option Fixed
        option Random

    comment === Density ===
    real    Sampling_overlap_(0-0.8)  0.3
    natural Max_grains             200

    comment === Spectral Analysis ===
    natural Number_of_peaks      4
    positive Min_frequency_Hz      80
    positive Max_frequency_Hz      5000
    real Peak_relative_threshold_dB 35

    comment === Sorting ===
    optionmenu Sort_direction 1
        option Chaos to Clarity  (descending dissonance)
        option Clarity to Chaos  (ascending dissonance)
    real Gap_between_grains_ms 10

    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result        1
endform

# ============================================================
# === Apply Presets ==========================================
# ============================================================
if preset = 2
    grain_size_ms          = 80
    grain_size_variation_ms= 20
    grain_size_mode        = 2
    sampling_overlap          = 0.3
    max_grains             = 200
    number_of_peaks        = 4
    max_frequency_Hz       = 5000
    sort_direction         = 1
    gap_between_grains_ms  = 0
    preset_name$           = "Chaos Purge"

elsif preset = 3
    grain_size_ms          = 150
    grain_size_variation_ms= 50
    grain_size_mode        = 2
    sampling_overlap          = 0.5
    max_grains             = 150
    number_of_peaks        = 4
    max_frequency_Hz       = 4000
    sort_direction         = 1
    gap_between_grains_ms  = 20
    preset_name$           = "Dawn Resolve"

elsif preset = 4
    grain_size_ms          = 60
    grain_size_variation_ms= 15
    grain_size_mode        = 2
    sampling_overlap          = 0.2
    max_grains             = 300
    number_of_peaks        = 5
    max_frequency_Hz       = 6000
    sort_direction         = 2
    gap_between_grains_ms  = 5
    preset_name$           = "Tritone Hell"

elsif preset = 5
    grain_size_ms          = 200
    grain_size_variation_ms= 60
    grain_size_mode        = 2
    sampling_overlap          = 0.6
    max_grains             = 120
    number_of_peaks        = 3
    max_frequency_Hz       = 3000
    sort_direction         = 1
    gap_between_grains_ms  = 30
    preset_name$           = "Perfect Fifth Cloud"

elsif preset = 6
    grain_size_ms          = 30
    grain_size_variation_ms= 10
    grain_size_mode        = 2
    sampling_overlap          = 0.1
    max_grains             = 400
    number_of_peaks        = 3
    max_frequency_Hz       = 8000
    sort_direction         = 1
    gap_between_grains_ms  = 0
    preset_name$           = "Micro Tension"

elsif preset = 7
    grain_size_ms          = 400
    grain_size_variation_ms= 100
    grain_size_mode        = 2
    sampling_overlap          = 0.7
    max_grains             = 80
    number_of_peaks        = 4
    max_frequency_Hz       = 3000
    sort_direction         = 1
    gap_between_grains_ms  = 50
    preset_name$           = "Slow Meditation"

elsif preset = 8
    grain_size_ms          = 100
    grain_size_variation_ms= 30
    grain_size_mode        = 2
    sampling_overlap          = 0.3
    max_grains             = 200
    number_of_peaks        = 4
    max_frequency_Hz       = 5000
    sort_direction         = 2
    gap_between_grains_ms  = 10
    preset_name$           = "Reverse Resolve"

elsif preset = 9
    grain_size_ms          = 50
    grain_size_variation_ms= 20
    grain_size_mode        = 2
    sampling_overlap          = 0.0
    max_grains             = 500
    number_of_peaks        = 5
    max_frequency_Hz       = 8000
    sort_direction         = 1
    gap_between_grains_ms  = 0
    preset_name$           = "Extreme Purge"

else
    preset_name$ = "Custom"
endif

# ============================================================
# === Check Input ============================================
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original    = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
sourceStart  = Get start time
sourceEnd    = Get end time
duration     = Get total duration
sample_rate  = Get sampling frequency
num_channels = Get number of channels
nyquist      = sample_rate / 2

# === Validate ===
if grain_size_ms <= 0
    exitScript: "Grain size must be > 0 ms"
endif
if grain_size_variation_ms < 0
    exitScript: "Grain-size variation must be >= 0 ms"
endif
if sampling_overlap < 0 or sampling_overlap > 0.8
    exitScript: "Sampling overlap must be between 0 and 0.8"
endif
if max_grains < 2 or max_grains > 5000
    exitScript: "Max grains must be between 2 and 5000"
endif
if number_of_peaks < 2 or number_of_peaks > 12
    exitScript: "Number of peaks must be between 2 and 12"
endif
if min_frequency_Hz <= 0
    exitScript: "Minimum analysis frequency must be > 0 Hz"
endif
if max_frequency_Hz <= min_frequency_Hz
    exitScript: "Maximum analysis frequency must exceed minimum frequency"
endif
if peak_relative_threshold_dB < 0
    exitScript: "Relative peak threshold must be >= 0 dB"
endif
if gap_between_grains_ms < 0
    exitScript: "Gap between grains must be >= 0 ms"
endif

analysisMinHz = min_frequency_Hz
analysisMaxHz = min(max_frequency_Hz, nyquist * 0.98)
if analysisMaxHz <= analysisMinHz
    exitScript: "Analysis frequency range is empty at this sampling rate"
endif
vizMaxHz = min(5000, nyquist)

grain_dur_base = grain_size_ms / 1000
minGrainDur = 2 / sample_rate
if duration < min(grain_dur_base, minGrainDur)
    exitScript: "Sound is too short for the requested grain analysis"
endif

# Mono is for spectral analysis only. Rendered grains come from original,
# preserving the source channel count.
if num_channels > 1
    selectObject: original
    Convert to mono
    analysisSource = selected("Sound")
else
    selectObject: original
    analysisSource = Copy: "ht_analysis_temp"
endif

# ============================================================
# === IC Weight Table (Set Theory) ===========================
# ============================================================
ic_weight[0] = 0.00
ic_weight[1] = 1.00
ic_weight[2] = 0.50
ic_weight[3] = 0.50
ic_weight[4] = 0.10
ic_weight[5] = 0.10
ic_weight[6] = 1.00

# ============================================================
# === Spectral Peak Strategy =================================
# ============================================================
# The analysis range is divided into Number_of_peaks non-overlapping
# logarithmic bands. Each band contributes at most one salient Pitch Class.
# Duplicate Pitch Classes are removed before IC scoring, so pc_set is a set.

# ============================================================
# === Calculate Grain Count ==================================
# ============================================================
hop_time = grain_dur_base * (1 - sampling_overlap)
hop_time = max(hop_time, 1 / sample_rate)
num_grains = round(duration / hop_time)
if num_grains > max_grains
    num_grains = max_grains
endif
if num_grains < 2
    removeObject: analysisSource
    exitScript: "Too few grains. Reduce grain size or increase sound duration."
endif

# ============================================================
# === Info ===================================================
# ============================================================
writeInfoLine: "=== Harmonic Tension Sorted Grains ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", preset_name$
if sort_direction = 1
    appendInfoLine: "Sort: Chaos -> Clarity (descending dissonance)"
else
    appendInfoLine: "Sort: Clarity -> Chaos (ascending dissonance)"
endif
appendInfoLine: "Grains: ", num_grains, " | Size: ", grain_size_ms, " ms | Peak bands: ", number_of_peaks
appendInfoLine: "Analysis: ", fixed$(analysisMinHz, 1), "-", fixed$(analysisMaxHz, 1), " Hz | threshold: ", peak_relative_threshold_dB, " dB"
appendInfoLine: ""
appendInfoLine: "Analysing grains..."

# ============================================================
# === Arrays =================================================
# ============================================================
grainIDs#   = zero#(num_grains)
grainScore# = zero#(num_grains)
grainDurs#  = zero#(num_grains)
grainCount  = 0

# ============================================================
# === Extract & Analyse Grains ===============================
# ============================================================
for i from 1 to num_grains

    # --- Grain duration ---
    if grain_size_mode = 2
        variation = (grain_size_variation_ms / 1000) * randomUniform(-1, 1)
        gDur = grain_dur_base + variation
        gDur = max(minGrainDur, min(duration, gDur))
    else
        gDur = min(duration, max(minGrainDur, grain_dur_base))
    endif

    # --- Source position (zero-based compositional offset) ---
    maxStartOffset = max(0, duration - gDur)
    if maxStartOffset > 0
        srcOffset = randomUniform(0, maxStartOffset)
    else
        srcOffset = 0
    endif
    srcStart = sourceStart + srcOffset
    srcEnd = min(sourceEnd, srcStart + gDur)
    gDur = srcEnd - srcStart

    # --- Analysis grain: mono, high-resolution spectrum ---
    selectObject: analysisSource
    Extract part: srcStart, srcEnd, "Hanning", 1, "no"
    analysisGrain = selected("Sound")

    selectObject: analysisGrain
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    To Ltas (1-to-1)
    ltas = selected("Ltas")

    selectObject: ltas
    globalPeakDb = Get maximum: analysisMinHz, analysisMaxHz, "Parabolic"

    n_valid_pc = 0
    bandRatio = (analysisMaxHz / analysisMinHz) ^ (1 / number_of_peaks)

    for b from 1 to number_of_peaks
        bLo = analysisMinHz * bandRatio ^ (b - 1)
        if b = number_of_peaks
            bHi = analysisMaxHz
        else
            bHi = analysisMinHz * bandRatio ^ b
        endif

        selectObject: ltas
        peakDb = Get maximum: bLo, bHi, "Parabolic"
        peak_hz = Get frequency of maximum: bLo, bHi, "Parabolic"

        if peak_hz >= analysisMinHz and peak_hz <= analysisMaxHz and peakDb >= globalPeakDb - peak_relative_threshold_dB
            midi_val = 69 + 12 * log2(peak_hz / 440)
            pc = round(midi_val) mod 12
            if pc < 0
                pc = pc + 12
            endif

            # Set-theory means SET: keep each Pitch Class only once.
            isDuplicate = 0
            for u from 1 to n_valid_pc
                if pc_set[u] = pc
                    isDuplicate = 1
                endif
            endfor
            if not isDuplicate
                n_valid_pc += 1
                pc_set[n_valid_pc] = pc
            endif
        endif
    endfor

    removeObject: ltas, spectrum, analysisGrain

    # --- Interval-Class tension score on UNIQUE Pitch Classes ---
    score = 0
    n_pairs = 0
    if n_valid_pc >= 2
        for p from 1 to n_valid_pc - 1
            for q from p + 1 to n_valid_pc
                raw_iv = abs(pc_set[p] - pc_set[q]) mod 12
                if raw_iv > 6
                    raw_iv = 12 - raw_iv
                endif
                score += ic_weight[raw_iv]
                n_pairs += 1
            endfor
        endfor
    endif
    if n_pairs > 0
        score = score / n_pairs
    endif

    # --- Render grain: preserve original channel count ---
    selectObject: original
    Extract part: srcStart, srcEnd, "Hanning", 1, "no"
    grain = selected("Sound")

    grainCount += 1
    grainIDs#[grainCount] = grain
    grainScore#[grainCount] = score
    grainDurs#[grainCount] = gDur

    if grainCount mod 25 = 0 or grainCount = num_grains
        appendInfoLine: "  Grain ", grainCount, "/", num_grains,
            ..."  score=", fixed$(score, 3), "  PCs=", n_valid_pc
    endif
endfor

appendInfoLine: "Analysed ", grainCount, " grains"
appendInfoLine: ""
appendInfoLine: "Sorting..."

# ============================================================
# === Sort Grains by Dissonance Score ========================
# ============================================================
# Insertion sort — stable, compact, fine for <=500 grains
for i from 2 to grainCount
    keyScore = grainScore#[i]
    keyID    = grainIDs#[i]
    keyDur   = grainDurs#[i]
    j = i - 1

    if sort_direction = 1
        # Descending: highest dissonance first (Chaos -> Clarity)
        while j >= 1 and grainScore#[j] < keyScore
            grainScore#[j+1] = grainScore#[j]
            grainIDs#[j+1]   = grainIDs#[j]
            grainDurs#[j+1]  = grainDurs#[j]
            j -= 1
        endwhile
    else
        # Ascending: lowest dissonance first (Clarity -> Chaos)
        while j >= 1 and grainScore#[j] > keyScore
            grainScore#[j+1] = grainScore#[j]
            grainIDs#[j+1]   = grainIDs#[j]
            grainDurs#[j+1]  = grainDurs#[j]
            j -= 1
        endwhile
    endif

    grainScore#[j+1] = keyScore
    grainIDs#[j+1]   = keyID
    grainDurs#[j+1]  = keyDur
endfor

if sort_direction = 1
    appendInfoLine: "Sorted: Chaos -> Clarity"
else
    appendInfoLine: "Sorted: Clarity -> Chaos"
endif

# ============================================================
# === Assemble Sorted Grains in Deterministic Object Order ====
# ============================================================
appendInfoLine: ""
appendInfoLine: "Assembling sorted output..."

gap_dur = gap_between_grains_ms / 1000
maxConcatObjects = grainCount * 2
concatIDs# = zero# (maxConcatObjects)
concatCount = 0

# Fresh objects are created in the exact desired timeline order. Praat's
# Concatenate follows Object-list creation order, so one final concatenate is
# both faster and deterministic.
for i from 1 to grainCount
    selectObject: grainIDs#[i]
    item = Copy: "ht_item_" + string$(i)
    concatCount += 1
    concatIDs#[concatCount] = item

    if gap_dur > 0 and i < grainCount
        gapItem = Create Sound from formula: "ht_gap_" + string$(i), num_channels, 0, gap_dur, sample_rate, "0"
        concatCount += 1
        concatIDs#[concatCount] = gapItem
    endif
endfor

selectObject: concatIDs#[1]
for c from 2 to concatCount
    plusObject: concatIDs#[c]
endfor
Concatenate
temp_snd = selected("Sound")

# Cleanup fresh assembly items and original render grains.
for c from 1 to concatCount
    removeObject: concatIDs#[c]
endfor
for i from 1 to grainCount
    removeObject: grainIDs#[i]
endfor

# Finalize output
selectObject: temp_snd
outputPeak = Get absolute extremum: 0, 0, "Sinc70"
if outputPeak > 0
    Scale peak: 0.9
endif
out_dur = Get total duration
edgeFade = min(0.02, out_dur / 4)
if edgeFade > 0
    Fade in: 0, 0, edgeFade, "yes"
    Fade out: 0, out_dur - edgeFade, edgeFade, "yes"
endif
Copy: sound_name$ + "_HTsorted_" + preset_name$
result = selected("Sound")
resultName$ = selected$("Sound")
removeObject: temp_snd, analysisSource

# ============================================================
# === Compute Statistics =====================================
# ============================================================
selectObject: result
output_duration = Get total duration

minScore = grainScore#[1]
maxScore = grainScore#[1]
sumScore = 0
n_high   = 0
n_med    = 0
n_low    = 0

for i from 1 to grainCount
    s = grainScore#[i]
    sumScore += s
    if s < minScore
        minScore = s
    endif
    if s > maxScore
        maxScore = s
    endif
    if s >= 0.75
        n_high += 1
    elsif s >= 0.35
        n_med += 1
    else
        n_low += 1
    endif
endfor
mean_score = sumScore / grainCount

# ============================================================
# === Visualization ==========================================
# ============================================================
if draw_visualization and grainCount > 0
    Erase all
    Select outer viewport: 0, 8, 0, 6.45

    if sort_direction = 1
        sortLabel$ = "Chaos -> Clarity"
    else
        sortLabel$ = "Clarity -> Chaos"
    endif

    # Escape underscores because Praat Picture text treats them as markup.
    vizName$ = replace$(sound_name$, "_", "\_ ", 0)

    # Shared waveform amplitude scale: comparison now reflects real level.
    selectObject: original
    vizInPeak = Get absolute extremum: 0, 0, "None"
    selectObject: result
    vizOutPeak = Get absolute extremum: 0, 0, "None"
    vizAmp = max(vizInPeak, vizOutPeak)
    if vizAmp < 1e-12
        vizAmp = 1
    endif
    vizAmp *= 1.05

    # --- Library-standard title block -----------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Harmonic Tension Sorted Grains v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ...vizName$ + " | " + preset_name$ + " | " + sortLabel$
        ...+ " | " + string$(grainCount) + " grains | " + fixed$(output_duration, 2) + " s"

    # --- Original waveform ---------------------------------
    Select outer viewport: 0, 8, 0.60, 1.45
    Select inner viewport: 0.60, 7.70, 0.65, 1.40
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    # --- Sorted output waveform ----------------------------
    Select outer viewport: 0, 8, 1.50, 2.35
    Select inner viewport: 0.60, 7.70, 1.55, 2.30
    selectObject: result
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, -vizAmp, vizAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Sorted"
    Text bottom: "yes", "Time (s)"

    # -------------------------------------------------------
    # --- Sorted tension trajectory -------------------------
    # -------------------------------------------------------
    Select outer viewport: 0, 8, 2.48, 4.38
    Select inner viewport: 0.60, 7.70, 2.60, 4.25
    yLo = 0
    yHi = 1.05
    Axes: 0, grainCount + 1, yLo, yHi

    Paint rectangle: "{0.97, 0.97, 0.97}", 0, grainCount + 1, yLo, yHi
    Paint rectangle: "{0.91, 0.96, 0.91}", 0, grainCount + 1, 0, 0.35
    Paint rectangle: "{0.98, 0.95, 0.86}", 0, grainCount + 1, 0.35, 0.75
    Paint rectangle: "{0.98, 0.90, 0.89}", 0, grainCount + 1, 0.75, yHi

    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    Draw line: 0, 0.35, grainCount + 1, 0.35
    Draw line: 0, 0.75, grainCount + 1, 0.75
    Solid line

    # Semantic class colours: consonant / medium / high tension.
    for i from 1 to grainCount
        s = grainScore#[i]
        if s < 0.35
            barColor$ = "{0.35, 0.60, 0.40}"
        elsif s < 0.75
            barColor$ = "{0.80, 0.60, 0.20}"
        else
            barColor$ = "{0.78, 0.28, 0.22}"
        endif
        Paint rectangle: barColor$, i - 0.8, i - 0.2, 0, s
    endfor

    Colour: "{0.25, 0.25, 0.35}"
    Line width: 1.7
    for i from 2 to grainCount
        Draw line: i - 1.5, grainScore#[i-1], i - 0.5, grainScore#[i]
    endfor
    Line width: 1

    Colour: "{0.35, 0.35, 0.50}"
    Dotted line
    Draw line: 0, mean_score, grainCount + 1, mean_score
    Solid line

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.1, "yes", "yes", "no"
    Marks bottom every: 1, max(1, round(grainCount / 8)), "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Tension score"
    Text bottom: "yes", "Grain # (sorted order)"

    Font size: 6
    labelX = grainCount + 0.70
    Colour: "{0.35, 0.60, 0.40}"
    Text: labelX, "right", 0.17, "half", "Consonant"
    Colour: "{0.80, 0.60, 0.20}"
    Text: labelX, "right", 0.55, "half", "Medium"
    Colour: "{0.78, 0.28, 0.22}"
    Text: labelX, "right", 0.88, "half", "High"

    Colour: "{0.35, 0.35, 0.50}"
    if mean_score > 0 and mean_score < 1.05
        Text: 1.2, "left", min(mean_score + 0.035, 1.02), "half",
            ..."mean=" + fixed$(mean_score, 3)
    endif

    # -------------------------------------------------------
    # --- Tension distribution ------------------------------
    # -------------------------------------------------------
    Select outer viewport: 0, 4, 4.55, 5.75
    Select inner viewport: 0.60, 3.85, 4.67, 5.62

    numBins  = 10
    binWidth = 1.0 / numBins
    maxBinH  = 0
    for bin from 1 to numBins
        histCount[bin] = 0
    endfor
    for i from 1 to grainCount
        binIdx = floor(grainScore#[i] / binWidth) + 1
        if binIdx < 1
            binIdx = 1
        endif
        if binIdx > numBins
            binIdx = numBins
        endif
        histCount[binIdx] += 1
        if histCount[binIdx] > maxBinH
            maxBinH = histCount[binIdx]
        endif
    endfor
    if maxBinH < 1
        maxBinH = 1
    endif

    Axes: 0, 1, 0, maxBinH * 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, maxBinH * 1.15
    for bin from 1 to numBins
        hbLo = (bin - 1) * binWidth
        hbHi = bin * binWidth - binWidth * 0.06
        hbMid = (hbLo + hbHi) / 2
        if hbMid < 0.35
            hColor$ = "{0.35, 0.60, 0.40}"
        elsif hbMid < 0.75
            hColor$ = "{0.80, 0.60, 0.20}"
        else
            hColor$ = "{0.78, 0.28, 0.22}"
        endif
        Paint rectangle: hColor$, hbLo, hbHi, 0, histCount[bin]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks bottom every: 1, 0.2, "yes", "yes", "no"
    Text left: "yes", "Count"
    Text bottom: "yes", "Tension score"
    Text top: "no", "Distribution"

    # -------------------------------------------------------
    # --- Output spectrogram --------------------------------
    # -------------------------------------------------------
    Select outer viewport: 4, 8, 4.55, 5.75
    Select inner viewport: 4.45, 7.70, 4.67, 5.62
    selectObject: result
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
    spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: spectrogram
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Sorted output spectrum"

    # -------------------------------------------------------
    # --- Library-standard summary strip --------------------
    # -------------------------------------------------------
    Select outer viewport: 0, 8, 5.90, 6.40
    Select inner viewport: 0.60, 7.70, 5.93, 6.37
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.5, "centre", 0.68, "half",
        ..."##Grains## " + string$(grainCount)
        ...+ "  |  ##Range## " + fixed$(minScore, 3) + "-" + fixed$(maxScore, 3)
        ...+ "  |  ##Mean## " + fixed$(mean_score, 3)
        ...+ "  |  ##Analysis## " + fixed$(min_frequency_Hz, 0) + "-" + fixed$(vizMaxHz, 0) + " Hz"
    Text: 0.5, "centre", 0.28, "half",
        ..."High >=0.75: " + string$(n_high) + " (" + fixed$(100*n_high/grainCount, 0) + "%)"
        ...+ "  |  Medium: " + string$(n_med) + " (" + fixed$(100*n_med/grainCount, 0) + "%)"
        ...+ "  |  Consonant <0.35: " + string$(n_low) + " (" + fixed$(100*n_low/grainCount, 0) + "%)"

    # Critical for reliable Picture export / clipboard copy.
    Select outer viewport: 0, 8, 0, 6.45
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# === Final Info =============================================
# ============================================================
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created:      ", resultName$
appendInfoLine: "Grains:       ", grainCount
appendInfoLine: "Score range:  ", fixed$(minScore, 3), " - ", fixed$(maxScore, 3)
appendInfoLine: "Mean tension: ", fixed$(mean_score, 3)
appendInfoLine: "High  (>=0.75): ", n_high, " (", fixed$(100*n_high/grainCount, 1), " %)"
appendInfoLine: "Medium (0.35-0.75): ", n_med, " (", fixed$(100*n_med/grainCount, 1), " %)"
appendInfoLine: "Consonant (<0.35):  ", n_low, " (", fixed$(100*n_low/grainCount, 1), " %)"
appendInfoLine: "Output dur:   ", fixed$(output_duration, 2), " s"

# ============================================================
# === Play ===================================================
# ============================================================
if play_result
    selectObject: result
    Play
endif

selectObject: result
