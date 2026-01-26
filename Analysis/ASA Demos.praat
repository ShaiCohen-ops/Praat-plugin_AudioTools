# ============================================================
# Praat AudioTools - ASA Demos 1-8.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3 (2025) 
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auditory Scene Analysis Demos
#
# ============================================================

form Auditory Scene Analysis Demos
    optionmenu Experiment_Type: 1
        option Demo 1: Stream Segregation (Cycle Speed)
        option Demo 2: Pattern Recognition (Within-Stream)
        option Demo 2: Pattern Recognition (Across-Stream)
        option Demo 3: Loss of Rhythm (Large Separation)
        option Demo 3: Loss of Rhythm (Small Separation)
        option Demo 4: Cumulative Effects of Repetition
        option Demo 5: Segregation of Melody from Interference
        option Demo 6: Telemann Sonata (Compound Melody)
        option Demo 7: African Xylophone (Interlocking Parts)
        option Demo 8: African Xylophone (Pitch Range Separation)
endform

# -------------------------
# Global Configuration
# -------------------------
sampleRate = 44100
gainHigh = 1.0
gainLow = 10 ^ (6.0 / 20) 
gainLowDemo2 = 10 ^ (1.5 / 20)
rampShort = 0.010
finalName$ = ""

# -------------------------
# 1. CORE PROCEDURES
# -------------------------

procedure MakeTone: .freq, .dur, .gain, .rise, .fall
    Create Sound from formula: "tone", 1, 0, .dur, sampleRate, "sin(2*pi*.freq*x)"
    .rEnd = .rise
    .fStart = .dur - .fall
    if .fStart < 0
        .fStart = 0
    endif
    Formula: "self * (if x < .rEnd then x/.rEnd else if x > .fStart then (xmax - x)/(xmax - .fStart) else 1 fi fi)"
    Formula: "self * .gain"
endproc

procedure MakeGap: .dur
    Create Sound from formula: "gap", 1, 0, .dur, sampleRate, "0"
endproc

procedure MakeXylophone: .freq, .dur
    # Exponential decay for wood sound (Amadinda style)
    Create Sound from formula: "xylo", 1, 0, .dur, sampleRate, "sin(2*pi*.freq*x) * exp(-40*x)"
    # Tiny fade in to prevent clicks
    Formula: "self * (if x < 0.002 then x/0.002 else 1 fi)"
endproc

procedure RepeatSound: .name$, .times, .outName$
    selectObject: "Sound " + .name$
    Copy: "repAccum"
    for .i from 2 to .times
        selectObject: "Sound " + .name$
        Copy: "tmpRep"
        selectObject: "Sound repAccum", "Sound tmpRep"
        Concatenate
        Rename: "repAccumNew"
        selectObject: "Sound repAccum", "Sound tmpRep"
        Remove
        selectObject: "Sound repAccumNew"
        Rename: "repAccum"
    endfor
    Rename: .outName$
endproc

# -------------------------
# 2. EXPERIMENT-SPECIFIC PROCEDURES
# -------------------------

# --- Demo 1 Cycle ---
procedure CycleD1: .dur
    h1 = 2500
    h2 = 2000
    h3 = 1600
    l1 = 350
    l2 = 430
    l3 = 550
    @MakeTone: h1, .dur, gainHigh, rampShort, rampShort
    Rename: "t1"
    @MakeTone: l1, .dur, gainLow, rampShort, rampShort
    Rename: "t2"
    @MakeTone: h2, .dur, gainHigh, rampShort, rampShort
    Rename: "t3"
    @MakeTone: l2, .dur, gainLow, rampShort, rampShort
    Rename: "t4"
    @MakeTone: h3, .dur, gainHigh, rampShort, rampShort
    Rename: "t5"
    @MakeTone: l3, .dur, gainLow, rampShort, rampShort
    Rename: "t6"
    selectObject: "Sound t1", "Sound t2", "Sound t3", "Sound t4", "Sound t5", "Sound t6"
    Concatenate
    Rename: "cycle"
    selectObject: "Sound t1", "Sound t2", "Sound t3", "Sound t4", "Sound t5", "Sound t6"
    Remove
    selectObject: "Sound cycle"
endproc

# --- Demo 2 Cycle ---
procedure MakeD2Cycle: .type$
    h1 = 2500
    h2 = 2000
    h3 = 1600
    l1 = 350
    l2 = 430
    l3 = 550
    toneDur = 0.100
    
    if .type$ = "Within_Standard"
        @MakeTone: h1, toneDur, gainHigh, rampShort, rampShort
        Rename: "s1"
        @MakeGap: toneDur
        Rename: "s2"
        @MakeTone: h2, toneDur, gainHigh, rampShort, rampShort
        Rename: "s3"
        @MakeGap: toneDur
        Rename: "s4"
        @MakeTone: h3, toneDur, gainHigh, rampShort, rampShort
        Rename: "s5"
        @MakeGap: toneDur
        Rename: "s6"
    elsif .type$ = "Across_Standard"
        @MakeTone: h1, toneDur, gainHigh, rampShort, rampShort
        Rename: "s1"
        @MakeGap: toneDur
        Rename: "s2"
        @MakeTone: h2, toneDur, gainHigh, rampShort, rampShort
        Rename: "s3"
        @MakeGap: toneDur
        Rename: "s4"
        @MakeTone: l3, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s5"
        @MakeGap: toneDur
        Rename: "s6"
    elsif .type$ = "Across_Full"
        @MakeTone: h1, toneDur, gainHigh, rampShort, rampShort
        Rename: "s1"
        @MakeTone: l1, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s2"
        @MakeTone: h2, toneDur, gainHigh, rampShort, rampShort
        Rename: "s3"
        @MakeTone: l2, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s4"
        @MakeTone: l3, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s5"
        @MakeTone: h3, toneDur, gainHigh, rampShort, rampShort
        Rename: "s6"
    else 
        @MakeTone: h1, toneDur, gainHigh, rampShort, rampShort
        Rename: "s1"
        @MakeTone: l1, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s2"
        @MakeTone: h2, toneDur, gainHigh, rampShort, rampShort
        Rename: "s3"
        @MakeTone: l2, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s4"
        @MakeTone: h3, toneDur, gainHigh, rampShort, rampShort
        Rename: "s5"
        @MakeTone: l3, toneDur, gainLowDemo2, rampShort, rampShort
        Rename: "s6"
    endif
    
    selectObject: "Sound s1", "Sound s2", "Sound s3", "Sound s4", "Sound s5", "Sound s6"
    Concatenate
    Rename: "cycle"
    selectObject: "Sound s1", "Sound s2", "Sound s3", "Sound s4", "Sound s5", "Sound s6"
    Remove
    selectObject: "Sound cycle"
endproc

# --- Demo 6 Telemann ---
procedure TelemannMeasure: .tDur
    toneG5 = 783.99
    toneE5 = 659.25
    toneD5 = 587.33
    toneC5 = 523.25
    toneB4 = 493.88
    toneA4 = 440.00
    toneG4 = 392.00
    
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n1"
    @MakeTone: toneE5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n2"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n3"
    @MakeTone: toneC5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n4"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n5"
    @MakeTone: toneD5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n6"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n7"
    @MakeTone: toneB4, .tDur, gainHigh, rampShort, rampShort
    Rename: "n8"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n9"
    @MakeTone: toneC5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n10"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n11"
    @MakeTone: toneA4, .tDur, gainHigh, rampShort, rampShort
    Rename: "n12"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n13"
    @MakeTone: toneB4, .tDur, gainHigh, rampShort, rampShort
    Rename: "n14"
    @MakeTone: toneG5, .tDur, gainHigh, rampShort, rampShort
    Rename: "n15"
    @MakeTone: toneG4, .tDur, gainHigh, rampShort, rampShort
    Rename: "n16"
    
    selectObject: "Sound n1", "Sound n2", "Sound n3", "Sound n4", "Sound n5", "Sound n6", "Sound n7", "Sound n8"
    plusObject: "Sound n9", "Sound n10", "Sound n11", "Sound n12", "Sound n13", "Sound n14", "Sound n15", "Sound n16"
    Concatenate
    Rename: "T_Measure"
    selectObject: "Sound n1", "Sound n2", "Sound n3", "Sound n4", "Sound n5", "Sound n6", "Sound n7", "Sound n8"
    plusObject: "Sound n9", "Sound n10", "Sound n11", "Sound n12", "Sound n13", "Sound n14", "Sound n15", "Sound n16"
    Remove
    selectObject: "Sound T_Measure"
endproc

# --- Demo 7/8 Xylophone Parts ---
procedure MakePartA: .count
    # Requires Globals: f1, f3, xyloDur
    for .i from 1 to .count
        @MakeXylophone: f1, xyloDur
        Rename: "xa1"
        @MakeGap: xyloDur
        Rename: "xa2"
        @MakeXylophone: f3, xyloDur
        Rename: "xa3"
        @MakeGap: xyloDur
        Rename: "xa4"
        selectObject: "Sound xa1", "Sound xa2", "Sound xa3", "Sound xa4"
        Concatenate
        Rename: "BlockA"
        
        selectObject: "Sound xa1", "Sound xa2", "Sound xa3", "Sound xa4"
        Remove
        selectObject: "Sound BlockA"
        
        if .i = 1
             Rename: "AccumA"
        else
             selectObject: "Sound AccumA", "Sound BlockA"
             Concatenate
             Rename: "NewA"
             selectObject: "Sound AccumA", "Sound BlockA"
             Remove
             selectObject: "Sound NewA"
             Rename: "AccumA"
        endif
    endfor
endproc

procedure MakePartB: .count
    # Requires Globals: f4, f5, xyloDur
    for .i from 1 to .count
        @MakeGap: xyloDur
        Rename: "xb1"
        @MakeXylophone: f4, xyloDur
        Rename: "xb2"
        @MakeGap: xyloDur
        Rename: "xb3"
        @MakeXylophone: f5, xyloDur
        Rename: "xb4"
        selectObject: "Sound xb1", "Sound xb2", "Sound xb3", "Sound xb4"
        Concatenate
        Rename: "BlockB"
        
        selectObject: "Sound xb1", "Sound xb2", "Sound xb3", "Sound xb4"
        Remove
        selectObject: "Sound BlockB"
        
        if .i = 1
             Rename: "AccumB"
        else
             selectObject: "Sound AccumB", "Sound BlockB"
             Concatenate
             Rename: "NewB"
             selectObject: "Sound AccumB", "Sound BlockB"
             Remove
             selectObject: "Sound NewB"
             Rename: "AccumB"
        endif
    endfor
endproc

procedure MakeCombined: .count
    # Requires Globals: f1, f3, f4, f5, xyloDur
    for .i from 1 to .count
        @MakeXylophone: f1, xyloDur
        Rename: "xc1"
        @MakeXylophone: f4, xyloDur
        Rename: "xc2"
        @MakeXylophone: f3, xyloDur
        Rename: "xc3"
        @MakeXylophone: f5, xyloDur
        Rename: "xc4"
        selectObject: "Sound xc1", "Sound xc2", "Sound xc3", "Sound xc4"
        Concatenate
        Rename: "BlockC"
        
        selectObject: "Sound xc1", "Sound xc2", "Sound xc3", "Sound xc4"
        Remove
        selectObject: "Sound BlockC"
        
        if .i = 1
             Rename: "AccumC"
        else
             selectObject: "Sound AccumC", "Sound BlockC"
             Concatenate
             Rename: "NewC"
             selectObject: "Sound AccumC", "Sound BlockC"
             Remove
             selectObject: "Sound NewC"
             Rename: "AccumC"
        endif
    endfor
endproc

# -------------------------
# 3. MAIN EXECUTION
# -------------------------

if experiment_Type = 1
    # === DEMO 1: STREAM SEGREGATION ===
    @CycleD1: 0.400
    Rename: "slowCyc"
    @RepeatSound: "slowCyc", 4, "part1"
    @MakeGap: 1.0
    Rename: "gap"
    @CycleD1: 0.100
    Rename: "fastCyc"
    @RepeatSound: "fastCyc", 16, "part2"
    
    selectObject: "Sound part1", "Sound gap", "Sound part2"
    Concatenate
    Rename: "Demo_1"
    finalName$ = "Demo_1"
    
    selectObject: "Sound part1", "Sound slowCyc", "Sound part2", "Sound fastCyc", "Sound gap"
    Remove
endif

if experiment_Type = 2 or experiment_Type = 3
    # === DEMO 2: PATTERN RECOGNITION ===
    if experiment_Type = 2
        @MakeD2Cycle: "Within_Standard"
        Rename: "std"
        @RepeatSound: "std", 15, "PartA"
        @MakeD2Cycle: "Normal"
        Rename: "full"
        @RepeatSound: "full", 15, "PartB"
        finalName$ = "Demo_2_Within"
    else
        @MakeD2Cycle: "Across_Standard"
        Rename: "std"
        @RepeatSound: "std", 15, "PartA"
        @MakeD2Cycle: "Across_Full"
        Rename: "full"
        @RepeatSound: "full", 15, "PartB"
        finalName$ = "Demo_2_Across"
    endif
    
    @MakeGap: 1.0
    Rename: "gap"
    
    selectObject: "Sound PartA", "Sound gap", "Sound PartB"
    Concatenate
    Rename: finalName$
    
    selectObject: "Sound PartA", "Sound std", "Sound PartB", "Sound full", "Sound gap"
    Remove
endif

if experiment_Type = 4 or experiment_Type = 5
    # === DEMO 3: LOSS OF RHYTHM ===
    h3 = 1400
    if experiment_Type = 4
        l3 = 500
    else
        l3 = 1320
    endif
    startUnit = 0.287
    endUnit = 0.088
    totalTime = 12.0
    currentUnit = startUnit
    d3_Rise = 0.010
    d3_Fall = 0.020
    
    @MakeGap: 0.001
    Rename: "accumulator"
    time = 0
    while time < totalTime
        @MakeTone: h3, currentUnit, gainHigh, d3_Rise, d3_Fall
        Rename: "u1"
        @MakeTone: l3, currentUnit, gainHigh, d3_Rise, d3_Fall
        Rename: "u2"
        @MakeTone: h3, currentUnit, gainHigh, d3_Rise, d3_Fall
        Rename: "u3"
        @MakeGap: currentUnit
        Rename: "u4"
        selectObject: "Sound u1", "Sound u2", "Sound u3", "Sound u4"
        Concatenate
        Rename: "cyc"
        selectObject: "Sound u1", "Sound u2", "Sound u3", "Sound u4"
        Remove
        selectObject: "Sound accumulator", "Sound cyc"
        Concatenate
        Rename: "temp"
        selectObject: "Sound accumulator", "Sound cyc"
        Remove
        selectObject: "Sound temp"
        Rename: "accumulator"
        time = time + (4 * currentUnit)
        currentUnit = currentUnit * 0.96
        if currentUnit < endUnit
            currentUnit = endUnit
        endif
    endwhile
    selectObject: "Sound accumulator"
    Rename: "Demo_3"
    finalName$ = "Demo_3"
endif

if experiment_Type = 6
    # === DEMO 4: CUMULATIVE EFFECTS ===
    h4 = 2000
    l4 = 700
    tRise = 0.0125
    tSteady = 0.088
    tFall = 0.0125
    tDur = tRise + tSteady + tFall
    gapInterTone = 0.012
    gapInterCycle = 0.125
    
    @MakeTone: h4, tDur, gainHigh, tRise, tFall
    Rename: "th"
    @MakeTone: l4, tDur, gainLow, tRise, tFall
    Rename: "tl"
    @MakeGap: gapInterTone
    Rename: "tg"
    @MakeGap: gapInterCycle
    Rename: "cg"
    
    selectObject: "Sound th"
    Copy: "th2"
    selectObject: "Sound tg"
    Copy: "tg2"
    Copy: "tg3"
    
    selectObject: "Sound th", "Sound tg", "Sound tl", "Sound tg2", "Sound th2", "Sound cg"
    Concatenate
    Rename: "Cycle4"
    selectObject: "Sound th", "Sound tl", "Sound tg", "Sound cg", "Sound th2", "Sound tg2", "Sound tg3"
    Remove
    
    @MakeGap: 0.001
    Rename: "Demo4_Accum"
    for k from 1 to 5
        count = 2 ^ k
        selectObject: "Sound Cycle4"
        Copy: "BlockAccum"
        if count > 1
            for j from 2 to count
                selectObject: "Sound Cycle4"
                Copy: "tmpCyc"
                selectObject: "Sound BlockAccum", "Sound tmpCyc"
                Concatenate
                Rename: "BlockAccumNew"
                selectObject: "Sound BlockAccum", "Sound tmpCyc"
                Remove
                selectObject: "Sound BlockAccumNew"
                Rename: "BlockAccum"
            endfor
        endif
        if k < 5
             @MakeGap: 4.0
             Rename: "FreshSilence"
             selectObject: "Sound Demo4_Accum", "Sound BlockAccum", "Sound FreshSilence"
             Concatenate
             Rename: "Demo4_Next"
             selectObject: "Sound FreshSilence"
             Remove
        else
             selectObject: "Sound Demo4_Accum", "Sound BlockAccum"
             Concatenate
             Rename: "Demo4_Next"
        endif
        selectObject: "Sound Demo4_Accum", "Sound BlockAccum"
        Remove
        selectObject: "Sound Demo4_Next"
        Rename: "Demo4_Accum"
    endfor
    selectObject: "Sound Cycle4"
    Remove
    selectObject: "Sound Demo4_Accum"
    Rename: "Demo_4_Cumulative"
    finalName$ = "Demo_4_Cumulative"
endif

if experiment_Type = 7
    # === DEMO 5: MELODY SEGREGATION ===
    toneDur5 = 0.120
    baseC4 = 261.63
    @MakeGap: 0.001
    Rename: "Demo5_Accum"
    
    for round from 1 to 3
        if round = 1
            trans = 0
        elsif round = 2
            trans = 7
        else
            trans = 12
        endif
        for n from 1 to 16
            if n=1 or n=5 or n=6 or n=7 or n=13
                semi = 4
            elsif n=2 or n=4 or n=9 or n=10 or n=11 or n=12
                semi = 2
            elsif n=3
                semi = 0
            elsif n=8
                semi = 4
            elsif n=14 or n=15 or n=16
                semi = 7
            endif
            mHz = baseC4 * (2 ^ ((semi + trans) / 12))
            dHz = randomUniform(261.63, 392.00)
            @MakeTone: mHz, toneDur5, gainHigh, rampShort, rampShort
            Rename: "mTone"
            @MakeTone: dHz, toneDur5, gainHigh, rampShort, rampShort
            Rename: "dTone"
            selectObject: "Sound Demo5_Accum", "Sound mTone", "Sound dTone"
            Concatenate
            Rename: "Demo5_Next"
            selectObject: "Sound Demo5_Accum", "Sound mTone", "Sound dTone"
            Remove
            selectObject: "Sound Demo5_Next"
            Rename: "Demo5_Accum"
        endfor
        @MakeGap: 1.0
        Rename: "RoundGap"
        selectObject: "Sound Demo5_Accum", "Sound RoundGap"
        Concatenate
        Rename: "Demo5_Next"
        selectObject: "Sound Demo5_Accum", "Sound RoundGap"
        Remove
        selectObject: "Sound Demo5_Next"
        Rename: "Demo5_Accum"
    endfor
    selectObject: "Sound Demo5_Accum"
    Rename: "Demo_5_Melody"
    finalName$ = "Demo_5_Melody"
endif

if experiment_Type = 8
    # === DEMO 6: TELEMANN SONATA ===
    @TelemannMeasure: 0.250
    Rename: "SlowPass"
    @RepeatSound: "SlowPass", 2, "PartA"
    @MakeGap: 1.0
    Rename: "Gap"
    @TelemannMeasure: 0.100
    Rename: "FastPass"
    @RepeatSound: "FastPass", 4, "PartB"
    
    selectObject: "Sound PartA", "Sound Gap", "Sound PartB"
    Concatenate
    Rename: "Demo_6_Telemann"
    finalName$ = "Demo_6_Telemann"
    
    selectObject: "Sound PartA", "Sound SlowPass", "Sound PartB", "Sound FastPass", "Sound Gap"
    Remove
endif

if experiment_Type = 9 or experiment_Type = 10
    # === DEMO 7 & 8: AFRICAN XYLOPHONE ===
    baseHz = 350
    xyloDur = 0.120
    
    # Scale: Equipentatonic (5 equal steps of 240 cents)
    f1 = baseHz
    f2 = baseHz * (2 ^ (240/1200))
    f3 = baseHz * (2 ^ (480/1200))
    f4 = baseHz * (2 ^ (720/1200))
    f5 = baseHz * (2 ^ (960/1200))
    f6 = baseHz * (2 ^ (1200/1200))
    
    # FOR DEMO 8: SHIFT PART B UP ONE OCTAVE (f4, f5)
    if experiment_Type = 10
        f4 = f4 * 2
        f5 = f5 * 2
    endif
    
    @MakePartA: 8
    Rename: "PartA_Solo"
    @MakeGap: 1.0
    Rename: "Gap1"
    
    @MakePartB: 8
    Rename: "PartB_Solo"
    @MakeGap: 1.0
    Rename: "Gap2"
    
    @MakeCombined: 16
    Rename: "Duet"
    
    selectObject: "Sound PartA_Solo", "Sound Gap1", "Sound PartB_Solo", "Sound Gap2", "Sound Duet"
    Concatenate
    
    if experiment_Type = 9
        Rename: "Demo_7_Xylophone"
        finalName$ = "Demo_7_Xylophone"
    else
        Rename: "Demo_8_PitchSep"
        finalName$ = "Demo_8_PitchSep"
    endif
    
    # Cleanup: Only remove objects that exist and were not renamed
    selectObject: "Sound PartA_Solo", "Sound Gap1", "Sound PartB_Solo", "Sound Gap2", "Sound Duet"
    Remove
endif

# -------------------------
# FINAL OUTPUT
# -------------------------
selectObject: "Sound " + finalName$
Scale peak: 0.99
Play