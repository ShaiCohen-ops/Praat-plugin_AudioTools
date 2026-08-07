# ============================================================
# Praat AudioTools - FormantSwarmGranulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.3 (2026) - Validity-aware formant descriptors
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

form Formant Swarm Granulator v1.3
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
    exitScript: "Cannot find Python engine: " + pythonScript$
endif

tempInput$ = temporaryDirectory$ + "/temp_fsg_input.wav"
tempCSV$ = temporaryDirectory$ + "/temp_fsg_grains.csv"
tempOutput$ = temporaryDirectory$ + "/temp_fsg_output.wav"
tempStats$ = temporaryDirectory$ + "/temp_fsg_stats.txt"
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
writeInfoLine: "=== Formant Swarm Granulator v1.3 ==="
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
    appendInfoLine: ""
    appendInfoLine: "--- Engine stats ---"
    appendInfoLine: statsText$
endif

# -----------------------------------------------------------------------------
# Visualization
# -----------------------------------------------------------------------------
if draw_visualization
    Erase all

    Select outer viewport: 0, 8, 0.1, 0.65
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Formant Swarm Granulator##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", -1.10, "half", soundName$ + " | " + swarmMode$

    Select outer viewport: 0, 8, 0.8, 1.8
    Select inner viewport: 0.65, 7.7, 0.9, 1.7
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"

    Select outer viewport: 0, 8, 1.9, 2.9
    Select inner viewport: 0.65, 7.7, 2.0, 2.8
    selectObject: result
    Colour: "{0.15, 0.55, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Swarm"
    Text bottom: "yes", "Time (s)"

    # Output spectrogram, channel 1 only.
    Select outer viewport: 0, 8, 3.05, 4.8
    Select inner viewport: 0.65, 7.7, 3.15, 4.7
    selectObject: result
    Extract one channel: 1
    vizCh = selected("Sound")
    vizMaxHz = min(5000, sampleRate / 2 - 50)
    To Spectrogram: 0.03, vizMaxHz, 0.002, 20, "Gaussian"
    vizSpec = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Swarm spectrogram"
    removeObject: vizSpec, vizCh

    Select outer viewport: 0, 8, 5.0, 6.25
    Select inner viewport: 0.65, 7.7, 5.08, 6.18
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.86, "half", "##Descriptor confidence##"
    Font size: 7
    Text: 0.02, "left", 0.66, "half", "Reliable grains: " + statValidGrains$ + "/" + statGrains$ + "  ratio=" + statValidRatio$
    Text: 0.02, "left", 0.49, "half", "Formant features active: " + statFormantActive$ + "  confidence=" + statMeanConfidence$ + "  contrast=" + statMedianContrast$ + " dB"
    Text: 0.02, "left", 0.32, "half", "Features: " + statFeatures$
    Text: 0.02, "left", 0.15, "half", "Reliable means: F1=" + statMeanF1$ + "  F2=" + statMeanF2$ + "  F3=" + statMeanF3$ + " Hz"
    Draw rectangle: 0, 1, 0, 1
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
