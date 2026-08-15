# ============================================================
# Praat AudioTools - Ikeda_audiovisual.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1.2 hybrid synchronization (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# IKEDA-INSPIRED AUDIOVISUAL STUDIES
#
# IMPORTANT CONCEPTUAL SCOPE
#   This script does NOT claim to reconstruct, emulate, or model Ryoji Ikeda's
#   works at sample level. It creates four small Praat studies that investigate
#   selected principles associated with those projects:
#
#   1. test pattern-inspired Binary Transduction
#      One generated binary word is the shared DATA OBJECT. Its bits determine
#      the barcode image, sonic pulse frequency, spectral/noise ratio and pan.
#      Thus audio and image are transformations of the same data rather than
#      two independent patterns that merely share a frame counter.
#
#      Ryoji Ikeda's test pattern operates at much more extreme display rates
#      (the artist describes points reaching hundreds of frames per second) and
#      explicitly tests both device performance and human perception. Praat's
#      Demo window cannot reproduce that technological/perceptual scale. The
#      present study preserves the data-transduction principle only.
#
#   2. datamatics-inspired Data Scan
#      A seeded numerical matrix is the shared source. A scan traverses its
#      cells; the active value determines both visual emphasis and the sound's
#      logarithmic frequency/amplitude/pan mapping.
#
#   3. spectra-inspired White-Light / Energy Field
#      This is an abstraction, not a reconstruction of spectra. A single slow
#      energy control drives both a minimal beating/high-frequency sound field
#      and the width/intensity of a white visual beam. The original spectra is
#      a site-specific large-scale white-light project; screen simulation in a
#      Demo window cannot reproduce its spatial or luminous conditions.
#
#   4. supercodex-inspired Data Pulse Field
#      A binary word is decomposed into sixteen micro-events. The same sixteen
#      bits are shown as barcode cells and rendered as a precisely timed pulse
#      packet. No claim is made that supercodex is a "genome barcode" work.
#
# AUDIOVISUAL SYNCHRONIZATION
#   v2.1.2 uses a HYBRID periodic hard-sync architecture. The master audio is
#   divided into short frame-aligned sync blocks (default 0.5 s). For each block:
#
#       asynchronous Play block k
#       -> pace its visual frames against a LOCAL stopwatch
#       -> skip a visual frame if rendering has already missed its deadline
#       -> hard re-lock when block k+1 starts
#
#   Drift therefore cannot accumulate across the entire piece as it could with
#   one long asynchronous playback. At the same time, playback is restarted only
#   once per sync block rather than once per visual frame as in exact lockstep.
#
#   This is a practical compromise for Praat: smoother audio than v2.1.1 exact
#   frame/chunk playback, but bounded audiovisual timing error unlike v2.1.
#   The final visual state is also held briefly after the last nominal boundary
#   to absorb small output-device latency.
#
# DATA / AUDIO / IMAGE RELATION
#   The governing principle is not "audio event X occurs when visual event X
#   occurs" but:
#
#       DATA -> audio mapping
#            -> visual mapping
#
#   Synchronization therefore follows from a shared source representation.
#
# FLICKER NOTE
#   test pattern itself investigates perceptual/device limits. The present
#   script defaults to a reduced-change mode in which binary states are held
#   for several display frames. High_flicker_mode removes that hold, but even
#   then the Demo window remains far below the original project's extreme rates.
#
# v2.1.2 hybrid synchronization:
#   - Added frame-aligned Sync_block_s (default 0.5 s).
#   - One asynchronous audio start per block, not per frame and not per piece.
#   - Local stopwatch is reset for every block, bounding cumulative drift.
#   - Late visual frames are skipped instead of accumulating visual delay.
#   - Final visual state remains visible for a short latency guard.
#   - Shared-data mappings and sound synthesis are unchanged.
#
# v2.1.1 synchronization fix:
#   - Removed asynchronous Play + stopwatch/sleep visual pacing.
#   - Restored pre-sliced blocking frame/chunk playback from v2.0.
#   - Uses ceiling(total duration * fps), so the final short frame/chunk is
#     retained instead of truncating the audio tail.
#   - New shared-data mappings and conceptual corrections are unchanged.
#
# v2.1 changes:
#   - removed the false "models four Ikeda works at sample level" claim
#   - renamed all modes as inspired studies / abstractions
#   - removed unsupported "Genome Barcodes" description of supercodex
#   - audio and visuals now derive from the SAME generated data/control source
#   - genuine binary-to-audio mapping in test-pattern and supercodex studies
#   - seeded numerical matrix drives both sound and image in datamatics study
#   - shared energy control drives both audio and light in spectra study
#   - v2.1.1 restores exact frame/chunk lockstep synchronization
#   - visual frame rate remains user-selectable; default restored to 8 fps
#   - exact output duration; no floor(totalDur/step) tail loss
#   - reproducible Random_seed
#   - Master_volume now matters; only DOWN-ONLY peak protection follows it
#   - efficient Formula(part) rendering; no whole-master Formula per event
#   - stereo mappings are data-derived and equal-power where relevant
#   - master Sound remains in Objects after playback for analysis/reuse
#   - sync QC reports skipped/late frames and block overruns
#
# Primary conceptual references:
#   Ryoji Ikeda Studio: test pattern, datamatics, spectra project pages;
#   official supercodex recording/live-set listings.
# ============================================================

form Ikeda-inspired Audiovisual Studies v2.1.2
    optionmenu Study 1
        option test pattern-inspired Binary Transduction
        option datamatics-inspired Data Scan
        option spectra-inspired White-Light Field
        option supercodex-inspired Data Pulse Field

    positive Duration_s 16
    integer Audio_sample_rate_Hz 44100
    positive Visual_frame_rate_Hz 8
    positive Sync_block_s 0.5
    integer Random_seed 0
    real Master_volume 0.75
    boolean Enable_color_accents 1
    boolean High_flicker_mode 0
endform

# ---------------------------------------------------------------------------
# 1. VALIDATION / LABELS
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if audio_sample_rate_Hz < 16000 or audio_sample_rate_Hz > 192000
    exitScript: "Audio sample rate must be between 16000 and 192000 Hz."
endif
if visual_frame_rate_Hz < 4 or visual_frame_rate_Hz > 20
    exitScript: "Visual frame rate must be between 4 and 20 Hz. 8 Hz is recommended."
endif
if sync_block_s < 0.20 or sync_block_s > 2.0
    exitScript: "Sync block must be between 0.20 and 2.0 seconds. 0.5 s is recommended."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if master_volume <= 0 or master_volume > 2
    exitScript: "Master volume must be > 0 and <= 2."
endif

if study = 1
    studyName$ = "test pattern-inspired Binary Transduction"
elsif study = 2
    studyName$ = "datamatics-inspired Data Scan"
elsif study = 3
    studyName$ = "spectra-inspired White-Light Field"
else
    studyName$ = "supercodex-inspired Data Pulse Field"
endif

sr = audio_sample_rate_Hz
safeTop = 0.45*sr
frameRate = visual_frame_rate_Hz
frameStep = 1/frameRate
totalFrames = ceiling(duration_s*frameRate)
framesPerSyncBlock = max(1,round(sync_block_s*frameRate))
syncBlock = framesPerSyncBlock*frameStep
totalSyncBlocks = ceiling(totalFrames/framesPerSyncBlock)
finalLatencyGuard = min(0.15,max(0.04,0.50*frameStep))

# Default state-change hold keeps the harshest binary modes from changing the
# entire barcode every display refresh. High-flicker mode removes this hold.
if high_flicker_mode
    holdFrames = 1
else
    holdFrames = max(1,round(frameRate/4))
endif

# ---------------------------------------------------------------------------
# 2. RANDOMNESS
# ---------------------------------------------------------------------------
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

uid$ = string$(randomInteger(10000,99999))

# ---------------------------------------------------------------------------
# 3. SHARED DATA OBJECTS
# ---------------------------------------------------------------------------
# Binary words are kept as exact 16-bit integers (0..65535).
dataWord# = zero#(totalFrames)
dataNorm# = zero#(totalFrames)
bitCount# = zero#(totalFrames)
transitionCount# = zero#(totalFrames)
framePan# = zero#(totalFrames)

# datamatics-inspired fixed numerical data field.
gridN = 12
gridCells = gridN*gridN
gridValue# = zero#(gridCells)

for cell from 1 to gridCells
    gridValue#[cell] = randomUniform(0,1)
endfor

lastWord = randomInteger(0,65535)

for frame from 1 to totalFrames
    # Binary studies may hold one word for several display frames.
    if study = 1 or study = 4
        if frame = 1 or ((frame-1) mod holdFrames)=0
            lastWord = randomInteger(0,65535)
        endif
        word = lastWord

    elsif study = 2
        # For datamatics the current scanned cell IS the data object. We still
        # create a 16-bit representation for HUD/QC and optional accents.
        scan = ((frame-1) mod gridCells)+1
        word = round(65535*gridValue#[scan])

    else
        # spectra: binary data is not the governing source; keep a word only
        # for a stable HUD identifier.
        word = randomInteger(0,65535)
    endif

    dataWord#[frame] = word
    dataNorm#[frame] = word/65535

    ones = 0
    changes = 0
    previousBit = floor(word/1) mod 2

    for bit from 0 to 15
        thisBit = floor(word/(2^bit)) mod 2
        ones = ones+thisBit

        if bit > 0
            if thisBit <> previousBit
                changes = changes+1
            endif
        endif
        previousBit = thisBit
    endfor

    bitCount#[frame] = ones
    transitionCount#[frame] = changes
    framePan#[frame] = 0.05+0.90*dataNorm#[frame]
endfor

# ---------------------------------------------------------------------------
# 4. MASTER SOUND
# ---------------------------------------------------------------------------
masterSound = Create Sound from formula:
    ... "IkedaStudy_" + uid$,2,0,duration_s,sr,"0"

# ---------------------------------------------------------------------------
# 5A. TEST PATTERN-INSPIRED BINARY TRANSDUCTION
# ---------------------------------------------------------------------------
if study = 1
    for frame from 1 to totalFrames
        t0 = (frame-1)*frameStep
        t1 = min(duration_s,frame*frameStep)

        if t0 < duration_s
            eventDur = min(t1-t0,0.042)
            eventEnd = min(duration_s,t0+eventDur)

            # Shared-data mapping:
            #   Hamming weight -> pitch
            #   bit transitions -> noise proportion / amplitude
            #   normalized word -> stereo position
            f = min(safeTop,1800+570*bitCount#[frame])
            transitionNorm = transitionCount#[frame]/15
            amp = 0.08+0.16*transitionNorm
            noiseMix = 0.05+0.35*transitionNorm
            toneGain = sqrt(1-noiseMix)
            noiseGain = sqrt(noiseMix)
            pan = framePan#[frame]
            gL = sqrt(1-pan)
            gR = sqrt(pan)
            phase = 2*pi*dataNorm#[frame]

            t0$ = fixed$(t0,9)
            dur$ = fixed$(max(1/sr,eventDur),9)
            age$ = "(x-" + t0$ + ")"
            env$ = "(0.5-0.5*cos(2*pi*" + age$ + "/" + dur$ + "))"
            source$ = "(" + fixed$(toneGain,8) + "*sin(2*pi*"
                ... + fixed$(f,6) + "*" + age$ + "+" + fixed$(phase,9)
                ... + ")+" + fixed$(noiseGain,8) + "*randomGauss(0,1))"

            selectObject: masterSound
            Formula (part): t0,eventEnd,1,2,
                ... "self+if row=1 then " + fixed$(amp*gL,9)
                ... + "*" + source$ + "*" + env$
                ... + " else " + fixed$(amp*gR,9)
                ... + "*" + source$ + "*" + env$ + " fi"
        endif
    endfor

# ---------------------------------------------------------------------------
# 5B. DATAMATICS-INSPIRED DATA SCAN
# ---------------------------------------------------------------------------
elsif study = 2
    for frame from 1 to totalFrames
        t0 = (frame-1)*frameStep
        t1 = min(duration_s,frame*frameStep)

        if t0 < duration_s
            scan = ((frame-1) mod gridCells)+1
            value = gridValue#[scan]
            colIndex = ((scan-1) mod gridN)+1

            # Log-frequency map, approximately 180 Hz .. 8 kHz before clamp.
            f = min(safeTop,180*2^(5.48*value))
            amp = 0.055+0.20*value
            eventDur = min(t1-t0,0.032+0.018*value)
            eventEnd = min(duration_s,t0+eventDur)
            pan = 0.05+0.90*(colIndex-1)/(gridN-1)
            gL = sqrt(1-pan)
            gR = sqrt(pan)
            phase = 2*pi*value

            t0$ = fixed$(t0,9)
            dur$ = fixed$(max(1/sr,eventDur),9)
            age$ = "(x-" + t0$ + ")"
            env$ = "(0.5-0.5*cos(2*pi*" + age$ + "/" + dur$ + "))"
            source$ = "sin(2*pi*" + fixed$(f,6) + "*" + age$
                ... + "+" + fixed$(phase,9) + ")"

            selectObject: masterSound
            Formula (part): t0,eventEnd,1,2,
                ... "self+if row=1 then " + fixed$(amp*gL,9)
                ... + "*" + source$ + "*" + env$
                ... + " else " + fixed$(amp*gR,9)
                ... + "*" + source$ + "*" + env$ + " fi"
        endif
    endfor

# ---------------------------------------------------------------------------
# 5C. SPECTRA-INSPIRED WHITE-LIGHT / ENERGY FIELD
# ---------------------------------------------------------------------------
elsif study = 3
    # One analytic energy field drives both audio and later the visual beam.
    # The sound is intentionally minimal: slow low beating + sparse high energy.
    selectObject: masterSound
    Formula: "(0.16+0.34*(0.5+0.5*sin(2*pi*0.055*x)))"
        ... + "*(if row=1 then sin(2*pi*50*x)+0.72*sin(2*pi*50.8*x)"
        ... + "+0.10*sin(2*pi*9800*x)"
        ... + " else sin(2*pi*50.3*x)+0.72*sin(2*pi*51.1*x)"
        ... + "+0.10*sin(2*pi*9813*x) fi)"

# ---------------------------------------------------------------------------
# 5D. SUPERCODEX-INSPIRED DATA PULSE FIELD
# ---------------------------------------------------------------------------
else
    for frame from 1 to totalFrames
        t0 = (frame-1)*frameStep
        t1 = min(duration_s,frame*frameStep)

        if t0 < duration_s
            word = dataWord#[frame]
            subStep = (t1-t0)/16
            pulseDur = max(1/sr,min(0.0018,0.60*subStep))
            leftTerms$ = "0"
            rightTerms$ = "0"

            for bit from 0 to 15
                bitValue = floor(word/(2^bit)) mod 2
                onset = t0+bit*subStep
                pend = min(t1,onset+pulseDur)
                localDur = max(1/sr,pend-onset)

                # Both 0 and 1 exist sonically, but with distinct frequency and
                # level, so the complete word is represented rather than only
                # its set bits.
                if bitValue = 1
                    f = min(safeTop,1600+620*bit)
                    a = 0.070
                else
                    f = min(safeTop,800+310*bit)
                    a = 0.022
                endif

                pan = 0.03+0.94*bit/15
                gL = sqrt(1-pan)
                gR = sqrt(pan)
                phase = 2*pi*((word mod 257)/257)

                onset$ = fixed$(onset,9)
                dur$ = fixed$(localDur,9)
                age$ = "(x-" + onset$ + ")"
                env$ = "(0.5-0.5*cos(2*pi*" + age$ + "/" + dur$ + "))"
                wave$ = "sin(2*pi*" + fixed$(f,6) + "*" + age$
                    ... + "+" + fixed$(phase,9) + ")"

                leftTerms$ = leftTerms$ + "+if x>=" + onset$
                    ... + " and x<" + fixed$(pend,9)
                    ... + " then " + fixed$(a*gL,9) + "*" + wave$
                    ... + "*" + env$ + " else 0 fi"
                rightTerms$ = rightTerms$ + "+if x>=" + onset$
                    ... + " and x<" + fixed$(pend,9)
                    ... + " then " + fixed$(a*gR,9) + "*" + wave$
                    ... + "*" + env$ + " else 0 fi"
            endfor

            selectObject: masterSound
            Formula (part): t0,t1,1,2,
                ... "self+if row=1 then (" + leftTerms$
                ... + ") else (" + rightTerms$ + ") fi"
        endif
    endfor
endif

# ---------------------------------------------------------------------------
# 6. MASTER LEVEL / DOWN-ONLY PROTECTION
# ---------------------------------------------------------------------------
selectObject: masterSound
Formula: "self*master_volume"

preProtectPeak = Get absolute extremum: 0,0,"None"
preProtectRMS = Get root-mean-square: 0,0
protectionApplied = 0

if preProtectPeak > 0.98
    Scale peak: 0.98
    protectionApplied = 1
endif

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0

safeName$ = replace$(studyName$," ","_",0)
Rename: "IkedaStudy_" + safeName$
masterSound = selected("Sound")

# All stochastic audio/data has now been generated.
if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 7. INFO / CONCEPTUAL QC
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  IKEDA-INSPIRED AUDIOVISUAL STUDIES v2.1.2"
writeInfoLine: "=============================================="
appendInfoLine: "Study: ", studyName$
appendInfoLine: "Scope: conceptual/data-mapping study, NOT work reconstruction"
appendInfoLine: "Duration: ", fixed$(duration_s,3), " s"
appendInfoLine: "Audio sample rate: ", sr, " Hz"
appendInfoLine: "Visual target rate: ", fixed$(frameRate,2), " fps"
appendInfoLine: "Hybrid sync block requested / aligned: ",
    ... fixed$(sync_block_s,3), " / ", fixed$(syncBlock,3), " s"
appendInfoLine: "Frames per sync block: ", framesPerSyncBlock
appendInfoLine: "Sync blocks / visual frames: ", totalSyncBlocks, " / ", totalFrames
appendInfoLine: "Binary state hold: ", holdFrames, " frame(s)"
appendInfoLine: "Randomness: ", seedLabel$
appendInfoLine: "Master volume: ", fixed$(master_volume,3)
appendInfoLine: "Pre-protection peak/RMS: ",
    ... fixed$(preProtectPeak,4), " / ", fixed$(preProtectRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Peak protection applied: ", protectionApplied
appendInfoLine: ""

if study = 1
    appendInfoLine: "Mapping: 16-bit word -> barcode + Hamming-weight pitch + transition noise + data pan"
elsif study = 2
    appendInfoLine: "Mapping: numerical grid cell -> scan position + log-frequency + amplitude + X pan"
elsif study = 3
    appendInfoLine: "Mapping: shared slow energy control -> white beam + minimal beating/high-frequency field"
else
    appendInfoLine: "Mapping: 16-bit word -> 16 barcode cells + 16 time-aligned micro-pulses"
endif

# ---------------------------------------------------------------------------
# 8. DEMO SETUP
# ---------------------------------------------------------------------------
demo Erase all
demo Select inner viewport: 0,100,0,100
demo Axes: 0,100,0,100
demo Paint rectangle: "Black",0,100,0,100
demo Font size: 13
demo Colour: "White"
demo Text: 50,"centre",53,"half","Starting " + studyName$
demo Font size: 8
demo Colour: "{0.55,0.55,0.55}"
demo Text: 50,"centre",44,"half","hybrid periodic hard-sync / shared data-control mapping"
demoShow()

# ---------------------------------------------------------------------------
# 9. PRE-SLICE MASTER INTO FRAME-ALIGNED SYNC BLOCKS
# ---------------------------------------------------------------------------
demo Paint rectangle: "Black",0,100,0,100
demo Font size: 12
demo Colour: "White"
demo Text: 50,"centre",53,"half","Preparing hybrid A/V synchronization..."
demo Font size: 8
demo Colour: "{0.60,0.60,0.62}"
demo Text: 50,"centre",44,"half",
    ... string$(framesPerSyncBlock) + " frames per block / " + fixed$(syncBlock,3) + " s"
demoShow()

blockID# = zero#(totalSyncBlocks)

for block from 1 to totalSyncBlocks
    firstFrame = (block-1)*framesPerSyncBlock+1
    lastFrame = min(totalFrames,block*framesPerSyncBlock)
    blockStart = (firstFrame-1)*frameStep
    blockEnd = min(duration_s,lastFrame*frameStep)

    selectObject: masterSound
    Extract part: blockStart,blockEnd,"rectangular",1,"no"
    blockID#[block] = selected("Sound")
endfor

# ---------------------------------------------------------------------------
# 10. HYBRID PLAYBACK: LOCAL CLOCK + PERIODIC HARD RE-LOCK
# ---------------------------------------------------------------------------
skippedFrames = 0
lateFrames = 0
blockOverruns = 0
maxLateness = 0

for block from 1 to totalSyncBlocks
    firstFrame = (block-1)*framesPerSyncBlock+1
    lastFrame = min(totalFrames,block*framesPerSyncBlock)
    blockStart = (firstFrame-1)*frameStep
    blockEnd = min(duration_s,lastFrame*frameStep)
    blockDuration = blockEnd-blockStart

    # A new asynchronous Play also defines the next hard synchronization point.
    # The stopwatch is local to this block, so timing error cannot accumulate
    # from earlier blocks.
    stopwatch
    selectObject: blockID#[block]
    asynchronous Play

    # Starting the new block hard-stops/replaces the previous asynchronous
    # playback. Only now is it safe to remove the previous block object.
    if block > 1
        removeObject: blockID#[block-1]
    endif

    elapsed = 0

    for frame from firstFrame to lastFrame
        elapsed = elapsed+stopwatch
        targetOffset = (frame-1)*frameStep-blockStart
        waitTime = targetOffset-elapsed

        if waitTime > 0
            sleep(waitTime)
            elapsed = elapsed+stopwatch
        endif

        lateness = max(0,elapsed-targetOffset)
        maxLateness = max(maxLateness,lateness)

        # If drawing is already more than 80% of a frame late, do not render
        # stale imagery. The next due frame will catch up to the audio clock.
        skipFrame = 0
        if frame > firstFrame and lateness > 0.80*frameStep
            skipFrame = 1
            skippedFrames = skippedFrames+1
        elsif lateness > 0.25*frameStep
            lateFrames = lateFrames+1
        endif

        if skipFrame = 0
            t = (frame-1)*frameStep
            if t >= duration_s
                t = duration_s
            endif

    demo Paint rectangle: "Black",0,100,0,100

    # -----------------------------------------------------------------------
    # VISUAL 1: BINARY TRANSDUCTION
    # -----------------------------------------------------------------------
    if study = 1
        word = dataWord#[frame]
        barW = 100/16

        for bit from 0 to 15
            bitValue = floor(word/(2^bit)) mod 2
            x0 = bit*barW
            x1 = (bit+1)*barW

            if bitValue = 1
                demo Paint rectangle: "White",x0,x1,8,92
            else
                demo Paint rectangle: "{0.08,0.08,0.08}",x0,x1,8,92
            endif
        endfor

        # Thin complement register makes binary difference explicit without
        # pretending to reproduce the original installation geometry.
        for bit from 0 to 15
            bitValue = 1-(floor(word/(2^bit)) mod 2)
            x0 = bit*barW
            x1 = (bit+1)*barW
            if bitValue = 1
                demo Paint rectangle: "White",x0,x1,1,5
            endif
        endfor

    # -----------------------------------------------------------------------
    # VISUAL 2: DATA SCAN
    # -----------------------------------------------------------------------
    elsif study = 2
        scan = ((frame-1) mod gridCells)+1
        activeX = ((scan-1) mod gridN)+1
        activeY = floor((scan-1)/gridN)+1
        cellW = 86/gridN
        cellH = 78/gridN
        xBase = 7
        yBase = 10

        for cell from 1 to gridCells
            cx = ((cell-1) mod gridN)+1
            cy = floor((cell-1)/gridN)+1
            value = gridValue#[cell]
            gray = 0.08+0.46*value
            col$ = "{" + fixed$(gray,3) + "," + fixed$(gray,3)
                ... + "," + fixed$(gray,3) + "}"
            x0 = xBase+(cx-1)*cellW+0.35
            x1 = xBase+cx*cellW-0.35
            y0 = yBase+(cy-1)*cellH+0.35
            y1 = yBase+cy*cellH-0.35
            demo Paint rectangle: col$,x0,x1,y0,y1
        endfor

        ax0 = xBase+(activeX-1)*cellW
        ax1 = xBase+activeX*cellW
        ay0 = yBase+(activeY-1)*cellH
        ay1 = yBase+activeY*cellH

        if enable_color_accents
            demo Colour: "{0.0,0.85,1.0}"
        else
            demo Colour: "White"
        endif
        demo Line width: 2
        demo Draw rectangle: ax0,ax1,ay0,ay1
        demo Draw line: ax0,5,ax0,95
        demo Line width: 1

    # -----------------------------------------------------------------------
    # VISUAL 3: WHITE-LIGHT / ENERGY FIELD
    # -----------------------------------------------------------------------
    elsif study = 3
        energy = 0.5+0.5*sin(2*pi*0.055*t)
        beamHalf = 3+43*energy
        gray = 0.20+0.80*energy
        beam$ = "{" + fixed$(gray,3) + "," + fixed$(gray,3)
            ... + "," + fixed$(gray,3) + "}"

        demo Paint rectangle: beam$,50-beamHalf,50+beamHalf,0,100
        demo Paint rectangle: "White",49.65,50.35,0,100
        demo Paint rectangle: "{0.18,0.18,0.18}",12,12.35,0,100
        demo Paint rectangle: "{0.18,0.18,0.18}",87.65,88,0,100

    # -----------------------------------------------------------------------
    # VISUAL 4: DATA PULSE FIELD
    # -----------------------------------------------------------------------
    else
        word = dataWord#[frame]
        barW = 92/16
        xBase = 4

        for bit from 0 to 15
            bitValue = floor(word/(2^bit)) mod 2
            x0 = xBase+bit*barW
            x1 = xBase+(bit+1)*barW-0.35

            if bitValue = 1
                demo Paint rectangle: "White",x0,x1,12,88
            else
                demo Paint rectangle: "{0.18,0.18,0.18}",x0,x1,12,88
            endif

            # Time-order marker: the visual left->right order is exactly the
            # micro-event order within the corresponding audio frame.
            markerY = 6+3*(bitValue)
            if enable_color_accents and bitValue=1
                demo Paint rectangle: "{0.0,0.80,1.0}",x0,x1,markerY,markerY+1.4
            else
                demo Paint rectangle: "White",x0,x1,markerY,markerY+0.7
            endif
        endfor
    endif

    # -----------------------------------------------------------------------
    # HUD: report the actual shared mapping shown/heard.
    # -----------------------------------------------------------------------
    demo Font size: 8
    demo Colour: "{0.62,0.62,0.64}"
    demo Text: 2,"left",98,"half",studyName$

    if study = 1
        hud$ = "t=" + fixed$(t,2) + " s | word=" + string$(dataWord#[frame])
            ... + " | 1-bits=" + string$(bitCount#[frame])
            ... + " | transitions=" + string$(transitionCount#[frame])
    elsif study = 2
        scan = ((frame-1) mod gridCells)+1
        hud$ = "t=" + fixed$(t,2) + " s | cell=" + string$(scan)
            ... + " | value=" + fixed$(gridValue#[scan],3)
    elsif study = 3
        energy = 0.5+0.5*sin(2*pi*0.055*t)
        hud$ = "t=" + fixed$(t,2) + " s | shared energy=" + fixed$(energy,3)
    else
        hud$ = "t=" + fixed$(t,2) + " s | word=" + string$(dataWord#[frame])
            ... + " | 16 visual bits = 16 audio micro-events"
    endif

    demo Text: 2,"left",94,"half",hud$
    demoShow()
        endif
    endfor

    # Keep the current image on screen until the nominal block boundary.
    elapsed = elapsed+stopwatch
    remaining = blockDuration-elapsed
    if remaining > 0
        sleep(remaining)
    else
        blockOverruns = blockOverruns+1
    endif

endfor

# Keep the final data frame visible briefly while any small device-buffer tail
# drains. This is intentionally short and does not accumulate across the work.
sleep(finalLatencyGuard)
removeObject: blockID#[totalSyncBlocks]

# ---------------------------------------------------------------------------
# 11. FINAL FRAME / HYBRID-SYNC QC
# ---------------------------------------------------------------------------
demo Paint rectangle: "Black",0,100,0,100
demo Paint rectangle: "White",0,100,49.7,50.3
demo Font size: 12
demo Colour: "White"
demo Text: 50,"centre",62,"half","AV study complete"
demo Font size: 8
demo Colour: "{0.60,0.60,0.62}"
demo Text: 50,"centre",43,"half",
    ... "hybrid sync: " + string$(totalSyncBlocks) + " hard re-lock blocks"
demo Text: 50,"centre",35,"half",
    ... "skipped " + string$(skippedFrames) + " | late " + string$(lateFrames)
demoShow()

appendInfoLine: "Synchronization: hybrid asynchronous blocks with periodic hard re-lock"
appendInfoLine: "Aligned sync block: ", fixed$(syncBlock,4), " s (", framesPerSyncBlock, " frames)"
appendInfoLine: "Completed sync blocks: ", totalSyncBlocks
appendInfoLine: "Skipped stale visual frames: ", skippedFrames, " / ", totalFrames
appendInfoLine: "Late but rendered visual frames: ", lateFrames, " / ", totalFrames
appendInfoLine: "Block overruns: ", blockOverruns, " / ", totalSyncBlocks
appendInfoLine: "Maximum local frame lateness: ", fixed$(maxLateness,4), " s"
appendInfoLine: "Final visual latency guard: ", fixed$(finalLatencyGuard,4), " s"

selectObject: masterSound
appendInfoLine: "Output Sound retained in Objects: ", selected$("Sound")
