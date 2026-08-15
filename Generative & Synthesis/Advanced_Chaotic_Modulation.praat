# ============================================================
# Praat AudioTools - Advanced Chaotic Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic modulation synthesis using actual chaotic systems:
#   - Logistic map for frequency modulation
#   - Lorenz attractor for amplitude modulation
#   - Henon map for timbre / brightness modulation
#
# Review changes v0.4:
#   - Replaced unstable control-rate Lorenz Euler integration with fixed,
#     internally sub-stepped integration. The Lorenz simulation still advances
#     10 model-seconds per real second, but stability no longer depends on
#     Control_rate_Hz. This fixes Deep Chaos without saturating the attractor.
#   - Freq/Amp depth = 0 now really disables that modulation.
#   - Henon Timbre now performs actual harmonic-colour modulation instead of
#     merely duplicating FM/AM behaviour.
#   - Resamples instantaneous frequency, then integrates phase at audio rate;
#     avoids interpolation of an already accumulated control-rate phase.
#   - Carrier and harmonic generation are Nyquist-aware.
#   - Formula object access uses numeric object IDs, not dynamic Sound names.
#   - Stereo Wide filters adapt to sample rate; Rotating uses complementary
#     equal-power panning.
#   - Visualization shows actual chaotic driver(s), actual oscillator-frequency
#     paths, measured output, and model paths over the measured spectrogram.
#   - Added realized-range / numerical-stability QC in Info and figure.
# ============================================================

form Advanced Chaotic Modulation
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Logistic
        option Lorenz Drift
        option Henon Stutter
        option Combined Attractors
        option Chaotic Bells
        option Insect Chorus
        option Deep Chaos

    comment === Basic Settings ===
    positive Duration_s 12
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 150
    integer Number_of_layers 3

    comment === Chaos Parameters ===
    real Logistic_r 3.9
    real Lorenz_sigma 10
    real Lorenz_rho 28
    real Lorenz_beta 2.667
    real Henon_a 1.4
    real Henon_b 0.3

    comment === Modulation ===
    real Freq_mod_depth 0.5
    real Amp_mod_depth 0.5
    real Timbre_mod_depth 0.5
    positive Control_rate_Hz 500

    comment === Synthesis Mode ===
    optionmenu Synthesis_mode 1
        option Logistic FM
        option Lorenz AM
        option Henon Timbre
        option Combined Chaos
        option Layered Attractors

    comment === Output ===
    positive Fade_time_s 2
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------

preset_name$ = "Custom"

if preset = 2
    duration_s = 10
    base_frequency_Hz = 220
    number_of_layers = 2
    logistic_r = 3.7
    freq_mod_depth = 0.3
    amp_mod_depth = 0.2
    timbre_mod_depth = 0.1
    synthesis_mode = 1
    spatial_mode = 1
    preset_name$ = "GentleLogistic"

elsif preset = 3
    duration_s = 15
    base_frequency_Hz = 110
    number_of_layers = 3
    lorenz_sigma = 10
    lorenz_rho = 28
    lorenz_beta = 2.667
    freq_mod_depth = 0.2
    amp_mod_depth = 0.6
    timbre_mod_depth = 0.1
    synthesis_mode = 2
    spatial_mode = 3
    preset_name$ = "LorenzDrift"

elsif preset = 4
    duration_s = 8
    base_frequency_Hz = 300
    number_of_layers = 4
    henon_a = 1.4
    henon_b = 0.3
    freq_mod_depth = 0.4
    amp_mod_depth = 0.7
    timbre_mod_depth = 0.8
    synthesis_mode = 3
    spatial_mode = 2
    preset_name$ = "HenonStutter"

elsif preset = 5
    duration_s = 12
    base_frequency_Hz = 180
    number_of_layers = 3
    logistic_r = 3.95
    lorenz_rho = 25
    freq_mod_depth = 0.5
    amp_mod_depth = 0.5
    timbre_mod_depth = 0.5
    synthesis_mode = 4
    spatial_mode = 3
    preset_name$ = "CombinedAttractors"

elsif preset = 6
    duration_s = 10
    base_frequency_Hz = 440
    number_of_layers = 5
    logistic_r = 3.85
    freq_mod_depth = 0.15
    amp_mod_depth = 0.4
    timbre_mod_depth = 0.45
    synthesis_mode = 5
    spatial_mode = 2
    preset_name$ = "ChaoticBells"

elsif preset = 7
    duration_s = 8
    base_frequency_Hz = 800
    number_of_layers = 6
    logistic_r = 3.99
    henon_a = 1.35
    freq_mod_depth = 0.6
    amp_mod_depth = 0.8
    timbre_mod_depth = 0.6
    control_rate_Hz = 800
    synthesis_mode = 4
    spatial_mode = 2
    preset_name$ = "InsectChorus"

elsif preset = 8
    duration_s = 20
    base_frequency_Hz = 55
    number_of_layers = 2
    lorenz_sigma = 12
    lorenz_rho = 30
    freq_mod_depth = 0.3
    amp_mod_depth = 0.7
    timbre_mod_depth = 0.1
    control_rate_Hz = 200
    synthesis_mode = 2
    spatial_mode = 3
    fade_time_s = 4
    preset_name$ = "DeepChaos"
endif

# ---------------------------------------------------------------------------
# Validation / guards
# ---------------------------------------------------------------------------

if sample_rate_Hz < 4000
    exitScript: "Sample rate must be at least 4000 Hz."
endif

if number_of_layers > 8
    number_of_layers = 8
elsif number_of_layers < 1
    number_of_layers = 1
endif

if fade_time_s > duration_s / 2
    fade_time_s = duration_s / 2
endif

if logistic_r > 4
    logistic_r = 4
elsif logistic_r < 0
    logistic_r = 0
endif

if lorenz_sigma <= 0 or lorenz_rho <= 0 or lorenz_beta <= 0
    exitScript: "Lorenz sigma, rho and beta must all be positive."
endif

if freq_mod_depth < 0
    freq_mod_depth = 0
elsif freq_mod_depth > 1
    freq_mod_depth = 1
endif

if amp_mod_depth < 0
    amp_mod_depth = 0
elsif amp_mod_depth > 1
    amp_mod_depth = 1
endif

if timbre_mod_depth < 0
    timbre_mod_depth = 0
elsif timbre_mod_depth > 1
    timbre_mod_depth = 1
endif

if control_rate_Hz > sample_rate_Hz / 2
    control_rate_Hz = sample_rate_Hz / 2
endif

# ---------------------------------------------------------------------------
# Constants / numerical policy
# ---------------------------------------------------------------------------

uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
nyquist = sample_rate_Hz / 2
safeTop = 0.45 * sample_rate_Hz

# Lorenz physical time advances 10x real time, as in v0.3.
# Internally integrate with steps <= 0.005 model-seconds so the attractor
# no longer changes numerical stability when Control_rate_Hz changes.
lorenzFrameDt = 10 / control_rate_Hz
lorenzSubsteps = ceiling(lorenzFrameDt / 0.005)
if lorenzSubsteps < 1
    lorenzSubsteps = 1
endif
lorenzDt = lorenzFrameDt / lorenzSubsteps

globalFreqMin = 1e30
globalFreqMax = 0
globalAmpMin = 1e30
globalAmpMax = 0
lorenzClampCount = 0
henonResetCount = 0
hasTimbre = 0

# ---------------------------------------------------------------------------
# Info
# ---------------------------------------------------------------------------

writeInfoLine: "=== Advanced Chaotic Modulation v0.4 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s, 3), " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Mode: ", synthesis_mode$
appendInfoLine: "Control rate: ", fixed$(control_rate_Hz, 1), " Hz"
appendInfoLine: "Lorenz internal substeps/frame: ", lorenzSubsteps
appendInfoLine: ""

# ---------------------------------------------------------------------------
# Create output
# ---------------------------------------------------------------------------

outputSound = Create Sound from formula: "chaos_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Control objects are retained until visualization so the figure can show the
# exact trajectories used by the DSP. They are removed before final return.

# ---------------------------------------------------------------------------
# Process each layer
# ---------------------------------------------------------------------------

for layer to number_of_layers
    appendInfoLine: "Layer ", layer, "/", number_of_layers, "..."

    layerType = (layer - 1) mod 3

    if synthesis_mode = 5
        layerFreq = base_frequency_Hz * layer
        layerAmp = (0.6 / number_of_layers) / sqrt(layer)
    else
        layerFreq = base_frequency_Hz * (0.9 + layer * 0.2)
        layerAmp = 0.6 / number_of_layers
    endif

    layerHasTimbre = 0
    if synthesis_mode = 3 or synthesis_mode = 4
        layerHasTimbre = 1
    elsif synthesis_mode = 5 and layerType = 2
        layerHasTimbre = 1
    endif

    if layerHasTimbre = 1
        # Reserve headroom for the third harmonic.
        maxCarrierFreq = safeTop / 3
        hasTimbre = 1
    else
        maxCarrierFreq = safeTop
    endif

    layerTag$ = uid$ + "_" + string$(layer)

    instFreqCtrl = Create Sound from formula: "instFreq_" + layerTag$, 1, 0, duration_s, control_rate_Hz, "0"
    ampModCtrl = Create Sound from formula: "ampMod_" + layerTag$, 1, 0, duration_s, control_rate_Hz, "0"
    timbreCtrl = Create Sound from formula: "timbre_" + layerTag$, 1, 0, duration_s, control_rate_Hz, "0"
    driverCtrl = Create Sound from formula: "driver_" + layerTag$, 1, 0, duration_s, control_rate_Hz, "0"

    vizFreq[layer] = instFreqCtrl
    vizAmp[layer] = ampModCtrl
    vizTimbre[layer] = timbreCtrl
    vizDriver[layer] = driverCtrl

    selectObject: instFreqCtrl
    nControlPoints = Get number of samples

    # Deterministic, layer-dependent initial conditions.
    logX = 0.1 + layer * 0.1
    if logX > 0.9
        logX = 0.9
    endif

    lorX = 1.0 + layer * 0.5
    lorY = 1.0 + layer * 0.3
    lorZ = 1.0 + layer * 0.7

    henSeedX = 0.1 + layer * 0.05
    henSeedY = 0.1 + layer * 0.03
    henX = henSeedX
    henY = henSeedY

    for cp to nControlPoints

        # ---------------- LOGISTIC ----------------
        logX = logistic_r * logX * (1 - logX)
        logNorm = (logX - 0.5) * 2
        if logNorm > 1
            logNorm = 1
        elsif logNorm < -1
            logNorm = -1
        endif

        # ---------------- LORENZ ----------------
        for ls to lorenzSubsteps
            dlorX = lorenz_sigma * (lorY - lorX) * lorenzDt
            dlorY = (lorX * (lorenz_rho - lorZ) - lorY) * lorenzDt
            dlorZ = (lorX * lorY - lorenz_beta * lorZ) * lorenzDt

            lorX = lorX + dlorX
            lorY = lorY + dlorY
            lorZ = lorZ + dlorZ

            # Emergency numerical guard for pathological Custom parameters.
            # Standard presets remain far inside this range.
            if lorX > 1000
                lorX = 1000
                lorenzClampCount = lorenzClampCount + 1
            elsif lorX < -1000
                lorX = -1000
                lorenzClampCount = lorenzClampCount + 1
            endif
            if lorY > 1000
                lorY = 1000
                lorenzClampCount = lorenzClampCount + 1
            elsif lorY < -1000
                lorY = -1000
                lorenzClampCount = lorenzClampCount + 1
            endif
            if lorZ > 1000
                lorZ = 1000
                lorenzClampCount = lorenzClampCount + 1
            elsif lorZ < -1000
                lorZ = -1000
                lorenzClampCount = lorenzClampCount + 1
            endif
        endfor

        lorNorm = lorX / 20
        if lorNorm > 1
            lorNorm = 1
        elsif lorNorm < -1
            lorNorm = -1
        endif

        # ---------------- HENON ----------------
        henXnew = 1 - henon_a * henX * henX + henY
        henYnew = henon_b * henX
        henX = henXnew
        henY = henYnew

        if henX > 2 or henX < -2
            henX = henSeedX
            henY = henSeedY
            henonResetCount = henonResetCount + 1
        endif

        henNorm = henX / 1.5
        if henNorm > 1
            henNorm = 1
        elsif henNorm < -1
            henNorm = -1
        endif

        # ---------------- MAP -> SYNTHESIS CONTROLS ----------------
        timbreMix = 0

        if synthesis_mode = 1
            # Logistic FM
            freqMod = logNorm * freq_mod_depth
            ampMod = 1
            activeDriver = logNorm

        elsif synthesis_mode = 2
            # Lorenz AM
            freqMod = 0
            ampMod = 1 + 0.5 * amp_mod_depth * lorNorm
            activeDriver = lorNorm

        elsif synthesis_mode = 3
            # Henon Timbre: modest FM/AM plus explicit harmonic-colour control.
            freqMod = 0.5 * henNorm * freq_mod_depth
            ampMod = 1 + 0.25 * amp_mod_depth * henNorm
            timbreMix = 0.5 * (henNorm + 1) * timbre_mod_depth
            activeDriver = henNorm

        elsif synthesis_mode = 4
            # Combined: Logistic -> FM, Lorenz/Henon -> AM, Henon -> colour.
            freqMod = 0.5 * logNorm * freq_mod_depth
            ampDriver = 0.65 * lorNorm + 0.35 * henNorm
            ampMod = 1 + 0.5 * amp_mod_depth * ampDriver
            timbreMix = 0.35 * 0.5 * (henNorm + 1) * timbre_mod_depth
            activeDriver = (logNorm + lorNorm + henNorm) / 3

        else
            # Layered Attractors: map cycles Logistic -> Lorenz -> Henon.
            if layerType = 0
                freqMod = 0.5 * logNorm * freq_mod_depth
                ampMod = 1 + 0.30 * amp_mod_depth * logNorm
                activeDriver = logNorm

            elsif layerType = 1
                freqMod = 0.30 * lorNorm * freq_mod_depth
                ampMod = 1 + 0.50 * amp_mod_depth * lorNorm
                activeDriver = lorNorm

            else
                freqMod = 0.50 * henNorm * freq_mod_depth
                ampMod = 1 + 0.25 * amp_mod_depth * henNorm
                timbreMix = 0.5 * (henNorm + 1) * timbre_mod_depth
                activeDriver = henNorm
            endif
        endif

        # Depth 0 now means exactly no AM; positive depths remain bounded.
        if ampMod < 0.05
            ampMod = 0.05
        elsif ampMod > 1.5
            ampMod = 1.5
        endif

        instFreq = layerFreq * (1 + freqMod)
        if instFreq < 20
            instFreq = 20
        elsif instFreq > maxCarrierFreq
            instFreq = maxCarrierFreq
        endif

        if instFreq < globalFreqMin
            globalFreqMin = instFreq
        endif
        if instFreq > globalFreqMax
            globalFreqMax = instFreq
        endif
        if ampMod < globalAmpMin
            globalAmpMin = ampMod
        endif
        if ampMod > globalAmpMax
            globalAmpMax = ampMod
        endif

        selectObject: instFreqCtrl
        Set value at sample number: 1, cp, instFreq

        selectObject: ampModCtrl
        Set value at sample number: 1, cp, ampMod * layerAmp

        selectObject: timbreCtrl
        Set value at sample number: 1, cp, timbreMix

        selectObject: driverCtrl
        Set value at sample number: 1, cp, activeDriver
    endfor

    # -----------------------------------------------------------------------
    # Control-rate -> audio-rate; integrate PHASE only after frequency is at
    # audio rate. Formula modification is left-to-right, so self[col-1] is a
    # true recursive integrator.
    # -----------------------------------------------------------------------

    selectObject: instFreqCtrl
    freqAudio = Resample: sample_rate_Hz, 50
    # Sinc interpolation can overshoot an abrupt control path; restore the
    # physical carrier bounds after interpolation.
    Formula: "if self < 20 then 20 else if self > maxCarrierFreq then maxCarrierFreq else self fi fi"

    selectObject: ampModCtrl
    ampAudio = Resample: sample_rate_Hz, 50
    layerAmpTop = 1.5 * layerAmp
    Formula: "if self < 0 then 0 else if self > layerAmpTop then layerAmpTop else self fi fi"

    selectObject: timbreCtrl
    timbreAudio = Resample: sample_rate_Hz, 50
    Formula: "if self < 0 then 0 else if self > 1 then 1 else self fi fi"

    phaseAudio = Create Sound from formula: "phase_" + layerTag$, 1, 0, duration_s, sample_rate_Hz, "0"
    freqAudioId$ = string$(freqAudio)

    selectObject: phaseAudio
    Formula: "if col = 1 then twoPi * object[" + freqAudioId$ + ", 1, col] * dx else self[col - 1] + twoPi * object[" + freqAudioId$ + ", 1, col] * dx fi"

    # -----------------------------------------------------------------------
    # Layer oscillator. Henon-related modes get a real, modest harmonic-colour
    # modulation. Carrier was capped at 0.45*SR/3 when these harmonics are used.
    # -----------------------------------------------------------------------

    ampAudioId$ = string$(ampAudio)
    phaseAudioId$ = string$(phaseAudio)
    timbreAudioId$ = string$(timbreAudio)

    if layerHasTimbre = 1
        layerSound = Create Sound from formula: "layer_" + layerTag$, 1, 0, duration_s, sample_rate_Hz, "object[" + ampAudioId$ + ", 1, col] * ((1 - 0.30 * object[" + timbreAudioId$ + ", 1, col]) * sin(object[" + phaseAudioId$ + ", 1, col]) + 0.22 * object[" + timbreAudioId$ + ", 1, col] * sin(2 * object[" + phaseAudioId$ + ", 1, col]) + 0.10 * object[" + timbreAudioId$ + ", 1, col] * sin(3 * object[" + phaseAudioId$ + ", 1, col]))"
    else
        layerSound = Create Sound from formula: "layer_" + layerTag$, 1, 0, duration_s, sample_rate_Hz, "object[" + ampAudioId$ + ", 1, col] * sin(object[" + phaseAudioId$ + ", 1, col])"
    endif

    layerSoundId$ = string$(layerSound)

    selectObject: outputSound
    Formula: "self + object[" + layerSoundId$ + ", 1, col]"

    removeObject: freqAudio, ampAudio, timbreAudio, phaseAudio, layerSound
endfor

# ---------------------------------------------------------------------------
# Envelope
# ---------------------------------------------------------------------------

appendInfoLine: "Applying envelope..."
selectObject: outputSound

if fade_time_s > 0
    Formula: "if x < fade_time_s then self * (x / fade_time_s) else self fi"
    fadeOutStart = duration_s - fade_time_s
    Formula: "if x > fadeOutStart then self * ((duration_s - x) / fade_time_s) else self fi"
endif

# ---------------------------------------------------------------------------
# Spatial processing
# ---------------------------------------------------------------------------

if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."

    stereoTop = min(8000, safeTop)
    stereoSplit = min(4000, 0.55 * stereoTop)
    stereoLow = min(200, 0.10 * stereoTop)
    stereoSmooth = min(100, 0.05 * stereoTop)

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): 0, stereoSplit, stereoSmooth
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * 0.8"
    Filter (pass Hann band): stereoLow, stereoTop, stereoSmooth
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered

    selectObject: leftSound, rightSound
    stereoSound = Combine to stereo
    Rename: "chaotic_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating equal-power rotating stereo..."

    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * cos(0.5 * pi * (0.5 + 0.5 * sin(twoPi * 0.15 * x)))"

    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * sin(0.5 * pi * (0.5 + 0.5 * sin(twoPi * 0.15 * x)))"

    selectObject: leftSound, rightSound
    stereoSound = Combine to stereo
    Rename: "chaotic_" + preset_name$

    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

else
    selectObject: outputSound
    Rename: "chaotic_" + preset_name$
endif

# ---------------------------------------------------------------------------
# Final normalization / QC
# ---------------------------------------------------------------------------

if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

selectObject: outputSound
outputPeak = Get absolute extremum: 0, 0, "none"
outputChannels = Get number of channels

appendInfoLine: ""
appendInfoLine: "Realized carrier range: ", fixed$(globalFreqMin, 2), " - ", fixed$(globalFreqMax, 2), " Hz"
appendInfoLine: "Realized AM multiplier range: ", fixed$(globalAmpMin, 3), " - ", fixed$(globalAmpMax, 3)
appendInfoLine: "Lorenz numerical clamps: ", lorenzClampCount
appendInfoLine: "Henon escape resets: ", henonResetCount
appendInfoLine: "Output peak: ", fixed$(outputPeak, 4)

# ---------------------------------------------------------------------------
# Visualization
# ---------------------------------------------------------------------------

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawChaosFigure: duration_s
endif

# Remove control objects retained for the research visualization.
for layer to number_of_layers
    removeObject: vizFreq[layer], vizAmp[layer], vizTimbre[layer], vizDriver[layer]
endfor

# ---------------------------------------------------------------------------
# Play / final selection
# ---------------------------------------------------------------------------

if play_result
    selectObject: outputSound
    Play
endif

selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# =============================================================================
# Procedure: drawChaosFigure
# =============================================================================

procedure drawChaosFigure: .duration

    Erase all

    .blue$ = "{0.20, 0.45, 0.68}"
    .red$ = "{0.72, 0.35, 0.32}"
    .green$ = "{0.32, 0.58, 0.42}"
    .purple$ = "{0.52, 0.40, 0.65}"
    .grey$ = "{0.42, 0.42, 0.45}"
    .light$ = "{0.965, 0.965, 0.970}"

    if .duration <= 2
        .timeTick = 0.2
    elsif .duration <= 5
        .timeTick = 0.5
    elsif .duration <= 12
        .timeTick = 1
    else
        .timeTick = 2
    endif

    # ---------------------------------------------------------------------
    # TITLE + metadata: own text viewports, axes reset to 0..1.
    # ---------------------------------------------------------------------

    Select inner viewport: 0, 8, 0.08, 0.43
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "Advanced Chaotic Modulation | " + preset_name$

    Select inner viewport: 0, 8, 0.44, 0.68
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: .grey$
    Text: 0.5, "centre", 0.52, "half", synthesis_mode$ + " | " + string$(number_of_layers) + " layers | control " + fixed$(control_rate_Hz, 0) + " Hz | " + spatial_mode$

    # ---------------------------------------------------------------------
    # Representative display channel. Never fold stereo to mono.
    # ---------------------------------------------------------------------

    if outputChannels = 2
        selectObject: outputSound
        Extract one channel: 1
        .dispLeft = selected("Sound")
        .rmsLeft = Get root-mean-square: 0, 0

        selectObject: outputSound
        Extract one channel: 2
        .dispRight = selected("Sound")
        .rmsRight = Get root-mean-square: 0, 0

        if .rmsRight > .rmsLeft
            removeObject: .dispLeft
            .disp = .dispRight
            .displayLabel$ = "Output R (stronger channel)"
        else
            removeObject: .dispRight
            .disp = .dispLeft
            .displayLabel$ = "Output L (stronger channel)"
        endif
    else
        selectObject: outputSound
        Copy: "disp_" + uid$
        .disp = selected("Sound")
        .displayLabel$ = "Output mono"
    endif

    # ---------------------------------------------------------------------
    # PANEL A: output waveform with explicit symmetric scale
    # ---------------------------------------------------------------------

    Select inner viewport: 0.55, 7.65, 0.82, 1.02
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "A | Measured output waveform"

    selectObject: .disp
    .wavePeak = Get absolute extremum: 0, 0, "none"
    if .wavePeak <= 0
        .wavePeak = 1
    endif
    .waveRange = 1.05 * .wavePeak

    Select inner viewport: 0.72, 7.62, 1.06, 1.75
    Axes: 0, .duration, -.waveRange, .waveRange
    Paint rectangle: .light$, 0, .duration, -.waveRange, .waveRange
    Colour: "{0.60, 0.60, 0.64}"
    Draw line: 0, 0, .duration, 0
    selectObject: .disp
    Colour: .blue$
    Draw: 0, .duration, -.waveRange, .waveRange, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks bottom every: 1, .timeTick, "no", "yes", "yes"
    Text left: "yes", .displayLabel$

    # ---------------------------------------------------------------------
    # PANEL B: actual chaotic driver(s)
    # ---------------------------------------------------------------------

    Select inner viewport: 0.55, 7.65, 1.90, 2.10
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "B | Actual chaotic control trajectory"

    Select inner viewport: 0.72, 7.62, 2.14, 2.98
    Axes: 0, .duration, -1.1, 1.1
    Paint rectangle: .light$, 0, .duration, -1.1, 1.1
    Colour: "{0.78, 0.78, 0.80}"
    Draw line: 0, 0, .duration, 0

    .driverLayers = 1
    if synthesis_mode = 5
        .driverLayers = min(3, number_of_layers)
    endif

    for .layer to .driverLayers
        selectObject: vizDriver[.layer]
        if .layer = 1
            Colour: .blue$
        elsif .layer = 2
            Colour: .red$
        else
            Colour: .green$
        endif
        Draw: 0, .duration, -1.1, 1.1, "no", "Curve"
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left every: 1, 0.5, "yes", "yes", "yes"
    Marks bottom every: 1, .timeTick, "no", "yes", "yes"

    if synthesis_mode = 1
        .driverLabel$ = "Logistic normalized"
    elsif synthesis_mode = 2
        .driverLabel$ = "Lorenz x / 20"
    elsif synthesis_mode = 3
        .driverLabel$ = "Henon x / 1.5"
    elsif synthesis_mode = 4
        .driverLabel$ = "Combined driver"
    else
        .driverLabel$ = "L1/L2/L3: Log/Lor/Hen"
    endif
    Text left: "yes", .driverLabel$

    # ---------------------------------------------------------------------
    # PANEL C: actual oscillator-frequency paths used by the DSP
    # ---------------------------------------------------------------------

    .freqTop = globalFreqMax * 1.08
    if .freqTop < 100
        .freqTop = 100
    endif
    .freqBottom = max(0, globalFreqMin * 0.85)

    Select inner viewport: 0.55, 7.65, 3.13, 3.33
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "C | Instantaneous carrier paths used for synthesis"

    Select inner viewport: 0.72, 7.62, 3.37, 4.27
    Axes: 0, .duration, .freqBottom, .freqTop
    Paint rectangle: .light$, 0, .duration, .freqBottom, .freqTop

    for .layer to number_of_layers
        selectObject: vizFreq[.layer]
        .colourIndex = (.layer - 1) mod 4
        if .colourIndex = 0
            Colour: .blue$
        elsif .colourIndex = 1
            Colour: .red$
        elsif .colourIndex = 2
            Colour: .green$
        else
            Colour: .purple$
        endif
        Draw: 0, .duration, .freqBottom, .freqTop, "no", "Curve"
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 5, "yes", "yes", "yes"
    Marks bottom every: 1, .timeTick, "no", "yes", "yes"
    Text left: "yes", "Carrier Hz"

    # ---------------------------------------------------------------------
    # PANEL D: measured spectrogram + SAME model paths.
    # ---------------------------------------------------------------------

    if hasTimbre = 1
        .spectralFactor = 3.25
    else
        .spectralFactor = 1.6
    endif

    .maxFreqSpec = min(0.48 * sample_rate_Hz, max(1500, globalFreqMax * .spectralFactor))

    Select inner viewport: 0.55, 7.65, 4.42, 4.62
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.52, "half", "D | Measured spectrogram + model carrier paths"

    Select inner viewport: 0.72, 7.62, 4.66, 6.12
    selectObject: .disp
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, .duration, 0, .maxFreqSpec, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec

    # IMPORTANT: reselect inner viewport and axes after Paint before data-world
    # overlays, because Picture commands can leave inherited viewport state.
    Select inner viewport: 0.72, 7.62, 4.66, 6.12
    Axes: 0, .duration, 0, .maxFreqSpec

    for .layer to number_of_layers
        selectObject: vizFreq[.layer]
        .colourIndex = (.layer - 1) mod 4
        if .colourIndex = 0
            Colour: .blue$
        elsif .colourIndex = 1
            Colour: .red$
        elsif .colourIndex = 2
            Colour: .green$
        else
            Colour: .purple$
        endif
        Draw: 0, .duration, 0, .maxFreqSpec, "no", "Curve"
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 5, "yes", "yes", "yes"
    Marks bottom every: 1, .timeTick, "yes", "yes", "yes"
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    removeObject: .disp

    # ---------------------------------------------------------------------
    # PROCESS STRIP
    # ---------------------------------------------------------------------

    Select inner viewport: 0.38, 7.62, 6.32, 6.86
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.945}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text: 0.5, "centre", 0.68, "half", "CHAOTIC MAPS  ->  f(t), A(t), colour(t)  ->  audio-rate phase integration  ->  oscillator layers  ->  spatial render"
    Colour: .grey$
    Text: 0.5, "centre", 0.28, "half", "phase[n] = phase[n-1] + 2*pi*f[n]*dt"

    # ---------------------------------------------------------------------
    # SUMMARY / QC STRIP
    # ---------------------------------------------------------------------

    Select inner viewport: 0.38, 7.62, 7.02, 7.58
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.955, 0.955, 0.958}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 5
    Colour: .grey$
    Text: 0.5, "centre", 0.68, "half", "Carrier " + fixed$(globalFreqMin, 1) + "-" + fixed$(globalFreqMax, 1) + " Hz | AM " + fixed$(globalAmpMin, 2) + "-" + fixed$(globalAmpMax, 2) + " | Lorenz substeps " + string$(lorenzSubsteps)
    Text: 0.5, "centre", 0.28, "half", "Lorenz clamps " + string$(lorenzClampCount) + " | Henon resets " + string$(henonResetCount) + " | Peak " + fixed$(outputPeak, 3) + " | " + spatial_mode$

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
