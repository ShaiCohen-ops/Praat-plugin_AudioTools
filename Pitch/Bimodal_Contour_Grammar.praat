# ============================================================
# Praat AudioTools - Bimodal Contour Grammar
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   The SAME procedures generate both audio resynthesis and
#   visual animation.
#   Grammar: S → Phrase + S (recursive)
#            Phrase → Onset + Nucleus + Coda
#
#   Terminals:
#     Onset   — JumpUp  | GlissandoUp
#     Nucleus — Plateau | Wobble
#     Coda    — Fall    | DeepDrop
#
#   Grammar parameters (pitch range, gesture speed, interval
#   width, wobble depth) shape the musical character.  Six
#   presets cover distinct compositional aesthetics.  The
#   seeded LCG ensures full reproducibility from seed.
#
# ============================================================

# Bimodal Contour Grammar: Sound Processing + Visual Presentation

form Bimodal Contour Generator v0.4
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Microtonal Murmur   (narrow, slow, tiny wobble)
        option Leaping Gestures    (wide jumps, moderate speed)
        option Rapid Stutter       (very short, narrow range)
        option Wide Arc            (large intervals, slow, deep)
        option Gentle Drift        (medium range, slow, soft wobble)

    comment === Grammar Parameters (Custom only) ===
    positive Pitch_base_lo_Hz 100
    positive Pitch_base_hi_Hz 200
    real Gesture_scale 1.0
    real Interval_scale 1.0
    positive Wobble_depth_Hz 5.0

    comment === Random Seed ===
    integer randomSeed 0
    comment (0 = use current time, any other number = fixed seed)
    
    comment === Color & Style ===
    optionmenu colorScheme 1
        option Pitch+Loudness Rainbow
        option PitchClass+Loudness Wheel
        option Intensity Heatmap
        option Octave Spiral
    
    optionmenu lineStyle 1
        option Thin continuous line
        option Thickness varies with loudness
        option Dots with size varies with loudness
    
    positive minDotSize 1.0
    positive maxDotSize 4.0
    
    comment === Audio Synthesis ===
    positive baseLoudness 70
    positive loudnessVariation 10
    
    comment === Display Options ===
    boolean showGrid 1
    boolean showNoteLabels 1
    boolean playAfterGeneration 1
endform

# ============================================================
# APPLY PRESETS
# ============================================================

presetName$ = "Custom"

if preset = 2
    presetName$       = "Microtonal Murmur"
    pitch_base_lo_Hz  = 120
    pitch_base_hi_Hz  = 160
    gesture_scale     = 1.8
    interval_scale    = 0.25
    wobble_depth_Hz   = 1.5
elsif preset = 3
    presetName$       = "Leaping Gestures"
    pitch_base_lo_Hz  = 80
    pitch_base_hi_Hz  = 250
    gesture_scale     = 0.9
    interval_scale    = 2.0
    wobble_depth_Hz   = 6.0
elsif preset = 4
    presetName$       = "Rapid Stutter"
    pitch_base_lo_Hz  = 140
    pitch_base_hi_Hz  = 180
    gesture_scale     = 0.3
    interval_scale    = 0.5
    wobble_depth_Hz   = 3.0
elsif preset = 5
    presetName$       = "Wide Arc"
    pitch_base_lo_Hz  = 60
    pitch_base_hi_Hz  = 300
    gesture_scale     = 1.6
    interval_scale    = 1.8
    wobble_depth_Hz   = 8.0
elsif preset = 6
    presetName$       = "Gentle Drift"
    pitch_base_lo_Hz  = 100
    pitch_base_hi_Hz  = 200
    gesture_scale     = 1.4
    interval_scale    = 0.7
    wobble_depth_Hz   = 4.0
endif

# Clamp grammar parameters
if gesture_scale < 0.1
    gesture_scale = 0.1
endif
if gesture_scale > 5.0
    gesture_scale = 5.0
endif
if interval_scale < 0.05
    interval_scale = 0.05
endif
if interval_scale > 5.0
    interval_scale = 5.0
endif
if wobble_depth_Hz < 0.1
    wobble_depth_Hz = 0.1
endif
if wobble_depth_Hz > 50.0
    wobble_depth_Hz = 50.0
endif

# ========================================================================================
# INITIALIZATION
# ========================================================================================

# Fixed Visual Display sizes to align all panels uniformly
image_width = 800
image_height = 300

# Select sound
ids = selected("Sound")
if ids = undefined
    exitScript: "Please select a Sound object first."
endif
name$ = selected$("Sound")
duration = Get total duration
startTime = Get start time
endTime = Get end time

writeInfoLine: "Bimodal Contour Grammar Generator v0.4"
appendInfoLine: "========================================================"
appendInfoLine: "Sound: ", name$
appendInfoLine: "Duration: ", fixed$ (duration, 3), " seconds"
appendInfoLine: "Grammar: S → Phrase + S | Phrase → Onset + Nucleus + Coda"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "  Pitch base: ", fixed$(pitch_base_lo_Hz, 0), " – ", fixed$(pitch_base_hi_Hz, 0), " Hz"
appendInfoLine: "  Gesture scale: ", fixed$(gesture_scale, 2),
    ... "  Interval scale: ", fixed$(interval_scale, 2),
    ... "  Wobble: ±", fixed$(wobble_depth_Hz, 1), " Hz"

# Set random seed
if randomSeed = 0
    # Use current time for randomness
    seedValue = round(endTime * 1000000) mod 1000000
    appendInfoLine: "Random seed: ", seedValue, " (auto-generated)"
else
    # Use user-specified seed
    seedValue = randomSeed
    appendInfoLine: "Random seed: ", seedValue, " (user-specified)"
endif

# Initialize random number generator with seed
randomUniform.seed = seedValue
appendInfoLine: ""

# Create PitchTier for sound processing
Create PitchTier: name$, 0, duration
pt_id = selected("PitchTier")

# Extract intensity for loudness modulation
selectObject: ids
intensityID = To Intensity: 75, 0.01, "yes"

# Setup Picture window
Erase all
Select outer viewport: 0, image_width/100, 0, image_height/100
Font size: 10

# Determine MIDI range
currentMidiMin = 40
currentMidiMax = 100

Axes: startTime, endTime, currentMidiMin - 0.5, currentMidiMax + 0.5

# ========================================================================================
# DRAW GRID
# ========================================================================================

if showGrid
    appendInfoLine: "Drawing grid..."
    
    # Horizontal grid lines
    for midiLine from currentMidiMin to currentMidiMax
        noteClass = midiLine - 12 * floor(midiLine / 12)
        
        if noteClass = 0
            Colour: "{0.65, 0.65, 0.65}"
            Line width: 2
            Draw line: startTime, midiLine, endTime, midiLine
        elif (midiLine mod 12) = 0
            Colour: "{0.75, 0.75, 0.75}"
            Line width: 1.2
            Draw line: startTime, midiLine, endTime, midiLine
        else
            Colour: "{0.92, 0.92, 0.92}"
            Line width: 0.4
            Draw line: startTime, midiLine, endTime, midiLine
        endif
    endfor
   
    # Note labels
    if showNoteLabels
        Font size: 8
        Colour: "{0.5, 0.5, 0.5}"
        
        for midiLine from currentMidiMin to currentMidiMax
            noteClass = midiLine - 12 * floor(midiLine / 12)
            
            if noteClass = 0
                @getMidiNoteName: midiLine
                Text: startTime - duration * 0.02, "right", midiLine, "half", getMidiNoteName.fullName$
            endif
        endfor
        
        Font size: 10
    endif
endif

# ========================================================================================
# GLOBAL VARIABLES (shared across sound and visual)
# ========================================================================================
current_time = 0
current_pitch = 150
prev_time = 0
prev_freq = 150
point_count = 0

# Intensity tracking
current_intensity = baseLoudness

# v0.3: phrase structure tracking
phrase_count = 0
last_gesture_type$ = ""

# ========================================================================================
# MAIN EXECUTION - GENERATE GRAMMAR
# ========================================================================================
appendInfoLine: "Generating contour from grammar..."
@generate_contour: duration

appendInfoLine: "Total points generated: ", point_count

# ========================================================================================
# POST-PROCESSING - SOUND RESYNTHESIS
# ========================================================================================
appendInfoLine: "Resynthesizing audio..."

selectObject: ids
To Manipulation: 0.01, 75, 600
selectObject: pt_id
plusObject: "Manipulation " + name$
Replace pitch tier
selectObject: "Manipulation " + name$
Get resynthesis (overlap-add)
Rename: name$ + "_grammar"
resynthID = selected("Sound")

# Cleanup manipulation
removeObject: "Manipulation " + name$

# ========================================================================================
# LABELS
# ========================================================================================

Colour: "Black"
Line width: 1
Font size: 12

Text top: "yes", "Bimodal Grammar: " + name$ + "  [" + presetName$ + "]  (S → Phrase + S)"
Text bottom: "yes", "Time (s)"
Text left: "yes", "MIDI Note (Hz mapped)"

Font size: 8
Select outer viewport: 0, image_width/100, 0, image_height/100
Text: (image_width/100) * 0.98, "right", currentMidiMax, "top", colorScheme$
if lineStyle = 3
    Text: (image_width/100) * 0.98, "right", currentMidiMax - 2, "top", "Dots: " + fixed$(minDotSize, 1) + "-" + fixed$(maxDotSize, 1)
else
    Text: (image_width/100) * 0.98, "right", currentMidiMax - 2, "top", lineStyle$
endif

# ========================================================================================
# CLEANUP & REPORT
# ========================================================================================

appendInfoLine: ""
appendInfoLine: "========================================================"
appendInfoLine: "✓ Complete!"
appendInfoLine: "  Preset: ", presetName$
appendInfoLine: "  Random seed: ", seedValue
appendInfoLine: "  Grammar points: ", point_count
appendInfoLine: "  MIDI range: ", currentMidiMin, "-", currentMidiMax
appendInfoLine: "  Line style: ", lineStyle$
appendInfoLine: "  Color scheme: ", colorScheme$
appendInfoLine: ""
appendInfoLine: "Objects created:"
appendInfoLine: "  - ", name$, "_grammar (resynthesized sound)"
appendInfoLine: ""
appendInfoLine: "💡 To replay this generation, use seed: ", seedValue

removeObject: pt_id

# ========================================================================================
# EXTENDED VISUALIZATION v0.3
# Three panels drawn below the main contour:
#   1. Phrase structure timeline  (onset / nucleus / coda colour bands)
#   2. Intensity curve            (source audio dB over time)
#   3. Stats bar                  (phrase count, points, MIDI range, seed)
# ========================================================================================

appendInfoLine: "Drawing extended panels..."

imgH = image_height / 100

# == Panel 1: Phrase structure timeline ====================================================
# Label strip
Select outer viewport: 1, 8, imgH + 0.05, imgH + 0.45
Axes: 0, 1, 0, 1
Font size: 7
Colour: "{0.40, 0.40, 0.40}"
Text: 0, "left", 0.5, "half", "Phrase structure  " + string$(phrase_count) + " phrases    orange = onset   teal = nucleus   blue = coda"

# Drawing panel
Select outer viewport: 0, 8, imgH + 0.45, imgH + 1.25
Select inner viewport: 0.6, 7.6, imgH + 0.55, imgH + 1.15
Axes: startTime, endTime, 0, 1

Paint rectangle: "{0.97, 0.97, 0.97}", startTime, endTime, 0, 1

for i from 1 to phrase_count
    if i mod 2 = 0
        Paint rectangle: "{0.93, 0.93, 0.93}", phrase_start_'i', coda_end_'i', 0, 1
    endif

    Paint rectangle: "{0.88, 0.42, 0.18}", phrase_start_'i', onset_end_'i', 0.08, 0.92
    Paint rectangle: "{0.18, 0.60, 0.44}", nuc_start_'i', nuc_end_'i', 0.08, 0.92
    Paint rectangle: "{0.22, 0.42, 0.72}", coda_start_'i', coda_end_'i', 0.08, 0.92

    Colour: "{0.55, 0.55, 0.55}"
    Line width: 0.6
    Draw line: phrase_start_'i', 0, phrase_start_'i', 1

    Font size: 5
    Colour: "White"

    segW = onset_end_'i' - phrase_start_'i'
    if segW > duration * 0.04
        midT = (phrase_start_'i' + onset_end_'i') / 2
        Text: midT, "centre", 0.50, "half", onset_type_'i'$
    endif

    segW = nuc_end_'i' - nuc_start_'i'
    if segW > duration * 0.04
        midT = (nuc_start_'i' + nuc_end_'i') / 2
        Text: midT, "centre", 0.50, "half", nuc_type_'i'$
    endif

    segW = coda_end_'i' - coda_start_'i'
    if segW > duration * 0.03
        midT = (coda_start_'i' + coda_end_'i') / 2
        Text: midT, "centre", 0.50, "half", coda_type_'i'$
    endif
endfor

Colour: "Black"
Line width: 1
Draw inner box
Font size: 7
Select outer viewport: 0, 0.65, imgH + 0.45, imgH + 1.25
Text left: "yes", "Gestures"

# == Panel 2: Output waveform =================================================================

Select outer viewport: 0, 8, imgH + 1.30, imgH + 2.10
Select inner viewport: 0.6, 7.6, imgH + 1.35, imgH + 2.05

selectObject: resynthID
resPeak = Get absolute extremum: 0, 0, "None"
if resPeak < 0.001
    resPeak = 0.001
endif
resAmpMax = resPeak * 1.15

Axes: startTime, endTime, -resAmpMax, resAmpMax
Paint rectangle: "{0.97, 0.97, 0.97}", startTime, endTime, -resAmpMax, resAmpMax
Colour: "{0.80, 0.80, 0.80}"
Draw line: startTime, 0, endTime, 0
selectObject: resynthID
Colour: "{0.22, 0.55, 0.72}"
Draw: 0, 0, -resAmpMax, resAmpMax, "no", "Curve"
Colour: "Black"
Draw inner box
Font size: 7
Text left: "yes", "Output"
Text top: "no", name$ + "_grammar  (PSOLA resynthesis)"
Text bottom: "yes", "Time (s)"

# == Panel 3: Intensity curve ==============================================================

selectObject: intensityID
intMin = Get minimum: 0, 0, "Parabolic"
intMax = Get maximum: 0, 0, "Parabolic"
intLo = intMin - 4
intHi = intMax + 4

# Label strip
Select outer viewport: 1, 8, imgH + 2.15, imgH + 2.50
Axes: 0, 1, 0, 1
Font size: 7
Colour: "{0.40, 0.40, 0.40}"
Text: 0, "left", 0.5, "half", "Source intensity  " + fixed$(intMin, 0) + " – " + fixed$(intMax, 0) + " dB   dashed = baseLoudness (" + fixed$(baseLoudness, 0) + " dB)"

# Drawing panel
Select outer viewport: 0, 8, imgH + 2.50, imgH + 3.30
Select inner viewport: 0.6, 7.6, imgH + 2.60, imgH + 3.20
Axes: startTime, endTime, intLo, intHi

Paint rectangle: "{0.97, 0.97, 0.97}", startTime, endTime, intLo, intHi

Colour: "{0.65, 0.30, 0.30}"
Line width: 0.8
Dashed line
Draw line: startTime, baseLoudness, endTime, baseLoudness
Solid line

selectObject: intensityID
Colour: "{0.28, 0.52, 0.72}"
Line width: 1.8
Draw: startTime, endTime, intLo, intHi, "no"

Colour: "Black"
Line width: 1
Draw inner box
Font size: 7
Select outer viewport: 0, 0.65, imgH + 2.50, imgH + 3.30
Text left: "yes", "Intensity (dB)"
Select outer viewport: 0.6, 7.6, imgH + 3.20, imgH + 3.37
Axes: 0, 1, 0, 1
Font size: 7
Colour: "{0.50, 0.50, 0.50}"
Text: 0.5, "centre", 0.5, "half", "Time (s)"

# == Panel 4: Stats bar ====================================================================

jumpUp_count = 0
glissUp_count = 0
plateau_count = 0
wobble_count = 0
fall_count = 0
deepDrop_count = 0

for i from 1 to phrase_count
    if onset_type_'i'$ = "JumpUp"
        jumpUp_count = jumpUp_count + 1
    else
        glissUp_count = glissUp_count + 1
    endif
    if nuc_type_'i'$ = "Plateau"
        plateau_count = plateau_count + 1
    else
        wobble_count = wobble_count + 1
    endif
    if coda_type_'i'$ = "Fall"
        fall_count = fall_count + 1
    else
        deepDrop_count = deepDrop_count + 1
    endif
endfor

Select outer viewport: 0, 8, imgH + 3.42, imgH + 4.10
Axes: 0, 1, 0, 1
Font size: 6
Colour: "{0.40, 0.40, 0.40}"
Text: 0.5, "centre", 0.78, "half",
    ... "##" + presetName$ + "##   Phrases: " + string$(phrase_count)
    ... + "   Points: " + string$(point_count)
    ... + "   MIDI: " + string$(currentMidiMin) + "–" + string$(currentMidiMax)
    ... + "   Seed: " + string$(seedValue)
Text: 0.5, "centre", 0.42, "half",
    ... "Pitch: " + fixed$(pitch_base_lo_Hz, 0) + "–" + fixed$(pitch_base_hi_Hz, 0) + " Hz"
    ... + "   GestScale: " + fixed$(gesture_scale, 2)
    ... + "   IntScale: " + fixed$(interval_scale, 2)
    ... + "   Wobble: ±" + fixed$(wobble_depth_Hz, 1) + " Hz"
Text: 0.5, "centre", 0.10, "half", "Onsets  JumpUp: " + string$(jumpUp_count) + "  GlissUp: " + string$(glissUp_count) + "     Nuclei  Plateau: " + string$(plateau_count) + "  Wobble: " + string$(wobble_count) + "     Codas  Fall: " + string$(fall_count) + "  DeepDrop: " + string$(deepDrop_count)

Font size: 10
Colour: "Black"
appendInfoLine: "Extended panels complete."
removeObject: intensityID

if playAfterGeneration
    appendInfoLine: ""
    appendInfoLine: "Playing generated sound..."
    selectObject: resynthID
    Play
endif

selectObject: resynthID

appendInfoLine: ""
appendInfoLine: "Done! The grammar-generated sound is now selected."
# ========================================================================================
# BIMODAL PRIMITIVE: Add Point (CORE PROCEDURE)
# ========================================================================================
procedure addPoint: .t, .f
    # Convert Hz to MIDI for visualization
    @hzToMidi: .f
    .midi = hzToMidi.midi
    
    # SOUND MODE: Add to PitchTier
    selectObject: pt_id
    Add point: .t, .f
    
    # Get intensity at this time for color/size modulation
    selectObject: intensityID
    .intensity = Get value at time: .t, "Cubic"
    if .intensity = undefined
        .intensity = baseLoudness
    endif
    
    # Calculate brightness/size from intensity
    @mapToRange: .intensity, baseLoudness - loudnessVariation, baseLoudness + loudnessVariation, 0.3, 1.0
    brightness = mapToRange.result
    
    # VISUAL MODE: Draw on Picture
    if prev_time > 0
        # Choose color scheme
        if colorScheme = 1
            @pitchHeightToRGB: .midi, brightness
            r = pitchHeightToRGB.red
            g = pitchHeightToRGB.green
            b = pitchHeightToRGB.blue
            
        elif colorScheme = 2
            @pitchClassToRGB: .midi, brightness
            r = pitchClassToRGB.red
            g = pitchClassToRGB.green
            b = pitchClassToRGB.blue
            
        elif colorScheme = 3
            @mapToRange: .intensity, baseLoudness - loudnessVariation, baseLoudness + loudnessVariation, 0, 1
            heatValue = mapToRange.result
            
            if heatValue < 0.33
                r = 0
                g = heatValue * 3
                b = 1 - heatValue * 3
            elif heatValue < 0.66
                localVal = (heatValue - 0.33) * 3
                r = localVal
                g = 1
                b = 0
            else
                localVal = (heatValue - 0.66) * 3
                r = 1
                g = 1 - localVal
                b = 0
            endif
            
        elif colorScheme = 4
            @octaveSpiralRGB: .midi, brightness
            r = octaveSpiralRGB.red
            g = octaveSpiralRGB.green
            b = octaveSpiralRGB.blue
        endif
        
        colourString$ = "{" + string$(r) + ", " + string$(g) + ", " + string$(b) + "}"
        Colour: colourString$
        
        # Convert MIDI back for visualization
        prev_midi = prev_freq
        if prev_midi > 0
            @hzToMidi: prev_midi
            prev_midi_note = hzToMidi.midi
        else
            prev_midi_note = .midi
        endif
        
        # Apply line style
        if lineStyle = 1
            Line width: 1.5
            Draw line: prev_time, prev_midi_note, .t, .midi
            
        elif lineStyle = 2
            @mapToRange: .intensity, baseLoudness - loudnessVariation, baseLoudness + loudnessVariation, 0.5, 4.5
            Line width: mapToRange.result
            Draw line: prev_time, prev_midi_note, .t, .midi
            
        elif lineStyle = 3
            @mapToRange: .intensity, baseLoudness - loudnessVariation, baseLoudness + loudnessVariation, minDotSize, maxDotSize
            dotSize = mapToRange.result
            Paint circle: colourString$, .t, .midi, dotSize
        endif
    endif
    
    # Update previous point
    prev_time = .t
    prev_freq = .f
    point_count = point_count + 1
endproc

# ========================================================================================
# GRAMMAR RULES
# ========================================================================================

procedure generate_contour: .targetTime
    while current_time < .targetTime - 0.2
        @phrase
    endwhile
endproc

procedure phrase
    # Determine base pitch from grammar parameters
    @randomUniform: pitch_base_lo_Hz, pitch_base_hi_Hz
    .base = randomUniform.result
    current_pitch = .base
    
    # Vary intensity for this phrase
    @randomUniform: -loudnessVariation, loudnessVariation
    current_intensity = baseLoudness + randomUniform.result
    
    # v0.3: record phrase index and timing boundaries
    phrase_count = phrase_count + 1
    cur_ph = phrase_count
    phrase_start_'cur_ph' = current_time

    @onset
    onset_end_'cur_ph' = current_time
    onset_type_'cur_ph'$ = last_gesture_type$
    nuc_start_'cur_ph' = onset_end_'cur_ph'

    @nucleus
    nuc_end_'cur_ph' = current_time
    nuc_type_'cur_ph'$ = last_gesture_type$
    coda_start_'cur_ph' = nuc_end_'cur_ph'

    @coda
    coda_end_'cur_ph' = current_time
    coda_type_'cur_ph'$ = last_gesture_type$
    
    # Breath pause
    @randomUniform: 0.05 * gesture_scale, 0.1 * gesture_scale
    current_time = current_time + randomUniform.result
endproc

# ========================================================================================
# TERMINALS
# ========================================================================================

procedure onset
    @randomUniform: 0.05 * gesture_scale, 0.15 * gesture_scale
    .dur = randomUniform.result
    @randomInteger: 1, 2
    .choice = randomInteger.result
    
    if .choice = 1
        # JumpUp
        last_gesture_type$ = "JumpUp"
        @addPoint: current_time, current_pitch
        @randomUniform: 10 * interval_scale, 30 * interval_scale
        current_pitch = current_pitch + randomUniform.result
        current_time = current_time + .dur
        @addPoint: current_time, current_pitch
    else
        # GlissandoUp
        last_gesture_type$ = "GlissUp"
        @addPoint: current_time, current_pitch
        current_time = current_time + .dur
        @randomUniform: 20 * interval_scale, 50 * interval_scale
        current_pitch = current_pitch + randomUniform.result
        @addPoint: current_time, current_pitch
    endif
endproc

procedure nucleus
    @randomUniform: 0.2 * gesture_scale, 0.5 * gesture_scale
    .dur = randomUniform.result
    .endTime = current_time + .dur
    @randomInteger: 1, 2
    .choice = randomInteger.result
    
    if .choice = 1
        # Plateau
        last_gesture_type$ = "Plateau"
        @addPoint: current_time, current_pitch
        current_time = .endTime
        @addPoint: current_time, current_pitch
    else
        # Wobble
        last_gesture_type$ = "Wobble"
        while current_time < .endTime
            .step = 0.05 * gesture_scale
            if .step < 0.01
                .step = 0.01
            endif
            @randomUniform: -wobble_depth_Hz, wobble_depth_Hz
            .wobble = randomUniform.result
            @addPoint: current_time, current_pitch + .wobble
            current_time = current_time + .step
        endwhile
    endif
endproc

procedure coda
    @randomUniform: 0.1 * gesture_scale, 0.2 * gesture_scale
    .dur = randomUniform.result
    
    @randomUniform: 0, 1
    if randomUniform.result > 0.5
        # Fall
        last_gesture_type$ = "Fall"
        @randomUniform: 20 * interval_scale, 40 * interval_scale
        .drop = randomUniform.result
    else
        # DeepDrop
        last_gesture_type$ = "DeepDrop"
        @randomUniform: 50 * interval_scale, 80 * interval_scale
        .drop = randomUniform.result
    endif
    
    @addPoint: current_time, current_pitch
    current_time = current_time + .dur
    current_pitch = current_pitch - .drop
    
    # Range clamping
    if current_pitch < 50
        current_pitch = 50
    endif
    
    @addPoint: current_time, current_pitch
endproc

# ========================================================================================
# HELPER FUNCTIONS (from visualization script)
# ========================================================================================

# Seeded random number generator
procedure randomUniform: .min, .max
    # Linear congruential generator for reproducible randomness
    if randomUniform.seed = undefined
        randomUniform.seed = 12345
    endif
    
    # LCG parameters (from Numerical Recipes)
    .a = 1664525
    .c = 1013904223
    .m = 2^32
    
    randomUniform.seed = ((.a * randomUniform.seed + .c) mod .m)
    .random01 = randomUniform.seed / .m
    .result = .min + .random01 * (.max - .min)
endproc

procedure randomInteger: .min, .max
    @randomUniform: .min, .max + 0.999999
    .result = floor(randomUniform.result)
endproc

procedure hzToMidi: .hz
    if .hz > 0
        .midi = 69 + 12 * log2(.hz / 440)
    else
        .midi = undefined
    endif
endproc

procedure mapToRange: .value, .fromMin, .fromMax, .toMin, .toMax
    .value = max(.fromMin, min(.fromMax, .value))
    .result = .toMin + (.value - .fromMin) / (.fromMax - .fromMin) * (.toMax - .toMin)
endproc

procedure getMidiNoteName: .midi
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave = floor(.midi / 12) - 1
    
    if .noteClass = 0
        .noteName$ = "C"
    elif .noteClass = 1
        .noteName$ = "C#"
    elif .noteClass = 2
        .noteName$ = "D"
    elif .noteClass = 3
        .noteName$ = "D#"
    elif .noteClass = 4
        .noteName$ = "E"
    elif .noteClass = 5
        .noteName$ = "F"
    elif .noteClass = 6
        .noteName$ = "F#"
    elif .noteClass = 7
        .noteName$ = "G"
    elif .noteClass = 8
        .noteName$ = "G#"
    elif .noteClass = 9
        .noteName$ = "A"
    elif .noteClass = 10
        .noteName$ = "A#"
    elif .noteClass = 11
        .noteName$ = "B"
    endif
    
    .fullName$ = .noteName$ + string$(.octave)
endproc

procedure pitchClassToRGB: .midi, .brightness
    .noteClass = .midi - 12 * floor(.midi / 12)
    .hue = .noteClass / 12.0
    
    .h = .hue * 360
    .s = 0.8
    .v = .brightness
    
    .c = .v * .s
    .x = .c * (1 - abs(((.h / 60) mod 2) - 1))
    .m = .v - .c
    
    if .h < 60
        .r = .c
        .g = .x
        .b = 0
    elif .h < 120
        .r = .x
        .g = .c
        .b = 0
    elif .h < 180
        .r = 0
        .g = .c
        .b = .x
    elif .h < 240
        .r = 0
        .g = .x
        .b = .c
    elif .h < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif
    
    .red = .r + .m
    .green = .g + .m
    .blue = .b + .m
endproc

procedure pitchHeightToRGB: .midi, .brightness
    @mapToRange: .midi, currentMidiMin, currentMidiMax, 0, 1
    .hue = mapToRange.result
    
    .h = (1 - .hue) * 240
    .s = 0.9
    .v = .brightness
    
    .c = .v * .s
    .x = .c * (1 - abs(((.h / 60) mod 2) - 1))
    .m = .v - .c
    
    if .h < 60
        .r = .c
        .g = .x
        .b = 0
    elif .h < 120
        .r = .x
        .g = .c
        .b = 0
    elif .h < 180
        .r = 0
        .g = .c
        .b = .x
    elif .h < 240
        .r = 0
        .g = .x
        .b = .c
    elif .h < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif
    
    .red = .r + .m
    .green = .g + .m
    .blue = .b + .m
endproc

procedure octaveSpiralRGB: .midi, .brightness
    .noteClass = .midi - 12 * floor(.midi / 12)
    .octave = floor(.midi / 12) - 1
    
    .hue = (.noteClass / 12.0) * 360
    
    .octaveFactor = (.octave - 2) / 6.0
    .octaveFactor = max(0, min(1, .octaveFactor))
    
    .finalBrightness = .brightness * (0.4 + 0.6 * .octaveFactor)
    
    .s = 0.85
    .v = .finalBrightness
    
    .c = .v * .s
    .x = .c * (1 - abs(((.hue / 60) mod 2) - 1))
    .m = .v - .c
    
    if .hue < 60
        .r = .c
        .g = .x
        .b = 0
    elif .hue < 120
        .r = .x
        .g = .c
        .b = 0
    elif .hue < 180
        .r = 0
        .g = .c
        .b = .x
    elif .hue < 240
        .r = 0
        .g = .x
        .b = .c
    elif .hue < 300
        .r = .x
        .g = 0
        .b = .c
    else
        .r = .c
        .g = 0
        .b = .x
    endif
    
    .red = .r + .m
    .green = .g + .m
    .blue = .b + .m
endproc