# ============================================================
# Praat AudioTools - Markov_Rhythm_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Clave Sound
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Markov chain rhythm generator with clave-like percussion sounds.
#   
#   Visualization includes Toussaint circular rhythm diagrams
#   (rhythm necklaces with onset polygons).
#
#   Reference: Toussaint, G. (2013). The Geometry of Musical Rhythm.
#
# Changelog v0.3:
#   - Clave-like percussion sound (high, woody, sharp attack)
#   - Higher base frequencies
#   - Faster decay envelopes
#   - Inharmonic overtones for wood character
# ============================================================

form Markov Rhythm Generator
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Simple March
        option Complex Funk
        option Techno Pattern
        option Swing Feel
        option Broken Beat
        option Latin Clave
        option Polyrhythmic
        option Euclidean 5-8
    
    comment === Basic Settings ===
    positive Duration_s 6.0
    integer Sample_rate_Hz 44100
    positive Tempo_bpm 120
    
    comment === Clave Sound ===
    positive Base_frequency_Hz 1800
    positive Decay_rate 60
    real Wood_character 0.4 (= 0-1, inharmonic overtones)
    
    comment === Canon Mode ===
    optionmenu Canon_mode 1
        option No Canon
        option Canon 2 voices
        option Canon 3 voices
    positive Canon_delay_s 1.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    tempo_bpm = 100
    base_frequency_Hz = 1500
    decay_rate = 50
    wood_character = 0.3
    preset_name$ = "SimpleMarch"
elsif preset = 3
    tempo_bpm = 110
    base_frequency_Hz = 2000
    decay_rate = 70
    wood_character = 0.5
    preset_name$ = "ComplexFunk"
elsif preset = 4
    tempo_bpm = 130
    base_frequency_Hz = 1200
    decay_rate = 80
    wood_character = 0.2
    preset_name$ = "TechnoPattern"
elsif preset = 5
    tempo_bpm = 90
    base_frequency_Hz = 1600
    decay_rate = 55
    wood_character = 0.4
    preset_name$ = "SwingFeel"
elsif preset = 6
    tempo_bpm = 140
    base_frequency_Hz = 1900
    decay_rate = 65
    wood_character = 0.5
    preset_name$ = "BrokenBeat"
elsif preset = 7
    # Latin Clave - authentic clave sound
    tempo_bpm = 120
    base_frequency_Hz = 2200
    decay_rate = 75
    wood_character = 0.6
    preset_name$ = "LatinClave"
elsif preset = 8
    tempo_bpm = 100
    base_frequency_Hz = 1700
    decay_rate = 60
    wood_character = 0.4
    preset_name$ = "Polyrhythmic"
elsif preset = 9
    tempo_bpm = 110
    base_frequency_Hz = 1800
    decay_rate = 65
    wood_character = 0.5
    preset_name$ = "Euclidean5-8"
endif

# === Define rhythm patterns ===
rhythmStates = 8

if preset = 2
    rhythmPattern$[1] = "1000"
    rhythmPattern$[2] = "1010"
    rhythmPattern$[3] = "1100"
    rhythmPattern$[4] = "1001"
    rhythmPattern$[5] = "1010"
    rhythmPattern$[6] = "1100"
    rhythmPattern$[7] = "1001"
    rhythmPattern$[8] = "1110"
elsif preset = 3
    rhythmPattern$[1] = "10101010"
    rhythmPattern$[2] = "10011001"
    rhythmPattern$[3] = "11001100"
    rhythmPattern$[4] = "10110100"
    rhythmPattern$[5] = "10010110"
    rhythmPattern$[6] = "11010010"
    rhythmPattern$[7] = "10100101"
    rhythmPattern$[8] = "10001011"
elsif preset = 4
    rhythmPattern$[1] = "1000"
    rhythmPattern$[2] = "1001"
    rhythmPattern$[3] = "1010"
    rhythmPattern$[4] = "1011"
    rhythmPattern$[5] = "1100"
    rhythmPattern$[6] = "1101"
    rhythmPattern$[7] = "1110"
    rhythmPattern$[8] = "1111"
elsif preset = 5
    rhythmPattern$[1] = "100010"
    rhythmPattern$[2] = "100100"
    rhythmPattern$[3] = "101000"
    rhythmPattern$[4] = "101010"
    rhythmPattern$[5] = "110000"
    rhythmPattern$[6] = "110010"
    rhythmPattern$[7] = "100110"
    rhythmPattern$[8] = "101100"
elsif preset = 6
    rhythmPattern$[1] = "1010101"
    rhythmPattern$[2] = "1001011"
    rhythmPattern$[3] = "1101001"
    rhythmPattern$[4] = "1011010"
    rhythmPattern$[5] = "1001101"
    rhythmPattern$[6] = "1110010"
    rhythmPattern$[7] = "1010110"
    rhythmPattern$[8] = "1100110"
elsif preset = 7
    # Son clave and rumba patterns
    rhythmPattern$[1] = "10010010"
    rhythmPattern$[2] = "01001001"
    rhythmPattern$[3] = "10100100"
    rhythmPattern$[4] = "01010010"
    rhythmPattern$[5] = "10010001"
    rhythmPattern$[6] = "01001010"
    rhythmPattern$[7] = "10001010"
    rhythmPattern$[8] = "01010100"
elsif preset = 8
    rhythmPattern$[1] = "10101"
    rhythmPattern$[2] = "10010"
    rhythmPattern$[3] = "11011"
    rhythmPattern$[4] = "10110"
    rhythmPattern$[5] = "10001"
    rhythmPattern$[6] = "11100"
    rhythmPattern$[7] = "10111"
    rhythmPattern$[8] = "11001"
elsif preset = 9
    rhythmPattern$[1] = "10010010"
    rhythmPattern$[2] = "10010100"
    rhythmPattern$[3] = "10100101"
    rhythmPattern$[4] = "10101010"
    rhythmPattern$[5] = "10110101"
    rhythmPattern$[6] = "10101101"
    rhythmPattern$[7] = "10110110"
    rhythmPattern$[8] = "10101011"
else
    rhythmPattern$[1] = "1000"
    rhythmPattern$[2] = "1010"
    rhythmPattern$[3] = "1100"
    rhythmPattern$[4] = "1110"
    rhythmPattern$[5] = "1001"
    rhythmPattern$[6] = "1011"
    rhythmPattern$[7] = "1101"
    rhythmPattern$[8] = "1111"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

beatsPerSecond = tempo_bpm / 60
beatDuration = 1 / beatsPerSecond
totalBeats = floor(duration_s * beatsPerSecond)

# Clave inharmonic ratio (wood resonance)
woodRatio = 2.76

if canon_mode > 1
    canonVoices = canon_mode
    totalDuration = duration_s + (canonVoices - 1) * canon_delay_s
else
    canonVoices = 1
    totalDuration = duration_s
endif

# === Info ===
writeInfoLine: "=== Markov Rhythm Generator (Clave) ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Tempo: ", tempo_bpm, " BPM"
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Decay rate: ", decay_rate
appendInfoLine: "Wood character: ", wood_character
appendInfoLine: "Canon voices: ", canonVoices
appendInfoLine: ""

# === Pre-generate all pulses ===
appendInfoLine: "Generating rhythm patterns..."

totalPulses = 0
maxPulses = 2000

for voice to canonVoices
    voiceDelay = (voice - 1) * canon_delay_s
    
    # Voice-specific frequency (higher/lower for different voices)
    if voice = 1
        voiceFreq = base_frequency_Hz
    elsif voice = 2
        voiceFreq = base_frequency_Hz * 1.25
    else
        voiceFreq = base_frequency_Hz * 0.8
    endif
    
    if canonVoices > 1
        voicePan[voice] = (voice - 1) / (canonVoices - 1)
    else
        voicePan[voice] = 0.5
    endif
    
    currentRhythm = randomInteger(1, rhythmStates)
    
    for beat to totalBeats
        currentPattern$ = rhythmPattern$[currentRhythm]
        subdivisions = length(currentPattern$)
        
        for subdiv to subdivisions
            currentChar$ = mid$(currentPattern$, subdiv, 1)
            
            if currentChar$ = "1" and totalPulses < maxPulses
                totalPulses = totalPulses + 1
                
                pulseTime[totalPulses] = voiceDelay + (beat - 1) * beatDuration + (subdiv - 1) * (beatDuration / subdivisions)
                pulseDur[totalPulses] = 0.08
                pulseFreq[totalPulses] = voiceFreq
                pulseVoice[totalPulses] = voice
                pulseBeat[totalPulses] = beat
                pulseState[totalPulses] = currentRhythm
            endif
        endfor
        
        # Markov transition
        r = randomUniform(0, 1)
        if r < 0.4
            currentRhythm = currentRhythm
        elsif r < 0.7
            currentRhythm = currentRhythm + 1
            if currentRhythm > rhythmStates
                currentRhythm = 1
            endif
        else
            currentRhythm = randomInteger(1, rhythmStates)
        endif
    endfor
    
    appendInfoLine: "  Voice ", voice, ": freq=", fixed$(voiceFreq, 0), " Hz"
endfor

appendInfoLine: "Total pulses: ", totalPulses

# === Sort pulses by time ===
appendInfoLine: "Sorting pulses..."
for i to totalPulses - 1
    for j from i + 1 to totalPulses
        if pulseTime[j] < pulseTime[i]
            tempTime = pulseTime[i]
            tempDur = pulseDur[i]
            tempFreq = pulseFreq[i]
            tempVoice = pulseVoice[i]
            tempBeat = pulseBeat[i]
            tempState = pulseState[i]
            
            pulseTime[i] = pulseTime[j]
            pulseDur[i] = pulseDur[j]
            pulseFreq[i] = pulseFreq[j]
            pulseVoice[i] = pulseVoice[j]
            pulseBeat[i] = pulseBeat[j]
            pulseState[i] = pulseState[j]
            
            pulseTime[j] = tempTime
            pulseDur[j] = tempDur
            pulseFreq[j] = tempFreq
            pulseVoice[j] = tempVoice
            pulseBeat[j] = tempBeat
            pulseState[j] = tempState
        endif
    endfor
endfor

# === Create output sound(s) ===
if canonVoices > 1
    leftSound = Create Sound from formula: "left_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
    rightSound = Create Sound from formula: "right_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
else
    outputSound = Create Sound from formula: "rhythm_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
endif

# === Synthesize pulses in chunks ===
appendInfoLine: ""
appendInfoLine: "Synthesizing clave sounds..."

# Pre-compute wood ratio string
sWood$ = fixed$(wood_character, 2)
sWoodRatio$ = fixed$(woodRatio, 2)
sDecay$ = fixed$(decay_rate, 1)
sDecay2$ = fixed$(decay_rate * 1.5, 1)

pulsesPerChunk = 20
pulseIndex = 1

while pulseIndex <= totalPulses
    chunkFormulaL$ = ""
    chunkFormulaR$ = ""
    chunkFormula$ = ""
    pulsesInChunk = 0
    
    while pulseIndex <= totalPulses and pulsesInChunk < pulsesPerChunk
        pTime = pulseTime[pulseIndex]
        pFreq = pulseFreq[pulseIndex]
        pVoice = pulseVoice[pulseIndex]
        
        sTime$ = fixed$(pTime, 5)
        sFreq$ = fixed$(pFreq, 1)
        sFreq2$ = fixed$(pFreq * woodRatio, 1)
        
        # CLAVE SOUND: Main tone + inharmonic overtone + click transient
        # Main body: fast-decaying sine at base frequency
        # Wood overtone: inharmonic partial (ratio ~2.76) for woody character
        # Click: very fast noise burst at attack
        
        pulseTerm$ = "if x >= " + sTime$ + " and x < " + sTime$ + " + 0.08 then "
        pulseTerm$ = pulseTerm$ + "0.6 * exp(-" + sDecay$ + " * (x - " + sTime$ + ")) * sin(twoPi * " + sFreq$ + " * x)"
        pulseTerm$ = pulseTerm$ + " + " + sWood$ + " * exp(-" + sDecay2$ + " * (x - " + sTime$ + ")) * sin(twoPi * " + sFreq2$ + " * x)"
        pulseTerm$ = pulseTerm$ + " + 0.3 * exp(-200 * (x - " + sTime$ + ")) * sin(twoPi * " + fixed$(pFreq * 4, 1) + " * x)"
        pulseTerm$ = pulseTerm$ + " else 0 fi"
        
        if canonVoices > 1
            panL = 1 - voicePan[pVoice]
            panR = voicePan[pVoice]
            
            if chunkFormulaL$ = ""
                chunkFormulaL$ = fixed$(panL, 2) + " * (" + pulseTerm$ + ")"
                chunkFormulaR$ = fixed$(panR, 2) + " * (" + pulseTerm$ + ")"
            else
                chunkFormulaL$ = chunkFormulaL$ + " + " + fixed$(panL, 2) + " * (" + pulseTerm$ + ")"
                chunkFormulaR$ = chunkFormulaR$ + " + " + fixed$(panR, 2) + " * (" + pulseTerm$ + ")"
            endif
        else
            if chunkFormula$ = ""
                chunkFormula$ = pulseTerm$
            else
                chunkFormula$ = chunkFormula$ + " + " + pulseTerm$
            endif
        endif
        
        pulsesInChunk = pulsesInChunk + 1
        pulseIndex = pulseIndex + 1
    endwhile
    
    if canonVoices > 1
        if chunkFormulaL$ <> ""
            selectObject: leftSound
            Formula: "self + (" + chunkFormulaL$ + ")"
        endif
        if chunkFormulaR$ <> ""
            selectObject: rightSound
            Formula: "self + (" + chunkFormulaR$ + ")"
        endif
    else
        if chunkFormula$ <> ""
            selectObject: outputSound
            Formula: "self + (" + chunkFormula$ + ")"
        endif
    endif
endwhile

# === Combine stereo if canon ===
if canonVoices > 1
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "clave_" + preset_name$
    
    removeObject: leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "clave_" + preset_name$
endif

# === Fade out only (sharp attack is good) ===
selectObject: outputSound
Formula: "if x > totalDuration - 0.02 then self * ((totalDuration - x) / 0.02) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

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
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Markov Clave Generator — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", string$(tempo_bpm) + " BPM | " + fixed$(base_frequency_Hz, 0) + " Hz | " + string$(totalPulses) + " hits"
    
    # =========================================================================
    # TOUSSAINT CIRCULAR DIAGRAMS
    # =========================================================================
    
    # === First Pattern Circle ===
    Select outer viewport: 0, 2.4, 0.8, 3.0
    Select inner viewport: 0.2, 2.2, 0.9, 2.9
    Axes: -1.4, 1.4, -1.4, 1.4
    
    .pattern1$ = rhythmPattern$[1]
    .len1 = length(.pattern1$)
    
    Colour: "{0.9, 0.9, 0.9}"
    Line width: 1
    Draw circle: 0, 0, 1.0
    
    .onsetCount1 = 0
    for .i to .len1
        .angle = ((.i - 1) / .len1) * twoPi - pi/2
        .px = cos(.angle)
        .py = sin(.angle)
        
        .char$ = mid$(.pattern1$, .i, 1)
        
        if .char$ = "1"
            .onsetCount1 = .onsetCount1 + 1
            .onsetAngle1[.onsetCount1] = .angle
            Colour: "{0.6, 0.3, 0.1}"
            Paint circle: "{0.6, 0.3, 0.1}", .px, .py, 0.12
        else
            Colour: "{0.8, 0.8, 0.8}"
            Paint circle: "{0.8, 0.8, 0.8}", .px, .py, 0.05
        endif
    endfor
    
    if .onsetCount1 > 1
        Colour: "{0.8, 0.5, 0.2}"
        Line width: 2
        for .k to .onsetCount1
            .nextK = .k + 1
            if .nextK > .onsetCount1
                .nextK = 1
            endif
            .x1 = cos(.onsetAngle1[.k]) * 0.7
            .y1 = sin(.onsetAngle1[.k]) * 0.7
            .x2 = cos(.onsetAngle1[.nextK]) * 0.7
            .y2 = sin(.onsetAngle1[.nextK]) * 0.7
            Draw line: .x1, .y1, .x2, .y2
        endfor
        Line width: 1
    endif
    
    Colour: "Black"
    Font size: 8
    Text: 0, "centre", -1.25, "half", "1: " + .pattern1$
    
    # === Second Pattern Circle ===
    Select outer viewport: 2.3, 4.7, 0.8, 3.0
    Select inner viewport: 2.5, 4.5, 0.9, 2.9
    Axes: -1.4, 1.4, -1.4, 1.4
    
    .pattern2$ = rhythmPattern$[2]
    .len2 = length(.pattern2$)
    
    Colour: "{0.9, 0.9, 0.9}"
    Draw circle: 0, 0, 1.0
    
    .onsetCount2 = 0
    for .i to .len2
        .angle = ((.i - 1) / .len2) * twoPi - pi/2
        .px = cos(.angle)
        .py = sin(.angle)
        
        .char$ = mid$(.pattern2$, .i, 1)
        
        if .char$ = "1"
            .onsetCount2 = .onsetCount2 + 1
            .onsetAngle2[.onsetCount2] = .angle
            Colour: "{0.5, 0.25, 0.1}"
            Paint circle: "{0.5, 0.25, 0.1}", .px, .py, 0.12
        else
            Colour: "{0.8, 0.8, 0.8}"
            Paint circle: "{0.8, 0.8, 0.8}", .px, .py, 0.05
        endif
    endfor
    
    if .onsetCount2 > 1
        Colour: "{0.7, 0.4, 0.15}"
        Line width: 2
        for .k to .onsetCount2
            .nextK = .k + 1
            if .nextK > .onsetCount2
                .nextK = 1
            endif
            .x1 = cos(.onsetAngle2[.k]) * 0.7
            .y1 = sin(.onsetAngle2[.k]) * 0.7
            .x2 = cos(.onsetAngle2[.nextK]) * 0.7
            .y2 = sin(.onsetAngle2[.nextK]) * 0.7
            Draw line: .x1, .y1, .x2, .y2
        endfor
        Line width: 1
    endif
    
    Colour: "Black"
    Font size: 8
    Text: 0, "centre", -1.25, "half", "2: " + .pattern2$
    
    # === Third Pattern Circle ===
    Select outer viewport: 4.6, 7.0, 0.8, 3.0
    Select inner viewport: 4.8, 6.8, 0.9, 2.9
    Axes: -1.4, 1.4, -1.4, 1.4
    
    .pattern3$ = rhythmPattern$[3]
    .len3 = length(.pattern3$)
    
    Colour: "{0.9, 0.9, 0.9}"
    Draw circle: 0, 0, 1.0
    
    .onsetCount3 = 0
    for .i to .len3
        .angle = ((.i - 1) / .len3) * twoPi - pi/2
        .px = cos(.angle)
        .py = sin(.angle)
        
        .char$ = mid$(.pattern3$, .i, 1)
        
        if .char$ = "1"
            .onsetCount3 = .onsetCount3 + 1
            .onsetAngle3[.onsetCount3] = .angle
            Colour: "{0.4, 0.2, 0.05}"
            Paint circle: "{0.4, 0.2, 0.05}", .px, .py, 0.12
        else
            Colour: "{0.8, 0.8, 0.8}"
            Paint circle: "{0.8, 0.8, 0.8}", .px, .py, 0.05
        endif
    endfor
    
    if .onsetCount3 > 1
        Colour: "{0.6, 0.35, 0.1}"
        Line width: 2
        for .k to .onsetCount3
            .nextK = .k + 1
            if .nextK > .onsetCount3
                .nextK = 1
            endif
            .x1 = cos(.onsetAngle3[.k]) * 0.7
            .y1 = sin(.onsetAngle3[.k]) * 0.7
            .x2 = cos(.onsetAngle3[.nextK]) * 0.7
            .y2 = sin(.onsetAngle3[.nextK]) * 0.7
            Draw line: .x1, .y1, .x2, .y2
        endfor
        Line width: 1
    endif
    
    Colour: "Black"
    Font size: 8
    Text: 0, "centre", -1.25, "half", "3: " + .pattern3$
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 3.1, 4.8
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 3.2, 4.7
    
    if canonVoices > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    
    selectObject: .monoSpec
    To Spectrogram: 0.01, 8000, 0.002, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 3.2, 4.7
    Axes: 0, totalDuration, 0, 8000
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # === Rhythm State Timeline ===
    Select outer viewport: 0, 7, 4.9, 5.7
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 5.0, 5.6
    
    .showBeats = min(16, totalBeats)
    Axes: 0, .showBeats, 0, rhythmStates + 1
    
    Colour: "{0.85, 0.85, 0.85}"
    Line width: 1
    for .b to .showBeats
        Draw line: .b, 0, .b, rhythmStates + 1
    endfor
    
    for .p to totalPulses
        if pulseBeat[.p] <= .showBeats
            .state = pulseState[.p]
            .beat = pulseBeat[.p]
            .voice = pulseVoice[.p]
            
            if .voice = 1
                Colour: "{0.6, 0.3, 0.1}"
                Paint circle: "{0.6, 0.3, 0.1}", .beat - 0.5, .state, 0.15
            elsif .voice = 2
                Colour: "{0.5, 0.25, 0.1}"
                Paint circle: "{0.5, 0.25, 0.1}", .beat - 0.5, .state, 0.15
            else
                Colour: "{0.4, 0.2, 0.05}"
                Paint circle: "{0.4, 0.2, 0.05}", .beat - 0.5, .state, 0.15
            endif
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Marks bottom every: 1, 4, "yes", "yes", "no"
    Text bottom: "yes", "Beat"
    Text left: "yes", "State"
    
    # === Footer ===
    Select outer viewport: 0, 7, 5.8, 6.2
    Select inner viewport: 0, 7, 5.8, 6.2
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Toussaint necklaces | Wood ratio: " + fixed$(woodRatio, 2) + " | Decay: " + fixed$(decay_rate, 0)
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
