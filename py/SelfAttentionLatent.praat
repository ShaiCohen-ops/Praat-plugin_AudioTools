# ============================================================
# Praat AudioTools - SelfAttentionLatent.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026) - Dual-trajectory attentional counterpoint
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Self-Attention Latent Navigation Engine
#   Part of Praat AudioTools plugin
#
# Pipeline:
#   1. User selects audio file
#   2. Praat segments into events → writes temp events.csv
#   3. Praat calls Python (self_attention_latent.py)
#   4. Python: VAE encode → self-attention → plan (in memory) → mix → output.wav
#   5. Praat loads output.wav, shows visualization, deletes temp files
#
# No plan.csv is ever written.
# Only output.wav persists after execution.
#
# Changelog v1.5 (engine self_attention_latent.py v1.6):
#   - Navigation_mode: Linked (v1.4 engine path, bit-identical audio) /
#     Independent / Competitive / Divergence_convergence. The three dual
#     modes navigate two latent trajectories (own position, velocity, RNG,
#     context, candidates, anchors and render) over one shared phase plan
#     and write a true two-voice stereo Sound (L voice / R voice).
#   - Trajectory_divergence (0-1): starting offset + minimum-separation floor
#     (Independent, Competitive) or the height of the separation arc (D/C).
#   - Competition_strength (0-1): symmetric soft competition, Competitive only.
#   - Presets 2-14 keep their settings and run Linked; new presets
#     "Dual chaotic plasma" and "Attentional counterpoint".
#   - One time convention: event times are written relative to the exported
#     WAV (Silences segmentation now subtracts the Sound's start time, as
#     Equal_intervals already did); --time_offset 0 and --mix_align on are
#     passed explicitly.
#   - Arguments go to Python through an args file (Windows runSystem limit).
#   - Dual modes draw the Attentional Counterpoint Map from the executed
#     per-step TSV diagnostics; Linked keeps the v1.4 picture.
#   - Review round 1: Competitive and Divergence_convergence share one set of
#     slot boundaries (step i of both voices sounds at the same time);
#     Independent keeps a free rhythm per voice. Overlap, same-dominant,
#     separation, trend and convergence are measured on the sounding
#     timeline (viz_timeline.tsv), not by pairing step numbers.
#   - Review round 2: a step whose event is far longer than its slot plays a
#     moving window through the event (one read cursor per voice and event)
#     instead of always its opening; the Info window reports how much of the
#     events was played and, when events and slots are badly matched,
#     proposes Plan_steps / Interval_size / Target_duration values. Shorter
#     map captions; subtitle names script and engine versions.
#
# Changelog v1.4:
#   - TRUE Equal_intervals segmentation; final interval is no longer omitted.
#   - Python dependency probe matches backend (numpy + soundfile; scipy removed).
#   - Unique temp paths per Sound and captured Python log/error diagnostics.
#   - Pitch modes simplified to varispeed / preserve_pitch (legacy aliases stay
#     accepted by the backend); presets that used the duplicate third mode now
#     map to preserve_pitch with the same intended pitch-preserved behavior.
#   - Visualization compares representative source/output channels on one
#     symmetric waveform scale and reports attention QC / effective head count.
#   - Backend v1.4: corrected VAE gradients, latent-similarity attention,
#     context-indexed attention/return anchors, true overlap crossfade, honest
#     duration/energy jitter, source channel-count preservation and FLOAT WAV.
#
# Changelog v1.3:
#   Backend: three exposed knobs made audible (see .py header):
#     - Pitch_mode now actually works (off = varispeed / pitch tracks
#       speed; preserve_f0 & preserve_spectral_envelope = phase-vocoder,
#       pitch preserved). It was previously inert.
#     - Duration_scale now sets output length (was cancelled by the
#       final time-normalize).
#     - Energy_scale now works as a master gain (was normalized away).
#
# Changelog v1.2:
#
#   TIER 1 (Praat polish, audio bit-identical):
#     - Dropped 8 decorative `comment ── ... ───────` form rows
#       (Preset / Segmentation / VAE / Self-attention / Navigation
#       plan / Output duration / Pitch / Misc). Form: 28 rows ->
#       20 rows. All 4 optionmenus already had colons.
#     - Replaced unicode `══` info window banners with plain
#       ASCII `===` separators (same gotcha as Auto-Harmonic
#       v1.7 -- non-ASCII chars in Praat's info window render
#       inconsistently across platforms).
#     - Replaced unicode `proportional-to` and `middle-dot` in
#       the viz footer formula with ASCII (`~` and `*`). Same
#       reasoning, but for Text() in graphics.
#     - Output filename: `<name>_sal` -> `<name>_sal_<preset>`
#       so multiple runs with different presets don't collide.
#     - Visualization rewritten from custom 8-panel stacked
#       layout to suite 8x8 with side-by-side pairs:
#         Title bar (light) + metadata subtitle
#         Phase bar (full width, signature, color-coded phases)
#         Original waveform / Output waveform (side-by-side)
#         Original spectrogram / Output spectrogram (side-by-side)
#         Light-grey 3-line summary including the formula
#
#   TIER 2 (real bugs, audio bit-identical):
#     - FIXED: subtitle text overflowing into Phase bar. v1.1
#       had axis y=-1.2 with viewport 0,8,0,0.5 -> outer y=1.1
#       inches, which is INSIDE the Phase bar panel (outer
#       0.6-1.4). The subtitle was drawn on top of the phase
#       bar. v1.2 uses suite-standard subtitle position (axis
#       y=-0.22 in a 0-0.65 title viewport).
#     - FIXED: `;` accidentally commented out inline if-statements
#       on v1.1 lines 588-591:
#         nd = number(driftStat$);  if nd = undefined then nd = 0 endif
#       Praat's `;` starts a line comment, so the `if ... endif`
#       portion was NEVER executed. When the Python stats file
#       is missing or any phase count fails to parse, `nd` /
#       `nm` / `nr` / `ns` would stay `undefined`, propagating to
#       `xd = nd / nTotal = undefined`, breaking the phase bar.
#       Only triggers on the failure path, which is why this hasn't
#       been seen in normal runs. v1.2 uses proper multi-line
#       `if ... endif` blocks.
#     - FIXED: `!=` is not valid Praat syntax (v1.1 line 587:
#       `if nTotal > 0 and nTotal != undefined`). Praat uses `<>`
#       for inequality. Replaced with `<>` for portability.
#     - FIXED: probe loop "break early" never actually breaks.
#       v1.1 line 363 had `iCand = nCandidates + 1 ; Break early`.
#       The `;` makes "Break early" a comment, but more importantly,
#       Praat's `for` loop doesn't honor mid-body modifications to
#       the loop variable. The loop ran all candidates regardless,
#       and the LAST successful candidate (not the first) overwrote
#       pythonCmd$. v1.2 uses a `pythonFound` flag and guards the
#       loop body so subsequent iterations skip after the first
#       success.
#
#   TIER 3 (Python backend cleanup):
#     - self_attention_latent.py: removed `"loudness"` alias in
#       `_rms_compensate`. The Praat front-end only ever passes
#       "none", "peak", or "rms" -- the "loudness" branch was
#       unreachable. Cosmetic-only; output is bit-identical.
#
#   Audio output is bit-identical to v1.1 for any input and seed.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-SPECIFIC PYTHON DISCOVERY ----
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

# ---- PATHS & UNIFIED CROSS-PLATFORM FIX ----
pluginDirRaw$ = preferencesDirectory$ + "/plugin_AudioTools/"
pluginDir$ = replace_regex$(pluginDirRaw$, "\\", "/", 0)

pythonScript$ = pluginDir$ + "py/self_attention_latent.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/self_attention_latent.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: self_attention_latent.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempDirRaw$ = temporaryDirectory$ + "/"
tempDir$ = replace_regex$(tempDirRaw$, "\\", "/", 0)

tempTag$     = string$(sound)
tempBase$    = tempDir$ + "temp_sal_" + tempTag$ + "_"
tempWav$     = tempBase$ + "input.wav"
eventsCSV$   = tempBase$ + "events.csv"
output_wav$  = tempBase$ + "output.wav"
stats_txt$   = tempBase$ + "stats.txt"
pythonLog$   = tempBase$ + "python.log"
probePy$     = tempBase$ + "probe.py"
probeMarker$ = tempBase$ + "probe.ok"
argsFile$    = tempBase$ + "args.txt"
vizPrefix$   = tempBase$ + "viz_"
stepsTsv$    = vizPrefix$ + "steps.tsv"
timelineTsv$ = vizPrefix$ + "timeline.tsv"
eventsTsv$   = vizPrefix$ + "events.tsv"

# Enforce forward slashes for all temporary paths passed to python
pythonScriptJ$ = replace_regex$(pythonScript$, "\\", "/", 0)
tempWavJ$      = replace_regex$(tempWav$, "\\", "/", 0)
eventsCSVJ$    = replace_regex$(eventsCSV$, "\\", "/", 0)
output_wavJ$   = replace_regex$(output_wav$, "\\", "/", 0)
stats_txtJ$    = replace_regex$(stats_txt$, "\\", "/", 0)
pythonLogJ$    = replace_regex$(pythonLog$, "\\", "/", 0)
probePyJ$      = replace_regex$(probePy$, "\\", "/", 0)
probeMarkerJ$  = replace_regex$(probeMarker$, "\\", "/", 0)
argsFileJ$     = replace_regex$(argsFile$, "\\", "/", 0)
vizPrefixJ$    = replace_regex$(vizPrefix$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempWav$)
        deleteFile: tempWav$
    endif
    if fileReadable(eventsCSV$)
        deleteFile: eventsCSV$
    endif
    if fileReadable(output_wav$)
        deleteFile: output_wav$
    endif
    if fileReadable(stats_txt$)
        deleteFile: stats_txt$
    endif
    if fileReadable(pythonLog$)
        deleteFile: pythonLog$
    endif
    if fileReadable(probePy$)
        deleteFile: probePy$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
    if fileReadable(argsFile$)
        deleteFile: argsFile$
    endif
    if fileReadable(stepsTsv$)
        deleteFile: stepsTsv$
    endif
    if fileReadable(eventsTsv$)
        deleteFile: eventsTsv$
    endif
    if fileReadable(timelineTsv$)
        deleteFile: timelineTsv$
    endif
endproc

@cleanUpTempFiles

# Six additional listening experiments (A-F). Each uses fixed 8 s, seed 42.
# Experiment F is identical to E except Attention_heads (4 vs 1).
# ---- FORM ----
form Self-Attention Latent Navigation v1.5
    optionmenu Preset: 1
        option Custom
        option Gentle drift
        option Vocal texture
        option Fragmented echo
        option Deep mutation
        option Rhythmic grid
        option Spectral smear
        option Chaotic plasma
        option Micro plasma (experiment)
        option Macro cloud (experiment)
        option Hyper rhythmic grid (experiment)
        option Gestural mutation (experiment)
        option Pure attractor (experiment)
        option Attention stress test (experiment)
        option Dual chaotic plasma
        option Attentional counterpoint
    optionmenu Navigation_mode: 1
        option Linked
        option Independent
        option Competitive
        option Divergence_convergence
    real Trajectory_divergence 0.50
    real Competition_strength 0.50
    optionmenu Segmentation_method: 1
        option Silences
        option Equal_intervals
    positive Silence_threshold_(dB) 25.0
    positive Min_event_duration_(s) 0.05
    positive Min_silence_duration_(s) 0.03
    positive Interval_size_(s) 0.25
    integer Latent_size 8
    integer Random_seed 42
    integer Attention_heads 4
    integer Plan_steps 72
    positive Duration_scale 1.0
    real Duration_jitter 0.0
    positive Energy_scale 1.0
    real Energy_jitter 0.0
    real Target_duration_(s) 0.0
    optionmenu Pitch_mode: 2
        option varispeed
        option preserve_pitch
    optionmenu Normalize_mode: 3
        option none
        option peak
        option rms
    boolean Load_output 1
    boolean Show_visualization 1
    boolean Play_result 1
endform

# ── Presets ────────────────────────────────────────────────────────────────
if preset = 2
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.25
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 24
    duration_scale       = 1.0
    duration_jitter      = 0.05
    energy_scale         = 1.0
    energy_jitter        = 0.0
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "GentleDrift"
elsif preset = 3
    segmentation_method  = 1
    silence_threshold    = 20.0
    min_event_duration   = 0.03
    min_silence_duration = 0.02
    interval_size        = 0.1
    latent_size          = 12
    attention_heads      = 8
    plan_steps           = 48
    duration_scale       = 0.8
    duration_jitter      = 0.1
    energy_scale         = 1.0
    energy_jitter        = 0.05
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "VocalTexture"
elsif preset = 4
    segmentation_method  = 1
    silence_threshold    = 15.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 96
    duration_scale       = 0.5
    duration_jitter      = 0.3
    energy_scale         = 0.8
    energy_jitter        = 0.2
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "FragmentedEcho"
elsif preset = 5
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.25
    latent_size          = 24
    attention_heads      = 8
    plan_steps           = 72
    duration_scale       = 1.2
    duration_jitter      = 0.15
    energy_scale         = 1.1
    energy_jitter        = 0.1
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "DeepMutation"
elsif preset = 6
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.05
    min_silence_duration = 0.03
    interval_size        = 0.125
    latent_size          = 8
    attention_heads      = 4
    plan_steps           = 64
    duration_scale       = 1.0
    duration_jitter      = 0.02
    energy_scale         = 1.0
    energy_jitter        = 0.05
    pitch_mode           = 1
    normalize_mode       = 2
    presetName$          = "RhythmicGrid"
elsif preset = 7
    segmentation_method  = 1
    silence_threshold    = 30.0
    min_event_duration   = 0.1
    min_silence_duration = 0.05
    interval_size        = 0.5
    latent_size          = 16
    attention_heads      = 4
    plan_steps           = 36
    duration_scale       = 1.5
    duration_jitter      = 0.2
    energy_scale         = 0.9
    energy_jitter        = 0.1
    pitch_mode           = 2
    normalize_mode       = 3
    presetName$          = "SpectralSmear"
elsif preset = 8
    segmentation_method  = 1
    silence_threshold    = 10.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 32
    attention_heads      = 16
    plan_steps           = 120
    duration_scale       = 1.0
    duration_jitter      = 0.5
    energy_scale         = 1.0
    energy_jitter        = 0.4
    pitch_mode           = 1
    normalize_mode       = 3
    presetName$          = "ChaoticPlasma"
elsif preset = 9
    # Listening experiment: preset 1 of 6. Existing presets are unchanged.
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.010
    min_silence_duration = 0.03
    interval_size        = 0.035
    latent_size          = 32
    random_seed          = 42
    attention_heads      = 16
    plan_steps           = 200
    duration_scale       = 1.0
    duration_jitter      = 0.50
    energy_scale         = 1.0
    energy_jitter        = 0.50
    target_duration      = 8.0
    pitch_mode           = 1
    normalize_mode       = 3
    load_output          = 1
    show_visualization   = 1
    play_result         = 1
    presetName$          = "MicroPlasma"
elsif preset = 10
    # Listening experiment: preset 2 of 6. Existing presets are unchanged.
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.050
    min_silence_duration = 0.03
    interval_size        = 0.500
    latent_size          = 2
    random_seed          = 42
    attention_heads      = 1
    plan_steps           = 12
    duration_scale       = 1.0
    duration_jitter      = 0.00
    energy_scale         = 1.0
    energy_jitter        = 0.00
    target_duration      = 8.0
    pitch_mode           = 2
    normalize_mode       = 3
    load_output          = 1
    show_visualization   = 1
    play_result         = 1
    presetName$          = "MacroCloud"
elsif preset = 11
    # Listening experiment: preset 3 of 6. Existing presets are unchanged.
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.010
    min_silence_duration = 0.03
    interval_size        = 0.050
    latent_size          = 8
    random_seed          = 42
    attention_heads      = 4
    plan_steps           = 200
    duration_scale       = 1.0
    duration_jitter      = 0.02
    energy_scale         = 1.0
    energy_jitter        = 0.02
    target_duration      = 8.0
    pitch_mode           = 1
    normalize_mode       = 3
    load_output          = 1
    show_visualization   = 1
    play_result         = 1
    presetName$          = "HyperRhythmicGrid"
elsif preset = 12
    # Listening experiment: preset 4 of 6. Existing presets are unchanged.
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.050
    min_silence_duration = 0.03
    interval_size        = 0.400
    latent_size          = 24
    random_seed          = 42
    attention_heads      = 8
    plan_steps           = 24
    duration_scale       = 1.0
    duration_jitter      = 0.50
    energy_scale         = 1.0
    energy_jitter        = 0.40
    target_duration      = 8.0
    pitch_mode           = 2
    normalize_mode       = 3
    load_output          = 1
    show_visualization   = 1
    play_result         = 1
    presetName$          = "GesturalMutation"
elsif preset = 13
    # Listening experiment: preset 5 of 6. Existing presets are unchanged.
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.020
    min_silence_duration = 0.03
    interval_size        = 0.125
    latent_size          = 8
    random_seed          = 42
    attention_heads      = 4
    plan_steps           = 120
    duration_scale       = 1.0
    duration_jitter      = 0.00
    energy_scale         = 1.0
    energy_jitter        = 0.00
    target_duration      = 8.0
    pitch_mode           = 2
    normalize_mode       = 3
    load_output          = 1
    show_visualization   = 1
    play_result         = 1
    presetName$          = "PureAttractor"
elsif preset = 14
    # Listening experiment: preset 6 of 6. Existing presets are unchanged.
    segmentation_method  = 2
    silence_threshold    = 25.0
    min_event_duration   = 0.020
    min_silence_duration = 0.03
    interval_size        = 0.125
    latent_size          = 8
    random_seed          = 42
    attention_heads      = 1
    plan_steps           = 120
    duration_scale       = 1.0
    duration_jitter      = 0.00
    energy_scale         = 1.0
    energy_jitter        = 0.00
    target_duration      = 8.0
    pitch_mode           = 2
    normalize_mode       = 3
    load_output          = 1
    show_visualization   = 1
    play_result         = 1
    presetName$          = "AttentionStressTest"
elsif preset = 15
    # Chaotic plasma processing, two independent highly divergent voices.
    segmentation_method  = 1
    silence_threshold    = 10.0
    min_event_duration   = 0.02
    min_silence_duration = 0.01
    interval_size        = 0.1
    latent_size          = 32
    attention_heads      = 16
    plan_steps           = 120
    duration_scale       = 1.0
    duration_jitter      = 0.5
    energy_scale         = 1.0
    energy_jitter        = 0.4
    pitch_mode           = 1
    normalize_mode       = 3
    navigation_mode      = 2
    trajectory_divergence = 0.85
    competition_strength = 0.0
    presetName$          = "DualChaoticPlasma"
elsif preset = 16
    # Moderately dense counterpoint: two voices that compete for material.
    segmentation_method  = 1
    silence_threshold    = 25.0
    min_event_duration   = 0.04
    min_silence_duration = 0.03
    interval_size        = 0.2
    latent_size          = 16
    attention_heads      = 8
    plan_steps           = 64
    duration_scale       = 1.0
    duration_jitter      = 0.15
    energy_scale         = 1.0
    energy_jitter        = 0.10
    pitch_mode           = 2
    normalize_mode       = 3
    navigation_mode      = 3
    trajectory_divergence = 0.50
    competition_strength = 0.75
    presetName$          = "AttentionalCounterpoint"
else
    presetName$ = "Custom"
endif
# Presets 2-14 are the v1.4 presets: settings and behaviour unchanged, so
# they always run the Linked (v1.4) navigation path.
if preset >= 2 and preset <= 14
    navigation_mode = 1
endif

# ── pitch mode string ──────────────────────────────────────────────────────
if pitch_mode = 1
    pitchStr$ = "varispeed"
else
    pitchStr$ = "preserve_pitch"
endif

# ── normalize mode string ─────────────────────────────────────────────────
if normalize_mode = 1
    normStr$ = "none"
elsif normalize_mode = 2
    normStr$ = "peak"
else
    normStr$ = "rms"
endif

# ── navigation mode string ────────────────────────────────────────────────
if navigation_mode = 1
    navStr$ = "linked"
    navLabel$ = "Linked"
elsif navigation_mode = 2
    navStr$ = "independent"
    navLabel$ = "Independent"
elsif navigation_mode = 3
    navStr$ = "competitive"
    navLabel$ = "Competitive"
else
    navStr$ = "divergence_convergence"
    navLabel$ = "Divergence/convergence"
endif
isDual = navigation_mode > 1
trajectory_divergence = max(0, min(1, trajectory_divergence))
competition_strength = max(0, min(1, competition_strength))

# ── Clamp parameters ─────────────────────────────────────────────────────
if attention_heads < 1
    attention_heads = 1
endif
if attention_heads > 16
    attention_heads = 16
endif
if plan_steps < 8
    plan_steps = 8
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 0 — Early Python Dependency Probe
# ═════════════════════════════════════════════════════════════════════════════
clearinfo
appendInfoLine: "=== Self-Attention Latent Navigation v1.5 ==="
appendInfoLine: "Input:  ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Navigation: ", navLabel$
appendInfoLine: ""
appendInfoLine: "[0/4] Detecting Python dependencies..."

writeFileLine: probePy$, "import sys"
appendFileLine: probePy$, "try:"
appendFileLine: probePy$, "    import numpy, soundfile"
appendFileLine: probePy$, "    with open(r'" + probeMarkerJ$ + "', 'w') as f: f.write('ok')"
appendFileLine: probePy$, "except ImportError:"
appendFileLine: probePy$, "    sys.exit(1)"

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

# v1.2: use a `pythonFound` flag instead of trying to mutate the loop
# variable. Praat's for loop doesn't honor mid-body modifications to
# the loop counter, so v1.1's `iCand = nCandidates + 1 ; Break early`
# was a no-op (the loop ran all candidates and the LAST successful one
# overwrote pythonCmd$). v1.2 guards the loop body with the flag so
# subsequent iterations skip cleanly after the first success.
pythonCmd$ = ""
pythonFound = 0

for iCand from 1 to nCandidates
    if pythonFound = 0
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

        runSystem_nocheck: tryCmd$ + " """ + probePyJ$ + """"

        if fileReadable(probeMarker$)
            pythonCmd$ = tryCmd$
            deleteFile: probeMarker$
            pythonFound = 1
        endif
    endif
endfor

deleteFile: probePy$

if pythonCmd$ = ""
    @cleanUpTempFiles
    exitScript: "Cannot find Python 3 installation with required packages." + newline$ + "Tried: python3, python, py" + newline$ + "Please install: pip install numpy soundfile"
endif

appendInfoLine: "  Python found: ", pythonCmd$

# ═════════════════════════════════════════════════════════════════════════════
# Stage 1 — Load / prepare the Sound
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[1/4] Loading and preparing audio..."

selectObject: sound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels
soundStart = Get start time

# Dual modes render exactly two voices. Channels are never dropped silently:
# a source with more than two channels must use Linked (which keeps all
# channels) or be converted first.
if isDual and nChannels > 2
    @cleanUpTempFiles
    exitScript: navLabel$ + " navigation renders two voices (left / right): the left voice reads channel 1, the right voice channel 2." + newline$ + "This Sound has " + string$(nChannels) + " channels, and channels are never dropped silently." + newline$ + "Use Navigation_mode = Linked (keeps all channels), or extract or mix the channels you want into a stereo or mono Sound first."
endif

# Write as wav so Python can read it reliably
Save as WAV file: tempWav$

# ═════════════════════════════════════════════════════════════════════════════
# Stage 2 — Segmentation → events.csv
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[2/4] Segmenting audio..."
writeFileLine: eventsCSV$, "start_time,end_time,label,duration"
n_events = 0
evSum = 0

if segmentation_method = 2
    # TRUE equal-interval segmentation. v1.3 incorrectly still traversed the
    # silence TextGrid and merely kept all of its intervals.
    eqSize = interval_size
    t = 0
    while t < dur
        en = min(t + eqSize, dur)
        evDur = en - t
        if evDur >= min_event_duration
            appendFileLine: eventsCSV$, fixed$(t, 6), ",", fixed$(en, 6), ",interval,", fixed$(evDur, 6)
            n_events = n_events + 1
            evSum = evSum + evDur
        endif
        t = en
    endwhile
    appendInfoLine: "  Equal intervals: ", fixed$(eqSize, 3), " s"
else
    selectObject: sound
    tg = To TextGrid (silences): 100, 0, -silence_threshold, min_silence_duration, min_event_duration, "silent", "sounding"
    selectObject: tg
    nInt = Get number of intervals: 1
    for i from 1 to nInt
        selectObject: tg
        lab$ = Get label of interval: 1, i
        if lab$ = "sounding"
            # TextGrid times are on the Sound's own timeline; the exported
            # WAV starts at 0, so write times relative to the Sound's start
            # (Equal_intervals already counts from 0).
            st = Get start time of interval: 1, i
            en = Get end time of interval: 1, i
            st = st - soundStart
            en = en - soundStart
            evDur = en - st
            if evDur >= min_event_duration
                appendFileLine: eventsCSV$, fixed$(st, 6), ",", fixed$(en, 6), ",", lab$, ",", fixed$(evDur, 6)
                n_events = n_events + 1
                evSum = evSum + evDur
            endif
        endif
    endfor
    removeObject: tg

    if n_events < 2
        # Dense/continuous material may contain no useful silence boundaries.
        appendInfoLine: "  Warning: too few silence events; falling back to equal intervals"
        writeFileLine: eventsCSV$, "start_time,end_time,label,duration"
        n_events = 0
        evSum = 0
        eqSize = interval_size
        if eqSize > dur / 2
            eqSize = dur / 2
        endif
        t = 0
        while t < dur
            en = min(t + eqSize, dur)
            evDur = en - t
            if evDur >= min_event_duration
                appendFileLine: eventsCSV$, fixed$(t, 6), ",", fixed$(en, 6), ",interval,", fixed$(evDur, 6)
                n_events = n_events + 1
                evSum = evSum + evDur
            endif
            t = en
        endwhile
    endif
endif

appendInfoLine: "  Events: " + string$(n_events)
if n_events < 2
    @cleanUpTempFiles
    exitScript: "Only " + string$(n_events) + " event detected. Latent navigation needs at least two events." + newline$ + "Use a smaller Interval size or shorter Min event duration."
endif

# Dual modes: are the events much longer than a step's slot? Then each step
# plays a moving window of its event rather than the whole event (engine
# round 2), and a better-matched segmentation is proposed. Nothing is
# changed automatically. (Linked compresses the whole render instead; its
# v1.4 behaviour is kept as it is.)
advice1$ = ""
advice2$ = ""
meanEv = evSum / n_events
if target_duration > 0
    outT = target_duration * duration_scale
else
    outT = dur * duration_scale
endif
slotEst = outT / plan_steps
fitEst = slotEst / meanEv
if isDual and fitEst < 0.5
    stepsWhole = max(8, round(outT / meanEv))
    intervalProp = max(0.02, 2 * slotEst)
    durProp = 0.5 * plan_steps * meanEv / duration_scale
    advice1$ = "Events average " + fixed$(meanEv, 3) + " s but a step slot is about " + fixed$(slotEst, 3) + " s, so each step plays a moving window through its event (about " + fixed$(100 * 2 * fitEst, 0) + " percent of it per step)."
    advice2$ = "For whole events: Plan_steps about " + string$(stepsWhole) + ", or Equal_intervals with Interval_size about " + fixed$(intervalProp, 3) + " s, or Target_duration of at least " + fixed$(durProp, 1) + " s."
endif
if isDual and n_events < 8
    advice2$ = advice2$ + if advice2$ = "" then "" else " " fi + "Only " + string$(n_events) + " events: the two voices have little material to choose between (a smaller Interval_size or Equal_intervals gives more)."
endif
if advice1$ <> "" or advice2$ <> ""
    appendInfoLine: "  Note: ", advice1$
    appendInfoLine: "        ", advice2$
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 3 — Call Python
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[3/4] Running Python engine..."

# One argument per line in an args file: no shell quoting, and no risk of
# the ~1 kB command-line truncation of runSystem on Windows.
writeFileLine: argsFile$, tempWavJ$
appendFileLine: argsFile$, eventsCSVJ$
appendFileLine: argsFile$, output_wavJ$
appendFileLine: argsFile$, stats_txtJ$
appendFileLine: argsFile$, "--latent_size", newline$, string$(latent_size)
appendFileLine: argsFile$, "--seed", newline$, string$(random_seed)
appendFileLine: argsFile$, "--attn_heads", newline$, string$(attention_heads)
appendFileLine: argsFile$, "--plan_steps", newline$, string$(plan_steps)
appendFileLine: argsFile$, "--plan_dur_scale", newline$, string$(duration_scale)
appendFileLine: argsFile$, "--plan_dur_jitter", newline$, string$(duration_jitter)
appendFileLine: argsFile$, "--plan_eng_scale", newline$, string$(energy_scale)
appendFileLine: argsFile$, "--plan_eng_jitter", newline$, string$(energy_jitter)
appendFileLine: argsFile$, "--pitch_mode", newline$, pitchStr$
appendFileLine: argsFile$, "--normalize_mode", newline$, normStr$
if target_duration > 0
    appendFileLine: argsFile$, "--duration", newline$, string$(target_duration)
endif
# Event times are relative to the exported WAV (see segmentation).
appendFileLine: argsFile$, "--time_offset", newline$, "0"
appendFileLine: argsFile$, "--mix_align", newline$, "on"
appendFileLine: argsFile$, "--nav_mode", newline$, navStr$
if isDual
    appendFileLine: argsFile$, "--divergence", newline$, string$(trajectory_divergence)
    appendFileLine: argsFile$, "--competition", newline$, string$(competition_strength)
    appendFileLine: argsFile$, "--viz_tsv", newline$, vizPrefixJ$
endif
appendFileLine: argsFile$, "--cleanup"

cmd$ = pythonCmd$ + " """ + pythonScriptJ$ + """ ""@" + argsFileJ$ + """"
    ... + " > """ + pythonLogJ$ + """ 2>&1"

runSystem_nocheck: cmd$

if not fileReadable(stats_txt$)
    errText$ = "Python engine failed."
    if fileReadable(pythonLog$)
        errText$ = errText$ + newline$ + readFile$(pythonLog$)
    endif
    @cleanUpTempFiles
    exitScript: errText$
endif

if fileReadable(pythonLog$)
    pyText$ = readFile$(pythonLog$)
    appendInfoLine: pyText$
endif

# ═════════════════════════════════════════════════════════════════════════════
# Stage 4 — Read stats & Load Output
# ═════════════════════════════════════════════════════════════════════════════
appendInfoLine: "[4/4] Finalizing results..."

# Stats parsing helper
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .kl = length(.key$)
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + .kl
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl    = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

nEventsStat$    = "?"
nStepsStat$     = "?"
nExecStat$      = "?"
outDurStat$     = "?"
attnHeadsStat$  = "?"
attnEntropyStat$ = "?"
attnEntropyNormStat$ = "?"
attnReweightStat$ = "?"
uniqueDomStat$ = "?"
analysisChannelStat$ = "1"
inputChannelsStat$ = "?"
outputChannelsStat$ = "?"
pitchModeStat$  = "?"
normModeStat$   = "?"
rmsInputStat$   = "?"
rmsOutputStat$  = "?"
vaeLossStat$    = "?"
driftStat$      = "?"
mutateStat$     = "?"
returnStat$     = "?"
settleStat$     = "?"
navModeStat$ = "linked"
ignoredStat$ = "?"
routingStat$ = "?"
srcLStat$ = "?"
srcRStat$ = "?"
uniqLStat$ = "?"
uniqRStat$ = "?"
sharedDomStat$ = "?"
overlapStat$ = "?"
sepMeanStat$ = "?"
sepBeginStat$ = "?"
sepPeakStat$ = "?"
sepEndStat$ = "?"
compAdjStat$ = "?"
lambdaStat$ = "?"
peakLStat$ = "?"
peakRStat$ = "?"
rmsLStat$ = "?"
rmsRStat$ = "?"
lrCorrStat$ = "?"
fitMedStat$ = "?"
cappedStat$ = "?"
pcaEv1Stat$ = "?"
pcaEv2Stat$ = "?"
finalResizeStat$ = "?"
timelineStat$ = "?"
startOffStat$ = "?"
windowedStat$ = "?"
covLStat$ = "?"
covRStat$ = "?"
cov0LStat$ = "?"

if fileReadable(stats_txt$)
    statsText$ = readFile$(stats_txt$)

    @parseStatLine: statsText$, "n_events="
    nEventsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_plan_steps="
    nStepsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_executed="
    nExecStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_heads="
    attnHeadsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_entropy="
    attnEntropyStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "attn_entropy_norm="
    attnEntropyNormStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_attention_reweight="
    attnReweightStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "unique_dominant_events="
    uniqueDomStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "analysis_channel="
    analysisChannelStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "input_channels="
    inputChannelsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_channels="
    outputChannelsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "pitch_mode="
    pitchModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "normalize_mode="
    normModeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_input="
    rmsInputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "rms_output="
    rmsOutputStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "vae_loss_final="
    vaeLossStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_drift="
    driftStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_mutate="
    mutateStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_return="
    returnStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mode_settle="
    settleStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_resize_ratio="
    finalResizeStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "nav_mode="
    navModeStat$ = parseStatLine.result$
    if isDual
        @parseStatLine: statsText$, "ignored_parameters="
        ignoredStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "dual_timeline="
        timelineStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "step_start_offset_max="
        startOffStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "segments_windowed="
        windowedStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "read_coverage_L="
        covLStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "read_coverage_R="
        covRStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "read_coverage_start_only_L="
        cov0LStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "dual_routing="
        routingStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "voice_L_source="
        srcLStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "voice_R_source="
        srcRStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "unique_dominant_L="
        uniqLStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "unique_dominant_R="
        uniqRStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "shared_dominant_fraction="
        sharedDomStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "selection_overlap_mean="
        overlapStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "separation_mean="
        sepMeanStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "separation_begin="
        sepBeginStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "separation_peak_region="
        sepPeakStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "separation_end="
        sepEndStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "competition_adjust_mean="
        compAdjStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "competition_lambda="
        lambdaStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "peak_L="
        peakLStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "peak_R="
        peakRStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "rms_L="
        rmsLStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "rms_R="
        rmsRStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "lr_correlation="
        lrCorrStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "segment_fit_ratio_median="
        fitMedStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "segments_capped="
        cappedStat$ = parseStatLine.result$
        @parseStatLine: statsText$, "pca_explained_1="
        pcaEv1Stat$ = parseStatLine.result$
        @parseStatLine: statsText$, "pca_explained_2="
        pcaEv2Stat$ = parseStatLine.result$
    endif
endif

haveOutput = 0
if load_output and fileReadable(output_wav$)
    outSound = Read from file: output_wav$
    # v1.2: include preset name in output filename.
    compositeName$ = soundName$ + "_sal_" + presetName$
    Rename: compositeName$
    appendInfoLine: "  Loaded output as: " + compositeName$
    haveOutput = 1
else
    compositeName$ = soundName$ + "_sal_" + presetName$
endif

# Executed per-step diagnostics are read into Tables BEFORE the temp files
# are deleted; the map draws nothing that is not in them or in the output.
stepsTab = 0
eventsTab = 0
timeTab = 0
if isDual and fileReadable(stepsTsv$) and fileReadable(eventsTsv$) and fileReadable(timelineTsv$)
    stepsTab = Read Table from tab-separated file: stepsTsv$
    eventsTab = Read Table from tab-separated file: eventsTsv$
    timeTab = Read Table from tab-separated file: timelineTsv$
endif

@cleanUpTempFiles

###############################################################################
# VISUALIZATION  (8 x 8 canvas, suite styling)
# Title bar (suite light) + metadata subtitle
# Panel A: Phase bar  (full width, signature, color-coded phases)
# Panel B: Original waveform   (left half)
# Panel C: Output waveform     (right half)
# Panel D: Original spectrogram   (left half)
# Panel E: Output spectrogram     (right half)
# Panel F: Light-grey 3-line summary (suite standard)
###############################################################################

if show_visualization and isDual
    if stepsTab and haveOutput
        appendInfoLine: "  Drawing Attentional Counterpoint Map..."
        @drawCounterpointMap
    else
        appendInfoLine: "  Map not drawn: needs the loaded output and the step diagnostics."
    endif
elsif show_visualization
    appendInfoLine: "  Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Black
    Plain line

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    # v1.2: subtitle position fixed. v1.1 had axis y=-1.2 with
    # viewport 0,8,0,0.5 -> outer y=1.1 (inside Phase bar). v1.2
    # uses suite-standard axis y=-0.22 with viewport 0-0.65.
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##SELF-ATTENTION LATENT NAVIGATION v1.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + presetName$
        ... + "  |  heads=" + attnHeadsStat$
        ... + "  |  steps=" + nStepsStat$
        ... + "  |  z=" + string$(latent_size)

    # ----------------------------------------------------------
    # PANEL A: PHASE BAR  (full width, signature, color-coded phases)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 1.95
    Select inner viewport: 0.55, 7.72, 0.95, 1.85

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.92, 0.92, 0.93}", 0, 1, 0, 1

    # v1.2: parse phase counts with proper if/endif blocks. v1.1 had
    # `nd = number(driftStat$);  if nd = undefined then nd = 0 endif`
    # but `;` is Praat's line-comment marker, so the if was a no-op.
    # When stats are missing, phase counts stayed undefined and broke
    # the phase bar drawing.
    nTotal = number(nStepsStat$)
    if nTotal = undefined
        nTotal = 0
    endif

    # v1.2: `<>` instead of v1.1's `!=` (which is not valid Praat
    # syntax -- Praat uses `<>` for inequality).
    if nTotal > 0
        nd = number(driftStat$)
        if nd = undefined
            nd = 0
        endif
        nm = number(mutateStat$)
        if nm = undefined
            nm = 0
        endif
        nr = number(returnStat$)
        if nr = undefined
            nr = 0
        endif
        ns = number(settleStat$)
        if ns = undefined
            ns = 0
        endif

        xd = nd / nTotal
        xm = xd + nm / nTotal
        xr = xm + nr / nTotal
        xs = xr + ns / nTotal

        Paint rectangle: "{0.30, 0.75, 0.88}",  0,  xd, 0, 1
        Paint rectangle: "{0.92, 0.82, 0.30}", xd, xm, 0, 1
        Paint rectangle: "{0.90, 0.55, 0.20}", xm, xr, 0, 1
        Paint rectangle: "{0.30, 0.72, 0.40}", xr, xs, 0, 1

        Font size: 8
        Colour: "Black"
        if xd > 0.08
            Text: xd / 2, "centre", 0.5, "half", "drift " + driftStat$
        endif
        if (xm - xd) > 0.08
            Text: (xd + xm) / 2, "centre", 0.5, "half", "mutate " + mutateStat$
        endif
        if (xr - xm) > 0.08
            Text: (xm + xr) / 2, "centre", 0.5, "half", "return " + returnStat$
        endif
        if (xs - xr) > 0.08
            Text: (xr + xs) / 2, "centre", 0.5, "half", "settle " + settleStat$
        endif
    else
        Font size: 8
        Colour: "{0.55, 0.55, 0.60}"
        Text: 0.5, "centre", 0.5, "half", "(no phase data available)"
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Navigation plan:  " + nStepsStat$ + " steps  /  " + nExecStat$ + " executed"
    Font size: 6
    Text left: "yes", "Phases"

    # Prepare representative channels once for waveform + spectrogram panels.
    analysisCh = number(analysisChannelStat$)
    if analysisCh = undefined or analysisCh < 1
        analysisCh = 1
    endif
    if analysisCh > nChannels
        analysisCh = nChannels
    endif

    selectObject: sound
    if nChannels > 1
        Extract one channel: analysisCh
        vizOrig = selected("Sound")
    else
        Copy: "sal_viz_orig"
        vizOrig = selected("Sound")
    endif
    selectObject: vizOrig
    origMax = Get maximum: 0, 0, "Sinc70"
    origMin = Get minimum: 0, 0, "Sinc70"
    wavePeak = max(abs(origMax), abs(origMin))

    vizOut = 0
    if haveOutput
        selectObject: outSound
        outChansViz = Get number of channels
        outAnalysisCh = min(analysisCh, outChansViz)
        if outChansViz > 1
            Extract one channel: outAnalysisCh
            vizOut = selected("Sound")
        else
            Copy: "sal_viz_out"
            vizOut = selected("Sound")
        endif
        selectObject: vizOut
        outMax = Get maximum: 0, 0, "Sinc70"
        outMin = Get minimum: 0, 0, "Sinc70"
        wavePeak = max(wavePeak, max(abs(outMax), abs(outMin)))
    endif
    if wavePeak < 0.001
        wavePeak = 1
    endif
    wavePeak = wavePeak * 1.05

    # ----------------------------------------------------------
    # PANEL B (left): ORIGINAL WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 2.05, 3.10
    Select inner viewport: 0.55, 4.00, 2.20, 3.00

    selectObject: vizOrig
    Colour: "{0.55, 0.55, 0.60}"
    Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original waveform"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL C (right): OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.05, 3.10
    Select inner viewport: 4.55, 7.75, 2.20, 3.00

    if haveOutput
        selectObject: vizOut
        Colour: "{0.30, 0.60, 0.50}"
        Draw: 0, 0, -wavePeak, wavePeak, "no", "Curve"
    endif
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output waveform"
    Font size: 6
    Text left: "yes", "Amp"

    # ----------------------------------------------------------
    # PANEL D (left): ORIGINAL SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 3.20, 5.40
    Select inner viewport: 0.55, 4.00, 3.35, 5.25

    selectObject: vizOrig
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    specOrig = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Original spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    removeObject: specOrig

    # ----------------------------------------------------------
    # PANEL E (right): OUTPUT SPECTROGRAM
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.20, 5.40
    Select inner viewport: 4.55, 7.75, 3.35, 5.25

    if haveOutput
        selectObject: vizOut
        To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
        specOut = selected("Spectrogram")
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Line width: 1
        Draw inner box
        removeObject: specOut
    else
        Colour: "Black"
        Line width: 1
        Draw inner box
    endif
    Font size: 7
    Text top: "no", "Output spectrogram"
    Font size: 6
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL F: SUMMARY BAR  (suite standard light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.50, 6.20
    Select inner viewport: 0.55, 7.72, 5.57, 6.15
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"

    Text: 0.02, "left", 0.82, "half",
        ... "##" + presetName$ + "##"
        ... + "  Events: " + nEventsStat$
        ... + "  |  Plan: " + nStepsStat$ + " steps / " + nExecStat$ + " executed"
        ... + "  |  Output dur: " + outDurStat$ + " s"
        ... + "  |  Attention: " + attnHeadsStat$ + " heads, Hnorm=" + attnEntropyNormStat$
        ... + ", reweight=" + attnReweightStat$

    Text: 0.02, "left", 0.50, "half",
        ... "Pitch: " + pitchModeStat$
        ... + "  |  Normalize: " + normModeStat$
        ... + "  |  VAE loss final: " + vaeLossStat$
        ... + "  |  RMS: " + rmsInputStat$ + " -> " + rmsOutputStat$
        ... + "  |  z=" + string$(latent_size)
        ... + "  |  dominant=" + uniqueDomStat$ + "/" + nEventsStat$
        ... + "  |  analysis ch=" + analysisChannelStat$

    # v1.2: ASCII formula -- v1.1 used `proportional-to` and middle-dot
    # which render unpredictably on some Praat installs.
    Text: 0.02, "left", 0.18, "half",
        ... "Output: " + compositeName$
        ... + "  |  w_j ~ (1/dist_j^p) * (A[context,j]^q)  (pure NumPy, no external models)"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    if haveOutput
        removeObject: vizOrig, vizOut
    else
        removeObject: vizOrig
    endif

    Font size: 10
    Colour: "Black"
    Line width: 1
    # v1.5: whole canvas selected, so Save as PNG / Copy export all panels
    Select outer viewport: 0, 8, 0, 6.2
else
    appendInfoLine: "  Visualization skipped."
endif

###############################################################################
# Text log
###############################################################################
appendInfoLine: ""
appendInfoLine: "=========================================="
appendInfoLine: "Self-Attention Latent - Run Summary"
appendInfoLine: "=========================================="
appendInfoLine: "Input:       ", soundName$
appendInfoLine: "Preset:      ", presetName$
appendInfoLine: "Output:      ", compositeName$, " (Praat object)"
appendInfoLine: "Events:      ", nEventsStat$
appendInfoLine: "Plan:        ", nStepsStat$, " steps  (", nExecStat$, " executed)"
appendInfoLine: "Phases:      drift=", driftStat$, "  mutate=", mutateStat$,
    ... "  return=", returnStat$, "  settle=", settleStat$
appendInfoLine: "Attention:   heads=", attnHeadsStat$, "  entropy=", attnEntropyStat$, " nats  Hnorm=", attnEntropyNormStat$
appendInfoLine: "Attention effect: reweight=", attnReweightStat$, "  dominant events=", uniqueDomStat$, "/", nEventsStat$
appendInfoLine: "Channels:    input=", inputChannelsStat$, "  analysis=", analysisChannelStat$, "  output=", outputChannelsStat$
appendInfoLine: "VAE loss:    ", vaeLossStat$
appendInfoLine: "Output dur:  ", outDurStat$, " s"
appendInfoLine: "Pitch mode:  ", pitchModeStat$
appendInfoLine: "Normalize:   ", normModeStat$, "  RMS: ", rmsInputStat$, " -> ", rmsOutputStat$
appendInfoLine: "Navigation:  ", navLabel$, "  (engine: ", navModeStat$, ")"
if isDual
    appendInfoLine: "Divergence:  ", fixed$(trajectory_divergence, 2), "   Competition: ", fixed$(competition_strength, 2), "  (lambda ", lambdaStat$, ")"
    appendInfoLine: "Ignored:     ", ignoredStat$
    appendInfoLine: "Routing:     ", routingStat$, "  (L voice <- ", srcLStat$, ", R voice <- ", srcRStat$, ")"
    appendInfoLine: "Step timing: ", timelineStat$, "  (largest start offset between step i of L and R: ", startOffStat$, " s)"
    appendInfoLine: "Dominant:    L ", uniqLStat$, "  R ", uniqRStat$, " of ", nEventsStat$, " events;  same dominant sounding together ", sharedDomStat$, " of the time"
    appendInfoLine: "Overlap:     ", overlapStat$, " (time-weighted, sounding together)   competition adjustment (TV) ", compAdjStat$
    appendInfoLine: "Separation:  mean ", sepMeanStat$, "  begin ", sepBeginStat$, "  peak region ", sepPeakStat$, "  end ", sepEndStat$, "  (x median latent distance)"
    appendInfoLine: "Stereo:      peak L/R ", peakLStat$, " / ", peakRStat$, "   RMS L/R ", rmsLStat$, " / ", rmsRStat$, "   L/R corr ", lrCorrStat$
    appendInfoLine: "Timeline:    no whole-file resize; per-segment fit ratio median ", fitMedStat$, ", segments at the fit limit ", cappedStat$, " (", windowedStat$, " read as moving windows)"
    appendInfoLine: "Coverage:    share of the dominant events played  L ", covLStat$, "  R ", covRStat$, "   (reading only their openings: L ", cov0LStat$, ")"
    if advice1$ <> "" or advice2$ <> ""
        appendInfoLine: "Suggestion:  ", advice1$
        appendInfoLine: "             ", advice2$
    endif
    if stepsTab = 0
        appendInfoLine: "Warning:     step diagnostics were not produced; the map was not drawn."
    endif
else
    appendInfoLine: "Timeline:    whole-file resize ratio ", finalResizeStat$
endif
appendInfoLine: "=========================================="
appendInfoLine: ""

if stepsTab
    removeObject: stepsTab, eventsTab, timeTab
endif

if haveOutput
    selectObject: outSound
    if play_result
        Play
    endif
endif

###############################################################################
# ATTENTIONAL COUNTERPOINT MAP  (dual navigation modes, 8 x 8.95 in canvas)
# Every mark is read from the executed per-step Table (stepsTab: one row per
# step and voice, rows 1..n = L, n+1..2n = R), the projected-event Table
# (eventsTab) or the output Sound itself.
#   A  phase timeline in output time (L / R slots) + executed separation trend
#   B  two lanes: dominant event per slot, L and R
#   C  latent constellation (shared PCA): events, both paths, start/end,
#      convergence points
#   D  normalised latent separation and selection overlap over time
#   E  L / R output waveforms on one shared amplitude scale
#   F  compositional summary
###############################################################################
procedure cmSafe: .s$
    .r$ = replace$(.s$, "\", "\bs", 0)
    .r$ = replace$(.r$, "_", "\_ ", 0)
    .r$ = replace$(.r$, "%", "\% ", 0)
    .r$ = replace$(.r$, "#", "\# ", 0)
    .r$ = replace$(.r$, "^", "\^ ", 0)
endproc

procedure cmNice: .span, .n
    .step = 1
    if .span > 0 and .n > 0
        .raw = .span / .n
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
    endif
endproc

procedure cmPhaseColour: .ph$
    if .ph$ = "drift"
        .c$ = "{0.30, 0.75, 0.88}"
    elsif .ph$ = "mutate"
        .c$ = "{0.92, 0.82, 0.30}"
    elsif .ph$ = "return"
        .c$ = "{0.90, 0.55, 0.20}"
    else
        .c$ = "{0.30, 0.72, 0.40}"
    endif
endproc

procedure drawCounterpointMap
    cmColL$ = "{0.20, 0.40, 0.80}"
    cmColR$ = "{0.85, 0.33, 0.10}"
    cmGrid$ = "{0.60, 0.60, 0.60}"
    selectObject: stepsTab
    cmRows = Get number of rows
    cmN = round(cmRows / 2)
    selectObject: eventsTab
    cmNEv = Get number of rows
    selectObject: outSound
    cmT = Get total duration
    @cmNice: cmT, 8
    cmTStep = cmNice.step

    Erase all
    Black
    Plain line
    Line width: 1

    # ---------------- TITLE ----------------
    Font size: 12
    Select inner viewport: 0.6, 7.7, 0.05, 0.62
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##ATTENTIONAL COUNTERPOINT MAP##"
    @cmSafe: soundName$
    cmSub$ = cmSafe.r$ + "  |  " + presetName$ + "  |  " + navLabel$
        ... + "  |  divergence " + fixed$(trajectory_divergence, 2)
        ... + "  |  competition " + fixed$(competition_strength, 2)
        ... + "  |  Self-Attention Latent v1.5 (engine 1.6)"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.05, 0.62
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.20, "half", cmSub$

    # ---------------- A: PHASE TIMELINE ----------------
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 1.45
    Axes: 0, cmT, 0, 3
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, cmT, 0, 3
    for cmI from 1 to cmRows
        selectObject: stepsTab
        cmV$ = Get value: cmI, "voice"
        cmPh$ = Get value: cmI, "phase"
        cmA = Get value: cmI, "t0"
        cmB = Get value: cmI, "t1"
        @cmPhaseColour: cmPh$
        if cmV$ = "L"
            Paint rectangle: cmPhaseColour.c$, cmA, cmB, 2, 3
        else
            Paint rectangle: cmPhaseColour.c$, cmA, cmB, 1, 2
        endif
    endfor
    # separation trend of the two voices as they sound together
    selectObject: timeTab
    cmNT = Get number of rows
    for cmI from 1 to cmNT
        selectObject: timeTab
        cmTr$ = Get value: cmI, "trend"
        cmA = Get value: cmI, "t0"
        cmB = Get value: cmI, "t1"
        if cmTr$ = "diverge"
            cmC$ = "{0.72, 0.58, 0.88}"
        elsif cmTr$ = "converge"
            cmC$ = "{0.55, 0.80, 0.55}"
        else
            cmC$ = "{0.90, 0.90, 0.90}"
        endif
        Paint rectangle: cmC$, cmA, cmB, 0, 1
    endfor
    Select inner viewport: 0.6, 7.7, 0.95, 1.45
    Axes: 0, cmT, 0, 3
    Colour: "White"
    Draw line: 0, 2, cmT, 2
    Draw line: 0, 1, cmT, 1
    # phase names at the first L slot of each phase
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.95, 1.45
    Axes: 0, cmT, 0, 3
    Colour: "Black"
    cmPrev$ = ""
    for cmI from 1 to cmN
        selectObject: stepsTab
        cmPh$ = Get value: cmI, "phase"
        if cmPh$ <> cmPrev$
            cmA = Get value: cmI, "t0"
            Text: cmA + 0.005 * cmT, "left", 2.5, "half", cmPh$
            cmPrev$ = cmPh$
        endif
    endfor
    Select inner viewport: 0.6, 7.7, 0.95, 1.45
    Axes: 0, cmT, 0, 3
    Text: -0.006 * cmT, "right", 2.5, "half", "L"
    Text: -0.006 * cmT, "right", 1.5, "half", "R"
    Text: -0.006 * cmT, "right", 0.5, "half", "trend"
    Font size: 7
    Select inner viewport: 0.6, 7.7, 0.95, 1.45
    Axes: 0, cmT, 0, 3
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, cmTStep, "no", "yes", "no"
    if timelineStat$ = "shared"
        Text top: "no", "##A## Phases (shared L / R slots) and separation trend: purple apart, green closer, grey steady"
    else
        Text top: "no", "##A## Phases (free L / R slots) and separation trend: purple apart, green closer, grey steady"
    endif

    # ---------------- B: LANES ----------------
    cmEvStep = 1
    if cmNEv > 12
        @cmNice: cmNEv, 5
        cmEvStep = max(1, cmNice.step)
    endif
    for cmLane from 1 to 2
        if cmLane = 1
            cmY0 = 1.85
            cmY1 = 2.80
            cmCol$ = cmColL$
            cmOff = 0
        else
            cmY0 = 3.10
            cmY1 = 4.05
            cmCol$ = cmColR$
            cmOff = cmN
        endif
        Font size: 7
        Select inner viewport: 0.6, 7.7, cmY0, cmY1
        Axes: 0, cmT, -0.5, cmNEv - 0.5
        Paint rectangle: "{0.985, 0.985, 0.985}", 0, cmT, -0.5, cmNEv - 0.5
        for cmI from 1 to cmN
            selectObject: stepsTab
            cmDom = Get value: cmI + cmOff, "dominant"
            cmW = Get value: cmI + cmOff, "dom_w"
            cmA = Get value: cmI + cmOff, "t0"
            cmB = Get value: cmI + cmOff, "t1"
            cmH = 0.10 + 0.32 * cmW
            Paint rectangle: cmCol$, cmA, cmB, cmDom - cmH, cmDom + cmH
        endfor
        Select inner viewport: 0.6, 7.7, cmY0, cmY1
        Axes: 0, cmT, -0.5, cmNEv - 0.5
        Colour: "Black"
        Line width: 1
        for cmI from 1 to cmNT
            selectObject: timeTab
            cmSh = Get value: cmI, "shared"
            if cmSh = 1
                cmDom = Get value: cmI, "domL"
                cmA = Get value: cmI, "t0"
                cmB = Get value: cmI, "t1"
                Draw rectangle: cmA, cmB, cmDom - 0.46, cmDom + 0.46
            endif
        endfor
        Font size: 7
        Select inner viewport: 0.6, 7.7, cmY0, cmY1
        Axes: 0, cmT, -0.5, cmNEv - 0.5
        Colour: "Black"
        Draw inner box
        Marks left every: 1, cmEvStep, "yes", "yes", "no"
        Text left: "yes", "Event"
        if cmLane = 1
            Marks bottom every: 1, cmTStep, "no", "yes", "no"
            Text top: "no", "##B## LEFT voice: dominant event per slot (thickness = mix weight; frame = same event sounding in R)"
        else
            Marks bottom every: 1, cmTStep, "yes", "yes", "no"
            Text bottom: "yes", "Output time (s)"
            Text top: "no", "RIGHT voice"
        endif
    endfor

    # ---------------- C: LATENT CONSTELLATION ----------------
    cmXmin = 1e30
    cmXmax = -1e30
    cmYmin = 1e30
    cmYmax = -1e30
    for cmI from 1 to cmNEv
        selectObject: eventsTab
        cmX = Get value: cmI, "x"
        cmY = Get value: cmI, "y"
        cmXmin = min(cmXmin, cmX)
        cmXmax = max(cmXmax, cmX)
        cmYmin = min(cmYmin, cmY)
        cmYmax = max(cmYmax, cmY)
    endfor
    for cmI from 1 to cmRows
        selectObject: stepsTab
        cmX = Get value: cmI, "x"
        cmY = Get value: cmI, "y"
        cmXmin = min(cmXmin, cmX)
        cmXmax = max(cmXmax, cmX)
        cmYmin = min(cmYmin, cmY)
        cmYmax = max(cmYmax, cmY)
    endfor
    # degenerate projection (identical latents): a fixed +-1 frame
    if cmXmax - cmXmin < 1e-9
        cmXmin = cmXmin - 1
        cmXmax = cmXmax + 1
    endif
    if cmYmax - cmYmin < 1e-9
        cmYmin = cmYmin - 1
        cmYmax = cmYmax + 1
    endif
    cmPad = 0.06 * (cmXmax - cmXmin)
    cmXmin = cmXmin - cmPad
    cmXmax = cmXmax + cmPad
    cmPad = 0.06 * (cmYmax - cmYmin)
    cmYmin = cmYmin - cmPad
    cmYmax = cmYmax + cmPad

    Font size: 7
    Select inner viewport: 0.6, 3.7, 4.85, 7.40
    Axes: cmXmin, cmXmax, cmYmin, cmYmax
    Paint rectangle: "{0.985, 0.985, 0.985}", cmXmin, cmXmax, cmYmin, cmYmax
    for cmI from 1 to cmNEv
        selectObject: eventsTab
        cmX = Get value: cmI, "x"
        cmY = Get value: cmI, "y"
        Paint circle (mm): "{0.62, 0.62, 0.62}", cmX, cmY, 0.45
    endfor
    Select inner viewport: 0.6, 3.7, 4.85, 7.40
    Axes: cmXmin, cmXmax, cmYmin, cmYmax
    Line width: 1
    for cmLane from 1 to 2
        if cmLane = 1
            Colour: cmColL$
            cmOff = 0
        else
            Colour: cmColR$
            cmOff = cmN
        endif
        for cmI from 1 to cmN - 1
            selectObject: stepsTab
            cmX = Get value: cmI + cmOff, "x"
            cmY = Get value: cmI + cmOff, "y"
            cmX2 = Get value: cmI + cmOff + 1, "x"
            cmY2 = Get value: cmI + cmOff + 1, "y"
            Draw line: cmX, cmY, cmX2, cmY2
        endfor
    endfor
    Line width: 2
    for cmLane from 1 to 2
        if cmLane = 1
            cmCol$ = cmColL$
            cmOff = 0
        else
            cmCol$ = cmColR$
            cmOff = cmN
        endif
        selectObject: stepsTab
        cmX = Get value: 1 + cmOff, "x"
        cmY = Get value: 1 + cmOff, "y"
        Colour: cmCol$
        Draw circle (mm): cmX, cmY, 1.6
        cmX = Get value: cmN + cmOff, "x"
        cmY = Get value: cmN + cmOff, "y"
        Paint circle (mm): cmCol$, cmX, cmY, 1.3
    endfor
    Line width: 1
    Colour: "Black"
    cmNConv = 0
    for cmI from 1 to cmNT
        selectObject: timeTab
        cmCv = Get value: cmI, "conv"
        if cmCv = 1
            cmX = Get value: cmI, "xL"
            cmY = Get value: cmI, "yL"
            cmX2 = Get value: cmI, "xR"
            cmY2 = Get value: cmI, "yR"
            Draw circle (mm): (cmX + cmX2) / 2, (cmY + cmY2) / 2, 1.1
            Paint circle (mm): "Black", (cmX + cmX2) / 2, (cmY + cmY2) / 2, 0.35
            cmNConv = cmNConv + 1
        endif
    endfor
    Font size: 6
    Select inner viewport: 0.6, 3.7, 4.85, 7.40
    Axes: 0, 1, 0, 1
    Colour: cmColL$
    Text: 0.03, "left", 0.95, "half", "##L voice##"
    Colour: cmColR$
    Text: 0.03, "left", 0.89, "half", "##R voice##"
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0.03, "left", 0.83, "half", "grey = source events"
    Font size: 7
    Select inner viewport: 0.6, 3.7, 4.85, 7.40
    Axes: cmXmin, cmXmax, cmYmin, cmYmax
    Colour: "Black"
    Draw inner box
    @cmNice: cmXmax - cmXmin, 5
    Marks bottom every: 1, cmNice.step, "yes", "yes", "no"
    @cmNice: cmYmax - cmYmin, 5
    Marks left every: 1, cmNice.step, "yes", "yes", "no"
    Text bottom: "yes", "PC1 (" + pcaEv1Stat$ + " of variance)"
    Text left: "yes", "PC2 (" + pcaEv2Stat$ + ")"
    Text top: "no", "##C## Latent paths (PCA): ring start, dot end, black ring meeting (" + string$(cmNConv) + ")"

    # ---------------- D: SEPARATION + OVERLAP ----------------
    cmSmax = 0
    for cmI from 1 to cmNT
        selectObject: timeTab
        cmS = Get value: cmI, "sep"
        cmS2 = Get value: cmI, "target"
        cmSmax = max(cmSmax, cmS)
        if navigation_mode = 4
            cmSmax = max(cmSmax, cmS2)
        endif
    endfor
    if cmSmax <= 0
        cmSmax = 1
    endif
    cmSmax = cmSmax * 1.1
    Font size: 7
    Select inner viewport: 4.5, 7.7, 4.85, 5.50
    Axes: 0, cmT, 0, cmSmax
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, cmT, 0, cmSmax
    Select inner viewport: 4.5, 7.7, 4.85, 5.50
    Axes: 0, cmT, 0, cmSmax
    for cmPass from 1 to 2
        if cmPass = 1
            cmCol$ = "Black"
            cmCol$ = "{0.10, 0.10, 0.10}"
            Line width: 1.5
            Solid line
            cmCname$ = "sep"
        else
            cmCol$ = "{0.45, 0.45, 0.45}"
            Line width: 1
            Dashed line
            cmCname$ = "target"
        endif
        if cmPass = 1 or navigation_mode = 4
            Colour: cmCol$
            # exact step function over the sounding intervals
            for cmI from 1 to cmNT
                selectObject: timeTab
                cmA = Get value: cmI, "t0"
                cmB = Get value: cmI, "t1"
                cmS = Get value: cmI, cmCname$
                Draw line: cmA, cmS, cmB, cmS
                if cmI < cmNT
                    cmS2 = Get value: cmI + 1, cmCname$
                    Draw line: cmB, cmS, cmB, cmS2
                endif
            endfor
        endif
    endfor
    Solid line
    Line width: 1
    Font size: 7
    Select inner viewport: 4.5, 7.7, 4.85, 5.50
    Axes: 0, cmT, 0, cmSmax
    Colour: "Black"
    Draw inner box
    @cmNice: cmSmax, 3
    Marks left every: 1, cmNice.step, "yes", "yes", "no"
    Marks bottom every: 1, cmTStep, "no", "yes", "no"
    Text left: "yes", "Sep"
    if navigation_mode = 4
        Text top: "no", "##D## Separation of the sounding voices (dashed = target)"
    else
        Text top: "no", "##D## Separation of the sounding voices"
    endif

    Font size: 7
    Select inner viewport: 4.5, 7.7, 5.75, 6.15
    Axes: 0, cmT, 0, 1
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, cmT, 0, 1
    Select inner viewport: 4.5, 7.7, 5.75, 6.15
    Axes: 0, cmT, 0, 1
    Colour: "{0.45, 0.25, 0.60}"
    Line width: 1.5
    for cmI from 1 to cmNT
        selectObject: timeTab
        cmA = Get value: cmI, "t0"
        cmB = Get value: cmI, "t1"
        cmS = Get value: cmI, "overlap"
        Draw line: cmA, cmS, cmB, cmS
        if cmI < cmNT
            cmS2 = Get value: cmI + 1, "overlap"
            Draw line: cmB, cmS, cmB, cmS2
        endif
    endfor
    Line width: 1
    Font size: 7
    Select inner viewport: 4.5, 7.7, 5.75, 6.15
    Axes: 0, cmT, 0, 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, cmTStep, "no", "yes", "no"
    Text left: "yes", "Ovl"
    Text top: "no", "Shared material of the sounding mixes"

    # ---------------- E: L / R WAVEFORMS ----------------
    selectObject: outSound
    cmWL = Extract one channel: 1
    cmMx = Get maximum: 0, 0, "Sinc70"
    cmMn = Get minimum: 0, 0, "Sinc70"
    cmPk = max(abs(cmMx), abs(cmMn))
    selectObject: outSound
    cmWR = Extract one channel: 2
    cmMx = Get maximum: 0, 0, "Sinc70"
    cmMn = Get minimum: 0, 0, "Sinc70"
    cmPk = max(cmPk, max(abs(cmMx), abs(cmMn)))
    if cmPk < 0.001
        cmPk = 1
    endif
    cmPk = cmPk * 1.05
    for cmLane from 1 to 2
        if cmLane = 1
            cmY0 = 6.42
            cmY1 = 6.86
            cmCol$ = cmColL$
            selectObject: cmWL
        else
            cmY0 = 6.92
            cmY1 = 7.36
            cmCol$ = cmColR$
            selectObject: cmWR
        endif
        Font size: 7
        Select inner viewport: 4.5, 7.7, cmY0, cmY1
        Colour: cmCol$
        Draw: 0, 0, -cmPk, cmPk, "no", "Curve"
        Font size: 7
        Select inner viewport: 4.5, 7.7, cmY0, cmY1
        Axes: 0, cmT, -cmPk, cmPk
        Colour: "Black"
        Draw inner box
        Font size: 6
        Select inner viewport: 4.5, 7.7, cmY0, cmY1
        Axes: 0, 1, 0, 1
        if cmLane = 1
            Text: -0.012, "right", 0.5, "half", "L"
        else
            Text: -0.012, "right", 0.5, "half", "R"
        endif
        Font size: 7
        Select inner viewport: 4.5, 7.7, cmY0, cmY1
        Axes: 0, cmT, -cmPk, cmPk
        if cmLane = 1
            Marks bottom every: 1, cmTStep, "no", "yes", "no"
            Text top: "no", "##E## Output L / R, one amplitude scale (+-" + fixed$(cmPk, 2) + ")"
        else
            Marks bottom every: 1, cmTStep, "yes", "yes", "no"
            Text bottom: "yes", "Output time (s)"
        endif
    endfor
    removeObject: cmWL, cmWR

    # ---------------- F: SUMMARY ----------------
    if target_duration > 0
        cmDurTxt$ = fixed$(target_duration, 3) + " s target"
    else
        cmDurTxt$ = fixed$(dur, 3) + " s source"
    endif
    if navigation_mode = 3
        cmCompTxt$ = fixed$(competition_strength, 2) + " (lambda " + lambdaStat$ + ", adjustment TV " + compAdjStat$ + ")"
    else
        cmCompTxt$ = fixed$(competition_strength, 2) + " (not used in this mode)"
    endif
    @cmSafe: routingStat$
    cmRout$ = cmSafe.r$
    @cmSafe: compositeName$
    cmOutName$ = cmSafe.r$
    cmL1$ = "##" + presetName$ + "##  " + navLabel$
        ... + "  |  Events " + string$(cmNEv)
        ... + "  |  Steps " + string$(cmN) + " per voice"
        ... + "  |  z " + string$(latent_size) + ", heads " + attnHeadsStat$
        ... + "  |  Duration " + fixed$(cmT, 3) + " s = " + cmDurTxt$ + " x Duration scale " + fixed$(duration_scale, 2)
    cmL2$ = "Divergence " + fixed$(trajectory_divergence, 2)
        ... + "  |  Competition " + cmCompTxt$
        ... + "  |  Unique dominant L " + uniqLStat$ + " / R " + uniqRStat$ + " of " + string$(cmNEv)
        ... + "  |  Same dominant sounding together " + sharedDomStat$ + " of the time"
    @cmSafe: timelineStat$
    cmL3$ = "Timeline " + cmSafe.r$ + "  |  Overlap (time-weighted) " + overlapStat$
        ... + "  |  Separation mean " + sepMeanStat$ + " (begin " + sepBeginStat$ + ", peak region " + sepPeakStat$ + ", end " + sepEndStat$ + ")"
        ... + "  |  Routing " + cmRout$ + " (L <- " + srcLStat$ + ", R <- " + srcRStat$ + ")"
    cmL4$ = "Peak L/R " + peakLStat$ + " / " + peakRStat$
        ... + "  |  RMS L/R " + rmsLStat$ + " / " + rmsRStat$
        ... + "  |  L/R correlation " + lrCorrStat$
        ... + "  |  Fit median " + fitMedStat$ + ", windows " + windowedStat$ + ", coverage L/R " + covLStat$ + " / " + covRStat$
        ... + "  |  Output: " + cmOutName$
    Font size: 6
    Select inner viewport: 0.6, 7.7, 8.05, 8.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Select inner viewport: 0.6, 7.7, 8.05, 8.85
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.01, "left", 0.82, "half", cmL1$
    Text: 0.01, "left", 0.60, "half", cmL2$
    Text: 0.01, "left", 0.38, "half", cmL3$
    Text: 0.01, "left", 0.16, "half", cmL4$
    Select inner viewport: 0.6, 7.7, 8.05, 8.85
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1
    # whole canvas selected, so Save as PNG / Copy export all panels
    Select outer viewport: 0, 8, 0, 8.95
endproc
