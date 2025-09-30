clearinfo
tierNames$ = "segments points"
pointTiers$ = "points"
inDir$ = chooseDirectory$: ""
if inDir$ == ""
	exitScript: "No folder given. Exiting"
endif

inDir$ = inDir$ + "/"
inDirWild$ = inDir$ + "*.wav"
wavList = Create Strings as file list: "wavList", inDirWild$
numFiles = Get number of strings
if numFiles == 0
	exitScript: "I didn't find any .wav files in that folder. Exiting"
endif

for fileNum from 1 to numFiles

	selectObject: wavList
	wavFile$ = Get string: fileNum
	wav = Read from file: inDir$ + wavFile$
	textGrid = To TextGrid (speech activity): 0, 0.3, 0.1, 70, 6000, -10, -35, 0.1, 0.1, "non-speech", "speech" 
		
	objName$ = selected$: "TextGrid"
	outPath$ = inDir$ + objName$ + ".TextGrid"

	if fileReadable: outPath$
		pauseScript: objName$ + ".TextGrid" + " exists! Overwrite?"
	endif

	Save as text file: outPath$
	selectObject: wav
	plusObject: textGrid
	Remove
endfor

# Remove the wav list
selectObject: wavList
Remove

pauseScript: "Done! The script ran with no errors."