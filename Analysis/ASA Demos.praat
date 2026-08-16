# ============================================================
# Praat AudioTools - ASA_Demos.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.1 (2026) - Audited stimuli + AudioTools visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Synthetic pedagogical reconstructions of eight sequential-
#   grouping demonstrations associated with Bregman & Ahad's
#   Auditory Scene Analysis demonstrations.
#
#   IMPORTANT: Demos 6-8 are synthetic models of the published
#   perceptual principles; they are NOT reproductions of the
#   original Telemann or Ugandan source recordings.
#
# Changelog v2.1 (2026):
#   - Audited claims against published Bregman/Ahad technical details.
#   - Demo 3 now actually reaches 88 ms/unit (287 -> 88 ms over 20 cycles).
#   - Demo 5 now uses five presentations transposed 0,2,4,6,8 semitones;
#     event rate is 7/s (120 ms tone + 23 ms silence), and the SAME
#     distractor realization is reused in every presentation and shown
#     in the visualization.
#   - Demo 6 renamed as a Telemann-style synthetic compound-melody model.
#   - Demos 7-8 renamed as amadinda-style synthetic interlocking models.
#   - New 2x2 AudioTools house visualization: exact stimulus/model,
#     explicit grouping hypothesis, control law, and measured spectrogram.
#   - Perceptual grouping overlays are explicitly labeled as hypotheses,
#     never as measurements of the listener.
# ============================================================

form Auditory Scene Analysis Demos v2.1
    optionmenu Experiment_Type: 1
        option Demo 1: Stream Segregation (Rate)
        option Demo 2: Pattern Recognition (Within-Stream)
        option Demo 2: Pattern Recognition (Across-Stream)
        option Demo 3: Loss of Rhythm (Large Separation)
        option Demo 3: Loss of Rhythm (Small Separation)
        option Demo 4: Cumulative Effects of Repetition
        option Demo 5: Melody from Interference
        option Demo 6: Telemann-style Compound Melody Model
        option Demo 7: Amadinda-style Interlocking Model
        option Demo 8: Amadinda-style Pitch-Range Separation
    comment === Visualization ===
    boolean Show_visualization 1
    boolean Show_spectrogram 1
    boolean Play_result 1
endform

# -------------------------
# Global configuration
# -------------------------
sampleRate = 44100
gainHigh = 1.0
# Published Demo 1/4 compensation: low tones are 6 dB more intense.
gainLow = 10 ^ (6.0 / 20)
# Published Demo 2 compensation: low tones are 1.5 dB more intense.
gainLowDemo2 = 10 ^ (1.5 / 20)
rampShort = 0.010
finalName$ = ""

# House colors
highColor$ = "{0.75,0.28,0.24}"
lowColor$ = "{0.24,0.45,0.72}"
melodyColor$ = "{0.24,0.58,0.35}"
distractorColor$ = "{0.58,0.58,0.58}"
partAColor$ = "{0.78,0.42,0.18}"
partBColor$ = "{0.20,0.48,0.68}"
lightBG$ = "{0.97,0.97,0.97}"
gridColor$ = "{0.82,0.82,0.82}"
textGray$ = "{0.32,0.32,0.32}"

# Demo-5 plan is generated once and reused by sound + visualization.
demo5N = 16
demo5Semi[1] = 4
demo5Semi[2] = 2
demo5Semi[3] = 0
demo5Semi[4] = 2
demo5Semi[5] = 4
demo5Semi[6] = 4
demo5Semi[7] = 4
demo5Semi[8] = 4
demo5Semi[9] = 2
demo5Semi[10] = 2
demo5Semi[11] = 2
demo5Semi[12] = 2
demo5Semi[13] = 4
demo5Semi[14] = 7
demo5Semi[15] = 7
demo5Semi[16] = 7

# Fixed random-like distractor realization (reused across all five passes).
demo5DistractorOffset[1] = 2
demo5DistractorOffset[2] = -3
demo5DistractorOffset[3] = 1
demo5DistractorOffset[4] = 4
demo5DistractorOffset[5] = -2
demo5DistractorOffset[6] = 0
demo5DistractorOffset[7] = 3
demo5DistractorOffset[8] = -4
demo5DistractorOffset[9] = 1
demo5DistractorOffset[10] = -1
demo5DistractorOffset[11] = 4
demo5DistractorOffset[12] = -3
demo5DistractorOffset[13] = 2
demo5DistractorOffset[14] = 0
demo5DistractorOffset[15] = -2
demo5DistractorOffset[16] = 3

# -------------------------
# VISUALIZATION HELPERS
# -------------------------
procedure houseTitle: .title$, .subtitle$
    Select outer viewport: 0, 8, 0.02, 0.38
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", .title$

    Select outer viewport: 0.4, 7.6, 0.40, 0.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: textGray$
    Text: 0.5, "centre", 0.5, "half", .subtitle$
endproc

procedure panelTitle: .x1, .x2, .y1, .y2, .label$
    Select outer viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.03, "left", 0.45, "half", .label$
endproc

procedure toneRect: .t1, .t2, .f, .height, .colour$
    Paint rectangle: .colour$, .t1, .t2, .f - .height/2, .f + .height/2
    Colour: "Black"
    Line width: 0.5
    Draw rectangle: .t1, .t2, .f - .height/2, .f + .height/2
    Line width: 1
endproc

procedure basicAxes: .tMax, .fMin, .fMax, .timeStep, .freqStep
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    if .timeStep > 0
        Marks bottom every: 1, .timeStep, "yes", "yes", "no"
    endif
    if .freqStep > 0
        Marks left every: 1, .freqStep, "yes", "yes", "no"
    endif
endproc

procedure summaryBar: .text$
    Select outer viewport: 0.45, 7.55, 5.05, 5.40
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94,0.94,0.94}", 0, 1, 0.15, 0.85
    Font size: 7
    Colour: textGray$
    Text: 0.5, "centre", 0.5, "half", .text$
endproc

procedure measuredPanel: .soundID, .t1, .t2, .fMax
    Select inner viewport: 4.55, 7.85, 3.32, 4.78
    if show_spectrogram
        selectObject: .soundID
        Extract part: .t1, .t2, "rectangular", 1, "no"
        .excerpt = selected("Sound")
        To Spectrogram: 0.03, .fMax, 0.002, 20, "Gaussian"
        .spec = selected("Spectrogram")
        Paint: 0, 0, 0, .fMax, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text bottom: "yes", "Excerpt time (s)"
        Text left: "yes", "Frequency (Hz)"
        removeObject: .excerpt, .spec
    else
        selectObject: .soundID
        Extract part: .t1, .t2, "rectangular", 1, "no"
        .excerpt = selected("Sound")
        Colour: lowColor$
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text bottom: "yes", "Excerpt time (s)"
        Text left: "yes", "Amplitude"
        removeObject: .excerpt
    endif
endproc

# -------------------------
# HOUSE VISUALIZATION
# -------------------------
procedure visualizeASA: .which, .soundID
    Erase all

    # Panel geometry is fixed across all AudioTools pedagogy plots.
    # A data: 0.45.0.3.75, 1.15.0.2.62
    # B data: 4.55.0.7.85, 1.15.0.2.62
    # C data: 0.45.0.3.75, 3.32.0.4.78
    # D data: 4.55.0.7.85, 3.32.0.4.78

    if .which = 1
        @houseTitle: "ASA 1 - Stream Segregation", "Exact six-tone cycle; perceptual contours are hypotheses, not measurements"
        @panelTitle: 0, 3.9, 0.80, 1.04, "A  SLOW STIMULUS"
        Select inner viewport: 0.45, 3.75, 1.15, 2.62
        h1=2500
        h2=2000
        h3=1600
        l1=350
        l2=430
        l3=550
        d=0.4
        tMax=2.4
        Axes: 0, tMax, 200, 3000
        Paint rectangle: lightBG$, 0, tMax, 200, 3000
        @toneRect: 0*d,0.8*d,h1,130,highColor$
        @toneRect: 1*d,1.8*d,l1,130,lowColor$
        @toneRect: 2*d,2.8*d,h2,130,highColor$
        @toneRect: 3*d,3.8*d,l2,130,lowColor$
        @toneRect: 4*d,4.8*d,h3,130,highColor$
        @toneRect: 5*d,5.8*d,l3,130,lowColor$
        Colour: textGray$
        Dashed line
        Line width: 1.5
        Draw line: 0.2,h1,0.6,l1
        Draw line: 0.6,l1,1.0,h2
        Draw line: 1.0,h2,1.4,l2
        Draw line: 1.4,l2,1.8,h3
        Draw line: 1.8,h3,2.2,l3
        Solid line
        Line width: 1
        @basicAxes: tMax,200,3000,0.8,500

        @panelTitle: 4.1, 8, 0.80, 1.04, "B  FAST GROUPING HYPOTHESIS"
        Select inner viewport: 4.55, 7.85, 1.15, 2.62
        d=0.1
        tMax=0.6
        Axes: 0,tMax,200,3000
        Paint rectangle: lightBG$,0,tMax,200,3000
        @toneRect: 0*d,0.8*d,h1,130,highColor$
        @toneRect: 1*d,1.8*d,l1,130,lowColor$
        @toneRect: 2*d,2.8*d,h2,130,highColor$
        @toneRect: 3*d,3.8*d,l2,130,lowColor$
        @toneRect: 4*d,4.8*d,h3,130,highColor$
        @toneRect: 5*d,5.8*d,l3,130,lowColor$
        Colour: highColor$
        Line width: 2
        Draw line: 0.04,h1,0.24,h2
        Draw line: 0.24,h2,0.44,h3
        Colour: lowColor$
        Draw line: 0.14,l1,0.34,l2
        Draw line: 0.34,l2,0.54,l3
        Line width: 1
        @basicAxes: tMax,200,3000,0.2,500

        @panelTitle: 0, 3.9, 2.97, 3.21, "C  RATE CONTROL"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 0,3,0,450
        Paint rectangle: lightBG$,0,3,0,450
        Paint rectangle: lowColor$,0.55,1.25,0,400
        Paint rectangle: highColor$,1.75,2.45,0,100
        Font size: 7
        Colour: "Black"
        Text: 0.9,"centre",420,"half","400 ms"
        Text: 2.1,"centre",120,"half","100 ms"
        Text: 0.9,"centre",25,"half","slow"
        Text: 2.1,"centre",25,"half","fast"
        Draw inner box
        Text left: "yes","Onset interval (ms)"

        if show_spectrogram
            @panelTitle: 4.1,8,2.97,3.21,"D  MEASURED FAST SPECTROGRAM"
        else
            @panelTitle: 4.1,8,2.97,3.21,"D  MEASURED FAST WAVEFORM"
        endif
        @measuredPanel: .soundID,10.6,11.8,3200
        @summaryBar: "H: 2500/2000/1600 Hz | L: 350/430/550 Hz (+6 dB) | 400 ms -> 100 ms onset interval"

    elsif .which = 2 or .which = 3
        if .which = 2
            .mode$="WITHIN-STREAM"
            .cross=0
        else
            .mode$="ACROSS-STREAM"
            .cross=1
        endif
        @houseTitle: "ASA 2 - Pattern Recognition: " + .mode$, "Same acoustic six-tone family; grouping can help or camouflage the target pattern"
        h1=2500
        h2=2000
        h3=1600
        l1=350
        l2=430
        l3=550
        d=0.1

        @panelTitle:0,3.9,0.80,1.04,"A  THREE-TONE STANDARD"
        Select inner viewport: 0.45,3.75,1.15,2.62
        Axes: 0,0.6,200,3000
        Paint rectangle: lightBG$,0,0.6,200,3000
        @toneRect:0,0.08,h1,130,highColor$
        @toneRect:0.2,0.28,h2,130,highColor$
        if .cross=0
            @toneRect:0.4,0.48,h3,130,highColor$
            .f3=h3
        else
            @toneRect:0.4,0.48,l3,130,lowColor$
            .f3=l3
        endif
        Colour: melodyColor$
        Line width: 2
        Draw line: 0.04,h1,0.24,h2
        Draw line: 0.24,h2,0.44,.f3
        Line width: 1
        @basicAxes: 0.6,200,3000,0.2,500

        @panelTitle:4.1,8,0.80,1.04,"B  STANDARD INSIDE FULL CYCLE"
        Select inner viewport: 4.55,7.85,1.15,2.62
        Axes: 0,0.6,200,3000
        Paint rectangle: lightBG$,0,0.6,200,3000
        if .cross=0
            .f5=h3
            .f6=l3
        else
            .f5=l3
            .f6=h3
        endif
        @toneRect:0,0.08,h1,130,highColor$
        @toneRect:0.1,0.18,l1,130,lowColor$
        @toneRect:0.2,0.28,h2,130,highColor$
        @toneRect:0.3,0.38,l2,130,lowColor$
        if .f5 > 1000
            @toneRect:0.4,0.48,.f5,130,highColor$
        else
            @toneRect:0.4,0.48,.f5,130,lowColor$
        endif
        if .f6 > 1000
            @toneRect:0.5,0.58,.f6,130,highColor$
        else
            @toneRect:0.5,0.58,.f6,130,lowColor$
        endif
        Colour: melodyColor$
        Line width: 2
        Draw line: 0.04,h1,0.24,h2
        Draw line: 0.24,h2,0.44,.f5
        Line width: 1
        @basicAxes: 0.6,200,3000,0.2,500

        @panelTitle:0,3.9,2.97,3.21,"C  PATTERN MEMBERSHIP"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 0.5,3.5,-0.4,1.4
        Paint rectangle: lightBG$,0.5,3.5,-0.4,1.4
        Colour: gridColor$
        Draw line: 0.5,0.5,3.5,0.5
        for .i from 1 to 3
            if .i < 3 or .cross=0
                .y=1
                Paint rectangle: highColor$, .i-0.06, .i+0.06, .y-0.06, .y+0.06
            else
                .y=0
                Paint rectangle: lowColor$, .i-0.06, .i+0.06, .y-0.06, .y+0.06
            endif
        endfor
        Colour: "Black"
        Font size: 7
        Text: 0.65,"left",1,"half","high stream"
        Text: 0.65,"left",0,"half","low stream"
        Draw inner box
        Text bottom: "yes","Target-note position"

        if show_spectrogram
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FULL-CYCLE SPECTROGRAM"
        else
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FULL-CYCLE WAVEFORM"
        endif
        @measuredPanel:.soundID,10.0,10.6,3200
        @summaryBar:"100 ms tones | low tones +1.5 dB | standard repeated before full six-tone cycle"

    elsif .which = 4 or .which = 5
        if .which=4
            .mode$="LARGE SEPARATION"
            .lowF=500
        else
            .mode$="SMALL SEPARATION"
            .lowF=1320
        endif
        .highF=1400
        @houseTitle:"ASA 3 - Loss of Rhythm: "+.mode$,"Exact HLH-gap pattern; acceleration reaches the published 88 ms endpoint"

        @panelTitle:0,3.9,0.80,1.04,"A  PHYSICAL HLH-GAP CYCLE"
        Select inner viewport: 0.45,3.75,1.15,2.62
        Axes: 0,1.148,300,1700
        Paint rectangle: lightBG$,0,1.148,300,1700
        .u=0.287
        @toneRect:0,0.267,.highF,70,highColor$
        @toneRect:0.287,0.554,.lowF,70,lowColor$
        @toneRect:0.574,0.841,.highF,70,highColor$
        Colour: textGray$
        Font size: 7
        Text: 0.995,"centre",1000,"half","silence"
        @basicAxes: 1.148,300,1700,0.287,200

        @panelTitle:4.1,8,0.80,1.04,"B  GROUPING HYPOTHESIS AT FAST RATE"
        Select inner viewport: 4.55,7.85,1.15,2.62
        Axes: 0,0.352,300,1700
        Paint rectangle: lightBG$,0,0.352,300,1700
        .u=0.088
        @toneRect:0,0.068,.highF,70,highColor$
        @toneRect:0.088,0.156,.lowF,70,lowColor$
        @toneRect:0.176,0.244,.highF,70,highColor$
        if .which=4
            Colour: highColor$
            Line width: 2
            Draw line: 0.034,.highF,0.210,.highF
            Colour: lowColor$
            Paint rectangle: lowColor$, 0.116, 0.128, .lowF-20, .lowF+20
            Font size: 7
            Colour: textGray$
            Text: 0.176,"centre",1550,"half","split streams"
        else
            Colour: melodyColor$
        Line width: 2
            Draw line: 0.034,.highF,0.122,.lowF
            Draw line: 0.122,.lowF,0.210,.highF
            Font size: 7
            Colour: textGray$
            Text: 0.176,"centre",1550,"half","one stream"
        endif
        Line width: 1
        @basicAxes: 0.352,300,1700,0.088,200

        @panelTitle:0,3.9,2.97,3.21,"C  ACTUAL TEMPO LAW"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 1,20,70,310
        Paint rectangle: lightBG$,1,20,70,310
        .prevX=1
        .prevY=287
        for .i from 1 to 20
            .frac=(.i-1)/19
            .ms=287*(88/287)^.frac
            if .i>1
                Colour: lowColor$
                Line width: 1.5
                Draw line: .prevX,.prevY,.i,.ms
            endif
            .prevX=.i
            .prevY=.ms
        endfor
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text bottom: "yes","Cycle"
        Text left: "yes","Unit duration (ms)"
        Marks bottom every: 1,5,"yes","yes","no"
        Marks left every: 1,50,"yes","yes","no"

        if show_spectrogram
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED ACCELERATION SPECTROGRAM"
        else
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED ACCELERATION WAVEFORM"
        endif
        selectObject:.soundID
        .dur=Get total duration
        @measuredPanel:.soundID,0,.dur,1800
        .semi=12*log2(.highF/.lowF)
        @summaryBar:"1400 vs "+fixed$(.lowF,0)+" Hz | separation "+fixed$(.semi,1)+" semitones | 20 exponential-speed cycles: 287 -> 88 ms/unit"

    elsif .which = 6
        @houseTitle:"ASA 4 - Cumulative Streaming","Longer uninterrupted HLH sequences provide more evidence for segregation"
        .h=2000
        .l=700
        @panelTitle:0,3.9,0.80,1.04,"A  ONE GALLOPING CYCLE"
        Select inner viewport: 0.45,3.75,1.15,2.62
        Axes: 0,0.5,400,2300
        Paint rectangle: lightBG$,0,0.5,400,2300
        @toneRect:0,0.113,.h,90,highColor$
        @toneRect:0.125,0.238,.l,90,lowColor$
        @toneRect:0.250,0.363,.h,90,highColor$
        Colour: textGray$
        Font size: 7
        Text: 0.43,"centre",1350,"half","125 ms gap"
        @basicAxes: 0.5,400,2300,0.125,500

        @panelTitle:4.1,8,0.80,1.04,"B  PRESENTATION SCHEDULE"
        Select inner viewport: 4.55,7.85,1.15,2.62
        Axes: 0,6,0,35
        Paint rectangle: lightBG$,0,6,0,35
        for .i from 1 to 5
            .n=2^.i
            Paint rectangle: lowColor$,.i-0.28,.i+0.28,0,.n
            Colour: "Black"
            Font size: 7
            Text: .i,"centre",.n+2,"half",string$(.n)
        endfor
        Draw inner box
        Text bottom: "yes","Block number"
        Text left: "yes","Uninterrupted cycles"

        @panelTitle:0,3.9,2.97,3.21,"C  PERCEPTUAL HYPOTHESIS"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 2,32,0,1
        Paint rectangle: lightBG$,2,32,0,1
        Colour: gridColor$
        Draw line: 2,0.5,32,0.5
        Colour: highColor$
        Line width: 1.5
        .px=2
        .py=0.18
        for .i from 2 to 32
            .y=0.12+0.78*(1-exp(-(.i-2)/8))
            if .i>2
                Draw line: .px,.py,.i,.y
            endif
            .px=.i
            .py=.y
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text bottom: "yes","Repetitions"
        Text left: "yes","Schematic split tendency"
        Font size: 6
        Colour: textGray$
        Text: 17,"centre",0.08,"half","conceptual - not a listener measurement"

        if show_spectrogram
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FINAL-BLOCK SPECTROGRAM"
        else
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FINAL-BLOCK WAVEFORM"
        endif
        selectObject:.soundID
        .dur=Get total duration
        .t1=.dur-4
        if .t1 < 0
            .t1 = 0
        endif
        @measuredPanel:.soundID,.t1,.dur,2600
        @summaryBar:"2000/700 Hz | low +6 dB | blocks: 2,4,8,16,32 cycles | 4 s silence resets between blocks"

    elsif .which = 7
        @houseTitle:"ASA 5 - Melody from Interference","Five presentations; same distractors, melody rises by two semitones each time"
        .base=256
        .event=0.143
        .tone=0.120

        @panelTitle:0,3.9,0.80,1.04,"A  FIRST PRESENTATION"
        Select inner viewport: 0.45,3.75,1.15,2.62
        Axes: 0,8*.event*2,220,650
        Paint rectangle: lightBG$,0,8*.event*2,220,650
        for .i from 1 to 8
            .m=.base*(2^(demo5Semi[.i]/12))
            .d=demo5DistractorHz[.i]
            .t=(.i-1)*2*.event
            @toneRect:.t,.t+.tone,.m,24,melodyColor$
            @toneRect:.t+.event,.t+.event+.tone,.d,24,distractorColor$
        endfor
        @basicAxes: 8*.event*2,220,650,0.572,100

        @panelTitle:4.1,8,0.80,1.04,"B  FIFTH PRESENTATION (+8 st)"
        Select inner viewport: 4.55,7.85,1.15,2.62
        Axes: 0,8*.event*2,220,850
        Paint rectangle: lightBG$,0,8*.event*2,220,850
        .prevT=-1
        .prevF=0
        for .i from 1 to 8
            .m=.base*(2^((demo5Semi[.i]+8)/12))
            .d=demo5DistractorHz[.i]
            .t=(.i-1)*2*.event
            @toneRect:.t,.t+.tone,.m,24,melodyColor$
            @toneRect:.t+.event,.t+.event+.tone,.d,24,distractorColor$
            if .prevT>=0
                Colour: melodyColor$
                Line width: 1.5
                Draw line: .prevT,.prevF,.t+.tone/2,.m
            endif
            .prevT=.t+.tone/2
            .prevF=.m
        endfor
        Line width: 1
        @basicAxes: 8*.event*2,220,850,0.572,100

        @panelTitle:0,3.9,2.97,3.21,"C  TRANSPOSITION LAW"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 1,5,-1,9
        Paint rectangle: lightBG$,1,5,-1,9
        .px=1
        .py=0
        for .i from 1 to 5
            .st=2*(.i-1)
            if .i>1
                Colour: melodyColor$
                Line width: 1.5
                Draw line: .px,.py,.i,.st
            endif
            Colour: melodyColor$
            Paint rectangle: melodyColor$, .i-0.05, .i+0.05, .st-0.12, .st+0.12
            Colour: "Black"
            Font size: 7
            Text: .i,"centre",.st+0.7,"half","+"+string$(.st)
            .px=.i
            .py=.st
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Text bottom: "yes","Presentation"
        Text left: "yes","Melody shift (semitones)"

        if show_spectrogram
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FIFTH-PASS SPECTROGRAM"
        else
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FIFTH-PASS WAVEFORM"
        endif
        .roundDur=demo5N*2*.event
        .t1=0.001+4*(.roundDur+0.5)
        .t2=.t1+.roundDur
        @measuredPanel:.soundID,.t1,.t2,1000
        @summaryBar:"5 passes: +0,+2,+4,+6,+8 st | 7 events/s | 120 ms tone + 23 ms silence | identical distractors each pass"

    elsif .which = 8
        @houseTitle:"ASA 6 - Telemann-style Compound Melody Model","Synthetic abstraction of alternating fixed G5 and changing lower notes; not the source recording"
        .g5 = 783.99
        .notes[1] = 783.99
        .notes[2] = 659.25
        .notes[3] = 783.99
        .notes[4] = 523.25
        .notes[5] = 783.99
        .notes[6] = 587.33
        .notes[7] = 783.99
        .notes[8] = 493.88

        @panelTitle:0,3.9,0.80,1.04,"A  SLOW: ONE LINE"
        Select inner viewport: 0.45,3.75,1.15,2.62
        Axes: 0,2,380,850
        Paint rectangle: lightBG$,0,2,380,850
        for .i from 1 to 8
            .t=(.i-1)*0.25
            @toneRect:.t,.t+0.2125,.notes[.i],24,"{0.48,0.48,0.55}"
            if .i>1
                Colour: textGray$
                Draw line: (.i-2)*0.25+0.106,.notes[.i-1],.t+0.106,.notes[.i]
            endif
        endfor
        @basicAxes: 2,380,850,0.5,100

        @panelTitle:4.1,8,0.80,1.04,"B  FAST: GROUPING HYPOTHESIS"
        Select inner viewport: 4.55,7.85,1.15,2.62
        Axes: 0,0.8,380,850
        Paint rectangle: lightBG$,0,0.8,380,850
        .prevLowT=-1
        .prevLowF=0
        .prevHighT=-1
        for .i from 1 to 8
            .t=(.i-1)*0.1
            if .notes[.i]=.g5
                @toneRect:.t,.t+0.085,.notes[.i],24,highColor$
                if .prevHighT>=0
                    Colour: highColor$
                    Line width: 2
                    Draw line: .prevHighT,.g5,.t+0.0425,.g5
                endif
                .prevHighT=.t+0.0425
            else
                @toneRect:.t,.t+0.085,.notes[.i],24,lowColor$
                if .prevLowT>=0
                    Colour: lowColor$
                    Line width: 2
                    Draw line: .prevLowT,.prevLowF,.t+0.0425,.notes[.i]
                endif
                .prevLowT=.t+0.0425
                .prevLowF=.notes[.i]
            endif
        endfor
        Line width: 1
        @basicAxes: 0.8,380,850,0.2,100

        @panelTitle:0,3.9,2.97,3.21,"C  RATE CONTROL"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 0,3,0,280
        Paint rectangle: lightBG$,0,3,0,280
        Paint rectangle: lowColor$,0.55,1.25,0,250
        Paint rectangle: highColor$,1.75,2.45,0,100
        Colour: "Black"
        Font size: 7
        Text: 0.9,"centre",265,"half","250 ms"
        Text: 2.1,"centre",115,"half","100 ms"
        Text: 0.9,"centre",18,"half","slow"
        Text: 2.1,"centre",18,"half","fast"
        Draw inner box
        Text left: "yes","Tone duration (ms)"

        if show_spectrogram
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FAST-PASS SPECTROGRAM"
        else
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED FAST-PASS WAVEFORM"
        endif
        @measuredPanel:.soundID,9.0,10.6,1000
        @summaryBar:"Synthetic compound-melody model | fixed G5 alternates with changing lower notes | 250 ms -> 100 ms"

    elsif .which = 9 or .which = 10
        if .which=9
            .name$="ASA 7 - Amadinda-style Interlocking Model"
            .sub$="Two isochronous synthetic parts interlock; perceived streams need not follow player ownership"
            .shift=0
        else
            .name$="ASA 8 - Amadinda-style Pitch-Range Separation"
            .sub$="The same synthetic interlock, with Part B shifted up one octave to favor player-based streaming"
            .shift=1
        endif
        @houseTitle:.name$,.sub$
        .base=350
        .f1=.base
        .f3=.base*(2^(480/1200))
        .f4=.base*(2^(720/1200))
        .f5=.base*(2^(960/1200))
        if .shift=1
            .f4=.f4*2
            .f5=.f5*2
            .fMax=1300
        else
            .fMax=750
        endif
        .d=0.12

        @panelTitle:0,3.9,0.80,1.04,"A  PLAYER OWNERSHIP"
        Select inner viewport: 0.45,3.75,1.15,2.62
        Axes: 0,0.48,250,.fMax
        Paint rectangle: lightBG$,0,0.48,250,.fMax
        @toneRect:0,0.084,.f1,30,partAColor$
        @toneRect:0.12,0.204,.f4,30,partBColor$
        @toneRect:0.24,0.324,.f3,30,partAColor$
        @toneRect:0.36,0.444,.f5,30,partBColor$
        Colour: "Black"
        Font size: 6
        Text: 0.04,"centre",.f1+45,"half","A"
        Text: 0.16,"centre",.f4+45,"half","B"
        Text: 0.28,"centre",.f3+45,"half","A"
        Text: 0.40,"centre",.f5+45,"half","B"
        if .shift = 1
            .fStep = 200
        else
            .fStep = 100
        endif
        @basicAxes: 0.48,250,.fMax,0.12,.fStep

        @panelTitle:4.1,8,0.80,1.04,"B  GROUPING HYPOTHESIS"
        Select inner viewport: 4.55,7.85,1.15,2.62
        Axes: 0,0.96,250,.fMax
        Paint rectangle: lightBG$,0,0.96,250,.fMax
        for .c from 0 to 1
            .o=.c*0.48
            @toneRect:.o,.o+0.084,.f1,30,partAColor$
            @toneRect:.o+0.12,.o+0.204,.f4,30,partBColor$
            @toneRect:.o+0.24,.o+0.324,.f3,30,partAColor$
            @toneRect:.o+0.36,.o+0.444,.f5,30,partBColor$
        endfor
        Line width: 2
        if .shift=0
            Colour: melodyColor$
            Draw line: 0.042,.f1,0.162,.f4
            Draw line: 0.162,.f4,0.282,.f3
            Draw line: 0.282,.f3,0.402,.f5
            Draw line: 0.402,.f5,0.522,.f1
            Draw line: 0.522,.f1,0.642,.f4
            Draw line: 0.642,.f4,0.762,.f3
            Draw line: 0.762,.f3,0.882,.f5
        else
            Colour: partAColor$
            Draw line: 0.042,.f1,0.282,.f3
            Draw line: 0.282,.f3,0.522,.f1
            Draw line: 0.522,.f1,0.762,.f3
            Colour: partBColor$
            Draw line: 0.162,.f4,0.402,.f5
            Draw line: 0.402,.f5,0.642,.f4
            Draw line: 0.642,.f4,0.882,.f5
        endif
        Line width: 1
        @basicAxes: 0.96,250,.fMax,0.24,.fStep

        @panelTitle:0,3.9,2.97,3.21,"C  EVENT RATE"
        Select inner viewport: 0.45,3.75,3.32,4.78
        Axes: 0,3,0,10
        Paint rectangle: lightBG$,0,3,0,10
        Paint rectangle: partAColor$,0.5,1.2,0,4.17
        Paint rectangle: melodyColor$,1.8,2.5,0,8.33
        Colour: "Black"
        Font size: 7
        Text: 0.85,"centre",4.65,"half","4.17/s"
        Text: 2.15,"centre",8.8,"half","8.33/s"
        Text: 0.85,"centre",0.6,"half","each part"
        Text: 2.15,"centre",0.6,"half","combined"
        Draw inner box
        Text left: "yes","Tone onsets per second"

        if show_spectrogram
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED DUET SPECTROGRAM"
        else
            @panelTitle:4.1,8,2.97,3.21,"D  MEASURED DUET WAVEFORM"
        endif
        @measuredPanel:.soundID,9.68,11.60,.fMax+100
        if .shift=0
            @summaryBar:"Synthetic amadinda-style model | exponential decay half-life ~17 ms | player parts interlock at 8.33 events/s"
        else
            @summaryBar:"Same synthetic interlock | Part B shifted +1 octave | pitch-range separation favors player-based streams"
        endif
    endif

    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# 1. CORE SYNTHESIS PROCEDURES
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
    Create Sound from formula: "xylo", 1, 0, .dur, sampleRate, "sin(2*pi*.freq*x) * exp(-40*x)"
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
# 2. EXPERIMENT-SPECIFIC SYNTHESIS PROCEDURES
# -------------------------

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

procedure MakePartA: .count
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
clearinfo
writeInfoLine: "=== Auditory Scene Analysis Demos v2.1 ==="
appendInfoLine: "Synthetic pedagogical reconstructions; perceptual overlays are hypotheses."
appendInfoLine: ""

if experiment_Type = 1
    appendInfoLine: "Demo 1: Stream Segregation"
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
    Rename: "Demo_1_StreamSegregation"
    finalName$ = "Demo_1_StreamSegregation"
    selectObject: "Sound part1", "Sound slowCyc", "Sound part2", "Sound fastCyc", "Sound gap"
    Remove
endif

if experiment_Type = 2 or experiment_Type = 3
    if experiment_Type = 2
        appendInfoLine: "Demo 2: Pattern Recognition (Within-Stream)"
        @MakeD2Cycle: "Within_Standard"
        Rename: "std"
        @RepeatSound: "std", 15, "PartA"
        @MakeD2Cycle: "Normal"
        Rename: "full"
        @RepeatSound: "full", 15, "PartB"
        finalName$ = "Demo_2_Within"
    else
        appendInfoLine: "Demo 2: Pattern Recognition (Across-Stream)"
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
    if experiment_Type = 4
        appendInfoLine: "Demo 3: Loss of Rhythm (Large Separation)"
        h3 = 1400
        l3 = 500
    else
        appendInfoLine: "Demo 3: Loss of Rhythm (Small Separation)"
        h3 = 1400
        l3 = 1320
    endif

    # Published endpoint is 287 -> 88 ms/unit. v2.0 stopped near 169 ms.
    d3Cycles = 20
    startUnit = 0.287
    endUnit = 0.088
    d3_Rise = 0.010
    d3_Fall = 0.020

    @MakeGap: 0.001
    Rename: "accumulator"
    for cycIndex from 1 to d3Cycles
        frac = (cycIndex - 1) / (d3Cycles - 1)
        currentUnit = startUnit * ((endUnit / startUnit) ^ frac)
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
    endfor
    selectObject: "Sound accumulator"
    Rename: "Demo_3_LossOfRhythm"
    finalName$ = "Demo_3_LossOfRhythm"
    appendInfoLine: "Tempo law: 20 cycles, 287 -> 88 ms/unit (actual endpoint reached)."
endif

if experiment_Type = 6
    appendInfoLine: "Demo 4: Cumulative Effects"
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

    selectObject: "Sound th", "Sound tg", "Sound tl", "Sound tg2", "Sound th2", "Sound cg"
    Concatenate
    Rename: "Cycle4"
    selectObject: "Sound th", "Sound tl", "Sound tg", "Sound cg", "Sound th2", "Sound tg2"
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
    appendInfoLine: "Demo 5: Melody from Interference"
    baseC4 = 256
    toneDur5 = 0.120
    gapDur5 = 0.023
    eventDur5 = toneDur5 + gapDur5
    roundGap5 = 0.500

    # Use ONE fixed random-like distractor realization, tied to the
    # untransposed melody, and reuse it for every presentation.
    for n from 1 to demo5N
        demo5DistractorHz[n] = baseC4 * (2 ^ ((demo5Semi[n] + demo5DistractorOffset[n]) / 12))
    endfor

    @MakeGap: 0.001
    Rename: "Demo5_Accum"
    for round from 1 to 5
        trans = 2 * (round - 1)
        for n from 1 to demo5N
            mHz = baseC4 * (2 ^ ((demo5Semi[n] + trans) / 12))
            dHz = demo5DistractorHz[n]

            @MakeTone: mHz, toneDur5, gainHigh, 0.003, 0.020
            Rename: "mTone"
            @MakeGap: gapDur5
            Rename: "mGap"
            @MakeTone: dHz, toneDur5, gainHigh, 0.003, 0.020
            Rename: "dTone"
            @MakeGap: gapDur5
            Rename: "dGap"

            selectObject: "Sound Demo5_Accum", "Sound mTone", "Sound mGap", "Sound dTone", "Sound dGap"
            Concatenate
            Rename: "Demo5_Next"
            selectObject: "Sound Demo5_Accum", "Sound mTone", "Sound mGap", "Sound dTone", "Sound dGap"
            Remove
            selectObject: "Sound Demo5_Next"
            Rename: "Demo5_Accum"
        endfor
        if round < 5
            @MakeGap: roundGap5
            Rename: "RoundGap"
            selectObject: "Sound Demo5_Accum", "Sound RoundGap"
            Concatenate
            Rename: "Demo5_Next"
            selectObject: "Sound Demo5_Accum", "Sound RoundGap"
            Remove
            selectObject: "Sound Demo5_Next"
            Rename: "Demo5_Accum"
        endif
    endfor
    selectObject: "Sound Demo5_Accum"
    Rename: "Demo_5_Melody"
    finalName$ = "Demo_5_Melody"
    appendInfoLine: "Five passes: melody +0,+2,+4,+6,+8 semitones; distractors unchanged."
endif

if experiment_Type = 8
    appendInfoLine: "Demo 6: Telemann-style Compound Melody Model"
    appendInfoLine: "Note: synthetic abstraction, not the original Telemann recording."
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
    Rename: "Demo_6_TelemannModel"
    finalName$ = "Demo_6_TelemannModel"
    selectObject: "Sound PartA", "Sound SlowPass", "Sound PartB", "Sound FastPass", "Sound Gap"
    Remove
endif

if experiment_Type = 9 or experiment_Type = 10
    baseHz = 350
    xyloDur = 0.120
    f1 = baseHz
    f2 = baseHz * (2 ^ (240/1200))
    f3 = baseHz * (2 ^ (480/1200))
    f4 = baseHz * (2 ^ (720/1200))
    f5 = baseHz * (2 ^ (960/1200))
    f6 = baseHz * (2 ^ (1200/1200))

    if experiment_Type = 9
        appendInfoLine: "Demo 7: Amadinda-style Interlocking Model"
        appendInfoLine: "Note: synthetic interlocking model, not the source recording."
    else
        appendInfoLine: "Demo 8: Amadinda-style Pitch-Range Separation"
        appendInfoLine: "Note: synthetic interlocking model, not the source recording."
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
        Rename: "Demo_7_AmadindaModel"
        finalName$ = "Demo_7_AmadindaModel"
    else
        Rename: "Demo_8_PitchSepModel"
        finalName$ = "Demo_8_PitchSepModel"
    endif
    selectObject: "Sound PartA_Solo", "Sound Gap1", "Sound PartB_Solo", "Sound Gap2", "Sound Duet"
    Remove
endif

# -------------------------
# FINAL OUTPUT + VISUALIZATION
# -------------------------
selectObject: "Sound " + finalName$
Scale peak: 0.99
finalID = selected("Sound")

appendInfoLine: ""
appendInfoLine: "Output: ", finalName$
selectObject: finalID
finalDur = Get total duration
appendInfoLine: "Duration: ", fixed$(finalDur, 3), " s"
appendInfoLine: ""

if show_visualization
    @visualizeASA: experiment_Type, finalID
endif

selectObject: finalID
if play_result
    Play
endif
appendInfoLine: "Done!"
