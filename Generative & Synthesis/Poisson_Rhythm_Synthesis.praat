# ============================================================
# Praat AudioTools - Poisson_Rhythm_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 mechanism visualization + compact form (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Rhythmic synthesis using two independent homogeneous Poisson layers.
#   One process generates accented main beats and a denser independent
#   secondary layer. Canon mode repeats the same stochastic realization
#   at delayed entries, with alternating pitch and stereo placement.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.2:
#   - Chunked synthesis (prevents formula explosion), added viz
#
# Changelog v0.3:
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, event timeline + spectrogram, grey summary, larger fonts,
#     full-precision RGB).
#   - Replaced the non-ASCII em-dash.
#
# Changelog v0.4:
#   - Corrected the model description: the two Poisson layers are independent,
#     not hierarchical.
#   - Reset oscillator phase at every event and added a smooth cosine release,
#     eliminating discontinuities at event onset and truncation.
#   - Added optional deterministic random seed for reproducible experiments.
#   - Added sample-rate/Nyquist validation and safer short-duration fades.
#   - Increased decay-rate precision in generated formulas.
#
# Changelog v0.5:
#   - Compact laptop-safe main form; technical/reproducibility controls moved
#     to an optional Details page.
#   - User-facing terminology now says secondary Poisson layer rather than
#     subdivision, preserving the actual independent-process model.
#   - Visualization rebuilt around the mechanism, not merely the result:
#       A actual normalized inter-arrival sequence vs Poisson expectation
#       B analytical event kernel: carrier x exponential decay x cosine release
#       C actual event schedule and delayed canon copies
#       D measured final waveform only as output confirmation
#   - Added inter-arrival mean/CV QC and measured peak/RMS QC.
#   - Added explicit process-flow line and model-honesty summary.
# ============================================================

form Poisson Rhythm Synthesis v0.5
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

    positive Duration_s 6.0
    positive Beat_rate 2.0
    positive Secondary_event_rate 8.0
    positive Base_frequency_Hz 150
    positive Percussive_decay_s 0.1

    optionmenu Canon_mode 1
        option No Canon
        option Canon 2 voices
        option Canon 3 voices
        option Canon 4 voices

    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
sample_rate_Hz = 44100
canon_delay_s = 1.0
random_seed = 0
beatDur = 0.15
subDur = 0.08
beatAmp = 0.8
subAmp = 0.5

# Preserve the established internal variable name while presenting the model
# honestly in the form and visualization.
subdivision_rate = secondary_event_rate

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

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT DETAILS PAGE
# ---------------------------------------------------------------------------
if edit_details
    beginPause: "Poisson Rhythm v0.5 - Technical / Reproducibility Details"
        integer: "Sample rate (Hz)", sample_rate_Hz
        positive: "Canon delay (s)", canon_delay_s
        integer: "Random seed (0 = unpredictable)", random_seed
        positive: "Main event window (s)", beatDur
        positive: "Secondary event window (s)", subDur
        positive: "Main event amplitude", beatAmp
        positive: "Secondary event amplitude", subAmp
    endPause: "Run", 1
endif

# === Validate Parameters ===
if sample_rate_Hz < 1000
    exitScript: "Sample_rate_Hz must be at least 1000 Hz."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 (random) or a positive integer."
endif
if beatDur <= 0 or subDur <= 0
    exitScript: "Event windows must be positive."
endif
if beatAmp <= 0 or subAmp <= 0
    exitScript: "Event amplitudes must be positive."
endif

nyquist = sample_rate_Hz / 2
if canon_mode = 1
    highestOscFreq = base_frequency_Hz * 1.5
else
    highestOscFreq = base_frequency_Hz * 1.8
endif
if highestOscFreq >= 0.95 * nyquist
    exitScript: "Highest oscillator frequency (", fixed$(highestOscFreq, 1), " Hz) must stay below 95% of Nyquist (", fixed$(0.95 * nyquist, 1), " Hz). Lower Base_frequency_Hz or raise Sample_rate_Hz."
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
appendInfoLine: "Secondary Poisson rate: ", subdivision_rate, "/s"
if canon_mode = 1
    appendInfoLine: "Canon: off"
else
    appendInfoLine: "Canon: ", canon_mode, " voices; delay ", canon_delay_s, " s"
endif
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed: random"
endif
appendInfoLine: ""

# === Generate Poisson Processes ===
appendInfoLine: "Generating Poisson events..."

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
endif

Create Poisson process: "beats_" + uid$, 0, duration_s, beat_rate
beatsProcess = selected("PointProcess")
nBeats = Get number of points

Create Poisson process: "subs_" + uid$, 0, duration_s, subdivision_rate
subsProcess = selected("PointProcess")
nSubs = Get number of points

if random_seed > 0
    random_initializeSafelyAndUnpredictably ()
endif

realizedBeatRate = nBeats / duration_s
realizedSubRate = nSubs / duration_s
appendInfoLine: "  Main beats: ", nBeats, " (realized ", fixed$(realizedBeatRate, 3), "/s)"
appendInfoLine: "  Secondary events: ", nSubs, " (realized ", fixed$(realizedSubRate, 3), "/s)"

# === Store Event Times ===
for b to nBeats
    selectObject: beatsProcess
    beatTime[b] = Get time from index: b
endfor

for s to nSubs
    selectObject: subsProcess
    subTime[s] = Get time from index: s
endfor

# === Poisson Inter-arrival QC ===
# Complete waiting times ending at each observed event. The final censored
# interval from the last event to duration_s is intentionally excluded.
beatMeanIoi = 0
beatCvIoi = 0
beatNormMean = 0
if nBeats > 0
    .sumIoi = 0
    .sumSqIoi = 0
    .prevT = 0
    for b to nBeats
        .ioi = beatTime[b] - .prevT
        beatIoi[b] = .ioi
        beatNormIoi[b] = beat_rate * .ioi
        .sumIoi = .sumIoi + .ioi
        .sumSqIoi = .sumSqIoi + .ioi * .ioi
        .prevT = beatTime[b]
    endfor
    beatMeanIoi = .sumIoi / nBeats
    beatNormMean = beat_rate * beatMeanIoi
    if nBeats > 1 and beatMeanIoi > 0
        .varIoi = max(0, .sumSqIoi / nBeats - beatMeanIoi * beatMeanIoi)
        beatCvIoi = sqrt(.varIoi) / beatMeanIoi
    endif
endif

subMeanIoi = 0
subCvIoi = 0
subNormMean = 0
if nSubs > 0
    .sumIoi = 0
    .sumSqIoi = 0
    .prevT = 0
    for s to nSubs
        .ioi = subTime[s] - .prevT
        subIoi[s] = .ioi
        subNormIoi[s] = subdivision_rate * .ioi
        .sumIoi = .sumIoi + .ioi
        .sumSqIoi = .sumSqIoi + .ioi * .ioi
        .prevT = subTime[s]
    endfor
    subMeanIoi = .sumIoi / nSubs
    subNormMean = subdivision_rate * subMeanIoi
    if nSubs > 1 and subMeanIoi > 0
        .varIoi = max(0, .sumSqIoi / nSubs - subMeanIoi * subMeanIoi)
        subCvIoi = sqrt(.varIoi) / subMeanIoi
    endif
endif

appendInfoLine: "  Main mean IOI: ", fixed$(beatMeanIoi, 4), " s (expected ", fixed$(1/beat_rate, 4), " s)"
if nBeats > 1
    appendInfoLine: "  Main IOI CV: ", fixed$(beatCvIoi, 3), " (Poisson expectation approx. 1)"
endif
appendInfoLine: "  Secondary mean IOI: ", fixed$(subMeanIoi, 4), " s (expected ", fixed$(1/subdivision_rate, 4), " s)"
if nSubs > 1
    appendInfoLine: "  Secondary IOI CV: ", fixed$(subCvIoi, 3), " (Poisson expectation approx. 1)"
endif

# === Synthesis Parameters ===
# Local-phase carrier x exponential decay x cosine release. The window lengths
# and amplitudes come from the defaults or optional Details page.
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
                
                # Local-phase percussive event with exponential decay and smooth release
                term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(beatAmp, 2) + " * sin(twoPi * " + fixed$(base_frequency_Hz, 3) + " * (x - " + t$ + ")) * exp(-" + fixed$(decayRate, 6) + " * (x - " + t$ + ")) * 0.5 * (1 + cos(pi * (x - " + t$ + ") / " + d$ + ")) else 0 fi"
                
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
                
                term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(subAmp, 2) + " * sin(twoPi * " + fixed$(subFreq, 3) + " * (x - " + t$ + ")) * exp(-" + fixed$(decayRate, 6) + " * (x - " + t$ + ")) * 0.5 * (1 + cos(pi * (x - " + t$ + ") / " + d$ + ")) else 0 fi"
                
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
                    
                    term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(beatAmp, 2) + " * sin(twoPi * " + fixed$(voiceFreq, 3) + " * (x - " + t$ + ")) * exp(-" + fixed$(decayRate, 6) + " * (x - " + t$ + ")) * 0.5 * (1 + cos(pi * (x - " + t$ + ") / " + d$ + ")) else 0 fi"
                    
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
                    
                    term$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + fixed$(subAmp, 2) + " * sin(twoPi * " + fixed$(voiceSubFreq, 3) + " * (x - " + t$ + ")) * exp(-" + fixed$(decayRate, 6) + " * (x - " + t$ + ")) * 0.5 * (1 + cos(pi * (x - " + t$ + ") / " + d$ + ")) else 0 fi"
                    
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
fadeIn = min(0.02, actualDuration / 4)
fadeOut = min(0.05, actualDuration / 4)
if fadeIn > 0
    Formula: "if x < fadeIn then self * (x / fadeIn) else self fi"
endif
if fadeOut > 0
    Formula: "if x > actualDuration - fadeOut then self * ((actualDuration - x) / fadeOut) else self fi"
endif

# === Level QC / Normalize ===
selectObject: outputSound
preNormPeak = Get absolute extremum: 0, 0, "None"
preNormRMS = Get root-mean-square: 0, 0

# Scale only non-silent realizations; a valid Poisson draw can contain zero events.
if nBeats + nSubs > 0 and preNormPeak > 0
    Scale peak: 0.9
endif

selectObject: outputSound
finalPeak = Get absolute extremum: 0, 0, "None"
finalRMS = Get root-mean-square: 0, 0
appendInfoLine: "Output pre-normalization peak/RMS: ", fixed$(preNormPeak, 4), " / ", fixed$(preNormRMS, 4)
appendInfoLine: "Output final peak/RMS: ", fixed$(finalPeak, 4), " / ", fixed$(finalRMS, 4)

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

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"
    .grey$ = "{0.42,0.42,0.45}"

    Erase all

    selectObject: outputSound
    .dur = Get total duration
    .nCh = Get number of channels
    if canon_mode = 1
        .nVisVoices = 1
    else
        .nVisVoices = canon_mode
    endif

    if random_seed > 0
        .seed$ = "seed " + string$(random_seed)
    else
        .seed$ = "unpredictable seed"
    endif

    # -----------------------------------------------------------------------
    # HEADER / PROCESS FLOW
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.32
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "POISSON RHYTHM SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.36,0.68
    Axes: 0,1,0,1
    Font size: 6
    Colour: .grey$
    Text: 0.5,"centre",0.70,"half",
        ... "two independent Poisson clocks | main " + fixed$(beat_rate,2)
        ... + "/s | secondary " + fixed$(subdivision_rate,2) + "/s | " + .seed$
    Text: 0.5,"centre",0.20,"half",
        ... "rates -> Poisson waiting times -> phase-reset event kernels -> delayed canon copies -> mix"

    # -----------------------------------------------------------------------
    # PANEL A: POISSON WAITING-TIME REALIZATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.78,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  POISSON CLOCKS | actual normalized waiting times; theoretical mean = 1"

    Select inner viewport: .left,.right,1.01,1.14
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.01,"left",0.72,"half",
        ... "Poisson rule: p(dt)=lambda exp(-lambda dt); expected normalized waiting time lambda dt = 1"
    Text: 0.01,"left",0.22,"half",
        ... "blue main | orange secondary | each stem is one realized complete waiting time"

    .ratioMax = 4
    for .b to nBeats
        .ratioMax = max(.ratioMax, beatNormIoi[.b])
    endfor
    for .s to nSubs
        .ratioMax = max(.ratioMax, subNormIoi[.s])
    endfor
    .ratioMax = 1.08 * .ratioMax

    Select inner viewport: .left,.right,1.16,2.08
    Axes: 0,duration_s,0,.ratioMax
    Paint rectangle: .bg$,0,duration_s,0,.ratioMax

    Colour: .grid$
    Dotted line
    Draw line: 0,1,duration_s,1
    Plain line

    .stepB = max(1,ceiling(max(1,nBeats)/500))
    for .b to nBeats
        if ((.b-1) mod .stepB)=0
            Colour: .blue$
            Draw line: beatTime[.b],0,beatTime[.b],beatNormIoi[.b]
            Paint circle (mm): .blue$,beatTime[.b],beatNormIoi[.b],1.1
        endif
    endfor

    .stepS = max(1,ceiling(max(1,nSubs)/700))
    for .s to nSubs
        if ((.s-1) mod .stepS)=0
            Colour: .orange$
            Draw line: subTime[.s],0,subTime[.s],subNormIoi[.s]
            Paint circle (mm): .orange$,subTime[.s],subNormIoi[.s],0.8
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","rate x IOI"
    Text bottom: "yes","Event time (s)"

    # -----------------------------------------------------------------------
    # PANEL B: EVENT-SYNTHESIS KERNEL
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.22,2.42
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  EVENT KERNEL | phase-reset carrier x exponential decay x cosine release"

    Select inner viewport: .left,.right,2.44,2.55
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.5,"centre",0.48,"half",
        ... "tau=t-tevent | y=A sin(2 pi f tau) exp(-tau/decay) 0.5[1+cos(pi tau/D)]"

    Select inner viewport: .left,3.92,2.57,2.68
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.5,"centre",0.48,"half",
        ... "main: " + fixed$(base_frequency_Hz,0) + " Hz | " + fixed$(1000*beatDur,0) + " ms"

    Select inner viewport: 4.20,.right,2.57,2.68
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    Text: 0.5,"centre",0.48,"half",
        ... "secondary: " + fixed$(subFreq,0) + " Hz | " + fixed$(1000*subDur,0) + " ms"

    # Main event kernel.
    .aY = 1.08 * beatAmp
    Select inner viewport: .left,3.92,2.70,3.48
    Axes: 0,1000*beatDur,-.aY,.aY
    Paint rectangle: .bg$,0,1000*beatDur,-.aY,.aY
    Colour: .grid$
    Dotted line
    Draw line: 0,0,1000*beatDur,0
    Plain line

    .nPts = 240
    .prevMs = 0
    .prevY = 0
    .prevEnv = beatAmp
    for .k from 1 to .nPts
        .tau = .k/.nPts*beatDur
        .ms = 1000*.tau
        .env = beatAmp * exp(-decayRate*.tau) * 0.5 * (1+cos(pi*.tau/beatDur))
        .y = .env * sin(twoPi*base_frequency_Hz*.tau)
        Colour: .blue$
        Draw line: .prevMs,.prevY,.ms,.y
        Colour: .grey$
        Dashed line
        Draw line: .prevMs,.prevEnv,.ms,.env
        Draw line: .prevMs,-.prevEnv,.ms,-.env
        Plain line
        .prevMs = .ms
        .prevY = .y
        .prevEnv = .env
    endfor
    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 4,"yes","yes","no"
    Font size: 5
    Text left: "yes","Amp"
    Text bottom: "yes","ms"

    # Secondary event kernel.
    .aY = 1.08 * subAmp
    Select inner viewport: 4.20,.right,2.70,3.48
    Axes: 0,1000*subDur,-.aY,.aY
    Paint rectangle: .bg$,0,1000*subDur,-.aY,.aY
    Colour: .grid$
    Dotted line
    Draw line: 0,0,1000*subDur,0
    Plain line

    .prevMs = 0
    .prevY = 0
    .prevEnv = subAmp
    for .k from 1 to .nPts
        .tau = .k/.nPts*subDur
        .ms = 1000*.tau
        .env = subAmp * exp(-decayRate*.tau) * 0.5 * (1+cos(pi*.tau/subDur))
        .y = .env * sin(twoPi*subFreq*.tau)
        Colour: .orange$
        Draw line: .prevMs,.prevY,.ms,.y
        Colour: .grey$
        Dashed line
        Draw line: .prevMs,.prevEnv,.ms,.env
        Draw line: .prevMs,-.prevEnv,.ms,-.env
        Plain line
        .prevMs = .ms
        .prevY = .y
        .prevEnv = .env
    endfor
    Colour: "Black"
    Draw inner box
    Marks left: 3,"yes","yes","no"
    Marks bottom: 4,"yes","yes","no"
    Font size: 5
    Text left: "yes","Amp"
    Text bottom: "yes","ms"

    # -----------------------------------------------------------------------
    # PANEL C: EVENT SCHEDULE -> CANON TRANSFORMATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.62,3.82
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    if canon_mode = 1
        Text: 0.5,"centre",0.52,"half",
            ... "C  EVENT SCHEDULE | two independent layers mapped to two event kernels"
    else
        Text: 0.5,"centre",0.52,"half",
            ... "C  CANON TRANSFORMATION | same realization copied at fixed delays; pitch/pan alternate by voice"
    endif

    Select inner viewport: .left,.right,3.84,3.95
    Axes: 0,1,0,1
    Font size: 5
    Colour: .grey$
    if canon_mode = 1
        Text: 0.5,"centre",0.48,"half",
            ... "render: main f | secondary 1.5f | all event phases reset at their own onset"
    else
        Text: 0.5,"centre",0.48,"half",
            ... "voice v: tv=t+(v-1)d | odd -> L, 0.8f | even -> R, 1.2f"
    endif

    .yMax = 2 * .nVisVoices + 0.5
    Select inner viewport: .left,.right,3.98,5.02
    Axes: 0,.dur,0.5,.yMax
    Paint rectangle: .bg$,0,.dur,0.5,.yMax

    Colour: .grid$
    Dotted line
    for .voice to .nVisVoices
        .beatY = 2*.voice-0.5
        .subY = 2*.voice+0.5
        Draw line: 0,.beatY,.dur,.beatY
        Draw line: 0,.subY,.dur,.subY
    endfor
    Plain line

    for .voice to .nVisVoices
        if canon_mode = 1
            .delay = 0
        else
            .delay = (.voice-1)*canon_delay_s
        endif
        .beatY = 2*.voice-0.5
        .subY = 2*.voice+0.5

        .stepB = max(1,ceiling(max(1,nBeats)/600))
        for .b to nBeats
            if ((.b-1) mod .stepB)=0
                .t = beatTime[.b]+.delay
                if .t <= .dur
                    Paint circle (mm): .blue$,.t,.beatY,1.25
                endif
            endif
        endfor

        .stepS = max(1,ceiling(max(1,nSubs)/900))
        for .s to nSubs
            if ((.s-1) mod .stepS)=0
                .t = subTime[.s]+.delay
                if .t <= .dur
                    Paint circle (mm): .orange$,.t,.subY,0.80
                endif
            endif
        endfor
    endfor

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Voice lanes"
    Text bottom: "yes","Time (s)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED OUTPUT CONFIRMATION
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.16,5.36
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MEASURED OUTPUT | final waveform on fixed amplitude scale (confirmation, not the model)"

    if .nCh = 1
        Select inner viewport: .left,.right,5.44,6.42
        Axes: 0,.dur,-1,1
        Paint rectangle: .bg$,0,.dur,-1,1
        selectObject: outputSound
        Colour: .purple$
        Draw: 0,0,-1,1,"no","Curve"
        Select inner viewport: .left,.right,5.44,6.42
        Axes: 0,.dur,-1,1
        Colour: "Black"
        Draw inner box
        Marks left: 3,"yes","yes","no"
        Marks bottom: 5,"yes","yes","no"
        Font size: 6
        Text left: "yes","Amplitude"
        Text bottom: "yes","Time (s)"
    else
        Select inner viewport: .left,.right,5.44,5.88
        Axes: 0,.dur,-1,1
        Paint rectangle: .bg$,0,.dur,-1,1
        selectObject: outputSound
        Extract one channel: 1
        .leftViz = selected("Sound")
        Colour: .green$
        Draw: 0,0,-1,1,"no","Curve"
        removeObject: .leftViz
        Select inner viewport: .left,.right,5.44,5.88
        Axes: 0,.dur,-1,1
        Colour: "Black"
        Draw inner box
        Font size: 5
        Text left: "yes","L"

        Select inner viewport: .left,.right,5.98,6.42
        Axes: 0,.dur,-1,1
        Paint rectangle: .bg$,0,.dur,-1,1
        selectObject: outputSound
        Extract one channel: 2
        .rightViz = selected("Sound")
        Colour: .purple$
        Draw: 0,0,-1,1,"no","Curve"
        removeObject: .rightViz
        Select inner viewport: .left,.right,5.98,6.42
        Axes: 0,.dur,-1,1
        Colour: "Black"
        Draw inner box
        Marks bottom: 5,"yes","yes","no"
        Font size: 5
        Text left: "yes","R"
        Text bottom: "yes","Time (s)"
    endif

    # -----------------------------------------------------------------------
    # PROCESS / QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.62,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"
    Text: 0.02,"left",0.80,"half",
        ... "MODEL  |  two independent homogeneous Poisson layers; not hierarchical subdivisions"

    if nBeats > 1
        .beatCv$ = fixed$(beatCvIoi,2)
    else
        .beatCv$ = "n/a"
    endif
    if nSubs > 1
        .subCv$ = fixed$(subCvIoi,2)
    else
        .subCv$ = "n/a"
    endif
    Text: 0.02,"left",0.58,"half",
        ... "POISSON QC  |  target/realized main " + fixed$(beat_rate,2) + "/"
        ... + fixed$(realizedBeatRate,2) + "/s, secondary " + fixed$(subdivision_rate,2)
        ... + "/" + fixed$(realizedSubRate,2) + "/s | IOI CV " + .beatCv$ + "/" + .subCv$

    Text: 0.02,"left",0.36,"half",
        ... "KERNEL  |  phase reset | decay " + fixed$(percussive_decay_s,3)
        ... + " s | windows " + fixed$(1000*beatDur,0) + "/" + fixed$(1000*subDur,0)
        ... + " ms | nominal frequencies " + fixed$(base_frequency_Hz,0) + "/" + fixed$(subFreq,0) + " Hz"

    if canon_mode = 1
        .canon$ = "off"
    else
        .canon$ = string$(canon_mode) + " voices x " + fixed$(canon_delay_s,2) + " s delay"
    endif
    Text: 0.02,"left",0.14,"half",
        ... "OUTPUT QC  |  canon " + .canon$ + " | sr " + string$(sample_rate_Hz)
        ... + " Hz | top oscillator " + fixed$(highestOscFreq,0) + " Hz | final peak/RMS "
        ... + fixed$(finalPeak,3) + "/" + fixed$(finalRMS,4)

    Colour: "Black"
    Line width: 1
endproc
