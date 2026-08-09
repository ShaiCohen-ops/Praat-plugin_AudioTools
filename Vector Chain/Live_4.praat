# ============================================================
# Praat AudioTools - Live 4
# Version: 1.3 (2026) - Praat 7 path fallback + Metamodulator v2.4
# ============================================================

form Live Recording - Composition 4 Settings
    positive Recording_time_seconds 5.0
endform

# ============================================================
# PART 1: RECORDING & PREPARATION
# ============================================================

Record Sound (fixed time): "Microphone", 1.0, 0.5, "44100", recording_time_seconds
recorded = selected("Sound")
Rename: "Recording_raw"

Scale peak: 0.99

Trim silences: 0.08, "yes", 100, 0, -35, 0.1, 0.05, "no", "Trim"
trimmed = selected("Sound")
Rename: "Recording"

selectObject: recorded
Remove
selectObject: trimmed

# ============================================================
# PART 2: COMPOSITION 4 (AudioTools)
# Flow: Cubic Phase -> Grain Cloud -> 8-Channel Comb
# ============================================================

initial_sound = selected("Sound")
initial_name$ = selected$("Sound")

# === GET PLUGIN PATH ===
preferencesDir$ = preferencesDirectory$
pluginPath$ = preferencesDir$ + "/plugin_AudioTools/"

overlap_sec = 0.1
final_fade_sec = 3.0

# === DEFINE SCRIPT PATHS ===
path_intro$ = pluginPath$ + "Modulation/Metamodulator.praat"
path_body$  = pluginPath$ + "Time & Granular/Adaptive_Grain_Cloud_Synthesis.praat"
path_outro$ = pluginPath$ + "Spatial & Surround/8-Channel_Comb_Delay.praat"

# Praat 7 / script-relative fallback
if not fileReadable(path_intro$)
    path_intro$ = defaultDirectory$ + "/../Modulation/Metamodulator.praat"
endif
if not fileReadable(path_body$)
    path_body$ = defaultDirectory$ + "/../Time & Granular/Adaptive_Grain_Cloud_Synthesis.praat"
endif
if not fileReadable(path_outro$)
    path_outro$ = defaultDirectory$ + "/../Spatial & Surround/8-Channel_Comb_Delay.praat"
endif

path_intro$ = replace_regex$(path_intro$, "\\", "/", 0)
path_body$  = replace_regex$(path_body$,  "\\", "/", 0)
path_outro$ = replace_regex$(path_outro$, "\\", "/", 0)

if not fileReadable(path_intro$)
    exitScript: "Cannot find Metamodulator.praat"
endif
if not fileReadable(path_body$)
    exitScript: "Cannot find Adaptive_Grain_Cloud_Synthesis.praat"
endif
if not fileReadable(path_outro$)
    exitScript: "Cannot find 8-Channel_Comb_Delay.praat"
endif

clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  LIVE 4 - Cubic -> Grain -> Comb"
writeInfoLine: "=============================================="
writeInfoLine: ""
writeInfoLine: "Recording time: ", recording_time_seconds, " seconds"
writeInfoLine: "Input: ", initial_name$
writeInfoLine: ""

# ============================================================
# PART 1: INTRO (Metamodulator / Cubic Phase)
# ============================================================

selectObject: initial_sound
appendInfoLine: "=== Part 1: Intro (Cubic Phase Distortion) ==="
appendInfoLine: "  Generating..."

# Metamodulator v2.4 args:
# Preset, Manual_Algorithm, Carrier, Start, End, Mod_factor, Mod_rate,
# Dry_wet_percent, Safety_peak, Show_spectrogram, Draw_visualization, Play_result
runScript: path_intro$, "Cubic: Strong Distortion", "1. Cubic Phase Distortion", 200, 100, 800, 2.0, 5.0, 100, 0.95, 0, 0, 0

sound_intro = selected("Sound")
Rename: initial_name$ + "_Part1_Cubic"

selectObject: sound_intro
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_intro
    sound_intro = tmp
    Rename: initial_name$ + "_Part1_Cubic"
endif

dur_intro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_intro, 2), " s"

selectObject: sound_intro
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ============================================================
# PART 2: BODY (Adaptive Grain Cloud Synthesis)
# ============================================================

selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 2: Body (Grain Cloud Synthesis) ==="
appendInfoLine: "  Generating..."

runScript: path_body$, "Dense Cloud", 50, 0.5, 2.0, 0.0, 0.2, 1, 0, 1.0, 0, 0

sound_body = selected("Sound")
Rename: initial_name$ + "_Part2_GrainCloud"

selectObject: sound_body
nch = Get number of channels
if nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_body
    sound_body = tmp
    Rename: initial_name$ + "_Part2_GrainCloud"
endif

dur_body = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_body, 2), " s"

selectObject: sound_body
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"
Formula: "if x > (xmax - " + string$(overlap_sec) + ") then self * ((xmax - x) / " + string$(overlap_sec) + ") else self fi"

# ============================================================
# PART 3: OUTRO (8-Channel Comb Delay)
# ============================================================

selectObject: initial_sound
appendInfoLine: ""
appendInfoLine: "=== Part 3: Outro (8-Channel Comb Delay) ==="
appendInfoLine: "  Generating..."

runScript: path_outro$, "Linear (2,4,6,8,10,12,14,16)", 2, 4, 6, 8, 10, 12, 14, 16, 0, 0.99, "8 channels - octophonic (Ch1-Ch8)", 0, 0

sound_outro_raw = selected("Sound")
Rename: initial_name$ + "_Part3_Raw"

selectObject: sound_outro_raw
Convert to mono
sound_outro_mono = selected("Sound")
Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"
mono_trimmed_outro = selected("Sound")
trimmed_dur = Get total duration
removeObject: sound_outro_mono, mono_trimmed_outro

selectObject: sound_outro_raw
Extract part: 0, trimmed_dur, "rectangular", 1, "no"
sound_outro = selected("Sound")
Rename: initial_name$ + "_Part3_Comb"

selectObject: sound_outro
nch = Get number of channels
if nch > 2
    Extract one channel: 1
    ch1 = selected("Sound")
    selectObject: sound_outro
    Extract one channel: 2
    ch2 = selected("Sound")
    selectObject: ch1
    plusObject: ch2
    Combine to stereo
    tmp = selected("Sound")
    removeObject: sound_outro, ch1, ch2
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_Comb"
elsif nch = 1
    Convert to stereo
    tmp = selected("Sound")
    removeObject: sound_outro
    sound_outro = tmp
    Rename: initial_name$ + "_Part3_Comb"
endif

dur_outro = Get total duration
appendInfoLine: "  Duration: ", fixed$(dur_outro, 2), " s"

removeObject: sound_outro_raw

selectObject: sound_outro
Formula: "if x < " + string$(overlap_sec) + " then self * (x / " + string$(overlap_sec) + ") else self fi"

# ============================================================
# MIXING
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== Mixing Parts ==="

selectObject: sound_intro
fs = Get sampling frequency

start_1 = 0
start_2 = dur_intro - overlap_sec
start_3 = start_2 + dur_body - overlap_sec
total_dur = start_3 + dur_outro

appendInfoLine: "  Part 1 starts: ", fixed$(start_1, 2), " s"
appendInfoLine: "  Part 2 starts: ", fixed$(start_2, 2), " s"
appendInfoLine: "  Part 3 starts: ", fixed$(start_3, 2), " s"
appendInfoLine: "  Total duration: ", fixed$(total_dur, 2), " s"

silence_end1_dur = total_dur - dur_intro
if silence_end1_dur > 0
    Create Sound from formula: "Silence_End1", 2, 0, silence_end1_dur, fs, "0"
    silence_end1 = selected("Sound")
    selectObject: sound_intro
    plusObject: silence_end1
    Concatenate
    track1 = selected("Sound")
    Rename: "Track_1_Aligned"
    removeObject: silence_end1
else
    selectObject: sound_intro
    track1 = Copy: "Track_1_Aligned"
endif

Create Sound from formula: "Silence_Start2", 2, 0, start_2, fs, "0"
silence_start2 = selected("Sound")

silence_end2_dur = total_dur - (start_2 + dur_body)
if silence_end2_dur > 0
    Create Sound from formula: "Silence_End2", 2, 0, silence_end2_dur, fs, "0"
    silence_end2 = selected("Sound")
else
    Create Sound from formula: "Silence_End2", 2, 0, 0.001, fs, "0"
    silence_end2 = selected("Sound")
endif

selectObject: silence_start2
plusObject: sound_body
plusObject: silence_end2
Concatenate
track2 = selected("Sound")
Rename: "Track_2_Aligned"
removeObject: silence_start2, silence_end2

Create Sound from formula: "Silence_Start3", 2, 0, start_3, fs, "0"
silence_start3 = selected("Sound")
selectObject: silence_start3
plusObject: sound_outro
Concatenate
track3 = selected("Sound")
Rename: "Track_3_Aligned"
removeObject: silence_start3

appendInfoLine: "  Summing tracks..."
selectObject: track1
track2_str$ = string$(track2)
track3_str$ = string$(track3)
Formula: "self + object(" + track2_str$ + ", x) + object(" + track3_str$ + ", x)"

final_name$ = initial_name$ + "_Composition4"
Rename: final_name$
final_sound = selected("Sound")

# ============================================================
# FINAL MASTERING
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== Final Mastering ==="
appendInfoLine: "  Trimming silence..."

selectObject: final_sound
Convert to mono
mono_for_trim = selected("Sound")
Trim silences: 0.1, "yes", 100, 0, -40, 0.1, 0.05, "no", "Trim"
mono_trimmed_final = selected("Sound")
trimmed_final_dur = Get total duration
removeObject: mono_for_trim, mono_trimmed_final

selectObject: final_sound
Extract part: 0, trimmed_final_dur, "rectangular", 1, "no"
trimmed_final = selected("Sound")
removeObject: final_sound
final_sound = trimmed_final
Rename: final_name$

appendInfoLine: "  Applying fade-out (", fixed$(final_fade_sec, 1), " s)..."
selectObject: final_sound
final_dur = Get total duration
fade_start = final_dur - final_fade_sec
if fade_start > 0
    Formula: "if x > " + string$(fade_start) + " then self * ((xmax - x) / " + string$(final_fade_sec) + ") else self fi"
endif

appendInfoLine: "  Normalizing..."
Scale peak: 0.99

# ============================================================
# CLEANUP
# ============================================================

appendInfoLine: ""
appendInfoLine: "Cleaning up intermediate files..."

nocheck removeObject: sound_intro
nocheck removeObject: sound_body
nocheck removeObject: sound_outro
nocheck removeObject: track2
nocheck removeObject: track3
nocheck removeObject: initial_sound

# ============================================================
# FINISH
# ============================================================

selectObject: final_sound
final_dur = Get total duration
final_nch = Get number of channels

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  LIVE 4 COMPOSITION COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Output: ", final_name$
appendInfoLine: "Duration: ", fixed$(final_dur, 2), " s"
appendInfoLine: "Channels: ", final_nch
appendInfoLine: ""
appendInfoLine: "Playing..."

Erase all
selectObject: final_sound
Play
