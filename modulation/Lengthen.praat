form Files
	positive target 5.2
endform
Convert to mono
duration = Get end time

change_factor = target / duration
Lengthen (overlap-add)... 75 600 change_factor
Play