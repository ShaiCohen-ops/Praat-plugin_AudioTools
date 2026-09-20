# ============================================================
# Praat AudioTools - IRCAM_Multichannel_to_Binaural.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.5.0 (2026) - Safe Binaural Render
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multichannel-to-binaural downmix via Spat5 virtual speakers.
#   The input channels are treated as loudspeaker feeds at the positions of
#   the chosen layout; spat5.virtualspeakers~ convolves each with its HRIR
#   pair and sums them into two ears.
#
#   SAFE RENDER (v1.4): every ear signal is a SUM of all channels filtered
#   by HRIRs, so it can exceed full scale even when each channel does not
#   (coherent worst case +6 dB for 2 ch, +18 dB for 8 ch, +27.6 dB for 24
#   ch, plus HRTF gain). Clipped samples cannot be repaired afterwards, so
#   the script measures every render and RE-RENDERS with more input
#   attenuation until it is clean; only then is it (optionally)
#   normalised to the output peak.
#
#   Channel order ASSUMED by this script (verify with the channel-order
#   test, below - the script cannot know how a Sound was assembled):
#     1 ch  mono      C
#     2 ch  2.0       L R
#     4 ch  4.0       FL FR BL BR
#     5 ch  5.0       L R C Ls Rs
#     6 ch  5.1       L R C LFE Ls Rs
#     7 ch  7.0       Spat5 7.0 order
#     8 ch  7.1       L R C LFE Ls Rs Lss Rss
#    10 ch  7.1.2     7.1 + TpFL TpFR
#    12 ch  7.1.4     7.1 + TpFL TpFR TpBL TpBR
#    24 ch  22.2      NHK/AES order; bridge reorders to 22 directional + LFE1/LFE2 at 23/24
#
#   CHANNEL-ORDER TEST: tick "Create channel-order test Sound" to get a
#   Sound for the chosen layout in which only one channel sounds at a time
#   (1 s pink-noise bursts at -20 dBFS). Render it: each burst should come
#   from the expected direction. Clean single bursts but distortion when
#   channels play together = summing/headroom; distortion on a single
#   burst = layout, HRTF, sample-rate or invocation.
#
# Dependencies:
#   Spat5 (IRCAM) - spat5.virtualspeakers~ command-line tool
#   Python 3 (stdlib; numpy optional, speeds up the output analysis)
#
# Changelog:
#   v1.4.1 - 24-bit intermediate WAV (the safe-render attenuation no longer
#            costs resolution: 16-bit + 17-20 dB attenuation + later
#            normalisation raised the quantisation floor with the signal).
#            If the FIRST render fails outright with the 24-bit file, the
#            script retries once with 16-bit and says so (16-bit is the
#            format v1.3 used with Spat5).
#            Guards: Output_peak_dBFS limited to -24..0 dB (a positive value
#            re-created clipping after the safe render); ITD 0..200 %.
#   v1.4 - SAFE BINAURAL RENDER
#          Fix: no headroom management. v1.3 applied a fixed -6 dB (any
#               value, even positive, unguarded) and never measured the
#               result; multichannel sums through HRIRs can exceed full
#               scale by far more. Now: automatic initial attenuation from
#               the source peak and channel count, clipping detection on
#               every render, iterative re-render (-6 dB per attempt, up to
#               5), normalisation only after a clean render.
#          Fix: the WAV exported to Spat5 could clip silently (16-bit PCM
#               clips at +-1); the export gain is now capped at -1 dBFS.
#          Fix: the bridge reported "stereo image looks healthy" for a file
#               with 78 % of its samples at full scale (it checked only RMS
#               and correlation). Now: peak, full-scale count, flat-top
#               run, crest factor per ear, machine-readable stats.
#          Fix: layout vs channel count is validated (a manual 5.1 on an
#               8-ch Sound used to be passed to Spat5 unchecked).
#          Fix: a failed render stopped the script at runSubprocess, so the
#               failure branch (log dump) was unreachable; nocheck + stats.
#          New: optional LFE mute (5.1 / 7.1 / 7.1.2 / 7.1.4, channel 4).
#          New: channel-order test Sound generator.
#          New: level ledger in Info and visualization (attempts, input
#               attenuation, render peak, normalisation, net gain).
#   v1.3 - robust 3-candidate Python detection; macOS/Linux; platform info
#   v1.2 - tools folder in the form; Room_preset fix; log kept on failure
#   v1.5.1 - FIX: 22.2 external 24-channel NHK/AES input is adapted before
#            virtualspeakers: external LFE1/LFE2 are moved from slots 4/10 to
#            slots 23/24, leaving the 22 directional feeds contiguous first.
#            Spat5 requires all 24 channels for its 22.2 preset.
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sourceName$ = selected$("Sound")
selectObject: original
numCh    = Get number of channels
duration = Get total duration
sr       = Get sampling frequency

# ---- FIXED PATHS (not user-editable) ----
helper_py$      = defaultDirectory$ + "/spat_binaural_bridge.py"
working_folder$ = defaultDirectory$ + "/"

# ---- FORM ----
form Multichannel to Binaural v1.5.1
    comment Folder containing spat5.virtualspeakers~
    sentence Tools_folder C:/Users/User/Documents/Max 9/Packages/spat5-x64/media/tools/
    optionmenu Layout_preset: 1
        option "Auto-detect from channel count"
        option "2.0  --- Stereo"
        option "4.0  --- Quad"
        option "5.0  --- Surround (no LFE)"
        option "5.1  --- Surround + LFE"
        option "7.0  --- Surround 7ch"
        option "7.1  --- Surround 7.1"
        option "7.1.2 --- Surround + Height pair"
        option "7.1.4 --- Surround + Height quad"
        option "22.2 --- NHK Full Sphere (24 ch)"
    comment Room_preset applies only to "SOFA custom / none"
    optionmenu Hrtf_preset: 1
        option "KEMAR / neutral"
        option "KEMAR / hall"
        option "KEMAR / studio"
        option "SOFA custom / none"
    sentence Sofa_file kemar
    real Itd_percent 100
    optionmenu Room_preset: 1
        option "none"
        option "hall"
        option "livingroom"
        option "studio"
    optionmenu Headroom: 1
        option "Auto safe render (re-render until clean)"
        option "Manual pre-gain (one render, still checked)"
    real Manual_pre_gain_dB -6
    boolean Normalise_output 1
    real Output_peak_dBFS -1
    boolean Mute_LFE 0
    boolean Create_channel_order_test_Sound 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---- RESOLVE HRTF PRESET ----
# Room_preset only applies for Hrtf_preset 4 (custom SOFA).
# Presets 1-3 carry their own room setting which must not be overwritten.
if hrtf_preset = 1
    actualSOFA$ = "kemar"
    roomName$   = "none"
elsif hrtf_preset = 2
    actualSOFA$ = "kemar"
    roomName$   = "hall"
elsif hrtf_preset = 3
    actualSOFA$ = "kemar"
    roomName$   = "studio"
else
    # Custom SOFA: honour the Room_preset menu
    actualSOFA$ = sofa_file$
    if room_preset = 1
        roomName$ = "none"
    elsif room_preset = 2
        roomName$ = "hall"
    elsif room_preset = 3
        roomName$ = "livingroom"
    else
        roomName$ = "studio"
    endif
endif


# ---- RESOLVE LAYOUT ----
tokenCount = 10
tok$[1] = "mono"
tokN[1] = 1
tok$[2] = "2.0"
tokN[2] = 2
tok$[3] = "4.0"
tokN[3] = 4
tok$[4] = "5.0"
tokN[4] = 5
tok$[5] = "5.1"
tokN[5] = 6
tok$[6] = "7.0"
tokN[6] = 7
tok$[7] = "7.1"
tokN[7] = 8
tok$[8] = "7.1.2"
tokN[8] = 10
tok$[9] = "7.1.4"
tokN[9] = 12
tok$[10] = "22.2"
tokN[10] = 24
tokOrder$[1] = "C"
tokOrder$[2] = "L R"
tokOrder$[3] = "FL FR BL BR"
tokOrder$[4] = "L R C Ls Rs"
tokOrder$[5] = "L R C LFE Ls Rs"
tokOrder$[6] = "Spat5 7.0 order"
tokOrder$[7] = "L R C LFE Ls Rs Lss Rss"
tokOrder$[8] = "L R C LFE Ls Rs Lss Rss TpFL TpFR"
tokOrder$[9] = "L R C LFE Ls Rs Lss Rss TpFL TpFR TpBL TpBR"
tokOrder$[10] = "NHK/AES 24ch; LFE1=4, LFE2=10 (reordered to Spat slots 23/24)"

if layout_preset = 1
    layoutIdx = 0
    for t from 1 to tokenCount
        if tokN[t] = numCh
            layoutIdx = t
        endif
    endfor
    if layoutIdx = 0 and create_channel_order_test_Sound = 0
        exitScript: "Cannot auto-detect a layout for " + string$(numCh) +
            ... " channels (supported: 1, 2, 4, 5, 6, 7, 8, 10, 12, 24). Choose a layout manually."
    endif
else
    layoutIdx = layout_preset
endif

# ---- CHANNEL-ORDER TEST SOUND (no render) ----
if create_channel_order_test_Sound
    if layoutIdx = 0
        exitScript: "Choose a layout (not Auto) for the channel-order test."
    endif
    nT = tokN[layoutIdx]
    test = Create Sound from formula: "channel_order_test_" + replace$(tok$[layoutIdx], ".", "_", 0),
        ... nT, 0, nT, 48000, "if (x >= row - 1 + 0.05) and (x < row - 0.15) then randomGauss (0, 1) else 0 fi"
    # pink-ish tilt (-3 dB/oct) and -20 dBFS peak per burst
    Filter (formula): "if x > 20 then self / sqrt (x / 20) else 0 fi"
    Formula: "self * min (1, (x - (row - 1 + 0.05)) / 0.01) * min (1, ((row - 0.15) - x) / 0.01) * (if (x >= row - 1 + 0.05) and (x < row - 0.15) then 1 else 0 fi)"
    Scale peak: 0.1
    writeInfoLine: "=== Channel-order test Sound ==="
    appendInfoLine: "Layout ", tok$[layoutIdx], ": ", nT, " channels, one 0.8 s burst per channel, -20 dBFS peak."
    appendInfoLine: "Assumed order: ", tokOrder$[layoutIdx]
    appendInfoLine: "Burst k (starting at k-1 s) should be heard from channel k's direction."
    appendInfoLine: "Render it with this script (headroom Auto, KEMAR / neutral, room none)."
    exitScript ()
endif

layoutToken$ = tok$[layoutIdx]
if tokN[layoutIdx] <> numCh
    exitScript: "Layout " + layoutToken$ + " expects " + string$(tokN[layoutIdx]) + " channels, but the Sound has "
        ... + string$(numCh) + ". Spat5 would refuse it or map the channels wrongly." + newline$
        ... + "Choose the matching layout (or Auto)."
endif
hasLFE = layoutToken$ = "5.1" or layoutToken$ = "7.1" or layoutToken$ = "7.1.2" or layoutToken$ = "7.1.4" or layoutToken$ = "22.2"
if mute_LFE and hasLFE = 0
    appendInfoLine: "Note: Mute_LFE ignored - layout " + layoutToken$ + " has no LFE at a known position."
endif
# For 22.2 the bridge reorders LFE1/LFE2 to channels 23/24 before virtualspeakers.
# muteLFE here is only the Praat-side zeroing used by the legacy layouts.
muteLFE = mute_LFE and hasLFE and layoutToken$ <> "22.2"

# ---- GUARDS ----
if not fileReadable(helper_py$)
    exitScript: "Python helper not found: " + helper_py$
endif

# ---- NORMALISE FOLDER PATHS ----
if right$(tools_folder$, 1) <> "/" and right$(tools_folder$, 1) <> "\"
    tools_folder$ = tools_folder$ + "/"
endif

# ---- TEMP FILES ----
inputWav$  = working_folder$ + "mcbin_input.wav"
outputWav$ = working_folder$ + "mcbin_output.wav"
logTxt$    = working_folder$ + "mcbin_log.txt"
statsTxt$  = working_folder$ + "mcbin_stats.txt"

# ---- SOURCE LEVEL ----
selectObject: original
srcPeak = Get absolute extremum: 0, 0, "None"
if srcPeak <= 0
    exitScript: "The Sound is silent (peak 0)."
endif
srcPeakDb = 20 * log10 (srcPeak)
nActive = if layoutToken$ = "22.2" then 22 else numCh - muteLFE fi
# largest gain that keeps the exported 16-bit WAV at or below -1 dBFS
exportSafeDb = -1 - srcPeakDb
if headroom = 1
    # summation estimate: incoherent sum of nActive channels + 3 dB for HRTF gain
    gainDb = min (exportSafeDb, -srcPeakDb - 10 * log10 (nActive) - 3)
    maxAttempts = 5
else
    gainDb = manual_pre_gain_dB
    maxAttempts = 1
    if gainDb > exportSafeDb
        appendInfoLine: "Note: manual pre-gain ", fixed$(manual_pre_gain_dB, 1), " dB would clip the exported WAV; capped at ", fixed$(exportSafeDb, 1), " dB."
        gainDb = exportSafeDb
    endif
endif

# ---- GUARDS ON OUTPUT PEAK AND ITD ----
guardNotes$ = ""
if output_peak_dBFS > 0 or output_peak_dBFS < -24
    guardNotes$ = guardNotes$ + "Note: Output_peak_dBFS " + fixed$(output_peak_dBFS, 1) + " dB is outside -24..0; using "
    output_peak_dBFS = max (-24, min (0, output_peak_dBFS))
    guardNotes$ = guardNotes$ + fixed$(output_peak_dBFS, 1) + " dB." + newline$
endif
if itd_percent < 0 or itd_percent > 200
    guardNotes$ = guardNotes$ + "Note: Itd_percent " + fixed$(itd_percent, 1) + " is outside 0..200; using "
    itd_percent = max (0, min (200, itd_percent))
    guardNotes$ = guardNotes$ + fixed$(itd_percent, 0) + "." + newline$
endif

# ---- INFO ----
if windows
    platform$ = "Windows"
elsif macintosh
    platform$ = "macOS"
else
    platform$ = "Linux"
endif
writeInfoLine:  "=== Multichannel to Binaural v1.5.1 (safe render) ==="
appendInfoLine: "Platform: ", platform$
appendInfoLine: "Source:   ", sourceName$, "  (", numCh, " ch  /  ", fixed$(duration, 2), " s  @  ", sr, " Hz)  peak ", fixed$(srcPeakDb, 1), " dBFS"
appendInfoLine: "Layout:   ", layoutToken$, "  assumed order: ", tokOrder$[layoutIdx]
if layoutToken$ = "22.2"
    appendInfoLine: "LFE:      NHK/AES channels 4/10 reordered to Spat channels 23/24 (24ch retained)"
elsif muteLFE
    appendInfoLine: "LFE:      channel 4 muted"
endif
appendInfoLine: "HRTF:     ", actualSOFA$, "  ITD=", fixed$(itd_percent, 1), "%   Room: ", roomName$
appendInfoLine: "Headroom: ", if headroom = 1 then "auto safe render" else "manual pre-gain" fi, ", start ", fixed$(gainDb, 1), " dB"
appendInfoLine: "Tools:    ", tools_folder$
if guardNotes$ <> ""
    appendInfo: guardNotes$
endif
appendInfoLine: ""
# ---- DETECT PYTHON (multi-candidate probe with dependency check) ----
# NOTE: candidates must be single-word commands because runSubprocess
# passes the executable name as one argument. "py -3" would fail.
probeMarker$ = working_folder$ + "mcbin_probe.ok"

if windows
    nPyCandidates = 3
    pyCandidate1$ = "python"
    pyCandidate2$ = "py"
    pyCandidate3$ = "python3"
else
    nPyCandidates = 3
    pyCandidate1$ = "python3"
    pyCandidate2$ = "python"
    pyCandidate3$ = "py"
endif

pythonCmd$ = ""
for iCand from 1 to nPyCandidates
    if iCand = 1
        tryCmd$ = pyCandidate1$
    elsif iCand = 2
        tryCmd$ = pyCandidate2$
    else
        tryCmd$ = pyCandidate3$
    endif

    if fileReadable(probeMarker$)
        deleteFile: probeMarker$
    endif

    # Probe: check Python exists AND can import the required stdlib modules
    probeCode$ = "import sys,os,subprocess,struct,math,wave; open(r'" + probeMarker$ + "','w').write('ok')"
    runSystem_nocheck: tryCmd$ + " -c """ + probeCode$ + """"

    if fileReadable(probeMarker$)
        pythonCmd$ = tryCmd$
        deleteFile: probeMarker$
        appendInfoLine: "  Python found: ", pythonCmd$
    endif
    if pythonCmd$ <> ""
        iCand = nPyCandidates + 1
    endif
endfor

if pythonCmd$ = ""
    exitScript: "Cannot find a working Python installation." + newline$
        ... + "" + newline$
        ... + "Tried: " + pyCandidate1$ + ", " + pyCandidate2$ + ", " + pyCandidate3$ + newline$
        ... + "" + newline$
        ... + "Please install Python 3 and ensure it is on your PATH."
endif

# ---- SAFE RENDER LOOP ----
# Clipping cannot be repaired after the fact: a clipped render is
# discarded and rendered again from the source with 6 dB more attenuation.
appendInfoLine: "Rendering binaural..."
attempt = 0
accepted = 0
hardFail = 0
exportBits = 24
fellBack = 0
while attempt < maxAttempts and accepted = 0 and hardFail = 0
    attempt += 1
    attGain[attempt] = gainDb
    if fileReadable(inputWav$)
        deleteFile: inputWav$
    endif
    selectObject: original
    work = Copy: "__mcbin_work"
    if muteLFE
        Formula: "if row = 4 then 0 else self fi"
    endif
    Multiply: 10 ^ (gainDb / 20)
    if exportBits = 24
        Save as 24-bit WAV file: inputWav$
    else
        Save as WAV file: inputWav$
    endif
    removeObject: work

    nocheck runSubprocess: pythonCmd$, helper_py$,
        ... inputWav$, outputWav$, logTxt$,
        ... tools_folder$, layoutToken$,
        ... actualSOFA$, string$(itd_percent), roomName$, statsTxt$

    if fileReadable(statsTxt$) and fileReadable(outputWav$)
        stats$ = readFile$(statsTxt$)
        attClipped[attempt] = extractNumber (stats$, "clipped=")
        attOvershoot[attempt] = extractNumber (stats$, "overshoot=")
        attPeak[attempt] = max (extractNumber (stats$, "peak_l="), extractNumber (stats$, "peak_r="))
        attFull[attempt] = extractNumber (stats$, "fullscale_l=") + extractNumber (stats$, "fullscale_r=")
        attRun[attempt] = max (extractNumber (stats$, "maxrun_l="), extractNumber (stats$, "maxrun_r="))
        outFormat$ = extractWord$ (stats$, "format=")
        attOver[attempt] = extractNumber (stats$, "over_l=") + extractNumber (stats$, "over_r=")
        outCorr = extractNumber (stats$, "correlation=")
        if attClipped[attempt]
            appendInfoLine: "  attempt ", attempt, ": input ", fixed$(gainDb, 1), " dB -> CLIPPED (",
                ... attFull[attempt], " full-scale samples, longest run ", attRun[attempt], ")"
            gainDb = gainDb - 6
        else
            accepted = 1
            appendInfoLine: "  attempt ", attempt, ": input ", fixed$(gainDb, 1), " dB -> clean, render peak ",
                ... fixed$(20 * log10 (max (attPeak[attempt], 1e-12)), 2), " dBFS (", outFormat$, ")"
        endif
    elsif attempt = 1 and exportBits = 24
        # the first render failed outright: retry once with a 16-bit
        # intermediate (the format v1.3 used) before giving up
        appendInfoLine: "  attempt 1 with a 24-bit intermediate failed; retrying with 16-bit"
        exportBits = 16
        fellBack = 1
        attempt = 0
    else
        hardFail = 1
    endif
endwhile

if hardFail
    appendInfoLine: "ERROR: Binaural render failed (attempt ", attempt, ")."
    appendInfoLine: "Log preserved at: ", logTxt$
    if fileReadable(logTxt$)
        appendInfoLine: ""
        appendInfoLine: "=== Spat5 log ==="
        appendInfoLine: readFile$(logTxt$)
    endif
    deleteFile: inputWav$
    deleteFile: outputWav$
    exitScript: "Binaural render failed - see the Info window."
endif

if accepted = 0
    appendInfoLine: ""
    if headroom = 1
        appendInfoLine: "ERROR: still clipping after ", maxAttempts, " renders (input down to ", fixed$(attGain[attempt], 1), " dB)."
        appendInfoLine: "This is no longer a summing problem: check the layout / channel order, the HRTF"
        appendInfoLine: "and the sample rate with the channel-order test (see script header)."
    else
        appendInfoLine: "The manual pre-gain render CLIPPED. Use Headroom = Auto safe render, or lower the gain."
    endif
    appendInfoLine: "The clipped render is loaded for inspection only; log: ", logTxt$
endif

# ---- IMPORT RESULT ----
Read from file: outputWav$
result = selected("Sound")
Rename: sourceName$ + "_binaural"
renderPeak = Get absolute extremum: 0, 0, "None"
renderPeakDb = 20 * log10 (max (renderPeak, 1e-12))
normDb = 0
if accepted
    if normalise_output and renderPeak > 0
        normDb = output_peak_dBFS - renderPeakDb
        Scale peak: 10 ^ (output_peak_dBFS / 20)
    elsif renderPeak > 0.99
        # float output above full scale: not clipped, but guard playback
        normDb = 20 * log10 (0.99 / renderPeak)
        Scale peak: 0.99
    endif
endif
finalPeak = Get absolute extremum: 0, 0, "None"
finalPeakDb = 20 * log10 (max (finalPeak, 1e-12))
# round before printing: fixed$ ignores the precision for tiny values
# (a 0 dB target printed as -0.0000000000000010)
finalPeakDb = round (finalPeakDb * 1000) / 1000
netDb = attGain[attempt] + normDb
actual_dur = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Level ledger ==="
appendInfoLine: "  source peak          ", fixed$(srcPeakDb, 2), " dBFS"
appendInfoLine: "  input attenuation    ", fixed$(attGain[attempt], 2), " dB   (", attempt, " render", if attempt > 1 then "s" else "" fi, ", ", exportBits, "-bit intermediate)"
if left$ (outFormat$, 5) = "float"
    appendInfoLine: "  render peak          ", fixed$(renderPeakDb, 2), " dBFS  (", outFormat$, ": ", attOver[attempt], " samples above 1.0, kept intact - float does not clip)"
else
    appendInfoLine: "  render peak          ", fixed$(renderPeakDb, 2), " dBFS  (", outFormat$, ", full-scale samples ", attFull[attempt], ")"
endif
appendInfoLine: "  normalisation        ", if normDb = 0 then "none" else fixed$(normDb, 2) + " dB" fi
appendInfoLine: "  output peak          ", fixed$(finalPeakDb, 2), " dBFS"
appendInfoLine: "  net source->output   ", fixed$(netDb, 2), " dB"
appendInfoLine: "  L/R correlation      ", fixed$(outCorr, 3), "  (descriptive only)"
appendInfoLine: ""
if accepted
    appendInfoLine: "Done. Output: ", sourceName$ + "_binaural"
    deleteFile: inputWav$
    deleteFile: outputWav$
    deleteFile: logTxt$
    deleteFile: statsTxt$
else
    deleteFile: inputWav$
endif

# ---- VISUALIZATION (house style, 8 x 6.5 in) ----
if draw_visualization
    cPrim$ = "{0.20, 0.48, 0.75}"
    cSec$ = "{0.85, 0.38, 0.18}"
    cGrey$ = "{0.55, 0.55, 0.60}"
    cGround$ = "{0.97, 0.97, 0.97}"
    cGrid$ = "{0.80, 0.80, 0.80}"
    cSub$ = "{0.35, 0.35, 0.50}"
    cSum$ = "{0.25, 0.25, 0.35}"
    nm$ = replace$ (sourceName$, "_", "\_ ", 0)
    Erase all

    Font size: 12
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Multichannel to Binaural v1.5.1##"
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: cSub$
    Text: 0.5, "centre", 0.22, "half", nm$ + "   |   " + string$(numCh) + " ch -> binaural   |   layout " + layoutToken$
        ... + "   |   HRTF " + actualSOFA$ + ", room " + roomName$ + "   |   " + if accepted then "clean render" else "CLIPPED render" fi

    # A: input (ch 1, ch 2) at its true level
    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    Axes: 0, duration, -1, 1
    Paint rectangle: cGround$, 0, duration, -1, 1
    if numCh > 1
        selectObject: original
        vizIn2 = Extract one channel: 2
        Colour: "{0.75, 0.75, 0.78}"
        Draw: 0, 0, -1, 1, "no", "Curve"
        removeObject: vizIn2
    endif
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    selectObject: original
    vizIn = Extract one channel: 1
    Colour: cGrey$
    Draw: 0, 0, -1, 1, "no", "Curve"
    removeObject: vizIn
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    Axes: 0, duration, -1, 1
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    Text left: "yes", "Input"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 0.95, 2.05
    Text top: "no", "##A   Input##   ch 1" + if numCh > 1 then " (dark) and ch 2 (light)" else "" fi + ", true level (full scale = frame)"

    # B: binaural output at its true level, full-scale guides
    Font size: 7
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    Axes: 0, actual_dur, -1.1, 1.1
    Paint rectangle: cGround$, 0, actual_dur, -1.1, 1.1
    selectObject: result
    vizR = Extract one channel: 2
    Colour: cSec$
    Draw: 0, 0, -1.1, 1.1, "no", "Curve"
    removeObject: vizR
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    selectObject: result
    vizL = Extract one channel: 1
    Colour: cPrim$
    Draw: 0, 0, -1.1, 1.1, "no", "Curve"
    removeObject: vizL
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    Axes: 0, actual_dur, -1.1, 1.1
    Colour: cGrid$
    Dotted line
    Draw line: 0, 1, actual_dur, 1
    Draw line: 0, -1, actual_dur, -1
    Solid line
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 1, "yes", "yes", "no"
    @niceStep: actual_dur, 8
    Marks bottom every: 1, niceStep.result, "yes", "yes", "no"
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Font size: 8
    Select inner viewport: 0.60, 7.70, 2.55, 3.75
    Text top: "no", "##B   Binaural output##   blue = L ear, orange = R ear; dotted = full scale; peak " + fixed$(finalPeakDb, 1) + " dBFS"

    # C: render attempts - input attenuation vs render peak
    yLo = min (-30, floor (min (attGain[attempt], renderPeakDb) / 6) * 6 - 6)
    Font size: 7
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Axes: 0.4, attempt + 0.6, yLo, 6
    Paint rectangle: cGround$, 0.4, attempt + 0.6, yLo, 6
    Colour: cSec$
    Dotted line
    Draw line: 0.4, 0, attempt + 0.6, 0
    Solid line
    for a from 1 to attempt
        pk = 20 * log10 (max (attPeak[a], 1e-12))
        if attClipped[a]
            Paint rectangle: cSec$, a - 0.3, a + 0.3, yLo, max (pk, 0)
        else
            Paint rectangle: cPrim$, a - 0.3, a + 0.3, yLo, pk
        endif
    endfor
    Font size: 6
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Axes: 0.4, attempt + 0.6, yLo, 6
    for a from 1 to attempt
        pk = 20 * log10 (max (attPeak[a], 1e-12))
        Colour: cSum$
        Text: a, "centre", max (pk, 0) + 0.8, "bottom", if attClipped[a] then "clipped" else fixed$(pk, 1) fi
        Text: a, "centre", yLo + 1.5, "bottom", "in " + fixed$(attGain[a], 1)
    endfor
    Font size: 7
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Axes: 0.4, attempt + 0.6, yLo, 6
    Colour: "Black"
    Draw inner box
    Marks left every: 1, 6, "yes", "yes", "no"
    for a from 1 to attempt
        One mark bottom: a, "no", "yes", "no", string$(a)
    endfor
    Text left: "yes", "Render peak (dBFS)"
    Text bottom: "yes", "Render attempt"
    Font size: 8
    Select inner viewport: 0.60, 3.85, 4.30, 5.45
    Text top: "no", "##C   Safe render##   orange = clipped, re-rendered"

    # D: level ledger
    Font size: 7
    Select inner viewport: 4.45, 7.70, 4.30, 5.45
    Axes: 0, 1, 0, 1
    Paint rectangle: cGround$, 0, 1, 0, 1
    Colour: cSum$
    Text: 0.04, "left", 0.88, "half", "Source peak"
    Text: 0.96, "right", 0.88, "half", fixed$(srcPeakDb, 1) + " dBFS"
    Text: 0.04, "left", 0.72, "half", "Input attenuation"
    Text: 0.96, "right", 0.72, "half", fixed$(attGain[attempt], 1) + " dB"
    Text: 0.04, "left", 0.56, "half", "Render peak"
    Text: 0.96, "right", 0.56, "half", fixed$(renderPeakDb, 1) + " dBFS"
    Text: 0.04, "left", 0.40, "half", "Normalisation"
    Text: 0.96, "right", 0.40, "half", if normDb = 0 then "none" else fixed$(normDb, 1) + " dB" fi
    Text: 0.04, "left", 0.24, "half", "##Output peak##"
    Text: 0.96, "right", 0.24, "half", "##" + fixed$(finalPeakDb, 1) + " dBFS##"
    Text: 0.04, "left", 0.08, "half", "Net source -> output"
    Text: 0.96, "right", 0.08, "half", fixed$(netDb, 1) + " dB"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Select inner viewport: 4.45, 7.70, 4.30, 5.45
    Text top: "no", "##D   Level ledger##"

    # summary strip
    Font size: 6
    Select inner viewport: 0.60, 7.70, 5.95, 6.45
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: cSum$
    Text: 0.01, "left", 0.72, "half", "##Layout:## " + layoutToken$ + " (" + tokOrder$[layoutIdx] + ")" + if muteLFE then ", LFE muted" else "" fi
        ... + "   ##HRTF:## " + actualSOFA$ + ", ITD " + fixed$(itd_percent, 0) + " \% , room " + roomName$
    Text: 0.01, "left", 0.28, "half", "##Headroom:## " + if headroom = 1 then "auto safe render" else "manual pre-gain" fi + ", " + string$(attempt) + " render(s), " + string$(exportBits) + "-bit intermediate"
        ... + "   ##Output:## " + outFormat$ + " from Spat5, " + fixed$(actual_dur, 2) + " s @ " + string$(sr) + " Hz"
        ... + "   ##L/R correlation:## " + fixed$(outCorr, 2) + " (descriptive)"
    Select inner viewport: 0.60, 7.70, 5.95, 6.45
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Line width: 1
    Select outer viewport: 0, 8, 0, 6.5
endif

# ---- PLAY ----
if play_result and accepted
    selectObject: result
    asynchronous Play
endif
selectObject: result

procedure niceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor (log10 (.raw))
    .result = 10 * .mag
    if 5 * .mag >= .raw
        .result = 5 * .mag
    endif
    if 2 * .mag >= .raw
        .result = 2 * .mag
    endif
    if .mag >= .raw
        .result = .mag
    endif
endproc
