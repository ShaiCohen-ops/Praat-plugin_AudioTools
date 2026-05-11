# ============================================================
# Praat AudioTools - PitchTrackedAdditive.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   IRCAM-Style Pitch-Tracked Additive Resynthesizer
#
#   Tracks F0 and intensity of a selected Sound, then performs
#   sample-accurate additive synthesis whose instantaneous partial
#   frequencies are derived mathematically from the tracked F0
#   curve via phase accumulation (no naive sin(2*pi*f0(t)*t)).
#
#   Partial families:
#     - harmonic, odd_only, even_only
#     - subharmonic
#     - inharmonic_power (k**beta * f0)
#     - frequency_shifted
#     - ring_sidebands
#     - fm_sidebands
#
#   Amplitude laws:
#     - 1/k, 1/k^2, equal
#     - spectral tilt (dB/octave)
#     - gaussian formant band
#     - random static / random slow
#
#   ENGINEERING NOTES:
#   - F0 + intensity + events CSV building: each CSV is built
#     as an in-memory string and written with one writeFile call.
#     appendFileLine inside a loop opens+closes the file every
#     iteration, which is dramatically slower.
#   - Cross-platform Python discovery: macOS tries Homebrew,
#     Framework, /usr/local, then PATH; Windows uses "python";
#     other platforms use "python3". A probe step verifies
#     numpy + scipy + soundfile before invoking the engine.
#   - The probe marker path is regex-converted from Windows
#     backslashes to forward slashes so Python sees a portable
#     path in the probe command string.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.1:
#   - Audio pipeline UNCHANGED. Output bit-identical to v1.0
#     for the same form parameters and same seed. Same pitch
#     tracking, same intensity extraction, same event-segment
#     building, same Python additive engine (helper unchanged),
#     same stats parsing.
#   - NEW: Show_spectrograms form toggle (default OFF). v1.0
#     always computed `To Spectrogram` twice (original + synth)
#     for the visualization panels — that can take several
#     seconds on long files. Default OFF means the script's
#     wallclock is dominated only by feature extraction and
#     the Python additive engine. Turn ON to see the
#     time-frequency comparison between input and resynthesis.
#   - Visualization rewritten to suite 8x8 standard (v1.0 used
#     8x9):
#       Title bar + metadata subtitle
#       Panel A (left, headline): tracked F0 contour — the
#         analysis input that drives synthesis
#       Panel B (right, headline): partial frequency plan
#         (min/mean/max ranges per partial) — the synthesis
#         spec, this script's most distinctive visual
#       Panel C: original waveform (or original spectrogram
#         when Show_spectrograms = ON)
#       Panel D: synthesized waveform (or synth spectrogram
#         when Show_spectrograms = ON)
#       Panel E: summary stats bar
#     All v1.0 information preserved (F0 trace, partial ranges,
#     waveform comparison, F0/RMS/peak stats, voiced %).
#   - Header documents the engineering pieces (CSV strategy,
#     Python discovery, probe marker path conversion) so future
#     maintainers understand what is intentional.
# Changelog v1.0:
#   - Initial unified cross-platform release.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/pitch_tracked_additive.py"

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: " + pythonScript$ + newline$ + "Please verify AudioTools installation."
endif

tempInput$     = temporaryDirectory$ + "/temp_ptadd_input.wav"
tempF0$        = temporaryDirectory$ + "/temp_ptadd_f0.csv"
tempIntensity$ = temporaryDirectory$ + "/temp_ptadd_intensity.csv"
tempEvents$    = temporaryDirectory$ + "/temp_ptadd_events.csv"
tempOutput$    = temporaryDirectory$ + "/temp_ptadd_output.wav"
tempStats$     = temporaryDirectory$ + "/temp_ptadd_stats.txt"
probeMarker$   = temporaryDirectory$ + "/temp_ptadd_probe.ok"

probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempF0$)
        deleteFile: tempF0$
    endif
    if fileReadable(tempIntensity$)
        deleteFile: tempIntensity$
    endif
    if fileReadable(tempEvents$)
        deleteFile: tempEvents$
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

# ---- FORM ----
form Pitch-Tracked Additive Resynthesizer v1.1
    optionmenu Preset: 1
        option custom
        option natural_voice
        option bright_harmonic
        option hollow_odd
        option inharmonic_bells
        option ring_metal
        option fm_electric
        option subharmonic_bass
        option formant_vowel
    optionmenu Partial_family: 1
        option harmonic
        option odd_only
        option even_only
        option subharmonic
        option inharmonic_power
        option frequency_shifted
        option ring_sidebands
        option fm_sidebands
    optionmenu Amplitude_law: 1
        option 1_over_k
        option 1_over_k_squared
        option equal
        option spectral_tilt_db_per_octave
        option gaussian_formant_band
        option random_static
        option random_slow
    integer Num_partials 16
    real Pitch_floor_Hz 75
    real Pitch_ceiling_Hz 600
    optionmenu Voicing_policy: 1
        option silence_unvoiced
        option noise_unvoiced
        option copy_original_unvoiced
    real Output_duration_s 0
    boolean Show_spectrograms 0
    comment (ON shows time-frequency comparison, but adds analysis time)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- DEFAULTS for fields removed from form ----
envelope_source = 1
stereo_mode = 1
normalize_mode = 3
attack_release_smoothing_ms = 15
spectral_tilt_db_per_octave = -6
formant_center_hz = 1200
formant_bandwidth_hz = 500
inharmonic_beta = 1.03
frequency_shift_hz = 0
ring_modulator_hz = 80
fm_modulator_ratio = 2.0
fm_index = 2.0
seed = 42
cleanup = 1

# ---- PRESET APPLICATION ----
# Presets set: partial_family, amplitude_law, num_partials, voicing_policy,
#              envelope_source, stereo_mode, inharmonic_beta, frequency_shift_Hz,
#              ring_mod_Hz, fm_ratio, fm_index, formant_center_Hz, formant_bw_Hz,
#              spectral_tilt_dB_oct
if preset = 2
    # natural_voice — warm harmonic speech resynthesis
    partial_family = 1
    amplitude_law = 1
    num_partials = 24
    voicing_policy = 3
    envelope_source = 1
    stereo_mode = 1
    spectral_tilt_db_per_octave = -6
    inharmonic_beta = 1.0
elsif preset = 3
    # bright_harmonic — full bright harmonic spectrum
    partial_family = 1
    amplitude_law = 3
    num_partials = 32
    voicing_policy = 2
    envelope_source = 1
    stereo_mode = 2
    spectral_tilt_db_per_octave = -3
elsif preset = 4
    # hollow_odd — clarinet-like odd harmonics only
    partial_family = 2
    amplitude_law = 1
    num_partials = 16
    voicing_policy = 1
    envelope_source = 1
    stereo_mode = 1
    spectral_tilt_db_per_octave = -6
elsif preset = 5
    # inharmonic_bells — stretched partials, bell-like
    partial_family = 5
    amplitude_law = 2
    num_partials = 12
    voicing_policy = 1
    envelope_source = 2
    stereo_mode = 3
    inharmonic_beta = 1.08
elsif preset = 6
    # ring_metal — ring modulation metallic texture
    partial_family = 7
    amplitude_law = 3
    num_partials = 8
    voicing_policy = 1
    envelope_source = 2
    stereo_mode = 2
    ring_modulator_hz = 120
elsif preset = 7
    # fm_electric — FM synthesis electric timbre
    partial_family = 8
    amplitude_law = 3
    num_partials = 8
    voicing_policy = 2
    envelope_source = 1
    stereo_mode = 2
    fm_modulator_ratio = 2.0
    fm_index = 3.5
elsif preset = 8
    # subharmonic_bass — sub-octave bass reinforcement
    partial_family = 4
    amplitude_law = 1
    num_partials = 8
    voicing_policy = 2
    envelope_source = 1
    stereo_mode = 1
    spectral_tilt_db_per_octave = -3
elsif preset = 9
    # formant_vowel — gaussian formant emphasis
    partial_family = 1
    amplitude_law = 5
    num_partials = 20
    voicing_policy = 3
    envelope_source = 1
    stereo_mode = 1
    formant_center_hz = 1200
    formant_bandwidth_hz = 400
endif

# Fixed pitch time step (not exposed in form — always 5 ms)
pitch_time_step_s = 0.005

# ---- MAP OPTION-MENUS TO STRINGS ----
if partial_family = 1
    partialFamilyStr$ = "harmonic"
elsif partial_family = 2
    partialFamilyStr$ = "odd_only"
elsif partial_family = 3
    partialFamilyStr$ = "even_only"
elsif partial_family = 4
    partialFamilyStr$ = "subharmonic"
elsif partial_family = 5
    partialFamilyStr$ = "inharmonic_power"
elsif partial_family = 6
    partialFamilyStr$ = "frequency_shifted"
elsif partial_family = 7
    partialFamilyStr$ = "ring_sidebands"
else
    partialFamilyStr$ = "fm_sidebands"
endif

if amplitude_law = 1
    ampLawStr$ = "1_over_k"
elsif amplitude_law = 2
    ampLawStr$ = "1_over_k_squared"
elsif amplitude_law = 3
    ampLawStr$ = "equal"
elsif amplitude_law = 4
    ampLawStr$ = "spectral_tilt_db_per_octave"
elsif amplitude_law = 5
    ampLawStr$ = "gaussian_formant_band"
elsif amplitude_law = 6
    ampLawStr$ = "random_static"
else
    ampLawStr$ = "random_slow"
endif

if voicing_policy = 1
    voicingStr$ = "silence_unvoiced"
elsif voicing_policy = 2
    voicingStr$ = "noise_unvoiced"
else
    voicingStr$ = "copy_original_unvoiced"
endif

if envelope_source = 1
    envSourceStr$ = "intensity"
elsif envelope_source = 2
    envSourceStr$ = "rms"
else
    envSourceStr$ = "flat"
endif

if stereo_mode = 1
    stereoStr$ = "mono"
elsif stereo_mode = 2
    stereoStr$ = "haas_width"
else
    stereoStr$ = "partial_spread"
endif

if normalize_mode = 1
    normModeStr$ = "none"
elsif normalize_mode = 2
    normModeStr$ = "peak"
elsif normalize_mode = 3
    normModeStr$ = "rms"
else
    normModeStr$ = "loudness"
endif

# ---- CLAMP ----
if num_partials < 1
    num_partials = 1
endif
if num_partials > 128
    num_partials = 128
endif
if pitch_floor_Hz < 30
    pitch_floor_Hz = 30
endif
if pitch_ceiling_Hz < pitch_floor_Hz + 10
    pitch_ceiling_Hz = pitch_floor_Hz + 10
endif
if pitch_time_step_s < 0.001
    pitch_time_step_s = 0.001
endif
if attack_release_smoothing_ms < 0
    attack_release_smoothing_ms = 0
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== Pitch-Tracked Additive Resynthesizer v1.1 ==="
appendInfoLine: "Input:           ", soundName$
appendInfoLine: ""
appendInfoLine: "Pitch range:     ", fixed$(pitch_floor_Hz, 1), " - ", fixed$(pitch_ceiling_Hz, 1), " Hz"
appendInfoLine: "Pitch step:      ", fixed$(pitch_time_step_s, 4), " s"
appendInfoLine: "Num partials:    ", num_partials
appendInfoLine: "Partial family:  ", partialFamilyStr$
appendInfoLine: "Amplitude law:   ", ampLawStr$
appendInfoLine: "Voicing policy:  ", voicingStr$
appendInfoLine: "Envelope src:    ", envSourceStr$
appendInfoLine: "Stereo mode:     ", stereoStr$
appendInfoLine: "Normalize:       ", normModeStr$
appendInfoLine: "Seed:            ", seed
appendInfoLine: ""

# ---- CAPTURE STATS ----
selectObject: sound
dur       = Get total duration
sr        = Get sampling frequency
nChannels = Get number of channels
rms_orig  = Get root-mean-square: 0, 0

if output_duration_s <= 0
    output_duration_s = dur
endif

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Extract pitch / intensity / events
# ===========================================================================
appendInfoLine: "[2/5] Extracting pitch & intensity..."

selectObject: sound
if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

# ---- Pitch ----
selectObject: analysisMono
pitchObj = To Pitch: pitch_time_step_s, pitch_floor_Hz, pitch_ceiling_Hz

# Build F0 CSV and events CSV in memory, then write each in one shot.
# appendFileLine inside a loop opens+closes the file every iteration — very slow.
nFrames = floor(dur / pitch_time_step_s) + 1
nVoiced = 0
f0Csv$ = "time,f0_hz,voiced" + newline$
eventsCsv$ = "start_time,end_time,kind" + newline$
prevVoiced = -1
segStart = 0

for iFr from 0 to nFrames - 1
    t = iFr * pitch_time_step_s
    if t > dur
        t = dur
    endif
    selectObject: pitchObj
    f0v = Get value at time: t, "Hertz", "Linear"
    if f0v = undefined or f0v <= 0
        f0Out = 0
        vFlag = 0
    else
        f0Out = f0v
        vFlag = 1
        nVoiced = nVoiced + 1
    endif
    f0Csv$ = f0Csv$ + fixed$(t, 6) + "," + fixed$(f0Out, 4) + "," + string$(vFlag) + newline$

    # Build events on the same pass — no second loop needed
    if prevVoiced = -1
        prevVoiced = vFlag
        segStart = t
    elsif vFlag <> prevVoiced
        if prevVoiced = 1
            kind$ = "voiced"
        else
            kind$ = "unvoiced"
        endif
        eventsCsv$ = eventsCsv$ + fixed$(segStart, 6) + "," + fixed$(t, 6) + "," + kind$ + newline$
        segStart = t
        prevVoiced = vFlag
    endif
endfor

# Final events segment
if prevVoiced = 1
    kind$ = "voiced"
else
    kind$ = "unvoiced"
endif
eventsCsv$ = eventsCsv$ + fixed$(segStart, 6) + "," + fixed$(dur, 6) + "," + kind$ + newline$

# Write both files in one call each
writeFile: tempF0$, f0Csv$
writeFile: tempEvents$, eventsCsv$

appendInfoLine: "  F0 frames: ", nFrames, " (voiced: ", nVoiced, ")"

# ---- Intensity ----
selectObject: analysisMono
intObj = To Intensity: 100, 0.005, "yes"

intStep = 0.005
nIntFrames = floor(dur / intStep) + 1
intCsv$ = "time,intensity_db" + newline$
for iFr from 0 to nIntFrames - 1
    t = iFr * intStep
    if t > dur
        t = dur
    endif
    selectObject: intObj
    iv = Get value at time: t, "Cubic"
    if iv = undefined
        iv = 0
    endif
    intCsv$ = intCsv$ + fixed$(t, 6) + "," + fixed$(iv, 4) + newline$
endfor

writeFile: tempIntensity$, intCsv$

appendInfoLine: "  Intensity frames: ", nIntFrames

# ---- Save input WAV ----
selectObject: sound
Save as WAV file: tempInput$

removeObject: analysisMono, pitchObj, intObj

# ===========================================================================
# Stage 3 — Call Python
# ===========================================================================
appendInfoLine: "[3/5] Running Python additive engine..."

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempF0$ + """"
    ... + " """ + tempIntensity$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " --events_csv """ + tempEvents$ + """"
    ... + " --duration "         + fixed$(output_duration_s, 4)
    ... + " --num_partials "     + string$(num_partials)
    ... + " --partial_family "   + partialFamilyStr$
    ... + " --amplitude_law "    + ampLawStr$
    ... + " --spectral_tilt "    + fixed$(spectral_tilt_db_per_octave, 4)
    ... + " --inharmonic_beta "  + fixed$(inharmonic_beta, 4)
    ... + " --frequency_shift "  + fixed$(frequency_shift_hz, 4)
    ... + " --ring_mod "         + fixed$(ring_modulator_hz, 4)
    ... + " --fm_ratio "         + fixed$(fm_modulator_ratio, 4)
    ... + " --fm_index "         + fixed$(fm_index, 4)
    ... + " --formant_center "   + fixed$(formant_center_hz, 4)
    ... + " --formant_bw "       + fixed$(formant_bandwidth_hz, 4)
    ... + " --voicing_policy "   + voicingStr$
    ... + " --envelope_source "  + envSourceStr$
    ... + " --ar_smoothing_ms "  + fixed$(attack_release_smoothing_ms, 4)
    ... + " --stereo_mode "      + stereoStr$
    ... + " --normalize_mode "   + normModeStr$
    ... + " --seed "             + string$(seed)

if cleanup
    pythonCall$ = pythonCall$ + " --cleanup"
endif

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python additive engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 4 — Import result
# ===========================================================================
appendInfoLine: "[4/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_ptadd"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut  = Get total duration

# ===========================================================================
# Read stats
# ===========================================================================
nSamplesStat$    = "?"
sampleRateStat$  = "?"
durationStat$    = "?"
voicedPctStat$   = "?"
f0MeanStat$      = "?"
f0MedianStat$    = "?"
f0MinStat$       = "?"
f0MaxStat$       = "?"
nPartialsStat$   = "?"
partialFamStat$  = "?"
ampLawStat$      = "?"
normModeStat$    = "?"
rmsInStat$       = "?"
rmsOutStat$      = "?"
peakOutStat$     = "?"
warningStat$     = ""

nPartialEntries = 0
nF0Pts = 0

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_samples="
    nSamplesStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "sample_rate="
    sampleRateStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "duration="
    durationStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "voiced_percent="
    voicedPctStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "f0_mean_hz="
    f0MeanStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "f0_median_hz="
    f0MedianStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "f0_min_hz="
    f0MinStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "f0_max_hz="
    f0MaxStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "num_partials="
    nPartialsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "partial_family="
    partialFamStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "amplitude_law="
    ampLawStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_input="
    rmsInStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_output="
    rmsOutStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "peak_output="
    peakOutStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "warnings="
    warningStat$ = parseStatLine.result$

    # ---- Partial frequency ranges (up to 16) ----
    @parseStatLine: statsText$, "n_partial_entries="
    npe$ = parseStatLine.result$
    if npe$ <> "?"
        nPartialEntries = number(npe$)
    endif
    if nPartialEntries > 16
        nPartialEntries = 16
    endif
    for iP from 1 to nPartialEntries
        @parseStatLine: statsText$, "partial_" + string$(iP) + "="
        praw$ = parseStatLine.result$
        pmin_'iP' = 0
        pmax_'iP' = 0
        pmean_'iP' = 0
        if praw$ <> "?"
            c1 = index(praw$, ",")
            if c1 > 0
                pmin_'iP' = number(left$(praw$, c1 - 1))
                rest$ = mid$(praw$, c1 + 1, length(praw$) - c1)
                c2 = index(rest$, ",")
                if c2 > 0
                    pmax_'iP' = number(left$(rest$, c2 - 1))
                    pmean_'iP' = number(mid$(rest$, c2 + 1, length(rest$) - c2))
                endif
            endif
        endif
    endfor

    # ---- F0 trace samples ----
    @parseStatLine: statsText$, "n_f0_pts="
    nf0$ = parseStatLine.result$
    if nf0$ <> "?"
        nF0Pts = number(nf0$)
    endif
    if nF0Pts > 400
        nF0Pts = 400
    endif
    for iFp from 0 to nF0Pts - 1
        @parseStatLine: statsText$, "f0pt_" + string$(iFp) + "="
        fpraw$ = parseStatLine.result$
        f0t_'iFp' = 0
        f0v_'iFp' = 0
        if fpraw$ <> "?"
            c1 = index(fpraw$, ",")
            if c1 > 0
                f0t_'iFp' = number(left$(fpraw$, c1 - 1))
                f0v_'iFp' = number(mid$(fpraw$, c1 + 1, length(fpraw$) - c1))
            endif
        endif
    endfor
endif

# ============================================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[5/5] Drawing visualization..."

    # ----------------------------------------------------------
    # Compute spectrograms ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrograms
        appendInfoLine: "  Computing spectrograms..."

        selectObject: sound
        if nChannels > 1
            Extract one channel: 1
            tmpOrig = selected("Sound")
        else
            Copy: "tmpOrig"
            tmpOrig = selected("Sound")
        endif
        selectObject: tmpOrig
        To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
        specOrig = selected("Spectrogram")

        selectObject: resultSound
        outChans_pre = Get number of channels
        if outChans_pre > 1
            Extract one channel: 1
            tmpOut = selected("Sound")
        else
            Copy: "tmpOut"
            tmpOut = selected("Sound")
        endif
        selectObject: tmpOut
        To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
        specOut = selected("Spectrogram")
    endif

    Erase all
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##PITCH-TRACKED ADDITIVE RESYNTHESIZER##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  Family: " + partialFamStat$
        ... + "  |  Amp: " + ampLawStat$
        ... + "  |  Partials: " + nPartialsStat$
        ... + "  |  Voicing: " + voicingStr$
        ... + "  |  F0: " + f0MinStat$ + "-" + f0MaxStat$ + " Hz (mean " + f0MeanStat$ + ")"

    # ----------------------------------------------------------
    # PANEL A: TRACKED F0 CONTOUR  (left, headline)
    # The analysis input — what drives the additive synthesis.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40

    if nF0Pts > 0
        f0Lo = pitch_floor_Hz
        f0Hi = pitch_ceiling_Hz
        Axes: 0, dur, f0Lo, f0Hi
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, f0Lo, f0Hi

        # Light reference grid at common octaves
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        Dotted line
        octaveLine = 100
        while octaveLine < f0Hi
            if octaveLine > f0Lo
                Draw line: 0, octaveLine, dur, octaveLine
                Font size: 5
                Colour: "{0.55, 0.55, 0.55}"
                Text: 0, "left", octaveLine, "half", "  " + string$(octaveLine)
                Colour: "{0.88, 0.88, 0.92}"
            endif
            octaveLine = octaveLine * 2
        endwhile
        Solid line

        # F0 trace
        Colour: "{0.20, 0.40, 0.70}"
        Line width: 2
        prevValid = 0
        prevT = 0
        prevV = 0
        for iFp from 0 to nF0Pts - 1
            tt = f0t_'iFp'
            vv = f0v_'iFp'
            if vv > 0
                if prevValid = 1
                    Draw line: prevT, prevV, tt, vv
                endif
                prevT = tt
                prevV = vv
                prevValid = 1
            else
                prevValid = 0
            endif
        endfor
        Line width: 1

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "F0 (Hz)"
        Text bottom: "yes", "Time (s)"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(no F0 trace data)"
        Colour: "Black"
        Draw inner box
    endif

    # ----------------------------------------------------------
    # PANEL B: PARTIAL FREQUENCY PLAN  (right, headline)
    # The synthesis spec — min/mean/max ranges per partial.
    # This is the script's most distinctive visual.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40

    if nPartialEntries > 0
        # Find global frequency range
        pfMin = pmin_1
        pfMax = pmax_1
        for iP from 2 to nPartialEntries
            if pmin_'iP' < pfMin
                pfMin = pmin_'iP'
            endif
            if pmax_'iP' > pfMax
                pfMax = pmax_'iP'
            endif
        endfor
        if pfMax <= pfMin
            pfMax = pfMin + 1
        endif

        Axes: 0, nPartialEntries + 1, pfMin * 0.9, pfMax * 1.1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, nPartialEntries + 1, pfMin * 0.9, pfMax * 1.1

        for iP from 1 to nPartialEntries
            Colour: "{0.70, 0.40, 0.20}"
            Line width: 4
            Draw line: iP, pmin_'iP', iP, pmax_'iP'
            Line width: 1
            Paint circle (mm): "{0.20, 0.20, 0.70}", iP, pmean_'iP', 0.8
        endfor

        Colour: "Black"
        Draw inner box
        Font size: 6
        Text left: "yes", "Hz"
        Text bottom: "yes", "Partial index"
    else
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, 0, 1
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        Text: 0.5, "centre", 0.5, "half", "(no partial data)"
        Colour: "Black"
        Draw inner box
    endif

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Tracked F0 contour (analysis input)"
    Text: 6.10, "centre", 7.30, "half", "Partial frequency plan (min/mean/max)"

    # ----------------------------------------------------------
    # PANEL C: ORIGINAL WAVEFORM or SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48

    if show_spectrograms
        selectObject: specOrig
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Original spectrogram"
        Text left: "yes", "Hz"
    else
        selectObject: sound
        Colour: "{0.50, 0.50, 0.50}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Original waveform (" + fixed$(dur, 2) + " s)"
        Text left: "yes", "Amp"
    endif

    # ----------------------------------------------------------
    # PANEL D: SYNTHESIZED WAVEFORM or SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48

    if show_spectrograms
        selectObject: specOut
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Synthesized spectrogram"
        Text left: "yes", "Hz"
        Text bottom: "yes", "Time (s)"
    else
        selectObject: resultSound
        Colour: "{0.20, 0.50, 0.70}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Synthesized waveform (" + durationStat$ + " s)"
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
    endif

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if show_spectrograms
        spectrogramStr$ = "shown"
    else
        spectrogramStr$ = "off"
    endif

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.78, "half",
        ... "##" + partialFamStat$ + " / " + ampLawStat$ + "##"
        ... + "  " + soundName$
        ... + "  |  Partials: " + nPartialsStat$
        ... + "  |  Voicing: " + voicingStr$
        ... + "  |  Env: " + envSourceStr$
        ... + "  |  Stereo: " + stereoStr$

    Text: 0.02, "left", 0.50, "half",
        ... "F0: " + f0MinStat$ + " - " + f0MaxStat$ + " Hz"
        ... + "  |  Mean: " + f0MeanStat$
        ... + "  |  Median: " + f0MedianStat$
        ... + "  |  Voiced: " + voicedPctStat$ + "%"
        ... + "  |  Samples: " + nSamplesStat$ + " @ " + sampleRateStat$ + " Hz"

    Text: 0.02, "left", 0.20, "half",
        ... "Duration: " + fixed$(dur, 2) + "s -> " + durationStat$ + "s"
        ... + "  |  Normalize: " + normModeStat$
        ... + "  |  RMS: " + rmsInStat$ + " -> " + rmsOutStat$
        ... + "  |  Peak: " + peakOutStat$
        ... + "  |  Seed: " + string$(seed)
        ... + "  |  Spectrograms: " + spectrogramStr$

    if warningStat$ <> "?" and warningStat$ <> ""
        Font size: 5
        Colour: "{0.80, 0.20, 0.20}"
        Text: 0.98, "right", 0.03, "half", "Warn: " + warningStat$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"

    # Cleanup spectrogram objects if computed
    if show_spectrograms
        removeObject: specOrig, tmpOrig, specOut, tmpOut
    endif
endif

# ===========================================================================
# Cleanup & summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:        ", soundName$, "_ptadd"
appendInfoLine: "Family:        ", partialFamStat$
appendInfoLine: "Amplitude law: ", ampLawStat$
appendInfoLine: "Partials:      ", nPartialsStat$
appendInfoLine: "F0 mean:       ", f0MeanStat$, " Hz"
appendInfoLine: "Voiced:        ", voicedPctStat$, "%"
appendInfoLine: "Duration:      ", fixed$(dur, 2), " s -> ", durationStat$, " s"
appendInfoLine: "Normalize:     ", normModeStat$
appendInfoLine: "RMS in/out:    ", rmsInStat$, " / ", rmsOutStat$
appendInfoLine: "Peak output:   ", peakOutStat$

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: "WARNING:       ", warningStat$
endif

selectObject: resultSound
if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================
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
