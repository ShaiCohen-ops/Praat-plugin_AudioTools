# ============================================================
# Praat AudioTools - BABBITT'S COMBINATORIAL ARRAYS
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Serial-array composition and synthesis system after the opening of
#   Milton Babbitt's Semi-Simple Variations (1956). One shared structural
#   engine (pitch array, time points, aggregates, event table) feeds two
#   realization models:
#
#     HISTORICAL / ANALYTICAL   minimal-assumption realization of the
#                               documented structures: fixed register
#                               bands, fixed voice positions, uniform
#                               articulation, accent-only dynamics, plain
#                               timbre. Every model decision is labelled
#                               in the Info window (PROVENANCE block).
#     CREATIVE COMBINATORIAL    independent extension on Babbitt's
#                               principles: structural voice distribution,
#                               combinatorial register mapping, structural
#                               dynamics / articulation / space,
#                               combinatorial spectral synthesis and a
#                               form engine that gives each cycle its own
#                               way of presenting the same material.
#
#   SERIAL ENGINE (shared, unchanged from v0.3.1)
#     ordered hexachord P -> combinatorial partner Y (I_n or T_k whose image
#     is the complementary hexachord) -> four-line array {P, R, Y, RY}.
#     Opening array:
#       S = P  10 6 11 8 7 9      A = RI  2 4 3 0 5 1
#       T = R   9 7 8 11 6 10     B = I   1 5 0 3 4 2      (I = I11)
#     Secondary sets (each line -> combinatorial transposition of its
#     retrograde) and trichord derivation (aggregate partitioned by a
#     segmental trichord and three of its T/I forms) as in v0.3.
#
#   TIME-POINT ENGINE (rewritten in v0.4)
#     The 16 symbols of the partition series are INDICES of rhythm types,
#     not bit masks. Decoding table (p = sixteenth 1..4 of the quarter):
#       0 0000 | 1 1000  2 0100  3 0010  4 0001
#       5 1100  6 1010  7 1001  8 0110  9 0101  T 0011
#       E 1110  W 1101  X 1011  Y 0111 | Z 1111
#     i.e. grouped by number of attacks, lexicographic inside each group.
#     The anchors 5 = 1100, 3 = 0010, T = 0011, 8 = 0110 fix the
#     convention; the order inside the 3-attack group (E W X Y) and of
#     6 7 9 is INFERRED from the same convention (see PROVENANCE).
#     Opening order: Z 5 4 X 3 T 9 Y | 7 1 E 6 2 8 W 0 -> 18 + 14 attacks.
#     Operations act on the binary patterns, never on the code numbers:
#       Q  order retrograde   the 16 patterns in reverse order
#       M  mirror             each pattern reversed inside its quarter
#       C  complement         attack <-> rest inside every pattern
#     Q, M and C generate a group of 8; R = QM is the true time retrograde
#     (attack at sixteenth s -> 63 - s). Every element keeps the series
#     exhaustive (16 distinct patterns, 32 attacks).
#
#   AGGREGATE SEGMENTATION
#     16 + 16 attacks (v0.3 model) or the two halves of the partition
#     series (8 + 8 quarters; 18 + 14 attacks for the opening). Each
#     aggregate block holds 12 entries + (attacks - 12) rearticulations.
#
#   STRUCTURAL VOICE DISTRIBUTION (Creative)
#     The 12 entries of an aggregate are distributed over S A T B (3 each,
#     line order kept) by a deterministic hill-climb on an explicit
#     texture objective: grouping of consecutive entries, overlap of voice
#     spans, staggering of first entries, distinct inter-onset patterns
#     and (withheld role) a planned late completion by one voice. QC
#     compares the result with 40 random distributions of the same block.
#
#   COMBINATORIAL REGISTER MAPPING (Creative)
#     Fixed bands | Distributed (register follows order number; I lines
#     descend, R lines run backwards) | Rotating (bands exchanged each
#     aggregate) | Structural (fixed registral aggregate per cycle,
#     mirror-symmetric around the inversion axis of the array: pcs x and
#     n-x always sound at equal distances above and below the axis).
#
#   COMBINATORIAL SPECTRAL SYNTHESIS (Timbre = Combinatorial spectral)
#     Each note carries a harmonic core whose tilt follows the interval-
#     class content of its own trichord (chromatic trichords bright, wide
#     ones dark) plus two partials at the intervals to the other members
#     of that trichord (so complementary trichords give complementary
#     spectra). Retrograde lines let those partials bloom instead of
#     decay; a cycle-dependent "harmonic pull" moves them toward or away
#     from the nearest harmonic (convergence / divergence); the entry that
#     completes an aggregate sounds the whole aggregate as a faint
#     spectral halo.
#
#   DYNAMICS / ARTICULATION / SPACE (Creative)
#     Dynamics from the form class of the line (P/T, I, R, RI), the
#     position of an entry relative to aggregate completion and the role
#     of the cycle. Articulation from the cardinality of the quarter's
#     partition (1 attack = legato ... 4 attacks = staccato), trichord
#     completions and the cycle's profile. Space: complementary hexachords
#     on opposite sides, inversion-axis symmetry, exchange of retrograde
#     partners, or crossing; equal-power panning, mono or stereo.
#
#   COMBINATORIAL FORM ENGINE (Creative)
#     Roles: exposition, monody (single lines), density, spectral,
#     withheld (delayed completion), revelation (register + space expose
#     the inversion axis). The Morphogenesis plan derives the role of each
#     cycle from the array itself (basic -> exposition; secondary sets ->
#     monody, so the 12-tone secondary lines are audible; the hybrid join
#     -> withheld; derived cycles by generator class: 012 density,
#     014/015 spectral, 025 revelation).
#
#   v0.5 INDEPENDENT RHYTHMIC VOICES (Creative, Texture = Independent)
#     every voice on its own partition series (form of its line + rotation
#     by its T/I index); aggregates = time windows of 8 quarters; six
#     textures; responsive form; complementary spectra. See changelog.
#
#   GLOBAL DYNAMIC ARC (v0.5.2, optional, default off; main form in v0.5.3)
#     one envelope table in composition time drives both the audio gain and
#     the MusicXML dynamics / wedges / note playback levels. The figure's
#     panel I shows the table against the measured gain and output RMS.
#
#   EVENT TABLE
#     All outputs (sound, figure, MusicXML, Info) read one event table
#     (atk* arrays): time, voice, pc, MIDI, written and sounding length,
#     articulation, accent, dB, dynamic mark, pan, role.
#
#   MUSICXML OUTPUT
#     Four parts, 4/4, divisions 4. Written values = time to the next
#     attack of the same voice (max a half note); articulation marks
#     (staccato, detached-legato, tenuto, accent, let-ring), dynamics
#     directions where the mark changes, parenthesised rearticulations.
#     4/4 barring is a notation choice of this script, not the score.
#
# HONEST SCOPE:
#   Taken from the analysis: the opening pitch array, the 16-symbol
#   partition order and its 32-attack total, the four decoding anchors.
#   Model rules of this script: the remaining decoding entries, aggregate
#   segmentation, voice assignment, rearticulation placement, register
#   bands, barring. "Complement" (attack/rest exchange) is not Babbitt's
#   modular time-point inversion. The derivation schedule and every
#   Creative mechanism are this script's own extensions. No claim is made
#   about how any of this sounds; listening evaluation is the user's.
#
# Changelog v0.5.4 (final functional upgrade):
#   NEW: SATB voice range protection (Details 2/2; default ON, standard
#   profile S 60-81, A 55-76, T 48-69, B 40-64, or a custom field of 8 MIDI
#   numbers; OFF = v0.5.3 behaviour, MIDI 21-108 only).
#   - Applied once, in the shared event model (realizeEvent), after the
#     register strategy has chosen a pitch: if it lies outside its voice's
#     range, the octave-equivalent pitch inside the range nearest the
#     intended pitch is used (near-ties toward the voice's previous pitch).
#     Pitch class, onsets, voices, order of appearances and every other
#     event field are unchanged; synthesis, halo chords, figure, Info table
#     and MusicXML all read the corrected pitch. The XML writer does not
#     alter pitches.
#   - Rearticulation octave displacement: the other octave if it fits,
#     otherwise no displacement (counted); a rearticulation of a pitch from
#     another voice is fitted to its own voice.
#   - Inversion-axis register: the axis map is unchanged; notes moved to fit
#     their voice are counted and reported as lost exact mirror symmetry.
#   - A range must span at least 11 semitones (every pitch class needs an
#     octave inside it); otherwise the run stops with an explanation.
#   - Self-tests: each voice within its range (actual lowest/highest
#     reported), pitch class kept, halo pitches in range, MusicXML part
#     pitch ranges = event table and inside the voice ranges.
#   - Voice crossing is still allowed where each voice stays in its range.
#   NEW: Composition duration (main form). Tempo mode (default) = v0.5.3.
#   Target mode: tempo = 16 x cycles x 60 / target seconds, unrounded; the
#   cycle structure is never changed. Outside 20-300 bpm a dialog explains
#   the reachable durations / cycle counts and lets the user change either
#   or cancel. Musical duration (16 x cycles beats) and rendered audio
#   (+ decay tail) are reported separately; in Target mode the audio always
#   contains the whole musical duration (final rests included). MusicXML
#   <sound tempo> carries up to 8 decimals (metronome mark 2). The Global
#   Dynamic Arc is defined in musical time, so its turning point stays at
#   the same proportion of any duration (audio, MusicXML, figure).
#
# Changelog v0.5.3 (interface only; no engine changes):
#   - Main form: Dynamic arc, Arc range (dB), Turning point (%, Arch and
#     Inverted only) and Write MusicXML file moved from the Details pages
#     to the main form; Keep MusicXML Strings moved to Details 1/2. Presets
#     never change these fields. Turning point is checked only for Arch /
#     Inverted arch and ignored otherwise (Praat forms cannot hide a field).
#   - MusicXML file and Strings are now exported after the final audio QC
#     (no clipping, no undefined samples); before, the file was written
#     after the structural gate but before synthesis. Content unchanged.
#   - Figure: new panel I (only when an arc is on): requested arc from the
#     shared table, measured gain per quarter-beat window (output RMS /
#     pre-arc RMS, normalization removed) and 4-beat smoothed output RMS.
#   - Info: measured-gain deviation, turning point exact (audio, note
#     levels) vs notated (hairpin on the nearest 16th).
#   - Documentation fix: the v0.5.2 note claiming the wedge sits at the
#     exact turning point was wrong; it sits on the nearest 16th.
#   - With Dynamic arc = None, audio, events and MusicXML are identical to
#     v0.5.2 (apart from the version string).
#
# Changelog v0.5.2 (final focused upgrade):
#   NEW: Global Dynamic Arc (Arc shape / peak position / range).
#   - Shapes None (default, output byte-identical to v0.5.1 apart from the
#     version string), Arch, Inverted arch, Rising, Falling; raised-cosine
#     transitions; one envelope over the whole composition (time / length of
#     all cycles), never restarting per aggregate or cycle.
#   - ONE shared model: an envelope table in composition time (every 1/8
#     beat). Audio = per-sample gain interpolated from it (all channels
#     alike, before the uniform peak normalization; the arc never exceeds
#     0 dB, so it cannot clip). MusicXML = from the same table: sounding level
#     of each note = event level + arc at its onset -> <dynamics> marks with
#     <sound dynamics>, the note's playback "dynamics" attribute, and
#     identical <wedge> crescendo / diminuendo in all four parts; the
#     turning point is notated on the nearest 16th (see v0.5.3), with
#     <offset> when it falls inside a sounding note.
#   - Unchanged: events (pitch, rhythm, voices, aggregates, articulation,
#     pan, event dynamics) and every engine; the event fingerprint is the
#     same for all five shapes.
#   - No MIDI file is written (Praat scripts cannot write binary files
#     reliably); see the limitations note in the verification report.

# Changelog v0.5.1:
#   Scope: Creative model, texture "Independent rhythmic voices" only. The
#   Historical model and the composite stream are unchanged (bit-identical
#   event tables and audio for presets 1-8 with fixed seeds).
#   BUG FIXES
#   - Monody fallback: when a relay window could not be built and fell back
#     to canon, the monody note-cutting rule was still applied (it read the
#     cycle's role, not the texture actually generated).
#   - Monody could overlap with notes ringing over from the previous cycle,
#     and portato / staccato notes left gaps: monody now guarantees exactly
#     one sounding voice from first to last attack of every relay window
#     (legato relay whose decay is stretched to reach the next attack;
#     anything still sounding - previous cycle, or a canon-fallback window
#     of the same cycle - stops at the relay's first attack) - self-test.
#     The option sweep found this case (5 of 108 configurations) through the
#     new structural gate, which stopped those runs without export.
#   - Spectral complementarity metric (v0.5) gave pure sine tones a perfect
#     score; it now measures UPPER partials only (fundamentals rendered to
#     separate stems and subtracted), so a timbre without partials is "n/a".
#   - Structural self-tests did not stop the run: a failure now ends the
#     script before synthesis and before any MusicXML export; a clipping
#     failure removes the rendered objects. MusicXML is built and checked
#     before synthesis.
#   NEW / CHANGED COMPOSITIONAL MECHANISMS
#   - Combinatorial gesture engine (replaces v0.5's fixed back-and-forth
#     walk, which gave e.g. 11212321 in every density gesture): number of
#     attacks from the trichord's intervals; entry placement (front,
#     interval-timed, spread, late) and elaboration type (neighbour, echo,
#     pedal, contour with octave displacement, imitation of the canon
#     leader) chosen from line form, interval size, partition-cell
#     cardinality, the voice's previous gesture, the other voices' choices
#     in the same window and the form relation. Entries keep line order;
#     elaborations only restate pcs the voice has already stated (verified).
#   - Spectral groups follow each aggregate's own combinatorial pairing
#     (S+T trichords / A+B trichords) instead of P's fixed hexachord;
#     inversion lines (I / RI) invert the spectral tilt (rising partials).
#   - Form model: each cycle continues, transforms, develops (neighbouring
#     role on a texture axis) or contrasts with the previous one. Plans give
#     novelty curves (Counterpoint: development; Spectral: continuity;
#     Temporal: alternation); Morphogenesis follows the role the array asks
#     for. Decisions read only features that exist at that moment: texture,
#     analytic brightness of the synthesis parameters, gesture-shape
#     distance to the cycle before (self-test).
#   REPORTING (not structural; never stops a run)
#   - Gesture diversity: shape DTW (step direction, octave leaps, rhythm)
#     nearest-neighbour distance and near-duplicate share.
#   - Density texture contract: >= 3.0 sounding voices and >= 3.0 onsets
#     per beat. Spectral: upper-partial separation, upper-partial level
#     relative to fundamentals, brightness contrast between the two groups.

# Changelog v0.5.0:
#   BUG FIXES (both realization models)
#   - Hybrid join (first derived cycle): v0.4 could repeat a pc inside a
#     voice line (opening material, cycle 3 bass: 8 10 9 | 5 9 4), because
#     only vertical aggregate completeness was enforced. The derived second
#     aggregate is now assigned to voices by searching the generator's
#     partitions and the 24 voice assignments (v0.4's assignment first) for
#     one in which every voice line keeps 6 distinct pcs; if none exists the
#     join becomes a fully derived cycle and the Info says so.
#     HISTORICAL MODEL CHANGE: Trichord Derivation (and Serial Synthesizer)
#     differ from v0.4 in aggregate 6 only (events 81-96 with the default
#     schedule): same partition, trichords redistributed among the voices.
#     All other Historical presets are bit-identical to v0.4.
#   - Density role (v0.4 Creative) aimed at overlap but shortened its notes
#     (articulation profile "dry"); it now sustains.
#   - Monody role (v0.4) did not produce one line; it is now a real relay.
#   NEW CHECKS
#   - Horizontal integrity: every voice line of every cycle holds 6
#     distinct pcs.
#   - Repetition classification: chromatic completeness (tested), exact
#     repetition of an aggregate's voice-assignment matrix (allowed only as a
#     declared relation: the hybrid "pivot" restatement or a "recurrence" of
#     the derivation schedule; anything else fails), and gesture repetition
#     (measured, never an error).
#   NEW COMPOSITIONAL MECHANISMS (Creative model only)
#   - Texture "Independent rhythmic voices": each voice runs its own
#     partition series. Rhythmic form follows the line form (P -> O, R ->
#     time retrograde, I -> attack/rest complement, RI -> RC) and is rotated
#     by the line's T / I index, so lines of one form class do not collapse
#     into rhythmic unison. Voices attack independently and simultaneously.
#     Each aggregate occupies one half of the series (8 quarters) as a hard
#     time window; inside it each voice states its three pcs in line order
#     and may elaborate only pcs it has already stated. Verified by
#     self-tests (window, 3 entries, attack on own series, own series
#     exhaustive, elaboration sources, no double attack in a voice).
#   - Six textures realize the roles: canon (staggered entrances),
#     relay monody (exactly one line sounds), density (all voices through
#     the window, sustained), spectral (few long attacks), withheld (one
#     voice states two pcs and completes the aggregate last), revelation
#     (attacks on time points shared by two voices).
#   - Responsive form: cycles are generated, realized and measured one at a
#     time; the next role is the one whose expected features are farthest
#     from what the previous cycle actually produced, plus structural
#     affinity (Morphogenesis: secondary -> monody, hybrid -> withheld,
#     012 -> density, 014/015 -> spectral, 025 -> revelation) and a penalty
#     for recent roles.
#   - Complementary spectral model (Timbre 6): notes of hexachord P keep
#     only partials whose chroma lies in P (retuned to tempered pitch), notes
#     of the complement only complement chroma; missing chroma of the note's
#     hexachord are added as completion partials. The two hexachord groups
#     occupy complementary spectral regions; measured from rendered stems.
#     The v0.4 interval model remains as Timbre 7 for A/B comparison.
#   MEASUREMENT (not optimization targets)
#   - Per cycle: sounding voices (until -30 dB), simultaneity rate, onset
#     density, audible length, rhythmic independence (1 - mean |r| of the
#     voices' onset counts), register / dynamic spread, measured centroid,
#     spectral complementarity, spectral distance to the previous cycle,
#     z-scored feature distance and onset-grid Jaccard similarity between
#     cycles. New figure panel H; QC panel extended.
#   - The composite-stream optimizer comparison is now labelled an
#     optimizer check, not a musical measure.
#   COMPATIBILITY
#   - Main form unchanged; preset indices unchanged. Presets 9-12 now use
#     independent voices and the complementary spectral model. New Details
#     fields: Texture; Timbre option 7.

# Changelog v0.4.0:
#   - FIX (rhythm): partition symbols are decoded through an explicit
#     index -> pattern table instead of being read as raw binary; v0.3.1
#     decoded 14 of the 16 symbols wrongly (only 0 and Z coincide), so
#     every rhythm, every rhythmic transform and the aggregate boundary
#     were wrong. The opening now gives 18 + 14 attacks per half.
#   - Rhythm operations act on patterns: Retrograde (time), Complement,
#     Retrograde complement, Order retrograde, Mirror, New ordering and a
#     Gray path through all eight Q/M/C elements (one change per cycle).
#   - Self-tests run on every execution (rhythm decoding, all eight
#     operations, P/I/R/RI relations, aggregates, secondary sets,
#     derivation, line order, register symmetry, MusicXML counts) and are
#     reported in Info and in the QC panel.
#   - FIX (Details): "Secondary sets cycle" created the variable
#     secondary_sets_cycle, which the script never read, so the Details
#     toggle had no effect; the field is now "Secondary sets".
#   - New aggregate segmentation option (16+16 attacks / partition halves)
#     with a variable number of rearticulations per aggregate.
#   - Historical / Creative realization models; PROVENANCE block.
#   - Structural Voice Distribution, Combinatorial Register Mapping,
#     Combinatorial Spectral Synthesis, structural dynamics, articulation
#     and stereo space, Combinatorial Form Engine (five plans).
#   - Shared event table; MusicXML now carries articulations, dynamics
#     and the same written values the figure shows.
#   - Synthesis renders each note once into a scratch Sound and adds it
#     to the (mono or stereo) master by sample index.
#   - QC reports result properties: density, polyphony, voice crossings,
#     register spread, dynamic range, IOI entropy, articulation mix,
#     measured spectral centroid per aggregate, structure-vs-random
#     comparison of the voice distribution and a reproducibility
#     fingerprint.
#   - Four new presets: Structural Counterpoint, Spectral
#     Combinatoriality, Temporal Labyrinth, Combinatorial Morphogenesis.
#   - Figure: piano-roll event score, corrected partition bits, space /
#     dynamics panel, spectral-centroid panel, extended QC panel.
#   - Aggregate-completing entries are never shorter than tenuto; a plan
#     never closes on two consecutive revelation cycles.
#   - Details split into two short dialogs (structure / realization).
#     The main form is unchanged, so runScript calls from v0.3.1 still
#     work; preset indices 1-8 are unchanged. Optionmenus inside the
#     Details dialogs need Praat 6.3 or newer (as in v0.3.1).
#   - Verified headless on Praat 6.4.06, 6.4.63 and 7.0: 78 option
#     combinations pass all self-tests; seeded runs are bit-identical
#     across the three builds; MusicXML of all 12 presets validates
#     against the MusicXML 3.1 XSD and matches the event table note for
#     note (onset, pitch, written value, articulation, rearticulation).
#
# Changelog v0.3.1:
#   - MusicXML output: in-memory Strings object (main form, default on)
#     and optional file (Details), from one shared line buffer.
#   - Keep_MusicXML_Strings became the last main-form field.
#
# Changelog v0.3:
#   - Secondary Sets cycle; derivation follows the preceding array;
#     Structural Timbre (partial slot = pitch class + 2); presets
#     "Secondary Sets" and "Serial Synthesizer".
#
# Changelog v0.2:
#   - Opening Model preset; Type-A generator; Trichord Derivation;
#     Associative Trichords; engine generalized to several cycles.
# ============================================================

# ============================================================
# COMPACT FORM
# ============================================================
form Babbitt's Combinatorial Arrays v0.5.4
    optionmenu Preset 1
        option Opening Model (Semi-Simple Variations)
        option Type-A Generator
        option Rhythmic Transformations
        option Associative Trichords
        option Secondary Sets
        option Trichord Derivation
        option Serial Synthesizer
        option Free Serial Field
        option Structural Counterpoint
        option Spectral Combinatoriality
        option Temporal Labyrinth
        option Combinatorial Morphogenesis
    comment Composition duration (cycles x 16 beats)
    optionmenu Duration_mode 1
        option Tempo (uses Tempo; Target duration ignored)
        option Target duration (tempo computed; Tempo ignored)
    positive Tempo_BPM_(Tempo_mode_only) 60
    positive Target_duration_(s,_Target_mode_only) 120
    integer Register_centre_MIDI 60
    comment Global dynamic arc (whole composition; audio and MusicXML)
    optionmenu Dynamic_arc 1
        option None (unchanged)
        option Arch (rise, then fall)
        option Inverted arch (fall, then rise)
        option Rising
        option Falling
    real Arc_range_(dB) 18
    real Turning_point_(%,_Arch_and_Inverted_only) 62
    boolean Write_MusicXML_file 0
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Main-form settings -> internal names (presets never change them)
tempo_bpm = tempo_BPM
target_duration_s = target_duration
arc_shape = dynamic_arc
arc_peak_position = turning_point

# ============================================================
# PRESET DEFAULTS (shown pre-filled in the Details dialogs)
# ============================================================
hexachord_source = 1
basic_set_transposition = 0
array_operation = 1
secondary_sets = 0
derivation_cycles = 0
rhythm = 1
segmentation = 1
rearticulation = 2
associative_target = 1
sample_rate = 44100
output_peak = 0.95
random_seed = 0
keep_MusicXML_Strings = 1
voice_range_protection = 1
voice_range_profile = 1
custom_ranges$ = "60-81 55-76 48-69 40-64"
realization = 1
form_plan = 1
voice_distribution = 1
register_strategy = 1
register_spread = 10
timbre = 2
trichord_halo = 0
dynamics = 1
articulation = 1
space = 1
channels = 2
decay_scale = 1.0
texture = 1
spec_groups = 1

if preset = 1
    preset_name$ = "OpeningModel"
    preset_label$ = "Opening Model (Var. 0)"
elsif preset = 2
    preset_name$ = "TypeAGenerator"
    preset_label$ = "Type-A Generator"
    hexachord_source = 2
    voice_distribution = 2
    rhythm = 7
    realization = 2
elsif preset = 3
    preset_name$ = "RhythmicTransformations"
    preset_label$ = "Rhythmic Transformations"
    rhythm = 4
elsif preset = 4
    preset_name$ = "AssociativeTrichords"
    preset_label$ = "Associative Trichords"
    rearticulation = 3
    associative_target = 3
    timbre = 3
    trichord_halo = 1
elsif preset = 5
    preset_name$ = "SecondarySets"
    preset_label$ = "Secondary Sets"
    secondary_sets = 1
elsif preset = 6
    preset_name$ = "TrichordDerivation"
    preset_label$ = "Trichord Derivation"
    secondary_sets = 1
    derivation_cycles = 4
    rearticulation = 3
    associative_target = 4
    trichord_halo = 1
elsif preset = 7
    preset_name$ = "SerialSynthesizer"
    preset_label$ = "Serial Synthesizer"
    secondary_sets = 1
    derivation_cycles = 4
    rearticulation = 3
    associative_target = 4
    timbre = 5
    realization = 2
elsif preset = 8
    preset_name$ = "FreeSerialField"
    preset_label$ = "Free Serial Field"
    hexachord_source = 3
    array_operation = 5
    voice_distribution = 2
    rhythm = 7
    rearticulation = 3
    associative_target = 3
    timbre = 4
    trichord_halo = 1
    realization = 2
elsif preset = 9
    preset_name$ = "StructuralCounterpoint"
    preset_label$ = "Structural Counterpoint"
    secondary_sets = 1
    derivation_cycles = 3
    realization = 2
    form_plan = 2
    voice_distribution = 3
    register_strategy = 5
    space = 6
    dynamics = 2
    articulation = 2
    timbre = 6
    texture = 2
elsif preset = 10
    preset_name$ = "SpectralCombinatoriality"
    preset_label$ = "Spectral Combinatoriality"
    secondary_sets = 1
    derivation_cycles = 2
    rearticulation = 3
    associative_target = 4
    realization = 2
    form_plan = 3
    voice_distribution = 3
    register_strategy = 5
    space = 6
    dynamics = 2
    articulation = 2
    timbre = 6
    texture = 2
elsif preset = 11
    preset_name$ = "TemporalLabyrinth"
    preset_label$ = "Temporal Labyrinth"
    derivation_cycles = 3
    rhythm = 8
    segmentation = 2
    rearticulation = 3
    associative_target = 3
    realization = 2
    form_plan = 4
    voice_distribution = 3
    register_strategy = 5
    space = 6
    dynamics = 2
    articulation = 2
    timbre = 6
    texture = 2
else
    preset_name$ = "CombinatorialMorphogenesis"
    preset_label$ = "Combinatorial Morphogenesis"
    secondary_sets = 1
    derivation_cycles = 4
    rhythm = 8
    segmentation = 2
    rearticulation = 3
    associative_target = 4
    realization = 2
    form_plan = 5
    voice_distribution = 3
    register_strategy = 5
    space = 6
    dynamics = 2
    articulation = 2
    timbre = 6
    texture = 2
endif

# optionmenu inside beginPause needs Praat 6.3 or newer.
if edit_details
    beginPause: "Babbitt Arrays - Details 1/2: structure"
        optionmenu: "Hexachord source", hexachord_source
            option: "Opening hexachord 10 6 11 8 7 9"
            option: "Type-A generator (ICs 1-5 once)"
            option: "Any combinatorial hexachord"
        integer: "Basic set transposition", string$(basic_set_transposition)
        optionmenu: "Array operation", array_operation
            option: "P RI R I (opening array)"
            option: "P I R RI (inversional pair)"
            option: "P Tk R RTk (transpositional pair)"
            option: "P RTk R Tk (retrograde pair)"
            option: "Random valid operation"
        boolean: "Secondary sets", secondary_sets
        integer: "Derivation cycles (0-7)", string$(derivation_cycles)
        optionmenu: "Rhythm", rhythm
            option: "Original 16 partitions"
            option: "Retrograde (time: order + contents)"
            option: "Complement (attack / rest)"
            option: "Retrograde complement"
            option: "Order retrograde (quarters only)"
            option: "Mirror (inside each quarter)"
            option: "New exhaustive ordering"
            option: "Gray path (one operation per cycle)"
        optionmenu: "Aggregate segmentation", segmentation
            option: "16 + 16 attacks"
            option: "Partition halves (8 + 8 quarters)"
        optionmenu: "Rearticulation", rearticulation
            option: "Strict"
            option: "Grouped (quarter onsets)"
            option: "Associative"
        optionmenu: "Associative target", associative_target
            option: "015 + 012"
            option: "025 + 014"
            option: "Segmental trichords of P"
            option: "Current generator"
        integer: "Sample rate (Hz)", string$(sample_rate)
        real: "Output peak", string$(output_peak)
        integer: "Random seed (0 = unpredictable)", string$(random_seed)
        boolean: "Keep MusicXML Strings", keep_MusicXML_Strings
    endPause: "Next", 1
    beginPause: "Babbitt Arrays - Details 2/2: realization"
        optionmenu: "Realization", realization
            option: "Historical / analytical model"
            option: "Creative combinatorial engine"
        optionmenu: "Form plan", form_plan
            option: "Static (exposition)"
            option: "Counterpoint"
            option: "Spectral"
            option: "Temporal"
            option: "Morphogenesis (from the array)"
        optionmenu: "Voice distribution", voice_distribution
            option: "Round robin S A T B"
            option: "Shuffled (line order kept)"
            option: "Structural (form-plan targets)"
        optionmenu: "Texture", texture
            option: "Composite stream (v0.4)"
            option: "Independent rhythmic voices"
        optionmenu: "Register strategy", register_strategy
            option: "Fixed bands"
            option: "Distributed (contour = operation)"
            option: "Rotating bands"
            option: "Structural (inversion axis)"
            option: "From form plan"
        real: "Register spread (st)", string$(register_spread)
        optionmenu: "Timbre", timbre
            option: "Pure"
            option: "Additive"
            option: "Bright"
            option: "Percussive"
            option: "Structural partial slots (v0.3)"
            option: "Complementary spectral (v0.5)"
            option: "Interval spectral (v0.4)"
        boolean: "Trichord halo", trichord_halo
        optionmenu: "Dynamics", dynamics
            option: "Flat (accents only)"
            option: "Structural"
        optionmenu: "Articulation", articulation
            option: "Uniform"
            option: "Structural"
        optionmenu: "Space", space
            option: "Fixed voice positions"
            option: "Complementary hexachords"
            option: "Symmetric (inversion axis)"
            option: "Exchange (retrograde partners)"
            option: "Crossing"
            option: "From form plan"
        optionmenu: "Channels", channels
            option: "Mono"
            option: "Stereo"
        real: "Decay scale", string$(decay_scale)
        boolean: "Voice range protection", voice_range_protection
        optionmenu: "Voice range profile", voice_range_profile
            option: "Standard SATB (S 60-81, A 55-76, T 48-69, B 40-64)"
            option: "Custom (field below)"
        sentence: "Custom ranges (S A T B, MIDI min-max)", custom_ranges$
    endPause: "Run", 1
endif

# ============================================================
# VALIDATION
# ============================================================
if derivation_cycles < 0 or derivation_cycles > 7
    exitScript: "Derivation cycles must be between 0 and 7."
endif
# ---- Composition duration: musical duration = 16 x cycles beats ----
if duration_mode = 2
    @durationFromTarget
else
    if tempo_bpm < 20 or tempo_bpm > 300
        exitScript: "Tempo must be between 20 and 300 bpm."
    endif
endif
# ---- Voice ranges (MIDI) ----
@voiceRangeSetup
if register_spread < 0 or register_spread > 18
    exitScript: "Register spread must be between 0 and 18 semitones."
endif
if register_centre_MIDI < 36 or register_centre_MIDI > 90
    exitScript: "Register centre must be between MIDI 36 and 90."
endif
if decay_scale <= 0
    exitScript: "Decay scale must be greater than 0."
endif
if sample_rate < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if (arc_shape = 2 or arc_shape = 3) and (arc_peak_position < 5 or arc_peak_position > 95)
    exitScript: "Turning point must be between 5 and 95 % (used by Arch and Inverted arch)."
endif
if arc_shape > 1 and (arc_range < 0 or arc_range > 36)
    exitScript: "Arc range must be between 0 and 36 dB."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be greater than 0 and at most 1."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (unpredictable) or a positive integer."
endif

# Historical model: only minimal-assumption realization choices.
# (Voice range protection applies to both models: it changes octaves only.)
hist_note$ = ""
if realization = 1
    if voice_distribution = 3
        voice_distribution = 1
        hist_note$ = hist_note$ + "voice distribution -> round robin; "
    endif
    if register_strategy <> 1
        register_strategy = 1
        hist_note$ = hist_note$ + "register -> fixed bands; "
    endif
    if space <> 1
        space = 1
        hist_note$ = hist_note$ + "space -> fixed; "
    endif
    if dynamics <> 1 or articulation <> 1 or form_plan <> 1
        hist_note$ = hist_note$ + "dynamics / articulation / form plan -> neutral; "
    endif
    dynamics = 1
    articulation = 1
    form_plan = 1
    if texture <> 1
        texture = 1
        hist_note$ = hist_note$ + "texture -> composite stream; "
    endif
    if timbre >= 5
        timbre = 2
        hist_note$ = hist_note$ + "timbre -> additive; "
    endif
    if rhythm >= 7
        rhythm = 1
        hist_note$ = hist_note$ + "rhythm -> original; "
    endif
endif

beat = 60 / tempo_bpm
nyquist = sample_rate / 2
transp = ((round(basic_set_transposition) mod 12) + 12) mod 12
n_cyc = 1 + secondary_sets + round(derivation_cycles)
n_agg = 2 * n_cyc
nch = channels

# Non-seeded UID keeps object names distinct without consuming the seeded sequence.
run_id = randomInteger(100000, 999999)

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

# ============================================================
# TABLES
# ============================================================
for c from 0 to 9
    codeChar$[c] = string$(c)
endfor
codeChar$[10] = "T"
codeChar$[11] = "E"
codeChar$[12] = "W"
codeChar$[13] = "X"
codeChar$[14] = "Y"
codeChar$[15] = "Z"

# Opening partition series (from the analysis).
origCode[1] = 15
origCode[2] = 5
origCode[3] = 4
origCode[4] = 13
origCode[5] = 3
origCode[6] = 10
origCode[7] = 9
origCode[8] = 14
origCode[9] = 7
origCode[10] = 1
origCode[11] = 11
origCode[12] = 6
origCode[13] = 2
origCode[14] = 8
origCode[15] = 12
origCode[16] = 0

# Symbol -> attack pattern. Mask bit for sixteenth p (0..3) is
# floor(mask / 2^(3-p)) mod 2, i.e. the leftmost digit is the first sixteenth.
# Grouped by attack count, lexicographic within a group. Anchored by
# 5 = 1100, 3 = 0010, T = 0011, 8 = 0110; all other entries follow the
# same convention (INFERRED, see PROVENANCE). Edit here if the source
# table differs.
maskOf[0] = 0
maskOf[1] = 8
maskOf[2] = 4
maskOf[3] = 2
maskOf[4] = 1
maskOf[5] = 12
maskOf[6] = 10
maskOf[7] = 9
maskOf[8] = 6
maskOf[9] = 5
maskOf[10] = 3
maskOf[11] = 14
maskOf[12] = 13
maskOf[13] = 11
maskOf[14] = 7
maskOf[15] = 15
for c from 0 to 15
    codeOf[maskOf[c]] = c
endfor
for m from 0 to 15
    popc[m] = 0
    for p from 0 to 3
        popc[m] = popc[m] + (floor(m / 2 ^ (3 - p)) mod 2)
    endfor
    mbits$[m] = ""
    for p from 0 to 3
        mbits$[m] = mbits$[m] + string$(floor(m / 2 ^ (3 - p)) mod 2)
    endfor
endfor

# Rhythm group elements: Q (order retrograde), M (mirror), C (complement).
opName$[1] = "Original"
opName$[2] = "Retrograde"
opName$[3] = "Complement"
opName$[4] = "Retro. complement"
opName$[5] = "Order retrograde"
opName$[6] = "Mirror"
opName$[7] = "Order retro. compl."
opName$[8] = "Mirror complement"
opName$[9] = "New ordering"
opShort$[1] = "O"
opShort$[2] = "R"
opShort$[3] = "C"
opShort$[4] = "RC"
opShort$[5] = "Q"
opShort$[6] = "M"
opShort$[7] = "QC"
opShort$[8] = "MC"
opShort$[9] = "new"
opQ[1] = 0
opM[1] = 0
opC[1] = 0
opQ[2] = 1
opM[2] = 1
opC[2] = 0
opQ[3] = 0
opM[3] = 0
opC[3] = 1
opQ[4] = 1
opM[4] = 1
opC[4] = 1
opQ[5] = 1
opM[5] = 0
opC[5] = 0
opQ[6] = 0
opM[6] = 1
opC[6] = 0
opQ[7] = 1
opM[7] = 0
opC[7] = 1
opQ[8] = 0
opM[8] = 1
opC[8] = 1
# Gray path: each step changes exactly one of Q, M, C.
grayOp[1] = 1
grayOp[2] = 5
grayOp[3] = 2
grayOp[4] = 6
grayOp[5] = 8
grayOp[6] = 4
grayOp[7] = 7
grayOp[8] = 3

# Trichord set classes, coded 10*a + (a+b) from the sorted cyclic intervals.
n_cls = 12
clsCode[1] = 12
clsCode[2] = 13
clsCode[3] = 14
clsCode[4] = 15
clsCode[5] = 16
clsCode[6] = 24
clsCode[7] = 25
clsCode[8] = 26
clsCode[9] = 27
clsCode[10] = 36
clsCode[11] = 37
clsCode[12] = 48
surfCount[0] = 0
anyTarget[0] = 0
for k from 1 to n_cls
    surfCount[clsCode[k]] = 0
    anyTarget[clsCode[k]] = 0
endfor

vName$[1] = "S"
vName$[2] = "A"
vName$[3] = "T"
vName$[4] = "B"
# Retrograde map for the second aggregate of a derived cycle.
dmap[1] = 3
dmap[2] = 4
dmap[3] = 1
dmap[4] = 2

artName$[0] = "uniform"
artName$[1] = "l.v."
artName$[2] = "legato"
artName$[3] = "tenuto"
artName$[4] = "portato"
artName$[5] = "staccato"
dynMark$[0] = "pp"
dynMark$[1] = "p"
dynMark$[2] = "mp"
dynMark$[3] = "mf"
dynMark$[4] = "f"
dynMark$[5] = "ff"

# ============================================================
# FORM ENGINE: roles
#   clT / ovT / stT  voice-distribution targets (grouping, span overlap,
#                    entry stagger); W = withhold one voice to complete
#   reg / space      register and space strategy codes
#   art              articulation profile shift (-1 sustained, +1 dry)
#   dyn              dynamic profile; sig = trichord-partial mix;
#   kap              harmonic pull (-1 = converge / diverge per aggregate)
#   pol              rearticulation placement (0 menu, 3 early, 4 delayed)
# ============================================================
roleName$[1] = "exposition"
roleName$[2] = "monody"
roleName$[3] = "density"
roleName$[4] = "spectral"
roleName$[5] = "withheld"
roleName$[6] = "revelation"
@setRole: 1, 0.10, 0.55, 0.30, 0, 1, 2, 0, 1, 0.30, 0.6, 0
@setRole: 2, 0.75, 0.15, 0.70, 0, 2, 4, -1, 2, 0.25, 0.8, 0
@setRole: 3, 0.00, 0.90, 0.10, 0, 3, 5, -1, 1, 0.20, 0.3, 0
@setRole: 4, 0.33, 0.75, 0.40, 0, 4, 3, -1, 3, 1.00, -1, 0
@setRole: 5, 0.30, 0.50, 0.50, 1, 2, 2, 0, 4, 0.45, 0.5, 4
@setRole: 6, 0.20, 0.60, 0.30, 0, 4, 3, 0, 5, 0.60, 1.0, 3
# v0.5 independent-voice textures: expected measured features of each role
# (sounding voices, simultaneity rate, onsets per beat, mean sounding beats)
# and harmonic count of the complementary spectral model.
# (calibrated on measured runs of the opening material, v0.5.0)
@setProto: 1, 1.55, 0.30, 2.40, 0.60, 8
@setProto: 2, 1.00, 0.00, 1.95, 0.48, 10
@setProto: 3, 3.20, 0.32, 4.00, 0.88, 6
@setProto: 4, 3.35, 0.35, 2.00, 1.90, 16
@setProto: 5, 1.95, 0.20, 1.90, 0.98, 8
@setProto: 6, 1.60, 0.85, 2.00, 0.75, 12
for c from 1 to 6
    roleUsed[c] = 0
    for k from 1 to 5
        planAllow[k, c] = 0
    endfor
    planAllow[5, c] = 1
endfor
planAllow[1, 1] = 1
planAllow[2, 1] = 1
planAllow[2, 2] = 1
planAllow[2, 3] = 1
planAllow[2, 5] = 1
planAllow[2, 6] = 1
planAllow[3, 2] = 1
planAllow[3, 3] = 1
planAllow[3, 4] = 1
planAllow[3, 6] = 1
planAllow[4, 1] = 1
planAllow[4, 2] = 1
planAllow[4, 3] = 1
planAllow[4, 5] = 1
planAllow[4, 6] = 1
planFirst[1] = 1
planFirst[2] = 1
planFirst[3] = 4
planFirst[4] = 3
planFirst[5] = 1
planName$[1] = "Static"
planName$[2] = "Counterpoint"
planName$[3] = "Spectral"
planName$[4] = "Temporal"
planName$[5] = "Morphogenesis"
for k from 1 to 9
    planSeq[1, k] = 1
endfor
planSeq[2, 1] = 1
planSeq[2, 2] = 2
planSeq[2, 3] = 3
planSeq[2, 4] = 5
planSeq[2, 5] = 2
planSeq[2, 6] = 3
planSeq[2, 7] = 5
planSeq[2, 8] = 3
planSeq[2, 9] = 6
planSeq[3, 1] = 1
planSeq[3, 2] = 4
planSeq[3, 3] = 6
planSeq[3, 4] = 4
planSeq[3, 5] = 6
planSeq[3, 6] = 4
planSeq[3, 7] = 6
planSeq[3, 8] = 4
planSeq[3, 9] = 6
planSeq[4, 1] = 3
planSeq[4, 2] = 5
planSeq[4, 3] = 2
planSeq[4, 4] = 5
planSeq[4, 5] = 3
planSeq[4, 6] = 5
planSeq[4, 7] = 2
planSeq[4, 8] = 5
planSeq[4, 9] = 6

# ============================================================
# SELF-TEST 1: rhythm decoding and the eight pattern operations
# ============================================================
st_pass = 0
st_total = 0
st_fail$ = ""
okv = maskOf[5] = 12 and maskOf[3] = 2 and maskOf[10] = 3 and maskOf[8] = 6
@stCheck: okv, "decode anchors 5 3 T 8"
for m from 0 to 15
    seenM[m] = 0
endfor
okv = 1
for c from 0 to 15
    seenM[maskOf[c]] = seenM[maskOf[c]] + 1
    if c > 0
        if popc[maskOf[c]] < popc[maskOf[c - 1]]
            okv = 0
        endif
    endif
endfor
for m from 0 to 15
    if seenM[m] <> 1
        okv = 0
    endif
endfor
@stCheck: okv, "16 distinct patterns, ordered by attack count"
okv = 1
for m from 0 to 15
    @mirror4: m
    mm = mirror4.m
    @mirror4: mm
    if mirror4.m <> m
        okv = 0
    endif
endfor
@stCheck: okv, "mirror is an involution"
# attack sets of the opening under all eight operations
for op from 1 to 8
    for s from 0 to 63
        tA[op, s] = 0
    endfor
    for m from 0 to 15
        seenM[m] = 0
    endfor
    cntA = 0
    for u from 1 to 16
        @rhPattern: op, u
        tMask[op, u] = rhPattern.m
        seenM[rhPattern.m] = seenM[rhPattern.m] + 1
        for p from 0 to 3
            if (floor(rhPattern.m / 2 ^ (3 - p)) mod 2) = 1
                tA[op, 4 * (u - 1) + p] = 1
                cntA = cntA + 1
            endif
        endfor
    endfor
    okv = cntA = 32
    for m from 0 to 15
        if seenM[m] <> 1
            okv = 0
        endif
    endfor
    @stCheck: okv, opShort$[op] + " exhaustive (16 patterns, 32 attacks)"
endfor
okR = 1
okC = 1
okRC = 1
okM = 1
okQ = 1
for s from 0 to 63
    if tA[2, s] <> tA[1, 63 - s]
        okR = 0
    endif
    if tA[3, s] <> 1 - tA[1, s]
        okC = 0
    endif
    if tA[4, s] <> 1 - tA[1, 63 - s]
        okRC = 0
    endif
    qq = floor(s / 4)
    pp = s - 4 * qq
    if tA[6, s] <> tA[1, 4 * qq + 3 - pp]
        okM = 0
    endif
    if tA[5, s] <> tA[1, 4 * (15 - qq) + pp]
        okQ = 0
    endif
endfor
@stCheck: okR, "R = time reversal (s -> 63 - s)"
@stCheck: okC, "C = attack / rest exchange"
@stCheck: okRC, "RC = complement of time reversal"
@stCheck: okQ, "Q reverses quarter order, keeps contents"
@stCheck: okM, "M mirrors inside each quarter, keeps order"
open_h1 = 0
for u from 1 to 8
    open_h1 = open_h1 + popc[maskOf[origCode[u]]]
endfor
open_h2 = 32 - open_h1
v03_wrong = 0
for u from 1 to 16
    if maskOf[origCode[u]] <> origCode[u]
        v03_wrong = v03_wrong + 1
    endif
endfor

# ============================================================
# SERIAL ENGINE: hexachord
# ============================================================
gen_attempts = 0
typeA_count = 0
typeA_pick = 0
if hexachord_source = 1
    gv_hex[1] = 10
    gv_hex[2] = 6
    gv_hex[3] = 11
    gv_hex[4] = 8
    gv_hex[5] = 7
    gv_hex[6] = 9
elsif hexachord_source = 2
    for d1 from 0 to 5
        for d2 from 0 to 5
            if d2 <> d1
                for d3 from 0 to 5
                    if d3 <> d1 and d3 <> d2
                        for d4 from 0 to 5
                            if d4 <> d1 and d4 <> d2 and d4 <> d3
                                for d5 from 0 to 5
                                    if d5 <> d1 and d5 <> d2 and d5 <> d3 and d5 <> d4
                                        d6 = 15 - d1 - d2 - d3 - d4 - d5
                                        for q from 1 to 5
                                            icUsed[q] = 0
                                        endfor
                                        icUsed[abs(d2 - d1)] = 1
                                        icUsed[abs(d3 - d2)] = 1
                                        icUsed[abs(d4 - d3)] = 1
                                        icUsed[abs(d5 - d4)] = 1
                                        icUsed[abs(d6 - d5)] = 1
                                        if icUsed[1] + icUsed[2] + icUsed[3] + icUsed[4] + icUsed[5] = 5
                                            typeA_count = typeA_count + 1
                                            typeA[typeA_count, 1] = d1
                                            typeA[typeA_count, 2] = d2
                                            typeA[typeA_count, 3] = d3
                                            typeA[typeA_count, 4] = d4
                                            typeA[typeA_count, 5] = d5
                                            typeA[typeA_count, 6] = d6
                                        endif
                                    endif
                                endfor
                            endif
                        endfor
                    endif
                endfor
            endif
        endfor
    endfor
    if typeA_count = 0
        exitScript: "Internal error: no Type-A orderings found."
    endif
    typeA_pick = randomInteger(1, typeA_count)
    content_level = randomInteger(0, 11)
    for k from 1 to 6
        gv_hex[k] = (typeA[typeA_pick, k] + content_level) mod 12
    endfor
else
    found = 0
    while found = 0 and gen_attempts < 5000
        gen_attempts = gen_attempts + 1
        for k from 1 to 12
            perm[k] = k - 1
        endfor
        for k from 1 to 11
            j = randomInteger(k, 12)
            tmp = perm[k]
            perm[k] = perm[j]
            perm[j] = tmp
        endfor
        for k from 1 to 6
            gv_hex[k] = perm[k]
        endfor
        @combCheck
        if array_operation <= 2
            found = comb_nInv > 0
        elsif array_operation <= 4
            found = comb_nTr > 0
        else
            found = (comb_nInv + comb_nTr) > 0
        endif
    endwhile
    if found = 0
        exitScript: "No combinatorial hexachord found for the selected array operation."
    endif
endif

for k from 1 to 6
    gv_hex[k] = (gv_hex[k] + transp) mod 12
    pP[k] = gv_hex[k]
endfor
@combCheck

for q from 1 to 6
    icUsed[q] = 0
endfor
ic_list$ = ""
for k from 1 to 5
    dd = ((pP[k + 1] - pP[k]) mod 12 + 12) mod 12
    icv = min(dd, 12 - dd)
    icUsed[icv] = 1
    ic_list$ = ic_list$ + string$(icv) + " "
endfor
all_ic = icUsed[1] + icUsed[2] + icUsed[3] + icUsed[4] + icUsed[5] = 5

# ============================================================
# SERIAL ENGINE: four-line basic array
# ============================================================
op = array_operation
if op = 5
    if comb_nInv > 0 and comb_nTr > 0
        op = randomInteger(1, 4)
    elsif comb_nInv > 0
        op = randomInteger(1, 2)
    else
        op = randomInteger(3, 4)
    endif
endif
if op <= 2 and comb_nInv = 0
    exitScript: "This hexachord is not inversionally combinatorial."
endif
if op >= 3 and comb_nTr = 0
    exitScript: "This hexachord is not transpositionally combinatorial."
endif

inv_pick = 0
tr_pick = 0
if comb_nInv > 0
    inv_pick = 1
    if hexachord_source >= 2
        inv_pick = randomInteger(1, comb_nInv)
    endif
endif
if comb_nTr > 0
    tr_pick = 1
    if hexachord_source >= 2
        tr_pick = randomInteger(1, comb_nTr)
    endif
endif
inv_n = comb_inv[inv_pick]
tr_k = comb_tr[tr_pick]

if op <= 2
    y_plain$ = "I" + string$(inv_n)
else
    y_plain$ = "T" + string$(tr_k)
endif
y_label$ = left$(y_plain$, 1)
for k from 2 to length(y_plain$)
    y_label$ = y_label$ + "_" + mid$(y_plain$, k, 1)
endfor

for k from 1 to 6
    if op <= 2
        yY[k] = ((inv_n - pP[k]) mod 12 + 12) mod 12
    else
        yY[k] = (pP[k] + tr_k) mod 12
    endif
endfor
for k from 1 to 6
    line[1, k] = pP[k]
    line[3, k] = pP[7 - k]
    if op = 1 or op = 4
        line[2, k] = yY[7 - k]
        line[4, k] = yY[k]
    else
        line[2, k] = yY[k]
        line[4, k] = yY[7 - k]
    endif
endfor
opLab$[1] = "P"
opLab$[3] = "R"
opPlain$[1] = "P"
opPlain$[3] = "R"
if op = 1 or op = 4
    opLab$[2] = "R" + y_label$
    opLab$[4] = y_label$
    opPlain$[2] = "R" + y_plain$
    opPlain$[4] = y_plain$
else
    opLab$[2] = y_label$
    opLab$[4] = "R" + y_label$
    opPlain$[2] = y_plain$
    opPlain$[4] = "R" + y_plain$
endif
if op = 1
    op_name$ = "P RI R I"
elsif op = 2
    op_name$ = "P I R RI"
elsif op = 3
    op_name$ = "P Tk R RTk"
else
    op_name$ = "P RTk R Tk"
endif

for v from 1 to 4
    for hh from 1 to 2
        b0 = 3 * hh - 2
        @trichordClass: line[v, b0], line[v, b0 + 1], line[v, b0 + 2]
        triCode[v, hh] = trichordClass.code
    endfor
endfor

for v from 1 to 4
    for k from 1 to 6
        arrLine[1, v, k] = line[v, k]
    endfor
    arrLab$[1, v] = opPlain$[v]
endfor

# Inversion axis of the array (used by Structural register and Symmetric
# space): pcs x and ax_n - x are mirror images. 2*ax_c0 = ax_n (mod 12).
if comb_nInv > 0
    ax_n = inv_n
else
    ax_n = (pP[1] + pP[6]) mod 12
endif
ax_c0 = ax_n / 2
best_d = 1e9
for mm from -20 to 20
    cand_c0 = ax_n / 2 + 6 * mm
    if abs(cand_c0 - register_centre_MIDI) < best_d
        best_d = abs(cand_c0 - register_centre_MIDI)
        ax_c0 = cand_c0
    endif
endfor
for c from 0 to 11
    inHexP[c] = 0
endfor
for k from 1 to 6
    inHexP[pP[k]] = 1
endfor

# ============================================================
# SERIAL ENGINE: secondary sets
# ============================================================
if comb_nTr > 0
    sec_useT = 1
    sec_n = tr_k
    sec_op$ = "T" + string$(tr_k) + "R"
else
    sec_useT = 0
    sec_n = inv_n
    sec_op$ = "I" + string$(inv_n) + "R"
endif
sec_ok = 0
for v from 1 to 4
    for k from 1 to 6
        src_pc = line[v, 7 - k]
        if sec_useT = 1
            arrLine[2, v, k] = (src_pc + sec_n) mod 12
        else
            arrLine[2, v, k] = ((sec_n - src_pc) mod 12 + 12) mod 12
        endif
        fl_line[k] = arrLine[2, v, k]
    endfor
    @formLabel
    arrLab$[2, v] = formLabel.lab$
    for c from 0 to 11
        seen[c] = 0
    endfor
    for k from 1 to 6
        seen[arrLine[1, v, k]] = 1
        seen[arrLine[2, v, k]] = 1
    endfor
    cnt = 0
    for c from 0 to 11
        cnt = cnt + seen[c]
    endfor
    secSetOk[v] = cnt = 12
    sec_ok = sec_ok + secSetOk[v]
endfor

seg_label$ = ""
for gi from 1 to 4
    for m from 1 to 3
        segPc[gi, m] = pP[gi + m - 1]
    endfor
    @trichordClass: segPc[gi, 1], segPc[gi, 2], segPc[gi, 3]
    segCode[gi] = trichordClass.code
    seg_label$ = seg_label$ + "0" + string$(segCode[gi]) + " "
endfor

arr_agg_ok = 1
for hh from 1 to 2
    for c from 0 to 11
        seen[c] = 0
    endfor
    for v from 1 to 4
        for k from 3 * hh - 2 to 3 * hh
            seen[line[v, k]] = 1
        endfor
    endfor
    for c from 0 to 11
        if seen[c] = 0
            arr_agg_ok = 0
        endif
    endfor
endfor

# ============================================================
# SELF-TEST 2: serial relations
# ============================================================
okv = 1
for k from 1 to 6
    if line[3, k] <> line[1, 7 - k] or line[4, k] <> line[2, 7 - k]
        okv = 0
    endif
endfor
@stCheck: okv, "T = R(S) and B = R(A)"
for c from 0 to 11
    seen[c] = 0
endfor
for k from 1 to 6
    seen[pP[k]] = 1
    seen[yY[k]] = 1
endfor
cnt = 0
for c from 0 to 11
    cnt = cnt + seen[c]
endfor
okv = cnt = 12
@stCheck: okv, "P and Y are complementary hexachords"
@stCheck: arr_agg_ok, "trichordal aggregates of the basic array"
okv = 1
for v from 1 to 4
    for k from 1 to 6
        fl_line[k] = line[v, k]
    endfor
    @formLabel
    if formLabel.lab$ = "?"
        okv = 0
    endif
endfor
@stCheck: okv, "every basic line is a P/I/R/RI form of P"
okv = 1
for nn from 0 to 11
    for k from 1 to 6
        ii = ((nn - pP[k]) mod 12 + 12) mod 12
        if ((nn - ii) mod 12 + 12) mod 12 <> pP[k]
            okv = 0
        endif
        tt = (pP[k] + nn) mod 12
        if ((tt - nn) mod 12 + 12) mod 12 <> pP[k]
            okv = 0
        endif
    endfor
endfor
@stCheck: okv, "I_n involution and T_n invertibility (all n)"
if secondary_sets
    okv = sec_ok = 4
    @stCheck: okv, "secondary sets are 12-tone (4/4)"
endif

# ============================================================
# SERIAL ENGINE: trichord derivation
# ============================================================
derive_random = hexachord_source >= 2 or voice_distribution = 2
n_valid = 0
deriv_label$ = ""
if derivation_cycles > 0
    for gi from 1 to 4
        @derive: gi
        if dervNSol[gi] > 0
            n_valid = n_valid + 1
            validG[n_valid] = gi
            deriv_label$ = deriv_label$ + "0" + string$(segCode[gi]) + "(" + string$(dervNSet[gi]) + ") "
        else
            deriv_label$ = deriv_label$ + "0" + string$(segCode[gi]) + "(none) "
        endif
    endfor
    if n_valid = 0
        exitScript: "No segmental trichord of this hexachord can partition the aggregate; trichord derivation is impossible here."
    endif
endif

n_derived_agg = 0
last_arr = 1 + secondary_sets
# all 24 voice permutations, identity first (lexicographic)
n_perm = 0
for p1 from 1 to 4
    for p2 from 1 to 4
        for p3 from 1 to 4
            for p4 from 1 to 4
                if p1 <> p2 and p1 <> p3 and p1 <> p4 and p2 <> p3 and p2 <> p4 and p3 <> p4
                    n_perm = n_perm + 1
                    permL[n_perm, 1] = p1
                    permL[n_perm, 2] = p2
                    permL[n_perm, 3] = p3
                    permL[n_perm, 4] = p4
                endif
            endfor
        endfor
    endfor
endfor
for j from 1 to n_agg
    aggPivot[j] = 0
endfor
hyb_count = 0
hyb_kept = 0
hyb_changed = 0
hyb_fail = 0
hyb_note$ = ""
for k from 1 to n_cyc
    j1 = 2 * k - 1
    j2 = 2 * k
    cycGen[k] = 0
    d = k - 1 - secondary_sets
    if k = 1
        cycKind$[k] = "basic"
        @aggArray: j1, 1, 1
        @aggArray: j2, 1, 2
    elsif d <= 0
        cycKind$[k] = "secondary"
        @aggArray: j1, 2, 1
        @aggArray: j2, 2, 2
    else
        g = validG[((d - 1) mod n_valid) + 1]
        cycGen[k] = segCode[g]
        cycKind$[k] = "0" + string$(segCode[g])
        if d = 1
            # Hybrid join: first aggregate restates the first aggregate of the
            # preceding array (declared pivot); the derived second aggregate is
            # assigned to voices so that every voice line keeps 6 distinct pcs.
            @aggArray: j1, last_arr, 1
            aggPivot[j1] = if last_arr = 2 then 3 else 1 fi
            hyb_count = hyb_count + 1
            @hybridDerived: j2, j1, g
            if hyb_ok = 1
                n_derived_agg = n_derived_agg + 1
            else
                # no valid assignment exists: this join becomes a fully derived cycle
                hyb_fail = hyb_fail + 1
                aggPivot[j1] = 0
                @aggDerived: j1, g, 0
                @aggDerived: j2, g, 1
                n_derived_agg = n_derived_agg + 2
            endif
        else
            @aggDerived: j1, g, 0
            @aggDerived: j2, g, 1
            n_derived_agg = n_derived_agg + 2
        endif
    endif
endfor

okv = 1
for j from 1 to n_agg
    if aggArr[j] = 0
        for v from 1 to 4
            @trichordClass: aggPc[j, v, 1], aggPc[j, v, 2], aggPc[j, v, 3]
            if trichordClass.code <> aggGen[j]
                okv = 0
            endif
        endfor
    endif
    for c from 0 to 11
        seen[c] = 0
    endfor
    for v from 1 to 4
        for m from 1 to 3
            seen[aggPc[j, v, m]] = 1
        endfor
    endfor
    cnt = 0
    for c from 0 to 11
        cnt = cnt + seen[c]
    endfor
    if cnt <> 12
        okv = 0
    endif
endfor
@stCheck: okv, "planned aggregates complete; derived trichords in generator class"

# Horizontal integrity: within a cycle each voice line (its trichords in the
# two aggregates) holds 6 distinct pcs.
horiz_ok = 1
horiz_bad$ = ""
for k from 1 to n_cyc
    for v from 1 to 4
        for c from 0 to 11
            seen[c] = 0
        endfor
        for m from 1 to 3
            seen[aggPc[2 * k - 1, v, m]] = 1
            seen[aggPc[2 * k, v, m]] = 1
        endfor
        cnt = 0
        for c from 0 to 11
            cnt = cnt + seen[c]
        endfor
        if cnt < 6
            horiz_ok = 0
            horiz_bad$ = horiz_bad$ + "c" + string$(k) + vName$[v] + " "
        endif
    endfor
endfor
@stCheck: horiz_ok, "horizontal: every voice line in every cycle has 6 distinct pcs"

# Repetition classification. Chromatic completeness is tested above; here an
# exact repetition of the voice-assignment matrix (same ordered trichord in
# every voice) is an error only when it is not one of the declared relations:
#   pivot       the hybrid join restates the preceding array's first aggregate
#   recurrence  the derivation schedule returns to a generator it used before
n_rep_pivot = 0
n_rep_recur = 0
n_rep_undecl = 0
rep_list$ = ""
for j from 1 to n_agg - 1
    for jj from j + 1 to n_agg
        same = 1
        for v from 1 to 4
            for m from 1 to 3
                if aggPc[j, v, m] <> aggPc[jj, v, m]
                    same = 0
                endif
            endfor
        endfor
        if same
            if aggPivot[jj] = j
                n_rep_pivot = n_rep_pivot + 1
                rep_list$ = rep_list$ + string$(jj) + "=" + string$(j) + " pivot; "
            elsif aggArr[j] = 0 and aggArr[jj] = 0 and aggGenIdx[j] = aggGenIdx[jj] and (j mod 2) = (jj mod 2)
                n_rep_recur = n_rep_recur + 1
                rep_list$ = rep_list$ + string$(jj) + "=" + string$(j) + " recurrence; "
            else
                n_rep_undecl = n_rep_undecl + 1
                rep_list$ = rep_list$ + string$(jj) + "=" + string$(j) + " UNDECLARED; "
            endif
        endif
    endfor
endfor
@stCheck: n_rep_undecl = 0, "every exact aggregate-matrix repetition is a declared relation"

for j from 1 to n_agg
    blkTgt[j, 0] = 0
    for k from 1 to n_cls
        blkTgt[j, clsCode[k]] = 0
    endfor
    if associative_target = 1
        blkTgt[j, 15] = 1
        blkTgt[j, 12] = 1
    elsif associative_target = 2
        blkTgt[j, 25] = 1
        blkTgt[j, 14] = 1
    elsif associative_target = 4 and aggGen[j] > 0
        blkTgt[j, aggGen[j]] = 1
    else
        for gi from 1 to 4
            blkTgt[j, segCode[gi]] = 1
        endfor
    endif
    for k from 1 to n_cls
        if blkTgt[j, clsCode[k]] = 1
            anyTarget[clsCode[k]] = 1
        endif
    endfor
endfor
if associative_target = 1
    target_label$ = "015 012"
elsif associative_target = 2
    target_label$ = "025 014"
elsif associative_target = 3
    target_label$ = "segmental " + seg_label$
else
    target_label$ = "current generator"
endif

# ============================================================
# FORM ENGINE: role of each cycle and the strategies it implies
# ============================================================
for k from 1 to n_cyc
    if realization = 1
        r = 1
    elsif form_plan = 5
        if cycKind$[k] = "basic"
            r = 1
        elsif cycKind$[k] = "secondary"
            r = 2
        elsif k - 1 - secondary_sets = 1
            r = 5
        elsif cycGen[k] = 12 or cycGen[k] = 13
            r = 3
        elsif cycGen[k] = 25 or cycGen[k] = 27
            r = 6
        else
            r = 4
        endif
    else
        r = planSeq[form_plan, k]
        if form_plan >= 2 and n_cyc >= 3 and k = n_cyc
            if cycRole[k - 1] <> 6
                r = 6
            endif
        endif
    endif
    cycRole[k] = r
    cycWhy$[k] = "plan table"
    @cycleStrategies: k
endfor

# ============================================================
# TIME-POINT ENGINE: pattern series per cycle
# ============================================================
partitions_ok = 0
n_att = 0
for k from 1 to n_cyc
    if rhythm = 7
        cycOp[k] = 9
        for q from 1 to 16
            perm[q] = q - 1
        endfor
        for q from 1 to 15
            j = randomInteger(q, 16)
            tmp = perm[q]
            perm[q] = perm[j]
            perm[j] = tmp
        endfor
    elsif rhythm = 8
        cycOp[k] = grayOp[((k - 1) mod 8) + 1]
    elsif rhythm <= 4
        cycOp[k] = ((rhythm - 1 + k - 1) mod 4) + 1
    else
        cycOp[k] = ((rhythm - 5 + k - 1) mod 4) + 5
    endif
    for m from 0 to 15
        seenM[m] = 0
    endfor
    cyc_att = 0
    for u from 1 to 16
        uu = 16 * (k - 1) + u
        if cycOp[k] = 9
            ser[uu] = perm[u]
        else
            @rhPattern: cycOp[k], u
            ser[uu] = rhPattern.m
        endif
        serCode[uu] = codeOf[ser[uu]]
        seenM[ser[uu]] = 1
        for p from 0 to 3
            if (floor(ser[uu] / 2 ^ (3 - p)) mod 2) = 1 and texture = 2
                cyc_att = cyc_att + 1
            elsif (floor(ser[uu] / 2 ^ (3 - p)) mod 2) = 1
                n_att = n_att + 1
                cyc_att = cyc_att + 1
                atkBeat[n_att] = (uu - 1) + p / 4
                atkUnit[n_att] = uu
                atkPos[n_att] = p
                atkCyc[n_att] = k
                atkCard[n_att] = popc[ser[uu]]
            endif
        endfor
    endfor
    used = 0
    for m from 0 to 15
        used = used + seenM[m]
    endfor
    if used = 16 and cyc_att = 32
        partitions_ok = partitions_ok + 1
    endif
endfor
if (texture = 1 and n_att <> 32 * n_cyc) or partitions_ok <> n_cyc
    exitScript: "Internal error: partition ordering is not exhaustive (" + string$(partitions_ok) + " of " + string$(n_cyc) + " cycles, " + string$(n_att) + " attacks)."
endif
@stCheck: partitions_ok = n_cyc, "every cycle series exhaustive (16 patterns, 32 attacks)"
if n_cyc = 1
    rhythm_name$ = opName$[cycOp[1]]
elsif rhythm = 7
    rhythm_name$ = "New ordering per cycle"
elsif rhythm = 8
    rhythm_name$ = "Gray path O Q R M MC RC QC C"
else
    rhythm_name$ = "Rotating from " + opName$[cycOp[1]]
endif

if texture = 1
# ============================================================
# AGGREGATE BLOCKS (composite stream only) (12 entries + rearticulations each)
# ============================================================
seg_clamped = 0
for k from 1 to n_cyc
    a0 = 32 * (k - 1)
    if segmentation = 1
        n1 = 16
    else
        n1 = 0
        for a from a0 + 1 to a0 + 32
            if atkUnit[a] <= 16 * (k - 1) + 8
                n1 = n1 + 1
            endif
        endfor
        if n1 < 12
            n1 = 12
            seg_clamped = seg_clamped + 1
        elsif n1 > 20
            n1 = 20
            seg_clamped = seg_clamped + 1
        endif
    endif
    j1 = 2 * k - 1
    blkA0[j1] = a0 + 1
    blkA1[j1] = a0 + n1
    blkA0[j1 + 1] = a0 + n1 + 1
    blkA1[j1 + 1] = a0 + 32
endfor
for j from 1 to n_agg
    blkN[j] = blkA1[j] - blkA0[j] + 1
    blkNRe[j] = blkN[j] - 12
    blkCyc[j] = floor((j - 1) / 2) + 1
    blkStart[j] = atkBeat[blkA0[j]]
    for a from blkA0[j] to blkA1[j]
        atkBlk[a] = j
        isRe[a] = 0
    endfor
endfor
for j from 1 to n_agg
    blkEnd[j] = if j < n_agg then blkStart[j + 1] else 16 * n_cyc fi
endfor

# ============================================================
# REARTICULATION SLOTS
#   pol 1 strict (evenly spaced), 2 quarter onsets, 3 early completion
#   (echoes after the 12th entry), 4 delayed completion (echoes just
#   before the final entry, which completes the aggregate)
# ============================================================
for j from 1 to n_agg
    k = blkCyc[j]
    if cycPol[k] > 0
        pol = cycPol[k]
    elsif rearticulation = 1
        pol = 1
    else
        pol = 2
    endif
    blkPol[j] = pol
    bs = blkA0[j] - 1
    nb = blkN[j]
    nre = blkNRe[j]
    if nre > 0
        if pol = 3
            for q from 1 to nre
                isRe[bs + nb - nre + q] = 1
            endfor
        elsif pol = 4
            for q from 1 to nre
                isRe[bs + nb - nre - 1 + q] = 1
            endfor
        elsif pol = 1
            for q from 1 to nre
                lp = max(2, round(q * nb / nre))
                while isRe[bs + lp] = 1 and lp > 2
                    lp = lp - 1
                endwhile
                isRe[bs + lp] = 1
            endfor
        else
            n_cand = 0
            for lp from 2 to nb
                if atkPos[bs + lp] = 0
                    n_cand = n_cand + 1
                    cand[n_cand] = lp
                endif
            endfor
            chosen = 0
            if n_cand >= nre
                for q from 1 to nre
                    ci = floor((q - 0.5) * n_cand / nre) + 1
                    isRe[bs + cand[ci]] = 1
                endfor
                chosen = nre
            else
                for q from 1 to n_cand
                    isRe[bs + cand[q]] = 1
                    chosen = chosen + 1
                endfor
            endif
            q = 1
            while chosen < nre and q <= nre
                lp = max(2, round(q * nb / nre))
                while isRe[bs + lp] = 1 and lp > 2
                    lp = lp - 1
                endwhile
                if isRe[bs + lp] = 0
                    isRe[bs + lp] = 1
                    chosen = chosen + 1
                endif
                q = q + 1
            endwhile
            lp = nb
            while chosen < nre
                if isRe[bs + lp] = 0
                    isRe[bs + lp] = 1
                    chosen = chosen + 1
                endif
                lp = lp - 1
            endwhile
        endif
    endif
    ne = 0
    for a from blkA0[j] to blkA1[j]
        if isRe[a] = 0
            ne = ne + 1
            eSlot[j, ne] = a
        endif
    endfor
    blkNE[j] = ne
endfor
okv = 1
for j from 1 to n_agg
    if blkNE[j] <> 12
        okv = 0
    endif
endfor
@stCheck: okv, "12 entry slots per aggregate"
if okv = 0
    exitScript: "Internal error: an aggregate block does not have 12 entry slots."
endif

# ============================================================
# VOICE DISTRIBUTION
# ============================================================
svd_total_iter = 0
for j from 1 to n_agg
    k = blkCyc[j]
    r = cycRole[k]
    svdClT = roleClT[r]
    svdOvT = roleOvT[r]
    svdStT = roleStT[r]
    svdW = if roleW[r] = 1 and voice_distribution = 3 then ((j - 1) mod 4) + 1 else 0 fi
    blkW[j] = svdW
    blkLead[j] = ((j - 1) mod 4) + 1
    svdLen = (blkEnd[j] - blkStart[j]) * 4
    for ee from 1 to 12
        svdT[ee] = round((atkBeat[eSlot[j, ee]] - blkStart[j]) * 4)
        svdA[ee] = ((ee - 1) mod 4) + 1
    endfor
    if voice_distribution = 2
        for i from 1 to 11
            jj = randomInteger(i, 12)
            tmp = svdA[i]
            svdA[i] = svdA[jj]
            svdA[jj] = tmp
        endfor
    elsif voice_distribution = 3
        @svdClimb
        svd_total_iter = svd_total_iter + svd_iters
    endif
    @svdScore
    blkScore[j] = svd_score
    blkClus[j] = svd_clus
    blkOv[j] = svd_ov
    blkStag[j] = svd_stag
    blkDup[j] = svd_dup
    for ee from 1 to 12
        blkAsg[j, ee] = svdA[ee]
    endfor
endfor

# Assign aggregate trichord entries (line order kept by construction).
for j from 1 to n_agg
    for v from 1 to 4
        nextPos[v] = 1
    endfor
    for ee from 1 to 12
        a = eSlot[j, ee]
        v = blkAsg[j, ee]
        atkVoice[a] = v
        atkIdx[a] = nextPos[v]
        atkPc[a] = aggPc[j, v, nextPos[v]]
        atkEntry[a] = ee
        atkComplete[a] = ee = 12
        atkSrc[a] = a
        nextPos[v] = nextPos[v] + 1
    endfor
endfor
for a from 1 to n_att
    if isRe[a] = 1
        atkVoice[a] = 0
        atkIdx[a] = 0
        atkPc[a] = -1
        atkEntry[a] = 0
        atkComplete[a] = 0
    endif
endfor

# Resolve rearticulations left to right.
for a from 1 to n_att
    if isRe[a] = 1
        blk = atkBlk[a]
        if rearticulation < 3
            src = a - 1
        else
            bs = blkA0[blk] - 1
            best = -1e9
            src = a - 1
            for b from bs + 1 to a - 1
                if isRe[b] = 0
                    cpc = atkPc[b]
                    score = 0
                    if a - 2 >= 1
                        @trichordClass: atkPc[a - 2], atkPc[a - 1], cpc
                        score = score + blkTgt[blk, trichordClass.code]
                    endif
                    if a + 1 <= n_att
                        if isRe[a + 1] = 0
                            @trichordClass: atkPc[a - 1], cpc, atkPc[a + 1]
                            score = score + blkTgt[blk, trichordClass.code]
                        endif
                    endif
                    if cpc = atkPc[a - 1]
                        score = score - 0.5
                    endif
                    score = score + randomUniform(0, 0.01)
                    if score > best
                        best = score
                        src = b
                    endif
                endif
            endfor
        endif
        src = atkSrc[src]
        atkSrc[a] = src
        atkVoice[a] = atkVoice[src]
        atkIdx[a] = atkIdx[src]
        atkPc[a] = atkPc[src]
        atkEntry[a] = atkEntry[src]
    endif
endfor

endif

# ============================================================
# REALIZATION: register, articulation, dynamics, space
# ============================================================
for v from 1 to 4
    vc[v] = register_centre_MIDI + (2.5 - v) * register_spread
endfor
# Structural register map per cycle: fixed registral aggregate,
# mirror-symmetric around the inversion axis ax_c0.
reg_sym_pairs = 0
reg_sym_ok = 0
any_struct_reg = 0
for v from 1 to 4
    panFix[v] = -0.6 + 0.4 * (v - 1)
    panEx[v] = 0
    panCr[v] = -0.8 + (v - 1) * 0.5333
endfor
panEx[1] = -0.75
panEx[2] = -0.25
panEx[3] = 0.75
panEx[4] = 0.25

# timbre tables (needed by the analytic brightness pass during realization)
n_h = if timbre = 5 then 13 else 8 fi
for v from 1 to 4
    for h from 1 to n_h
        w[v, h] = 0
    endfor
    w[v, 1] = 1
endfor
if timbre = 2
    w[1, 2] = 0.18
    w[1, 3] = 0.08
    w[2, 3] = 0.12
    w[3, 2] = 0.15
    w[3, 4] = 0.06
    w[4, 2] = 0.20
    w[4, 3] = 0.10
    timbre_name$ = "Additive"
elsif timbre = 3
    for v from 1 to 4
        for h from 1 to 6
            w[v, h] = 1 / h ^ 0.9
        endfor
    endfor
    timbre_name$ = "Bright"
elsif timbre = 4
    for v from 1 to 4
        for h from 1 to 6
            w[v, h] = 1 / h
        endfor
    endfor
    timbre_name$ = "Percussive"
elsif timbre = 5
    timbre_name$ = "Structural slots"
    for k from 1 to n_cyc
        for v from 1 to 4
            for h from 1 to 13
                stw[k, v, h] = 0
            endfor
            stw[k, v, 1] = 1
            for q from 1 to 6
                if q <= 3
                    spc = aggPc[2 * k - 1, v, q]
                else
                    spc = aggPc[2 * k, v, q - 3]
                endif
                hh = spc + 2
                stw[k, v, hh] = max(stw[k, v, hh], 0.55 * (7 - q) / 6 / hh ^ 0.6)
            endfor
        endfor
    endfor
elsif timbre = 6
    timbre_name$ = "Compl. spectral"
elsif timbre = 7
    timbre_name$ = "Interval spectral"
else
    timbre_name$ = "Pure"
endif
if timbre = 4
    tau = 0.22 * decay_scale
else
    tau = 0.9 * decay_scale
endif

if timbre = 4
    tau = 0.22 * decay_scale
else
    tau = 0.9 * decay_scale
endif
reg_clamped = 0
rng_moved = 0
rng_axis_moved = 0
rng_re_supp = 0
rng_re_fit = 0
for v from 1 to 4
    vPrev[v] = 0
    rng_moved_v[v] = 0
endfor
min_midi = 1000
max_midi = -1000
max_end_beat = 0
for k from 1 to n_cyc
    cycWhy$[k] = if realization = 2 then cycWhy$[k] else "historical" fi
endfor
tex_fallback = 0
rp_analyze = 0
mono_cuts = 0
n_gest = 0
form_feature_missing = 0
@formSetup
seg_clamped = 0
svd_total_iter = 0
if texture = 1
    for kc from 1 to n_cyc
        cycA0[kc] = 32 * (kc - 1) + 1
        cycA1[kc] = 32 * kc
        if cycReg[kc] = 4
            @buildRegMap: kc
        endif
    endfor
    for ai from 1 to n_att
        @realizeEvent: ai
    endfor
    for kc from 1 to n_cyc
        @cycleFeatures: kc
        @cycleBrightness: kc
        @gestureShapes: kc
        @cycleNovelty: kc
    endfor
else
    # ============================================================
    # INDEPENDENT RHYTHMIC VOICES: generate, realize and measure cycle by
    # cycle, so that the role of each cycle responds to what the previous
    # cycle actually produced.
    # ============================================================
    n_att = 0
    for v from 1 to 4
        gh_type[v] = 0
        gh_place[v] = 0
    endfor
    gestMap[1] = 2
    gestMap[2] = 1
    gestMap[3] = 4
    gestMap[4] = 3
    gestMap[5] = 5
    for kc from 1 to n_cyc
        cycRel[kc] = 0
    endfor
    for kc from 1 to n_cyc
        @chooseRole: kc
        @cycleStrategies: kc
        if cycReg[kc] = 4
            @buildRegMap: kc
        endif
        cycA0[kc] = n_att + 1
        @texWindow: kc, 1
        @texWindow: kc, 2
        cycA1[kc] = n_att
        for ai from cycA0[kc] to cycA1[kc]
            @realizeEvent: ai
        endfor
        # exactly one sounding voice in every relay window: whatever was
        # still sounding (previous cycle, or a non-relay window of this cycle)
        # stops at the window's first attack
        for jw from 2 * kc - 1 to 2 * kc
            if blkMode[jw] = 2
                tcut = atkBeat[blkA0[jw]]
                a_lo = if kc > 1 then cycA0[kc - 1] else 1 fi
                for ai from a_lo to blkA0[jw] - 1
                    if atkBeat[ai] + atkSoundB[ai] > tcut
                        atkSoundB[ai] = tcut - atkBeat[ai]
                        atkEffB[ai] = min(atkEffB[ai], atkSoundB[ai])
                        mono_cuts = mono_cuts + 1
                    endif
                endfor
            endif
        endfor
        @cycleFeatures: kc
        @cycleBrightness: kc
        @gestureShapes: kc
        @cycleNovelty: kc
    endfor
endif
if any_struct_reg
    @stCheck: reg_sym_ok = reg_sym_pairs, "structural register mirror-symmetric about the axis"
endif
# Voice ranges actually generated; pitch class of every sounding pitch
rng_pc_bad = 0
for v from 1 to 4
    vMinM[v] = 1000
    vMaxM[v] = -1000
    rng_out_v[v] = 0
endfor
for a from 1 to n_att
    v = atkVoice[a]
    vMinM[v] = min(vMinM[v], atkMidi[a])
    vMaxM[v] = max(vMaxM[v], atkMidi[a])
    if (atkMidi[a] - atkPc[a]) mod 12 <> 0
        rng_pc_bad = rng_pc_bad + 1
    endif
    if voice_range_protection and (atkMidi[a] < vLo[v] or atkMidi[a] > vHi[v])
        rng_out_v[v] = rng_out_v[v] + 1
    endif
endfor
if voice_range_protection
    for v from 1 to 4
        @stCheck: rng_out_v[v] = 0, vFull$[v] + " events within " + string$(vLo[v]) + "-" + string$(vHi[v]) + " (actual " + string$(vMinM[v]) + "-" + string$(vMaxM[v]) + ")"
    endfor
    @stCheck: rng_pc_bad = 0, "range protection: every sounding pitch keeps its event's pitch class"
endif


# Structural checks on the realized stream.
n_agg_ok = 0
re_in_agg = 0
order_ok = 1
for blk from 1 to n_agg
    for c from 0 to 11
        seen[c] = 0
    endfor
    for v from 1 to 4
        lastIdx[v] = 0
    endfor
    for a from blkA0[blk] to blkA1[blk]
        seen[atkPc[a]] = 1
        if isRe[a] = 0
            v = atkVoice[a]
            if atkIdx[a] <> lastIdx[v] + 1 or atkPc[a] <> aggPc[blk, v, atkIdx[a]]
                order_ok = 0
            endif
            lastIdx[v] = atkIdx[a]
        elsif atkBlk[atkSrc[a]] = blk
            re_in_agg = re_in_agg + 1
        endif
    endfor
    cnt = 0
    for c from 0 to 11
        cnt = cnt + seen[c]
    endfor
    aggFull[blk] = cnt
    if cnt = 12
        n_agg_ok = n_agg_ok + 1
    endif
endfor
n_new = 0
n_re = 0
for a from 1 to n_att
    if isRe[a] = 1
        n_re = n_re + 1
    else
        n_new = n_new + 1
    endif
endfor
@stCheck: n_agg_ok = n_agg, "realized aggregates complete"
@stCheck: order_ok, "line order kept in every voice"
@stCheck: re_in_agg = n_re, "rearticulations repeat a pc of their own aggregate"

n_surf = 0
surf_hits = 0
for a from 1 to n_att - 2
    @trichordClass: atkPc[a], atkPc[a + 1], atkPc[a + 2]
    tc = trichordClass.code
    surfCount[tc] = surfCount[tc] + 1
    if tc > 0
        n_surf = n_surf + 1
        surf_hits = surf_hits + blkTgt[atkBlk[a + 1], tc]
    endif
endfor


if texture = 2
    @texTests
    @stCheck: form_feature_missing = 0, "form: every decision feature existed when the next cycle was chosen"
endif
if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

if texture = 1
# Structure-versus-random comparison of the voice distribution (own LCG,
# so it never disturbs Praat's random sequence).
lcg_state = 20260404
svd_rand_mean = 0
svd_real_mean = 0
for j from 1 to n_agg
    k = blkCyc[j]
    r = cycRole[k]
    svdClT = roleClT[r]
    svdOvT = roleOvT[r]
    svdStT = roleStT[r]
    svdW = blkW[j]
    svdLen = (blkEnd[j] - blkStart[j]) * 4
    for ee from 1 to 12
        svdT[ee] = round((atkBeat[eSlot[j, ee]] - blkStart[j]) * 4)
    endfor
    acc_s = 0
    for rr from 1 to 40
        for ee from 1 to 12
            svdA[ee] = ((ee - 1) mod 4) + 1
        endfor
        for i from 1 to 11
            @lcgNext
            jj = i + floor(lcg_u * (13 - i))
            tmp = svdA[i]
            svdA[i] = svdA[jj]
            svdA[jj] = tmp
        endfor
        @svdScore
        acc_s = acc_s + svd_score
    endfor
    blkRand[j] = acc_s / 40
    svd_rand_mean = svd_rand_mean + blkRand[j] / n_agg
    svd_real_mean = svd_real_mean + blkScore[j] / n_agg
endfor

else
    svd_rand_mean = 0
    svd_real_mean = 0
endif

if trichord_halo
    max_end_beat = max(max_end_beat, atkBeat[n_att] + 1.5)
endif
master_duration = (max_end_beat + 0.25) * beat
musical_duration = 16 * n_cyc * beat
# Target mode: the audio always contains the whole musical duration (when
# the last cycle ends in rests, the file runs to its final beat). Tempo mode
# keeps the v0.5.3 length: last sound + 0.25 beat.
dur_padded = 0
if duration_mode = 2 and master_duration < musical_duration
    dur_padded = musical_duration - master_duration
    master_duration = musical_duration
endif

# ============================================================
# RESULT METRICS (from the event table)
# ============================================================
@resultMetrics

# ============================================================
# GLOBAL DYNAMIC ARC: one shared envelope table for audio and score
# ============================================================
arc_names$[1] = "None"
arc_names$[2] = "Arch"
arc_names$[3] = "Inverted arch"
arc_names$[4] = "Rising"
arc_names$[5] = "Falling"
arc_on = arc_shape > 1
@arcBuild
@arcWedgePlan

# ============================================================
# MUSICXML (in-memory Strings object and/or file)
# ============================================================
xmlPath$ = ""
writeXmlActual = 0
xml_note$ = ""
if write_MusicXML_file
    xmlPath$ = chooseWriteFile$: "Save MusicXML as...", "babbitt_arrays_" + preset_name$ + ".musicxml"
    if xmlPath$ <> ""
        writeXmlActual = 1
        if praatVersion >= 7000
            trust_ok = askForTrust ()
            if trust_ok = 0
                writeXmlActual = 0
                xml_note$ = " (file refused: no write permission)"
            endif
        endif
    else
        xml_note$ = " (file picker cancelled)"
    endif
endif
buildXml = 1
xmlStringsId = 0
xmlStringsName$ = ""
nXmlLines = 0
xml$ = ""
xml_measures = 0
xml_consistent = 0
if buildXml
    @buildMusicXml
    xml_consistent = 1
    for v from 1 to 4
        evc = 0
        for a from 1 to n_att
            if atkVoice[a] = v
                evc = evc + 1
            endif
        endfor
        if xm_onsets[v] <> evc or xm_badMeasures > 0
            xml_consistent = 0
        endif
    endfor
    @stCheck: xml_consistent, "MusicXML: one notated onset per event, every bar = 16 sixteenths"
    xml_pitch_ok = 1
    for v from 1 to 4
        if xm_pmin[v] <> vMinM[v] or xm_pmax[v] <> vMaxM[v]
            xml_pitch_ok = 0
        endif
        if voice_range_protection and (xm_pmin[v] < vLo[v] or xm_pmax[v] > vHi[v])
            xml_pitch_ok = 0
        endif
    endfor
    @stCheck: xml_pitch_ok, "MusicXML: written pitch range of every part = event table" + (if voice_range_protection then ", inside its voice range" else "" fi)
    # STRUCTURAL GATE: no audio and no MusicXML export after a failed check
    @structuralGate
    # The MusicXML is complete here but is exported only after the final
    # audio QC (see FINALIZE / QC): a failed run exports nothing.
endif

# ============================================================
# SYNTHESIS ENGINE
# ============================================================
if rearticulation = 1
    rearticulation_name$ = "Strict"
elsif rearticulation = 2
    rearticulation_name$ = "Grouped"
else
    rearticulation_name$ = "Associative"
endif
if hexachord_source = 1
    source_name$ = "opening"
elsif hexachord_source = 2
    source_name$ = "Type-A " + string$(typeA_pick) + "/" + string$(typeA_count)
else
    source_name$ = "any comb."
endif
realization_name$ = if realization = 1 then "Historical / analytical" else "Creative combinatorial" fi

master_name$ = "BabbittArrays_" + preset_name$ + "_" + string$(run_id)
Create Sound from formula: master_name$, nch, 0, master_duration, sample_rate, "0"
master_id = selected("Sound")
n_master_samples = Get number of samples
stemH_id = Create Sound from formula: "babbitt_stemH_tmp", 1, 0, master_duration, sample_rate, "0"
stemC_id = Create Sound from formula: "babbitt_stemC_tmp", 1, 0, master_duration, sample_rate, "0"
fundH_id = Create Sound from formula: "babbitt_fundH_tmp", 1, 0, master_duration, sample_rate, "0"
fundC_id = Create Sound from formula: "babbitt_fundC_tmp", 1, 0, master_duration, sample_rate, "0"

dropped_partials = 0
max_partial = 0
n_halo = 0
halo_out = 0
n_partials_total = 0
for a from 1 to n_att
    @renderEvent: a
endfor

# ============================================================
# FINALIZE / QC
# ============================================================
if arc_on
    @arcRmsWindows
    for i from 1 to arc_nb
        arcPreRms[i] = arcWinR[i]
    endfor
    @arcApplyAudio
endif
selectObject: master_id
pre_norm_peak = Get absolute extremum: 0, 0, "None"
if pre_norm_peak > 0
    Scale peak: output_peak
endif
Rename: "babbitt_arrays_" + preset_name$
master_id = selected("Sound")
final_peak = Get absolute extremum: 0, 0, "None"
final_rms = Get root-mean-square: 0, 0
if arc_on
    @arcMeasure
    @arcGainCurve
endif
n_nan = 0
if final_peak = undefined or final_rms = undefined
    n_nan = 1
endif
if voice_range_protection and trichord_halo
    @stCheck: halo_out = 0, "trichord halo pitches within their voice's range (" + string$(n_halo) + " halos)"
endif
@stCheck: n_nan = 0 and final_peak <= output_peak + 1e-6, "no clipping, no undefined samples"
if st_pass < st_total
    removeObject: master_id, stemH_id, stemC_id, fundH_id, fundC_id
    @structuralGate
endif

# MusicXML export: only now, after the final audio QC has passed
if buildXml
    if writeXmlActual
        writeFile: xmlPath$, xml$
    endif
    if keep_MusicXML_Strings
        xmlStringsId = Create Strings as tokens: "placeholder", " "
        Set string: 1, xmlLine$[1]
        for lineNo from 2 to nXmlLines
            Insert string: 0, xmlLine$[lineNo]
        endfor
        Rename: "musicxml_babbitt_arrays_" + preset_name$
        xmlStringsName$ = selected$("Strings")
    endif
endif
if writeXmlActual and xmlStringsId <> 0
    xmlStatus$ = "file+Strings"
elsif writeXmlActual
    xmlStatus$ = "file"
elsif xmlStringsId <> 0
    xmlStatus$ = "Strings"
else
    xmlStatus$ = "skipped"
endif

# Measured spectral centroid per aggregate (mono mix).
selectObject: master_id
if nch = 2
    mono_id = Convert to mono
else
    mono_id = Copy: "babbitt_mono_tmp"
endif
cent_min = 1e9
cent_max = 0
for j from 1 to n_agg
    selectObject: mono_id
    tA0 = blkStart[j] * beat
    tA1 = min(master_duration, blkEnd[j] * beat)
    part_id = Extract part: tA0, tA1, "rectangular", 1, "no"
    spec_id = To Spectrum: "yes"
    blkCent[j] = Get centre of gravity: 2
    removeObject: spec_id, part_id
    if blkCent[j] <> undefined
        cent_min = min(cent_min, blkCent[j])
        cent_max = max(cent_max, blkCent[j])
    endif
endfor
removeObject: mono_id
@measureSpectra
removeObject: stemH_id, stemC_id, fundH_id, fundC_id
@interCycle
@gestureDiversity

# Reproducibility fingerprint of the event table.
fp = 0
for a from 1 to n_att
    fp = (fp * 31 + atkPc[a] * 7 + atkMidi[a] * 13 + atkVoice[a] * 3 + round(atkDb[a] * 10) + atkArt[a] * 5 + round(atkPan[a] * 100) + round(atkBeat[a] * 4)) mod 1000000007
endfor

# ============================================================
# INFO REPORT
# ============================================================
@infoReport

if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: master_id
    Play
endif

selectObject: master_id
appendInfoLine: "Done. Created Sound: ", selected$("Sound")

# ==============================================================================
# Procedures: self-test, roles, rhythm
# ==============================================================================
procedure structuralGate
    if st_pass < st_total
        writeInfoLine: "Babbitt Combinatorial Arrays: STRUCTURAL SELF-TEST FAILED (", st_total - st_pass, " of ", st_total, ")"
        for .i from 1 to st_total
            appendInfoLine: "  ", stRes$[.i]
        endfor
        exitScript: "Structural self-test failed; no audio and no MusicXML were exported: " + st_fail$
    endif
endproc

procedure stCheck: .ok, .name$
    st_total = st_total + 1
    if .ok
        st_pass = st_pass + 1
        stRes$[st_total] = "pass  " + .name$
    else
        st_fail$ = st_fail$ + .name$ + "; "
        stRes$[st_total] = "FAIL  " + .name$
    endif
endproc

procedure setRole: .r, .cl, .ov, .st, .w, .reg, .sp, .art, .dyn, .sig, .kap, .pol
    roleClT[.r] = .cl
    roleOvT[.r] = .ov
    roleStT[.r] = .st
    roleW[.r] = .w
    roleReg[.r] = .reg
    roleSpace[.r] = .sp
    roleArt[.r] = .art
    roleDyn[.r] = .dyn
    roleSig[.r] = .sig
    roleKap[.r] = .kap
    rolePol[.r] = .pol
endproc

procedure mirror4: .c
    .m = 0
    for .p from 0 to 3
        .bit = floor(.c / 2 ^ (3 - .p)) mod 2
        .m = .m + .bit * 2 ^ .p
    endfor
endproc

# Pattern of quarter .u (1..16) of the opening series under operation .op.
procedure rhPattern: .op, .u
    .src = if opQ[.op] = 1 then 17 - .u else .u fi
    .m = maskOf[origCode[.src]]
    if opM[.op] = 1
        @mirror4: .m
        .m = mirror4.m
    endif
    if opC[.op] = 1
        .m = 15 - .m
    endif
endproc

procedure lcgNext
    lcg_state = (16807 * lcg_state) mod 2147483647
    lcg_u = lcg_state / 2147483647
endproc

# ==============================================================================
# Procedures: structural voice distribution
#   reads svdA[1..12] (voice per entry), svdT[1..12] (sixteenths from the
#   block start), svdLen, targets svdClT svdOvT svdStT, withheld voice svdW
# ==============================================================================
procedure svdScore
    for .v from 1 to 4
        svc[.v] = 0
        svFe[.v] = 12
    endfor
    .adj = 0
    for .ei from 1 to 12
        .v = svdA[.ei]
        svc[.v] = svc[.v] + 1
        svt[.v, svc[.v]] = svdT[.ei]
        if svc[.v] = 1
            svFe[.v] = .ei
        endif
        if .ei > 1
            if svdA[.ei - 1] = .v
                .adj = .adj + 1
            endif
        endif
    endfor
    .clus = .adj / 8
    .ov = 0
    .dup = 0
    for .a from 1 to 3
        for .b from .a + 1 to 4
            .lo = max(svt[.a, 1], svt[.b, 1])
            .hi = min(svt[.a, 3], svt[.b, 3]) + 1
            .u0 = min(svt[.a, 1], svt[.b, 1])
            .u1 = max(svt[.a, 3], svt[.b, 3]) + 1
            .ov = .ov + max(0, .hi - .lo) / (.u1 - .u0)
            if svt[.a, 2] - svt[.a, 1] = svt[.b, 2] - svt[.b, 1]
                if svt[.a, 3] - svt[.a, 2] = svt[.b, 3] - svt[.b, 2]
                    .dup = .dup + 1
                endif
            endif
        endfor
    endfor
    .ov = .ov / 6
    .stag = (max(svFe[1], svFe[2], svFe[3], svFe[4]) - 1) / 11
    .s = -4 * (.clus - svdClT) ^ 2 - 3 * (.ov - svdOvT) ^ 2 - 2 * (.stag - svdStT) ^ 2 - 0.6 * .dup
    if svdW > 0
        if svdA[12] <> svdW
            .s = .s - 2
        endif
        .s = .s + 1.5 * (svt[svdW, 3] - svt[svdW, 2]) / max(svdLen, 1)
    endif
    svd_score = .s
    svd_clus = .clus
    svd_ov = .ov
    svd_stag = .stag
    svd_dup = .dup
endproc

# Deterministic best-improvement hill climb over pairwise swaps.
procedure svdClimb
    @svdScore
    .best = svd_score
    .it = 0
    .go = 1
    while .go = 1 and .it < 40
        .it = .it + 1
        .bi = 0
        .bj = 0
        .bs = .best
        for .i from 1 to 11
            for .j from .i + 1 to 12
                if svdA[.i] <> svdA[.j]
                    .tmp = svdA[.i]
                    svdA[.i] = svdA[.j]
                    svdA[.j] = .tmp
                    @svdScore
                    if svd_score > .bs + 1e-9
                        .bs = svd_score
                        .bi = .i
                        .bj = .j
                    endif
                    svdA[.j] = svdA[.i]
                    svdA[.i] = .tmp
                endif
            endfor
        endfor
        if .bi > 0
            .tmp = svdA[.bi]
            svdA[.bi] = svdA[.bj]
            svdA[.bj] = .tmp
            .best = .bs
        else
            .go = 0
        endif
    endwhile
    svd_iters = .it
endproc

# ==============================================================================
# Procedures: serial helpers (globals only; no dotted interpolation)
# ==============================================================================
procedure combCheck
    for .c from 0 to 11
        comb_in[.c] = 0
    endfor
    for .k from 1 to 6
        comb_in[gv_hex[.k]] = 1
    endfor
    comb_nInv = 0
    for .n from 0 to 11
        .ok = 1
        for .k from 1 to 6
            .img = ((.n - gv_hex[.k]) mod 12 + 12) mod 12
            if comb_in[.img] = 1
                .ok = 0
            endif
        endfor
        if .ok = 1
            comb_nInv = comb_nInv + 1
            comb_inv[comb_nInv] = .n
        endif
    endfor
    comb_nTr = 0
    for .t from 1 to 11
        .ok = 1
        for .k from 1 to 6
            .img = (gv_hex[.k] + .t) mod 12
            if comb_in[.img] = 1
                .ok = 0
            endif
        endfor
        if .ok = 1
            comb_nTr = comb_nTr + 1
            comb_tr[comb_nTr] = .t
        endif
    endfor
    comb_inv[0] = 0
    comb_tr[0] = 0
endproc

procedure trichordClass: .p1, .p2, .p3
    .code = 0
    if .p1 >= 0 and .p2 >= 0 and .p3 >= 0
        if .p1 <> .p2 and .p1 <> .p3 and .p2 <> .p3
            .a = min(.p1, .p2, .p3)
            .c = max(.p1, .p2, .p3)
            .b = .p1 + .p2 + .p3 - .a - .c
            .i1 = .b - .a
            .i2 = .c - .b
            .i3 = 12 - (.c - .a)
            .lo = min(.i1, .i2, .i3)
            .hi = max(.i1, .i2, .i3)
            .mid = .i1 + .i2 + .i3 - .lo - .hi
            .code = 10 * .lo + (.lo + .mid)
        endif
    endif
endproc

procedure formsDisjoint: .fa, .fb
    .res = 1
    for .x from 1 to 3
        for .y from 1 to 3
            if dv_form[.fa, .x] = dv_form[.fb, .y]
                .res = 0
            endif
        endfor
    endfor
endproc

procedure derive: .gi
    for .n from 0 to 11
        for .m from 1 to 3
            dv_form[.n + 1, .m] = (segPc[.gi, .m] + .n) mod 12
            dv_form[.n + 13, .m] = ((.n - segPc[.gi, .m]) mod 12 + 12) mod 12
        endfor
        dv_mask[.n + 1] = 2 ^ dv_form[.n + 1, 1] + 2 ^ dv_form[.n + 1, 2] + 2 ^ dv_form[.n + 1, 3]
        dv_mask[.n + 13] = 2 ^ dv_form[.n + 13, 1] + 2 ^ dv_form[.n + 13, 2] + 2 ^ dv_form[.n + 13, 3]
    endfor
    for .c from 0 to 11
        dv_inG[.c] = 0
    endfor
    for .m from 1 to 3
        dv_inG[segPc[.gi, .m]] = 1
    endfor
    .nL = 0
    for .f from 1 to 24
        .ok = 1
        for .m from 1 to 3
            if dv_inG[dv_form[.f, .m]] = 1
                .ok = 0
            endif
        endfor
        if .ok = 1
            .nL = .nL + 1
            dv_L[.nL] = .f
        endif
    endfor
    dv_nSol = 0
    dv_nSet = 0
    for .i from 1 to .nL - 2
        for .j from .i + 1 to .nL - 1
            @formsDisjoint: dv_L[.i], dv_L[.j]
            if formsDisjoint.res = 1
                for .k from .j + 1 to .nL
                    @formsDisjoint: dv_L[.i], dv_L[.k]
                    .d1 = formsDisjoint.res
                    @formsDisjoint: dv_L[.j], dv_L[.k]
                    if .d1 = 1 and formsDisjoint.res = 1
                        dv_nSol = dv_nSol + 1
                        dv_sol[dv_nSol, 1] = dv_L[.i]
                        dv_sol[dv_nSol, 2] = dv_L[.j]
                        dv_sol[dv_nSol, 3] = dv_L[.k]
                        .ma = dv_mask[dv_L[.i]]
                        .mb = dv_mask[dv_L[.j]]
                        .mc = dv_mask[dv_L[.k]]
                        .sig$ = string$(min(.ma, .mb, .mc)) + "-" + string$(max(.ma, .mb, .mc))
                        .new = 1
                        for .q from 1 to dv_nSet
                            if dv_sig$[.q] = .sig$
                                .new = 0
                            endif
                        endfor
                        if .new = 1
                            dv_nSet = dv_nSet + 1
                            dv_sig$[dv_nSet] = .sig$
                        endif
                    endif
                endfor
            endif
        endfor
    endfor
    dervNSol[.gi] = dv_nSol
    dervNSet[.gi] = dv_nSet
    if dv_nSol > 0
        .pick = 1
        if derive_random
            .pick = randomInteger(1, dv_nSol)
        endif
        for .s from 1 to 3
            .ord[.s] = .s
        endfor
        if derive_random
            for .s from 1 to 2
                .r = randomInteger(.s, 3)
                .tmp = .ord[.s]
                .ord[.s] = .ord[.r]
                .ord[.r] = .tmp
            endfor
        endif
        dervPick[.gi] = .pick
        for .s from 1 to 3
            dervOrd[.gi, .s] = .ord[.s]
        endfor
        for .s from 1 to dv_nSol
            for .t from 1 to 3
                .f = dv_sol[.s, .t]
                for .m from 1 to 3
                    dvAll[.gi, .s, .t, .m] = dv_form[.f, .m]
                endfor
                dvAllLab$[.gi, .s, .t] = if .f <= 12 then "T" + string$(.f - 1) else "I" + string$(.f - 13) fi
            endfor
        endfor
        for .m from 1 to 3
            dervPc[.gi, 1, .m] = segPc[.gi, .m]
        endfor
        dervLab$[.gi, 1] = "T0"
        for .s from 1 to 3
            .f = dv_sol[.pick, .ord[.s]]
            for .m from 1 to 3
                dervPc[.gi, .s + 1, .m] = dv_form[.f, .m]
            endfor
            if .f <= 12
                dervLab$[.gi, .s + 1] = "T" + string$(.f - 1)
            else
                dervLab$[.gi, .s + 1] = "I" + string$(.f - 13)
            endif
        endfor
    endif
endproc

procedure aggArray: .j, .arr, .half
    for .v from 1 to 4
        for .m from 1 to 3
            aggPc[.j, .v, .m] = arrLine[.arr, .v, 3 * (.half - 1) + .m]
        endfor
        aggLab$[.j, .v] = arrLab$[.arr, .v]
    endfor
    aggGen[.j] = 0
    aggGenIdx[.j] = 0
    aggArr[.j] = .arr
    aggHalf[.j] = .half
    if .arr = 1
        aggSrcShort$[.j] = "P" + string$(.half)
        aggSrc$[.j] = "basic array, trichords " + string$(.half)
    else
        aggSrcShort$[.j] = "Sec" + string$(.half)
        aggSrc$[.j] = "secondary array (" + sec_op$ + "), trichords " + string$(.half)
    endif
endproc

procedure formLabel
    .lab$ = "?"
    for .n from 0 to 11
        .t = 1
        .i = 1
        .rt = 1
        .ri = 1
        for .k from 1 to 6
            if fl_line[.k] <> (pP[.k] + .n) mod 12
                .t = 0
            endif
            if fl_line[.k] <> ((.n - pP[.k]) mod 12 + 12) mod 12
                .i = 0
            endif
            if fl_line[.k] <> (pP[7 - .k] + .n) mod 12
                .rt = 0
            endif
            if fl_line[.k] <> ((.n - pP[7 - .k]) mod 12 + 12) mod 12
                .ri = 0
            endif
        endfor
        if .t = 1
            .lab$ = if .n = 0 then "P" else "T" + string$(.n) fi
        elsif .i = 1
            .lab$ = "I" + string$(.n)
        elsif .rt = 1
            .lab$ = if .n = 0 then "R" else "RT" + string$(.n) fi
        elsif .ri = 1
            .lab$ = "RI" + string$(.n)
        endif
    endfor
endproc

# Hybrid second aggregate: search the generator's partitions (the one picked
# by derive first) and the 24 voice assignments (generator on S first, v0.4's
# assignment first of all) for one in which no voice repeats a pc of its own
# trichord in the hybrid's first aggregate .jPrev.
procedure hybridDerived: .j, .jPrev, .gi
    hyb_ok = 0
    .nS = dervNSol[.gi]
    for .si from 0 to .nS
        if .si = 0
            .s = dervPick[.gi]
        else
            .s = .si
        endif
        .skip = .si > 0 and .si = dervPick[.gi]
        if hyb_ok = 0 and .skip = 0
            for .m from 1 to 3
                .tr[1, .m] = segPc[.gi, .m]
            endfor
            .trLab$[1] = "T0"
            for .t from 1 to 3
                .src = if .si = 0 then dervOrd[.gi, .t] else .t fi
                for .m from 1 to 3
                    .tr[.t + 1, .m] = dvAll[.gi, .s, .src, .m]
                endfor
                .trLab$[.t + 1] = dvAllLab$[.gi, .s, .src]
            endfor
            for .pass from 1 to 2
                for .pi from 1 to n_perm
                    .onS = permL[.pi, 1] = 1
                    .use = (.pass = 1 and .onS) or (.pass = 2 and .onS = 0)
                    if hyb_ok = 0 and .use
                        .good = 1
                        for .v from 1 to 4
                            for .m from 1 to 3
                                for .mm from 1 to 3
                                    if .tr[permL[.pi, .v], .m] = aggPc[.jPrev, .v, .mm]
                                        .good = 0
                                    endif
                                endfor
                            endfor
                        endfor
                        if .good
                            hyb_ok = 1
                            for .v from 1 to 4
                                for .m from 1 to 3
                                    aggPc[.j, .v, .m] = .tr[permL[.pi, .v], .m]
                                endfor
                                aggLab$[.j, .v] = .trLab$[permL[.pi, .v]]
                            endfor
                            if .si = 0 and .pi = 1
                                hyb_kept = hyb_kept + 1
                                hyb_note$ = hyb_note$ + "agg " + string$(.j) + " kept; "
                            else
                                hyb_changed = hyb_changed + 1
                                hyb_note$ = hyb_note$ + "agg " + string$(.j) + " reassigned (partition " + string$(.s) + ", voices " + string$(permL[.pi, 1]) + string$(permL[.pi, 2]) + string$(permL[.pi, 3]) + string$(permL[.pi, 4]) + "); "
                            endif
                        endif
                    endif
                endfor
            endfor
        endif
    endfor
    aggGen[.j] = segCode[.gi]
    aggGenIdx[.j] = .gi
    aggArr[.j] = 0
    aggHalf[.j] = 0
    aggSrcShort$[.j] = "0" + string$(segCode[.gi])
    aggSrc$[.j] = "derived from 0" + string$(segCode[.gi]) + " (segment " + string$(.gi) + ", hybrid join)"
endproc

procedure aggDerived: .j, .gi, .even
    for .v from 1 to 4
        if .even = 0
            for .m from 1 to 3
                aggPc[.j, .v, .m] = dervPc[.gi, .v, .m]
            endfor
            aggLab$[.j, .v] = dervLab$[.gi, .v]
        else
            .sv = dmap[.v]
            for .m from 1 to 3
                aggPc[.j, .v, .m] = dervPc[.gi, .sv, 4 - .m]
            endfor
            aggLab$[.j, .v] = "R" + dervLab$[.gi, .sv]
        endif
    endfor
    aggGen[.j] = segCode[.gi]
    aggGenIdx[.j] = .gi
    aggArr[.j] = 0
    aggHalf[.j] = 0
    if .even = 0
        aggSrcShort$[.j] = "0" + string$(segCode[.gi])
    else
        aggSrcShort$[.j] = "R 0" + string$(segCode[.gi])
    endif
    aggSrc$[.j] = "derived from 0" + string$(segCode[.gi]) + " (segment " + string$(.gi) + ")"
endproc

# ==============================================================================
# Procedure: result metrics from the event table
# ==============================================================================
procedure resultMetrics
    m_density = n_att / master_duration
    .step = 0.125
    .nG = floor(max_end_beat / .step)
    .poly = 0
    .ge3 = 0
    .silent = 0
    .cross = 0
    .multi = 0
    .lo = 1
    for .g from 0 to .nG - 1
        .tg = .g * .step
        for .v from 1 to 4
            mx_snd[.v] = -1
        endfor
        while .lo < n_att and atkBeat[.lo] < .tg - 4
            .lo = .lo + 1
        endwhile
        .a = .lo
        .go = 1
        while .go = 1
            if .a > n_att
                .go = 0
            elsif atkBeat[.a] > .tg
                .go = 0
            else
                if .tg < atkBeat[.a] + atkEffB[.a]
                    mx_snd[atkVoice[.a]] = atkMidi[.a]
                endif
                .a = .a + 1
            endif
        endwhile
        .n = 0
        for .v from 1 to 4
            if mx_snd[.v] >= 0
                .n = .n + 1
            endif
        endfor
        .poly = .poly + .n
        if .n >= 3
            .ge3 = .ge3 + 1
        endif
        if .n = 0
            .silent = .silent + 1
        endif
        if .n >= 2
            .multi = .multi + 1
            .cr = 0
            for .v from 1 to 3
                for .w from .v + 1 to 4
                    if mx_snd[.v] >= 0 and mx_snd[.w] >= 0
                        if mx_snd[.v] < mx_snd[.w]
                            .cr = 1
                        endif
                    endif
                endfor
            endfor
            .cross = .cross + .cr
        endif
    endfor
    m_poly = .poly / max(.nG, 1)
    m_ge3 = 100 * .ge3 / max(.nG, 1)
    m_silent = 100 * .silent / max(.nG, 1)
    m_cross = 100 * .cross / max(.multi, 1)
    .sum = 0
    .sum2 = 0
    for .a from 1 to n_att
        .sum = .sum + atkMidi[.a]
        .sum2 = .sum2 + atkMidi[.a] ^ 2
    endfor
    m_midi_mean = .sum / n_att
    m_midi_sd = sqrt(max(0, .sum2 / n_att - m_midi_mean ^ 2))
    m_db_min = 1e9
    m_db_max = -1e9
    for .d from 0 to 5
        mx_dynUsed[.d] = 0
    endfor
    for .q from 0 to 5
        m_art[.q] = 0
    endfor
    for .a from 1 to n_att
        m_db_min = min(m_db_min, atkDb[.a])
        m_db_max = max(m_db_max, atkDb[.a])
        mx_dynUsed[atkDyn[.a]] = 1
        m_art[atkArt[.a]] = m_art[atkArt[.a]] + 1
    endfor
    m_marks = 0
    for .d from 0 to 5
        m_marks = m_marks + mx_dynUsed[.d]
    endfor
    for .q from 1 to 16
        mx_ioi[.q] = 0
    endfor
    .nI = 0
    for .a from 1 to n_att
        .b = .a + 1
        .nx = 0
        while .nx = 0 and .b <= n_att
            if atkVoice[.b] = atkVoice[.a]
                .nx = .b
            endif
            .b = .b + 1
        endwhile
        if .nx > 0
            .q = min(16, round((atkBeat[.nx] - atkBeat[.a]) * 4))
            mx_ioi[.q] = mx_ioi[.q] + 1
            .nI = .nI + 1
        endif
    endfor
    m_ioi_h = 0
    m_ioi_n = 0
    for .q from 1 to 16
        if mx_ioi[.q] > 0
            .p = mx_ioi[.q] / .nI
            m_ioi_h = m_ioi_h - .p * log2(.p)
            m_ioi_n = m_ioi_n + 1
        endif
    endfor
    m_clus = 0
    m_ov = 0
    m_stag = 0
    for .j from 1 to n_agg
        m_clus = m_clus + blkClus[.j] / n_agg
        m_ov = m_ov + blkOv[.j] / n_agg
        m_stag = m_stag + blkStag[.j] / n_agg
    endfor
endproc

# ==============================================================================
# Procedure: render one event into a scratch Sound and add it to the master
# ==============================================================================
procedure renderEvent: .a
    .v = atkVoice[.a]
    .blk = atkBlk[.a]
    .k = atkCyc[.a]
    .f0 = atkF[.a]
    .t0 = atkBeat[.a] * beat
    .dur = atkSoundB[.a] * beat
    .t1 = .t0 + .dur
    .relMax = if atkArt[.a] = 1 then 0.08 else 0.015 fi
    .rel = min(.relMax, 0.3 * .dur)
    .relS = .t1 - .rel
    .tauE = tau * atkTauM[.a]
    .t0$ = fixed$(.t0, 6)
    .u$ = "(x-" + .t0$ + ")"
    .sumW = 0
    .harm$ = ""
    .fund$ = ""
    .grp = if .v = 1 or .v = 3 then 1 else 2 fi
    if spec_groups = 2
        .grp = 2 - inHexP[atkPc[.a]]
    endif
    if timbre = 6
        @complementarySpectrum: .a
    elsif timbre = 7
        # harmonic core: tilt from the interval-class content of the trichord
        @trichordClass: aggPc[.blk, .v, 1], aggPc[.blk, .v, 2], aggPc[.blk, .v, 3]
        .tc = trichordClass.code
        .lo = floor(.tc / 10)
        .mi = (.tc mod 10) - .lo
        .hi = 12 - .lo - .mi
        .rho = 0
        @icWeight: .lo
        .rho = .rho + icWeight.w
        @icWeight: .mi
        .rho = .rho + icWeight.w
        @icWeight: .hi
        .rho = .rho + icWeight.w
        .rho = min(1, .rho / 6)
        .beta = 1.6 - 0.9 * .rho
        for .h from 1 to 6
            .wh = 1 / .h ^ .beta
            .rate = (1 + 0.15 * (.h - 1)) / .tauE
            @addPartial: .h * .f0, .wh, "exp(-" + fixed$(.rate, 5) + "*" + .u$ + ")"
        endfor
        # trichord partials: intervals to the other two members
        .sig = cycSig[.k]
        .kap = atkKap[.a]
        for .m from 1 to 3
            .y = aggPc[.blk, .v, .m]
            if .y <> atkPc[.a]
                .iv = ((.y - atkPc[.a]) mod 12 + 12) mod 12
                .r = 2 ^ (1 + .iv / 12)
                .r = .r + .kap * (round(.r) - .r)
                if atkIsR[.a]
                    .env$ = "(1-exp(-" + .u$ + "/" + fixed$(0.25 * .tauE, 5) + "))*exp(-" + fixed$(0.5 / .tauE, 5) + "*" + .u$ + ")"
                else
                    .env$ = "exp(-" + fixed$(1.4 / .tauE, 5) + "*" + .u$ + ")"
                endif
                @addPartial: .r * .f0, 0.5 * .sig, .env$
                @addPartial: 2 * .r * .f0, 0.25 * .sig, .env$
            endif
        endfor
        # aggregate halo on the entry that completes the aggregate
        if atkComplete[.a] and isRe[.a] = 0
            for .y from 0 to 11
                if .y <> atkPc[.a]
                    .iv = ((.y - atkPc[.a]) mod 12 + 12) mod 12
                    @addPartial: 2 ^ (2 + .iv / 12) * .f0, 0.05 * .sig + 0.02, "(1-exp(-" + .u$ + "/0.15))*exp(-" + fixed$(1 / (1.5 * .tauE), 5) + "*" + .u$ + ")"
                endif
            endfor
        endif
    else
        for .h from 1 to n_h
            if timbre = 5
                .wh = stw[.k, .v, .h]
            else
                .wh = w[.v, .h]
            endif
            if .wh > 0
                if timbre = 4
                    .env$ = "exp(-" + fixed$(.h / .tauE, 5) + "*" + .u$ + ")"
                elsif timbre = 5
                    .env$ = "exp(-" + fixed$((1 + 0.12 * (.h - 1)) / .tauE, 5) + "*" + .u$ + ")"
                else
                    .env$ = "1"
                endif
                @addPartial: .h * .f0, .wh, .env$
            endif
        endfor
    endif
    if rp_analyze = 0
    .amp = 0.22 * 10 ^ (atkDb[.a] / 20) / max(.sumW, 1e-9)
    .relf$ = "(if x > " + fixed$(.relS, 6) + " then 0.5+0.5*cos(pi*(x-" + fixed$(.relS, 6) + ")/" + fixed$(.rel, 6) + ") else 1 fi)"
    if timbre = 4 or timbre >= 5
        .env$ = "min(1," + .u$ + "/" + fixed$(atkAtt[.a], 5) + ")*" + .relf$
    else
        .env$ = "min(1," + .u$ + "/" + fixed$(atkAtt[.a], 5) + ")*exp(-" + .u$ + "/" + fixed$(.tauE, 5) + ")*" + .relf$
    endif
    .formula$ = "if x < " + .t0$ + " or x > " + fixed$(.t1, 6) + " then 0 else " + fixed$(.amp, 7) + "*" + .env$ + "*(0" + .harm$ + ") fi"
    @mixScratch: .t0, .t1, .formula$, atkPan[.a], .grp
    if .fund$ <> ""
        .formulaF$ = "if x < " + .t0$ + " or x > " + fixed$(.t1, 6) + " then 0 else " + fixed$(.amp, 7) + "*" + .env$ + "*(0" + .fund$ + ") fi"
        @mixScratch: .t0, .t1, .formulaF$, 0, .grp + 2
    endif

    # Trichord halo: when a line completes its trichord in this aggregate.
    if trichord_halo and isRe[.a] = 0 and atkIdx[.a] = 3
        n_halo = n_halo + 1
        haloVoice[n_halo] = .v
        haloBeat[n_halo] = atkBeat[.a]
        haloMidi[n_halo] = atkMidi[.a]
        .hdur = min(1.5 * beat, master_duration - .t0 - 0.001)
        haloDurBeat[n_halo] = .hdur / beat
        .chord$ = ""
        for .kk from 1 to 3
            if voice_range_protection and (blkVMidi[.blk, .v, .kk] < vLo[.v] or blkVMidi[.blk, .v, .kk] > vHi[.v])
                halo_out = halo_out + 1
            endif
            .hf = 440 * 2 ^ ((blkVMidi[.blk, .v, .kk] - 69) / 12)
            .chord$ = .chord$ + "+sin(" + fixed$(2 * pi * .hf, 6) + "*" + .u$ + ")"
        endfor
        .hf$ = "if x < " + .t0$ + " or x > " + fixed$(.t0 + .hdur, 6) + " then 0 else " + fixed$(0.07 * 10 ^ (atkDb[.a] / 20), 6) + "*sin(pi*" + .u$ + "/" + fixed$(.hdur, 6) + ")^2*(0" + .chord$ + ") fi"
        @mixScratch: .t0, .t0 + .hdur, .hf$, atkPan[.a], .grp
    endif
    endif
endproc

# Appends one partial to the sum being built by renderEvent (writes the
# renderEvent.sumW and renderEvent.harm$ variables directly).
procedure addPartial: .f, .wgt, .env$
    if rp_analyze = 1
        if .wgt > 0 and .f < 0.45 * sample_rate
            rp_wf = rp_wf + .wgt * .f
            rp_w = rp_w + .wgt
        endif
    elsif .wgt > 0
        if .f < 0.45 * sample_rate
            renderEvent.sumW = renderEvent.sumW + .wgt
            max_partial = max(max_partial, .f)
            n_partials_total = n_partials_total + 1
            .term$ = "+" + fixed$(.wgt, 5) + "*" + .env$ + "*sin(" + fixed$(2 * pi * .f, 6) + "*" + renderEvent.u$ + ")"
            renderEvent.harm$ = renderEvent.harm$ + .term$
            if renderEvent.fund$ = "" and abs(.f - renderEvent.f0) < 1e-6 * .f
                renderEvent.fund$ = .term$
            endif
        else
            dropped_partials = dropped_partials + 1
        endif
    endif
endproc

procedure icWeight: .iv
    .ic = min(.iv, 12 - .iv)
    if .ic = 1
        .w = 2.0
    elsif .ic = 2
        .w = 1.2
    elsif .ic = 3
        .w = 0.3
    elsif .ic = 4
        .w = 0.2
    elsif .ic = 5
        .w = 0.1
    else
        .w = 0.8
    endif
endproc

# Render a formula once into a scratch Sound on the master's sample grid,
# then add it into the master with equal-power pan gains (index access,
# no interpolation).
procedure mixScratch: .t0, .t1, .formula$, .pan, .grp
    .n0 = max(0, floor(.t0 * sample_rate))
    .nS = min(n_master_samples - .n0, ceiling((.t1 - .n0 / sample_rate) * sample_rate) + 1)
    if .nS >= 1 and .grp >= 3
        .xs = .n0 / sample_rate
        .xe = (.n0 + .nS) / sample_rate
        .sid = Create Sound from formula: "babbitt_fund_tmp", 1, .xs, .xe, sample_rate, .formula$
        .idx$ = "object[" + string$(.sid) + ", 1, col - " + string$(.n0) + "]"
        .guard$ = "col > " + string$(.n0) + " and col <= " + string$(.n0 + .nS)
        selectObject: if .grp = 3 then fundH_id else fundC_id fi
        Formula (part): .xs, .xe, 1, 1, "if " + .guard$ + " then self + " + .idx$ + " else self fi"
        removeObject: .sid
    elsif .nS >= 1
        .xs = .n0 / sample_rate
        .xe = (.n0 + .nS) / sample_rate
        .sid = Create Sound from formula: "babbitt_note_tmp", 1, .xs, .xe, sample_rate, .formula$
        selectObject: master_id
        .idx$ = "object[" + string$(.sid) + ", 1, col - " + string$(.n0) + "]"
        .guard$ = "col > " + string$(.n0) + " and col <= " + string$(.n0 + .nS)
        if nch = 2
            .gL = cos((.pan + 1) * pi / 4)
            .gR = sin((.pan + 1) * pi / 4)
            Formula (part): .xs, .xe, 1, 2, "if " + .guard$ + " then self + (if row = 1 then " + fixed$(.gL, 6) + " else " + fixed$(.gR, 6) + " fi) * " + .idx$ + " else self fi"
        else
            Formula (part): .xs, .xe, 1, 1, "if " + .guard$ + " then self + " + .idx$ + " else self fi"
        endif
        # analysis stems: hexachord P (grp 1) and its complement (grp 2)
        selectObject: if .grp = 1 then stemH_id else stemC_id fi
        Formula (part): .xs, .xe, 1, 1, "if " + .guard$ + " then self + " + .idx$ + " else self fi"
        removeObject: .sid
    endif
endproc

procedure buildRegMap: .kc
    k = .kc
    if cycReg[k] = 4
        any_struct_reg = 1
        for c from 0 to 11
            regAsg[c] = 0
        endfor
        nl = 0
        for m from 1 to 3
            nl = nl + 1
            rl[nl] = aggPc[2 * k - 1, 1, m]
        endfor
        for m from 1 to 3
            nl = nl + 1
            rl[nl] = aggPc[2 * k, 1, m]
        endfor
        for c from 0 to 11
            nl = nl + 1
            rl[nl] = c
        endfor
        side = if (k mod 2) = 1 then 1 else -1 fi
        dmax = (1.2 * register_spread + 6) * cycSpreadF[k]
        dstep = (dmax - 1.5) / 5
        rank = 0
        for i from 1 to nl
            xpc = rl[i]
            if regAsg[xpc] = 0
                rank = rank + 1
                dTarget = 1.5 + (min(rank, 6) - 1) * dstep
                sgn = side * (if (rank mod 2) = 1 then 1 else -1 fi)
                base = (xpc - ax_c0) - 12 * floor((xpc - ax_c0) / 12)
                dsel = base + 12 * round((sgn * dTarget - base) / 12)
                regMap[k, xpc] = round(ax_c0 + dsel)
                regAsg[xpc] = 1
                y = ((ax_n - xpc) mod 12 + 12) mod 12
                if regAsg[y] = 0
                    regMap[k, y] = round(2 * ax_c0 - regMap[k, xpc])
                    regAsg[y] = 1
                endif
            endif
        endfor
        for c from 0 to 11
            while regMap[k, c] < 21
                regMap[k, c] = regMap[k, c] + 12
            endwhile
            while regMap[k, c] > 108
                regMap[k, c] = regMap[k, c] - 12
            endwhile
        endfor
        for c from 0 to 11
            y = ((ax_n - c) mod 12 + 12) mod 12
            if y > c
                reg_sym_pairs = reg_sym_pairs + 1
                if abs(regMap[k, c] + regMap[k, y] - 2 * ax_c0) < 0.01
                    reg_sym_ok = reg_sym_ok + 1
                endif
            endif
        endfor
    endif
endproc

procedure realizeEvent: .a
    a = .a
    v = atkVoice[a]
    blk = atkBlk[a]
    k = atkCyc[a]
    pc = atkPc[a]
    lab$ = aggLab$[blk, v]
    atkLab$[a] = lab$
    isR = left$(lab$, 1) = "R"
    isI = index(lab$, "I") > 0
    atkIsR[a] = isR
    if aggHalf[blk] > 0
        lpos = 3 * (aggHalf[blk] - 1) + atkIdx[a]
        lnn = 6
    else
        lpos = atkIdx[a]
        lnn = 3
    endif
    atkLinePos[a] = lpos
    # register (rearticulations repeat their source pitch)
    if isRe[a] = 1
        midv = atkMidi[atkSrc[a]]
        if texture = 2
            midv = midv + atkOct[a]
            if voice_range_protection
                # octave displacement: the other octave, else no displacement
                if midv < vLo[v] or midv > vHi[v]
                    midv = atkMidi[atkSrc[a]] - atkOct[a]
                    if midv < vLo[v] or midv > vHi[v]
                        midv = atkMidi[atkSrc[a]]
                        if atkOct[a] <> 0
                            rng_re_supp = rng_re_supp + 1
                        endif
                    endif
                endif
            elsif midv < 21 or midv > 108
                midv = atkMidi[atkSrc[a]] - atkOct[a]
            endif
        endif
        if voice_range_protection
            @voiceFit: v, midv, vPrev[v]
            if voiceFit.moved
                rng_re_fit = rng_re_fit + 1
                rng_moved_v[v] = rng_moved_v[v] + 1
            endif
            midv = voiceFit.out
        endif
        atkMidi[a] = midv
    else
        strat = cycReg[k]
        if strat = 2
            ordn = if isR then lnn + 1 - lpos else lpos fi
            dirn = if isI then -1 else 1 fi
            tgt = vc[v] + dirn * ((ordn - 1) / (lnn - 1) - 0.5) * 1.8 * register_spread * cycSpreadF[k]
            midv = pc + 12 * round((tgt - pc) / 12)
        elsif strat = 3
            vb = ((v - 1 + blk - 1) mod 4) + 1
            midv = pc + 12 * round((vc[vb] - pc) / 12)
        elsif strat = 4
            midv = regMap[k, pc]
        else
            midv = pc + 12 * round((vc[v] - pc) / 12)
        endif
        if voice_range_protection
            # SATB range protection: octave placement only (pitch class kept)
            @voiceFit: v, midv, vPrev[v]
            if voiceFit.moved
                rng_moved = rng_moved + 1
                rng_moved_v[v] = rng_moved_v[v] + 1
                if strat = 4
                    rng_axis_moved = rng_axis_moved + 1
                endif
            endif
            midv = voiceFit.out
        else
            while midv < 21
                midv = midv + 12
                reg_clamped = reg_clamped + 1
            endwhile
            while midv > 108
                midv = midv - 12
                reg_clamped = reg_clamped + 1
            endwhile
        endif
        atkMidi[a] = midv
        blkVMidi[blk, v, atkIdx[a]] = midv
    endif
    vPrev[v] = atkMidi[a]
    atkF[a] = 440 * 2 ^ ((atkMidi[a] - 69) / 12)
    min_midi = min(min_midi, atkMidi[a])
    max_midi = max(max_midi, atkMidi[a])
    # written value: time to the next attack of the same voice, max 2 beats
    b = a + 1
    nxt = 0
    while nxt = 0 and b <= n_att
        if atkVoice[b] = v
            nxt = b
        endif
        b = b + 1
    endwhile
    if nxt > 0
        atkWritB[a] = min(atkBeat[nxt] - atkBeat[a], 2)
    elsif texture = 2 and k < n_cyc
        atkWritB[a] = min(2, 16 * k - atkBeat[a])
    else
        atkWritB[a] = 1.5
    endif
    atkWrit16[a] = round(atkWritB[a] * 4)
    # articulation
    if articulation = 1
        art = 0
        acc = 0
    else
        art = atkCard[a] + 1 + cycArt[k]
        if isRe[a] = 1
            art = if cycArt[k] < 0 then 4 else 5 fi
        endif
        if art < 2
            art = 2
        endif
        if art > 5
            art = 5
        endif
        if atkComplete[a] and art > 3
            art = 3
        endif
        if isRe[a] = 0 and cycArt[k] < 0 and (atkIdx[a] = 3 or atkComplete[a])
            art = 1
        endif
        acc = atkComplete[a] or (atkIdx[a] = 1 and atkPos[a] = 0 and isRe[a] = 0 and (cycRole[k] = 1 or cycRole[k] = 2))
    endif
    atkArt[a] = art
    atkAcc[a] = acc
    wB = atkWritB[a]
    if art = 1
        snd = min(max(wB * 1.8, 1.0), 3.5)
        atkAtt[a] = 0.005
        atkTauM[a] = 2.2
    elsif art = 2
        snd = wB + 0.06
        atkAtt[a] = 0.012
        atkTauM[a] = 1.3
    elsif art = 3
        snd = 0.9 * wB
        atkAtt[a] = 0.008
        atkTauM[a] = 1.0
    elsif art = 4
        snd = 0.6 * wB
        atkAtt[a] = 0.005
        atkTauM[a] = 0.7
    elsif art = 5
        snd = min(0.4 * wB, 0.2)
        atkAtt[a] = 0.0025
        atkTauM[a] = 0.45
    else
        snd = wB
        atkAtt[a] = if timbre = 4 then 0.003 else 0.006 fi
        atkTauM[a] = 1
    endif
    if acc
        atkAtt[a] = 0.002
    endif
    # genuine monody (relay): legato, and every note lasts exactly until the
    # next attack of any voice, so one voice sounds at a time without gaps
    if texture = 2 and blkMode[blk] = 2
        b = a + 1
        nxa = 0
        while nxa = 0 and b <= n_att
            if atkBeat[b] > atkBeat[a]
                nxa = b
            endif
            b = b + 1
        endwhile
        art = 2
        atkArt[a] = 2
        atkAtt[a] = if acc then 0.002 else 0.012 fi
        atkTauM[a] = 1.3
        if nxa > 0
            snd = atkBeat[nxa] - atkBeat[a]
            # the decay must stay above -30 dB until the next attack
            atkTauM[a] = max(1.3, snd * beat / (3.45 * tau) * 1.02)
        endif
    endif
    atkSoundB[a] = snd
    # audible length: until the fundamental has decayed by 30 dB (3.45 time constants)
    atkEffB[a] = min(snd, 3.45 * tau * atkTauM[a] / beat)
    if atkBeat[a] + snd > max_end_beat
        max_end_beat = atkBeat[a] + snd
    endif
    # dynamics
    formDb = 0
    if isR and isI
        formDb = 3
    elsif isI
        formDb = -3
    elsif isR
        formDb = -6
    endif
    if dynamics = 1
        accf = 1
        if rearticulation > 1 and atkPos[a] = 0
            accf = 1.15
        endif
        if isRe[a] = 1
            accf = 0.8
        endif
        db = 20 * log10(accf * (if v = 4 then 1.1 else if v = 1 then 0.9 else 1 fi fi))
    else
        ei = atkEntry[a]
        arcv = 5 * (ei - 1) / 11 - 2.5
        prof = cycDyn[k]
        if prof = 1
            db = formDb + arcv
        elsif prof = 2
            db = 0.5 * formDb + (if v = blkLead[blk] then 5 else -5 fi)
        elsif prof = 3
            db = 0.5 * formDb + 0.5 * arcv - 3
        elsif prof = 4
            db = formDb - 4 * (ei - 1) / 11
        else
            db = 1.6 * formDb + 0.5 * arcv
        endif
        if atkComplete[a]
            db = db + (if prof = 4 then 8 else 4 fi)
        endif
        if acc
            db = db + 3
        endif
        if isRe[a] = 1
            db = atkDb[atkSrc[a]] - 6
        endif
        db = min(12, max(-24, db))
    endif
    atkDb[a] = db
    atkDyn[a] = min(5, max(0, round(db / 6) + 3))
    # space
    if nch = 1
        pan = 0
    else
        sp = cycSpace[k]
        if sp = 2
            pan = (if inHexP[pc] then -1 else 1 fi) * (0.35 + 0.15 * (v - 1))
        elsif sp = 3
            pan = 0.85 * sin(2 * pi * (pc - ax_c0) / 12)
        elsif sp = 4
            pan = panEx[v] * (if (blk mod 2) = 0 then -1 else 1 fi)
        elsif sp = 5
            phase = (atkBeat[a] - 16 * (k - 1)) / 16
            pan = panCr[v] * (1 - 2 * phase)
        else
            pan = panFix[v]
        endif
        pan = pan * cycWidth[k]
    endif
    atkPan[a] = pan
    # harmonic pull for the spectral model
    kp = cycKap[k]
    if kp < 0
        frac = (atkEntry[a] - 1) / 11
        kp = if (blk mod 2) = 1 then frac else 1 - frac fi
    endif
    atkKap[a] = kp
endproc

# ==============================================================================
# Procedures: form engine (v0.5)
# ==============================================================================
procedure setProto: .r, .poly, .sim, .dens, .dur, .hmax
    protoPoly[.r] = .poly
    protoSim[.r] = .sim
    protoDens[.r] = .dens
    protoDur[.r] = .dur
    roleHmax[.r] = .hmax
endproc

procedure cycleStrategies: .k
    .r = cycRole[.k]
    cycDev[.k] = if n_cyc > 1 then (.k - 1) / (n_cyc - 1) else 0 fi
    .morph = form_plan = 5
    cycReg[.k] = if register_strategy = 5 then roleReg[.r] else register_strategy fi
    cycSpace[.k] = if space = 6 then roleSpace[.r] else space fi
    cycArt[.k] = roleArt[.r]
    cycDyn[.k] = roleDyn[.r]
    if texture = 2 and .r = 2
        cycDyn[.k] = 1
    endif
    cycSig[.k] = roleSig[.r] * (if .morph then 0.6 + 0.4 * cycDev[.k] else 1 fi)
    cycKap[.k] = roleKap[.r]
    cycPol[.k] = if realization = 2 then rolePol[.r] else 0 fi
    cycWidth[.k] = if .morph then 0.55 + 0.45 * cycDev[.k] else 1 fi
    cycSpreadF[.k] = if .morph then 0.7 + 0.6 * cycDev[.k] else 1 fi
    cycHmax[.k] = roleHmax[.r]
endproc

# Structural affinity of a role for a cycle (Morphogenesis reads the array).
procedure roleAffinity: .k, .c
    .a = 0
    if form_plan = 3 and .c = 4
        .a = 0.6
    elsif form_plan = 4 and .c = 5
        .a = 0.4
    elsif form_plan = 5
        .want = 0
        if cycKind$[.k] = "secondary"
            .want = 2
        elsif cycKind$[.k] <> "basic"
            if .k - 1 - secondary_sets = 1
                .want = 5
            elsif cycGen[.k] = 12 or cycGen[.k] = 13
                .want = 3
            elsif cycGen[.k] = 24 or cycGen[.k] = 25 or cycGen[.k] = 26 or cycGen[.k] = 27
                .want = 6
            else
                .want = 4
            endif
        endif
        if .c = .want
            .a = 2.5
        endif
    endif
endproc

# ==============================================================================
# Procedures: form model v0.5.1 (independent voices)
#   Each new cycle stands in one of four relations to the previous one:
#     1 continue    same role; voices keep their gesture types
#     2 transform   same role; gesture types mapped (neighbour <-> echo,
#                   pedal <-> contour), imitation kept
#     3 develop     the neighbouring role on the texture axis
#                   monody - canon - withheld - revelation - spectral - density
#     4 contrast    the role farthest from what the previous cycle produced
#   Plans prescribe a novelty curve (Counterpoint: gradual development;
#   Spectral: continuity; Temporal: alternation), Morphogenesis follows the
#   role the array asks for and names the relation that reaches it. The
#   decision reads ONLY features of the previous cycle that exist when it is
#   taken: texture (sounding voices, simultaneity, onsets, audible length),
#   analytic brightness of the synthesis parameters, and gesture-shape
#   distance to the cycle before it.
# ==============================================================================
procedure formSetup
    axisPos[2] = 1
    axisPos[1] = 2
    axisPos[5] = 3
    axisPos[6] = 4
    axisPos[4] = 5
    axisPos[3] = 6
    axisRole[1] = 2
    axisRole[2] = 1
    axisRole[3] = 5
    axisRole[4] = 6
    axisRole[5] = 4
    axisRole[6] = 3
    relName$[0] = "opening"
    relName$[1] = "continue"
    relName$[2] = "transform"
    relName$[3] = "develop"
    relName$[4] = "contrast"
    # expected novelty of each relation (feature-distance units, calibrated)
    # (calibrated on measured runs: a new cycle always brings new pitches and
    # gestures, so even "continue" measures about 1.9)
    relNov[1] = 1.9
    relNov[2] = 2.1
    relNov[3] = 3.0
    relNov[4] = 4.2
    # novelty targets per plan, cycle 2..9
    for .k from 1 to 9
        novT[2, .k] = 3.0
        novT[3, .k] = if (.k mod 2) = 0 then 2.1 else 1.9 fi
        novT[4, .k] = if (.k mod 2) = 0 then 4.2 else 1.9 fi
        novT[5, .k] = 3.0
    endfor
    novT[2, 4] = 4.2
    novT[2, 5] = 2.1
    novT[2, 8] = 4.2
    novT[3, 4] = 3.0
    novT[3, 6] = 4.2
endproc

procedure structWant: .k
    .want = 0
    if cycKind$[.k] = "basic"
        .want = 1
    elsif cycKind$[.k] = "secondary"
        .want = 2
    elsif .k - 1 - secondary_sets = 1
        .want = 5
    elsif cycGen[.k] = 12 or cycGen[.k] = 13
        .want = 3
    elsif cycGen[.k] = 24 or cycGen[.k] = 25 or cycGen[.k] = 26 or cycGen[.k] = 27
        .want = 6
    else
        .want = 4
    endif
endproc

procedure chooseRole: .k
    cycRel[.k] = 0
    if realization = 1 or form_plan = 1
        .r = 1
        cycWhy$[.k] = "static"
    elsif .k = 1
        .r = planFirst[form_plan]
        cycWhy$[.k] = "plan opening"
    else
        .prev = cycRole[.k - 1]
        # features must exist now: the self-test checks this flag
        if cf_poly[.k - 1] = undefined or cf_bright[.k - 1] = undefined or cf_gest[.k - 1] = undefined
            form_feature_missing = form_feature_missing + 1
        endif
        if form_plan = 5
            @structWant: .k
            .w = structWant.want
            if .w = .prev
                .rel = if cf_nov[.k - 1] < relNov[2] then 2 else 1 fi
            elsif abs(axisPos[.w] - axisPos[.prev]) = 1
                .rel = 3
            else
                .rel = 4
            endif
            .r = .w
            if .rel = 4
                .r = .w
            endif
        else
            .tgt = novT[form_plan, .k]
            if .k > 2
                .tgt = .tgt + 0.5 * (novT[form_plan, .k - 1] - cf_nov[.k - 1])
            endif
            .best = 1e9
            .rel = 1
            for .c from 1 to 4
                .dd = abs(relNov[.c] - .tgt)
                if .dd < .best - 1e-9
                    .best = .dd
                    .rel = .c
                endif
            endfor
            # no role three times running
            if .rel <= 2 and .k > 2
                if cycRole[.k - 2] = .prev
                    .rel = 3
                endif
            endif
            if .rel <= 2
                .r = .prev
            elsif .rel = 3
                # step along the texture axis, turning at the ends and away
                # from roles the plan does not allow
                .dir = if (.k mod 2) = 0 then 1 else -1 fi
                .p = axisPos[.prev] + .dir
                if .p < 1 or .p > 6
                    .p = axisPos[.prev] - .dir
                endif
                .r = axisRole[.p]
                if planAllow[form_plan, .r] = 0
                    .p = axisPos[.prev] - .dir
                    if .p >= 1 and .p <= 6
                        .r = axisRole[.p]
                    endif
                    if planAllow[form_plan, .r] = 0
                        .rel = 4
                    endif
                endif
            endif
            if .rel = 4
                .bestS = -1e9
                .r = .prev
                for .c from 1 to 6
                    if planAllow[form_plan, .c] = 1 and .c <> .prev
                        .d = sqrt(((cf_poly[.k - 1] - protoPoly[.c]) / 1.0) ^ 2 + ((cf_sim[.k - 1] - protoSim[.c]) / 0.25) ^ 2 + ((cf_dens[.k - 1] - protoDens[.c]) / 0.75) ^ 2 + ((cf_dur[.k - 1] - protoDur[.c]) / 0.5) ^ 2)
                        .s = .d - 1.0 * roleUsed[.c]
                        if .s > .bestS
                            .bestS = .s
                            .r = .c
                        endif
                    endif
                endfor
            endif
        endif
        cycRel[.k] = .rel
        cycWhy$[.k] = relName$[.rel] + " (novelty in c" + string$(.k - 1) + " " + fixed$(cf_nov[.k - 1], 2) + ")"
    endif
    cycRole[.k] = .r
    roleUsed[.r] = roleUsed[.r] + 1
endproc

# Analytic brightness of cycle .k from the synthesis parameters
# (amplitude-weighted centroid / f0 of every event, in octaves).
procedure cycleBrightness: .k
    .sw = 0
    .sb = 0
    for .a from cycA0[.k] to cycA1[.k]
        rp_analyze = 1
        rp_wf = 0
        rp_w = 0
        @renderEvent: .a
        rp_analyze = 0
        if rp_w > 0
            .amp = 10 ^ (atkDb[.a] / 20)
            .sb = .sb + .amp * log2(max(rp_wf / rp_w, atkF[.a]) / atkF[.a])
            .sw = .sw + .amp
        endif
    endfor
    cf_bright[.k] = if .sw > 0 then .sb / .sw else 0 fi
endproc

# Gesture shapes of cycle .k (one per block-voice): step direction
# (-1 / 0 = repetition / +1), octave-or-more leap flag, IOI in sixteenths.
procedure gestureShapes: .k
    cycG0[.k] = n_gest + 1
    for .j from 2 * .k - 1 to 2 * .k
        for .v from 1 to 4
            n_gest = n_gest + 1
            gsCyc[n_gest] = .k
            gsBlk[n_gest] = .j
            gsVoice[n_gest] = .v
            gsN[n_gest] = 0
            .prevA = 0
            for .a from blkA0[.j] to blkA1[.j]
                if atkVoice[.a] = .v
                    if .prevA > 0
                        gsN[n_gest] = gsN[n_gest] + 1
                        .dm = atkMidi[.a] - atkMidi[.prevA]
                        gsD[n_gest, gsN[n_gest]] = if .dm > 0 then 1 else if .dm < 0 then -1 else 0 fi fi
                        gsO[n_gest, gsN[n_gest]] = abs(.dm) >= 12
                        gsI[n_gest, gsN[n_gest]] = max(1, round((atkBeat[.a] - atkBeat[.prevA]) * 4))
                    endif
                    .prevA = .a
                endif
            endfor
        endfor
    endfor
    cycG1[.k] = n_gest
    # shape distance to the previous cycle: mean over this cycle's gestures of
    # the nearest gesture of the previous cycle
    if .k > 1
        .sum = 0
        .n = 0
        for .g from cycG0[.k] to cycG1[.k]
            .best = 1e9
            for .h from cycG0[.k - 1] to cycG1[.k - 1]
                @shapeDTW: .g, .h
                .best = min(.best, shapeDTW.d)
            endfor
            .sum = .sum + .best
            .n = .n + 1
        endfor
        cf_gest[.k] = .sum / .n
    else
        cf_gest[.k] = 0
    endif
endproc

procedure shapeDTW: .g1, .g2
    .n = gsN[.g1]
    .m = gsN[.g2]
    if .n = 0 or .m = 0
        .d = if .n = 0 and .m = 0 then 0 else 1 fi
    else
        for .i from 0 to .n
            for .jj from 0 to .m
                .dd[.i, .jj] = 1e9
                .ll[.i, .jj] = 0
            endfor
        endfor
        .dd[0, 0] = 0
        for .i from 1 to .n
            for .jj from 1 to .m
                .c = abs(gsD[.g1, .i] - gsD[.g2, .jj]) / 2 + 0.5 * (gsO[.g1, .i] <> gsO[.g2, .jj]) + 0.5 * abs(log2(gsI[.g1, .i] / gsI[.g2, .jj]))
                .b = .dd[.i - 1, .jj - 1]
                .bl = .ll[.i - 1, .jj - 1]
                if .dd[.i - 1, .jj] < .b
                    .b = .dd[.i - 1, .jj]
                    .bl = .ll[.i - 1, .jj]
                endif
                if .dd[.i, .jj - 1] < .b
                    .b = .dd[.i, .jj - 1]
                    .bl = .ll[.i, .jj - 1]
                endif
                .dd[.i, .jj] = .b + .c
                .ll[.i, .jj] = .bl + 1
            endfor
        endfor
        .d = .dd[.n, .m] / .ll[.n, .m]
    endif
endproc

# Measured novelty of cycle .k relative to .k-1 (decision feature space).
procedure cycleNovelty: .k
    if .k = 1
        cf_nov[.k] = 0
    else
        cf_nov[.k] = sqrt(((cf_poly[.k] - cf_poly[.k - 1]) / 1.0) ^ 2 + ((cf_sim[.k] - cf_sim[.k - 1]) / 0.25) ^ 2 + ((cf_dens[.k] - cf_dens[.k - 1]) / 0.75) ^ 2 + ((cf_dur[.k] - cf_dur[.k - 1]) / 0.5) ^ 2 + ((cf_bright[.k] - cf_bright[.k - 1]) / 0.5) ^ 2 + (cf_gest[.k] / 0.3) ^ 2)
    endif
endproc

# Gesture diversity over the whole piece (reported, never an error):
# nearest-neighbour shape distance, share of near-duplicates (< 0.15),
# share of distinct entry/elaboration index patterns.
procedure gestureDiversity
    gd_nn = 0
    gd_dup = 0
    gd_cnt = 0
    for .g from 1 to n_gest
        if gsN[.g] > 0
            .best = 1e9
            for .h from 1 to n_gest
                if .h <> .g and gsN[.h] > 0
                    @shapeDTW: .g, .h
                    .best = min(.best, shapeDTW.d)
                endif
            endfor
            gd_nn = gd_nn + .best
            gd_dup = gd_dup + (.best < 0.15)
            gd_cnt = gd_cnt + 1
        endif
    endfor
    gd_nn = if gd_cnt > 0 then gd_nn / gd_cnt else undefined fi
    gd_dup = if gd_cnt > 0 then gd_dup / gd_cnt else undefined fi
endproc

# ==============================================================================
# Procedures: combinatorial gesture engine (v0.5.1, independent voices)
#   A gesture = one voice's attacks inside one aggregate window. The engine
#   decides (1) how many attacks (from the intervals of the voice's trichord),
#   (2) where the three entries fall among them (placement), and (3) which
#   already-stated pcs the elaborations restate, in which octave (type).
#   Inputs: the line form (P / R / I / RI), the trichord's intervals, the
#   partition cells under the attacks (rhythmic context), the voice's own
#   previous gesture (history), the gestures already chosen by the other
#   voices in this window (interaction), the canon leader (imitation) and the
#   cycle's form relation (continue / transform / develop / contrast).
#   Constraint kept: entries present the trichord in line order; an
#   elaboration may only restate a pc this voice has already stated in this
#   aggregate, so the order of first appearances is never changed.
#   Placements: 1 front (entries first), 2 interval-timed (time before each
#   entry grows with the interval it leaps), 3 spread, 4 late (first pc
#   dwelt on, then quick completion).
#   Types: 1 neighbour (back and forth), 2 echo (restates the stated pcs in
#   retrograde), 3 pedal (insists on the newest pc), 4 contour (alternates
#   first and newest pc with octave displacement, mirrored for I lines),
#   5 imitation (copies the leader voice's elaboration pattern).
# ==============================================================================
procedure gestIntervals: .j, .v
    .d1 = ((aggPc[.j, .v, 2] - aggPc[.j, .v, 1]) mod 12 + 12) mod 12
    .d2 = ((aggPc[.j, .v, 3] - aggPc[.j, .v, 2]) mod 12 + 12) mod 12
    .ic1 = min(.d1, 12 - .d1)
    .ic2 = min(.d2, 12 - .d2)
    .sum = .ic1 + .ic2
    .mod = if .sum <= 4 then 1 else if .sum >= 9 then -1 else 0 fi fi
endproc

procedure gesturePlan: .j, .v, .i, .mode
    .k = blkCyc[.j]
    .n = tw_ns[.v]
    .lab$ = aggLab$[.j, .v]
    .isR = left$(.lab$, 1) = "R"
    .isI = index(.lab$, "I") > 0
    @gestIntervals: .j, .v
    .ic1 = gestIntervals.ic1
    .ic2 = gestIntervals.ic2
    .cs = 0
    for .s from 1 to .n
        .cs = .cs + popc[tw_mask[.v, floor(tw_sel[.v, .s] / 4) + 1]]
    endfor
    .cbar = .cs / .n
    .rel = cycRel[.k]
    .lead = tw_ord[1]
    .follower = .i > 1 and .mode = 1
    # ---- placement
    .bestP = -1e9
    .place = 1
    for .p from 1 to 4
        .sc = 0
        if .p = 1 and .isR = 0 and .isI = 0
            .sc = .sc + 1
        elsif .p = 2 and .isI and .isR = 0
            .sc = .sc + 1
        elsif .p = 3 and .isR and .isI = 0
            .sc = .sc + 1
        elsif .p = 4 and .isR and .isI
            .sc = .sc + 1
        endif
        if .p = 2 and .ic1 + .ic2 >= 8
            .sc = .sc + 0.6
        endif
        if .p = gh_place[.v]
            .sc = .sc + (if .rel = 1 then 0.8 else -0.8 fi)
        endif
        if .mode <> 1
            .sc = .sc - 0.4 * gw_placeCount[.p]
        endif
        if .follower
            if .p = gp_place[.lead]
                .sc = .sc + 2
            endif
        endif
        if .sc > .bestP + 1e-9
            .bestP = .sc
            .place = .p
        endif
    endfor
    for .s from 1 to .n
        tw_isE[.v, .s] = 0
    endfor
    if .place = 1
        .e1 = 1
        .e2 = 2
        .e3 = 3
    elsif .place = 2
        .sl = .n - 3
        .w1 = .ic1 + 1
        .w2 = .ic2 + 1
        .wsum = .w1 + .w2 + 3
        .a = round(.sl * .w1 / .wsum)
        .b = round(.sl * .w2 / .wsum)
        .e1 = 1
        .e2 = 2 + .a
        .e3 = min(.n, 3 + .a + .b)
    elsif .place = 3
        .e1 = 1
        .e2 = 1 + floor(.n / 3)
        .e3 = 1 + floor(2 * .n / 3)
    else
        .e1 = 1
        .e2 = .n - 1
        .e3 = .n
    endif
    tw_isE[.v, .e1] = 1
    tw_isE[.v, .e2] = 1
    tw_isE[.v, .e3] = 1
    # ---- elaboration type
    .bestT = -1e9
    .type = 1
    .leadHas = 0
    if .i > 1
        .leadHas = gp_nE[.lead] > 0
    endif
    for .t from 1 to 5
        .sc = 0
        if .t = 1
            .sc = .sc + (if .cbar >= 2.5 then 1 else 0 fi) + (if .isR = 0 and .isI = 0 then 0.4 else 0 fi) + (if .ic1 + .ic2 <= 4 then 0.5 else 0 fi)
        elsif .t = 2
            .sc = .sc + (if .cbar < 2 then 1 else 0 fi) + (if .isR then 0.8 else 0 fi)
        elsif .t = 3
            .sc = .sc + (if .cbar >= 3 then 0.7 else 0 fi) + (if .ic1 + .ic2 <= 4 then 0.3 else 0 fi)
        elsif .t = 4
            .sc = .sc + (if .cbar < 2.5 then 0.8 else 0 fi) + (if .isI then 0.8 else 0 fi) + (if .ic1 + .ic2 >= 8 then 0.5 else 0 fi)
        else
            if .leadHas
                .sc = .sc + (if .follower then 2.2 else if .mode = 6 then 0.6 else -0.4 fi fi)
            else
                .sc = -1e6
            endif
        endif
        if .t = gh_type[.v]
            .sc = .sc + (if .rel = 1 then 1.5 else -1.0 fi)
        endif
        if .rel = 2 and gh_type[.v] > 0
            if .t = gestMap[gh_type[.v]]
                .sc = .sc + 1.5
            endif
        endif
        if .t <> 5
            .sc = .sc - (if .mode = 3 then 0.8 else 0.5 fi) * gw_typeCount[.t]
        endif
        if .sc > .bestT + 1e-9
            .bestT = .sc
            .type = .t
        endif
    endfor
    # ---- generate the elaboration pcs (index into the stated pcs) and octaves
    .m = 0
    .es = 0
    .step = 0
    .last = 0
    .dir = -1
    .sgn = if .isI then -1 else 1 fi
    for .s from 1 to .n
        if tw_isE[.v, .s] = 1
            .m = .m + 1
            gp_idx[.v, .s] = 0
            gp_oct[.v, .s] = 0
            .last = .m
            .dir = -1
            .step = 0
        else
            .es = .es + 1
            .oct = 0
            if .type = 1 or (.type = 5 and .leadHas = 0)
                if .m <= 1
                    .idx = 1
                else
                    .idx = .last + .dir
                    if .idx < 1 or .idx > .m
                        .dir = - .dir
                        .idx = .last + .dir
                    endif
                endif
            elsif .type = 2
                .idx = (((.m - 2 - .step) mod .m) + .m) mod .m + 1
            elsif .type = 3
                .idx = .m
            elsif .type = 4
                if (.step mod 2) = 0
                    .idx = 1
                    .oct = 12 * .sgn
                else
                    .idx = .m
                endif
            else
                .q = ((.es - 1) mod gp_nE[.lead]) + 1
                .idx = min(gp_eIdx[.lead, .q], .m)
                .oct = gp_eOct[.lead, .q]
            endif
            .idx = max(1, min(.idx, .m))
            gp_idx[.v, .s] = .idx
            gp_oct[.v, .s] = .oct
            gp_eIdx[.v, .es] = .idx
            gp_eOct[.v, .es] = .oct
            .last = .idx
            .step = .step + 1
        endif
    endfor
    gp_nE[.v] = .es
    gp_place[.v] = .place
    gp_type[.v] = .type
    gh_place[.v] = .place
    gh_type[.v] = .type
    gw_placeCount[.place] = gw_placeCount[.place] + 1
    gw_typeCount[.type] = gw_typeCount[.type] + 1
    blkGType[.j, .v] = .type
    blkGPlace[.j, .v] = .place
endproc

# ==============================================================================
# Procedures: independent rhythmic voices (v0.5)
# ==============================================================================
# Pattern of quarter .u (1..16) of cycle .k's series under the voice's own
# operation flags (Q, M, C), applied on top of the cycle operation.
procedure voicePattern: .k, .u, .q, .mm, .c, .rot
    .uu = ((.u - 1 + .rot) mod 16) + 1
    .src = if .q = 1 then 17 - .uu else .uu fi
    .m = ser[16 * (.k - 1) + .src]
    if .mm = 1
        @mirror4: .m
        .m = mirror4.m
    endif
    if .c = 1
        .m = 15 - .m
    endif
endproc

procedure pickEven: .nTot, .n
    for .i from 1 to .n
        pe_idx[.i] = if .n = 1 then 1 else round(1 + (.i - 1) * (.nTot - 1) / (.n - 1)) fi
    endfor
endproc

# Take .n evenly spaced positions from tw_L[1..nL] for voice .v.
# .emode 1: the first three are the entries; 2: entries spread over the run.
procedure twTake: .v, .nL, .n, .emode
    .n = min(max(3, .n + tw_mod[.v]), .nL)
    @pickEven: .nL, .n
    tw_ns[.v] = .n
    for .i from 1 to .n
        tw_sel[.v, .i] = tw_L[pe_idx[.i]]
        tw_isE[.v, .i] = 0
    endfor
    if .emode = 1
        for .i from 1 to 3
            tw_isE[.v, .i] = 1
        endfor
    else
        tw_isE[.v, 1] = 1
        tw_isE[.v, 1 + floor(.n / 3)] = 1
        tw_isE[.v, 1 + floor(2 * .n / 3)] = 1
    endif
endproc

# candidates of voice .v in [.lo, .hi) -> tw_L, returns .n
procedure twCands: .v, .lo, .hi
    .n = 0
    for .c from 1 to tw_nc[.v]
        if tw_cand[.v, .c] >= .lo and tw_cand[.v, .c] < .hi
            .n = .n + 1
            tw_L[.n] = tw_cand[.v, .c]
        endif
    endfor
endproc

# Relay monody: the window's quarters are divided into contiguous runs, one
# per voice, so exactly one line sounds at a time.
procedure texMonody
    .ok = 1
    .qp = 0
    for .i from 1 to 4
        .v = tw_ord[.i]
        if .i = 4
            .qe = 8
        else
            .qe = min(8, .qp + max(1, round((8 - .qp) / (5 - .i))))
        endif
        @twCands: .v, 4 * .qp, 4 * .qe
        while twCands.n < 3 and .qe < 8 and .i < 4
            .qe = .qe + 1
            @twCands: .v, 4 * .qp, 4 * .qe
        endwhile
        if twCands.n < 3
            .ok = 0
        else
            @twTake: .v, twCands.n, min(6, twCands.n), 1
        endif
        .qp = .qe
    endfor
endproc

procedure texWindow: .k, .half
    .j = 2 * (.k - 1) + .half
    .q0 = 8 * (.half - 1)
    .base = 16 * (.k - 1) + .q0
    .r = cycRole[.k]
    blkCyc[.j] = .k
    for .v from 1 to 4
        .lab$ = aggLab$[.j, .v]
        .isR = left$(.lab$, 1) = "R"
        .isI = index(.lab$, "I") > 0
        # rhythmic form follows the line form: P -> O, R -> R, I -> C, RI -> RC,
        # rotated by the line's T / I index
        blkVQ[.j, .v] = .isR
        blkVM[.j, .v] = .isR
        blkVC[.j, .v] = .isI
        # rotation by the line's transposition / inversion index (in quarters)
        .dig$ = replace_regex$(.lab$, "^[^0-9]*", "", 0)
        blkVRot[.j, .v] = if .dig$ = "" then 0 else number(.dig$) mod 16 fi
        tw_nc[.v] = 0
        for .u from 1 to 8
            @voicePattern: .k, .q0 + .u, blkVQ[.j, .v], blkVM[.j, .v], blkVC[.j, .v], blkVRot[.j, .v]
            tw_mask[.v, .u] = voicePattern.m
            for .p from 0 to 3
                if (floor(voicePattern.m / 2 ^ (3 - .p)) mod 2) = 1
                    tw_nc[.v] = tw_nc[.v] + 1
                    tw_cand[.v, tw_nc[.v]] = 4 * (.u - 1) + .p
                endif
            endfor
        endfor
        tw_ns[.v] = 0
    endfor
    .rot = (.j - 1) mod 4
    for .i from 1 to 4
        tw_ord[.i] = ((.rot + .i - 1) mod 4) + 1
    endfor
    for .v from 1 to 4
        @gestIntervals: .j, .v
        tw_mod[.v] = gestIntervals.mod
        gp_nE[.v] = 0
        gp_place[.v] = 0
    endfor
    for .p from 1 to 5
        gw_placeCount[.p] = 0
        gw_typeCount[.p] = 0
    endfor
    blkW[.j] = 0
    blkLead[.j] = tw_ord[1]
    blkMode[.j] = .r
    if .r = 2
        @texMonody
        if texMonody.ok = 0
            blkMode[.j] = 1
            tex_fallback = tex_fallback + 1
        endif
    endif
    .mode = blkMode[.j]
    if .mode = 2
        # relay monody already selected by texMonody
    elsif .mode = 1
        # canon: staggered entrances two quarters apart, each voice continues
        for .i from 1 to 4
            .v = tw_ord[.i]
            @twCands: .v, 8 * (.i - 1), 32
            if twCands.n < 3
                @twCands: .v, 0, 32
            endif
            @twTake: .v, twCands.n, 5, 1
        endfor
    elsif .mode = 3
        # density: every voice through the whole window, entries spread
        for .v from 1 to 4
            @twCands: .v, 0, 32
            @twTake: .v, twCands.n, 8, 2
        endfor
    elsif .mode = 4
        # spectral: few, widely spaced, sustained attacks
        for .v from 1 to 4
            @twCands: .v, 0, 32
            @twTake: .v, twCands.n, 4, 1
        endfor
    elsif .mode = 5
        # withheld: voice W states two pcs, falls silent, completes last
        .w = ((.j - 1) mod 4) + 1
        blkW[.j] = .w
        .wl = tw_cand[.w, tw_nc[.w]]
        tw_ns[.w] = 3
        tw_sel[.w, 1] = tw_cand[.w, 1]
        tw_sel[.w, 2] = tw_cand[.w, 2]
        tw_sel[.w, 3] = .wl
        for .i from 1 to 3
            tw_isE[.w, .i] = 1
        endfor
        for .v from 1 to 4
            if .v <> .w
                @twCands: .v, 0, .wl - 6
                if twCands.n < 3
                    @twCands: .v, 0, .wl
                endif
                if twCands.n < 3
                    @twCands: .v, 0, 32
                endif
                @twTake: .v, twCands.n, 4, 1
            endif
        endfor
    else
        # revelation: attacks placed on the time points two voices share
        for .pos from 0 to 31
            tw_cc[.pos] = 0
        endfor
        for .v from 1 to 4
            tw_ns[.v] = 0
            for .c from 1 to tw_nc[.v]
                tw_cc[tw_cand[.v, .c]] = tw_cc[tw_cand[.v, .c]] + 1
            endfor
        endfor
        .last = -10
        for .pos from 0 to 31
            if tw_cc[.pos] >= 2 and .pos - .last >= 3
                .took = 0
                for .v from 1 to 4
                    .has = 0
                    for .c from 1 to tw_nc[.v]
                        if tw_cand[.v, .c] = .pos
                            .has = 1
                        endif
                    endfor
                    if .has and tw_ns[.v] < 4
                        tw_ns[.v] = tw_ns[.v] + 1
                        tw_sel[.v, tw_ns[.v]] = .pos
                        .took = 1
                    endif
                endfor
                if .took
                    .last = .pos
                endif
            endif
        endfor
        for .v from 1 to 4
            # too few shared points: add the voice's own points, evenly
            if tw_ns[.v] < 3
                .n = 0
                for .c from 1 to tw_nc[.v]
                    .used = 0
                    for .i from 1 to tw_ns[.v]
                        if tw_sel[.v, .i] = tw_cand[.v, .c]
                            .used = 1
                        endif
                    endfor
                    if .used = 0
                        .n = .n + 1
                        tw_L[.n] = tw_cand[.v, .c]
                    endif
                endfor
                .need = 3 - tw_ns[.v]
                @pickEven: .n, .need
                for .i from 1 to .need
                    tw_ns[.v] = tw_ns[.v] + 1
                    tw_sel[.v, tw_ns[.v]] = tw_L[pe_idx[.i]]
                endfor
            endif
            # time order
            for .i from 2 to tw_ns[.v]
                .x = tw_sel[.v, .i]
                .i2 = .i - 1
                .go = 1
                while .go
                    if .i2 < 1
                        .go = 0
                    elsif tw_sel[.v, .i2] <= .x
                        .go = 0
                    else
                        tw_sel[.v, .i2 + 1] = tw_sel[.v, .i2]
                        .i2 = .i2 - 1
                    endif
                endwhile
                tw_sel[.v, .i2 + 1] = .x
            endfor
            for .i from 1 to tw_ns[.v]
                tw_isE[.v, .i] = .i <= 3
            endfor
        endfor
    endif

    # combinatorial gesture engine: entry placement + elaborations per voice,
    # in canon order so that followers can imitate the leader
    for .i from 1 to 4
        .v = tw_ord[.i]
        if .mode = 5 and .v = blkW[.j]
            blkGType[.j, .v] = 0
            blkGPlace[.j, .v] = 0
            for .s from 1 to tw_ns[.v]
                gp_idx[.v, .s] = 0
                gp_oct[.v, .s] = 0
            endfor
        else
            @gesturePlan: .j, .v, .i, .mode
        endif
    endfor

    # merge the four voices, sort by (time, voice)
    .ne = 0
    for .v from 1 to 4
        for .i from 1 to tw_ns[.v]
            .ne = .ne + 1
            te_pos[.ne] = tw_sel[.v, .i]
            te_v[.ne] = .v
            te_ent[.ne] = tw_isE[.v, .i]
        endfor
    endfor
    for .i from 2 to .ne
        .kp = te_pos[.i] * 10 + te_v[.i]
        .xp = te_pos[.i]
        .xv = te_v[.i]
        .xe = te_ent[.i]
        .i2 = .i - 1
        .go = 1
        while .go
            if .i2 < 1
                .go = 0
            elsif te_pos[.i2] * 10 + te_v[.i2] <= .kp
                .go = 0
            else
                te_pos[.i2 + 1] = te_pos[.i2]
                te_v[.i2 + 1] = te_v[.i2]
                te_ent[.i2 + 1] = te_ent[.i2]
                .i2 = .i2 - 1
            endif
        endwhile
        te_pos[.i2 + 1] = .xp
        te_v[.i2 + 1] = .xv
        te_ent[.i2 + 1] = .xe
    endfor

    # emit events: entries take the voice's next pc in line order;
    # elaborations walk back and forth over the pcs this voice has already
    # presented in this aggregate (never a pc it has not yet stated).
    for .v from 1 to 4
        tw_entCnt[.v] = 0
        tw_cnt[.v] = 0
    endfor
    blkA0[.j] = n_att + 1
    .ecount = 0
    for .t from 1 to .ne
        n_att = n_att + 1
        .v = te_v[.t]
        .pos = te_pos[.t]
        atkBeat[n_att] = .base + .pos / 4
        atkUnit[n_att] = 16 * (.k - 1) + .q0 + floor(.pos / 4) + 1
        atkPos[n_att] = .pos mod 4
        atkCyc[n_att] = .k
        atkCard[n_att] = popc[tw_mask[.v, floor(.pos / 4) + 1]]
        atkBlk[n_att] = .j
        atkVoice[n_att] = .v
        atkComplete[n_att] = 0
        atkOct[n_att] = 0
        tw_cnt[.v] = tw_cnt[.v] + 1
        if te_ent[.t] = 1
            tw_entCnt[.v] = tw_entCnt[.v] + 1
            .idx = tw_entCnt[.v]
            isRe[n_att] = 0
            atkIdx[n_att] = .idx
            atkPc[n_att] = aggPc[.j, .v, .idx]
            atkSrc[n_att] = n_att
            .ecount = .ecount + 1
            atkEntry[n_att] = .ecount
            tw_entAtk[.v, .idx] = n_att
        else
            .idx = max(1, min(gp_idx[.v, tw_cnt[.v]], tw_entCnt[.v]))
            atkOct[n_att] = gp_oct[.v, tw_cnt[.v]]
            .src = tw_entAtk[.v, .idx]
            isRe[n_att] = 1
            atkIdx[n_att] = .idx
            atkPc[n_att] = atkPc[.src]
            atkSrc[n_att] = .src
            atkEntry[n_att] = atkEntry[.src]
        endif
    endfor
    blkA1[.j] = n_att
    for .a from blkA0[.j] to blkA1[.j]
        if isRe[.a] = 0 and atkEntry[.a] = .ecount
            atkComplete[.a] = 1
        endif
    endfor
    blkNE[.j] = .ecount
    blkN[.j] = blkA1[.j] - blkA0[.j] + 1
    blkNRe[.j] = blkN[.j] - .ecount
    blkCyc[.j] = .k
    blkStart[.j] = .base
    blkEnd[.j] = .base + 8
    blkPol[.j] = 0
    blkScore[.j] = 0
    blkClus[.j] = 0
    blkOv[.j] = 0
    blkStag[.j] = 0
    blkDup[.j] = 0
endproc

# Structural tests specific to independent voices.
procedure texTests
    .okWin = 1
    .okEnt = 1
    .okRhy = 1
    .okSrc = 1
    .okSame = 1
    .okSer = 1
    for .j from 1 to n_agg
        if .j > 1
            if blkStart[.j] < blkEnd[.j - 1]
                .okWin = 0
            endif
        endif
        for .v from 1 to 4
            .ce[.v] = 0
            # the voice's full series under its operation stays exhaustive
            for .m from 0 to 15
                .sm[.m] = 0
            endfor
            for .u from 1 to 16
                @voicePattern: blkCyc[.j], .u, blkVQ[.j, .v], blkVM[.j, .v], blkVC[.j, .v], blkVRot[.j, .v]
                .sm[voicePattern.m] = .sm[voicePattern.m] + 1
            endfor
            for .m from 0 to 15
                if .sm[.m] <> 1
                    .okSer = 0
                endif
            endfor
        endfor
        for .a from blkA0[.j] to blkA1[.j]
            if atkBeat[.a] < blkStart[.j] or atkBeat[.a] >= blkEnd[.j]
                .okWin = 0
            endif
            .v = atkVoice[.a]
            if isRe[.a] = 0
                .ce[.v] = .ce[.v] + 1
            else
                .s = atkSrc[.a]
                if atkVoice[.s] <> .v or atkBlk[.s] <> .j or atkBeat[.s] >= atkBeat[.a] or isRe[.s] = 1
                    .okSrc = 0
                endif
            endif
            # the attack lies on the voice's own series
            .u = atkUnit[.a] - 16 * (blkCyc[.j] - 1)
            @voicePattern: blkCyc[.j], .u, blkVQ[.j, .v], blkVM[.j, .v], blkVC[.j, .v], blkVRot[.j, .v]
            if (floor(voicePattern.m / 2 ^ (3 - atkPos[.a])) mod 2) <> 1
                .okRhy = 0
            endif
            if .a > blkA0[.j]
                if atkBeat[.a - 1] = atkBeat[.a] and atkVoice[.a - 1] = .v
                    .okSame = 0
                endif
            endif
        endfor
        for .v from 1 to 4
            if .ce[.v] <> 3
                .okEnt = 0
            endif
        endfor
    endfor
    @stCheck: .okWin, "independent voices: every event inside its aggregate's time window"
    @stCheck: .okEnt, "independent voices: exactly 3 entries per voice per aggregate"
    @stCheck: .okRhy, "independent voices: every attack lies on the voice's own partition series"
    @stCheck: .okSer, "independent voices: each voice series (cycle op x line op) exhaustive"
    @stCheck: .okSrc, "independent voices: elaborations repeat an earlier pc of the same voice and aggregate"
    @stCheck: .okSame, "independent voices: no voice has two attacks at one time point"
    # monody guarantee: from the first to the last attack of every relay
    # window exactly one voice sounds (sixteenth grid, audible length)
    .okMono = 1
    mono_checked = 0
    for .j from 1 to n_agg
        if blkMode[.j] = 2
            mono_checked = mono_checked + 1
            .k = blkCyc[.j]
            .lo = if .k > 1 then cycA0[.k - 1] else 1 fi
            .g0 = round(atkBeat[blkA0[.j]] * 16)
            .g1 = round(atkBeat[blkA1[.j]] * 16)
            for .g from .g0 to .g1
                .tg = .g / 16
                .n = 0
                for .v from 1 to 4
                    .sv[.v] = 0
                endfor
                for .a from .lo to cycA1[.k]
                    if atkBeat[.a] <= .tg and .tg < atkBeat[.a] + atkEffB[.a]
                        .sv[atkVoice[.a]] = 1
                    endif
                endfor
                .n = .sv[1] + .sv[2] + .sv[3] + .sv[4]
                if .n <> 1
                    .okMono = 0
                endif
            endfor
        endif
    endfor
    if mono_checked > 0
        @stCheck: .okMono, "monody: exactly one sounding voice from first to last attack (" + string$(mono_checked) + " windows)"
    endif
endproc

# ==============================================================================
# Procedure: measured features of one cycle (from the event table)
# ==============================================================================
procedure cycleFeatures: .k
    .t0 = 16 * (.k - 1)
    .a0 = cycA0[.k]
    .a1 = cycA1[.k]
    .lo = if .k > 1 then cycA0[.k - 1] else 1 fi
    .poly = 0
    for .g from 0 to 127
        .tg = .t0 + .g / 8
        for .v from 1 to 4
            .s[.v] = 0
        endfor
        for .a from .lo to .a1
            if atkBeat[.a] <= .tg and .tg < atkBeat[.a] + atkEffB[.a]
                .s[atkVoice[.a]] = 1
            endif
        endfor
        .poly = .poly + .s[1] + .s[2] + .s[3] + .s[4]
    endfor
    cf_poly[.k] = .poly / 128
    # simultaneity: share of onset times with two or more voices
    .nt = 0
    .ns = 0
    .a = .a0
    while .a <= .a1
        .b = .a
        .go = 1
        while .go
            if .b + 1 > .a1
                .go = 0
            elsif atkBeat[.b + 1] <> atkBeat[.a]
                .go = 0
            else
                .b = .b + 1
            endif
        endwhile
        .nt = .nt + 1
        if .b > .a
            .ns = .ns + 1
        endif
        .a = .b + 1
    endwhile
    cf_sim[.k] = .ns / max(.nt, 1)
    .n = .a1 - .a0 + 1
    cf_dens[.k] = .n / 16
    .sd = 0
    .sm = 0
    .sm2 = 0
    .sdb = 0
    .sdb2 = 0
    .sp = 0
    .sp2 = 0
    for .a from .a0 to .a1
        .sd = .sd + atkEffB[.a]
        .sm = .sm + atkMidi[.a]
        .sm2 = .sm2 + atkMidi[.a] ^ 2
        .sdb = .sdb + atkDb[.a]
        .sdb2 = .sdb2 + atkDb[.a] ^ 2
        .sp = .sp + atkPan[.a]
        .sp2 = .sp2 + atkPan[.a] ^ 2
    endfor
    cf_dur[.k] = .sd / .n
    cf_regMean[.k] = .sm / .n
    cf_regSd[.k] = sqrt(max(0, .sm2 / .n - (.sm / .n) ^ 2))
    cf_dynSd[.k] = sqrt(max(0, .sdb2 / .n - (.sdb / .n) ^ 2))
    cf_panSd[.k] = sqrt(max(0, .sp2 / .n - (.sp / .n) ^ 2))
    # rhythmic independence: 1 - mean |r| between the voices' onset counts per
    # half quarter (32 bins per cycle)
    for .v from 1 to 4
        for .q from 1 to 32
            .oc[.v, .q] = 0
        endfor
    endfor
    for .a from .a0 to .a1
        .q = floor((atkBeat[.a] - .t0) * 2) + 1
        .oc[atkVoice[.a], .q] = .oc[atkVoice[.a], .q] + 1
    endfor
    .sumr = 0
    .np = 0
    for .v from 1 to 3
        for .w from .v + 1 to 4
            .mx = 0
            .my = 0
            for .q from 1 to 32
                .mx = .mx + .oc[.v, .q] / 32
                .my = .my + .oc[.w, .q] / 32
            endfor
            .cxy = 0
            .cxx = 0
            .cyy = 0
            for .q from 1 to 32
                .cxy = .cxy + (.oc[.v, .q] - .mx) * (.oc[.w, .q] - .my)
                .cxx = .cxx + (.oc[.v, .q] - .mx) ^ 2
                .cyy = .cyy + (.oc[.w, .q] - .my) ^ 2
            endfor
            if .cxx > 0 and .cyy > 0
                .sumr = .sumr + abs(.cxy / sqrt(.cxx * .cyy))
                .np = .np + 1
            endif
        endfor
    endfor
    cf_indep[.k] = if .np > 0 then 1 - .sumr / .np else 0 fi
    # composite onset grid for gesture similarity (time point x voice)
    for .x from 0 to 255
        cg[.k, .x] = 0
    endfor
    for .a from .a0 to .a1
        .x = round((atkBeat[.a] - .t0) * 4) * 4 + atkVoice[.a] - 1
        cg[.k, .x] = 1
    endfor
endproc

# ==============================================================================
# Procedure: complementary spectral model (v0.5, Timbre = Complementary)
#   A note whose pc belongs to hexachord H (the content of P) keeps only
#   partials whose chroma lies in H, retuned to the exact tempered pitch; a
#   note of the complement keeps only complement chroma. Missing chroma of the
#   note's own hexachord are added as completion partials in the octave above
#   2 f0, stronger for its own trichord, and growing as the aggregate nears
#   completion. The two groups therefore occupy complementary spectral
#   pitch-class regions; the note that completes an aggregate sounds all 12.
# ==============================================================================
procedure complementarySpectrum: .a
    .v = atkVoice[.a]
    .blk = atkBlk[.a]
    .k = atkCyc[.a]
    .x = atkPc[.a]
    .f0 = atkF[.a]
    # chroma set: the two trichords of the voice pair (S+T or A+B) in this
    # aggregate; spec_groups = 2 is a verification hook reproducing v0.5's
    # fixed hexachord of P.
    .pv = dmap[.v]
    for .c from 0 to 11
        .gs[.c] = 0
        if spec_groups = 2
            .gs[.c] = inHexP[.c] = inHexP[.x]
        endif
    endfor
    if spec_groups = 1
        for .m from 1 to 3
            .gs[aggPc[.blk, .v, .m]] = 1
            .gs[aggPc[.blk, .pv, .m]] = 1
        endfor
    endif
    .tauE = renderEvent.tauE
    .u$ = renderEvent.u$
    .isIline = index(aggLab$[.blk, .v], "I") > 0 and spec_groups = 1
    @trichordClass: aggPc[.blk, .v, 1], aggPc[.blk, .v, 2], aggPc[.blk, .v, 3]
    .tc = trichordClass.code
    .lo = floor(.tc / 10)
    .mi = (.tc mod 10) - .lo
    .hi = 12 - .lo - .mi
    .rho = 0
    @icWeight: .lo
    .rho = .rho + icWeight.w
    @icWeight: .mi
    .rho = .rho + icWeight.w
    @icWeight: .hi
    .rho = .rho + icWeight.w
    .rho = min(1, .rho / 6)
    .beta = 1.6 - 0.9 * .rho
    for .c from 0 to 11
        .cov[.c] = 0
    endfor
    for .h from 1 to cycHmax[.k]
        .mh = 69 + 12 * log2(.h * .f0 / 440)
        .mr = round(.mh)
        .ch = .mr mod 12
        if .gs[.ch] = 1
            .ft = if .h = 1 then .f0 else 440 * 2 ^ ((.mr - 69) / 12) fi
            .rate = (1 + 0.15 * (.h - 1)) / .tauE
            # inversion -> inverted spectral tilt: I / RI lines weight their
            # upper partials rising toward the top instead of falling
            .wh = 1 / .h ^ .beta
            if .isIline and .h > 1
                .wh = 0.7 * (.h / cycHmax[.k]) ^ (0.5 * .beta)
            endif
            @addPartial: .ft, .wh, "exp(-" + fixed$(.rate, 5) + "*" + .u$ + ")"
            .cov[.ch] = 1
        endif
    endfor
    .sig = cycSig[.k]
    .prog = (atkEntry[.a] - 1) / 11
    if atkIsR[.a]
        .env$ = "(1-exp(-" + .u$ + "/" + fixed$(0.25 * .tauE, 5) + "))*exp(-" + fixed$(0.5 / .tauE, 5) + "*" + .u$ + ")"
    else
        .env$ = "exp(-" + fixed$(1.4 / .tauE, 5) + "*" + .u$ + ")"
    endif
    for .y from 0 to 11
        if .gs[.y] = 1 and .cov[.y] = 0
            .inT = .y = aggPc[.blk, .v, 1] or .y = aggPc[.blk, .v, 2] or .y = aggPc[.blk, .v, 3]
            .wt = .sig * (if .inT then 0.5 else 0.10 + 0.25 * .prog fi)
            .iv = ((.y - .x) mod 12 + 12) mod 12
            @addPartial: 2 ^ (1 + .iv / 12) * .f0, .wt, .env$
        endif
    endfor
    if atkComplete[.a] and isRe[.a] = 0
        for .y from 0 to 11
            if .y <> .x
                .iv = ((.y - .x) mod 12 + 12) mod 12
                @addPartial: 2 ^ (2 + .iv / 12) * .f0, 0.05 * .sig + 0.02, "(1-exp(-" + .u$ + "/0.15))*exp(-" + fixed$(1 / (1.5 * .tauE), 5) + "*" + .u$ + ")"
            endif
        endfor
    endif
endproc

# ==============================================================================
# Procedure: measured spectra per cycle (rendered sound and group stems)
#   chroma = energy in semitone bands MIDI 36-119 folded to 12 classes;
#   complementarity = share of each hexachord stem's energy that falls in its
#   own six chroma (0.5 = no separation, 1 = complete separation).
# ==============================================================================
procedure measureSpectra
    # ---- per cycle: master chroma / octave profile / centroid (QC only)
    selectObject: master_id
    if nch = 2
        .mono = Convert to mono
    else
        .mono = Copy: "babbitt_mono_tmp2"
    endif
    for .k from 1 to n_cyc
        .t0 = 16 * (.k - 1) * beat
        .t1 = if .k = n_cyc then master_duration else 16 * .k * beat fi
        selectObject: .mono
        .part = Extract part: .t0, .t1, "rectangular", 1, "no"
        .sp = To Spectrum: "yes"
        cycCent[.k] = Get centre of gravity: 2
        @chromaBands
        removeObject: .sp, .part
        .sum = 0
        .sumO = 0
        for .c from 0 to 11
            .sum = .sum + cb_ch[.c]
        endfor
        for .o from 1 to 7
            .sumO = .sumO + cb_ob[.o]
        endfor
        for .c from 0 to 11
            cycCh[.k, .c] = cb_ch[.c] / max(.sum, 1e-30)
        endfor
        for .o from 1 to 7
            cycOb[.k, .o] = cb_ob[.o] / max(.sumO, 1e-30)
        endfor
        if .k > 1
            .dot = 0
            .na = 0
            .nb = 0
            for .c from 0 to 11
                .dot = .dot + cycCh[.k, .c] * cycCh[.k - 1, .c]
                .na = .na + cycCh[.k, .c] ^ 2
                .nb = .nb + cycCh[.k - 1, .c] ^ 2
            endfor
            for .o from 1 to 7
                .dot = .dot + cycOb[.k, .o] * cycOb[.k - 1, .o]
                .na = .na + cycOb[.k, .o] ^ 2
                .nb = .nb + cycOb[.k - 1, .o] ^ 2
            endfor
            cycSpecDist[.k] = 1 - .dot / sqrt(max(.na * .nb, 1e-30))
        else
            cycSpecDist[.k] = 0
        endif
    endfor
    removeObject: .mono

    # ---- upper partials = full group stem minus its fundamental-only stem
    selectObject: stemH_id
    .upH = Copy: "babbitt_upH_tmp"
    Formula: "self - object[" + string$(fundH_id) + ", 1, col]"
    selectObject: stemC_id
    .upC = Copy: "babbitt_upC_tmp"
    Formula: "self - object[" + string$(fundC_id) + ", 1, col]"

    # ---- per aggregate: group chroma = the voice pair's two trichords
    #   numerical separation: share of each group's UPPER-partial energy in
    #   its own six chroma (fundamentals excluded, so pure tones score n/a);
    #   audibility proxy: upper-partial energy relative to the fundamentals;
    #   timbral differentiation proxy: brightness (upper-partial centroid over
    #   fundamental centroid, in octaves) compared between the two groups.
    .uIn = 0
    .uTot = 0
    .fTot = 0
    .bc = 0
    .nbc = 0
    for .k from 1 to n_cyc
        cycUIn[.k] = 0
        cycUTot[.k] = 0
    endfor
    for .j from 1 to n_agg
        .t0 = blkStart[.j] * beat
        .t1 = min(master_duration, blkEnd[.j] * beat)
        for .c from 0 to 11
            .g1[.c] = 0
        endfor
        if spec_groups = 1
            for .m from 1 to 3
                .g1[aggPc[.j, 1, .m]] = 1
                .g1[aggPc[.j, 3, .m]] = 1
            endfor
        else
            for .c from 0 to 11
                .g1[.c] = inHexP[.c]
            endfor
        endif
        for .s from 1 to 4
            .id = if .s = 1 then .upH else if .s = 2 then .upC else if .s = 3 then fundH_id else fundC_id fi fi fi
            selectObject: .id
            .part = Extract part: .t0, .t1, "rectangular", 1, "no"
            .sp = To Spectrum: "yes"
            .cent[.s] = Get centre of gravity: 2
            @chromaBands
            removeObject: .sp, .part
            .e = 0
            .in = 0
            for .c from 0 to 11
                .e = .e + cb_ch[.c]
                if (.s = 1 and .g1[.c] = 1) or (.s = 2 and .g1[.c] = 0)
                    .in = .in + cb_ch[.c]
                endif
            endfor
            if .s <= 2
                .uIn = .uIn + .in
                .uTot = .uTot + .e
                cycUIn[blkCyc[.j]] = cycUIn[blkCyc[.j]] + .in
                cycUTot[blkCyc[.j]] = cycUTot[blkCyc[.j]] + .e
            else
                .fTot = .fTot + .e
            endif
        endfor
        # brightness of a group = centroid of its upper partials over the
        # centroid of its fundamentals (octaves); compared between the groups
        if .cent[1] <> undefined and .cent[2] <> undefined and .cent[3] <> undefined and .cent[4] <> undefined
            if .cent[3] > 0 and .cent[4] > 0 and .cent[1] > 0 and .cent[2] > 0
                .bc = .bc + abs(log2(.cent[1] / .cent[3]) - log2(.cent[2] / .cent[4]))
                .nbc = .nbc + 1
            endif
        endif
    endfor
    removeObject: .upH, .upC
    spec_upper_db = if .fTot > 0 and .uTot > 0 then 10 * log10(.uTot / .fTot) else undefined fi
    spec_ci = if .uTot > 1e-4 * .fTot then .uIn / .uTot else undefined fi
    spec_bright = if .nbc > 0 then .bc / .nbc else undefined fi
    for .k from 1 to n_cyc
        cycCI[.k] = if cycUTot[.k] > 1e-4 * .fTot / n_cyc then cycUIn[.k] / cycUTot[.k] else undefined fi
    endfor
endproc

# energy of the selected Spectrum in semitone bands MIDI 36-119 -> cb_ch (12), cb_ob (7)
procedure chromaBands
    for .c from 0 to 11
        cb_ch[.c] = 0
    endfor
    for .o from 1 to 7
        cb_ob[.o] = 0
    endfor
    for .mm from 36 to 119
        .fc = 440 * 2 ^ ((.mm - 69) / 12)
        .e = Get band energy: .fc * 2 ^ (-1 / 24), .fc * 2 ^ (1 / 24)
        if .e = undefined
            .e = 0
        endif
        cb_ch[.mm mod 12] = cb_ch[.mm mod 12] + .e
        .o = floor((.mm - 36) / 12) + 1
        cb_ob[.o] = cb_ob[.o] + .e
    endfor
endproc

# ==============================================================================
# Procedure: inter-cycle similarity (not an optimization target anywhere)
#   feature distance: Euclidean distance of z-scored per-cycle features
#   (sounding voices, simultaneity, onset density, audible length, register
#   spread, dynamic spread, pan spread, rhythmic independence, log centroid);
#   gesture similarity: Jaccard index of the (time point, voice) onset grids.
# ==============================================================================
procedure interCycle
    ic_adj = 0
    ic_min = undefined
    ic_minA = 0
    ic_minB = 0
    jac_adj = 0
    jac_max = 0
    jac_maxA = 0
    jac_maxB = 0
    if n_cyc > 1
        for .k from 1 to n_cyc
            .f[.k, 1] = cf_poly[.k]
            .f[.k, 2] = cf_sim[.k]
            .f[.k, 3] = cf_dens[.k]
            .f[.k, 4] = cf_dur[.k]
            .f[.k, 5] = cf_regSd[.k]
            .f[.k, 6] = cf_dynSd[.k]
            .f[.k, 7] = cf_panSd[.k]
            .f[.k, 8] = cf_indep[.k]
            .f[.k, 9] = log2(max(cycCent[.k], 1))
        endfor
        for .q from 1 to 9
            .m = 0
            for .k from 1 to n_cyc
                .m = .m + .f[.k, .q] / n_cyc
            endfor
            .s = 0
            for .k from 1 to n_cyc
                .s = .s + (.f[.k, .q] - .m) ^ 2 / n_cyc
            endfor
            .s = sqrt(.s)
            for .k from 1 to n_cyc
                .z[.k, .q] = if .s > 1e-9 then (.f[.k, .q] - .m) / .s else 0 fi
            endfor
        endfor
        for .k from 1 to n_cyc - 1
            for .l from .k + 1 to n_cyc
                .d = 0
                for .q from 1 to 9
                    .d = .d + (.z[.k, .q] - .z[.l, .q]) ^ 2
                endfor
                .d = sqrt(.d)
                .inter = 0
                .union = 0
                for .x from 0 to 255
                    .inter = .inter + cg[.k, .x] * cg[.l, .x]
                    .union = .union + max(cg[.k, .x], cg[.l, .x])
                endfor
                .jac = .inter / max(.union, 1)
                if .l = .k + 1
                    ic_adj = ic_adj + .d / (n_cyc - 1)
                    jac_adj = jac_adj + .jac / (n_cyc - 1)
                    cycFeatDist[.l] = .d
                    cycJac[.l] = .jac
                endif
                if ic_min = undefined
                    ic_min = .d
                    ic_minA = .k
                    ic_minB = .l
                elsif .d < ic_min
                    ic_min = .d
                    ic_minA = .k
                    ic_minB = .l
                endif
                if .jac > jac_max
                    jac_max = .jac
                    jac_maxA = .k
                    jac_maxB = .l
                endif
            endfor
        endfor
    endif
    cycFeatDist[1] = 0
    cycJac[1] = 0
endproc

# ==============================================================================
# Procedures: SATB voice range protection and composition duration (v0.5.4)
# ==============================================================================
# Voice ranges: standard SATB profile or the custom field (8 MIDI numbers).
# A range must span at least 11 semitones so that every pitch class has a
# placement; otherwise the run stops with an error (no pitch-class change).
procedure voiceRangeSetup
    vFull$[1] = "Soprano"
    vFull$[2] = "Alto"
    vFull$[3] = "Tenor"
    vFull$[4] = "Bass"
    vLo[1] = 60
    vHi[1] = 81
    vLo[2] = 55
    vHi[2] = 76
    vLo[3] = 48
    vHi[3] = 69
    vLo[4] = 40
    vHi[4] = 64
    range_src$ = "standard SATB"
    if voice_range_protection and voice_range_profile = 2
        .s$ = replace$(custom_ranges$, "-", " ", 0)
        .s$ = replace$(.s$, ",", " ", 0)
        .s$ = replace$(.s$, tab$, " ", 0) + " "
        .n = 0
        while length(.s$) > 0
            .p = index(.s$, " ")
            .tok$ = left$(.s$, .p - 1)
            .s$ = right$(.s$, length(.s$) - .p)
            if .tok$ <> ""
                .n = .n + 1
                .val[.n] = number(.tok$)
                if .val[.n] = undefined
                    exitScript: "Custom ranges: """ + .tok$ + """ is not a MIDI number. Expected 8 numbers, e.g. 60-81 55-76 48-69 40-64 (S A T B, min-max)."
                endif
            endif
        endwhile
        if .n <> 8
            exitScript: "Custom ranges: expected 8 MIDI numbers (S A T B, min-max), found " + string$(.n) + "."
        endif
        for .v from 1 to 4
            vLo[.v] = round(.val[2 * .v - 1])
            vHi[.v] = round(.val[2 * .v])
        endfor
        range_src$ = "custom"
    endif
    if voice_range_protection
        for .v from 1 to 4
            if vLo[.v] < 21 or vHi[.v] > 108 or vLo[.v] >= vHi[.v]
                exitScript: vFull$[.v] + " range " + string$(vLo[.v]) + "-" + string$(vHi[.v]) + " is invalid: minimum < maximum, both within MIDI 21-108."
            endif
            if vHi[.v] - vLo[.v] < 11
                exitScript: vFull$[.v] + " range " + string$(vLo[.v]) + "-" + string$(vHi[.v]) + " spans " + string$(vHi[.v] - vLo[.v]) + " semitones: at least 11 are needed so that every pitch class has an octave placement inside it. Widen the range or switch Voice range protection off."
            endif
        endfor
    endif
endproc

# Octave placement inside the voice range: keeps the pitch class; among the
# octave-equivalent candidates in range, the one nearest the intended pitch
# (the register strategy's choice), ties and near-ties toward the voice's
# previous pitch (melodic continuity). Pitches already in range are kept.
procedure voiceFit: .v, .m, .prev
    .out = .m
    .moved = 0
    if .m < vLo[.v] or .m > vHi[.v]
        .pc = .m - 12 * floor(.m / 12)
        .c = vLo[.v] + ((.pc - vLo[.v]) - 12 * floor((.pc - vLo[.v]) / 12))
        .best = -1
        .bc = 1e9
        while .c <= vHi[.v]
            .cost = abs(.c - .m) + (if .prev > 0 then 0.25 * abs(.c - .prev) else 0 fi)
            if .cost < .bc - 1e-9
                .bc = .cost
                .best = .c
            endif
            .c = .c + 12
        endwhile
        if .best < 0
            exitScript: "Voice range protection: pitch class " + string$(.pc) + " has no octave inside the " + vFull$[.v] + " range " + string$(vLo[.v]) + "-" + string$(vHi[.v]) + ". No pitch class is ever changed; widen the range."
        endif
        .out = .best
        .moved = 1
    endif
endproc

# Target-duration mode: tempo from the existing cycle count (no cycles added
# or removed, no truncation, no time-stretching). If the tempo would leave
# 20-300 bpm, the user changes the duration or the cycle count, or cancels.
procedure durationFromTarget
    .go = 1
    while .go
        if target_duration_s <= 0
            exitScript: "Target duration must be greater than 0 seconds."
        endif
        if derivation_cycles < 0 or derivation_cycles > 7
            exitScript: "Derivation cycles must be between 0 and 7."
        endif
        .nc = 1 + secondary_sets + round(derivation_cycles)
        .t = 16 * .nc * 60 / target_duration_s
        if .t >= 20 and .t <= 300
            tempo_bpm = .t
            .go = 0
        else
            .dmin = 16 * .nc * 60 / 300
            .dmax = 16 * .nc * 60 / 20
            .cmin = max(1 + secondary_sets, ceiling(target_duration_s * 20 / 960))
            .cmax = min(8 + secondary_sets, floor(target_duration_s * 300 / 960))
            if .cmin <= .cmax
                .cyc$ = "derivation cycles " + string$(.cmin - 1 - secondary_sets) + " to " + string$(.cmax - 1 - secondary_sets) + " would fit"
            else
                .cyc$ = "no cycle count (derivation cycles 0-7) fits"
            endif
            .oldT = target_duration_s
            .oldD = round(derivation_cycles)
            beginPause: "Babbitt Arrays - target duration not reachable"
                comment: "Target " + fixed$(target_duration_s, 2) + " s with " + string$(.nc) + " cycles (" + string$(16 * .nc) + " beats) needs " + fixed$(.t, 2) + " bpm; supported: 20-300 bpm."
                comment: "With " + string$(.nc) + " cycles, choose a duration from " + fixed$(.dmin, 2) + " to " + fixed$(.dmax, 2) + " s."
                comment: "For " + fixed$(target_duration_s, 2) + " s, " + .cyc$ + "."
                real: "Target duration (s)", fixed$(target_duration_s, 3)
                integer: "Derivation cycles (0-7)", string$(.oldD)
            .clicked = endPause: "Cancel", "Apply", 2, 1
            if .clicked = 1
                exitScript: "Target duration " + fixed$(.oldT, 2) + " s is not reachable with " + string$(.nc) + " cycles (needs " + fixed$(.t, 2) + " bpm). Run cancelled."
            endif
            target_duration_s = target_duration
            if target_duration_s = .oldT and round(derivation_cycles) = .oldD
                exitScript: "Target duration " + fixed$(.oldT, 2) + " s is not reachable with " + string$(.nc) + " cycles (needs " + fixed$(.t, 2) + " bpm; supported 20-300). Choose a duration from " + fixed$(.dmin, 2) + " to " + fixed$(.dmax, 2) + " s, or " + .cyc$ + "."
            endif
        endif
    endwhile
endproc

# tempo as text: integers as before ("60"), otherwise enough decimals to
# reproduce the musical duration (MusicXML <sound tempo>)
procedure tempoText: .t, .nd
    if abs(.t - round(.t)) < 1e-9
        .s$ = fixed$(.t, 0)
    else
        .s$ = fixed$(.t, .nd)
        while right$(.s$, 1) = "0"
            .s$ = left$(.s$, length(.s$) - 1)
        endwhile
    endif
endproc

# ==============================================================================
# Procedures: Global Dynamic Arc (v0.5.2)
#   ONE shared envelope, defined in composition time (beats), sampled every
#   arc_step beats into arcDbT[] (dB, 0 = unchanged). The same table drives
#   (a) the audio: per-sample gain, linearly interpolated in dB between the
#       table points, applied to the finished mix (all channels alike), and
#   (b) the MusicXML: the sounding level of every note = its own event level
#       + the arc at its onset -> dynamic marks, the note's playback
#       "dynamics" attribute, and wedges over the arc's rising / falling
#       spans. Events (pitch, rhythm, voices, articulation, pan) are not
#       touched.
#   Shapes (u = time / composition length, p = peak or valley position,
#   R = range, s(x) = 0.5 - 0.5 cos(pi x), a smooth raised-cosine ramp):
#     Arch           -R (1 - s(u / p))  then  -R (1 - s((1 - u) / (1 - p)))
#     Inverted arch  -R s(u / p)        then  -R s((1 - u) / (1 - p))
#     Rising         -R (1 - s(u))      Falling  -R s(u)
#   The arc never raises the level (maximum 0 dB), so it cannot cause
#   clipping; the final peak normalization is one uniform factor and keeps
#   the arc's shape intact.
# ==============================================================================
procedure arcFunc: .u
    .p = arc_peak_position / 100
    .r = arc_range
    .u = max(0, min(1, .u))
    if arc_shape = 2
        if .u <= .p
            .x = .u / .p
            .d = -.r * (0.5 + 0.5 * cos(pi * .x))
        else
            .x = (1 - .u) / (1 - .p)
            .d = -.r * (0.5 + 0.5 * cos(pi * .x))
        endif
    elsif arc_shape = 3
        if .u <= .p
            .x = .u / .p
        else
            .x = (1 - .u) / (1 - .p)
        endif
        .d = -.r * (0.5 - 0.5 * cos(pi * .x))
    elsif arc_shape = 4
        .d = -.r * (0.5 + 0.5 * cos(pi * .u))
    elsif arc_shape = 5
        .d = -.r * (0.5 - 0.5 * cos(pi * .u))
    else
        .d = 0
    endif
endproc

procedure arcBuild
    arc_step = 0.125
    arc_T = 16 * n_cyc
    arc_n = ceiling(master_duration / beat / arc_step) + 2
    for .i from 1 to arc_n
        .tb = (.i - 1) * arc_step
        @arcFunc: .tb / arc_T
        arcDbT[.i] = arcFunc.d
    endfor
endproc

# arc level (dB) at composition time .tb (beats): the table, interpolated
procedure arcAt: .tb
    .x = .tb / arc_step + 1
    .i = max(1, min(arc_n - 1, floor(.x)))
    .f = max(0, min(1, .x - .i))
    .d = arcDbT[.i] * (1 - .f) + arcDbT[.i + 1] * .f
endproc

# Gain automation of the finished mix: the table becomes a control Sound
# whose sample k sits exactly at table time (k - 1) * step; object(id, x)
# interpolates linearly between them for every audio sample.
procedure arcApplyAudio
    .dt = arc_step * beat
    .env = Create Sound from formula: "babbitt_arc_env", 1, -0.5 * .dt, (arc_n - 0.5) * .dt, 1 / .dt, "0"
    for .i from 1 to arc_n
        Set value at sample number: .i, arcDbT[.i]
    endfor
    selectObject: master_id
    Formula: "self * 10 ^ (object(" + string$(.env) + ", x) / 20)"
    removeObject: .env
endproc

# MusicXML wedge plan (identical for every part): crescendo where the arc
# rises, diminuendo where it falls, switching at the peak / valley.
procedure arcWedgePlan
    arc_nw = 0
    .end16 = arc_T * 4
    .pk16 = round(arc_peak_position / 100 * .end16)
    if arc_shape = 2
        @arcWedgeAdd: 0, "crescendo"
        @arcWedgeAdd: .pk16, "stop"
        @arcWedgeAdd: .pk16, "diminuendo"
        @arcWedgeAdd: .end16, "stop"
    elsif arc_shape = 3
        @arcWedgeAdd: 0, "diminuendo"
        @arcWedgeAdd: .pk16, "stop"
        @arcWedgeAdd: .pk16, "crescendo"
        @arcWedgeAdd: .end16, "stop"
    elsif arc_shape = 4
        @arcWedgeAdd: 0, "crescendo"
        @arcWedgeAdd: .end16, "stop"
    elsif arc_shape = 5
        @arcWedgeAdd: 0, "diminuendo"
        @arcWedgeAdd: .end16, "stop"
    endif
endproc

procedure arcWedgeAdd: .t16, .type$
    arc_nw = arc_nw + 1
    arcW16[arc_nw] = .t16
    arcWType$[arc_nw] = .type$
endproc

# emit (in the current part) every pending wedge whose time has come
# (a wedge that falls inside the previous note is placed exactly with a
# negative <offset>, never across the barline)
procedure arcFlushWedges: .pos16
    .go = 1
    while .go
        if xm_wNext > arc_nw
            .go = 0
        elsif arcW16[xm_wNext] > .pos16
            .go = 0
        else
            .off$ = ""
            .barStart = (xm_meas - 1) * 16
            if .pos16 < 1e8
                .target = max(arcW16[xm_wNext], .barStart)
                if .target < .pos16
                    .off$ = "<offset>" + string$(.target - .pos16) + "</offset>"
                endif
            endif
            @xmlAdd: "      <direction placement=""below""><direction-type><wedge type=""" + arcWType$[xm_wNext] + """ number=""1""/></direction-type>" + .off$ + "</direction>"
            xm_wNext = xm_wNext + 1
        endif
    endwhile
endproc

# sounding level of an event (event dB + arc at its onset) -> mark index and
# MusicXML playback percentage of the forte velocity: 89 x 2^(dB / 12)
# (mf = 89 as in the dynamic marks' sound values; invertible at every level,
# so a deep arc is never clipped by a floor)
procedure arcEventLevel: .a
    @arcAt: atkBeat[.a]
    .db = atkDb[.a] + arcAt.d
    .mark = min(5, max(0, round(.db / 6) + 3))
    .pct = 89 * 2 ^ (.db / 12)
endproc

# measured check: loudest / softest 4-beat RMS window of the output
procedure arcMeasure
    selectObject: master_id
    .w = 4
    .nw = floor(arc_T / .w)
    arc_meas_max = -1e9
    arc_meas_min = 1e9
    arc_meas_tmax = 0
    arc_meas_tmin = 0
    for .i from 1 to .nw
        .r = Get root-mean-square: (.i - 1) * .w * beat, .i * .w * beat
        if .r <> undefined and .r > 0
            .db = 20 * log10(.r)
            if .db > arc_meas_max
                arc_meas_max = .db
                arc_meas_tmax = (.i - 0.5) * .w
            endif
            if .db < arc_meas_min
                arc_meas_min = .db
                arc_meas_tmin = (.i - 0.5) * .w
            endif
        endif
    endfor
endproc

# RMS of the mix in quarter-beat windows over the composition (all channels)
procedure arcRmsWindows
    selectObject: master_id
    arc_wb = 0.25
    arc_nb = floor(min(arc_T, master_duration / beat) / arc_wb)
    for .i from 1 to arc_nb
        .r = Get root-mean-square: (.i - 1) * arc_wb * beat, .i * arc_wb * beat
        arcWinR[.i] = if .r = undefined then 0 else .r fi
    endfor
endproc

# measured gain = RMS after / RMS before the arc (normalization factor
# removed), per quarter-beat window; compared with the table; plus a
# 4-beat smoothed output RMS for the figure
procedure arcGainCurve
    @arcRmsWindows
    .g = if pre_norm_peak > 0 then output_peak / pre_norm_peak else 1 fi
    arc_gain_err = 0
    arc_gain_n = 0
    arc_gmax = -1e9
    arc_gmin = 1e9
    arc_gtmax = 0
    arc_gtmin = 0
    for .i from 1 to arc_nb
        .tc = (.i - 0.5) * arc_wb
        @arcAt: .tc
        arcReqW[.i] = arcAt.d
        arcGainOk[.i] = arcPreRms[.i] > 1e-5 and arcWinR[.i] > 0
        if arcGainOk[.i]
            arcGainW[.i] = 20 * log10(arcWinR[.i] / (arcPreRms[.i] * .g))
            arc_gain_err = max(arc_gain_err, abs(arcGainW[.i] - arcReqW[.i]))
            arc_gain_n = arc_gain_n + 1
            if arcGainW[.i] > arc_gmax
                arc_gmax = arcGainW[.i]
                arc_gtmax = .tc
            endif
            if arcGainW[.i] < arc_gmin
                arc_gmin = arcGainW[.i]
                arc_gtmin = .tc
            endif
        endif
    endfor
    # smoothed output RMS: power mean over 4 beats (16 windows), dB re loudest
    .h = 8
    .top = -1e9
    for .i from 1 to arc_nb
        .p = 0
        .c = 0
        for .k from max(1, .i - .h) to min(arc_nb, .i + .h - 1)
            .p = .p + arcWinR[.k] ^ 2
            .c = .c + 1
        endfor
        arcSmoothDb[.i] = if .p > 0 then 10 * log10(.p / .c) else -200 fi
        .top = max(.top, arcSmoothDb[.i])
    endfor
    for .i from 1 to arc_nb
        arcSmoothDb[.i] = arcSmoothDb[.i] - .top
    endfor
    # exact turning point (table) and its notated position (16th grid)
    arc_tp_exact = arc_peak_position / 100 * arc_T
    arc_tp_notated = round(arc_peak_position / 100 * arc_T * 4) / 4
endproc

# ==============================================================================
# Procedure: Info report
# ==============================================================================
procedure infoReport
    clearinfo
    writeInfoLine: "=== Babbitt Combinatorial Arrays v0.5.4 ==="
    appendInfoLine: "Preset: ", preset_label$, "   |   Realization: ", realization_name$, if realization = 2 then "   |   Form plan: " + planName$[form_plan] else "" fi
    if hist_note$ <> ""
        appendInfoLine: "Historical model overrides: ", hist_note$
    endif
    if random_seed > 0
        appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
    else
        appendInfoLine: "Random seed: unpredictable"
    endif
    appendInfoLine: ""
    appendInfoLine: "PROVENANCE"
    appendInfoLine: "  [analysis]  opening hexachord 10 6 11 8 7 9, array P RI11 R I11, partition order Z 5 4 X 3 T 9 Y | 7 1 E 6 2 8 W 0, 32 attacks"
    appendInfoLine: "  [analysis]  decoding anchors 5=1100 3=0010 T=0011 8=0110"
    appendInfoLine: "  [inferred]  remaining decoding entries (attack-count groups, lexicographic): 1 2 4 6 7 9 E W X Y"
    appendInfoLine: "  [model]     aggregate segmentation, voice assignment, rearticulation placement, register bands, 4/4 barring"
    if secondary_sets or derivation_cycles > 0
        appendInfoLine: "  [model]     secondary-set cycle and derivation schedule (reading of the later variations, not their score)"
    endif
    if realization = 2
        appendInfoLine: "  [extension] Creative engine: voice distribution, register mapping, dynamics, articulation, space, spectral model, form plan"
    endif
    appendInfoLine: ""
    appendInfoLine: "SELF-TESTS: ", st_pass, " / ", st_total, " passed", if st_fail$ <> "" then "   FAILED: " + st_fail$ else "" fi
    for .i from 1 to st_total
        appendInfoLine: "  ", stRes$[.i]
    endfor
    appendInfoLine: "Rhythm decoding: v0.3.1 read ", v03_wrong, " of 16 opening symbols as wrong patterns; opening halves = ", open_h1, " + ", open_h2, " attacks"
    appendInfoLine: ""
    if hexachord_source = 2
        appendInfoLine: "Type-A ordering ", typeA_pick, " of ", typeA_count, " (content level ", content_level, " before transposition)"
    elsif hexachord_source = 3
        appendInfoLine: "Combinatorial hexachord after ", gen_attempts, " draw(s)"
    endif
    appendInfoLine: "Adjacent ICs of P: ", ic_list$, if all_ic then "(1-5 each once)" else "(not all-IC)" fi
    appendInfoLine: "Segmental trichords of P: ", seg_label$
    appendInfoLine: "Basic array ", op_name$, " with Y = ", y_plain$, " | transposition ", transp, " | inversion axis n = ", ax_n
    for .v from 1 to 4
        .row$ = vName$[.v] + "  " + opPlain$[.v] + tab$
        for .k from 1 to 6
            .row$ = .row$ + string$(line[.v, .k]) + " "
            if .k = 3
                .row$ = .row$ + "| "
            endif
        endfor
        .row$ = .row$ + tab$ + "0" + string$(triCode[.v, 1]) + " / 0" + string$(triCode[.v, 2])
        appendInfoLine: .row$
    endfor
    if secondary_sets
        appendInfoLine: "Secondary array (", sec_op$, " of each line); lines forming 12-tone sets: ", sec_ok, "/4"
        for .v from 1 to 4
            .row$ = vName$[.v] + "  " + arrLab$[2, .v] + tab$
            for .k from 1 to 6
                .row$ = .row$ + string$(arrLine[2, .v, .k]) + " "
            endfor
            appendInfoLine: .row$
        endfor
    endif
    if derivation_cycles > 0
        appendInfoLine: "Derived-set partitions per generator (distinct sets): ", deriv_label$
        appendInfoLine: "Hybrid joins: ", hyb_count, " (kept ", hyb_kept, ", reassigned ", hyb_changed, ", impossible -> fully derived ", hyb_fail, ") ", hyb_note$
    endif
    appendInfoLine: "Aggregate-matrix repetitions: pivot ", n_rep_pivot, ", recurrence ", n_rep_recur, ", undeclared ", n_rep_undecl, if rep_list$ <> "" then "  [" + rep_list$ + "]" else "" fi
    appendInfoLine: ""
    appendInfoLine: "CYCLES"
    for .k from 1 to n_cyc
        .row$ = "c" + string$(.k) + " [" + cycKind$[.k] + "] role " + roleName$[cycRole[.k]] + " | rhythm " + opShort$[cycOp[.k]] + ": "
        for .u from 1 to 16
            .row$ = .row$ + codeChar$[serCode[16 * (.k - 1) + .u]] + " "
            if .u = 8
                .row$ = .row$ + "| "
            endif
        endfor
        .j1 = 2 * .k - 1
        .row$ = .row$ + "| agg sizes " + string$(blkN[.j1]) + "+" + string$(blkN[.j1 + 1])
        if realization = 2
            .row$ = .row$ + " | reg " + string$(cycReg[.k]) + " space " + string$(cycSpace[.k])
        endif
        appendInfoLine: .row$
    endfor
    if n_cyc > 1
        appendInfoLine: "Aggregate schedule:"
        for .j from 1 to n_agg
            .row$ = "  agg " + string$(.j) + tab$ + aggSrc$[.j] + tab$
            for .v from 1 to 4
                .row$ = .row$ + vName$[.v] + " " + string$(aggPc[.j, .v, 1]) + " " + string$(aggPc[.j, .v, 2]) + " " + string$(aggPc[.j, .v, 3]) + " (" + aggLab$[.j, .v] + ")  "
            endfor
            appendInfoLine: .row$
        endfor
    endif
    appendInfoLine: ""
    appendInfoLine: "RESULT PROPERTIES"
    appendInfoLine: "  Attacks ", n_att, " = ", n_new, " entries + ", n_re, " rearticulations (", rearticulation_name$, ")", if seg_clamped > 0 then " | segmentation clamped in " + string$(seg_clamped) + " cycle(s)" else "" fi
    appendInfoLine: "  Aggregates complete ", n_agg_ok, "/", n_agg, " | surface trichords in target (", target_label$, "): ", surf_hits, "/", n_surf
    appendInfoLine: "  Density ", fixed$(m_density, 2), " attacks/s | mean sounding voices ", fixed$(m_poly, 2), " | >=3 voices ", fixed$(m_ge3, 1), " % of time | silence ", fixed$(m_silent, 1), " %"
    appendInfoLine: "  Register MIDI ", min_midi, "-", max_midi, " (mean ", fixed$(m_midi_mean, 1), ", sd ", fixed$(m_midi_sd, 1), ") | voice crossings at ", fixed$(m_cross, 1), " % of polyphonic time | octave clamps ", reg_clamped
    if voice_range_protection
        appendInfoLine: "  Voice range protection ON (", range_src$, "): octave corrections ", rng_moved, " notes + ", rng_re_fit, " rearticulations (S/A/T/B ", rng_moved_v[1], "/", rng_moved_v[2], "/", rng_moved_v[3], "/", rng_moved_v[4], "); octave displacements suppressed ", rng_re_supp, "; pitch classes unchanged"
        if any_struct_reg
            appendInfoLine: "    inversion-axis register: ", rng_axis_moved, " notes moved by octave to fit their voice -> exact registral mirror symmetry lost for those notes (the axis map itself and all pitch-class relations unchanged)"
        endif
    else
        appendInfoLine: "  Voice range protection OFF (instrumental realization: only MIDI 21-108 enforced)"
    endif
    for v from 1 to 4
        appendInfoLine: "    ", vFull$[v], ": generated MIDI ", vMinM[v], "-", vMaxM[v], if voice_range_protection then " | allowed " + string$(vLo[v]) + "-" + string$(vHi[v]) else "" fi
    endfor
    appendInfoLine: "  Dynamics ", fixed$(m_db_min, 1), " .. ", fixed$(m_db_max, 1), " dB (", m_marks, " marks) | articulation l.v./leg./ten./port./stacc./uniform: ", m_art[1], "/", m_art[2], "/", m_art[3], "/", m_art[4], "/", m_art[5], "/", m_art[0]
    appendInfoLine: "  Rhythm: ", m_ioi_n, " distinct within-voice IOIs, IOI entropy ", fixed$(m_ioi_h, 2), " bits"
    if texture = 1
        appendInfoLine: "  Voice distribution (composite stream): grouping ", fixed$(m_clus, 2), ", span overlap ", fixed$(m_ov, 2), ", stagger ", fixed$(m_stag, 2), " | objective ", fixed$(svd_real_mean, 3), " vs random ", fixed$(svd_rand_mean, 3), " (optimizer check only, not a musical measure)"
    else
        appendInfoLine: "  Independent rhythmic voices: each voice on its own partition series (P->O R->R I->C RI->RC); monody fallbacks ", tex_fallback
    endif
    appendInfoLine: "  Spectrum: timbre ", timbre_name$, " | measured centroid per aggregate ", fixed$(cent_min, 0), "-", fixed$(cent_max, 0), " Hz | partials ", n_partials_total, " (dropped ", dropped_partials, ", max ", fixed$(max_partial, 0), " Hz) | halos ", n_halo
    @tempoText: tempo_bpm, 6
    appendInfoLine: "  Composition duration: ", if duration_mode = 2 then "Target mode, requested " + fixed$(target_duration_s, 3) + " s -> tempo " + tempoText.s$ + " bpm (= 16 x " + string$(n_cyc) + " x 60 / " + fixed$(target_duration_s, 3) + ")" else "Tempo mode, " + tempoText.s$ + " bpm" fi
    appendInfoLine: "    musical duration ", fixed$(musical_duration, 6), " s (", 16 * n_cyc, " beats = ", n_cyc, " cycles x 16) | rendered audio ", fixed$(master_duration, 6), " s = musical ", if master_duration >= musical_duration then "+ tail " + fixed$(master_duration - musical_duration, 3) else "- " + fixed$(musical_duration - master_duration, 3) fi, " s (last sound ends at beat ", fixed$(max_end_beat, 2), " + 0.25 beat", if dur_padded > 0 then "; final rests to the structural end: " + fixed$(dur_padded, 3) + " s" else "" fi, ")"
    if duration_mode = 1 and master_duration < musical_duration
        appendInfoLine: "    note: the last cycle ends in rests, so the audio stops ", fixed$(musical_duration - master_duration, 3), " s before the structural end (Tempo mode keeps the v0.5.3 length; Target mode runs to the end)"
    endif
    if arc_on and arc_shape <= 3
        appendInfoLine: "    arc turning point ", fixed$(arc_peak_position, 1), " % of the musical duration = beat ", fixed$(arc_tp_exact, 3), " = ", fixed$(arc_tp_exact * beat, 3), " s"
    endif
    appendInfoLine: "  Output ", if nch = 2 then "stereo" else "mono" fi, " | duration ", fixed$(master_duration, 3), " s | pre-normalization peak ", fixed$(pre_norm_peak, 4), " | peak/RMS ", fixed$(final_peak, 4), " / ", fixed$(final_rms, 6)
    appendInfoLine: "  Spectral groups (S+T / A+B trichords of each aggregate): upper-partial separation ", if spec_ci = undefined then "n/a (no upper partials)" else fixed$(spec_ci, 3) fi, " | upper partials re fundamentals ", if spec_upper_db = undefined then "n/a" else fixed$(spec_upper_db, 1) + " dB" fi, " | group brightness contrast ", if spec_bright = undefined then "n/a" else fixed$(spec_bright, 2) + " oct" fi
    if n_cyc > 1
        appendInfoLine: "  Inter-cycle: mean adjacent feature distance ", fixed$(ic_adj, 2), " | most similar pair c", ic_minA, "/c", ic_minB, " (", fixed$(ic_min, 2), ") | gesture Jaccard adjacent ", fixed$(jac_adj, 3), ", max ", fixed$(jac_max, 3), " (c", jac_maxA, "/c", jac_maxB, ")"
    endif
    .dc$ = ""
    for .k from 1 to n_cyc
        if cycRole[.k] = 3
            .ok$ = if cf_poly[.k] >= 3.0 and cf_dens[.k] >= 3.0 then "met" else "NOT met" fi
            .dc$ = .dc$ + "c" + string$(.k) + " " + fixed$(cf_poly[.k], 2) + " voices / " + fixed$(cf_dens[.k], 2) + " onsets per beat (" + .ok$ + ")  "
        endif
    endfor
    if .dc$ <> ""
        appendInfoLine: "  Texture contract, density (>= 3.0 sounding voices AND >= 3.0 onsets per beat; reported, not structural): ", .dc$
    endif
    appendInfoLine: "  Gesture diversity (reported, not a structural test): ", n_gest, " gestures | nearest-neighbour shape distance ", fixed$(gd_nn, 3), " | near-duplicates (< 0.15) ", fixed$(100 * gd_dup, 1), " %"
    if arc_on
        appendInfoLine: "  Global dynamic arc: ", arc_names$[arc_shape], ", range ", fixed$(arc_range, 1), " dB", if arc_shape <= 3 then ", turning point at " + fixed$(arc_peak_position, 1) + " % (beat " + fixed$(arc_peak_position / 100 * arc_T, 2) + ")" else "" fi, " | one table (", arc_n, " points, every ", fixed$(arc_step, 3), " beat) drives audio gain and MusicXML levels"
        appendInfoLine: "  Measured output (4-beat RMS windows): loudest at beat ", fixed$(arc_meas_tmax, 1), " (", fixed$(100 * arc_meas_tmax / arc_T, 1), " %), softest at beat ", fixed$(arc_meas_tmin, 1), " (", fixed$(100 * arc_meas_tmin / arc_T, 1), " %), spread ", fixed$(arc_meas_max - arc_meas_min, 1), " dB"
        appendInfoLine: "  Measured gain (output / pre-arc mix, quarter-beat windows, ", arc_gain_n, " windows): max deviation from the table ", fixed$(arc_gain_err, 3), " dB; highest at beat ", fixed$(arc_gtmax, 2), ", lowest at beat ", fixed$(arc_gtmin, 2)
        if arc_shape <= 3
            appendInfoLine: "  Turning point: exact beat ", fixed$(arc_tp_exact, 3), " (audio, note levels); hairpin turning point notated at beat ", fixed$(arc_tp_notated, 2), " (nearest 16th, the score's rhythmic grid)"
        else
            appendInfoLine: "  Turning point: not used by ", arc_names$[arc_shape], " (the arc runs from the first to the last beat)"
        endif
    else
        appendInfoLine: "  Global dynamic arc: none"
    endif
    appendInfoLine: "  Fingerprint ", fp
    appendInfoLine: ""
    appendInfoLine: "CYCLE MEASUREMENTS (measured on the realized events / rendered sound)"
    appendInfoLine: "cyc", tab$, "kind", tab$, "role", tab$, "voices", tab$, "simult", tab$, "onsets/b", tab$, "aud.len", tab$, "indep", tab$, "reg.sd", tab$, "dyn.sd", tab$, "centroid", tab$, "compl.", tab$, "specDist", tab$, "featDist", tab$, "Jaccard", tab$, "why"
    for .k from 1 to n_cyc
        appendInfoLine: .k, tab$, cycKind$[.k], tab$, roleName$[cycRole[.k]], tab$, fixed$(cf_poly[.k], 2), tab$, fixed$(cf_sim[.k], 2), tab$, fixed$(cf_dens[.k], 2), tab$, fixed$(cf_dur[.k], 2), tab$, fixed$(cf_indep[.k], 2), tab$, fixed$(cf_regSd[.k], 1), tab$, fixed$(cf_dynSd[.k], 1), tab$, fixed$(cycCent[.k], 0), tab$, if cycCI[.k] = undefined then "n/a" else fixed$(cycCI[.k], 3) fi, tab$, fixed$(cycSpecDist[.k], 3), tab$, fixed$(cycFeatDist[.k], 2), tab$, fixed$(cycJac[.k], 3), tab$, cycWhy$[.k]
    endfor
    if xmlStatus$ <> "skipped"
        appendInfoLine: "  MusicXML ", xmlStatus$, ": ", nXmlLines, " lines, ", xml_measures, " bars x 4 parts", if xmlStringsName$ <> "" then " (Strings """ + xmlStringsName$ + """)" else "" fi, if writeXmlActual then " -> " + xmlPath$ else "" fi
    endif
    if xml_note$ <> ""
        appendInfoLine: "  MusicXML note:", xml_note$
    endif
    appendInfoLine: ""
    appendInfoLine: "a", tab$, "beat", tab$, "agg", tab$, "voice", tab$, "line", tab$, "pc", tab$, "midi", tab$, "writ", tab$, "sound", tab$, "type", tab$, "artic", tab$, "dB", tab$, "pan"
    for .a from 1 to n_att
        .type$ = if isRe[.a] = 1 then "re" else "entry " + string$(atkIdx[.a]) fi
        if atkComplete[.a]
            .type$ = .type$ + " *"
        endif
        appendInfoLine: .a, tab$, fixed$(atkBeat[.a], 2), tab$, atkBlk[.a], tab$, vName$[atkVoice[.a]], tab$, atkLab$[.a], tab$, atkPc[.a], tab$, atkMidi[.a], tab$, fixed$(atkWritB[.a], 2), tab$, fixed$(atkSoundB[.a], 2), tab$, .type$, tab$, artName$[atkArt[.a]] + (if atkAcc[.a] then " >" else "" fi), tab$, fixed$(atkDb[.a], 1), tab$, fixed$(atkPan[.a], 2)
    endfor
endproc

# ==============================================================================
# Procedures: MusicXML writer (globals only; no dotted interpolation)
# ==============================================================================
procedure xmlAdd: .line$
    nXmlLines = nXmlLines + 1
    xmlLine$[nXmlLines] = .line$
    if writeXmlActual
        xml$ = xml$ + .line$ + newline$
    endif
endproc

procedure xmlEscape: .s$
    .out$ = replace$(.s$, "&", "&amp;", 0)
    .out$ = replace$(.out$, "<", "&lt;", 0)
    .out$ = replace$(.out$, ">", "&gt;", 0)
endproc

procedure buildMusicXml
    for .v from 1 to 4
        xm_pmin[.v] = 1000
        xm_pmax[.v] = -1000
    endfor
    xm_step$[0] = "C"
    xm_step$[1] = "C"
    xm_step$[2] = "D"
    xm_step$[3] = "D"
    xm_step$[4] = "E"
    xm_step$[5] = "F"
    xm_step$[6] = "F"
    xm_step$[7] = "G"
    xm_step$[8] = "G"
    xm_step$[9] = "A"
    xm_step$[10] = "A"
    xm_step$[11] = "B"
    for .c from 0 to 11
        xm_alter[.c] = 0
    endfor
    xm_alter[1] = 1
    xm_alter[3] = 1
    xm_alter[6] = 1
    xm_alter[8] = 1
    xm_alter[10] = 1
    xm_stepIdx[0] = 0
    xm_stepIdx[1] = 0
    xm_stepIdx[2] = 1
    xm_stepIdx[3] = 1
    xm_stepIdx[4] = 2
    xm_stepIdx[5] = 3
    xm_stepIdx[6] = 3
    xm_stepIdx[7] = 4
    xm_stepIdx[8] = 4
    xm_stepIdx[9] = 5
    xm_stepIdx[10] = 5
    xm_stepIdx[11] = 6
    for .key from 0 to 79
        xm_accStamp[.key] = -1
        xm_accVal[.key] = 0
    endfor
    xm_val[1] = 16
    xm_val[2] = 12
    xm_val[3] = 8
    xm_val[4] = 6
    xm_val[5] = 4
    xm_val[6] = 3
    xm_val[7] = 2
    xm_val[8] = 1
    xm_type$[16] = "whole"
    xm_type$[12] = "half"
    xm_type$[8] = "half"
    xm_type$[6] = "quarter"
    xm_type$[4] = "quarter"
    xm_type$[3] = "eighth"
    xm_type$[2] = "eighth"
    xm_type$[1] = "16th"
    for .q from 1 to 8
        xm_dot[xm_val[.q]] = 0
    endfor
    xm_dot[12] = 1
    xm_dot[6] = 1
    xm_dot[3] = 1
    xm_dynSound[0] = 36
    xm_dynSound[1] = 54
    xm_dynSound[2] = 71
    xm_dynSound[3] = 89
    xm_dynSound[4] = 106
    xm_dynSound[5] = 124

    .end16 = 0
    for .a from 1 to n_att
        .end16 = max(.end16, round(atkBeat[.a] * 4) + atkWrit16[.a])
    endfor
    xml_measures = max(4 * n_cyc, ceiling(.end16 / 16))
    xm_badMeasures = 0

    @xmlEscape: preset_label$
    .title$ = xmlEscape.out$
    @xmlAdd: "<?xml version=""1.0"" encoding=""UTF-8""?>"
    @xmlAdd: "<!DOCTYPE score-partwise PUBLIC ""-//Recordare//DTD MusicXML 3.1 Partwise//EN"" ""http://www.musicxml.org/dtds/partwise.dtd"">"
    @xmlAdd: "<score-partwise version=""3.1"">"
    # ASCII only: Praat writes non-ASCII text files as UTF-16.
    @xmlAdd: "  <work><work-title>Babbitt&#8217;s Combinatorial Arrays &#8212; " + .title$ + "</work-title></work>"
    @xmlAdd: "  <identification><creator type=""software"">Praat AudioTools - Babbitt Combinatorial Arrays v0.5.4</creator></identification>"
    @xmlAdd: "  <part-list>"
    xm_name$[1] = "Soprano"
    xm_name$[2] = "Alto"
    xm_name$[3] = "Tenor"
    xm_name$[4] = "Bass"
    for .v from 1 to 4
        @xmlAdd: "    <score-part id=""P" + string$(.v) + """><part-name>" + xm_name$[.v] + " (" + arrLab$[1, .v] + ")</part-name><part-abbreviation>" + vName$[.v] + "</part-abbreviation></score-part>"
    endfor
    @xmlAdd: "  </part-list>"

    for .v from 1 to 4
        xm_voice = .v
        xm_meas = 0
        xm_lastDyn = -1
        xm_wNext = 1
        xm_onsets[.v] = 0
        xm_measFill = 0
        for .key from 0 to 79
            xm_accStamp[.key] = -1
        endfor
        @xmlAdd: "  <part id=""P" + string$(.v) + """>"
        .pos = 0
        for .a from 1 to n_att
            if atkVoice[.a] = .v
                .s16 = round(atkBeat[.a] * 4)
                .l16 = atkWrit16[.a]
                if .s16 > .pos
                    @xmSpan: 0, 0, .pos, .s16, .a
                endif
                @xmSpan: 1, atkMidi[.a], .s16, .s16 + .l16, .a
                xm_onsets[.v] = xm_onsets[.v] + 1
                .pos = .s16 + .l16
            endif
        endfor
        if .pos < 16 * xml_measures
            @xmSpan: 0, 0, .pos, 16 * xml_measures, 0
        endif
        if xm_measFill <> 16
            xm_badMeasures = xm_badMeasures + 1
        endif
        if arc_on
            @arcFlushWedges: 1e9
        endif
        @xmlAdd: "    </measure>"
        @xmlAdd: "  </part>"
    endfor
    @xmlAdd: "</score-partwise>"
endproc

procedure xmOpenMeasure
    if xm_meas > 0 and xm_measFill <> 16
        xm_badMeasures = xm_badMeasures + 1
    endif
    xm_meas = xm_meas + 1
    xm_measFill = 0
    @xmlAdd: "    <measure number=""" + string$(xm_meas) + """>"
    if xm_meas = 1
        if vc[xm_voice] >= 60
            .clef$ = "<clef><sign>G</sign><line>2</line></clef>"
        else
            .clef$ = "<clef><sign>F</sign><line>4</line></clef>"
        endif
        @xmlAdd: "      <attributes><divisions>4</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time>" + .clef$ + "</attributes>"
        if xm_voice = 1 and arc_on
            @xmlAdd: "      <direction placement=""above""><direction-type><words>Global dynamic arc: " + arc_names$[arc_shape] + ", " + fixed$(arc_range, 0) + " dB" + (if arc_shape <= 3 then ", turning point at " + fixed$(arc_peak_position, 0) + " percent" else "" fi) + "</words></direction-type></direction>"
        endif
        if xm_voice = 1
            @tempoText: tempo_bpm, 2
            .tShow$ = tempoText.s$
            @tempoText: tempo_bpm, 8
            @xmlAdd: "      <direction placement=""above""><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>" + .tShow$ + "</per-minute></metronome></direction-type><sound tempo=""" + tempoText.s$ + """/></direction>"
        endif
    endif
    if ((xm_meas - 1) mod 4) = 0
        .k = (xm_meas - 1) / 4 + 1
        if .k <= n_cyc
            .lab$ = aggLab$[2 * .k - 1, xm_voice]
            if xm_voice = 1
                .lab$ = "c" + string$(.k) + " " + cycKind$[.k] + " &#8212; " + .lab$
                if realization = 2
                    .lab$ = .lab$ + " (" + roleName$[cycRole[.k]] + ")"
                endif
            endif
            @xmlAdd: "      <direction placement=""above""><direction-type><words>" + .lab$ + "</words></direction-type></direction>"
        endif
    endif
endproc

procedure xmEnsureMeasure: .pos
    .need = floor(.pos / 16) + 1
    while xm_meas < .need
        if xm_meas > 0 and arc_on
            @arcFlushWedges: xm_meas * 16
        endif
        if xm_meas > 0
            @xmlAdd: "    </measure>"
        endif
        @xmOpenMeasure
    endwhile
endproc

# A note or rest from .from to .to (sixteenths), split at barlines and into
# single note values; note pieces are tied. .a = event index (0 for rests).
procedure xmSpan: .isNote, .midi, .from, .to, .a
    .cur = .from
    while .cur < .to
        @xmEnsureMeasure: .cur
        if arc_on
            @arcFlushWedges: .cur
        endif
        .barEnd = (floor(.cur / 16) + 1) * 16
        .rem = min(.to, .barEnd) - .cur
        .chunk = 0
        for .q from 1 to 8
            if .chunk = 0 and xm_val[.q] <= .rem
                .chunk = xm_val[.q]
            endif
        endfor
        .tStop = 0
        .tStart = 0
        .first = 0
        .last = 0
        if .isNote
            xm_pmin[xm_voice] = min(xm_pmin[xm_voice], .midi)
            xm_pmax[xm_voice] = max(xm_pmax[xm_voice], .midi)
            .tStop = .cur > .from
            .tStart = .cur + .chunk < .to
            .first = .cur = .from
            .last = .cur + .chunk >= .to
            .dynIdx = atkDyn[.a]
            if arc_on
                @arcEventLevel: .a
                .dynIdx = arcEventLevel.mark
            endif
            if .first and (dynamics = 2 or arc_on)
                if .dynIdx <> xm_lastDyn
                    @xmlAdd: "      <direction placement=""below""><direction-type><dynamics><" + dynMark$[.dynIdx] + "/></dynamics></direction-type><sound dynamics=""" + string$(xm_dynSound[.dynIdx]) + """/></direction>"
                    xm_lastDyn = .dynIdx
                endif
            endif
        endif
        @xmNote: .isNote, .midi, .chunk, .tStart, .tStop, .first, .last, .a
        xm_measFill = xm_measFill + .chunk
        .cur = .cur + .chunk
    endwhile
endproc

procedure xmNote: .isNote, .midi, .dur, .tStart, .tStop, .first, .last, .a
    if arc_on and .isNote
        @arcEventLevel: .a
        @xmlAdd: "      <note dynamics=""" + fixed$(arcEventLevel.pct, 1) + """>"
    else
        @xmlAdd: "      <note>"
    endif
    if .isNote
        .pc = .midi mod 12
        .line$ = "        <pitch><step>" + xm_step$[.pc] + "</step>"
        if xm_alter[.pc] <> 0
            .line$ = .line$ + "<alter>1</alter>"
        endif
        .line$ = .line$ + "<octave>" + string$(floor(.midi / 12) - 1) + "</octave></pitch>"
    else
        .line$ = "        <rest/>"
    endif
    @xmlAdd: .line$
    .line$ = "        <duration>" + string$(.dur) + "</duration>"
    if .tStop
        .line$ = .line$ + "<tie type=""stop""/>"
    endif
    if .tStart
        .line$ = .line$ + "<tie type=""start""/>"
    endif
    .line$ = .line$ + "<voice>1</voice><type>" + xm_type$[.dur] + "</type>"
    if xm_dot[.dur] = 1
        .line$ = .line$ + "<dot/>"
    endif
    if .isNote and .tStop = 0
        .key = xm_stepIdx[.pc] * 10 + floor(.midi / 12)
        .prev = 0
        if xm_accStamp[.key] = xm_meas
            .prev = xm_accVal[.key]
        endif
        if xm_alter[.pc] <> .prev
            if xm_alter[.pc] = 1
                .line$ = .line$ + "<accidental>sharp</accidental>"
            else
                .line$ = .line$ + "<accidental>natural</accidental>"
            endif
        endif
        xm_accStamp[.key] = xm_meas
        xm_accVal[.key] = xm_alter[.pc]
    endif
    if .isNote and .first
        if isRe[.a] = 1
            .line$ = .line$ + "<notehead parentheses=""yes"">normal</notehead>"
        endif
    endif
    @xmlAdd: .line$
    .not$ = ""
    if .tStop
        .not$ = .not$ + "<tied type=""stop""/>"
    endif
    if .tStart
        .not$ = .not$ + "<tied type=""start""/>"
    endif
    if .isNote and .last
        if atkArt[.a] = 1
            .not$ = .not$ + "<tied type=""let-ring""/>"
        endif
    endif
    if .isNote and .first
        .ar$ = ""
        if atkAcc[.a]
            .ar$ = .ar$ + "<accent/>"
        endif
        if atkArt[.a] = 5
            .ar$ = .ar$ + "<staccato/>"
        elsif atkArt[.a] = 4
            .ar$ = .ar$ + "<detached-legato/>"
        elsif atkArt[.a] = 3
            .ar$ = .ar$ + "<tenuto/>"
        endif
        if .ar$ <> ""
            .not$ = .not$ + "<articulations>" + .ar$ + "</articulations>"
        endif
    endif
    if .not$ <> ""
        @xmlAdd: "        <notations>" + .not$ + "</notations>"
    endif
    @xmlAdd: "      </note>"
endproc

# ==============================================================================
# Procedures: drawing frame helpers
# Font is set BEFORE the viewport; every Text re-selects the panel first.
# ==============================================================================
procedure frame
    Font size: pf_font
    Select inner viewport: pf_l, pf_r, pf_b, pf_t
    Axes: pf_x0, pf_x1, pf_y0, pf_y1
endproc

# requested arc (table) vs measured gain and smoothed output RMS
procedure drawArcPanel: .head, .top, .bot
    .x1 = arc_T
    .y0 = -6 * ceiling((arc_range + 12) / 6)
    .y1 = 3
    Colour: "Black"
    @strip: 0.6, 7.7, .head, .head + 0.18, 9, 0, "left", "##I  Global dynamic arc## — " + arc_names$[arc_shape] + ", " + fixed$(arc_range, 0) + " dB: requested (table) vs measured gain and smoothed output RMS (dB)"
    @setPanel: 0.6, 7.7, .top, .bot, 0, .x1, .y0, .y1, 6
    Colour: "{0.86, 0.86, 0.86}"
    .yy = .y0 + 6
    while .yy < .y1
        Draw line: 0, .yy, .x1, .yy
        .yy = .yy + 6
    endwhile
    if arc_shape <= 3
        Colour: "{0.70, 0.15, 0.15}"
        Line width: 1
        Draw line: arc_tp_notated, .y0, arc_tp_notated, .y1
    endif
    # smoothed output RMS (material + arc), grey
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    for .i from 2 to arc_nb
        .a = max(.y0, arcSmoothDb[.i - 1])
        .b = max(.y0, arcSmoothDb[.i])
        Draw line: (.i - 1.5) * arc_wb, .a, (.i - 0.5) * arc_wb, .b
    endfor
    # requested arc from the shared table, blue (wide, underneath)
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 4
    .nb = round(.x1 / arc_step) + 1
    for .i from 2 to min(.nb, arc_n)
        Draw line: (.i - 2) * arc_step, arcDbT[.i - 1], (.i - 1) * arc_step, arcDbT[.i]
    endfor
    Line width: 1
    # measured gain, every 4th quarter-beat window (one per beat), orange dots
    for .i from 1 to arc_nb
        if arcGainOk[.i] and (.i mod 4) = 2
            if arcGainW[.i] >= .y0
                Paint circle (mm): "{0.85, 0.40, 0.15}", (.i - 0.5) * arc_wb, arcGainW[.i], 0.7
            endif
        endif
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    Marks left every: 1, 6, "yes", "yes", "no"
    .tick = if .x1 <= 32 then 4 else if .x1 <= 64 then 8 else 16 fi fi
    Marks bottom every: 1, .tick, "yes", "yes", "no"
    pf_font = 6
    Colour: "{0.20, 0.40, 0.80}"
    @label: .x1 * 0.02, "left", .y0 + 0.16 * (.y1 - .y0), "half", "requested arc (table)"
    Colour: "{0.85, 0.40, 0.15}"
    @label: .x1 * 0.22, "left", .y0 + 0.16 * (.y1 - .y0), "half", "measured gain (out / pre-arc, 1 dot per beat), max dev. " + fixed$(arc_gain_err, 2) + " dB"
    Colour: "{0.45, 0.45, 0.45}"
    @label: .x1 * 0.58, "left", .y0 + 0.16 * (.y1 - .y0), "half", "output RMS, 4-beat smoothed (material + arc)"
    if arc_shape <= 3
        Colour: "{0.70, 0.15, 0.15}"
        .tpy = if arc_shape = 2 then .y0 + 0.04 * (.y1 - .y0) else .y1 - 0.04 * (.y1 - .y0) fi
        .tpv$ = if arc_shape = 2 then "bottom" else "top" fi
        @label: arc_tp_notated + .x1 * 0.006, "left", .tpy, .tpv$, "turning point, beat " + fixed$(arc_tp_exact, 2) + " = " + fixed$(arc_tp_exact * beat, 2) + " s"
    endif
    Colour: "Black"
endproc

procedure setPanel: .l, .r, .b, .t, .x0, .x1, .y0, .y1, .font
    pf_l = .l
    pf_r = .r
    pf_b = .b
    pf_t = .t
    pf_x0 = .x0
    pf_x1 = .x1
    pf_y0 = .y0
    pf_y1 = .y1
    pf_font = .font
    @frame
endproc

procedure label: .x, .h$, .y, .v$, .s$
    @frame
    Text: .x, .h$, .y, .v$, .s$
endproc

procedure strip: .l, .r, .b, .t, .size, .x, .h$, .s$
    @setPanel: .l, .r, .b, .t, 0, 1, 0, 1, .size
    Text: .x, .h$, 0.5, "half", .s$
endproc


# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    col$[1] = "{0.20, 0.40, 0.80}"
    col$[2] = "{0.85, 0.40, 0.15}"
    col$[3] = "{0.15, 0.58, 0.35}"
    col$[4] = "{0.55, 0.25, 0.65}"
    tint$[1] = "{0.62, 0.72, 0.92}"
    tint$[2] = "{0.96, 0.74, 0.60}"
    tint$[3] = "{0.62, 0.84, 0.70}"
    tint$[4] = "{0.80, 0.68, 0.88}"
    genTint$[1] = "{0.90, 0.85, 0.97}"
    genTint$[2] = "{0.84, 0.94, 0.89}"
    genTint$[3] = "{0.98, 0.87, 0.84}"
    genTint$[4] = "{0.95, 0.93, 0.78}"
    .agg1$ = "{0.95, 0.96, 0.99}"
    .agg2$ = "{0.99, 0.97, 0.93}"
    .sec1$ = "{0.88, 0.96, 0.97}"
    .sec2$ = "{0.97, 0.91, 0.95}"
    .bnd$ = "{0.70, 0.15, 0.15}"
    .grid$ = "{0.86, 0.86, 0.86}"
    .multi = n_cyc > 1
    .xMax = ceiling((max_end_beat + 0.25) * 2) / 2
    .xPerInch = .xMax / 7.1
    for .j from 1 to n_agg
        if aggGen[.j] > 0
            aggTint$[.j] = genTint$[aggGenIdx[.j]]
        elsif aggArr[.j] = 2
            aggTint$[.j] = if (.j mod 2) = 1 then .sec1$ else .sec2$ fi
        elsif (.j mod 2) = 1
            aggTint$[.j] = .agg1$
        else
            aggTint$[.j] = .agg2$
        endif
        .tx0[.j] = if .j = 1 then 0 else blkStart[.j] fi
    endfor
    for .j from 1 to n_agg
        .tx1[.j] = if .j = n_agg then .xMax else blkStart[.j + 1] fi
    endfor
    if .xMax <= 20
        .tick = 2
    elsif .xMax <= 40
        .tick = 4
    elsif .xMax <= 80
        .tick = 8
    else
        .tick = 16
    endif
    if associative_target = 1
        .tgtShort$ = "015 012"
    elsif associative_target = 2
        .tgtShort$ = "025 014"
    elsif associative_target = 3
        .tgtShort$ = "segmental"
    else
        .tgtShort$ = "generator"
    endif

    # Vertical layout (inches)
    if .multi
        .rows = n_agg + 1
        .rowH = 0.15
    else
        .rows = 5
        .rowH = 0.216
    endif
    .tabTop = 5.42
    .tabBot = .tabTop + .rows * .rowH
    .histBot = .tabTop + max(0.80, .rows * .rowH - 0.28)
    .eHead = .tabBot + 0.16
    .eTop = .eHead + 0.24
    .eBot = .eTop + 0.85
    .fHead = .eBot + 0.52
    .fTop = .fHead + 0.24
    .fBot = .fTop + 0.75
    .hHead = .fBot + 0.20
    .hTop = .hHead + 0.24
    .hBot = .hTop + 0.85
    .gOn = timbre = 5
    .eRows = 4 * n_cyc
    if .gOn
        .gHead = .hBot + 0.42
        .gTop = .gHead + 0.24
        .gH = min(1.8, max(0.56, .eRows * 0.06))
        .gBot = .gTop + .gH
        .qcTop = .gBot + 0.36
    else
        .qcTop = .hBot + 0.42
    endif
    if arc_on
        .aHead = .qcTop - 0.04
        .aTop = .aHead + 0.24
        .aBot = .aTop + 1.0
        .qcTop = .aBot + 0.42
    endif
    .qcBot = .qcTop + 2.5
    .canvasH = .qcBot + 0.10
    .plan$ = ""
    for .k from 1 to n_cyc
        .sep$ = if .k = 1 then "" else " > " fi
        .plan$ = .plan$ + .sep$ + cycKind$[.k]
    endfor

    Erase all
    Line width: 1
    Colour: "Black"

    # ---------------- Title / process ----------------
    @strip: 0.6, 7.7, 0.08, 0.38, 14, 0.5, "centre", "##Babbitt’s Combinatorial Arrays## — " + preset_label$
    Colour: "{0.30, 0.30, 0.30}"
    .proc$ = realization_name$ + "   |   hexachord  ->  " + op_name$ + " array"
    if secondary_sets
        .proc$ = .proc$ + "  ->  secondary sets"
    endif
    if derivation_cycles > 0
        .proc$ = .proc$ + "  ->  derived sets"
    endif
    .proc$ = .proc$ + "   |   " + string$(n_cyc) + " x 16 partitions  ->  " + string$(n_att) + " time points   |   " + timbre_name$
    if realization = 2
        .proc$ = .proc$ + "   |   plan " + planName$[form_plan]
    endif
    @strip: 0.6, 7.7, 0.40, 0.60, 7, 0.5, "centre", .proc$
    Colour: "Black"
    @strip: 0.6, 7.7, 0.62, 0.80, 9, 0, "left", "##A  Event score## (piano roll: bar = sounding length, thickness = dynamic, dot = entry, ring = rearticulation)"

    # ---------------- A: piano roll ----------------
    .yMin = min_midi - 2
    .yMax = max_midi + 2
    @setPanel: 0.6, 7.7, 1.00, 3.30, 0, .xMax, .yMin, .yMax, 7
    for .j from 1 to n_agg
        Paint rectangle: aggTint$[.j], .tx0[.j], .tx1[.j], .yMin, .yMax
    endfor
    Colour: .grid$
    Line width: 0.8
    for .mm from ceiling(.yMin) to floor(.yMax)
        if (.mm mod 12) = 0
            Draw line: 0, .mm, .xMax, .mm
        endif
    endfor
    Colour: "{0.60, 0.60, 0.60}"
    Line width: 1.2
    for .k from 2 to n_cyc
        Draw line: 16 * (.k - 1), .yMin, 16 * (.k - 1), .yMax
    endfor
    if .multi = 0
        Line width: 0.8
        Colour: .grid$
        for .u from 1 to 15
            Draw line: .u, .yMin, .u, .yMin + 0.6
        endfor
    endif
    # halos
    for .i from 1 to n_halo
        .v = haloVoice[.i]
        Paint rectangle: tint$[.v], haloBeat[.i], haloBeat[.i] + haloDurBeat[.i], haloMidi[.i] - 0.45, haloMidi[.i] - 0.2
    endfor
    # sounding bars
    for .a from 1 to n_att
        .v = atkVoice[.a]
        Line width: 1 + 3 * (atkDb[.a] + 24) / 36
        Colour: tint$[.v]
        Draw line: atkBeat[.a], atkMidi[.a], atkBeat[.a] + atkSoundB[.a], atkMidi[.a]
    endfor
    # attacks
    .dot = if .multi then 0.7 else 1.1 fi
    Line width: 1.0
    for .a from 1 to n_att
        .v = atkVoice[.a]
        .ds = .dot * (0.7 + 0.6 * (atkDb[.a] + 24) / 36)
        if isRe[.a] = 0
            Paint circle (mm): col$[.v], atkBeat[.a], atkMidi[.a], .ds
        else
            Paint circle (mm): "White", atkBeat[.a], atkMidi[.a], .ds
            Colour: col$[.v]
            Draw circle (mm): atkBeat[.a], atkMidi[.a], .ds
        endif
        if atkComplete[.a]
            Colour: "Black"
            Draw circle (mm): atkBeat[.a], atkMidi[.a], .ds + 0.45
        endif
    endfor
    # aggregate boundaries
    Colour: .bnd$
    Line width: if .multi then 1.0 else 1.5 fi
    Dashed line
    for .j from 2 to n_agg
        Draw line: blkStart[.j], .yMin, blkStart[.j], .yMax
    endfor
    Solid line
    Line width: 1
    pf_font = 6
    if .multi = 0
        Colour: "{0.25, 0.25, 0.25}"
        for .a from 1 to n_att
            if isRe[.a] = 0
                Colour: col$[atkVoice[.a]]
                @label: atkBeat[.a] + 0.04 * .xPerInch, "left", atkMidi[.a] + 0.25, "bottom", string$(atkPc[.a])
            endif
        endfor
        Colour: .bnd$
        @label: blkStart[2] - 0.04 * .xPerInch, "right", .yMax, "bottom", "aggregate 1 (" + string$(blkN[1]) + " attacks)"
        @label: blkStart[2] + 0.04 * .xPerInch, "left", .yMax, "bottom", "aggregate 2 (" + string$(blkN[2]) + " attacks)"
    else
        Colour: "{0.25, 0.25, 0.25}"
        for .k from 1 to n_cyc
            .cl$ = "c" + string$(.k) + " " + cycKind$[.k]
            if realization = 2
                .cl$ = .cl$ + " · " + roleName$[cycRole[.k]]
            endif
            @label: 16 * (.k - 1) + 8, "centre", .yMax, "bottom", .cl$
        endfor
    endif
    pf_font = 7
    Colour: "Black"
    @frame
    Draw inner box
    Marks bottom every: 1, .tick, "yes", "yes", "no"
    for .mm from ceiling(.yMin) to floor(.yMax)
        if (.mm mod 12) = 0
            One mark left: .mm, "no", "yes", "no", "C" + string$(.mm / 12 - 1)
        endif
    endfor
    @tempoText: tempo_bpm, 2
    Text bottom: "yes", "Quarter-note units  (quarter = " + tempoText.s$ + " bpm" + (if duration_mode = 2 then ", from target " + fixed$(target_duration_s, 1) + " s" else "" fi) + ")"
    # voice legend in the left margin
    pf_font = 7
    for .v from 1 to 4
        Colour: col$[.v]
        @label: -0.42 * .xPerInch, "left", .yMax - (.v - 0.5) * (.yMax - .yMin) / 8, "half", "##" + vName$[.v] + "##"
    endfor
    Colour: "{0.30, 0.30, 0.30}"
    .leg$ = "dot = entry  |  ring = rearticulation  |  black ring = aggregate completed  |  dashed = aggregate  |  grey = cycle  |  S blue  A orange  T green  B purple"
    @strip: 0.6, 7.7, 3.80, 3.96, 6, 0.5, "centre", .leg$

    # ---------------- B ----------------
    Colour: "Black"
    if .multi = 0
        @strip: 0.6, 7.7, 4.02, 4.20, 9, 0, "left", "##B  Time-point partitions## — " + rhythm_name$ + " (symbol = rhythm type; bits = its four sixteenths)"
        @setPanel: 0.6, 7.7, 4.26, 4.94, 0, .xMax, 0, 1, 7
        for .u from 1 to 16
            Paint rectangle: "{0.93, 0.93, 0.93}", .u - 1 - 0.09, .u - 1 + 0.84, 0.46, 0.94
        endfor
        Colour: "{0.60, 0.60, 0.60}"
        Line width: 1.2
        Draw line: 8 - 0.125, 0, 8 - 0.125, 1
        for .u from 1 to 16
            for .p from 0 to 3
                .bit = floor(ser[.u] / 2 ^ (3 - .p)) mod 2
                if .bit = 0
                    Paint circle (mm): "{0.72, 0.72, 0.72}", .u - 1 + .p / 4, 0.70, 0.5
                endif
            endfor
        endfor
        Line width: 1.3
        for .a from 1 to n_att
            .v = atkVoice[.a]
            if isRe[.a] = 0
                Paint circle (mm): col$[.v], atkBeat[.a], 0.70, 1.3
            else
                Paint circle (mm): "White", atkBeat[.a], 0.70, 1.3
                Colour: col$[.v]
                Draw circle (mm): atkBeat[.a], 0.70, 1.3
            endif
        endfor
        Colour: .bnd$
        Line width: 1.5
        Dashed line
        Draw line: blkStart[2], 0, blkStart[2], 1
        Solid line
        Line width: 1
        for .u from 1 to 16
            pf_font = 9
            Colour: "Black"
            @label: .u - 1 + 0.375, "centre", 0.27, "half", "##" + codeChar$[serCode[.u]] + "##"
            pf_font = 6
            Colour: "{0.40, 0.40, 0.40}"
            @label: .u - 1 + 0.375, "centre", 0.08, "half", mbits$[ser[.u]]
        endfor
    else
        @strip: 0.6, 7.7, 4.02, 4.20, 9, 0, "left", "##B  Array plan## — " + .plan$ + "   |   rhythm: " + rhythm_name$
        @setPanel: 0.6, 7.7, 4.26, 4.94, 0, .xMax, 0, 1, 7
        for .j from 1 to n_agg
            Paint rectangle: aggTint$[.j], .tx0[.j], .tx1[.j], 0.52, 0.97
        endfor
        Paint rectangle: "{0.94, 0.94, 0.94}", 0, .xMax, 0, 0.48
        Colour: .bnd$
        Line width: 1.0
        Dashed line
        for .j from 2 to n_agg
            Draw line: blkStart[.j], 0.52, blkStart[.j], 0.97
        endfor
        Solid line
        Colour: "{0.60, 0.60, 0.60}"
        Line width: 1.2
        for .k from 2 to n_cyc
            Draw line: 16 * (.k - 1), 0, 16 * (.k - 1), 1
        endfor
        Line width: 1
        pf_font = 6
        Colour: "Black"
        for .j from 1 to n_agg
            @label: 0.5 * (.tx0[.j] + .tx1[.j]), "centre", 0.745, "half", "##" + aggSrcShort$[.j] + "## (" + string$(blkN[.j]) + ")"
        endfor
        for .k from 1 to n_cyc
            .codes$ = ""
            for .u from 1 to 16
                .codes$ = .codes$ + codeChar$[serCode[16 * (.k - 1) + .u]]
                if .u = 8
                    .codes$ = .codes$ + if n_cyc > 5 then "|" else " | " fi
                endif
            endfor
            pf_font = if n_cyc > 5 then 5 else 6 fi
            Colour: "{0.20, 0.20, 0.20}"
            @label: 16 * (.k - 1) + 8, "centre", 0.34, "half", .codes$
            Colour: "{0.45, 0.45, 0.45}"
            @label: 16 * (.k - 1) + 8, "centre", 0.12, "half", "c" + string$(.k) + "  " + opName$[cycOp[.k]]
        endfor
    endif
    pf_font = 7
    Colour: "Black"
    @frame
    Draw inner box

    # ---------------- C: array / derivation table ----------------
    if .multi = 0
        @strip: 0.6, 4.0, 5.14, 5.32, 9, 0, "left", "##C  Four-line array## (columns 1-3 / 4-6 = aggregates)"
    else
        @strip: 0.6, 4.0, 5.14, 5.32, 9, 0, "left", "##C  Aggregate derivation## (one row per aggregate)"
    endif
    @strip: 4.55, 7.7, 5.14, 5.32, 9, 0, "left", "##D  Surface trichords## (orange = target classes)"

    if .multi = 0
        @setPanel: 0.6, 4.0, .tabTop, .tabBot, 0, 10, 0, 5, 8
        Paint rectangle: .agg1$, 2.2, 4.9, 0, 4
        Paint rectangle: .agg2$, 4.9, 7.6, 0, 4
        Paint rectangle: "{0.90, 0.90, 0.90}", 0, 10, 4, 5
        Colour: "{0.75, 0.75, 0.75}"
        Line width: 0.8
        for .r from 1 to 3
            Draw line: 0, .r, 10, .r
        endfor
        Draw line: 2.2, 0, 2.2, 5
        Draw line: 7.6, 0, 7.6, 5
        Colour: .bnd$
        Line width: 1.5
        Dashed line
        Draw line: 4.9, 0, 4.9, 5
        Solid line
        Line width: 1
        pf_font = 7
        Colour: "{0.25, 0.25, 0.25}"
        @label: 1.1, "centre", 4.5, "half", "line"
        for .k from 1 to 6
            @label: 2.2 + (.k - 0.5) * 0.9, "centre", 4.5, "half", string$(.k)
        endfor
        @label: 8.8, "centre", 4.5, "half", "trichords"
        for .v from 1 to 4
            .yr = 4 - .v + 0.5
            pf_font = 8
            Colour: col$[.v]
            @label: 0.25, "left", .yr, "half", "##" + vName$[.v] + "##   " + opLab$[.v]
            for .k from 1 to 6
                @label: 2.2 + (.k - 0.5) * 0.9, "centre", .yr, "half", string$(line[.v, .k])
            endfor
            pf_font = 7
            Colour: "{0.25, 0.25, 0.25}"
            @label: 8.8, "centre", .yr, "half", "0" + string$(triCode[.v, 1]) + "  /  0" + string$(triCode[.v, 2])
        endfor
    else
        .nR = .rows
        @setPanel: 0.6, 4.0, .tabTop, .tabBot, 0, 10, 0, .nR, 6
        Paint rectangle: "{0.90, 0.90, 0.90}", 0, 10, .nR - 1, .nR
        for .j from 1 to n_agg
            Paint rectangle: aggTint$[.j], 0, 10, .nR - 1 - .j, .nR - .j
        endfor
        Colour: "{0.75, 0.75, 0.75}"
        Line width: 0.8
        for .j from 1 to n_agg - 1
            Draw line: 0, .nR - 1 - .j, 10, .nR - 1 - .j
        endfor
        Draw line: 0.7, 0, 0.7, .nR
        Draw line: 2.2, 0, 2.2, .nR
        Draw line: 4.15, 0, 4.15, .nR
        Draw line: 6.1, 0, 6.1, .nR
        Draw line: 8.05, 0, 8.05, .nR
        Colour: "{0.45, 0.45, 0.45}"
        Line width: 1.2
        for .k from 1 to n_cyc - 1
            Draw line: 0, .nR - 1 - 2 * .k, 10, .nR - 1 - 2 * .k
        endfor
        Line width: 1
        pf_font = 6
        Colour: "{0.25, 0.25, 0.25}"
        @label: 0.35, "centre", .nR - 0.5, "half", "agg"
        @label: 1.45, "centre", .nR - 0.5, "half", "source"
        for .v from 1 to 4
            Colour: col$[.v]
            @label: 2.2 + (.v - 0.5) * 1.95, "centre", .nR - 0.5, "half", "##" + vName$[.v] + "##"
        endfor
        for .j from 1 to n_agg
            .yr = .nR - .j - 0.5
            Colour: "{0.25, 0.25, 0.25}"
            @label: 0.35, "centre", .yr, "half", string$(.j)
            @label: 1.45, "centre", .yr, "half", aggSrcShort$[.j]
            for .v from 1 to 4
                Colour: col$[.v]
                @label: 2.2 + (.v - 0.5) * 1.95, "centre", .yr, "half", string$(aggPc[.j, .v, 1]) + " " + string$(aggPc[.j, .v, 2]) + " " + string$(aggPc[.j, .v, 3]) + "   " + aggLab$[.j, .v]
            endfor
        endfor
    endif
    pf_font = 7
    Colour: "Black"
    @frame
    Draw inner box

    # ---------------- D: surface-trichord histogram ----------------
    .maxCount = 1
    for .k from 1 to n_cls
        .maxCount = max(.maxCount, surfCount[clsCode[.k]])
    endfor
    if .maxCount <= 5
        .step = 1
    elsif .maxCount <= 12
        .step = 2
    elsif .maxCount <= 30
        .step = 5
    else
        .step = 10
    endif
    .yTop = ceiling(.maxCount * 1.15 / .step) * .step
    @setPanel: 4.55, 7.7, .tabTop, .histBot, 0.4, 12.6, 0, .yTop, 6
    for .k from 1 to n_cls
        .cnt = surfCount[clsCode[.k]]
        if .cnt > 0
            if anyTarget[clsCode[.k]] = 1
                .bc$ = "{0.85, 0.40, 0.15}"
            else
                .bc$ = "{0.62, 0.62, 0.62}"
            endif
            Paint rectangle: .bc$, .k - 0.32, .k + 0.32, 0, .cnt
        endif
    endfor
    for .k from 1 to n_cls
        .cnt = surfCount[clsCode[.k]]
        if .cnt > 0
            Colour: "{0.25, 0.25, 0.25}"
            @label: .k, "centre", .cnt, "bottom", string$(.cnt)
        endif
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    for .k from 1 to n_cls
        One mark bottom: .k, "no", "yes", "no", "0" + string$(clsCode[.k])
    endfor
    Marks left every: 1, .step, "yes", "yes", "no"

    # ---------------- E: space / dynamics ----------------
    Colour: "Black"
    .spaceList$ = ""
    for .k from 1 to n_cyc
        .sn = cycSpace[.k]
        .s$ = if .sn = 1 then "fixed" else if .sn = 2 then "complementary" else if .sn = 3 then "symmetric" else if .sn = 4 then "exchange" else "crossing" fi fi fi fi
        .spaceList$ = .spaceList$ + (if .k = 1 then "" else ", " fi)
        .spaceList$ = .spaceList$ + .s$
    endfor
    if nch = 2
        @strip: 0.6, 7.7, .eHead, .eHead + 0.18, 9, 0, "left", "##E  Space## — pan per event (dot size = dynamic); strategy per cycle: " + .spaceList$
        .ey0 = -1.1
        .ey1 = 1.1
    else
        @strip: 0.6, 7.7, .eHead, .eHead + 0.18, 9, 0, "left", "##E  Dynamics## — level per event in dB (mono output)"
        .ey0 = -26
        .ey1 = 14
    endif
    @setPanel: 0.6, 7.7, .eTop, .eBot, 0, .xMax, .ey0, .ey1, 6
    for .j from 1 to n_agg
        Paint rectangle: aggTint$[.j], .tx0[.j], .tx1[.j], .ey0, .ey1
    endfor
    Colour: "{0.70, 0.70, 0.70}"
    Dotted line
    if nch = 2
        Draw line: 0, 0, .xMax, 0
    else
        for .d from 0 to 5
            Draw line: 0, (.d - 3) * 6, .xMax, (.d - 3) * 6
        endfor
    endif
    Solid line
    Colour: .bnd$
    Dashed line
    for .j from 2 to n_agg
        Draw line: blkStart[.j], .ey0, blkStart[.j], .ey1
    endfor
    Solid line
    for .a from 1 to n_att
        .v = atkVoice[.a]
        .yv = if nch = 2 then atkPan[.a] else atkDb[.a] fi
        .ds = 0.35 + 0.75 * (atkDb[.a] + 24) / 36
        if isRe[.a] = 0
            Paint circle (mm): col$[.v], atkBeat[.a], .yv, .ds
        else
            Paint circle (mm): "White", atkBeat[.a], .yv, .ds
            Colour: col$[.v]
            Draw circle (mm): atkBeat[.a], .yv, .ds
        endif
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    Marks bottom every: 1, .tick, "yes", "yes", "no"
    if nch = 2
        One mark left: -1, "no", "yes", "no", "L"
        One mark left: 0, "no", "yes", "no", "C"
        One mark left: 1, "no", "yes", "no", "R"
    else
        for .d from 0 to 5
            One mark left: (.d - 3) * 6, "no", "yes", "no", dynMark$[.d]
        endfor
    endif

    # ---------------- F: measured spectral centroid ----------------
    Colour: "Black"
    @strip: 0.6, 7.7, .fHead, .fHead + 0.18, 9, 0, "left", "##F  Measured spectral centroid per aggregate## (Hz, from the rendered sound)"
    .cTop = max(500, ceiling(cent_max * 1.2 / 500) * 500)
    @setPanel: 0.6, 7.7, .fTop, .fBot, 0, .xMax, 0, .cTop, 6
    for .j from 1 to n_agg
        if blkCent[.j] <> undefined
            Paint rectangle: aggTint$[.j], .tx0[.j], .tx1[.j], 0, .cTop
            Paint rectangle: "{0.45, 0.55, 0.70}", .tx0[.j] + 0.15 * (.tx1[.j] - .tx0[.j]), .tx1[.j] - 0.15 * (.tx1[.j] - .tx0[.j]), 0, blkCent[.j]
        endif
    endfor
    for .j from 1 to n_agg
        if blkCent[.j] <> undefined
            Colour: "{0.20, 0.20, 0.20}"
            @label: 0.5 * (.tx0[.j] + .tx1[.j]), "centre", blkCent[.j], "bottom", fixed$(blkCent[.j], 0)
        endif
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    .cStep = if .cTop <= 2000 then 500 else 1000 fi
    Marks left every: 1, .cStep, "yes", "yes", "no"

    # ---------------- H: per-cycle measurements ----------------
    Colour: "Black"
    @strip: 0.6, 7.7, .hHead, .hHead + 0.18, 9, 0, "left", "##H  Measured per cycle## — sounding voices / 4, simultaneity, rhythmic independence, spectral distance to previous cycle (x2)"
    @setPanel: 0.6, 7.7, .hTop, .hBot, 0, n_cyc, 0, 1.05, 6
    hc$[1] = "{0.20, 0.40, 0.80}"
    hc$[2] = "{0.85, 0.40, 0.15}"
    hc$[3] = "{0.15, 0.58, 0.35}"
    hc$[4] = "{0.55, 0.25, 0.65}"
    for .k from 1 to n_cyc
        hv[1] = min(1, cf_poly[.k] / 4)
        hv[2] = cf_sim[.k]
        hv[3] = max(0, cf_indep[.k])
        hv[4] = min(1, 2 * cycSpecDist[.k])
        for .q from 1 to 4
            .x0 = .k - 1 + 0.12 + (.q - 1) * 0.19
            if hv[.q] > 0.002
                Paint rectangle: hc$[.q], .x0, .x0 + 0.16, 0, hv[.q]
            endif
        endfor
    endfor
    Colour: "{0.70, 0.70, 0.70}"
    for .k from 1 to n_cyc - 1
        Draw line: .k, 0, .k, 1.05
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    Marks left every: 1, 0.5, "yes", "yes", "no"
    for .k from 1 to n_cyc
        One mark bottom: .k - 0.5, "no", "no", "no", "c" + string$(.k) + " " + roleName$[cycRole[.k]]
    endfor
    pf_font = 6
    for .q from 1 to 4
        Colour: hc$[.q]
        .lab$ = if .q = 1 then "voices/4" else if .q = 2 then "simultaneity" else if .q = 3 then "independence" else "spectral dist. x2" fi fi fi
        @label: n_cyc * (0.30 + 0.15 * (.q - 1)), "left", 1.0, "half", .lab$
    endfor

    # ---------------- G: v0.3 structural partial slots ----------------
    if .gOn
        Colour: "Black"
        @strip: 0.6, 7.7, .gHead, .gHead + 0.18, 9, 0, "left", "##G  Structural partial slots (v0.3)## — partial h = pitch class h-2 (h1 = anchor)"
        colR[1] = 0.20
        colG[1] = 0.40
        colB[1] = 0.80
        colR[2] = 0.85
        colG[2] = 0.40
        colB[2] = 0.15
        colR[3] = 0.15
        colG[3] = 0.58
        colB[3] = 0.35
        colR[4] = 0.55
        colG[4] = 0.25
        colB[4] = 0.65
        @setPanel: 1.0, 7.7, .gTop, .gBot, 0.5, 13.5, 0, .eRows, 6
        Paint rectangle: "{0.98, 0.98, 0.98}", 0.5, 13.5, 0, .eRows
        for .k from 1 to n_cyc
            for .v from 1 to 4
                .row = .eRows - ((.k - 1) * 4 + .v)
                .rowMax = 0
                for .h from 2 to 13
                    .rowMax = max(.rowMax, stw[.k, .v, .h])
                endfor
                for .h from 1 to 13
                    .wv = stw[.k, .v, .h]
                    if .h = 1
                        .mix = 0.35
                    elsif .rowMax > 0
                        .mix = .wv / .rowMax
                    else
                        .mix = 0
                    endif
                    if .mix > 0
                        .cr = 1 - .mix * (1 - colR[.v])
                        .cg = 1 - .mix * (1 - colG[.v])
                        .cb = 1 - .mix * (1 - colB[.v])
                        .cc$ = "{" + fixed$(.cr, 3) + ", " + fixed$(.cg, 3) + ", " + fixed$(.cb, 3) + "}"
                        Paint rectangle: .cc$, .h - 0.45, .h + 0.45, .row + 0.08, .row + 0.92
                    endif
                endfor
            endfor
        endfor
        Colour: "{0.45, 0.45, 0.45}"
        Line width: 1.2
        for .k from 1 to n_cyc - 1
            Draw line: 0.5, .eRows - 4 * .k, 13.5, .eRows - 4 * .k
        endfor
        Line width: 1
        Colour: "{0.75, 0.75, 0.75}"
        Draw line: 1.5, 0, 1.5, .eRows
        for .k from 1 to n_cyc
            pf_font = 6
            Colour: "{0.25, 0.25, 0.25}"
            @label: -0.35, "right", .eRows - (.k - 1) * 4 - 2, "half", "c" + string$(.k) + " " + cycKind$[.k]
        endfor
        pf_font = 6
        Colour: "Black"
        @frame
        Draw inner box
        One mark bottom: 1, "no", "yes", "no", "h1"
        for .h from 2 to 13
            One mark bottom: .h, "no", "yes", "no", "h" + string$(.h) + " / " + string$(.h - 2)
        endfor
    endif

    # ---------------- I: global dynamic arc ----------------
    if arc_on
        @drawArcPanel: .aHead, .aTop, .aBot
    endif

    # ---------------- QC summary ----------------
    @setPanel: 0.6, 7.7, .qcTop, .qcBot, 0, 3, -2, 8, 7
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 3, -2, 8
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 1, -2, 1, 8
    Draw line: 2, -2, 2, 8
    for .r from -1 to 7
        Draw line: 0, .r, 3, .r
    endfor
    Colour: "Black"
    @frame
    Draw inner box
    Colour: "{0.25, 0.25, 0.25}"
    .hexa$ = ""
    for .k from 1 to 6
        .hexa$ = .hexa$ + string$(pP[.k]) + " "
    endfor
    .arrOk$ = if arr_agg_ok = 1 then "ok" else "FAIL" fi
    .icOk$ = if all_ic then "= 1-5 once" else "(not all-IC)" fi
    .der$ = if derivation_cycles > 0 then "Derived partitions " + deriv_label$ else "Derivation off" fi
    .sec$ = if secondary_sets then "Secondary sets " + sec_op$ + " | 12-tone " + string$(sec_ok) + "/4" else "Secondary sets off" fi
    .xmlQc$ = if xmlStatus$ = "skipped" then "MusicXML skipped" else "MusicXML " + xmlStatus$ + " | " + string$(xml_measures) + " bars | " + (if xml_consistent then "consistent" else "MISMATCH" fi) fi
    .planShow$ = .plan$
    if length(.planShow$) > 46
        .planShow$ = left$(.planShow$, 43) + "..."
    endif
    .stOk$ = if st_pass = st_total then "all passed" else "FAILED " + string$(st_total - st_pass) fi
    .roles$ = ""
    for .k from 1 to n_cyc
        .roles$ = .roles$ + (if .k = 1 then "" else " > " fi) + left$(roleName$[cycRole[.k]], 5)
    endfor
    @label: 0.5, "centre", 7.5, "half", "##Self-tests " + string$(st_pass) + "/" + string$(st_total) + "## (" + .stOk$ + ")"
    @label: 1.5, "centre", 7.5, "half", "Decoding: v0.3.1 misread " + string$(v03_wrong) + "/16 | opening halves " + string$(open_h1) + "+" + string$(open_h2)
    @label: 2.5, "centre", 7.5, "half", "Plan " + .planShow$
    @label: 0.5, "centre", 6.5, "half", "Hexachord " + .hexa$ + "(" + source_name$ + ")"
    @label: 1.5, "centre", 6.5, "half", "Adjacent ICs " + ic_list$ + .icOk$
    @label: 2.5, "centre", 6.5, "half", "Array " + op_name$ + " (Y = " + y_label$ + ") | aggregates " + .arrOk$
    @label: 0.5, "centre", 5.5, "half", .sec$
    @label: 1.5, "centre", 5.5, "half", "Segmental trichords " + seg_label$
    @label: 2.5, "centre", 5.5, "half", .der$
    @label: 0.5, "centre", 4.5, "half", "Aggregates realized " + string$(n_agg_ok) + "/" + string$(n_agg) + " | line order " + (if order_ok then "kept" else "BROKEN" fi)
    @label: 1.5, "centre", 4.5, "half", string$(n_att) + " attacks = " + string$(n_new) + " + " + string$(n_re) + " re | partitions " + string$(partitions_ok) + "/" + string$(n_cyc)
    @label: 2.5, "centre", 4.5, "half", rearticulation_name$ + " | target " + .tgtShort$ + ": " + string$(surf_hits) + "/" + string$(n_surf)
    @label: 0.5, "centre", 3.5, "half", "Density " + fixed$(m_density, 2) + "/s | voices " + fixed$(m_poly, 2) + " | 3+ " + fixed$(m_ge3, 0) + "\%  "
    @label: 1.5, "centre", 3.5, "half", "MIDI " + string$(min_midi) + "-" + string$(max_midi) + " | crossings " + fixed$(m_cross, 0) + "\% | SATB " + (if voice_range_protection then (if rng_out_v[1] + rng_out_v[2] + rng_out_v[3] + rng_out_v[4] = 0 then "in range" else "OUT" fi) + " (" + string$(rng_moved + rng_re_fit) + " oct.)" else "off" fi)
    @label: 2.5, "centre", 3.5, "half", "Dynamics " + fixed$(m_db_min, 0) + ".." + fixed$(m_db_max, 0) + " dB, " + string$(m_marks) + " marks | IOI H " + fixed$(m_ioi_h, 2) + " bits"
    if texture = 1
        @label: 0.5, "centre", 2.5, "half", "Composite stream: group " + fixed$(m_clus, 2) + " overlap " + fixed$(m_ov, 2) + " stagger " + fixed$(m_stag, 2)
        @label: 1.5, "centre", 2.5, "half", "Optimizer objective " + fixed$(svd_real_mean, 2) + " vs random " + fixed$(svd_rand_mean, 2)
    else
        @label: 0.5, "centre", 2.5, "half", "Independent rhythmic voices | monody fallbacks " + string$(tex_fallback)
        @label: 1.5, "centre", 2.5, "half", "Roles " + .roles$
    endif
    @label: 2.5, "centre", 2.5, "half", "Artic. lv/leg/ten/port/stac " + string$(m_art[1]) + "/" + string$(m_art[2]) + "/" + string$(m_art[3]) + "/" + string$(m_art[4]) + "/" + string$(m_art[5])
    @label: 0.5, "centre", 1.5, "half", "Timbre " + timbre_name$ + " | centroid " + fixed$(cent_min, 0) + "-" + fixed$(cent_max, 0) + " Hz"
    @label: 1.5, "centre", 1.5, "half", "Partials " + string$(n_partials_total) + " | max " + fixed$(max_partial, 0) + " Hz | dropped " + string$(dropped_partials)
    @label: 2.5, "centre", 1.5, "half", .xmlQc$
    @label: 0.5, "centre", 0.5, "half", (if arc_on then "Arc " + arc_names$[arc_shape] + " " + fixed$(arc_range, 0) + " dB | " else "" fi) + (if nch = 2 then "Stereo" else "Mono" fi) + " | music " + fixed$(musical_duration, 2) + " s, audio " + fixed$(master_duration, 2) + " s"
    @label: 1.5, "centre", 0.5, "half", "Peak/RMS " + fixed$(final_peak, 3) + "/" + fixed$(final_rms, 3) + " | pre-norm peak " + fixed$(pre_norm_peak, 3)
    @label: 2.5, "centre", 0.5, "half", "Fingerprint " + string$(fp)
    .ci$ = if spec_ci = undefined then "n/a" else fixed$(spec_ci, 3) fi
    @label: 0.5, "centre", -0.5, "half", "Upper-partial separation " + .ci$ + " | upper " + (if spec_upper_db = undefined then "n/a" else fixed$(spec_upper_db, 0) + " dB" fi)
    if n_cyc > 1
        @label: 1.5, "centre", -0.5, "half", "Inter-cycle feature dist. " + fixed$(ic_adj, 2) + " | closest c" + string$(ic_minA) + "/c" + string$(ic_minB) + " " + fixed$(ic_min, 2)
        @label: 2.5, "centre", -0.5, "half", "Gesture Jaccard adjacent " + fixed$(jac_adj, 3) + " | max " + fixed$(jac_max, 3)
    else
        @label: 1.5, "centre", -0.5, "half", "Inter-cycle measures need 2+ cycles"
    endif
    @label: 0.5, "centre", -1.5, "half", "Horizontal lines " + (if horiz_ok then "ok" else "BROKEN " + horiz_bad$ fi)
    @label: 1.5, "centre", -1.5, "half", "Matrix repetitions: pivot " + string$(n_rep_pivot) + ", recurrence " + string$(n_rep_recur) + ", undeclared " + string$(n_rep_undecl)
    @label: 2.5, "centre", -1.5, "half", "Hybrid joins " + string$(hyb_count) + ": kept " + string$(hyb_kept) + ", reassigned " + string$(hyb_changed) + ", fully derived " + string$(hyb_fail)

    Font size: 10
    Colour: "Black"
    Line width: 1
    Select outer viewport: 0, 8, 0, .canvasH
    viz_canvas_height = .canvasH
endproc
