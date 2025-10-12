# ============================================================
# Praat AudioTools - Time Polyphony - 8 Channels.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Time Polyphony - 8 Channels
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================
# Time Polyphony - 8 Channels
# Creates 8 copies with different time-stretching and combines to 8-channel output
form Phase Vocoder Polyphony 8 Channels
    optionmenu Preset: 1
        option Classic Polyphony
        option Slow Motion
        option Fast Chaos
        option Rhythmic Pulse
        option Subtle Variation
        option Extreme Stretch
        option Glitch Matrix
    real Time_scale_1 1.0
    real Time_scale_2 1.15
    real Time_scale_3 0.85
    real Time_scale_4 1.3
    real Time_scale_5 0.7
    real Time_scale_6 1.1
    real Time_scale_7 0.9
    real Time_scale_8 1.2
    boolean Play_result 1
    comment Time_scale: 1.0 = normal, > 1.0 = slower, < 1.0 = faster
endform

# Apply preset values based on selection
if preset$ = "Classic Polyphony"
    time_scale_1 = 1.0
    time_scale_2 = 1.15
    time_scale_3 = 0.85
    time_scale_4 = 1.3
    time_scale_5 = 0.7
    time_scale_6 = 1.1
    time_scale_7 = 0.9
    time_scale_8 = 1.2
elsif preset$ = "Slow Motion"
    time_scale_1 = 1.5
    time_scale_2 = 1.7
    time_scale_3 = 1.3
    time_scale_4 = 1.6
    time_scale_5 = 1.4
    time_scale_6 = 1.8
    time_scale_7 = 1.2
    time_scale_8 = 1.9
elsif preset$ = "Fast Chaos"
    time_scale_1 = 0.5
    time_scale_2 = 0.6
    time_scale_3 = 0.4
    time_scale_4 = 0.7
    time_scale_5 = 0.3
    time_scale_6 = 0.8
    time_scale_7 = 0.2
    time_scale_8 = 0.9
elsif preset$ = "Rhythmic Pulse"
    time_scale_1 = 1.0
    time_scale_2 = 0.5
    time_scale_3 = 1.0
    time_scale_4 = 0.5
    time_scale_5 = 1.0
    time_scale_6 = 0.5
    time_scale_7 = 1.0
    time_scale_8 = 0.5
elsif preset$ = "Subtle Variation"
    time_scale_1 = 1.0
    time_scale_2 = 1.05
    time_scale_3 = 0.98
    time_scale_4 = 1.02
    time_scale_5 = 0.95
    time_scale_6 = 1.03
    time_scale_7 = 0.97
    time_scale_8 = 1.01
elsif preset$ = "Extreme Stretch"
    time_scale_1 = 3.0
    time_scale_2 = 2.5
    time_scale_3 = 3.5
    time_scale_4 = 2.0
    time_scale_5 = 4.0
    time_scale_6 = 2.2
    time_scale_7 = 3.8
    time_scale_8 = 2.7
elsif preset$ = "Glitch Matrix"
    time_scale_1 = 0.1
    time_scale_2 = 0.8
    time_scale_3 = 0.3
    time_scale_4 = 1.5
    time_scale_5 = 0.2
    time_scale_6 = 1.2
    time_scale_7 = 0.4
    time_scale_8 = 2.0
endif

# Check if a sound object is selected
if numberOfSelected("Sound") = 0
    exit Please select a Sound object first
endif

# Get the selected sound
originalSound = selected("Sound")
sound_name$ = selected$("Sound")

# Get original duration and sampling frequency
selectObject: originalSound
duration = Get total duration
sampling_frequency = Get sampling frequency

# Create first copy with time_scale_1
selectObject: originalSound
manipulation1 = To Manipulation: 0.01, 75, 600
durationTier1 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_1
Add point: duration, time_scale_1
selectObject: manipulation1
plusObject: durationTier1
Replace duration tier
selectObject: manipulation1
voice1 = Get resynthesis (overlap-add)
removeObject: durationTier1, manipulation1
selectObject: voice1
Override sampling frequency: sampling_frequency
dur1 = Get total duration
silent1 = Create Sound from formula: "silence", 1, 0, dur1, sampling_frequency, "0"
selectObject: voice1
plusObject: silent1
stereo1 = Combine to stereo
selectObject: stereo1
mono1 = Convert to mono
removeObject: voice1, silent1, stereo1

# Create second copy with time_scale_2
selectObject: originalSound
manipulation2 = To Manipulation: 0.01, 75, 600
durationTier2 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_2
Add point: duration, time_scale_2
selectObject: manipulation2
plusObject: durationTier2
Replace duration tier
selectObject: manipulation2
voice2 = Get resynthesis (overlap-add)
removeObject: durationTier2, manipulation2
selectObject: voice2
Override sampling frequency: sampling_frequency
dur2 = Get total duration
silent2 = Create Sound from formula: "silence", 1, 0, dur2, sampling_frequency, "0"
selectObject: silent2
plusObject: voice2
stereo2 = Combine to stereo
selectObject: stereo2
mono2 = Convert to mono
removeObject: voice2, silent2, stereo2

# Create third copy with time_scale_3
selectObject: originalSound
manipulation3 = To Manipulation: 0.01, 75, 600
durationTier3 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_3
Add point: duration, time_scale_3
selectObject: manipulation3
plusObject: durationTier3
Replace duration tier
selectObject: manipulation3
voice3 = Get resynthesis (overlap-add)
removeObject: durationTier3, manipulation3
selectObject: voice3
Override sampling frequency: sampling_frequency
dur3 = Get total duration
silent3 = Create Sound from formula: "silence", 1, 0, dur3, sampling_frequency, "0"
selectObject: voice3
plusObject: silent3
stereo3 = Combine to stereo
selectObject: stereo3
mono3 = Convert to mono
removeObject: voice3, silent3, stereo3

# Create fourth copy with time_scale_4
selectObject: originalSound
manipulation4 = To Manipulation: 0.01, 75, 600
durationTier4 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_4
Add point: duration, time_scale_4
selectObject: manipulation4
plusObject: durationTier4
Replace duration tier
selectObject: manipulation4
voice4 = Get resynthesis (overlap-add)
removeObject: durationTier4, manipulation4
selectObject: voice4
Override sampling frequency: sampling_frequency
dur4 = Get total duration
silent4 = Create Sound from formula: "silence", 1, 0, dur4, sampling_frequency, "0"
selectObject: silent4
plusObject: voice4
stereo4 = Combine to stereo
selectObject: stereo4
mono4 = Convert to mono
removeObject: voice4, silent4, stereo4

# Create fifth copy with time_scale_5
selectObject: originalSound
manipulation5 = To Manipulation: 0.01, 75, 600
durationTier5 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_5
Add point: duration, time_scale_5
selectObject: manipulation5
plusObject: durationTier5
Replace duration tier
selectObject: manipulation5
voice5 = Get resynthesis (overlap-add)
removeObject: durationTier5, manipulation5
selectObject: voice5
Override sampling frequency: sampling_frequency
dur5 = Get total duration
silent5 = Create Sound from formula: "silence", 1, 0, dur5, sampling_frequency, "0"
selectObject: voice5
plusObject: silent5
stereo5 = Combine to stereo
selectObject: stereo5
mono5 = Convert to mono
removeObject: voice5, silent5, stereo5

# Create sixth copy with time_scale_6
selectObject: originalSound
manipulation6 = To Manipulation: 0.01, 75, 600
durationTier6 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_6
Add point: duration, time_scale_6
selectObject: manipulation6
plusObject: durationTier6
Replace duration tier
selectObject: manipulation6
voice6 = Get resynthesis (overlap-add)
removeObject: durationTier6, manipulation6
selectObject: voice6
Override sampling frequency: sampling_frequency
dur6 = Get total duration
silent6 = Create Sound from formula: "silence", 1, 0, dur6, sampling_frequency, "0"
selectObject: voice6
plusObject: silent6
stereo6 = Combine to stereo
selectObject: stereo6
mono6 = Convert to mono
removeObject: voice6, silent6, stereo6

# Create seventh copy with time_scale_7
selectObject: originalSound
manipulation7 = To Manipulation: 0.01, 75, 600
durationTier7 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_7
Add point: duration, time_scale_7
selectObject: manipulation7
plusObject: durationTier7
Replace duration tier
selectObject: manipulation7
voice7 = Get resynthesis (overlap-add)
removeObject: durationTier7, manipulation7
selectObject: voice7
Override sampling frequency: sampling_frequency
dur7 = Get total duration
silent7 = Create Sound from formula: "silence", 1, 0, dur7, sampling_frequency, "0"
selectObject: voice7
plusObject: silent7
stereo7 = Combine to stereo
selectObject: stereo7
mono7 = Convert to mono
removeObject: voice7, silent7, stereo7

# Create eighth copy with time_scale_8
selectObject: originalSound
manipulation8 = To Manipulation: 0.01, 75, 600
durationTier8 = Create DurationTier: "duration", 0, duration
Add point: 0, time_scale_8
Add point: duration, time_scale_8
selectObject: manipulation8
plusObject: durationTier8
Replace duration tier
selectObject: manipulation8
voice8 = Get resynthesis (overlap-add)
removeObject: durationTier8, manipulation8
selectObject: voice8
Override sampling frequency: sampling_frequency
dur8 = Get total duration
silent8 = Create Sound from formula: "silence", 1, 0, dur8, sampling_frequency, "0"
selectObject: voice8
plusObject: silent8
stereo8 = Combine to stereo
selectObject: stereo8
mono8 = Convert to mono
removeObject: voice8, silent8, stereo8

# Combine all 8 mono sounds to create 8-channel polyphony
selectObject: mono1
plusObject: mono2
combined12 = Combine to stereo
selectObject: combined12
plusObject: mono3
combined123 = Combine to stereo
selectObject: combined123
plusObject: mono4
combined1234 = Combine to stereo
selectObject: combined1234
plusObject: mono5
combined12345 = Combine to stereo
selectObject: combined12345
plusObject: mono6
combined123456 = Combine to stereo
selectObject: combined123456
plusObject: mono7
combined1234567 = Combine to stereo
selectObject: combined1234567
plusObject: mono8
polyphony = Combine to stereo
Rename: sound_name$ + "_polyphony_8ch"
Scale peak: 0.99

# Clean up intermediate objects
removeObject: mono1, mono2, mono3, mono4, mono5, mono6, mono7, mono8
removeObject: combined12, combined123, combined1234, combined12345, combined123456, combined1234567

# Play if requested
if play_result
    selectObject: polyphony
    Play
endif