# ============================================================
# Praat AudioTools - FormantSwarmGranulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.4 (2026) - Validity-aware formant descriptors, process-narrative figure
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Formants are analysis descriptors only. They organize grains when the
# local spectrum supports a plausible broad resonance structure. They are
# never synthesized and are never replaced by a canonical/median vowel.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Formant Swarm Granulator v1.4
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
    natural Number_of_formants 5
    real Min_reliable_formant_ratio 0.15
    real Min_resonance_contrast_dB 0.8
    integer Random_seed 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# -----------------------------------------------------------------------------
# Paths / Python
# -----------------------------------------------------------------------------
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
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
pythonScript$ = pluginDir$ + "py/formant_swarm_granulator.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/formant_swarm_granulator.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python engine: formant_swarm_granulator.py" + newline$
        ... + "Expected at: " + pluginDir$ + "py/" + newline$
        ... + "or next to this script."
endif

tempInput$ = temporaryDirectory$ + "/temp_fsg_input.wav"
tempCSV$ = temporaryDirectory$ + "/temp_fsg_grains.csv"
tempOutput$ = temporaryDirectory$ + "/temp_fsg_output.wav"
tempStats$ = temporaryDirectory$ + "/temp_fsg_stats.txt"
tempMap$ = temporaryDirectory$ + "/temp_fsg_map.csv"
tempSched$ = temporaryDirectory$ + "/temp_fsg_sched.csv"
probeMarker$ = temporaryDirectory$ + "/temp_fsg_pyprobe.ok"
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

procedure cleanUpTempFiles
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
    if fileReadable(tempMap$)
        deleteFile: tempMap$
    endif
    if fileReadable(tempSched$)
        deleteFile: tempSched$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# -----------------------------------------------------------------------------
# Parameter guards
# -----------------------------------------------------------------------------
swarmMode$ = "vowel_cloud"
if swarm_mode = 2
    swarmMode$ = "resonance_turbulence"
elsif swarm_mode = 3
    swarmMode$ = "migration"
elsif swarm_mode = 4
    swarmMode$ = "counterpoint"
endif

grainLengthSec = max(0.025, grain_length_ms / 1000)
grainJitterSec = grain_jitter_ms / 1000
overlapFrac = max(0, min(0.9, grain_overlap_percent / 100))
hopSec = max(0.010, grainLengthSec * (1 - overlapFrac))
density_grains_per_sec = max(1, density_grains_per_sec)
pan_spread = max(0, min(1, pan_spread))
pitch_drift_semitones = max(0, pitch_drift_semitones)
min_reliable_formant_ratio = max(0, min(1, min_reliable_formant_ratio))
min_resonance_contrast_dB = max(-20, min(20, min_resonance_contrast_dB))
if number_of_formants < 3
    number_of_formants = 3
endif
if number_of_formants > 7
    number_of_formants = 7
endif

selectObject: sound
totalDur = Get total duration
sampleRate = Get sampling frequency
nChannels = Get number of channels
nyquist = sampleRate / 2
safeMaxFormant = min(max_formant_hz, nyquist - 100)
if safeMaxFormant < 1200
    exitScript: "Sample rate is too low for a three-landmark resonance analysis."
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably(random_seed)
    pythonSeed = random_seed
else
    random_initializeSafelyAndUnpredictably()
    pythonSeed = randomInteger(1, 2000000000)
endif

clearinfo
writeInfoLine: "=== Formant Swarm Granulator v1.4 ==="
appendInfoLine: "Input:      ", soundName$
appendInfoLine: "Mode:       ", swarmMode$
appendInfoLine: "Grain:      ", fixed$(grainLengthSec * 1000, 1), " ms"
appendInfoLine: "Hop:        ", fixed$(hopSec * 1000, 1), " ms"
appendInfoLine: "Formants:   analysis descriptors only"
appendInfoLine: "Min reliable ratio: ", fixed$(100 * min_reliable_formant_ratio, 1), "%"
appendInfoLine: "Min resonance contrast: ", fixed$(min_resonance_contrast_dB, 2), " dB"
appendInfoLine: ""

# -----------------------------------------------------------------------------
# Build an analysis channel. Do not fold stereo to mono: anti-phase material
# would cancel. Use the globally strongest input channel for descriptors.
# -----------------------------------------------------------------------------
analysisSound = sound
analysisIsTemp = 0
if nChannels > 1
    bestChannel = 1
    bestRms = -1
    for ch from 1 to nChannels
        selectObject: sound
        Extract one channel: ch
        tmpCh = selected("Sound")
        rmsCh = Get root-mean-square: 0, 0
        if rmsCh > bestRms
            bestRms = rmsCh
            bestChannel = ch
        endif
        removeObject: tmpCh
    endfor
    selectObject: sound
    Extract one channel: bestChannel
    analysisSound = selected("Sound")
    Rename: "FSG_analysis_channel"
    analysisIsTemp = 1
    appendInfoLine: "Analysis channel: ", bestChannel, " (anti-phase safe)"
else
    appendInfoLine: "Analysis channel: mono input"
endif

# -----------------------------------------------------------------------------
# Dependency probe + source export
# -----------------------------------------------------------------------------
probeCmd$ = pythonCmd$ + " -c ""import numpy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$
if not fileReadable(probeMarker$)
    if analysisIsTemp
        removeObject: analysisSound
    endif
    @cleanUpTempFiles
    exitScript: "Cannot find Python with numpy and soundfile."
endif
deleteFile: probeMarker$

selectObject: sound
Save as WAV file: tempInput$

# -----------------------------------------------------------------------------
# Grain descriptor extraction
# -----------------------------------------------------------------------------
appendInfoLine: "[1/2] Extracting validity-aware grain descriptors..."
csvHeader$ = "grain_id,start_time_s,duration_s,pitch_hz,intensity_db,centroid_hz,f1_hz,f2_hz,f3_hz,bw1_hz,bw2_hz,bw3_hz,voiced,formant_valid,formant_span_hz,resonance_contrast_db,confidence"
fileappend 'tempCSV$' 'csvHeader$''newline$'

# Analyse Pitch and FormantPath ONCE for the full analysis channel. The older
# script repeated both analyses for every grain, which was expensive and made
# adjacent grains disagree simply because each tiny window fitted its own model.
selectObject: analysisSound
analysisXmin = Get start time
analysisXmax = Get end time
pitchCeiling = min(800, nyquist - 50)
globalPitch = To Pitch (cc): 0.005, 50, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14, pitchCeiling

pathMaxFormant = min(max_formant_hz, (nyquist - 50) / 1.22)
if pathMaxFormant < 1000
    removeObject: globalPitch
    if analysisIsTemp
        removeObject: analysisSound
    endif
    @cleanUpTempFiles
    exitScript: "Sample rate is too low for FormantPath analysis."
endif
selectObject: analysisSound
globalFormantPath = To FormantPath (burg): 0.005, number_of_formants, pathMaxFormant, 0.030, 35, 0.05, 4
globalFormant = Extract Formant

appendInfoLine: "  Global Pitch + FormantPath analysis complete."

grainId = 0
reliableCount = 0
sumConfidence = 0
startTime = 0

while startTime < totalDur - 0.015
    localDur = grainLengthSec
    if abs(grainJitterSec) > 0
        localDur = grainLengthSec + randomUniform(-abs(grainJitterSec), abs(grainJitterSec))
    endif
    localDur = max(0.025, localDur)
    if startTime + localDur > totalDur
        localDur = totalDur - startTime
    endif
    # startTime is RELATIVE to the exported WAV, while analysis queries must
    # respect the Praat Sound's original xmin.
    absStart = analysisXmin + startTime
    absEnd = absStart + localDur
    absMid = absStart + 0.5 * localDur

    # Relative intensity feature, valid even for grains shorter than the
    # standard Intensity analysis window.
    selectObject: analysisSound
    rms = Get root-mean-square: absStart, absEnd
    intensityDb = 20 * log10(rms + 1e-12)

    # Local spectral centroid. This is also a narrow-band sanity check.
    selectObject: analysisSound
    Extract part: absStart, absEnd, "rectangular", 1, "no"
    grain = selected("Sound")
    To Spectrum: "yes"
    spectrumObj = selected("Spectrum")
    centroidHz = Get centre of gravity: 2
    if centroidHz = undefined
        centroidHz = 0
    endif

    # Pitch at the grain centre.
    selectObject: globalPitch
    pitchHz = Get value at time: absMid, "Hertz", "Linear"
    if pitchHz = undefined or pitchHz < 0
        pitchHz = 0
    endif
    voiced = 0
    if pitchHz > 0
        voiced = 1
    endif

    # Three-point FormantPath sample inside the grain. A stable local resonance
    # should persist across the grain; random Burg poles on broadband noise do
    # not get a free pass just because one midpoint returned numbers.
    tA = absStart + 0.30 * localDur
    tB = absMid
    tC = absStart + 0.70 * localDur

    selectObject: globalFormant
    f1a = Get value at time: 1, tA, "Hertz", "Linear"
    f1b = Get value at time: 1, tB, "Hertz", "Linear"
    f1c = Get value at time: 1, tC, "Hertz", "Linear"
    f2a = Get value at time: 2, tA, "Hertz", "Linear"
    f2b = Get value at time: 2, tB, "Hertz", "Linear"
    f2c = Get value at time: 2, tC, "Hertz", "Linear"
    f3a = Get value at time: 3, tA, "Hertz", "Linear"
    f3b = Get value at time: 3, tB, "Hertz", "Linear"
    f3c = Get value at time: 3, tC, "Hertz", "Linear"
    bw1 = Get bandwidth at time: 1, tB, "Hertz", "Linear"
    bw2 = Get bandwidth at time: 2, tB, "Hertz", "Linear"
    bw3 = Get bandwidth at time: 3, tB, "Hertz", "Linear"

    haveTriplet = 1
    if f1a = undefined or f1b = undefined or f1c = undefined or f2a = undefined or f2b = undefined or f2c = undefined or f3a = undefined or f3b = undefined or f3c = undefined
        haveTriplet = 0
    endif

    if haveTriplet
        # Median of three without sorting.
        f1 = f1a + f1b + f1c - min(f1a, min(f1b, f1c)) - max(f1a, max(f1b, f1c))
        f2 = f2a + f2b + f2c - min(f2a, min(f2b, f2c)) - max(f2a, max(f2b, f2c))
        f3 = f3a + f3b + f3c - min(f3a, min(f3b, f3c)) - max(f3a, max(f3b, f3c))
        f1Spread = max(f1a, max(f1b, f1c)) - min(f1a, min(f1b, f1c))
        f2Spread = max(f2a, max(f2b, f2c)) - min(f2a, min(f2b, f2c))
        f3Spread = max(f3a, max(f3b, f3c)) - min(f3a, min(f3b, f3c))
    else
        f1 = 0
        f2 = 0
        f3 = 0
        f1Spread = 1e30
        f2Spread = 1e30
        f3Spread = 1e30
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

    formantSpan = 0
    if f1 > 0 and f3 > 0
        formantSpan = f3 - f1
    endif

    ordered = 0
    if f1 >= 80 and f2 > f1 + 100 and f3 > f2 + 120 and f3 < nyquist - 80
        ordered = 1
    endif

    spanThreshold = 350
    if voiced and pitchHz > 0
        spanThreshold = max(spanThreshold, 1.25 * pitchHz)
    endif
    spanGood = 0
    if formantSpan >= spanThreshold
        spanGood = 1
    endif

    spacingGood = 0
    if ordered
        r21 = f2 / f1
        r32 = f3 / f2
        if r21 >= 1.15 and r21 <= 8 and r32 >= 1.05 and r32 <= 4.5
            spacingGood = 1
        endif
    endif

    bandwidthGood = 0
    if bw1 >= 10 and bw2 >= 10 and bw3 >= 10
        if bw1 <= max(800, 0.9 * f1) and bw2 <= max(1000, 0.8 * f2) and bw3 <= max(1200, 0.7 * f3)
            bandwidthGood = 1
        endif
    endif

    stabilityGood = 0
    if haveTriplet and ordered
        if f1Spread <= max(140, 0.30 * f1) and f2Spread <= max(190, 0.22 * f2) and f3Spread <= max(240, 0.18 * f3)
            stabilityGood = 1
        endif
    endif

    broadSpectrumGood = 1
    if voiced and pitchHz > 0
        if centroidHz < 1.8 * pitchHz
            broadSpectrumGood = 0
        endif
    endif

    # Evidence in the ACTUAL local spectrum. FormantPath can produce smooth,
    # evenly spaced poles on white noise; that is model structure, not a real
    # resonance envelope. Compare local power density around F2/F3 with their
    # neighbouring bands. A positive contrast means the measured landmark is
    # supported by the spectrum itself.
    resonanceContrast = 0
    contrastCount = 0
    if ordered
        selectObject: spectrumObj

        w2 = max(80, min(250, 0.5 * max(40, bw2)))
        c2lo = max(0, f2 - 0.5 * w2)
        c2hi = min(nyquist, f2 + 0.5 * w2)
        l2lo = max(0, f2 - 2 * w2)
        l2hi = max(0, f2 - w2)
        r2lo = min(nyquist, f2 + w2)
        r2hi = min(nyquist, f2 + 2 * w2)
        d2c = Get band density: c2lo, c2hi
        d2flank = 0
        d2n = 0
        if l2hi > l2lo + 10
            d2l = Get band density: l2lo, l2hi
            d2flank = d2flank + d2l
            d2n = d2n + 1
        endif
        if r2hi > r2lo + 10
            d2r = Get band density: r2lo, r2hi
            d2flank = d2flank + d2r
            d2n = d2n + 1
        endif
        if d2n > 0
            d2flank = d2flank / d2n
            c2dB = 10 * log10((d2c + 1e-30) / (d2flank + 1e-30))
            resonanceContrast = resonanceContrast + c2dB
            contrastCount = contrastCount + 1
        endif

        w3 = max(80, min(250, 0.5 * max(40, bw3)))
        c3lo = max(0, f3 - 0.5 * w3)
        c3hi = min(nyquist, f3 + 0.5 * w3)
        l3lo = max(0, f3 - 2 * w3)
        l3hi = max(0, f3 - w3)
        r3lo = min(nyquist, f3 + w3)
        r3hi = min(nyquist, f3 + 2 * w3)
        d3c = Get band density: c3lo, c3hi
        d3flank = 0
        d3n = 0
        if l3hi > l3lo + 10
            d3l = Get band density: l3lo, l3hi
            d3flank = d3flank + d3l
            d3n = d3n + 1
        endif
        if r3hi > r3lo + 10
            d3r = Get band density: r3lo, r3hi
            d3flank = d3flank + d3r
            d3n = d3n + 1
        endif
        if d3n > 0
            d3flank = d3flank / d3n
            c3dB = 10 * log10((d3c + 1e-30) / (d3flank + 1e-30))
            resonanceContrast = resonanceContrast + c3dB
            contrastCount = contrastCount + 1
        endif
    endif
    if contrastCount > 0
        resonanceContrast = resonanceContrast / contrastCount
    endif

    formantValid = 0
    if ordered and spanGood and spacingGood and stabilityGood and broadSpectrumGood
        formantValid = 1
    endif

    confidence = 0.05
    if ordered
        confidence = confidence + 0.20
    endif
    if spanGood
        confidence = confidence + 0.20
    endif
    if spacingGood
        confidence = confidence + 0.15
    endif
    if bandwidthGood
        confidence = confidence + 0.15
    endif
    if stabilityGood
        confidence = confidence + 0.15
    endif
    if broadSpectrumGood
        confidence = confidence + 0.05
    endif
    if voiced
        confidence = confidence + 0.05
    endif
    confidence = min(1, confidence)
    if not formantValid
        confidence = min(0.20, confidence)
    else
        reliableCount = reliableCount + 1
        sumConfidence = sumConfidence + confidence
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
        ... + string$(formantValid) + ","
        ... + fixed$(formantSpan, 3) + ","
        ... + fixed$(resonanceContrast, 4) + ","
        ... + fixed$(confidence, 4)
    fileappend 'tempCSV$' 'csvRow$''newline$'

    removeObject: spectrumObj, grain
    grainId = grainId + 1
    startTime = startTime + hopSec
endwhile

removeObject: globalPitch, globalFormant, globalFormantPath

if grainId < 2
    if analysisIsTemp
        removeObject: analysisSound
    endif
    @cleanUpTempFiles
    exitScript: "Not enough grains were extracted."
endif

reliableRatio = reliableCount / grainId
meanReliableConfidence = 0
if reliableCount > 0
    meanReliableConfidence = sumConfidence / reliableCount
endif
appendInfoLine: "  Grains: ", grainId
appendInfoLine: "  Structurally plausible formant grains: ", reliableCount, "/", grainId,
    ... " (", fixed$(100 * reliableRatio, 1), "%)"
appendInfoLine: "  Mean structural confidence: ", fixed$(meanReliableConfidence, 3)
appendInfoLine: "  Final formant-space activation also requires median spectral resonance contrast in Python."

if analysisIsTemp
    removeObject: analysisSound
endif

# -----------------------------------------------------------------------------
# Python swarm engine
# -----------------------------------------------------------------------------
appendInfoLine: "[2/2] Running validity-aware swarm engine..."

# argparse aborts on an unrecognised option, so an engine older than v1.3 would
# fail the whole run if the figure-table flags were sent blind. Read the engine
# source and ask it what it supports before asking for anything.
engineText$ = readFile$(pythonScript$)
engineHasTables = 0
if index(engineText$, "--map") > 0
    if index(engineText$, "--sched") > 0
        engineHasTables = 1
    endif
endif
if engineHasTables = 0
    appendInfoLine: "  Engine predates v1.3: process tables unavailable, drawing the compact figure."
endif

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
    ... + " --min_formant_ratio " + fixed$(min_reliable_formant_ratio, 4)
    ... + " --min_resonance_contrast " + fixed$(min_resonance_contrast_dB, 4)
    ... + " --seed " + string$(pythonSeed)
if engineHasTables
    pythonCall$ = pythonCall$ + " --map """ + tempMap$ + """" + " --sched """ + tempSched$ + """"
endif
runSystem: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python engine failed to create output WAV."
endif

Read from file: tempOutput$
result = selected("Sound")
Rename: soundName$ + "_formantSwarm"

# -----------------------------------------------------------------------------
# Stats
# -----------------------------------------------------------------------------
statGrains$ = "?"
statScheduled$ = "?"
statClusters$ = "?"
statVoicedRatio$ = "?"
statFormantActive$ = "?"
statValidGrains$ = "?"
statValidRatio$ = "?"
statMeanConfidence$ = "?"
statMedianContrast$ = "?"
statFeatures$ = "?"
statMeanF1$ = "?"
statMeanF2$ = "?"
statMeanF3$ = "?"
statRmsIn$ = "?"
statRmsOut$ = "?"
statPeakOut$ = "?"
statOutDur$ = "?"
statUnused$ = "?"
statMaxReuse$ = "?"
statMedReuse$ = "?"
statStride$ = "1"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "grains="
    statGrains$ = parseStatLine.result$
    @parseStatLine: statsText$, "scheduled_events="
    statScheduled$ = parseStatLine.result$
    @parseStatLine: statsText$, "clusters="
    statClusters$ = parseStatLine.result$
    @parseStatLine: statsText$, "voiced_ratio="
    statVoicedRatio$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_features_active="
    statFormantActive$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_valid_grains="
    statValidGrains$ = parseStatLine.result$
    @parseStatLine: statsText$, "formant_valid_ratio="
    statValidRatio$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_formant_confidence="
    statMeanConfidence$ = parseStatLine.result$
    @parseStatLine: statsText$, "median_resonance_contrast_db="
    statMedianContrast$ = parseStatLine.result$
    @parseStatLine: statsText$, "feature_dimensions="
    statFeatures$ = parseStatLine.result$
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
    @parseStatLine: statsText$, "peak_out="
    statPeakOut$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration_s="
    statOutDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "unused_grains="
    statUnused$ = parseStatLine.result$
    @parseStatLine: statsText$, "max_grain_reuse="
    statMaxReuse$ = parseStatLine.result$
    @parseStatLine: statsText$, "median_grain_reuse="
    statMedReuse$ = parseStatLine.result$
    @parseStatLine: statsText$, "schedule_stride="
    statStride$ = parseStatLine.result$
    appendInfoLine: ""
    appendInfoLine: "--- Engine stats ---"
    appendInfoLine: statsText$
endif

# -----------------------------------------------------------------------------
# Visualization
#
# The figure is a narrative, read top to bottom:
#   1. what the source is, and which of its grains earned trustworthy formant
#      landmarks (the gate);
#   2. what those landmarks actually were;
#   3. the feature space the swarm inhabits, and the walk it took through it;
#   4. how that walk maps back onto source time and onto the stereo field;
#   5. what came out.
# Panels 1-4 are driven by two small tables the Python engine writes next to the
# audio. If an older engine is installed those tables are absent, and the script
# falls back to the compact original figure rather than drawing empty panels.
# -----------------------------------------------------------------------------
if draw_visualization
    vizL = 0.65
    vizR = 7.70
    railX = -0.043

    selectObject: sound
    srcXmin = Get start time
    srcXmax = Get end time
    srcHiAmp = Get maximum: 0, 0, "None"
    srcLoAmp = Get minimum: 0, 0, "None"
    srcAmp = max(1e-6, max(abs(srcHiAmp), abs(srcLoAmp)))

    selectObject: result
    outDur = Get total duration
    outHiAmp = Get maximum: 0, 0, "None"
    outLoAmp = Get minimum: 0, 0, "None"
    outAmp = max(1e-6, max(abs(outHiAmp), abs(outLoAmp)))

    # --- process tables ------------------------------------------------------
    hasMap = 0
    nMap = 0
    if fileReadable(tempMap$)
        mapTbl = Read Table from comma-separated file: tempMap$
        nMap = Get number of rows
        if nMap >= 2
            hasMap = 1
            # A single outlier grain can push the principal map's full range
            # far enough to collapse every other grain into one blob, so the
            # panel is framed on the central 96% and stragglers are clamped
            # onto the border instead of setting the scale.
            mapXlo = Get quantile: "x", 0.05
            mapXhi = Get quantile: "x", 0.95
            mapYlo = Get quantile: "y", 0.05
            mapYhi = Get quantile: "y", 0.95
            mapUseHi = Get maximum: "usage"
            mapF3hi = Get maximum: "f3_hz"
        else
            removeObject: mapTbl
        endif
    endif

    hasSched = 0
    nSched = 0
    if fileReadable(tempSched$)
        schedTbl = Read Table from comma-separated file: tempSched$
        nSched = Get number of rows
        if nSched >= 2
            hasSched = 1
            schedGainHi = Get maximum: "gain"
        else
            removeObject: schedTbl
        endif
    endif

    fullFigure = 0
    if hasMap = 1 and hasSched = 1
        fullFigure = 1
    endif

    # --- layout --------------------------------------------------------------
    if fullFigure
        canvasH = 11.28
        yA1a = 0.82
        yA1b = 1.36
        yA2a = 1.38
        yA2b = 1.62
        yBa = 1.85
        yBb = 2.75
        yCa = 3.32
        yCb = 5.22
        yDa = 5.85
        yDb = 6.75
        yEa = 6.77
        yEb = 7.42
        yFa = 8.02
        yFb = 8.57
        yGa = 8.79
        yGb = 9.81
        yHa = 10.31
        yHb = 11.11
    else
        canvasH = 6.40
        yA1a = 0.90
        yA1b = 1.70
        yFa = 2.05
        yFb = 2.85
        yGa = 3.20
        yGb = 4.55
        yHa = 5.05
        yHb = 6.15
    endif

    gateOn = 0
    if statFormantActive$ = "1"
        gateOn = 1
    endif
    gateTxt$ = "FORMANT SPACE DISABLED - spectral / dynamic fallback"
    if gateOn
        gateTxt$ = "FORMANT SPACE ACTIVE"
    endif

    @snapStep: srcXmax - srcXmin, 8
    snapT = snapStep.step

    Erase all
    Colour: "Black"
    Line width: 1
    Solid line

    # --- title ---------------------------------------------------------------
    @sanitize: soundName$
    hdrName$ = sanitize.out$
    @sanitize: replace$(swarmMode$, "_", " ", 0)
    hdrMode$ = sanitize.out$

    Font size: 13
    Select inner viewport: vizL, vizR, 0.05, 0.62
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##Formant Swarm Granulator##"
    Font size: 7
    Select inner viewport: vizL, vizR, 0.05, 0.62
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.24, "half", hdrName$ + "   |   " + hdrMode$ + "   |   " + gateTxt$
    Colour: "Black"

    # --- A1: source waveform -------------------------------------------------
    if fullFigure
        @caption: vizL, vizR, yA1a, yA1b, "Source and the resonance gate - which grains earned trustworthy formant landmarks"
    else
        @caption: vizL, vizR, yA1a, yA1b, "Source waveform"
    endif
    Font size: 7
    Select inner viewport: vizL, vizR, yA1a, yA1b
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, -srcAmp, srcAmp, "no", "Curve"
    Colour: "Black"
    Select inner viewport: vizL, vizR, yA1a, yA1b
    Axes: srcXmin, srcXmax, -srcAmp, srcAmp
    Draw inner box
    @rail: yA1a, yA1b, "Source"

    if fullFigure
        # --- A2: per-grain gate ribbon ---------------------------------------
        Font size: 7
        Select inner viewport: vizL, vizR, yA2a, yA2b
        Axes: srcXmin, srcXmax, 0, 1
        Paint rectangle: "{1.00, 1.00, 1.00}", srcXmin, srcXmax, 0, 1
        selectObject: mapTbl
        for i from 1 to nMap
            gStart = Get value: i, "start_s"
            gDur = Get value: i, "dur_s"
            gValid = Get value: i, "valid"
            gContr = Get value: i, "contrast_db"
            gConf = Get value: i, "confidence"
            cellHi = gStart + gDur
            if i < nMap
                iNext = i + 1
                nextStart = Get value: iNext, "start_s"
                cellHi = max(gStart + 0.002, min(cellHi, nextStart))
            endif
            if gValid < 0.5
                ribCol$ = "{0.87, 0.87, 0.87}"
            else
                # Darkness = how far the measured resonance contrast clears the
                # threshold the gate actually used. Orange = measured but not
                # supported by the local spectrum.
                over = (gContr - min_resonance_contrast_dB) / 3
                if over < 0
                    shade = min(1, max(0, (gContr + 2) / max(0.2, min_resonance_contrast_dB + 2)))
                    ribCol$ = "{" + fixed$(0.95 - 0.10 * shade, 3) + ", " + fixed$(0.80 - 0.30 * shade, 3) + ", " + fixed$(0.62 - 0.40 * shade, 3) + "}"
                else
                    shade = min(1, over)
                    ribCol$ = "{" + fixed$(0.72 - 0.57 * shade, 3) + ", " + fixed$(0.84 - 0.29 * shade, 3) + ", " + fixed$(0.94 - 0.12 * shade, 3) + "}"
                endif
            endif
            confHi = 0.25 + 0.75 * min(1, max(0, gConf))
            Paint rectangle: ribCol$, gStart + srcXmin, cellHi + srcXmin, 0, confHi
        endfor
        Colour: "Black"
        Select inner viewport: vizL, vizR, yA2a, yA2b
        Axes: srcXmin, srcXmax, 0, 1
        Draw inner box
        Marks bottom every: 1, snapT, "no", "yes", "no"
        @rail: yA2a, yA2b, "Gate"

        # --- B: formant landmarks --------------------------------------------
        bCap$ = "Formant landmarks as measured - the gate rejected them, so none of this reached the swarm"
        if gateOn
            bCap$ = "Formant landmarks of the gated grains - dot size is descriptor confidence, dashed lines are the reliable means"
        endif
        @caption: vizL, vizR, yBa, yBb, bCap$
        fMaxHz = min(nyquist, max(3000, 1.15 * mapF3hi))
        Font size: 7
        Select inner viewport: vizL, vizR, yBa, yBb
        Axes: srcXmin, srcXmax, 0, fMaxHz
        Paint rectangle: "{1.00, 1.00, 1.00}", srcXmin, srcXmax, 0, fMaxHz

        # reliable means first, so the dots sit on top of them
        Dotted line
        Colour: "{0.72, 0.72, 0.78}"
        if gateOn
            meanF1 = number(statMeanF1$)
            meanF2 = number(statMeanF2$)
            meanF3 = number(statMeanF3$)
            if meanF1 <> undefined and meanF1 > 0
                Draw line: srcXmin, meanF1, srcXmax, meanF1
            endif
            if meanF2 <> undefined and meanF2 > 0
                Draw line: srcXmin, meanF2, srcXmax, meanF2
            endif
            if meanF3 <> undefined and meanF3 > 0
                Draw line: srcXmin, meanF3, srcXmax, meanF3
            endif
        endif
        Solid line
        Colour: "Black"

        Select inner viewport: vizL, vizR, yBa, yBb
        Axes: srcXmin, srcXmax, 0, fMaxHz
        selectObject: mapTbl
        for i from 1 to nMap
            gStart = Get value: i, "start_s"
            gDur = Get value: i, "dur_s"
            gValid = Get value: i, "valid"
            gConf = Get value: i, "confidence"
            gF1 = Get value: i, "f1_hz"
            gF2 = Get value: i, "f2_hz"
            gF3 = Get value: i, "f3_hz"
            tMid = srcXmin + gStart + 0.5 * gDur
            if gValid > 0.5
                dotD = 0.7 + 1.1 * min(1, max(0, gConf))
                Paint circle (mm): "{0.85, 0.42, 0.18}", tMid, gF1, dotD
                Paint circle (mm): "{0.20, 0.62, 0.38}", tMid, gF2, dotD
                Paint circle (mm): "{0.60, 0.32, 0.70}", tMid, gF3, dotD
            else
                Paint rectangle: "{0.80, 0.80, 0.80}", tMid - 0.3 * gDur, tMid + 0.3 * gDur, 0.012 * fMaxHz, 0.030 * fMaxHz
            endif
        endfor

        # legend
        Font size: 6
        Select inner viewport: vizL, vizR, yBa, yBb
        Axes: 0, 1, 0, 1
        legY = 0.93
        Paint circle (mm): "{0.85, 0.42, 0.18}", 0.725, legY, 1.3
        Text: 0.737, "left", legY, "half", "F1"
        Paint circle (mm): "{0.20, 0.62, 0.38}", 0.793, legY, 1.3
        Text: 0.805, "left", legY, "half", "F2"
        Paint circle (mm): "{0.60, 0.32, 0.70}", 0.861, legY, 1.3
        Text: 0.873, "left", legY, "half", "F3"
        Paint rectangle: "{0.80, 0.80, 0.80}", 0.920, 0.935, legY - 0.022, legY + 0.022
        Text: 0.941, "left", legY, "half", "none"

        Font size: 7
        Select inner viewport: vizL, vizR, yBa, yBb
        Axes: srcXmin, srcXmax, 0, fMaxHz
        Colour: "Black"
        Draw inner box
        @snapStep: fMaxHz, 4
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        Marks bottom every: 1, snapT, "yes", "yes", "no"
        Text bottom: "yes", "Source time (s)"
        @rail: yBa, yBb, "Hz"

        # --- C left: feature space and the swarm walk -------------------------
        @caption: vizL, 3.95, yCa, yCb, "Feature space and the swarm walk - dot size = grain reuse"
        padX = max(0.10, 0.10 * (mapXhi - mapXlo))
        padY = max(0.10, 0.10 * (mapYhi - mapYlo))
        cx1 = mapXlo - padX
        cx2 = mapXhi + padX
        cy1 = mapYlo - padY
        cy2 = mapYhi + padY
        cxIn1 = cx1 + 0.015 * (cx2 - cx1)
        cxIn2 = cx2 - 0.015 * (cx2 - cx1)
        cyIn1 = cy1 + 0.015 * (cy2 - cy1)
        cyIn2 = cy2 - 0.015 * (cy2 - cy1)

        Font size: 7
        Select inner viewport: vizL, 3.95, yCa, yCb
        Axes: cx1, cx2, cy1, cy2
        Paint rectangle: "{1.00, 1.00, 1.00}", cx1, cx2, cy1, cy2

        # walk first, grains on top
        pathStride = 1
        if nSched > 1200
            pathStride = ceiling(nSched / 1200)
        endif
        Line width: 1
        Colour: "{0.68, 0.71, 0.82}"
        selectObject: schedTbl
        prevX = undefined
        prevY = undefined
        for i from 1 to nSched
            if i - pathStride * floor(i / pathStride) = 0 or pathStride = 1
                eX = Get value: i, "x"
                eY = Get value: i, "y"
                eX = min(cxIn2, max(cxIn1, eX))
                eY = min(cyIn2, max(cyIn1, eY))
                if prevX <> undefined
                    Draw line: prevX, prevY, eX, eY
                endif
                prevX = eX
                prevY = eY
            endif
        endfor

        Select inner viewport: vizL, 3.95, yCa, yCb
        Axes: cx1, cx2, cy1, cy2
        offScale = 0
        selectObject: mapTbl
        for i from 1 to nMap
            gX = Get value: i, "x"
            gY = Get value: i, "y"
            if gX < cxIn1 or gX > cxIn2 or gY < cyIn1 or gY > cyIn2
                offScale = offScale + 1
            endif
            gX = min(cxIn2, max(cxIn1, gX))
            gY = min(cyIn2, max(cyIn1, gY))
            gClu = Get value: i, "cluster"
            gUse = Get value: i, "usage"
            useNorm = 0
            if mapUseHi > 0
                useNorm = gUse / mapUseHi
            endif
            if gUse < 0.5
                @clusterCol: gClu, 0.70
                Paint circle (mm): clusterCol.col$, gX, gY, 0.7
            else
                @clusterCol: gClu, 0
                Paint circle (mm): clusterCol.col$, gX, gY, 0.9 + 1.7 * useNorm
            endif
        endfor

        Colour: "Black"
        Select inner viewport: vizL, 3.95, yCa, yCb
        Axes: cx1, cx2, cy1, cy2
        Draw inner box
        @snapStep: cx2 - cx1, 4
        Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        @snapStep: cy2 - cy1, 4
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: vizL, 3.95, yCa, yCb
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "Feature axis 1  (sets pan)"
        Text left: "yes", "Feature axis 2  (sets pitch drift)"
        if offScale > 0
            Paint rectangle: "{1.00, 1.00, 1.00}", 0.44, 0.995, 0.005, 0.070
            Colour: "{0.45, 0.45, 0.55}"
            Text: 0.985, "right", 0.038, "half", string$(offScale) + " off-scale, drawn on the border"
            Colour: "Black"
        endif

        # --- C right: cluster budget -----------------------------------------
        @caption: 4.40, vizR, yCa, yCb, "Cluster budget - grains (pale) vs scheduled events (solid)"
        cg0 = 0
        cg1 = 0
        cg2 = 0
        cg3 = 0
        cg4 = 0
        cg5 = 0
        selectObject: mapTbl
        for i from 1 to nMap
            gClu = Get value: i, "cluster"
            if gClu = 0
                cg0 = cg0 + 1
            elsif gClu = 1
                cg1 = cg1 + 1
            elsif gClu = 2
                cg2 = cg2 + 1
            elsif gClu = 3
                cg3 = cg3 + 1
            elsif gClu = 4
                cg4 = cg4 + 1
            else
                cg5 = cg5 + 1
            endif
        endfor
        ce0 = 0
        ce1 = 0
        ce2 = 0
        ce3 = 0
        ce4 = 0
        ce5 = 0
        selectObject: schedTbl
        for i from 1 to nSched
            eClu = Get value: i, "cluster"
            if eClu = 0
                ce0 = ce0 + 1
            elsif eClu = 1
                ce1 = ce1 + 1
            elsif eClu = 2
                ce2 = ce2 + 1
            elsif eClu = 3
                ce3 = ce3 + 1
            elsif eClu = 4
                ce4 = ce4 + 1
            else
                ce5 = ce5 + 1
            endif
        endfor

        budMax = 1
        for k from 0 to 5
            @budgetShare: k
            budMax = max(budMax, budgetShare.pool, budgetShare.play)
        endfor
        budMax = budMax * 1.22

        Font size: 7
        Select inner viewport: 4.40, vizR, yCa, yCb
        Axes: 0, budMax, 0, 6
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, budMax, 0, 6
        for k from 0 to 5
            @budgetShare: k
            rowTop = 6 - k
            @clusterCol: k, 0.55
            Paint rectangle: clusterCol.col$, 0, budgetShare.pool, rowTop - 0.44, rowTop - 0.12
            @clusterCol: k, 0
            Paint rectangle: clusterCol.col$, 0, budgetShare.play, rowTop - 0.82, rowTop - 0.50
        endfor
        Colour: "Black"
        Select inner viewport: 4.40, vizR, yCa, yCb
        Axes: 0, budMax, 0, 6
        Font size: 6
        for k from 0 to 5
            @budgetShare: k
            rowTop = 6 - k
            Text: budgetShare.play + 0.02 * budMax, "left", rowTop - 0.47, "half", fixed$(budgetShare.pool, 1) + " / " + fixed$(budgetShare.play, 1)
        endfor
        Font size: 7
        Select inner viewport: 4.40, vizR, yCa, yCb
        Axes: 0, budMax, 0, 6
        Draw inner box
        for k from 0 to 5
            rowTop = 6 - k
            One mark left: rowTop - 0.47, "no", "yes", "no", "C" + string$(k)
        endfor
        @snapStep: budMax, 4
        Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: 4.40, vizR, yCa, yCb
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "Share of total (\% )"

        # --- D: schedule, output time against source time ---------------------
        srcPad = 0.04 * max(1e-6, srcXmax - srcXmin)
        srcYlo = srcXmin - srcPad
        srcYhi = srcXmax + srcPad
        @caption: vizL, vizR, yDa, yDb, "Swarm schedule - which source moment plays when, and where it lands in the stereo field"
        Font size: 7
        Select inner viewport: vizL, vizR, yDa, yDb
        Axes: 0, outDur, srcYlo, srcYhi
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, outDur, srcYlo, srcYhi
        Dotted line
        Colour: "{0.72, 0.72, 0.78}"
        diagEnd = min(outDur, srcXmax - srcXmin)
        Draw line: 0, srcXmin, diagEnd, srcXmin + diagEnd
        Solid line
        Select inner viewport: vizL, vizR, yDa, yDb
        Axes: 0, outDur, srcYlo, srcYhi
        selectObject: schedTbl
        for i from 1 to nSched
            eOut = Get value: i, "out_start_s"
            eSrc = Get value: i, "src_start_s"
            eClu = Get value: i, "cluster"
            eGain = Get value: i, "gain"
            gNorm = 0
            if schedGainHi > 0
                gNorm = eGain / schedGainHi
            endif
            @clusterCol: eClu, 0
            Paint circle (mm): clusterCol.col$, eOut, srcXmin + eSrc, 0.7 + 0.9 * gNorm
        endfor
        Colour: "Black"
        Select inner viewport: vizL, vizR, yDa, yDb
        Axes: 0, outDur, srcYlo, srcYhi
        Draw inner box
        @snapStep: srcXmax - srcXmin, 3
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        @snapStep: outDur, 8
        snapOut = snapStep.step
        Marks bottom every: 1, snapOut, "no", "yes", "no"
        @rail: yDa, yDb, "Source s"

        # --- E: pan field ------------------------------------------------------
        Font size: 7
        Select inner viewport: vizL, vizR, yEa, yEb
        Axes: 0, outDur, -1.1, 1.1
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, outDur, -1.1, 1.1
        Dotted line
        Colour: "{0.72, 0.72, 0.78}"
        Draw line: 0, 0, outDur, 0
        Solid line
        Select inner viewport: vizL, vizR, yEa, yEb
        Axes: 0, outDur, -1.1, 1.1
        selectObject: schedTbl
        for i from 1 to nSched
            eOut = Get value: i, "out_start_s"
            ePan = Get value: i, "pan"
            eClu = Get value: i, "cluster"
            eGain = Get value: i, "gain"
            gNorm = 0
            if schedGainHi > 0
                gNorm = eGain / schedGainHi
            endif
            @clusterCol: eClu, 0
            Paint circle (mm): clusterCol.col$, eOut, ePan, 0.7 + 0.9 * gNorm
        endfor
        Colour: "Black"
        Select inner viewport: vizL, vizR, yEa, yEb
        Axes: 0, outDur, -1.1, 1.1
        Draw inner box
        One mark left: 0.86, "no", "yes", "no", "R"
        One mark left: 0, "no", "yes", "no", "0"
        One mark left: -0.86, "no", "yes", "no", "L"
        Marks bottom every: 1, snapOut, "yes", "yes", "no"
        Text bottom: "yes", "Output time (s)"
        @rail: yEa, yEb, "Pan L-R"
    endif

    # --- F: rendered output --------------------------------------------------
    @caption: vizL, vizR, yFa, yFb, "Rendered swarm"
    Font size: 7
    Select inner viewport: vizL, vizR, yFa, yFb
    selectObject: result
    Colour: "{0.15, 0.55, 0.82}"
    Draw: 0, 0, -outAmp, outAmp, "no", "Curve"
    Colour: "Black"
    Select inner viewport: vizL, vizR, yFa, yFb
    Axes: 0, outDur, -outAmp, outAmp
    Draw inner box
    @rail: yFa, yFb, "Swarm"

    # --- G: output spectrogram -----------------------------------------------
    @caption: vizL, vizR, yGa, yGb, "Output spectrogram (channel 1)"
    Font size: 7
    Select inner viewport: vizL, vizR, yGa, yGb
    selectObject: result
    Extract one channel: 1
    vizCh = selected("Sound")
    vizMaxHz = min(5000, sampleRate / 2 - 50)
    To Spectrogram: 0.03, vizMaxHz, 0.002, 20, "Gaussian"
    vizSpec = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
    removeObject: vizSpec, vizCh
    Colour: "Black"
    Select inner viewport: vizL, vizR, yGa, yGb
    Axes: 0, outDur, 0, vizMaxHz
    Draw inner box
    @snapStep: vizMaxHz, 3
    Marks left every: 1, snapStep.step, "yes", "yes", "no"
    @snapStep: outDur, 8
    Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Output time (s)"
    @rail: yGa, yGb, "Hz"

    # --- H: summary ----------------------------------------------------------
    Font size: 7
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    @sanitize: replace$(statFeatures$, ",", ", ", 0)
    featTxt$ = sanitize.out$

    Font size: 8
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.015, "left", 0.90, "half", "##Process summary##"

    Font size: 7
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Text: 0.015, "left", 0.755, "half", "Gate: " + gateTxt$ + "  -  reliable " + statValidGrains$ + "/" + statGrains$
        ... + ", ratio " + statValidRatio$ + " (min " + fixed$(min_reliable_formant_ratio, 2) + ")"
        ... + ", median contrast " + statMedianContrast$ + " dB (min " + fixed$(min_resonance_contrast_dB, 2) + ")"
        ... + ", mean confidence " + statMeanConfidence$
    Text: 0.015, "left", 0.620, "half", "Feature space: " + featTxt$ + "  -  " + statClusters$ + " clusters"
    Text: 0.015, "left", 0.485, "half", "Reliable means: F1 " + statMeanF1$ + "   F2 " + statMeanF2$ + "   F3 " + statMeanF3$ + " Hz"
    Text: 0.015, "left", 0.350, "half", "Swarm: " + hdrMode$ + ", " + statScheduled$ + " events over " + fixed$(outDur, 2) + " s"
        ... + ", density " + fixed$(density_grains_per_sec, 1) + "/s"
        ... + ", attraction " + fixed$(attraction, 2)
        ... + ", repulsion time " + fixed$(temporal_repulsion, 2) + " / density " + fixed$(density_repulsion, 2)
    reuseTxt$ = "Grain reuse: not reported by this engine"
    if fullFigure
        reuseTxt$ = "Grain reuse: median " + statMedReuse$ + ", max " + statMaxReuse$
            ... + ", " + statUnused$ + " of " + statGrains$ + " never used"
    endif
    Text: 0.015, "left", 0.215, "half", reuseTxt$ + "   |   pan spread " + fixed$(pan_spread, 2)
        ... + ", pitch drift \+- " + fixed$(pitch_drift_semitones, 2) + " st"
    Text: 0.015, "left", 0.080, "half", "Level: RMS in " + statRmsIn$ + " to out " + statRmsOut$ + ", peak " + fixed$(outAmp, 3)
        ... + "   |   grain " + fixed$(grainLengthSec * 1000, 1) + " ms, hop " + fixed$(hopSec * 1000, 1) + " ms"
    if fullFigure = 0
        Colour: "{0.70, 0.35, 0.10}"
        Text: 0.985, "right", 0.90, "half", "compact figure: engine did not export the process tables"
        Colour: "Black"
    endif
    Select inner viewport: vizL, vizR, yHa, yHb
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1

    if hasMap
        removeObject: mapTbl
    endif
    if hasSched
        removeObject: schedTbl
    endif

    # The PNG export follows the CURRENT viewport selection, so end on the
    # whole canvas or Save/Copy silently crops to the last panel.
    Select outer viewport: 0, 8, 0, canvasH
endif

@cleanUpTempFiles
if random_seed > 0
    random_initializeSafelyAndUnpredictably()
endif

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_formantSwarm"
appendInfoLine: "Reliable formants: ", statValidGrains$, "/", statGrains$, " (ratio ", statValidRatio$, ")"
appendInfoLine: "Formant features active: ", statFormantActive$
appendInfoLine: "Median resonance contrast: ", statMedianContrast$, " dB"
appendInfoLine: "Feature space: ", statFeatures$
appendInfoLine: "RMS in/out: ", statRmsIn$, " / ", statRmsOut$

selectObject: result
if play_result
    Play
endif

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

# -----------------------------------------------------------------------------
# Drawing helpers
# -----------------------------------------------------------------------------

# Picture-window text treats _ ^ # % and \ as markup, so every machine-generated
# label (object names, mode names, feature lists) has to be escaped first.
procedure sanitize: .s$
    .out$ = replace$(.s$, "\", "\bs ", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
endproc

# Six cluster hues, tinted towards white by .tint (0 = full strength).
procedure clusterCol: .k, .tint
    .i = .k - 6 * floor(.k / 6)
    if .i = 0
        .r = 0.15
        .g = 0.55
        .b = 0.82
    elsif .i = 1
        .r = 0.85
        .g = 0.42
        .b = 0.18
    elsif .i = 2
        .r = 0.20
        .g = 0.62
        .b = 0.38
    elsif .i = 3
        .r = 0.60
        .g = 0.32
        .b = 0.70
    elsif .i = 4
        .r = 0.88
        .g = 0.66
        .b = 0.10
    else
        .r = 0.30
        .g = 0.42
        .b = 0.62
    endif
    .col$ = "{" + fixed$(.r + (1 - .r) * .tint, 3)
        ... + ", " + fixed$(.g + (1 - .g) * .tint, 3)
        ... + ", " + fixed$(.b + (1 - .b) * .tint, 3) + "}"
endproc

# A tick step derived as span/N prints labels like 0.6569; snap it to 1/2/5.
procedure snapStep: .span, .target
    .step = 1
    if .span > 0
        if .target > 0
            .raw = .span / .target
            .mag = 10 ^ floor(log10(.raw))
            .n = .raw / .mag
            if .n <= 1.5
                .step = .mag
            elsif .n <= 3.5
                .step = 2 * .mag
            elsif .n <= 7.5
                .step = 5 * .mag
            else
                .step = 10 * .mag
            endif
        endif
    endif
endproc

# Text left: anchors against whatever drawing frame is current, which puts each
# panel's name at a different x. Place the rail by hand at one shared offset.
procedure rail: .y1, .y2, .name$
    Font size: 7
    Select inner viewport: vizL, vizR, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure caption: .x1, .x2, .y1, .y2, .txt$
    Font size: 6
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text top: "no", .txt$
    Colour: "Black"
endproc

# Percentage of the grain pool and of the scheduled events held by cluster .k.
procedure budgetShare: .k
    if .k = 0
        .cg = cg0
        .ce = ce0
    elsif .k = 1
        .cg = cg1
        .ce = ce1
    elsif .k = 2
        .cg = cg2
        .ce = ce2
    elsif .k = 3
        .cg = cg3
        .ce = ce3
    elsif .k = 4
        .cg = cg4
        .ce = ce4
    else
        .cg = cg5
        .ce = ce5
    endif
    .pool = 0
    .play = 0
    if nMap > 0
        .pool = 100 * .cg / nMap
    endif
    if nSched > 0
        .play = 100 * .ce / nSched
    endif
endproc
