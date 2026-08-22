# ============================================================
# Praat AudioTools - CA_Reverb_IR.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Convolution reverb whose impulse response is grown from an
#   Elementary Cellular Automaton (Wolfram rule 0-255). Live
#   cells become signed impulses shaped by an exponential decay;
#   the rule chooses the room: chaotic rules give noise-like
#   (Schroeder-idealized) reverberation, structured rules give
#   self-similar metallic resonators that no physical room could
#   produce.
#
# Changelog v0.4 (2026):
#   - Public form and output naming are unchanged.
#   - Fixed Praat RNG initialization syntax and restore safe RNG state
#     after all CA/sign/rotation randomness has been generated.
#   - IR/sample rate now follows the selected source instead of forcing
#     every source/output through 44.1 kHz.
#   - CA evolution is computed in one recursive Matrix Formula pass
#     (row-major), reducing O(G^2*W) work to O(G*W) with identical
#     elementary-CA state evolution.
#   - Ir_duration now maps to the requested sample count exactly; the
#     final CA generation may be only partially represented in the IR.
#   - Added a practical CA-width ceiling to prevent pathological memory
#     allocation from extreme Custom values.
#   - Safe IR normalization skips digital silence.
#   - Wet/dry mix uses a safety ceiling instead of always boosting the
#     mixed output to peak 0.99; 0% wet now preserves the dry signal.
#   - Visualization spectrum is capped at Nyquist.
#
# Changelog v0.3 (2026):
#   - FIX (the "muffled" sound): dead cells mapped to -1, so the
#     CA background was a full-amplitude DC field -- from a
#     centre seed the loudest, least-decayed part of the IR was
#     almost pure low frequency. v0.3 maps dead cells to SILENCE
#     and live cells to +/-1 through a fixed seeded per-column
#     sign vector: runs of live cells whiten (no LF buildup), the
#     background stops thumping, and -- because the sign map is
#     fixed across generations -- row-to-row correlation
#     survives, so the decorr-OFF comb feature is untouched.
#   - Library standard: presets, house visualization (CA matrix
#     image, IR waveform + spectrum, wet waveform, summary
#     strip), wet/dry mix, cleanup (Keep_IR_and_CA flag).
#   - Stereo dry sounds convolve natively (Praat broadcasts a
#     mono IR across channels -- verified on 6.4.42).
#
# Changelog v0.2 (2026):
#   - Measured and fixed the raw v0.1 artifacts: +26 dB comb at
#     samplerate/ca_width (seeded per-generation read rotation,
#     exposed as Frame_decorrelation) and +29 dB/Hz LF rumble
#     (0-25 Hz stop-band). IR end fade; random-row seed mode;
#     wider ir_duration range; rule 0 made legal.
#
# Usage: select a Sound object, then run.
# ============================================================

form CA Convolution Reverb v0.5.1
    optionmenu Preset: 1
        option Chaotic Room (rule 30, natural)
        option Sierpinski Plate (rule 90, metallic comb)
        option Complex Bloom (rule 110, swelling)
        option Granular Traffic (rule 184, grainy)
        option Cathedral Chaos (rule 45, vast)
        option Custom
    comment === Cellular Automaton (Custom) ===
    integer Rule 30
    positive Ca_width 256
    optionmenu Seed_mode: 2
        option single centre cell (canonical, deterministic)
        option random row (density 0.5, uses Random_seed)
    integer Random_seed 42
    comment === Impulse Response (Custom) ===
    positive Ir_duration 1.5
    positive Decay_time 0.35
    boolean Frame_decorrelation 1
    comment (ON = room-like; OFF = keep the samplerate/width comb: metallic)
    comment === Mix ===
    real Wet_dry_percent 100
    comment === Output ===
    boolean Keep_IR_and_CA 0
    boolean Draw_visualization 1
    boolean Play_impulse_response 0
    boolean Play_result 1
endform

# ---- Grab the selected sound ---------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object, then run the script again."
endif
dryID = selected("Sound")
dryName$ = selected$("Sound")

selectObject: dryID
sampleRate = Get sampling frequency

# ---- Presets --------------------------------------------------
if preset = 1
    rule = 30
    ca_width = 256
    seed_mode = 2
    ir_duration = 1.2
    decay_time = 0.35
    frame_decorrelation = 1
    presetName$ = "ChaoticRoom"
elsif preset = 2
    rule = 90
    ca_width = 512
    seed_mode = 1
    ir_duration = 2.0
    decay_time = 0.6
    frame_decorrelation = 0
    presetName$ = "SierpinskiPlate"
elsif preset = 3
    rule = 110
    ca_width = 256
    seed_mode = 1
    ir_duration = 2.5
    decay_time = 0.9
    frame_decorrelation = 1
    presetName$ = "ComplexBloom"
elsif preset = 4
    rule = 184
    ca_width = 128
    seed_mode = 2
    ir_duration = 0.8
    decay_time = 0.2
    frame_decorrelation = 1
    presetName$ = "GranularTraffic"
elsif preset = 5
    rule = 45
    ca_width = 1024
    seed_mode = 2
    ir_duration = 4.0
    decay_time = 1.4
    frame_decorrelation = 1
    presetName$ = "CathedralChaos"
else
    presetName$ = "Custom"
endif

# ---- Clamps ----------------------------------------------------
if ir_duration < 0.25
    ir_duration = 0.25
elsif ir_duration > 10
    ir_duration = 10
endif
if ca_width < 16
    ca_width = 16
elsif ca_width > 8192
    ca_width = 8192
endif
if rule < 0
    rule = 0
elsif rule > 255
    rule = 255
endif
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif
wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

random_initializeWithSeedUnsafelyButPredictably (random_seed)

width = round(ca_width)
rule = round(rule)

# ---- Geometry --------------------------------------------------
targetSamples = round(ir_duration * sampleRate)
if targetSamples < 1
    targetSamples = 1
endif
numGenerations = ceiling(targetSamples / width)
totalSamples = targetSamples
actualDuration = totalSamples / sampleRate

clearinfo
writeInfoLine: "=== CA Reverb IR v0.3 ==="
appendInfoLine: "Dry sound: ", dryName$
appendInfoLine: "Preset: ", presetName$, " | Rule: ", rule
appendInfoLine: "CA: ", width, " cells x ", numGenerations, " generations"
appendInfoLine: "IR: ", fixed$(actualDuration, 3), " s | decay ", fixed$(decay_time, 2), " s | decorrelation ",
    ... if frame_decorrelation then "ON" else "OFF (comb at " + fixed$(sampleRate / width, 0) + " Hz)" fi
appendInfoLine: "Wet/Dry: ", fixed$(wet_dry_percent, 0), "%"
appendInfoLine: ""

# =============================================================
# STEP 1 - blank IR
# =============================================================
irID = Create Sound from formula: "IR", 1, 0, actualDuration, sampleRate, "0"

# =============================================================
# STEP 2 - Cellular Automaton evolution (Matrix)
# =============================================================
caID = Create simple Matrix: "CA", numGenerations, width, "0"

selectObject: caID
if seed_mode = 1
    centerCol = round((width + 1) / 2)
    Set value: 1, centerCol, 1
else
    Formula: "if row = 1 then (if randomUniform(0, 1) < 0.5 then 1 else 0 fi) else self fi"
endif

# Matrix Formula is evaluated row-major. Keeping row 1 unchanged and
# reading only self[row-1,...] therefore computes each later generation
# from the already-completed previous row in ONE pass. This is the same
# elementary-CA recurrence as v0.3, without re-scanning the whole matrix
# once per generation. Boundary is periodic.
selectObject: caID
Formula: "if row = 1 then
    ... self
    ... else if col = 1 then
    ...   floor('rule' / 2 ^ (self[row-1,'width']*4 + self[row-1,1]*2 + self[row-1,2])) mod 2
    ... else if col = 'width' then
    ...   floor('rule' / 2 ^ (self[row-1,'width'-1]*4 + self[row-1,'width']*2 + self[row-1,1])) mod 2
    ... else
    ...   floor('rule' / 2 ^ (self[row-1,col-1]*4 + self[row-1,col]*2 + self[row-1,col+1])) mod 2
    ... fi fi fi"

appendInfoLine: "CA evolution complete."

# =============================================================
# STEP 3 - map CA onto the IR
# v0.3: dead cells -> SILENCE, live cells -> +/-1 through a fixed
# seeded per-column sign vector. (The old 0 -> -1 mapping made
# the background a full-amplitude DC field: the muffled sound.)
# With Frame_decorrelation ON, generation g is read through a
# seeded circular rotation (kills the samplerate/width comb; the
# CA matrix itself stays intact). The sign attaches to the
# PHYSICAL cell, so row-to-row correlation -- the comb feature in
# OFF mode -- survives the sign map.
# =============================================================
sgnID = Create simple Matrix: "sgn", 1, width,
    ... "if randomUniform(0, 1) < 0.5 then -1 else 1 fi"

if frame_decorrelation
    rotID = Create simple Matrix: "rot", 1, numGenerations, "0"
    Formula: "randomInteger(0, 'width' - 1)"
    selectObject: irID
    Formula: "object['caID', ceiling(col/'width'),"
        ... + " ((col - (ceiling(col/'width') - 1) * 'width' - 1"
        ... + " + object['rotID', 1, ceiling(col/'width')]) mod 'width') + 1]"
        ... + " * object['sgnID', 1,"
        ... + " ((col - (ceiling(col/'width') - 1) * 'width' - 1"
        ... + " + object['rotID', 1, ceiling(col/'width')]) mod 'width') + 1]"
    removeObject: rotID
else
    selectObject: irID
    Formula: "object['caID', ceiling(col/'width'), col - (ceiling(col/'width') - 1) * 'width']"
        ... + " * object['sgnID', 1, col - (ceiling(col/'width') - 1) * 'width']"
endif
removeObject: sgnID

# Do not leak a predictable RNG state into caller scripts or later Praat work.
random_initializeSafelyAndUnpredictably ()

# residual LF safety (density fluctuations)
selectObject: irID
filteredIR = Filter (stop Hann band): 0, 25, 12
removeObject: irID
irID = filteredIR
Rename: "IR"

# =============================================================
# STEP 4 - exponential decay + end fade
# =============================================================
selectObject: irID
Formula: "self * exp(-x / 'decay_time')"

endLevel = exp(-actualDuration / decay_time)
if endLevel > 0.1
    appendInfoLine: "NOTE: decay reaches only ", fixed$(endLevel * 100, 0),
        ... "% by the IR end -- tail truncated. Raise Ir_duration or lower Decay_time."
endif
fadeDur = min(0.03, actualDuration * 0.1)
Fade out: 0, actualDuration, -fadeDur, "yes"
irPeak = Get absolute extremum: 0, 0, "None"
if irPeak > 0
    Scale peak: 0.99
endif

appendInfoLine: "Impulse response ready."

if play_impulse_response
    selectObject: irID
    Play
endif

# =============================================================
# STEP 5 - convolve (stereo dry broadcasts a mono IR natively)
# =============================================================
selectObject: dryID
dryRate = Get sampling frequency
dryDur = Get total duration
dryConvID = dryID

if wet_level <= 0
    # Exact dry endpoint: no reverb and no forced loudness normalization.
    selectObject: dryConvID
    wetID = Copy: "CAreverb_dry"
else
    selectObject: dryConvID
    plusObject: irID
    wetID = Convolve: "peak 0.99", "zero"

    # ---- wet/dry mix (the dry ends where it ends; the tail stays
    #      pure wet -- out-of-range object[] reads return 0)
    if dry_level > 0
        dryStr$ = string$(dryConvID)
        selectObject: wetID
        Formula: "self * " + string$(wet_level)
            ... + " + object[" + dryStr$ + ", row, col] * " + string$(dry_level)

        # Safety ceiling only: preserve wet/dry balance and source level.
        mixPeak = Get absolute extremum: 0, 0, "None"
        if mixPeak > 0.99
            Scale peak: 0.99
        endif
    endif
endif

selectObject: wetID
Rename: dryName$ + "_CAreverb_" + presetName$
wetDur = Get total duration
wetCh = Get number of channels

appendInfoLine: "Convolution complete: ", dryName$, "_CAreverb_", presetName$,
    ... " (", fixed$(wetDur, 2), " s, ", wetCh, " ch)"

# =============================================================
# VISUALIZATION (house style)
# =============================================================
if draw_visualization
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Select outer viewport: 0, 8, 0, 7

    # --- Title strip (explicit inner viewport pattern) ---
    Select outer viewport: 0, 8, 0, 0.6
    Select inner viewport: 0.60, 7.70, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##CA Reverb IR v0.5.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... dryName$ + "  |  " + presetName$ + "  |  rule " + string$(rule)
        ... + "  |  " + string$(width) + " x " + string$(numGenerations)
        ... + "  |  decay " + fixed$(decay_time, 2) + " s"
        ... + "  |  " + if frame_decorrelation then "decorrelated" else "comb " + fixed$(sampleRate / width, 0) + " Hz" fi

    # --- Panel A: the automaton itself ---
    Select outer viewport: 0, 4.1, 0.68, 3.3
    Select inner viewport: 0.60, 3.85, 0.83, 3.2
    selectObject: caID
    Paint image: 0, 0, 0, 0, 0, 0
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Cellular automaton (rule " + string$(rule) + ")"
    Select inner viewport: 0.20, 0.48, 0.83, 3.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "generation"
    Select inner viewport: 0.60, 3.85, 0.83, 3.2
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "cell"

    # --- Panel B: IR waveform ---
    Select outer viewport: 4.1, 8, 0.68, 2.0
    Select inner viewport: 4.45, 7.70, 0.83, 1.92
    selectObject: irID
    Colour: "{0.35, 0.58, 0.72}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Impulse response"
    Select inner viewport: 4.05, 4.33, 0.83, 1.92
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "amp"
    Select inner viewport: 4.45, 7.70, 0.83, 1.92
    Axes: 0, 1, 0, 1

    # --- Panel C: IR spectrum ---
    Select outer viewport: 4.1, 8, 2.0, 3.3
    Select inner viewport: 4.45, 7.70, 2.13, 3.2
    selectObject: irID
    vizIrSpec = To Spectrum: "yes"
    vizMaxHz = min(10000, sampleRate / 2)
    Colour: "{0.80, 0.45, 0.25}"
    Draw: 0, vizMaxHz, 0, 80, "no"
    removeObject: vizIrSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "IR spectrum (to " + fixed$(vizMaxHz / 1000, 1) + " kHz)"
    Select inner viewport: 4.05, 4.33, 2.13, 3.2
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "dB"
    Select inner viewport: 4.45, 7.70, 2.13, 3.2
    Axes: 0, 1, 0, 1

    # --- Panel D: wet output waveform ---
    Select outer viewport: 0, 8, 3.38, 5.0
    Select inner viewport: 0.60, 7.70, 3.53, 4.92
    selectObject: wetID
    if wetCh > 1
        vizWet = Extract one channel: 1
    else
        vizWet = Copy: "vizWet"
    endif
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    removeObject: vizWet
    Colour: "Black"
    Draw inner box
    Font size: 7
    Select inner viewport: 0.20, 0.48, 3.53, 4.92
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Wet"
    Select inner viewport: 0.60, 7.70, 3.53, 4.92
    Axes: 0, 1, 0, 1
    Text bottom: "yes", "Time (s)"

    # --- Summary strip ---
    Select outer viewport: 0, 8, 5.15, 6.15
    Select inner viewport: 0.60, 7.70, 5.22, 6.08
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", 
        ... "Rule " + string$(rule) + "   Width " + string$(width)
        ... + "   Generations " + string$(numGenerations)
        ... + "   Seed: " + if seed_mode = 1 then "centre" else "random (" + string$(random_seed) + ")" fi
        ... + "   IR " + fixed$(actualDuration, 2) + " s   Decay " + fixed$(decay_time, 2) + " s"
    Font size: 6
    Text: 0.02, "left", 0.24, "half", 
        ... "Decorrelation: " + if frame_decorrelation then "ON (room)" else "OFF (comb " + fixed$(sampleRate / width, 0) + " Hz)" fi
        ... + "   Wet/Dry " + fixed$(wet_dry_percent, 0) + "\%  "
        ... + "   Output " + fixed$(wetDur, 2) + " s / " + string$(wetCh) + " ch"
    Colour: "Black"

    Select inner viewport: 0.60, 7.70, 5.22, 6.08
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Line width: 1

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 6.25
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# =============================================================
# CLEANUP + FINAL
# =============================================================
if not keep_IR_and_CA
    removeObject: irID, caID
    appendInfoLine: "Intermediates removed (set Keep_IR_and_CA to inspect the IR and the CA matrix)."
else
    appendInfoLine: "Kept: Sound IR and Matrix CA."
endif

selectObject: wetID

if play_result
    Play
endif

selectObject: wetID
appendInfoLine: "Done."
