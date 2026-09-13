# ============================================================
# Praat AudioTools - LatentCounterpoint.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5 (2026) - click-safe reconstruction + latent-space process figure
#
# Changelog v1.5:
#   - The figure now shows the latent space the tool is named for: a PCA map of
#     the event corpus with each voice's selected-event path, plus clean
#     autoencoder reconstruction loss and per-step voice separation.
#   - Intensity segmentation now cuts at local minima (valleys between gestures)
#     rather than at intensity maxima inside the gestures themselves.
#   - Pairs with latent_counterpoint.py v1.5: phase-safe analysis/render fold-down,
#     duration-aware physics step count, full timeline/latent export.
#   - The process-architecture diagram, the QC box and the agent-profile box
#     were three prose panels filling half the canvas; they collapse into one
#     summary and the space goes to a per-voice event-usage matrix.
#   - Fixed: the polyphonic timeline drew its lowest voice below the panel's
#     ymin, and Paint rectangle does not clip, so it spilled over the summary.
#   - Fixed: no panel drew axis numbers; the output panel's axis label was
#     painted over by the next panel; "adaptive_equal_power" rendered with a
#     subscript because _ is Picture markup.
#
# Changelog v1.4:
#   - Reconstruction uses adaptive local equal-power splices; removed global
#     median click smoothing that could erase genuine transients.
#   - Short/simple sources with one latent event no longer propagate NaN scale.
#   - Phase-safe multichannel event fold-down and 32-bit FLOAT output.
#   - Timeline mirrors actual adaptive splice positions; visualization now
#     emphasizes the real analysis->latent->physics->voice process.
#   - Removed unused Pitch/Harmonicity/event-descriptor calculations in Praat;
#     only intensity segmentation + start/end event times feed this engine.
#
# Changelog v1.3:
#   - counterpoint_rigidity is now a real, monotonic control over how
#     independent the voices are. Previously the rigidity knob drove only
#     the spatial repulsion force, which is capped (at speed*3) right when
#     agents are closest and clamped by max-velocity, so it was swamped by
#     the agent-profile attractions and the LRU memory: sweeping rigidity
#     0 -> 2 barely changed voice separation (~0.83 -> 0.88 x median, non-
#     monotonic) and the TightCP vs FreeScatter presets were nearly
#     identical. A graded Gaussian proximity penalty is now applied at event
#     selection time, scaled by rigidity, so each voice avoids events near
#     what the other voices just chose. Separation now rises monotonically
#     with rigidity (0.83 -> 1.07 x median) and the presets are genuinely
#     distinct, while per-voice diversity is preserved. The existing physics
#     repulsion is kept (it still shapes trajectories). Verified by sweeping
#     the live engine.
#   - Synced the version string across header, form title, and banner.
#
# Changelog v1.2:
#   - Viz: title/subtitle split into separate viewport bands (subtitle was
#     at y=-1.2, rendering over the input waveform).
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   The Latent Counterpoint
#
#   Trains an autoencoder on-the-fly to learn a latent space from
#   event-level audio patches, then deploys multiple agents that
#   navigate the latent space simultaneously with counterpoint forces
#   (attraction, repulsion, inertia, jitter) to produce polyphonic
#   recombination of the input material.
#
#   Agent profiles:
#   - Cantus:  heavy, slow, gravitates to center of gravity
#   - Florid:  light, fast, attracted to peripheral/atypical sounds
#   - Shadow:  mirrors Cantus with temporal lag + inverted coordinates
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

# ---- OS-Specific Python Discovery ----
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

# ---- PATHS ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/latent_counterpoint.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/latent_counterpoint.py"
endif
if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: latent_counterpoint.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_latcp_input.wav"
tempCSV$     = temporaryDirectory$ + "/temp_latcp_events.csv"
tempOutput$  = temporaryDirectory$ + "/temp_latcp_output.wav"
tempStats$   = temporaryDirectory$ + "/temp_latcp_stats.txt"
probeMarker$ = temporaryDirectory$ + "/temp_latcp_probe.ok"

# Replace backslashes for the Python inline probe
probeMarkerJ$ = replace_regex$(probeMarker$, "\\", "/", 0)

# ---- CLEANUP PROCEDURE ----
procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempCSV$)
        deleteFile: tempCSV$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
    if fileReadable(tempStats$)
        deleteFile: tempStats$
    endif
    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif
endproc

@cleanUpTempFiles

# ---- FORM ----
form The Latent Counterpoint v1.5
    optionmenu Preset: 1
        option Custom
        option Duo (2 voices)
        option Trio (3 voices)
        option Quartet (4 voices)
        option Dense ensemble (5 voices)
        option Tight counterpoint
        option Free scatter
    integer Number_of_agents 3
    integer Latent_size 8
    real Counterpoint_rigidity 0.5
    real Speed 0.5
    real Duration_(0_=_original) 0
    integer Seed 42
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- PRESETS ----
if preset = 2
    number_of_agents = 2
    latent_size = 6
    counterpoint_rigidity = 0.4
    speed = 0.4
    presetName$ = "Duo"
elsif preset = 3
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 0.5
    speed = 0.5
    presetName$ = "Trio"
elsif preset = 4
    number_of_agents = 4
    latent_size = 10
    counterpoint_rigidity = 0.6
    speed = 0.5
    presetName$ = "Quartet"
elsif preset = 5
    number_of_agents = 5
    latent_size = 12
    counterpoint_rigidity = 0.7
    speed = 0.6
    presetName$ = "DenseEnsemble"
elsif preset = 6
    # TightCP - tight, interlocked counterpoint: LOW rigidity so voices
    # stay close (rigidity drives REPULSION, so low = cohesive), with a
    # deliberate, controlled speed.
    number_of_agents = 3
    latent_size = 8
    counterpoint_rigidity = 0.15
    speed = 0.4
    presetName$ = "TightCP"
elsif preset = 7
    # FreeScatter - voices fly apart: HIGH rigidity = strong mutual
    # repulsion, fast speed -> wide, scattered, independent lines.
    number_of_agents = 3
    latent_size = 10
    counterpoint_rigidity = 1.5
    speed = 1.0
    presetName$ = "FreeScatter"
else
    presetName$ = "Custom"
endif

# Clamp
if number_of_agents < 2
    number_of_agents = 2
endif
if number_of_agents > 6
    number_of_agents = 6
endif
if latent_size < 2
    latent_size = 2
endif
if latent_size > 32
    latent_size = 32
endif

# ---- INFO ----
clearinfo
writeInfoLine:  "=== The Latent Counterpoint v1.5 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Agents:     ", number_of_agents
appendInfoLine: "Latent:     ", latent_size
appendInfoLine: "Rigidity:   ", fixed$(counterpoint_rigidity, 2)
appendInfoLine: "Speed:      ", fixed$(speed, 2)
appendInfoLine: "Duration:   ", if duration > 0 then fixed$(duration, 1) else "original" fi
appendInfoLine: "Seed:       ", seed
appendInfoLine: ""

# ---- CAPTURE ORIGINAL STATS ----
selectObject: sound
dur = Get total duration
sr  = Get sampling frequency
nChannels = Get number of channels
rms_orig = Get root-mean-square: 0, 0

if duration <= 0
    duration = dur
endif

appendInfoLine: "Duration: ", fixed$(dur, 2), " s | SR: ", sr, " Hz | Channels: ", nChannels
appendInfoLine: ""

# ===========================================================================
# Stage 1 — Detect Python Dependencies
# ===========================================================================
appendInfoLine: "[1/5] Detecting Python dependencies..."

probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open('""" + probeMarkerJ$ + """', 'w').write('ok')"""
runSystem_nocheck: probeCmd$

if not fileReadable(probeMarker$)
    @cleanUpTempFiles
    exitScript: "Python not found or dependencies missing." + newline$ + "Please install: pip install numpy scipy soundfile"
endif

deleteFile: probeMarker$
appendInfoLine: "  Python found: ", pythonCmd$

# ===========================================================================
# Stage 2 — Event Segmentation
# ===========================================================================
appendInfoLine: "[2/5] Segmenting events..."

minEventDur = 0.200
maxEventDur = 3.000

selectObject: sound
if nChannels > 1
    Extract one channel: 1
    analysisMono = selected("Sound")
else
    Copy: "analysisMono"
    analysisMono = selected("Sound")
endif

# Intensity is the only Praat analysis required here: it drives event
# segmentation.  Pitch/HNR/attack descriptors were formerly exported but
# never consumed by the Python engine, whose latent features are log-mel.
selectObject: analysisMono
intObj = To Intensity: 100, 0.01, "yes"

selectObject: intObj
intMatrix = Down to Matrix
intSound = To Sound (slice): 1
selectObject: intSound
# Event boundaries belong in intensity valleys between gestures, not on the
# local maxima inside the gestures.  Extrema arguments: include maxima=no,
# include minima=yes.  minEventDur below suppresses clusters of tiny valleys.
ppObj = To PointProcess (extrema): 1, "no", "yes", "Sinc70"

selectObject: ppObj
nValleys = Get number of points

bound_1 = 0
bound_2 = dur
iBound = 3
for iValley from 1 to nValleys
    selectObject: ppObj
    valleyT = Get time from index: iValley
    bound_'iBound' = valleyT
    iBound = iBound + 1
endfor
nBounds = iBound - 1

for i from 1 to nBounds
    for j from i + 1 to nBounds
        if bound_'j' < bound_'i'
            tmpVal = bound_'i'
            bound_'i' = bound_'j'
            bound_'j' = tmpVal
        endif
    endfor
endfor

nFinal = 0
prevT = -1
for i from 1 to nBounds
    thisT = bound_'i'
    if thisT - prevT >= minEventDur
        nFinal = nFinal + 1
        final_'nFinal' = thisT
        prevT = thisT
    endif
endfor

if nFinal > 0
    lastFinal = final_'nFinal'
    if dur - lastFinal > 0.050
        nFinal = nFinal + 1
        final_'nFinal' = dur
    else
        final_'nFinal' = dur
    endif
else
    nFinal = 2
    final_1 = 0
    final_2 = dur
endif

nEvents = 0
for i from 1 to nFinal - 1
    evStart = final_'i'
    iNext = i + 1
    evEnd = final_'iNext'
    evDur = evEnd - evStart

    if evDur > maxEventDur
        nChunks = ceiling(evDur / maxEventDur)
        chunkDur = evDur / nChunks
        for iChunk from 0 to nChunks - 1
            nEvents = nEvents + 1
            evS_'nEvents' = evStart + iChunk * chunkDur
            if iChunk = nChunks - 1
                evE_'nEvents' = evEnd
            else
                evE_'nEvents' = evStart + (iChunk + 1) * chunkDur
            endif
        endfor
    elsif evDur >= minEventDur
        nEvents = nEvents + 1
        evS_'nEvents' = evStart
        evE_'nEvents' = evEnd
    endif
endfor

if nEvents < 2
    nEvents = 1
    evS_1 = 0
    evE_1 = dur
endif

appendInfoLine: "  Found ", nEvents, " events"

# ===========================================================================
# Stage 3 — Extract Features + Export
# ===========================================================================
appendInfoLine: "[3/5] Extracting features..."

Create Table with column names: "eventFeatures", nEvents, "start_time end_time label"
eventTable = selected("Table")

for iEv from 1 to nEvents
    t1 = evS_'iEv'
    t2 = evE_'iEv'
    selectObject: eventTable
    Set numeric value: iEv, "start_time", t1
    Set numeric value: iEv, "end_time", t2
    Set string value: iEv, "label", "ev" + string$(iEv)
endfor

appendInfoLine: "  Exporting temp files..."
selectObject: sound
Save as WAV file: tempInput$
selectObject: eventTable
Save as comma-separated file: tempCSV$

removeObject: analysisMono, intObj
removeObject: intMatrix, intSound, ppObj, eventTable

# ===========================================================================
# Stage 4 — Call Python
# ===========================================================================
appendInfoLine: "[4/5] Running Python engine..."
appendInfoLine: "  (Training AE + running ", number_of_agents, "-voice counterpoint)"

pythonCall$ = pythonCmd$ + " """ + pythonScript$ + """"
    ... + " """ + tempInput$ + """"
    ... + " """ + tempCSV$ + """"
    ... + " """ + tempOutput$ + """"
    ... + " """ + tempStats$ + """"
    ... + " " + string$(number_of_agents)
    ... + " " + string$(latent_size)
    ... + " " + fixed$(counterpoint_rigidity, 4)
    ... + " " + fixed$(speed, 4)
    ... + " " + fixed$(duration, 4)
    ... + " " + string$(seed)

# Remove any stale output/stats from a PREVIOUS run before calling Python.
# The temp filenames are fixed, so without this a crashed run would leave
# the old files in place and the fileReadable() check below would pass on
# stale data - silently importing a previous result as if it were new.
if fileReadable(tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable(tempStats$)
    deleteFile: tempStats$
endif

runSystem_nocheck: pythonCall$

if not fileReadable(tempOutput$)
    @cleanUpTempFiles
    exitScript: "Python counterpoint engine failed." + newline$ + "Check terminal for error details."
endif

# ===========================================================================
# Stage 5 — Import Result
# ===========================================================================
appendInfoLine: "[5/5] Importing result..."

Read from file: tempOutput$
Rename: soundName$ + "_cp"
resultSound = selected("Sound")

selectObject: resultSound
rms_out = Get root-mean-square: 0, 0
durOut = Get total duration

# ===========================================================================
# Read Stats
# ===========================================================================
nEvStat$ = "?"
nAgentsStat$ = "?"
outDurStat$ = "?"
finalLoss$ = "?"
initialLoss$ = "?"
meanEvDur$ = "?"
totalUnique$ = "?"
warningStat$ = ""
meanSep$ = "?"
phaseSafe$ = "?"
spliceMode$ = "?"

for iA from 0 to 5
    agProfile_'iA'$ = "?"
    agSteps_'iA'$ = "?"
    agUnique_'iA'$ = "?"
    agRepRate_'iA'$ = "?"
    agTravel_'iA'$ = "?"
    agPeriph_'iA'$ = "?"
    agTop_'iA'$ = "?"
endfor

nUnisonPairs = 0
for iA from 0 to 5
    for iB from iA + 1 to 5
        unisonRate_'iA'_'iB'$ = "?"
    endfor
endfor

for iAT from 0 to 5
    agNBlocks_'iAT' = 0
endfor

nLat = 0
nLoss = 0
nSep = 0
nUseEvents = 0
latShare$ = "?"
latCx = 0
latCy = 0
latXlo = -1
latXhi = 1
latYlo = -1
latYhi = 1
lossHi = 1
lossSteps = 1
sepHi = 1
useHi = 1

if fileReadable(tempStats$)
    statsText$ = readFile$(tempStats$)

    @parseStatLine: statsText$, "n_events="
    nEvStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "n_agents="
    nAgentsStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "output_duration="
    outDurStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "final_loss="
    finalLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "initial_loss="
    initialLoss$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_event_dur="
    meanEvDur$ = parseStatLine.result$
    @parseStatLine: statsText$, "total_unique_events="
    totalUnique$ = parseStatLine.result$
    @parseStatLine: statsText$, "warning="
    warningStat$ = parseStatLine.result$
    @parseStatLine: statsText$, "mean_separation_ratio="
    meanSep$ = parseStatLine.result$
    @parseStatLine: statsText$, "phase_safe_events="
    phaseSafe$ = parseStatLine.result$
    @parseStatLine: statsText$, "splice_mode="
    spliceMode$ = parseStatLine.result$

    for iA from 0 to number_of_agents - 1
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_profile="
        agProfile_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_steps="
        agSteps_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_unique="
        agUnique_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_rep_rate="
        agRepRate_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_avg_travel="
        agTravel_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_mean_periphery="
        agPeriph_'iA'$ = parseStatLine.result$
        @parseStatLine: statsText$, "agent_" + string$(iA) + "_top_event="
        agTop_'iA'$ = parseStatLine.result$
    endfor

    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            @parseStatLine: statsText$, "unison_rate_" + string$(iA) + "_" + string$(iB) + "="
            unisonRate_'iA'_'iB'$ = parseStatLine.result$
        endfor
    endfor

    # ── Parse per-agent polyphonic timeline blocks ──
    for iAT from 0 to number_of_agents - 1
        @parseStatLine: statsText$, "ag_" + string$(iAT) + "_n_blocks="
        nBl$ = parseStatLine.result$
        agNBlocks_'iAT' = 0
        if nBl$ <> "?"
            agNBlocks_'iAT' = number(nBl$)
        endif
        for iBl from 0 to agNBlocks_'iAT' - 1
            @parseStatLine: statsText$, "ag_" + string$(iAT) + "_bl_" + string$(iBl) + "="
            blRaw$ = parseStatLine.result$
            agBl_'iAT'_'iBl'_ev = 0
            agBl_'iAT'_'iBl'_s = 0
            agBl_'iAT'_'iBl'_e = 0
            if blRaw$ <> "?"
                comma1 = index(blRaw$, ",")
                if comma1 > 0
                    agBl_'iAT'_'iBl'_ev = number(left$(blRaw$, comma1 - 1))
                    rest$ = mid$(blRaw$, comma1 + 1, length(blRaw$) - comma1)
                    comma2 = index(rest$, ",")
                    if comma2 > 0
                        agBl_'iAT'_'iBl'_s = number(left$(rest$, comma2 - 1))
                        agBl_'iAT'_'iBl'_e = number(mid$(rest$, comma2 + 1, length(rest$) - comma2))
                    endif
                endif
            endif
        endfor
    endfor

    # ── Latent map: events projected to two dimensions, plus the centre ──
    @parseStatLine: statsText$, "n_lat="
    if parseStatLine.result$ <> "?"
        nLat = number(parseStatLine.result$)
    endif
    @parseStatLine: statsText$, "latent_pc_share="
    latShare$ = parseStatLine.result$
    @parseStatLine: statsText$, "lat_center="
    if parseStatLine.result$ <> "?"
        crow$ = parseStatLine.result$
        cc = index(crow$, ",")
        if cc > 0
            latCx = number(left$(crow$, cc - 1))
            latCy = number(mid$(crow$, cc + 1, length(crow$) - cc))
        endif
    endif
    # latOf_ maps a source event index back to its row in the drawn map, so a
    # voice path can be traced from the timeline blocks without a second export.
    for iEvL from 0 to nEvents - 1
        latOf_'iEvL' = -1
    endfor
    for iL from 0 to nLat - 1
        @parseStatLine: statsText$, "lat_" + string$(iL) + "="
        lrow$ = parseStatLine.result$
        if lrow$ <> "?"
            k1 = index(lrow$, ",")
            latIdx = number(left$(lrow$, k1 - 1))
            r1$ = mid$(lrow$, k1 + 1, length(lrow$) - k1)
            k2 = index(r1$, ",")
            latX_'iL' = number(left$(r1$, k2 - 1))
            r2$ = mid$(r1$, k2 + 1, length(r1$) - k2)
            k3 = index(r2$, ",")
            latY_'iL' = number(left$(r2$, k3 - 1))
            latP_'iL' = number(mid$(r2$, k3 + 1, length(r2$) - k3))
            if latIdx >= 0 and latIdx < nEvents
                latOf_'latIdx' = iL
            endif
            if iL = 0
                latXlo = latX_'iL'
                latXhi = latX_'iL'
                latYlo = latY_'iL'
                latYhi = latY_'iL'
            else
                latXlo = min(latXlo, latX_'iL')
                latXhi = max(latXhi, latX_'iL')
                latYlo = min(latYlo, latY_'iL')
                latYhi = max(latYhi, latY_'iL')
            endif
        endif
    endfor
    if nLat >= 2
        latXlo = min(latXlo, latCx)
        latXhi = max(latXhi, latCx)
        latYlo = min(latYlo, latCy)
        latYhi = max(latYhi, latCy)
    endif
    # A single far-flung event can squash the rest of a large corpus into one
    # blob, so on anything but a small corpus frame the map on mean +/- 3 sd and
    # clamp the stragglers onto the border rather than let them set the scale.
    if nLat >= 20
        sxSum = 0
        sySum = 0
        for iL from 0 to nLat - 1
            sxSum = sxSum + latX_'iL'
            sySum = sySum + latY_'iL'
        endfor
        sxMean = sxSum / nLat
        syMean = sySum / nLat
        sxVar = 0
        syVar = 0
        for iL from 0 to nLat - 1
            sxVar = sxVar + (latX_'iL' - sxMean) ^ 2
            syVar = syVar + (latY_'iL' - syMean) ^ 2
        endfor
        sxSd = sqrt(sxVar / nLat)
        sySd = sqrt(syVar / nLat)
        if sxSd > 0
            latXlo = max(latXlo, sxMean - 3 * sxSd)
            latXhi = min(latXhi, sxMean + 3 * sxSd)
        endif
        if sySd > 0
            latYlo = max(latYlo, syMean - 3 * sySd)
            latYhi = min(latYhi, syMean + 3 * sySd)
        endif
    endif

    # ── Autoencoder training curve ──
    @parseStatLine: statsText$, "n_loss="
    if parseStatLine.result$ <> "?"
        nLoss = number(parseStatLine.result$)
    endif
    for iLo from 0 to nLoss - 1
        @parseStatLine: statsText$, "loss_" + string$(iLo) + "="
        lrow$ = parseStatLine.result$
        lossStep_'iLo' = iLo
        lossVal_'iLo' = 0
        if lrow$ <> "?"
            k1 = index(lrow$, ",")
            if k1 > 0
                lossStep_'iLo' = number(left$(lrow$, k1 - 1))
                lossVal_'iLo' = number(mid$(lrow$, k1 + 1, length(lrow$) - k1))
                lossHi = max(lossHi * (iLo > 0), lossVal_'iLo')
                lossSteps = max(lossSteps, lossStep_'iLo')
            endif
        endif
    endfor

    # ── Voice separation per physics step ──
    @parseStatLine: statsText$, "n_sep="
    if parseStatLine.result$ <> "?"
        nSep = number(parseStatLine.result$)
    endif
    sepHi = 0
    for iSp from 0 to nSep - 1
        @parseStatLine: statsText$, "sep_" + string$(iSp) + "="
        srow$ = parseStatLine.result$
        sepVal_'iSp' = 0
        if srow$ <> "?"
            k1 = index(srow$, ",")
            if k1 > 0
                sepVal_'iSp' = number(mid$(srow$, k1 + 1, length(srow$) - k1))
                sepHi = max(sepHi, sepVal_'iSp')
            endif
        endif
    endfor
    sepHi = max(sepHi, 1)

    # ── Per-voice event usage ──
    @parseStatLine: statsText$, "n_use_events="
    if parseStatLine.result$ <> "?"
        nUseEvents = number(parseStatLine.result$)
    endif
    useHi = 1
    for iAT from 0 to number_of_agents - 1
        @parseStatLine: statsText$, "use_" + string$(iAT) + "="
        urow$ = parseStatLine.result$
        for iEv2 from 0 to nUseEvents - 1
            uk = iAT * nUseEvents + iEv2
            useCount_'uk' = 0
            if urow$ <> ""
                up = index(urow$, ",")
                if up > 0
                    utxt$ = left$(urow$, up - 1)
                    urow$ = mid$(urow$, up + 1, length(urow$) - up)
                else
                    utxt$ = urow$
                    urow$ = ""
                endif
                useCount_'uk' = number(utxt$)
                if useCount_'uk' = undefined
                    useCount_'uk' = 0
                endif
                useHi = max(useHi, useCount_'uk')
            endif
        endfor
    endfor
endif

###############################################################################
# VISUALIZATION
#
# The tool is named for a latent space that the figure never showed. It does
# now, and the three prose boxes that filled half the old canvas (process
# architecture, QC, agent profiles) collapse into one summary so the space can
# carry measurements instead:
#
#   1  source with the event boundaries that were actually cut;
#   2  the rendered result on the same scale;
#   3  the latent space itself, with each voice's selected-event path;
#   4  clean reconstruction loss, and how far apart the voices stayed;
#   5  which events each voice took, and the polyphonic timeline.
###############################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    vizL = 0.60
    vizR = 7.70
    railX = -0.040

    selectObject: sound
    srcHi = Get maximum: 0, 0, "None"
    srcLo = Get minimum: 0, 0, "None"
    selectObject: resultSound
    outHi = Get maximum: 0, 0, "None"
    outLo = Get minimum: 0, 0, "None"
    ampViz = max(abs(srcHi), abs(srcLo))
    ampViz = max(ampViz, max(abs(outHi), abs(outLo)))
    if ampViz < 0.001
        ampViz = 0.001
    endif
    axisDur = max(dur, durOut)
    @snapStep: axisDur, 8
    snapT = snapStep.step

    hasLatent = 0
    if nLat >= 2
        hasLatent = 1
    endif
    hasLoss = 0
    if nLoss >= 2
        hasLoss = 1
    endif
    hasSep = 0
    if nSep >= 2
        hasSep = 1
    endif
    hasUse = 0
    if nUseEvents >= 1
        hasUse = 1
    endif

    # --- layout --------------------------------------------------------------
    yInA = 0.80
    yInB = 1.45
    yOutA = 1.47
    yOutB = 2.12

    yLatA = 2.75
    yLatB = 4.85
    if hasLatent = 0
        yLatA = 2.62
        yLatB = 2.62
    endif

    yCurveA = yLatB + 0.50
    yCurveB = yCurveA + 0.85
    if hasLoss = 0 and hasSep = 0
        yCurveA = yLatB
        yCurveB = yLatB
    endif

    yUseA = yCurveB + 0.50
    yUseB = yUseA + 0.70
    if hasUse = 0
        yUseA = yCurveB
        yUseB = yCurveB
    endif

    yTlA = yUseB + 0.32
    yTlB = yTlA + 0.95
    ySumA = yTlB + 0.54
    # header + 3 analysis lines + one line per voice + 2 tail lines
    sumRows = 6 + number_of_agents
    sumPitch = 0.115
    sumH = 0.12 + sumPitch * sumRows
    ySumB = ySumA + sumH
    canvasH = ySumB + 0.15

    Erase all
    Colour: "Black"
    Line width: 1
    Solid line

    # --- title ---------------------------------------------------------------
    @sanitize: soundName$
    hdrName$ = sanitize.out$
    Font size: 13
    Select inner viewport: vizL, vizR, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.74, "half", "##The Latent Counterpoint##"
    Font size: 7
    Select inner viewport: vizL, vizR, 0.05, 0.60
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    Text: 0.5, "centre", 0.24, "half", hdrName$ + "   |   " + presetName$
        ... + "   |   " + string$(number_of_agents) + " voices"
        ... + "   |   rigidity " + fixed$(counterpoint_rigidity, 2)
        ... + ", speed " + fixed$(speed, 2)
        ... + ", latent " + string$(latent_size) + "-D, seed " + string$(seed)
    Colour: "Black"

    # --- 1: source with the event cuts ---------------------------------------
    @caption: vizL, vizR, yInA, yInB, "1  Source and the " + string$(nEvents) + " event boundaries the engine was given, against the rendered result on the same scale"
    Font size: 7
    Select inner viewport: vizL, vizR, yInA, yInB
    selectObject: sound
    if nChannels > 1
        Extract one channel: 1
    else
        Copy: "lcVizIn"
    endif
    tmpInWave = selected("Sound")
    Colour: "{0.55, 0.55, 0.58}"
    Draw: 0, axisDur, -ampViz, ampViz, "no", "Curve"
    removeObject: tmpInWave
    Select inner viewport: vizL, vizR, yInA, yInB
    Axes: 0, axisDur, -ampViz, ampViz
    Colour: "{0.80, 0.30, 0.30}"
    for iEv from 1 to nEvents
        evBound = evS_'iEv'
        if evBound > 0 and evBound < dur
            Draw line: evBound, -ampViz, evBound, ampViz
        endif
    endfor
    Colour: "Black"
    Select inner viewport: vizL, vizR, yInA, yInB
    Axes: 0, axisDur, -ampViz, ampViz
    Draw inner box
    Marks bottom every: 1, snapT, "no", "yes", "no"
    @rail: yInA, yInB, "Source"

    # --- 2: result -----------------------------------------------------------
    Font size: 7
    Select inner viewport: vizL, vizR, yOutA, yOutB
    selectObject: resultSound
    Extract one channel: 1
    tmpOutWave = selected("Sound")
    Colour: "{0.20, 0.40, 0.75}"
    Draw: 0, axisDur, -ampViz, ampViz, "no", "Curve"
    removeObject: tmpOutWave
    Colour: "Black"
    Select inner viewport: vizL, vizR, yOutA, yOutB
    Axes: 0, axisDur, -ampViz, ampViz
    Draw inner box
    Marks bottom every: 1, snapT, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @rail: yOutA, yOutB, "Result L"

    # --- 3: the latent space and the voices' paths through it ----------------
    if hasLatent
        @caption: vizL, vizR, yLatA, yLatB, "3  Latent event space - dots are source events; coloured lines connect each voice's selected events; x marks the centre"
        padL = max(0.05, 0.08 * (latXhi - latXlo))
        padM = max(0.05, 0.08 * (latYhi - latYlo))
        lx1 = latXlo - padL
        lx2 = latXhi + padL
        ly1 = latYlo - padM
        ly2 = latYhi + padM
        lxIn1 = lx1 + 0.012 * (lx2 - lx1)
        lxIn2 = lx2 - 0.012 * (lx2 - lx1)
        lyIn1 = ly1 + 0.012 * (ly2 - ly1)
        lyIn2 = ly2 - 0.012 * (ly2 - ly1)
        latOff = 0
        for iL from 0 to nLat - 1
            if latX_'iL' < lxIn1 or latX_'iL' > lxIn2 or latY_'iL' < lyIn1 or latY_'iL' > lyIn2
                latOff = latOff + 1
            endif
            latX_'iL' = min(lxIn2, max(lxIn1, latX_'iL'))
            latY_'iL' = min(lyIn2, max(lyIn1, latY_'iL'))
        endfor
        latCx = min(lxIn2, max(lxIn1, latCx))
        latCy = min(lyIn2, max(lyIn1, latCy))
        Font size: 7
        Select inner viewport: vizL, vizR, yLatA, yLatB
        Axes: lx1, lx2, ly1, ly2
        Paint rectangle: "{1.00, 1.00, 1.00}", lx1, lx2, ly1, ly2

        # Voice paths first, events on top, so a dot is never hidden by a line.
        Line width: 1
        for iAT from 0 to number_of_agents - 1
            @agentCol: iAT
            # Paths run lighter than the legend swatch so a dense corpus does
            # not disappear under its own trajectories.
            Colour: "{" + fixed$(agentCol.r + (1 - agentCol.r) * 0.35, 3)
                ... + ", " + fixed$(agentCol.g + (1 - agentCol.g) * 0.35, 3)
                ... + ", " + fixed$(agentCol.b + (1 - agentCol.b) * 0.35, 3) + "}"
            nBl = agNBlocks_'iAT'
            prevSet = 0
            for iBl from 0 to nBl - 1
                blEv = agBl_'iAT'_'iBl'_ev
                lk = latOf_'blEv'
                if lk >= 0
                    thisX = latX_'lk'
                    thisY = latY_'lk'
                    if prevSet = 1
                        Draw line: prevX, prevY, thisX, thisY
                    endif
                    prevX = thisX
                    prevY = thisY
                    prevSet = 1
                endif
            endfor
        endfor

        Select inner viewport: vizL, vizR, yLatA, yLatB
        Axes: lx1, lx2, ly1, ly2
        # All event coordinates are parsed so voice paths stay exact. For very
        # large corpora draw a sparse background cloud only; selected-event paths
        # still use the full mapping.
        latDrawStride = max(1, ceiling(nLat / 800))
        for iL from 0 to nLat - 1
            if iL - latDrawStride * floor(iL / latDrawStride) = 0
                # Dot size is the event's periphery score, the quantity the Florid
                # profile is attracted to and the Cantus profile is not.
                dotD = 0.7 + 1.6 * min(1, max(0, latP_'iL'))
                Paint circle (mm): "{0.62, 0.62, 0.68}", latX_'iL', latY_'iL', dotD
            endif
        endfor

        Select inner viewport: vizL, vizR, yLatA, yLatB
        Axes: lx1, lx2, ly1, ly2
        Line width: 2
        Colour: "{0.20, 0.20, 0.25}"
        crossX = 0.018 * (lx2 - lx1)
        crossY = 0.018 * (ly2 - ly1)
        Draw line: latCx - crossX, latCy - crossY, latCx + crossX, latCy + crossY
        Draw line: latCx - crossX, latCy + crossY, latCx + crossX, latCy - crossY
        Line width: 1

        Colour: "Black"
        Select inner viewport: vizL, vizR, yLatA, yLatB
        Axes: lx1, lx2, ly1, ly2
        Draw inner box
        @snapStep: lx2 - lx1, 5
        Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        @snapStep: ly2 - ly1, 4
        Marks left every: 1, snapStep.step, "yes", "yes", "no"

        # Voice legend, on a plate so a path cannot run through the text.
        Font size: 6
        Select inner viewport: vizL, vizR, yLatA, yLatB
        Axes: 0, 1, 0, 1
        legTop = 0.985
        legBot = legTop - 0.052 * number_of_agents - 0.015
        Paint rectangle: "{1.00, 1.00, 1.00}", 0.735, 0.998, legBot, legTop
        for iAT from 0 to number_of_agents - 1
            @agentCol: iAT
            legY = legTop - 0.030 - 0.052 * iAT
            Colour: agentCol.col$
            Line width: 2
            Draw line: 0.748, legY, 0.786, legY
            Line width: 1
            @sanitize: agProfile_'iAT'$
            Text: 0.794, "left", legY, "half", "voice " + string$(iAT) + "  " + sanitize.out$
        endfor
        Colour: "{0.45, 0.45, 0.52}"
        shareTxt$ = "PC1 + PC2 hold " + latShare$ + " of the " + string$(latent_size) + "-D latent variance"
        if latOff > 0
            shareTxt$ = shareTxt$ + "   |   " + string$(latOff) + " off-scale, drawn on the border"
        endif
        Text: 0.015, "left", 0.030, "half", shareTxt$
        Colour: "Black"
        Font size: 6
        Select inner viewport: vizL, vizR, yLatA, yLatB
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "latent PC1"
        Text left: "yes", "latent PC2"
    endif

    # --- 4: clean reconstruction loss, and how far apart did voices stay? --
    if hasLoss or hasSep
        @caption: vizL, 3.90, yCurveA, yCurveB, "4a  Autoencoder clean reconstruction loss"
        Font size: 7
        Select inner viewport: vizL, 3.90, yCurveA, yCurveB
        lossTop = max(1e-6, lossHi * 1.08)
        Axes: 0, lossSteps, 0, lossTop
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, lossSteps, 0, lossTop
        if hasLoss
            Colour: "{0.20, 0.40, 0.75}"
            Line width: 2
            for iLo from 1 to nLoss - 1
                iPrev = iLo - 1
                Draw line: lossStep_'iPrev', lossVal_'iPrev', lossStep_'iLo', lossVal_'iLo'
            endfor
            Line width: 1
        endif
        Colour: "Black"
        Select inner viewport: vizL, 3.90, yCurveA, yCurveB
        Axes: 0, lossSteps, 0, lossTop
        Draw inner box
        @snapStep: lossTop, 3
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        @snapStep: lossSteps, 4
        Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: vizL, 3.90, yCurveA, yCurveB
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "training step"
        Text left: "yes", "clean reconstruction loss"

        @caption: 4.35, vizR, yCurveA, yCurveB, "4b  Simultaneous voice separation, in units of the corpus median distance"
        Font size: 7
        Select inner viewport: 4.35, vizR, yCurveA, yCurveB
        sepTop = max(0.2, sepHi * 1.12)
        Axes: 0, max(1, nSep - 1), 0, sepTop
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, max(1, nSep - 1), 0, sepTop
        Dotted line
        Colour: "{0.75, 0.75, 0.80}"
        Draw line: 0, 1, max(1, nSep - 1), 1
        Solid line
        Select inner viewport: 4.35, vizR, yCurveA, yCurveB
        Axes: 0, max(1, nSep - 1), 0, sepTop
        if hasSep
            Colour: "{0.45, 0.35, 0.55}"
            Line width: 2
            for iSp from 1 to nSep - 1
                iPrev = iSp - 1
                Draw line: iPrev, sepVal_'iPrev', iSp, sepVal_'iSp'
            endfor
            Line width: 1
        endif
        Colour: "Black"
        Select inner viewport: 4.35, vizR, yCurveA, yCurveB
        Axes: 0, max(1, nSep - 1), 0, sepTop
        Draw inner box
        @snapStep: sepTop, 3
        Marks left every: 1, snapStep.step, "yes", "yes", "no"
        @snapStep: max(1, nSep - 1), 5
        Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: 4.35, vizR, yCurveA, yCurveB
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "physics step   -   dotted line = one median distance"
        Text left: "yes", "separation"
    endif

    # --- 5a: which events each voice took ------------------------------------
    if hasUse
        @caption: vizL, vizR, yUseA, yUseB, "5  Which source events each voice took, and when it played them"
        Font size: 7
        Select inner viewport: vizL, vizR, yUseA, yUseB
        Axes: 0, nUseEvents, 0, number_of_agents
        Paint rectangle: "{1.00, 1.00, 1.00}", 0, nUseEvents, 0, number_of_agents
        for iAT from 0 to number_of_agents - 1
            @agentCol: iAT
            yTop = number_of_agents - iAT
            for iEv2 from 0 to nUseEvents - 1
                uk = iAT * nUseEvents + iEv2
                uv = useCount_'uk'
                if uv = undefined
                    uv = 0
                endif
                if uv > 0
                    shade = min(1, uv / max(1, useHi))
                    cellCol$ = "{" + fixed$(1 - (1 - agentCol.r) * (0.35 + 0.65 * shade), 3)
                        ... + ", " + fixed$(1 - (1 - agentCol.g) * (0.35 + 0.65 * shade), 3)
                        ... + ", " + fixed$(1 - (1 - agentCol.b) * (0.35 + 0.65 * shade), 3) + "}"
                    Paint rectangle: cellCol$, iEv2 + 0.08, iEv2 + 0.92, yTop - 0.88, yTop - 0.12
                endif
            endfor
        endfor
        Colour: "Black"
        Select inner viewport: vizL, vizR, yUseA, yUseB
        Axes: 0, nUseEvents, 0, number_of_agents
        Draw inner box
        for iAT from 0 to number_of_agents - 1
            One mark left: number_of_agents - iAT - 0.5, "no", "yes", "no", "v" + string$(iAT)
        endfor
        @snapStep: nUseEvents, 8
        Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
        Font size: 6
        Select inner viewport: vizL, vizR, yUseA, yUseB
        Axes: 0, 1, 0, 1
        Text bottom: "yes", "source event index   -   darker = used more often"
    endif

    # --- 5b: polyphonic timeline ---------------------------------------------
    tlMaxTime = 0.01
    for iAT from 0 to number_of_agents - 1
        nBl = agNBlocks_'iAT'
        if nBl > 0
            lastBl = nBl - 1
            blEnd = agBl_'iAT'_'lastBl'_e
            if blEnd > tlMaxTime
                tlMaxTime = blEnd
            endif
        endif
    endfor

    Font size: 7
    Select inner viewport: vizL, vizR, yTlA, yTlB
    # The old axis ran -0.2..n-0.8 while lanes were centred at n-1-i-0.5, so the
    # bottom voice was drawn below ymin. Paint rectangle does not clip, and it
    # spilled over the panel below.
    Axes: 0, tlMaxTime, 0, number_of_agents
    Paint rectangle: "{1.00, 1.00, 1.00}", 0, tlMaxTime, 0, number_of_agents
    for iAT from 0 to number_of_agents - 1
        laneY = number_of_agents - iAT - 0.5
        nBl = agNBlocks_'iAT'
        @agentCol: iAT
        for iBl from 0 to nBl - 1
            blS = agBl_'iAT'_'iBl'_s
            blE = agBl_'iAT'_'iBl'_e
            if blE > blS
                Paint rectangle: agentCol.col$, blS, blE, laneY - 0.36, laneY + 0.36
            endif
        endfor
    endfor
    # Without separators a run of adjacent blocks reads as one solid bar.
    Colour: "White"
    Line width: 1
    for iAT from 0 to number_of_agents - 1
        laneY = number_of_agents - iAT - 0.5
        nBl = agNBlocks_'iAT'
        for iBl from 1 to nBl - 1
            blS = agBl_'iAT'_'iBl'_s
            Draw line: blS, laneY - 0.36, blS, laneY + 0.36
        endfor
    endfor
    Colour: "Black"
    if nUseEvents <= 40
        Font size: 4.5
        Select inner viewport: vizL, vizR, yTlA, yTlB
        Axes: 0, tlMaxTime, 0, number_of_agents
        Colour: "White"
        for iAT from 0 to number_of_agents - 1
            laneY = number_of_agents - iAT - 0.5
            nBl = agNBlocks_'iAT'
            for iBl from 0 to nBl - 1
                blS = agBl_'iAT'_'iBl'_s
                blE = agBl_'iAT'_'iBl'_e
                blEv = agBl_'iAT'_'iBl'_ev
                if blE - blS > tlMaxTime * 0.016
                    Text: (blS + blE) / 2, "centre", laneY, "half", string$(blEv)
                endif
            endfor
        endfor
        Colour: "Black"
    endif
    Font size: 7
    Select inner viewport: vizL, vizR, yTlA, yTlB
    Axes: 0, tlMaxTime, 0, number_of_agents
    Draw inner box
    for iAT from 0 to number_of_agents - 1
        One mark left: number_of_agents - iAT - 0.5, "no", "yes", "no", "v" + string$(iAT)
    endfor
    @snapStep: tlMaxTime, 8
    Marks bottom every: 1, snapStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Output time (s)   -   numbers are source event indices"

    # --- summary --------------------------------------------------------------
    @sanitize: spliceMode$
    spliceTxt$ = sanitize.out$

    Font size: 7
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 8
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Colour: "Black"
    @sumRow: 0
    Text: 0.015, "left", sumRow.y, "half", "##Process summary##"

    Font size: 7
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    lossStepsTxt$ = ""
    if hasLoss
        lossStepsTxt$ = " over " + string$(lossSteps) + " steps"
    endif
    @sumRow: 1
    Text: 0.015, "left", sumRow.y, "half", "Analysis: " + nEvStat$ + " events, mean " + meanEvDur$
        ... + " s, " + totalUnique$ + " used by at least one voice"
        ... + "   clean AE loss " + initialLoss$ + " to " + finalLoss$
        ... + lossStepsTxt$ + ", " + string$(latent_size) + "-D latent"
    @sumRow: 2
    Text: 0.015, "left", sumRow.y, "half", "Counterpoint: mean separation " + meanSep$
        ... + " x the corpus median distance   rigidity " + fixed$(counterpoint_rigidity, 2)
        ... + ", speed " + fixed$(speed, 2)
        ... + "   forces: inertia, profile attraction, mutual repulsion, jitter"
    @sumRow: 3
    Text: 0.015, "left", sumRow.y, "half", "Selection: nearest event, LRU memory of 15, graded proximity penalty scaled by rigidity"

    # Per-voice lines, in that voice's own colour.
    for iAT from 0 to number_of_agents - 1
        @agentCol: iAT
        @sanitize: agProfile_'iAT'$
        Font size: 7
        Select inner viewport: vizL, vizR, ySumA, ySumB
        Axes: 0, 1, 0, 1
        Colour: agentCol.col$
        @sumRow: 4 + iAT
        Text: 0.015, "left", sumRow.y, "half", "voice " + string$(iAT) + "  " + sanitize.out$
            ... + ":  " + agSteps_'iAT'$ + " steps, " + agUnique_'iAT'$ + " unique events"
            ... + ", repetition " + agRepRate_'iAT'$
            ... + ", mean latent travel " + agTravel_'iAT'$
            ... + ", mean periphery " + agPeriph_'iAT'$
    endfor
    Colour: "Black"

    unisonLine$ = "Unison rates: "
    for iA from 0 to number_of_agents - 2
        for iB from iA + 1 to number_of_agents - 1
            thisRate$ = unisonRate_'iA'_'iB'$
            if thisRate$ <> "?"
                unisonLine$ = unisonLine$ + string$(iA) + "-" + string$(iB) + " " + thisRate$ + "   "
            endif
        endfor
    endfor
    Font size: 7
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    @sumRow: 4 + number_of_agents
    Text: 0.015, "left", sumRow.y, "half", unisonLine$
    @sumRow: 5 + number_of_agents
    Text: 0.015, "left", sumRow.y, "half", "Render: " + spliceTxt$ + " splices, "
        ... + phaseSafe$ + " phase-safe event folds"
        ... + "   duration " + fixed$(dur, 2) + " to " + outDurStat$ + " s"
        ... + "   RMS " + fixed$(rms_orig, 4) + " to " + fixed$(rms_out, 4)
    if warningStat$ <> "?" and warningStat$ <> ""
        @sanitize: warningStat$
        Colour: "{0.80, 0.20, 0.20}"
        Text: 0.985, "right", 1 - 0.10 / sumH, "half", "warning: " + sanitize.out$
        Colour: "Black"
    endif
    if hasLatent = 0
        Colour: "{0.70, 0.35, 0.10}"
        Text: 0.985, "right", 1 - (0.10 + sumPitch * (5 + number_of_agents)) / sumH, "half", "panels 3 and 4 need engine v1.5 or newer"
        Colour: "Black"
    endif
    Select inner viewport: vizL, vizR, ySumA, ySumB
    Axes: 0, 1, 0, 1
    Draw rectangle: 0, 1, 0, 1

    # Save as / Copy follow the CURRENT viewport selection, so end on the whole
    # canvas or the export is silently cropped to the last panel.
    Select outer viewport: 0, 8, 0, canvasH
endif

# ===========================================================================
# Cleanup & Summary
# ===========================================================================
@cleanUpTempFiles

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", soundName$, "_cp (stereo)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Agents:"
for iA from 0 to number_of_agents - 1
    appendInfoLine: "  ", string$(iA), ": ", agProfile_'iA'$, " | Steps=", agSteps_'iA'$, " | Unique=", agUnique_'iA'$, " | Rep=", agRepRate_'iA'$, " | Travel=", agTravel_'iA'$, " | Periphery=", agPeriph_'iA'$
endfor

appendInfoLine: ""
appendInfoLine: "Counterpoint (unison rates):"
for iA from 0 to number_of_agents - 2
    for iB from iA + 1 to number_of_agents - 1
        appendInfoLine: "  ", string$(iA), " ↔ ", string$(iB), ": ", unisonRate_'iA'_'iB'$
    endfor
endfor

appendInfoLine: ""
appendInfoLine: "Duration: ", fixed$(dur, 2), " s -> ", outDurStat$, " s"
appendInfoLine: "RMS: ", fixed$(rms_orig, 4), " -> ", fixed$(rms_out, 4)
appendInfoLine: "Mean latent separation / median: ", meanSep$
appendInfoLine: "Phase-safe event folds: ", phaseSafe$

if warningStat$ <> "?" and warningStat$ <> ""
    appendInfoLine: ""
    appendInfoLine: "WARNING: ", warningStat$
endif

selectObject: resultSound
if play_result
    Play
endif

# ===========================================================================
# Procedures
# ===========================================================================
procedure parseStatLine: .text$, .key$
    .result$ = "?"
    .pos = index(.text$, .key$)
    if .pos > 0
        .start = .pos + length(.key$)
        .rest$ = mid$(.text$, .start, length(.text$) - .start + 1)
        .nlPos = index(.rest$, newline$)
        if .nlPos > 0
            .result$ = left$(.rest$, .nlPos - 1)
        else
            .result$ = .rest$
        endif
    endif
endproc

procedure sanitize: .s$
    .out$ = replace$(.s$, "\", "\bs ", 0)
    .out$ = replace$(.out$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
endproc

# A tick step derived as span/N prints labels like 0.6569; snap it to 1/2/5.
procedure snapStep: .span, .target
    .step = 1
    if .span > 0
        if .target > 0
            .raw = .span / .target
            .mag = 10 ^ floor(log10(.raw))
            .n = .raw / .mag
            if .n <= 1.5
                .step = .mag
            elsif .n <= 3.5
                .step = 2 * .mag
            elsif .n <= 7.5
                .step = 5 * .mag
            else
                .step = 10 * .mag
            endif
        endif
    endif
endproc

# Text left: anchors against whatever drawing frame is current, which puts each
# panel's name at a different x. Place the rail by hand at one shared offset.
procedure rail: .y1, .y2, .name$
    Font size: 7
    Select inner viewport: vizL, vizR, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: railX, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure caption: .x1, .x2, .y1, .y2, .txt$
    Font size: 6
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: "{0.40, 0.40, 0.50}"
    Text top: "no", .txt$
    Colour: "Black"
endproc

# One voice palette, shared by the latent paths, the usage matrix, the timeline
# and the summary lines, so a colour means the same voice everywhere.
procedure agentCol: .k
    .i = .k - 6 * floor(.k / 6)
    if .i = 0
        .r = 0.20
        .g = 0.40
        .b = 0.70
    elsif .i = 1
        .r = 0.70
        .g = 0.30
        .b = 0.20
    elsif .i = 2
        .r = 0.30
        .g = 0.60
        .b = 0.30
    elsif .i = 3
        .r = 0.60
        .g = 0.40
        .b = 0.60
    elsif .i = 4
        .r = 0.70
        .g = 0.60
        .b = 0.20
    else
        .r = 0.40
        .g = 0.60
        .b = 0.70
    endif
    .col$ = "{" + fixed$(.r, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(.b, 3) + "}"
endproc

# Summary rows are laid out from a pitch rather than hard-coded fractions, so
# the box grows with the number of voices instead of overprinting itself.
procedure sumRow: .r
    .y = 1 - (0.10 + sumPitch * .r) / sumH
endproc
