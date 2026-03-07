# ============================================================
# Praat -> Python host -> VST3 -> Praat
# Put this .praat file and host_vst.py in the same folder.
# Select one Sound object and run this script.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

q$ = """"

# ============================================================
# Platform setup
# ============================================================

if windows
    sep$ = "\"
    pythonCmd$ = "py"
    nDirs = 4
    scanDir$[1] = "C:" + sep$ + "Program Files" + sep$ + "Common Files" + sep$ + "VST3"
    scanDir$[2] = "C:" + sep$ + "Program Files (x86)" + sep$ + "Common Files" + sep$ + "VST3"
    scanDir$[3] = homeDirectory$ + sep$ + "AppData" + sep$ + "Local" + sep$ + "Programs" + sep$ + "Common" + sep$ + "VST3"
    scanDir$[4] = homeDirectory$ + sep$ + "AppData" + sep$ + "Roaming" + sep$ + "VST3"
    platform$ = "Windows"
elsif macintosh
    sep$ = "/"
    pythonCmd$ = "python3"
    nDirs = 2
    scanDir$[1] = "/Library/Audio/Plug-Ins/VST3"
    scanDir$[2] = homeDirectory$ + "/Library/Audio/Plug-Ins/VST3"
    platform$ = "macOS"
else
    sep$ = "/"
    pythonCmd$ = "python3"
    nDirs = 3
    scanDir$[1] = homeDirectory$ + "/.vst3"
    scanDir$[2] = "/usr/lib/vst3"
    scanDir$[3] = "/usr/local/lib/vst3"
    platform$ = "Linux"
endif

pluginDir$    = preferencesDirectory$ + sep$ + "plugin_AudioTools" + sep$
prefsFile$    = pluginDir$ + "vst_host_default.txt"
favoritesFile$ = pluginDir$ + "vst_favorites.txt"

# ============================================================
# Load saved default plugin
# ============================================================

defaultPlugin$ = ""
if fileReadable(prefsFile$)
    defaultPlugin$ = readFile$(prefsFile$)
    if right$(defaultPlugin$, 1) = newline$
        defaultPlugin$ = left$(defaultPlugin$, length(defaultPlugin$) - 1)
    endif
endif

# ============================================================
# Load plugin list: favorites file OR directory scan
# ============================================================

nPlugins = 0
usingFavorites = 0

if fileReadable(favoritesFile$)
    # --- Load from favorites file ---
    usingFavorites = 1
    favText$ = readFile$(favoritesFile$)
    # Parse line by line
    repeat
        nl = index(favText$, newline$)
        if nl > 0
            line$ = left$(favText$, nl - 1)
            favText$ = mid$(favText$, nl + 1, length(favText$))
        else
            line$ = favText$
            favText$ = ""
        endif
        # Trim whitespace
        line$ = replace$(line$, " ", "", 0)
        if length(line$) > 4 and right$(line$, 5) = ".vst3" and fileReadable(line$)
            nPlugins += 1
            # Extract filename from full path
            lastSep = rindex(line$, sep$)
            if lastSep > 0
                pluginFile$[nPlugins] = mid$(line$, lastSep + 1, length(line$))
            else
                pluginFile$[nPlugins] = line$
            endif
            pluginPath$[nPlugins] = line$
        endif
    until length(favText$) = 0 and length(line$) = 0

else
    # --- Scan standard directories ---
    for d from 1 to nDirs
        dir$ = scanDir$[d]
        strings = 0
        nocheck strings = Create Strings as file list: "vst3list", dir$ + sep$ + "*.vst3"
        if strings > 0
            selectObject: strings
            n = Get number of strings
            for i from 1 to n
                selectObject: strings
                entry$ = Get string: i
                nPlugins += 1
                pluginFile$[nPlugins] = entry$
                pluginPath$[nPlugins] = dir$ + sep$ + entry$
            endfor
            selectObject: strings
            Remove
        endif
    endfor
endif

# ============================================================
# Build plugin list text and find default
# ============================================================

defaultNum = 1
listText$ = ""
if nPlugins > 0
    if usingFavorites
        listText$ = "★ Favorites (" + string$(nPlugins) + "):" + newline$
    endif
    for i from 1 to nPlugins
        name$ = pluginFile$[i]
        if right$(name$, 5) = ".vst3"
            name$ = left$(name$, length(name$) - 5)
        endif
        listText$ = listText$ + string$(i) + ".  " + name$ + newline$
    endfor
    for i from 1 to nPlugins
        if pluginPath$[i] = defaultPlugin$
            defaultNum = i
        endif
    endfor
endif

# ============================================================
# Paths and validation
# ============================================================

pythonScript$ = "host_vst.py"
if not fileReadable(pythonScript$)
    exitScript: "Cannot find host_vst.py. Put host_vst.py in the same folder as this Praat script."
endif

tempInput$  = pluginDir$ + "vst_input.wav"
tempOutput$ = pluginDir$ + "vst_output.wav"
tempLog$    = pluginDir$ + "vst_log.txt"

# ============================================================
# Initial form values
# ============================================================

cur_plugin_number = defaultNum
cur_tail      = 1.0
cur_buf       = 8192
cur_params$   = ""
cur_play      = 1
cur_save      = 1
cur_favorite  = 0
chosenPath$   = defaultPlugin$
browseUsed    = 0

# ============================================================
# Main loop
# ============================================================

clicked = 1
repeat

    if chosenPath$ <> ""
        currentLabel$ = "Plugin: " + chosenPath$
    else
        currentLabel$ = "No plugin selected yet — use Browse or pick from list."
    endif

    if usingFavorites
        favLabel$ = "Favorites file: " + favoritesFile$
    else
        favLabel$ = "No favorites file yet — tick Add to favorites to create one."
    endif

    if nPlugins > 0
        beginPause: "VST3 Effect"
            comment: currentLabel$
            comment: listText$
            natural: "Plugin number", cur_plugin_number
            real: "Tail seconds", cur_tail
            natural: "Buffer size", cur_buf
            sentence: "Parameters", cur_params$
            boolean: "Save as default plugin", cur_save
            boolean: "Add to favorites", cur_favorite
            boolean: "Play result", cur_play
            comment: favLabel$
        clicked = endPause: "Browse", "Apply", "Done", 2
    else
        beginPause: "VST3 Effect"
            comment: currentLabel$
            comment: "No plugins found — use Browse to locate a plugin."
            real: "Tail seconds", cur_tail
            natural: "Buffer size", cur_buf
            sentence: "Parameters", cur_params$
            boolean: "Add to favorites", cur_favorite
            boolean: "Play result", cur_play
            comment: favLabel$
        clicked = endPause: "Browse", "Apply", "Done", 1
    endif

    # --- Browse ---
    if clicked = 1
        browsed$ = chooseReadFile$: "Select your VST3 plugin"
        if browsed$ <> ""
            # Trim trailing whitespace/CR that Windows file dialogs sometimes add
            if right$(browsed$, 1) = newline$ or right$(browsed$, 1) = " "
                browsed$ = left$(browsed$, length(browsed$) - 1)
            endif
            # Case-insensitive extension check
            ext$ = right$(browsed$, 5)
            ext$ = replace$(replace$(replace$(replace$(replace$(replace$(ext$,
                ..."A","a",0),"B","b",0),"C","c",0),"D","d",0),"E","e",0),"F","f",0)
            if not ext$ = ".vst3"
                exitScript: "Selected file does not appear to be a .vst3 plugin: " + browsed$
            endif
            chosenPath$ = browsed$
            browseUsed = 1
        endif

    # --- Apply or Done ---
    elsif clicked = 2 or clicked = 3

        # Read form values
        if nPlugins > 0
            cur_plugin_number = plugin_number
            if browseUsed = 0 and plugin_number >= 1 and plugin_number <= nPlugins
                chosenPath$ = pluginPath$[plugin_number]
            endif
            cur_save = save_as_default_plugin
            if save_as_default_plugin
                writeFileLine: prefsFile$, chosenPath$
            endif
        endif
        cur_tail      = tail_seconds
        cur_buf       = buffer_size
        cur_params$   = parameters$
        cur_play      = play_result
        cur_favorite  = add_to_favorites
        browseUsed    = 0

        # Add to favorites if requested
        if add_to_favorites and chosenPath$ <> ""
            # Check if already in favorites
            alreadyIn = 0
            for i from 1 to nPlugins
                if pluginPath$[i] = chosenPath$
                    alreadyIn = 1
                endif
            endfor
            if not alreadyIn
                appendFileLine: favoritesFile$, chosenPath$
                appendInfoLine: "Added to favorites: ", chosenPath$
            endif
        endif

        # Validate plugin
        if chosenPath$ = ""
            appendInfoLine: "*** No plugin selected. Use Browse to pick a plugin. ***"
            clicked = 2
        elsif not fileReadable(chosenPath$)
            appendInfoLine: "*** Cannot find VST3 plugin: " + chosenPath$ + " ***"
            clicked = 2
        else
            # Strip stray surrounding quotes from parameters
            paramString$ = cur_params$
            if left$(paramString$, 1) = q$ and right$(paramString$, 1) = q$ and length(paramString$) >= 2
                paramString$ = mid$(paramString$, 2, length(paramString$) - 2)
            endif

            # Write input WAV
            selectObject: sound
            Save as WAV file: tempInput$

            # Build command
            cmd$ = pythonCmd$ + " " + q$ + pythonScript$ + q$
                ... + " " + q$ + tempInput$ + q$
                ... + " " + q$ + tempOutput$ + q$
                ... + " " + q$ + chosenPath$ + q$
                ... + " " + string$(cur_tail)
                ... + " " + string$(cur_buf)
                ... + " " + q$ + paramString$ + q$
                ... + " 1"
                ... + " > " + q$ + tempLog$ + q$ + " 2>&1"

            clearinfo
            writeInfoLine:  "=== Praat -> Python -> VST3 ==="
            appendInfoLine: "Input sound:   ", soundName$
            appendInfoLine: "Platform:      ", platform$
            appendInfoLine: "Python:        ", pythonCmd$
            appendInfoLine: "VST3 plugin:   ", chosenPath$
            appendInfoLine: "Tail seconds:  ", fixed$(cur_tail, 2)
            appendInfoLine: "Buffer size:   ", cur_buf
            if length(paramString$) > 0
                appendInfoLine: "Parameters:    ", paramString$
            else
                appendInfoLine: "Parameters:    <plugin defaults>"
            endif
            if usingFavorites
                appendInfoLine: "Plugin list:   favorites"
            else
                appendInfoLine: "Plugin list:   directory scan"
            endif
            appendInfoLine: ""
            appendInfoLine: "Running..."
            appendInfoLine: cmd$

            t0 = stopwatch
            runSystem_nocheck: cmd$
            elapsed = stopwatch
            appendInfoLine: "Processing time: ", fixed$(elapsed, 2), " s"

            if fileReadable(tempLog$)
                log$ = readFile$(tempLog$)
                appendInfoLine: log$
                deleteFile: tempLog$
            endif

            deleteFile: tempInput$

            if fileReadable(tempOutput$)
                Read from file: tempOutput$
                Rename: soundName$ + "_vst"
                resultSound = selected("Sound")
                deleteFile: tempOutput$
                appendInfoLine: "Done. Created: ", soundName$ + "_vst"
                if cur_play
                    selectObject: resultSound
                    Play
                endif
            else
                appendInfoLine: ""
                appendInfoLine: "*** PROCESSING FAILED — see Python error above ***"
                appendInfoLine: "Adjust settings and try again, or click Done to exit."
                clicked = 2
            endif
        endif
    endif

until clicked = 3
