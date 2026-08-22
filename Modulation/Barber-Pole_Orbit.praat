# ============================================================
# Praat AudioTools - Barber-Pole_Orbit.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Barber-pole-inspired modulated-delay orbit. Multiple phase-offset
#   feedforward delay taps use two nearby modulation rates to create
#   cyclical comb/vibrato motion and stereo rotation.
#
#   IMPORTANT: This is not a Shepard-tone resynthesizer and does not
#   produce discrete octave pitch layers. "Barber-pole" describes the
#   perceptual/orbital character of the delay modulation.
#
# Changelog v0.5:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.4:
#   - Corrected the DSP description: the effect is a modulated-delay orbit,
#     not a Shepard-tone pitch shifter.
#   - LFO phase now uses local sound time, so shifting the Sound time domain
#     does not change the rendered effect.
#   - Delay reads use linear interpolation instead of rounded sample indices.
#   - Added normalized wet-tap summing, Dry_wet_percent, and attenuation-only
#     Safety_peak. Dry=0 is an exact bypass (mono is duplicated to stereo).
#   - Preserved arbitrary multichannel input; mono intentionally becomes stereo.
#   - Updated preset names to avoid unsupported perpetual-pitch claims.
#   - Rebuilt visualization text/layout to the AudioTools reference template.
#
# Changelog v0.3:
#   - Corrected channel indexing and removed recursive delay reads.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
dur = Get total duration
numberOfChannels = Get number of channels
sampling = Get sampling frequency
soundStart = Get start time
soundEnd = Get end time

# === Form ===
form Barber-Pole Orbit Effect v0.5
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Orbit
        option Classic Barber-Pole Orbit
        option Intense Spiral
        option Subtle Shimmer
        option Deep Space Rotation
        option Extreme Drift

    comment === Orbit Parameters ===
    natural Number_of_turns 5
    positive Base_delay_ms 7.0
    real Modulation_depth 0.10
    comment (0-0.95; fraction of base delay)

    comment === Modulation Rates ===
    positive Base_rate_hz 3.8
    real Drift_rate_hz 0.12
    real Opposing_phase_offset_rad 1.2

    comment === Spatial / Layer Phase ===
    real Stereo_phase_offset_cycles 0.5
    real Turn_phase_step_rad 0.3

    comment === Layer Weights ===
    positive Turn_attenuation 1.0

    comment === Mix / Output ===
    real Dry_wet_percent 70
    real Safety_peak 0.99
    comment (Safety_peak 0 disables; only attenuates)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    number_of_turns = 3
    base_delay_ms = 5.0
    modulation_depth = 0.08
    base_rate_hz = 3.0
    drift_rate_hz = 0.08
    opposing_phase_offset_rad = 1.57
    stereo_phase_offset_cycles = 0.25
    turn_attenuation = 1.5
    turn_phase_step_rad = 0.2
    dry_wet_percent = 60
    presetName$ = "Gentle Orbit"
elsif preset = 3
    number_of_turns = 5
    base_delay_ms = 7.0
    modulation_depth = 0.12
    base_rate_hz = 4.0
    drift_rate_hz = 0.15
    opposing_phase_offset_rad = 1.2
    stereo_phase_offset_cycles = 0.5
    turn_attenuation = 1.0
    turn_phase_step_rad = 0.3
    dry_wet_percent = 70
    presetName$ = "Classic Orbit"
elsif preset = 4
    number_of_turns = 7
    base_delay_ms = 9.0
    modulation_depth = 0.18
    base_rate_hz = 5.5
    drift_rate_hz = 0.22
    opposing_phase_offset_rad = 0.9
    stereo_phase_offset_cycles = 0.75
    turn_attenuation = 0.7
    turn_phase_step_rad = 0.45
    dry_wet_percent = 78
    presetName$ = "Intense Spiral"
elsif preset = 5
    number_of_turns = 4
    base_delay_ms = 4.0
    modulation_depth = 0.06
    base_rate_hz = 2.5
    drift_rate_hz = 0.05
    opposing_phase_offset_rad = 1.8
    stereo_phase_offset_cycles = 0.3
    turn_attenuation = 2.0
    turn_phase_step_rad = 0.15
    dry_wet_percent = 45
    presetName$ = "Subtle Shimmer"
elsif preset = 6
    number_of_turns = 6
    base_delay_ms = 12.0
    modulation_depth = 0.15
    base_rate_hz = 2.0
    drift_rate_hz = 0.10
    opposing_phase_offset_rad = 1.0
    stereo_phase_offset_cycles = 0.66
    turn_attenuation = 0.8
    turn_phase_step_rad = 0.5
    dry_wet_percent = 75
    presetName$ = "Deep Space Rotation"
elsif preset = 7
    number_of_turns = 10
    base_delay_ms = 10.0
    modulation_depth = 0.25
    base_rate_hz = 6.5
    drift_rate_hz = 0.30
    opposing_phase_offset_rad = 0.8
    stereo_phase_offset_cycles = 0.9
    turn_attenuation = 0.5
    turn_phase_step_rad = 0.6
    dry_wet_percent = 85
    presetName$ = "Extreme Drift"
else
    presetName$ = "Custom"
endif

# === Defensive limits ===
number_of_turns = max(1, min(32, number_of_turns))
modulation_depth = max(0, min(0.95, modulation_depth))
drift_rate_hz = max(0, drift_rate_hz)
dry_wet_percent = max(0, min(100, dry_wet_percent))
wetAmt = dry_wet_percent / 100
dryAmt = 1 - wetAmt
safety_peak = max(0, min(1, safety_peak))

# Phase offsets are periodic; keep the stereo offset compact.
stereo_phase_offset_cycles = stereo_phase_offset_cycles - floor(stereo_phase_offset_cycles)
stereo_phase = stereo_phase_offset_cycles * 2 * pi

# Delay must fit inside the sound. Keep at least one sample of valid range.
maxDelaySamples = max(1, floor(dur * sampling) - 2)
base = round(base_delay_ms * sampling / 1000)
base = max(1, min(maxDelaySamples, base))
actualBaseDelayMs = base * 1000 / sampling

# === Info ===
writeInfoLine: "=== Barber-Pole Orbit v0.5 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(dur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Model: barber-pole-inspired feedforward modulated-delay orbit"
appendInfoLine: "Note: this is not Shepard-tone pitch resynthesis."
appendInfoLine: ""
appendInfoLine: "Turns: ", number_of_turns
appendInfoLine: "Base delay: ", fixed$(actualBaseDelayMs, 3), " ms"
appendInfoLine: "Modulation depth: ", fixed$(modulation_depth, 3)
appendInfoLine: "Base / drift rates: ", fixed$(base_rate_hz, 3), " / ", fixed$(drift_rate_hz, 3), " Hz"
appendInfoLine: "Dry / wet: ", fixed$(dry_wet_percent, 1), "%"
appendInfoLine: ""

# === Prepare channel layout ===
selectObject: original
monoConverted = 0
if numberOfChannels = 1
    Convert to stereo
    sourceLayout = selected("Sound")
    monoConverted = 1
else
    sourceLayout = Copy: originalName$ + "_layout"
endif

# Clean dry reference.
selectObject: sourceLayout
dry = Copy: originalName$ + "_orbit_dry"
dryName$ = "ATorbitdry" + string$(dry)
Rename: dryName$

# Exact bypass: no modulation work and no safety attenuation.
if wetAmt = 0
    selectObject: dry
    result = Copy: originalName$ + "_barber_" + presetName$

else
    # === Build normalized wet tap field ===
    selectObject: dry
    wet = Copy: originalName$ + "_orbit_wet"
    Formula: "0"

    sumWeights = 0
    for t from 1 to number_of_turns
        sumWeights = sumWeights + 1 / (t + turn_attenuation)
    endfor
    wetNorm = 1 / (2 * sumWeights)

    appendInfoLine: "Applying modulated-delay layers..."
    for t from 1 to number_of_turns
        w = 1 / (t + turn_attenuation)
        appendInfoLine: "  Turn ", t, "/", number_of_turns

        # Local time (x-soundStart) makes the result independent of the
        # absolute Praat time domain. Sound_name(time) provides interpolated
        # sampling at fractional delay positions.
        selectObject: wet
        upFormula$ = "self + w * (Sound_" + dryName$ + "(x + (base + base*modulation_depth*sin(2*pi*(base_rate_hz+drift_rate_hz)*(x-soundStart) + t*turn_phase_step_rad + (row-1)*stereo_phase))/sampling) + Sound_" + dryName$ + "(x + (base + base*modulation_depth*sin(2*pi*(base_rate_hz-drift_rate_hz)*(x-soundStart) + opposing_phase_offset_rad - t*turn_phase_step_rad + (row-1)*stereo_phase))/sampling))"
        Formula: upFormula$
    endfor

    selectObject: wet
    Formula: ~ self * wetNorm

    # === Dry / wet mix ===
    selectObject: dry
    result = Copy: originalName$ + "_barber_" + presetName$
    Formula: ~ self * dryAmt + object[wet,row,col] * wetAmt

    # Attenuation-only safety ceiling.
    if safety_peak > 0
        selectObject: result
        outPeak = Get absolute extremum: 0, 0, "None"
        if outPeak > safety_peak
            safetyGain = safety_peak / outPeak
            Multiply: safetyGain
            appendInfoLine: "Safety attenuation: ", fixed$(20*log10(safetyGain), 2), " dB"
        else
            appendInfoLine: "Safety attenuation: none"
        endif
    endif
endif

selectObject: result
Rename: originalName$ + "_barber_" + presetName$
outputChannels = Get number of channels
resultStart = Get start time

# === Visualization ===
if draw_visualization
    pageHeight = 5.8
    Erase all

    # Title
    Select outer viewport: 0, 8, 0.05, 0.38
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Barber-Pole Orbit v0.5##"

    # Metadata subtitle
    Select outer viewport: 0, 8, 0.38, 0.62
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " | " + presetName$ + " | Modulated-delay orbit"

    # Original waveform
    Select outer viewport: 0, 8, 0.70, 1.52
    Select inner viewport: 0.65, 7.65, 0.80, 1.42
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"

    # Result waveform
    Select outer viewport: 0, 8, 1.60, 2.42
    Select inner viewport: 0.65, 7.65, 1.70, 2.32
    selectObject: result
    Colour: "{0.22, 0.46, 0.80}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Modulation trajectories (first few turns)
    Select outer viewport: 0, 8, 2.58, 4.00
    Select inner viewport: 0.65, 7.65, 2.72, 3.88
    Axes: 0, dur, -1.15, 1.15
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, dur, -1.15, 1.15

    Colour: "{0.84, 0.84, 0.84}"
    Dotted line
    Draw line: 0, 0, dur, 0
    Solid line

    numVizTurns = min(number_of_turns, 4)
    step = dur / 180
    for t from 1 to numVizTurns
        Colour: "{0.22, 0.46, 0.80}"
        prevTime = 0
        prevVal = sin(t * turn_phase_step_rad)
        plotTime = step
        while plotTime <= dur
            modVal = sin(2*pi*(base_rate_hz+drift_rate_hz)*plotTime + t*turn_phase_step_rad)
            Draw line: prevTime, prevVal, plotTime, modVal
            prevTime = plotTime
            prevVal = modVal
            plotTime = plotTime + step
        endwhile

        Colour: "{0.50, 0.35, 0.74}"
        Dotted line
        prevTime = 0
        prevVal = sin(opposing_phase_offset_rad - t * turn_phase_step_rad)
        plotTime = step
        while plotTime <= dur
            modVal = sin(2*pi*(base_rate_hz-drift_rate_hz)*plotTime + opposing_phase_offset_rad - t*turn_phase_step_rad)
            Draw line: prevTime, prevVal, plotTime, modVal
            prevTime = plotTime
            prevVal = modVal
            plotTime = plotTime + step
        endwhile
        Solid line
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Delay modulation"
    Text bottom: "yes", "Time (s)"

    # Compact legend
    Font size: 6
    Colour: "{0.22, 0.46, 0.80}"
    Text: dur*0.03, "left", 1.02, "half", "Rate + drift"
    Colour: "{0.50, 0.35, 0.74}"
    Text: dur*0.20, "left", 1.02, "half", "Rate - drift"

    # Turn weights
    Select outer viewport: 0, 8, 4.12, 4.72
    Select inner viewport: 0.65, 7.65, 4.22, 4.62
    maxW = 1 / (1 + turn_attenuation)
    Axes: 0, number_of_turns + 1, 0, maxW * 1.2
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, number_of_turns + 1, 0, maxW * 1.2
    for t from 1 to number_of_turns
        w = 1 / (t + turn_attenuation)
        Paint rectangle: "{0.50, 0.35, 0.74}", t - 0.3, t + 0.3, 0, w
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Weight"
    Text bottom: "yes", "Turn"

    # Summary panel
    Select outer viewport: 0, 8, 4.86, 5.62
    Select inner viewport: 0.55, 7.75, 4.96, 5.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.48, "half", "Turns: " + string$(number_of_turns) + " | Delay: " + fixed$(actualBaseDelayMs, 2) + " ms | Depth: " + fixed$(modulation_depth, 2) + " | Base/Drift: " + fixed$(base_rate_hz, 2) + "/" + fixed$(drift_rate_hz, 2) + " Hz"
    Text: 0.02, "left", 0.20, "half", "Stereo phase: " + fixed$(stereo_phase_offset_cycles, 2) + " cyc | Dry/Wet: " + fixed$(dry_wet_percent, 0) + "% | Duration: " + fixed$(dur, 2) + " s | Channels: " + string$(outputChannels)

    # Reset drawing state
    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Cleanup ===
if wetAmt <> 0
    removeObject: wet
endif
removeObject: dry, sourceLayout

# === Final Info ===
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output channels: ", outputChannels
appendInfoLine: "Start time preserved: ", fixed$(resultStart, 6), " s"

if play_result
    Play
endif

selectObject: result
