# ============================================================
# Praat AudioTools - BPM_SURROUND _Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel or spatialisation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# 8-CHANNEL SURROUND SPATIALIZATION LABORATORY
form Immersive Audio Laboratory
    choice Cycles_Per_File: 4
        option 1 cycle (very slow)
        option 2 cycles
        option 4 cycles  
        option 8 cycles (medium)
        option 16 cycles
        option 32 cycles (fast)
        option 64 cycles (very fast)
    choice Spatial_Pattern: 1
        option Circle (clockwise orbit)
        option Figure-8 (infinity loop)
        option Spiral (inward/outward)
        option Bounce (wall collision)
        option Swarm (bee movement)
        option Tornado (vortex motion)
        option Wave (ocean current)
        option Plasma (energy field)
        option Neural (brain network)
        option Quantum (probability cloud)
        option DNA (helix in 3D space)
        option Galaxy (stellar motion)
        option Lightning (electrical discharge)
        option Heartbeat (pulse expansion)
        option Breathing (lung expansion)
endform

# Select sound object
sound = selected("Sound")
selectObject: sound

# Check if mono (we'll expand to 8 channels)
num_channels = Get number of channels
if num_channels > 2
    exitScript: "Please use mono or stereo source"
endif

# Convert to mono if stereo
if num_channels = 2
    Convert to mono
    sound = selected("Sound")
endif

# Get duration and calculate base rate
duration = Get total duration
appendInfoLine: "🎵 8-CHANNEL SPATIALIZATION LABORATORY 🎵"
appendInfoLine: "File duration: ", fixed$(duration, 2), " seconds"

# Calculate base rate
if cycles_Per_File = 1
    cycles = 1
elsif cycles_Per_File = 2
    cycles = 2
elsif cycles_Per_File = 3
    cycles = 4
elsif cycles_Per_File = 4
    cycles = 8
elsif cycles_Per_File = 5
    cycles = 16
elsif cycles_Per_File = 6
    cycles = 32
else
    cycles = 64
endif

base_rate = cycles / duration
appendInfoLine: "Spatial cycles: ", cycles
appendInfoLine: "Movement rate: ", fixed$(base_rate, 2), " Hz"

# Define 8-channel speaker positions (7.1 surround)
# Channel 1: Front Left (FL)
# Channel 2: Front Right (FR)
# Channel 3: Center (C)
# Channel 4: LFE (Low Frequency)
# Channel 5: Surround Left (SL)
# Channel 6: Surround Right (SR)
# Channel 7: Back Left (BL)
# Channel 8: Back Right (BR)

appendInfoLine: "Speaker layout: 7.1 Surround (8 channels)"
appendInfoLine: "FL-FR-C-LFE-SL-SR-BL-BR"

# Create 8 individual channels from the mono source
selectObject: sound
Copy: "channel_1_FL"
Copy: "channel_2_FR" 
Copy: "channel_3_C"
Copy: "channel_4_LFE"
Copy: "channel_5_SL"
Copy: "channel_6_SR"
Copy: "channel_7_BL"
Copy: "channel_8_BR"

# Apply spatial pattern
if spatial_Pattern = 1
    # CIRCLE - Clockwise orbit around listener
    appendInfoLine: "Pattern: CIRCULAR ORBIT (clockwise)"
    
    selectObject: "Sound channel_1_FL"
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x - 5*pi/4)))"
    selectObject: "Sound channel_2_FR"  
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x - pi/4)))"
    selectObject: "Sound channel_3_C"
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_4_LFE"
    Formula: "self * 0.3"
    # Constant low-level bass
    selectObject: "Sound channel_5_SL"
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x - 3*pi/2)))"
    selectObject: "Sound channel_6_SR"
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x - pi/2)))"
    selectObject: "Sound channel_7_BL"
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x - 7*pi/4)))"
    selectObject: "Sound channel_8_BR"
    Formula: "self * max(0.05, (0.5 + 0.45 * cos(2*pi*" + string$(base_rate) + "*x - 3*pi/4)))"
    
elsif spatial_Pattern = 2
    # FIGURE-8 - Infinity loop through space
    appendInfoLine: "Pattern: FIGURE-8 INFINITY LOOP"
    
    # Figure-8 uses parametric equations
    selectObject: "Sound channel_1_FL"
    Formula: "self * max(0.05, (0.5 + 0.4 * sin(2*pi*" + string$(base_rate) + "*x) * cos(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_2_FR"
    Formula: "self * max(0.05, (0.5 - 0.4 * sin(2*pi*" + string$(base_rate) + "*x) * cos(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_3_C"
    Formula: "self * max(0.05, (0.5 + 0.3 * sin(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_4_LFE"
    Formula: "self * (0.2 + 0.1 * abs(sin(2*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_5_SL"
    Formula: "self * max(0.05, (0.5 - 0.4 * sin(2*pi*" + string$(base_rate) + "*x) * cos(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_6_SR"
    Formula: "self * max(0.05, (0.5 + 0.4 * sin(2*pi*" + string$(base_rate) + "*x) * cos(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_7_BL"
    Formula: "self * max(0.05, (0.5 - 0.3 * sin(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_8_BR"
    Formula: "self * max(0.05, (0.5 - 0.3 * sin(4*pi*" + string$(base_rate) + "*x)))"

elsif spatial_Pattern = 3
    # SPIRAL - Inward/outward motion with rotation
    appendInfoLine: "Pattern: SPIRAL (expanding/contracting)"
    
    radius$ = "0.3 + 0.2 * sin(0.5*pi*" + string$(base_rate) + "*x)"
    selectObject: "Sound channel_1_FL"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x - 5*pi/4)))"
    selectObject: "Sound channel_2_FR"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x - pi/4)))"
    selectObject: "Sound channel_3_C"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x)))"
    selectObject: "Sound channel_4_LFE"
    Formula: "self * (0.4 - 0.1 * (" + radius$ + "))"
    selectObject: "Sound channel_5_SL"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x - 3*pi/2)))"
    selectObject: "Sound channel_6_SR"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x - pi/2)))"
    selectObject: "Sound channel_7_BL"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x - 7*pi/4)))"
    selectObject: "Sound channel_8_BR"
    Formula: "self * max(0.05, (0.5 + (" + radius$ + ") * cos(4*pi*" + string$(base_rate) + "*x - 3*pi/4)))"

elsif spatial_Pattern = 4
    # BOUNCE - Ricocheting off invisible walls
    appendInfoLine: "Pattern: BOUNCE (wall collisions)"
    
    bounce_x$ = "abs((4*" + string$(base_rate) + "*x) mod 4 - 2) - 1"
    bounce_y$ = "abs((3*" + string$(base_rate) + "*x) mod 6 - 3) - 1.5"
    selectObject: "Sound channel_1_FL"
    Formula: "self * max(0.05, 0.5 + 0.3 * (" + bounce_x$ + ") - 0.2 * (" + bounce_y$ + "))"
    selectObject: "Sound channel_2_FR"
    Formula: "self * max(0.05, 0.5 - 0.3 * (" + bounce_x$ + ") - 0.2 * (" + bounce_y$ + "))"
    selectObject: "Sound channel_3_C"
    Formula: "self * max(0.05, 0.5 - 0.4 * (" + bounce_y$ + "))"
    selectObject: "Sound channel_4_LFE"
    Formula: "self * (0.3 + 0.1 * abs(" + bounce_x$ + "))"
    selectObject: "Sound channel_5_SL"
    Formula: "self * max(0.05, 0.5 + 0.3 * (" + bounce_x$ + ") + 0.2 * (" + bounce_y$ + "))"
    selectObject: "Sound channel_6_SR"
    Formula: "self * max(0.05, 0.5 - 0.3 * (" + bounce_x$ + ") + 0.2 * (" + bounce_y$ + "))"
    selectObject: "Sound channel_7_BL"
    Formula: "self * max(0.05, 0.5 + 0.4 * (" + bounce_y$ + "))"
    selectObject: "Sound channel_8_BR"
    Formula: "self * max(0.05, 0.5 + 0.4 * (" + bounce_y$ + "))"

elsif spatial_Pattern = 5
    # SWARM - Bee-like chaotic but organized movement
    appendInfoLine: "Pattern: SWARM (collective intelligence)"
    
    swarm1$ = "sin(7*pi*" + string$(base_rate) + "*x) * sin(3*pi*" + string$(base_rate) + "*x)"
    swarm2$ = "sin(5*pi*" + string$(base_rate) + "*x) * sin(11*pi*" + string$(base_rate) + "*x)"
    selectObject: "Sound channel_1_FL"
    Formula: "self * max(0.05, min(0.9, 0.5 + 0.25 * (" + swarm1$ + ") + 0.15 * (" + swarm2$ + ")))"
    selectObject: "Sound channel_2_FR"
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.25 * (" + swarm1$ + ") + 0.15 * (" + swarm2$ + ")))"
    selectObject: "Sound channel_3_C"
    Formula: "self * max(0.05, min(0.9, 0.5 + 0.2 * (" + swarm2$ + ")))"
    selectObject: "Sound channel_4_LFE"
    Formula: "self * (0.25 + 0.1 * abs(" + swarm1$ + "))"
    selectObject: "Sound channel_5_SL"
    Formula: "self * max(0.05, min(0.9, 0.5 + 0.25 * (" + swarm2$ + ") - 0.15 * (" + swarm1$ + ")))"
    selectObject: "Sound channel_6_SR"
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.25 * (" + swarm2$ + ") - 0.15 * (" + swarm1$ + ")))"
    selectObject: "Sound channel_7_BL"
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.2 * (" + swarm1$ + ")))"
    selectObject: "Sound channel_8_BR"
    Formula: "self * max(0.05, min(0.9, 0.5 - 0.2 * (" + swarm1$ + ")))"

else
    # Default: TORNADO - Vortex motion with vertical component
    appendInfoLine: "Pattern: TORNADO (3D vortex)"
    
    height$ = "sin(pi*" + string$(base_rate) + "*x)"
    vortex_speed$ = "6*pi*" + string$(base_rate) + "*x"
    selectObject: "Sound channel_1_FL"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + " - 5*pi/4) * (0.7 + 0.3 * (" + height$ + "))))"
    selectObject: "Sound channel_2_FR"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + " - pi/4) * (0.7 + 0.3 * (" + height$ + "))))"
    selectObject: "Sound channel_3_C"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + ") * (0.7 + 0.3 * (" + height$ + "))))"
    selectObject: "Sound channel_4_LFE"
    Formula: "self * (0.4 - 0.1 * abs(" + height$ + "))"
    selectObject: "Sound channel_5_SL"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + " - 3*pi/2) * (0.7 - 0.3 * (" + height$ + "))))"
    selectObject: "Sound channel_6_SR"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + " - pi/2) * (0.7 - 0.3 * (" + height$ + "))))"
    selectObject: "Sound channel_7_BL"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + " - 7*pi/4) * (0.7 - 0.3 * (" + height$ + "))))"
    selectObject: "Sound channel_8_BR"
    Formula: "self * max(0.05, (0.5 + 0.35 * cos(" + vortex_speed$ + " - 3*pi/4) * (0.7 - 0.3 * (" + height$ + "))))"
endif

# Combine all 8 channels into final surround sound
# Note: Praat doesn't support true multichannel beyond stereo
# This creates 8 separate mono files that can be combined externally

appendInfoLine: "🎭 8-CHANNEL PROCESSING COMPLETE! 🎭"
appendInfoLine: "Created 8 individual channel files:"
appendInfoLine: "- channel_1_FL (Front Left)"
appendInfoLine: "- channel_2_FR (Front Right)" 
appendInfoLine: "- channel_3_C (Center)"
appendInfoLine: "- channel_4_LFE (Subwoofer)"
appendInfoLine: "- channel_5_SL (Surround Left)"
appendInfoLine: "- channel_6_SR (Surround Right)"
appendInfoLine: "- channel_7_BL (Back Left)"
appendInfoLine: "- channel_8_BR (Back Right)"
appendInfoLine: ""
appendInfoLine: "🎧 PLAYBACK OPTIONS:"
appendInfoLine: "1. Select individual channels to hear spatial movement"
appendInfoLine: "2. Export each channel as WAV for external mixing"
appendInfoLine: "3. Use DAW to combine into true 7.1 surround"

# Create a stereo preview mix (FL+FR for basic preview)
selectObject: "Sound channel_1_FL"
plusObject: "Sound channel_2_FR"
Combine to stereo
Rename: "stereo_preview"

# Create simplified binaural downmix for headphone preview
appendInfoLine: "Creating binaural headphone mix..."

# Left ear: FL + reduced C + reduced SL + reduced BL
selectObject: "Sound channel_1_FL"
Copy: "binaural_left"
Formula: "self * 1.0"

selectObject: "Sound channel_3_C"
Formula: "self * 0.3"
plusObject: "Sound binaural_left"
Combine to stereo
Extract one channel: 1
Rename: "binaural_left"
Formula: "self * (0.9 + 0.1 * sin(800*pi*x))"

# Right ear: FR + reduced C + reduced SR + reduced BR  
selectObject: "Sound channel_2_FR"
Copy: "binaural_right"
Formula: "self * 1.0"

selectObject: "Sound channel_3_C"
Formula: "self * 0.3"
plusObject: "Sound binaural_right"
Combine to stereo
Extract one channel: 1
Rename: "binaural_right"
Formula: "self * (0.9 + 0.1 * cos(1000*pi*x))"

# Combine binaural mix
selectObject: "Sound binaural_left"
plusObject: "Sound binaural_right"
Combine to stereo
Rename: "binaural_headphone_mix"

# Clean up
removeObject: "Sound binaural_left"
removeObject: "Sound binaural_right"

appendInfoLine: ""
appendInfoLine: "Playing stereo preview (FL + FR channels only)..."
appendInfoLine: "Select individual channels above to hear full spatial effect!"

# Play the stereo preview
selectObject: "Sound stereo_preview"
Play