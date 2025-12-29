# ============================================================
# Praat AudioTools - Poisson Point Process Synthesis (Stereo Enhanced)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Stereo Enhancement
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound synthesis or generative algorithm script with stereo processing
#   and preset system. Creates independent Poisson processes for left and
#   right channels with customizable parameters.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Poisson Point Process Synthesis - Stereo
    comment === Preset Selection ===
    optionmenu Preset: 1
        option Custom
        option Sparse Ambience
        option Dense Texture
        option Rhythmic Pulse
        option Wide Stereo Field
        option Narrow Center
        option Ascending Shimmer
        option Granular Cloud
        option Metallic Rain
    
    comment === Global Parameters ===
    real Duration 10.0
    real Sampling_frequency 44100
    
    comment === Left Channel Parameters ===
    real Left_event_rate 8.0
    real Left_base_frequency 120
    real Left_frequency_spread 200
    real Left_grain_duration 0.1
    real Left_grain_duration_spread 0.05
    real Left_amplitude 0.6
    
    comment === Right Channel Parameters ===
    real Right_event_rate 8.0
    real Right_base_frequency 120
    real Right_frequency_spread 200
    real Right_grain_duration 0.1
    real Right_grain_duration_spread 0.05
    real Right_amplitude 0.6
    
    comment === Stereo Settings ===
    real Stereo_width 1.0
endform

# Apply preset values if not Custom
if preset$ = "Sparse Ambience"
    left_event_rate = 3.0
    right_event_rate = 2.5
    left_base_frequency = 80
    right_base_frequency = 100
    left_frequency_spread = 150
    right_frequency_spread = 180
    left_grain_duration = 0.15
    right_grain_duration = 0.18
    left_grain_duration_spread = 0.08
    right_grain_duration_spread = 0.09
    left_amplitude = 0.5
    right_amplitude = 0.5
    stereo_width = 1.0
    
elsif preset$ = "Dense Texture"
    left_event_rate = 25.0
    right_event_rate = 22.0
    left_base_frequency = 200
    right_base_frequency = 220
    left_frequency_spread = 400
    right_frequency_spread = 380
    left_grain_duration = 0.05
    right_grain_duration = 0.06
    left_grain_duration_spread = 0.02
    right_grain_duration_spread = 0.025
    left_amplitude = 0.4
    right_amplitude = 0.4
    stereo_width = 0.8
    
elsif preset$ = "Rhythmic Pulse"
    left_event_rate = 12.0
    right_event_rate = 12.0
    left_base_frequency = 100
    right_base_frequency = 105
    left_frequency_spread = 50
    right_frequency_spread = 55
    left_grain_duration = 0.08
    right_grain_duration = 0.08
    left_grain_duration_spread = 0.01
    right_grain_duration_spread = 0.01
    left_amplitude = 0.7
    right_amplitude = 0.7
    stereo_width = 0.3
    
elsif preset$ = "Wide Stereo Field"
    left_event_rate = 10.0
    right_event_rate = 10.0
    left_base_frequency = 150
    right_base_frequency = 450
    left_frequency_spread = 100
    right_frequency_spread = 300
    left_grain_duration = 0.12
    right_grain_duration = 0.09
    left_grain_duration_spread = 0.05
    right_grain_duration_spread = 0.04
    left_amplitude = 0.6
    right_amplitude = 0.6
    stereo_width = 1.0
    
elsif preset$ = "Narrow Center"
    left_event_rate = 15.0
    right_event_rate = 15.0
    left_base_frequency = 200
    right_base_frequency = 205
    left_frequency_spread = 80
    right_frequency_spread = 85
    left_grain_duration = 0.07
    right_grain_duration = 0.07
    left_grain_duration_spread = 0.02
    right_grain_duration_spread = 0.02
    left_amplitude = 0.65
    right_amplitude = 0.65
    stereo_width = 0.2
    
elsif preset$ = "Ascending Shimmer"
    left_event_rate = 18.0
    right_event_rate = 16.0
    left_base_frequency = 300
    right_base_frequency = 600
    left_frequency_spread = 500
    right_frequency_spread = 800
    left_grain_duration = 0.04
    right_grain_duration = 0.03
    left_grain_duration_spread = 0.01
    right_grain_duration_spread = 0.01
    left_amplitude = 0.45
    right_amplitude = 0.45
    stereo_width = 0.9
    
elsif preset$ = "Granular Cloud"
    left_event_rate = 35.0
    right_event_rate = 32.0
    left_base_frequency = 400
    right_base_frequency = 380
    left_frequency_spread = 600
    right_frequency_spread = 620
    left_grain_duration = 0.03
    right_grain_duration = 0.035
    left_grain_duration_spread = 0.015
    right_grain_duration_spread = 0.018
    left_amplitude = 0.35
    right_amplitude = 0.35
    stereo_width = 0.85
    
elsif preset$ = "Metallic Rain"
    left_event_rate = 20.0
    right_event_rate = 18.0
    left_base_frequency = 800
    right_base_frequency = 1200
    left_frequency_spread = 1000
    right_frequency_spread = 1500
    left_grain_duration = 0.02
    right_grain_duration = 0.025
    left_grain_duration_spread = 0.008
    right_grain_duration_spread = 0.01
    left_amplitude = 0.4
    right_amplitude = 0.4
    stereo_width = 1.0
endif

echo Building Stereo Poisson Point Process Synthesis...
echo Preset: 'preset$'
echo Duration: 'duration' seconds

# ============================================================
# LEFT CHANNEL PROCESSING
# ============================================================

echo Processing LEFT channel...

Create Poisson process: "poisson_left", 0, duration, left_event_rate
Rename: "poisson_points_left"

numberOfPoints_left = Get number of points
echo Left channel: Found 'numberOfPoints_left' Poisson points

Create Sound from formula: "temp_left", 1, 0, duration, sampling_frequency, "0"

formula_left$ = "0"

for point to numberOfPoints_left
    selectObject: "PointProcess poisson_points_left"
    pointTime = Get time from index: point
    
    grain_freq = left_base_frequency + left_frequency_spread * (randomUniform(0,1) - 0.5)
    grain_dur = left_grain_duration + left_grain_duration_spread * (randomUniform(0,1) - 0.5)
    grain_dur = max(0.01, grain_dur)
    grain_amp = left_amplitude * (0.7 + 0.3 * randomUniform(0,1))
    
    if pointTime + grain_dur > duration
        grain_dur = duration - pointTime
    endif
    
    if grain_dur > 0.005
        grain_formula$ = "if x >= " + string$(pointTime) + " and x < " + string$(pointTime + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
        grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(pointTime) + ")/" + string$(grain_dur) + "))/2"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula_left$ = "0"
            formula_left$ = grain_formula$
        else
            formula_left$ = formula_left$ + " + " + grain_formula$
        endif
    endif
    
    if point mod 100 = 0
        echo Left: Processed 'point'/'numberOfPoints_left' points...
    endif
endfor

selectObject: "Sound temp_left"
Remove

Create Sound from formula: "left_channel", 1, 0, duration, sampling_frequency, formula_left$
Scale peak: 0.85

selectObject: "PointProcess poisson_points_left"
Remove

# ============================================================
# RIGHT CHANNEL PROCESSING
# ============================================================

echo Processing RIGHT channel...

Create Poisson process: "poisson_right", 0, duration, right_event_rate
Rename: "poisson_points_right"

numberOfPoints_right = Get number of points
echo Right channel: Found 'numberOfPoints_right' Poisson points

Create Sound from formula: "temp_right", 1, 0, duration, sampling_frequency, "0"

formula_right$ = "0"

for point to numberOfPoints_right
    selectObject: "PointProcess poisson_points_right"
    pointTime = Get time from index: point
    
    grain_freq = right_base_frequency + right_frequency_spread * (randomUniform(0,1) - 0.5)
    grain_dur = right_grain_duration + right_grain_duration_spread * (randomUniform(0,1) - 0.5)
    grain_dur = max(0.01, grain_dur)
    grain_amp = right_amplitude * (0.7 + 0.3 * randomUniform(0,1))
    
    if pointTime + grain_dur > duration
        grain_dur = duration - pointTime
    endif
    
    if grain_dur > 0.005
        grain_formula$ = "if x >= " + string$(pointTime) + " and x < " + string$(pointTime + grain_dur)
        grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
        grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
        grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(pointTime) + ")/" + string$(grain_dur) + "))/2"
        grain_formula$ = grain_formula$ + " else 0 fi"
        
        if formula_right$ = "0"
            formula_right$ = grain_formula$
        else
            formula_right$ = formula_right$ + " + " + grain_formula$
        endif
    endif
    
    if point mod 100 = 0
        echo Right: Processed 'point'/'numberOfPoints_right' points...
    endif
endfor

selectObject: "Sound temp_right"
Remove

Create Sound from formula: "right_channel", 1, 0, duration, sampling_frequency, formula_right$
Scale peak: 0.85

selectObject: "PointProcess poisson_points_right"
Remove

# ============================================================
# COMBINE INTO STEREO
# ============================================================

echo Combining channels into stereo...

selectObject: "Sound left_channel"
plusObject: "Sound right_channel"
Combine to stereo

Rename: "poisson_synthesis_stereo"

# Apply stereo width control
if stereo_width < 1.0
    selectObject: "Sound poisson_synthesis_stereo"
    Formula: "if col = 1 then self + " + string$(1 - stereo_width) + " * self[2] else self + " + string$(1 - stereo_width) + " * self[1] fi"
endif

selectObject: "Sound poisson_synthesis_stereo"
Scale peak: 0.9
Play

# Clean up individual channels
selectObject: "Sound left_channel"
Remove
selectObject: "Sound right_channel"
Remove

selectObject: "Sound poisson_synthesis_stereo"

echo ============================================================
echo Stereo Poisson Synthesis complete!
echo Preset: 'preset$'
echo Left channel events: 'numberOfPoints_left'
echo Right channel events: 'numberOfPoints_right'
echo Total events: 'numberOfPoints_left + numberOfPoints_right'
echo Stereo width: 'stereo_width'
echo ============================================================
