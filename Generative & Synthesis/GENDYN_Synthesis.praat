# ============================================================
# Praat AudioTools - GENDYN_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 3.1 (2026)
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
# Changelog v3.1 (2026):
#   - FIX (audible, severe): the "control rate" architecture
#     bandlimited the output at HALF THE SYNTHESIS RATE -- the
#     default (Balanced) synthesized at 4 kHz and upsampled, so
#     nothing above 2 kHz survived (measured: -35 dB above 2 kHz).
#     GENDYN's timbre lives in the breakpoint CORNERS; capping
#     their spectrum is the recurring "muffle" pattern in
#     synthesis form. v3.1 synthesizes at the target sample rate.
#   - REWRITE (speed): the per-sample interpreter loop with
#     Set-value-per-sample writes cost 3.0 s mono / 9.2 s stereo
#     AT 4-8 kHz (v3.0 measured); at 44.1 kHz it would run
#     ~30-100 s. v3.1 evaluates ONE Formula (part) per waveform
#     period -- breakpoint data in two small matrices, the
#     interpolation cascade as a constant formula string, C++
#     per-sample evaluation. MEASURED: 12 s mono in 5.1 s and
#     stereo GENDY3 in 10.3 s at FULL 44.1 kHz, vs v3.0's 3.0 /
#     9.2 s at 4-8 kHz -- comparable wall time at 11x the
#     synthesis rate; HF energy (2-12 kHz vs 0.1-2 kHz) rose
#     from -35.0 to -22.4 dB.
#   - Speed modes removed (they only chose how much spectrum to
#     discard). Form argument list changed accordingly.
#   - FIX: float-edge gap where phase in [sum(dur), 1) produced
#     silent samples (click seeds); the cumulative-duration
#     matrix now pins its final boundary to exactly 1.
#   - NOTE (honesty): pitch here is a SEPARATE bounded random
#     walk; canonical GENDYN derives pitch from the unnormalized
#     duration sum. This variant is more controllable and is the
#     established sound of this tool.
#
# Reference:
#   Xenakis, I. (1992). Formalized Music. Pendragon Press.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
# ============================================================

form GENDYN Synthesis v3.1 (Tribute to Xenakis)
    comment === Preset ===
    optionmenu Preset: 1
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
    optionmenu Distribution_type: 2
        option Uniform
        option Cauchy (Xenakis)
        option Gaussian
        option Logistic
    
    comment === Barrier Settings ===
    real Amplitude_barrier 0.95
    real Min_frequency_Hz 20
    real Max_frequency_Hz 2000
    
    comment === Output ===
    optionmenu Spatial_mode: 1
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

speedStr$ = "Full bandwidth"

startTime = stopwatch

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# v3.1: synthesis runs at the target sample rate (the old
# "control rate" bandlimited the output at half its value)
synthRate = sample_rate_Hz

# === Info ===
clearinfo
writeInfoLine: "=============================================="
appendInfoLine: "  GENDYN SYNTHESIS v3.1"
appendInfoLine: "  A Tribute to Iannis Xenakis (1922-2001)"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Speed: ", speedStr$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Breakpoints: ", number_of_breakpoints
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Synthesis rate: ", synthRate, " Hz (full bandwidth)"
appendInfoLine: "Distribution: ", distribution_type$
appendInfoLine: ""

# === Initialize breakpoints ===
appendInfoLine: "Initializing breakpoints..."

# Amplitudes
for bp to number_of_breakpoints
    amp[bp] = randomUniform(-0.5, 0.5)
endfor

# Durations as fractions
for bp to number_of_breakpoints
    dur[bp] = 1.0 / number_of_breakpoints
endfor

currentFreq = base_frequency_Hz

# Second voice for stereo
if spatial_mode >= 2
    for bp to number_of_breakpoints
        amp2[bp] = randomUniform(-0.5, 0.5)
        dur2[bp] = 1.0 / number_of_breakpoints
    endfor
    currentFreq2 = base_frequency_Hz * (1 + 0.05 * randomUniform(-1, 1))
endif

# === Create output sound buffer (v3.1: full audio rate) ===
appendInfoLine: "Creating sound buffer..."
outputSound = Create Sound from formula: "gendyn_" + uid$, 1, 0, duration_s, synthRate, "0"

if spatial_mode >= 2
    outputSound2 = Create Sound from formula: "gendyn2_" + uid$, 1, 0, duration_s, synthRate, "0"
endif

# === v3.1 SYNTHESIS: one Formula (part) per waveform period ===
# Breakpoint state lives in two small matrices per voice:
#   am: amplitudes, N+1 cols (col N+1 = col 1, the wrap)
#   cm: cumulative durations, N+1 cols (col 1 = 0, col N+1
#       PINNED to exactly 1.0 -- also fixes the v3.0 float-edge
#       silent-sample gap)
# The interpolation cascade is a CONSTANT formula string reading
# them via object[]; genT/genP are plain script variables the
# formula references. Praat's C++ engine evaluates per sample.

nBp1 = number_of_breakpoints + 1
amMat = Create simple Matrix: "am1_" + uid$, 1, nBp1, "0"
cmMat = Create simple Matrix: "cm1_" + uid$, 1, nBp1, "0"
if spatial_mode >= 2
    amMat2 = Create simple Matrix: "am2_" + uid$, 1, nBp1, "0"
    cmMat2 = Create simple Matrix: "cm2_" + uid$, 1, nBp1, "0"
endif

procedure refreshMats: .amId, .cmId, .which
    .cum = 0
    selectObject: .cmId
    Set value: 1, 1, 0
    for .bp from 1 to number_of_breakpoints
        if .which = 1
            .a = amp[.bp]
            .d = dur[.bp]
        else
            .a = amp2[.bp]
            .d = dur2[.bp]
        endif
        selectObject: .amId
        Set value: 1, .bp, .a
        .cum = .cum + .d
        selectObject: .cmId
        if .bp < number_of_breakpoints
            Set value: 1, .bp + 1, .cum
        else
            Set value: 1, .bp + 1, 1.0
        endif
    endfor
    selectObject: .amId
    if .which = 1
        Set value: 1, number_of_breakpoints + 1, amp[1]
    else
        Set value: 1, number_of_breakpoints + 1, amp2[1]
    endif
endproc

procedure buildGendynFormula: .amId, .cmId, .tVar$, .pVar$
    .ph$ = "min((x - " + .tVar$ + ") / " + .pVar$ + ", 0.9999995)"
    .am$ = string$(.amId)
    .cm$ = string$(.cmId)
    .f$ = ""
    for .bp from 1 to number_of_breakpoints
        .b$ = string$(.bp)
        .b1$ = string$(.bp + 1)
        .lerp$ = "object[" + .am$ + ",1," + .b$ + "] + (object[" + .am$ + ",1," + .b1$
            ... + "] - object[" + .am$ + ",1," + .b$ + "]) * (" + .ph$
            ... + " - object[" + .cm$ + ",1," + .b$ + "]) / (object[" + .cm$ + ",1," + .b1$
            ... + "] - object[" + .cm$ + ",1," + .b$ + "] + 1e-12)"
        if .bp < number_of_breakpoints
            .f$ = .f$ + "if " + .ph$ + " < object[" + .cm$ + ",1," + .b1$ + "] then " + .lerp$ + " else "
        else
            .f$ = .f$ + .lerp$
        endif
    endfor
    for .bp from 1 to number_of_breakpoints - 1
        .f$ = .f$ + " fi"
    endfor
    buildGendynFormula.result$ = .f$
endproc

@buildGendynFormula: amMat, cmMat, "genT", "genP"
gendynF1$ = buildGendynFormula.result$
if spatial_mode >= 2
    @buildGendynFormula: amMat2, cmMat2, "genT2", "genP2"
    gendynF2$ = buildGendynFormula.result$
endif

appendInfoLine: "Synthesizing GENDYN (voice 1)..."

genT = 0
generation = 0
lastReportPercent = 0
while genT < duration_s
    genP = 1 / currentFreq
    @refreshMats: amMat, cmMat, 1
    selectObject: outputSound
    Formula (part): genT, min(genT + genP, duration_s), 1, 1, gendynF1$
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
    for bp to number_of_breakpoints
        dur[bp] = dur[bp] / totalDur
    endfor
    
    # Evolve frequency
    @getRandomStep: duration_step
    currentFreq = currentFreq * (1 + getRandomStep.result * 0.5)
    @applyBarrier: currentFreq, min_frequency_Hz, max_frequency_Hz
    currentFreq = applyBarrier.result
    
    genT = genT + genP
    
    percentDone = round(100 * genT / duration_s)
    if percentDone >= lastReportPercent + 20
        appendInfoLine: "  ", min(percentDone, 100), "% | Gen: ", generation, " | Freq: ", fixed$(currentFreq, 0), " Hz"
        lastReportPercent = percentDone
    endif
endwhile

if spatial_mode >= 2
    appendInfoLine: "Synthesizing GENDYN (voice 2)..."
    genT2 = 0
    generation2 = 0
    while genT2 < duration_s
        genP2 = 1 / currentFreq2
        @refreshMats: amMat2, cmMat2, 2
        selectObject: outputSound2
        Formula (part): genT2, min(genT2 + genP2, duration_s), 1, 1, gendynF2$
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
        
        genT2 = genT2 + genP2
    endwhile
endif

appendInfoLine: ""
appendInfoLine: "Total generations: ", generation

removeObject: amMat, cmMat
if spatial_mode >= 2
    removeObject: amMat2, cmMat2
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

processingTime = stopwatch - startTime

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"

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
    
    # === Title ===
    Select outer viewport: 0, 7, 0.5, 1.2
    Select inner viewport: 0, 7, 0.5, 1.2
    Axes: 0, 1, 0, 1
    
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.8, "half", "GENDYN Synthesis — " + preset_name$
    
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
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
    Axes: 0, 1, 0, 1
    
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = speedStr$ + " | " + fixed$(processingTime, 1) + "s | BP: " + string$(number_of_breakpoints) + " | Amp: " + fixed$(amplitude_step, 2) + " | Dur: " + fixed$(duration_step, 2) + " | Gen: " + string$(generation)
    
    Text: 0.5, "centre", 0.5, "half", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc