# ============================================================
# Praat AudioTools - 22.2_Synthetic_Stem_Renderer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Psychoacoustic approximation of a 22.2-style synthetic stem
#   renderer. Takes a mono or stereo input and produces:
#       (1) a 24-channel synthetic surround render
#       (2) an optional headphone output
#
#   The 24-channel render is arranged as:
#       Middle Layer (10)
#         Ch  1 — FL   (Front Left)
#         Ch  2 — FR   (Front Right)
#         Ch  3 — FC   (Front Center)
#         Ch  4 — FWL  (Front Wide Left)
#         Ch  5 — FWR  (Front Wide Right)
#         Ch  6 — SiL  (Side Left)
#         Ch  7 — SiR  (Side Right)
#         Ch  8 — BL   (Back Left)
#         Ch  9 — BR   (Back Right)
#         Ch 10 — BC   (Back Center)
#
#       Upper Layer (9)
#         Ch 11 — TpFL  (Top Front Left)
#         Ch 12 — TpFR  (Top Front Right)
#         Ch 13 — TpFC  (Top Front Center)
#         Ch 14 — TpSiL (Top Side Left)
#         Ch 15 — TpSiR (Top Side Right)
#         Ch 16 — TpBL  (Top Back Left)
#         Ch 17 — TpBR  (Top Back Right)
#         Ch 18 — TpBC  (Top Back Center)
#         Ch 19 — TpC   (Top Center)
#
#       Lower Layer (3)
#         Ch 20 — BFL  (Bottom Front Left)
#         Ch 21 — BFR  (Bottom Front Right)
#         Ch 22 — BFC  (Bottom Front Center)
#
#       LFE (2)
#         Ch 23 — LFE1
#         Ch 24 — LFE2
#
#   This is a practical signal-processing approximation, not a
#   claim of physically accurate 22.2 capture, decoding, or
#   scene reconstruction. No external plug-ins or binaries are
#   required for the main render. The optional binaural mode
#   uses locally stored CNMAT KEMAR HRIR WAV files.
#
# Input:
#   One selected Sound object (mono or stereo). Any other
#   channel count causes a clean error exit.
#
# Output:
#   One 24-channel Sound object left in the Praat Objects list,
#   named:
#       <original>_22_2_Array
#
#   Optionally, one headphone output is also created:
#       <original>_Headphone_Preview
#   or
#       <original>_True_Binaural
#
# Processing summary:
#   STEREO input
#     Front FL/FR → original stereo channels (preserved)
#     FC          → mild Mid reinforcement
#     Ambience    → lateral residual stems derived from L and R
#                   by subtractive side extraction
#     Wides       → blend of direct fronts and lateral residuals
#     Surround /
#     Height /
#     Lower       → delayed, filtered, scaled derivatives of the
#                   direct and ambience stems
#
#   MONO input
#     Front FL/FR → real ITD widening: FL = original,
#                   FR = delayed by front_width_ms
#     FC          → mild Mid reinforcement
#     Ambience    → synthetic lateral residuals derived from the
#                   widened mono pair
#     Surround /
#     Height /
#     Lower       → delayed, filtered, scaled derivatives of the
#                   widened and ambience stems
#
#   In both cases:
#     - FL / FR are kept spectrally intact as the main anchors
#     - FC is added conservatively to stabilize the center
#     - Surround and upper channels are band-limited to reduce
#       directness and prevent tonal clutter
#     - Lower channels act as restrained floor-support signals
#     - LFE channels are derived from Mid and low-pass filtered
#     - Final outputs are peak-normalised with headroom_dBFS of
#       clearance
#
# Headphone modes:
#   1. Headphone Fold-down (Clean)
#      A deliberately EQ-transparent reference consisting of:
#        FL + FR + a very small amount of FC
#      This mode avoids delayed, filtered, and subtractive
#      surround feeds in order to preserve the original timbre.
#
#   2. True Binaural (CNMAT KEMAR)
#      Experimental binaural render using locally mapped CNMAT
#      KEMAR HRIR WAV files. Only speaker positions for which a
#      verified HRIR pair exists are used. If required mapped
#      files are missing, binaural rendering aborts cleanly
#      rather than producing a partial, tonally corrupted render.
#
# Changelog v1.0:
#   - Established stable 24-channel 22.2-style synthetic render
#   - Added clean headphone fold-down reference mode
#   - Added CNMAT KEMAR experimental binaural mode
#   - Added relative HRIR folder support for plugin deployment
#   - Added safe abort behavior for incomplete HRIR mappings
# ============================================================

form 22.2 Upmixer & Headphone Renderer
    comment === PRESET ===
    optionmenu Preset: 1
        option Cinematic Film
        option Subtle Music
        option Wide Mono

    comment === FRONT WIDENING (Mono Input) ===
    positive Front_width_ms 0.35

    comment === OUTPUT OPTIONS ===
    boolean Render_22_2_output 1
    boolean Render_headphone_output 1

    comment === HEADPHONE MIX ===
    optionmenu Headphone_mode: 1
        option Headphone Fold-down (Clean)
        option True Binaural (CNMAT KEMAR)
    sentence Hrir_folder Kemar_HRIR/

    comment === MASTER ===
    real Headroom_dBFS -1.0
    boolean Draw_visualization 1
    boolean Play_headphone_result 1
endform

# ============================================================
# 0. VALIDATION & PATH CLEANUP
# ============================================================
if numberOfSelected ("Sound") <> 1
    exitScript: "Please select exactly one Sound object (mono or stereo)."
endif

if render_22_2_output = 0 and render_headphone_output = 0
    exitScript: "Please select at least one output format."
endif

original = selected ("Sound")
sourceName$ = selected$ ("Sound")
numInCh = Get number of channels

if numInCh > 2
    exitScript: "Input has " + string$ (numInCh) + " channels. Script accepts mono or stereo only."
endif

# Ensure HRIR folder ends with a slash
len = length (hrir_folder$)
if len > 0
    lastChar$ = mid$ (hrir_folder$, len, 1)
    if lastChar$ <> "\" and lastChar$ <> "/"
        hrir_folder$ = hrir_folder$ + "/"
    endif
endif

# Validate HRIR folder only if binaural mode may be used
if render_headphone_output = 1 and headphone_mode = 2
    if not folderExists (hrir_folder$)
        exitScript: "HRIR folder not found: " + hrir_folder$
    endif
    if not fileReadable (hrir_folder$ + "L-12e036a.wav")
        exitScript: "HRIR test file not found: " + hrir_folder$ + "L-12e036a.wav"
    endif
endif

# ============================================================
# 1. APPLY PRESET MACRO-CONTROLS
# ============================================================
if preset = 2
    # Subtle Music
    c_reinforce = 0.30
    fw_gain_dB = -10.0
    amb_gain_dB = -8.0
    upper_gain_dB = -12.0
    lower_gain_dB = -18.0
    side_delay = 25.0
    upper_delay = 15.0
elsif preset = 3
    # Wide Mono
    c_reinforce = 0.40
    fw_gain_dB = -9.0
    amb_gain_dB = -6.0
    upper_gain_dB = -9.0
    lower_gain_dB = -12.0
    side_delay = 35.0
    upper_delay = 25.0
else
    # Cinematic Film
    c_reinforce = 0.50
    fw_gain_dB = -6.0
    amb_gain_dB = -4.0
    upper_gain_dB = -6.0
    lower_gain_dB = -9.0
    side_delay = 40.0
    upper_delay = 30.0
endif

rear_gain_dB = amb_gain_dB
decorr_ms = 7.0
hp_rear = 120
lp_rear = 6000
hp_top = 250
lp_top = 4000
lfe_hz = 120

# ============================================================
# 2. SETUP & BUILD BASE STEMS
# ============================================================
dur = Get total duration
sr = Get sampling frequency
nyq = sr / 2
headroomLin = 10 ^ (min (headroom_dBFS, 0) / 20)

writeInfoLine: "=== 22.2 Synthetic Stem Renderer ==="
appendInfoLine: "Source: ", sourceName$, " (", numInCh, " ch)"
appendInfoLine: "Rendering 24 channels..."

if numInCh = 2
    selectObject: original
    Extract one channel: 1
    stem_L = selected ("Sound")
    Rename: "stem_L"

    selectObject: original
    Extract one channel: 2
    stem_R = selected ("Sound")
    Rename: "stem_R"
else
    selectObject: original
    stem_L = Copy: "stem_L"

    selectObject: original
    stem_R = Copy: "stem_R"

    widthSamples = round (front_width_ms / 1000 * sr)
    if widthSamples > 0
        widthDur = widthSamples / sr
        Create Sound from formula: "sil", 1, 0, widthDur, sr, "0"
        sil = selected ("Sound")
        selectObject: sil
        plusObject: stem_R
        concat = Concatenate
        removeObject: sil, stem_R
        selectObject: concat
        stem_R = Extract part: 0, dur, "rectangular", 1, "no"
        removeObject: concat
        Rename: "stem_R"
    endif
endif

selectObject: stem_L
stem_Mid = Copy: "stem_Mid"
rId$ = string$ (stem_R)
Formula: "(self + Object_" + rId$ + "[col]) * 0.5"
midId$ = string$ (stem_Mid)

# ============================================================
# 3. GENTLE MATRIX EXTRACTION
# ============================================================
selectObject: stem_L
stem_FL = Copy: "stem_FL"

selectObject: stem_R
stem_FR = Copy: "stem_FR"

selectObject: stem_Mid
stem_FC = Copy: "stem_FC"
Formula: "self * " + string$ (c_reinforce)

selectObject: stem_L
stem_Amb_L = Copy: "stem_Amb_L"
Formula: "self - (Object_" + rId$ + "[col] * 0.5)"
ambLId$ = string$ (stem_Amb_L)

selectObject: stem_R
stem_Amb_R = Copy: "stem_Amb_R"
Formula: "self - (Object_" + string$ (stem_L) + "[col] * 0.5)"
ambRId$ = string$ (stem_Amb_R)

selectObject: stem_FL
stem_FW_L = Copy: "stem_FW_L"
Formula: "(self * 0.6) + (Object_" + ambLId$ + "[col] * 0.6)"

selectObject: stem_FR
stem_FW_R = Copy: "stem_FW_R"
Formula: "(self * 0.6) + (Object_" + ambRId$ + "[col] * 0.6)"

stem_LFE = stem_Mid

# ============================================================
# 4. CHANNEL BUILDER PROCEDURES
# ============================================================
procedure build_channel: .idx, .baseSig, .delayMs, .hpHz, .lpHz, .gainDb, .outName$
    .gainLin = 10 ^ (.gainDb / 20)
    selectObject: .baseSig
    .work = Copy: .outName$ + "_work"

    if .hpHz > 0 or .lpHz < (nyq - 100)
        .safeLp = min (.lpHz, nyq - 10)
        .safeHp = min (.hpHz, .safeLp - 10)
        selectObject: .work
        Filter (pass Hann band): .safeHp, .safeLp, 100
        .filt = selected ("Sound")
        removeObject: .work
        .work = .filt
    endif

    if .delayMs > 0
        Create Sound from formula: "sil", 1, 0, .delayMs / 1000, sr, "0"
        .sil = selected ("Sound")
        selectObject: .sil
        plusObject: .work
        .concat = Concatenate
        removeObject: .sil, .work
        selectObject: .concat
        .work = Extract part: 0, dur, "rectangular", 1, "no"
        removeObject: .concat
    endif

    selectObject: .work
    Formula: "self * " + string$ (.gainLin)
    Rename: .outName$
    outCh[.idx] = .work
endproc

procedure add_to_mix: .mixObj, .addObj, .gainLin
    .addStr$ = string$ (.addObj)
    selectObject: .mixObj
    Formula: "self + (Object_" + .addStr$ + "[col] * " + string$ (.gainLin) + ")"
endproc

# ============================================================
# 5. RENDER 24 CHANNELS
# ============================================================
@build_channel: 1, stem_FL, 0, 0, nyq, 0.0, "FL"
@build_channel: 2, stem_FR, 0, 0, nyq, 0.0, "FR"
@build_channel: 3, stem_FC, 0, 0, nyq, 0.0, "FC"
@build_channel: 4, stem_FW_L, 5, 0, nyq, fw_gain_dB, "FWL"
@build_channel: 5, stem_FW_R, 5 + decorr_ms, 0, nyq, fw_gain_dB, "FWR"
@build_channel: 6, stem_Amb_L, side_delay, hp_rear, lp_rear, amb_gain_dB, "SiL"
@build_channel: 7, stem_Amb_R, side_delay + decorr_ms, hp_rear, lp_rear, amb_gain_dB, "SiR"
@build_channel: 8, stem_Amb_L, side_delay + 10, hp_rear, lp_rear, rear_gain_dB, "BL"
@build_channel: 9, stem_Amb_R, side_delay + 10 + decorr_ms, hp_rear, lp_rear, rear_gain_dB, "BR"
@build_channel: 10, stem_Mid, side_delay + 15, hp_rear, lp_rear, rear_gain_dB - 3.0, "BC"
@build_channel: 11, stem_FL, upper_delay, hp_top, lp_top, upper_gain_dB, "TpFL"
@build_channel: 12, stem_FR, upper_delay + decorr_ms, hp_top, lp_top, upper_gain_dB, "TpFR"
@build_channel: 13, stem_FC, upper_delay + 5, hp_top, lp_top, upper_gain_dB - 3.0, "TpFC"
@build_channel: 14, stem_Amb_L, upper_delay + side_delay, hp_top, lp_top, upper_gain_dB, "TpSiL"
@build_channel: 15, stem_Amb_R, upper_delay + side_delay + decorr_ms, hp_top, lp_top, upper_gain_dB, "TpSiR"
@build_channel: 16, stem_Amb_L, upper_delay + side_delay + 10, hp_top, lp_top, upper_gain_dB, "TpBL"
@build_channel: 17, stem_Amb_R, upper_delay + side_delay + 10 + decorr_ms, hp_top, lp_top, upper_gain_dB, "TpBR"
@build_channel: 18, stem_Mid, upper_delay + side_delay + 15, hp_top, lp_top, upper_gain_dB - 3.0, "TpBC"
@build_channel: 19, stem_Mid, upper_delay + 25, hp_top, lp_top, upper_gain_dB - 3.0, "TpC"
@build_channel: 20, stem_FL, 4, 300, 3000, lower_gain_dB, "BFL"
@build_channel: 21, stem_FR, 4 + decorr_ms, 300, 3000, lower_gain_dB, "BFR"
@build_channel: 22, stem_FC, 4 + decorr_ms / 2, 300, 3000, lower_gain_dB - 3.0, "BFC"
@build_channel: 23, stem_LFE, 0, 20, lfe_hz, 0.0, "LFE1"
@build_channel: 24, stem_LFE, 0, 20, lfe_hz, 0.0, "LFE2"

# ============================================================
# 6. HEADPHONE / BINAURAL ENGINE
# ============================================================
if render_headphone_output = 1
    if headphone_mode = 1
        appendInfoLine: "Rendering Transparent Headphone Preview..."

        Create Sound from formula: "sum_L", 1, 0, dur, sr, "0"
        sum_L = selected ("Sound")
        Create Sound from formula: "sum_R", 1, 0, dur, sr, "0"
        sum_R = selected ("Sound")
        Create Sound from formula: "sum_C", 1, 0, dur, sr, "0"
        sum_C = selected ("Sound")

        # Clean reference: FL / FR + tiny FC only
        @add_to_mix: sum_L, outCh[1], 1.0
        @add_to_mix: sum_R, outCh[2], 1.0
        @add_to_mix: sum_C, outCh[3], 0.10

        @add_to_mix: sum_L, sum_C, 0.707
        @add_to_mix: sum_R, sum_C, 0.707

        selectObject: sum_L, sum_R
        hpOut = Combine to stereo
        Rename: sourceName$ + "_Headphone_Preview"
        removeObject: sum_L, sum_R, sum_C

    else
        appendInfoLine: "Rendering True Binaural Output using KEMAR Symmetry..."

        for i from 1 to 24
            kMapL$[i] = ""
            kMapR$[i] = ""
        endfor

        # Use only filenames confirmed to exist in the CNMAT folder

        # Front pair
        kMapL$[1] = "L-12e036a.wav"
        kMapR$[1] = "L-12e324a.wav"
        kMapL$[2] = "L-12e324a.wav"
        kMapR$[2] = "L-12e036a.wav"

        # Front center
        kMapL$[3] = "L12e000a.wav"
        kMapR$[3] = "L12e000a.wav"

        # Side pair
        kMapL$[6] = "L12e072a.wav"
        kMapR$[6] = "L12e288a.wav"
        kMapL$[7] = "L12e288a.wav"
        kMapR$[7] = "L12e072a.wav"

        # Back pair
        kMapL$[8] = "L12e144a.wav"
        kMapR$[8] = "L12e216a.wav"
        kMapL$[9] = "L12e216a.wav"
        kMapR$[9] = "L12e144a.wav"

        # Top front pair
        kMapL$[11] = "L-53e036a.wav"
        kMapR$[11] = "L-53e324a.wav"
        kMapL$[12] = "L-53e324a.wav"
        kMapR$[12] = "L-53e036a.wav"

        # Top side pair
        kMapL$[14] = "L53e072a.wav"
        kMapR$[14] = "L53e288a.wav"
        kMapL$[15] = "L53e288a.wav"
        kMapR$[15] = "L53e072a.wav"

        # Top back pair
        kMapL$[16] = "L53e144a.wav"
        kMapR$[16] = "L53e216a.wav"
        kMapL$[17] = "L53e216a.wav"
        kMapR$[17] = "L53e144a.wav"

        # Top center
        kMapL$[19] = "L90e000a.wav"
        kMapR$[19] = "L90e000a.wav"

        Create Sound from formula: "ear_L", 1, 0, dur, sr, "0"
        ear_L = selected ("Sound")
        Create Sound from formula: "ear_R", 1, 0, dur, sr, "0"
        ear_R = selected ("Sound")

        missingPairs = 0

        for i from 1 to 24
            if kMapL$[i] <> ""
                path_L$ = hrir_folder$ + kMapL$[i]
                path_R$ = hrir_folder$ + kMapR$[i]

                if fileReadable (path_L$) and fileReadable (path_R$)
                    # Left ear HRIR
                    Read from file: path_L$
                    hrir_L_raw = selected ("Sound")

                    selectObject: hrir_L_raw
                    hrir_L_sr = Get sampling frequency
                    if hrir_L_sr <> sr
                        hrir_L_resamp = Resample: sr, 50
                        removeObject: hrir_L_raw
                        hrir_L_raw = hrir_L_resamp
                    endif

                    selectObject: hrir_L_raw
                    hrir_L_ch = Get number of channels
                    if hrir_L_ch > 1
                        hrir_L_mono = Extract one channel: 1
                        removeObject: hrir_L_raw
                        hrir_L_raw = hrir_L_mono
                    endif

                    # Right ear HRIR
                    Read from file: path_R$
                    hrir_R_raw = selected ("Sound")

                    selectObject: hrir_R_raw
                    hrir_R_sr = Get sampling frequency
                    if hrir_R_sr <> sr
                        hrir_R_resamp = Resample: sr, 50
                        removeObject: hrir_R_raw
                        hrir_R_raw = hrir_R_resamp
                    endif

                    selectObject: hrir_R_raw
                    hrir_R_ch = Get number of channels
                    if hrir_R_ch > 1
                        hrir_R_mono = Extract one channel: 1
                        removeObject: hrir_R_raw
                        hrir_R_raw = hrir_R_mono
                    endif

                    # Contribution scale by role
                    scale = 1.0
                    if i = 3
                        scale = 0.12
                    endif
                    if i = 6 or i = 7
                        scale = 0.10
                    endif
                    if i = 8 or i = 9
                        scale = 0.08
                    endif
                    if i = 11 or i = 12
                        scale = 0.06
                    endif
                    if i = 14 or i = 15
                        scale = 0.05
                    endif
                    if i = 16 or i = 17
                        scale = 0.04
                    endif
                    if i = 19
                        scale = 0.03
                    endif

                    # Convolve to ears
                    selectObject: outCh[i], hrir_L_raw
                    conv_L = Convolve: "sum", "zero"
                    @add_to_mix: ear_L, conv_L, scale

                    selectObject: outCh[i], hrir_R_raw
                    conv_R = Convolve: "sum", "zero"
                    @add_to_mix: ear_R, conv_R, scale

                    removeObject: hrir_L_raw, hrir_R_raw, conv_L, conv_R
                else
                    missingPairs = missingPairs + 1
                endif
            endif
        endfor

        if missingPairs > 0
            appendInfoLine: ">>> BINAURAL RENDER ABORTED: " + string$ (missingPairs) + " missing HRIR pair(s) <<<"
            removeObject: ear_L, ear_R
            render_headphone_output = 0
        else
            selectObject: ear_L, ear_R
            hpOut = Combine to stereo
            Rename: sourceName$ + "_True_Binaural"
            removeObject: ear_L, ear_R
        endif
    endif

    if render_headphone_output = 1
        selectObject: hpOut
        rawPeak = Get absolute extremum: 0, 0, "None"
        if rawPeak < 0.0001
            rawPeak = 0.0001
        endif
        normGain = headroomLin / rawPeak
        Formula: "self * " + string$ (normGain)
    endif
endif

# ============================================================
# 7. 24-CHANNEL COMBINE
# ============================================================
if render_22_2_output = 1
    selectObject: outCh[1]
    for i from 2 to 24
        plusObject: outCh[i]
    endfor
    ch24Out = Combine to stereo
    Rename: sourceName$ + "_22_2_Array"

    selectObject: ch24Out
    rawPeak24 = Get absolute extremum: 0, 0, "None"
    if rawPeak24 < 0.0001
        rawPeak24 = 0.0001
    endif
    normGain24 = headroomLin / rawPeak24
    Formula: "self * " + string$ (normGain24)
endif

# ============================================================
# 8. CLEANUP
# ============================================================
removeObject: stem_L, stem_R, stem_Mid
removeObject: stem_FL, stem_FR, stem_FC, stem_FW_L, stem_FW_R
removeObject: stem_Amb_L, stem_Amb_R
for i from 1 to 24
    removeObject: outCh[i]
endfor

appendInfoLine: "Done."

# ============================================================
# 9. VISUALIZATION
# ============================================================

if draw_visualization

    Erase all

    # Collect preset name for display
    if preset = 1
        presetName$ = "Cinematic Film"
    elsif preset = 2
        presetName$ = "Subtle Music"
    else
        presetName$ = "Wide Mono"
    endif

    if numInCh = 2
        inTypeStr$ = "Stereo"
    else
        inTypeStr$ = "Mono"
    endif

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##22.2 Synthetic Stem Renderer##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... sourceName$
        ... + "  |  " + inTypeStr$ + " in  →  24 ch out"
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + fixed$(dur, 2) + " s"

    # ----------------------------------------------------------
    # PANEL A: 3-LAYER DOME MAP  (left column, rows 1-3)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.95, 4.60
    Select inner viewport: 0.40, 4.00, 1.05, 4.50

    Axes: -1.8, 1.8, -1.6, 2.0

    # Background
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.8, 1.8, -1.6, 2.0

    # ---- ring guides
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw ellipse: -1.25, 1.25, -0.55, 0.55
    Draw ellipse: -0.95, 0.95, 0.30, 0.95 + 0.80
    Draw ellipse: -0.55, 0.55, -0.95, -0.30

    # Crosshairs
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, -1.5, 0, 1.9
    Draw line: -1.7, 0, 1.7, 0

    # ---- MIDDLE LAYER speakers ----
    gFront = 1.0
    gAmb = 10 ^ (amb_gain_dB / 20)
    gUpper = 10 ^ (upper_gain_dB / 20)
    gLower = 10 ^ (lower_gain_dB / 20)
    gFW = 10 ^ (fw_gain_dB / 20)

    dotScaleM = 2.5 + gFront * 3.5   
    dotScaleFW = 2.5 + gFW * 3.5
    dotScaleA = 2.5 + gAmb * 3.5
    dotScaleU = 2.5 + gUpper * 3.5
    dotScaleBot = 2.5 + gLower * 3.5

    # --- Front pair
    Paint circle (mm): "{0.25, 0.50, 0.72}", -0.85, 0.0, dotScaleM
    Paint circle (mm): "{0.25, 0.50, 0.72}", 0.85, 0.0, dotScaleM
    Paint circle (mm): "{0.25, 0.50, 0.72}", 0.0, 0.18, dotScaleM
    Paint circle (mm): "{0.40, 0.60, 0.78}", -1.18, 0.0, dotScaleFW
    Paint circle (mm): "{0.40, 0.60, 0.78}", 1.18, 0.0, dotScaleFW
    Paint circle (mm): "{0.25, 0.50, 0.72}", -1.22, -0.18, dotScaleA
    Paint circle (mm): "{0.25, 0.50, 0.72}", 1.22, -0.18, dotScaleA
    Paint circle (mm): "{0.25, 0.50, 0.72}", -0.75, -0.42, dotScaleA
    Paint circle (mm): "{0.25, 0.50, 0.72}", 0.75, -0.42, dotScaleA
    Paint circle (mm): "{0.25, 0.50, 0.72}", 0.0, -0.50, dotScaleA

    # --- UPPER LAYER
    yUp = 0.80
    Paint circle (mm): "{0.82, 0.55, 0.22}", -0.72, 0.12 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", 0.72, 0.12 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", 0.0, 0.25 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", -0.88, -0.05 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", 0.88, -0.05 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", -0.62, -0.30 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", 0.62, -0.30 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", 0.0, -0.38 + yUp, dotScaleU
    Paint circle (mm): "{0.82, 0.55, 0.22}", 0.0, 0.0 + yUp + 0.30, dotScaleU

    # --- LOWER LAYER
    yBot = -0.60
    Paint circle (mm): "{0.35, 0.68, 0.42}", -0.42, 0.10 + yBot, dotScaleBot
    Paint circle (mm): "{0.35, 0.68, 0.42}", 0.42, 0.10 + yBot, dotScaleBot
    Paint circle (mm): "{0.35, 0.68, 0.42}", 0.0, 0.20 + yBot, dotScaleBot

    # --- LFE pair
    Paint circle (mm): "{0.82, 0.28, 0.28}", -0.22, -1.30, 3.0
    Paint circle (mm): "{0.82, 0.28, 0.28}", 0.22, -1.30, 3.0

    # --- Listener at origin
    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 2.2
    Font size: 5
    Colour: "{0.15, 0.45, 0.18}"
    Text: 0, "centre", -0.15, "half", "L"

    # --- Layer legend
    Font size: 5
    Colour: "{0.25, 0.50, 0.72}"
    Text: -1.68, "left", -0.55, "half", "Mid"
    Colour: "{0.82, 0.55, 0.22}"
    Text: -1.68, "left", 0.78, "half", "Top"
    Colour: "{0.35, 0.68, 0.42}"
    Text: -1.68, "left", -1.20, "half", "Bot"
    Colour: "{0.82, 0.28, 0.28}"
    Text: -1.68, "left", -1.38, "half", "LFE"

    Colour: "Black"
    Line width: 1
    Draw inner box
    
    # REMOVED: Text top: "no", "24-ch dome map  (dot size = gain,  layer colour = elevation)"

    # ----------------------------------------------------------
    # PANEL B: STEM ROUTING FLOW (right column, top half)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.95, 3.00
    Select inner viewport: 4.45, 7.75, 1.05, 2.92

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1

    # --- Column 1: INPUT
    Font size: 6
    Colour: "{0.20, 0.38, 0.58}"
    Text: 0.08, "centre", 0.93, "half", "##INPUT##"
    Paint rectangle: "{0.78, 0.88, 0.96}", 0.01, 0.15, 0.74, 0.88
    Font size: 5
    Colour: "{0.18, 0.35, 0.55}"
    Text: 0.08, "centre", 0.81, "half", inTypeStr$
    Text: 0.08, "centre", 0.76, "half", string$(numInCh) + " ch"

    # --- Column 2: BASE STEMS
    Font size: 6
    Colour: "{0.20, 0.38, 0.58}"
    Text: 0.38, "centre", 0.93, "half", "##STEMS##"

    stemNames$[1] = "stem_L"
    stemNames$[2] = "stem_R"
    stemNames$[3] = "stem_Mid"
    stemNames$[4] = "stem_FL"
    stemNames$[5] = "stem_FR"
    stemNames$[6] = "stem_FC"
    stemNames$[7] = "stem_Amb_L"
    stemNames$[8] = "stem_Amb_R"
    stemNames$[9] = "stem_FW_L"
    stemNames$[10] = "stem_FW_R"

    for s from 1 to 10
        sy = 0.86 - (s - 1) * 0.082
        Paint rectangle: "{0.88, 0.92, 0.98}", 0.24, 0.52, sy - 0.028, sy + 0.028
        Font size: 4
        Colour: "{0.25, 0.40, 0.60}"
        Text: 0.38, "centre", sy, "half", stemNames$[s]
    endfor

    # --- Column 3: CHANNEL GROUPS
    Font size: 6
    Colour: "{0.20, 0.38, 0.58}"
    Text: 0.76, "centre", 0.93, "half", "##GROUPS##"

    Paint rectangle: "{0.78, 0.88, 0.96}", 0.62, 0.90, 0.76, 0.88
    Font size: 4
    Colour: "{0.18, 0.35, 0.55}"
    Text: 0.76, "centre", 0.82, "half", "Front (1-3)"
    
    Paint rectangle: "{0.78, 0.88, 0.96}", 0.62, 0.90, 0.66, 0.74
    Text: 0.76, "centre", 0.70, "half", "Wides (4-5)"
    
    Paint rectangle: "{0.78, 0.88, 0.96}", 0.62, 0.90, 0.56, 0.64
    Text: 0.76, "centre", 0.60, "half", "Surr (6-10)"
    
    Paint rectangle: "{0.82, 0.78, 0.60}", 0.62, 0.90, 0.44, 0.54
    Font size: 4
    Colour: "{0.52, 0.35, 0.12}"
    Text: 0.76, "centre", 0.49, "half", "Upper (11-19)"
    
    Paint rectangle: "{0.72, 0.88, 0.75}", 0.62, 0.90, 0.34, 0.42
    Colour: "{0.22, 0.52, 0.28}"
    Text: 0.76, "centre", 0.38, "half", "Lower (20-22)"
    
    Paint rectangle: "{0.95, 0.82, 0.82}", 0.62, 0.90, 0.24, 0.32
    Colour: "{0.65, 0.18, 0.18}"
    Text: 0.76, "centre", 0.28, "half", "LFE (23-24)"

    # --- Arrows
    Colour: "{0.75, 0.75, 0.75}"
    Line width: 1
    Draw arrow: 0.15, 0.81, 0.24, 0.82
    Draw arrow: 0.52, 0.82, 0.62, 0.82
    Draw arrow: 0.52, 0.74, 0.62, 0.70
    Draw arrow: 0.52, 0.66, 0.62, 0.60
    Draw arrow: 0.52, 0.56, 0.62, 0.49
    Draw arrow: 0.52, 0.46, 0.62, 0.38
    Draw arrow: 0.52, 0.36, 0.62, 0.28

    Colour: "Black"
    Line width: 1
    Draw inner box
    
    # REMOVED: Text top: "no", "Signal routing  (Input → Stems → Output groups)"

   # ----------------------------------------------------------
    # ALIGNED PANEL TITLES (A & B)
    # ----------------------------------------------------------
    # Create a viewport that spans the entire 8x8 window
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"

    # Panel A Title (Moved up from 7.15 to 7.25)
    Text: 2.20, "centre", 7.25, "half", "24-ch dome map  (dot size = gain,  layer colour = elevation)"
    
    # Panel B Title (Moved up from 7.15 to 7.25)
    Text: 6.10, "centre", 7.25, "half", "Signal routing  (Input → Stems → Output groups)"


    # ----------------------------------------------------------
    # PANEL C: 24-CHANNEL GAIN/DELAY BARS (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.55, 7.75, 3.12, 4.52

    # Channel gains (dB) and delays (ms) for 24 channels
    chGainDb[1]  = 0.0
    chDelay[1]   = 0.0
    chGainDb[2]  = 0.0
    chDelay[2]   = 0.0
    chGainDb[3]  = 0.0
    chDelay[3]   = 0.0
    chGainDb[4]  = fw_gain_dB
    chDelay[4]   = 5.0
    chGainDb[5]  = fw_gain_dB
    chDelay[5]   = 5.0 + decorr_ms
    chGainDb[6]  = amb_gain_dB
    chDelay[6]   = side_delay
    chGainDb[7]  = amb_gain_dB
    chDelay[7]   = side_delay + decorr_ms
    chGainDb[8]  = rear_gain_dB
    chDelay[8]   = side_delay + 10
    chGainDb[9]  = rear_gain_dB
    chDelay[9]   = side_delay + 10 + decorr_ms
    chGainDb[10] = rear_gain_dB - 3.0
    chDelay[10]  = side_delay + 15
    chGainDb[11] = upper_gain_dB
    chDelay[11]  = upper_delay
    chGainDb[12] = upper_gain_dB
    chDelay[12]  = upper_delay + decorr_ms
    chGainDb[13] = upper_gain_dB - 3.0
    chDelay[13]  = upper_delay + 5
    chGainDb[14] = upper_gain_dB
    chDelay[14]  = upper_delay + side_delay
    chGainDb[15] = upper_gain_dB
    chDelay[15]  = upper_delay + side_delay + decorr_ms
    chGainDb[16] = upper_gain_dB
    chDelay[16]  = upper_delay + side_delay + 10
    chGainDb[17] = upper_gain_dB
    chDelay[17]  = upper_delay + side_delay + 10 + decorr_ms
    chGainDb[18] = upper_gain_dB - 3.0
    chDelay[18]  = upper_delay + side_delay + 15
    chGainDb[19] = upper_gain_dB - 3.0
    chDelay[19]  = upper_delay + 25
    chGainDb[20] = lower_gain_dB
    chDelay[20]  = 4.0
    chGainDb[21] = lower_gain_dB
    chDelay[21]  = 4.0 + decorr_ms
    chGainDb[22] = lower_gain_dB - 3.0
    chDelay[22]  = 4.0 + decorr_ms / 2
    chGainDb[23] = 0.0
    chDelay[23]  = 0.0
    chGainDb[24] = 0.0
    chDelay[24]  = 0.0

    chName$[1]  = "FL"
    chName$[2]  = "FR"
    chName$[3]  = "FC"
    chName$[4]  = "FWL"
    chName$[5]  = "FWR"
    chName$[6]  = "SiL"
    chName$[7]  = "SiR"
    chName$[8]  = "BL"
    chName$[9]  = "BR"
    chName$[10] = "BC"
    chName$[11] = "TpFL"
    chName$[12] = "TpFR"
    chName$[13] = "TpFC"
    chName$[14] = "TpSiL"
    chName$[15] = "TpSiR"
    chName$[16] = "TpBL"
    chName$[17] = "TpBR"
    chName$[18] = "TpBC"
    chName$[19] = "TpC"
    chName$[20] = "BFL"
    chName$[21] = "BFR"
    chName$[22] = "BFC"
    chName$[23] = "LFE1"
    chName$[24] = "LFE2"

    Axes: 0, 1, 0.2, 24.8
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0.2, 24.8

    Colour: "{0.82, 0.82, 0.82}"
    Dotted line
    Draw line: 1.0, 0.2, 1.0, 24.8
    Solid line

    for ch from 1 to 24
        gainLin = 10 ^ (chGainDb[ch] / 20)
        y = 25 - ch   
        yLo = y - 0.38
        yHi = y + 0.38

        if ch <= 3
            Paint rectangle: "{0.25, 0.50, 0.72}", 0, gainLin, yLo, yHi
        elsif ch <= 5
            Paint rectangle: "{0.48, 0.68, 0.85}", 0, gainLin, yLo, yHi
        elsif ch <= 10
            Paint rectangle: "{0.35, 0.58, 0.78}", 0, gainLin, yLo, yHi
        elsif ch <= 19
            Paint rectangle: "{0.82, 0.55, 0.22}", 0, gainLin, yLo, yHi
        elsif ch <= 22
            Paint rectangle: "{0.35, 0.68, 0.42}", 0, gainLin, yLo, yHi
        else
            Paint rectangle: "{0.82, 0.28, 0.28}", 0, gainLin, yLo, yHi
        endif

        Font size: 4
        Colour: "{0.30, 0.30, 0.30}"
        Text: -0.01, "right", y, "half", chName$[ch]

        delayX = 0.86 + (chDelay[ch] / 80) * 0.13
        if delayX > 0.99
            delayX = 0.99
        endif
        Paint circle (mm): "{0.50, 0.50, 0.50}", delayX, y, 1.2
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Ch"
    Text bottom: "yes", "Gain (linear 0–1)          ● delay"
    Text top: "no", "Per-channel gain (bar) & delay (dot)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    if render_headphone_output = 1
        selectObject: hpOut
        hpPeak = Get absolute extremum: 0, 0, "None"
        if hpPeak < 0.001
            hpPeak = 0.001
        endif
        outDurViz = Get total duration
        Axes: 0, outDurViz, -hpPeak * 1.15, hpPeak * 1.15
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -hpPeak * 1.15, hpPeak * 1.15
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, outDurViz, 0

        selectObject: hpOut
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -hpPeak * 1.15, hpPeak * 1.15, "no", "Curve"
        removeObject: vizL

        selectObject: hpOut
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -hpPeak * 1.15, hpPeak * 1.15, "no", "Curve"
        removeObject: vizR

        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        if headphone_mode = 1
            Text top: "no", "Headphone fold-down  (blue = L ear,  orange = R ear)"
        else
            Text top: "no", "True Binaural output  (blue = L ear,  orange = R ear)"
        endif
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"

    elsif render_22_2_output = 1
        selectObject: ch24Out
        outDurViz = Get total duration
        outPeak24 = Get absolute extremum: 0, 0, "None"
        if outPeak24 < 0.001
            outPeak24 = 0.001
        endif
        ampViz = outPeak24 * 1.15

        Axes: 0, outDurViz, -ampViz, ampViz
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, outDurViz, 0

        selectObject: ch24Out
        Extract one channel: 1
        vizFL = selected("Sound")
        Colour: "{0.25, 0.50, 0.72}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vizFL

        selectObject: ch24Out
        Extract one channel: 2
        vizFR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vizFR

        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "FL & FR of 24-ch array  (blue = FL,  orange = FR)"
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
    endif

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + inTypeStr$ + " → 24 ch  |  " + sourceName$
        ... + "  |  " + fixed$(dur, 2) + " s  @" + string$(sr) + " Hz"
    Text: 0.02, "left", 0.28, "half",
        ... "FW=" + fixed$(fw_gain_dB, 1) + "dB"
        ... + "  Amb=" + fixed$(amb_gain_dB, 1) + "dB"
        ... + "  Upper=" + fixed$(upper_gain_dB, 1) + "dB"
        ... + "  Lower=" + fixed$(lower_gain_dB, 1) + "dB"
        ... + "  SideDly=" + fixed$(side_delay, 0) + "ms"
        ... + "  TopDly=" + fixed$(upper_delay, 0) + "ms"
        ... + "  DecorrΔ=" + fixed$(decorr_ms, 1) + "ms"
        ... + "  Ceil=" + fixed$(headroom_dBFS, 1) + "dBFS"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Reset drawing state
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# Select a sensible final object
if render_headphone_output = 1
    if play_headphone_result = 1
        selectObject: hpOut
        Play
    endif
    selectObject: hpOut
elsif render_22_2_output = 1
    selectObject: ch24Out
endif