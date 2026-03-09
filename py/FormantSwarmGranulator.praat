# ============================================================
# Praat AudioTools - FormantSwarmGranulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026)
# License: MIT License
#
# Description:
#   Formant Swarm Granulator
#
#   Segments the selected Sound into short grains, extracts a compact
#   resonance profile for each grain via Praat formant analysis, and
#   delegates swarm planning to a Python engine. The Python layer treats
#   grains as particles in a perceptual field where attraction is weighted
#   by formant similarity while repulsion is shaped by temporal adjacency
#   and local density. The result is a granular cloud organized by hidden
#   vowel anatomy rather than raw randomness.
#
# Python engine: formant_swarm_granulator.py
#
# Dependencies (Python):
#   pip install numpy soundfile
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/formant_swarm_granulator.py"
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "formant_swarm_granulator.py"
endif
if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/formant_swarm_granulator.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: formant_swarm_granulator.py" + newline$
        ... + "Expected at: " + pythonScript$ + newline$
        ... + "Please place formant_swarm_granulator.py next to this script" + newline$
        ... + "or inside the plugin_AudioTools/py/ folder."
endif

tempInput$ = pluginDir$ + "temp_fsg_input.wav"
tempCSV$ = pluginDir$ + "temp_fsg_grains.csv"
tempOutput$ = pluginDir$ + "temp_fsg_output.wav"
tempStats$ = pluginDir$ + "temp_fsg_stats.txt"
probeMarker$ = pluginDir$ + "temp_fsg_pyprobe.ok"

form Formant Swarm Granulator
    optionmenu Swarm_mode: 1
        option vowel_cloud
        option resonance_turbulence
        option migration
        option counterpoint
    positive Grain_length_ms 55
    real Grain_jitter_ms 15
    real Grain_overlap_percent 0
    real Density_grains_per_sec 18
    real Attraction 1.0
    real Temporal_repulsion 0.9
    real Density_repulsion 0.7
    real Pan_spread 1.0
    real Pitch_drift_semitones 0.5
    positive Max_formant_hz 5500
    positive Number_of_formants 5
    positive Random_seed 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

swarmMode$ = "vowel_cloud"
if swarm_mode = 2
    swarmMode$ = "resonance_turbulence"
elsif swarm_mode = 3
    swarmMode$ = "migration"
elsif swarm_mode = 4
    swarmMode$ = "counterpoint"
endif

grainLengthSec = grain_length_ms / 1000
grainJitterSec = grain_jitter_ms / 1000
if grainLengthSec < 0.025
    grainLengthSec = 0.025
endif
overlapFrac = grain_overlap_percent / 100
if overlapFrac < 0
    overlapFrac = 0
endif
if overlapFrac > 0.9
    overlapFrac = 0.9
endif
hopSec = grainLengthSec * (1 - overlapFrac)
if hopSec < 0.010
    hopSec = 0.010
endif
if density_grains_per_sec < 1
    density_grains_per_sec = 1
endif
if pan_spread < 0
    pan_spread = 0
endif
if pan_spread > 1
    pan_spread = 1
endif
if pitch_drift_semitones < 0
    pitch_drift_semitones = 0
endif

clearinfo
writeInfoLine: "=== Formant Swarm Granulator ==="
appendInfoLine: "Input:      ", soundName$
appendInfoLine: "Mode:       ", swarmMode$
appendInfoLine: "Grain ms:   ", grain_length_ms
appendInfoLine: "Hop ms:     ", fixed$(hopSec * 1000, 1), " (overlap ", fixed$(grain_overlap_percent, 0), "%)"
appendInfoLine: "Density:    ", fixed$(density_grains_per_sec, 2)
appendInfoLine: "Seed:       ", random_seed
appendInfoLine: ""

# ============================================================
# Stage 1 — Export source audio
# ============================================================
appendInfoLine: "[1/4] Exporting source audio..."
selectObject: sound
Save as WAV file: tempInput$

# ============================================================
# Stage 2 — Extract grain table in Praat
# ============================================================
appendInfoLine: "[2/4] Extracting grain formants..."
if fileReadable(tempCSV$)
    deleteFile: tempCSV$
endif
csvHeader$ = "grain_id,start_time_s,duration_s,pitch_hz,intensity_db,centroid_hz,f1_hz,f2_hz,f3_hz,bw1_hz,bw2_hz,bw3_hz,voiced,confidence"
fileappend 'tempCSV$' 'csvHeader$''newline$'

selectObject: sound
totalDur = Get total duration
grainId = 0
startTime = 0
while startTime < totalDur - 0.01
    localDur = grainLengthSec
    if abs(grainJitterSec) > 0
        localDur = grainLengthSec + randomUniform(-grainJitterSec, grainJitterSec)
    endif
    if localDur < 0.025
        localDur = 0.025
    endif
    if startTime + localDur > totalDur
        localDur = totalDur - startTime
    endif
    if localDur <= 0.015
        break
    endif

    selectObject: sound
    Extract part: startTime, startTime + localDur, "rectangular", 1, "no"
    grain = selected("Sound")

    selectObject: grain
    actualDur = Get total duration
    pitchObj = 0
    pitchHz = 0
    ; Praat pitch floor rule: floor must be < 0.8/duration.
    ; Use ceiling with a generous +20 buffer to clear floating-point edge cases.
    ; Also require actualDur > 0.040 s (below that pitch is unreliable anyway).
    if actualDur > 0.040
        safePitchFloor = ceiling(0.8 / actualDur) + 20
        if safePitchFloor < 75
            safePitchFloor = 75
        endif
        if safePitchFloor < 550
            pitchObj = To Pitch: 0.0, safePitchFloor, 600
            pitchHz = Get mean: 0, 0, "Hertz"
            if pitchHz = undefined
                pitchHz = 0
            endif
        endif
    endif

    intensityDb = 0
    minIntensityDur = 6.4 / 75
    if actualDur >= minIntensityDur
        selectObject: grain
        To Intensity: 75, 0, "yes"
        intensityObj = selected("Intensity")
        intensityDb = Get mean: 0, 0, "energy"
        if intensityDb = undefined
            intensityDb = 0
        endif
    endif

    selectObject: grain
    To Spectrum: "yes"
    spectrumObj = selected("Spectrum")
    centroidHz = Get centre of gravity: 2
    if centroidHz = undefined
        centroidHz = 0
    endif

    f1 = 0
    f2 = 0
    f3 = 0
    bw1 = 0
    bw2 = 0
    bw3 = 0
    if actualDur >= 0.03
        selectObject: grain
        To Formant (burg): 0, number_of_formants, max_formant_hz, 0.025, 50
        formantObj = selected("Formant")
        midTime = actualDur / 2
        f1 = Get value at time: 1, midTime, "Hertz", "Linear"
        f2 = Get value at time: 2, midTime, "Hertz", "Linear"
        f3 = Get value at time: 3, midTime, "Hertz", "Linear"
        bw1 = Get bandwidth at time: 1, midTime, "Hertz", "Linear"
        bw2 = Get bandwidth at time: 2, midTime, "Hertz", "Linear"
        bw3 = Get bandwidth at time: 3, midTime, "Hertz", "Linear"
    endif
    if f1 = undefined
        f1 = 0
    endif
    if f2 = undefined
        f2 = 0
    endif
    if f3 = undefined
        f3 = 0
    endif
    if bw1 = undefined
        bw1 = 0
    endif
    if bw2 = undefined
        bw2 = 0
    endif
    if bw3 = undefined
        bw3 = 0
    endif

    voiced = 0
    if pitchHz > 0
        voiced = 1
    endif
    confidence = 0.25
    if f1 > 0
        confidence = confidence + 0.25
    endif
    if f2 > 0
        confidence = confidence + 0.25
    endif
    if f3 > 0
        confidence = confidence + 0.15
    endif
    if voiced = 1
        confidence = confidence + 0.10
    endif
    if confidence > 1
        confidence = 1
    endif

    csvRow$ = string$(grainId) + ","
        ... + fixed$(startTime, 6) + ","
        ... + fixed$(localDur, 6) + ","
        ... + fixed$(pitchHz, 3) + ","
        ... + fixed$(intensityDb, 3) + ","
        ... + fixed$(centroidHz, 3) + ","
        ... + fixed$(f1, 3) + ","
        ... + fixed$(f2, 3) + ","
        ... + fixed$(f3, 3) + ","
        ... + fixed$(bw1, 3) + ","
        ... + fixed$(bw2, 3) + ","
        ... + fixed$(bw3, 3) + ","
        ... + string$(voiced) + ","
        ... + fixed$(confidence, 3)
    fileappend 'tempCSV$' 'csvRow$''newline$'

    if pitchObj <> 0
        selectObject: pitchObj
        if actualDur >= minIntensityDur
            plusObject: intensityObj
        endif
        plusObject: spectrumObj
        if actualDur >= 0.03
            plusObject: formantObj
        endif
        plusObject: grain
    else
        selectObject: spectrumObj
        if actualDur >= minIntensityDur
            plusObject: intensityObj
        endif
        if actualDur >= 0.03
            plusObject: formantObj
        endif
        plusObject: grain
    endif
    Remove

    grainId = grainId + 1
    startTime = startTime + hopSec
endwhile
appendInfoLine: "  Grains analysed: ", grainId

# ============================================================
# Stage 3 — Detect Python and call engine
# ============================================================
appendInfoLine: "[3/4] Detecting Python..."
if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

if windows
    nCandidates = 4
    candidate1$ = "python"
    candidate2$ = "py"
    candidate3$ = "py -3"
    candidate4$ = "python3"
else
    nCandidates = 3
    candidate1$ = "python3"
    candidate2$ = "python"
    candidate3$ = "py"
    candidate4$ = ""
endif

pythonCmd$ = ""
for iCand from 1 to nCandidates
    if iCand = 1
        tryCmd$ = candidate1$
    elsif iCand = 2
        tryCmd$ = candidate2$
    elsif iCand = 3
        tryCmd$ = candidate3$
    else
        tryCmd$ = candidate4$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    probeCode$ = "import numpy,soundfile; open(r'" + probeMarker$ + "','w').write('ok')"
    nocheck runSystem: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = nCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    exitScript: "Cannot find Python with required packages." + newline$
        ... + "  pip install numpy soundfile"
endif

appendInfoLine: "[4/4] Running Python engine..."
pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " --grains """ + tempCSV$ + """"
    ... + " --input """ + tempInput$ + """"
    ... + " --output """ + tempOutput$ + """"
    ... + " --stats """ + tempStats$ + """"
    ... + " --mode " + swarmMode$
    ... + " --density " + fixed$(density_grains_per_sec, 4)
    ... + " --attraction " + fixed$(attraction, 4)
    ... + " --temporal_repulsion " + fixed$(temporal_repulsion, 4)
    ... + " --density_repulsion " + fixed$(density_repulsion, 4)
    ... + " --pan_spread " + fixed$(pan_spread, 4)
    ... + " --pitch_drift " + fixed$(pitch_drift_semitones, 4)
    ... + " --seed " + string$(random_seed)
appendInfoLine: "  CMD: " + pythonCall$
runSystem: pythonCall$

if not fileReadable(tempOutput$)
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    exitScript: "Python engine failed to create output WAV." + newline$
        ... + "Check the Info window for the executed command."
endif

Read from file: tempOutput$
result = selected("Sound")
Rename: soundName$ + "_formantSwarm"

appendInfoLine: "Done. Output created as: ", soundName$, "_formantSwarm"

# ============================================================
# Read stats
# ============================================================

statMode$       = "?"
statGrains$     = "?"
statScheduled$  = "?"
statClusters$   = "?"
statVoicedRatio$ = "?"
statMeanF1$     = "?"
statMeanF2$     = "?"
statMeanF3$     = "?"
statRmsIn$      = "?"
statRmsOut$     = "?"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "mode="
    statMode$ = parseStatLine.result$
    @parseStatLine: statsText$, "grains="
    statGrains$ = parseStatLine.result$
    @parseStatLine: statsText$, "scheduled_events="
    statScheduled$ = parseStatLine.result$
    @parseStatLine: statsText$, "clusters="
    statClusters$ = parseStatLine.result$
    @parseStatLine: statsText$, "voiced_ratio="
    statVoicedRatio$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_f1_hz="
    statMeanF1$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_f2_hz="
    statMeanF2$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_f3_hz="
    statMeanF3$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_in="
    statRmsIn$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_out="
    statRmsOut$ = parseStatLine.result$
    appendInfoLine: ""
    appendInfoLine: "--- Stats ---"
    appendInfoLine: statsText$
endif

# ============================================================
# Visualization
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ---------------------------------------------------------
    # Title panel
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Formant Swarm Granulator##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", -1.0, "half",
        ... soundName$ + "  |  Mode: " + swarmMode$
        ... + "  |  Grain=" + fixed$(grain_length_ms, 0) + "ms"
        ... + "  |  Density=" + fixed$(density_grains_per_sec, 1)
        ... + "  |  Seed=" + string$(random_seed)

    # ---------------------------------------------------------
    # Original waveform
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 0.55, 1.45
    Select inner viewport: 0.6, 7.7, 0.60, 1.40
    selectObject: sound
    Colour: "{0.50, 0.50, 0.50}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", "Duration: " + fixed$(totalDur, 3) + " s"

    # ---------------------------------------------------------
    # Output waveform
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 1.45, 2.35
    Select inner viewport: 0.6, 7.7, 1.50, 2.30
    selectObject: result
    Colour: "{0.15, 0.55, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Swarm"
    Text bottom: "yes", "Time (s)"

    # ---------------------------------------------------------
    # Original spectrogram
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 2.45, 3.55
    Select inner viewport: 0.6, 7.7, 2.50, 3.50
    selectObject: sound
    nChannels = Get number of channels
    if nChannels > 1
        Extract one channel: 1
        tmpOrig = selected("Sound")
    else
        Copy: "tmpOrig"
        tmpOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text top: "no", "Original spectrogram"
    removeObject: specOrig, tmpOrig

    # ---------------------------------------------------------
    # Output spectrogram
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 3.55, 4.65
    Select inner viewport: 0.6, 7.7, 3.60, 4.60
    selectObject: result
    Extract one channel: 1
    tmpOut = selected("Sound")
    To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
    specOut = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Swarm spectrogram"
    removeObject: specOut, tmpOut

    # ---------------------------------------------------------
    # Formant bar panel  (F1 / F2 / F3 mean Hz as horizontal bars)
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 4.75, 5.60
    Select inner viewport: 0.6, 7.7, 4.80, 5.55

    f1Mean = 0
    f2Mean = 0
    f3Mean = 0
    if statMeanF1$ <> "?"
        f1Mean = number(statMeanF1$)
    endif
    if statMeanF2$ <> "?"
        f2Mean = number(statMeanF2$)
    endif
    if statMeanF3$ <> "?"
        f3Mean = number(statMeanF3$)
    endif

    fMax = 5000
    Axes: 0, fMax, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, fMax, 0, 1

    # F1 bar  (warm red)
    if f1Mean > 0
        Paint rectangle: "{0.82, 0.25, 0.18}", 0, f1Mean, 0.62, 0.92
        Colour: "Black"
        Font size: 6
        Text: f1Mean + 60, "left", 0.77, "half", "F1 " + fixed$(f1Mean, 0) + " Hz"
    endif
    # F2 bar  (steel blue)
    if f2Mean > 0
        Paint rectangle: "{0.22, 0.48, 0.80}", 0, f2Mean, 0.35, 0.60
        Colour: "Black"
        Font size: 6
        Text: f2Mean + 60, "left", 0.475, "half", "F2 " + fixed$(f2Mean, 0) + " Hz"
    endif
    # F3 bar  (teal)
    if f3Mean > 0
        Paint rectangle: "{0.15, 0.62, 0.55}", 0, f3Mean, 0.08, 0.33
        Colour: "Black"
        Font size: 6
        Text: f3Mean + 60, "left", 0.205, "half", "F3 " + fixed$(f3Mean, 0) + " Hz"
    endif

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Mean formant profile across grains"

    # ---------------------------------------------------------
    # Mode colour strip
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 5.70, 6.00
    Select inner viewport: 0.6, 7.7, 5.73, 5.97

    Axes: 0, 1, 0, 1
    if swarm_mode = 1
        Paint rectangle: "{0.22, 0.48, 0.80}", 0, 1, 0, 1
    elsif swarm_mode = 2
        Paint rectangle: "{0.78, 0.28, 0.22}", 0, 1, 0, 1
    elsif swarm_mode = 3
        Paint rectangle: "{0.25, 0.65, 0.45}", 0, 1, 0, 1
    else
        Paint rectangle: "{0.65, 0.35, 0.70}", 0, 1, 0, 1
    endif
    Font size: 9
    Colour: "White"
    Text: 0.5, "centre", 0.5, "half", "##" + swarmMode$ + "##"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # ---------------------------------------------------------
    # Summary panel
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 6.10, 7.10
    Select inner viewport: 0.6, 7.7, 6.15, 7.05

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.68, "half",
        ... "Grains analysed: " + statGrains$
        ... + "  |  Scheduled events: " + statScheduled$
        ... + "  |  Clusters: " + statClusters$
    Text: 0.02, "left", 0.48, "half",
        ... "Voiced ratio: " + statVoicedRatio$
        ... + "  |  Mean F1: " + statMeanF1$ + " Hz"
        ... + "  |  Mean F2: " + statMeanF2$ + " Hz"
        ... + "  |  Mean F3: " + statMeanF3$ + " Hz"
    Text: 0.02, "left", 0.28, "half",
        ... "Grain length: " + fixed$(grain_length_ms, 0) + " ms"
        ... + "  |  Overlap: " + fixed$(grain_overlap_percent, 0) + "%"
        ... + "  |  Attraction: " + fixed$(attraction, 2)
        ... + "  |  Temporal rep: " + fixed$(temporal_repulsion, 2)
        ... + "  |  Density rep: " + fixed$(density_repulsion, 2)
    Text: 0.02, "left", 0.18, "half",
        ... "Pan spread: " + fixed$(pan_spread, 2)
        ... + "  |  Pitch drift: " + fixed$(pitch_drift_semitones, 2) + " st"
        ... + "  |  Seed: " + string$(random_seed)
    Text: 0.02, "left", 0.05, "half",
        ... "RMS in: " + statRmsIn$
        ... + "  →  RMS out: " + statRmsOut$
        ... + "  (channel-balanced + source-matched)"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"

endif

# ============================================================
# Cleanup temp files
# ============================================================

if fileReadable(tempInput$)
    deleteFile: tempInput$
endif
if fileReadable(tempCSV$)
    deleteFile: tempCSV$
endif
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif
if fileReadable(probeMarker$)
    deleteFile: probeMarker$
endif

# ============================================================
# Final info + play
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:    ", soundName$, "_formantSwarm"
appendInfoLine: "Mode:      ", swarmMode$
appendInfoLine: "Grains:    ", statGrains$
appendInfoLine: "Scheduled: ", statScheduled$
appendInfoLine: "Clusters:  ", statClusters$
appendInfoLine: "Voiced:    ", statVoicedRatio$
appendInfoLine: "Mean F1:   ", statMeanF1$, " Hz"
appendInfoLine: "Mean F2:   ", statMeanF2$, " Hz"
appendInfoLine: "Mean F3:   ", statMeanF3$, " Hz"
appendInfoLine: "RMS in:    ", statRmsIn$
appendInfoLine: "RMS out:   ", statRmsOut$

selectObject: result
if play_result
    Play
endif

# ============================================================
# Procedures
# ============================================================

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
