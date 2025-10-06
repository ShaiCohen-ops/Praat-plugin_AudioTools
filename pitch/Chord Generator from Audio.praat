# ============================================================
# Praat AudioTools - Chord Generator from Audio.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Chord Generator from Audio
    optionmenu Chord_type: 1
        option "Major"
        option "Minor"
        option "Sus2"
        option "Sus4"
        option "Diminished"
        option "Augmented"
        option "Major7"
        option "Minor7"
    real Volume_each_note 0.33
endform

# Check if a sound is selected
if numberOfSelected("Sound") = 0
    exitScript: "Please select a sound first."
endif

# Get the original sound
original = selected("Sound")
selectObject: original

# Convert to mono if stereo
channels = Get number of channels
if channels = 2
    mono_original = Convert to mono
    removeObject: original
    original = mono_original
    selectObject: original
endif

# Define chord intervals based on selection
if chord_type = 1
    # Major (Root, Major 3rd, Perfect 5th)
    interval2 = 4
    interval3 = 7
elsif chord_type = 2
    # Minor (Root, Minor 3rd, Perfect 5th)
    interval2 = 3
    interval3 = 7
elsif chord_type = 3
    # Sus2 (Root, Major 2nd, Perfect 5th)
    interval2 = 2
    interval3 = 7
elsif chord_type = 4
    # Sus4 (Root, Perfect 4th, Perfect 5th)
    interval2 = 5
    interval3 = 7
elsif chord_type = 5
    # Diminished (Root, Minor 3rd, Diminished 5th)
    interval2 = 3
    interval3 = 6
elsif chord_type = 6
    # Augmented (Root, Major 3rd, Augmented 5th)
    interval2 = 4
    interval3 = 8
elsif chord_type = 7
    # Major7 (Root, Major 3rd, Perfect 5th, Major 7th)
    interval2 = 4
    interval3 = 7
    interval4 = 11
elsif chord_type = 8
    # Minor7 (Root, Minor 3rd, Perfect 5th, Minor 7th)
    interval2 = 3
    interval3 = 7
    interval4 = 10
else
    # Default to Major
    interval2 = 4
    interval3 = 7
endif

# Get sampling frequency
selectObject: original
fs = Get sampling frequency
semitone_ratio = 2 ^ (1/12)

# Create root note (original)
selectObject: original
root_note = Copy: "root"
selectObject: root_note
Scale peak: volume_each_note

# Create second note using the provided pitch shift method
selectObject: original
second_copy = Copy: "tmp_src_2"
selectObject: second_copy
note_ratio_2 = semitone_ratio ^ interval2
newfs_2 = fs * note_ratio_2
Override sampling frequency: newfs_2
manip_2 = To Manipulation: 0.01, 75, 600
selectObject: manip_2
dur_tier_2 = Extract duration tier
selectObject: dur_tier_2
Add point: 0, note_ratio_2
selectObject: manip_2
plusObject: dur_tier_2
Replace duration tier
selectObject: manip_2
second_resyn = Get resynthesis (overlap-add)
selectObject: second_resyn
Rename: "pitch_shifted_2"
second_final = Resample: fs, 50
selectObject: second_final
Scale peak: volume_each_note

# Clean up second note working objects
removeObject: dur_tier_2, manip_2, second_copy, second_resyn

# Create third note using the provided pitch shift method
selectObject: original
third_copy = Copy: "tmp_src_3"
selectObject: third_copy
note_ratio_3 = semitone_ratio ^ interval3
newfs_3 = fs * note_ratio_3
Override sampling frequency: newfs_3
manip_3 = To Manipulation: 0.01, 75, 600
selectObject: manip_3
dur_tier_3 = Extract duration tier
selectObject: dur_tier_3
Add point: 0, note_ratio_3
selectObject: manip_3
plusObject: dur_tier_3
Replace duration tier
selectObject: manip_3
third_resyn = Get resynthesis (overlap-add)
selectObject: third_resyn
Rename: "pitch_shifted_3"
third_final = Resample: fs, 50
selectObject: third_final
Scale peak: volume_each_note

# Clean up third note working objects
removeObject: dur_tier_3, manip_3, third_copy, third_resyn

# For 7th chords, create fourth note
if chord_type = 7 or chord_type = 8
    selectObject: original
    fourth_copy = Copy: "tmp_src_4"
    selectObject: fourth_copy
    note_ratio_4 = semitone_ratio ^ interval4
    newfs_4 = fs * note_ratio_4
    Override sampling frequency: newfs_4
    manip_4 = To Manipulation: 0.01, 75, 600
    selectObject: manip_4
    dur_tier_4 = Extract duration tier
    selectObject: dur_tier_4
    Add point: 0, note_ratio_4
    selectObject: manip_4
    plusObject: dur_tier_4
    Replace duration tier
    selectObject: manip_4
    fourth_resyn = Get resynthesis (overlap-add)
    selectObject: fourth_resyn
    Rename: "pitch_shifted_4"
    fourth_final = Resample: fs, 50
    selectObject: fourth_final
    Scale peak: volume_each_note
    
    # Clean up fourth note working objects
    removeObject: dur_tier_4, manip_4, fourth_copy, fourth_resyn
    
    # Combine all four notes for 7th chords
    selectObject: root_note
    plusObject: second_final
    chord_stereo = Combine to stereo
    
    selectObject: chord_stereo
    plusObject: third_final
    chord_stereo2 = Combine to stereo
    
    selectObject: chord_stereo2
    plusObject: fourth_final
    chord_result = Combine to stereo
    
    # Clean up intermediate objects
    removeObject: root_note, second_final, third_final, fourth_final, chord_stereo, chord_stereo2
else
    # Combine three notes for triads
    selectObject: root_note
    plusObject: second_final
    chord_stereo = Combine to stereo
    
    selectObject: chord_stereo
    plusObject: third_final
    chord_result = Combine to stereo
    
    # Clean up
    removeObject: root_note, second_final, third_final, chord_stereo
endif

# Play the chord
selectObject: chord_result
Play

# Keep the chord selected
selectObject: chord_result