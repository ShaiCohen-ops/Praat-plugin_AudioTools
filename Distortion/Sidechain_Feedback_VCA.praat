# ============================================================
# Praat AudioTools - Sidechain_Feedback_VCA.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sidechain Feedback VCA - simulates a "no-input mixer" where
#   feedback creates self-oscillation. The input's pitch controls the
#   resonant frequency and its intensity controls the feedback gain
#   (VCA); the Dry/Wet control blends the original input back in, and a
#   synthetic high-frequency exciter adds air. Evolving, audio-reactive
#   electronic textures.
#
# Changelog v0.2:
#   - Fixed form placement (before analysis)
#   - Fixed name-based references (use object IDs)
#   - Fixed formula syntax
#   - Added visualization
#   - Improved cleanup
#
# Changelog v0.3:
#   - FIX: the feedback core seeded L and R from two independent noise calls,
#     so the channels resonated at the same pitch with random phase = decorrelated
#     noise (and cancelled when summed to mono). Now one shared seed feeds both
#     channels; stereo width is created by the spatial stage instead.
#   - ROBUSTNESS: VCA control is made stereo and the feedback formula indexes
#     object[id, row, col] explicitly, so the right channel can never read an
#     undefined mono value (NaN -> blow-up) on some Praat versions.
#   - Removed the redundant per-iteration Copy (filter the loop directly).
#   - Added Debug mode: per-stage levels, sample-count check, per-iteration loop
#     peak with an undefined / out-of-bound guard, and final per-channel peaks.
#   - FIX: Binaural right channel was silent (in-place delay read its own zeros);
#     now reads the 30-sample delay from an unmodified copy.
#   - HIGHS: High_Freq_Add adds a synthetic treble 'air' band by ring-
#     modulating the output with a high harmonic of the resonance, then
#     high-passing and blending it in (the pure feedback is dark/narrow).
#   - DOC: description updated for the Dry/Wet behaviour (the original input
#     can now be blended into the output).
#   - VIZ: title and parameter line were centred against a stale wide world
#     window so they spilled off the left edge; now pinned to a 0..1 axis.
#   - BALANCE: Stereo Wide high-passed the right channel at 200 Hz, silencing
#     low resonances on the right; both channels now overlap across the
#     resonance so L and R stay balanced.
#   - DRY/WET: Dry_Wet mixes the original controller back into the output
#     (0 = pure feedback / no-input-mixer, default 0.3). The pure feedback is a
#     self-generated resonance with no direct sound, which is what makes it
#     hollow / tunnel-like; blending dry restores body. Reduce feedback /
#     iterations and widen Bandwidth_Hz for an even less resonant character.
#   - CLEAN RING: the seed is band-limited to the resonance region so the loop
#     carries only in-band energy. The final Scale peak then amplifies a clean
#     pitched ring instead of a broadband noise floor (matters most at low
#     iteration counts, where a broadband seed has not yet been filtered out).
# ============================================================

form Sidechain Feedback VCA
    comment Select a Sound object - it CONTROLS the feedback circuit
    comment (use Dry/Wet below to blend the original sound back in)
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Resonance
        option Aggressive Feedback
        option Slow Evolution
        option Chaotic Burst
    
    comment === Circuit Behavior ===
    positive Base_Feedback 0.8
    positive Input_Sensitivity 0.5
    comment (higher = louder input drives more chaos)
    positive Damping_Factor 0.92
    natural Iterations 40
    
    comment === Resonance ===
    real Frequency_Offset_Hz 0.0
    positive Bandwidth_Hz 150
    positive Analog_Instability 0.05
    
    comment === Dry / Wet (0 = pure feedback / no-input-mixer, 1 = original sound) ===
    real Dry_Wet 0.3
    
    comment === Synthetic high frequencies / air (0 = off) ===
    real High_Freq_Add 0.3
    
    comment === Spatial Mode ===
    optionmenu Spatial_Mode 2
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
    comment === Debug (logs per-stage levels to the Info window) ===
    boolean Debug 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object to act as the controller."
endif

original = selected("Sound")
input_Name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
n_channels = Get number of channels

# === Debug helper: report level/shape of the currently selected Sound ===
procedure dbg: .lbl$
    if debug
        .pk = Get absolute extremum: 0, 0, "None"
        .ns = Get number of samples
        .nc = Get number of channels
        if .pk = undefined
            appendInfoLine: "  [DBG] ", .lbl$, ": *** UNDEFINED / NaN *** (samples=", .ns, ", channels=", .nc, ")"
        else
            appendInfoLine: "  [DBG] ", .lbl$, ": peak=", fixed$(.pk, 4), "  samples=", .ns, "  channels=", .nc
            if .pk > 1.5
                appendInfoLine: "  [DBG]   ^^^ peak exceeds expected bound (>1.5) ^^^"
            endif
        endif
    endif
endproc

# === Apply Presets ===
if preset = 2
    # Gentle Resonance
    base_Feedback = 0.6
    input_Sensitivity = 0.3
    damping_Factor = 0.95
    iterations = 30
    bandwidth_Hz = 200
    analog_Instability = 0.03
    presetName$ = "Gentle"
elsif preset = 3
    # Aggressive Feedback
    base_Feedback = 0.9
    input_Sensitivity = 0.7
    damping_Factor = 0.88
    iterations = 50
    bandwidth_Hz = 100
    analog_Instability = 0.08
    presetName$ = "Aggressive"
elsif preset = 4
    # Slow Evolution
    base_Feedback = 0.75
    input_Sensitivity = 0.4
    damping_Factor = 0.96
    iterations = 60
    bandwidth_Hz = 250
    analog_Instability = 0.02
    presetName$ = "SlowEvolve"
elsif preset = 5
    # Chaotic Burst
    base_Feedback = 0.95
    input_Sensitivity = 0.9
    damping_Factor = 0.85
    iterations = 40
    bandwidth_Hz = 80
    analog_Instability = 0.15
    presetName$ = "Chaotic"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Sidechain Feedback VCA ==="
appendInfoLine: "Controller: ", input_Name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# FEATURE EXTRACTION (The "Knobs")
# ============================================================

appendInfoLine: "Extracting control features..."

# A. Extract Pitch (Controls Resonance Center)
selectObject: original

if n_channels > 1
    Convert to mono
    tempMono = selected("Sound")
    To Pitch: 0.0, 75, 600
    pitch = selected("Pitch")
    removeObject: tempMono
else
    To Pitch: 0.0, 75, 600
    pitch = selected("Pitch")
endif

selectObject: pitch
mean_Pitch = Get mean: 0, 0, "Hertz"

if mean_Pitch = undefined
    mean_Pitch = 100
    appendInfoLine: "  No pitch detected. Defaulting resonance to 100 Hz."
else
    appendInfoLine: "  Detected pitch: ", fixed$(mean_Pitch, 1), " Hz"
endif

removeObject: pitch

# B. Extract Intensity (Controls Feedback Gain)
selectObject: original
To Intensity: 100, 0, "yes"
intensity = selected("Intensity")

Down to Matrix
matrix = selected("Matrix")

To Sound
controlRaw = selected("Sound")

Resample: sr, 50
vcaControl = selected("Sound")
if debug
    selectObject: vcaControl
    rawPk = Get absolute extremum: 0, 0, "None"
    appendInfoLine: "  [DBG] vcaControl raw (intensity in dB, normalized next): peak=", fixed$(rawPk, 2)
endif

removeObject: intensity, matrix, controlRaw

appendInfoLine: "  Extracted intensity envelope as VCA control"
appendInfoLine: ""

# ============================================================
# PREPARE CONTROL SIGNAL
# ============================================================

selectObject: vcaControl
Scale peak: 1.0
@dbg: "vcaControl after Scale peak 1.0"

# Apply sensitivity curve: base + (envelope * sensitivity)
base_str$ = string$(base_Feedback)
sens_str$ = string$(input_Sensitivity)
Formula: "" + base_str$ + " + (self * " + sens_str$ + ")"

# Clip to safe limits
Formula: ~ if self > 1.8 then 1.8 else self fi

# Make the control stereo so the per-channel feedback formula can read
# object[vca, row, col] for BOTH channels (a mono read from the right channel
# returns undefined in some Praat versions -> NaN -> blow-up).
selectObject: vcaControl
Convert to stereo
vcaMono = vcaControl
vcaControl = selected("Sound")
removeObject: vcaMono
if debug
    selectObject: vcaControl
    vcaPk = Get absolute extremum: 0, 0, "None"
    vcaNc = Get number of channels
    appendInfoLine: "  [DBG] vcaControl after sens+clip (max 1.8 by design): peak=", fixed$(vcaPk, 4), "  channels=", vcaNc
endif

# ============================================================
# INITIALIZE CIRCUIT
# ============================================================

appendInfoLine: "Initializing feedback loop..."

# Create ONE coherent noise seed and copy it to both channels, so the feedback
# core stays phase-coherent (independent L/R seeds produced decorrelated noise).
Create Sound from formula: "temp_noise", 1, 0, duration, sr, "randomGauss(0, 0.0001)"
noiseSeed = selected("Sound")

selectObject: noiseSeed
Copy: "temp_noise_L"
noiseL = selected("Sound")

selectObject: noiseSeed
Copy: "temp_noise_R"
noiseR = selected("Sound")

selectObject: noiseL, noiseR
Combine to stereo
stereoLoop = selected("Sound")

removeObject: noiseSeed, noiseL, noiseR

selectObject: stereoLoop
@dbg: "stereoLoop noise seed"

# Set center frequency
resonance_Center = mean_Pitch + frequency_Offset_Hz

appendInfoLine: "Resonance center: ", fixed$(resonance_Center, 1), " Hz"
appendInfoLine: ""

# Band-limit the seed to the resonance region. The loop retains its own state
# through self*damping, so a broadband seed leaves a broadband noise floor that
# the final Scale peak amplifies. Filtering the seed once keeps the whole loop
# in-band -> a clean pitched ring instead of amplified noise (no gain change).
seedLow = resonance_Center - bandwidth_Hz
seedHigh = resonance_Center + bandwidth_Hz
if seedLow < 20
    seedLow = 20
endif
selectObject: stereoLoop
Filter (pass Hann band): seedLow, seedHigh, 20
seedBandLimited = selected("Sound")
removeObject: stereoLoop
stereoLoop = seedBandLimited
selectObject: stereoLoop
@dbg: "stereoLoop seed (band-limited to clean the floor)"

# ============================================================
# THE FEEDBACK LOOP
# ============================================================

appendInfoLine: "Running ", iterations, " iterations..."

damp_str$ = string$(damping_Factor)
vca_str$ = string$(vcaControl)

if debug
    selectObject: vcaControl
    nVca = Get number of samples
    selectObject: stereoLoop
    nLoop = Get number of samples
    appendInfoLine: "  [DBG] sample counts: vcaControl=", nVca, "  stereoLoop=", nLoop, "  match=", (nVca = nLoop)
endif

for i from 1 to iterations
    # Progress indicator
    if i mod 10 = 0
        appendInfoLine: "  Iteration ", i, "/", iterations
    endif
    
    # Dynamic drift (analog instability)
    drift_hz = resonance_Center * analog_Instability
    current_freq = resonance_Center + randomGauss(0, drift_hz)
    width_drift = bandwidth_Hz * analog_Instability
    current_width = bandwidth_Hz + randomGauss(0, width_drift)
    
    # Safety clamps
    if current_freq < 50
        current_freq = 50
    endif
    if current_width < 10
        current_width = 10
    endif
    
    # Filter stage
    lowEdge = current_freq - (current_width / 2)
    highEdge = current_freq + (current_width / 2)
    if lowEdge < 20
        lowEdge = 20
    endif
    
    selectObject: stereoLoop
    Filter (pass Hann band): lowEdge, highEdge, 20
    filteredSignal = selected("Sound")
    
    # Mixing stage (VCA) with soft clipping
    # Formula: arctan((loop * damping) + (filtered * vca_control))
    selectObject: stereoLoop
    filtered_str$ = string$(filteredSignal)
    
    Formula: "2/pi * arctan((self * " + damp_str$ + ") + (object[" + filtered_str$ + ", row, col] * object[" + vca_str$ + ", row, col]))"
    
    if debug
        selectObject: stereoLoop
        loopPk = Get absolute extremum: 0, 0, "None"
        if loopPk = undefined
            appendInfoLine: "  [DBG] iter ", i, ": *** stereoLoop UNDEFINED ***  band=[", fixed$(lowEdge, 1), ", ", fixed$(highEdge, 1), "]  <- explosion source"
        elsif loopPk > 1.5 or i <= 2 or i mod 10 = 0 or i = iterations
            appendInfoLine: "  [DBG] iter ", i, ": loop peak=", fixed$(loopPk, 5), "  band=[", fixed$(lowEdge, 1), ", ", fixed$(highEdge, 1), "]"
            if loopPk > 1.5
                appendInfoLine: "  [DBG]   ^^^ exceeds bound at iter ", i, " <- explosion source ^^^"
            endif
        endif
    endif
    
    # Cleanup iteration
    removeObject: filteredSignal
endfor

appendInfoLine: ""

# ============================================================
# SPATIAL POST-PROCESSING
# ============================================================

appendInfoLine: "Applying spatial mode: ", spatial_Mode$, "..."

selectObject: stereoLoop

# Ensure stereo
nChLoop = Get number of channels
if nChLoop = 1
    Convert to stereo
    newStereo = selected("Sound")
    removeObject: stereoLoop
    stereoLoop = newStereo
endif

if spatial_Mode$ = "Mono"
    selectObject: stereoLoop
    Convert to mono
    result = selected("Sound")
    Rename: input_Name$ + "_feedback_" + presetName$
    removeObject: stereoLoop
    
else
    selectObject: stereoLoop
    Extract all channels
    chL = selected("Sound", 1)
    chR = selected("Sound", 2)
    
    if spatial_Mode$ = "Stereo Wide"
        # Widen by giving L the lows and R the highs, but keep an overlap across
        # the resonance so both channels carry the fundamental and stay balanced.
        wideLowTop = resonance_Center * 4
        if wideLowTop < 2000
            wideLowTop = 2000
        endif
        wideHighBot = resonance_Center * 0.5
        if wideHighBot < 20
            wideHighBot = 20
        endif
        selectObject: chL
        Filter (pass Hann band): 20, wideLowTop, 100
        chL_filtered = selected("Sound")
        
        selectObject: chR
        Filter (pass Hann band): wideHighBot, 20000, 100
        chR_filtered = selected("Sound")
        
    elsif spatial_Mode$ = "Rotating"
        rotation_rate = 0.2
        rot_str$ = string$(rotation_rate)
        
        selectObject: chL
        Copy: "temp_chL_rot"
        chL_filtered = selected("Sound")
        Formula: "self * (0.6 + cos(2*pi*" + rot_str$ + "*x) * 0.4)"
        
        selectObject: chR
        Copy: "temp_chR_rot"
        chR_filtered = selected("Sound")
        Formula: "self * (0.6 + sin(2*pi*" + rot_str$ + "*x) * 0.4)"
        
    elsif spatial_Mode$ = "Binaural"
        selectObject: chL
        Filter (pass Hann band): 50, 3000, 80
        chL_filtered = selected("Sound")
        
        selectObject: chR
        Copy: "temp_chR_src"
        chR_src = selected("Sound")
        selectObject: chR
        Formula: ~ if col > 30 then object[chR_src, col - 30] else 0 fi
        removeObject: chR_src
        Filter (pass Hann band): 200, 6000, 80
        chR_filtered = selected("Sound")
    endif
    
    selectObject: chL_filtered, chR_filtered
    Combine to stereo
    result = selected("Sound")
    Rename: input_Name$ + "_feedback_" + presetName$
    
    # Cleanup
    removeObject: chL_filtered, chR_filtered, chL, chR, stereoLoop
endif

# Cleanup VCA control
removeObject: vcaControl

# Scale output (wet / feedback signal)
selectObject: result
@dbg: "result (wet) before scale"
Scale peak: 0.95

# === Dry / Wet Mix ===
# The feedback signal alone is self-generated resonance with no original sound -
# that is what makes it hollow / tunnel-like. Blending the dry controller back
# in restores the direct sound. 0 = pure feedback, 1 = fully dry.
if dry_Wet > 0
    selectObject: result
    nChResult = Get number of channels

    selectObject: original
    Copy: "dry_signal"
    drySig = selected("Sound")
    nChDry = Get number of channels
    if nChDry <> nChResult
        selectObject: drySig
        if nChResult = 1
            Convert to mono
        else
            Convert to stereo
        endif
        dryConv = selected("Sound")
        removeObject: drySig
        drySig = dryConv
    endif
    selectObject: drySig
    Scale peak: 0.95

    selectObject: result
    dry_str$ = string$(drySig)
    wetGain$ = string$(1 - dry_Wet)
    dryGain$ = string$(dry_Wet)
    Formula: "self * " + wetGain$ + " + object[" + dry_str$ + ", row, col] * " + dryGain$
    removeObject: drySig

    selectObject: result
    Scale peak: 0.95
    appendInfoLine: "Mixed dry/wet: ", fixed$((1-dry_Wet)*100, 0), "% feedback / ", fixed$(dry_Wet*100, 0), "% original"
endif

# === Synthetic High Frequencies (harmonic air) ===
# The feedback resonance is inherently low/narrow. Ring-modulating by a high
# harmonic of the resonance shifts energy up into the treble (sidebands land
# near real harmonics, so it reads as air rather than a fixed tone), then we
# high-pass and blend it back in.
if high_Freq_Add > 0
    selectObject: result
    Copy: "exciter_raw"
    excRaw = selected("Sound")
    excCarrier = resonance_Center * 20
    if excCarrier < 3000
        excCarrier = 3000
    endif
    if excCarrier > 16000
        excCarrier = 16000
    endif
    carr$ = string$(excCarrier)
    Formula: "self * sin(2 * pi * " + carr$ + " * x)"
    Filter (pass Hann band): 2000, 20000, 100
    excHigh = selected("Sound")
    removeObject: excRaw
    selectObject: result
    exc_str$ = string$(excHigh)
    hfa$ = string$(high_Freq_Add * 1.2)
    Formula: "self + object[" + exc_str$ + ", row, col] * " + hfa$
    removeObject: excHigh
    Scale peak: 0.95
    appendInfoLine: "Added synthetic highs around ", fixed$(excCarrier, 0), " Hz (amount ", fixed$(high_Freq_Add, 2), ")"
endif

selectObject: result
@dbg: "result FINAL (after dry/wet mix + scale)"

if debug
    selectObject: result
    nChk = Get number of channels
    if nChk = 2
        Extract one channel: 1
        rChkL = selected("Sound")
        pkL = Get absolute extremum: 0, 0, "None"
        selectObject: result
        Extract one channel: 2
        rChkR = selected("Sound")
        pkR = Get absolute extremum: 0, 0, "None"
        removeObject: rChkL, rChkR
        appendInfoLine: "  [DBG] final per-channel peak: L=", fixed$(pkL, 4), "  R=", fixed$(pkR, 4)
    endif
    selectObject: result
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Sidechain Feedback VCA: " + input_Name$ + " (" + presetName$ + ")"
    
    # Controller input waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Controller"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Feedback Out"
    Text bottom: "yes", "Time (s)"
    
    # Signal flow diagram
    Select outer viewport: 0, 8, 2.7, 4.2
    Select inner viewport: 0.6, 7.6, 2.8, 4.1
    
    Axes: 0, 10, 0, 4
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 4
    
    Font size: 5
    
    # Input analysis
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.2, 1.5, 2.8, 3.6
    Colour: "Black"
    Text: 0.85, "centre", 3.2, "half", "Input"
    
    Draw arrow: 1.5, 3.2, 2.2, 3.5
    Draw arrow: 1.5, 3.2, 2.2, 2.9
    
    # Pitch extraction
    Paint rectangle: "{0.7, 0.8, 0.7}", 2.2, 3.2, 3.2, 3.8
    Text: 2.7, "centre", 3.5, "half", "Pitch"
    Text: 2.7, "centre", 3.1, "half", fixed$(mean_Pitch, 0) + "Hz"
    
    # Intensity extraction
    Paint rectangle: "{0.8, 0.7, 0.7}", 2.2, 3.2, 2.6, 3.1
    Text: 2.7, "centre", 2.85, "half", "Intensity"
    
    # Feedback loop box
    Paint rectangle: "{0.8, 0.8, 0.9}", 4, 8.5, 1.2, 3.8
    Colour: "{0.5, 0.5, 0.6}"
    Text: 6.25, "centre", 3.6, "half", "FEEDBACK LOOP"
    
    # Loop components
    Colour: "Black"
    Paint rectangle: "{0.6, 0.7, 0.6}", 4.3, 5.3, 2.2, 2.8
    Text: 4.8, "centre", 2.5, "half", "Filter"
    
    Draw arrow: 5.3, 2.5, 5.6, 2.5
    
    Paint rectangle: "{0.7, 0.6, 0.6}", 5.6, 6.6, 2.2, 2.8
    Text: 6.1, "centre", 2.5, "half", "VCA"
    
    Draw arrow: 6.6, 2.5, 6.9, 2.5
    
    Paint rectangle: "{0.6, 0.6, 0.7}", 6.9, 7.9, 2.2, 2.8
    Text: 7.4, "centre", 2.5, "half", "Clip"
    
    # Feedback arrow
    Colour: "{0.5, 0.5, 0.6}"
    Draw arrow: 7.9, 2.5, 8.2, 2.5
    Draw line: 8.2, 2.5, 8.2, 1.6
    Draw line: 8.2, 1.6, 4.1, 1.6
    Draw arrow: 4.1, 1.6, 4.1, 2.2
    
    # Control arrows
    Colour: "{0.5, 0.7, 0.5}"
    Draw arrow: 3.2, 3.5, 4.8, 3.0
    Font size: 4
    Text: 4.0, "centre", 3.4, "half", "freq"
    
    Colour: "{0.7, 0.5, 0.5}"
    Draw arrow: 3.2, 2.85, 6.1, 3.0
    Text: 4.7, "centre", 2.9, "half", "gain"
    
    # Output
    Colour: "Black"
    Draw arrow: 8.2, 2.5, 9.0, 2.5
    Paint rectangle: "{0.6, 0.8, 0.6}", 9.0, 9.8, 2.2, 2.8
    Text: 9.4, "centre", 2.5, "half", "Out"
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 0, 8, 4.3, 4.8
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Feedback: " + fixed$(base_Feedback, 2) + " | Sensitivity: " + fixed$(input_Sensitivity, 2) + " | Damping: " + fixed$(damping_Factor, 2) + " | Iterations: " + string$(iterations) + " | Bandwidth: " + fixed$(bandwidth_Hz, 0) + " Hz"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result