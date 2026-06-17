# ============================================================
# Praat AudioTools - a-e-i-o_filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026) - Stereo-safe (mono copy for LPC Filter)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Vowel Formant Filter - Applies vocal tract resonances
#   of vowels (a, e, i, o, u) to shape the input sound's timbre.
#
# Changelog v0.2:
#   - Fixed old syntax (select, exit)
#   - Added presets and vowel selection
#   - Added visualization
#   - ID-based object management
#   - Added 'u' vowel option
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
origName$ = selected$("Sound")

form Vowel Formant Filter v0.3
    comment === Preset ===
    optionmenu Preset: 1
        option All Vowels (a-e-i-o-u)
        option Classic (a-e-i-o)
        option Front Vowels (e-i)
        option Back Vowels (a-o-u)
        option Single: a
        option Single: e
        option Single: i
        option Single: o
        option Single: u
    comment === Vowel Selection (for Manual) ===
    boolean Include_a 1
    boolean Include_e 1
    boolean Include_i 1
    boolean Include_o 1
    boolean Include_u 0
    comment === Output ===
    boolean Concatenate_results 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 1
    # All Vowels
    include_a = 1
    include_e = 1
    include_i = 1
    include_o = 1
    include_u = 1
    presetName$ = "AllVowels"
elsif preset = 2
    # Classic
    include_a = 1
    include_e = 1
    include_i = 1
    include_o = 1
    include_u = 0
    presetName$ = "Classic"
elsif preset = 3
    # Front Vowels
    include_a = 0
    include_e = 1
    include_i = 1
    include_o = 0
    include_u = 0
    presetName$ = "FrontVowels"
elsif preset = 4
    # Back Vowels
    include_a = 1
    include_e = 0
    include_i = 0
    include_o = 1
    include_u = 1
    presetName$ = "BackVowels"
elsif preset = 5
    include_a = 1
    include_e = 0
    include_i = 0
    include_o = 0
    include_u = 0
    presetName$ = "Vowel_a"
elsif preset = 6
    include_a = 0
    include_e = 1
    include_i = 0
    include_o = 0
    include_u = 0
    presetName$ = "Vowel_e"
elsif preset = 7
    include_a = 0
    include_e = 0
    include_i = 1
    include_o = 0
    include_u = 0
    presetName$ = "Vowel_i"
elsif preset = 8
    include_a = 0
    include_e = 0
    include_i = 0
    include_o = 1
    include_u = 0
    presetName$ = "Vowel_o"
elsif preset = 9
    include_a = 0
    include_e = 0
    include_i = 0
    include_o = 0
    include_u = 1
    presetName$ = "Vowel_u"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
clearinfo
writeInfoLine: "=== Vowel Formant Filter v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", origName$
appendInfoLine: ""

selectObject: sound
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels

appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "Sample rate: ", fs, " Hz"
appendInfoLine: ""

# LPC Filter requires a mono signal. Build a mono copy to filter; the
# original (possibly stereo) is kept for the visualization.
selectObject: sound
if nch > 1
    filterSrc = Convert to mono
    Rename: "vt_filter_src"
else
    filterSrc = Copy: "vt_filter_src"
endif

# Count selected vowels
numVowels = include_a + include_e + include_i + include_o + include_u
if numVowels = 0
    exitScript: "Please select at least one vowel."
endif

# Build vowel list
vowelList$ = ""
if include_a
    vowelList$ = vowelList$ + "a "
endif
if include_e
    vowelList$ = vowelList$ + "e "
endif
if include_i
    vowelList$ = vowelList$ + "i "
endif
if include_o
    vowelList$ = vowelList$ + "o "
endif
if include_u
    vowelList$ = vowelList$ + "u "
endif

appendInfoLine: "Vowels: ", vowelList$
appendInfoLine: ""

# ============================================================
# Create Vocal Tracts and LPCs
# VocalTract -> VocalTractTier -> LPC (correct workflow)
# ============================================================
appendInfoLine: "Creating vocal tract models..."

if include_a
    Create Vocal Tract from phone: "a"
    vt_a = selected("VocalTract")
    selectObject: vt_a
    To VocalTractTier: 0, dur, 0.5
    vtt_a = selected("VocalTractTier")
    To LPC: 0.005
    lpc_a = selected("LPC")
    appendInfoLine: "  [a] created"
endif

if include_e
    Create Vocal Tract from phone: "e"
    vt_e = selected("VocalTract")
    selectObject: vt_e
    To VocalTractTier: 0, dur, 0.5
    vtt_e = selected("VocalTractTier")
    To LPC: 0.005
    lpc_e = selected("LPC")
    appendInfoLine: "  [e] created"
endif

if include_i
    Create Vocal Tract from phone: "i"
    vt_i = selected("VocalTract")
    selectObject: vt_i
    To VocalTractTier: 0, dur, 0.5
    vtt_i = selected("VocalTractTier")
    To LPC: 0.005
    lpc_i = selected("LPC")
    appendInfoLine: "  [i] created"
endif

if include_o
    Create Vocal Tract from phone: "o"
    vt_o = selected("VocalTract")
    selectObject: vt_o
    To VocalTractTier: 0, dur, 0.5
    vtt_o = selected("VocalTractTier")
    To LPC: 0.005
    lpc_o = selected("LPC")
    appendInfoLine: "  [o] created"
endif

if include_u
    Create Vocal Tract from phone: "u"
    vt_u = selected("VocalTract")
    selectObject: vt_u
    To VocalTractTier: 0, dur, 0.5
    vtt_u = selected("VocalTractTier")
    To LPC: 0.005
    lpc_u = selected("LPC")
    appendInfoLine: "  [u] created"
endif

# ============================================================
# Filter with each LPC
# ============================================================
appendInfoLine: ""
appendInfoLine: "Filtering..."

outputCount = 0

if include_a
    selectObject: filterSrc
    plusObject: lpc_a
    Filter: "no"
    filtered_a_temp = selected("Sound")
    selectObject: filtered_a_temp
    Resample: fs, 50
    filtered_a = selected("Sound")
    Rename: origName$ + "_VT_a"
    removeObject: filtered_a_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_a
    appendInfoLine: "  [a] filtered"
endif

if include_e
    selectObject: filterSrc
    plusObject: lpc_e
    Filter: "no"
    filtered_e_temp = selected("Sound")
    selectObject: filtered_e_temp
    Resample: fs, 50
    filtered_e = selected("Sound")
    Rename: origName$ + "_VT_e"
    removeObject: filtered_e_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_e
    appendInfoLine: "  [e] filtered"
endif

if include_i
    selectObject: filterSrc
    plusObject: lpc_i
    Filter: "no"
    filtered_i_temp = selected("Sound")
    selectObject: filtered_i_temp
    Resample: fs, 50
    filtered_i = selected("Sound")
    Rename: origName$ + "_VT_i"
    removeObject: filtered_i_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_i
    appendInfoLine: "  [i] filtered"
endif

if include_o
    selectObject: filterSrc
    plusObject: lpc_o
    Filter: "no"
    filtered_o_temp = selected("Sound")
    selectObject: filtered_o_temp
    Resample: fs, 50
    filtered_o = selected("Sound")
    Rename: origName$ + "_VT_o"
    removeObject: filtered_o_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_o
    appendInfoLine: "  [o] filtered"
endif

if include_u
    selectObject: filterSrc
    plusObject: lpc_u
    Filter: "no"
    filtered_u_temp = selected("Sound")
    selectObject: filtered_u_temp
    Resample: fs, 50
    filtered_u = selected("Sound")
    Rename: origName$ + "_VT_u"
    removeObject: filtered_u_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_u
    appendInfoLine: "  [u] filtered"
endif

# ============================================================
# Concatenate if requested
# ============================================================
if concatenate_results and outputCount > 1
    appendInfoLine: ""
    appendInfoLine: "Concatenating..."
    
    selectObject: output_1
    for i from 2 to outputCount
        plusObject: output_'i'
    endfor
    Concatenate
    concatenated = selected("Sound")
    Rename: origName$ + "_VT_" + presetName$
    
    finalOutput = concatenated
else
    finalOutput = output_1
endif

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Vowel Formant Filter: " + origName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.75, 1.7
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Filtered outputs
    panelHeight = 1.0
    if outputCount > 4
        panelHeight = 0.8
    endif
    
    currentTop = 2.0
    
    for i from 1 to outputCount
        Select outer viewport: 0, 8, currentTop, currentTop + panelHeight
        Select inner viewport: 0.6, 7.6, currentTop + 0.1, currentTop + panelHeight - 0.1
        
        selectObject: output_'i'
        outName$ = selected$("Sound")
        
        # Color by vowel
        if index(outName$, "_a") > 0
            Colour: "{0.8, 0.3, 0.3}"
            vowelLabel$ = "[a]"
        elsif index(outName$, "_e") > 0
            Colour: "{0.3, 0.7, 0.3}"
            vowelLabel$ = "[e]"
        elsif index(outName$, "_i") > 0
            Colour: "{0.3, 0.3, 0.8}"
            vowelLabel$ = "[i]"
        elsif index(outName$, "_o") > 0
            Colour: "{0.8, 0.6, 0.2}"
            vowelLabel$ = "[o]"
        else
            Colour: "{0.6, 0.3, 0.7}"
            vowelLabel$ = "[u]"
        endif
        
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", vowelLabel$
        
        currentTop = currentTop + panelHeight
    endfor
    
    # Concatenated output (if exists)
    if concatenate_results and outputCount > 1
        Select outer viewport: 0, 8, currentTop + 0.1, currentTop + 1.2
        Select inner viewport: 0.6, 7.6, currentTop + 0.2, currentTop + 1.1
        
        selectObject: concatenated
        Colour: "{0.2, 0.5, 0.7}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text left: "yes", "Output"
        Text bottom: "yes", "Time (s)"
    endif
    
    Font size: 10
endif

# ============================================================
# Cleanup
# ============================================================
appendInfoLine: ""
appendInfoLine: "Cleaning up..."

nocheck removeObject: filterSrc

# Remove VocalTracts, VocalTractTiers, and LPCs
if include_a
    removeObject: vt_a, vtt_a, lpc_a
endif
if include_e
    removeObject: vt_e, vtt_e, lpc_e
endif
if include_i
    removeObject: vt_i, vtt_i, lpc_i
endif
if include_o
    removeObject: vt_o, vtt_o, lpc_o
endif
if include_u
    removeObject: vt_u, vtt_u, lpc_u
endif

# Remove individual filtered sounds if concatenated
if concatenate_results and outputCount > 1
    for i from 1 to outputCount
        removeObject: output_'i'
    endfor
endif

# ============================================================
# Output
# ============================================================
selectObject: sound
plusObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")

if play_result
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput