clearinfo
pause select all sounds to be used for this operation
number_of_selected_sounds = numberOfSelected ("Sound")

for index to number_of_selected_sounds
	sound'index' = selected("Sound",index)
endfor


for current_sound_index from 1 to number_of_selected_sounds
    select sound'current_sound_index'
	name$ = selected$("Sound")
	

a = selected("Sound")
b = To Pitch (raw cc): 0, 75, 600, 15, "no", 0.03, 0.45, 0.01, 0.35, 0.14
select a
plus b
c = To PointProcess (cc)
select a
plus b
plus c
voiceReport$ = Voice report: 0, 0, 75, 600, 1.3, 1.6, 0.03, 0.45


	int = (extractNumber (voiceReport$, "Jitter (local): "))*100
    	print 'name$''tab$''int:2''newline$'


endfor

select sound1
for current_sound_index from 2 to number_of_selected_sounds
    plus sound'current_sound_index'
endfor











