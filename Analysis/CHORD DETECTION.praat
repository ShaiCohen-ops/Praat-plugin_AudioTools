# ============================================================
# Praat AudioTools - CHORD_DETECTION.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.4.1 (2026)
# License: MIT License
#
# Description:
#   Offline chord/pitch-class estimator for sustained harmonic audio.
#   Each frame is Hanning-windowed, spectral peaks are measured, likely
#   harmonics are softly downweighted, and the remaining peak energy is
#   folded into 12 pitch classes. Common chord templates are scored
#   against that measured evidence; a confidence margin and temporal
#   confirmation stage turn frame estimates into TextGrid segments.
#
#   This is a spectral-template estimator, not a general-purpose MIR
#   transcription system. Inversions are usually treated as the same
#   chord, while bass evidence is used only as a weak tie-breaker.
#   Rootless voicings, inharmonic sounds, clusters and fast changes can
#   remain ambiguous.
#
# Changelog v0.4.1:
#   - Performance engine: scans only bins inside the requested frequency range.
#   - Single rolling pass finds spectral maxima; removed the separate max scan.
#   - Reuses neighbouring-bin magnitudes instead of six Spectrum queries per bin.
#   - Partial top-K selection replaces full bubble sorting of every detected peak.
#   - Detection model, thresholds, templates and visualization are unchanged.
#
# Changelog v0.4:
#   - Replaced brittle exact pitch-class-set matching with scored templates.
#   - Hanning peak analysis with local parabolic frequency refinement.
#   - Harmonic peaks are downweighted rather than blindly deleted.
#   - Multichannel spectra are analyzed separately and pooled in magnitude.
#   - Added confidence margin + temporal confirmation/hysteresis.
#   - TextGrid tier 1 = confirmed chord segments; tier 2 = frame pitch classes.
#   - Added optional editor opening instead of forcing View & Edit.
#   - Visualization rebuilt in AudioTools 2x2 house layout.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
sound_name$ = selected$("Sound")

form Chord Detection v0.4.1
    comment === Presets ===
    optionmenu Preset: 3
        option Custom
        option Quick Scan
        option Standard Analysis
        option Fine Detail
        option Polyphonic Dense
        option Monophonic Melody
    comment === Time Analysis ===
    positive Window_size_ms 120
    positive Time_step_ms 50
    positive Skip_transient_ms 10
    comment === Spectral Peak Evidence ===
    positive Min_frequency_Hz 60
    positive Max_frequency_Hz 4000
    positive Tuning_A4_Hz 440
    positive Relative_peak_threshold_dB 35
    positive Min_peak_separation_Hz 12
    positive Harmonic_tolerance_cents 45
    boolean Downweight_harmonic_duplicates 1
    real Harmonic_downweight_percent 12
    natural Max_peaks_to_keep 36
    positive Pitch_class_floor_percent 22
    comment === Decision ===
    real Min_confidence_percent 7
    positive Min_chord_duration_ms 200
    real Silence_floor_dB -45
    comment === Output ===
    boolean Show_all_detections 0
    boolean Draw_visualization 1
    boolean Open_TextGrid_editor 0
endform

# ---------- Presets ----------
presetName$ = "Custom"
detection_mode = 1
if preset = 2
    window_size_ms = 160
    time_step_ms = 100
    skip_transient_ms = 20
    min_frequency_Hz = 80
    max_frequency_Hz = 3000
    relative_peak_threshold_dB = 30
    min_peak_separation_Hz = 20
    harmonic_tolerance_cents = 55
    harmonic_downweight_percent = 15
    max_peaks_to_keep = 24
    pitch_class_floor_percent = 28
    min_confidence_percent = 9
    min_chord_duration_ms = 300
    presetName$ = "Quick Scan"
elsif preset = 3
    window_size_ms = 120
    time_step_ms = 50
    skip_transient_ms = 10
    min_frequency_Hz = 60
    max_frequency_Hz = 4000
    relative_peak_threshold_dB = 35
    min_peak_separation_Hz = 12
    harmonic_tolerance_cents = 45
    harmonic_downweight_percent = 12
    max_peaks_to_keep = 36
    pitch_class_floor_percent = 22
    min_confidence_percent = 7
    min_chord_duration_ms = 200
    presetName$ = "Standard"
elsif preset = 4
    window_size_ms = 160
    time_step_ms = 25
    skip_transient_ms = 5
    min_frequency_Hz = 45
    max_frequency_Hz = 5500
    relative_peak_threshold_dB = 40
    min_peak_separation_Hz = 8
    harmonic_tolerance_cents = 40
    harmonic_downweight_percent = 10
    max_peaks_to_keep = 48
    pitch_class_floor_percent = 20
    min_confidence_percent = 5
    min_chord_duration_ms = 100
    presetName$ = "Fine Detail"
elsif preset = 5
    window_size_ms = 180
    time_step_ms = 60
    skip_transient_ms = 10
    min_frequency_Hz = 45
    max_frequency_Hz = 6000
    relative_peak_threshold_dB = 42
    min_peak_separation_Hz = 6
    harmonic_tolerance_cents = 45
    harmonic_downweight_percent = 15
    max_peaks_to_keep = 64
    pitch_class_floor_percent = 18
    min_confidence_percent = 5
    min_chord_duration_ms = 180
    presetName$ = "Polyphonic Dense"
elsif preset = 6
    window_size_ms = 80
    time_step_ms = 25
    skip_transient_ms = 5
    min_frequency_Hz = 70
    max_frequency_Hz = 3000
    relative_peak_threshold_dB = 30
    min_peak_separation_Hz = 25
    harmonic_tolerance_cents = 60
    harmonic_downweight_percent = 8
    max_peaks_to_keep = 20
    pitch_class_floor_percent = 30
    min_confidence_percent = 0
    min_chord_duration_ms = 50
    detection_mode = 2
    presetName$ = "Monophonic Melody"
endif

# ---------- Validation ----------
if window_size_ms < 20
    window_size_ms = 20
endif
if time_step_ms < 5
    time_step_ms = 5
endif
if relative_peak_threshold_dB < 6
    relative_peak_threshold_dB = 6
elsif relative_peak_threshold_dB > 80
    relative_peak_threshold_dB = 80
endif
if min_peak_separation_Hz < 1
    min_peak_separation_Hz = 1
endif
if harmonic_tolerance_cents < 5
    harmonic_tolerance_cents = 5
elsif harmonic_tolerance_cents > 150
    harmonic_tolerance_cents = 150
endif
if harmonic_downweight_percent < 0
    harmonic_downweight_percent = 0
elsif harmonic_downweight_percent > 100
    harmonic_downweight_percent = 100
endif
if max_peaks_to_keep < 4
    max_peaks_to_keep = 4
elsif max_peaks_to_keep > 128
    max_peaks_to_keep = 128
endif
if pitch_class_floor_percent < 5
    pitch_class_floor_percent = 5
elsif pitch_class_floor_percent > 90
    pitch_class_floor_percent = 90
endif
if min_confidence_percent < 0
    min_confidence_percent = 0
elsif min_confidence_percent > 100
    min_confidence_percent = 100
endif
if tuning_A4_Hz < 300 or tuning_A4_Hz > 500
    exitScript: "Tuning A4 must be between 300 and 500 Hz."
endif

window_size = window_size_ms / 1000
time_step = time_step_ms / 1000
skip_transient = skip_transient_ms / 1000
min_chord_duration = min_chord_duration_ms / 1000
pc_floor = pitch_class_floor_percent / 100
harmonic_downweight = harmonic_downweight_percent / 100
min_confirm_frames = round(min_chord_duration / time_step)
if min_confirm_frames < 1
    min_confirm_frames = 1
endif

epsilon = 1e-12

# ---------- Input / analysis channel ----------
selectObject: sound
duration = Get total duration
sampling_rate = Get sampling frequency
n_channels = Get number of channels
nyquist = sampling_rate / 2

if duration < window_size + skip_transient
    exitScript: "Sound is shorter than one analysis window after Skip transient."
endif
if min_frequency_Hz >= nyquist
    exitScript: "Minimum analysis frequency is above Nyquist."
endif
if max_frequency_Hz > nyquist * 0.98
    max_frequency_Hz = nyquist * 0.98
endif
if max_frequency_Hz <= min_frequency_Hz
    exitScript: "Maximum analysis frequency must be above minimum analysis frequency."
endif

analysisId = 0
analysisChannel = 1
bestChannelRms = -1
for ch from 1 to n_channels
    selectObject: sound
    if n_channels = 1
        chId = Copy: "chord_analysis"
    else
        chId = Extract one channel: ch
        Rename: "chord_analysis_ch" + string$(ch)
    endif
    analysis_ch_id_'ch' = chId
    chRms = Get root-mean-square: 0, 0
    if chRms > bestChannelRms
        analysisId = chId
        analysisChannel = ch
        bestChannelRms = chRms
    endif
endfor

# Silence detection uses multichannel RMS energy; pitch-class evidence is
# computed per channel and pooled in the magnitude domain (max salience),
# avoiding phase cancellation while retaining notes panned to either side.
selectObject: sound
globalRms = Get root-mean-square: 0, 0

clearinfo
writeInfoLine: "=== CHORD DETECTION v0.4.1 ==="
appendInfoLine: "Input: ", sound_name$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s | channels: ", n_channels
appendInfoLine: "Channel evidence: pooled across ", n_channels, " channel(s); display channel: ", analysisChannel, " (strongest RMS)"
appendInfoLine: "Method: Hanning frame -> measured peaks -> harmonic-aware pitch classes -> chord templates -> temporal confirmation"
appendInfoLine: "A4: ", fixed$(tuning_A4_Hz, 1), " Hz | peak threshold: -", fixed$(relative_peak_threshold_dB, 0), " dB | PC floor: ", fixed$(pitch_class_floor_percent, 0), "%"
appendInfoLine: "Minimum confidence margin: ", fixed$(min_confidence_percent, 1), "%"
appendInfoLine: ""
appendInfoLine: "Analyzing..."

# ---------- Frame analysis ----------
frame_number = 0
analysis_time = skip_transient
n_segments = 0

stable_chord$ = ""
stable_start = skip_transient
pending_chord$ = ""
pending_start = skip_transient
pending_count = 0

bestFrameConfidence = -1
bestFrameChord$ = ""
bestFrameRoot = -1
bestFrameQuality = 0
bestFrameTime = 0
for pc from 0 to 11
    best_pc_'pc' = 0
endfor

# FFT geometry is constant for fixed-size frames. Cache it after the first FFT.
cachedDx = 0
cachedNBins = 0
cachedMinBin = 0
cachedMaxBin = 0

while analysis_time + window_size <= duration + 1e-12
    frame_number += 1
    frame_time = analysis_time + 0.5 * window_size

    selectObject: sound
    frameRms = Get root-mean-square: analysis_time, analysis_time + window_size
    if globalRms > epsilon
        frameRelDb = 20 * log10((frameRms + epsilon) / (globalRms + epsilon))
    else
        frameRelDb = -999
    endif

    chord_name$ = "Silence"
    notes_list$ = ""
    confidence = 0
    bestScore = 0
    secondScore = 0
    winningRoot = -1
    winningQuality = 0

    for pc from 0 to 11
        pc_raw_'pc' = 0
        pc_salience_'pc' = 0
        pc_active_'pc' = 0
    endfor

    if globalRms > epsilon and frameRelDb >= silence_floor_dB
        bassPc = -1
        bassFreq = 1e30

        # Analyze each channel independently, then pool pitch-class evidence
        # in the magnitude domain. This avoids phase cancellation while still
        # retaining notes that are panned to different channels.
        for ch from 1 to n_channels
            for pc from 0 to 11
                channel_pc_'pc' = 0
            endfor

            selectObject: analysis_ch_id_'ch'
            extract = Extract part: analysis_time, analysis_time + window_size, "Hanning", 1.0, "no"
            channelFrameRms = Get root-mean-square: 0, 0
            spectrum = To Spectrum: "yes"

            # Fixed FFT geometry: compute once, then reuse for every frame/channel.
            if cachedDx = 0
                cachedNBins = Get number of bins
                cachedDx = Get bin width
                cachedMinBin = ceiling(min_frequency_Hz / cachedDx) + 1
                cachedMaxBin = floor(max_frequency_Hz / cachedDx) + 1
                if cachedMinBin < 2
                    cachedMinBin = 2
                endif
                if cachedMaxBin > cachedNBins - 1
                    cachedMaxBin = cachedNBins - 1
                endif
            endif
            n_bins = cachedNBins
            dx = cachedDx
            minBin = cachedMinBin
            maxBin = cachedMaxBin

            # FAST SPECTRAL SCAN. One rolling pass does two jobs at once:
            # (1) finds the maximum level in the requested band, and
            # (2) records local maxima for later thresholding/refinement.
            # Only one new complex bin is queried per step.
            raw_peak_count = 0
            channelMaxDb = -999

            if maxBin >= minBin
                leftBin = minBin - 1
                rePrev = Get real value in bin: leftBin
                imPrev = Get imaginary value in bin: leftBin
                mPrev = sqrt(rePrev * rePrev + imPrev * imPrev)

                reCur = Get real value in bin: minBin
                imCur = Get imaginary value in bin: minBin
                mCur = sqrt(reCur * reCur + imCur * imCur)

                for i_bin from minBin to maxBin
                    nextBin = i_bin + 1
                    reNext = Get real value in bin: nextBin
                    imNext = Get imaginary value in bin: nextBin
                    mNext = sqrt(reNext * reNext + imNext * imNext)

                    if mCur > epsilon
                        dbCur = 20 * log10(mCur)
                    else
                        dbCur = -999
                    endif
                    if dbCur > channelMaxDb
                        channelMaxDb = dbCur
                    endif

                    if mCur > mPrev and mCur >= mNext
                        y1 = ln(mPrev + epsilon)
                        y2 = ln(mCur + epsilon)
                        y3 = ln(mNext + epsilon)
                        denom = y1 - 2 * y2 + y3
                        delta = 0
                        if abs(denom) > 1e-12
                            delta = 0.5 * (y1 - y3) / denom
                            if delta < -0.5
                                delta = -0.5
                            elsif delta > 0.5
                                delta = 0.5
                            endif
                        endif
                        raw_peak_count += 1
                        raw_peak_freq_'raw_peak_count' = (i_bin - 1 + delta) * dx
                        raw_peak_db_'raw_peak_count' = dbCur
                    endif

                    mPrev = mCur
                    mCur = mNext
                endfor
            endif

            n_peaks = 0
            if channelMaxDb > -900
                effectiveThreshold = channelMaxDb - relative_peak_threshold_dB

                # Apply the same threshold and frequency-domain NMS as v0.4,
                # now only to actual local maxima instead of every FFT bin.
                for r from 1 to raw_peak_count
                    db0 = raw_peak_db_'r'
                    if db0 >= effectiveThreshold
                        refinedFreq = raw_peak_freq_'r'
                        tooClose = 0
                        for k from 1 to n_peaks
                            if abs(refinedFreq - peak_freq_'k') < min_peak_separation_Hz
                                if db0 > peak_db_'k'
                                    peak_freq_'k' = refinedFreq
                                    peak_db_'k' = db0
                                endif
                                tooClose = 1
                            endif
                        endfor
                        if not tooClose
                            n_peaks += 1
                            peak_freq_'n_peaks' = refinedFreq
                            peak_db_'n_peaks' = db0
                        endif
                    endif
                endfor

                # Partial selection sort: only order the strongest K entries.
                # This preserves the evidence set while avoiding O(N^2) full sort.
                keepCount = n_peaks
                if keepCount > max_peaks_to_keep
                    keepCount = max_peaks_to_keep
                endif
                for i from 1 to keepCount
                    bestJ = i
                    bestDb = peak_db_'i'
                    for j from i + 1 to n_peaks
                        if peak_db_'j' > bestDb
                            bestDb = peak_db_'j'
                            bestJ = j
                        endif
                    endfor
                    if bestJ <> i
                        tf = peak_freq_'i'
                        td = peak_db_'i'
                        peak_freq_'i' = peak_freq_'bestJ'
                        peak_db_'i' = peak_db_'bestJ'
                        peak_freq_'bestJ' = tf
                        peak_db_'bestJ' = td
                    endif
                endfor
                n_peaks = keepCount

                # Convert measured peaks to pitch-class evidence. Peaks that
                # align with integer harmonics of a lower-frequency peak are
                # softly downweighted rather than removed, preserving real
                # doubled notes while reducing overtone-induced false chords.
                for i from 1 to n_peaks
                    pf = peak_freq_'i'
                    pdb = peak_db_'i'
                    factor = 1
                    if downweight_harmonic_duplicates
                        for j from 1 to n_peaks
                            lowerF = peak_freq_'j'
                            lowerDb = peak_db_'j'
                            if lowerF < pf and lowerDb >= pdb - 24
                                ratio = pf / lowerF
                                hGuess = round(ratio)
                                if hGuess >= 2 and hGuess <= 8
                                    centsDiff = 1200 * abs(ln(ratio / hGuess) / ln(2))
                                    if centsDiff <= harmonic_tolerance_cents
                                        factor = harmonic_downweight
                                    endif
                                endif
                            endif
                        endfor
                    endif

                    relMag = 10 ^ ((pdb - channelMaxDb) / 20)
                    evidence = relMag * factor
                    midiNote = 69 + 12 * (ln(pf / tuning_A4_Hz) / ln(2))
                    midiRounded = round(midiNote)
                    pc = midiRounded mod 12
                    if pc < 0
                        pc += 12
                    endif
                    channel_pc_'pc' += evidence

                    # Weak bass tie-breaker: only a strong, non-downweighted
                    # low peak can define the frame bass pitch class.
                    channelWeight = channelFrameRms / (frameRms + epsilon)
                    if channelWeight > 1
                        channelWeight = 1
                    endif
                    if factor >= 0.5 and relMag * channelWeight >= 0.20 and pf < bassFreq
                        bassFreq = pf
                        bassPc = pc
                    endif
                endfor

                # Normalize within channel, weight by channel energy, then pool.
                channelPcMax = 0
                for pc from 0 to 11
                    if channel_pc_'pc' > channelPcMax
                        channelPcMax = channel_pc_'pc'
                    endif
                endfor
                channelWeight = channelFrameRms / (frameRms + epsilon)
                if channelWeight > 1
                    channelWeight = 1
                endif
                if channelPcMax > epsilon
                    for pc from 0 to 11
                        channel_pc_'pc' = channelWeight * channel_pc_'pc' / channelPcMax
                        if channel_pc_'pc' > pc_raw_'pc'
                            pc_raw_'pc' = channel_pc_'pc'
                        endif
                    endfor
                endif
            endif

            removeObject: spectrum, extract
        endfor

        # Normalize pitch-class salience within this frame.
        maxPc = 0
        for pc from 0 to 11
            if pc_raw_'pc' > maxPc
                maxPc = pc_raw_'pc'
            endif
        endfor

        activeCount = 0
        totalActive = 0
        if maxPc > epsilon
            for pc from 0 to 11
                pc_salience_'pc' = pc_raw_'pc' / maxPc
                if pc_salience_'pc' >= pc_floor
                    pc_active_'pc' = pc_salience_'pc'
                    activeCount += 1
                    totalActive += pc_active_'pc'
                    @pitchClassToName: pc
                    if notes_list$ <> ""
                        notes_list$ = notes_list$ + " "
                    endif
                    notes_list$ = notes_list$ + pitchClassToName.result$
                endif
            endfor
        endif

        if activeCount = 0
            chord_name$ = "No clear pitch"
        elsif detection_mode = 2 or activeCount = 1
            # Monophonic mode: simply report strongest pitch class.
            bestPc = 0
            bestPcVal = -1
            for pc from 0 to 11
                if pc_salience_'pc' > bestPcVal
                    bestPcVal = pc_salience_'pc'
                    bestPc = pc
                endif
            endfor
            @pitchClassToName: bestPc
            chord_name$ = pitchClassToName.result$
            winningRoot = bestPc
            winningQuality = 0
            confidence = 100
            bestScore = bestPcVal
            secondScore = 0
        elsif activeCount = 2
            # A dyad does not uniquely imply a harmonic root; report evidence
            # rather than overclaiming a chord inversion/root.
            chord_name$ = notes_list$
            confidence = 100 * abs(pc_active_0 + pc_active_1 + pc_active_2 + pc_active_3 + pc_active_4 + pc_active_5 + pc_active_6 + pc_active_7 + pc_active_8 + pc_active_9 + pc_active_10 + pc_active_11) / max(2, activeCount)
            if confidence > 100
                confidence = 100
            endif
        else
            bestScore = -999
            secondScore = -999
            winningRoot = -1
            winningQuality = 0

            # Only active pitch classes are plausible roots. This reduces
            # computation and avoids rootless overinterpretation.
            for tryRoot from 0 to 11
                if pc_active_'tryRoot' > 0
                    for quality from 1 to 15
                        @scoreChordCandidate: tryRoot, quality, totalActive, bassPc
                        candidate = scoreChordCandidate.score

                        if candidate > bestScore
                            secondScore = bestScore
                            bestScore = candidate
                            winningRoot = tryRoot
                            winningQuality = quality
                        elsif candidate > secondScore
                            # Ignore equivalent roots for symmetric templates.
                            equivalent = 0
                            if quality = 4 and winningQuality = 4
                                d = (tryRoot - winningRoot + 12) mod 12
                                if d mod 4 = 0
                                    equivalent = 1
                                endif
                            elsif quality = 11 and winningQuality = 11
                                d = (tryRoot - winningRoot + 12) mod 12
                                if d mod 3 = 0
                                    equivalent = 1
                                endif
                            endif
                            if not equivalent
                                secondScore = candidate
                            endif
                        endif
                    endfor
                endif
            endfor

            if secondScore < -900
                secondScore = 0
            endif
            confidence = 100 * (bestScore - secondScore) / (abs(bestScore) + epsilon)
            if confidence < 0
                confidence = 0
            elsif confidence > 100
                confidence = 100
            endif

            if winningRoot >= 0 and confidence >= min_confidence_percent
                @chordName: winningRoot, winningQuality
                chord_name$ = chordName.result$
            else
                chord_name$ = "Ambiguous: " + notes_list$
            endif
        endif

    endif

    # Frame ledger for TextGrid and visualization.
    frame_time_'frame_number' = frame_time
    frame_start_'frame_number' = analysis_time
    frame_label_'frame_number'$ = chord_name$
    frame_notes_'frame_number'$ = notes_list$
    frame_conf_'frame_number' = confidence
    frame_best_score_'frame_number' = bestScore
    frame_second_score_'frame_number' = secondScore

    if show_all_detections
        appendInfoLine: fixed$(frame_time, 3), " s: ", chord_name$, " | PCs: ", notes_list$, " | confidence ", fixed$(confidence, 1), "%"
    endif

    # Representative evidence frame: highest-confidence non-silence frame.
    if chord_name$ <> "Silence" and chord_name$ <> "No clear pitch" and confidence > bestFrameConfidence
        bestFrameConfidence = confidence
        bestFrameChord$ = chord_name$
        bestFrameRoot = winningRoot
        bestFrameQuality = winningQuality
        bestFrameTime = frame_time
        for pc from 0 to 11
            best_pc_'pc' = pc_salience_'pc'
        endfor
    endif

    # Temporal confirmation / hysteresis.
    if stable_chord$ = ""
        if chord_name$ = pending_chord$
            pending_count += 1
        else
            pending_chord$ = chord_name$
            pending_start = analysis_time
            pending_count = 1
        endif
        if pending_count >= min_confirm_frames
            stable_chord$ = pending_chord$
            stable_start = pending_start
            pending_chord$ = ""
            pending_count = 0
        endif
    else
        if chord_name$ = stable_chord$
            pending_chord$ = ""
            pending_count = 0
        else
            if chord_name$ = pending_chord$
                pending_count += 1
            else
                pending_chord$ = chord_name$
                pending_start = analysis_time
                pending_count = 1
            endif

            if pending_count >= min_confirm_frames
                if pending_start > stable_start
                    n_segments += 1
                    segment_start_'n_segments' = stable_start
                    segment_end_'n_segments' = pending_start
                    segment_label_'n_segments'$ = stable_chord$
                endif
                stable_chord$ = pending_chord$
                stable_start = pending_start
                pending_chord$ = ""
                pending_count = 0
            endif
        endif
    endif

    analysis_time += time_step
endwhile

# Close confirmed final segment. If nothing reached confirmation, preserve
# the longest pending interpretation rather than returning an empty grid.
if stable_chord$ <> ""
    n_segments += 1
    segment_start_'n_segments' = stable_start
    segment_end_'n_segments' = duration
    segment_label_'n_segments'$ = stable_chord$
elsif pending_chord$ <> ""
    n_segments += 1
    segment_start_'n_segments' = pending_start
    segment_end_'n_segments' = duration
    segment_label_'n_segments'$ = pending_chord$
endif

# ---------- Build TextGrid from the ledgers ----------
selectObject: sound
textgrid = To TextGrid: "chords pitch_classes", ""
Rename: sound_name$ + "_chords"

# Tier 1: confirmed chord segments.
for i from 1 to n_segments
    st = segment_start_'i'
    en = segment_end_'i'
    if st > 0.001 and st < duration - 0.001
        selectObject: textgrid
        Insert boundary: 1, st
    endif
    if i = n_segments and en < duration - 0.001
        selectObject: textgrid
        Insert boundary: 1, en
    endif
endfor
for i from 1 to n_segments
    st = segment_start_'i'
    en = segment_end_'i'
    mid = 0.5 * (st + en)
    selectObject: textgrid
    interval = Get interval at time: 1, mid
    Set interval text: 1, interval, segment_label_'i'$
endfor

# Tier 2: frame pitch-class evidence.
for i from 2 to frame_number
    b = frame_start_'i'
    if b > 0.001 and b < duration - 0.001
        selectObject: textgrid
        Insert boundary: 2, b
    endif
endfor
for i from 1 to frame_number
    st = frame_start_'i'
    sampleTime = st + 0.5 * time_step
    if sampleTime > duration
        sampleTime = duration - 0.001
    endif
    selectObject: textgrid
    interval = Get interval at time: 2, sampleTime
    Set interval text: 2, interval, frame_notes_'i'$
endfor

appendInfoLine: ""
appendInfoLine: "=== ANALYSIS COMPLETE ==="
appendInfoLine: "Frames: ", frame_number, " | confirmed segments: ", n_segments
if bestFrameConfidence >= 0
    appendInfoLine: "Strongest decision frame: ", bestFrameChord$, " at ", fixed$(bestFrameTime, 3), " s (", fixed$(bestFrameConfidence, 1), "%)"
endif
appendInfoLine: "TextGrid tiers: chords | pitch_classes"

# ---------- Visualization ----------
if draw_visualization
    @drawVisualization: analysisId, textgrid, duration, frame_number, n_segments, presetName$, analysisChannel
endif

# ---------- Optional editor ----------
selectObject: sound
plusObject: textgrid
if open_TextGrid_editor
    View & Edit
endif

# Leave source + TextGrid selected.
selectObject: sound
plusObject: textgrid
for ch from 1 to n_channels
    removeObject: analysis_ch_id_'ch'
endfor

# ============================================================
# Procedures
# ============================================================

procedure pitchClassToName: .pc
    if .pc = 0
        .result$ = "C"
    elsif .pc = 1
        .result$ = "C#"
    elsif .pc = 2
        .result$ = "D"
    elsif .pc = 3
        .result$ = "D#"
    elsif .pc = 4
        .result$ = "E"
    elsif .pc = 5
        .result$ = "F"
    elsif .pc = 6
        .result$ = "F#"
    elsif .pc = 7
        .result$ = "G"
    elsif .pc = 8
        .result$ = "G#"
    elsif .pc = 9
        .result$ = "A"
    elsif .pc = 10
        .result$ = "A#"
    else
        .result$ = "B"
    endif
endproc

procedure scoreChordCandidate: .root, .quality, .totalActive, .bassPc
    # Collect template pitch classes.
    .size = 3
    .i1 = 0
    .i2 = 0
    .i3 = 0
    .i4 = -1
    if .quality = 1
        .i1 = 0
        .i2 = 4
        .i3 = 7
    elsif .quality = 2
        .i1 = 0
        .i2 = 3
        .i3 = 7
    elsif .quality = 3
        .i1 = 0
        .i2 = 3
        .i3 = 6
    elsif .quality = 4
        .i1 = 0
        .i2 = 4
        .i3 = 8
    elsif .quality = 5
        .i1 = 0
        .i2 = 2
        .i3 = 7
    elsif .quality = 6
        .i1 = 0
        .i2 = 5
        .i3 = 7
    elsif .quality = 7
        .size = 4
        .i1 = 0
        .i2 = 4
        .i3 = 7
        .i4 = 10
    elsif .quality = 8
        .size = 4
        .i1 = 0
        .i2 = 4
        .i3 = 7
        .i4 = 11
    elsif .quality = 9
        .size = 4
        .i1 = 0
        .i2 = 3
        .i3 = 7
        .i4 = 10
    elsif .quality = 10
        .size = 4
        .i1 = 0
        .i2 = 3
        .i3 = 6
        .i4 = 10
    elsif .quality = 11
        .size = 4
        .i1 = 0
        .i2 = 3
        .i3 = 6
        .i4 = 9
    elsif .quality = 12
        .size = 4
        .i1 = 0
        .i2 = 4
        .i3 = 7
        .i4 = 9
    elsif .quality = 13
        .size = 4
        .i1 = 0
        .i2 = 3
        .i3 = 7
        .i4 = 9
    elsif .quality = 14
        .size = 4
        .i1 = 0
        .i2 = 2
        .i3 = 4
        .i4 = 7
    else
        .size = 4
        .i1 = 0
        .i2 = 2
        .i3 = 3
        .i4 = 7
    endif

    .p1 = (.root + .i1) mod 12
    .p2 = (.root + .i2) mod 12
    .p3 = (.root + .i3) mod 12
    .sumIn = pc_active_'.p1' + pc_active_'.p2' + pc_active_'.p3'
    .coverage = 0
    if pc_active_'.p1' > 0
        .coverage += 1
    endif
    if pc_active_'.p2' > 0
        .coverage += 1
    endif
    if pc_active_'.p3' > 0
        .coverage += 1
    endif
    if .size = 4
        .p4 = (.root + .i4) mod 12
        .sumIn += pc_active_'.p4'
        if pc_active_'.p4' > 0
            .coverage += 1
        endif
    endif

    .coverage /= .size
    .sumOut = .totalActive - .sumIn
    if .sumOut < 0
        .sumOut = 0
    endif
    .rootEvidence = pc_active_'.root'
    .bassBonus = 0
    if .root = .bassPc
        .bassBonus = 0.10
    endif

    # Match present template tones, penalize unexplained pitch classes,
    # reward complete templates and measured root evidence. Bass is only
    # a weak tie-breaker so ordinary inversions remain template-driven.
    .score = (.sumIn / .size) - 0.18 * .sumOut + 0.12 * .coverage + 0.05 * .rootEvidence + .bassBonus
    scoreChordCandidate.score = .score
endproc

procedure chordName: .root, .quality
    @pitchClassToName: .root
    .rootName$ = pitchClassToName.result$
    if .quality = 1
        .suffix$ = " Major"
    elsif .quality = 2
        .suffix$ = " Minor"
    elsif .quality = 3
        .suffix$ = " Diminished"
    elsif .quality = 4
        .suffix$ = " Augmented"
    elsif .quality = 5
        .suffix$ = " Sus2"
    elsif .quality = 6
        .suffix$ = " Sus4"
    elsif .quality = 7
        .suffix$ = " Dom7"
    elsif .quality = 8
        .suffix$ = " Maj7"
    elsif .quality = 9
        .suffix$ = " Min7"
    elsif .quality = 10
        .suffix$ = " m7b5"
    elsif .quality = 11
        .suffix$ = " Dim7"
    elsif .quality = 12
        .suffix$ = "6"
    elsif .quality = 13
        .suffix$ = " m6"
    elsif .quality = 14
        .suffix$ = " add9"
    else
        .suffix$ = " m(add9)"
    endif
    .result$ = .rootName$ + .suffix$
endproc

procedure templateMember: .root, .quality, .pc
    .interval = (.pc - .root + 12) mod 12
    .result = 0
    if .quality = 1 and (.interval = 0 or .interval = 4 or .interval = 7)
        .result = 1
    elsif .quality = 2 and (.interval = 0 or .interval = 3 or .interval = 7)
        .result = 1
    elsif .quality = 3 and (.interval = 0 or .interval = 3 or .interval = 6)
        .result = 1
    elsif .quality = 4 and (.interval = 0 or .interval = 4 or .interval = 8)
        .result = 1
    elsif .quality = 5 and (.interval = 0 or .interval = 2 or .interval = 7)
        .result = 1
    elsif .quality = 6 and (.interval = 0 or .interval = 5 or .interval = 7)
        .result = 1
    elsif .quality = 7 and (.interval = 0 or .interval = 4 or .interval = 7 or .interval = 10)
        .result = 1
    elsif .quality = 8 and (.interval = 0 or .interval = 4 or .interval = 7 or .interval = 11)
        .result = 1
    elsif .quality = 9 and (.interval = 0 or .interval = 3 or .interval = 7 or .interval = 10)
        .result = 1
    elsif .quality = 10 and (.interval = 0 or .interval = 3 or .interval = 6 or .interval = 10)
        .result = 1
    elsif .quality = 11 and (.interval = 0 or .interval = 3 or .interval = 6 or .interval = 9)
        .result = 1
    elsif .quality = 12 and (.interval = 0 or .interval = 4 or .interval = 7 or .interval = 9)
        .result = 1
    elsif .quality = 13 and (.interval = 0 or .interval = 3 or .interval = 7 or .interval = 9)
        .result = 1
    elsif .quality = 14 and (.interval = 0 or .interval = 2 or .interval = 4 or .interval = 7)
        .result = 1
    elsif .quality = 15 and (.interval = 0 or .interval = 2 or .interval = 3 or .interval = 7)
        .result = 1
    endif
    templateMember.result = .result
endproc

procedure drawVisualization: .analysisId, .textgrid, .duration, .nFrames, .nSegments, .preset$, .analysisChannel
    Erase all

    # House style / geometry: 8 wide, 5.3 high.
    .blue$ = "{0.18,0.43,0.72}"
    .red$ = "{0.72,0.28,0.22}"
    .gray$ = "{0.55,0.55,0.55}"
    .light$ = "{0.95,0.95,0.95}"
    .grid$ = "{0.82,0.82,0.82}"

    # Header title.
    Select outer viewport: 0, 8, 0.02, 0.38
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Chord Detection v0.4.1 - " + .preset$

    Select outer viewport: 0, 8, 0.40, 0.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: .gray$
    Text: 0.5, "centre", 0.5, "half", "measured peaks -> harmonic downweighting -> pitch classes -> chord template -> confirmation"

    # ---------- A title ----------
    Select outer viewport: 0.12, 3.90, 0.78, 1.03
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  ANALYSIS CHANNEL"
    Font size: 6
    Colour: .gray$
    Text: 0.98, "right", 0.5, "half", "representative channel " + string$(.analysisChannel)

    # ---------- A data ----------
    Select inner viewport: 0.48, 3.82, 1.08, 2.48
    selectObject: .analysisId
    .mx = Get maximum: 0, 0, "Sinc70"
    .mn = Get minimum: 0, 0, "Sinc70"
    .amp = max(abs(.mx), abs(.mn))
    if .amp < 1e-12
        .amp = 1
    endif
    .amp *= 1.05
    Colour: .gray$
    Draw: 0, .duration, -.amp, .amp, "no", "Curve"
    Axes: 0, .duration, -.amp, .amp
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Time (s)"

    # Segment boundaries over waveform. Re-select the data viewport after
    # Draw inner box / marks so Picture state cannot leak from the garnish.
    Select inner viewport: 0.48, 3.82, 1.08, 2.48
    Axes: 0, .duration, -.amp, .amp
    Colour: .grid$
    Line width: 1
    for .i from 2 to .nSegments
        .x = segment_start_'.i'
        Draw line: .x, -.amp, .x, .amp
    endfor

    # ---------- B title ----------
    Select outer viewport: 4.10, 7.88, 0.78, 1.03
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  CONFIRMED CHORD TIMELINE"

    # ---------- B data ----------
    Select inner viewport: 4.46, 7.80, 1.08, 2.48
    Axes: 0, .duration, 0, 1
    Paint rectangle: .light$, 0, .duration, 0, 1
    for .i from 1 to .nSegments
        .st = segment_start_'.i'
        .en = segment_end_'.i'
        .lab$ = segment_label_'.i'$
        if index(.lab$, "Major") > 0 or index(.lab$, "Maj7") > 0
            .c$ = "{0.38,0.64,0.42}"
        elsif index(.lab$, "Minor") > 0 or index(.lab$, "Min7") > 0
            .c$ = "{0.42,0.50,0.72}"
        elsif index(.lab$, "Ambiguous") > 0
            .c$ = "{0.72,0.66,0.42}"
        elsif .lab$ = "Silence" or .lab$ = "No clear pitch"
            .c$ = "{0.82,0.82,0.82}"
        else
            .c$ = "{0.58,0.63,0.67}"
        endif
        Paint rectangle: .c$, .st, .en, 0.12, 0.88
        if .en - .st > max(0.22, .duration / 14)
            Colour: "Black"
            Font size: 6
            Text: 0.5 * (.st + .en), "centre", 0.5, "half", .lab$
        endif
    endfor
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Time (s)"

    # ---------- C title ----------
    Select outer viewport: 0.12, 3.90, 2.70, 2.98
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  BEST-FRAME PITCH-CLASS EVIDENCE"

    # ---------- C data ----------
    Select inner viewport: 0.48, 3.82, 3.03, 4.48
    Axes: 0, 12, -0.18, 1.08
    Colour: .grid$
    Draw line: 0, pc_floor, 12, pc_floor
    for .pc from 0 to 11
        .v = best_pc_'.pc'
        .member = 0
        if bestFrameQuality > 0 and bestFrameRoot >= 0
            @templateMember: bestFrameRoot, bestFrameQuality, .pc
            .member = templateMember.result
        endif
        if .member
            .c$ = .blue$
        else
            .c$ = "{0.68,0.68,0.68}"
        endif
        Paint rectangle: .c$, .pc + 0.12, .pc + 0.88, 0, .v
        @pitchClassToName: .pc
        Colour: "Black"
        Font size: 6
        Text: .pc + 0.5, "centre", -0.09, "half", pitchClassToName.result$
    endfor
    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Normalized salience"

    # ---------- D title ----------
    Select outer viewport: 4.10, 7.88, 2.70, 2.98
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "D  DECISION CONFIDENCE"
    Font size: 6
    Colour: .gray$
    Text: 0.98, "right", 0.5, "half", "best-vs-runner-up score margin"

    # ---------- D data ----------
    Select inner viewport: 4.46, 7.80, 3.03, 4.48
    Axes: 0, .duration, 0, 100
    Colour: .grid$
    Dotted line
    Draw line: 0, min_confidence_percent, .duration, min_confidence_percent
    Solid line
    Colour: .blue$
    Line width: 1.5
    .havePrev = 0
    for .i from 1 to .nFrames
        .x = frame_time_'.i'
        .y = frame_conf_'.i'
        if .havePrev
            Draw line: .px, .py, .x, .y
        endif
        .px = .x
        .py = .y
        .havePrev = 1
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 25, "yes", "yes", "no"
    Marks bottom: 3, "yes", "yes", "no"
    Font size: 7
    Text left: "yes", "Confidence (%)"
    Text bottom: "yes", "Time (s)"

    # Footer summary.
    Select outer viewport: 0.15, 7.85, 4.78, 5.17
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96,0.96,0.96}", 0, 1, 0.15, 0.85
    Font size: 7
    Colour: "{0.30,0.30,0.30}"
    .footer$ = "frames=" + string$(.nFrames) + " | segments=" + string$(.nSegments) + " | A4=" + fixed$(tuning_A4_Hz, 1) + " Hz | peaks<=" + string$(max_peaks_to_keep) + " | PC floor=" + fixed$(pitch_class_floor_percent, 0) + "% | confirm=" + fixed$(min_chord_duration_ms, 0) + " ms"
    Text: 0.5, "centre", 0.5, "half", .footer$

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
