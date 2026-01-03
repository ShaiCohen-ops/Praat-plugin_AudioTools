# ============================================================
# Praat AudioTools - Poisson_Rhythm_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Chunked synthesis
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic synthesis using hierarchical Poisson point processes.
#   Two independent processes generate main beats and subdivisions,
#   creating statistically varied rhythmic patterns with optional
#   canon (delayed voice entries).
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.2:
#   - Chunked synthesis (prevents formula explosion)
#   - Added visualization
#   - Modern syntax
# ============================================================

form Poisson Rhythm Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Gentle Pulse
        option Nervous Ticks
        option Techno Beat
        option Ambient Drift
        option Glitchy Percussion
        option Heartbeat
        option Rain Drops
        option Industrial Noise
    
    comment === Canon Mode ===
    optionmenu Canon_mode 1
        option No Canon
        option Canon 2 voices
        option Canon 3 voices
        option Canon 4 voices
    positive Canon_delay_s 1.0
    
    comment === Timing ===
    positive Duration_s 6.0
    integer Sample_rate_Hz 44100
    
    comment === Rhythm Parameters ===
    positive Beat_rate 2.0 (= main beats per second)
    positive Subdivision_rate 8.0 (= subdivisions per second)
    
    comment === Sound Parameters ===
    positive Base_frequency_Hz 150
    positive Percussive_decay_s 0.1
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    beat_rate = 1.5
    subdivision_rate = 4.0
    base_frequency_Hz = 120
    percussive_decay_s = 0.2
    preset_name$ = "GentlePulse"
elsif preset = 3
    beat_rate = 4.0
    subdivision_rate = 15.0
    base_frequency_Hz = 200
    percussive_decay_s = 0.05
    preset_name$ = "NervousTicks"
elsif preset = 4
    beat_rate = 2.5
    subdivision_rate = 12.0
    base_frequency_Hz = 80
    percussive_decay_s = 0.08
    preset_name$ = "TechnoBeat"
elsif preset = 5
    beat_rate = 0.8
    subdivision_rate = 3.0
    base_frequency_Hz = 100
    percussive_decay_s = 0.3
    preset_name$ = "AmbientDrift"
elsif preset = 6
    beat_rate = 3.0
    subdivision_rate = 20.0
    base_frequency_Hz = 180
    percussive_decay_s = 0.04
    preset_name$ = "GlitchyPercussion"
elsif preset = 7
    beat_rate = 1.2
    subdivision_rate = 6.0
    base_frequency_Hz = 60
    percussive_decay_s = 0.15
    preset_name$ = "Heartbeat"
elsif preset = 8
    beat_rate = 0.5
    subdivision_rate = 10.0
    base_frequency_Hz = 250
    percussive_decay_s = 0.25
    preset_name$ = "RainDrops"
elsif preset = 9
    beat_rate = 5.0
    subdivision_rate = 25.0
    base_frequency_Hz = 140
    percussive_decay_s = 0.06
    preset_name$ = "IndustrialNoise"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
eventsPerChunk = 20

# === Info ===
writeInfoLine: "=== Poisson Rhythm Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Beat rate: ", beat_rate, "/s"
appendInfoLine: "Subdivision rate: ", subdivision_rate, "/s"
appendInfoLine: "Canon: ", canon_mode, " voices"
appendInfoLine: ""

# === Generate Poisson Processes ===
appendInfoLine: "Generating Poisson events..."

Create Poisson process: "beats_" + uid$, 0, duration_s, beat_rate
beatsProcess = selected("PointProcess")
nBeats = Get number of points

Create Poisson process: "subs_" + uid$, 0, duration_s, subdivision_rate
subsProcess = selected("PointProcess")
nSubs = Get number of points

appendInfoLine: "  Main beats: ", nBeats
appendInfoLine: "  Subdivisions: ", nSubs

# === Store Event Times ===
for b to nBeats
    selectObject: beatsProcess
    beatTime[b] = Get time from index: b
endfor

for s to nSubs
    selectObject: subsProcess
    subTime[s] = Get time from index: s
endfor

# === Synthesis Parameters ===
beatDur = 0.15
subDur = 0.08
beatAmp = 0.8
subAmp = 0.5
decayRate = 1 / percussive_decay_s
subFreq = base_frequency_Hz * 1.5

# === Non-Canon Mode: Simple Mono Output ===
if canon_mode = 1
    appendInfoLine: ""
    appendInfoLine: "Synthesizing (no canon)..."
    
    outputSound = Create Sound from formula: "rhythm_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    
    # Synthesize beats in chunks
    nChunksB = ceiling(nBeats / eventsPerChunk)
    for chunk to nChunksB
        startIdx = (chunk - 1) * eventsPerChunk + 1
        endIdx = min(chunk * eventsPerChunk, nBeats)
        
        chunkFormula$ = ""
        for ev from startIdx to endIdx
            t = beatTime[ev]
            d = beatDur
            if t + d > duration_s
                d = duration_s - t
            endif
            
            if d > 0.005
                t$ = fixed$(t, 6)
                d$ = fixed$(d, 6)
                
                # Exponential decay drum: amp * sin(freq*x) * exp(-decay*(x-t))
                term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(beatAmp, 2) + " * sin(twoPi * " + fixed$(base_frequency_Hz, 1) + " * x) * exp(-" + fixed$(decayRate, 1) + " * (x - " + t$ + ")) else 0 fi"
                
                if chunkFormula$ = ""
                    chunkFormula$ = term$
                else
                    chunkFormula$ = chunkFormula$ + " + " + term$
                endif
            endif
        endfor
        
        if chunkFormula$ <> ""
            selectObject: outputSound
            Formula: "self + (" + chunkFormula$ + ")"
        endif
    endfor
    
    # Synthesize subdivisions in chunks
    nChunksS = ceiling(nSubs / eventsPerChunk)
    for chunk to nChunksS
        startIdx = (chunk - 1) * eventsPerChunk + 1
        endIdx = min(chunk * eventsPerChunk, nSubs)
        
        chunkFormula$ = ""
        for ev from startIdx to endIdx
            t = subTime[ev]
            d = subDur
            if t + d > duration_s
                d = duration_s - t
            endif
            
            if d > 0.005
                t$ = fixed$(t, 6)
                d$ = fixed$(d, 6)
                
                term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(subAmp, 2) + " * sin(twoPi * " + fixed$(subFreq, 1) + " * x) * exp(-" + fixed$(decayRate, 1) + " * (x - " + t$ + ")) else 0 fi"
                
                if chunkFormula$ = ""
                    chunkFormula$ = term$
                else
                    chunkFormula$ = chunkFormula$ + " + " + term$
                endif
            endif
        endfor
        
        if chunkFormula$ <> ""
            selectObject: outputSound
            Formula: "self + (" + chunkFormula$ + ")"
        endif
    endfor
    
    Rename: "poisson_rhythm_" + preset_name$

# === Canon Mode: Multiple Delayed Voices ===
else
    nVoices = canon_mode
    totalDuration = duration_s + (nVoices - 1) * canon_delay_s
    
    appendInfoLine: ""
    appendInfoLine: "Synthesizing canon (", nVoices, " voices)..."
    
    leftSound = Create Sound from formula: "left_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
    rightSound = Create Sound from formula: "right_" + uid$, 1, 0, totalDuration, sample_rate_Hz, "0"
    
    for voice to nVoices
        voiceDelay = (voice - 1) * canon_delay_s
        
        # Alternate L/R panning and frequency
        if voice mod 2 = 1
            voiceFreq = base_frequency_Hz * 0.8
            targetSound = leftSound
            appendInfoLine: "  Voice ", voice, ": LEFT, ", fixed$(voiceFreq, 0), " Hz"
        else
            voiceFreq = base_frequency_Hz * 1.2
            targetSound = rightSound
            appendInfoLine: "  Voice ", voice, ": RIGHT, ", fixed$(voiceFreq, 0), " Hz"
        endif
        
        voiceSubFreq = voiceFreq * 1.5
        
        # Synthesize beats for this voice
        nChunksB = ceiling(nBeats / eventsPerChunk)
        for chunk to nChunksB
            startIdx = (chunk - 1) * eventsPerChunk + 1
            endIdx = min(chunk * eventsPerChunk, nBeats)
            
            chunkFormula$ = ""
            for ev from startIdx to endIdx
                t = beatTime[ev] + voiceDelay
                d = beatDur
                if t + d > totalDuration
                    d = totalDuration - t
                endif
                
                if d > 0.005 and t < totalDuration
                    t$ = fixed$(t, 6)
                    d$ = fixed$(d, 6)
                    
                    term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(beatAmp, 2) + " * sin(twoPi * " + fixed$(voiceFreq, 1) + " * x) * exp(-" + fixed$(decayRate, 1) + " * (x - " + t$ + ")) else 0 fi"
                    
                    if chunkFormula$ = ""
                        chunkFormula$ = term$
                    else
                        chunkFormula$ = chunkFormula$ + " + " + term$
                    endif
                endif
            endfor
            
            if chunkFormula$ <> ""
                selectObject: targetSound
                Formula: "self + (" + chunkFormula$ + ")"
            endif
        endfor
        
        # Synthesize subdivisions for this voice
        nChunksS = ceiling(nSubs / eventsPerChunk)
        for chunk to nChunksS
            startIdx = (chunk - 1) * eventsPerChunk + 1
            endIdx = min(chunk * eventsPerChunk, nSubs)
            
            chunkFormula$ = ""
            for ev from startIdx to endIdx
                t = subTime[ev] + voiceDelay
                d = subDur
                if t + d > totalDuration
                    d = totalDuration - t
                endif
                
                if d > 0.005 and t < totalDuration
                    t$ = fixed$(t, 6)
                    d$ = fixed$(d, 6)
                    
                    term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(subAmp, 2) + " * sin(twoPi * " + fixed$(voiceSubFreq, 1) + " * x) * exp(-" + fixed$(decayRate, 1) + " * (x - " + t$ + ")) else 0 fi"
                    
                    if chunkFormula$ = ""
                        chunkFormula$ = term$
                    else
                        chunkFormula$ = chunkFormula$ + " + " + term$
                    endif
                endif
            endfor
            
            if chunkFormula$ <> ""
                selectObject: targetSound
                Formula: "self + (" + chunkFormula$ + ")"
            endif
        endfor
    endfor
    
    # Combine to stereo
    selectObject: leftSound
    plusObject: rightSound
    outputSound = Combine to stereo
    Rename: "poisson_rhythm_" + preset_name$ + "_canon"
    
    removeObject: leftSound, rightSound
endif

# === Fade In/Out ===
selectObject: outputSound
actualDuration = Get total duration
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > actualDuration - 0.05 then self * ((actualDuration - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Cleanup ===
removeObject: beatsProcess, subsProcess

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
    
    selectObject: outputSound
    .dur = Get total duration
    
    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.7
    Select inner viewport: 0, 7, 0.2, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "Poisson Rhythm — " + preset_name$
    Font size: 10
    Colour: "{0.4, 0.4, 0.4}"
    if canon_mode > 1
        Text: 0.5, "centre", 0.2, "half", "Beats: " + string$(nBeats) + " | Subs: " + string$(nSubs) + " | Canon: " + string$(canon_mode) + " voices"
    else
        Text: 0.5, "centre", 0.2, "half", "Beats: " + string$(nBeats) + " (" + fixed$(beat_rate, 1) + "/s) | Subs: " + string$(nSubs) + " (" + fixed$(subdivision_rate, 1) + "/s)"
    endif
    
    # === Event Timeline ===
    Select outer viewport: 0, 7, 0.8, 2.3
    Colour: "{0.95, 0.95, 0.95}"
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Select inner viewport: 0.5, 6.5, 0.9, 2.2
    Axes: 0, .dur, 0, 2
    
    # Draw beats (bottom, larger)
    for .b to nBeats
        .t = beatTime[.b]
        Paint circle (mm): "{0.2, 0.4, 0.8}", .t, 0.5, 2
    endfor
    
    # Draw subdivisions (top, smaller)
    for .s to nSubs
        .t = subTime[.s]
        Paint circle (mm): "{0.8, 0.5, 0.2}", .t, 1.5, 1
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Beats  Subs"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 2.5, 5.0
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: 0.5, 6.5, 2.6, 4.9
    
    selectObject: outputSound
    .nCh = Get number of channels
    if .nCh > 1
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    
    selectObject: .monoSpec
    .maxFreq = base_frequency_Hz * 4
    .maxFreq = max(1000, .maxFreq)
    To Spectrogram: 0.02, .maxFreq, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: 0.5, 6.5, 2.6, 4.9
    Axes: 0, .dur, 0, .maxFreq
    
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 8
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 5.1, 5.5
    Select inner viewport: 0, 7, 5.1, 5.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Blue = Main beats | Orange = Subdivisions"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc