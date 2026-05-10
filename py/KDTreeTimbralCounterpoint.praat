# ============================================================
# Praat AudioTools - KDTreeTimbralCounterpoint.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026) - Unified Cross-Platform Version
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
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

form KD-Tree Timbral Counterpoint
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
    exitScript: "Cannot find Python script. Expected at: " + pythonScript$
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

# Temp Paths
tempTargCSV$  = temporaryDirectory$ + "/temp_kdtc_target.csv"
tempCorpCSV$  = temporaryDirectory$ + "/temp_kdtc_corpus.csv"
tempMatchCSV$ = temporaryDirectory$ + "/temp_kdtc_match.csv"
tempStderr$   = temporaryDirectory$ + "/temp_kdtc_stderr.log"

deleteFile: tempMatchCSV$
deleteFile: tempStderr$

grain_sec = grain_size_ms / 1000
hop = grain_sec * (1 - grain_overlap_percent / 100)

procedure extractFeatures: .sndObj, .fPath$, .csvTable, .isCorpus
    selectObject: .sndObj
    .dur = Get total duration
    
    # Guard against sounds shorter than the analysis window minimum.
    # To Intensity (pitchFloor=100) needs ≥ 6.4/100 = 0.064 s.
    # To Pitch      (pitchFloor=75)  needs ≥ 3/75   ≈ 0.040 s.
    # Use 0.1 s as a safe floor: pad with silence at the end if needed.
    .minAnalysisDur = 0.1
    if .dur < .minAnalysisDur
        .padDur = .minAnalysisDur - .dur
        selectObject: .sndObj
        .nCh_pad = Get number of channels
        .sr_pad  = Get sampling frequency
        Create Sound from formula: "pad_sil", .nCh_pad, 0, .padDur, .sr_pad, "0"
        .padSil = selected("Sound")
        selectObject: .sndObj
        plusObject: .padSil
        Concatenate
        .analysisObj = selected("Sound")
        removeObject: .padSil
        .createdAnalysisObj = 1
    else
        .analysisObj = .sndObj
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
        
        .m1 = Get value in frame: 1, .frame
        if .m1 = undefined
            .m1 = 0
        endif
        .m2 = Get value in frame: 2, .frame
        if .m2 = undefined
            .m2 = 0
        endif
        .m3 = Get value in frame: 3, .frame
        if .m3 = undefined
            .m3 = 0
        endif
        .m4 = Get value in frame: 4, .frame
        if .m4 = undefined
            .m4 = 0
        endif
        .m5 = Get value in frame: 5, .frame
        if .m5 = undefined
            .m5 = 0
        endif
        .m6 = Get value in frame: 6, .frame
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
        
        selectObject: .sndObj
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
endproc

clearinfo
writeInfoLine: "KD-Tree Timbral Counterpoint running..."

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

if nFiles == 0
    removeObject: fileList
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

if fileReadable(tempStderr$)
    err_txt$ = readFile$(tempStderr$)
    if length(err_txt$) > 10
        exitScript: "PYTHON FATAL ERROR:" + newline$ + err_txt$
    endif
endif

if not fileReadable(tempMatchCSV$)
    exitScript: "CRITICAL: Python failed to generate the output CSV, and no logs were found."
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
    
    if c_file$ <> prev_file$
        if corpusAudio <> 0
            removeObject: corpusAudio
        endif
        Read from file: c_file$
        corpusAudio = selected("Sound")
        prev_file$ = c_file$
    endif
    
    selectObject: corpusAudio
    Extract part: c_start, c_end, "rectangular", 1, "no"
    grainTemp = selected("Sound")
    
    selectObject: grainTemp
    fade = crossfade_duration
    
    # ── THE FIX: Two separate, simple formulas to avoid 'elsif' completely ──
    Formula: "if x < xmin + 'fade' then self * (0.5 - 0.5*cos(pi*(x-xmin)/'fade')) else self fi"
    Formula: "if x > xmax - 'fade' then self * (0.5 - 0.5*cos(pi*(xmax-x)/'fade')) else self fi"
    Formula: "self * 'gain'"
    
    angle = (pan + 1) * pi / 4
    lg = cos(angle)
    rg = sin(angle)
    
    selectObject: grainTemp
    nChan = Get number of channels
    if nChan = 1
        Copy: "grain_temp_dup"
        grainTempDup = selected("Sound")
        selectObject: grainTemp
        plusObject: grainTempDup
        Combine to stereo
        grainStereo = selected("Sound")
        removeObject: grainTemp, grainTempDup
    else
        grainStereo = grainTemp
    endif
    
    selectObject: grainStereo
    Formula: "if row = 1 then self * 'lg' else self * 'rg' fi"

    # Normalise sample rate so Concatenate never sees mismatched rates
    selectObject: grainStereo
    grainSR = Get sampling frequency
    if grainSR <> 44100
        Resample: 44100, 50
        grainResampled = selected("Sound")
        removeObject: grainStereo
        grainStereo = grainResampled
    endif

    vg_idx[voice] = vg_idx[voice] + 1
    idx = vg_idx[voice]

    vg_obj[voice, idx] = grainStereo
    vg_start[voice, idx] = t_start + delay / 1000
    vg_dur[voice, idx] = c_end - c_start
endfor

if corpusAudio <> 0
    removeObject: corpusAudio
endif

Create Sound from formula: "KDTC_mix", 2, 0, targetDur + 2.0, 44100, "0"
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
            endif
        endfor
    endfor
    
    nTracks = 0
    for i from 1 to nG
        g_start = vg_start[v, i]
        g_dur = vg_dur[v, i]
        g_obj = vg_obj[v, i]
        
        assigned_t = 0
        for t from 1 to nTracks
            if track_end[t] <= g_start
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
        sil_dur = g_start - track_end[t]
        if sil_dur > 0.001
            Create Sound from formula: "silence", 2, 0, sil_dur, 44100, "0"
            silTemp = selected("Sound")
            track_nParts[t] = track_nParts[t] + 1
            track_part[t, track_nParts[t]] = silTemp
        endif
        
        track_nParts[t] = track_nParts[t] + 1
        track_part[t, track_nParts[t]] = g_obj
        track_end[t] = g_start + g_dur
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
    
    Create Sound from formula: vName$, 2, 0, targetDur + 2.0, 44100, "0"
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
Extract one channel: 1
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
        Extract one channel: 1
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
            ..."max(0, min(1, (Object_'tgtIntEnv'(x) - 'minIntDB') / ('maxIntDB' - 'minIntDB')))"
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
# Visualization
# ===========================================================================
if draw_visualization
    Erase all
    Black
    Plain line

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##KD-Tree Timbral Counterpoint##"
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.2, "half", soundName$ + " | " + string$(number_of_voices) + " voices | Ranks: " + eff_ranks$ + " | " + presetName$

    # === Target Waveform (with grain boundaries) ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: targetObj
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Target"
    Colour: "{0.75, 0.45, 0.15}"
    Line width: 1
    Axes: 0, targetDur, -1, 1
    grainT = hop
    while grainT < targetDur
        Draw line: grainT, -0.9, grainT, 0.9
        grainT = grainT + hop
    endwhile
    Line width: 1
    nTargetGrains = vg_idx[1]
    Text top: "no", "Grain: " + fixed$(grain_size_ms, 0) + " ms | Overlap: " + fixed$(grain_overlap_percent, 0) + "% | " + string$(nTargetGrains) + " grains/voice"

    # === Output Mix Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: kdtcMix
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Mix"
    Text bottom: "yes", "Time (s)"

    # === Target Spectrogram ===
    Select outer viewport: 0, 8, 2.5, 3.7
    Select inner viewport: 0.6, 7.7, 2.6, 3.6
    selectObject: targetObj
    tgtChans = Get number of channels
    if tgtChans > 1
        Extract one channel: 1
        tmpTgt = selected("Sound")
    else
        Copy: "tmpTgt"
        tmpTgt = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specTgt = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Target spectrogram"
    removeObject: specTgt, tmpTgt

    # === Output Spectrogram ===
    Select outer viewport: 0, 8, 3.7, 4.9
    Select inner viewport: 0.6, 7.7, 3.8, 4.8
    selectObject: kdtcMix
    Extract one channel: 1
    tmpMix = selected("Sound")
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specMix = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Mix spectrogram (L channel)"
    removeObject: specMix, tmpMix

    # === Contrapuntal Voice Timeline ===
    Select outer viewport: 0, 8, 5.0, 6.5
    Select inner viewport: 0.6, 7.7, 5.1, 6.4

    tlDur = trimEnd
    Axes: 0, tlDur, -0.5, number_of_voices - 0.5
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, tlDur, -0.5, number_of_voices - 0.5

    vCol_1$ = "{0.20, 0.50, 0.80}"
    vCol_2$ = "{0.70, 0.30, 0.20}"
    vCol_3$ = "{0.25, 0.62, 0.35}"
    vCol_4$ = "{0.60, 0.30, 0.70}"
    vCol_5$ = "{0.75, 0.60, 0.15}"
    vCol_6$ = "{0.25, 0.62, 0.75}"

    laneH = 0.33
    for v from 1 to number_of_voices
        laneY = number_of_voices - v
        vIdx = min(v, 6)
        thisCol$ = vCol_'vIdx'$
        nG = vg_idx[v]
        for i from 1 to nG
            blS = vg_start[v, i]
            blE = blS + vg_dur[v, i]
            Paint rectangle: thisCol$, blS, blE, laneY - laneH, laneY + laneH
        endfor
        Font size: 5
        Colour: "Black"
        Text: -tlDur * 0.005, "right", laneY, "half", "V" + string$(v)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Voice"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Contrapuntal Voice Timeline — " + string$(number_of_voices) + " voices | each colour = one corpus-grain block"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.6, 8.0
    Select inner viewport: 0.6, 7.7, 6.65, 7.90

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

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

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.74, "half", "Voices: " + string$(number_of_voices) + " | Ranks: " + eff_ranks$ + " | Randomness: " + fixed$(eff_randomness, 2) + " | Rep penalty: " + string$(repetition_penalty)
    Text: 0.02, "left", 0.54, "half", "Grain: " + fixed$(grain_size_ms, 0) + " ms | Overlap: " + fixed$(grain_overlap_percent, 0) + "% | " + string$(nTargetGrains) + " grains/voice | Corpus files: " + string$(nFiles)
    Text: 0.02, "left", 0.34, "half", "Target: " + fixed$(targetDur, 2) + " s | Output: " + fixed$(trimEnd, 2) + " s | Preset: " + presetName$ + " | Shaping: " + envShapeLabel$
    Text: 0.02, "left", 0.14, "half", "Weights — MFCC: " + fixed$(eff_mfcc_w, 2) + "  Pitch: " + fixed$(eff_pitch_w, 2) + "  Centroid: " + fixed$(eff_cent_w, 2) + "  Intensity: " + fixed$(eff_int_w, 2) + "  HNR: " + fixed$(eff_hnr_w, 2)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ===========================================================================
# Cleanup temps and utilities
# ===========================================================================
deleteFile: tempTargCSV$
deleteFile: tempCorpCSV$
deleteFile: tempMatchCSV$
deleteFile: tempStderr$
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