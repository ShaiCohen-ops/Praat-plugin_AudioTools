# GENERATED autosave job - written by the Python launcher, do not edit.
# Exports every Sound object in the Objects window to numbered temp
# WAV files inside the project tmp/ folder, writes a manifest mapping
# index -> save status -> object name, restores the user's selection,
# and finally writes the done-marker (the LAST action, so the marker
# guarantees the manifest and all WAVs are complete).

tmpDir$ = "%TMP_DIR%"
manifest$ = tmpDir$ + "/manifest.txt"
done$ = tmpDir$ + "/done.txt"

nocheck deleteFile: manifest$
nocheck deleteFile: done$

# --- capture the user's current selection so we can restore it ---
nsel = numberOfSelected ()
for i to nsel
    sel_'i' = selected (i)
endfor

# --- enumerate all Sound objects ---
select all
nSounds = numberOfSelected ("Sound")
for i to nSounds
    sndId_'i' = selected ("Sound", i)
    sndName_'i'$ = selected$ ("Sound", i)
endfor

# --- export each Sound to a numbered temp file ---
for i to nSounds
    ok = 0
    nocheck selectObject: sndId_'i'
    # the object may have been removed meanwhile; verify the selection
    if numberOfSelected ("Sound") = 1 and selected ("Sound") = sndId_'i'
        wavPath$ = tmpDir$ + "/snd_" + right$ ("0000" + string$ (i), 4) + ".wav"
        nocheck Save as WAV file: wavPath$
        if fileReadable (wavPath$)
            ok = 1
        endif
    endif
    appendFileLine: manifest$, string$ (i), tab$, string$ (ok), tab$, sndName_'i'$
endfor

# --- restore the user's selection (objects may have vanished: nocheck) ---
if nsel > 0
    nocheck selectObject: sel_1
    for i from 2 to nsel
        nocheck plusObject: sel_'i'
    endfor
else
    selectObject ( )
endif

# --- done marker: must be the very last action of this job ---
writeFileLine: done$, "ok ", nSounds
