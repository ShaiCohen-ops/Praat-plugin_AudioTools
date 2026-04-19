# ============================================================
# Praat AudioTools - semantic_timbre_retrieval.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Semantic Timbre Retrieval.
#   Type a free-text timbre prompt (e.g. "dark airy swelling scrape")
#   and retrieve the best-matching files or segments from a corpus.
#   A Python engine performs segmentation, feature extraction,
#   rule-based tagging, prompt parsing, and hybrid scoring.
#   An optional preview montage is returned as a Praat Sound object.
#
# Python engine: semantic_timbre_retrieval.py
# Data:          semantic_timbre_rules.json
#                semantic_prompt_lexicon.json
#
# Dependencies (Python):
#   pip install numpy scipy soundfile librosa
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-
#   Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form "Semantic Timbre Retrieval"
    sentence Prompt dark airy swelling scrape
    optionmenu Retrieval_mode: 2
        option files
        option segments
    positive Top_matches 8
    boolean Build_preview_montage 1
    positive Crossfade_ms 30
    real Min_segment_sec 0.25
    real Max_segment_sec 4.0
    real Segment_gate_dB -35.0
    real Weight_semantic 1.0
    real Weight_tag 0.5
    real Weight_keyword 0.25
    real Diversity_penalty 0.15
    boolean Draw_visualization 1
    boolean Play_preview 1
endform

corpusDir$ = chooseDirectory$("Select Corpus Folder (WAV/FLAC/AIFF/MP3)")
if corpusDir$ == ""
    exitScript: "Operation cancelled."
endif

if prompt$ == ""
    exitScript: "Please enter a text prompt."
endif

# ============================================================
# OS-Specific Python Discovery
# ============================================================
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ============================================================
# Paths Setup
# ============================================================
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/semantic_timbre_retrieval.py"
rulesJson$    = pluginDir$ + "py/semantic_timbre_rules.json"
lexiconJson$  = pluginDir$ + "py/semantic_prompt_lexicon.json"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/semantic_timbre_retrieval.py"
endif
if not fileReadable(rulesJson$)
    rulesJson$ = defaultDirectory$ + "/semantic_timbre_rules.json"
endif
if not fileReadable(lexiconJson$)
    lexiconJson$ = defaultDirectory$ + "/semantic_prompt_lexicon.json"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find semantic_timbre_retrieval.py." + newline$ + "Expected at: " + pluginDir$ + "py/"
endif
if not fileReadable(rulesJson$)
    exitScript: "Cannot find semantic_timbre_rules.json." + newline$ + "Expected at: " + pluginDir$ + "py/"
endif
if not fileReadable(lexiconJson$)
    exitScript: "Cannot find semantic_prompt_lexicon.json." + newline$ + "Expected at: " + pluginDir$ + "py/"
endif

tempPreview$     = temporaryDirectory$ + "/temp_str_preview.wav"
tempRetrieval$   = temporaryDirectory$ + "/temp_str_retrieval.csv"
tempSegments$    = temporaryDirectory$ + "/temp_str_segments.csv"
tempManifest$    = temporaryDirectory$ + "/temp_str_manifest.csv"
tempStats$       = temporaryDirectory$ + "/temp_str_stats.txt"
pyLog$           = temporaryDirectory$ + "/temp_str_error.log"
probeMarker$     = temporaryDirectory$ + "/temp_str_probe.ok"

# Replace backslashes for the Python inline probe to prevent escape crashes on Windows
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ============================================================
# Cleanup Procedure
# ============================================================
procedure cleanUpTempFiles
    if fileReadable(tempPreview$)
        deleteFile: tempPreview$
    endif
    if fileReadable(tempRetrieval$)
        deleteFile: tempRetrieval$
    endif
    if fileReadable(tempSegments$)
        deleteFile: tempSegments$
    endif
    if fileReadable(tempManifest$)
        deleteFile: tempManifest$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(pyLog$)
        deleteFile: pyLog$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ============================================================
# Check Python Dependencies
# ============================================================
clearinfo
writeInfoLine: "=== Semantic Timbre Retrieval ==="
appendInfoLine: "Prompt: ", prompt$
appendInfoLine: "Corpus: ", corpusDir$
appendInfoLine: "[1/4] Detecting Python and Librosa..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile, librosa; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Missing Python dependencies!" + newline$ + "Please run: pip install numpy scipy soundfile librosa"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ============================================================
# Stage 2 — Run Python Engine
# ============================================================
appendInfoLine: "[2/4] Running retrieval engine..."

# Resolve mode string from optionmenu
if retrieval_mode = 1
    modeStr$ = "files"
else
    modeStr$ = "segments"
endif

previewFlag$ = ""
if build_preview_montage
    previewFlag$ = "--do_preview --out_preview_wav """ + tempPreview$ + """ --crossfade_ms " + fixed$(crossfade_ms, 1)
endif

pyCmd$ = pythonCmd$ + " """ + pythonScript$ + """"
pyCmd$ = pyCmd$ + " --corpus """ + corpusDir$ + """"
pyCmd$ = pyCmd$ + " --prompt """ + prompt$ + """"
pyCmd$ = pyCmd$ + " --mode " + modeStr$
pyCmd$ = pyCmd$ + " --top_n " + string$(top_matches)
pyCmd$ = pyCmd$ + " --rules_json """ + rulesJson$ + """"
pyCmd$ = pyCmd$ + " --lexicon_json """ + lexiconJson$ + """"
pyCmd$ = pyCmd$ + " --out_retrieval_csv """ + tempRetrieval$ + """"
pyCmd$ = pyCmd$ + " --out_segments_csv """ + tempSegments$ + """"
pyCmd$ = pyCmd$ + " --out_manifest_csv """ + tempManifest$ + """"
pyCmd$ = pyCmd$ + " --out_stats """ + tempStats$ + """"
pyCmd$ = pyCmd$ + " --min_seg_sec " + fixed$(min_segment_sec, 3)
pyCmd$ = pyCmd$ + " --max_seg_sec " + fixed$(max_segment_sec, 3)
pyCmd$ = pyCmd$ + " --seg_gate_db " + fixed$(segment_gate_dB, 1)
pyCmd$ = pyCmd$ + " --w_semantic " + fixed$(weight_semantic, 3)
pyCmd$ = pyCmd$ + " --w_tag " + fixed$(weight_tag, 3)
pyCmd$ = pyCmd$ + " --w_keyword " + fixed$(weight_keyword, 3)
pyCmd$ = pyCmd$ + " --diversity_penalty " + fixed$(diversity_penalty, 3)
pyCmd$ = pyCmd$ + " " + previewFlag$
pyCmd$ = pyCmd$ + " 2> """ + pyLog$ + """"

runSystem_nocheck: pyCmd$

if not fileReadable(tempRetrieval$)
    errMsg$ = ""
    if fileReadable(pyLog$)
        errMsg$ = readFile$: pyLog$
    endif
    @cleanUpTempFiles
    if errMsg$ = ""
        errMsg$ = "(no error output captured. Check that the corpus folder contains audio files.)"
    endif
    exitScript: "Python engine failed." + newline$ + newline$ + errMsg$
endif

appendInfoLine: "  Engine complete."

# ============================================================
# Stage 3 — Load Output & Report
# ============================================================
appendInfoLine: "[3/4] Reading results..."

retrievalTable = Read Table from comma-separated file: tempRetrieval$
selectObject: retrievalTable
nRanks = Get number of rows

previewSound = 0
if build_preview_montage and fileReadable(tempPreview$)
    Read from file: tempPreview$
    previewSound = selected("Sound")
    promptSlug$ = replace_regex$(prompt$, "[^A-Za-z0-9]+", "_", 0)
    if length(promptSlug$) > 32
        promptSlug$ = left$(promptSlug$, 32)
    endif
    if promptSlug$ = ""
        promptSlug$ = "prompt"
    endif
    Rename: "str_preview_" + promptSlug$
endif

appendInfoLine: ""
appendInfoLine: "=== TOP MATCHES (", nRanks, ") ==="
for r from 1 to nRanks
    selectObject: retrievalTable
    rnk         = Get value: r, "rank"
    itemId$     = Get value: r, "item_id"
    srcFile$    = Get value: r, "source_file"
    startS      = Get value: r, "start_sec"
    endS        = Get value: r, "end_sec"
    scoreTot    = Get value: r, "score_total"
    scoreSem    = Get value: r, "score_semantic"
    scoreTag    = Get value: r, "score_tag"
    matchedT$   = Get value: r, "matched_tags"
    caption$    = Get value: r, "short_caption"
    explain$    = Get value: r, "explanation"
    appendInfoLine: "#", rnk, "  score=", fixed$(scoreTot, 3),
        ... "  [", fixed$(startS, 2), "-", fixed$(endS, 2), "s]"
    appendInfoLine: "    ", srcFile$
    appendInfoLine: "    caption: ", caption$
    if matchedT$ <> ""
        appendInfoLine: "    tags:    ", matchedT$
    endif
    appendInfoLine: "    why:     ", explain$
endfor

# ============================================================
# Parse stats
# ============================================================
statCorpusFiles$ = "0"
statFilesUsed$   = "0"
statItems$       = "0"
statMode$        = modeStr$
statPromptToks$  = "0"
statTopReturned$ = "0"
statTime$        = "0.00"

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)
    @parseStatLine: statsText$, "Corpus files scanned: "
    statCorpusFiles$ = parseStatLine.result$
    @parseStatLine: statsText$, "Files analysed: "
    statFilesUsed$ = parseStatLine.result$
    @parseStatLine: statsText$, "Items indexed: "
    statItems$ = parseStatLine.result$
    @parseStatLine: statsText$, "Prompt tokens resolved: "
    statPromptToks$ = parseStatLine.result$
    @parseStatLine: statsText$, "Top N returned: "
    statTopReturned$ = parseStatLine.result$
    @parseStatLine: statsText$, "Render time: "
    statTime$ = parseStatLine.result$
endif

# ============================================================
# Stage 4 — Visualization
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "[4/4] Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ---------------------------------------------------------
    # Title panel
    # ---------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Semantic Timbre Retrieval##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.50}"
    promptDisp$ = prompt$
    if length(promptDisp$) > 90
        promptDisp$ = left$(promptDisp$, 87) + "..."
    endif
    Text: 0.5, "centre", -1.20, "half",
        ... "prompt: " + promptDisp$
        ... + "   |   mode=" + modeStr$
        ... + "   |   top " + string$(nRanks)

    # ---------------------------------------------------------
    # Target dim bar chart (top, from the best pick's position in dim-space
    # as reconstructed via segments.csv)
    # ---------------------------------------------------------
    # We derive the target profile by averaging the top-3 picks'
    # dims from segments.csv. This gives a visual "what it found".
    segmentsTable = 0
    if fileReadable(tempSegments$)
        segmentsTable = Read Table from comma-separated file: tempSegments$
    endif

    # Build per-rank dim vectors by cross-referencing segments table
    # Dim columns order
    dimNames$# = {"brightness", "noisiness", "tonalness", "stability",
        ... "impulsiveness", "sustain", "roughness", "spatiality"}
    nDim = 8

    # Allocate storage:
    # dimGrid# [rank * nDim + dim]  (rank 1..nRanks, dim 1..nDim)
    maxRanks = nRanks
    totalCells = maxRanks * nDim
    if totalCells < 1
        totalCells = 1
    endif
    dimGrid# = zero#(totalCells)

    if segmentsTable <> 0
        for r from 1 to nRanks
            selectObject: retrievalTable
            itemIdLookup$ = Get value: r, "item_id"
            selectObject: segmentsTable
            segRow = Search column: "segment_id", itemIdLookup$
            if segRow > 0
                for d from 1 to nDim
                    colName$ = dimNames$# [d]
                    v = Get value: segRow, colName$
                    idx = (r - 1) * nDim + d
                    dimGrid# [idx] = v
                endfor
            endif
        endfor
    endif

    # Target-profile bar chart: average of top-3 picks across dims
    Select outer viewport: 0, 8, 0.55, 1.60
    Select inner viewport: 0.6, 7.7, 0.65, 1.55
    Axes: 0, nDim, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, nDim, 0, 1
    Colour: "{0.22, 0.50, 0.82}"
    avgTop = 3
    if avgTop > nRanks
        avgTop = nRanks
    endif
    if avgTop < 1
        avgTop = 1
    endif
    for d from 1 to nDim
        sumv = 0
        for r from 1 to avgTop
            idx = (r - 1) * nDim + d
            sumv = sumv + dimGrid# [idx]
        endfor
        meanv = sumv / avgTop
        Paint rectangle: "{0.22, 0.50, 0.82}", d - 0.85, d - 0.15, 0, meanv
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    for d from 1 to nDim
        lbl$ = dimNames$# [d]
        Text special: d - 0.5, "centre", -0.05, "top", "Helvetica", 6, "0", lbl$
    endfor
    Font size: 7
    Text left: "yes", "0..1"
    Text top: "no", "Retrieved profile (mean of top-" + string$(avgTop) + ")"

    # ---------------------------------------------------------
    # Top matches list + score bars
    # ---------------------------------------------------------
    listTop = 1.70
    listRowH = 0.42
    maxListRows = nRanks
    if maxListRows > 8
        maxListRows = 8
    endif
    listBottom = listTop + listRowH * maxListRows + 0.10

    Select outer viewport: 0, 8, listTop, listBottom
    Select inner viewport: 0.6, 7.7, listTop + 0.05, listBottom - 0.05
    Axes: 0, 1, 0, maxListRows
    Paint rectangle: "{0.98, 0.98, 0.98}", 0, 1, 0, maxListRows

    for r from 1 to maxListRows
        selectObject: retrievalTable
        rnk      = Get value: r, "rank"
        srcFile$ = Get value: r, "source_file"
        startS   = Get value: r, "start_sec"
        endS     = Get value: r, "end_sec"
        scoreT   = Get value: r, "score_total"
        caption$ = Get value: r, "short_caption"

        yTop = maxListRows - (r - 1)
        yBot = maxListRows - r
        yMid = (yTop + yBot) / 2

        # Score bar background
        Paint rectangle: "{0.92, 0.92, 0.94}", 0.25, 0.98, yBot + 0.10, yTop - 0.10
        # Score bar fill
        Paint rectangle: "{0.22, 0.50, 0.82}", 0.25, 0.25 + 0.73 * scoreT, yBot + 0.10, yTop - 0.10

        # Extract base name for display (paths are forward-slash from Python)
        baseName$ = srcFile$
        lastSlash = rindex(baseName$, "/")
        if lastSlash > 0
            baseName$ = mid$(baseName$, lastSlash + 1, length(baseName$) - lastSlash)
        endif
        if length(baseName$) > 28
            baseName$ = left$(baseName$, 25) + "..."
        endif

        shortCaption$ = caption$
        if length(shortCaption$) > 48
            shortCaption$ = left$(shortCaption$, 45) + "..."
        endif

        Colour: "Black"
        Font size: 7
        Text: 0.01, "left", yMid + 0.18, "half", "##" + string$(rnk) + "##  " + baseName$
        Font size: 6
        Colour: "{0.35, 0.35, 0.35}"
        Text: 0.01, "left", yMid - 0.20, "half",
            ... "[" + fixed$(startS, 2) + "-" + fixed$(endS, 2) + "s]  " + shortCaption$
        Colour: "White"
        Font size: 7
        Text: 0.27, "left", yMid, "half", "##" + fixed$(scoreT, 3) + "##"
        Colour: "Black"
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Ranked matches (bar = total score)"

    # ---------------------------------------------------------
    # Per-rank semantic dim heatmap
    # ---------------------------------------------------------
    heatTop = listBottom + 0.10
    heatBottom = heatTop + 1.40
    if heatBottom > 6.40
        heatBottom = 6.40
    endif

    Select outer viewport: 0, 8, heatTop, heatBottom
    Select inner viewport: 0.6, 7.7, heatTop + 0.10, heatBottom - 0.10
    rowsH = maxListRows
    if rowsH < 1
        rowsH = 1
    endif
    Axes: 0, nDim, 0, rowsH
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, nDim, 0, rowsH

    for r from 1 to maxListRows
        yTop = rowsH - (r - 1)
        yBot = rowsH - r
        for d from 1 to nDim
            idx = (r - 1) * nDim + d
            v = dimGrid# [idx]
            # Map v (0..1) to a blue-shaded color
            blue = 0.35 + 0.55 * v
            red  = 0.96 - 0.70 * v
            grn  = 0.96 - 0.45 * v
            Paint rectangle: "{" + fixed$(red, 2) + "," + fixed$(grn, 2) + "," + fixed$(blue, 2) + "}",
                ... d - 1 + 0.03, d - 0.03, yBot + 0.08, yTop - 0.08
        endfor
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    for d from 1 to nDim
        lbl$ = dimNames$# [d]
        Text special: d - 0.5, "centre", -0.05, "top", "Helvetica", 6, "0", lbl$
    endfor
    Font size: 7
    Text left: "yes", "Rank"
    Text top: "no", "Per-rank semantic profile (darker blue = higher value)"

    # ---------------------------------------------------------
    # Summary panel
    # ---------------------------------------------------------
    sumTop = heatBottom + 0.15
    if sumTop > 6.60
        sumTop = 6.60
    endif
    sumBottom = sumTop + 1.20
    if sumBottom > 7.75
        sumBottom = 7.75
    endif

    Select outer viewport: 0, 8, sumTop, sumBottom
    Select inner viewport: 0.6, 7.7, sumTop + 0.05, sumBottom - 0.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.66, "half",
        ... "Mode: " + modeStr$
        ... + "  |  Corpus files: " + statCorpusFiles$
        ... + "  |  Files analysed: " + statFilesUsed$
        ... + "  |  Items indexed: " + statItems$
    Text: 0.02, "left", 0.44, "half",
        ... "Prompt tokens resolved: " + statPromptToks$
        ... + "  |  Top returned: " + statTopReturned$
        ... + "  |  Render time: " + statTime$
    Text: 0.02, "left", 0.22, "half",
        ... "W_sem: " + fixed$(weight_semantic, 2)
        ... + "  |  W_tag: " + fixed$(weight_tag, 2)
        ... + "  |  W_kw: " + fixed$(weight_keyword, 2)
        ... + "  |  Diversity: " + fixed$(diversity_penalty, 2)
        ... + "  |  Gate: " + fixed$(segment_gate_dB, 1) + " dB"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    if segmentsTable <> 0
        removeObject: segmentsTable
    endif

    Font size: 10
    Colour: "Black"
endif

# ============================================================
# Final info + cleanup
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Corpus files scanned: ", statCorpusFiles$
appendInfoLine: "Files analysed:       ", statFilesUsed$
appendInfoLine: "Items indexed:        ", statItems$
appendInfoLine: "Prompt tokens:        ", statPromptToks$
appendInfoLine: "Top returned:         ", statTopReturned$
appendInfoLine: "Render time:          ", statTime$

# Remove retrieval table object (data already reported)
removeObject: retrievalTable

# Select the preview sound (if any) as the final selection
if previewSound <> 0
    selectObject: previewSound
endif

@cleanUpTempFiles

if play_preview and previewSound <> 0
    Play
endif

# ============================================================
# Procedures
# ============================================================

procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nl = index(.rest$, newline$)
        if .nl > 0
            .result$ = left$(.rest$, .nl - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc
