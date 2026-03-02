# ============================================================
# Praat AudioTools - Harmonic_Tension_Sorted_Grains.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
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
#   Dissonance weights (IC = Interval Class):
#     IC 1 (m2/M7) = 1.00  HIGH TENSION
#     IC 6 (TT)    = 1.00  HIGH TENSION
#     IC 2 (M2/m7) = 0.50  MEDIUM
#     IC 3 (m3/M6) = 0.50  MEDIUM
#     IC 4 (M3/m6) = 0.10  CONSONANT
#     IC 5 (P4/P5) = 0.10  CONSONANT
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

form Harmonic Tension Sorted Grains
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
    positive Grain_size_variation_ms 20
    optionmenu Grain_size_mode 1
        option Fixed
        option Random

    comment === Density ===
    real    Grain_overlap_(0-0.8)  0.3
    positive Max_grains            200

    comment === Spectral Analysis ===
    positive Number_of_peaks   4
    positive Max_frequency_Hz  5000

    comment === Sorting ===
    optionmenu Sort_direction 1
        option Chaos to Clarity  (descending dissonance)
        option Clarity to Chaos  (ascending dissonance)
    positive Gap_between_grains_ms 10

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
    grain_overlap          = 0.3
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
    grain_overlap          = 0.5
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
    grain_overlap          = 0.2
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
    grain_overlap          = 0.6
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
    grain_overlap          = 0.1
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
    grain_overlap          = 0.7
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
    grain_overlap          = 0.3
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
    grain_overlap          = 0.0
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
duration     = Get total duration
sample_rate  = Get sampling frequency
num_channels = Get number of channels

# === Convert to Mono (keep original for visualization) ===
if num_channels > 1
    selectObject: original
    Convert to mono
    source = selected("Sound")
else
    selectObject: original
    Copy: "ht_src_temp"
    source = selected("Sound")
endif

# === Validate ===
grain_dur_base = grain_size_ms / 1000
if duration < grain_dur_base
    removeObject: source
    exitScript: "Sound is shorter than grain size"
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
# === Frequency Bands for Fast Peak Finding ==================
# ============================================================
# Instead of iterating every spectrum bin (slow),
# we call Get frequency of maximum once per band (fast).
# Bands are logarithmically spaced across the audible range.
band_lo[1] =   80
band_hi[1] =  300
band_lo[2] =  300
band_hi[2] =  800
band_lo[3] =  800
band_hi[3] = 2000
band_lo[4] = 2000
band_hi[4] = 4500
band_lo[5] = 1000
band_hi[5] = max_frequency_Hz

# ============================================================
# === Calculate Grain Count ==================================
# ============================================================
hop_time = grain_dur_base * (1 - grain_overlap)
if hop_time < 0.005
    hop_time = 0.005
endif
num_grains = round(duration / hop_time)
if num_grains > max_grains
    num_grains = max_grains
endif
if num_grains < 2
    removeObject: source
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
appendInfoLine: "Grains: ", num_grains, " | Size: ", grain_size_ms, " ms | Peaks: ", number_of_peaks
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
        gDur = max(grain_dur_base * 0.3, min(grain_dur_base * 2.0, gDur))
    else
        gDur = grain_dur_base
    endif

    # --- Source position (random scatter across full file) ---
    maxStart = duration - gDur
    if maxStart < 0
        maxStart = 0
    endif
    srcPos = randomUniform(0, maxStart)

    if srcPos + gDur > duration
        gDur = duration - srcPos
    endif
    if gDur < 0.01
        gDur = 0.01
    endif

    # --- Extract grain with Hanning window ---
    selectObject: source
    Extract part: srcPos, srcPos + gDur, "Hanning", 1, "no"
    grain = selected("Sound")

    # --- Fast Spectral Analysis via Ltas ---
    # Ltas supports Get frequency of maximum: fLo, fHi, "Parabolic"
    # One native call per band — no bin loop needed.
    selectObject: grain
    To Ltas: 100
    ltas = selected("Ltas")

    n_valid_pc = 0
    for b from 1 to number_of_peaks
        bIdx = b
        if bIdx > 5
            bIdx = 5
        endif
        bLo = band_lo[bIdx]
        bHi = band_hi[bIdx]
        if bHi > max_frequency_Hz
            bHi = max_frequency_Hz
        endif
        if bLo >= bHi
            bLo = bHi * 0.5
        endif

        selectObject: ltas
        peak_hz = Get frequency of maximum: bLo, bHi, "Parabolic"

        if peak_hz > 20 and peak_hz <= max_frequency_Hz
            # Hz -> MIDI -> Pitch Class
            midi_val = 69 + 12 * log2(peak_hz / 440)
            pc = round(midi_val) mod 12
            if pc < 0
                pc = pc + 12
            endif
            n_valid_pc += 1
            pc_set[n_valid_pc] = pc
        endif
    endfor

    removeObject: ltas

    # --- Dissonance Score ---
    score    = 0
    n_pairs  = 0
    for p from 1 to n_valid_pc - 1
        for q from p + 1 to n_valid_pc
            raw_iv = abs(pc_set[p] - pc_set[q]) mod 12
            if raw_iv > 6
                raw_iv = 12 - raw_iv
            endif
            score   += ic_weight[raw_iv]
            n_pairs += 1
        endfor
    endfor
    if n_pairs > 0
        score = score / n_pairs
    endif

    grainCount              += 1
    grainIDs#[grainCount]    = grain
    grainScore#[grainCount]  = score
    grainDurs#[grainCount]   = gDur

    if grainCount mod 25 = 0 or grainCount = num_grains
        appendInfoLine: "  Grain ", grainCount, "/", num_grains,
            ..."  score=", fixed$(score, 3)
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
# === Concatenate Sorted Grains (fast, like Brightness) ======
# ============================================================
appendInfoLine: ""
appendInfoLine: "Concatenating..."

gap_dur = gap_between_grains_ms / 1000
if gap_dur > 0
    silence = Create Sound from formula: "gap", 1, 0, gap_dur, sample_rate, "0"
endif

selectObject: grainIDs#[1]
Copy: "ht_concat_temp"
temp_snd = selected("Sound")

for i from 2 to grainCount
    if gap_dur > 0
        selectObject: temp_snd, silence
        Concatenate
        with_gap = selected("Sound")
        selectObject: with_gap, grainIDs#[i]
        Concatenate
        new_temp = selected("Sound")
        removeObject: temp_snd, with_gap
        temp_snd = new_temp
    else
        selectObject: temp_snd, grainIDs#[i]
        Concatenate
        new_temp = selected("Sound")
        removeObject: temp_snd
        temp_snd = new_temp
    endif
endfor

if gap_dur > 0
    removeObject: silence
endif

# Cleanup grain objects
for i from 1 to grainCount
    removeObject: grainIDs#[i]
endfor

# Finalize output
selectObject: temp_snd
Scale peak: 0.9
Fade in: 0, 0, 0.02, "yes"
out_dur = Get total duration
if out_dur > 0.05
    Fade out: 0, out_dur - 0.03, 0.03, "yes"
endif
Copy: "Set_Sorted_Grains"
result = selected("Sound")
removeObject: temp_snd
removeObject: source

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

    # --- Title ---
    Select outer viewport: 0, 8, 0.05, 0.55
    Font size: 13
    Colour: "Black"
    if sort_direction = 1
        sortLabel$ = "Chaos -> Clarity"
    else
        sortLabel$ = "Clarity -> Chaos"
    endif
    Text: 0.5, "centre", 0.5, "half",
        ..."Harmonic Tension:  " + sound_name$ + "     [" + sortLabel$ + "]     preset: " + preset_name$

    # --- Original Waveform ---
    Select outer viewport: 0, 8, 0.6, 1.65
    Select inner viewport: 0.6, 7.6, 0.7, 1.6
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    # --- Sorted Output Waveform ---
    Select outer viewport: 0, 8, 1.7, 2.75
    Select inner viewport: 0.6, 7.6, 1.75, 2.7
    selectObject: result
    Colour: "{0.25, 0.50, 0.85}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Sorted"
    Text bottom: "yes", "Time (s)"

    # -------------------------------------------------------
    # --- Tension Curve (main panel) ------------------------
    # -------------------------------------------------------
    Select outer viewport: 0, 8, 2.85, 4.65
    Select inner viewport: 0.6, 7.6, 2.95, 4.6

    scoreRange = maxScore - minScore
    if scoreRange < 0.05
        scoreRange = 0.05
    endif
    yLo = max(0, minScore - scoreRange * 0.10)
    yHi = maxScore + scoreRange * 0.15

    Axes: 0, grainCount + 1, yLo, yHi

    # Background
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, grainCount + 1, yLo, yHi

    # Zone shading: consonant (green), medium (yellow), tension (red)
    consHi = min(0.35, yHi)
    if consHi > yLo
        Paint rectangle: "{0.87, 0.96, 0.87}", 0, grainCount + 1, yLo, consHi
    endif
    medLo = max(0.35, yLo)
    medHi = min(0.75, yHi)
    if medHi > medLo
        Paint rectangle: "{0.97, 0.97, 0.83}", 0, grainCount + 1, medLo, medHi
    endif
    hiLo = max(0.75, yLo)
    if yHi > hiLo
        Paint rectangle: "{0.99, 0.87, 0.87}", 0, grainCount + 1, hiLo, yHi
    endif

    # Zone threshold lines
    Colour: "{0.72, 0.72, 0.72}"
    Dotted line
    if 0.35 > yLo and 0.35 < yHi
        Draw line: 0, 0.35, grainCount + 1, 0.35
    endif
    if 0.75 > yLo and 0.75 < yHi
        Draw line: 0, 0.75, grainCount + 1, 0.75
    endif
    Solid line

    # Bars: color gradient blue (consonant) -> yellow -> red (tension)
    for i from 1 to grainCount
        s = grainScore#[i]
        normS = (s - yLo) / (yHi - yLo)
        if normS < 0
            normS = 0
        endif
        if normS > 1
            normS = 1
        endif
        r_bar = min(1.0, normS * 2.0)
        g_bar = max(0.0, 1.0 - abs(normS - 0.5) * 2.2)
        b_bar = max(0.0, 1.0 - normS * 2.0)
        barColor$ = "{" + fixed$(r_bar, 2) + ", " + fixed$(g_bar, 2) + ", " + fixed$(b_bar, 2) + "}"
        Paint rectangle: barColor$, i - 0.8, i - 0.2, yLo, s
    endfor

    # Trend line
    Colour: "{0.1, 0.1, 0.1}"
    Line width: 2
    for i from 2 to grainCount
        Draw line: i - 1.5, grainScore#[i-1], i - 0.5, grainScore#[i]
    endfor
    Line width: 1

    # Mean score line
    Colour: "{0.3, 0.3, 0.7}"
    Dotted line
    Draw line: 0, mean_score, grainCount + 1, mean_score
    Solid line

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.1, "yes", "yes", "no"
    Marks bottom every: 1, round(grainCount / 8), "yes", "yes", "no"
    Font size: 7
    Text left:   "yes", "Tension Score"
    Text bottom: "yes", "Grain # (sorted order)"

    # Zone labels (right side of plot, if in range)
    Font size: 6
    labelX = grainCount * 0.97
    Colour: "{0.25, 0.65, 0.25}"
    if 0.17 > yLo and 0.17 < yHi
        Text: labelX, "right", 0.17, "half", "Consonant"
    endif
    Colour: "{0.75, 0.65, 0.10}"
    if 0.55 > yLo and 0.55 < yHi
        Text: labelX, "right", 0.55, "half", "Medium"
    endif
    Colour: "{0.80, 0.15, 0.15}"
    if 0.87 > yLo and 0.87 < yHi
        Text: labelX, "right", 0.87, "half", "High"
    endif

    Font size: 7
    Colour: "{0.3, 0.3, 0.7}"
    if mean_score > yLo and mean_score < yHi
        Text: 1.2, "left", mean_score + (yHi - yLo) * 0.03, "half",
            ..."mean=" + fixed$(mean_score, 3)
    endif

    # -------------------------------------------------------
    # --- Tension Distribution Histogram --------------------
    # -------------------------------------------------------
    Select outer viewport: 0, 4, 4.72, 5.85
    Select inner viewport: 0.6, 3.8, 4.80, 5.78

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
        rh = min(1.0, hbMid * 2.0)
        gh = max(0.0, 1.0 - abs(hbMid - 0.5) * 2.2)
        bh = max(0.0, 1.0 - hbMid * 2.0)
        hColor$ = "{" + fixed$(rh, 2) + ", " + fixed$(gh, 2) + ", " + fixed$(bh, 2) + "}"
        Paint rectangle: hColor$, hbLo, hbHi, 0, histCount[bin]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks bottom every: 1, 0.2, "yes", "yes", "no"
    Text left:   "yes", "Count"
    Text bottom: "yes", "Tension Score"

    # -------------------------------------------------------
    # --- Output Spectrogram --------------------------------
    # -------------------------------------------------------
    Select outer viewport: 4, 8, 4.72, 5.85
    Select inner viewport: 4.4, 7.6, 4.80, 5.78
    selectObject: result
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: spectrogram
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left:   "yes", "Freq (Hz)"
    Text bottom: "yes", "Sorted output"

    # -------------------------------------------------------
    # --- Stats Footer --------------------------------------
    # -------------------------------------------------------
    Select outer viewport: 0, 8, 5.9, 6.3
    Font size: 7
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half",
        ..."Grains: " + string$(grainCount) +
        ..."  |  Tension range: " + fixed$(minScore, 3) + " - " + fixed$(maxScore, 3) +
        ..."  |  Mean: " + fixed$(mean_score, 3) +
        ..."  |  High(>=0.75): " + string$(n_high) + " (" + fixed$(100*n_high/grainCount, 0) + "%)" +
        ..."  Med: " + string$(n_med) + " (" + fixed$(100*n_med/grainCount, 0) + "%)" +
        ..."  Cons: " + string$(n_low) + " (" + fixed$(100*n_low/grainCount, 0) + "%)"

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# === Final Info =============================================
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created:      Set_Sorted_Grains"
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
