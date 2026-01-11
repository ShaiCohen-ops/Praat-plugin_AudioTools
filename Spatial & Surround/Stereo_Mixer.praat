# ============================================================
# Praat AudioTools - Add_signals.praat (FIXED)
# Fixed for 8-Channel Support
# ============================================================

form Add Signals (Stereo Mixer)
    comment === PRESET PANNING ===
    optionmenu Preset: 1
        option: "Custom (use gains below)"
        option: "All Center (1.0, 1.0)"
        option: "Stereo Spread (alternate L/R)"
        option: "Left Heavy"
        option: "Right Heavy"
        option: "Fade L to R"
    
    comment === SOUND 1 ===
    real Gain_1_L 1.0
    real Gain_1_R 1.0
    
    comment === SOUND 2 ===
    real Gain_2_L 1.0
    real Gain_2_R 1.0
    
    comment === SOUND 3 ===
    real Gain_3_L 1.0
    real Gain_3_R 1.0
    
    comment === SOUND 4 ===
    real Gain_4_L 1.0
    real Gain_4_R 1.0
    
    comment === SOUND 5 ===
    real Gain_5_L 1.0
    real Gain_5_R 1.0
    
    comment === SOUND 6 ===
    real Gain_6_L 1.0
    real Gain_6_R 1.0
    
    comment === SOUND 7 ===
    real Gain_7_L 1.0
    real Gain_7_R 1.0
    
    comment === SOUND 8 ===
    real Gain_8_L 1.0
    real Gain_8_R 1.0
    
    comment === OUTPUT ===
    boolean Normalize_output 1
    real Target_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === 1. Safe Array Initialization ===
# We explicitly map form variables to arrays to prevent "Unknown Variable" errors
# inside loops later.

gainL# = zero#(8)
gainR# = zero#(8)

gainL#[1] = gain_1_L
gainR#[1] = gain_1_R
gainL#[2] = gain_2_L
gainR#[2] = gain_2_R
gainL#[3] = gain_3_L
gainR#[3] = gain_3_R
gainL#[4] = gain_4_L
gainR#[4] = gain_4_R
gainL#[5] = gain_5_L
gainR#[5] = gain_5_R
gainL#[6] = gain_6_L
gainR#[6] = gain_6_R
gainL#[7] = gain_7_L
gainR#[7] = gain_7_R
gainL#[8] = gain_8_L
gainR#[8] = gain_8_R

# === 2. Apply Presets ===
# This overrides the custom values if a preset is chosen

if preset = 2
    # All Center
    for i from 1 to 8
        gainL#[i] = 1.0
        gainR#[i] = 1.0
    endfor
    presetName$ = "Center"
elsif preset = 3
    # Stereo Spread (Alternate)
    for i from 1 to 8
        if (i mod 2) = 1
            # Odd numbers left
            gainL#[i] = 1.0
            gainR#[i] = 0.3
        else
            # Even numbers right
            gainL#[i] = 0.3
            gainR#[i] = 1.0
        endif
    endfor
    presetName$ = "Spread"
elsif preset = 4
    # Left Heavy
    for i from 1 to 8
        gainL#[i] = 1.0
        gainR#[i] = 0.3
    endfor
    presetName$ = "LeftHeavy"
elsif preset = 5
    # Right Heavy
    for i from 1 to 8
        gainL#[i] = 0.3
        gainR#[i] = 1.0
    endfor
    presetName$ = "RightHeavy"
elsif preset = 6
    # Fade L to R
    for i from 1 to 8
        progress = (i - 1) / 7
        gainL#[i] = 1.0 - progress * 0.7
        gainR#[i] = 0.3 + progress * 0.7
    endfor
    presetName$ = "FadeLR"
else
    presetName$ = "Custom"
endif

# === 3. Validate Input ===
numSounds = numberOfSelected("Sound")
if numSounds = 0
    exitScript: "No sounds selected! Please select 1 to 8 Sound objects."
endif

if numSounds > 8
    exitScript: "Too many sounds selected! This script supports a maximum of 8."
endif

writeInfoLine: "=== Mixing ", numSounds, " Sounds ==="

# === 4. Process Source Sounds ===
# Store IDs and find max duration/sample rate
maxDur = 0
maxSR = 0

for i from 1 to numSounds
    soundID[i] = selected("Sound", i)
    selectObject: soundID[i]
    soundName$[i] = selected$("Sound")
    
    dur = Get total duration
    sr = Get sampling frequency
    
    if dur > maxDur
        maxDur = dur
    endif
    if sr > maxSR
        maxSR = sr
    endif
endfor

# === 5. Prepare Output ===
# Create empty stereo track
Create Sound from formula: "mixed", 2, 0, maxDur, maxSR, "0"
resultID = selected("Sound")

# === 6. The Mixing Loop ===
for i from 1 to numSounds
    # Select original source
    selectObject: soundID[i]
    
    # Check channels
    nCh = Get number of channels
    
    # Create a temporary copy to manipulate
    Copy: "temp_mix_layer"
    tempID = selected("Sound")
    
    # If mono, convert to stereo first so we can pan
    if nCh = 1
        Convert to stereo
        removeObject: tempID
        tempID = selected("Sound")
    endif
    
    # Get gains for this index
    valL = gainL#[i]
    valR = gainR#[i]
    
    # Apply gains using Formula
    # Channel 1 (Left) * valL
    Formula (part): 0, 0, 1, 1, "self * valL"
    # Channel 2 (Right) * valR
    Formula (part): 0, 0, 2, 2, "self * valR"
    
    # Add this layer to the main result
    selectObject: resultID
    Formula: "self + object[tempID]"
    
    # Clean up temp object
    removeObject: tempID
    
    appendInfoLine: "Added: ", soundName$[i], " (L:", fixed$(valL,2), " R:", fixed$(valR,2), ")"
endfor

# === 7. Post Processing ===
selectObject: resultID

if normalize_output
    Scale peak: target_peak
    appendInfoLine: "Normalized to peak: ", target_peak
endif

new_name$ = "Mixed_" + presetName$ + "_" + string$(numSounds) + "ch"
Rename: new_name$

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 10, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Mixer Output: " + new_name$
    
    # --- Stereo Field (Left) ---
    Select outer viewport: 0, 5, 1, 5
    Axes: -1.2, 1.2, 0, numSounds + 1
    Paint rectangle: "{0.9, 0.9, 0.9}", -1.2, 1.2, 0, numSounds + 1
    
    # Center Guide
    Colour: "{0.6, 0.6, 0.6}"
    Dotted line
    Draw line: 0, 0, 0, numSounds + 1
    Solid line
    
    # Draw Dots
    for i from 1 to numSounds
        yPos = numSounds - i + 1
        l = gainL#[i]
        r = gainR#[i]
        
        # Calculate Pan (-1 to 1)
        if l + r > 0
            pan = (r - l) / (l + r)
        else
            pan = 0
        endif
        
        # Color Logic
        if pan < 0
            # Left = Blueish
            col$ = "{0.2, 0.2, 0.8}"
        else
            # Right = Orangish
            col$ = "{0.8, 0.4, 0.0}"
        endif
        
        Paint circle (mm): col$, pan, yPos, 3
        
        Colour: "Black"
        Font size: 10
        Text: -1.1, "left", yPos, "half", string$(i)
    endfor
    
    Font size: 10
    Text: -1, "centre", 0.2, "half", "L"
    Text: 1, "centre", 0.2, "half", "R"
    Draw inner box
    
    # --- Waveform (Right) ---
    Select outer viewport: 5, 10, 1, 5
    selectObject: resultID
    Draw: 0, 0, 0, 0, "no", "Curve"
    Draw inner box
endif

# === Finish ===
selectObject: resultID
if play_result
    Play
endif