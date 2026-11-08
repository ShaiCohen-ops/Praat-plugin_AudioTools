# ============================================================
# Praat AudioTools - TimeLine_Composer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Non-destructive, corpus-based composition. Organises existing
#   recordings from one to five folders into a new temporal, dynamic and
#   spatial form of a given total duration, with intentional absolute
#   silence. The recordings are never cut, stretched, copied, converted
#   or modified: each event plays one whole source file, with only short
#   click-free fades, a gain and a spatial position.
#
#   v2.0: the main choice is a COMPOSITION PRESET - a whole strategy,
#   not one effect - plus the duration and a Compositional intensity.
#   Edit composition controls shows every value the preset set, for
#   editing; Custom sets them all by hand.
#
#   Two stages, kept apart:
#     1. PLAN   - an event timeline is computed from the catalog and the
#                 settings and saved as text (TSV). No audio is loaded.
#     2. RENDER - only on request; sources are read through LongSound,
#                 one event segment at a time, never the whole library.
#
# Architecture:
#   Catalog    Folder scan through LongSound headers (duration, sample
#              rate, channels) - no sample data is read. Saved as
#              TimeLine_catalog.tsv in the output folder and reusable.
#   Conductor  A global curve c(x) in [0,1] (x = time / duration) with a
#              climax. It drives event density and overlap, event gain
#              and spatial width DURING PLANNING - it is not a gain
#              envelope laid over a finished mix.
#   Silence    Absolute silences are global (all layers) and planned
#              before the events: count, lengths and positions come from
#              the mode, amount, min/max and placement. Each phrase
#              between two silences has a hard deadline, and every event
#              in it must END by that deadline, so the following silence
#              is genuine (no tails). Gaps that occur inside phrases are
#              measured and taken off the remaining silence budget.
#   Continuity Inter-onset gaps are not absolute silence. The lead layer
#              of each phrase stays continuous (it prefers a sound long
#              enough to reach its next onset, else the onset moves to its
#              tail), and a repair pass closes any hole left in the union
#              of layers. Only holes no unused source can fill remain;
#              they are measured and reported as material shortage.
#   Material   Expected entrances per layer are checked against files x
#              max repetitions; if short, density is scaled uniformly, and
#              use is paced along the conductor's density curve so that
#              material is left for the climax.
#   Selection  Source DURATION is chosen by the temporal preset (short to
#              long, arch, ...) independently of ONSET SPACING, which
#              comes from the density, overlap and conductor.
#   Placement  (v2.1) Spatial BEHAVIOUR (the space preset: how space
#              changes over the form) is separate from PLACEMENT (where
#              each source group sits). Every layer - or, in a combined
#              pool, every folder - has a region: a position (-1 left ...
#              +1 right) and a spread. Spatial movement m (0-1) says how
#              far the behaviour may take sounds out of their regions:
#              p = (1 - m) (H + S q) + m q, with q the behaviour on the
#              whole field. m = 0: fixed regions, the behaviour acts
#              inside each; m = 1: whole field (v2.0, the default).
#              Layer-based space is always regional. Edit spatial
#              layout sets m and each region (one per stream when a
#              folder is split into streams).
#   Space      Equal-power panning on a position p in [-1, 1]. Stereo
#              out: lay/R. Multichannel out (4 or 8): p runs across the
#              channels in order (ch1 = -1 ... chN = +1), equal-power
#              between neighbours - real channel-based distribution.
#              Stereo sources keep their image as two narrowed points
#              (never summed to mono, so no lay+R cancellation).
#   Render     Chunked: each event segment is read from disk, faded,
#              resampled if needed, and added into the output with
#              per-channel gains. Below the memory budget the whole
#              output is held once and saved as 24-bit WAV; above it the
#              output is rendered in 30 s chunks, each saved to a 16-bit
#              scratch file, and the chunks are joined into one 16-bit
#              WAV (multi-LongSound save); the scratch files are then
#              deleted. Peak disk use is about twice the output size.
#
# Reproducibility:
#   The saved plan is the exact, portable record: "Render a saved plan"
#   rebuilds the audio from it on any Praat version (6.4.06 vs 7.0:
#   within 3 LSB at 24 bit, measured). Rebuilding the PLAN from the seed
#   and settings is byte-identical on the same Praat build, but not
#   guaranteed across builds - floating-point details of different
#   binaries can change a borderline choice (seen between 6.4.06 and 7.0).
#
# Output (v1.1 - the Praat AudioTools workflow):
#   Create in Praat (default)  render into a Sound object, play it, keep
#                              it selected. No folder, no files.
#   Plan only                  the timeline as Table objects in Praat
#                              (plan + settings); no audio, no playback.
#   Export composition         as Create in Praat, then also save the
#                              audio (mix, stems) to a folder you choose.
#   Render a saved plan        a *_plan.tsv file, or the two plan Tables
#                              left by Plan only (select them first).
#   Files are written only when asked for (export, Save plan, Save
#   catalog) or when the output exceeds the memory budget - then it is
#   streamed to a 16-bit WAV, opened as a LongSound, and the file is
#   kept, because the LongSound reads from it. Existing files are never
#   overwritten without confirmation.
#   Saved files:  <base>_plan.tsv  <base>_settings.tsv  <base>_<mix>.wav
#                 <base>_stem<k>_<library>.wav   TimeLine_catalog.tsv
#
# Composition presets (v2.0):
#   Emergence            short, quiet, sparse, central -> longer, louder,
#                        wider (one pool, crescendo; silences where the
#                        conductor is low, so they gather early)
#   Accumulation         layers enter one after another (first 45 % of
#                        the form), entrances and overlaps thicken to the
#                        end; no absolute silence
#   Breathing Form       duration waves in phase with the conductor's 4
#                        waves; silences in the troughs; width follows
#                        the conductor (Breathing space)
#   Climax & Rupture     arch durations, late climax (84 %); the grand
#                        pause starts AT the peak and takes 3/4 of the
#                        silence budget; quiet epilogue
#   Spatial Counterpoint independent layers, each with its own temporal
#                        shape, pace and region of space
#   Fragmentation        long -> short, decrescendo; many short silences
#                        that gather and lengthen toward the end
#   Controlled Chaos     loose duration order, extreme overlap, a
#                        conductor stepped on 16 segments, random
#                        silence positions
#   Custom               the v1.1 defaults; every control by hand
#   One folder: Accumulation and Spatial Counterpoint split it into 3
#   independent streams that share its sources (and their repetition
#   limit); with 2-5 folders each folder is a layer.
#   Compositional intensity (presets only; 50 % = as designed): scales
#   density (x0.66..x1.52), overlap (+/-0.2), the conductor's density
#   and spatial influence (x0.5..x1.5) and the shaping strictness
#   together. Dynamics move only gently: dynamics influence and range
#   x0.9..x1.1 each. It never changes the duration or the planned
#   silences.
#   Dynamics (conductor depth = influence x range, at 50 %):
#   Emergence, Accumulation, Breathing Form 0.50 x 8 dB = 4 dB;
#   Climax & Rupture 0.55 x 8 = 4.4 dB; Spatial Counterpoint 0.45 x 6
#   = 2.7 dB; Fragmentation 0.45 x 8 = 3.6 dB; Controlled Chaos
#   0.55 x 10 = 5.5 dB. Form comes mainly from the relations between
#   sounds; deeper contrasts remain available by hand.
#
# Changelog v2.3 (2026) - dynamics recalibration:
#   - Presets: restrained conductor dynamics (see "Dynamics" above);
#     previously 12-27 dB deep, now 2.7-5.5 dB at 50 % intensity.
#   - Intensity scales dynamics influence and range by (1 + 0.2 di)
#     each (was 1.0 and 0.6); other intensity dimensions unchanged.
#   - Event timeline unchanged: only the conductor's share of the
#     event gains differs (verified).
#
# Changelog v2.2 (2026) - dynamics in the composition controls:
#   - UI: Dynamic range (dB) moved from Edit details to Edit composition
#     controls, beside the conductor curve and the climax position - the
#     three dynamic decisions in one place. It can be changed there
#     without touching the other values (Compositional intensity is
#     applied before the dialog, which shows the resulting value).
#   - Report: the deepest conductor attenuation, influence x range, and
#     0 dB at the climax.
#   - Plans identical to v2.1 (verified).
#
# Changelog v2.1 (2026) - spatial placement:
#   - NEW: Edit spatial layout (main form): Spatial movement + a
#     position and a spread for every layer / folder / stream. The
#     behaviour now acts inside the regions the user sets (m < 1).
#   - FIX: positions edited in Edit layers had no effect unless the
#     space preset was Layer-based. They moved to Edit spatial layout,
#     where every value acts (m < 1 or Layer-based); with m = 1 the
#     dialog says the positions are inactive, and the report warns if
#     they were changed.
#   - FIX: with one folder split into streams, the automatic stream
#     positions overrode the user's. They are now only defaults, shown
#     per stream and editable.
#   - NEW: Stream sources: shared pool, or split the files so each file
#     belongs to one stream (a stream keeps its own sounds - and so its
#     position).
#   - Figure: region lines in the space panel; a combined pool is
#     coloured by folder there. Report lists the regions.
#   - Default (no dialog): identical plans to v2.0 (verified, 8 presets).
#   - Scripted calls: one more boolean in the main form.
#
# Changelog v2.0 (2026) - compositional strategies:
#   - NEW: Composition preset (7 strategies + Custom) and Compositional
#     intensity in the main form; the individual controls moved to the
#     Edit composition controls dialog, pre-filled by the preset.
#   - NEW engine options used by the presets: Breathing space (width
#     follows the conductor), duration waves in phase with the conductor
#     waves, a stepped conductor, the grand pause at the peak, staggered
#     layer entries, several streams from one folder, a per-layer region
#     for Layer-based space in Independent layers.
#   - UI: "Folders to browse (1-5)" (default 1) and "Folder paths
#     (optional; separated by ;)" - paths, when given, decide the folders.
#   - Custom reproduces v1.2 exactly (verified sample-identical). Plans
#     saved by v1.x render unchanged.
#   - BREAKING for scripted calls: the main form's fields changed.
#
# Changelog v1.2 (2026) - clean-up and file safety:
#   - Output-file registry: every file is registered before it is
#     written, with its state (not written / written, not committed /
#     committed). One exit path (@fail) removes every temporary object
#     and deletes only files THIS run wrote and did not commit. Files that
#     existed before the run, and files a kept LongSound reads, are never
#     deleted.
#   - Plan + settings form one group (both kept or both deleted); an
#     export (mix + all stems) is one group.
#   - Confirmed overwrite: the new file is written beside the target
#     ("__tl_new"), verified, and only then copied over it.
#   - Verification reads real samples back (not only the header): a
#     file truncated by a full disk is detected and deleted.
#   - All object-creating commands that can fail (open, extract,
#     resample, create buffer, read table) are checked; "every source is
#     longer than the target" now exits through @fail too.
#   - Streamed render: chunks go to scratch files that are joined at the
#     end; "Append to existing sound file" is no longer used, because on a
#     full disk it crashes Praat itself (6.4.06 and 7.0).
#   Limits: a Praat crash, or pressing Stop, ends the script without any
#   clean-up; Praat has no rename, so a replace is a verified copy.
#
# Changelog v1.1 (2026):
#   - WORKFLOW: the default result is a Sound object in Praat that plays
#     at once and stays selected. No output folder is needed; plan,
#     settings and catalog are saved only on request.
#   - NEW: Library Loudness Balance (Off / Gentle / Full / Manual) from a
#     sampled active-signal level per file and a median per library;
#     optional bounded per-file leveling. Every gain component is stored
#     per event in the plan.
#   - FIX: Overlap now sets onset spacing relative to the duration of the
#     sound just placed (blended with the density spacing), not only a
#     voice cap. Mean and maximum polyphony are reported.
#   - NEW: Ending silence; the report separates requested duration, last
#     audible end, planned ending silence and any unintended empty tail.
#   - FIX: upper-case file extensions (.WAV .MP3 .FLAC .AIF .AIFF) were
#     skipped as non-audio: the lower-casing regex had been corrupted to
#     "\lay\1". Replaced by a plain letter-by-letter lower-casing.
#   - NEW: multichannel output is kept as the result; playback uses a
#     temporary stereo audition mix, removed afterwards.
#   - Clean-up: every temporary object is removed on success and on the
#     script's own error exits; user objects are never touched.
#   - v1.0 behaviour kept: presets, layers, silence engine, conductor,
#     continuity repair, material pacing, deterministic plans, figure.
# ============================================================

form TimeLine Composer
    comment === SOURCES (folder dialogs open after OK) ===
    integer Folders_to_browse_(1-5) 1
    sentence Folder_paths_(optional;_separated_by_;)
    comment === COMPOSITION ===
    optionmenu Composition_preset: 1
        option: "Emergence"
        option: "Accumulation"
        option: "Breathing Form"
        option: "Climax & Rupture"
        option: "Spatial Counterpoint"
        option: "Fragmentation"
        option: "Controlled Chaos"
        option: "Custom (set every control yourself)"
    positive Target_duration_(s) 180
    real Compositional_intensity_(%) 50
    integer Random_seed 1
    boolean Edit_composition_controls 0
    optionmenu Library_balance: 2
        option: "Off (original source levels)"
        option: "Gentle (half the difference, max 6 dB)"
        option: "Full (toward a common level)"
        option: "Manual (Gain_dB per library only)"
    comment === OUTPUT ===
    optionmenu Output: 1
        option: "Create in Praat (render, play, keep the Sound)"
        option: "Plan only (timeline Tables, no audio)"
        option: "Export composition (also save audio files)"
        option: "Render a saved plan (file or selected Tables)"
    optionmenu Channels: 1
        option: "Stereo"
        option: "4 channels"
        option: "8 channels"
    boolean Layer_stems 0
    boolean Edit_details 0
    boolean Edit_layers 0
    boolean Edit_spatial_layout 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

stopwatch
tScan = 0
tPlan = 0
tRender = 0
tViz = 0

# The selection at start (for Render a saved plan from Tables).
nSelTables = numberOfSelected("Table")
for k from 1 to nSelTables
    selTable[k] = selected("Table", k)
endfor

# ============================================================
# DETAIL DEFAULTS (second dialogs show and edit these)
# ============================================================
duration_order_strictness = 0.7
duration_preference = 0.5
randomness = 0.4
max_repetitions = 3
min_silence = 1.5
max_silence = 6
silence_placement = 1
ending_silence = 0
dynamics_influence = 0.7
density_influence = 0.7
spatial_influence = 0.6
dynamic_range = 24
max_correction = 12
per_file_leveling = 0
file_level_limit = 4
output_sample_rate = 0
event_fade_in = 10
event_fade_out = 40
final_fade = 3
normalize = 1
peak_dBFS = -1
memory_budget = 1024
existing_files = 1
catalog_mode = 1
catalog_file$ = ""
save_plan = 0
save_catalog = 0
output_folder$ = ""
plan_file$ = ""

# ============================================================
# COMPOSITION PRESETS (v2.0)
# A preset is a whole compositional strategy: it sets organisation,
# temporal shape, density, overlap, silence, conductor, space and the
# influence depths together. It never changes the target duration.
# The values below are the preset at 50 % intensity. Every value can
# still be edited (Edit composition controls); Custom starts from the
# v1.1 defaults and does not use the intensity.
# ============================================================
cpName$[1] = "Emergence"
cpName$[2] = "Accumulation"
cpName$[3] = "Breathing Form"
cpName$[4] = "Climax & Rupture"
cpName$[5] = "Spatial Counterpoint"
cpName$[6] = "Fragmentation"
cpName$[7] = "Controlled Chaos"
cpName$[8] = "Custom"
cpDesc$[1] = "Short, quiet, sparse sounds in the centre; durations, density and width grow."
cpDesc$[2] = "Entrances crowd together, overlaps thicken, layers pile up to a loud peak."
cpDesc$[3] = "Waves of activity and silence: density, durations and space expand and contract."
cpDesc$[4] = "Long preparation, intense build-up to a late climax, sudden silence, short epilogue."
cpDesc$[5] = "Independent layers in separate regions of space, each with its own shape."
cpDesc$[6] = "From long sounds and continuous textures to short, scattered fragments."
cpDesc$[7] = "Unpredictable durations, extreme overlaps, abrupt density changes, irregular silences."
cpDesc$[8] = "Every control set by hand (starts from the v1.1 defaults)."
composition_preset = max(1, min(8, composition_preset))
compositional_intensity = max(0, min(100, compositional_intensity))

# v2.1 spatial placement: 1 = the behaviour uses the whole field (v2.0)
spatial_movement = 1

# strategy flags (engine features a preset can switch on)
waveCycles = 3
ruptureMode = 0
condJag = 0
streamsWanted = 0
layerStagger = 0
counterpoint = 0

# v1.1 defaults (Custom)
organization = 2
temporal_preset = 3
event_density = 10
overlap = 0.5
silence_mode = 2
silence_amount = 12
conductor_preset = 4
climax_position = 75
spatial_preset = 4

cp = composition_preset
if cp = 1
    # Emergence: one pool ranked short -> long, crescendo, from the centre
    organization = 1
    temporal_preset = 1
    event_density = 8
    overlap = 0.4
    silence_mode = 2
    silence_amount = 14
    silence_placement = 7
    min_silence = 0.8
    max_silence = 3.5
    conductor_preset = 1
    climax_position = 90
    spatial_preset = 4
    duration_order_strictness = 0.8
    randomness = 0.3
    dynamics_influence = 0.5
    density_influence = 0.8
    spatial_influence = 0.7
    dynamic_range = 8
elsif cp = 2
    # Accumulation: layers enter one after another and thicken
    organization = 2
    streamsWanted = 3
    layerStagger = 0.45
    temporal_preset = 6
    event_density = 8
    overlap = 0.6
    silence_mode = 1
    silence_amount = 0
    conductor_preset = 1
    climax_position = 90
    spatial_preset = 4
    duration_order_strictness = 0.5
    randomness = 0.5
    dynamics_influence = 0.5
    density_influence = 1
    spatial_influence = 0.6
    dynamic_range = 8
elsif cp = 3
    # Breathing Form: duration waves in phase with the conductor waves,
    # silences in the troughs, width follows the conductor
    organization = 2
    temporal_preset = 5
    waveCycles = 4
    event_density = 10
    overlap = 0.5
    silence_mode = 2
    silence_amount = 15
    silence_placement = 7
    min_silence = 1.5
    max_silence = 5
    conductor_preset = 6
    climax_position = 60
    spatial_preset = 8
    duration_order_strictness = 0.7
    randomness = 0.35
    dynamics_influence = 0.5
    density_influence = 0.8
    spatial_influence = 0.9
    dynamic_range = 8
elsif cp = 4
    # Climax & Rupture: the grand pause starts AT the peak
    organization = 2
    temporal_preset = 3
    event_density = 10
    overlap = 0.55
    silence_mode = 4
    silence_amount = 6
    silence_placement = 6
    ruptureMode = 1
    min_silence = 1
    max_silence = 8
    conductor_preset = 4
    climax_position = 84
    spatial_preset = 4
    duration_order_strictness = 0.75
    randomness = 0.3
    dynamics_influence = 0.55
    density_influence = 0.9
    spatial_influence = 0.7
    dynamic_range = 8
elsif cp = 5
    # Spatial Counterpoint: each layer has its own shape and region
    organization = 2
    streamsWanted = 3
    counterpoint = 1
    temporal_preset = 3
    event_density = 7
    overlap = 0.45
    silence_mode = 3
    silence_amount = 10
    silence_placement = 3
    conductor_preset = 3
    climax_position = 55
    spatial_preset = 7
    duration_order_strictness = 0.75
    randomness = 0.3
    dynamics_influence = 0.45
    density_influence = 0.6
    spatial_influence = 0.4
    dynamic_range = 6
elsif cp = 6
    # Fragmentation: long -> short, decrescendo, silences cluster and
    # lengthen where the conductor is low (late)
    organization = 1
    temporal_preset = 2
    event_density = 10
    overlap = 0.6
    silence_mode = 2
    silence_amount = 18
    silence_placement = 7
    min_silence = 0.6
    max_silence = 3
    conductor_preset = 2
    climax_position = 10
    spatial_preset = 1
    duration_order_strictness = 0.8
    randomness = 0.4
    dynamics_influence = 0.45
    density_influence = 0.9
    spatial_influence = 0
    dynamic_range = 8
elsif cp = 7
    # Controlled Chaos: loose duration order, stepped conductor
    organization = 2
    temporal_preset = 6
    event_density = 14
    overlap = 0.85
    silence_mode = 4
    silence_amount = 10
    silence_placement = 2
    min_silence = 0.5
    max_silence = 6
    conductor_preset = 6
    condJag = 1
    climax_position = 50
    spatial_preset = 1
    duration_order_strictness = 0.15
    randomness = 0.95
    dynamics_influence = 0.55
    density_influence = 1
    spatial_influence = 0.5
    dynamic_range = 10
endif

# Compositional intensity: how far the preset is pushed (50 % = as
# designed). It scales density, overlap, the conductor's density and
# spatial influence and the shaping strictness together; it never
# changes the duration and never removes planned silences.
# Dynamics policy: musical form should come mainly from the relations
# between sounds (durations, density, overlap, silence, layers, space),
# not from attenuating the sounds themselves. The presets therefore
# use a restrained conductor depth (influence x range = 3-5.5 dB at
# 50 %), and intensity moves the two dynamic parameters only gently
# (each x0.9 at 0 %, x1.1 at 100 %; their product x0.81..x1.21). The
# event-gain formula is unchanged (evCondDb = influence x range x
# (c - 1)), and both values can still be set to anything by hand:
# Dynamic range in Edit composition controls, Dynamics influence in
# Edit details.
if cp < 8
    di = compositional_intensity / 100 - 0.5
    event_density = event_density * 2 ^ (1.2 * di)
    overlap = max(0, min(1, overlap + 0.4 * di))
    dynamics_influence = max(0, min(1, dynamics_influence * (1 + 0.2 * di)))
    density_influence = max(0, min(1, density_influence * (1 + 1.0 * di)))
    spatial_influence = max(0, min(1, spatial_influence * (1 + 1.0 * di)))
    dynamic_range = dynamic_range * (1 + 0.2 * di)
    if cp = 7
        # chaos: more intensity = less order
        duration_order_strictness = max(0, min(1, duration_order_strictness - 0.3 * di))
        randomness = max(0, min(1, randomness + 0.3 * di))
    else
        duration_order_strictness = max(0, min(1, duration_order_strictness + 0.3 * di))
        randomness = max(0, min(1, randomness - 0.3 * di))
    endif
endif

if (edit_composition_controls or cp = 8) and output <> 4
    beginPause: "TimeLine Composer - composition controls"
        comment: cpName$[cp] + ": " + cpDesc$[cp]
        if cp < 8
            comment: "Loaded from the preset at " + fixed$(compositional_intensity, 0) + " % intensity - every value can be changed."
        endif
        optionmenu: "Organization", organization
            option: "Combined pool (all folders = one collection)"
            option: "Independent layers (one layer per folder)"
        optionmenu: "Temporal_preset", temporal_preset
            option: "Short to long"
            option: "Long to short"
            option: "Arch (short-long-short)"
            option: "Inverted arch (long-short-long)"
            option: "Waves"
            option: "Controlled random"
        real: "Event_density", fixed$(event_density, 2)
        real: "Overlap", fixed$(overlap, 2)
        optionmenu: "Silence_mode", silence_mode
            option: "Continuous (no absolute silence)"
            option: "Breathing (many short silences)"
            option: "Structural (few long silences)"
            option: "Dramatic (grand pause at the climax)"
        real: "Silence_amount", fixed$(silence_amount, 1)
        optionmenu: "Conductor_preset", conductor_preset
            option: "Crescendo"
            option: "Decrescendo"
            option: "Arch"
            option: "Late climax"
            option: "Early climax"
            option: "Waves"
        real: "Climax_position", fixed$(climax_position, 1)
        real: "Dynamic_range_(dB)", fixed$(dynamic_range, 1)
        optionmenu: "Spatial_preset", spatial_preset
            option: "Random space"
            option: "Left to right"
            option: "Right to left"
            option: "Expanding space"
            option: "Contracting space"
            option: "Alternating sides"
            option: "Layer-based"
            option: "Breathing space (width follows the conductor)"
    clicked = endPause: "Cancel", "Continue", 2, 1
    if clicked = 1
        exitScript: "Cancelled: nothing was done."
    endif
    event_density = max(0.1, event_density)
    dynamic_range = max(0, dynamic_range)
endif

if edit_details
    beginPause: "TimeLine Composer - composition details"
        comment: "Source selection"
        real: "Duration_order_strictness", string$(duration_order_strictness)
        real: "Duration_preference", string$(duration_preference)
        real: "Randomness", string$(randomness)
        integer: "Max_repetitions", string$(max_repetitions)
        comment: "Silence (seconds); ending silence = deliberate silence before the end"
        positive: "Min_silence", string$(min_silence)
        positive: "Max_silence", string$(max_silence)
        optionmenu: "Silence_placement", silence_placement
            option: "Mode default"
            option: "Random"
            option: "Periodic"
            option: "Phrase-based"
            option: "Before climax"
            option: "After climax"
            option: "Controlled by the conductor"
        real: "Ending_silence", string$(ending_silence)
        comment: "Conductor influence (0-1); the dynamic range is in the composition controls"
        real: "Dynamics_influence", string$(dynamics_influence)
        real: "Density_influence", string$(density_influence)
        real: "Spatial_influence", string$(spatial_influence)
        comment: "Loudness: Full-balance limit (dB); optional bounded per-file leveling"
        positive: "Max_correction", string$(max_correction)
        boolean: "Per_file_leveling", per_file_leveling
        positive: "File_level_limit", string$(file_level_limit)
    endPause: "Continue", 1
    beginPause: "TimeLine Composer - render and files"
        comment: "Output sample rate (0 = most common source rate)"
        real: "Output_sample_rate", string$(output_sample_rate)
        comment: "Fades: event in/out (ms), end of composition (s)"
        real: "Event_fade_in", string$(event_fade_in)
        real: "Event_fade_out", string$(event_fade_out)
        real: "Final_fade", string$(final_fade)
        boolean: "Normalize", normalize
        real: "Peak_dBFS", string$(peak_dBFS)
        positive: "Memory_budget", string$(memory_budget)
        comment: "Files (only when asked for)"
        boolean: "Save_plan", save_plan
        boolean: "Save_catalog", save_catalog
        optionmenu: "Catalog_mode", catalog_mode
            option: "Analyse the folders"
            option: "Reuse a saved catalog (validated)"
        sentence: "Catalog_file", catalog_file$
        sentence: "Output_folder", output_folder$
        optionmenu: "Existing_files", existing_files
            option: "Add a number (never overwrite)"
            option: "Ask before overwriting"
        sentence: "Plan_file", plan_file$
    endPause: "Continue", 1
endif

# Output flags (v1.1)
rerender = 0
planOnly = 0
exportFiles = 0
if output = 2
    planOnly = 1
elsif output = 3
    exportFiles = 1
elsif output = 4
    rerender = 1
endif
wantMix = 1 - planOnly
wantStems = 0
if layer_stems and wantMix
    wantStems = 1
endif
if channels = 1
    nOutChWanted = 2
elsif channels = 2
    nOutChWanted = 4
else
    nOutChWanted = 8
endif
balName$[1] = "Off"
balName$[2] = "Gentle"
balName$[3] = "Full"
balName$[4] = "Manual"

# ---- clamp ----
folders_to_browse = max(1, min(5, folders_to_browse))
overlap = max(0, min(1, overlap))
silence_amount = max(0, min(80, silence_amount))
climax_position = max(2, min(98, climax_position))
duration_order_strictness = max(0, min(1, duration_order_strictness))
duration_preference = max(0, min(1, duration_preference))
randomness = max(0, min(1, randomness))
max_repetitions = max(1, max_repetitions)
dynamics_influence = max(0, min(1, dynamics_influence))
density_influence = max(0, min(1, density_influence))
spatial_influence = max(0, min(1, spatial_influence))
if min_silence > max_silence
    tmp = min_silence
    min_silence = max_silence
    max_silence = tmp
endif
event_fade_in = max(0, event_fade_in)
event_fade_out = max(0, event_fade_out)
final_fade = max(0, min(final_fade, target_duration / 4))
ending_silence = max(0, min(ending_silence, target_duration / 2))
max_correction = max(0, max_correction)
file_level_limit = max(0, file_level_limit)
if peak_dBFS > 0
    peak_dBFS = 0
endif
if silence_mode = 1
    silence_amount = 0
endif

# Names used in reports and the figure
tempName$[1] = "Short to long"
tempName$[2] = "Long to short"
tempName$[3] = "Arch"
tempName$[4] = "Inverted arch"
tempName$[5] = "Waves"
tempName$[6] = "Controlled random"
silName$[1] = "Continuous"
silName$[2] = "Breathing"
silName$[3] = "Structural"
silName$[4] = "Dramatic"
plcName$[1] = "Mode default"
plcName$[2] = "Random"
plcName$[3] = "Periodic"
plcName$[4] = "Phrase-based"
plcName$[5] = "Before climax"
plcName$[6] = "After climax"
plcName$[7] = "Conductor"
condName$[1] = "Crescendo"
condName$[2] = "Decrescendo"
condName$[3] = "Arch"
condName$[4] = "Late climax"
condName$[5] = "Early climax"
condName$[6] = "Waves"
spName$[1] = "Random space"
spName$[2] = "Left to right"
spName$[3] = "Right to left"
spName$[4] = "Expanding space"
spName$[5] = "Contracting space"
spName$[6] = "Alternating sides"
spName$[7] = "Layer-based"
spName$[8] = "Breathing space"
orgName$[1] = "Combined pool"
orgName$[2] = "Independent layers"

layerR[1] = 0.12
layerG[1] = 0.47
layerB[1] = 0.71
layerR[2] = 1.00
layerG[2] = 0.50
layerB[2] = 0.05
layerR[3] = 0.17
layerG[3] = 0.63
layerB[3] = 0.17
layerR[4] = 0.84
layerG[4] = 0.15
layerB[4] = 0.16
layerR[5] = 0.58
layerG[5] = 0.40
layerB[5] = 0.74

warnCount = 0

# ============================================================
# PROCEDURES
# ============================================================
procedure warn: .msg$
    warnCount = warnCount + 1
    warn$[warnCount] = .msg$
endproc

procedure trimText: .s$
    .s$ = replace_regex$(.s$, "^[ \t]+", "", 1)
    .s$ = replace_regex$(.s$, "[ \t]+$", "", 1)
    .s$ = replace_regex$(.s$, "^""", "", 1)
    .s$ = replace_regex$(.s$, """$", "", 1)
    .s$ = replace_regex$(.s$, "[/\\]+$", "", 1)
    trimText.out$ = .s$
endproc

procedure baseName: .p$
    baseName.out$ = replace_regex$(.p$, "^.*[/\\]", "", 1)
endproc

procedure safeText: .s$
    .s$ = replace$(.s$, "\", "\bs", 0)
    .s$ = replace$(.s$, "_", "\_ ", 0)
    .s$ = replace$(.s$, "%", "\% ", 0)
    .s$ = replace$(.s$, "#", "\# ", 0)
    .s$ = replace$(.s$, "^", "\^ ", 0)
    safeText.out$ = .s$
endproc

# Lower-case without regular-expression case escapes (portable).
procedure toLower: .s$
    .u$ = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    .l$ = "abcdefghijklmnopqrstuvwxyz"
    for .k from 1 to 26
        .s$ = replace$(.s$, mid$(.u$, .k, 1), mid$(.l$, .k, 1), 0)
    endfor
    toLower.out$ = .s$
endproc

# Level of one source, from the LongSound .ls (no full load).
#   Files up to 12 s: the whole file. Longer files: six 2-s sections,
#   centred at 1/12, 3/12 ... 11/12 of the duration.
#   Every section is cut in 50-ms blocks. Active blocks are those above
#   max(-60 dBFS, loudest block - 40 dB). Active RMS = power mean of the
#   active blocks. Reliable = at least 0.1 s active and a loudest block
#   above -60 dBFS (near-silent files get no automatic correction).
procedure measureLevel: .ls, .d
    if .d <= 12
        .nSec = 1
        .secLen = .d
    else
        .nSec = 6
        .secLen = 2
    endif
    .nBlk = 0
    .sumAll = 0
    .lenAll = 0
    .peak = 0
    measureLevel.nch = 0
    for .k from 1 to .nSec
        if .nSec = 1
            .a = 0
            .b = .d
        else
            .c = (.k - 0.5) / .nSec * .d
            .a = max(0, .c - .secLen / 2)
            .b = min(.d, .c + .secLen / 2)
        endif
        selectObject: .ls
        nocheck Extract part: .a, .b, "no"
        @gotNew: "Sound", .ls
        .part = gotNew.id
        if .part = 0
            @fail: "Cannot read a section of a source while measuring its level (memory?)."
        endif
        @addTemp: .part
        measureLevel.nch = Get number of channels
        .len = Get total duration
        .pk = Get absolute extremum: 0, 0, "None"
        .peak = max(.peak, .pk)
        .nb = max(1, floor(.len / 0.05))
        .bl = .len / .nb
        for .q from 1 to .nb
            .r = Get root-mean-square: (.q - 1) * .bl, .q * .bl
            if .r = undefined
                .r = 0
            endif
            .nBlk = .nBlk + 1
            mlBlk[.nBlk] = .r
            .sumAll = .sumAll + .r * .r * .bl
            .lenAll = .lenAll + .bl
        endfor
        removeObject: .part
        @dropTemp: .part
    endfor
    .maxB = 0
    for .q from 1 to .nBlk
        .maxB = max(.maxB, mlBlk[.q])
    endfor
    .thr = max(0.001, .maxB * 0.01)
    .sumAct = 0
    .nAct = 0
    for .q from 1 to .nBlk
        if mlBlk[.q] >= .thr
            .sumAct = .sumAct + mlBlk[.q] * mlBlk[.q]
            .nAct = .nAct + 1
        endif
    endfor
    .blk = .lenAll / max(1, .nBlk)
    measureLevel.actS = .nAct * .blk
    measureLevel.rmsDb = 20 * log10(max(1e-10, sqrt(.sumAll / max(1e-12, .lenAll))))
    measureLevel.peakDb = 20 * log10(max(1e-10, .peak))
    if .nAct > 0
        measureLevel.actDb = 20 * log10(max(1e-10, sqrt(.sumAct / .nAct)))
    else
        measureLevel.actDb = -200
    endif
    measureLevel.reliable = 0
    if measureLevel.actS >= 0.1 and .maxB >= 0.001
        measureLevel.reliable = 1
    endif
endproc

# Median of medBuf[1 .. .n] (sorted copy; medBuf is left as is).
procedure median: .n
    for .i from 1 to .n
        mdTmp[.i] = medBuf[.i]
    endfor
    for .i from 2 to .n
        .a = mdTmp[.i]
        .j = .i - 1
        .mv = 1
        while .mv = 1
            if .j < 1
                .mv = 0
            elsif mdTmp[.j] > .a
                mdTmp[.j + 1] = mdTmp[.j]
                .j = .j - 1
            else
                .mv = 0
            endif
        endwhile
        mdTmp[.j + 1] = .a
    endfor
    if .n mod 2 = 1
        median.v = mdTmp[(.n + 1) / 2]
    else
        median.v = (mdTmp[.n / 2] + mdTmp[.n / 2 + 1]) / 2
    endif
endproc

procedure gcdInt: .a, .b
    .a = round(abs(.a))
    .b = round(abs(.b))
    while .b > 0
        .t = .a mod .b
        .a = .b
        .b = .t
    endwhile
    gcdInt.out = max(1, .a)
endproc

procedure fileFree: .p$
    fileFree.ok = 1
    if fileReadable(.p$)
        fileFree.ok = 0
    endif
endproc

# Conductor curve c(x), x in [0,1], value in [0,1].
procedure cond: .x
    .x = max(0, min(1, .x))
    if conductor_preset = 1
        .v = .x ^ 1.4
    elsif conductor_preset = 2
        .v = (1 - .x) ^ 1.4
    elsif conductor_preset = 3 or conductor_preset = 6
        if .x < xcEff
            .v = 0.5 - 0.5 * cos(pi * .x / xcEff)
        else
            .v = 0.5 + 0.5 * cos(pi * (.x - xcEff) / (1 - xcEff))
        endif
        if conductor_preset = 6
            .v = .v * (0.55 + 0.45 * (0.5 - 0.5 * cos(2 * pi * 4 * .x)))
            if condJag = 1
                # Controlled Chaos: abrupt level steps on 16 segments
                .v = .v * jagF[min(15, floor(.x * 16))]
            endif
            .v = .v / wavesNorm
        endif
    elsif conductor_preset = 4
        if .x < xcEff
            .v = (.x / xcEff) ^ 2.2
        else
            .v = 0.12 + 0.88 * exp(-(.x - xcEff) / (0.25 * (1 - xcEff)))
        endif
    else
        if .x < xcEff
            .v = (.x / xcEff) ^ 0.5
        else
            .v = (1 - (.x - xcEff) / (1 - xcEff)) ^ 1.6
        endif
    endif
    .v = max(0, min(1, .v))
endproc

# Target duration rank (0 = shortest, 1 = longest) for a temporal preset.
procedure rankTarget: .preset, .x
    .xa = max(0.1, min(0.9, climax_position / 100))
    if .preset = 1
        .r = .x
    elsif .preset = 2
        .r = 1 - .x
    elsif .preset = 3 or .preset = 4
        if .x < .xa
            .r = .x / .xa
        else
            .r = (1 - .x) / (1 - .xa)
        endif
        if .preset = 4
            .r = 1 - .r
        endif
    elsif .preset = 5
        # waveCycles = 4 puts the duration waves in phase with the
        # conductor's waves (Breathing Form); 3 otherwise (v1.x)
        .r = 0.5 - 0.5 * cos(2 * pi * waveCycles * .x)
    else
        .r = duration_preference
    endif
endproc

# Choose a source for layer .lay at time .t that ENDS by .t + .room.
# Returns pickSource.s (0 = nothing fits).
procedure pickSource: .lay, .t, .room, .bridge
    # Pacing: normal picks may use only the share of the layer's supply
    # that matches the share of the form so far (on the conductor's
    # density curve) plus 15 %. Repairs (.bridge < 0 marks none) and
    # closing events are exempt.
    pickSource.s = 0
    .pace = 1
    if pacingOn = 1 and .bridge >= 0 and repairing = 0
        .ix = max(0, min(200, round(.t / target_duration * 200)))
        if layerUsed[.lay] >= layerAvail[.lay] * min(1, cumF[.ix] + 0.15)
            .pace = 0
        endif
    endif
    if .pace = 1
    .x = .t / target_duration
    @rankTarget: layerPreset[.lay], .x
    .r = rankTarget.r
    .sd = 0.04 + 0.5 * (1 - duration_order_strictness)
    if layerPreset[.lay] = 6
        .sd = .sd + 0.1
    endif
    .wsum = 0
    .best = 0
    .bestD = 1e9
    for .k from 1 to layerN[.lay]
        .si = layerSrc[.lay, .k]
        .w = 0
        if srcUses[.si] < max_repetitions and srcDur[.si] <= .room + 1e-9
            .d = abs(srcRank[.si] - .r)
            .w = exp(-(.d * .d) / (2 * .sd * .sd)) * 0.5 ^ srcUses[.si]
            if .si = layerLast[.lay]
                .w = .w * 0.2
            endif
            # lead layer: prefer a sound long enough to reach the next
            # onset, so an inter-onset gap does not become absolute silence
            if .bridge > 0 and srcDur[.si] < .bridge
                .w = .w * 0.15
            endif
            .dd = .d + srcUses[.si] * 0.05 + randomUniform(0, 1e-6)
            if .dd < .bestD
                .bestD = .dd
                .best = .si
            endif
        endif
        cand[.k] = .w
        .wsum = .wsum + .w
    endfor
    # (.s is pickSource.s itself in Praat, so never use it as a loop name)
    pickSource.s = 0
    if .best > 0
        if duration_order_strictness >= 0.999 or .wsum <= 0
            pickSource.s = .best
        else
            .u = randomUniform(0, .wsum)
            .acc = 0
            .k = 0
            .found = 0
            while .found = 0 and .k < layerN[.lay]
                .k = .k + 1
                .acc = .acc + cand[.k]
                if .acc >= .u and cand[.k] > 0
                    .found = 1
                    pickSource.s = layerSrc[.lay, .k]
                endif
            endwhile
            if .found = 0
                pickSource.s = .best
            endif
        endif
    endif
    endif
endproc

# Spatial position p in [-1, 1] for an event.
procedure spatialPos: .lay, .lib, .x, .c
    .w = (1 - spatial_influence) + spatial_influence * .c
    .jit = randomUniform(-1, 1)
    if spatial_preset = 1
        .p = .jit * .w
    elsif spatial_preset = 2
        .p = (2 * .x - 1) + 0.15 * randomness * .jit
    elsif spatial_preset = 3
        .p = (1 - 2 * .x) + 0.15 * randomness * .jit
    elsif spatial_preset = 4
        .p = .jit * (0.05 + 0.95 * .x) * (0.5 + 0.5 * .w)
    elsif spatial_preset = 5
        .p = .jit * (1 - 0.95 * .x) * (0.5 + 0.5 * .w)
    elsif spatial_preset = 6
        altCount[.lay] = altCount[.lay] + 1
        .side = 1
        if altCount[.lay] mod 2 = 0
            .side = -1
        endif
        .p = .side * (0.35 + 0.6 * .w) + 0.1 * randomness * .jit
    elsif spatial_preset = 7
        # layer-based: only the spread inside the layer's region
        .p = .jit * .w
    else
        # v2.0 breathing space: the width follows the conductor
        .p = .jit * (0.08 + 0.92 * ((1 - spatial_influence) * 0.5 + spatial_influence * .c))
    endif
    # v2.1 placement. .p is the BEHAVIOUR on the whole field [-1, 1].
    # Each layer (Independent layers) or each folder (Combined pool) has
    # a region: position H and spread S. Spatial movement m decides how
    # far the behaviour may take a sound out of its region:
    #   m = 0  the behaviour acts inside the region: H + S * p
    #   m = 1  the behaviour uses the whole field (v2.0)
    # Layer-based space is always regional.
    if organization = 2
        .r = .lay
    else
        .r = .lib
    endif
    .pr = regC[.r] + regW[.r] * max(-1, min(1, .p))
    if spatial_preset = 7
        # (same expression as v2.0, so plans stay bit-identical)
        .p = regC[.r] + .jit * regW[.r] * .w
    elsif spatial_movement < 1
        .p = (1 - spatial_movement) * .pr + spatial_movement * .p
    endif
    spatialPos.p = max(-1, min(1, .p))
    spatialPos.width = 0.3 + 0.4 * .w
endproc

# Append one event to the plan.
procedure addEvent: .lay, .s, .t, .ph, .closing
    nEv = nEv + 1
    .x = .t / target_duration
    @cond: .x
    .c = cond.v
    evLayer[nEv] = .lay
    evLib[nEv] = srcLib[.s]
    evSrc[nEv] = .s
    evOn[nEv] = .t
    evDur[nEv] = srcDur[.s]
    evEnd[nEv] = .t + srcDur[.s]
    # gain = library balance + manual library gain + per-file leveling
    #        + conductor dynamics + controlled random variation
    evBalDb[nEv] = libAuto[srcLib[.s]]
    evManDb[nEv] = libManual[srcLib[.s]]
    evFileDb[nEv] = srcFileDb[.s]
    evCondDb[nEv] = dynamics_influence * dynamic_range * (.c - 1)
    evRandDb[nEv] = 1.5 * randomness * randomGauss(0, 1)
    evGainDb[nEv] = evBalDb[nEv] + evManDb[nEv] + evFileDb[nEv] + evCondDb[nEv] + evRandDb[nEv]
    @spatialPos: .lay, srcLib[.s], .x, .c
    evPos[nEv] = spatialPos.p
    evWidth[nEv] = spatialPos.width
    evFi[nEv] = min(event_fade_in / 1000, srcDur[.s] / 3)
    evFo[nEv] = min(event_fade_out / 1000, srcDur[.s] / 3)
    evCond[nEv] = .c
    evPhrase[nEv] = .ph
    evClosing[nEv] = .closing
    srcUses[.s] = srcUses[.s] + 1
    layerUsed[.lay] = layerUsed[.lay] + 1
    layerLast[.lay] = .s
endproc

# Schedule one layer inside phrase window [.ws, .we].
procedure scheduleLayer: .lay, .ws, .we, .ph, .lead
    .dens0 = event_density * layerDensity[.lay]
    .t = .ws
    if .lead = 0
        .t = .ws + randomUniform(0, 0.6) * 60 / .dens0
    endif
    # v2.0: a layer that has not entered yet (Accumulation) starts later
    .t = max(.t, layerEntry[.lay])
    .tail = .t
    .first = nEv + 1
    .go = 1
    .guard = 0
    while .go = 1 and .t < .we and .guard < 5000
        .guard = .guard + 1
        @cond: .t / target_duration
        .c = cond.v
        .densEff = .dens0 * 2 ^ (density_influence * (2 * .c - 1) * 1.25)
        .ovEff = max(0, min(1, overlap + 0.35 * density_influence * (2 * .c - 1)))
        .voices = 1 + round(.ovEff * 9)
        # voice limit: count this layer's events still sounding at .t
        .active = 0
        .soonest = 1e9
        for .ei from .first to nEv
            if evEnd[.ei] > .t + 1e-9
                .active = .active + 1
                .soonest = min(.soonest, evEnd[.ei])
            endif
        endfor
        if .active >= .voices
            .t = .soonest
        else
            # v1.1 spacing. Density sets the entrance spacing (.ioiD);
            # Overlap sets how much of the sound just placed runs before
            # the next entrance: k = 1 - 0.95 overlap of its duration
            # (overlap 0 -> after it ends, 1 -> almost on top of it).
            # The two are blended geometrically (0.4 density, 0.6
            # overlap), so neither control can stand in for the other.
            .ioiD = 60 / .densEff * exp(randomness * randomGauss(0, 0.45))
            .kOv = 1 - 0.95 * .ovEff
            .bridge = 0
            if .lead = 1
                # shortest sound that reaches its own next entrance
                .bridge = min(.ioiD * .kOv ^ 1.5, .we - .t)
            endif
            @pickSource: .lay, .t, .we - .t, .bridge
            if pickSource.s = 0
                .go = 0
            else
                @addEvent: .lay, pickSource.s, floor(.t * srOut) / srOut, .ph, 0
                .tail = max(.tail, evEnd[nEv])
                .dPlaced = evDur[nEv]
                .ioi = .ioiD ^ 0.4 * max(0.02, .dPlaced * .kOv) ^ 0.6
                if .ovEff < 0.02
                    .ioi = max(.ioi, .dPlaced)
                endif
                .t = .t + .ioi
                # Inter-onset gaps are not absolute silence: the lead layer
                # never leaves a hole (other layers may - the phrase repair
                # closes whatever the union leaves open).
                # Absolute silence belongs to the Silence Engine.
                if .lead = 1 and .t > .tail
                    nBridged = nBridged + 1
                    .t = .tail
                endif
            endif
        endif
    endwhile
endproc

# Repair pass for one phrase: close holes in the union of its events
# (including a late start) with any playing layer's fitting source.
# Holes nothing can fill stay - they are reported as material shortage.
procedure repairPhrase: .e0, .ws, .we, .ph
    .it = 0
    .go = 1
    while .go = 1 and .it < 60
        .it = .it + 1
        .go = 0
        if nEv >= .e0
            .tailP = .ws
            for .ei from .e0 to nEv
                .tailP = max(.tailP, evEnd[.ei])
            endfor
            @unionGaps: .e0, nEv, .ws, .tailP
            repairing = 1
            .k = 1
            .done = 0
            while .done = 0 and .k <= unionGaps.count
                .g0 = ugGapS[.k]
                .gl = ugGapE[.k] - .g0
                if .gl > 0.002
                    # try the layers in turn, starting after the last used
                    .tryL = 0
                    while .done = 0 and .tryL < nLayers
                        .tryL = .tryL + 1
                        .lay = ((repairNext + .tryL - 1) mod nLayers) + 1
                        if plays[.lay] = 1 and .g0 >= layerEntry[.lay]
                            @pickSource: .lay, .g0, .we - .g0, .gl
                            if pickSource.s > 0
                                @addEvent: .lay, pickSource.s, floor(.g0 * srOut) / srOut, .ph, 0
                                nRepaired = nRepaired + 1
                                repairNext = .lay
                                .done = 1
                                .go = 1
                            endif
                        endif
                    endwhile
                endif
                .k = .k + 1
            endwhile
            repairing = 0
        endif
    endwhile
endproc

# Gaps (absolute silence) inside the union of events from .e0 to .e1
# within [.from, .to]. Returns the total and the gap list.
procedure unionGaps: .e0, .e1, .from, .to
    .n = 0
    for .ei from .e0 to .e1
        .n = .n + 1
        ugOn[.n] = evOn[.ei]
        ugEnd[.n] = evEnd[.ei]
    endfor
    # insertion sort by onset (explicit flag: 'and' does not short-circuit)
    for .i from 2 to .n
        .a = ugOn[.i]
        .b = ugEnd[.i]
        .j = .i - 1
        .mv = 1
        while .mv = 1
            if .j < 1
                .mv = 0
            elsif ugOn[.j] > .a
                ugOn[.j + 1] = ugOn[.j]
                ugEnd[.j + 1] = ugEnd[.j]
                .j = .j - 1
            else
                .mv = 0
            endif
        endwhile
        ugOn[.j + 1] = .a
        ugEnd[.j + 1] = .b
    endfor
    unionGaps.total = 0
    unionGaps.count = 0
    .cover = .from
    for .i from 1 to .n
        if ugOn[.i] > .cover + 1e-6
            unionGaps.count = unionGaps.count + 1
            ugGapS[unionGaps.count] = .cover
            ugGapE[unionGaps.count] = min(ugOn[.i], .to)
            unionGaps.total = unionGaps.total + min(ugOn[.i], .to) - .cover
        endif
        .cover = max(.cover, ugEnd[.i])
    endfor
    if .to > .cover + 1e-6
        unionGaps.count = unionGaps.count + 1
        ugGapS[unionGaps.count] = .cover
        ugGapE[unionGaps.count] = .to
        unionGaps.total = unionGaps.total + .to - .cover
    endif
endproc

# Pan gains for position .q in [-1,1] over nOutCh channels.
# Returns up to two channels with equal-power gains.
procedure panGains: .q
    .q = max(-1, min(1, .q))
    if nOutCh = 2
        .th = (.q + 1) * pi / 4
        panGains.k1 = 1
        panGains.g1 = cos(.th)
        panGains.k2 = 2
        panGains.g2 = sin(.th)
    else
        .pos = (.q + 1) / 2 * (nOutCh - 1)
        .i = floor(.pos)
        if .i >= nOutCh - 1
            .i = nOutCh - 2
        endif
        .f = .pos - .i
        panGains.k1 = .i + 1
        panGains.g1 = cos(.f * pi / 2)
        panGains.k2 = .i + 2
        panGains.g2 = sin(.f * pi / 2)
    endif
endproc

# One render pass over the plan.
#   .lib   0 = all libraries (mix), k = only library k (stem)
#   .sink  0 = measure peak only, 1 = whole output in memory -> 24-bit,
#          2 = stream 30 s chunks -> 16-bit (scratch files, joined)
#   .gain  linear gain applied before saving
procedure renderPass: .lib, .sink, .gain, .path$, .measure
    .nTot = round(target_duration * srOut)
    if .sink = 1
        .chunkN = .nTot
    else
        .chunkN = round(30 * srOut)
    endif
    .nChunks = ceiling(.nTot / .chunkN)
    renderPass.peak = 0
    renderPass.verA = 0
    renderPass.verB = 0
    renderPass.verRms = 0
    renderPass.silenceRms = 0
    .buffer = 0
    for .ci from 1 to .nChunks
        .s0 = (.ci - 1) * .chunkN
        .s1 = min(.nTot, .s0 + .chunkN)
        .c0 = .s0 / srOut
        .c1 = .s1 / srOut
        if .nChunks > 1
            appendInfoLine: "  ", renderLabel$, ": chunk ", .ci, " / ", .nChunks
        endif
        selectObject: placeholderID
        nocheck Create Sound from formula: "tl_buffer", nOutCh, .c0, .c1, srOut, "0"
        @gotNew: "Sound", placeholderID
        .buffer = gotNew.id
        if .buffer = 0
            @fail: "Not enough memory for a " + fixed$(.c1 - .c0, 1) + " s render buffer - lower the Memory budget."
        endif
        @addTemp: .buffer
        .bx1 = Get time from sample number: 1
        for .ei from 1 to nEv
            .use = 1
            if .lib > 0 and evLib[.ei] <> .lib
                .use = 0
            endif
            if .use = 1 and evOn[.ei] < .c1 and evEnd[.ei] > .c0
                @addEventToBuffer: .ei, .buffer, .c0, .c1, .bx1
            endif
        endfor
        # end-of-composition fade (only the last final_fade seconds)
        if final_fade > 0 and .c1 > endTime - final_fade
            selectObject: .buffer
            Formula (part): max(.c0, endTime - final_fade), .c1, 1, nOutCh,
                ... "self * max(0, min(1, (" + string$(endTime) + " - x) / "
                ... + string$(final_fade) + "))^2"
        endif
        selectObject: .buffer
        .pk = Get absolute extremum: 0, 0, "None"
        renderPass.peak = max(renderPass.peak, .pk)
        if .measure = 1
            # loudness per 1 s window, and residual level inside every
            # planned absolute silence (should be exactly zero)
            for .w from floor(.c0) + 1 to ceiling(.c1)
                .wa = max(.c0, .w - 1)
                .wb = min(.c1, .w)
                if .wb - .wa > 0.01 and .w <= nWin
                    .rms = Get root-mean-square: .wa, .wb
                    winRms[.w] = .rms
                endif
            endfor
            for .k from 1 to nGap
                if gapE[.k] - gapS[.k] > 0.02
                    .ga = max(.c0, gapS[.k] + 0.001)
                    .gb = min(.c1, gapE[.k] - 0.001)
                    if .gb - .ga > 0.005
                        .rms = Get root-mean-square: .ga, .gb
                        renderPass.silenceRms = max(renderPass.silenceRms, .rms)
                    endif
                endif
            endfor
        endif
        if .sink = 2
            if .gain <> 1
                Multiply: .gain
            endif
            # verification window (see verifyOut), in the chunk that holds its end
            if rpWb > .c0 and rpWb <= .c1 and rpWb > rpWa
                renderPass.verA = max(rpWa, .c0)
                renderPass.verB = rpWb
                renderPass.verRms = Get root-mean-square: renderPass.verA, renderPass.verB
            endif
            # nocheck: a failed write is caught by the checks below and by
            # the one the caller makes on the finished file (@verifyOut)
            if .nChunks = 1
                nocheck Save as WAV file: .path$
                outState[renderOutK] = 1
            else
                # v1.2: every chunk goes to its own scratch file, and the
                # chunks are joined at the end by Praat's multi-LongSound
                # save. "Append to existing sound file" is not used: on a
                # full disk it crashes Praat itself (6.4.06 and 7.0,
                # "double free"), and a crashed Praat cleans up nothing.
                .tw = min(0.1, .c1 - .c0)
                .tailExp = Get root-mean-square: .c1 - .tw, .c1
                @regScratch: .path$, .ci
                .cp$ = regScratch.path$
                nocheck Save as WAV file: .cp$
                outState[regScratch.k] = 1
                selectObject: placeholderID
                nocheck Open long sound file: .cp$
                @gotNew: "LongSound", placeholderID
                .cls = gotNew.id
                if .cls = 0
                    @fail: "Could not write " + .cp$ + " (disk full or no permission?)"
                endif
                @addTemp: .cls
                rpChunkLS[.ci] = .cls
                # the header always states the full length; read real
                # samples back from the end of the chunk
                .okChunk = 0
                .dd = Get total duration
                if abs(.dd - (.c1 - .c0)) <= 1.5 / srOut
                    # (a chunk file starts at time 0)
                    nocheck Extract part: .c1 - .c0 - .tw, .c1 - .c0, "no"
                    @gotNew: "Sound", .cls
                    if gotNew.id > 0
                        .rr = Get root-mean-square: 0, 0
                        removeObject: gotNew.id
                        if abs(.rr - .tailExp) <= 0.05 * .tailExp + 0.0001
                            .okChunk = 1
                        endif
                    endif
                endif
                if .okChunk = 0
                    @fail: "Could not write " + .cp$ + " (disk full or no permission?)"
                endif
            endif
        endif
        if .sink <> 1
            removeObject: .buffer
            @dropTemp: .buffer
        endif
    endfor
    if .sink = 2 and .nChunks > 1
        appendInfoLine: "  ", renderLabel$, ": joining ", .nChunks, " chunks"
        selectObject: rpChunkLS[1]
        for .ci from 2 to .nChunks
            plusObject: rpChunkLS[.ci]
        endfor
        outState[renderOutK] = 1
        nocheck Save as WAV file: .path$
        # the scratch files are no longer needed, whatever the outcome
        # (a failed join is caught by the caller's @verifyOut)
        for .ci from 1 to .nChunks
            removeObject: rpChunkLS[.ci]
            @dropTemp: rpChunkLS[.ci]
        endfor
        for .k from 1 to nOutF
            if outKind[.k] = 4 and outState[.k] = 1
                nocheck deleteFile: outWrite$[.k]
                outState[.k] = 3
            endif
        endfor
    endif
    renderPass.bufID = 0
    if .sink = 1
        selectObject: .buffer
        if .gain <> 1
            Multiply: .gain
        endif
        if .path$ = ""
            # v1.1: keep the buffer as the result (a Sound object)
            renderPass.bufID = .buffer
        else
            nocheck Save as 24-bit WAV file: .path$
            removeObject: .buffer
            @dropTemp: .buffer
        endif
    endif
endproc

# Read one event segment from disk and add it into the buffer.
procedure addEventToBuffer: .ei, .buf, .c0, .c1, .bx1
    .s = evSrc[.ei]
    .on = evOn[.ei]
    .ta = max(0, .c0 - .on)
    .tb = min(evDur[.ei], .c1 - .on)
    .srs = srcSr[.s]
    .resample = 0
    if abs(.srs - srOut) > 0.5
        .resample = 1
    endif
    if .resample = 0
        .pa = max(0, .ta - 2 / .srs)
        .pb = min(srcDur[.s], .tb + 2 / .srs)
    else
        # align the extract to a grid common to both rates, so the
        # resampled samples land exactly on the output grid
        @gcdInt: .srs, srOut
        .g = gcdInt.out
        .pa = max(0, floor((.ta - 0.02) * .g) / .g)
        .pb = min(srcDur[.s], ceiling((.tb + 0.02) * .g) / .g)
    endif
    selectObject: placeholderID
    nocheck Open long sound file: srcPath$[.s]
    @gotNew: "LongSound", placeholderID
    .lsID = gotNew.id
    if .lsID = 0
        @fail: "Cannot read the source " + srcPath$[.s] + " during rendering."
    endif
    @addTemp: .lsID
    nocheck Extract part: .pa, .pb, "yes"
    @gotNew: "Sound", .lsID
    .partID = gotNew.id
    if .partID = 0
        @fail: "Cannot read " + fixed$(.pa, 2) + "-" + fixed$(.pb, 2) + " s of " + srcPath$[.s] + "."
    endif
    @addTemp: .partID
    removeObject: .lsID
    @dropTemp: .lsID
    if .resample = 1
        selectObject: .partID
        nocheck Resample: srOut, 50
        @gotNew: "Sound", .partID
        .rsID = gotNew.id
        if .rsID = 0
            @fail: "Resampling " + srcPath$[.s] + " to " + string$(srOut) + " Hz failed (memory?)."
        endif
        @addTemp: .rsID
        removeObject: .partID
        @dropTemp: .partID
        .partID = .rsID
    endif
    selectObject: .partID
    .nsc = Get number of channels
    # event fades (x is the time inside the source here)
    .fi = evFi[.ei]
    .fo = evFo[.ei]
    .d = evDur[.ei]
    .env$ = "1"
    if .fi > 0
        .env$ = .env$ + " * (if x < " + string$(.fi) + " then sin(pi / 2 * max(0, x) / "
            ... + string$(.fi) + ")^2 else 1 fi)"
    endif
    if .fo > 0
        .env$ = .env$ + " * (if x > " + string$(.d - .fo) + " then sin(pi / 2 * max(0, "
            ... + string$(.d) + " - x) / " + string$(.fo) + ")^2 else 1 fi)"
    endif
    if .env$ <> "1"
        Formula: "self * " + .env$
    endif
    .px1 = Get time from sample number: 1
    .dOff = round((.bx1 - .on - .px1) * srOut)
    .g = 10 ^ (evGainDb[.ei] / 20)
    # source channel positions: mono = one point; stereo = two points,
    # image kept, narrowed to the event width (never summed to mono)
    if .nsc >= 2
        .nUse = 2
        aebQ[1] = max(-1, min(1, evPos[.ei] - evWidth[.ei] / 2))
        aebQ[2] = max(-1, min(1, evPos[.ei] + evWidth[.ei] / 2))
        .scale = 1
    else
        .nUse = 1
        aebQ[1] = evPos[.ei]
        .scale = 1
    endif
    .from = .on + .ta
    .to = .on + .tb
    for .sc from 1 to .nUse
        @panGains: aebQ[.sc]
        aebK[1] = panGains.k1
        aebG[1] = panGains.g1
        aebK[2] = panGains.k2
        aebG[2] = panGains.g2
        for .j from 1 to 2
            .gch = .g * aebG[.j] * .scale
            if .gch > 1e-6
                selectObject: .buf
                Formula (part): .from, .to, aebK[.j], aebK[.j],
                    ... "self + " + string$(.gch) + " * object[" + string$(.partID)
                    ... + ", " + string$(.sc) + ", col + " + string$(.dOff) + "]"
            endif
        endfor
    endfor
    removeObject: .partID
    @dropTemp: .partID
endproc

# Are all files this run would write under base .b$ free?
# (wPlan: plan + settings; wAudio: mix + stems)
procedure targetsFree: .b$
    .free = 1
    if wPlan
        if fileReadable(.b$ + "_plan.tsv") or fileReadable(.b$ + "_settings.tsv")
            .free = 0
        endif
    endif
    if wAudio
        if fileReadable(.b$ + mixSuffix$)
            .free = 0
        endif
        if wantStems
            for .i from 1 to nLib
                if fileReadable(.b$ + "_stem" + string$(.i) + "_" + libName$[.i] + ".wav")
                    .free = 0
                endif
            endfor
        endif
    endif
    targetsFree.free = .free
endproc

# Choose a base name in outDir$ that overwrites nothing (or ask).
procedure chooseBase: .short$
    base$ = outDir$ + "/" + .short$
    @targetsFree: base$
    if targetsFree.free = 0
        .doNumber = 1
        if existing_files = 2
            beginPause: "TimeLine Composer - files exist"
                comment: "Files named " + .short$ + "... already exist in"
                comment: outDir$
            .clicked = endPause: "Cancel", "New name", "Overwrite", 2, 1
            if .clicked = 1
                @fail: "Cancelled: nothing was written."
            elsif .clicked = 3
                .doNumber = 0
                overwriteConfirmed = 1
                @warn: "Existing files were replaced (confirmed in the dialog); each new file was written beside the old one first and copied over it only when complete."
            endif
        endif
        if .doNumber
            .n = 1
            while targetsFree.free = 0
                .n = .n + 1
                base$ = outDir$ + "/" + .short$ + "_" + string$(.n)
                @targetsFree: base$
            endwhile
        endif
    endif
endproc

# Save a Table under the overwrite policy for single files.
# Save one Table as its own committed group (the catalog), under the
# overwrite policy, through the registry.
procedure saveTableSafely: .id, .path$, .group
    .p$ = .path$
    .confirm = 0
    if fileReadable(.p$)
        if existing_files = 2
            beginPause: "TimeLine Composer - file exists"
                comment: .p$
            .clicked = endPause: "Cancel", "New name", "Overwrite", 2, 1
            if .clicked = 1
                @fail: "Cancelled: nothing more was written."
            elsif .clicked = 3
                .confirm = 1
            endif
        endif
        if .confirm = 0
            .n = 1
            .stem$ = replace$(.path$, ".tsv", "", 1)
            while fileReadable(.p$)
                .n = .n + 1
                .p$ = .stem$ + "_" + string$(.n) + ".tsv"
            endwhile
        endif
    endif
    .keep = overwriteConfirmed
    overwriteConfirmed = .confirm
    @regOut: .p$, 3, .group
    overwriteConfirmed = .keep
    outObj[regOut.k] = .id
    selectObject: .id
    nocheck Save as tab-separated file: regOut.path$
    outState[regOut.k] = 1
    selectObject: .id
    verRows = Get number of rows
    @verifyOut: regOut.k, 0
    if verifyOut.ok = 0
        @fail: "Could not write " + regOut.path$ + " (disk full or no permission?)."
    endif
    @commitGroup: .group
    saveTableSafely.path$ = .p$
endproc

procedure kv: .k$, .v$
    selectObject: setID
    Append row
    .r = Get number of rows
    Set string value: .r, "key", .k$
    Set string value: .r, "value", .v$
endproc

procedure col: .lay, .f
    # layer colour mixed toward white by .f (0 = full colour)
    .r = layerR[.lay] + (1 - layerR[.lay]) * .f
    .g = layerG[.lay] + (1 - layerG[.lay]) * .f
    .b = layerB[.lay] + (1 - layerB[.lay]) * .f
    col.c$ = "{" + fixed$(.r, 2) + ", " + fixed$(.g, 2) + ", " + fixed$(.b, 2) + "}"
endproc

procedure niceStep: .span, .target
    .raw = .span / .target
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .result = .p
    elsif .m < 3.5
        .result = 2 * .p
    elsif .m < 7.5
        .result = 5 * .p
    else
        .result = 10 * .p
    endif
endproc

# ============================================================
# 0. HOUSEKEEPING: placeholder, clean exits, on-demand folder
# ============================================================
# A placeholder keeps a known selection, so a failed nocheck open is
# detectable without guessing. It is removed on every exit.
Create Sound from formula: "tl_placeholder", 1, 0, 0.001, 1000, "0"
placeholderID = selected("Sound")
nTemp = 0
nOutF = 0
renderOutK = 0
verWa = 0
verWb = 0
verExp = 0
verRows = 0
rpWa = 0
rpWb = 0
overwriteConfirmed = 0
mixID = 0
nStems = 0
trustAsked = 0
outDir$ = ""

writeInfoLine: "=== TimeLine Composer v2.3 ==="

# Remove our temporary objects, then stop with a message. Objects that
# belonged to the user before the run are never touched.
procedure fail: .msg$
    # 1. temporary objects (a LongSound must go before its file)
    for .k from 1 to nTemp
        if tempID[.k] > 0
            nocheck removeObject: tempID[.k]
        endif
    endfor
    nocheck removeObject: placeholderID
    # 2. files THIS run wrote and has not committed: partial or unconfirmed
    #    outputs. Files that existed before the run are never deleted -
    #    a confirmed overwrite writes to a side file first (see regOut).
    .nDel = 0
    for .k from 1 to nOutF
        if outState[.k] = 1
            if fileReadable(outWrite$[.k])
                nocheck deleteFile: outWrite$[.k]
                .nDel = .nDel + 1
            endif
        endif
    endfor
    if .nDel > 0
        exitScript: .msg$ + newline$ + "(" + string$(.nDel) + " incomplete file(s) written by this run were deleted.)"
    else
        exitScript: .msg$
    endif
endproc

# ---------- output-file registry ----------
# Every file the script writes is registered first.
#   kind 1 = Sound saved as 24-bit WAV, 2 = streamed 16-bit WAV that a
#   LongSound reads, 3 = Table (TSV), 4 = scratch chunk of a streamed
#   render (always deleted).
#   state 0 = not written, 1 = written but not committed (deleted by
#   @fail), 2 = committed (kept; never deleted by this script),
#   3 = scratch file already deleted.
# A confirmed overwrite of an existing file writes to a side file
# "<name>__tl_new.<ext>"; only after it is complete and verified is the
# target replaced. Praat has no rename, so the replace is a verified
# copy followed by deleting the side file.
procedure regOut: .target$, .kind, .group
    nOutF = nOutF + 1
    outTarget$[nOutF] = .target$
    outKind[nOutF] = .kind
    outGroup[nOutF] = .group
    outObj[nOutF] = 0
    outState[nOutF] = 0
    outWrite$[nOutF] = .target$
    if overwriteConfirmed = 1 and fileReadable(.target$)
        .dot = rindex(.target$, ".")
        outWrite$[nOutF] = left$(.target$, .dot - 1) + "__tl_new" + mid$(.target$, .dot, length(.target$) - .dot + 1)
    endif
    regOut.k = nOutF
    regOut.path$ = outWrite$[nOutF]
endproc

# A scratch file for one streamed chunk (kind 4, group 0): written next
# to the output, never kept - deleted after the join, or by @fail.
procedure regScratch: .out$, .ci
    nOutF = nOutF + 1
    .dot = rindex(.out$, ".")
    outTarget$[nOutF] = left$(.out$, .dot - 1) + "__tl_part" + string$(.ci) + ".wav"
    outWrite$[nOutF] = outTarget$[nOutF]
    outKind[nOutF] = 4
    outGroup[nOutF] = 0
    outObj[nOutF] = 0
    outState[nOutF] = 0
    regScratch.k = nOutF
    regScratch.path$ = outWrite$[nOutF]
endproc

# Is the file complete? A WAV header states the full length before the
# samples are written, so a disk that fills up leaves a file whose
# header is right and whose end is missing - and Praat then reads the
# missing samples as zeros with only a warning. So the check reads REAL
# audio back: the RMS of a window just before the last sound ends
# (verWa..verWb, expected verExp from the rendered data). Files are
# written front to back, so if that window is intact, all of it is.
# A TSV is read back and its row count compared (verRows).
procedure verifyOut: .k, .dur
    verifyOut.ok = 0
    if fileReadable(outWrite$[.k])
        if outKind[.k] = 3
            selectObject: placeholderID
            nocheck Read Table from tab-separated file: outWrite$[.k]
            @gotNew: "Table", placeholderID
            if gotNew.id > 0
                .rows = Get number of rows
                removeObject: gotNew.id
                if .rows = verRows
                    verifyOut.ok = 1
                endif
            endif
        else
            selectObject: placeholderID
            nocheck Open long sound file: outWrite$[.k]
            @gotNew: "LongSound", placeholderID
            .ls = gotNew.id
            if .ls > 0
                .d = Get total duration
                .okDur = 0
                if abs(.d - .dur) <= 1.5 / srOut
                    .okDur = 1
                endif
                .okData = 1
                if verExp > 0 and verWb > verWa
                    .okData = 0
                    nocheck Extract part: verWa, verWb, "no"
                    @gotNew: "Sound", .ls
                    if gotNew.id > 0
                        .r = Get root-mean-square: 0, 0
                        removeObject: gotNew.id
                        # 16-bit quantisation and 24-bit rounding stay far inside 5 %
                        if abs(.r - verExp) <= 0.05 * verExp + 0.0001
                            .okData = 1
                        endif
                    endif
                endif
                selectObject: .ls
                removeObject: .ls
                if .okDur and .okData
                    verifyOut.ok = 1
                endif
            endif
        endif
    endif
endproc

# The check window for a library (0 = the mix): the last 0.25 s before
# its last sound ends, inside the musical end.
procedure verWindow: .lib
    .le = 0
    for .ei from 1 to nEv
        if .lib = 0 or evLib[.ei] = .lib
            .le = max(.le, evEnd[.ei])
        endif
    endfor
    .le = min(.le, endTime)
    verWb = max(0, .le - 0.01)
    verWa = max(0, .le - 0.26)
endproc

# Commit the files of one group: replace targets from side files,
# then mark everything kept.
procedure commitGroup: .group
    for .k from 1 to nOutF
        if outGroup[.k] = .group and outState[.k] = 1
            if outWrite$[.k] <> outTarget$[.k]
                .okCopy = 0
                if outKind[.k] = 1 and outObj[.k] > 0
                    selectObject: outObj[.k]
                    nocheck Save as 24-bit WAV file: outTarget$[.k]
                    .okCopy = fileReadable(outTarget$[.k])
                elsif outKind[.k] = 3 and outObj[.k] > 0
                    selectObject: outObj[.k]
                    nocheck Save as tab-separated file: outTarget$[.k]
                    .okCopy = fileReadable(outTarget$[.k])
                elsif outKind[.k] = 2
                    selectObject: placeholderID
                    nocheck Open long sound file: outWrite$[.k]
                    if left$(selected$(), 9) = "LongSound"
                        .ls = selected()
                        nocheck Save as WAV file: outTarget$[.k]
                        removeObject: .ls
                        .okCopy = fileReadable(outTarget$[.k])
                    endif
                endif
                if .okCopy = 0
                    # keep the side file: it is now the only complete copy
                    outState[.k] = 2
                    @warn: "Could not replace " + outTarget$[.k] + " - the new version is kept as "
                        ... + outWrite$[.k]
                else
                    # a LongSound must read the target, not the side file
                    if outKind[.k] = 2 and outObj[.k] > 0
                        selectObject: placeholderID
                        nocheck Open long sound file: outTarget$[.k]
                        if left$(selected$(), 9) = "LongSound"
                            .newLS = selected()
                            selectObject: outObj[.k]
                            .nm$ = selected$("LongSound")
                            removeObject: outObj[.k]
                            @swapID: outObj[.k], .newLS
                            selectObject: .newLS
                            Rename: .nm$
                            outObj[.k] = .newLS
                        endif
                    endif
                    nocheck deleteFile: outWrite$[.k]
                    outWrite$[.k] = outTarget$[.k]
                    outState[.k] = 2
                endif
            else
                outState[.k] = 2
            endif
        endif
    endfor
endproc

# Replace an object id in the result lists (after a LongSound swap).
procedure swapID: .old, .new
    if mixID = .old
        mixID = .new
    endif
    for .k from 1 to nStems
        if stemID[.k] = .old
            stemID[.k] = .new
        endif
    endfor
    for .k from 1 to nTemp
        if tempID[.k] = .old
            tempID[.k] = .new
        endif
    endfor
endproc

# Object-creating command check: after a nocheck command, was a new
# object of .type$ selected (instead of the previous selection)?
procedure gotNew: .type$, .prev
    # (.id would BE gotNew.id in Praat, so the candidate has its own name)
    gotNew.id = 0
    if numberOfSelected() = 1
        .cand = selected()
        if .cand <> .prev and left$(selected$(), length(.type$)) = .type$
            gotNew.id = .cand
        endif
    endif
endproc

procedure addTemp: .id
    nTemp = nTemp + 1
    tempID[nTemp] = .id
endproc

procedure dropTemp: .id
    for .k from 1 to nTemp
        if tempID[.k] = .id
            tempID[.k] = 0
        endif
    endfor
endproc

# Praat 7 needs permission before a script writes a file; ask once, and
# only when a file is actually about to be written.
procedure ensureTrust
    if trustAsked = 0
        trustAsked = 1
        if praatVersion >= 7000
            if askForTrust() = 0
                @fail: "Saving files needs your permission in Praat 7 (nothing was written)."
            endif
        endif
    endif
endproc

# The output folder is asked for only when something must be saved.
procedure needOutDir: .why$
    if outDir$ = ""
        @trimText: output_folder$
        outDir$ = trimText.out$
        if outDir$ = ""
            outDir$ = chooseFolder$: "TimeLine Composer: choose a folder to " + .why$
            @trimText: outDir$
            outDir$ = trimText.out$
        endif
        if outDir$ = ""
            @fail: "No folder chosen to " + .why$ + " - nothing was written."
        endif
        if folderExists(outDir$) = 0
            @fail: "Folder not found: " + outDir$
        endif
        for .i from 1 to nLib
            if libFolder$[.i] = outDir$
                @fail: "The chosen folder is source folder " + string$(.i) + ". Choose a"
                    ... + " different folder, so saved files never become sources."
            endif
        endfor
    endif
    @ensureTrust
endproc

# ============================================================
# 2a. RE-RENDER A SAVED PLAN (file, or the Tables left by Plan only)
# ============================================================
if rerender
    planTab = 0
    setTab = 0
    for k from 1 to nSelTables
        selectObject: selTable[k]
        c1 = Get column index: "kind"
        c2 = Get column index: "key"
        if c1 > 0
            planTab = selTable[k]
        elsif c2 > 0
            setTab = selTable[k]
        endif
    endfor
    if planTab > 0 and setTab > 0
        pf$ = "(Tables in the Objects window)"
        selectObject: setTab
        Copy: "tl_settings_tmp"
        setID = selected("Table")
        selectObject: planTab
        Copy: "tl_plan_tmp"
        planID = selected("Table")
        selectObject: planTab
        baseShort$ = replace$(selected$("Table"), "_plan", "", 1)
    else
        @trimText: plan_file$
        pf$ = trimText.out$
        if pf$ = ""
            @trimText: folder_paths$
            if right$(trimText.out$, 4) = ".tsv"
                pf$ = trimText.out$
            endif
        endif
        if pf$ = ""
            pf$ = chooseReadFile$: "Choose a TimeLine *_plan.tsv file"
        endif
        if pf$ = "" or fileReadable(pf$) = 0
            @fail: "No plan chosen: select the two plan Tables, or choose a *_plan.tsv file."
        endif
        sf$ = replace$(pf$, "_plan.tsv", "_settings.tsv", 1)
        if fileReadable(sf$) = 0
            @fail: "The settings file next to the plan is missing: " + sf$
        endif
        selectObject: placeholderID
        nocheck Read Table from tab-separated file: sf$
        @gotNew: "Table", placeholderID
        setID = gotNew.id
        if setID = 0
            @fail: "Cannot read the settings file " + sf$
        endif
        @addTemp: setID
        selectObject: placeholderID
        nocheck Read Table from tab-separated file: pf$
        @gotNew: "Table", placeholderID
        planID = gotNew.id
        if planID = 0
            @fail: "Cannot read the plan file " + pf$
        endif
        @baseName: replace$(pf$, "_plan.tsv", "", 1)
        baseShort$ = baseName.out$
    endif
    @addTemp: setID
    @addTemp: planID
    selectObject: setID
    nSet = Get number of rows
    set$["ending_silence"] = "0"
    # keys added in v2.0 (older plans: v1.x behaviour)
    set$["composition_preset"] = "Custom"
    set$["compositional_intensity"] = "50"
    set$["wave_cycles"] = "3"
    set$["conductor_steps"] = "0"
    set$["streams"] = "0"
    for r from 1 to nSet
        k$ = Get value: r, "key"
        v$ = Get value: r, "value"
        set$[k$] = v$
    endfor
    target_duration = number(set$["target_duration"])
    srOut = number(set$["output_sample_rate"])
    nOutCh = number(set$["output_channels"])
    final_fade = number(set$["final_fade"])
    normalize = number(set$["normalize"])
    peak_dBFS = number(set$["peak_dBFS"])
    random_seed = number(set$["random_seed"])
    conductor_preset = number(set$["conductor_preset"])
    climax_position = number(set$["climax_position"])
    silence_mode = number(set$["silence_mode"])
    silence_amount = number(set$["silence_amount"])
    temporal_preset = number(set$["temporal_preset"])
    spatial_preset = number(set$["spatial_preset"])
    organization = number(set$["organization"])
    ending_silence = number(set$["ending_silence"])
    library_balance = 1
    nLib = number(set$["libraries"])
    for i from 1 to nLib
        libName$[i] = set$["library_" + string$(i) + "_name"]
        libFolder$[i] = set$["library_" + string$(i) + "_folder"]
    endfor
    nLayers = number(set$["layers"])
    waveCycles = number(set$["wave_cycles"])
    condJag = number(set$["conductor_steps"])
    nStreams = number(set$["streams"])
    compositional_intensity = number(set$["compositional_intensity"])
    composition_preset = 8
    for k from 1 to 7
        if set$["composition_preset"] = cpName$[k]
            composition_preset = k
        endif
    endfor

    selectObject: planID
    nRows = Get number of rows
    nEv = 0
    nGapPlan = 0
    nSrc = 0
    missing = 0
    for r from 1 to nRows
        kind$ = Get value: r, "kind"
        if kind$ = "event"
            nEv = nEv + 1
            evLayer[nEv] = Get value: r, "layer"
            evLib[nEv] = Get value: r, "library"
            layerLibOf[evLayer[nEv]] = evLib[nEv]
            p$ = Get value: r, "path"
            evOn[nEv] = Get value: r, "onset"
            evDur[nEv] = Get value: r, "duration"
            evEnd[nEv] = evOn[nEv] + evDur[nEv]
            # the stored EFFECTIVE gain: loudness decisions are not redone
            evGainDb[nEv] = Get value: r, "gain_db"
            evPos[nEv] = Get value: r, "position"
            evWidth[nEv] = Get value: r, "width"
            evFi[nEv] = Get value: r, "fade_in"
            evFo[nEv] = Get value: r, "fade_out"
            evCond[nEv] = Get value: r, "conductor"
            evPhrase[nEv] = Get value: r, "phrase"
            evClosing[nEv] = 0
            found = 0
            for s from 1 to nSrc
                if srcPath$[s] = p$
                    found = s
                endif
            endfor
            if found = 0
                nSrc = nSrc + 1
                found = nSrc
                srcPath$[nSrc] = p$
                srcDur[nSrc] = evDur[nEv]
                srcSr[nSrc] = Get value: r, "source_rate"
                srcCh[nSrc] = Get value: r, "source_channels"
                srcLib[nSrc] = evLib[nEv]
                @baseName: p$
                srcName$[nSrc] = baseName.out$
            endif
            evSrc[nEv] = found
        endif
    endfor
    removeObject: planID, setID
    @dropTemp: planID
    @dropTemp: setID
    # every source must still exist and have the planned duration
    for s from 1 to nSrc
        ok = 0
        if fileReadable(srcPath$[s])
            selectObject: placeholderID
            nocheck Open long sound file: srcPath$[s]
            if left$(selected$(), 9) = "LongSound"
                lsID = selected()
                d = Get total duration
                sr = Get sampling frequency
                removeObject: lsID
                if abs(d - srcDur[s]) < 0.002 and abs(sr - srcSr[s]) < 0.5
                    ok = 1
                endif
            endif
        endif
        if ok = 0
            missing = missing + 1
            appendInfoLine: "  missing or changed: ", srcPath$[s]
        endif
    endfor
    if missing > 0
        @fail: string$(missing) + " source file(s) are missing or have changed"
            ... + " (see Info). The plan refers to the originals and cannot be"
            ... + " rendered faithfully."
    endif
    appendInfoLine: "Plan: ", pf$
    appendInfoLine: "  ", nEv, " events from ", nSrc, " source files - all present and unchanged."
    xcEff = climax_position / 100
    nSilP = 0
endif

# ============================================================
# 2b. NEW COMPOSITION: FOLDERS AND CATALOG
# ============================================================
if rerender = 0
    @trimText: folder_paths$
    sfText$ = trimText.out$
    nLib = 0
    if sfText$ <> ""
        rest$ = sfText$ + ";"
        while index(rest$, ";") > 0 and nLib < 5
            p = index(rest$, ";")
            @trimText: left$(rest$, p - 1)
            if trimText.out$ <> ""
                nLib = nLib + 1
                libFolder$[nLib] = trimText.out$
            endif
            rest$ = mid$(rest$, p + 1, length(rest$) - p)
        endwhile
    else
        for i from 1 to folders_to_browse
            f$ = chooseFolder$: "TimeLine Composer: choose SOURCE folder " + string$(i)
                ... + " of " + string$(folders_to_browse)
            @trimText: f$
            if trimText.out$ = ""
                @fail: "Cancelled at source folder " + string$(i) + " - nothing was done."
            endif
            nLib = nLib + 1
            libFolder$[nLib] = trimText.out$
        endfor
    endif
    if nLib = 0
        @fail: "No source folder chosen."
    endif
    for i from 1 to nLib
        if folderExists(libFolder$[i]) = 0
            @fail: "Source folder not found: " + libFolder$[i]
        endif
        @baseName: libFolder$[i]
        libName$[i] = baseName.out$
    endfor

    # ---- previous catalog, if reuse is requested ----
    nOld = 0
    oldHasLevels = 0
    if catalog_mode = 2
        @trimText: catalog_file$
        catPath$ = trimText.out$
        if catPath$ = ""
            catPath$ = chooseReadFile$: "Choose a TimeLine catalog (*.tsv) to reuse"
        endif
        if catPath$ <> "" and fileReadable(catPath$)
            selectObject: placeholderID
            nocheck Read Table from tab-separated file: catPath$
            @gotNew: "Table", placeholderID
            catOld = gotNew.id
            if catOld = 0
                @fail: "Cannot read the catalog " + catPath$
            endif
            @addTemp: catOld
            nOld = Get number of rows
            cLev = Get column index: "active_db"
            if cLev > 0
                oldHasLevels = 1
            endif
            for r from 1 to nOld
                oldPath$[r] = Get value: r, "path"
                oldDur[r] = Get value: r, "duration"
                oldSr[r] = Get value: r, "sample_rate"
                oldCh[r] = Get value: r, "channels"
                if oldHasLevels
                    oldRms[r] = Get value: r, "rms_db"
                    oldPeak[r] = Get value: r, "peak_db"
                    oldAct[r] = Get value: r, "active_db"
                    oldActS[r] = Get value: r, "active_s"
                    oldRel[r] = Get value: r, "reliable"
                endif
            endfor
            removeObject: catOld
            @dropTemp: catOld
            appendInfoLine: "Reusing catalog (", nOld, " entries): ", catPath$
            if oldHasLevels = 0
                @warn: "The saved catalog has no loudness data (v1.0 format): levels are measured now."
            endif
        else
            @warn: "No readable catalog chosen - the folders are analysed instead."
        endif
    endif

    # ---- scan: headers through LongSound, levels from sampled sections ----
    appendInfoLine: "Scanning ", nLib, " folder(s)..."
    nSrc = 0
    nSkipped = 0
    nNonAudio = 0
    nReused = 0
    nChanged = 0
    nMeasured = 0
    for i from 1 to nLib
        libCount[i] = 0
        selectObject: placeholderID
        nocheck Create Strings as file list: "tl_files", libFolder$[i] + "/*"
        @gotNew: "Strings", placeholderID
        fl = gotNew.id
        if fl = 0
            @fail: "Cannot list the files of " + libFolder$[i]
        endif
        @addTemp: fl
        Sort
        nf = Get number of strings
        for j from 1 to nf
            selectObject: fl
            fn$ = Get string: j
            ext$ = ""
            if index(fn$, ".") > 0
                ext$ = replace_regex$(fn$, "^.*\.", "", 1)
            endif
            @toLower: ext$
            ext$ = toLower.out$
            isAudio = 0
            if ext$ = "wav" or ext$ = "wave" or ext$ = "aif" or ext$ = "aiff" or ext$ = "aifc"
                ... or ext$ = "flac" or ext$ = "mp3" or ext$ = "au" or ext$ = "snd" or ext$ = "nist"
                isAudio = 1
            endif
            if isAudio = 0
                nNonAudio = nNonAudio + 1
            else
                path$ = libFolder$[i] + "/" + fn$
                d = 0
                # the header is always read (cheap); it validates catalog entries
                selectObject: placeholderID
                nocheck Open long sound file: path$
                if left$(selected$(), 9) = "LongSound"
                    lsID = selected()
                    d = Get total duration
                    sr = Get sampling frequency
                    got = 0
                    for r from 1 to nOld
                        if oldPath$[r] = path$
                            got = r
                        endif
                    endfor
                    reuse = 0
                    if got > 0
                        if abs(oldDur[got] - d) < 0.002 and abs(oldSr[got] - sr) < 0.5 and oldHasLevels
                            reuse = 1
                        else
                            nChanged = nChanged + 1
                        endif
                    endif
                    if reuse = 1
                        nc = oldCh[got]
                        lvRms = oldRms[got]
                        lvPeak = oldPeak[got]
                        lvAct = oldAct[got]
                        lvActS = oldActS[got]
                        lvRel = oldRel[got]
                        nReused = nReused + 1
                    elsif d > 0.005
                        @measureLevel: lsID, d
                        nc = measureLevel.nch
                        lvRms = measureLevel.rmsDb
                        lvPeak = measureLevel.peakDb
                        lvAct = measureLevel.actDb
                        lvActS = measureLevel.actS
                        lvRel = measureLevel.reliable
                        nMeasured = nMeasured + 1
                        if nc = 0
                            d = 0
                        endif
                    endif
                    removeObject: lsID
                endif
                if d > 0.005
                    nSrc = nSrc + 1
                    srcPath$[nSrc] = path$
                    srcName$[nSrc] = fn$
                    srcLib[nSrc] = i
                    srcDur[nSrc] = d
                    srcSr[nSrc] = sr
                    srcCh[nSrc] = nc
                    srcUses[nSrc] = 0
                    srcRmsDb[nSrc] = lvRms
                    srcPeakDb[nSrc] = lvPeak
                    srcActDb[nSrc] = lvAct
                    srcActS[nSrc] = lvActS
                    srcReliable[nSrc] = lvRel
                    libCount[i] = libCount[i] + 1
                else
                    nSkipped = nSkipped + 1
                    @warn: "Skipped (unreadable or empty): " + fn$
                endif
            endif
        endfor
        removeObject: fl
        @dropTemp: fl
        appendInfoLine: "  ", i, ": ", libName$[i], " - ", libCount[i], " audio file(s)"
    endfor
    if nOld > 0
        appendInfoLine: "  catalog: ", nReused, " entries reused, ", nChanged, " changed and re-analysed, ",
            ... nMeasured - nChanged, " new analysed (every header was re-checked)"
    endif
    if nSrc = 0
        @fail: "No readable audio files in the chosen folder(s)."
    endif
    for i from 1 to nLib
        if libCount[i] = 0
            @warn: "Folder " + string$(i) + " (" + libName$[i] + ") has no readable audio files."
        endif
    endfor
endif

# ============================================================
# 3. OUTPUT SAMPLE RATE, LAYERS, LIBRARY SETTINGS
# ============================================================
if rerender = 0
    # most common source rate (ties -> higher)
    if output_sample_rate > 0
        srOut = output_sample_rate
    else
        bestN = 0
        srOut = 44100
        for s from 1 to nSrc
            cnt = 0
            for s2 from 1 to nSrc
                if abs(srcSr[s2] - srcSr[s]) < 0.5
                    cnt = cnt + 1
                endif
            endfor
            if cnt > bestN or (cnt = bestN and srcSr[s] > srOut)
                bestN = cnt
                srOut = srcSr[s]
            endif
        endfor
    endif

    nOutCh = nOutChWanted

    # per-library defaults
    for i from 1 to nLib
        libGain[i] = 0
        if nLib = 1
            libCentre[i] = 0
            libWidth[i] = 1
        else
            libCentre[i] = -0.75 + 1.5 * (i - 1) / (nLib - 1)
            libWidth[i] = 0.75 / nLib + 0.1
        endif
        libPreset[i] = temporal_preset
        libDensity[i] = 1
        libRest[i] = 0
        if i > 1
            libRest[i] = 0.1
        endif
        libSeed[i] = i
    endfor
    # v2.0 preset defaults per library (shown in Edit layers)
    # Counterpoint: every layer its own temporal shape and pace, and a
    # narrower region of space
    cpShape[1] = 1
    cpShape[2] = 2
    cpShape[3] = 5
    cpShape[4] = 3
    cpShape[5] = 4
    cpPace[1] = 1
    cpPace[2] = 0.75
    cpPace[3] = 1.25
    cpPace[4] = 0.9
    cpPace[5] = 1.1
    if counterpoint = 1 and nLib > 1
        for i from 1 to nLib
            libPreset[i] = cpShape[i]
            libDensity[i] = cpPace[i]
            libWidth[i] = 0.5 / nLib + 0.05
        endfor
    endif
    if layerStagger > 0
        # Accumulation: every layer plays once it has entered
        for i from 1 to nLib
            libRest[i] = 0
        endfor
    endif
    if edit_layers
        for i from 1 to nLib
            beginPause: "Layer " + string$(i) + " of " + string$(nLib)
                comment: "Library: " + libName$[i] + "  (" + string$(libCount[i]) + " files)"
                comment: "Preset, density and rest apply in Independent layers mode."
                comment: "(Position and spread in space: Edit spatial layout.)"
                optionmenu: "Layer_preset", libPreset[i]
                    option: "Short to long"
                    option: "Long to short"
                    option: "Arch (short-long-short)"
                    option: "Inverted arch (long-short-long)"
                    option: "Waves"
                    option: "Controlled random"
                real: "Density_factor", string$(libDensity[i])
                real: "Gain_dB", string$(libGain[i])
                real: "Rest_probability", string$(libRest[i])
                integer: "Seed_offset", string$(libSeed[i])
            endPause: "Continue", 1
            libPreset[i] = layer_preset
            libDensity[i] = max(0.05, density_factor)
            libGain[i] = gain_dB
            libRest[i] = max(0, min(0.95, rest_probability))
            libSeed[i] = seed_offset
        endfor
    endif

    # ---- Library Loudness Balance ----
    # Reference per library = MEDIAN active-signal level (dB) of its
    # reliable files, so a few very loud or quiet files, silent files
    # and file durations do not move it. The common reference is the
    # median of the library references. Corrections are in dB:
    #   Off     none (manual Gain_dB ignored too: original levels)
    #   Gentle  half the difference, limited to +/-6 dB, + manual gain
    #   Full    the whole difference, limited to +/-Max_correction, + manual
    #   Manual  only the per-library Gain_dB
    # Individual files keep their level differences inside a library
    # unless Per-file leveling is on (half the distance to the library
    # reference, bounded by File_level_limit, reliable files only).
    nRefLib = 0
    for i from 1 to nLib
        n = 0
        for s from 1 to nSrc
            if srcLib[s] = i and srcReliable[s] = 1
                n = n + 1
                medBuf[n] = srcActDb[s]
            endif
        endfor
        libRef[i] = undefined
        libNRel[i] = n
        if n > 0
            @median: n
            libRef[i] = median.v
            nRefLib = nRefLib + 1
            refBuf[nRefLib] = libRef[i]
        endif
    endfor
    globalRef = undefined
    if nRefLib > 0
        for k from 1 to nRefLib
            medBuf[k] = refBuf[k]
        endfor
        @median: nRefLib
        globalRef = median.v
    endif
    for i from 1 to nLib
        libAuto[i] = 0
        libManual[i] = libGain[i]
        if library_balance = 1
            libManual[i] = 0
        endif
        if libRef[i] <> undefined and globalRef <> undefined
            dlt = globalRef - libRef[i]
            if library_balance = 2
                libAuto[i] = max(-6, min(6, 0.5 * dlt))
            elsif library_balance = 3
                libAuto[i] = max(-max_correction, min(max_correction, dlt))
            endif
        endif
    endfor
    for s from 1 to nSrc
        srcFileDb[s] = 0
        if per_file_leveling and srcReliable[s] = 1 and libRef[srcLib[s]] <> undefined
            srcFileDb[s] = max(-file_level_limit, min(file_level_limit, 0.5 * (libRef[srcLib[s]] - srcActDb[s])))
        endif
    endfor

    # layers
    nStreams = 0
    if organization = 1
        nLayers = 1
        layerPreset[1] = temporal_preset
        layerDensity[1] = 1
        layerRest[1] = 0
        layerSeed[1] = 1
        layerLibOf[1] = 1
        layerN[1] = 0
        for s from 1 to nSrc
            layerN[1] = layerN[1] + 1
            layerSrc[1, layerN[1]] = s
        endfor
    elsif nLib = 1 and streamsWanted > 1
        # v2.0: ONE folder, several independent streams drawn from the
        # same pool (Accumulation, Spatial Counterpoint). The streams
        # share every source and its repetition limit.
        nStreams = streamsWanted
        nLayers = nStreams
        for lay from 1 to nLayers
            layerLibOf[lay] = 1
            layerPreset[lay] = libPreset[1]
            layerDensity[lay] = libDensity[1]
            if counterpoint = 1
                layerPreset[lay] = cpShape[lay]
                layerDensity[lay] = libDensity[1] * cpPace[lay]
            endif
            layerRest[lay] = 0
            if lay > 1 and layerStagger = 0
                layerRest[lay] = 0.1
            endif
            layerSeed[lay] = libSeed[1] + lay - 1
            layerN[lay] = 0
            for s from 1 to nSrc
                layerN[lay] = layerN[lay] + 1
                layerSrc[lay, layerN[lay]] = s
            endfor
        endfor
    else
        nLayers = 0
        for i from 1 to nLib
            if libCount[i] > 0
                nLayers = nLayers + 1
                layerLibOf[nLayers] = i
                layerPreset[nLayers] = libPreset[i]
                layerDensity[nLayers] = libDensity[i]
                layerRest[nLayers] = libRest[i]
                layerSeed[nLayers] = libSeed[i]
                layerN[nLayers] = 0
                for s from 1 to nSrc
                    if srcLib[s] = i
                        layerN[nLayers] = layerN[nLayers] + 1
                        layerSrc[nLayers, layerN[nLayers]] = s
                    endif
                endfor
            endif
        endfor
    endif

    # ---- v2.1 spatial layout: one region per layer (Independent
    # layers) or per folder (Combined pool); streams get their own ----
    if organization = 2
        nReg = nLayers
        for r from 1 to nReg
            regC[r] = libCentre[layerLibOf[r]]
            regW[r] = libWidth[layerLibOf[r]]
            regName$[r] = libName$[layerLibOf[r]]
            if nStreams > 1
                regC[r] = -0.75 + 1.5 * (r - 1) / (nStreams - 1)
                regW[r] = 0.5 / nStreams + 0.05
                regName$[r] = libName$[1] + " / stream " + string$(r)
            endif
        endfor
    else
        nReg = nLib
        for r from 1 to nReg
            regC[r] = libCentre[r]
            regW[r] = libWidth[r]
            regName$[r] = libName$[r]
        endfor
    endif
    for r from 1 to nReg
        regC0[r] = regC[r]
        regW0[r] = regW[r]
    endfor
    stream_sources = 1
    if edit_spatial_layout
        # the dialog's variables hold the current values (also when the
        # pause is skipped, as in a non-interactive run)
        for r from 1 to nReg
            position_'r' = regC[r]
            spread_'r' = regW[r]
        endfor
        beginPause: "TimeLine Composer - spatial layout"
            comment: "Behaviour: " + spName$[spatial_preset] + " (from the preset or the composition controls)"
            comment: "Position: -1 = left ... 0 = centre ... +1 = right.  Spread: how far sounds scatter around it."
            if spatial_preset = 7
                comment: "Layer-based space always keeps every layer inside its region."
            else
                comment: "Spatial movement: 0 = each layer stays in its region and the behaviour acts inside it;"
                comment: "1 = the behaviour uses the whole field and the positions below have no effect."
            endif
            real: "Spatial_movement", fixed$(spatial_movement, 2)
            if nStreams > 1
                optionmenu: "Stream_sources", 1
                    option: "Shared pool (every stream draws from all the files)"
                    option: "Split the files (each file belongs to one stream)"
            endif
            for r from 1 to nReg
                comment: string$(r) + ": " + regName$[r]
                real: "Position_" + string$(r), fixed$(regC[r], 2)
                real: "Spread_" + string$(r), fixed$(regW[r], 2)
            endfor
        clicked = endPause: "Cancel", "Continue", 2, 1
        if clicked = 1
            @fail: "Cancelled: nothing was done."
        endif
        spatial_movement = max(0, min(1, spatial_movement))
        for r from 1 to nReg
            regC[r] = max(-1, min(1, position_'r'))
            regW[r] = max(0, min(2, spread_'r'))
        endfor
    endif
    placeEdited = 0
    for r from 1 to nReg
        if abs(regC[r] - regC0[r]) > 1e-9 or abs(regW[r] - regW0[r]) > 1e-9
            placeEdited = 1
        endif
    endfor
    if placeEdited = 1 and spatial_movement >= 1 and spatial_preset <> 7
        @warn: "Positions were edited but Spatial movement = 1: the behaviour uses the whole field, so they have no effect."
    endif
    # split the files of one folder between its streams: sorted by
    # duration and dealt in turn, so every stream keeps its own files
    # with a similar range of durations
    if nStreams > 1 and stream_sources = 2
        Create Table with column names: "tl_split", nSrc, "s dur"
        sp = selected("Table")
        @addTemp: sp
        for k from 1 to nSrc
            Set numeric value: k, "s", k
            Set numeric value: k, "dur", srcDur[k]
        endfor
        Sort rows: "dur"
        for lay from 1 to nLayers
            layerN[lay] = 0
        endfor
        for k from 1 to nSrc
            s = Get value: k, "s"
            lay = ((k - 1) mod nLayers) + 1
            layerN[lay] = layerN[lay] + 1
            layerSrc[lay, layerN[lay]] = s
        endfor
        removeObject: sp
        @dropTemp: sp
    endif

    # exclude sources that can never fit; rank the rest by duration
    nTooLong = 0
    shortest = 1e9
    for lay from 1 to nLayers
        Create Table with column names: "tl_rank", layerN[lay], "s dur"
        rk = selected("Table")
        for k from 1 to layerN[lay]
            Set numeric value: k, "s", layerSrc[lay, k]
            Set numeric value: k, "dur", srcDur[layerSrc[lay, k]]
        endfor
        Sort rows: "dur"
        nKeep = 0
        for k from 1 to layerN[lay]
            s = Get value: k, "s"
            if srcDur[s] <= target_duration
                nKeep = nKeep + 1
                layerSrc[lay, nKeep] = s
                shortest = min(shortest, srcDur[s])
            else
                nTooLong = nTooLong + 1
            endif
        endfor
        removeObject: rk
        layerN[lay] = nKeep
        for k from 1 to nKeep
            if nKeep = 1
                srcRank[layerSrc[lay, k]] = 0.5
            else
                srcRank[layerSrc[lay, k]] = (k - 1) / (nKeep - 1)
            endif
        endfor
        layerLast[lay] = 0
        altCount[lay] = 0
    endfor
    if nTooLong > 0
        @warn: string$(nTooLong) + " source(s) are longer than the target duration and were excluded (never truncated)."
    endif
    usable = 0
    for lay from 1 to nLayers
        usable = usable + layerN[lay]
    endfor
    if usable = 0
        @fail: "Impossible: every source is longer than the target duration ("
            ... + fixed$(target_duration, 1) + " s). Recordings are never truncated."
    endif
    for lay from 1 to nLayers
        if layerN[lay] = 0
            @warn: "Layer " + string$(lay) + " has no source short enough for the timeline; it stays silent."
        endif
    endfor
    # share of a shared pool (streams) and entry time (Accumulation)
    for lay from 1 to nLayers
        layerShare[lay] = 1
        if nStreams > 1 and stream_sources = 1
            layerShare[lay] = 1 / nStreams
        endif
        layerEntry[lay] = 0
        if layerStagger > 0 and nLayers > 1
            layerEntry[lay] = layerStagger * target_duration * (lay - 1) / nLayers
        endif
    endfor
endif
tScan = stopwatch

# ============================================================
# 4. PLAN
# ============================================================
# conductor constants
if conductor_preset = 1
    xcEff = 1
elsif conductor_preset = 2
    xcEff = 0
elsif conductor_preset = 4
    xcEff = max(climax_position / 100, 0.6)
elsif conductor_preset = 5
    xcEff = min(climax_position / 100, 0.4)
else
    xcEff = climax_position / 100
endif
xcEff = max(0, min(1, xcEff))
if conductor_preset >= 3
    xcEff = max(0.02, min(0.98, xcEff))
endif
# Controlled Chaos: stepped conductor levels, fixed by the seed
for k from 0 to 15
    jagF[k] = 1
endfor
if condJag = 1
    random_initializeWithSeedUnsafelyButPredictably (random_seed * 6151 + 29)
    for k from 0 to 15
        jagF[k] = randomUniform(0.25, 1)
    endfor
    random_initializeSafelyAndUnpredictably ()
endif
wavesNorm = 1
if conductor_preset = 6
    wavesNorm = 1
    mx = 0
    for k from 0 to 1000
        @cond: k / 1000
        mx = max(mx, cond.v)
    endfor
    wavesNorm = mx
endif
# where the curve actually peaks
cBest = -1
xPeak = 0
for k from 0 to 1000
    @cond: k / 1000
    if cond.v > cBest
        cBest = cond.v
        xPeak = k / 1000
    endif
endfor

if rerender = 0
    appendInfoLine: "Planning..."
    tDur = target_duration
    tol = max(0.25, 0.005 * tDur)
    # the musical end: target minus a deliberate ending silence
    endTime = tDur - ending_silence
    minPh = max(1, 1.5 * shortest)

    # ---- silence plan: count, lengths ----
    random_initializeWithSeedUnsafelyButPredictably (random_seed * 7919 + 17)
    sTot = silence_amount / 100 * tDur
    nK = 0
    plc = silence_placement
    if plc = 1
        if silence_mode = 2
            plc = 4
        elsif silence_mode = 3
            plc = 3
        else
            plc = 5
        endif
    endif
    if silence_mode > 1 and sTot > 0
        if silence_mode = 2
            meanS = min_silence + 0.25 * (max_silence - min_silence)
        elsif silence_mode = 3
            meanS = min_silence + 0.7 * (max_silence - min_silence)
        else
            meanS = min_silence + 0.5 * (max_silence - min_silence)
        endif
        nK = max(1, round(sTot / meanS))
        if silence_mode = 3
            nK = min(nK, 8)
        endif
        if nK * max_silence < sTot
            nK = ceiling(sTot / max_silence)
        endif
        if sTot < min_silence
            nK = 1
            @warn: "Silence amount (" + fixed$(sTot, 1) + " s) is below the minimum silence; one " + fixed$(min_silence, 1) + " s silence is used instead."
            sTot = min_silence
        endif
        # phrases must be able to hold at least one event
        while nK > 0 and (nK + 1) * minPh + sTot > tDur
            nK = nK - 1
        endwhile
        if nK = 0
            @warn: "Silence plan impossible with these sources and this duration: no absolute silence was placed."
            sTot = 0
        endif
        # lengths
        for k from 1 to nK
            if silence_mode = 2
                silD[k] = randomUniform(min_silence, min_silence + 0.5 * (max_silence - min_silence))
            elsif silence_mode = 3
                silD[k] = randomUniform(min_silence + 0.4 * (max_silence - min_silence), max_silence)
            else
                silD[k] = randomUniform(min_silence, min_silence + 0.6 * (max_silence - min_silence))
            endif
        endfor
        grand = 0
        if silence_mode = 4 or plc = 5 or plc = 6
            grand = 1
            silD[1] = min(max_silence, max(min_silence, 0.5 * sTot))
            if ruptureMode = 1
                # the rupture is THE silence: three quarters of the budget
                silD[1] = min(max_silence, max(min_silence, 0.75 * sTot))
            endif
        endif
        # rescale to sTot within [min, max]
        for it from 1 to 12
            sumD = 0
            for k from 1 to nK
                if grand = 0 or k > 1
                    sumD = sumD + silD[k]
                endif
            endfor
            want = sTot
            if grand = 1
                want = sTot - silD[1]
            endif
            if sumD > 0
                f = want / sumD
                for k from 1 to nK
                    if grand = 0 or k > 1
                        silD[k] = max(min_silence, min(max_silence, silD[k] * f))
                    endif
                endfor
            endif
        endfor
        sumD = 0
        for k from 1 to nK
            sumD = sumD + silD[k]
        endfor
        sTot = sumD
    endif
    nSilP = nK

    # ---- silence placement: centre positions (fractions of tDur) ----
    if nK > 0
                if plc = 3
            for k from 1 to nK
                silF[k] = k / (nK + 1)
            endfor
        elsif plc = 4
            for k from 1 to nK
                silF[k] = (k + randomUniform(-0.3, 0.3)) / (nK + 1)
            endfor
        elsif plc = 2
            for k from 1 to nK
                silF[k] = randomUniform(0.08, 0.92)
            endfor
        elsif plc = 7
            for k from 1 to nK
                tries = 0
                ok = 0
                while ok = 0 and tries < 400
                    tries = tries + 1
                    xx = randomUniform(0.06, 0.94)
                    @cond: xx
                    if randomUniform(0, 1) < (1 - cond.v) ^ 2
                        ok = 1
                        for k2 from 1 to k - 1
                            if abs(silF[k2] - xx) < 0.5 / (nK + 1)
                                ok = 0
                            endif
                        endfor
                    endif
                endwhile
                silF[k] = xx
                @cond: xx
                silD[k] = silD[k] * (0.6 + 0.8 * (1 - cond.v))
            endfor
        endif
        if plc = 5 or plc = 6
            # silence 1 is the grand pause, at the climax
            xcl = max(0.1, min(0.9, xPeak))
            if plc = 5
                silF[1] = xcl - silD[1] / 2 / tDur
            elsif ruptureMode = 1
                # Climax & Rupture: the pause begins at the peak itself
                silF[1] = xcl + silD[1] / 2 / tDur
            else
                silF[1] = xcl + 0.04 + silD[1] / 2 / tDur
            endif
            # the others spread evenly on both sides
            nBefore = round((nK - 1) * xcl)
            nAfter = nK - 1 - nBefore
            k = 1
            for b from 1 to nBefore
                k = k + 1
                silF[k] = (silF[1] - 0.03) * b / (nBefore + 1)
            endfor
            for a from 1 to nAfter
                k = k + 1
                silF[k] = silF[1] + 0.03 + (0.97 - silF[1]) * a / (nAfter + 1)
            endfor
        endif
        # sort positions (keep lengths with them)
        for i from 2 to nK
            a = silF[i]
            b = silD[i]
            j = i - 1
            mv = 1
            while mv = 1
                if j < 1
                    mv = 0
                elsif silF[j] > a
                    silF[j + 1] = silF[j]
                    silD[j + 1] = silD[j]
                    j = j - 1
                else
                    mv = 0
                endif
            endwhile
            silF[j + 1] = a
            silD[j + 1] = b
        endfor
        # anchors: silence k starts at B_k; keep phrases >= minPh
        prev = 0
        for k from 1 to nK
            silB[k] = silF[k] * tDur - silD[k] / 2
            silB[k] = max(silB[k], prev + minPh)
            prev = silB[k] + silD[k]
        endfor
        # push back from the end if needed
        nextStart = endTime
        for kk from 1 to nK
            k = nK + 1 - kk
            if silB[k] + silD[k] + minPh > nextStart
                silB[k] = nextStart - minPh - silD[k]
            endif
            nextStart = silB[k]
        endfor
    endif

    # ---- material budget ----
    # Expected entrances per layer (density x conductor over the active
    # time) against what its sources can supply (files x max repetitions).
    # When short, the density is scaled down uniformly, so the conductor's
    # shape survives with fewer events instead of the material running
    # out before the climax.
    nDensityScaled = 0
    for lay from 1 to nLayers
        # expected spacing from the v1.1 model with the layer's mean duration
        mD = 0
        for k from 1 to layerN[lay]
            mD = mD + srcDur[layerSrc[lay, k]]
        endfor
        mD = mD / max(1, layerN[lay])
        dem = 0
        for k from 1 to 200
            @cond: (k - 0.5) / 200
            iD = 60 / (event_density * layerDensity[lay] * 2 ^ (density_influence * (2 * cond.v - 1) * 1.25))
            oE = max(0, min(1, overlap + 0.35 * density_influence * (2 * cond.v - 1)))
            iO = iD ^ 0.4 * max(0.02, mD * (1 - 0.95 * oE)) ^ 0.6
            dem = dem + tDur / 200 / iO
        endfor
        dem = dem * (1 - sTot / tDur) * (1 - layerRest[lay]) * (1 - layerEntry[lay] / tDur)
        avail = layerN[lay] * max_repetitions * layerShare[lay]
        layerDemand[lay] = dem
        layerAvail[lay] = avail
        layerDensityScale[lay] = 1
        if dem > 0.75 * avail and dem > 0
            # density enters the spacing with exponent 0.4, so scaling the
            # entrances by r needs the density scaled by r ^ 2.5
            layerDensityScale[lay] = max(0.02, (0.75 * avail / dem) ^ 2.5)
            layerDensity[lay] = layerDensity[lay] * layerDensityScale[lay]
            nDensityScaled = nDensityScaled + 1
            @warn: "Layer " + string$(lay) + ": about " + fixed$(dem, 0) + " entrances wanted but only "
                ... + string$(avail) + " available (files x max repetitions) - entrance rate reduced to x"
                ... + fixed$(0.75 * avail / dem, 2) + " (density x" + fixed$(layerDensityScale[lay], 3)
                ... + ") to keep material for the whole form."
        endif
    endfor

    # cumulative share of entrances over the form (pacing)
    cumF[0] = 0
    accF = 0
    for k from 1 to 200
        @cond: (k - 0.5) / 200
        accF = accF + 2 ^ (density_influence * (2 * cond.v - 1) * 1.25)
        cumF[k] = accF
    endfor
    for k from 1 to 200
        cumF[k] = cumF[k] / accF
    endfor
    for lay from 1 to nLayers
        layerUsed[lay] = 0
    endfor
    repairing = 0
    pacingOn = 1

    # ---- sequential phrase scheduling ----
    nEv = 0
    nBridged = 0
    nRepaired = 0
    repairNext = 0
    cur = 0
    nPh = nK + 1
    silDone = 0
    incidental = 0
    nGapPlan = 0
    j = 0
    while j < nPh
        j = j + 1
        ws = cur
        if j <= nK
            we = silB[j]
            if we < ws + minPh
                we = ws + minPh
            endif
        else
            we = endTime
        endif
        we = min(we, endTime)
        phStart[j] = ws
        phDeadline[j] = we
        e0 = nEv + 1
        # which layers play in this phrase
        nAct = 0
        for lay from 1 to nLayers
            random_initializeWithSeedUnsafelyButPredictably ((random_seed * 7919 + lay * 104729
                ... + j * 1299709 + layerSeed[lay] * 15485863) mod 2147483647)
            plays[lay] = 0
            if layerN[lay] > 0
                plays[lay] = 1
                if randomUniform(0, 1) < layerRest[lay]
                    plays[lay] = 0
                endif
            endif
            nAct = nAct + plays[lay]
        endfor
        if nAct = 0
            for lay from 1 to nLayers
                if nAct = 0 and layerN[lay] > 0
                    plays[lay] = 1
                    nAct = 1
                endif
            endfor
        endif
        lead = 0
        for lay from 1 to nLayers
            if plays[lay] = 1
                random_initializeWithSeedUnsafelyButPredictably ((random_seed * 7919 + lay * 104729
                    ... + j * 1299709 + layerSeed[lay] * 15485863 + 7) mod 2147483647)
                isLead = 0
                if lead = 0
                    lead = lay
                    isLead = 1
                endif
                @scheduleLayer: lay, ws, we, j, isLead
            endif
        endfor
        # repair holes (also a late phrase start), then a closing
        # event that ends the phrase at its deadline - lead layer first,
        # then the others
        @repairPhrase: e0, ws, we, j
        tailNow = ws
        for ie from e0 to nEv
            tailNow = max(tailNow, evEnd[ie])
        endfor
        if we - tailNow > tol
            bestS = 0
            bestLay = 0
            bestD = 1e9
            altS = 0
            altLay = 0
            altD = -1
            for li from 1 to nLayers
                lay = ((max(lead, 1) + li - 2) mod nLayers) + 1
                if plays[lay] = 1
                    for k from 1 to layerN[lay]
                        s = layerSrc[lay, k]
                        if srcUses[s] < max_repetitions and srcDur[s] <= we - ws and we - srcDur[s] >= layerEntry[lay]
                            if srcDur[s] >= we - tailNow and srcDur[s] < bestD
                                bestD = srcDur[s]
                                bestS = s
                                bestLay = lay
                            endif
                            if srcDur[s] > altD
                                altD = srcDur[s]
                                altS = s
                                altLay = lay
                            endif
                        endif
                    endfor
                endif
            endfor
            if bestS = 0
                bestS = altS
                bestLay = altLay
            endif
            if bestS > 0
                onC = floor((we - srcDur[bestS]) * srOut) / srOut
                if onC >= ws
                    @addEvent: bestLay, bestS, onC, j, 1
                    # a closing sound that starts after the tail would open a
                    # hole: repair it
                    @repairPhrase: e0, ws, we, j
                endif
            endif
        endif
        phEnd = ws
        for ie from e0 to nEv
            phEnd = max(phEnd, evEnd[ie])
        endfor
        if nEv < e0
            @warn: "Phrase " + string$(j) + " is empty: no source fits its window."
        endif
        phEnd[j] = phEnd
        # silence that happened inside this phrase
        if nEv >= e0
            @unionGaps: e0, nEv, ws, phEnd
            incidental = incidental + unionGaps.total
        endif
        if j <= nK
            # take incidental silence off the remaining planned silences
            remPlanned = 0
            for k from j to nK
                remPlanned = remPlanned + silD[k]
            endfor
            want = sTot - silDone - incidental
            if want < remPlanned and remPlanned > 0
                f = max(0, want / remPlanned)
                for k from j to nK
                    silD[k] = max(min_silence, silD[k] * f)
                endfor
            endif
            silStartP[j] = phEnd
            silEndP[j] = phEnd + silD[j]
            silDone = silDone + silD[j]
            cur = phEnd + silD[j]
            if cur >= endTime - minPh
                @warn: "No room left after silence " + string$(j) + "; the remaining phrases were dropped."
                nPh = j
                nK = j
                nSilP = j
                silEndP[j] = min(silEndP[j], tDur)
            endif
        endif
    endwhile

    # ---- measured timeline ----
    @unionGaps: 1, nEv, 0, tDur
    nGap = unionGaps.count
    for k from 1 to nGap
        gapS[k] = ugGapS[k]
        gapE[k] = ugGapE[k]
    endfor
    silMeasured = unionGaps.total
    # unplanned silence = measured minus what the Silence Engine placed
    plannedReal = ending_silence
    for k from 1 to nSilP
        plannedReal = plannedReal + max(0, min(silEndP[k], tDur) - silStartP[k])
    endfor
    unplanned = silMeasured - plannedReal
    if unplanned > tol
        nAtMax = 0
        nFit = 0
        for lay from 1 to nLayers
            for k from 1 to layerN[lay]
                nFit = nFit + 1
                if srcUses[layerSrc[lay, k]] >= max_repetitions
                    nAtMax = nAtMax + 1
                endif
            endfor
        endfor
        @warn: fixed$(unplanned, 1) + " s of silence were not planned: no unused source fits those holes ("
            ... + string$(nAtMax) + " of " + string$(nFit) + " usable sources are at Max repetitions = "
            ... + string$(max_repetitions) + "). Add material, raise Max repetitions, or lower the density."
    endif
    lastEnd = 0
    firstOn = tDur
    for ie from 1 to nEv
        lastEnd = max(lastEnd, evEnd[ie])
        firstOn = min(firstOn, evOn[ie])
    endfor
    random_initializeSafelyAndUnpredictably ()
endif

# For a re-render, rebuild the measured silences from the events.
if rerender = 1
    tDur = target_duration
    endTime = tDur - ending_silence
    @unionGaps: 1, nEv, 0, tDur
    nGap = unionGaps.count
    for k from 1 to nGap
        gapS[k] = ugGapS[k]
        gapE[k] = ugGapE[k]
    endfor
    silMeasured = unionGaps.total
    lastEnd = 0
    for ie from 1 to nEv
        lastEnd = max(lastEnd, evEnd[ie])
    endfor
    tol = max(0.25, 0.005 * tDur)
endif

# voice lanes for the drawing (greedy, per layer)
maxLane = 1
for ie from 1 to nEv
    lane = 1
    busy = 1
    while busy = 1
        busy = 0
        for e2 from 1 to ie - 1
            if evLayer[e2] = evLayer[ie] and evLane[e2] = lane and evEnd[e2] > evOn[ie] + 1e-9 and evOn[e2] < evEnd[ie]
                busy = 1
            endif
        endfor
        if busy = 1
            lane = lane + 1
        endif
    endwhile
    evLane[ie] = lane
    maxLane = max(maxLane, lane)
endfor
for lay from 1 to nLayers
    layerLanes[lay] = 1
endfor
for ie from 1 to nEv
    layerLanes[evLayer[ie]] = max(layerLanes[evLayer[ie]], evLane[ie])
endfor

tPlan = stopwatch

# ============================================================
# 5. NAMES
# ============================================================
if rerender = 0
    objBase$ = "TimeLine_Seed" + string$(random_seed)
else
    objBase$ = replace$(baseShort$, "TimeLine_seed", "TimeLine_Seed", 1) + "_render"
endif
if nOutCh > 2
    mixName$ = objBase$ + "_mc" + string$(nOutCh)
    mixSuffix$ = "_mc" + string$(nOutCh) + ".wav"
else
    mixName$ = objBase$
    mixSuffix$ = "_stereo.wav"
endif
savedFiles = 0

# ============================================================
# 6. PLAN AND SETTINGS AS TABLES (in memory; saved only on request)
# ============================================================
planID = 0
setID = 0
if rerender = 0
    Create Table with column names: objBase$ + "_plan", nEv + nSilP,
        ... "kind n layer library library_name source path onset duration end gain_db position width fade_in fade_out source_rate source_channels conductor phrase closing balance_db manual_db file_db conductor_db random_db"
    planID = selected("Table")
    @addTemp: planID
    for ie from 1 to nEv
        s = evSrc[ie]
        Set string value: ie, "kind", "event"
        Set numeric value: ie, "n", ie
        Set numeric value: ie, "layer", evLayer[ie]
        Set numeric value: ie, "library", evLib[ie]
        Set string value: ie, "library_name", libName$[evLib[ie]]
        Set string value: ie, "source", srcName$[s]
        Set string value: ie, "path", srcPath$[s]
        Set numeric value: ie, "onset", evOn[ie]
        Set numeric value: ie, "duration", evDur[ie]
        Set numeric value: ie, "end", evEnd[ie]
        Set numeric value: ie, "gain_db", evGainDb[ie]
        Set numeric value: ie, "position", evPos[ie]
        Set numeric value: ie, "width", evWidth[ie]
        Set numeric value: ie, "fade_in", evFi[ie]
        Set numeric value: ie, "fade_out", evFo[ie]
        Set numeric value: ie, "source_rate", srcSr[s]
        Set numeric value: ie, "source_channels", srcCh[s]
        Set numeric value: ie, "conductor", evCond[ie]
        Set numeric value: ie, "phrase", evPhrase[ie]
        Set numeric value: ie, "closing", evClosing[ie]
        Set numeric value: ie, "balance_db", evBalDb[ie]
        Set numeric value: ie, "manual_db", evManDb[ie]
        Set numeric value: ie, "file_db", evFileDb[ie]
        Set numeric value: ie, "conductor_db", evCondDb[ie]
        Set numeric value: ie, "random_db", evRandDb[ie]
    endfor
    for k from 1 to nSilP
        r = nEv + k
        Set string value: r, "kind", "silence"
        Set numeric value: r, "n", k
        Set numeric value: r, "layer", 0
        Set numeric value: r, "library", 0
        Set string value: r, "library_name", "-"
        Set string value: r, "source", "-"
        Set string value: r, "path", "-"
        Set numeric value: r, "onset", silStartP[k]
        Set numeric value: r, "duration", silEndP[k] - silStartP[k]
        Set numeric value: r, "end", silEndP[k]
        @cond: silStartP[k] / tDur
        Set numeric value: r, "conductor", cond.v
        Set numeric value: r, "phrase", k
        # numeric cells left empty would read back as "?"
        Set numeric value: r, "gain_db", 0
        Set numeric value: r, "position", 0
        Set numeric value: r, "width", 0
        Set numeric value: r, "fade_in", 0
        Set numeric value: r, "fade_out", 0
        Set numeric value: r, "source_rate", 0
        Set numeric value: r, "source_channels", 0
        Set numeric value: r, "closing", 0
        Set numeric value: r, "balance_db", 0
        Set numeric value: r, "manual_db", 0
        Set numeric value: r, "file_db", 0
        Set numeric value: r, "conductor_db", 0
        Set numeric value: r, "random_db", 0
    endfor

    Create Table with column names: objBase$ + "_settings", 0, "key value"
    setID = selected("Table")
    @addTemp: setID
    @kv: "script", "TimeLine_Composer.praat v2.3"
    @kv: "praat_version", praatVersion$
    @kv: "target_duration", string$(target_duration)
    @kv: "ending_silence", string$(ending_silence)
    @kv: "organization", string$(organization)
    @kv: "temporal_preset", string$(temporal_preset)
    @kv: "event_density", string$(event_density)
    @kv: "overlap", string$(overlap)
    @kv: "overlap_model", "v1.1: IOI = IOIdensity^0.4 * (duration * (1 - 0.95 overlap))^0.6"
    @kv: "random_seed", string$(random_seed)
    @kv: "duration_order_strictness", string$(duration_order_strictness)
    @kv: "duration_preference", string$(duration_preference)
    @kv: "randomness", string$(randomness)
    @kv: "max_repetitions", string$(max_repetitions)
    @kv: "silence_mode", string$(silence_mode)
    @kv: "silence_amount", string$(silence_amount)
    @kv: "min_silence", string$(min_silence)
    @kv: "max_silence", string$(max_silence)
    @kv: "silence_placement", string$(silence_placement)
    @kv: "conductor_preset", string$(conductor_preset)
    @kv: "climax_position", string$(climax_position)
    @kv: "dynamics_influence", string$(dynamics_influence)
    @kv: "density_influence", string$(density_influence)
    @kv: "spatial_influence", string$(spatial_influence)
    @kv: "dynamic_range", string$(dynamic_range)
    @kv: "spatial_preset", string$(spatial_preset)
    @kv: "composition_preset", cpName$[composition_preset]
    @kv: "compositional_intensity", string$(compositional_intensity)
    @kv: "wave_cycles", string$(waveCycles)
    @kv: "conductor_steps", string$(condJag)
    @kv: "rupture_at_peak", string$(ruptureMode)
    @kv: "streams", string$(nStreams)
    @kv: "spatial_movement", string$(spatial_movement)
    @kv: "stream_sources", if stream_sources = 2 then "split" else "shared" fi
    @kv: "regions", string$(nReg)
    for r from 1 to nReg
        @kv: "region_" + string$(r) + "_name", regName$[r]
        @kv: "region_" + string$(r) + "_position", string$(regC[r])
        @kv: "region_" + string$(r) + "_spread", string$(regW[r])
    endfor
    @kv: "layer_entry_span", string$(layerStagger)
    @kv: "library_balance", balName$[library_balance]
    @kv: "max_correction", string$(max_correction)
    @kv: "per_file_leveling", string$(per_file_leveling)
    @kv: "file_level_limit", string$(file_level_limit)
    @kv: "output_channels", string$(nOutCh)
    @kv: "output_sample_rate", string$(srOut)
    @kv: "event_fade_in", string$(event_fade_in)
    @kv: "event_fade_out", string$(event_fade_out)
    @kv: "final_fade", string$(final_fade)
    @kv: "normalize", string$(normalize)
    @kv: "peak_dBFS", string$(peak_dBFS)
    @kv: "libraries", string$(nLib)
    @kv: "layers", string$(nLayers)
    for i from 1 to nLib
        @kv: "library_" + string$(i) + "_folder", libFolder$[i]
        @kv: "library_" + string$(i) + "_name", libName$[i]
        @kv: "library_" + string$(i) + "_reference_db", string$(libRef[i])
        @kv: "library_" + string$(i) + "_balance_db", string$(libAuto[i])
        @kv: "library_" + string$(i) + "_gain_db", string$(libManual[i])
        @kv: "library_" + string$(i) + "_space_centre", string$(libCentre[i])
        @kv: "library_" + string$(i) + "_space_half_width", string$(libWidth[i])
        @kv: "library_" + string$(i) + "_preset", string$(libPreset[i])
        @kv: "library_" + string$(i) + "_density_factor", string$(libDensity[i])
        @kv: "library_" + string$(i) + "_rest_probability", string$(libRest[i])
        @kv: "library_" + string$(i) + "_seed_offset", string$(libSeed[i])
    endfor

    if save_plan
        @needOutDir: "save the composition plan"
        wPlan = 1
        wAudio = 0
        @chooseBase: replace$(objBase$, "TimeLine_Seed", "TimeLine_seed", 1)
        # the pair is written as one group: both files or neither
        @regOut: base$ + "_plan.tsv", 3, 2
        kPlan = regOut.k
        outObj[kPlan] = planID
        @regOut: base$ + "_settings.tsv", 3, 2
        kSet = regOut.k
        outObj[kSet] = setID
        selectObject: planID
        nocheck Save as tab-separated file: outWrite$[kPlan]
        outState[kPlan] = 1
        selectObject: setID
        nocheck Save as tab-separated file: outWrite$[kSet]
        outState[kSet] = 1
        selectObject: planID
        verRows = Get number of rows
        @verifyOut: kPlan, 0
        ok1 = verifyOut.ok
        selectObject: setID
        verRows = Get number of rows
        @verifyOut: kSet, 0
        if ok1 = 0 or verifyOut.ok = 0
            @fail: "Could not write the plan files to " + outDir$ + " (disk full or no permission?)."
        endif
        @commitGroup: 2
        overwriteConfirmed = 0
        savedFiles = savedFiles + 1
        savedFile$[savedFiles] = base$ + "_plan.tsv"
        savedFiles = savedFiles + 1
        savedFile$[savedFiles] = base$ + "_settings.tsv"
    endif

    if save_catalog
        @needOutDir: "save the catalog"
        Create Table with column names: "tl_catalog", nSrc,
            ... "library folder file path duration sample_rate channels rms_db peak_db active_db active_s reliable"
        catID = selected("Table")
        @addTemp: catID
        for s from 1 to nSrc
            Set numeric value: s, "library", srcLib[s]
            Set string value: s, "folder", libFolder$[srcLib[s]]
            Set string value: s, "file", srcName$[s]
            Set string value: s, "path", srcPath$[s]
            Set numeric value: s, "duration", srcDur[s]
            Set numeric value: s, "sample_rate", srcSr[s]
            Set numeric value: s, "channels", srcCh[s]
            Set numeric value: s, "rms_db", srcRmsDb[s]
            Set numeric value: s, "peak_db", srcPeakDb[s]
            Set numeric value: s, "active_db", srcActDb[s]
            Set numeric value: s, "active_s", srcActS[s]
            Set numeric value: s, "reliable", srcReliable[s]
        endfor
        @saveTableSafely: catID, outDir$ + "/TimeLine_catalog.tsv", 1
        savedFiles = savedFiles + 1
        savedFile$[savedFiles] = saveTableSafely.path$
        removeObject: catID
        @dropTemp: catID
    endif

    if planOnly
        # the plan stays in Praat, ready for "Render a saved plan"
        @dropTemp: planID
        @dropTemp: setID
    else
        removeObject: planID, setID
        @dropTemp: planID
        @dropTemp: setID
        planID = 0
        setID = 0
    endif
endif

# ============================================================
# 7. RENDER INTO PRAAT
# ============================================================
mixGain = 1
mixPeak = 0
outPeak = 0
silenceRms = 0
nWin = ceiling(tDur)
for w from 1 to nWin
    winRms[w] = 0
endfor
sinkName$ = "-"
memMB = 0
mixID = 0
nStems = 0
diskBacked = 0
if wantMix
    # the libraries that have events (one stem each)
    nStemLib = 0
    if wantStems
        for i from 1 to nLib
            has = 0
            for ie from 1 to nEv
                if evLib[ie] = i
                    has = 1
                endif
            endfor
            if has
                nStemLib = nStemLib + 1
                stemLib[nStemLib] = i
            endif
        endfor
    endif
    memMB = tDur * srOut * nOutCh * 8 / 1048576
    totalMB = memMB * (1 + nStemLib)
    targetPeak = 10 ^ (peak_dBFS / 20)
    if totalMB <= memory_budget
        sink = 1
        sinkName$ = "Sound object in memory"
    else
        # Exceptional: too large to hold. Render 30 s chunks to scratch
        # files, join them into one 16-bit WAV and open it as a
        # LongSound, which reads from that file - so the file is kept.
        sink = 2
        diskBacked = 1
        sinkName$ = "disk-backed LongSound (16-bit WAV, streamed in 30 s chunks)"
        appendInfoLine: "The result (" + fixed$(totalMB, 0) + " MB) exceeds the memory budget ("
            ... + string$(memory_budget) + " MB): it will be written to a WAV file and opened as a LongSound."
        @needOutDir: "hold the large rendered composition (a LongSound needs its file)"
    endif
    if sink = 2 or exportFiles
        if outDir$ = ""
            @needOutDir: "export the composition"
        endif
        wPlan = 0
        wAudio = 1
        @chooseBase: replace$(objBase$, "TimeLine_Seed", "TimeLine_seed", 1)
    endif

    if sink = 2 and normalize = 1
        appendInfoLine: "Rendering (pass 1: peak)..."
        renderLabel$ = "peak pass"
        @renderPass: 0, 0, 1, "", 0
        mixPeak = renderPass.peak
        if mixPeak > 0
            mixGain = targetPeak / mixPeak
        endif
    endif
    if sink = 1
        appendInfoLine: "Rendering..."
        renderLabel$ = "mix"
        nNeed = round(tDur * srOut)
        selectObject: placeholderID
        nocheck Create Sound from formula: mixName$, nOutCh, 0, nNeed / srOut, srOut, "0"
        @gotNew: "Sound", placeholderID
        mixID = gotNew.id
        if mixID = 0
            @fail: "Not enough memory for the " + fixed$(memMB, 0) + " MB result - lower the Memory budget."
        endif
        @addTemp: mixID
        bx1 = Get time from sample number: 1
        for ie from 1 to nEv
            @addEventToBuffer: ie, mixID, 0, nNeed / srOut, bx1
        endfor
        if final_fade > 0
            selectObject: mixID
            Formula (part): endTime - final_fade, endTime, 1, nOutCh,
                ... "self * max(0, min(1, (" + string$(endTime) + " - x) / " + string$(final_fade) + "))^2"
        endif
        selectObject: mixID
        mixPeak = Get absolute extremum: 0, 0, "None"
        if normalize = 1 and mixPeak > 0
            mixGain = targetPeak / mixPeak
        endif
        for w from 1 to nWin
            wa = w - 1
            wb = min(tDur, w)
            if wb - wa > 0.01
                winRms[w] = Get root-mean-square: wa, wb
            endif
        endfor
        for k from 1 to nGap
            if gapE[k] - gapS[k] > 0.02
                rms = Get root-mean-square: gapS[k] + 0.001, gapE[k] - 0.001
                silenceRms = max(silenceRms, rms)
            endif
        endfor
        if mixGain <> 1
            Multiply: mixGain
        endif
        outPeak = Get absolute extremum: 0, 0, "None"
        if exportFiles
            @regOut: base$ + mixSuffix$, 1, 3
            kMix = regOut.k
            outObj[kMix] = mixID
            nocheck Save as 24-bit WAV file: outWrite$[kMix]
            outState[kMix] = 1
            @verWindow: 0
            selectObject: mixID
            verExp = Get root-mean-square: verWa, verWb
            @verifyOut: kMix, tDur
            if verifyOut.ok = 0
                @fail: "Could not write " + outWrite$[kMix] + " (disk full or no permission?)."
            endif
            savedFiles = savedFiles + 1
            savedFile$[savedFiles] = base$ + mixSuffix$
        endif
    else
        appendInfoLine: "Rendering (streamed)..."
        renderLabel$ = "mix"
        @regOut: base$ + mixSuffix$, 2, 3
        kMix = regOut.k
        renderOutK = kMix
        @verWindow: 0
        rpWa = verWa
        rpWb = verWb
        @renderPass: 0, 2, mixGain, outWrite$[kMix], 1
        verWa = renderPass.verA
        verWb = renderPass.verB
        verExp = renderPass.verRms
        silenceRms = renderPass.silenceRms
        if normalize = 0
            mixPeak = renderPass.peak
        endif
        outPeak = renderPass.peak * mixGain
        @verifyOut: kMix, tDur
        if verifyOut.ok = 0
            @fail: "The streamed file " + outWrite$[kMix] + " is incomplete (disk full?)."
        endif
        savedFiles = savedFiles + 1
        savedFile$[savedFiles] = base$ + mixSuffix$
        selectObject: placeholderID
        nocheck Open long sound file: outWrite$[kMix]
        @gotNew: "LongSound", placeholderID
        mixID = gotNew.id
        if mixID = 0
            @fail: "Cannot open the rendered file " + outWrite$[kMix] + " as a LongSound."
        endif
        Rename: mixName$
        @addTemp: mixID
        outObj[kMix] = mixID
    endif
    if outPeak > 1
        @warn: "The mix peaks at " + fixed$(outPeak, 3) + " (above 0 dBFS) and clips - switch Normalize on."
    endif
    # stems: the same gain as the mix, so they sum to the mix
    for si from 1 to nStemLib
        i = stemLib[si]
        nStems = nStems + 1
        stemName$[nStems] = objBase$ + "_stem" + string$(i) + "_" + libName$[i]
        appendInfoLine: "Rendering stem ", i, " (", libName$[i], ")..."
        renderLabel$ = "stem " + string$(i)
        if sink = 1
            @renderPass: i, 1, mixGain, "", 0
            stemID[nStems] = renderPass.bufID
            selectObject: stemID[nStems]
            Rename: stemName$[nStems]
            @addTemp: stemID[nStems]
            if exportFiles
                @regOut: base$ + "_stem" + string$(i) + "_" + libName$[i] + ".wav", 1, 3
                kS = regOut.k
                outObj[kS] = stemID[nStems]
                selectObject: stemID[nStems]
                nocheck Save as 24-bit WAV file: outWrite$[kS]
                outState[kS] = 1
                @verWindow: i
                selectObject: stemID[nStems]
                verExp = Get root-mean-square: verWa, verWb
                @verifyOut: kS, tDur
                if verifyOut.ok = 0
                    @fail: "Could not write " + outWrite$[kS] + " (disk full or no permission?)."
                endif
                savedFiles = savedFiles + 1
                savedFile$[savedFiles] = outTarget$[kS]
            endif
        else
            @regOut: base$ + "_stem" + string$(i) + "_" + libName$[i] + ".wav", 2, 3
            kS = regOut.k
            renderOutK = kS
            @verWindow: i
            rpWa = verWa
            rpWb = verWb
            @renderPass: i, 2, mixGain, outWrite$[kS], 0
            verWa = renderPass.verA
            verWb = renderPass.verB
            verExp = renderPass.verRms
            @verifyOut: kS, tDur
            if verifyOut.ok = 0
                @fail: "The streamed stem " + outWrite$[kS] + " is incomplete (disk full?)."
            endif
            savedFiles = savedFiles + 1
            savedFile$[savedFiles] = outTarget$[kS]
            selectObject: placeholderID
            nocheck Open long sound file: outWrite$[kS]
            @gotNew: "LongSound", placeholderID
            stemID[nStems] = gotNew.id
            if stemID[nStems] = 0
                @fail: "Cannot open the rendered stem " + outWrite$[kS] + " as a LongSound."
            endif
            Rename: stemName$[nStems]
            @addTemp: stemID[nStems]
            outObj[kS] = stemID[nStems]
        endif
        stemPeak[nStems] = renderPass.peak * mixGain
    endfor
endif
# all audio written and verified: commit (replace confirmed overwrites)
if nOutF > 0
    @commitGroup: 3
endif
tRender = stopwatch

# ============================================================
# 8. MEASUREMENTS
# ============================================================
nPerLayer# = zero#(5)
for ie from 1 to nEv
    nPerLayer#[evLayer[ie]] = nPerLayer#[evLayer[ie]] + 1
endfor
nUsedSrc = 0
maxUses = 0
if rerender = 0
    for s from 1 to nSrc
        if srcUses[s] > 0
            nUsedSrc = nUsedSrc + 1
        endif
        maxUses = max(maxUses, srcUses[s])
    endfor
endif
# event onset density per 5% window and loudest rendered window
nBin = 20
bestBin = 1
bestCnt = -1
for b from 1 to nBin
    cnt = 0
    for ie from 1 to nEv
        if evOn[ie] >= (b - 1) / nBin * tDur and evOn[ie] < b / nBin * tDur
            cnt = cnt + 1
        endif
    endfor
    binCnt[b] = cnt
    if cnt > bestCnt
        bestCnt = cnt
        bestBin = b
    endif
endfor
densPeakX = (bestBin - 0.5) / nBin
# Exact polyphony by a sweep over all event starts (+1) and ends (-1):
# mean over the SOUNDING time (absolute silence excluded), maximum, and
# the time-weighted mean per 5 % window for the activity peak.
for b from 1 to nBin
    binAct[b] = 0
endfor
polyMean = 0
polyMax = 0
soundT = 0
if nEv > 0
    Create Table with column names: "tl_sweep", 2 * nEv, "t d"
    swID = selected("Table")
    @addTemp: swID
    for ie from 1 to nEv
        Set numeric value: 2 * ie - 1, "t", evOn[ie]
        Set numeric value: 2 * ie - 1, "d", 1
        Set numeric value: 2 * ie, "t", evEnd[ie]
        Set numeric value: 2 * ie, "d", -1
    endfor
    # ends sort before starts at equal times (d = -1 first)
    Sort rows: "t d"
    lev = 0
    tPrev = 0
    polyInt = 0
    for r from 1 to 2 * nEv
        tNow = Get value: r, "t"
        dd = Get value: r, "d"
        if tNow > tPrev and lev > 0
            polyInt = polyInt + lev * (tNow - tPrev)
            soundT = soundT + (tNow - tPrev)
            # spread over the 5 % windows the interval touches
            b0 = max(1, floor(tPrev / tDur * nBin) + 1)
            b1 = min(nBin, floor(tNow / tDur * nBin - 1e-9) + 1)
            for b from b0 to b1
                wa = max(tPrev, (b - 1) / nBin * tDur)
                wb = min(tNow, b / nBin * tDur)
                if wb > wa
                    binAct[b] = binAct[b] + lev * (wb - wa)
                endif
            endfor
        endif
        lev = lev + dd
        polyMax = max(polyMax, lev)
        tPrev = tNow
    endfor
    removeObject: swID
    @dropTemp: swID
    if soundT > 0
        polyMean = polyInt / soundT
    endif
endif
bestAct = -1
actPeakX = 0
for b from 1 to nBin
    binAct[b] = binAct[b] / (tDur / nBin)
    if binAct[b] > bestAct
        bestAct = binAct[b]
        actPeakX = (b - 0.5) / nBin
    endif
endfor
loudX = -1
if wantMix
    best = -1
    for w from 1 to nWin
        # 3 s smoothing
        acc = 0
        nn = 0
        for w2 from max(1, w - 1) to min(nWin, w + 1)
            acc = acc + winRms[w2] ^ 2
            nn = nn + 1
        endfor
        sm = sqrt(acc / nn)
        if sm > best
            best = sm
            loudX = (w - 0.5) / tDur
        endif
    endfor
endif
overrun = 0
for ie from 1 to nEv
    if evEnd[ie] > tDur + 1e-6
        overrun = overrun + 1
    endif
endfor

# ============================================================
# 9. VISUALIZATION
# ============================================================
if draw_visualization
    Erase all


    @niceStep: tDur, 8
    tStep = niceStep.result

    # ---- title ----
    Font size: 13
    Select inner viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##TIMELINE COMPOSER v2.3##"
    Font size: 7
    Select inner viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.52}"
    if composition_preset < 8
        sub$ = cpName$[composition_preset] + " " + fixed$(compositional_intensity, 0) + "\%  |  "
    else
        sub$ = "Custom  |  "
    endif
    sub$ = sub$ + orgName$[organization] + "  |  " + string$(nLib) + " librar" + if nLib = 1 then "y" else "ies" fi
        ... + "  |  " + fixed$(tDur, 1) + " s  |  " + tempName$[temporal_preset]
        ... + "  |  Silence: " + silName$[silence_mode]
        ... + "  |  Conductor: " + condName$[conductor_preset]
        ... + "  |  Space: " + spName$[spatial_preset]
        ... + "  |  seed " + string$(random_seed)
    Text: 0.5, "centre", 0.12, "half", sub$

    # ---- panel titles ----
    Font size: 7
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 8, 0
    Colour: "Black"
    Text: 4.15, "centre", 0.78, "half", "Conductor curve c(t) - climax and absolute silences"
    Text: 4.15, "centre", 2.20, "half", "Event timeline - one bar per source file (whole, never cut); paler = quieter"
    Text: 2.27, "centre", 5.18, "half", "Spatial position of each event"
    Text: 6.07, "centre", 5.18, "half", "Active events (steps) and rendered loudness (grey)"

    # ---- A: conductor ----
    Font size: 6
    Select inner viewport: 0.6, 7.7, 0.95, 1.75
    Axes: 0, tDur, 0, 1.08
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, tDur, 0, 1.08
    for k from 1 to nGap
        Paint rectangle: "{0.88, 0.88, 0.88}", gapS[k], gapE[k], 0, 1.08
    endfor
    Colour: "{0.20, 0.20, 0.20}"
    Line width: 2
    prevX = 0
    @cond: 0
    prevY = cond.v
    for k from 1 to 300
        xx = k / 300
        @cond: xx
        Draw line: prevX * tDur, prevY, xx * tDur, cond.v
        prevX = xx
        prevY = cond.v
    endfor
    Line width: 1
    Colour: "{0.84, 0.15, 0.16}"
    Dashed line
    Draw line: xPeak * tDur, 0, xPeak * tDur, 1.08
    Solid line
    Select inner viewport: 0.6, 7.7, 0.95, 1.75
    Axes: 0, tDur, 0, 1.08
    Colour: "{0.84, 0.15, 0.16}"
    Text: xPeak * tDur, if xPeak > 0.85 then "right" else "left" fi, 1.0, "half", " climax " + fixed$(xPeak * 100, 0) + "\%  "
    Select inner viewport: 0.6, 7.7, 0.95, 1.75
    Axes: 0, tDur, 0, 1.08
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, tStep, "no", "yes", "no"

    # ---- B: event timeline ----
    totalLanes = 0
    for lay from 1 to nLayers
        laneBase[lay] = totalLanes
        totalLanes = totalLanes + layerLanes[lay] + 0.6
    endfor
    Select inner viewport: 0.6, 7.7, 2.35, 4.55
    Axes: 0, tDur, totalLanes, 0
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, tDur, 0, totalLanes
    for k from 1 to nGap
        Paint rectangle: "{0.88, 0.88, 0.88}", gapS[k], gapE[k], 0, totalLanes
    endfor
    gMin = 1e9
    gMax = -1e9
    for ie from 1 to nEv
        gMin = min(gMin, evGainDb[ie])
        gMax = max(gMax, evGainDb[ie])
    endfor
    if gMax - gMin < 1
        gMin = gMax - 1
    endif
    for ie from 1 to nEv
        lay = evLayer[ie]
        y0 = laneBase[lay] + evLane[ie] - 0.92
        y1 = laneBase[lay] + evLane[ie] - 0.08
        f = 0.75 * (gMax - evGainDb[ie]) / (gMax - gMin)
        @col: lay, f
        Paint rectangle: col.c$, evOn[ie], max(evEnd[ie], evOn[ie] + tDur / 1500), y0, y1
    endfor
    Colour: "{0.84, 0.15, 0.16}"
    Dashed line
    Draw line: xPeak * tDur, 0, xPeak * tDur, totalLanes
    Solid line
    Select inner viewport: 0.6, 7.7, 2.35, 4.55
    Axes: 0, tDur, totalLanes, 0
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, tStep, "yes", "yes", "no"
    Select inner viewport: 0.6, 7.7, 2.35, 4.55
    Axes: 0, 1, 0, 1
    for lay from 1 to nLayers
        if organization = 1
            lab$ = "Pool"
        elsif nStreams > 1
            lab$ = libName$[layerLibOf[lay]] + " / stream " + string$(lay)
        else
            lab$ = libName$[layerLibOf[lay]]
        endif
        @safeText: lab$
        yMid = 1 - (laneBase[lay] + layerLanes[lay] / 2) / totalLanes
        @col: lay, 0
        Colour: col.c$
        Text special: -0.012, "centre", yMid, "bottom", "Helvetica", 6, "90", left$(safeText.out$, 22)
    endfor
    Font size: 7
    Select inner viewport: 0.6, 7.7, 2.35, 4.55
    Axes: 0, tDur, totalLanes, 0
    Colour: "Black"
    Text bottom: "yes", "Time (s)  - grey bands = measured absolute silence, red = conductor climax"

    # ---- C: space ----
    Font size: 6
    Select inner viewport: 0.6, 3.95, 5.32, 6.32
    Axes: 0, tDur, -1.15, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, tDur, -1.15, 1.15
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0, tDur, 0
    Solid line
    # v2.1: the regions, when the placement is regional
    if rerender = 0
        if spatial_preset = 7 or spatial_movement < 1
            for r from 1 to nReg
                @col: min(5, r), 0
                Colour: col.c$
                Dashed line
                Draw line: 0, regC[r], tDur, regC[r]
                Dotted line
                Draw line: 0, max(-1, regC[r] - regW[r]), tDur, max(-1, regC[r] - regW[r])
                Draw line: 0, min(1, regC[r] + regW[r]), tDur, min(1, regC[r] + regW[r])
                Solid line
            endfor
        endif
    endif
    for ie from 1 to nEv
        # a combined pool is coloured by folder here, so the folders'
        # placement can be read
        if organization = 1 and nLib > 1
            @col: min(5, evLib[ie]), 0
        else
            @col: evLayer[ie], 0
        endif
        Paint circle (mm): col.c$, evOn[ie], evPos[ie], 0.6 + 0.9 * (evGainDb[ie] - gMin) / (gMax - gMin)
    endfor
    Select inner viewport: 0.6, 3.95, 5.32, 6.32
    Axes: 0, tDur, -1.15, 1.15
    Colour: "Black"
    Draw inner box
    if nOutCh = 2
        One mark left: -1, "no", "yes", "no", "L"
        One mark left: 0, "no", "yes", "no", "C"
        One mark left: 1, "no", "yes", "no", "R"
    else
        One mark left: -1, "no", "yes", "no", "ch1"
        One mark left: 1, "no", "yes", "no", "ch" + string$(nOutCh)
    endif
    @niceStep: tDur, 4
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Font size: 7
    Select inner viewport: 0.6, 3.95, 5.32, 6.32
    Axes: 0, tDur, -1.15, 1.15
    Text bottom: "yes", "Time (s)"

    # ---- D: activity ----
    nStep = 400
    actMax = 1
    for k from 1 to nStep
        tt = (k - 0.5) / nStep * tDur
        a = 0
        for ie from 1 to nEv
            if evOn[ie] <= tt and evEnd[ie] > tt
                a = a + 1
            endif
        endfor
        act[k] = a
        actMax = max(actMax, a)
    endfor
    Font size: 6
    Select inner viewport: 4.45, 7.7, 5.32, 6.32
    Axes: 0, tDur, 0, actMax * 1.1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, tDur, 0, actMax * 1.1
    for k from 1 to nStep
        @col: 1, 0.35
        Paint rectangle: col.c$, (k - 1) / nStep * tDur, k / nStep * tDur, 0, act[k]
    endfor
    if wantMix
        rMax = 0
        for w from 1 to nWin
            rMax = max(rMax, winRms[w])
        endfor
        if rMax > 0
            Colour: "{0.30, 0.30, 0.30}"
            Line width: 1.5
            for w from 2 to nWin
                Draw line: w - 1.5, winRms[w - 1] / rMax * actMax, w - 0.5, winRms[w] / rMax * actMax
            endfor
            Line width: 1
        endif
    endif
    Colour: "{0.84, 0.15, 0.16}"
    Dashed line
    Draw line: xPeak * tDur, 0, xPeak * tDur, actMax * 1.1
    Solid line
    Select inner viewport: 4.45, 7.7, 5.32, 6.32
    Axes: 0, tDur, 0, actMax * 1.1
    Colour: "Black"
    Draw inner box
    @niceStep: actMax, 3
    Marks left every: 1, max(1, round(niceStep.result)), "yes", "yes", "no"
    @niceStep: tDur, 4
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Font size: 7
    Select inner viewport: 4.45, 7.7, 5.32, 6.32
    Axes: 0, tDur, 0, actMax * 1.1
    Text bottom: "yes", "Time (s)"

    # ---- E: summary ----
    Font size: 6
    Select inner viewport: 0.6, 7.7, 6.95, 7.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    @safeText: objBase$
    Text: 0.015, "left", 0.80, "half", "##" + safeText.out$ + "##  |  " + string$(nEv)
        ... + " events  |  " + string$(nGap) + " silences  |  target " + fixed$(tDur, 1)
        ... + " s, last tail " + fixed$(lastEnd, 2) + " s  |  output " + string$(nOutCh) + " ch @ "
        ... + string$(srOut) + " Hz"
    Text: 0.015, "left", 0.50, "half", "Silence: planned " + fixed$(silence_amount, 1) + "\%  , measured "
        ... + fixed$(silMeasured / tDur * 100, 1) + "\%  (" + fixed$(silMeasured, 1) + " s)  |  climax: conductor "
        ... + fixed$(xPeak * 100, 0) + "\%  , most simultaneous sounds " + fixed$(actPeakX * 100, 0) + "\%  "
        ... + if loudX >= 0 then ", loudest rendered " + fixed$(loudX * 100, 0) + "\%  " else "" fi
    if wantMix
        @safeText: sinkName$
        rl$ = "Render: " + safeText.out$ + "  |  balance " + balName$[library_balance] + "  |  gain x" + fixed$(mixGain, 3)
            ... + "  |  residual in silences " + if silenceRms = 0 then "0 (exact)" else fixed$(20 * log10(silenceRms), 1) + " dBFS" fi
    else
        rl$ = "Plan only - no audio rendered  |  re-render later with Action: Render a saved plan"
    endif
    Text: 0.015, "left", 0.20, "half", rl$
    Select inner viewport: 0.6, 7.7, 6.95, 7.85
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Line width: 1
    Select outer viewport: 0, 8, 0, 8
endif
tViz = stopwatch

# ============================================================
# 10. REPORT
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Composition ==="
if composition_preset < 8
    appendInfoLine: "Preset: ", cpName$[composition_preset], " at ", fixed$(compositional_intensity, 0),
        ... " % intensity - ", cpDesc$[composition_preset]
else
    appendInfoLine: "Preset: Custom (controls set by hand)"
endif
appendInfoLine: "Libraries: ", nLib, "   organisation: ", orgName$[organization], "   layers: ", nLayers
for i from 1 to nLib
    appendInfoLine: "  ", i, ": ", libName$[i], "   ", libFolder$[i]
endfor
if rerender = 0
    appendInfoLine: "Catalog: ", nSrc, " readable files (", nSkipped, " unreadable, ", nNonAudio,
        ... " non-audio skipped), shortest usable ", fixed$(shortest, 2), " s"
    appendInfoLine: "Temporal preset: ", tempName$[temporal_preset], "   strictness ",
        ... fixed$(duration_order_strictness, 2), "   density ", fixed$(event_density, 1),
        ... "/min   overlap ", fixed$(overlap, 2), "   max repetitions ", max_repetitions
    appendInfoLine: "Conductor: ", condName$[conductor_preset], " - curve peaks at ",
        ... fixed$(xPeak * 100, 1), "% (requested ", fixed$(climax_position, 1), "%)"
        ... + if condJag = 1 then " - stepped on 16 segments" else "" fi
    appendInfoLine: "Space: ", spName$[spatial_preset], "   influence: dynamics ", fixed$(dynamics_influence, 2),
        ... "  density ", fixed$(density_influence, 2), "  space ", fixed$(spatial_influence, 2),
        ... "   range ", fixed$(dynamic_range, 1), " dB"
    appendInfoLine: "Dynamics: the conductor lowers the quietest moments by up to ",
        ... fixed$(dynamics_influence * dynamic_range, 1), " dB (influence ", fixed$(dynamics_influence, 2),
        ... " x range ", fixed$(dynamic_range, 1), " dB); 0 dB at the climax"
    if spatial_preset = 7
        appendInfoLine: "Placement: every layer stays in its region (Layer-based)"
    elsif spatial_movement >= 1
        appendInfoLine: "Placement: spatial movement 1 - the behaviour uses the whole field"
    else
        appendInfoLine: "Placement: spatial movement ", fixed$(spatial_movement, 2),
            ... " - 0 keeps each layer in its region, 1 = whole field"
    endif
    if spatial_preset = 7 or spatial_movement < 1
        for r from 1 to nReg
            appendInfoLine: "  region ", r, " (", regName$[r], "): position ", fixed$(regC[r], 2),
                ... ", spread ", fixed$(regW[r], 2)
        endfor
    endif
    if nStreams > 1 and stream_sources = 2
        appendInfoLine: "Streams: the folder's files are split between the streams (each file in one stream)."
    endif
    if nStreams > 1
        appendInfoLine: "One folder is split into ", nStreams, " independent streams that share its sources."
    endif
    if layerStagger > 0 and nLayers > 1
        ent$ = ""
        for lay from 2 to nLayers
            ent$ = ent$ + "  " + fixed$(layerEntry[lay], 1) + " s"
        endfor
        appendInfoLine: "Layers enter one after another: layer 1 at 0 s,", ent$
    endif
    if silence_mode = 1
        appendInfoLine: "Silence: Continuous - no absolute silence is planned"
    else
        appendInfoLine: "Silence: ", silName$[silence_mode], ", placement ", plcName$[plc]
            ... + " - ", nSilP, " planned silence(s)"
    endif
endif
appendInfoLine: ""
appendInfoLine: "Timeline (target ", fixed$(tDur, 2), " s, tolerance ", fixed$(tol, 2), " s):"
appendInfoLine: "  events: ", nEv, "    sources used: ", nUsedSrc, "    most repetitions of one source: ", maxUses
if rerender = 0
    appendInfoLine: "  onsets per minute: ", fixed$(nEv / tDur * 60, 1), " (requested base ", fixed$(event_density, 1),
        ... " per layer, shaped by the conductor); ", nBridged, " onset(s) pulled earlier and ", nRepaired, " hole(s) filled to avoid unplanned silence"
endif
for lay from 1 to nLayers
    appendInfoLine: "    layer ", lay, ": ", nPerLayer#[lay], " events"
endfor
appendInfoLine: "  polyphony (sounding time): mean ", fixed$(polyMean, 2), ", maximum ", polyMax,
    ... "   (overlap ", fixed$(overlap, 2), ")"
appendInfoLine: ""
appendInfoLine: "Duration:"
appendInfoLine: "  requested ", fixed$(tDur, 3), " s = timeline length (exact, ", round(tDur * srOut), " samples)"
appendInfoLine: "  last audible event ends at ", fixed$(lastEnd, 3), " s"
appendInfoLine: "  planned ending silence ", fixed$(ending_silence, 2), " s (musical end at ", fixed$(endTime, 3), " s)"
emptyTail = max(0, endTime - lastEnd)
if emptyTail > tol
    appendInfoLine: "  UNINTENDED empty tail: ", fixed$(emptyTail, 2), " s before the musical end - no unused"
    appendInfoLine: "    source fits there (raise Max repetitions, add sources or lower the density)."
else
    appendInfoLine: "  unintended empty tail: none (", fixed$(emptyTail, 3), " s, within the ", fixed$(tol, 2), " s tolerance)"
endif
appendInfoLine: "  events running past the end: ", overrun, "  (must be 0)"
appendInfoLine: "  absolute silence: planned ", fixed$(silence_amount, 1), "%, measured ",
    ... fixed$(silMeasured / tDur * 100, 2), "% = ", fixed$(silMeasured, 2), " s in ", nGap, " interval(s)"
if ending_silence > 0
    appendInfoLine: "    of which the planned ending silence is ", fixed$(ending_silence, 2), " s; the form's own silences: ",
        ... fixed$((silMeasured - ending_silence) / tDur * 100, 2), "%"
endif
for k from 1 to nGap
    appendInfoLine: "    ", fixed$(gapS[k], 2), " - ", fixed$(gapE[k], 2), " s  (", fixed$(gapE[k] - gapS[k], 2), " s)"
endfor
appendInfoLine: ""
appendInfoLine: "Climax check (positions in % of the duration; they need not coincide):"
appendInfoLine: "  conductor ", fixed$(xPeak * 100, 0), "   densest entrances ", fixed$(densPeakX * 100, 0),
    ... "   most simultaneous sounds ", fixed$(actPeakX * 100, 0),
    ... if loudX >= 0 then "   loudest rendered 3 s " + fixed$(loudX * 100, 0) else "" fi
if loudX >= 0 and abs(loudX - xPeak) > 0.15
    appendInfoLine: "  NOTE: the loudest passage is ", fixed$(abs(loudX - xPeak) * 100, 0),
        ... "% of the duration away from the conductor climax."
endif

if rerender = 0
    appendInfoLine: ""
    appendInfoLine: "Library loudness (active-signal RMS, median of reliable files) - balance: ", balName$[library_balance]
    for i from 1 to nLib
        if libRef[i] = undefined
            appendInfoLine: "  ", libName$[i], ": no reliable file - no automatic correction"
        else
            appendInfoLine: "  ", libName$[i], ": reference ", fixed$(libRef[i], 1), " dBFS (", libNRel[i],
                ... " reliable files)   automatic ", fixed$(libAuto[i], 1), " dB   manual ", fixed$(libManual[i], 1), " dB"
        endif
    endfor
    if globalRef <> undefined
        appendInfoLine: "  common reference ", fixed$(globalRef, 1), " dBFS"
    endif
    if per_file_leveling
        mxF = 0
        for s from 1 to nSrc
            mxF = max(mxF, abs(srcFileDb[s]))
        endfor
        appendInfoLine: "  per-file leveling on: largest file correction ", fixed$(mxF, 1), " dB (limit ", fixed$(file_level_limit, 1), ")"
    endif
endif

appendInfoLine: ""
appendInfoLine: "Result in Praat:"
if planOnly
    appendInfoLine: "  Plan only - no audio. Tables: ", objBase$, "_plan and ", objBase$, "_settings"
    appendInfoLine: "  (select both and run Render a saved plan to hear it)."
else
    if diskBacked
        appendInfoLine: "  LongSound ", mixName$, " - ", nOutCh, " ch, reads from its WAV file (keep that file):"
    else
        appendInfoLine: "  Sound ", mixName$, " - ", nOutCh, " ch, ", fixed$(tDur, 3), " s, peak ",
            ... fixed$(20 * log10(max(outPeak, 1e-12)), 2), " dBFS (gain x", fixed$(mixGain, 4), ")"
    endif
    appendInfoLine: "    measured residual inside absolute silences: ",
        ... if silenceRms = 0 then "0 (exact digital silence)" else fixed$(silenceRms, 9) fi
    for k from 1 to nStems
        appendInfoLine: "  stem ", stemName$[k], " (peak ", fixed$(20 * log10(max(stemPeak[k], 1e-12)), 2), " dBFS)"
    endfor
    if nStems > 0
        appendInfoLine: "    stems use the mix gain and length, so they sum to the mix."
    endif
endif
if savedFiles > 0
    appendInfoLine: "Files written:"
    for k from 1 to savedFiles
        appendInfoLine: "  ", savedFile$[k]
    endfor
    if diskBacked
        appendInfoLine: "  The audio file(s) back the LongSound object(s): do not delete them while"
        appendInfoLine: "  those objects exist."
    endif
else
    appendInfoLine: "Files written: none"
endif
if warnCount > 0
    appendInfoLine: ""
    appendInfoLine: "Notes:"
    for k from 1 to warnCount
        appendInfoLine: "  - ", warn$[k]
    endfor
endif
appendInfoLine: ""
appendInfoLine: "Time (s): scan ", fixed$(tScan, 2), "   plan ", fixed$(tPlan, 2), "   render ",
    ... fixed$(tRender, 2), "   figure ", fixed$(tViz, 2)

# ---- the results are kept; only temporary objects go ----
removeObject: placeholderID
if mixID > 0
    @dropTemp: mixID
endif
for k from 1 to nStems
    @dropTemp: stemID[k]
endfor
for k from 1 to nTemp
    if tempID[k] > 0
        nocheck removeObject: tempID[k]
    endif
endfor

# ---- playback (the result stays in Praat) ----
if play_result and wantMix
    if diskBacked
        # a LongSound has no Play; Play part streams it from its file
        selectObject: mixID
        Play part: 0, tDur
    elsif nOutCh = 2
        selectObject: mixID
        Play
    else
        # Temporary stereo audition of the multichannel result: channel k
        # sits at p = -1 + 2 (k-1)/(N-1), equal-power to L/R; scaled down
        # only if the fold would clip. Removed after playing.
        fl$ = "0"
        fr$ = "0"
        for k from 1 to nOutCh
            pk = -1 + 2 * (k - 1) / (nOutCh - 1)
            th = (pk + 1) * pi / 4
            fl$ = fl$ + " + " + string$(cos(th)) + " * object[" + string$(mixID) + ", " + string$(k) + ", col]"
            fr$ = fr$ + " + " + string$(sin(th)) + " * object[" + string$(mixID) + ", " + string$(k) + ", col]"
        endfor
        selectObject: mixID
        nA = Get number of samples
        Create Sound from formula: "tl_audition", 2, 0, nA / srOut, srOut,
            ... "if row = 1 then " + fl$ + " else " + fr$ + " fi"
        audID = selected("Sound")
        @addTemp: audID
        apk = Get absolute extremum: 0, 0, "None"
        if apk > 0.99
            Scale peak: 0.99
        endif
        appendInfoLine: "Playing a temporary stereo audition of the ", nOutCh, "-channel result (removed afterwards)."
        Play
        removeObject: audID
        @dropTemp: audID
    endif
endif

# ---- leave the result selected ----
if mixID > 0
    selectObject: mixID
elsif planOnly and planID > 0
    selectObject: planID, setID
endif
