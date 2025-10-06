# ============================================================
# Praat AudioTools - compare pitch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# Praat script to compare pitch between two audio files (teacher vs student)
# Select two Sound objects in the Objects list before running

clearinfo

# Set parameters for pitch analysis
time_step = 0.01
pitch_floor = 75
pitch_ceiling = 600
max_number_of_candidates = 15
very_accurate = 0
silence_threshold = 0.03
voicing_threshold = 0.45
octave_cost = 0.01
octave_jump_cost = 0.35
voiced_unvoiced_cost = 0.14

# Check if exactly two sounds are selected
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds != 2
    exitScript: "Please select exactly two Sound objects."
endif

# Get the two selected sounds
sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

appendInfoLine: "Starting pitch comparison..."

# Get basic info about sounds
selectObject: sound1
name1$ = selected$("Sound")
duration1 = Get total duration

selectObject: sound2
name2$ = selected$("Sound")
duration2 = Get total duration

appendInfoLine: "Sound 1 (Teacher): ", name1$, " (", fixed$(duration1, 3), "s)"
appendInfoLine: "Sound 2 (Student): ", name2$, " (", fixed$(duration2, 3), "s)"

# Create Pitch objects for analysis
appendInfoLine: "Extracting pitch contours..."

selectObject: sound1
pitch1 = To Pitch: time_step, pitch_floor, pitch_ceiling

selectObject: sound2
pitch2 = To Pitch: time_step, pitch_floor, pitch_ceiling

# Get pitch statistics
selectObject: pitch1
frames1 = Get number of frames
mean_f0_1 = Get mean: 0, 0, "Hertz"
std_f0_1 = Get standard deviation: 0, 0, "Hertz"
min_f0_1 = Get minimum: 0, 0, "Hertz", "Parabolic"
max_f0_1 = Get maximum: 0, 0, "Hertz", "Parabolic"

selectObject: pitch2
frames2 = Get number of frames
mean_f0_2 = Get mean: 0, 0, "Hertz"
std_f0_2 = Get standard deviation: 0, 0, "Hertz"
min_f0_2 = Get minimum: 0, 0, "Hertz", "Parabolic"
max_f0_2 = Get maximum: 0, 0, "Hertz", "Parabolic"

appendInfoLine: "Pitch analysis completed."
appendInfoLine: "Pitch frames: ", frames1, " vs ", frames2

# Calculate frame-by-frame pitch distance
min_frames = min(frames1, frames2)
total_hz_distance = 0
total_semitone_distance = 0
total_cent_distance = 0
voiced_frames = 0
max_hz_diff = 0
min_hz_diff = 999999
max_semitone_diff = 0

appendInfoLine: "Calculating pitch distances..."

for frame from 1 to min_frames
    selectObject: pitch1
    f0_1 = Get value in frame: frame, "Hertz"
    selectObject: pitch2
    f0_2 = Get value in frame: frame, "Hertz"
    
    # Only calculate for voiced frames in both sounds
    if f0_1 != undefined and f0_2 != undefined and f0_1 > 0 and f0_2 > 0
        voiced_frames += 1
        
        # Calculate Hz difference
        hz_diff = abs(f0_1 - f0_2)
        total_hz_distance += hz_diff
        
        # Calculate semitone difference
        semitone_diff = abs(12 * log2(f0_1 / f0_2))
        total_semitone_distance += semitone_diff
        
        # Calculate cent difference (1 semitone = 100 cents)
        cent_diff = semitone_diff * 100
        total_cent_distance += cent_diff
        
        # Track extremes
        if hz_diff > max_hz_diff
            max_hz_diff = hz_diff
        endif
        if hz_diff < min_hz_diff
            min_hz_diff = hz_diff
        endif
        if semitone_diff > max_semitone_diff
            max_semitone_diff = semitone_diff
        endif
    endif
endfor

# Calculate averages (only for voiced frames)
if voiced_frames > 0
    average_hz_distance = total_hz_distance / voiced_frames
    average_semitone_distance = total_semitone_distance / voiced_frames
    average_cent_distance = total_cent_distance / voiced_frames
else
    average_hz_distance = 0
    average_semitone_distance = 0
    average_cent_distance = 0
endif

# Calculate pitch range differences
pitch_range_1 = max_f0_1 - min_f0_1
pitch_range_2 = max_f0_2 - min_f0_2
pitch_range_diff = abs(pitch_range_1 - pitch_range_2)

# Calculate pitch variability difference
pitch_variability_diff = abs(std_f0_1 - std_f0_2)

# Calculate mean pitch difference in semitones
if mean_f0_1 > 0 and mean_f0_2 > 0
    mean_pitch_semitone_diff = abs(12 * log2(mean_f0_1 / mean_f0_2))
else
    mean_pitch_semitone_diff = 0
endif

# Display comprehensive results
appendInfoLine: ""
appendInfoLine: "=== PITCH COMPARISON RESULTS ==="
appendInfoLine: ""
appendInfoLine: "Pitch Distance (Voiced Frames Only):"
appendInfoLine: "  Voiced frames analyzed: ", voiced_frames, " out of ", min_frames
appendInfoLine: "  Average Hz difference: ", fixed$(average_hz_distance, 2), " Hz"
appendInfoLine: "  Average semitone difference: ", fixed$(average_semitone_distance, 3), " semitones"
appendInfoLine: "  Average cent difference: ", fixed$(average_cent_distance, 1), " cents"
appendInfoLine: "  Maximum Hz difference: ", fixed$(max_hz_diff, 2), " Hz"
appendInfoLine: "  Minimum Hz difference: ", fixed$(min_hz_diff, 2), " Hz"
appendInfoLine: "  Maximum semitone difference: ", fixed$(max_semitone_diff, 3), " semitones"
appendInfoLine: ""
appendInfoLine: "Overall Pitch Statistics:"
appendInfoLine: "  Mean pitch difference: ", fixed$(mean_pitch_semitone_diff, 3), " semitones"
appendInfoLine: "  Pitch range difference: ", fixed$(pitch_range_diff, 2), " Hz"
appendInfoLine: "  Pitch variability difference: ", fixed$(pitch_variability_diff, 2), " Hz"
appendInfoLine: ""
appendInfoLine: "Teacher (Sound 1) Details:"
appendInfoLine: "  Mean F0: ", fixed$(mean_f0_1, 2), " Hz"
appendInfoLine: "  Standard deviation: ", fixed$(std_f0_1, 2), " Hz"
appendInfoLine: "  Pitch range: ", fixed$(pitch_range_1, 2), " Hz (", fixed$(min_f0_1, 1), " to ", fixed$(max_f0_1, 1), ")"
appendInfoLine: ""
appendInfoLine: "Student (Sound 2) Details:"
appendInfoLine: "  Mean F0: ", fixed$(mean_f0_2, 2), " Hz"
appendInfoLine: "  Standard deviation: ", fixed$(std_f0_2, 2), " Hz"
appendInfoLine: "  Pitch range: ", fixed$(pitch_range_2, 2), " Hz (", fixed$(min_f0_2, 1), " to ", fixed$(max_f0_2, 1), ")"
appendInfoLine: ""
appendInfoLine: "Pitch Accuracy Assessment:"
if average_semitone_distance < 0.25
    appendInfoLine: "  Pitch accuracy: EXCELLENT (< 25 cents average)"
elsif average_semitone_distance < 0.5
    appendInfoLine: "  Pitch accuracy: VERY GOOD (25-50 cents average)"
elsif average_semitone_distance < 1.0
    appendInfoLine: "  Pitch accuracy: GOOD (50-100 cents average)"
elsif average_semitone_distance < 2.0
    appendInfoLine: "  Pitch accuracy: MODERATE (1-2 semitones average)"
else
    appendInfoLine: "  Pitch accuracy: NEEDS WORK (> 2 semitones average)"
endif

if mean_pitch_semitone_diff < 0.5
    appendInfoLine: "  Overall pitch level: EXCELLENT match"
elsif mean_pitch_semitone_diff < 1.0
    appendInfoLine: "  Overall pitch level: GOOD match"
elsif mean_pitch_semitone_diff < 2.0
    appendInfoLine: "  Overall pitch level: MODERATE difference"
else
    appendInfoLine: "  Overall pitch level: SIGNIFICANT difference"
endif

if pitch_variability_diff < 10
    appendInfoLine: "  Pitch expression: EXCELLENT (similar melodic variation)"
elsif pitch_variability_diff < 20
    appendInfoLine: "  Pitch expression: GOOD (comparable melodic range)"
else
    appendInfoLine: "  Pitch expression: DIFFERENT (varying melodic styles)"
endif

# Clean up
selectObject: pitch1, pitch2
Remove

# Reselect original sounds
selectObject: sound1, sound2

appendInfoLine: ""
appendInfoLine: "Pitch analysis completed successfully!"