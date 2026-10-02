# ============================================================
# Praat AudioTools - IRCAM_SuperVP_Transform.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   IRCAM SuperVP bridge. Praat analyses the Sound (F0 with an automatic
#   or chosen pitch range, intensity), a Python engine turns that analysis
#   into SuperVP control curves (BPFs), runs SuperVP, and reports exactly
#   what it sent. The figure shows the analysis, the control curves that
#   reached SuperVP, and the result — the process, not just before/after.
#
#   Two-stage dialog that stays open between runs:
#     1. common settings (mode, quality profile, pitch range, output)
#     2. only the chosen mode's parameters  ->  Apply / < Back / Close
#
#   Modes: Age, Gender, Age + gender, Flatten pitch, Vibrato, Harmoniser,
#   Formant shift (constant / ramp / follow F0 / follow intensity /
#   wander), Time stretch (constant / voiced / unvoiced / ramp), Tremolo
#   (amplitude or spectral envelope, intensity-driven depth),
#   Breathiness (whisper blend), Cross synthesis (2 Sounds), Dynamic
#   gate, Diagnostics.
#
#   Quality profiles: Standard (v2 behaviour), General, Voice
#   (monophonic), Percussive, Smeared. New SuperVP flags are only used if
#   the installed SuperVP lists them in its own help; dropped flags are
#   reported. Run "Diagnostics" once to see what your SuperVP supports.
#
# Changelog v3.2.2:
#   - Spectral denoise is active: select a noise-only segment; SuperVP learns
#     an M1 SDIF profile (-avseg/-OM1) and applies -Fsub in a second pass.
#     Controls expose reduction, noise-estimate strength, relaxation,
#     amplitude/energy subtraction and deterministic-noise handling.
#
# Changelog v3.2.1:
#   - Engine 3.2.1: full help sections for the pending modes (details
#     blocks were cut off at their first blank line).
#
# Changelog v3.2.4:
#   - Spectral phase diffusion is active: documented SuperVP -rnd_force /
#     -rnd_voi / -rnd_stval / -rnd_ff, with optional -shape 1 + -rnd_sin
#     for sinusoidal-component separation.
#
# Changelog v3.2:
#   - Cross: simple control renamed "Spectral cross coupling" (it is not a
#     linear mix: low = S1 amplitude with S2 spectral structure, high = the
#     reverse). The four SuperVP weights are unchanged.
#   - Tremolo: new type Native SuperVP (-gtremolo, sine / triangle /
#     square / sawtooth), depth over time from Praat intensity.
#   - New modes: Organic vibrato (-trmdlp), Frequency shift (Hz, -Ffshift).
#   - Spectral denoise and Spectral phase diffusion are in the menu but do
#     not run yet: Apply prints the matching section of your SuperVP help
#     so the parameter format can be confirmed. No guessed command is sent.
#   - Diagnostics lists every v3.2 feature as supported / not supported.
#   - Mode handling by name instead of menu position.
#
# Changelog v3.1.1:
#   - Auto pitch range: first pass widened from 50-1000 Hz to 30-3000 Hz
#     (same span as the Wide preset).
#   - Engine 3.1.1: -F0/-Mauto now reach every mode when the profile
#     reports an F0-adaptive window.
#
# Changelog v3.1:
#   - Engine 3.1: adaptive true envelope from Praat F0 (-F0 + -Afft
#     +<maxF0>Hz) in General/Voice; -envpl 1 in Voice. Both checked
#     against the installed SuperVP help, dropped with a report otherwise.
#
# Changelog v3.0.1:
#   - Parameters are passed to Python in a key=value file instead of on
#     the command line: on Windows an empty value (no second Sound) or a
#     value with a space (pitch-range label) broke the argument list and
#     Python exited with status 2 before writing any log.
#
# Changelog v3.0:
#   - Engine semantics fixed (see supervp_transform.py): De-noise renamed
#     Dynamic gate (it is an output gain envelope); tremolo depth now
#     follows intensity over time; breathiness rebuilt as a whispered copy
#     (voice envelope on noise via -Gcross) blended with the original.
#   - Quality profiles with help-checked flags; Diagnostics mode.
#   - Pitch range: Auto (two-pass, quantile-based) / Speech / Singing /
#     Instrument / Wide / Custom, replacing the fixed 75-600 Hz.
#   - Analysis BPF times are now relative to the Sound's start (a Sound
#     not starting at 0 s previously sent shifted curves to SuperVP).
#   - New controls: flatten amount, voiced-only vibrato with onset fade,
#     formant shapes, stretch shapes, four cross weights, source-2 fit.
#   - Two-stage dialog: only the chosen mode's parameters are shown.
#   - Figure rebuilt: input spectrogram, analysis tracks (the ones the
#     mode uses highlighted), every control curve sent to SuperVP with
#     its unit, result spectrogram, waveforms, and the actual commands.
#   - Dry run draws the analysis and control curves without rendering.
#   - Session-tagged temporary files; SuperVP path remembered between
#     sessions; Praat 7 trust request; no goto.
#   - Version unified at 3.0 for both files (website page showed 2.5).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: SuperVP Transform.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Requires:
#   Praat 6.3+; Python 3 (numpy + soundfile for Harmoniser, Breathiness
#   and Cross loop/pad); IRCAM SuperVP command-line executable.
# ============================================================

version$ = "3.2.3"

# ---- INPUT CHECK ----
nSounds = numberOfSelected("Sound")
if nSounds < 1 or nSounds > 2
    exitScript: "Please select one Sound (or two for Cross synthesis)."
endif
sound1 = selected("Sound", 1)
soundName1$ = selected$("Sound", 1)
sound2 = 0
soundName2$ = ""
if nSounds = 2
    sound2 = selected("Sound", 2)
    soundName2$ = selected$("Sound", 2)
endif

# ---- PRAAT 7 TRUST ----
if praatVersion >= 7000
    trustOK = askForTrust()
    if not trustOK
        exitScript: "SuperVP Transform needs permission to write temporary files and run Python/SuperVP."
    endif
endif

# ---- PATHS ----
pluginDir$ = replace$(preferencesDirectory$, "\", "/", 0) + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/supervp_transform.py"
settingsFile$ = pluginDir$ + "supervp_path.txt"
if not fileReadable(pythonScript$)
    pythonScript$ = replace$(defaultDirectory$, "\", "/", 0) + "/supervp_transform.py"
    settingsFile$ = replace$(preferencesDirectory$, "\", "/", 0) + "/supervp_path.txt"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find supervp_transform.py (expected in " + pluginDir$ + "py/ or next to this script)."
endif

tmpDir$ = replace$(temporaryDirectory$, "\", "/", 0) + "/"
sessionTag$ = replace_regex$(date$(), "[^0-9]", "", 0) + "_" + string$(randomInteger(100000, 999999))
tmp$ = tmpDir$ + "svp_" + sessionTag$ + "_"
inputWav1$ = tmp$ + "input1.wav"
inputWav2$ = tmp$ + "input2.wav"
f0File$ = tmp$ + "f0.bpf"
intensityFile$ = tmp$ + "intensity.bpf"
resultWav$ = tmp$ + "result.wav"
doneFile$ = tmp$ + "done.txt"
logFile$ = tmp$ + "log.txt"
manifestFile$ = tmp$ + "manifest.txt"
paramFile$ = tmp$ + "params.txt"
diagFile$ = tmpDir$ + "SuperVP_diagnostics.txt"

# ---- SUPERVP PATH (remembered) ----
v_exe$ = ""
if fileReadable(settingsFile$)
    v_exe$ = readFile$(settingsFile$)
    v_exe$ = replace_regex$(v_exe$, "[\r\n]+", "", 0)
endif
if v_exe$ = "" or not fileReadable(v_exe$)
    home$ = replace$(homeDirectory$, "\", "/", 0)
    if windows
        c1$ = home$ + "/SuperVP/bin/supervp.exe"
        c2$ = "C:/Program Files/IRCAM/SuperVP/bin/supervp.exe"
        c3$ = "C:/Users/User/SuperVP/bin/supervp.exe"
    else
        c1$ = home$ + "/SuperVP/bin/supervp"
        c2$ = "/usr/local/bin/supervp"
        c3$ = "/Applications/SuperVP/bin/supervp"
    endif
    if v_exe$ = ""
        v_exe$ = c1$
    endif
    for k from 1 to 3
        if fileReadable(c'k'$)
            v_exe$ = c'k'$
        endif
    endfor
endif

# ---- PYTHON ----
probeOK$ = tmp$ + "probe.ok"
if windows
    nCand = 3
    cand1$ = "python"
    cand2$ = "py"
    cand3$ = "python3"
else
    nCand = 2
    cand1$ = "python3"
    cand2$ = "python"
endif
pythonCmd$ = ""
iCand = 1
while iCand <= nCand and pythonCmd$ = ""
    tryCmd$ = cand'iCand'$
    probePy$ = tmp$ + "probe.py"
    writeFileLine: probePy$, "import sys"
    appendFileLine: probePy$, "open(sys.argv[1], ""w"").write(""ok"")"
    runSystem_nocheck: tryCmd$ + " """ + probePy$ + """ """ + probeOK$ + """"
    deleteFile: probePy$
    if fileReadable(probeOK$)
        pythonCmd$ = tryCmd$
        deleteFile: probeOK$
    endif
    iCand = iCand + 1
endwhile
if pythonCmd$ = ""
    exitScript: "Cannot find a working Python 3 (tried python / py / python3)."
endif

# ============================================================
# DEFAULTS (kept between Apply runs)
# ============================================================
v_mode = 1
v_profile = 1
v_range = 1
v_customFloor = 75
v_customCeiling = 600
v_dry = 0
v_keep = 0
v_draw = 1
v_play = 1
v_ageYears = 20
v_genderDir = 1
v_genderAmount = 3
v_genderReinforce = 1
v_targetF0 = 0
v_flattenAmount = 1
v_vibRate = 5.5
v_vibDepth = 50
v_vibVoiced = 1
v_vibFade = 0.25
v_harmInterval = 700
v_harmMix = 0.3
v_fmShape = 1
v_fmShift = 200
v_fmEnd = -200
v_fmDepth = 300
v_fmWander = 1
v_fmSeed = 1
v_stFactor = 1.5
v_stShape = 1
v_trType = 1
v_trMap = 2
v_trRate = 5
v_trAmpDepth = 0.6
v_trEnvDepth = 30
v_trSmooth = 50
v_brAmount = 0.4
v_brSeed = 1
v_crControl = 1
v_crMix = 0.5
v_crX = 1
v_crx = 0
v_crY = 0
v_cry = 1
v_crFit = 1
v_trWave = 1
v_ovRateMin = 4.5
v_ovRateMax = 6.5
v_ovDepthMin = 20
v_ovDepthMax = 60
v_ovInterval = 0.4
v_fsShape = 1
v_fsHz = -50
v_fsEnd = 50
v_fsDepth = 100
v_fsWander = 0.5
v_fsSeed = 1
v_gtThresh = 30
v_gtSmooth = 40
v_dnStart = 0
v_dnEnd = 0.25
v_dnBeta = 20
v_dnSfac = 1
v_dnRelax = 30
v_dnGamma = 1
v_dnDet = 0
v_pdSin = 0
v_pdVoi = 0.15
v_pdStval = 0.30
v_pdFF = 18
v_pdShape = 0
prevResult = 0
stage = 1

# ============================================================
# MAIN LOOP
# ============================================================
repeat
    if stage = 1
        beginPause: "SuperVP Transform v" + version$ + " — " + soundName1$
            sentence: "SuperVP executable", v_exe$
            optionMenu: "Mode", v_mode
                option: "Voice age"
                option: "Gender"
                option: "Age + gender"
                option: "Flatten pitch"
                option: "Vibrato"
                option: "Organic vibrato (randomised)"
                option: "Harmoniser"
                option: "Formant shift"
                option: "Time stretch"
                option: "Tremolo"
                option: "Breathiness"
                option: "Spectral cross synthesis (2 Sounds)"
                option: "Dynamic gate (time-domain gain)"
                option: "Spectral denoise"
                option: "Spectral phase diffusion"
                option: "Frequency shift (Hz)"
                option: "Diagnostics (what my SuperVP supports)"
            optionMenu: "Quality profile", v_profile
                option: "Standard (v2 behaviour)"
                option: "General"
                option: "Voice (monophonic speech/singing)"
                option: "Percussive"
                option: "Smeared (long window)"
            optionMenu: "Pitch range", v_range
                option: "Auto (two-pass)"
                option: "Speech 75-500 Hz"
                option: "Singing 80-1000 Hz"
                option: "Instrument 40-2000 Hz"
                option: "Wide 30-3000 Hz"
                option: "Custom"
            positive: "Custom floor (Hz)", string$(v_customFloor)
            positive: "Custom ceiling (Hz)", string$(v_customCeiling)
            boolean: "Dry run (curves + commands only)", v_dry
            boolean: "Keep previous results", v_keep
            boolean: "Draw visualisation", v_draw
            boolean: "Play result", v_play
        clicked = endPause: "Close", "Next >", 2, 1
        v_exe$ = superVP_executable$
        v_mode = mode
        v_profile = quality_profile
        v_range = pitch_range
        v_customFloor = custom_floor
        v_customCeiling = custom_ceiling
        v_dry = dry_run
        v_keep = keep_previous_results
        v_draw = draw_visualisation
        v_play = play_result
        if clicked = 1
            exitScript: "SuperVP Transform closed."
        endif
        if v_customFloor >= v_customCeiling
            v_customCeiling = v_customFloor * 4
        endif
        @rememberExe
        @modeName: v_mode
        if modeName.s$ = "diagnostics"
            @runDiagnostics
        else
            stage = 2
        endif
    else
        @modeDialog
        if clicked = 1
            exitScript: "SuperVP Transform closed."
        elsif clicked = 2
            stage = 1
        else
            @applyOnce
        endif
    endif
until 0

# ============================================================
# PROCEDURES
# ============================================================

procedure rememberExe
    if fileReadable(v_exe$)
        writeFileLine: settingsFile$, v_exe$
    endif
endproc

procedure modeName: .m
    # menu position -> engine mode name (the only place that knows the order)
    .s$ = "age"
    if .m = 2
        .s$ = "gender"
    elsif .m = 3
        .s$ = "age_gender"
    elsif .m = 4
        .s$ = "flatten_pitch"
    elsif .m = 5
        .s$ = "vibrato"
    elsif .m = 6
        .s$ = "organic_vibrato"
    elsif .m = 7
        .s$ = "harmoniser"
    elsif .m = 8
        .s$ = "formant_shift"
    elsif .m = 9
        .s$ = "time_stretch"
    elsif .m = 10
        .s$ = "tremolo"
    elsif .m = 11
        .s$ = "breathiness"
    elsif .m = 12
        .s$ = "cross"
    elsif .m = 13
        .s$ = "gate"
    elsif .m = 14
        .s$ = "spectral_denoise"
    elsif .m = 15
        .s$ = "phase_diffusion"
    elsif .m = 16
        .s$ = "freq_shift"
    elsif .m = 17
        .s$ = "diagnostics"
    endif
endproc

procedure modeDialog
    @modeName: v_mode
    m$ = modeName.s$
    beginPause: "SuperVP — " + replace$(modeName.s$, "_", " ", 0) + " parameters"
    if m$ = "age" or m$ = "age_gender"
        comment: "Age (SuperVP -age): + older, - younger"
        integer: "Age years", string$(v_ageYears)
    endif
    if m$ = "gender" or m$ = "age_gender"
        comment: "Gender (SuperVP -female / -male, amount 1-5)"
        optionMenu: "Gender direction", v_genderDir
            option: "To female"
            option: "To male"
        natural: "Gender amount", string$(v_genderAmount)
        boolean: "Formant reinforcement", v_genderReinforce
    endif
    if m$ = "flatten_pitch"
        comment: "Transposition toward a target F0 (-transke, envelope preserved)"
        real: "Target pitch (Hz)", string$(v_targetF0)
        comment: "0 = median F0.  Amount: 1 flat, 0.5 half range, 0 unchanged, <0 exaggerated"
        real: "Flatten amount", string$(v_flattenAmount)
    endif
    if m$ = "vibrato"
        positive: "Rate (Hz)", string$(v_vibRate)
        real: "Depth (cents)", string$(v_vibDepth)
        boolean: "Voiced only", v_vibVoiced
        real: "Onset fade (s)", string$(v_vibFade)
    endif
    if m$ = "harmoniser"
        real: "Interval (cents)", string$(v_harmInterval)
        real: "Harmony level (0-1)", string$(v_harmMix)
    endif
    if m$ = "formant_shift"
        comment: "Spectral-envelope shift (-transenv); shapes other than Constant send a BPF"
        optionMenu: "Shape", v_fmShape
            option: "Constant"
            option: "Ramp"
            option: "Follow F0"
            option: "Follow intensity"
            option: "Wander"
        real: "Shift (cents)", string$(v_fmShift)
        real: "Ramp end (cents)", string$(v_fmEnd)
        comment: "Depth: cents per F0 octave (Follow F0), or +/- range (Follow intensity, Wander)"
        real: "Modulation depth (cents)", string$(v_fmDepth)
        positive: "Wander rate (Hz)", string$(v_fmWander)
        integer: "Seed", string$(v_fmSeed)
    endif
    if m$ = "time_stretch"
        positive: "Stretch factor", string$(v_stFactor)
        optionMenu: "Stretch shape", v_stShape
            option: "Constant"
            option: "Voiced only (keep consonants/attacks)"
            option: "Unvoiced only"
            option: "Ramp (1 to factor)"
    endif
    if m$ = "tremolo"
        optionMenu: "Tremolo type", v_trType
            option: "Amplitude (gain BPF)"
            option: "Spectral envelope (BPF)"
            option: "Spectral envelope, constant (-trmdle)"
            option: "Native SuperVP (-gtremolo)"
        optionMenu: "Native waveform", v_trWave
            option: "Sine"
            option: "Triangle"
            option: "Square"
            option: "Sawtooth"
        optionMenu: "Intensity mapping", v_trMap
            option: "None (constant depth)"
            option: "Direct (louder = deeper)"
            option: "Inverse (softer = deeper)"
            option: "Exaggerated"
            option: "Quantised (4 levels)"
        positive: "Rate (Hz)", string$(v_trRate)
        real: "Amplitude depth (0-1)", string$(v_trAmpDepth)
        comment: "Native SuperVP: Amplitude depth = base depth; Rate is set by SuperVP, not by this form"
        real: "Envelope depth (cents)", string$(v_trEnvDepth)
        real: "Smoothing (ms)", string$(v_trSmooth)
    endif
    if m$ = "breathiness"
        comment: "Whispered copy (voice envelope on noise, -Gcross) blended in"
        real: "Amount (0-1)", string$(v_brAmount)
        integer: "Seed", string$(v_brSeed)
    endif
    if m$ = "cross"
        comment: "Source 1 = first selected, source 2 = second selected"
        optionMenu: "Control", v_crControl
            option: "Simple (spectral cross-coupling)"
            option: "Advanced (four weights)"
        comment: "Coupling: low = amplitude of S1 with spectral structure of S2; high = the reverse"
        real: "Spectral cross coupling (0-1)", string$(v_crMix)
        comment: "Advanced: -X / -x amplitude, -Y / -y frequency"
        real: "Amplitude from source 1", string$(v_crX)
        real: "Amplitude from source 2", string$(v_crx)
        real: "Frequency from source 1", string$(v_crY)
        real: "Frequency from source 2", string$(v_cry)
        optionMenu: "Fit source 2", v_crFit
            option: "As is"
            option: "Loop to source 1 length"
            option: "Pad with silence"
    endif
    if m$ = "gate"
        comment: "Output gain envelope from intensity (-ggain). Not spectral de-noising."
        positive: "Threshold below peak (dB)", string$(v_gtThresh)
        real: "Smoothing (ms)", string$(v_gtSmooth)
    endif
    if m$ = "organic_vibrato"
        comment: "SuperVP -trmdlp: rate and depth re-drawn at random within the ranges"
        positive: "Rate min (Hz)", string$(v_ovRateMin)
        positive: "Rate max (Hz)", string$(v_ovRateMax)
        real: "Depth min", string$(v_ovDepthMin)
        real: "Depth max", string$(v_ovDepthMax)
        positive: "New values every (s)", string$(v_ovInterval)
    endif
    if m$ = "freq_shift"
        comment: "True frequency shift in Hz (every partial moves by the same Hz; not transposition)"
        optionMenu: "Shift shape", v_fsShape
            option: "Constant"
            option: "Ramp"
            option: "Follow intensity"
            option: "Inverse intensity"
            option: "Wander"
        real: "Shift (Hz)", string$(v_fsHz)
        real: "Ramp end (Hz)", string$(v_fsEnd)
        real: "Modulation depth (Hz)", string$(v_fsDepth)
        positive: "Wander rate (Hz)", string$(v_fsWander)
        integer: "Seed", string$(v_fsSeed)
    endif
    if m$ = "spectral_denoise"
        comment: "Two-pass spectral subtraction: choose a noise-only region to learn (-avseg/-OM1), then -Fsub."
        real: "Noise sample start (s)", string$(v_dnStart)
        positive: "Noise sample end (s)", string$(v_dnEnd)
        positive: "Maximum reduction (dB)", string$(v_dnBeta)
        real: "Noise estimate std factor", string$(v_dnSfac)
        real: "Relaxation (ms)", string$(v_dnRelax)
        optionMenu: "Subtraction type", v_dnGamma
            option: "Amplitude"
            option: "Energy"
        boolean: "Deterministic noise handling", v_dnDet
    endif
    if m$ = "phase_diffusion"
        comment: "SuperVP phase randomization as an effect (-rnd_force). Levels are fractions of pi (0-1)."
        real: "Sinusoidal randomization (0-1)", string$(v_pdSin)
        real: "Non sinusoidal randomization (0-1)", string$(v_pdVoi)
        real: "Noise randomization at VUF (0-1)", string$(v_pdStval)
        positive: "Full randomization frequency (kHz)", string$(v_pdFF)
        boolean: "Separate sinusoids (-shape 1; mono source)", v_pdShape
        comment: "If separation is off, the sinusoidal value is ignored; the other phase controls still apply."
    endif
    clicked = endPause: "Close", "< Back", "Apply", 3, 1
    if clicked = 3
        if m$ = "age" or m$ = "age_gender"
            v_ageYears = age_years
        endif
        if m$ = "gender" or m$ = "age_gender"
            v_genderDir = gender_direction
            v_genderAmount = max(1, min(5, gender_amount))
            v_genderReinforce = formant_reinforcement
        endif
        if m$ = "flatten_pitch"
            v_targetF0 = target_pitch
            v_flattenAmount = flatten_amount
        endif
        if m$ = "vibrato"
            v_vibRate = rate
            v_vibDepth = depth
            v_vibVoiced = voiced_only
            v_vibFade = max(0, onset_fade)
        endif
        if m$ = "harmoniser"
            v_harmInterval = interval
            v_harmMix = max(0, min(1, harmony_level))
        endif
        if m$ = "formant_shift"
            v_fmShape = shape
            v_fmShift = shift
            v_fmEnd = ramp_end
            v_fmDepth = modulation_depth
            v_fmWander = wander_rate
            v_fmSeed = seed
        endif
        if m$ = "time_stretch"
            v_stFactor = stretch_factor
            v_stShape = stretch_shape
        endif
        if m$ = "tremolo"
            v_trType = tremolo_type
            v_trMap = intensity_mapping
            v_trRate = rate
            v_trAmpDepth = max(0, min(1, amplitude_depth))
            v_trWave = native_waveform
            v_trEnvDepth = envelope_depth
            v_trSmooth = max(0, smoothing)
        endif
        if m$ = "breathiness"
            v_brAmount = max(0, min(1, amount))
            v_brSeed = seed
        endif
        if m$ = "cross"
            v_crControl = control
            v_crMix = max(0, min(1, spectral_cross_coupling))
            v_crX = amplitude_from_source_1
            v_crx = amplitude_from_source_2
            v_crY = frequency_from_source_1
            v_cry = frequency_from_source_2
            v_crFit = fit_source_2
        endif
        if m$ = "gate"
            v_gtThresh = threshold_below_peak
            v_gtSmooth = max(0, smoothing)
        endif
        if m$ = "spectral_denoise"
            v_dnStart = max(0, noise_sample_start)
            v_dnEnd = noise_sample_end
            v_dnBeta = max(0, maximum_reduction)
            v_dnSfac = noise_estimate_std_factor
            v_dnRelax = max(0, relaxation)
            v_dnGamma = subtraction_type
            v_dnDet = deterministic_noise_handling
        endif
        if m$ = "phase_diffusion"
            v_pdSin = max(0, min(1, sinusoidal_randomization))
            v_pdVoi = max(0, min(1, non_sinusoidal_randomization))
            v_pdStval = max(0, min(1, noise_randomization_at_VUF))
            v_pdFF = full_randomization_frequency
            v_pdShape = separate_sinusoids
        endif
        if m$ = "organic_vibrato"
            v_ovRateMin = rate_min
            v_ovRateMax = rate_max
            v_ovDepthMin = depth_min
            v_ovDepthMax = depth_max
            v_ovInterval = new_values_every
        endif
        if m$ = "freq_shift"
            v_fsShape = shift_shape
            v_fsHz = shift
            v_fsEnd = ramp_end
            v_fsDepth = modulation_depth
            v_fsWander = wander_rate
            v_fsSeed = seed
        endif
    endif
endproc

procedure cleanTemp
    if fileReadable(paramFile$)
        deleteFile: paramFile$
    endif
    for .k from 1 to 8
        if .k = 1
            .f$ = inputWav1$
        elsif .k = 2
            .f$ = inputWav2$
        elsif .k = 3
            .f$ = f0File$
        elsif .k = 4
            .f$ = intensityFile$
        elsif .k = 5
            .f$ = resultWav$
        elsif .k = 6
            .f$ = doneFile$
        elsif .k = 7
            .f$ = manifestFile$
        else
            .f$ = logFile$
        endif
        if fileReadable(.f$)
            deleteFile: .f$
        endif
    endfor
    # control curves written by the engine
    .lst = Create Strings as file list: "svpctrl", tmp$ + "ctrl_*.bpf"
    .n = Get number of strings
    for .i to .n
        selectObject: .lst
        .nm$ = Get string: .i
        deleteFile: tmpDir$ + .nm$
    endfor
    removeObject: .lst
endproc

procedure runDiagnostics
    if not fileReadable(v_exe$)
        writeInfoLine: "SuperVP executable not found: ", v_exe$
    else
        @cleanTemp
        writeFileLine: f0File$, "0 0"
        writeFileLine: intensityFile$, "0 0"
        writeFileLine: paramFile$, "input_wav1=" + inputWav1$
        appendFileLine: paramFile$, "f0_file=" + f0File$
        appendFileLine: paramFile$, "intensity_file=" + intensityFile$
        appendFileLine: paramFile$, "done_file=" + doneFile$
        appendFileLine: paramFile$, "supervp_exe=" + v_exe$
        appendFileLine: paramFile$, "mode=diagnostics"
        appendFileLine: paramFile$, "tmp_prefix=" + tmp$
        appendFileLine: paramFile$, "manifest=" + manifestFile$
        appendFileLine: paramFile$, "diag_file=" + diagFile$
        runSubprocess: pythonCmd$, pythonScript$, paramFile$
        writeInfoLine: "=== SuperVP Transform v", version$, " — Diagnostics ==="
        appendInfoLine: "SuperVP: ", v_exe$
        if fileReadable(manifestFile$)
            .m$ = readFile$(manifestFile$)
            appendInfoLine: ""
            appendInfoLine: "Quality flags (used only if listed in the help of your SuperVP):"
            .rest$ = .m$
            while index(.rest$, newline$) > 0
                .ln$ = left$(.rest$, index(.rest$, newline$) - 1)
                .rest$ = mid$(.rest$, index(.rest$, newline$) + 1, length(.rest$))
                if left$(.ln$, 4) = "cap="
                    appendInfoLine: "  ", replace$(mid$(.ln$, 5, length(.ln$)), "|", "   ", 1)
                elsif left$(.ln$, 8) = "feature="
                    appendInfoLine: "  ", replace$(mid$(.ln$, 9, length(.ln$)), "|", ":  ", 1)
                elsif left$(.ln$, 6) = "scout="
                    appendInfoLine: "  [scouted] ", replace$(mid$(.ln$, 7, length(.ln$)), "|", "   ", 1)
                endif
            endwhile
            appendInfoLine: ""
            appendInfoLine: "Full help text, plus the help sections for the v3.2 features, saved to:"
            appendInfoLine: "  ", diagFile$
            appendInfoLine: "Spectral denoise and spectral phase diffusion are active in this build."
        else
            appendInfoLine: "Diagnostics failed."
            if fileReadable(logFile$)
                appendInfoLine: readFile$(logFile$)
            endif
        endif
        @cleanTemp
    endif
endproc

procedure resolvePitchRange
    rangeNote$ = ""
    if v_range = 2
        pFloor = 75
        pCeil = 500
    elsif v_range = 3
        pFloor = 80
        pCeil = 1000
    elsif v_range = 4
        pFloor = 40
        pCeil = 2000
    elsif v_range = 5
        pFloor = 30
        pCeil = 3000
    elsif v_range = 6
        pFloor = v_customFloor
        pCeil = v_customCeiling
    else
        # Two-pass (quantile rule): wide first pass, then 0.72*q35 .. 1.9*q65.
        # The first pass covers the same span as the Wide preset, so high
        # instrumental material is not clipped before the quantiles are read.
        selectObject: sound1
        .p0 = To Pitch: 0, 30, min(3000, sr1 / 2 * 0.9)
        .nv = Count voiced frames
        if .nv >= 10
            .q35 = Get quantile: 0, 0, 0.35, "Hertz"
            .q65 = Get quantile: 0, 0, 0.65, "Hertz"
            pFloor = max(30, round(0.72 * .q35))
            pCeil = max(pFloor * 2, round(1.9 * .q65))
            rangeNote$ = "auto from " + string$(.nv) + " voiced frames"
            if pFloor <= 30
                rangeNote$ = rangeNote$ + " — floor reached the 30 Hz search limit (very low or polyphonic material?); consider a preset"
            endif
        else
            pFloor = 30
            pCeil = 3000
            rangeNote$ = "auto: too few voiced frames, using Wide"
        endif
        removeObject: .p0
    endif
    pCeil = min(pCeil, sr1 / 2 * 0.9)
    rangeLabel$ = string$(pFloor) + "-" + string$(round(pCeil)) + " Hz"
endproc

procedure exportAnalysis
    selectObject: sound1
    tmin = Get start time
    tmax = Get end time
    pitchObj = To Pitch: 0, pFloor, pCeil
    nVoiced = Count voiced frames
    nFrames = Get number of frames
    selectObject: sound1
    intObj = To Intensity: max(pFloor, 40), 0, "no"
    .step = 0.01
    .bufF$ = ""
    .bufI$ = ""
    .cnt = 0
    .t = tmin
    while .t <= tmax + .step / 2
        selectObject: pitchObj
        .f = Get value at time: .t, "Hertz", "Linear"
        if .f = undefined
            .f = 0
        endif
        selectObject: intObj
        .d = Get value at time: .t, "Cubic"
        if .d = undefined
            .d = 0
        endif
        .bufF$ = .bufF$ + fixed$(.t - tmin, 4) + " " + fixed$(.f, 3) + newline$
        .bufI$ = .bufI$ + fixed$(.t - tmin, 4) + " " + fixed$(.d, 3) + newline$
        .cnt = .cnt + 1
        if .cnt = 400
            appendFile: f0File$, .bufF$
            appendFile: intensityFile$, .bufI$
            .bufF$ = ""
            .bufI$ = ""
            .cnt = 0
        endif
        .t = .t + .step
    endwhile
    appendFile: f0File$, .bufF$
    appendFile: intensityFile$, .bufI$
endproc

procedure readManifest
    nCtrl = 0
    nCmd = 0
    nDrop = 0
    nNote = 0
    nHelp = 0
    engineError$ = ""
    qualityFlags$ = "(none)"
    expectedRatio = 1
    if fileReadable(manifestFile$)
        .rest$ = readFile$(manifestFile$)
        while index(.rest$, newline$) > 0
            .ln$ = left$(.rest$, index(.rest$, newline$) - 1)
            .rest$ = mid$(.rest$, index(.rest$, newline$) + 1, length(.rest$))
            .eq = index(.ln$, "=")
            if .eq > 0
                .k$ = left$(.ln$, .eq - 1)
                .v$ = mid$(.ln$, .eq + 1, length(.ln$) - .eq)
                if .k$ = "ctrl"
                    nCtrl = nCtrl + 1
                    .b1 = index(.v$, "|")
                    ctrlPath'nCtrl'$ = left$(.v$, .b1 - 1)
                    .r$ = mid$(.v$, .b1 + 1, length(.v$))
                    .b2 = index(.r$, "|")
                    ctrlLabel'nCtrl'$ = left$(.r$, .b2 - 1)
                    ctrlUnit'nCtrl'$ = mid$(.r$, .b2 + 1, length(.r$))
                elsif .k$ = "cmd"
                    nCmd = nCmd + 1
                    cmd'nCmd'$ = .v$
                elsif .k$ = "dropped"
                    nDrop = nDrop + 1
                    drop'nDrop'$ = replace$(.v$, "|", ": ", 1)
                elsif .k$ = "note"
                    nNote = nNote + 1
                    note'nNote'$ = .v$
                elsif .k$ = "error"
                    engineError$ = .v$
                elsif .k$ = "helpsec"
                    nHelp = nHelp + 1
                    helpSec'nHelp'$ = replace$(.v$, " || ", newline$, 0)
                elsif .k$ = "quality_flags"
                    qualityFlags$ = .v$
                elsif .k$ = "expected_ratio"
                    expectedRatio = number(.v$)
                endif
            endif
        endwhile
    endif
endproc

procedure applyOnce
    @modeName: v_mode
    mode$ = modeName.s$
    @profileName
    if not fileReadable(v_exe$)
        writeInfoLine: "SuperVP executable not found: ", v_exe$
        appendInfoLine: "Correct the path (< Back) and Apply again."
    elsif mode$ = "cross" and nSounds < 2
        writeInfoLine: "Cross synthesis needs two selected Sounds."
    else
        @cleanTemp
        if prevResult > 0 and not v_keep
            removeObject: prevResult
        endif
        prevResult = 0
        selectObject: sound1
        dur1 = Get total duration
        sr1 = Get sampling frequency
        Save as WAV file: inputWav1$
        resampleNote$ = ""
        if nSounds = 2
            selectObject: sound2
            .sr2 = Get sampling frequency
            if .sr2 <> sr1
                .rs = Resample: sr1, 50
                Save as WAV file: inputWav2$
                removeObject: .rs
                resampleNote$ = "source 2 resampled " + string$(.sr2) + " -> " + string$(sr1) + " Hz"
            else
                Save as WAV file: inputWav2$
            endif
        endif
        @resolvePitchRange
        @exportAnalysis

        writeInfoLine: "=== SuperVP Transform v", version$, " ==="
        appendInfoLine: "Source:    ", soundName1$, "  (", fixed$(dur1, 2), " s, ", sr1, " Hz)"
        if mode$ = "cross"
            appendInfoLine: "Source 2:  ", soundName2$, "  ", resampleNote$
        endif
        appendInfoLine: "Mode:      ", mode$, "     profile: ", profileName$
        appendInfoLine: "Pitch:     ", rangeLabel$, "  ", rangeNote$, "  (", nVoiced, "/", nFrames, " frames voiced)"
        if v_dry
            appendInfoLine: "DRY RUN — SuperVP will not be executed."
        endif
        appendInfoLine: "Running..."

        @engineArgs
        writeFileLine: paramFile$, "input_wav1=" + inputWav1$
        appendFileLine: paramFile$, "f0_file=" + f0File$
        appendFileLine: paramFile$, "intensity_file=" + intensityFile$
        appendFileLine: paramFile$, "done_file=" + doneFile$
        appendFileLine: paramFile$, "supervp_exe=" + v_exe$
        appendFileLine: paramFile$, "result_wav=" + resultWav$
        appendFileLine: paramFile$, "tmp_prefix=" + tmp$
        appendFileLine: paramFile$, "manifest=" + manifestFile$
        appendFileLine: paramFile$, "mode=" + mode$
        appendFileLine: paramFile$, "profile=" + profileTok$
        appendFileLine: paramFile$, "range_label=" + rangeLabel$
        appendFileLine: paramFile$, "dry_run_flag=" + string$(v_dry)
        appendFileLine: paramFile$, "seed=" + string$(seedArg)
        appendFileLine: paramFile$, "age_val=" + string$(v_ageYears)
        appendFileLine: paramFile$, "gender_dir=" + genderTok$
        appendFileLine: paramFile$, "gender_amount=" + string$(v_genderAmount)
        appendFileLine: paramFile$, "gender_reinforce=" + string$(v_genderReinforce)
        appendFileLine: paramFile$, "target_f0=" + string$(v_targetF0)
        appendFileLine: paramFile$, "flatten_amount=" + string$(v_flattenAmount)
        appendFileLine: paramFile$, "vibrato_freq=" + string$(v_vibRate)
        appendFileLine: paramFile$, "vibrato_depth=" + string$(v_vibDepth)
        appendFileLine: paramFile$, "vibrato_voiced_only=" + string$(v_vibVoiced)
        appendFileLine: paramFile$, "vibrato_fade=" + string$(v_vibFade)
        appendFileLine: paramFile$, "harmoniser_interval=" + string$(v_harmInterval)
        appendFileLine: paramFile$, "harmoniser_mix=" + string$(v_harmMix)
        appendFileLine: paramFile$, "formant_shape=" + fmShapeTok$
        appendFileLine: paramFile$, "formant_shift_cents=" + string$(v_fmShift)
        appendFileLine: paramFile$, "formant_end_cents=" + string$(v_fmEnd)
        appendFileLine: paramFile$, "formant_depth_cents=" + string$(v_fmDepth)
        appendFileLine: paramFile$, "formant_wander_rate=" + string$(v_fmWander)
        appendFileLine: paramFile$, "stretch_factor=" + string$(v_stFactor)
        appendFileLine: paramFile$, "stretch_shape=" + stShapeTok$
        appendFileLine: paramFile$, "tremolo_type=" + trTypeTok$
        appendFileLine: paramFile$, "tremolo_map=" + trMapTok$
        appendFileLine: paramFile$, "tremolo_freq=" + string$(v_trRate)
        appendFileLine: paramFile$, "tremolo_amp_depth=" + string$(v_trAmpDepth)
        appendFileLine: paramFile$, "tremolo_env_depth=" + string$(v_trEnvDepth)
        appendFileLine: paramFile$, "tremolo_smooth_ms=" + string$(v_trSmooth)
        appendFileLine: paramFile$, "tremolo_waveform=" + trWaveTok$
        appendFileLine: paramFile$, "trmdlp_rate_min=" + string$(v_ovRateMin)
        appendFileLine: paramFile$, "trmdlp_rate_max=" + string$(v_ovRateMax)
        appendFileLine: paramFile$, "trmdlp_depth_min=" + string$(v_ovDepthMin)
        appendFileLine: paramFile$, "trmdlp_depth_max=" + string$(v_ovDepthMax)
        appendFileLine: paramFile$, "trmdlp_interval=" + string$(v_ovInterval)
        appendFileLine: paramFile$, "fshift_shape=" + fsShapeTok$
        appendFileLine: paramFile$, "fshift_hz=" + string$(v_fsHz)
        appendFileLine: paramFile$, "fshift_end_hz=" + string$(v_fsEnd)
        appendFileLine: paramFile$, "fshift_depth_hz=" + string$(v_fsDepth)
        appendFileLine: paramFile$, "fshift_wander_rate=" + string$(v_fsWander)
        appendFileLine: paramFile$, "breathiness_amount=" + string$(v_brAmount)
        appendFileLine: paramFile$, "cross_control=" + crControlTok$
        appendFileLine: paramFile$, "cross_mix=" + string$(v_crMix)
        appendFileLine: paramFile$, "cross_X=" + string$(v_crX)
        appendFileLine: paramFile$, "cross_x=" + string$(v_crx)
        appendFileLine: paramFile$, "cross_Y=" + string$(v_crY)
        appendFileLine: paramFile$, "cross_y=" + string$(v_cry)
        appendFileLine: paramFile$, "cross_fit=" + crFitTok$
        appendFileLine: paramFile$, "input_wav2=" + input2Arg$
        appendFileLine: paramFile$, "gate_threshold_db=" + string$(v_gtThresh)
        appendFileLine: paramFile$, "gate_smooth_ms=" + string$(v_gtSmooth)
        appendFileLine: paramFile$, "denoise_noise_start=" + string$(v_dnStart)
        appendFileLine: paramFile$, "denoise_noise_end=" + string$(v_dnEnd)
        appendFileLine: paramFile$, "denoise_avbeta=" + string$(v_dnBeta)
        appendFileLine: paramFile$, "denoise_avsfac=" + string$(v_dnSfac)
        appendFileLine: paramFile$, "denoise_avrelax=" + string$(v_dnRelax)
        appendFileLine: paramFile$, "denoise_avgamma=" + string$(v_dnGamma)
        appendFileLine: paramFile$, "denoise_avdet=" + string$(v_dnDet)
        appendFileLine: paramFile$, "phase_rnd_sin=" + string$(v_pdSin)
        appendFileLine: paramFile$, "phase_rnd_voi=" + string$(v_pdVoi)
        appendFileLine: paramFile$, "phase_rnd_stval=" + string$(v_pdStval)
        appendFileLine: paramFile$, "phase_rnd_ff=" + string$(v_pdFF)
        appendFileLine: paramFile$, "phase_shape=" + string$(v_pdShape)
        runSubprocess: pythonCmd$, pythonScript$, paramFile$

        doneOk = 0
        if fileReadable(doneFile$)
            .st$ = readFile$(doneFile$)
            if left$(.st$, 2) = "ok"
                doneOk = 1
            endif
        endif
        @readManifest
        if not doneOk
            appendInfoLine: ""
            appendInfoLine: "ERROR: ", engineError$
            if nHelp > 0
                appendInfoLine: ""
                appendInfoLine: "=== matching section(s) of your SuperVP help ==="
                for .h to nHelp
                    appendInfoLine: helpSec'.h'$
                    appendInfoLine: ""
                endfor
            endif
            if fileReadable(logFile$)
                appendInfoLine: ""
                appendInfoLine: "=== engine / SuperVP log ==="
                appendInfoLine: readFile$(logFile$)
            endif
            removeObject: pitchObj, intObj
        else
            resultObj = 0
            if not v_dry
                resultObj = Read from file: resultWav$
                Rename: soundName1$ + "_svp_" + mode$
                prevResult = resultObj
                resultDur = Get total duration
                resultPeak = Get absolute extremum: 0, 0, "None"
            endif
            @reportRun
            if v_draw
                @drawFigure
            endif
            removeObject: pitchObj, intObj
            if not v_dry
                selectObject: resultObj
                if v_play
                    Play
                endif
            endif
        endif
        @cleanTemp
        selectObject: sound1
        if nSounds = 2
            plusObject: sound2
        endif
        appendInfoLine: ""
        appendInfoLine: "— adjust parameters and Apply again, < Back for mode/profile, or Close —"
    endif
endproc

procedure profileName
    if v_profile = 1
        profileTok$ = "standard"
        profileName$ = "Standard (v2)"
    elsif v_profile = 2
        profileTok$ = "general"
        profileName$ = "General"
    elsif v_profile = 3
        profileTok$ = "voice"
        profileName$ = "Voice"
    elsif v_profile = 4
        profileTok$ = "percussive"
        profileName$ = "Percussive"
    else
        profileTok$ = "smeared"
        profileName$ = "Smeared"
    endif
endproc

procedure engineArgs
    genderTok$ = "female"
    if v_genderDir = 2
        genderTok$ = "male"
    endif
    if v_fmShape = 1
        fmShapeTok$ = "constant"
    elsif v_fmShape = 2
        fmShapeTok$ = "ramp"
    elsif v_fmShape = 3
        fmShapeTok$ = "follow_f0"
    elsif v_fmShape = 4
        fmShapeTok$ = "follow_intensity"
    else
        fmShapeTok$ = "wander"
    endif
    if v_stShape = 1
        stShapeTok$ = "constant"
    elsif v_stShape = 2
        stShapeTok$ = "voiced"
    elsif v_stShape = 3
        stShapeTok$ = "unvoiced"
    else
        stShapeTok$ = "ramp"
    endif
    if v_trType = 1
        trTypeTok$ = "amplitude"
    elsif v_trType = 2
        trTypeTok$ = "envelope"
    elsif v_trType = 3
        trTypeTok$ = "trmdle"
    else
        trTypeTok$ = "native"
    endif
    if v_trWave = 1
        trWaveTok$ = "sine"
    elsif v_trWave = 2
        trWaveTok$ = "triangle"
    elsif v_trWave = 3
        trWaveTok$ = "square"
    else
        trWaveTok$ = "saw"
    endif
    if v_fsShape = 1
        fsShapeTok$ = "constant"
    elsif v_fsShape = 2
        fsShapeTok$ = "ramp"
    elsif v_fsShape = 3
        fsShapeTok$ = "follow_intensity"
    elsif v_fsShape = 4
        fsShapeTok$ = "inverse_intensity"
    else
        fsShapeTok$ = "wander"
    endif
    if v_trMap = 1
        trMapTok$ = "none"
    elsif v_trMap = 2
        trMapTok$ = "direct"
    elsif v_trMap = 3
        trMapTok$ = "inverse"
    elsif v_trMap = 4
        trMapTok$ = "exaggerated"
    else
        trMapTok$ = "quantised"
    endif
    crControlTok$ = "simple"
    if v_crControl = 2
        crControlTok$ = "advanced"
    endif
    if v_crFit = 1
        crFitTok$ = "as_is"
    elsif v_crFit = 2
        crFitTok$ = "loop"
    else
        crFitTok$ = "pad"
    endif
    input2Arg$ = ""
    if nSounds = 2
        input2Arg$ = inputWav2$
    endif
    seedArg = 1
    if mode$ = "formant_shift"
        seedArg = v_fmSeed
    elsif mode$ = "breathiness"
        seedArg = v_brSeed
    elsif mode$ = "freq_shift"
        seedArg = v_fsSeed
    endif
endproc

procedure reportRun
    appendInfoLine: ""
    appendInfoLine: "--- SuperVP commands (paths shortened) ---"
    for .i to nCmd
        appendInfoLine: "  ", cmd'.i'$
    endfor
    appendInfoLine: "Quality flags: ", qualityFlags$
    if nDrop > 0
        appendInfoLine: "Dropped (not listed in the help of this SuperVP):"
        for .i to nDrop
            appendInfoLine: "  ", drop'.i'$
        endfor
    endif
    if nNote > 0
        appendInfoLine: "Notes:"
        for .i to nNote
            appendInfoLine: "  ", note'.i'$
        endfor
    endif
    appendInfoLine: "Control curves sent: ", nCtrl
    for .i to nCtrl
        appendInfoLine: "  ", ctrlLabel'.i'$, "  [", ctrlUnit'.i'$, "]"
    endfor
    if not v_dry
        appendInfoLine: ""
        appendInfoLine: "Result: ", soundName1$, "_svp_", mode$, "   ", fixed$(resultDur, 3), " s (ratio ",
            ... fixed$(resultDur / dur1, 3), "; expected ", fixed$(expectedRatio, 3), "), peak ", fixed$(resultPeak, 3)
    endif
endproc

# ---------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------
procedure sanitize: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    .out$ = .s$
endproc

procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure ctrlColour: .i
    .rgb$ = "{0.20, 0.40, 0.80}"
    if .i = 2
        .rgb$ = "{0.85, 0.35, 0.15}"
    elsif .i = 3
        .rgb$ = "{0.15, 0.60, 0.35}"
    elsif .i = 4
        .rgb$ = "{0.60, 0.25, 0.70}"
    elsif .i >= 5
        .rgb$ = "{0.45, 0.45, 0.45}"
    endif
endproc

procedure paintSpectrogram: .snd, .y0, .y1, .fmax, .setScale
    # .setScale = 1: measure this Sound's peak and use it as the shared
    # scale; 0: paint with the scale measured earlier (specMaxDb), so the
    # input and result spectrograms are directly comparable.
    selectObject: .snd
    .d = Get total duration
    .mono = Convert to mono
    .spec = To Spectrogram: 0.02, .fmax, max(0.002, .d / 1000), 20, "Gaussian"
    if .setScale
        .mat = To Matrix
        .pmax = Get maximum
        removeObject: .mat
        specMaxDb = 10 * log10(max(.pmax, 1e-30) / 4e-10)
    endif
    selectObject: .spec
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Paint: 0, 0, 0, .fmax, specMaxDb, "no", 50, 6, 0, "no"
    removeObject: .spec, .mono
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    @sanitize: mode$
    modeS$ = sanitize.out$
    usesF0 = 0
    usesInt = 0
    if mode$ = "flatten_pitch" or mode$ = "harmoniser" or (mode$ = "vibrato" and v_vibVoiced) or (mode$ = "formant_shift" and v_fmShape = 3) or (mode$ = "time_stretch" and (v_stShape = 2 or v_stShape = 3))
        usesF0 = 1
    endif
    if (mode$ = "tremolo" and v_trMap > 1) or (mode$ = "formant_shift" and v_fmShape = 4) or mode$ = "gate" or (mode$ = "freq_shift" and (v_fsShape = 3 or v_fsShape = 4))
        usesInt = 1
    endif
    fmaxSpec = min(8000, sr1 / 2)

    # geometry (inches)
    t0 = 0.10
    t1 = 0.60
    a0 = 0.90
    a1 = 2.25
    b0 = 2.55
    b1 = 3.45
    c0 = 3.75
    c1 = 5.35
    d0 = 5.95
    d1 = 7.30
    e0 = 7.60
    e1 = 8.50
    s0 = 9.05
    s1 = 10.10
    canvasH = 10.20

    # ---- title ----
    Font size: 13
    Select inner viewport: 0.6, 7.7, t0, t1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##SuperVP Transform — " + modeS$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, t0, t1
    Axes: 0, 1, 0, 1
    @sanitize: soundName1$
    .sub$ = sanitize.out$ + "   |   profile " + profileName$ + "   |   pitch range " + rangeLabel$
    if v_dry
        .sub$ = .sub$ + "   |   DRY RUN"
    endif
    Colour: "{0.35, 0.35, 0.42}"
    Text: 0.5, "centre", 0.18, "half", .sub$

    # ---- A: input spectrogram ----
    Font size: 7
    @paintSpectrogram: sound1, a0, a1, fmaxSpec, 1
    Select inner viewport: 0.6, 7.7, a0, a1
    Axes: 0, dur1, 0, fmaxSpec
    Colour: "Black"
    Text top: "no", "##Input## — spectrogram 0-" + string$(fmaxSpec) + " Hz"
    Select inner viewport: 0.6, 7.7, a0, a1
    Axes: 0, dur1, 0, fmaxSpec
    Draw inner box
    @niceStep: dur1, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @niceStep: fmaxSpec, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: a0, a1, "Freq (Hz)"

    # ---- B: analysis tracks (F0 upper half, intensity lower half) ----
    #      Cross synthesis reads no analysis track: show source 2 instead.
    if mode$ = "cross"
        @drawSource2Panel
    else
        @drawAnalysisPanel
    endif

    # ---- C: control curves sent to SuperVP ----
    @drawControlPanel
    @drawResultPanels
    @drawSummary
endproc

procedure drawSource2Panel
    selectObject: sound2
    .d2 = Get total duration
    @paintSpectrogram: sound2, b0, b1, fmaxSpec, 0
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, .d2, 0, fmaxSpec
    Colour: "Black"
    @sanitize: soundName2$
    .fitTxt$ = "as is"
    if v_crFit = 2
        .fitTxt$ = "looped to source 1 length"
    elsif v_crFit = 3
        .fitTxt$ = "padded to source 1 length"
    endif
    Text top: "no", "##Source 2## — " + sanitize.out$ + " (" + fixed$(.d2, 2) + " s, own time axis; " + .fitTxt$ + "), input dB scale"
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, .d2, 0, fmaxSpec
    Draw inner box
    @niceStep: fmaxSpec, 2
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: b0, b1, "Source 2"
endproc

procedure drawAnalysisPanel
    bm = (b0 + b1) / 2
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, 1, 0, 1
    # F0
    .fLo = pFloor * 0.8
    .fHi = pCeil * 1.05
    if usesF0
        .fCol$ = "{0.75, 0.25, 0.25}"
    else
        .fCol$ = "{0.70, 0.62, 0.62}"
    endif
    Select inner viewport: 0.6, 7.7, b0, bm
    Axes: 0, dur1, .fLo, .fHi
    Colour: "{0.70, 0.70, 0.74}"
    Dotted line
    Draw line: 0, pFloor, dur1, pFloor
    Draw line: 0, pCeil, dur1, pCeil
    Solid line
    selectObject: pitchObj
    Colour: .fCol$
    Line width: 1.5
    Draw: tmin, tmax, .fLo, .fHi, "no"
    Line width: 1
    Font size: 6
    Select inner viewport: 0.6, 7.7, b0, bm
    Axes: 0, dur1, .fLo, .fHi
    Colour: "{0.45, 0.45, 0.50}"
    Text: dur1, "right", pFloor, "bottom", string$(pFloor) + " Hz"
    Text: dur1, "right", pCeil, "top", string$(round(pCeil)) + " Hz"
    Font size: 7
    # Intensity
    selectObject: intObj
    .iMax = Get maximum: 0, 0, "Parabolic"
    .iMin = .iMax - 60
    if usesInt
        .iCol$ = "{0.20, 0.40, 0.80}"
    else
        .iCol$ = "{0.62, 0.66, 0.74}"
    endif
    Select inner viewport: 0.6, 7.7, bm, b1
    Axes: tmin, tmax, .iMin, .iMax
    Colour: .iCol$
    Line width: 1.5
    Draw: tmin, tmax, .iMin, .iMax, "no"
    Line width: 1
    Font size: 6
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, 1, 0, 1
    Colour: .fCol$
    .tagF$ = "F0 (Praat, " + rangeLabel$ + ")"
    if usesF0
        .tagF$ = "##" + .tagF$ + " — used##"
    endif
    Text: 0.005, "left", 0.92, "half", .tagF$
    Colour: .iCol$
    .tagI$ = "Intensity (dB, top 60 dB)"
    if usesInt
        .tagI$ = "##" + .tagI$ + " — used##"
    endif
    Text: 0.005, "left", 0.42, "half", .tagI$
    Font size: 7
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, 1, 0, 1
    Colour: "{0.85, 0.85, 0.88}"
    Draw line: 0, 0.5, 1, 0.5
    Colour: "Black"
    Text top: "no", "##Praat analysis## — what the engine reads (dotted: pitch floor / ceiling)"
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, dur1, 0, 1
    Draw inner box
    @niceStep: dur1, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @railLabel: b0, b1, "Analysis"
endproc

procedure drawControlPanel
    Select inner viewport: 0.6, 7.7, c0, c1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, 1, 0, 1
    nShow = min(nCtrl, 4)
    if nShow = 0
        Font size: 7
        Select inner viewport: 0.6, 7.7, c0, c1
        Axes: 0, 1, 0, 1
        Colour: "{0.40, 0.40, 0.40}"
        Text: 0.5, "centre", 0.5, "half", "No control curves"
    endif
    for iC to nShow
        lane0 = c0 + (iC - 1) * (c1 - c0) / nShow
        lane1 = c0 + iC * (c1 - c0) / nShow
        .mx = Read Matrix from raw text file: ctrlPath'iC'$
        .nr = Get number of rows
        .vMin = Get value in cell: 1, 2
        .vMax = .vMin
        for .r to .nr
            .v = Get value in cell: .r, 2
            .vMin = min(.vMin, .v)
            .vMax = max(.vMax, .v)
        endfor
        .isConst = (.vMax - .vMin) < 1e-9
        .pad = max((.vMax - .vMin) * 0.12, 1e-6)
        if .isConst
            .pad = max(abs(.vMax) * 0.5, 1)
        endif
        .y0 = .vMin - .pad
        .y1 = .vMax + .pad * 3
        .stride = max(1, floor(.nr / 3000))
        @ctrlColour: iC
        Select inner viewport: 0.6, 7.7, lane0, lane1
        Axes: 0, dur1, .y0, .y1
        if .y0 < 0 and .y1 > 0
            Colour: "{0.82, 0.82, 0.86}"
            Draw line: 0, 0, dur1, 0
        endif
        Colour: ctrlColour.rgb$
        Line width: 1.5
        .xa = Get value in cell: 1, 1
        .ya = Get value in cell: 1, 2
        .r = 1 + .stride
        while .r <= .nr
            .xb = Get value in cell: .r, 1
            .yb = Get value in cell: .r, 2
            Draw line: .xa, .ya, .xb, .yb
            .xa = .xb
            .ya = .yb
            .r = .r + .stride
        endwhile
        if .xa < dur1
            Draw line: .xa, .ya, dur1, .ya
        endif
        Line width: 1
        removeObject: .mx
        Font size: 6
        Select inner viewport: 0.6, 7.7, lane0, lane1
        Axes: 0, 1, 0, 1
        Colour: ctrlColour.rgb$
        @sanitize: ctrlLabel'iC'$ + "  [" + ctrlUnit'iC'$ + "]"
        Text: 0.005, "left", 0.86, "half", "##" + sanitize.out$ + "##"
        Colour: "{0.30, 0.30, 0.34}"
        if .isConst
            Text: 0.995, "right", 0.86, "half", "constant " + fixed$(.vMax, 3)
        else
            Text: 0.995, "right", 0.86, "half", "range " + fixed$(.vMin, 3) + " … " + fixed$(.vMax, 3)
        endif
        if iC > 1
            Colour: "{0.80, 0.80, 0.84}"
            Draw line: 0, 1, 1, 1
        endif
        Font size: 7
    endfor
    Select inner viewport: 0.6, 7.7, c0, c1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    .capC$ = "##Control curves sent to SuperVP## — exactly the BPF / values in the command line"
    if nCtrl > 4
        .capC$ = .capC$ + " (first 4 of " + string$(nCtrl) + ")"
    endif
    Text top: "no", .capC$
    Select inner viewport: 0.6, 7.7, c0, c1
    Axes: 0, dur1, 0, 1
    Draw inner box
    @niceStep: dur1, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Input time (s)"
    @railLabel: c0, c1, "Controls"
endproc

procedure drawResultPanels
    if v_dry
        Select inner viewport: 0.6, 7.7, d0, e1
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
        Font size: 9
        Select inner viewport: 0.6, 7.7, d0, e1
        Axes: 0, 1, 0, 1
        Colour: "{0.40, 0.40, 0.40}"
        Text: 0.5, "centre", 0.5, "half", "Dry run — commands and control curves only; no audio rendered"
        Font size: 7
        Select inner viewport: 0.6, 7.7, d0, e1
        Axes: 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
    else
        @paintSpectrogram: resultObj, d0, d1, fmaxSpec, 0
        Select inner viewport: 0.6, 7.7, d0, d1
        Axes: 0, resultDur, 0, fmaxSpec
        Colour: "Black"
        Text top: "no", "##Result## — spectrogram on the input dB scale (" + fixed$(resultDur, 2) + " s)"
        Select inner viewport: 0.6, 7.7, d0, d1
        Axes: 0, resultDur, 0, fmaxSpec
        Draw inner box
        @niceStep: resultDur, 8
        Marks bottom every: 1, niceStep.step, "no", "yes", "no"
        @niceStep: fmaxSpec, 4
        Marks left every: 1, niceStep.step, "yes", "yes", "no"
        @railLabel: d0, d1, "Freq (Hz)"

        # ---- E: waveforms (overlay on a shared output-time axis) ----
        .tSpan = max(dur1, resultDur)
        selectObject: sound1
        .m1 = Get absolute extremum: 0, 0, "None"
        selectObject: resultObj
        .m2 = Get absolute extremum: 0, 0, "None"
        .wR = max(.m1, .m2, 1e-6) * 1.05
        Select inner viewport: 0.6, 7.7, e0, e1
        Axes: 0, .tSpan, -.wR, .wR
        Paint rectangle: "{0.98, 0.98, 0.99}", 0, .tSpan, -.wR, .wR
        selectObject: sound1
        .mono1 = Convert to mono
        Shift times to: "start time", 0
        Select inner viewport: 0.6, 7.7, e0, e1
        Colour: "{0.72, 0.72, 0.76}"
        Draw: 0, .tSpan, -.wR, .wR, "no", "Curve"
        removeObject: .mono1
        selectObject: resultObj
        .mono2 = Convert to mono
        Shift times to: "start time", 0
        Select inner viewport: 0.6, 7.7, e0, e1
        Colour: "{0.20, 0.40, 0.80}"
        Draw: 0, .tSpan, -.wR, .wR, "no", "Curve"
        removeObject: .mono2
        Select inner viewport: 0.6, 7.7, e0, e1
        Axes: 0, .tSpan, -.wR, .wR
        Colour: "Black"
        Text top: "no", "##Waveforms## — grey input, blue result; peak " + fixed$(resultPeak, 3)
        Select inner viewport: 0.6, 7.7, e0, e1
        Axes: 0, .tSpan, -.wR, .wR
        Draw inner box
        @niceStep: .tSpan, 8
        Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
        Text bottom: "yes", "Time (s)"
        @railLabel: e0, e1, "Wave"
    endif
endproc

procedure drawSummary
    Font size: 7
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    .l1$ = "Mode " + mode$ + "  |  profile " + profileName$ + "  |  pitch " + rangeLabel$ + " (" + string$(nVoiced) + "/" + string$(nFrames) + " voiced)  |  input " + fixed$(dur1, 2) + " s"
    if not v_dry
        .l1$ = .l1$ + " → output " + fixed$(resultDur, 2) + " s (ratio " + fixed$(resultDur / dur1, 3) + ", expected " + fixed$(expectedRatio, 3) + ")"
    endif
    @sanitize: .l1$
    Text: 0.012, "left", 0.70, "half", sanitize.out$
    @sanitize: "Quality flags: " + qualityFlags$
    Text: 0.012, "left", 0.55, "half", sanitize.out$
    .dl$ = "Dropped: none"
    if nDrop > 0
        .dl$ = "Dropped (not in the help of this SuperVP): "
        for .i to nDrop
            .dl$ = .dl$ + left$(drop'.i'$, index(drop'.i'$, ":") - 1) + "  "
        endfor
    endif
    @sanitize: .dl$
    Text: 0.012, "left", 0.41, "half", sanitize.out$
    Font size: 5
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    for .i to min(nCmd, 3)
        .c$ = cmd'.i'$
        if length(.c$) > 230
            .c$ = left$(.c$, 227) + "..."
        endif
        @sanitize: .c$
        Text: 0.012, "left", 0.27 - (.i - 1) * 0.105, "half", sanitize.out$
    endfor
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH
endproc
