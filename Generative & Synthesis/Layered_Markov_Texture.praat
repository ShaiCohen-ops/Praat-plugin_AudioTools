# ============================================================
# Praat AudioTools - Layered_Markov_Texture.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multiple independent Markov chains running in parallel layers.
#   Each layer has its own state machine with distinct frequencies,
#   creating complex evolving textures.
#
#   Different from single-chain Markov_Synthesis: here each layer
#   evolves independently with its own transition probabilities.
#
# Usage:
#   Run this script (no input sound required).
#
# Changelog v0.2:
#   - Focused layered Markov, chunked events, filters, if/fi, viz
#
# Changelog v0.3:
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, layer-activity plot + spectrogram, grey summary, larger fonts).
#   - Replaced non-ASCII characters (multiplication sign, em-dash) with ASCII.
# ============================================================

form Layered Markov Texture
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Sparse Layers
        option Dense Weave
        option Harmonic Stack
        option Wide Spread
        option Converging
        option Diverging
    
    comment === Basic Settings ===
    positive Duration_s 10.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 80
    
    comment === Layer Settings ===
    integer Number_of_layers 3
    real Layer_spacing 1.5
    positive Events_per_layer 3.0
    
    comment === Markov Settings ===
    real Complexity 1.0
    boolean Cross_layer_influence 1
    
    comment === Output ===
    positive Fade_time_s 2.0
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Sparse Layers
    number_of_layers = 2
    layer_spacing = 2.0
    events_per_layer = 1.5
    complexity = 0.5
    preset_name$ = "SparseLayers"
    
elsif preset = 3
    # Dense Weave
    number_of_layers = 4
    layer_spacing = 1.3
    events_per_layer = 5.0
    complexity = 1.5
    preset_name$ = "DenseWeave"
    
elsif preset = 4
    # Harmonic Stack
    number_of_layers = 5
    layer_spacing = 2.0
    events_per_layer = 3.0
    complexity = 0.8
    base_frequency_Hz = 55
    preset_name$ = "HarmonicStack"
    
elsif preset = 5
    # Wide Spread
    number_of_layers = 3
    layer_spacing = 3.0
    events_per_layer = 2.5
    complexity = 1.0
    preset_name$ = "WideSpread"
    
elsif preset = 6
    # Converging
    number_of_layers = 4
    layer_spacing = 1.2
    events_per_layer = 4.0
    complexity = 1.2
    base_frequency_Hz = 100
    preset_name$ = "Converging"
    
elsif preset = 7
    # Diverging
    number_of_layers = 3
    layer_spacing = 2.5
    events_per_layer = 2.0
    complexity = 0.7
    base_frequency_Hz = 150
    preset_name$ = "Diverging"
endif

# === Validation ===
if number_of_layers > 8
    number_of_layers = 8
endif
if number_of_layers < 1
    number_of_layers = 1
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
eventsPerChunk = 20

# === Info ===
writeInfoLine: "=== Layered Markov Texture ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Layers: ", number_of_layers
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Layer spacing: ", layer_spacing, "x"
appendInfoLine: "Events/layer: ", events_per_layer
appendInfoLine: "Complexity: ", complexity
appendInfoLine: ""

# === Create output buffer ===
outputSound = Create Sound from formula: "markov_layers_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Track all events for visualization ===
totalEventCount = 0

# === Build each layer with independent Markov chain ===
for layer to number_of_layers
    appendInfoLine: "=== Layer ", layer, " ==="
    
    # Layer-specific frequency
    layerFreq = base_frequency_Hz * (layer_spacing ^ (layer - 1))
    
    # Number of states increases with layer
    numStates = 4 + layer
    
    # Initialize state parameters for this layer
    for state to numStates
        stateFreq[state] = layerFreq * (1.15 ^ (state - 1))
        stateDur[state] = (0.1 + (state / numStates) * 0.25) * complexity
        stateAmp[state] = (0.25 / number_of_layers) * (0.7 + 0.3 * state / numStates)
    endfor
    
    # Calculate events for this layer
    layerEvents = round(duration_s * events_per_layer)
    
    appendInfoLine: "  Frequency: ", fixed$(layerFreq, 1), " Hz"
    appendInfoLine: "  States: ", numStates
    appendInfoLine: "  Target events: ", layerEvents
    
    # Pre-generate events using Markov chain
    currentState = randomInteger(1, numStates)
    currentTime = 0
    layerEventCount = 0
    
    while currentTime < duration_s and layerEventCount < layerEvents * 2
        layerEventCount = layerEventCount + 1
        totalEventCount = totalEventCount + 1
        
        # Store event
        eventTime[totalEventCount] = currentTime
        eventLayer[totalEventCount] = layer
        eventState[totalEventCount] = currentState
        eventFreq[totalEventCount] = stateFreq[currentState] * randomUniform(0.98, 1.02)
        eventDur[totalEventCount] = stateDur[currentState] * randomUniform(0.8, 1.2)
        eventAmp[totalEventCount] = stateAmp[currentState] * randomUniform(0.8, 1.0)
        
        # Clamp duration
        if currentTime + eventDur[totalEventCount] > duration_s
            eventDur[totalEventCount] = duration_s - currentTime
        endif
        
        # Advance time
        currentTime = currentTime + eventDur[totalEventCount]
        
        # Markov transition
        r = randomUniform(0, 1)
        transitionThreshold = 0.5 + complexity * 0.1
        
        if r < transitionThreshold * 0.4
            # Stay in current state
            currentState = currentState
        elsif r < transitionThreshold * 0.7
            # Move to next state (wrap)
            currentState = currentState + 1
            if currentState > numStates
                currentState = 1
            endif
        else
            # Move to previous state (wrap)
            currentState = currentState - 1
            if currentState < 1
                currentState = numStates
            endif
        endif
    endwhile
    
    appendInfoLine: "  Generated: ", layerEventCount, " events"
endfor

appendInfoLine: ""
appendInfoLine: "Total events: ", totalEventCount

# === Sort events by time ===
appendInfoLine: "Sorting events..."
for i to totalEventCount - 1
    for j from i + 1 to totalEventCount
        if eventTime[j] < eventTime[i]
            # Swap
            tempTime = eventTime[i]
            tempLayer = eventLayer[i]
            tempState = eventState[i]
            tempFreq = eventFreq[i]
            tempDur = eventDur[i]
            tempAmp = eventAmp[i]
            
            eventTime[i] = eventTime[j]
            eventLayer[i] = eventLayer[j]
            eventState[i] = eventState[j]
            eventFreq[i] = eventFreq[j]
            eventDur[i] = eventDur[j]
            eventAmp[i] = eventAmp[j]
            
            eventTime[j] = tempTime
            eventLayer[j] = tempLayer
            eventState[j] = tempState
            eventFreq[j] = tempFreq
            eventDur[j] = tempDur
            eventAmp[j] = tempAmp
        endif
    endfor
endfor

# === Synthesize events in chunks ===
appendInfoLine: "Synthesizing..."

eventIndex = 1
while eventIndex <= totalEventCount
    chunkFormula$ = "0"
    eventsInChunk = 0
    
    while eventIndex <= totalEventCount and eventsInChunk < eventsPerChunk
        evTime = eventTime[eventIndex]
        evDur = eventDur[eventIndex]
        evFreq = eventFreq[eventIndex]
        evAmp = eventAmp[eventIndex]
        
        if evDur > 0.01
            sTime$ = fixed$(evTime, 5)
            sEnd$ = fixed$(evTime + evDur, 5)
            sDur$ = fixed$(evDur, 5)
            sFreq$ = fixed$(evFreq, 2)
            sAmp$ = fixed$(evAmp, 4)
            
            # Build event formula
            if cross_layer_influence
                # Add subtle FM for cross-influence effect
                modDepth$ = fixed$(0.1 * complexity, 3)
                modFreq$ = fixed$(evFreq * 0.3, 2)
                eventTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * x * (1 + " + modDepth$ + " * sin(twoPi * " + modFreq$ + " * x))) * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
            else
                eventTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + sAmp$ + " * sin(twoPi * " + sFreq$ + " * x) * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2 else 0 fi"
            endif
            
            chunkFormula$ = chunkFormula$ + eventTerm$
            eventsInChunk = eventsInChunk + 1
        endif
        
        eventIndex = eventIndex + 1
    endwhile
    
    # Apply chunk
    if chunkFormula$ <> "0"
        selectObject: outputSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
endwhile

# === Apply fade envelope ===
selectObject: outputSound
if fade_time_s > 0
    fadeSamples = fade_time_s * sample_rate_Hz
    totalSamples = duration_s * sample_rate_Hz
    releaseStart = totalSamples - fadeSamples
    
    Formula: "if col < fadeSamples then self * (col / fadeSamples) else self fi"
    Formula: "if col > releaseStart then self * ((totalSamples - col) / fadeSamples) else self fi"
endif

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Wide
    appendInfoLine: ""
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 4000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 200, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "markov_layers_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating
    appendInfoLine: ""
    appendInfoLine: "Creating rotating stereo..."
    
    rotationRate = 0.2
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * rotationRate * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * rotationRate * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "markov_layers_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "markov_layers_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
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
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Layered Markov Texture: " + preset_name$

    # --- Panel 1: Layer activity ---
    Select outer viewport: 0, 8, 1.0, 2.8
    Select inner viewport: 0.75, 7.6, 1.15, 2.7
    Axes: 0, duration_s, 0, number_of_layers + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration_s, 0, number_of_layers + 1

    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    for lay to number_of_layers
        Draw line: 0, lay, duration_s, lay
    endfor

    for ev to totalEventCount
        .lay = eventLayer[ev]
        .hue = (.lay - 1) / max(1, number_of_layers - 1)
        .r = 0.20 + 0.60 * .hue
        .g = 0.60 - 0.30 * .hue
        .b = 0.80 - 0.50 * .hue
        .evStart = eventTime[ev]
        .evEnd = eventTime[ev] + eventDur[ev]
        Paint rectangle: "{" + fixed$(.r, 2) + ", " + fixed$(.g, 2) + ", " + fixed$(.b, 2) + "}", .evStart, .evEnd, .lay - 0.3, .lay + 0.3
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Marks left: number_of_layers, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "Layer"
    Text bottom: "yes", "Time (s)"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 3.1, 5.0
    Select inner viewport: 0.75, 7.6, 3.25, 4.9

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
    .maxFreqSpec = base_frequency_Hz * (layer_spacing ^ number_of_layers) * 3
    .maxFreqSpec = min(8000, .maxFreqSpec)
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .monoSpec, .spec

    Select inner viewport: 0.75, 7.6, 3.25, 4.9
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 5.2, 5.6
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", string$(number_of_layers) + " layers x " + fixed$(events_per_layer, 1) + " events/layer | " + string$(totalEventCount) + " events | Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Spacing: " + fixed$(layer_spacing, 2) + "x | Complexity: " + fixed$(complexity, 2)
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc