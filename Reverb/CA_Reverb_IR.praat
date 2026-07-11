# ============================================================
# Praat AudioTools - CA_Reverb_IR.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
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

form CA Convolution Reverb v0.3
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

sampleRate = 44100

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

random_initializeWithSeedUnsafelyButPredictably: random_seed

width = round(ca_width)
rule = round(rule)

# ---- Geometry --------------------------------------------------
targetSamples = round(ir_duration * sampleRate)
numGenerations = ceiling(targetSamples / width)
totalSamples = numGenerations * width
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

# Row-by-row evolution. Matrix objects do not support
# "Formula (part)" (verified on 6.4.42), so each generation is a
# whole-matrix Formula with a row guard. Reads of self[row-1,...]
# land on rows finished in EARLIER calls -- correct, not the
# in-place pattern. Boundary is periodic.
for g from 2 to numGenerations
    selectObject: caID
    Formula: "if row = 'g' then
        ... if col = 1 then
        ...   floor('rule' / 2 ^ (self[row-1,'width']*4 + self[row-1,1]*2 + self[row-1,2])) mod 2
        ... else if col = 'width' then
        ...   floor('rule' / 2 ^ (self[row-1,'width'-1]*4 + self[row-1,'width']*2 + self[row-1,1])) mod 2
        ... else
        ...   floor('rule' / 2 ^ (self[row-1,col-1]*4 + self[row-1,col]*2 + self[row-1,col+1])) mod 2
        ... fi fi
        ... else
        ...   self
        ... fi"
endfor

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
Scale peak: 0.99

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

if dryRate <> sampleRate
    appendInfoLine: "Resampling dry sound from ", dryRate, " Hz to ", sampleRate, " Hz."
    selectObject: dryID
    resampledID = Resample: sampleRate, 50
    dryConvID = resampledID
else
    dryConvID = dryID
endif

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
    Scale peak: 0.99
endif

selectObject: wetID
Rename: dryName$ + "_CAreverb_" + presetName$
wetDur = Get total duration
wetCh = Get number of channels

if dryConvID <> dryID
    removeObject: dryConvID
endif

appendInfoLine: "Convolution complete: ", dryName$, "_CAreverb_", presetName$,
    ... " (", fixed$(wetDur, 2), " s, ", wetCh, " ch)"

# =============================================================
# VISUALIZATION (house style)
# =============================================================
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 7

    # --- Title strip (explicit inner viewport pattern) ---
    Select outer viewport: 0, 8, 0, 0.6
    Select inner viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##CA Reverb IR v0.3##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.26, "half",
        ... dryName$ + "  |  " + presetName$ + "  |  rule " + string$(rule)
        ... + "  |  " + string$(width) + " x " + string$(numGenerations)
        ... + "  |  decay " + fixed$(decay_time, 2) + " s"
        ... + "  |  " + if frame_decorrelation then "decorrelated" else "comb " + fixed$(sampleRate / width, 0) + " Hz" fi

    # --- Panel A: the automaton itself ---
    Select outer viewport: 0, 4.1, 0.68, 3.3
    Select inner viewport: 0.55, 3.85, 0.83, 3.2
    selectObject: caID
    Paint image: 0, 0, 0, 0, 0, 0
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Cellular automaton (rule " + string$(rule) + ")"
    Text left: "yes", "generation"
    Text bottom: "yes", "cell"

    # --- Panel B: IR waveform ---
    Select outer viewport: 4.1, 8, 0.68, 2.0
    Select inner viewport: 4.45, 7.65, 0.83, 1.92
    selectObject: irID
    Colour: "{0.35, 0.58, 0.72}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Impulse response"
    Text left: "yes", "amp"

    # --- Panel C: IR spectrum ---
    Select outer viewport: 4.1, 8, 2.0, 3.3
    Select inner viewport: 4.45, 7.65, 2.13, 3.2
    selectObject: irID
    vizIrSpec = To Spectrum: "yes"
    Colour: "{0.80, 0.45, 0.25}"
    Draw: 0, 10000, 0, 80, "no"
    removeObject: vizIrSpec
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "IR spectrum (0-10 kHz)"
    Text left: "yes", "dB"

    # --- Panel D: wet output waveform ---
    Select outer viewport: 0, 8, 3.38, 5.0
    Select inner viewport: 0.55, 7.65, 3.53, 4.92
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
    Text left: "yes", "Wet"
    Text bottom: "yes", "Time (s)"

    # --- Summary strip ---
    Select outer viewport: 0, 8, 5.1, 5.9
    Select inner viewport: 0.55, 7.65, 5.18, 5.84
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.76, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.46, "half",
        ... "Rule " + string$(rule) + "   Width " + string$(width)
        ... + "   Generations " + string$(numGenerations)
        ... + "   Seed: " + if seed_mode = 1 then "centre" else "random (" + string$(random_seed) + ")" fi
        ... + "   IR " + fixed$(actualDuration, 2) + " s   Decay " + fixed$(decay_time, 2) + " s"
    Text: 0.02, "left", 0.18, "half",
        ... "Decorrelation: " + if frame_decorrelation then "ON (room)" else "OFF (comb " + fixed$(sampleRate / width, 0) + " Hz)" fi
        ... + "   Wet/Dry " + fixed$(wet_dry_percent, 0) + "%"
        ... + "   Output " + fixed$(wetDur, 2) + " s / " + string$(wetCh) + " ch"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Line width: 1
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
