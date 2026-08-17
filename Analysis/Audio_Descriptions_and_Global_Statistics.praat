# ============================================================
# Praat AudioTools - Audio_Descriptions_and_Global_Statistics
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3.1 (2026) - Distinct per-Sound acoustic portrait visualization
# License: MIT License
#
# Usage:
#   Select one or more Sound objects and run this script.
#
# Changelog v0.3:
#   - Replaced the z-score heatmap with distinct per-Sound raw acoustic portrait cards.
#   - Pitch cards show measured min/max, quartile band and median on a log-frequency axis.
#   - Added voiced-fraction, intensity-IQR/median, and spectral centroid/R85 gauges.
#   - Voice-quality statistics remain raw measurements; the Results table remains unchanged.
#
# Changelog v0.2:
#   - Analyses only the Sounds explicitly selected by the user; the previous
#     version silently selected every object in the Objects window.
#   - Multichannel Sounds use the strongest-RMS channel, avoiding stereo
#     cancellation while leaving the original Sounds untouched.
#   - Missing pitch/jitter/shimmer/HNR/spectral values remain undefined instead
#     of being written as misleading zeros.
#   - Added voiced-frame fraction and robust pitch IQR in semitones.
#   - Replaced intensity variance with standard deviation and robust IQR.
#   - Jitter and shimmer use periodic pulses with period limits tied to the
#     selected pitch range.
#   - Spectral descriptors use complex power (real^2 + imaginary^2) and one
#     shared Spectrum per Sound.
#   - SPR is integrated power 50-2000 Hz / 2000-4000 Hz in dB, not peak-to-peak.
#   - Legacy spectral roughness renamed SpectralJaggedness_dB because it is a
#     local spectral-irregularity measure, not psychoacoustic roughness.
#   - Whole-file spectral features are calculated on fixed 20-Hz bands so that
#     comparisons are not driven by FFT-bin density when durations differ.
#   - Added a grounded Description column: absolute periodicity/pitch facts and,
#     for batches, relative descriptors based on z-scores within the selected set.
#   - Replaced crowded Picture tables with an 8x8 comparative feature portrait.
# ============================================================

clearinfo

number_of_selected_sounds = numberOfSelected("Sound")
if number_of_selected_sounds = 0
    exitScript: "Please select one or more Sound objects first."
endif

for i to number_of_selected_sounds
    sound'i' = selected("Sound", i)
endfor

form Audio Descriptions and Global Statistics v0.3
    positive Pitch_floor_Hz 75
    positive Pitch_ceiling_Hz 600
    boolean Draw_visualization 1
endform

if pitch_floor_Hz <= 0
    exitScript: "Pitch floor must be positive."
endif
if pitch_ceiling_Hz <= pitch_floor_Hz
    exitScript: "Pitch ceiling must be greater than pitch floor."
endif

# Fixed spectral regions kept out of the compact form.
spectral_min_Hz = 80
spectral_max_Hz = 5000
rolloff_min_Hz = 20
rolloff_max_Hz = 8000
spr_low_min_Hz = 50
spr_split_Hz = 2000
spr_high_max_Hz = 4000
descriptor_band_Hz = 20
period_floor = 1 / pitch_ceiling_Hz
period_ceiling = 1 / pitch_floor_Hz

procedure formatValue: .value, .decimals
    if .value = undefined
        .result$ = "NA"
    else
        .result$ = fixed$(.value, .decimals)
    endif
endproc

procedure meanSd: .data#
    .n = size(.data#)
    .count = 0
    .sum = 0
    for .i to .n
        if .data#[.i] <> undefined
            .count = .count + 1
            .sum = .sum + .data#[.i]
        endif
    endfor
    if .count > 0
        .mean = .sum / .count
    else
        .mean = undefined
    endif

    .sq = 0
    if .count >= 2
        for .i to .n
            if .data#[.i] <> undefined
                .d = .data#[.i] - .mean
                .sq = .sq + .d * .d
            endif
        endfor
        .sd = sqrt(.sq / (.count - 1))
    else
        .sd = 0
    endif
endproc

# Arrays retained for batch descriptions and visualization.
duration_values# = zero#(number_of_selected_sounds)
channel_values# = zero#(number_of_selected_sounds)
voiced_values# = zero#(number_of_selected_sounds)
pitch_median_values# = zero#(number_of_selected_sounds)
pitch_q25_values# = zero#(number_of_selected_sounds)
pitch_q75_values# = zero#(number_of_selected_sounds)
pitch_iqr_values# = zero#(number_of_selected_sounds)
intensity_mean_values# = zero#(number_of_selected_sounds)
intensity_q25_values# = zero#(number_of_selected_sounds)
intensity_q75_values# = zero#(number_of_selected_sounds)
intensity_iqr_values# = zero#(number_of_selected_sounds)
hnr_values# = zero#(number_of_selected_sounds)
jitter_values# = zero#(number_of_selected_sounds)
shimmer_values# = zero#(number_of_selected_sounds)
centroid_values# = zero#(number_of_selected_sounds)
spread_values# = zero#(number_of_selected_sounds)
rolloff_values# = zero#(number_of_selected_sounds)
flatness_values# = zero#(number_of_selected_sounds)
jaggedness_values# = zero#(number_of_selected_sounds)
spr_values# = zero#(number_of_selected_sounds)

resultsTable = Create Table with column names: "AudioDescriptions_Results", number_of_selected_sounds,
    ... "SoundName Description Duration_s AnalysisChannel VoicedFraction Pitch_mean_Hz Pitch_min_Hz Pitch_max_Hz Pitch_median_Hz Pitch_IQR_st Pitch_stdev_Hz Intensity_mean_dB Intensity_median_dB Intensity_stdev_dB Intensity_IQR_dB Jitter_local_percent Shimmer_local_percent Harmonicity_dB SPR_50_2000_vs_2000_4000_dB Spectral_centroid_Hz Spectral_spread_Hz Spectral_rolloff85_Hz Spectral_flatness SpectralJaggedness_dB"

appendInfoLine: "Audio Descriptions and Global Statistics v0.3"
appendInfoLine: "============================================="
appendInfoLine: "Selected Sounds: ", number_of_selected_sounds
appendInfoLine: "Pitch range: ", fixed$(pitch_floor_Hz, 0), "-", fixed$(pitch_ceiling_Hz, 0), " Hz"
appendInfoLine: "Spectral descriptors: fixed 20-Hz bands; 80-5000 Hz unless stated otherwise"
appendInfoLine: "SPR: integrated power 50-2000 Hz / 2000-4000 Hz"
appendInfoLine: ""

for s from 1 to number_of_selected_sounds
    currentSoundID = sound's'
    selectObject: currentSoundID
    soundName$ = selected$("Sound")
    sound_tmin = Get start time
    sound_tmax = Get end time
    duration = sound_tmax - sound_tmin
    n_channels = Get number of channels

    # ----- representative analysis channel: strongest RMS -----
    analysis_sound = currentSoundID
    analysis_is_copy = 0
    analysis_channel = 1
    if n_channels > 1
        best_rms = -1
        for ch from 1 to n_channels
            selectObject: currentSoundID
            tmp_channel = Extract one channel: ch
            channel_rms = Get root-mean-square: 0, 0
            if channel_rms > best_rms
                best_rms = channel_rms
                analysis_channel = ch
            endif
            removeObject: tmp_channel
        endfor
        selectObject: currentSoundID
        analysis_sound = Extract one channel: analysis_channel
        analysis_is_copy = 1
    endif

    duration_values#[s] = duration
    channel_values#[s] = analysis_channel

    # Initialise optional measures as undefined, not zero.
    voicedFraction = undefined
    meanPitch = undefined
    minPitch = undefined
    maxPitch = undefined
    medianPitch = undefined
    q25Pitch = undefined
    q75Pitch = undefined
    pitchIQRst = undefined
    stdevPitch = undefined
    intensityMean = undefined
    intensityMedian = undefined
    intensityQ25 = undefined
    intensityQ75 = undefined
    intensityStdev = undefined
    intensityIQR = undefined
    jitterPercent = undefined
    shimmerPercent = undefined
    hnr = undefined
    spr = undefined
    spectralCentroid = undefined
    spectralSpread = undefined
    spectralRolloff = undefined
    spectralFlatness = undefined
    spectralJaggedness = undefined

    # 1) PITCH / PERIODICITY
    selectObject: analysis_sound
    pitchID = To Pitch (raw cc): 0, pitch_floor_Hz, pitch_ceiling_Hz, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
    pitch_frames = Get number of frames
    voiced_frames = Count voiced frames
    if pitch_frames > 0
        voicedFraction = voiced_frames / pitch_frames
    endif
    if voiced_frames > 1
        meanPitch = Get mean: 0, 0, "Hertz"
        minPitch = Get minimum: 0, 0, "Hertz", "Parabolic"
        maxPitch = Get maximum: 0, 0, "Hertz", "Parabolic"
        q25Pitch = Get quantile: 0, 0, 0.25, "Hertz"
        medianPitch = Get quantile: 0, 0, 0.50, "Hertz"
        q75Pitch = Get quantile: 0, 0, 0.75, "Hertz"
        stdevPitch = Get standard deviation: 0, 0, "Hertz"
        if q25Pitch > 0 and q75Pitch > 0
            pitchIQRst = 12 * ln(q75Pitch / q25Pitch) / ln(2)
        endif
    endif
    removeObject: pitchID

    # 2) INTENSITY
    selectObject: analysis_sound
    intensityID = To Intensity: pitch_floor_Hz, 0, "yes"
    intensityMean = Get mean: 0, 0, "energy"
    intensityMedian = Get quantile: 0, 0, 0.50
    intensityQ25 = Get quantile: 0, 0, 0.25
    intensityQ75 = Get quantile: 0, 0, 0.75
    intensityStdev = Get standard deviation: 0, 0
    if intensityQ25 <> undefined and intensityQ75 <> undefined
        intensityIQR = intensityQ75 - intensityQ25
    endif
    removeObject: intensityID

    # 3) JITTER / SHIMMER FROM PERIODIC PULSES
    selectObject: analysis_sound
    ppID = To PointProcess (periodic, cc): pitch_floor_Hz, pitch_ceiling_Hz
    nPeriods = Get number of periods: 0, 0, period_floor, period_ceiling, 1.3
    if nPeriods > 1
        jitterLocal = Get jitter (local): 0, 0, period_floor, period_ceiling, 1.3
        if jitterLocal <> undefined
            jitterPercent = 100 * jitterLocal
        endif
        selectObject: ppID
        plusObject: analysis_sound
        shimmerLocal = Get shimmer (local): 0, 0, period_floor, period_ceiling, 1.3, 1.6
        if shimmerLocal <> undefined
            shimmerPercent = 100 * shimmerLocal
        endif
    endif
    removeObject: ppID

    # 4) HARMONICITY
    selectObject: analysis_sound
    harmonicityID = To Harmonicity (cc): 0.01, pitch_floor_Hz, 0.1, 1.0
    hnr = Get mean: 0, 0
    removeObject: harmonicityID

    # 5) SHARED WHOLE-SOUND SPECTRUM
    selectObject: analysis_sound
    specID = To Spectrum: "yes"
    nBins = object[specID].nx
    binWidth = object[specID].dx
    nyquist = object[specID].xmax

    n_descriptor_bands = max(1, ceiling(nyquist / descriptor_band_Hz))
    band_power# = zero#(n_descriptor_bands)
    band_bins# = zero#(n_descriptor_bands)

    for b from 1 to nBins
        re = Get real value in bin: b
        im = Get imaginary value in bin: b
        p = re * re + im * im
        if p < 0
            p = 0
        endif
        f = (b - 1) * binWidth
        descriptor_band = floor(f / descriptor_band_Hz) + 1
        descriptor_band = max(1, min(n_descriptor_bands, descriptor_band))
        band_power#[descriptor_band] = band_power#[descriptor_band] + p
        band_bins#[descriptor_band] = band_bins#[descriptor_band] + 1
    endfor

    # 5a) 85 percent roll-off in 20-8000 Hz, Nyquist-limited.
    total_roll_power = 0
    for band from 1 to n_descriptor_bands
        band_center = (band - 0.5) * descriptor_band_Hz
        if band_center >= rolloff_min_Hz and band_center <= min(rolloff_max_Hz, nyquist)
            total_roll_power = total_roll_power + band_power#[band]
        endif
    endfor
    if total_roll_power > 1e-30
        target_power = 0.85 * total_roll_power
        cumulative_power = 0
        found_rolloff = 0
        for band from 1 to n_descriptor_bands
            band_center = (band - 0.5) * descriptor_band_Hz
            if band_center >= rolloff_min_Hz and band_center <= min(rolloff_max_Hz, nyquist) and found_rolloff = 0
                cumulative_power = cumulative_power + band_power#[band]
                if cumulative_power >= target_power
                    spectralRolloff = min(nyquist, band_center)
                    found_rolloff = 1
                endif
            endif
        endfor
    endif

    # 5b) Band-limited centroid, spread, flatness, and jaggedness.
    effective_spectral_max = min(spectral_max_Hz, nyquist)
    band_count = 0
    band_sum = 0
    centroid_num = 0
    band_max_power = 0
    for band from 1 to n_descriptor_bands
        band_center = (band - 0.5) * descriptor_band_Hz
        if band_center >= spectral_min_Hz and band_center <= effective_spectral_max and band_bins#[band] > 0
            p = band_power#[band]
            band_count = band_count + 1
            band_sum = band_sum + p
            centroid_num = centroid_num + band_center * p
            if p > band_max_power
                band_max_power = p
            endif
        endif
    endfor

    if band_count > 0 and band_sum > 1e-30
        spectralCentroid = centroid_num / band_sum
        spread_num = 0
        log_sum = 0
        power_floor = max(1e-30, band_max_power * 1e-12)
        for band from 1 to n_descriptor_bands
            band_center = (band - 0.5) * descriptor_band_Hz
            if band_center >= spectral_min_Hz and band_center <= effective_spectral_max and band_bins#[band] > 0
                p = band_power#[band]
                spread_num = spread_num + (band_center - spectralCentroid) ^ 2 * p
                p_log = max(p, power_floor)
                log_sum = log_sum + ln(p_log)
            endif
        endfor
        spectralSpread = sqrt(spread_num / band_sum)
        spectralFlatness = exp(log_sum / band_count) / (band_sum / band_count)

        jag_sum = 0
        jag_count = 0
        for band from 2 to n_descriptor_bands - 1
            band_center = (band - 0.5) * descriptor_band_Hz
            if band_center >= spectral_min_Hz and band_center <= effective_spectral_max
                if band_bins#[band - 1] > 0 and band_bins#[band] > 0 and band_bins#[band + 1] > 0
                    prev_db = 10 * ln(max(band_power#[band - 1], power_floor)) / ln(10)
                    curr_db = 10 * ln(max(band_power#[band], power_floor)) / ln(10)
                    next_db = 10 * ln(max(band_power#[band + 1], power_floor)) / ln(10)
                    local_baseline = (prev_db + next_db) / 2
                    jag_sum = jag_sum + abs(curr_db - local_baseline)
                    jag_count = jag_count + 1
                endif
            endif
        endfor
        if jag_count > 0
            spectralJaggedness = jag_sum / jag_count
        endif
    endif

    # 5c) Integrated spectral-power ratio: 50-2000 / 2000-4000 Hz.
    low_power = 0
    high_power = 0
    for band from 1 to n_descriptor_bands
        band_center = (band - 0.5) * descriptor_band_Hz
        if band_center >= spr_low_min_Hz and band_center < spr_split_Hz
            low_power = low_power + band_power#[band]
        elsif band_center >= spr_split_Hz and band_center <= min(spr_high_max_Hz, nyquist)
            high_power = high_power + band_power#[band]
        endif
    endfor
    if low_power > 1e-30 and high_power > 1e-30
        spr = 10 * ln(low_power / high_power) / ln(10)
    endif

    removeObject: specID

    # Store arrays for batch-level descriptions/visualization.
    voiced_values#[s] = voicedFraction
    pitch_median_values#[s] = medianPitch
    pitch_q25_values#[s] = q25Pitch
    pitch_q75_values#[s] = q75Pitch
    pitch_iqr_values#[s] = pitchIQRst
    intensity_mean_values#[s] = intensityMean
    intensity_q25_values#[s] = intensityQ25
    intensity_q75_values#[s] = intensityQ75
    intensity_iqr_values#[s] = intensityIQR
    hnr_values#[s] = hnr
    jitter_values#[s] = jitterPercent
    shimmer_values#[s] = shimmerPercent
    centroid_values#[s] = spectralCentroid
    spread_values#[s] = spectralSpread
    rolloff_values#[s] = spectralRolloff
    flatness_values#[s] = spectralFlatness
    jaggedness_values#[s] = spectralJaggedness
    spr_values#[s] = spr

    # Write raw measurements. Description is filled in a second pass.
    selectObject: resultsTable
    Set string value: s, "SoundName", soundName$
    Set string value: s, "Description", ""
    Set numeric value: s, "Duration_s", duration
    Set numeric value: s, "AnalysisChannel", analysis_channel
    Set numeric value: s, "VoicedFraction", voicedFraction
    Set numeric value: s, "Pitch_mean_Hz", meanPitch
    Set numeric value: s, "Pitch_min_Hz", minPitch
    Set numeric value: s, "Pitch_max_Hz", maxPitch
    Set numeric value: s, "Pitch_median_Hz", medianPitch
    Set numeric value: s, "Pitch_IQR_st", pitchIQRst
    Set numeric value: s, "Pitch_stdev_Hz", stdevPitch
    Set numeric value: s, "Intensity_mean_dB", intensityMean
    Set numeric value: s, "Intensity_median_dB", intensityMedian
    Set numeric value: s, "Intensity_stdev_dB", intensityStdev
    Set numeric value: s, "Intensity_IQR_dB", intensityIQR
    Set numeric value: s, "Jitter_local_percent", jitterPercent
    Set numeric value: s, "Shimmer_local_percent", shimmerPercent
    Set numeric value: s, "Harmonicity_dB", hnr
    Set numeric value: s, "SPR_50_2000_vs_2000_4000_dB", spr
    Set numeric value: s, "Spectral_centroid_Hz", spectralCentroid
    Set numeric value: s, "Spectral_spread_Hz", spectralSpread
    Set numeric value: s, "Spectral_rolloff85_Hz", spectralRolloff
    Set numeric value: s, "Spectral_flatness", spectralFlatness
    Set numeric value: s, "SpectralJaggedness_dB", spectralJaggedness

    if analysis_is_copy
        removeObject: analysis_sound
    endif
endfor

# ============================================================
# BATCH STATISTICS FOR GROUNDED RELATIVE DESCRIPTIONS
# ============================================================
@meanSd: centroid_values#
mean_centroid = meanSd.mean
sd_centroid = meanSd.sd
@meanSd: hnr_values#
mean_hnr = meanSd.mean
sd_hnr = meanSd.sd
@meanSd: intensity_iqr_values#
mean_dyn = meanSd.mean
sd_dyn = meanSd.sd
@meanSd: flatness_values#
mean_flatness = meanSd.mean
sd_flatness = meanSd.sd
@meanSd: pitch_iqr_values#
mean_pitch_iqr = meanSd.mean
sd_pitch_iqr = meanSd.sd

# Build a description for each row. Absolute statements are limited to direct
# measurements; qualitative terms are explicitly relative to the selected set.
for s from 1 to number_of_selected_sounds
    description$ = ""
    vf = voiced_values#[s]
    pmed = pitch_median_values#[s]
    piqr = pitch_iqr_values#[s]

    if vf = undefined
        description$ = "Periodicity unavailable"
    elsif vf >= 0.70
        description$ = "Mostly trackable pitch"
    elsif vf >= 0.30
        description$ = "Mixed periodic/aperiodic content"
    else
        description$ = "Little trackable pitch"
    endif

    if pmed <> undefined
        description$ = description$ + "; median F0 " + fixed$(pmed, 1) + " Hz"
    endif
    if piqr <> undefined
        description$ = description$ + "; pitch IQR " + fixed$(piqr, 1) + " st"
    endif

    if number_of_selected_sounds >= 2
        relative_count = 0
        if centroid_values#[s] <> undefined and sd_centroid > 1e-12
            z = (centroid_values#[s] - mean_centroid) / sd_centroid
            if z >= 0.65
                description$ = description$ + "; brighter than selected set"
                relative_count = relative_count + 1
            elsif z <= -0.65
                description$ = description$ + "; darker than selected set"
                relative_count = relative_count + 1
            endif
        endif
        if hnr_values#[s] <> undefined and sd_hnr > 1e-12 and relative_count < 2
            z = (hnr_values#[s] - mean_hnr) / sd_hnr
            if z >= 0.65
                description$ = description$ + "; more harmonic than selected set"
                relative_count = relative_count + 1
            elsif z <= -0.65
                description$ = description$ + "; noisier than selected set"
                relative_count = relative_count + 1
            endif
        endif
        if intensity_iqr_values#[s] <> undefined and sd_dyn > 1e-12 and relative_count < 2
            z = (intensity_iqr_values#[s] - mean_dyn) / sd_dyn
            if z >= 0.65
                description$ = description$ + "; more level variation"
                relative_count = relative_count + 1
            elsif z <= -0.65
                description$ = description$ + "; steadier level"
                relative_count = relative_count + 1
            endif
        endif
        if flatness_values#[s] <> undefined and sd_flatness > 1e-12 and relative_count < 2
            z = (flatness_values#[s] - mean_flatness) / sd_flatness
            if z >= 0.65
                description$ = description$ + "; flatter spectrum"
            elsif z <= -0.65
                description$ = description$ + "; more peaked spectrum"
            endif
        endif
    endif

    selectObject: resultsTable
    Set string value: s, "Description", description$
endfor

# ============================================================
# INFO SUMMARY
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== GLOBAL PORTRAITS ==="
for s from 1 to number_of_selected_sounds
    selectObject: resultsTable
    rowName$ = Get value: s, "SoundName"
    rowDescription$ = Get value: s, "Description"
    appendInfoLine: rowName$ + ": " + rowDescription$
endfor
appendInfoLine: ""
appendInfoLine: "Relative adjectives are z-score comparisons within the selected set, not universal labels."
appendInfoLine: "Jitter/shimmer/HNR/pitch can be undefined when stable periodic evidence is absent."

# ============================================================
# VISUALIZATION: PER-SOUND ACOUSTIC PORTRAIT CARDS
# ============================================================
if draw_visualization
    Erase all

    # Title strip
    Select outer viewport: 0, 8, 0.00, 0.48
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Audio Descriptions and Global Statistics##"

    # Metadata strip
    Select outer viewport: 0, 8, 0.48, 0.86
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.5, "centre", 0.62, "half", string$(number_of_selected_sounds) + " selected Sounds  |  raw global portraits  |  strongest-RMS analysis channel"

    # Cards intentionally show raw measurements rather than z-scores. This keeps
    # this tool visually and conceptually distinct from the batch feature extractor.
    max_cards = 4
    n_cards = min(number_of_selected_sounds, max_cards)
    card_top_page = 0.96
    card_bottom_page = 7.78
    card_gap_page = 0.10
    card_height_page = (card_bottom_page - card_top_page - (n_cards - 1) * card_gap_page) / n_cards

    for card from 1 to n_cards
        if n_cards = 1
            actual_row = 1
        else
            actual_row = 1 + round((card - 1) * (number_of_selected_sounds - 1) / (n_cards - 1))
        endif

        card_y1 = card_top_page + (card - 1) * (card_height_page + card_gap_page)
        card_y2 = card_y1 + card_height_page

        selectObject: resultsTable
        cardName$ = Get value: actual_row, "SoundName"
        cardName$ = replace$(cardName$, "_", " ", 0)
        cardName$ = replace$(cardName$, "%", "pct", 0)
        cardName$ = left$(cardName$, 30)
        cardDescription$ = Get value: actual_row, "Description"
        cardDescription$ = replace$(cardDescription$, "%", "pct", 0)
        cardDescription$ = left$(cardDescription$, 112)

        pmin = Get value: actual_row, "Pitch_min_Hz"
        pmax = Get value: actual_row, "Pitch_max_Hz"
        pmed = Get value: actual_row, "Pitch_median_Hz"
        vf = Get value: actual_row, "VoicedFraction"
        imed = Get value: actual_row, "Intensity_median_dB"
        hnr_card = Get value: actual_row, "Harmonicity_dB"
        flat_card = Get value: actual_row, "Spectral_flatness"
        spr_card = Get value: actual_row, "SPR_50_2000_vs_2000_4000_dB"
        cent_card = Get value: actual_row, "Spectral_centroid_Hz"
        roll_card = Get value: actual_row, "Spectral_rolloff85_Hz"
        jit_card = Get value: actual_row, "Jitter_local_percent"
        shim_card = Get value: actual_row, "Shimmer_local_percent"

        pq25 = pitch_q25_values#[actual_row]
        pq75 = pitch_q75_values#[actual_row]
        iq25 = intensity_q25_values#[actual_row]
        iq75 = intensity_q75_values#[actual_row]

        Select outer viewport: 0.18, 7.82, card_y1, card_y2
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.975, 0.975, 0.975}", 0, 1, 0, 1
        Colour: "{0.72, 0.72, 0.72}"
        Draw rectangle: 0, 1, 0, 1

        # Card heading and grounded description.
        Colour: "Black"
        Font size: 10
        Text: 0.025, "left", 0.91, "half", "##" + cardName$ + "##"
        Font size: 7
        Text: 0.025, "left", 0.79, "half", cardDescription$

        # Common horizontal gauge geometry.
        gx1 = 0.17
        gx2 = 0.70

        # --- Pitch portrait: min/max, interquartile band, median ---
        Font size: 8
        Text: 0.025, "left", 0.60, "half", "Pitch"
        Colour: "{0.70, 0.70, 0.70}"
        Draw line: gx1, 0.60, gx2, 0.60
        Colour: "Black"
        Font size: 6
        Text: gx1, "centre", 0.525, "half", fixed$(pitch_floor_Hz, 0)
        Text: gx2, "centre", 0.525, "half", fixed$(pitch_ceiling_Hz, 0) + " Hz"

        pitch_log_range = ln(pitch_ceiling_Hz / pitch_floor_Hz)
        if pmin <> undefined and pmin > 0 and pmax <> undefined and pmax > 0 and pitch_log_range > 0
            px_min = gx1 + (gx2 - gx1) * max(0, min(1, ln(pmin / pitch_floor_Hz) / pitch_log_range))
            px_max = gx1 + (gx2 - gx1) * max(0, min(1, ln(pmax / pitch_floor_Hz) / pitch_log_range))
            Colour: "{0.28, 0.33, 0.40}"
            Line width: 1
            Draw line: px_min, 0.60, px_max, 0.60
        endif
        if pq25 <> undefined and pq25 > 0 and pq75 <> undefined and pq75 > 0 and pitch_log_range > 0
            px_q25 = gx1 + (gx2 - gx1) * max(0, min(1, ln(pq25 / pitch_floor_Hz) / pitch_log_range))
            px_q75 = gx1 + (gx2 - gx1) * max(0, min(1, ln(pq75 / pitch_floor_Hz) / pitch_log_range))
            Colour: "{0.34, 0.48, 0.66}"
            Line width: 4
            Draw line: px_q25, 0.60, px_q75, 0.60
            Line width: 1
        endif
        if pmed <> undefined and pmed > 0 and pitch_log_range > 0
            px_med = gx1 + (gx2 - gx1) * max(0, min(1, ln(pmed / pitch_floor_Hz) / pitch_log_range))
            Colour: "Black"
            Paint circle (mm): "Black", px_med, 0.60, 1.3
        endif

        # Voiced fraction bar directly below pitch.
        Text: 0.025, "left", 0.44, "half", "Voiced"
        Colour: "{0.86, 0.86, 0.86}"
        Paint rectangle: "{0.90, 0.90, 0.90}", gx1, gx2, 0.405, 0.455
        if vf <> undefined
            vf_cap = max(0, min(1, vf))
            Paint rectangle: "{0.60, 0.68, 0.76}", gx1, gx1 + (gx2 - gx1) * vf_cap, 0.405, 0.455
            Colour: "Black"
            Font size: 7
            Text: gx2 + 0.02, "left", 0.43, "half", fixed$(100 * vf_cap, 0) + "%"
        else
            Colour: "Black"
            Text: gx2 + 0.02, "left", 0.43, "half", "NA"
        endif

        # --- Intensity portrait: interquartile range and median ---
        Font size: 8
        Text: 0.025, "left", 0.28, "half", "Level"
        Colour: "{0.70, 0.70, 0.70}"
        Draw line: gx1, 0.28, gx2, 0.28
        intensity_low = 20
        intensity_high = 100
        Font size: 6
        Colour: "Black"
        Text: gx1, "centre", 0.205, "half", "20"
        Text: gx2, "centre", 0.205, "half", "100 dB"
        if iq25 <> undefined and iq75 <> undefined
            ix25 = gx1 + (gx2 - gx1) * max(0, min(1, (iq25 - intensity_low) / (intensity_high - intensity_low)))
            ix75 = gx1 + (gx2 - gx1) * max(0, min(1, (iq75 - intensity_low) / (intensity_high - intensity_low)))
            Colour: "{0.48, 0.58, 0.48}"
            Line width: 4
            Draw line: ix25, 0.28, ix75, 0.28
            Line width: 1
        endif
        if imed <> undefined
            ixmed = gx1 + (gx2 - gx1) * max(0, min(1, (imed - intensity_low) / (intensity_high - intensity_low)))
            Colour: "Black"
            Paint circle (mm): "Black", ixmed, 0.28, 1.3
        endif

        # --- Spectrum portrait: logarithmic frequency line with centroid and R85 ---
        Text: 0.025, "left", 0.115, "half", "Spectrum"
        sx1 = gx1
        sx2 = gx2
        spec_low = 50
        spec_high = 8000
        spec_log_range = ln(spec_high / spec_low)
        Colour: "{0.70, 0.70, 0.70}"
        Draw line: sx1, 0.115, sx2, 0.115
        if cent_card <> undefined and cent_card > 0
            cx = sx1 + (sx2 - sx1) * max(0, min(1, ln(cent_card / spec_low) / spec_log_range))
            Colour: "{0.35, 0.42, 0.62}"
            Draw line: cx, 0.075, cx, 0.155
            Font size: 6
            Text: cx, "centre", 0.035, "half", "C"
        endif
        if roll_card <> undefined and roll_card > 0
            rx = sx1 + (sx2 - sx1) * max(0, min(1, ln(roll_card / spec_low) / spec_log_range))
            Colour: "{0.62, 0.40, 0.34}"
            Draw line: rx, 0.075, rx, 0.155
            Font size: 6
            Text: rx, "centre", 0.035, "half", "R85"
        endif
        Colour: "Black"
        Text: sx1, "centre", 0.035, "half", "50"
        Text: sx2, "centre", 0.035, "half", "8k Hz"

        # Compact raw-statistics column. These are measurements, not scores.
        metrics_x = 0.755
        Font size: 7
        @formatValue: hnr_card, 1
        Text: metrics_x, "left", 0.62, "half", "HNR  " + formatValue.result$ + " dB"
        @formatValue: flat_card, 3
        Text: metrics_x, "left", 0.48, "half", "Flat  " + formatValue.result$
        @formatValue: spr_card, 1
        Text: metrics_x, "left", 0.34, "half", "SPR  " + formatValue.result$ + " dB"
        @formatValue: jit_card, 2
        jitText$ = formatValue.result$
        @formatValue: shim_card, 2
        shimText$ = formatValue.result$
        Text: metrics_x, "left", 0.20, "half", "Jit/Shim  " + jitText$ + "/" + shimText$ + "%"
    endfor

    # Bottom legend / QC strip.
    Select outer viewport: 0, 8, 7.82, 8.00
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "Black"
    if number_of_selected_sounds > n_cards
        bottomText$ = "Showing " + string$(n_cards) + " evenly sampled portraits of " + string$(number_of_selected_sounds) + ".  All Sounds remain in Table AudioDescriptions Results."
    else
        bottomText$ = "Raw portrait: pitch=min/max + IQR + median; level=IQR + median; spectrum=C centroid, R85 roll-off."
    endif
    Text: 0.5, "centre", 0.55, "half", bottomText$
endif

selectObject: resultsTable
appendInfoLine: ""
appendInfoLine: "=== OUTPUT ==="
appendInfoLine: "Table: AudioDescriptions_Results"
if draw_visualization
    appendInfoLine: "Picture: per-Sound acoustic portrait cards"
endif
appendInfoLine: "Done."
