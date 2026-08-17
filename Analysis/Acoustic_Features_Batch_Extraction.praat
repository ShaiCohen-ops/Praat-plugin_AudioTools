# ============================================================
# Praat AudioTools - Acoustic_Features_Batch_Extraction
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.2 (2026) - Reviewed batch descriptors + comparative visualization
# License: MIT License
#
# Usage:
#   Select one or more Sound objects and run this script.
#
# Changelog v0.2:
#   - Multichannel Sounds are analysed on the strongest-RMS channel, avoiding
#     phase-cancelling fold-downs while leaving the originals untouched.
#   - Jitter now uses periodic pulse detection (periodic, cc) instead of waveform
#     extrema; period limits are tied to the selected pitch range.
#   - Spectral descriptors use complex-spectrum power (re^2 + im^2), not the
#     real FFT component alone.
#   - Only one Spectrum is created per Sound; roll-off, centroid, spread,
#     flatness, spectral jaggedness, and SPR share that analysis.
#   - SPR is now an integrated spectral-power ratio: 50-2000 Hz versus
#     2000-4000 Hz, in dB. The previous peak-to-peak difference was not an SPR.
#   - Legacy "Roughness" renamed to SpectralJaggedness_dB because the metric is
#     local spectral irregularity, not a psychoacoustic roughness model.
#   - Added duration, analysis channel, spectral centroid, and spectral spread.
#   - Added a per-feature z-score comparison heatmap (display only); the Table
#     retains raw measurements and physical units.
#   - Visualization samples evenly when more than 24 Sounds are selected.
# ============================================================

clearinfo

number_of_selected_sounds = numberOfSelected("Sound")
if number_of_selected_sounds = 0
    exitScript: "Please select one or more Sound objects first."
endif

for i to number_of_selected_sounds
    sound'i' = selected("Sound", i)
endfor

form Acoustic Features Batch Extraction v0.2
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

# Fixed spectral regions. These are intentionally kept out of the compact form.
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

# Arrays retained for visualization/QC.
duration_values# = zero#(number_of_selected_sounds)
channel_values# = zero#(number_of_selected_sounds)
intensity_values# = zero#(number_of_selected_sounds)
harmonicity_values# = zero#(number_of_selected_sounds)
jitter_values# = zero#(number_of_selected_sounds)
rolloff_values# = zero#(number_of_selected_sounds)
centroid_values# = zero#(number_of_selected_sounds)
spread_values# = zero#(number_of_selected_sounds)
flatness_values# = zero#(number_of_selected_sounds)
jaggedness_values# = zero#(number_of_selected_sounds)
spr_values# = zero#(number_of_selected_sounds)

resultsTable = Create Table with column names: "AudioTools_Results", number_of_selected_sounds,
    ... "Filename Duration_s AnalysisChannel IntensityMean_dB HarmonicityMean_dB JitterLocal_percent RollOff85_Hz SpectralCentroid_Hz SpectralSpread_Hz Flatness_80_5000 SpectralJaggedness_dB SPR_50_2000_vs_2000_4000_dB"

appendInfoLine: "AudioTools batch analysis v0.2"
appendInfoLine: "=========================="
appendInfoLine: "Sounds: ", number_of_selected_sounds
appendInfoLine: "Pitch range for periodicity/jitter: ", fixed$(pitch_floor_Hz, 0), "-", fixed$(pitch_ceiling_Hz, 0), " Hz"
appendInfoLine: "Spectral descriptor band: ", spectral_min_Hz, "-", spectral_max_Hz, " Hz on ", descriptor_band_Hz, "-Hz bands (Nyquist-limited)"
appendInfoLine: "Roll-off band: 20-8000 Hz (Nyquist-limited)"
appendInfoLine: "SPR: 50-2000 Hz / 2000-4000 Hz integrated power"
appendInfoLine: ""
appendInfoLine: "Sound", tab$, "Intensity", tab$, "HNR", tab$, "Jitter%", tab$, "RollOff85", tab$, "Centroid", tab$, "Flatness", tab$, "Jaggedness", tab$, "SPR"
appendInfoLine: "------------------------------------------------------------------------------------------------------------"

for s from 1 to number_of_selected_sounds
    currentSoundID = sound's'
    selectObject: currentSoundID
    name$ = selected$("Sound")
    duration = Get total duration
    n_channels = Get number of channels

    # ----- representative channel: strongest RMS -----
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

    intensityMean = undefined
    harmonicityMean = undefined
    jitterLocalPercent = undefined
    rolloff85 = undefined
    centroid = undefined
    spread = undefined
    flatness = undefined
    spectralJaggedness = undefined
    spr = undefined

    # 1) INTENSITY
    selectObject: analysis_sound
    intensityID = To Intensity: pitch_floor_Hz, 0, "yes"
    intensityMean = Get mean: 0, 0, "energy"
    removeObject: intensityID

    # 2) HARMONICITY (cc)
    selectObject: analysis_sound
    harmID = To Harmonicity (cc): 0.01, pitch_floor_Hz, 0.1, 1
    harmonicityMean = Get mean: 0, 0
    removeObject: harmID

    # 3) JITTER (local) from periodic pulses, not waveform extrema.
    selectObject: analysis_sound
    ppID = To PointProcess (periodic, cc): pitch_floor_Hz, pitch_ceiling_Hz
    jitterLocal = Get jitter (local): 0, 0, period_floor, period_ceiling, 1.3
    if jitterLocal <> undefined
        jitterLocalPercent = 100 * jitterLocal
    endif
    removeObject: ppID

    # 4) SHARED WHOLE-SOUND SPECTRUM
    # Complex power is re^2 + im^2. To make batch comparisons independent of
    # whole-file FFT resolution (df = 1 / duration), raw bins are accumulated
    # into fixed 20-Hz descriptor bands before spectral features are computed.
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

    # 4a) Spectral roll-off: 85% of power in 20-8000 Hz (Nyquist-limited).
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
                    rolloff85 = min(nyquist, band_center)
                    found_rolloff = 1
                endif
            endif
        endfor
    endif

    # 4b) Band-limited centroid, spread, and flatness.
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
        centroid = centroid_num / band_sum
        spread_num = 0
        log_sum = 0
        power_floor = max(1e-30, band_max_power * 1e-12)
        for band from 1 to n_descriptor_bands
            band_center = (band - 0.5) * descriptor_band_Hz
            if band_center >= spectral_min_Hz and band_center <= effective_spectral_max and band_bins#[band] > 0
                p = band_power#[band]
                spread_num = spread_num + (band_center - centroid) ^ 2 * p
                p_log = max(p, power_floor)
                log_sum = log_sum + ln(p_log)
            endif
        endfor
        spread = sqrt(spread_num / band_sum)
        flatness = exp(log_sum / band_count) / (band_sum / band_count)

        # Local spectral irregularity on a fixed 20-Hz log-power grid, in dB.
        # This is intentionally named jaggedness, not psychoacoustic roughness.
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

    # 4c) Integrated spectral-power ratio: 50-2000 / 2000-4000 Hz.
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

    intensity_values#[s] = intensityMean
    harmonicity_values#[s] = harmonicityMean
    jitter_values#[s] = jitterLocalPercent
    rolloff_values#[s] = rolloff85
    centroid_values#[s] = centroid
    spread_values#[s] = spread
    flatness_values#[s] = flatness
    jaggedness_values#[s] = spectralJaggedness
    spr_values#[s] = spr

    # WRITE RAW VALUES TO TABLE
    selectObject: resultsTable
    Set string value: s, "Filename", name$
    Set numeric value: s, "Duration_s", duration
    Set numeric value: s, "AnalysisChannel", analysis_channel
    Set numeric value: s, "IntensityMean_dB", intensityMean
    Set numeric value: s, "HarmonicityMean_dB", harmonicityMean
    Set numeric value: s, "JitterLocal_percent", jitterLocalPercent
    Set numeric value: s, "RollOff85_Hz", rolloff85
    Set numeric value: s, "SpectralCentroid_Hz", centroid
    Set numeric value: s, "SpectralSpread_Hz", spread
    Set numeric value: s, "Flatness_80_5000", flatness
    Set numeric value: s, "SpectralJaggedness_dB", spectralJaggedness
    Set numeric value: s, "SPR_50_2000_vs_2000_4000_dB", spr

    @formatValue: intensityMean, 2
    intText$ = formatValue.result$
    @formatValue: harmonicityMean, 2
    hnrText$ = formatValue.result$
    @formatValue: jitterLocalPercent, 3
    jitterText$ = formatValue.result$
    @formatValue: rolloff85, 0
    rollText$ = formatValue.result$
    @formatValue: centroid, 0
    centText$ = formatValue.result$
    @formatValue: flatness, 4
    flatText$ = formatValue.result$
    @formatValue: spectralJaggedness, 2
    jagText$ = formatValue.result$
    @formatValue: spr, 2
    sprText$ = formatValue.result$

    appendInfoLine: name$, tab$, intText$, tab$, hnrText$, tab$, jitterText$, tab$, rollText$, tab$, centText$, tab$, flatText$, tab$, jagText$, tab$, sprText$

    if analysis_is_copy
        removeObject: analysis_sound
    endif
endfor

# ============================================================
# COMPARATIVE VISUALIZATION
# ============================================================
if draw_visualization
    Erase all

    # Title strip
    Select outer viewport: 0, 8, 0.00, 0.52
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Acoustic Features Batch Extraction##"

    # Metadata strip
    Select outer viewport: 0, 8, 0.52, 0.88
    Axes: 0, 1, 0, 1
    Font size: 8
    Text: 0.5, "centre", 0.62, "half", string$(number_of_selected_sounds) + " Sounds  |  strongest-RMS channel  |  raw values retained in Table AudioTools Results"

    if number_of_selected_sounds >= 2
        @meanSd: intensity_values#
        mean_intensity = meanSd.mean
        sd_intensity = meanSd.sd
        @meanSd: harmonicity_values#
        mean_harmonicity = meanSd.mean
        sd_harmonicity = meanSd.sd
        @meanSd: jitter_values#
        mean_jitter = meanSd.mean
        sd_jitter = meanSd.sd
        @meanSd: rolloff_values#
        mean_rolloff = meanSd.mean
        sd_rolloff = meanSd.sd
        @meanSd: centroid_values#
        mean_centroid = meanSd.mean
        sd_centroid = meanSd.sd
        @meanSd: spread_values#
        mean_spread = meanSd.mean
        sd_spread = meanSd.sd
        @meanSd: flatness_values#
        mean_flatness = meanSd.mean
        sd_flatness = meanSd.sd
        @meanSd: jaggedness_values#
        mean_jaggedness = meanSd.mean
        sd_jaggedness = meanSd.sd
        @meanSd: spr_values#
        mean_spr = meanSd.mean
        sd_spr = meanSd.sd

        max_viz_rows = 24
        viz_rows = min(number_of_selected_sounds, max_viz_rows)

        # Panel title strip
        Select outer viewport: 0, 8, 0.90, 1.18
        Axes: 0, 1, 0, 1
        Font size: 9
        Text: 0.5, "centre", 0.58, "half", "##Relative feature profile##   per-feature z-score; display only"

        # Heatmap panel
        Select outer viewport: 0, 8, 1.18, 7.08
        Select inner viewport: 0.42, 7.72, 1.34, 6.92
        Axes: -3.2, 9, 0, viz_rows + 1
        Paint rectangle: "{0.98, 0.98, 0.98}", -3.2, 9, 0, viz_rows + 1

        Font size: 7
        Text: 0.5, "centre", viz_rows + 0.55, "half", "Int"
        Text: 1.5, "centre", viz_rows + 0.55, "half", "HNR"
        Text: 2.5, "centre", viz_rows + 0.55, "half", "Jit"
        Text: 3.5, "centre", viz_rows + 0.55, "half", "R85"
        Text: 4.5, "centre", viz_rows + 0.55, "half", "Cent"
        Text: 5.5, "centre", viz_rows + 0.55, "half", "Sprd"
        Text: 6.5, "centre", viz_rows + 0.55, "half", "Flat"
        Text: 7.5, "centre", viz_rows + 0.55, "half", "Jag"
        Text: 8.5, "centre", viz_rows + 0.55, "half", "SPR"

        if viz_rows <= 14
            cell_font = 7
        else
            cell_font = 6
        endif
        Font size: cell_font

        for vr from 1 to viz_rows
            if viz_rows = 1
                actual_row = 1
            else
                actual_row = 1 + round((vr - 1) * (number_of_selected_sounds - 1) / (viz_rows - 1))
            endif
            y = viz_rows - vr + 0.5

            selectObject: resultsTable
            rowName$ = Get value: actual_row, "Filename"
            rowName$ = replace$(rowName$, "_", " ", 0)
            rowName$ = replace$(rowName$, "%", "pct", 0)
            rowName$ = left$(rowName$, 22)
            Select inner viewport: 0.42, 7.72, 1.34, 6.92
            Axes: -3.2, 9, 0, viz_rows + 1
            Colour: "Black"
            Text: -0.12, "right", y, "half", rowName$

            for fc from 1 to 9
                if fc = 1
                    value = intensity_values#[actual_row]
                    feature_mean = mean_intensity
                    feature_sd = sd_intensity
                elsif fc = 2
                    value = harmonicity_values#[actual_row]
                    feature_mean = mean_harmonicity
                    feature_sd = sd_harmonicity
                elsif fc = 3
                    value = jitter_values#[actual_row]
                    feature_mean = mean_jitter
                    feature_sd = sd_jitter
                elsif fc = 4
                    value = rolloff_values#[actual_row]
                    feature_mean = mean_rolloff
                    feature_sd = sd_rolloff
                elsif fc = 5
                    value = centroid_values#[actual_row]
                    feature_mean = mean_centroid
                    feature_sd = sd_centroid
                elsif fc = 6
                    value = spread_values#[actual_row]
                    feature_mean = mean_spread
                    feature_sd = sd_spread
                elsif fc = 7
                    value = flatness_values#[actual_row]
                    feature_mean = mean_flatness
                    feature_sd = sd_flatness
                elsif fc = 8
                    value = jaggedness_values#[actual_row]
                    feature_mean = mean_jaggedness
                    feature_sd = sd_jaggedness
                else
                    value = spr_values#[actual_row]
                    feature_mean = mean_spr
                    feature_sd = sd_spr
                endif

                x1 = fc - 1
                x2 = fc
                if value = undefined
                    Paint rectangle: "{0.90, 0.90, 0.90}", x1, x2, y - 0.42, y + 0.42
                    Colour: "{0.35, 0.35, 0.35}"
                    Text: fc - 0.5, "centre", y, "half", "NA"
                elsif feature_sd <= 1e-12
                    Paint rectangle: "{0.95, 0.95, 0.95}", x1, x2, y - 0.42, y + 0.42
                    Colour: "Black"
                    Text: fc - 0.5, "centre", y, "half", "0.0"
                else
                    z = (value - feature_mean) / feature_sd
                    z_cap = max(-2.5, min(2.5, z))
                    strength = abs(z_cap) / 2.5
                    if z_cap >= 0
                        red = 0.98
                        green = 0.98 - 0.28 * strength
                        blue = 0.98 - 0.28 * strength
                    else
                        red = 0.98 - 0.28 * strength
                        green = 0.98 - 0.18 * strength
                        blue = 0.98
                    endif
                    cellColour$ = "{" + fixed$(red, 2) + ", " + fixed$(green, 2) + ", " + fixed$(blue, 2) + "}"
                    Paint rectangle: cellColour$, x1, x2, y - 0.42, y + 0.42
                    Colour: "Black"
                    Text: fc - 0.5, "centre", y, "half", fixed$(z, 1)
                endif
            endfor
        endfor

        Select inner viewport: 0.42, 7.72, 1.34, 6.92
        Axes: -3.2, 9, 0, viz_rows + 1
        Colour: "{0.70, 0.70, 0.70}"
        Line width: 1
        for fc from 0 to 9
            Draw line: fc, 0, fc, viz_rows
        endfor
        for vr from 0 to viz_rows
            Draw line: 0, vr, 9, vr
        endfor
        Colour: "Black"
        Draw rectangle: 0, 9, 0, viz_rows

        # Summary strip
        Select outer viewport: 0, 8, 7.16, 7.92
        Select inner viewport: 0.45, 7.60, 7.24, 7.84
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
        Colour: "Black"
        Font size: 8
        if number_of_selected_sounds > viz_rows
            displayText$ = "Displaying " + string$(viz_rows) + " evenly sampled Sounds of " + string$(number_of_selected_sounds)
        else
            displayText$ = "Displaying all " + string$(number_of_selected_sounds) + " Sounds"
        endif
        Text: 0.02, "left", 0.68, "half", displayText$ + "   |   z capped at +/-2.5 for colour only"
        Text: 0.02, "left", 0.28, "half", "R85=85 percent roll-off   Cent/Sprd=80-5000 Hz   Flat/Jag use 20-Hz bands   SPR=50-2k / 2-4k dB"
        Draw rectangle: 0, 1, 0, 1
    else
        # With one Sound, z-scores are undefined by definition; show raw values.
        Select outer viewport: 0, 8, 1.10, 7.05
        Select inner viewport: 0.75, 7.30, 1.35, 6.75
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Font size: 10
        Text: 0.04, "left", 0.92, "half", "##Single-Sound feature summary##"
        Font size: 9
        selectObject: resultsTable
        singleName$ = Get value: 1, "Filename"
        singleName$ = replace$(singleName$, "_", " ", 0)
        singleName$ = replace$(singleName$, "%", "pct", 0)
        Text: 0.04, "left", 0.84, "half", "Sound: " + singleName$

        @formatValue: intensity_values#[1], 2
        Text: 0.08, "left", 0.70, "half", "Intensity mean: " + formatValue.result$ + " dB"
        @formatValue: harmonicity_values#[1], 2
        Text: 0.08, "left", 0.62, "half", "Harmonicity mean: " + formatValue.result$ + " dB"
        @formatValue: jitter_values#[1], 3
        Text: 0.08, "left", 0.54, "half", "Jitter local: " + formatValue.result$ + " percent"
        @formatValue: rolloff_values#[1], 0
        Text: 0.08, "left", 0.46, "half", "Roll-off 85: " + formatValue.result$ + " Hz"
        @formatValue: centroid_values#[1], 0
        Text: 0.54, "left", 0.70, "half", "Spectral centroid: " + formatValue.result$ + " Hz"
        @formatValue: spread_values#[1], 0
        Text: 0.54, "left", 0.62, "half", "Spectral spread: " + formatValue.result$ + " Hz"
        @formatValue: flatness_values#[1], 4
        Text: 0.54, "left", 0.54, "half", "Flatness: " + formatValue.result$
        @formatValue: jaggedness_values#[1], 2
        Text: 0.54, "left", 0.46, "half", "Spectral jaggedness: " + formatValue.result$ + " dB"
        @formatValue: spr_values#[1], 2
        Text: 0.54, "left", 0.38, "half", "SPR: " + formatValue.result$ + " dB"

        Font size: 8
        Text: 0.04, "left", 0.20, "half", "A comparative z-score heatmap appears when two or more Sounds are selected."
        Text: 0.04, "left", 0.12, "half", "All raw measurements are available in Table AudioTools Results."
        Draw rectangle: 0, 1, 0, 1
    endif
endif

# Return the useful outputs to the object list selection.
selectObject: resultsTable

appendInfoLine: ""
appendInfoLine: "=== OUTPUT ==="
appendInfoLine: "Table: AudioTools_Results (raw values)"
if draw_visualization
    appendInfoLine: "Picture: comparative feature visualization"
endif
appendInfoLine: "Jitter uses periodic pulses and may be undefined for material without stable periodicity."
appendInfoLine: "Done."
