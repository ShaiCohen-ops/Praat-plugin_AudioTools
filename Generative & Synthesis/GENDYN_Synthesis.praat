# ============================================================
# Praat AudioTools - GENDYN_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Optimized
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   GENDYN (Génération Dynamique) Synthesis
#   A tribute to Iannis Xenakis and his groundbreaking work GENDY3 (1991)
#
#   "I wanted to make music starting from the very roots of sound,
#    from the waveform itself." — Iannis Xenakis
#
#   GENDYN defines a waveform as N breakpoints with amplitudes and
#   time intervals. Both evolve via stochastic random walks, creating
#   continuously morphing timbres impossible to achieve otherwise.
#
# Algorithm:
#   1. Initialize N breakpoints with amplitudes a[i] and durations d[i]
#   2. Linear interpolate between breakpoints to create one waveform period
#   3. After each period, apply random walks to all a[i] and d[i]
#   4. Apply elastic barriers to keep values bounded
#   5. Repeat with evolved waveform
#
# Reference:
#   Xenakis, I. (1992). Formalized Music. Pendragon Press.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit 
#   for Experimental Composition.
# ============================================================

form GENDYN Synthesis (Tribute to Xenakis)
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option GENDY3 Tribute
        option Insect Swarm
        option Deep Mutations
        option Crystalline Fractures
        option Slow Evolution
        option Chaotic Bursts
        option Whispered Stochasm
        option Electronic Organisms
    
    comment === Basic Settings ===
    positive Duration_s 12.0
    integer Sample_rate_Hz 44100
    
    comment === Breakpoint Configuration ===
    integer Number_of_breakpoints 12
    positive Base_frequency_Hz 180
    real Frequency_range 2.0
    
    comment === Stochastic Parameters ===
    real Amplitude_step 0.15
    real Duration_step 0.12
    optionmenu Distribution_type 2
        option Uniform
        option Cauchy (Xenakis)
        option Gaussian
        option Logistic
    
    comment === Barrier Settings ===
    real Amplitude_barrier 0.95
    real Min_frequency_Hz 20
    real Max_frequency_Hz 2000
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Dual
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # GENDY3 Tribute
    duration_s = 12.0
    number_of_breakpoints = 12
    base_frequency_Hz = 180
    frequency_range = 2.5
    amplitude_step = 0.18
    duration_step = 0.15
    distribution_type = 2
    amplitude_barrier = 0.92
    min_frequency_Hz = 30
    max_frequency_Hz = 1500
    spatial_mode = 2
    preset_name$ = "GENDY3_Tribute"
    
elsif preset = 3
    # Insect Swarm
    duration_s = 8.0
    number_of_breakpoints = 8
    base_frequency_Hz = 400
    frequency_range = 1.5
    amplitude_step = 0.25
    duration_step = 0.20
    distribution_type = 2
    min_frequency_Hz = 100
    max_frequency_Hz = 3000
    spatial_mode = 3
    preset_name$ = "InsectSwarm"
    
elsif preset = 4
    # Deep Mutations
    duration_s = 20.0
    number_of_breakpoints = 16
    base_frequency_Hz = 60
    frequency_range = 1.8
    amplitude_step = 0.10
    duration_step = 0.08
    distribution_type = 3
    min_frequency_Hz = 20
    max_frequency_Hz = 400
    spatial_mode = 2
    preset_name$ = "DeepMutations"
    
elsif preset = 5
    # Crystalline Fractures
    duration_s = 10.0
    number_of_breakpoints = 10
    base_frequency_Hz = 800
    frequency_range = 2.0
    amplitude_step = 0.20
    duration_step = 0.18
    distribution_type = 2
    min_frequency_Hz = 200
    max_frequency_Hz = 4000
    spatial_mode = 3
    preset_name$ = "CrystallineFractures"
    
elsif preset = 6
    # Slow Evolution
    duration_s = 30.0
    number_of_breakpoints = 20
    base_frequency_Hz = 100
    frequency_range = 1.2
    amplitude_step = 0.05
    duration_step = 0.04
    distribution_type = 3
    min_frequency_Hz = 30
    max_frequency_Hz = 500
    spatial_mode = 2
    preset_name$ = "SlowEvolution"
    
elsif preset = 7
    # Chaotic Bursts
    duration_s = 8.0
    number_of_breakpoints = 8
    base_frequency_Hz = 200
    frequency_range = 4.0
    amplitude_step = 0.35
    duration_step = 0.30
    distribution_type = 2
    min_frequency_Hz = 40
    max_frequency_Hz = 2500
    spatial_mode = 3
    preset_name$ = "ChaoticBursts"
    
elsif preset = 8
    # Whispered Stochasm
    duration_s = 15.0
    number_of_breakpoints = 14
    base_frequency_Hz = 150
    frequency_range = 1.5
    amplitude_step = 0.08
    duration_step = 0.06
    distribution_type = 4
    amplitude_barrier = 0.6
    min_frequency_Hz = 50
    max_frequency_Hz = 800
    spatial_mode = 2
    preset_name$ = "WhisperedStochasm"
    
elsif preset = 9
    # Electronic Organisms
    duration_s = 12.0
    number_of_breakpoints = 12
    base_frequency_Hz = 120
    frequency_range = 2.2
    amplitude_step = 0.12
    duration_step = 0.10
    distribution_type = 4
    min_frequency_Hz = 40
    max_frequency_Hz = 1000
    spatial_mode = 3
    preset_name$ = "ElectronicOrganisms"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# Control rate - high enough to capture waveform shape
controlRate = max(8000, base_frequency_Hz * number_of_breakpoints * 2)
if controlRate > 22050
    controlRate = 22050
endif

nControlSamples = round(duration_s * controlRate)

# === Info ===
writeInfoLine: "=============================================="
writeInfoLine: "  GENDYN SYNTHESIS"
writeInfoLine: "  A Tribute to Iannis Xenakis (1922-2001)"
writeInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Breakpoints: ", number_of_breakpoints
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Control rate: ", controlRate, " Hz"
appendInfoLine: "Distribution: ", distribution_type$
appendInfoLine: ""

# === Initialize breakpoints ===
appendInfoLine: "Initializing breakpoints..."

# Amplitudes
for bp to number_of_breakpoints
    amp[bp] = randomUniform(-0.5, 0.5)
endfor

# Durations as fractions (will be scaled by current frequency)
for bp to number_of_breakpoints
    dur[bp] = 1.0 / number_of_breakpoints
endfor

# Current frequency
currentFreq = base_frequency_Hz

# Second voice for stereo
if spatial_mode >= 2
    for bp to number_of_breakpoints
        amp2[bp] = randomUniform(-0.5, 0.5)
        dur2[bp] = 1.0 / number_of_breakpoints
    endfor
    currentFreq2 = base_frequency_Hz * (1 + 0.05 * randomUniform(-1, 1))
endif

# === Create control-rate sound ===
appendInfoLine: "Creating control-rate buffer..."
ctrlSound = Create Sound from formula: "ctrl_" + uid$, 1, 0, duration_s, controlRate, "0"

if spatial_mode >= 2
    ctrlSound2 = Create Sound from formula: "ctrl2_" + uid$, 1, 0, duration_s, controlRate, "0"
endif

# === Main synthesis at control rate ===
appendInfoLine: "Synthesizing GENDYN (this may take a moment)..."

# Phase through the breakpoint waveform [0, 1)
phase = 0
generation = 0
lastReportTime = 0

if spatial_mode >= 2
    phase2 = 0
    generation2 = 0
endif

for cs to nControlSamples
    currentTime = (cs - 1) / controlRate
    
    # === Voice 1 ===
    # Find current segment and interpolate
    cumDur = 0
    value = 0
    for bp to number_of_breakpoints
        nextCumDur = cumDur + dur[bp]
        if phase >= cumDur and phase < nextCumDur
            # Found segment
            nextBp = bp + 1
            if nextBp > number_of_breakpoints
                nextBp = 1
            endif
            
            # Local phase within segment [0, 1)
            if dur[bp] > 0
                localPhase = (phase - cumDur) / dur[bp]
            else
                localPhase = 0
            endif
            
            # Linear interpolation
            value = amp[bp] + (amp[nextBp] - amp[bp]) * localPhase
            
            bp = number_of_breakpoints
        endif
        cumDur = nextCumDur
    endfor
    
    selectObject: ctrlSound
    Set value at sample number: 1, cs, value
    
    # Advance phase
    phaseIncrement = currentFreq / controlRate
    phase = phase + phaseIncrement
    
    # Wrap and evolve
    if phase >= 1
        phase = phase - 1
        generation = generation + 1
        
        # Evolve amplitudes
        for bp to number_of_breakpoints
            @getRandomStep: amplitude_step
            newAmp = amp[bp] + getRandomStep.result
            @applyBarrier: newAmp, -amplitude_barrier, amplitude_barrier
            amp[bp] = applyBarrier.result
        endfor
        
        # Evolve durations
        totalDur = 0
        for bp to number_of_breakpoints
            @getRandomStep: duration_step
            newDur = dur[bp] * (1 + getRandomStep.result)
            if newDur < 0.01
                newDur = 0.01
            endif
            dur[bp] = newDur
            totalDur = totalDur + newDur
        endfor
        # Normalize durations
        for bp to number_of_breakpoints
            dur[bp] = dur[bp] / totalDur
        endfor
        
        # Evolve frequency
        @getRandomStep: duration_step
        currentFreq = currentFreq * (1 + getRandomStep.result * 0.5)
        @applyBarrier: currentFreq, min_frequency_Hz, max_frequency_Hz
        currentFreq = applyBarrier.result
    endif
    
    # === Voice 2 (for stereo) ===
    if spatial_mode >= 2
        cumDur2 = 0
        value2 = 0
        for bp to number_of_breakpoints
            nextCumDur2 = cumDur2 + dur2[bp]
            if phase2 >= cumDur2 and phase2 < nextCumDur2
                nextBp = bp + 1
                if nextBp > number_of_breakpoints
                    nextBp = 1
                endif
                if dur2[bp] > 0
                    localPhase2 = (phase2 - cumDur2) / dur2[bp]
                else
                    localPhase2 = 0
                endif
                value2 = amp2[bp] + (amp2[nextBp] - amp2[bp]) * localPhase2
                bp = number_of_breakpoints
            endif
            cumDur2 = nextCumDur2
        endfor
        
        selectObject: ctrlSound2
        Set value at sample number: 1, cs, value2
        
        phaseIncrement2 = currentFreq2 / controlRate
        phase2 = phase2 + phaseIncrement2
        
        if phase2 >= 1
            phase2 = phase2 - 1
            generation2 = generation2 + 1
            
            for bp to number_of_breakpoints
                @getRandomStep: amplitude_step
                newAmp2 = amp2[bp] + getRandomStep.result
                @applyBarrier: newAmp2, -amplitude_barrier, amplitude_barrier
                amp2[bp] = applyBarrier.result
            endfor
            
            totalDur2 = 0
            for bp to number_of_breakpoints
                @getRandomStep: duration_step
                newDur2 = dur2[bp] * (1 + getRandomStep.result)
                if newDur2 < 0.01
                    newDur2 = 0.01
                endif
                dur2[bp] = newDur2
                totalDur2 = totalDur2 + newDur2
            endfor
            for bp to number_of_breakpoints
                dur2[bp] = dur2[bp] / totalDur2
            endfor
            
            @getRandomStep: duration_step
            currentFreq2 = currentFreq2 * (1 + getRandomStep.result * 0.5)
            @applyBarrier: currentFreq2, min_frequency_Hz, max_frequency_Hz
            currentFreq2 = applyBarrier.result
        endif
    endif
    
    # Progress
    if currentTime - lastReportTime >= 2
        appendInfoLine: "  Time: ", fixed$(currentTime, 1), " s | Gen: ", generation, " | Freq: ", fixed$(currentFreq, 1), " Hz"
        lastReportTime = currentTime
    endif
endfor

appendInfoLine: ""
appendInfoLine: "Total generations: ", generation

# === Resample to audio rate ===
appendInfoLine: "Resampling to audio rate..."

selectObject: ctrlSound
outputSound = Resample: sample_rate_Hz, 50
Rename: "gendyn_" + uid$
removeObject: ctrlSound

if spatial_mode >= 2
    selectObject: ctrlSound2
    outputSound2 = Resample: sample_rate_Hz, 50
    Rename: "gendyn2_" + uid$
    removeObject: ctrlSound2
endif

# === Apply fade ===
selectObject: outputSound
Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

if spatial_mode >= 2
    selectObject: outputSound2
    Formula: "if x < 0.05 then self * (x / 0.05) else self fi"
    Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"
endif

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo dual voices..."
    
    selectObject: outputSound
    plusObject: outputSound2
    stereoSound = Combine to stereo
    Rename: "gendyn_" + preset_name$
    
    removeObject: outputSound, outputSound2
    outputSound = stereoSound

elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Formula: "self * (0.5 + 0.5 * cos(2 * pi * 0.08 * x))"
    
    selectObject: outputSound2
    Formula: "self * (0.5 + 0.5 * sin(2 * pi * 0.08 * x))"
    
    selectObject: outputSound
    plusObject: outputSound2
    stereoSound = Combine to stereo
    Rename: "gendyn_" + preset_name$
    
    removeObject: outputSound, outputSound2
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "gendyn_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  Created: ", selected$("Sound")
appendInfoLine: "=============================================="

# ==============================================================================
# Procedure: getRandomStep
# ==============================================================================
procedure getRandomStep: .maxStep
    if distribution_type = 1
        # Uniform
        .result = randomUniform(-.maxStep, .maxStep)
    elsif distribution_type = 2
        # Cauchy (heavy tails - Xenakis's choice)
        .u = randomUniform(0.01, 0.99)
        .cauchy = tan(pi * (.u - 0.5))
        .result = .maxStep * .cauchy / 5
        if .result > .maxStep * 2
            .result = .maxStep * 2
        elsif .result < -.maxStep * 2
            .result = -.maxStep * 2
        endif
    elsif distribution_type = 3
        # Gaussian
        .result = randomGauss(0, .maxStep * 0.5)
    elsif distribution_type = 4
        # Logistic
        .u = randomUniform(0.01, 0.99)
        .result = .maxStep * ln(.u / (1 - .u)) / 5
        if .result > .maxStep * 2
            .result = .maxStep * 2
        elsif .result < -.maxStep * 2
            .result = -.maxStep * 2
        endif
    endif
endproc

# ==============================================================================
# Procedure: applyBarrier
# ==============================================================================
procedure applyBarrier: .value, .min, .max
    .result = .value
    if .result < .min
        .result = .min + (.min - .result)
        if .result > .max
            .result = .min
        endif
    elsif .result > .max
        .result = .max - (.result - .max)
        if .result < .min
            .result = .max
        endif
    endif
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title (close to waveform top) ===
    Select outer viewport: 0, 7, 0.5, 1.2
    
    # FIX: Force the inner drawing area to match the outer box exactly.
    # This prevents default margins from squashing the text together.
    Select inner viewport: 0, 7, 0.5, 1.2
    Axes: 0, 1, 0, 1
    
    Font size: 14
    Colour: "Black"
    # Position Title high up (0.8)
    Text: 0.5, "centre", 0.8, "half", "GENDYN Synthesis — " + preset_name$
    
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    # Position Tribute low down (0.2)
    Text: 0.5, "centre", 0.2, "half", "Tribute to Iannis Xenakis (1922–2001)"
	    
    # === Waveform Detail ===
    Select outer viewport: 0, 7, 1.2, 2.8
    Colour: "{0.9, 0.9, 0.9}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 1.3, 2.7
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoWave = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_wave"
        .monoWave = selected("Sound")
    endif
    
    selectObject: .monoWave
    .showDur = min(0.3, duration_s)
    Colour: "{0.2, 0.5, 0.3}"
    Draw: 0, .showDur, -1, 1, "no", "Curve"
    
    removeObject: .monoWave
    
    Select inner viewport: .leftMargin, .rightMargin, 1.3, 2.7
    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 0.1, "yes", "yes", "no"
    Font size: 9
    Text bottom: "yes", "Waveform (first " + fixed$(.showDur * 1000, 0) + " ms)"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 3.0, 5.6
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 3.1, 5.5
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    
    selectObject: .monoSpec
    .maxFreqSpec = min(8000, max_frequency_Hz * 1.5)
    
    To Spectrogram: 0.02, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: .leftMargin, .rightMargin, 3.1, 5.5
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 5.7, 6.2
    
    # Establish a 0-1 coordinate system for precise placement
    Axes: 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "BP: " + string$(number_of_breakpoints) + " | Amp: " + fixed$(amplitude_step, 2) + " | Dur: " + fixed$(duration_step, 2) + " | " + distribution_type$ + " | Gen: " + string$(generation)
    
    # "centre" aligns horizontally, "half" aligns vertically (middle)
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc