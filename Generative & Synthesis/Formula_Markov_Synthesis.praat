# ============================================================
# Praat AudioTools - Markov_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Markov chain synthesis - probabilistic state-based composition.
#   Each state has distinct sonic properties (frequency, duration, amplitude).
#   Transitions between states follow Markov probabilities.
#
#   "Markov chains have been used extensively in algorithmic composition,
#    from Xenakis's stochastic music to modern generative systems."
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit 
#   for Experimental Composition.
#
# Changelog v0.2:
#   - Chunked event processing, filters, state-trajectory viz, spatial modes
#
# Changelog v0.3:
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     0.6/7.6 inner-viewport margins, font-12 title in its own band, larger
#     fonts, grey summary panel). Content kept: state trajectory + spectrogram.
#   - Replaced non-ASCII characters (dashes, plus-minus) with ASCII.
# ============================================================

form Markov Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Melodic Walk
        option Drone States
        option Rhythmic Pulse
        option Ascending Chain
        option Chaotic Jumps
        option Centered Gravity
        option Sparse Texture
        option Dense Cluster
    
    comment === Basic Settings ===
    positive Duration_s 12.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 100
    
    comment === Markov Settings ===
    integer Number_of_states 8
    positive Event_density 5.0
    real Transition_randomness 0.3
    
    comment === Markov Chain Type ===
    optionmenu Markov_type 1
        option Simple Chain (neighbor bias)
        option Circular Chain (cycles through)
        option Random Walk (+/-2 steps)
        option Biased Chain (attracts to center)
    
    comment === Sound Options ===
    boolean Enable_harmonics 1
    boolean Enable_envelopes 1
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo (state-based pan)
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Melodic Walk
    number_of_states = 12
    event_density = 4
    base_frequency_Hz = 220
    markov_type = 1
    transition_randomness = 0.2
    preset_name$ = "MelodicWalk"
    
elsif preset = 3
    # Drone States
    number_of_states = 4
    event_density = 2
    base_frequency_Hz = 60
    markov_type = 4
    transition_randomness = 0.1
    enable_harmonics = 1
    preset_name$ = "DroneStates"
    
elsif preset = 4
    # Rhythmic Pulse
    number_of_states = 6
    event_density = 8
    base_frequency_Hz = 150
    markov_type = 2
    enable_envelopes = 1
    preset_name$ = "RhythmicPulse"
    
elsif preset = 5
    # Ascending Chain
    number_of_states = 10
    event_density = 5
    base_frequency_Hz = 80
    markov_type = 2
    preset_name$ = "AscendingChain"
    
elsif preset = 6
    # Chaotic Jumps
    number_of_states = 8
    event_density = 6
    base_frequency_Hz = 120
    markov_type = 3
    transition_randomness = 0.8
    preset_name$ = "ChaoticJumps"
    
elsif preset = 7
    # Centered Gravity
    number_of_states = 9
    event_density = 4
    base_frequency_Hz = 180
    markov_type = 4
    transition_randomness = 0.3
    preset_name$ = "CenteredGravity"
    
elsif preset = 8
    # Sparse Texture
    duration_s = 20
    number_of_states = 6
    event_density = 1.5
    base_frequency_Hz = 200
    markov_type = 1
    preset_name$ = "SparseTexture"
    
elsif preset = 9
    # Dense Cluster
    number_of_states = 5
    event_density = 12
    base_frequency_Hz = 100
    markov_type = 3
    transition_randomness = 0.5
    preset_name$ = "DenseCluster"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
eventsPerChunk = 20

# === Define state properties ===
for state to number_of_states
    # Frequency: exponential spread over one octave
    stateFreq[state] = base_frequency_Hz * (2 ^ ((state - 1) / number_of_states))
    # Duration: longer for higher states
    stateDur[state] = 0.15 + (state / number_of_states) * 0.2
    # Amplitude: louder for higher states
    stateAmp[state] = 0.3 + (state / number_of_states) * 0.4
endfor

# === Calculate total events ===
totalEvents = round(duration_s * event_density)
maxEvents = min(totalEvents * 2, 500)

# === Info ===
writeInfoLine: "=== Markov Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "States: ", number_of_states
appendInfoLine: "Event density: ", event_density, " /s"
appendInfoLine: "Expected events: ~", totalEvents
appendInfoLine: "Markov type: ", markov_type$
appendInfoLine: ""

# === Pre-generate events using Markov chain ===
appendInfoLine: "Running Markov chain..."

currentState = randomInteger(1, number_of_states)
currentTime = 0
eventCount = 0

while currentTime < duration_s and eventCount < maxEvents
    eventCount = eventCount + 1
    
    # Store event properties
    eventTime[eventCount] = currentTime
    eventState[eventCount] = currentState
    eventFreq[eventCount] = stateFreq[currentState] * randomUniform(0.98, 1.02)
    eventDur[eventCount] = stateDur[currentState] * randomUniform(0.7, 1.3)
    eventAmp[eventCount] = stateAmp[currentState] * randomUniform(0.8, 1.2) / sqrt(event_density)
    
    # Clamp duration
    if currentTime + eventDur[eventCount] > duration_s
        eventDur[eventCount] = duration_s - currentTime
    endif
    
    # Advance time
    currentTime = currentTime + eventDur[eventCount]
    
    # === Markov transition ===
    oldState = currentState
    
    if markov_type = 1
        # Simple Chain: prefer neighbors, occasional jumps
        r = randomUniform(0, 1)
        if r < 0.5 - transition_randomness / 2
            # Stay
            currentState = currentState
        elsif r < 0.85 - transition_randomness / 3
            # Move to neighbor
            direction = randomInteger(0, 1) * 2 - 1
            currentState = currentState + direction
            if currentState < 1
                currentState = 1
            elsif currentState > number_of_states
                currentState = number_of_states
            endif
        else
            # Random jump
            currentState = randomInteger(1, number_of_states)
        endif
        
    elsif markov_type = 2
        # Circular Chain: always advance, wrap around
        currentState = currentState + 1
        if currentState > number_of_states
            currentState = 1
        endif
        
    elsif markov_type = 3
        # Random Walk: +/-2 steps
        step = randomInteger(-2, 2)
        currentState = currentState + step
        if currentState < 1
            currentState = 1
        elsif currentState > number_of_states
            currentState = number_of_states
        endif
        
    elsif markov_type = 4
        # Biased Chain: attracted to center
        centerState = round(number_of_states / 2)
        if currentState < centerState
            if randomUniform(0, 1) < 0.7
                currentState = currentState + 1
            endif
        elsif currentState > centerState
            if randomUniform(0, 1) < 0.7
                currentState = currentState - 1
            endif
        else
            # At center: small random moves
            if randomUniform(0, 1) > 0.6
                currentState = currentState + randomInteger(-1, 1)
                if currentState < 1
                    currentState = 1
                elsif currentState > number_of_states
                    currentState = number_of_states
                endif
            endif
        endif
    endif
endwhile

appendInfoLine: "Generated ", eventCount, " events"

# === Create output sound ===
outputSound = Create Sound from formula: "markov_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Synthesize events in chunks ===
appendInfoLine: "Synthesizing..."

eventIndex = 1
while eventIndex <= eventCount
    chunkFormula$ = "0"
    eventsInChunk = 0
    
    while eventIndex <= eventCount and eventsInChunk < eventsPerChunk
        eTime = eventTime[eventIndex]
        eDur = eventDur[eventIndex]
        eFreq = eventFreq[eventIndex]
        eAmp = eventAmp[eventIndex]
        
        if eDur > 0.01
            sTime$ = fixed$(eTime, 5)
            sEnd$ = fixed$(eTime + eDur, 5)
            sDur$ = fixed$(eDur, 5)
            sAmp$ = fixed$(eAmp, 4)
            sFreq$ = fixed$(eFreq, 2)
            
            # Build waveform
            if enable_harmonics
                # 3 harmonics with decreasing amplitude
                sFreq2$ = fixed$(eFreq * 2, 2)
                sFreq3$ = fixed$(eFreq * 3, 2)
                sAmp2$ = fixed$(eAmp * 0.5, 4)
                sAmp3$ = fixed$(eAmp * 0.25, 4)
                waveForm$ = "(" + sAmp$ + " * sin(twoPi * " + sFreq$ + " * x) + " + sAmp2$ + " * sin(twoPi * " + sFreq2$ + " * x) + " + sAmp3$ + " * sin(twoPi * " + sFreq3$ + " * x))"
            else
                waveForm$ = sAmp$ + " * sin(twoPi * " + sFreq$ + " * x)"
            endif
            
            # Envelope
            if enable_envelopes
                envelope$ = " * (1 - cos(twoPi * (x - " + sTime$ + ") / " + sDur$ + ")) / 2"
            else
                envelope$ = " * exp(-3 * (x - " + sTime$ + ") / " + sDur$ + ")"
            endif
            
            eventTerm$ = " + if x >= " + sTime$ + " and x < " + sEnd$ + " then " + waveForm$ + envelope$ + " else 0 fi"
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

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo (state-based pan) - pre-compute pan per event
    appendInfoLine: "Creating stereo mix..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    
    # Lower states left, higher states right
    selectObject: leftSound
    Filter (pass Hann band): 0, base_frequency_Hz * 2, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: rightSound
    Filter (pass Hann band): base_frequency_Hz, base_frequency_Hz * 8, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "markov_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * 0.1 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * 0.1 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "markov_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "markov_" + preset_name$
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
    Text: 0.5, "centre", 0.5, "half", "Markov Synthesis: " + preset_name$

    # --- Panel 1: State trajectory ---
    Select outer viewport: 0, 8, 1.0, 3.0
    Select inner viewport: 0.75, 7.6, 1.15, 2.9
    Axes: 0, duration_s, 0, number_of_states + 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration_s, 0, number_of_states + 1

    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    for s to number_of_states
        Draw line: 0, s, duration_s, s
    endfor

    Colour: "{0.20, 0.40, 0.70}"
    Line width: 2
    for ev from 1 to eventCount - 1
        Draw line: eventTime[ev], eventState[ev], eventTime[ev + 1], eventState[ev + 1]
    endfor

    for ev to eventCount
        .state = eventState[ev]
        .hue = (.state - 1) / max(1, number_of_states - 1)
        .r = 0.20 + 0.60 * .hue
        .g = 0.50 - 0.30 * .hue
        .b = 0.80 - 0.50 * .hue
        Paint circle: "{" + fixed$(.r, 2) + ", " + fixed$(.g, 2) + ", " + fixed$(.b, 2) + "}", eventTime[ev], .state, 0.10
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Marks left: number_of_states, "yes", "yes", "no"
    Marks bottom every: 1, 2, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "State"
    Text bottom: "yes", "Time (s)"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 3.3, 5.2
    Select inner viewport: 0.75, 7.6, 3.45, 5.1

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
    .maxFreqSpec = stateFreq[number_of_states] * 4
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .monoSpec, .spec

    Select inner viewport: 0.75, 7.6, 3.45, 5.1
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
    Select outer viewport: 0, 8, 5.4, 5.8
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", markov_type$ + " | " + string$(number_of_states) + " states | " + string$(eventCount) + " events | Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Density: " + fixed$(event_density, 1) + " | Randomness: " + fixed$(transition_randomness, 2)
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc