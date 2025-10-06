# ============================================================
# Praat AudioTools - compare loudness.praat
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

# Praat script to compare loudness between two audio files (teacher vs student)
# Select two Sound objects in the Objects list before running

clearinfo

# Set parameters for loudness analysis
time_step = 0.01
window_length = 0.025

# Check if exactly two sounds are selected
numberOfSelectedSounds = numberOfSelected("Sound")
if numberOfSelectedSounds != 2
    exitScript: "Please select exactly two Sound objects."
endif

# Get the two selected sounds
sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

appendInfoLine: "Starting loudness comparison..."

# Get basic info about sounds
selectObject: sound1
name1$ = selected$("Sound")
duration1 = Get total duration

selectObject: sound2
name2$ = selected$("Sound")
duration2 = Get total duration

appendInfoLine: "Sound 1 (Teacher): ", name1$, " (", fixed$(duration1, 3), "s)"
appendInfoLine: "Sound 2 (Student): ", name2$, " (", fixed$(duration2, 3), "s)"

# Create Intensity objects for detailed analysis
appendInfoLine: "Creating intensity contours..."

selectObject: sound1
intensity1 = To Intensity: 75, time_step, "yes"

selectObject: sound2
intensity2 = To Intensity: 75, time_step, "yes"

# Get intensity statistics
selectObject: intensity1
frames1 = Get number of frames
mean_db1 = Get mean: 0, 0, "dB"
std_db1 = Get standard deviation: 0, 0
min_db1 = Get minimum: 0, 0, "Parabolic"
max_db1 = Get maximum: 0, 0, "Parabolic"

selectObject: intensity2
frames2 = Get number of frames
mean_db2 = Get mean: 0, 0, "dB"
std_db2 = Get standard deviation: 0, 0
min_db2 = Get minimum: 0, 0, "Parabolic"
max_db2 = Get maximum: 0, 0, "Parabolic"

appendInfoLine: "Intensity analysis completed."
appendInfoLine: "Intensity frames: ", frames1, " vs ", frames2

# Calculate frame-by-frame loudness distance
min_frames = min(frames1, frames2)
total_db_distance = 0
max_db_diff = 0
min_db_diff = 999
squared_differences = 0

appendInfoLine: "Calculating loudness distances..."

for frame from 1 to min_frames
    selectObject: intensity1
    db1 = Get value in frame: frame
    selectObject: intensity2
    db2 = Get value in frame: frame
    
    # Skip undefined values (silence)
    if db1 != undefined and db2 != undefined
        db_diff = abs(db1 - db2)
        total_db_distance += db_diff
        squared_differences += db_diff * db_diff
        
        if db_diff > max_db_diff
            max_db_diff = db_diff
        endif
        if db_diff < min_db_diff
            min_db_diff = db_diff
        endif
    endif
endfor

# Calculate statistics
average_db_distance = total_db_distance / min_frames
rms_db_distance = sqrt(squared_differences / min_frames)

# Calculate dynamic range differences
dynamic_range1 = max_db1 - min_db1
dynamic_range2 = max_db2 - min_db2
dynamic_range_diff = abs(dynamic_range1 - dynamic_range2)

# Calculate loudness consistency (standard deviation difference)
consistency_diff = abs(std_db1 - std_db2)

# Display comprehensive results
appendInfoLine: ""
appendInfoLine: "=== LOUDNESS COMPARISON RESULTS ==="
appendInfoLine: ""
appendInfoLine: "Overall Loudness Distance:"
appendInfoLine: "  Average dB difference per frame: ", fixed$(average_db_distance, 3), " dB"
appendInfoLine: "  RMS dB difference: ", fixed$(rms_db_distance, 3), " dB"
appendInfoLine: "  Maximum frame difference: ", fixed$(max_db_diff, 3), " dB"
appendInfoLine: "  Minimum frame difference: ", fixed$(min_db_diff, 3), " dB"
appendInfoLine: ""
appendInfoLine: "Loudness Statistics:"
appendInfoLine: "  Mean loudness difference: ", fixed$(abs(mean_db1 - mean_db2), 3), " dB"
appendInfoLine: "  Dynamic range difference: ", fixed$(dynamic_range_diff, 3), " dB"
appendInfoLine: "  Consistency difference: ", fixed$(consistency_diff, 3), " dB"
appendInfoLine: ""
appendInfoLine: "Teacher (Sound 1) Details:"
appendInfoLine: "  Mean intensity: ", fixed$(mean_db1, 2), " dB"
appendInfoLine: "  Standard deviation: ", fixed$(std_db1, 2), " dB"
appendInfoLine: "  Dynamic range: ", fixed$(dynamic_range1, 2), " dB (", fixed$(min_db1, 1), " to ", fixed$(max_db1, 1), ")"
appendInfoLine: ""
appendInfoLine: "Student (Sound 2) Details:"
appendInfoLine: "  Mean intensity: ", fixed$(mean_db2, 2), " dB"
appendInfoLine: "  Standard deviation: ", fixed$(std_db2, 2), " dB"
appendInfoLine: "  Dynamic range: ", fixed$(dynamic_range2, 2), " dB (", fixed$(min_db2, 1), " to ", fixed$(max_db2, 1), ")"
appendInfoLine: ""
appendInfoLine: "Comparison Assessment:"
if average_db_distance < 3
    appendInfoLine: "  Loudness similarity: EXCELLENT (very close loudness control)"
elsif average_db_distance < 6
    appendInfoLine: "  Loudness similarity: GOOD (similar loudness patterns)"
elsif average_db_distance < 10
    appendInfoLine: "  Loudness similarity: MODERATE (noticeable loudness differences)"
else
    appendInfoLine: "  Loudness similarity: NEEDS WORK (significant loudness differences)"
endif

if consistency_diff < 2
    appendInfoLine: "  Loudness consistency: EXCELLENT (similar dynamic control)"
elsif consistency_diff < 4
    appendInfoLine: "  Loudness consistency: GOOD (comparable dynamics)"
else
    appendInfoLine: "  Loudness consistency: NEEDS WORK (different dynamic control)"
endif

# Clean up
selectObject: intensity1, intensity2
Remove

# Reselect original sounds
selectObject: sound1, sound2

appendInfoLine: ""
appendInfoLine: "Loudness analysis completed successfully!"