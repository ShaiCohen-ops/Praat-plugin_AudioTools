# ============================================================
# Praat AudioTools - KDTreeTimbralCounterpoint.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   KD-Tree Timbral Counterpoint
#
#   Creates N contrapuntal layers from a target sound by searching
#   a corpus for grains at different timbral distances. A KD-Tree
#   provides efficient N-dimensional nearest-neighbour lookup across
#   weighted MFCC, pitch, centroid, intensity and HNR/ZCR features.
#   Each voice is assigned a different neighbour rank, producing
#   layers ranging from close imitation to distant timbral echo.
#
#   Voice separation rules:
#   - Voice 1 (close):  rank 1  | centre pan     | 0 ms delay
#   - Voice 2 (shadow): rank 3  | alt ±0.5 pan   | 20 ms delay
#   - Voice 3 (cousin): rank 8  | wide ±0.8 pan  | 45 ms delay
#   - Voice 4 (ghost):  rank 20 | random pan     | 80 ms delay
#
#   ENGINEERING NOTES:
#   - Track scheduling: each voice's grains are scheduled into
#     a FIFO list of "tracks" where each track holds only
#     non-overlapping grains. Tracks are concatenated linearly
#     then additively mixed into the voice sound. This avoids
#     per-grain Formula writes (which would be slow).
#   - Corpus file caching: the matching CSV is sorted by file
#     path so each unique corpus file is opened only once.
#   - Cosine fade-in/out is split into two separate Formula
#     passes (the recursive elsif pattern doesn't work reliably
#     inside Praat's Formula context).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.3:
#   BUG FIX (changes audio output):
#   - MFCC extraction used the wrong argument order. `Get value in frame:`
#     takes (frameNumber, index); the script passed (index, frameNumber).
#     Since the MFCC time step is 0.005 s, every grain past roughly 65 ms
#     asked for a coefficient index beyond the 12 that exist, got undefined,
#     and the guard clamped it to 0. Verified on 6.4.06: (1, 100) returns
#     undefined, (100, 1) returns 26.67. Consequence: mfcc1-mfcc6 were 0.0
#     for every row of both feature CSVs, mfcc_distance was 0.0 on every
#     match, and the KD-tree was matching on centroid, pitch, intensity, HNR
#     and ZCR only — the MFCC weight did nothing. Output WILL differ from
#     v1.2.1 for every preset, because matching now uses the feature the
#     script was named for.
#   VISUALIZATION (rebuilt around results instead of parameters):
#   - Removed the voice-timeline panel. Hop is grain x (1 - overlap/100), so
#     hop <= grain always and adjacent blocks always abut: the panel rendered
#     as solid bars at every setting, including 0% overlap. It also plotted
#     scheduled grains, so pause-gating never appeared in it.
#   - Removed the parameter report panel. Every field in it also appeared in
#     the subtitle, the summary bar and the Info window.
#   - Removed Show_spectrograms and both spectrogram panels, with the two
#     `To Spectrogram` calls they needed.
#   - NEW Panel A: timbral distance per grain over time, one line per voice,
#     with per-voice means. This is the script's premise, plotted.
#   - NEW Panel B: grain provenance — one block per grain coloured by corpus
#     file, consecutive grains alternating half-lanes so overlap and grain
#     count stay legible.
#   - NEW Panel C: voice separation — distance min/max/mean per voice with
#     requested vs actually used neighbour rank.
#   - NEW Panel D: corpus usage — grains drawn per corpus file, which makes
#     repetition-penalty behaviour and corpus coverage visible.
#   - Removed the target and mix waveform panels. The output waveform says
#     nothing about the matching decisions this figure exists to report, and
#     the reclaimed height goes to the four panels that do.
#   - Summary bar reports mean MFCC contribution, and warns outright if the
#     MFCC weight is non-zero while its contribution is 0 — the condition
#     that hid the bug above.
#   - Layout follows the suite drawing rules: font set before viewport
#     selection, viewport re-selected between drawing groups, no
#     `Text bottom:` / `Text left:` (units moved into panel captions, panel
#     names onto a rotated left rail), and the full canvas re-selected at the
#     end so Save/Copy captures the whole figure.
# Changelog v1.2.1:
#   - FIXED stereo corpus reconstruction: every multichannel corpus grain is
#     downmixed to mono before stereo duplication and constant-power panning.
#     Reconstruction now uses the same mono timbral content represented by the
#     feature analysis, instead of retaining the original L/R image for stereo
#     corpus files. Matching, scheduling and all other DSP are unchanged.
#   - Runtime banner synchronized to v1.2.1.
# Changelog v1.2:
#   - Sample-accurate track scheduler: start times and silence gaps are
#     quantized to the target sample grid, eliminating zero-sample Sound
#     creation caused by floating-point residue.
#   - Track end times now follow the actual durations of concatenated
#     objects rather than theoretical CSV times.
#   - Short-sound analysis padding is sample-quantized and safely skips
#     unrepresentable sub-sample padding.
#   - Includes the multichannel, target-SR, concatenate-order, validation,
#     envelope-analysis, cleanup and output-safety fixes from the 2026
#     reconstruction hardening pass.
# Changelog v1.1:
#   - Audio pipeline UNCHANGED. Output bit-identical to v1.0
#     for the same form parameters and same RNG state. Same
#     feature extraction, same KD-tree matching (Python helper
#     unchanged), same track-scheduling reconstruction, same
#     pause-gate and amplitude-envelope shaping, same trim and
#     fade-out.
#   - Fix: == comparison on line 319 (nFiles == 0) changed to
#     = (Praat's documented comparison operator). v1.0 used ==
#     as an alias which works in current Praat but isn't
#     guaranteed.
#   - NEW: Show_spectrograms form toggle (default OFF). v1.0
#     always computed `To Spectrogram` twice (target + mix) for
#     the visualization panels — that can take several seconds
#     on long files. Default OFF means the script's wallclock
#     is dominated only by feature extraction and audio
#     reconstruction. Turn ON to see the time-frequency
#     comparison.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): voice timeline — promoted
#         from v1.0's bottom-of-canvas position. This is the
#         script's most distinctive visual.
#       Panel B (right, headline): parameter report
#       Panel C (full width): target waveform (or target
#         spectrogram when Show_spectrograms = ON)
#       Panel D (full width): mix waveform (or mix
#         spectrogram when Show_spectrograms = ON)
#       Panel E: summary stats bar
#   - Header documents the engineering pieces (track scheduling,
#     file caching, two-pass cosine fade) so future maintainers
#     understand what is intentional.
# Changelog v1.0:
#   - Initial unified cross-platform release.
# ============================================================

form KD-Tree Timbral Counterpoint v1.3
    comment ── Target & Corpus ──
    sentence Corpus_folder /Users/username/Desktop/Corpus
    real Grain_size_ms 200
    real Grain_overlap_percent 50
    comment ── Architecture ──
    integer Number_of_voices 4
    sentence Neighbor_ranks 1, 3, 8, 20
    comment ── Aesthetics ──
    optionmenu Preset: 2
        option Custom
        option Strict Doppelgänger
        option Spectral Counterpoint
        option Ghost Choir
        option Orchestral Shadow
        option Noise Doppelgänger
    real Mfcc_weight 1.0
    real Pitch_weight 0.8
    real Spectral_centroid_weight 0.5
    real Intensity_weight 0.5
    real Hnr_weight 0.5
    real Randomness_amount 0.2
    boolean Repetition_penalty 1
    comment ── Output ──
    optionmenu Output_mode: 1
        option Mixdown
        option Separate voices
        option Both
    real Crossfade_duration 0.05
    optionmenu Envelope_shaping: 4
        option Off
        option Pauses only
        option Amplitude envelope only
        option Pauses + Amplitude envelope
    boolean Draw_visualization 1
    boolean Play_result 1
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one target Sound object."
endif
targetObj = selected("Sound")
soundName$ = selected$("Sound")
targetDur = Get total duration
targetSR = Get sampling frequency

# ---- PARAMETER VALIDATION ----
if grain_size_ms <= 0
    exitScript: "Grain size must be greater than 0 ms."
endif
if grain_overlap_percent < 0 or grain_overlap_percent >= 100
    exitScript: "Grain overlap must be in the range 0 <= overlap < 100 percent."
endif
if number_of_voices < 1
    exitScript: "Number of voices must be at least 1."
endif
if crossfade_duration < 0
    exitScript: "Crossfade duration cannot be negative."
endif
if not folderExists(corpus_folder$)
    exitScript: "Corpus folder not found: " + corpus_folder$
endif

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/kd_tree_timbral_counterpoint.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/kd_tree_timbral_counterpoint.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: kd_tree_timbral_counterpoint.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

# Apply preset overrides
eff_randomness = randomness_amount
eff_ranks$ = neighbor_ranks$
eff_mfcc_w = mfcc_weight
eff_pitch_w = pitch_weight
eff_cent_w = spectral_centroid_weight
eff_int_w = intensity_weight
eff_hnr_w = hnr_weight

if preset = 2 ; Strict Doppelgänger
    eff_randomness = 0.05
    eff_ranks$ = "1, 2, 3, 4"
    eff_mfcc_w = 1.5
    eff_int_w = 1.0
    presetName$ = "StrictDoppelganger"
elsif preset = 3 ; Spectral Counterpoint
    eff_randomness = 0.2
    eff_ranks$ = "1, 3, 8, 20"
    presetName$ = "SpectralCounterpoint"
elsif preset = 4 ; Ghost Choir
    eff_randomness = 0.5
    eff_ranks$ = "5, 12, 25, 50"
    presetName$ = "GhostChoir"
elsif preset = 5 ; Orchestral Shadow
    eff_randomness = 0.2
    eff_pitch_w = 1.5
    eff_cent_w = 1.2
    presetName$ = "OrchestraShadow"
elsif preset = 6 ; Noise Doppelgänger
    eff_randomness = 0.2
    eff_hnr_w = 2.0
    eff_cent_w = 1.5
    presetName$ = "NoiseDoppelganger"
else
    presetName$ = "Custom"
endif

if eff_randomness < 0 or eff_randomness > 1
    exitScript: "Randomness amount must be between 0 and 1."
endif
if eff_mfcc_w < 0 or eff_pitch_w < 0 or eff_cent_w < 0 or eff_int_w < 0 or eff_hnr_w < 0
    exitScript: "Feature weights cannot be negative."
endif
if eff_mfcc_w = 0 and eff_pitch_w = 0 and eff_cent_w = 0 and eff_int_w = 0 and eff_hnr_w = 0
    exitScript: "At least one feature weight must be greater than zero."
endif

# Temp Paths
tempTargCSV$  = temporaryDirectory$ + "/temp_kdtc_target.csv"
tempCorpCSV$  = temporaryDirectory$ + "/temp_kdtc_corpus.csv"
tempMatchCSV$ = temporaryDirectory$ + "/temp_kdtc_match.csv"
tempStderr$   = temporaryDirectory$ + "/temp_kdtc_stderr.log"

procedure cleanUpTempFiles
    if fileReadable(tempTargCSV$)
        deleteFile: tempTargCSV$
    endif
    if fileReadable(tempCorpCSV$)
        deleteFile: tempCorpCSV$
    endif
    if fileReadable(tempMatchCSV$)
        deleteFile: tempMatchCSV$
    endif
    if fileReadable(tempStderr$)
        deleteFile: tempStderr$
    endif
endproc

@cleanUpTempFiles

grain_sec = grain_size_ms / 1000
hop = grain_sec * (1 - grain_overlap_percent / 100)

procedure extractFeatures: .sndObj, .fPath$, .csvTable, .isCorpus
    selectObject: .sndObj
    .dur = Get total duration
    .nCh = Get number of channels

    # Use one consistent mono analysis signal for target and corpus material.
    # This avoids channel-1-only ZCR/centroid behaviour and makes multichannel
    # corpus files comparable to mono/stereo files in the feature space.
    if .nCh > 1
        Convert to mono
        .monoObj = selected("Sound")
        .baseAnalysisObj = .monoObj
        .createdMonoObj = 1
    else
        .baseAnalysisObj = .sndObj
        .createdMonoObj = 0
    endif

    # Guard against sounds shorter than the analysis window minimum.
    # To Intensity (pitchFloor=100) needs >= 6.4/100 = 0.064 s.
    # To Pitch      (pitchFloor=75)  needs >= 3/75   ~= 0.040 s.
    # Use 0.1 s as a safe floor: pad the mono analysis signal if needed.
    .minAnalysisDur = 0.1
    if .dur < .minAnalysisDur
        .padDur = .minAnalysisDur - .dur
        selectObject: .baseAnalysisObj
        .sr_pad = Get sampling frequency
        .padSamples = round(.padDur * .sr_pad)
        if .padSamples >= 1
            .padDurQ = .padSamples / .sr_pad
            Create Sound from formula: "pad_sil", 1, 0, .padDurQ, .sr_pad, "0"
            .padSil = selected("Sound")
            selectObject: .baseAnalysisObj
            plusObject: .padSil
            Concatenate
            .analysisObj = selected("Sound")
            removeObject: .padSil
            .createdAnalysisObj = 1
        else
            # Sub-sample padding is not representable as a Sound.
            .analysisObj = .baseAnalysisObj
            .createdAnalysisObj = 0
        endif
    else
        .analysisObj = .baseAnalysisObj
        .createdAnalysisObj = 0
    endif

    selectObject: .analysisObj
    To Pitch: 0, 75, 600
    .pitch = selected("Pitch")

    selectObject: .analysisObj
    To MFCC: 12, 0.015, 0.005, 100, 100, 0
    .mfcc = selected("MFCC")

    selectObject: .analysisObj
    To Intensity: 100, 0, "yes"
    .int = selected("Intensity")

    selectObject: .analysisObj
    To Harmonicity (cc): 0.01, 75, 0.1, 1.0
    .harm = selected("Harmonicity")

    .nGrains = floor((.dur - grain_sec) / hop) + 1
    if .nGrains < 1
        .nGrains = 1
    endif

    for .iG from 1 to .nGrains
        .start = (.iG - 1) * hop
        .end = .start + grain_sec
        if .end > .dur
            .end = .dur
        endif
        .t_mid = .start + (.end - .start) / 2

        selectObject: .pitch
        .pval = Get value at time: .t_mid, "Hertz", "Linear"
        if .pval = undefined
            .pval = 0
        endif

        selectObject: .mfcc
        .nFrames = Get number of frames
        .raw_frame = Get frame from time: .t_mid
        .frame = round(.raw_frame)
        if .frame < 1
            .frame = 1
        elsif .frame > .nFrames
            .frame = .nFrames
        endif

        .m1 = Get value in frame: .frame, 1
        if .m1 = undefined
            .m1 = 0
        endif
        .m2 = Get value in frame: .frame, 2
        if .m2 = undefined
            .m2 = 0
        endif
        .m3 = Get value in frame: .frame, 3
        if .m3 = undefined
            .m3 = 0
        endif
        .m4 = Get value in frame: .frame, 4
        if .m4 = undefined
            .m4 = 0
        endif
        .m5 = Get value in frame: .frame, 5
        if .m5 = undefined
            .m5 = 0
        endif
        .m6 = Get value in frame: .frame, 6
        if .m6 = undefined
            .m6 = 0
        endif

        selectObject: .int
        .ival = Get mean: .start, .end, "energy"
        if .ival = undefined
            .ival = 0
        endif

        selectObject: .harm
        .hval = Get mean: .start, .end
        if .hval = undefined
            .hval = -200
        endif

        # Spectral centroid and ZCR use the same mono analysis signal.
        selectObject: .analysisObj
        Extract part: .start, .end, "rectangular", 1, "no"
        .part = selected("Sound")
        To Spectrum: "yes"
        .spec = selected("Spectrum")
        .cval = Get centre of gravity: 2.0
        if .cval = undefined
            .cval = 0
        endif

        selectObject: .part
        To PointProcess (zeroes): 1, "yes", "no"
        .part_ppz = selected("PointProcess")
        .nz = Get number of points
        .zcr = .nz / max(0.001, .end - .start)

        removeObject: .part_ppz, .part, .spec

        selectObject: .csvTable
        Append row
        .r = Get number of rows
        Set string value: .r, "file_path", .fPath$
        Set numeric value: .r, "start_time", .start
        Set numeric value: .r, "end_time", .end
        Set numeric value: .r, "mfcc1", .m1
        Set numeric value: .r, "mfcc2", .m2
        Set numeric value: .r, "mfcc3", .m3
        Set numeric value: .r, "mfcc4", .m4
        Set numeric value: .r, "mfcc5", .m5
        Set numeric value: .r, "mfcc6", .m6
        Set numeric value: .r, "centroid", .cval
        Set numeric value: .r, "pitch", .pval
        Set numeric value: .r, "intensity", .ival
        Set numeric value: .r, "hnr", .hval
        Set numeric value: .r, "zcr", .zcr
    endfor

    removeObject: .pitch, .mfcc, .int, .harm
    if .createdAnalysisObj
        removeObject: .analysisObj
    endif
    if .createdMonoObj
        removeObject: .monoObj
    endif
endproc

clearinfo
writeInfoLine: "KD-Tree Timbral Counterpoint v1.3 running..."

# 1. Target Features
appendInfoLine: "[1/4] Extracting Target Features..."
Create Table with column names: "target", 0, "file_path start_time end_time mfcc1 mfcc2 mfcc3 mfcc4 mfcc5 mfcc6 centroid pitch intensity hnr zcr"
targetTable = selected("Table")
@extractFeatures: targetObj, "target", targetTable, 0
Save as comma-separated file: tempTargCSV$
removeObject: targetTable

# 2. Corpus Features
appendInfoLine: "[2/4] Extracting Corpus Features..."
Create Strings as file list: "list", corpus_folder$ + "/*.wav"
fileList = selected("Strings")
nFiles = Get number of strings

# v1.1 fix: == changed to = (Praat's documented comparison operator)
if nFiles = 0
    removeObject: fileList
    @cleanUpTempFiles
    exitScript: "Error: No .wav files found in the specified Corpus folder: " + corpus_folder$
endif

Create Table with column names: "corpus", 0, "file_path start_time end_time mfcc1 mfcc2 mfcc3 mfcc4 mfcc5 mfcc6 centroid pitch intensity hnr zcr"
corpusTable = selected("Table")

for iF from 1 to nFiles
    selectObject: fileList
    fName$ = Get string: iF
    fPath$ = corpus_folder$ + "/" + fName$
    Read from file: fPath$
    cObj = selected("Sound")
    @extractFeatures: cObj, fPath$, corpusTable, 1
    removeObject: cObj
endfor

selectObject: corpusTable
Save as comma-separated file: tempCorpCSV$
removeObject: corpusTable, fileList

# 3. KD-Tree Mapping via Python
appendInfoLine: "[3/4] Generating Contrapuntal Mapping (KD-Tree)..."
weightStr$ = string$(eff_mfcc_w) + "," + string$(eff_pitch_w) + "," + string$(eff_cent_w) + "," + string$(eff_int_w) + "," + string$(eff_hnr_w)

cmd$ = pythonCmd$ + " """ + pythonScript$ + """ """ + tempTargCSV$ + """ """ + tempCorpCSV$ + """ """ + tempMatchCSV$ + """ --voices " + string$(number_of_voices) + " --ranks """ + eff_ranks$ + """ --weights """ + weightStr$ + """ --randomness " + string$(eff_randomness) + " --rep_penalty " + string$(repetition_penalty) + " 2> """ + tempStderr$ + """"
runSystem_nocheck: cmd$

if not fileReadable(tempMatchCSV$)
    if fileReadable(tempStderr$)
        err_txt$ = readFile$(tempStderr$)
    else
        err_txt$ = "(no Python stderr was captured)"
    endif
    @cleanUpTempFiles
    exitScript: "PYTHON ERROR:" + newline$ + err_txt$
endif

# Non-fatal Python warnings are shown but do not invalidate a valid mapping.
if fileReadable(tempStderr$)
    err_txt$ = readFile$(tempStderr$)
    if length(err_txt$) > 0
        appendInfoLine: "Python diagnostics:"
        appendInfoLine: err_txt$
    endif
endif

# 4. Audio Reconstruction 
appendInfoLine: "[4/4] Resynthesizing Polyphony..."

Read Table from comma-separated file: tempMatchCSV$
mapTable = selected("Table")

selectObject: mapTable
Sort rows: "selected_corpus_file"
nRows = Get number of rows

for v from 1 to number_of_voices
    vg_idx[v] = 0
endfor

corpusAudio = 0
prev_file$ = ""
nUsedFiles = 0

for r from 1 to nRows
    selectObject: mapTable
    
    c_file$ = Get value: r, "selected_corpus_file"
    c_start = Get value: r, "selected_corpus_start_time"
    c_end   = Get value: r, "selected_corpus_end_time"
    t_start = Get value: r, "target_start_time"
    gain    = Get value: r, "final_gain"
    pan     = Get value: r, "pan_position"
    delay   = Get value: r, "delay_ms"
    voice   = Get value: r, "voice_number"

    # Match metrics, kept for the figure. These are the only record of what
    # the KD-tree actually decided; the table is removed before drawing.
    m_dist  = Get value: r, "distance"
    m_mdist = Get value: r, "mfcc_distance"
    m_rank  = Get value: r, "neighbor_rank"

    if c_file$ <> prev_file$
        if corpusAudio <> 0
            removeObject: corpusAudio
        endif
        Read from file: c_file$
        corpusAudio = selected("Sound")
        prev_file$ = c_file$
        # The table is sorted by file path, so each distinct corpus file is
        # seen exactly once here: this doubles as the provenance index.
        nUsedFiles = nUsedFiles + 1
        @baseName: c_file$
        usedFileName$[nUsedFiles] = baseName$
        usedFileCount[nUsedFiles] = 0
    endif
    usedFileCount[nUsedFiles] = usedFileCount[nUsedFiles] + 1
    
    selectObject: corpusAudio
    Extract part: c_start, c_end, "rectangular", 1, "no"
    grainTemp = selected("Sound")
    
    selectObject: grainTemp
    grainDur = Get total duration
    fade = min(crossfade_duration, grainDur / 2)

    # Cosine fade-in then fade-out, clamped so the two fades can never
    # extend beyond the grain itself. A zero crossfade skips both formulas.
    if fade > 0
        Formula: "if x < xmin + 'fade' then self * (0.5 - 0.5*cos(pi*(x-xmin)/'fade')) else self fi"
        Formula: "if x > xmax - 'fade' then self * (0.5 - 0.5*cos(pi*(xmax-x)/'fade')) else self fi"
    endif
    Formula: "self * 'gain'"

    angle = (pan + 1) * pi / 4
    lg = cos(angle)
    rg = sin(angle)

    # The reconstruction engine is stereo. Mono corpus grains are duplicated;
    # multichannel grains are first downmixed to mono, then duplicated, so the
    # KDTC pan law controls the final stereo position consistently.
    selectObject: grainTemp
    nChan = Get number of channels
    if nChan > 1
        Convert to mono
        grainMono = selected("Sound")
        removeObject: grainTemp
    else
        grainMono = grainTemp
    endif

    selectObject: grainMono
    Convert to stereo
    grainStereo = selected("Sound")
    removeObject: grainMono

    selectObject: grainStereo
    Formula: "if row = 1 then self * 'lg' else self * 'rg' fi"

    # Match the target sample rate so every reconstruction object is compatible
    # and the output preserves the target's native sampling frequency.
    selectObject: grainStereo
    grainSR = Get sampling frequency
    if grainSR <> targetSR
        Resample: targetSR, 50
        grainResampled = selected("Sound")
        removeObject: grainStereo
        grainStereo = grainResampled
    endif

    vg_idx[voice] = vg_idx[voice] + 1
    idx = vg_idx[voice]

    # Quantize scheduling to the target sample grid. This prevents tiny
    # positive floating-point gaps from becoming zero-sample Sound requests.
    selectObject: grainStereo
    grainDurActual = Get total duration
    startSamples = round((t_start + delay / 1000) * targetSR)
    if startSamples < 0
        startSamples = 0
    endif

    vg_obj[voice, idx] = grainStereo
    vg_start[voice, idx] = startSamples / targetSR
    vg_dur[voice, idx] = grainDurActual
    vg_dist[voice, idx] = m_dist
    vg_mdist[voice, idx] = m_mdist
    vg_rank[voice, idx] = m_rank
    vg_file[voice, idx] = nUsedFiles
endfor

if corpusAudio <> 0
    removeObject: corpusAudio
endif

Create Sound from formula: "KDTC_mix", 2, 0, targetDur + 2.0, targetSR, "0"
kdtcMix = selected("Sound")

for v from 1 to number_of_voices
    nG = vg_idx[v]
    for i from 1 to nG - 1
        for j from i + 1 to nG
            if vg_start[v, j] < vg_start[v, i]
                tmpT = vg_start[v, i]
                vg_start[v, i] = vg_start[v, j]
                vg_start[v, j] = tmpT
                
                tmpD = vg_dur[v, i]
                vg_dur[v, i] = vg_dur[v, j]
                vg_dur[v, j] = tmpD
                
                tmpObj = vg_obj[v, i]
                vg_obj[v, i] = vg_obj[v, j]
                vg_obj[v, j] = tmpObj

                # The match metrics must travel with their grain, or the
                # figure would plot them against the wrong times.
                tmpX = vg_dist[v, i]
                vg_dist[v, i] = vg_dist[v, j]
                vg_dist[v, j] = tmpX

                tmpX = vg_mdist[v, i]
                vg_mdist[v, i] = vg_mdist[v, j]
                vg_mdist[v, j] = tmpX

                tmpX = vg_rank[v, i]
                vg_rank[v, i] = vg_rank[v, j]
                vg_rank[v, j] = tmpX

                tmpX = vg_file[v, i]
                vg_file[v, i] = vg_file[v, j]
                vg_file[v, j] = tmpX
            endif
        endfor
    endfor
    
    nTracks = 0
    sampleTol = 0.5 / targetSR
    for i from 1 to nG
        g_start = vg_start[v, i]
        g_dur = vg_dur[v, i]
        g_obj = vg_obj[v, i]
        
        assigned_t = 0
        for t from 1 to nTracks
            # Allow a half-sample numerical tolerance at touching boundaries.
            if track_end[t] <= g_start + sampleTol
                assigned_t = t
                t = nTracks + 1
            endif
        endfor
        if assigned_t = 0
            nTracks = nTracks + 1
            assigned_t = nTracks
            track_end[nTracks] = 0
            track_nParts[nTracks] = 0
        endif
        
        t = assigned_t

        # Convert the requested gap to an integer number of samples first.
        # Praat cannot create a Sound whose duration rounds to zero samples.
        gapSamples = round((g_start - track_end[t]) * targetSR)
        if gapSamples >= 1
            sil_dur = gapSamples / targetSR
            Create Sound from formula: "silence", 2, 0, sil_dur, targetSR, "0"
            silTemp = selected("Sound")
            track_nParts[t] = track_nParts[t] + 1
            track_part[t, track_nParts[t]] = silTemp
            track_end[t] = track_end[t] + sil_dur
        endif

        # Praat Concatenate follows Objects-list order, not selection order.
        # Create a fresh copy at scheduling time so each track's object IDs are
        # guaranteed to follow chronological order even though source grains
        # were originally created in corpus-file order for caching efficiency.
        selectObject: g_obj
        Copy: "kdtc_track_grain"
        gPart = selected("Sound")
        gPartDur = Get total duration
        removeObject: g_obj

        track_nParts[t] = track_nParts[t] + 1
        track_part[t, track_nParts[t]] = gPart
        track_end[t] = track_end[t] + gPartDur
    endfor
    
    vName$ = "KDTC_voice_" + string$(v)
    if v = 1
        vName$ = vName$ + "_close"
    elsif v = 2
        vName$ = vName$ + "_shadow"
    elsif v = 3
        vName$ = vName$ + "_cousin"
    elsif v = 4
        vName$ = vName$ + "_ghost"
    endif
    
    Create Sound from formula: vName$, 2, 0, targetDur + 2.0, targetSR, "0"
    vSound = selected("Sound")
    
    for t from 1 to nTracks
        if track_nParts[t] > 0
            selectObject: track_part[t, 1]
            if track_nParts[t] > 1
                for p from 2 to track_nParts[t]
                    plusObject: track_part[t, p]
                endfor
            endif
            Concatenate
            tSound = selected("Sound")
            
            # Pre-read sample count outside the formula (ncol() is not
            # supported as an inline formula function in all Praat versions)
            selectObject: tSound
            nColsT = Get number of samples
            selectObject: vSound
            Formula: "self + if col <= 'nColsT' then Object_'tSound'[row, col] else 0 fi"
            
            removeObject: tSound
        endif
        
        for p from 1 to track_nParts[t]
            removeObject: track_part[t, p]
        endfor
    endfor
    
    selectObject: kdtcMix
    Formula: "self + Object_'vSound'[row, col]"
    
    voiceSound[v] = vSound
    if output_mode = 1
        removeObject: vSound
    endif
endfor

# ===========================================================================
# Trim trailing silence + fast cosine fade-out
# ===========================================================================
appendInfoLine: "  Trimming silence and applying fade-out..."

fadeOutDur = 0.05

# Detect true content boundary directly from the waveform
# (same method as the Auto-Trim Silence tool — intensity-based TextGrid)
selectObject: kdtcMix
Convert to mono
kdtcMono = selected("Sound")
tgSil = To TextGrid (silences): 100, 0, -35, 0.1, 0.05, "silent", "sounding"
numSilIntervals = Get number of intervals: 1
actualEnd = targetDur
for iSil from 1 to numSilIntervals
    lbl$ = Get label of interval: 1, iSil
    if lbl$ = "sounding"
        actualEnd = Get end time of interval: 1, iSil
    endif
endfor
removeObject: tgSil, kdtcMono

trimEnd = min(actualEnd + fadeOutDur + 0.005, targetDur + 2.0)

# Trim and fade the mix
selectObject: kdtcMix
Extract part: 0, trimEnd, "rectangular", 1, "no"
kdtcMixTrimmed = selected("Sound")
Rename: "KDTC_mix"
selectObject: kdtcMixTrimmed
Formula: "if x > xmax - 'fadeOutDur' then self * (0.5 - 0.5 * cos(pi * (xmax - x) / 'fadeOutDur')) else self fi"
removeObject: kdtcMix
kdtcMix = kdtcMixTrimmed

# Trim and fade separate voice sounds if they were kept
if output_mode <> 1
    for v from 1 to number_of_voices
        vNameT$ = "KDTC_voice_" + string$(v)
        if v = 1
            vNameT$ = vNameT$ + "_close"
        elsif v = 2
            vNameT$ = vNameT$ + "_shadow"
        elsif v = 3
            vNameT$ = vNameT$ + "_cousin"
        elsif v = 4
            vNameT$ = vNameT$ + "_ghost"
        endif
        selectObject: voiceSound[v]
        Extract part: 0, trimEnd, "rectangular", 1, "no"
        vSoundTrimmed = selected("Sound")
        Rename: vNameT$
        selectObject: vSoundTrimmed
        Formula: "if x > xmax - 'fadeOutDur' then self * (0.5 - 0.5 * cos(pi * (xmax - x) / 'fadeOutDur')) else self fi"
        removeObject: voiceSound[v]
        voiceSound[v] = vSoundTrimmed
    endfor
endif

# ===========================================================================
# Envelope shaping: follow target pauses and/or amplitude envelope
# ===========================================================================

do_pauses   = (envelope_shaping = 2 or envelope_shaping = 4)
do_envelope = (envelope_shaping = 3 or envelope_shaping = 4)

if envelope_shaping > 1
    appendInfoLine: "  Applying envelope shaping (mode ", envelope_shaping, ")..."

    # Mono target for all analysis
    selectObject: targetObj
    nChTgt = Get number of channels
    if nChTgt > 1
        Convert to mono
        tgtMono2 = selected("Sound")
    else
        Copy: "env_tgt_mono"
        tgtMono2 = selected("Sound")
    endif

    selectObject: kdtcMix
    sr_mix = Get sampling frequency

    # ── Pause gate ────────────────────────────────────────────────────────
    if do_pauses
        selectObject: tgtMono2
        tgPause = To TextGrid (silences): 100, 0, -35, 0.1, 0.05, "silent", "sounding"
        nPInt = Get number of intervals: 1
        rampDur = 0.015   ; 15 ms cosine ramp at every silence edge

        Create Sound from formula: "pause_gate", 1, 0, trimEnd, sr_mix, "1"
        gateSound = selected("Sound")

        for iPause from 1 to nPInt
            selectObject: tgPause
            lbl$ = Get label of interval: 1, iPause
            if lbl$ = "silent"
                silS  = Get start time of interval: 1, iPause
                silE  = Get end time of interval:   1, iPause
                silDur = silE - silS
                actRamp = min(rampDur, silDur / 2)

                selectObject: gateSound
                # Cosine fade-out: 1 → 0 at silence start
                Formula (part): silS, silS + actRamp, 1, 1,
                    ..."0.5 + 0.5 * cos(pi * (x - 'silS') / 'actRamp')"
                # Flat zero in the body of the silence
                if silS + actRamp < silE - actRamp
                    Formula (part): silS + actRamp, silE - actRamp, 1, 1, "0"
                endif
                # Cosine fade-in: 0 → 1 at silence end
                Formula (part): silE - actRamp, silE, 1, 1,
                    ..."0.5 - 0.5 * cos(pi * (x - ('silE' - 'actRamp')) / 'actRamp')"
            endif
        endfor
        removeObject: tgPause
    endif

    # ── Amplitude envelope ────────────────────────────────────────────────
    if do_envelope
        selectObject: tgtMono2
        To Intensity: 100, 0, "yes"
        tgtIntEnv = selected("Intensity")
        maxIntDB = Get maximum: 0, 0, "Parabolic"
        minIntDB = maxIntDB - 60   ; 60 dB dynamic range floor

        # Build a gain sound: linear amplitude 0–1 matched to mix SR and duration
        Create Sound from formula: "amp_env", 1, 0, trimEnd, sr_mix,
            ..."if x > 'targetDur' then 0 else max(0, min(1, (Object_'tgtIntEnv'(x) - 'minIntDB') / ('maxIntDB' - 'minIntDB'))) fi"
        envSound = selected("Sound")
        removeObject: tgtIntEnv
    endif

    # ── Apply to mix ─────────────────────────────────────────────────────
    selectObject: kdtcMix
    if do_pauses and do_envelope
        Formula: "self * Object_'gateSound'(x) * Object_'envSound'(x)"
    elsif do_pauses
        Formula: "self * Object_'gateSound'(x)"
    else
        Formula: "self * Object_'envSound'(x)"
    endif

    # ── Apply to separate voices ─────────────────────────────────────────
    if output_mode <> 1
        for v from 1 to number_of_voices
            selectObject: voiceSound[v]
            if do_pauses and do_envelope
                Formula: "self * Object_'gateSound'(x) * Object_'envSound'(x)"
            elsif do_pauses
                Formula: "self * Object_'gateSound'(x)"
            else
                Formula: "self * Object_'envSound'(x)"
            endif
        endfor
    endif

    # ── Cleanup ───────────────────────────────────────────────────────────
    if do_pauses
        removeObject: gateSound
    endif
    if do_envelope
        removeObject: envSound
    endif
    removeObject: tgtMono2
endif

# ===========================================================================
# Output safety: preserve voice balance while preventing mix clipping
# ===========================================================================
selectObject: kdtcMix
mixPeak = Get absolute extremum: 0, 0, "Sinc70"
safetyScale = 1
if mixPeak > 0.99
    safetyScale = 0.99 / mixPeak
    selectObject: kdtcMix
    Formula: "self * 'safetyScale'"

    # Use the same factor on retained voices so their sum remains the mix.
    if output_mode <> 1
        for v from 1 to number_of_voices
            selectObject: voiceSound[v]
            Formula: "self * 'safetyScale'"
        endfor
    endif
    appendInfoLine: "  Output safety scale applied: ", fixed$(safetyScale, 4)
endif

# ===========================================================================
# Pre-compute envelope shaping label (used in viz and info output)
# ===========================================================================
envShapeLabel$ = ""
if envelope_shaping = 1
    envShapeLabel$ = "Off"
elsif envelope_shaping = 2
    envShapeLabel$ = "Pauses only"
elsif envelope_shaping = 3
    envShapeLabel$ = "Envelope only"
else
    envShapeLabel$ = "Pauses + Envelope"
endif

nTargetGrains = vg_idx[1]

# ============================================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
#
# Every panel below reports a RESULT of the match, not a form input. The
# parameters live in the subtitle, the summary bar and the Info window; there
# is no reason for a fourth copy of them on the canvas.
# ============================================================================
if draw_visualization

    # ------------------------------------------------------------
    # Per-voice match statistics
    # ------------------------------------------------------------
    gdMin = 1e30
    gdMax = -1e30
    mfccTotal = 0
    grainTotal = 0

    for v from 1 to number_of_voices
        nG = vg_idx[v]
        dLoV[v] = 0
        dHiV[v] = 0
        dMeanV[v] = 0
        rMeanV[v] = 0
        mMeanV[v] = 0
        if nG > 0
            dLo = 1e30
            dHi = -1e30
            dSum = 0
            rSum = 0
            mSum = 0
            for i from 1 to nG
                dv = vg_dist[v, i]
                if dv < dLo
                    dLo = dv
                endif
                if dv > dHi
                    dHi = dv
                endif
                dSum = dSum + dv
                rSum = rSum + vg_rank[v, i]
                mSum = mSum + vg_mdist[v, i]
            endfor
            dLoV[v] = dLo
            dHiV[v] = dHi
            dMeanV[v] = dSum / nG
            rMeanV[v] = rSum / nG
            mMeanV[v] = mSum / nG
            if dLo < gdMin
                gdMin = dLo
            endif
            if dHi > gdMax
                gdMax = dHi
            endif
            mfccTotal = mfccTotal + mSum
            grainTotal = grainTotal + nG
        endif
    endfor

    if gdMin > gdMax
        gdMin = 0
        gdMax = 1
    endif
    if gdMax - gdMin < 1e-6
        gdMax = gdMin + 1
    endif
    dPad = (gdMax - gdMin) * 0.08
    dAxLo = gdMin - dPad
    dAxHi = gdMax + dPad
    @niceStep: dAxHi - dAxLo, 5
    dMarkStep = niceStep

    # Requested rank per voice, parsed from the form string. The Python
    # helper pads a short list by repeating its last value; mirror that here
    # so the figure reports what the matcher actually used.
    rkScan$ = eff_ranks$ + ","
    nRk = 0
    rkBuf$ = ""
    for ci from 1 to length(rkScan$)
        rkCh$ = mid$(rkScan$, ci, 1)
        if rkCh$ = "," or rkCh$ = " " or rkCh$ = ";"
            if length(rkBuf$) > 0
                nRk = nRk + 1
                rkVal = number(rkBuf$)
                if rkVal = undefined
                    rkVal = 1
                endif
                reqRank[nRk] = rkVal
                rkBuf$ = ""
            endif
        else
            rkBuf$ = rkBuf$ + rkCh$
        endif
    endfor
    if nRk < 1
        nRk = 1
        reqRank[1] = 1
    endif
    for v from nRk + 1 to number_of_voices
        reqRank[v] = reqRank[nRk]
    endfor

    mfccMeanAll = 0
    if grainTotal > 0
        mfccMeanAll = mfccTotal / grainTotal
    endif

    # Diagnostic: an MFCC weight that contributes nothing means the feature
    # columns are flat, and the "timbral" match is running on the remaining
    # scalar features alone. Worth saying out loud rather than hiding.
    mfccDead = 0
    if eff_mfcc_w > 0 and mfccMeanAll < 1e-6
        mfccDead = 1
    endif

    # ------------------------------------------------------------
    # Palette and layout
    # ------------------------------------------------------------
    bgCol$    = "{0.97, 0.97, 0.99}"
    gridCol$  = "{0.74, 0.74, 0.80}"
    axisCol$  = "{0.20, 0.20, 0.28}"
    dimCol$   = "{0.45, 0.45, 0.55}"
    panelBg$  = "{0.94, 0.94, 0.94}"
    warnCol$  = "{0.75, 0.20, 0.15}"

    vCol_1$ = "{0.20, 0.50, 0.80}"
    vCol_2$ = "{0.70, 0.30, 0.20}"
    vCol_3$ = "{0.25, 0.62, 0.35}"
    vCol_4$ = "{0.60, 0.30, 0.70}"
    vCol_5$ = "{0.75, 0.60, 0.15}"
    vCol_6$ = "{0.25, 0.62, 0.75}"

    vL = 0.60
    vR = 7.70
    hL1 = 0.60
    hR1 = 3.85
    hL2 = 4.45
    hR2 = 7.70
    railX = -0.035
    pageHeight = 8

    voiceWord$ = " voices"
    if number_of_voices = 1
        voiceWord$ = " voice"
    endif

    tlDur = trimEnd
    if tlDur <= 0
        tlDur = targetDur
    endif

    @niceStep: tlDur, 8
    tickStep = niceStep

    Erase all
    Black
    Solid line
    Line width: 1

    # ============================================================
    # TITLE
    # ============================================================
    Font size: 12
    Select inner viewport: vL, vR, 0.12, 0.32
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##KD-TREE TIMBRAL COUNTERPOINT##"

    @vizSafe: soundName$
    srcLabel$ = vizSafe$

    Font size: 7
    Select inner viewport: vL, vR, 0.34, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.5, "half",
        ... srcLabel$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(number_of_voices) + voiceWord$
        ... + "  |  Ranks: " + eff_ranks$
        ... + "  |  Grain " + fixed$(grain_size_ms, 0) + " ms / "
        ... + fixed$(grain_overlap_percent, 0) + "\%  overlap"
        ... + "  |  " + envShapeLabel$

    # ============================================================
    # PANEL A — TIMBRAL DISTANCE OVER TIME
    # The script's premise, plotted: do the ranks actually separate
    # the voices, and do they stay separated locally?
    # ============================================================
    pAT = 0.85
    pAB = 2.80

    Font size: 6
    Select inner viewport: vL, vR, pAT, pAB
    Axes: 0, tlDur, dAxLo, dAxHi
    Paint rectangle: bgCol$, 0, tlDur, dAxLo, dAxHi

    Select inner viewport: vL, vR, pAT, pAB
    Axes: 0, tlDur, dAxLo, dAxHi
    Colour: gridCol$
    for v from 1 to number_of_voices
        if vg_idx[v] > 0
            Draw line: 0, dMeanV[v], tlDur, dMeanV[v]
        endif
    endfor

    Select inner viewport: vL, vR, pAT, pAB
    Axes: 0, tlDur, dAxLo, dAxHi
    Line width: 1
    for v from 1 to number_of_voices
        vIdx = min(v, 6)
        Colour: vCol_'vIdx'$
        nG = vg_idx[v]
        for i from 2 to nG
            xa = vg_start[v, i - 1] + vg_dur[v, i - 1] / 2
            xb = vg_start[v, i] + vg_dur[v, i] / 2
            ya = vg_dist[v, i - 1]
            yb = vg_dist[v, i]
            if xa > tlDur
                xa = tlDur
            endif
            if xb > tlDur
                xb = tlDur
            endif
            Draw line: xa, ya, xb, yb
        endfor
    endfor

    Select inner viewport: vL, vR, pAT, pAB
    Axes: 0, tlDur, dAxLo, dAxHi
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tickStep, "yes", "yes", "no"
    Marks left every: 1, dMarkStep, "yes", "yes", "no"

    Select inner viewport: vL, vR, pAT, pAB
    Axes: 0, 1, 0, 1
    Colour: dimCol$
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 6, "90", "Distance"

    # Legend
    for v from 1 to number_of_voices
        Select inner viewport: vL, vR, pAT, pAB
        Axes: 0, 1, 0, 1
        vIdx = min(v, 6)
        Colour: vCol_'vIdx'$
        Text: 0.975 - (number_of_voices - v) * 0.042, "left", 0.955, "half", "V" + string$(v)
    endfor

    Select inner viewport: vL, vR, pAT, pAB
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no",
        ... "##Timbral distance per grain## — weighted feature-space distance"
        ... + " to the target, time in seconds (grey lines = per-voice means)"

    # ============================================================
    # PANEL B — GRAIN PROVENANCE
    # One block per grain, coloured by which corpus file it came
    # from. Consecutive grains alternate between the upper and lower
    # half of each lane, so overlap and grain count stay visible
    # instead of merging into one solid bar.
    # ============================================================
    pBT = 3.30
    pBB = 5.20

    Font size: 6
    Select inner viewport: vL, vR, pBT, pBB
    Axes: 0, tlDur, -0.5, number_of_voices - 0.5
    Paint rectangle: bgCol$, 0, tlDur, -0.5, number_of_voices - 0.5

    Select inner viewport: vL, vR, pBT, pBB
    Axes: 0, tlDur, -0.5, number_of_voices - 0.5
    for v from 1 to number_of_voices
        laneY = number_of_voices - v
        nG = vg_idx[v]
        for i from 1 to nG
            blS = vg_start[v, i]
            blE = blS + vg_dur[v, i]
            if blE > tlDur
                blE = tlDur
            endif
            if blS < tlDur
                @fileCol: vg_file[v, i]
                if i mod 2 = 1
                    Paint rectangle: fileCol$, blS, blE, laneY - 0.34, laneY - 0.01
                else
                    Paint rectangle: fileCol$, blS, blE, laneY + 0.01, laneY + 0.34
                endif
            endif
        endfor
    endfor

    Select inner viewport: vL, vR, pBT, pBB
    Axes: 0, tlDur, -0.5, number_of_voices - 0.5
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tickStep, "yes", "yes", "no"

    for v from 1 to number_of_voices
        Select inner viewport: vL, vR, pBT, pBB
        Axes: 0, tlDur, -0.5, number_of_voices - 0.5
        vIdx = min(v, 6)
        Colour: vCol_'vIdx'$
        Text: -tlDur * 0.008, "right", number_of_voices - v, "half", "V" + string$(v)
    endfor

    Select inner viewport: vL, vR, pBT, pBB
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no",
        ... "##Grain provenance## — one block per grain, colour = corpus file;"
        ... + " consecutive grains alternate half-lanes to show overlap,"
        ... + " time in seconds"

    # ============================================================
    # PANEL C — VOICE SEPARATION SUMMARY
    # ============================================================
    pCT = 5.72
    pCB = 7.02

    Font size: 6
    Select inner viewport: hL1, hR1, pCT, pCB
    Axes: dAxLo, dAxHi, number_of_voices + 0.62, 0.38
    Paint rectangle: bgCol$, dAxLo, dAxHi, number_of_voices + 0.62, 0.38

    Select inner viewport: hL1, hR1, pCT, pCB
    Axes: dAxLo, dAxHi, number_of_voices + 0.62, 0.38
    for v from 1 to number_of_voices
        if vg_idx[v] > 0
            vIdx = min(v, 6)
            Paint rectangle: vCol_'vIdx'$, dLoV[v], dHiV[v], v + 0.02, v + 0.34
        endif
    endfor

    Select inner viewport: hL1, hR1, pCT, pCB
    Axes: dAxLo, dAxHi, number_of_voices + 0.62, 0.38
    Colour: "{0.12, 0.12, 0.16}"
    Line width: 1.5
    for v from 1 to number_of_voices
        if vg_idx[v] > 0
            Draw line: dMeanV[v], v - 0.02, dMeanV[v], v + 0.38
        endif
    endfor
    Line width: 1

    Select inner viewport: hL1, hR1, pCT, pCB
    Axes: dAxLo, dAxHi, number_of_voices + 0.62, 0.38
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, dMarkStep, "yes", "yes", "no"

    for v from 1 to number_of_voices
        Select inner viewport: hL1, hR1, pCT, pCB
        Axes: dAxLo, dAxHi, number_of_voices + 0.62, 0.38
        Colour: axisCol$
        Text: dAxLo + (dAxHi - dAxLo) * 0.02, "left", v - 0.26, "half",
            ... "V" + string$(v)
            ... + "   rank " + string$(reqRank[v]) + " -> " + fixed$(rMeanV[v], 1)
            ... + "   mean " + fixed$(dMeanV[v], 3)
    endfor

    Select inner viewport: hL1, hR1, pCT, pCB
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", "##Voice separation## — distance min-max, tick = mean"

    # ============================================================
    # PANEL D — CORPUS USAGE
    # ============================================================
    nShow = nUsedFiles
    if nShow > 12
        nShow = 12
    endif

    # Rank files by grain count (selection sort on an index array)
    for f from 1 to nUsedFiles
        fOrder[f] = f
    endfor
    for f from 1 to nUsedFiles - 1
        for g from f + 1 to nUsedFiles
            fa = fOrder[f]
            fb = fOrder[g]
            if usedFileCount[fb] > usedFileCount[fa]
                fOrder[f] = fb
                fOrder[g] = fa
            endif
        endfor
    endfor

    maxCount = 1
    for f from 1 to nUsedFiles
        if usedFileCount[f] > maxCount
            maxCount = usedFileCount[f]
        endif
    endfor
    @niceStep: maxCount, 4
    dCountStep = niceStep
    if dCountStep < 1
        dCountStep = 1
    endif

    Font size: 6
    Select inner viewport: hL2, hR2, pCT, pCB
    Axes: 0, maxCount * 1.18, nShow + 0.62, 0.38
    Paint rectangle: bgCol$, 0, maxCount * 1.18, nShow + 0.62, 0.38

    Select inner viewport: hL2, hR2, pCT, pCB
    Axes: 0, maxCount * 1.18, nShow + 0.62, 0.38
    for f from 1 to nShow
        fSrc = fOrder[f]
        @fileCol: fSrc
        Paint rectangle: fileCol$, 0, usedFileCount[fSrc], f - 0.42, f + 0.42
    endfor

    Select inner viewport: hL2, hR2, pCT, pCB
    Axes: 0, maxCount * 1.18, nShow + 0.62, 0.38
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, dCountStep, "yes", "yes", "no"

    dFont = 6
    if nShow > 8
        dFont = 5
    endif

    for f from 1 to nShow
        fSrc = fOrder[f]
        @vizSafe: usedFileName$[fSrc]
        fLabel$ = vizSafe$
        Font size: dFont
        Select inner viewport: hL2, hR2, pCT, pCB
        Axes: 0, maxCount * 1.18, nShow + 0.62, 0.38
        # A short bar cannot hold white text; put the name beside it instead.
        if usedFileCount[fSrc] > maxCount * 0.24
            Colour: "{1.0, 1.0, 1.0}"
            Text: maxCount * 0.02, "left", f, "half", fLabel$
        else
            Colour: dimCol$
            Text: usedFileCount[fSrc] + maxCount * 0.09, "left", f, "half", fLabel$
        endif
        Font size: dFont
        Select inner viewport: hL2, hR2, pCT, pCB
        Axes: 0, maxCount * 1.18, nShow + 0.62, 0.38
        Colour: axisCol$
        Text: usedFileCount[fSrc] + maxCount * 0.02, "left", f, "half",
            ... string$(usedFileCount[fSrc])
    endfor

    usageCap$ = "##Corpus usage## — grains drawn per file"
    if nUsedFiles > nShow
        usageCap$ = usageCap$ + "  (top " + string$(nShow)
            ... + " of " + string$(nUsedFiles) + ")"
    endif

    Select inner viewport: hL2, hR2, pCT, pCB
    Axes: 0, 1, 0, 1
    Colour: axisCol$
    Text top: "no", usageCap$

    # ============================================================
    # SUMMARY BAR
    # ============================================================
    sT = 7.38
    sB = 7.92

    Font size: 7
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Paint rectangle: panelBg$, 0, 1, 0, 1

    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.84, "half",
        ... "##" + presetName$ + "##   " + srcLabel$
        ... + "   |   " + string$(number_of_voices) + voiceWord$ + " x "
        ... + string$(nTargetGrains) + " grains"
        ... + "   |   corpus " + string$(nUsedFiles) + " of "
        ... + string$(nFiles) + " files used"
        ... + "   |   target " + fixed$(targetDur, 2) + " s -> output "
        ... + fixed$(trimEnd, 2) + " s"

    Font size: 6
    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.012, "left", 0.56, "half",
        ... "Weights — MFCC " + fixed$(eff_mfcc_w, 2)
        ... + "  Pitch " + fixed$(eff_pitch_w, 2)
        ... + "  Cent " + fixed$(eff_cent_w, 2)
        ... + "  Int " + fixed$(eff_int_w, 2)
        ... + "  HNR " + fixed$(eff_hnr_w, 2)
        ... + "   |   randomness " + fixed$(eff_randomness, 2)
        ... + "   |   rep penalty " + string$(repetition_penalty)
        ... + "   |   crossfade " + fixed$(crossfade_duration * 1000, 0) + " ms"

    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    if mfccDead = 1
        Colour: warnCol$
        Text: 0.012, "left", 0.26, "half",
            ... "WARNING: mean MFCC contribution is 0.000 — the MFCC columns are"
            ... + " flat, so matching is running on the scalar features only."
    else
        Colour: "{0.28, 0.28, 0.28}"
        Text: 0.012, "left", 0.26, "half",
            ... "Mean MFCC contribution to distance: " + fixed$(mfccMeanAll, 3)
            ... + "   |   distance range across all voices "
            ... + fixed$(gdMin, 3) + " to " + fixed$(gdMax, 3)
            ... + "   |   " + envShapeLabel$
    endif

    Select inner viewport: vL, vR, sT, sB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ------------------------------------------------------------
    # Restore the full canvas so Save / Copy from the Picture window
    # (and any scripted PNG export) captures the whole figure.
    # ------------------------------------------------------------
    Font size: 10
    Select outer viewport: 0, 8, 0, pageHeight
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ===========================================================================
# Cleanup temps and utilities
# ===========================================================================
@cleanUpTempFiles
removeObject: mapTable

if output_mode = 2
    removeObject: kdtcMix
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, " (", number_of_voices, " voices)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Grain size:   ", fixed$(grain_size_ms, 0), " ms | Overlap: ", fixed$(grain_overlap_percent, 0), "%"
appendInfoLine: "Grains/voice: ", vg_idx[1]
appendInfoLine: "Corpus files: ", nFiles
appendInfoLine: ""
appendInfoLine: "Target dur:   ", fixed$(targetDur, 2), " s"
appendInfoLine: "Output dur:   ", fixed$(trimEnd, 2), " s  (trimmed + ", fixed$(fadeOutDur * 1000, 0), " ms fade-out)"
appendInfoLine: "Env shaping:  ", envShapeLabel$
appendInfoLine: ""
appendInfoLine: "Ranks:        ", eff_ranks$
appendInfoLine: "Randomness:   ", fixed$(eff_randomness, 2)
appendInfoLine: "Rep penalty:  ", repetition_penalty
appendInfoLine: ""
appendInfoLine: "Weights — MFCC: ", fixed$(eff_mfcc_w, 2), "  Pitch: ", fixed$(eff_pitch_w, 2), "  Centroid: ", fixed$(eff_cent_w, 2), "  Intensity: ", fixed$(eff_int_w, 2), "  HNR: ", fixed$(eff_hnr_w, 2)

if output_mode <> 2
    selectObject: kdtcMix
    if play_result
        Play
    endif
endif


# ============================================================================
# HELPERS
# ============================================================================

# Snap an axis step to 1 / 2 / 5 x 10^k so tick labels read in round numbers.
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .pw = 10 ^ floor(log10(.raw))
    .nm = .raw / .pw
    if .nm < 1.5
        niceStep = 1 * .pw
    elsif .nm < 3.5
        niceStep = 2 * .pw
    elsif .nm < 7.5
        niceStep = 5 * .pw
    else
        niceStep = 10 * .pw
    endif
endproc

# Categorical colour for a corpus file index: six hues, darkened one step
# every six files, so up to 18 files stay distinguishable.
procedure fileCol: .f
    .tier = floor((.f - 1) / 6)
    .hue = .f - .tier * 6
    .shade = 1 - .tier * 0.26
    if .shade < 0.40
        .shade = 0.40
    endif
    if .hue = 1
        .r = 0.20
        .g = 0.50
        .b = 0.80
    elsif .hue = 2
        .r = 0.80
        .g = 0.45
        .b = 0.15
    elsif .hue = 3
        .r = 0.25
        .g = 0.62
        .b = 0.35
    elsif .hue = 4
        .r = 0.60
        .g = 0.30
        .b = 0.70
    elsif .hue = 5
        .r = 0.85
        .g = 0.30
        .b = 0.25
    else
        .r = 0.25
        .g = 0.55
        .b = 0.62
    endif
    fileCol$ = "{" + fixed$(.r * .shade, 3) + ", " + fixed$(.g * .shade, 3)
        ... + ", " + fixed$(.b * .shade, 3) + "}"
endproc

# Strip a path and extension down to a bare file name.
procedure baseName: .p$
    .cut = 0
    for .i from 1 to length(.p$)
        .ch$ = mid$(.p$, .i, 1)
        if .ch$ = "/" or .ch$ = "\"
            .cut = .i
        endif
    endfor
    .b$ = mid$(.p$, .cut + 1, length(.p$) - .cut)
    .dot = 0
    for .i from 1 to length(.b$)
        if mid$(.b$, .i, 1) = "."
            .dot = .i
        endif
    endfor
    if .dot > 1
        .b$ = mid$(.b$, 1, .dot - 1)
    endif
    baseName$ = .b$
endproc

# Escape Picture-window markup in machine-generated names. Order matters:
# the replacements for #, % and ^ contain no underscore, so the underscore
# pass must run last.
procedure vizSafe: .s$
    vizSafe$ = replace$(.s$, "#", "\# ", 0)
    vizSafe$ = replace$(vizSafe$, "%", "\% ", 0)
    vizSafe$ = replace$(vizSafe$, "^", "\^ ", 0)
    vizSafe$ = replace$(vizSafe$, "_", "\_ ", 0)
endproc
