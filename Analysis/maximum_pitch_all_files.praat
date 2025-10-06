# ============================================================
# Praat AudioTools - maximum_pitch_all_files.praat
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

clearinfo
pause select all sounds to be used for this operation
number_of_selected_sounds = numberOfSelected ("Sound")

for index to number_of_selected_sounds
	sound'index' = selected("Sound",index)
endfor


for current_sound_index from 1 to number_of_selected_sounds
    select sound'current_sound_index'
	name$ = selected$("Sound")
	To Pitch (raw cc): 0, 75, 600, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
        int = Get maximum: 0, 0, "Hertz", "parabolic"
    	print 'name$''tab$''int:2''newline$'


endfor

select sound1
for current_sound_index from 2 to number_of_selected_sounds
    plus sound'current_sound_index'
endfor