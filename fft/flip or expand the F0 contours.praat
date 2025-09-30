# # ## ### ##### ########  #############  ##################### 
# Praat script to flip or expand the F0 contours 
# of each sound file in a folder
# using PSOLA 
#
# Matthew B. Winn
# July 2014
##################################
##################### 
############# 
######## 
#####
###
##
#
#
# options to 
	# flip contour, 
	# expand contour (by some multiplier), 
	# or flatten contour (to the mean, or a fixed value)

form Enter Settings for F0 manipulation
	comment Set floor & ceiling for pitch analysis
	comment (range where you expect the pitch to fall)
	real minPitch 70
	real maxPitch 250


	comment choose your method of F0 manipulation 
	optionmenu method 1
	   option Flip F0 contour
	   option Expand/Contract F0 contour
	   option Flatten F0 contour 

	comment Type a suffix for the altered sound names
	comment (e.g. "Name" -> "NameSuffix") (this can be left blank)
	sentence suffix _flipped

	#boolean leave_original_sounds_in_list_window 1
	#boolean leave_altered_sounds_in_list_window 1
endform



#### Offer wizard-type options to declare settings

if method = 1
    # Flip F0 contour 
    # simple; no settings to declare

elsif method = 2
    # expand F0 contour
    # bring up form to declare settings
    beginPause ("Choose the settings for F0 expansion/contraction")
	comment ("I want to multiply the F0 contour")
	comment ("by a factor of... ")

	real ("multiplier", "1.3")
	#sentence ("sub_directory_name", "F0_mult_13")
     endPause ("Cancel", "OK", 2)
     
elsif method = 3
     # flatten F0 contour
     # bring up form to declare settings
     beginPause ("Choose the settings for F0 flattening")
	comment ("I want to flatten the F0 contour")
	comment ("to the level of... ")
	comment ("leave at 0 to use the mean")
	real ("flat_level", "0")
	#sentence ("sub_directory_name", "F0_flat_mean")
     endPause ("Cancel", "OK", 2)
     
endif

# do the procedure
clearinfo
pause select all sounds to be used for this operation
numberOfSelectedSounds = numberOfSelected ("Sound")

# assign an object number to each sound, 
# assign those object numbers to a pseudo-array
for thisSelectedSound to numberOfSelectedSounds
	sound'thisSelectedSound' = selected("Sound",thisSelectedSound)
endfor

for thisSound from 1 to numberOfSelectedSounds
    select sound'thisSound'
	thisSound$ = selected$("Sound")

   
   # Do the manipulation using a dynamic procedure
	call f0_contour_adjust 'thisSound$' minPitch maxPitch 'suffix$'
	
   # Cleanup files
   # vestiges of a previous version of the script;
   # should be enabled only in the case of altering MANY objects,
   # for the purpose of memory management. 
	#if leave_original_sounds_in_list_window = 0
	#	select Sound 'thisSound$'
	#	Remove
	#endif
	#if leave_altered_sounds_in_list_window = 0
	#	select Sound 'thisSound$''suffix$'
	#	Remove
	#endif	
endfor

#re-select the sounds
   select sound1
    for thisSound from 2 to numberOfSelectedSounds
       plus sound'thisSound'
   endfor


#
#
##
###
#####
########
#############
#####################

procedure f0_contour_adjust .name$ .minPitch .maxPitch .suffix$
    ## get the sound and the mean pitch 
	select Sound '.name$'
	do ("To Manipulation...", 0.01, .minPitch, .maxPitch)
	do ("Extract pitch tier")
	meanPitch = do ("Get mean (points)...", 0, 0)

    ### Modify the pitch contour in one of three ways
	if method = 1
		# flip F0 contour 
		   do ("Formula...", "meanPitch-(self-meanPitch)")

	elsif method = 2
		# multiply F0 contour around the mean
		# (excursions are multiplied) 
		   do ("Formula...", "meanPitch-((meanPitch-self)*multiplier)")

	elsif method = 3
		# flatten F0 contour
		# if the user left the flat level at 0,
		# then query the mean
		if flat_level = 0
		   target_level = meanPitch
		else
		   target_level = flat_level
		endif
		# flatten F0 contour
		do ("Formula...", "'target_level'")
	endif
		
    # replace pitch tier in manipulation object
    	select Manipulation '.name$'
    	plus PitchTier '.name$'
    	do ("Replace pitch tier")
    	select Manipulation '.name$'
    	do ("Get resynthesis (overlap-add)")
    	do ("Rename...", "'.name$''.suffix$'")
    	
    # cleanup
    	select Manipulation '.name$'
    	plus PitchTier '.name$'
	do ("Remove")
    
endproc