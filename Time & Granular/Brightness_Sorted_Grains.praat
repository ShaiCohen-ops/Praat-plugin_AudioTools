# ============================================================
# Praat AudioTools - Brightness_Sorted_Grains.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brightness Sorted Grains - extracts grains from audio and
#   sorts them by spectral centroid (brightness) before
#   concatenation. Creates spectral sweep effects from dark
#   to bright or bright to dark.
#
# Algorithmic notes:
#   - Grain extraction: random zero-based source offsets, converted to the
#     Sound's absolute time domain for Extract part.
#   - Brightness measurement: spectral centroid (centre of gravity of the
#     Spectrum object, exponent 2 = power weighting).
#   - Spectral exaggeration: source-adaptive pivot. Grains above the pivot
#     receive extra energy above their own centroid; grains below the pivot
#     receive extra energy below their own centroid. Brightness is then
#     measured again from the processed Spectrum before sorting.
#   - Gain scatter: zero-mean Gaussian dB gain, applied after equal-peak
#     normalization. This replaces the mislabeled/non-effective v0.3
#     "Pitch scatter" control; no pitch shifting is claimed.
#   - Sort: O(N^2), acceptable for the hard limit of 500 grains.
#   - Concatenation: ordered output copies + one Concatenate pass.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4.1:
#   Visualization only - DSP is unchanged from v0.4.
#   - Aligned to the current Praat AudioTools visual language:
#     Source -> Brightness sort map -> Output -> Summary.
#   - Replaced the generic parameter-report / overlay layout with a
#     signature process map. For every grain, a neutral stem links the
#     pre-exaggeration centroid to the measured post-processing centroid;
#     the lower ribbon shows final concatenation order, with colour =
#     brightness and cell width = grain duration.
#   - Sanitized underscores in display names to avoid Praat subscripts.
#   - Colour has one semantic role in the process map: spectral brightness.
#   - Kept Show_spectrograms as a visual option: when enabled, the Output
#     panel shows the result spectrogram; otherwise it shows the waveform.
#
# Changelog v0.4:
#   DSP / semantics / performance:
#   - FIXED non-zero Sound time domains: random grain positions are stored
#     as zero-based offsets but extraction uses sourceStart + offset.
#   - Brightness after spectral exaggeration is now RE-MEASURED from the
#     processed Spectrum instead of being faked with x1.3 / x0.7 factors.
#   - Spectral exaggeration is source-adaptive: the mean valid centroid of
#     the generated grain set is used as a brightness pivot. Brighter grains
#     are boosted above their own centroid; darker grains below it.
#   - FIXED reverse-grain bookkeeping: reversing a grain does not change its
#     magnitude spectrum, so it no longer multiplies brightness by 0.9.
#   - Renamed misleading Pitch_scatter to Gain_scatter_dB. The old control
#     never shifted pitch; it uniformly scaled the whole Spectrum. v0.4
#     applies a true zero-mean random gain in dB AFTER peak normalization,
#     so the control is now both correctly named and audibly effective.
#   - All grains use the same base peak target before gain scatter, removing
#     the unintended brightness-to-loudness coupling of v0.3.
#   - Renamed Grain_overlap to Analysis_overlap: it controls the nominal
#     analysis hop used to derive grain count; source positions are random,
#     so it was never a literal overlap between extracted grains.
#   - FIXED unsorted brightness statistics: min/max are now computed over
#     all grains instead of assuming first/last are extrema.
#   - Replaced O(N^2) iterative output concatenation with one Concatenate:
#     output grain/gap copies are created in final order and joined once.
#   - Added validation for overlap, density, variation, gain scatter, gap,
#     minimum renderable grain duration, and silent-result normalization.
#   - Spectrogram ceiling now respects Nyquist.
#
# Changelog v0.3:
#   - CRITICAL FIX: Removed duplicate `=== Done ===` block at
#     end of script. v0.2 had two final-report sections (lines
#     572-606 in the original) — for grainCount > 0 the script
#     printed stats and called Play TWICE; for grainCount = 0
#     the second block referenced undefined variables and
#     would error. v0.3 has a single, conditional final report.
#   - Audio output is bit-identical to v0.2 for the same form
#     parameters AND same Praat RNG state — except Play runs
#     once instead of twice.
#   - Form syntax modernized: 5 `optionmenu X:` with colons
#     (Preset, Grain_size_mode, Window_type, Sort_direction,
#     Exaggeration_intensity).
#   - Dropped 8 decorative form lines (6 `comment === ... ===`
#     section dividers, 1 instructional, 1 inline parenthetical).
#     Form went from ~22 effective rows to 14.
#   - NEW: Show_spectrograms boolean form toggle (default OFF).
#     v0.2 always computed two `To Spectrogram` calls. Default
#     OFF skips them; ON puts side-by-side spectrograms in
#     Panel D (replacing the waveform comparison).
#   - Output filename now includes preset name suffix:
#     `<name>_brightness_sorted_<presetName>` (e.g.
#     `_brightness_sorted_DenseCloud`). v0.2 was just
#     `<name>_brightness_sorted`.
#   - Visualization rewritten to suite 8x8 standard (v0.2 was
#     8x6.7 with title + 2 waveforms + brightness bars + 2
#     spectrograms + stats line):
#       Title bar + metadata subtitle (preset, grain count,
#         brightness range, sort direction, gap, exaggeration)
#       Panel A (left, headline): brightness distribution —
#         PRESERVED v0.2 design (bars with dark blue -> bright
#         yellow gradient + red trend line)
#       Panel B (right, headline): parameter report — algorithm
#         explanation, settings, sort direction, exaggeration
#         intensity, gain-scatter clarification
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         blue = sorted, SHARED y-axis)
#       Panel D: full waveform comparison (gray = original,
#         blue = sorted, SHARED y-axis) OR side-by-side
#         spectrograms (when Show_spectrograms = ON)
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Fixed mono conversion bug
#   - Added presets
#   - Added visualization
#   - Improved sorting display
#   - Renamed for clarity
# ============================================================

form Brightness Sorted Grains v0.4
    optionmenu Preset: 1
        option Custom
        option Gentle Sweep (few grains)
        option Dense Cloud (many grains)
        option Micro Grains (short, fast)
        option Long Drones (slow evolution)
        option Extreme Sort (strong exaggeration)
    positive Grain_size_ms 150
    real Grain_size_variation_ms 50
    optionmenu Grain_size_mode: 1
        option Fixed
        option Random
    real Analysis_overlap 0.3
    real Density_factor 1.5
    real Gain_scatter_dB 1.0
    boolean Reverse_grains 0
    optionmenu Window_type: 2
        option Rectangular
        option Triangular
        option Parabolic
    boolean Sort_grains 1
    optionmenu Sort_direction: 1
        option Dark to bright
        option Bright to dark
    real Gap_between_grains_ms 50
    boolean Exaggerate_spectral 1
    optionmenu Exaggeration_intensity: 2
        option Subtle
        option Moderate
        option Strong
    boolean Show_spectrograms 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
presetName$ = "Custom"

if preset = 2
    # Gentle Sweep
    grain_size_ms = 200
    grain_size_variation_ms = 30
    grain_size_mode = 1
    analysis_overlap = 0.2
    density_factor = 0.8
    gain_scatter_dB = 0.5
    reverse_grains = 0
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 80
    exaggerate_spectral = 1
    exaggeration_intensity = 1
    presetName$ = "GentleSweep"
elsif preset = 3
    # Dense Cloud
    grain_size_ms = 100
    grain_size_variation_ms = 40
    grain_size_mode = 2
    analysis_overlap = 0.5
    density_factor = 2.5
    gain_scatter_dB = 1.5
    reverse_grains = 1
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 20
    exaggerate_spectral = 1
    exaggeration_intensity = 2
    presetName$ = "DenseCloud"
elsif preset = 4
    # Micro Grains
    grain_size_ms = 50
    grain_size_variation_ms = 20
    grain_size_mode = 2
    analysis_overlap = 0.4
    density_factor = 3.0
    gain_scatter_dB = 2.0
    reverse_grains = 0
    window_type = 3
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 10
    exaggerate_spectral = 0
    exaggeration_intensity = 2
    presetName$ = "MicroGrains"
elsif preset = 5
    # Long Drones
    grain_size_ms = 400
    grain_size_variation_ms = 100
    grain_size_mode = 2
    analysis_overlap = 0.6
    density_factor = 0.5
    gain_scatter_dB = 0.25
    reverse_grains = 0
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 150
    exaggerate_spectral = 1
    exaggeration_intensity = 1
    presetName$ = "LongDrones"
elsif preset = 6
    # Extreme Sort
    grain_size_ms = 120
    grain_size_variation_ms = 50
    grain_size_mode = 2
    analysis_overlap = 0.3
    density_factor = 2.0
    gain_scatter_dB = 2.5
    reverse_grains = 1
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 40
    exaggerate_spectral = 1
    exaggeration_intensity = 3
    presetName$ = "ExtremeSort"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sample_rate = Get sampling frequency
num_channels = Get number of channels

# === Convert to Mono ===
selectObject: original
if num_channels > 1
    Convert to mono
    sound = selected("Sound")
else
    Copy: "mono_temp"
    sound = selected("Sound")
endif

selectObject: sound
sourceStart = Get start time
sourceEnd = Get end time

# === Validate Parameters ===
if grain_size_ms <= 0
    removeObject: sound
    exitScript: "Grain size must be > 0 ms"
endif
if grain_size_variation_ms < 0
    removeObject: sound
    exitScript: "Grain size variation must be >= 0 ms"
endif
if analysis_overlap < 0 or analysis_overlap >= 1
    removeObject: sound
    exitScript: "Analysis overlap must be >= 0 and < 1"
endif
if density_factor <= 0
    removeObject: sound
    exitScript: "Density factor must be > 0"
endif
if gain_scatter_dB < 0
    removeObject: sound
    exitScript: "Gain scatter must be >= 0 dB"
endif
if gap_between_grains_ms < 0
    removeObject: sound
    exitScript: "Gap between grains must be >= 0 ms"
endif

if duration < grain_size_ms / 1000
    removeObject: sound
    exitScript: "Sound is shorter than grain size"
endif

if grain_size_mode = 2 and grain_size_variation_ms > grain_size_ms
    grain_size_variation_ms = grain_size_ms * 0.8
endif

# === Calculate Grain Parameters ===
base_grain_duration = grain_size_ms / 1000
minRenderableGrain = 2 / sample_rate
if base_grain_duration < minRenderableGrain
    removeObject: sound
    exitScript: "Grain size is shorter than two samples at this sampling rate"
endif

# Analysis_overlap controls only the nominal analysis hop used to derive
# the number of random grain draws. It is not an output crossfade.
hop_time = base_grain_duration * (1 - analysis_overlap)
num_grains = max(1, round((duration / hop_time) * density_factor))

# Limit grain count for performance
if num_grains > 500
    num_grains = 500
endif

# === Get Window Shape ===
if window_type = 1
    window_shape$ = "rectangular"
elsif window_type = 2
    window_shape$ = "triangular"
else
    window_shape$ = "parabolic"
endif

# === Get Exaggeration Factor ===
if exaggeration_intensity = 1
    spectral_boost = 1.2
    exaggerationLabel$ = "Subtle"
elsif exaggeration_intensity = 2
    spectral_boost = 1.5
    exaggerationLabel$ = "Moderate"
else
    spectral_boost = 2.0
    exaggerationLabel$ = "Strong"
endif

if sort_direction = 1
    sortLabel$ = "Dark -> Bright"
else
    sortLabel$ = "Bright -> Dark"
endif

# === Info ===
writeInfoLine: "=== Brightness Sorted Grains v0.4.1 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target grains: ", num_grains
appendInfoLine: "Grain size: ", grain_size_ms, " ms"
if grain_size_mode = 2
    appendInfoLine: "Size variation: +/- ", grain_size_variation_ms, " ms"
endif
appendInfoLine: "Analysis overlap: ", fixed$(analysis_overlap, 2), " | Density: ", fixed$(density_factor, 2)
appendInfoLine: "Gain scatter: ", fixed$(gain_scatter_dB, 2), " dB SD"
appendInfoLine: ""

# === Arrays ===
grainIDs# = zero#(num_grains)
grainBrightness# = zero#(num_grains)
grainOriginalBrightness# = zero#(num_grains)
grainDurations# = zero#(num_grains)
grainCount = 0

# === Generate Grains: pass 1 (extract + measure original brightness) ===
appendInfoLine: "Generating and analyzing grains..."

for i from 1 to num_grains
    if grain_size_mode = 1
        grain_duration = base_grain_duration
    else
        variation_seconds = (grain_size_variation_ms / 1000) * randomUniform(-1, 1)
        grain_duration = base_grain_duration + variation_seconds
        min_duration = max(minRenderableGrain, base_grain_duration * 0.3)
        max_duration = base_grain_duration * 2.0
        grain_duration = max(min_duration, min(max_duration, grain_duration))
    endif

    grain_duration = min(grain_duration, duration)
    max_start = max(0, duration - grain_duration)
    source_offset = 0
    if max_start > 0
        source_offset = randomUniform(0, max_start)
    endif
    extractStart = sourceStart + source_offset
    extractEnd = extractStart + grain_duration

    selectObject: sound
    Extract part: extractStart, extractEnd, window_shape$, 1, "no"
    grain = selected("Sound")

    selectObject: grain
    To Spectrum: "yes"
    spectrum = selected("Spectrum")
    centroid = Get centre of gravity: 2
    if centroid = undefined
        centroid = 0
    endif
    removeObject: spectrum

    grainCount += 1
    grainIDs#[grainCount] = grain
    grainOriginalBrightness#[grainCount] = centroid
    grainBrightness#[grainCount] = centroid
    grainDurations#[grainCount] = grain_duration
endfor

appendInfoLine: "Created ", grainCount, " grains"

# Source-adaptive brightness pivot (ignore silent / undefined-centroid grains).
brightnessSum = 0
brightnessValidCount = 0
for i from 1 to grainCount
    if grainOriginalBrightness#[i] > 0
        brightnessSum += grainOriginalBrightness#[i]
        brightnessValidCount += 1
    endif
endfor
if brightnessValidCount > 0
    brightnessPivot = brightnessSum / brightnessValidCount
else
    brightnessPivot = 0
endif
appendInfoLine: "Brightness pivot: ", fixed$(brightnessPivot, 0), " Hz"

# === Process grains: spectral exaggeration, reverse, level, gain scatter ===
for i from 1 to grainCount
    grain = grainIDs#[i]
    original_brightness = grainOriginalBrightness#[i]
    brightness = original_brightness

    # Reinforce each grain away from the source-adaptive pivot, then measure
    # the ACTUAL processed centroid. This keeps sorting physically grounded.
    if exaggerate_spectral and original_brightness > 0 and brightnessPivot > 0
        selectObject: grain
        To Spectrum: "yes"
        spectrum = selected("Spectrum")

        if original_brightness >= brightnessPivot
            Formula: "if x >= original_brightness then self * spectral_boost else self fi"
        else
            Formula: "if x <= original_brightness then self * spectral_boost else self fi"
        endif

        To Sound
        processed_grain = selected("Sound")
        removeObject: spectrum, grain
        grain = processed_grain
        grainIDs#[i] = grain

        # Re-measure after filtering.
        selectObject: grain
        To Spectrum: "yes"
        checkSpectrum = selected("Spectrum")
        processedCentroid = Get centre of gravity: 2
        if processedCentroid <> undefined
            brightness = processedCentroid
        endif
        removeObject: checkSpectrum
    endif

    # Reverse changes temporal direction, not magnitude-spectrum brightness.
    selectObject: grain
    if reverse_grains and randomUniform(0, 1) > 0.7
        Reverse
    endif

    # Normalize all non-silent grains to the same base peak so brightness is
    # not confounded with loudness. Gain scatter is applied AFTER this.
    selectObject: grain
    grainPeak = Get absolute extremum: 0, 0, "Sinc70"
    if grainPeak > 0
        Scale peak: 0.30
    endif

    if gain_scatter_dB > 0 and grainPeak > 0
        gainDB = randomGauss(0, gain_scatter_dB)
        maxGainDB = min(12, 3 * gain_scatter_dB)
        gainDB = min(maxGainDB, max(-maxGainDB, gainDB))
        gainFactor = 10 ^ (gainDB / 20)
        Formula: "self * gainFactor"
    endif

    grainBrightness#[i] = brightness
endfor

# === Sort Grains by Brightness ===
if sort_grains and grainCount > 1
    appendInfoLine: ""
    appendInfoLine: "Sorting by measured brightness..."
    
    # Bubble sort (simple, works fine for <500 grains)
    for i from 1 to grainCount
        for j from i + 1 to grainCount
            doSwap = 0
            if sort_direction = 1 and grainBrightness#[i] > grainBrightness#[j]
                doSwap = 1
            elsif sort_direction = 2 and grainBrightness#[i] < grainBrightness#[j]
                doSwap = 1
            endif
            
            if doSwap
                # Swap all arrays
                tempBrightness = grainBrightness#[i]
                grainBrightness#[i] = grainBrightness#[j]
                grainBrightness#[j] = tempBrightness
                
                tempOriginal = grainOriginalBrightness#[i]
                grainOriginalBrightness#[i] = grainOriginalBrightness#[j]
                grainOriginalBrightness#[j] = tempOriginal
                
                tempGrain = grainIDs#[i]
                grainIDs#[i] = grainIDs#[j]
                grainIDs#[j] = tempGrain
                
                tempDuration = grainDurations#[i]
                grainDurations#[i] = grainDurations#[j]
                grainDurations#[j] = tempDuration
            endif
        endfor
    endfor
    
    appendInfoLine: "Sorted: ", sortLabel$
endif

# === Concatenate Grains Efficiently ===
gap_duration = gap_between_grains_ms / 1000

if grainCount > 0
    appendInfoLine: ""
    appendInfoLine: "Concatenating..."

    # Create output parts in FINAL order. Praat concatenates selected Sounds
    # in Object-list order, so creation order guarantees the intended chain.
    maxParts = 2 * grainCount
    outputPartIDs# = zero#(maxParts)
    outputPartCount = 0

    for i from 1 to grainCount
        selectObject: grainIDs#[i]
        Copy: "ordered_grain_" + string$(i)
        outputPartCount += 1
        outputPartIDs#[outputPartCount] = selected("Sound")

        if gap_duration > 0 and i < grainCount
            Create Sound from formula: "grain_gap_" + string$(i), 1, 0, gap_duration, sample_rate, "0"
            outputPartCount += 1
            outputPartIDs#[outputPartCount] = selected("Sound")
        endif
    endfor

    selectObject: outputPartIDs#[1]
    for i from 2 to outputPartCount
        plusObject: outputPartIDs#[i]
    endfor
    Concatenate
    result = selected("Sound")
    Rename: sound_name$ + "_brightness_sorted_" + presetName$

    # Remove ordered output copies and source grains.
    for i from 1 to outputPartCount
        removeObject: outputPartIDs#[i]
    endfor
    for i from 1 to grainCount
        removeObject: grainIDs#[i]
    endfor

    # Safe final scaling.
    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "Sinc70"
    if resultPeak > 0
        Scale peak: 0.9
    endif
    output_duration = Get total duration

    # Correct min/max statistics regardless of sort state.
    minBrightness = grainBrightness#[1]
    maxBrightness = grainBrightness#[1]
    for i from 2 to grainCount
        if grainBrightness#[i] < minBrightness
            minBrightness = grainBrightness#[i]
        endif
        if grainBrightness#[i] > maxBrightness
            maxBrightness = grainBrightness#[i]
        endif
    endfor
endif

# Cleanup mono copy
removeObject: sound

# ============================================================
# VISUALIZATION  (current Praat AudioTools suite styling)
# Source -> signature Brightness sort map -> Output -> Summary.
# The central map directly shows the transformation law:
#   stem = centroid before -> after spectral exaggeration,
#   colour = measured brightness,
#   lower ribbon = final concatenation order,
#   cell width = grain duration.
# ============================================================
if draw_visualization and grainCount > 0
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.10
    Black
    Plain line

    displayName$ = replace$(sound_name$, "_", " ", 0)

    # Mono, zero-based source display copy.
    selectObject: original
    if num_channels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz orig"
    endif
    selectObject: vizOrig
    vizOrigStart = Get start time
    Shift times by: -vizOrigStart

    # Zero-based result display copy.
    selectObject: result
    vizResult = Copy: "viz result"
    selectObject: vizResult
    vizResultStart = Get start time
    Shift times by: -vizResultStart

    # Shared waveform amplitude scale.
    selectObject: vizOrig
    origPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizResult
    outPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = origPeak
    if outPeak > sharedPeak
        sharedPeak = outPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = 1.15 * sharedPeak

    # Brightness bounds include BOTH pre- and post-exaggeration centroids.
    minMapB = grainBrightness#[1]
    maxMapB = grainBrightness#[1]
    for i from 1 to grainCount
        if grainBrightness#[i] < minMapB
            minMapB = grainBrightness#[i]
        endif
        if grainBrightness#[i] > maxMapB
            maxMapB = grainBrightness#[i]
        endif
        if grainOriginalBrightness#[i] > 0
            if grainOriginalBrightness#[i] < minMapB
                minMapB = grainOriginalBrightness#[i]
            endif
            if grainOriginalBrightness#[i] > maxMapB
                maxMapB = grainOriginalBrightness#[i]
            endif
        endif
    endfor
    if maxMapB <= minMapB
        maxMapB = minMapB + 1
    endif
    bSpan = maxMapB - minMapB
    mapY0 = max(0, minMapB - 0.08 * bSpan)
    mapY1 = maxMapB + 0.12 * bSpan

    # Total grain duration, excluding gaps, for proportional ribbon widths.
    totalGrainDur = 0
    for i from 1 to grainCount
        totalGrainDur += grainDurations#[i]
    endfor
    if totalGrainDur <= 0
        totalGrainDur = 1
    endif

    # Optional result spectrogram for the Output panel only.
    specMaxHz = min(5000, 0.95 * sample_rate / 2)
    if show_spectrograms
        selectObject: vizResult
        resSpec = To Spectrogram: 0.03, specMaxHz, 0.01, 20, "Gaussian"
    endif

    # ----------------------------------------------------------
    # TITLE / SUBTITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Brightness Sorted Grains##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.30, "half", "Brightness Sorted Grains.praat  |  " + displayName$ + "  |  spectral-centroid grain ordering"

    # ----------------------------------------------------------
    # SOURCE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.65, 1.90
    Select inner viewport: 0.55, 7.75, 0.82, 1.78
    Axes: 0, duration, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, -sharedAmp, sharedAmp
    selectObject: vizOrig
    Colour: "{0.58, 0.58, 0.62}"
    Draw: 0, duration, -sharedAmp, sharedAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Source##"
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Axes: 0, duration, -sharedAmp, sharedAmp
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01 * duration, "left", 0.82 * sharedAmp, "half", string$(grainCount) + " grains sampled  |  grain size " + fixed$(grain_size_ms, 0) + " ms  |  density " + fixed$(density_factor, 2)

    # ----------------------------------------------------------
    # BRIGHTNESS SORT MAP - signature process view
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 2.05, 4.55
    Select inner viewport: 0.55, 7.75, 2.25, 4.40
    Axes: 0, grainCount + 1, mapY0, mapY1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, grainCount + 1, mapY0, mapY1

    # Light horizontal guides.
    Colour: "{0.86, 0.86, 0.89}"
    Dotted line
    for q from 1 to 3
        gy = mapY0 + q * (mapY1 - mapY0) / 4
        Draw line: 0, gy, grainCount + 1, gy
    endfor
    Solid line

    # Each stem shows the spectral exaggeration displacement for one grain.
    # Grey endpoint = pre-exaggeration centroid; coloured endpoint = measured
    # post-processing centroid. Colour is used ONLY for brightness here.
    for i from 1 to grainCount
        bNow = grainBrightness#[i]
        bBefore = grainOriginalBrightness#[i]
        if bBefore <= 0
            bBefore = bNow
        endif
        normalizedB = (bNow - minBrightness) / max(1, maxBrightness - minBrightness)
        if normalizedB < 0
            normalizedB = 0
        elsif normalizedB > 1
            normalizedB = 1
        endif
        rr = 0.18 + 0.77 * normalizedB
        gg = 0.32 + 0.36 * normalizedB
        bb = 0.78 - 0.60 * normalizedB
        brightCol$ = "{" + fixed$(rr, 2) + ", " + fixed$(gg, 2) + ", " + fixed$(bb, 2) + "}"

        Colour: "{0.68, 0.68, 0.71}"
        Line width: 0.8
        Draw line: i, bBefore, i, bNow
        Paint circle: "{0.68, 0.68, 0.71}", i, bBefore, 0.035
        Paint circle: brightCol$, i, bNow, 0.050
    endfor
    Line width: 1

    # The lower ribbon is final output order. Cell width is proportional to
    # grain duration while hue follows the same brightness scale as above.
    ribbonY0 = mapY0 + 0.025 * (mapY1 - mapY0)
    ribbonY1 = mapY0 + 0.105 * (mapY1 - mapY0)
    cursorX = 0.5
    ribbonSpan = grainCount
    for i from 1 to grainCount
        normalizedB = (grainBrightness#[i] - minBrightness) / max(1, maxBrightness - minBrightness)
        if normalizedB < 0
            normalizedB = 0
        elsif normalizedB > 1
            normalizedB = 1
        endif
        rr = 0.18 + 0.77 * normalizedB
        gg = 0.32 + 0.36 * normalizedB
        bb = 0.78 - 0.60 * normalizedB
        brightCol$ = "{" + fixed$(rr, 2) + ", " + fixed$(gg, 2) + ", " + fixed$(bb, 2) + "}"
        cellW = ribbonSpan * grainDurations#[i] / totalGrainDur
        Paint rectangle: brightCol$, cursorX, cursorX + cellW, ribbonY0, ribbonY1
        cursorX += cellW
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "##Brightness sort map##"
    Font size: 6
    Text left: "yes", "Centroid (Hz)"
    Text bottom: "yes", "Grain (final order)"
    Axes: 0, grainCount + 1, mapY0, mapY1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.7, "left", mapY1 - 0.055 * (mapY1 - mapY0), "half", "grey dot = before exaggeration  |  coloured dot = measured brightness  |  ribbon: colour = brightness, width = duration"
    if sort_grains
        Text: grainCount + 0.3, "right", mapY0 + 0.15 * (mapY1 - mapY0), "half", sortLabel$
    else
        Text: grainCount + 0.3, "right", mapY0 + 0.15 * (mapY1 - mapY0), "half", "sorting OFF"
    endif

    # ----------------------------------------------------------
    # OUTPUT
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.70, 5.95
    Select inner viewport: 0.55, 7.75, 4.87, 5.83

    if show_spectrograms
        selectObject: resSpec
        Paint: 0, 0, 0, specMaxHz, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "yes", "##Output##"
        Font size: 6
        Text left: "yes", "Frequency (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        Axes: 0, output_duration, -sharedAmp, sharedAmp
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, output_duration, -sharedAmp, sharedAmp
        selectObject: vizResult
        Colour: "{0.48, 0.33, 0.72}"
        Draw: 0, output_duration, -sharedAmp, sharedAmp, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "yes", "##Output##"
        Font size: 6
        Text left: "yes", "Amplitude"
        Text bottom: "yes", "Time (s)"
    endif

    # Output note inside the panel, away from the frame/title.
    if not show_spectrograms
        Axes: 0, output_duration, -sharedAmp, sharedAmp
        Colour: "{0.28, 0.28, 0.28}"
        Text: 0.01 * output_duration, "left", 0.82 * sharedAmp, "half", sortLabel$ + "  |  gaps " + fixed$(gap_between_grains_ms, 0) + " ms  |  duration " + fixed$(duration, 2) + " -> " + fixed$(output_duration, 2) + " s"
    endif

    # ----------------------------------------------------------
    # SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.10, 7.05
    Select inner viewport: 0.30, 7.80, 6.17, 6.98
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    if exaggerate_spectral
        exaggerationSummary$ = exaggerationLabel$ + " x" + fixed$(spectral_boost, 2)
    else
        exaggerationSummary$ = "OFF"
    endif
    if reverse_grains
        reverseSummary$ = "30% random"
    else
        reverseSummary$ = "OFF"
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.49, "half", presetName$ + "  |  " + string$(grainCount) + " grains  |  brightness " + fixed$(minBrightness, 0) + "-" + fixed$(maxBrightness, 0) + " Hz  |  " + sortLabel$ + "  |  exaggeration " + exaggerationSummary$
    Text: 0.02, "left", 0.18, "half", "Grain " + fixed$(grain_size_ms, 0) + " ms  |  variation +/-" + fixed$(grain_size_variation_ms, 0) + " ms  |  gap " + fixed$(gap_between_grains_ms, 0) + " ms  |  gain scatter " + fixed$(gain_scatter_dB, 2) + " dB  |  reverse " + reverseSummary$ + "  |  duration " + fixed$(duration, 2) + " -> " + fixed$(output_duration, 2) + " s"

    Font size: 10
    Colour: "Black"
    Line width: 1

    removeObject: vizOrig, vizResult
    if show_spectrograms
        removeObject: resSpec
    endif
endif

# ============================================================
# FINAL REPORT  (single block — fixes v0.2's duplicate)
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Done ==="

if grainCount > 0
    selectObject: result
    appendInfoLine: "Created: ", selected$("Sound")
    appendInfoLine: "Grains: ", grainCount
    appendInfoLine: "Brightness range: ", fixed$(minBrightness, 0), "-", fixed$(maxBrightness, 0), " Hz"
    appendInfoLine: "Duration: ", fixed$(output_duration, 2), " s"
    
    if play_result
        Play
    endif
    
    selectObject: result
else
    appendInfoLine: "No grains could be created with current parameters"
endif
