clearinfo
pause select all sounds to be used for this operation
number_of_selected_sounds = numberOfSelected ("Sound")

for index to number_of_selected_sounds
	sound'index' = selected("Sound",index)
endfor


for current_sound_index from 1 to number_of_selected_sounds
    select sound'current_sound_index'
	name$ = selected$("Sound")
	To Intensity: 100, 0, "yes"
        int = Get mean: 0, 0, "energy"
    	print 'name$''tab$''int:2''newline$'


endfor

select sound1
for current_sound_index from 2 to number_of_selected_sounds
    plus sound'current_sound_index'
endfor



