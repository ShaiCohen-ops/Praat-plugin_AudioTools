# ============================================================
# Praat AudioTools - ASA_Demos.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Bregman-style Visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Auditory Scene Analysis Demos with Bregman-style visualization
#   Based on phenomena from "Auditory Scene Analysis" (Bregman, 1990)
#
# Visualization Style:
#   - Frequency × Time diagrams
#   - Rectangular tone representations
#   - Stream grouping indicators (color, contours)
#   - Perceptual organization overlays
#
# ============================================================

form Auditory Scene Analysis Demos v2.0
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
    comment === Visualization ===
    boolean Show_visualization 1
    boolean Show_spectrogram 1
    boolean Play_result 1
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

# Stream colors (Bregman style)
streamHighColor$ = "{0.8, 0.3, 0.3}"
streamLowColor$ = "{0.3, 0.5, 0.8}"
streamMelodyColor$ = "{0.3, 0.7, 0.4}"
streamDistractorColor$ = "{0.6, 0.6, 0.6}"
streamAColor$ = "{0.8, 0.4, 0.2}"
streamBColor$ = "{0.2, 0.5, 0.7}"

# -------------------------
# VISUALIZATION PROCEDURES
# -------------------------

procedure drawBregmanTitle: .title$, .subtitle$
    Select outer viewport: 0, 8, 0, 1.1
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.7, "half", "##" + .title$ + "##"
    Font size: 9
    Colour: "{0.3, 0.3, 0.4}"
    Text: 0.5, "centre", 0.25, "half", .subtitle$
endproc

procedure drawToneRect: .tStart, .tEnd, .freqLow, .freqHigh, .color$
    Paint rectangle: .color$, .tStart, .tEnd, .freqLow, .freqHigh
    # Outline
    Colour: "Black"
    Line width: 0.5
    Draw rectangle: .tStart, .tEnd, .freqLow, .freqHigh
endproc

procedure drawStreamContour: .x1, .y1, .x2, .y2, .color$
    # Draw curved line connecting tones in same stream
    Colour: .color$
    Line width: 2
    # Simple line connection (Bregman often uses this)
    Draw line: .x1, .y1, .x2, .y2
    Line width: 1
endproc

procedure drawFreqTimeAxes: .tMax, .fMin, .fMax, .logScale
    Colour: "Black"
    Line width: 1
    Draw inner box
    
    # Time axis
    Font size: 8
    Text bottom: "yes", "Time (s)"
    
    if .tMax > 3
        Marks bottom every: 1, 1, "yes", "yes", "no"
    elsif .tMax > 1
        Marks bottom every: 1, 0.5, "yes", "yes", "no"
    else
        Marks bottom every: 1, 0.2, "yes", "yes", "no"
    endif
    
    # Frequency axis
    Text left: "yes", "Frequency (Hz)"
    
    if .fMax > 3000
        Marks left every: 1, 1000, "yes", "yes", "no"
    elsif .fMax > 1000
        Marks left every: 1, 500, "yes", "yes", "no"
    else
        Marks left every: 1, 200, "yes", "yes", "no"
    endif
endproc

procedure drawLegend: .x, .y, .items, .colors$, .labels$
    # Draw a simple legend box
    Font size: 7
    .boxW = 0.04
    .boxH = 0.06
    .spacing = 0.12
    
    # This is a simplified version - actual implementation needs arrays
endproc

# -------------------------
# DEMO 1: Stream Segregation Visualization
# -------------------------
procedure visualizeDemo1
    Erase all
    
    @drawBregmanTitle: "Demo 1: Stream Segregation", "Effect of presentation rate on perceptual organization"
    
    h1 = 2500
    h2 = 2000
    h3 = 1600
    l1 = 350
    l2 = 430
    l3 = 550
    
    fMin = 200
    fMax = 3000
    toneHeight = 150
    
    # === PANEL A: Slow Presentation (Integrated) ===
    Select outer viewport: 0, 8, 1.0, 3.5
    Select inner viewport: 0.7, 7.7, 1.2, 3.3
    
    slowDur = 0.4
    tMax = slowDur * 6
    
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Draw tones
    t = 0
    # H1
    @drawToneRect: t, t + slowDur * 0.8, h1 - toneHeight/2, h1 + toneHeight/2, streamHighColor$
    t += slowDur
    # L1
    @drawToneRect: t, t + slowDur * 0.8, l1 - toneHeight/2, l1 + toneHeight/2, streamLowColor$
    t += slowDur
    # H2
    @drawToneRect: t, t + slowDur * 0.8, h2 - toneHeight/2, h2 + toneHeight/2, streamHighColor$
    t += slowDur
    # L2
    @drawToneRect: t, t + slowDur * 0.8, l2 - toneHeight/2, l2 + toneHeight/2, streamLowColor$
    t += slowDur
    # H3
    @drawToneRect: t, t + slowDur * 0.8, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
    t += slowDur
    # L3
    @drawToneRect: t, t + slowDur * 0.8, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
    
    # Draw integrated stream contour (galloping perception)
    Colour: "{0.4, 0.4, 0.4}"
    Line width: 2
    Dashed line
    # Connect all tones as one stream
    Draw line: slowDur * 0.4, h1, slowDur * 1.4, l1
    Draw line: slowDur * 1.4, l1, slowDur * 2.4, h2
    Draw line: slowDur * 2.4, h2, slowDur * 3.4, l2
    Draw line: slowDur * 3.4, l2, slowDur * 4.4, h3
    Draw line: slowDur * 4.4, h3, slowDur * 5.4, l3
    Solid line
    Line width: 1
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    # Label
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: tMax / 2, "centre", fMax + 150, "half", "SLOW: One integrated stream (galloping)"
    
    # === PANEL B: Fast Presentation (Segregated) ===
    Select outer viewport: 0, 8, 3.7, 6.2
    Select inner viewport: 0.7, 7.7, 3.9, 6.0
    
    fastDur = 0.1
    tMax = fastDur * 12
    
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Draw two cycles of tones
    for cycle from 0 to 1
        offset = cycle * fastDur * 6
        
        t = offset
        @drawToneRect: t, t + fastDur * 0.8, h1 - toneHeight/2, h1 + toneHeight/2, streamHighColor$
        t += fastDur
        @drawToneRect: t, t + fastDur * 0.8, l1 - toneHeight/2, l1 + toneHeight/2, streamLowColor$
        t += fastDur
        @drawToneRect: t, t + fastDur * 0.8, h2 - toneHeight/2, h2 + toneHeight/2, streamHighColor$
        t += fastDur
        @drawToneRect: t, t + fastDur * 0.8, l2 - toneHeight/2, l2 + toneHeight/2, streamLowColor$
        t += fastDur
        @drawToneRect: t, t + fastDur * 0.8, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        t += fastDur
        @drawToneRect: t, t + fastDur * 0.8, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
    endfor
    
    # Draw segregated stream contours
    # High stream
    Colour: streamHighColor$
    Line width: 2
    for cycle from 0 to 1
        offset = cycle * fastDur * 6
        Draw line: offset + fastDur * 0.4, h1, offset + fastDur * 2.4, h2
        Draw line: offset + fastDur * 2.4, h2, offset + fastDur * 4.4, h3
        if cycle = 0
            Draw line: offset + fastDur * 4.4, h3, offset + fastDur * 6.4, h1
        endif
    endfor
    
    # Low stream
    Colour: streamLowColor$
    for cycle from 0 to 1
        offset = cycle * fastDur * 6
        Draw line: offset + fastDur * 1.4, l1, offset + fastDur * 3.4, l2
        Draw line: offset + fastDur * 3.4, l2, offset + fastDur * 5.4, l3
        if cycle = 0
            Draw line: offset + fastDur * 5.4, l3, offset + fastDur * 7.4, l1
        endif
    endfor
    Line width: 1
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: tMax / 2, "centre", fMax + 150, "half", "FAST: Two segregated streams"
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 6.4, 7.0
    Axes: 0, 1, 0, 1
    
    Font size: 8
    
    # High stream
    Paint rectangle: streamHighColor$, 0.15, 0.19, 0.4, 0.7
    Colour: "Black"
    Text: 0.21, "left", 0.55, "half", "High tones (2500-1600 Hz)"
    
    # Low stream
    Paint rectangle: streamLowColor$, 0.55, 0.59, 0.4, 0.7
    Colour: "Black"
    Text: 0.61, "left", 0.55, "half", "Low tones (350-550 Hz)"
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# DEMO 2: Pattern Recognition Visualization
# -------------------------
procedure visualizeDemo2: .type$
    Erase all
    
    if .type$ = "Within"
        @drawBregmanTitle: "Demo 2: Within-Stream Pattern", "Patterns are easy to detect within a single frequency region"
    else
        @drawBregmanTitle: "Demo 2: Across-Stream Pattern", "Patterns spanning frequency regions are difficult to detect"
    endif
    
    h1 = 2500
    h2 = 2000
    h3 = 1600
    l1 = 350
    l2 = 430
    l3 = 550
    
    fMin = 200
    fMax = 3000
    toneHeight = 150
    toneDur = 0.1
    
    # === PANEL A: Standard Pattern ===
    Select outer viewport: 0, 8, 1.0, 3.2
    Select inner viewport: 0.7, 7.7, 1.2, 3.0
    
    tMax = toneDur * 6
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    if .type$ = "Within"
        # Standard: H1 - H2 - H3 (gaps between)
        t = 0
        @drawToneRect: t, t + toneDur * 0.8, h1 - toneHeight/2, h1 + toneHeight/2, streamHighColor$
        t += toneDur * 2
        @drawToneRect: t, t + toneDur * 0.8, h2 - toneHeight/2, h2 + toneHeight/2, streamHighColor$
        t += toneDur * 2
        @drawToneRect: t, t + toneDur * 0.8, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        
        # Highlight pattern
        Colour: "{0.2, 0.7, 0.3}"
        Line width: 3
        Draw line: toneDur * 0.4, h1, toneDur * 2.4, h2
        Draw line: toneDur * 2.4, h2, toneDur * 4.4, h3
        Line width: 1
        
        Font size: 9
        Colour: "{0.2, 0.6, 0.3}"
        Text: tMax / 2, "centre", fMax + 150, "half", "Standard: Descending pattern H1→H2→H3 (WITHIN high stream)"
    else
        # Standard: H1 - H2 - L3
        t = 0
        @drawToneRect: t, t + toneDur * 0.8, h1 - toneHeight/2, h1 + toneHeight/2, streamHighColor$
        t += toneDur * 2
        @drawToneRect: t, t + toneDur * 0.8, h2 - toneHeight/2, h2 + toneHeight/2, streamHighColor$
        t += toneDur * 2
        @drawToneRect: t, t + toneDur * 0.8, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
        
        # Highlight pattern (crosses streams)
        Colour: "{0.8, 0.5, 0.2}"
        Line width: 3
        Dashed line
        Draw line: toneDur * 0.4, h1, toneDur * 2.4, h2
        Draw line: toneDur * 2.4, h2, toneDur * 4.4, l3
        Solid line
        Line width: 1
        
        Font size: 9
        Colour: "{0.7, 0.4, 0.2}"
        Text: tMax / 2, "centre", fMax + 150, "half", "Standard: Pattern H1→H2→L3 (ACROSS streams - hard to hear)"
    endif
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    # === PANEL B: Full Sequence ===
    Select outer viewport: 0, 8, 3.4, 5.6
    Select inner viewport: 0.7, 7.7, 3.6, 5.4
    
    tMax = toneDur * 6
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    if .type$ = "Within"
        # Full: H1-L1-H2-L2-H3-L3
        t = 0
        @drawToneRect: t, t + toneDur * 0.8, h1 - toneHeight/2, h1 + toneHeight/2, streamHighColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, l1 - toneHeight/2, l1 + toneHeight/2, streamLowColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, h2 - toneHeight/2, h2 + toneHeight/2, streamHighColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, l2 - toneHeight/2, l2 + toneHeight/2, streamLowColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
        
        # Show pattern embedded in high stream
        Colour: "{0.2, 0.7, 0.3}"
        Line width: 3
        Draw line: toneDur * 0.4, h1, toneDur * 2.4, h2
        Draw line: toneDur * 2.4, h2, toneDur * 4.4, h3
        Line width: 1
        
        Font size: 9
        Colour: "{0.3, 0.3, 0.3}"
        Text: tMax / 2, "centre", fMax + 150, "half", "Full sequence: Pattern visible WITHIN high stream"
    else
        # Full: H1-L1-H2-L2-L3-H3
        t = 0
        @drawToneRect: t, t + toneDur * 0.8, h1 - toneHeight/2, h1 + toneHeight/2, streamHighColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, l1 - toneHeight/2, l1 + toneHeight/2, streamLowColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, h2 - toneHeight/2, h2 + toneHeight/2, streamHighColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, l2 - toneHeight/2, l2 + toneHeight/2, streamLowColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
        t += toneDur
        @drawToneRect: t, t + toneDur * 0.8, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        
        # Show pattern crosses streams (hard to detect)
        Colour: "{0.8, 0.5, 0.2}"
        Line width: 3
        Dashed line
        Draw line: toneDur * 0.4, h1, toneDur * 2.4, h2
        Draw line: toneDur * 2.4, h2, toneDur * 4.4, l3
        Solid line
        Line width: 1
        
        Font size: 9
        Colour: "{0.3, 0.3, 0.3}"
        Text: tMax / 2, "centre", fMax + 150, "half", "Full sequence: Pattern spans ACROSS streams (lost)"
    endif
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    # === Explanation ===
    Select outer viewport: 0, 8, 5.8, 6.8
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.3, 0.3, 0.4}"
    
    if .type$ = "Within"
        Text: 0.5, "centre", 0.6, "half", "When captor tones (low) are added, the target pattern remains"
        Text: 0.5, "centre", 0.25, "half", "within the high stream and is still easily detected."
    else
        Text: 0.5, "centre", 0.6, "half", "The target pattern H1→H2→L3 crosses the stream boundary."
        Text: 0.5, "centre", 0.25, "half", "Segregation breaks the pattern - it becomes very difficult to detect."
    endif
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# DEMO 3: Loss of Rhythm Visualization
# -------------------------
procedure visualizeDemo3: .separation$
    Erase all
    
    if .separation$ = "Large"
        @drawBregmanTitle: "Demo 3: Loss of Rhythm (Large Separation)", "Wide frequency gap causes stream segregation - rhythm lost"
        h3 = 1400
        l3 = 500
    else
        @drawBregmanTitle: "Demo 3: Loss of Rhythm (Small Separation)", "Narrow frequency gap - streams fuse - rhythm preserved"
        h3 = 1400
        l3 = 1320
    endif
    
    fMin = 300
    fMax = 1800
    toneHeight = 80
    unitDur = 0.2
    
    # === PANEL A: Physical Stimulus ===
    Select outer viewport: 0, 8, 1.0, 3.3
    Select inner viewport: 0.7, 7.7, 1.2, 3.1
    
    tMax = unitDur * 8
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Pattern: H-L-H-gap (repeated twice)
    for cycle from 0 to 1
        offset = cycle * unitDur * 4
        
        t = offset
        @drawToneRect: t, t + unitDur * 0.85, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        t += unitDur
        @drawToneRect: t, t + unitDur * 0.85, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
        t += unitDur
        @drawToneRect: t, t + unitDur * 0.85, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        # Gap at t + unitDur * 3
    endfor
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: tMax / 2, "centre", fMax + 80, "half", "Physical stimulus: H - L - H - (gap) - H - L - H - (gap)"
    
    # === PANEL B: Perceptual Organization ===
    Select outer viewport: 0, 8, 3.5, 5.8
    Select inner viewport: 0.7, 7.7, 3.7, 5.6
    
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    if .separation$ = "Large"
        # Two separate streams - rhythm lost
        # High stream
        for cycle from 0 to 1
            offset = cycle * unitDur * 4
            t = offset
            @drawToneRect: t, t + unitDur * 0.85, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
            t += unitDur * 2
            @drawToneRect: t, t + unitDur * 0.85, h3 - toneHeight/2, h3 + toneHeight/2, streamHighColor$
        endfor
        
        # Low stream
        for cycle from 0 to 1
            offset = cycle * unitDur * 4
            t = offset + unitDur
            @drawToneRect: t, t + unitDur * 0.85, l3 - toneHeight/2, l3 + toneHeight/2, streamLowColor$
        endfor
        
        # Stream contours
        Colour: streamHighColor$
        Line width: 2
        Draw line: unitDur * 0.4, h3, unitDur * 2.4, h3
        Draw line: unitDur * 4.4, h3, unitDur * 6.4, h3
        
        Colour: streamLowColor$
        Draw line: unitDur * 1.4, l3, unitDur * 5.4, l3
        Line width: 1
        
        Font size: 9
        Colour: "{0.7, 0.3, 0.3}"
        Text: tMax / 2, "centre", fMax + 80, "half", "SEGREGATED: Two streams - galloping rhythm LOST"
        
        # Rhythm indication
        Font size: 7
        Colour: streamHighColor$
        Text: unitDur * 0.4, "centre", h3 + 120, "half", "H...H"
        Text: unitDur * 4.4, "centre", h3 + 120, "half", "H...H"
        Colour: streamLowColor$
        Text: unitDur * 1.4, "centre", l3 - 100, "half", "L.......L"
        
    else
        # One fused stream - rhythm preserved
        for cycle from 0 to 1
            offset = cycle * unitDur * 4
            
            t = offset
            @drawToneRect: t, t + unitDur * 0.85, h3 - toneHeight/2, h3 + toneHeight/2, streamMelodyColor$
            t += unitDur
            @drawToneRect: t, t + unitDur * 0.85, l3 - toneHeight/2, l3 + toneHeight/2, streamMelodyColor$
            t += unitDur
            @drawToneRect: t, t + unitDur * 0.85, h3 - toneHeight/2, h3 + toneHeight/2, streamMelodyColor$
        endfor
        
        # Single stream contour
        Colour: streamMelodyColor$
        Line width: 2
        Draw line: unitDur * 0.4, h3, unitDur * 1.4, l3
        Draw line: unitDur * 1.4, l3, unitDur * 2.4, h3
        Draw line: unitDur * 4.4, h3, unitDur * 5.4, l3
        Draw line: unitDur * 5.4, l3, unitDur * 6.4, h3
        Line width: 1
        
        Font size: 9
        Colour: "{0.2, 0.6, 0.3}"
        Text: tMax / 2, "centre", fMax + 80, "half", "INTEGRATED: One stream - galloping rhythm PRESERVED"
        
        # Rhythm indication
        Font size: 8
        Colour: streamMelodyColor$
        Text: unitDur * 1.4, "centre", (h3 + l3) / 2, "half", "♩ ♪ ♩"
    endif
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    # === Explanation ===
    Select outer viewport: 0, 8, 6.0, 7.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.3, 0.3, 0.4}"
    
    if .separation$ = "Large"
        Text: 0.5, "centre", 0.65, "half", "Frequency separation: " + string$(h3) + " Hz vs " + string$(l3) + " Hz (large gap)"
        Text: 0.5, "centre", 0.35, "half", "The H-L-H-gap galloping pattern breaks into two isochronous streams."
    else
        Text: 0.5, "centre", 0.65, "half", "Frequency separation: " + string$(h3) + " Hz vs " + string$(l3) + " Hz (small gap)"
        Text: 0.5, "centre", 0.35, "half", "Close frequencies fuse into one stream - the gallop is clearly audible."
    endif
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# DEMO 4: Cumulative Effects Visualization
# -------------------------
procedure visualizeDemo4
    Erase all
    
    @drawBregmanTitle: "Demo 4: Cumulative Effects of Repetition", "Stream segregation builds up over time with repeated exposure"
    
    h4 = 2000
    l4 = 700
    
    fMin = 400
    fMax = 2500
    toneHeight = 120
    cycleDur = 0.35
    
    # === PANEL: Build-up over repetitions ===
    Select outer viewport: 0, 8, 1.0, 5.5
    Select inner viewport: 0.7, 7.7, 1.2, 5.3
    
    # Show 5 stages
    numStages = 5
    stageHeight = (5.3 - 1.2) / numStages
    
    for stage from 1 to numStages
        reps = 2 ^ stage
        
        yTop = 5.3 - (stage - 1) * stageHeight
        yBot = yTop - stageHeight * 0.8
        
        Select inner viewport: 0.7, 7.7, 7.0 - yTop, 7.0 - yBot
        
        tMax = cycleDur * min(reps, 8)
        Axes: 0, tMax, fMin, fMax
        
        # Background
        if stage <= 2
            Paint rectangle: "{0.95, 0.98, 0.95}", 0, tMax, fMin, fMax
        elsif stage = 3
            Paint rectangle: "{0.98, 0.98, 0.95}", 0, tMax, fMin, fMax
        else
            Paint rectangle: "{0.98, 0.95, 0.95}", 0, tMax, fMin, fMax
        endif
        
        # Draw cycles
        numDraw = min(reps, 8)
        for c from 1 to numDraw
            offset = (c - 1) * cycleDur
            
            # H-L-H pattern
            t = offset
            tDur = cycleDur / 3.5
            
            # Integration level based on stage
            if stage <= 2
                # Mostly integrated
                @drawToneRect: t, t + tDur * 0.8, h4 - toneHeight/2, h4 + toneHeight/2, "{0.6, 0.5, 0.6}"
                @drawToneRect: t + tDur, t + tDur * 1.8, l4 - toneHeight/2, l4 + toneHeight/2, "{0.6, 0.5, 0.6}"
                @drawToneRect: t + tDur * 2, t + tDur * 2.8, h4 - toneHeight/2, h4 + toneHeight/2, "{0.6, 0.5, 0.6}"
            else
                # Segregated
                @drawToneRect: t, t + tDur * 0.8, h4 - toneHeight/2, h4 + toneHeight/2, streamHighColor$
                @drawToneRect: t + tDur, t + tDur * 1.8, l4 - toneHeight/2, l4 + toneHeight/2, streamLowColor$
                @drawToneRect: t + tDur * 2, t + tDur * 2.8, h4 - toneHeight/2, h4 + toneHeight/2, streamHighColor$
            endif
        endfor
        
        # Label
        Font size: 7
        Colour: "Black"
        Text: -0.05, "right", (fMin + fMax) / 2, "half", string$(reps) + "×"
        
        if reps > 8
            Text: tMax * 0.95, "right", fMax - 100, "half", "..."
        endif
        
        Draw inner box
    endfor
    
    # Arrow showing build-up
    Select outer viewport: 0, 8, 1.0, 5.5
    Axes: 0, 1, 0, 1
    
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 2
    Arrow size: 1.5
    Draw arrow: 0.03, 0.85, 0.03, 0.15
    Line width: 1
    
    Font size: 8
    Text special: 0.02, "centre", 0.5, "half", "Helvetica", 8, "90", "Repetitions"
    
    # Segregation indicator
    Select outer viewport: 7.2, 8, 1.0, 5.5
    Axes: 0, 1, 0, 1
    
    # Gradient bar
    for g from 1 to 20
        gPos = (g - 1) / 20
        gY1 = 0.1 + gPos * 0.8
        gY2 = 0.1 + (g / 20) * 0.8
        
        gR = 0.5 + gPos * 0.3
        gG = 0.6 - gPos * 0.3
        gB = 0.5 - gPos * 0.2
        
        Paint rectangle: "{" + fixed$(gR, 2) + "," + fixed$(gG, 2) + "," + fixed$(gB, 2) + "}", 0.3, 0.7, gY1, gY2
    endfor
    
    Font size: 6
    Colour: "{0.3, 0.5, 0.3}"
    Text: 0.5, "centre", 0.05, "half", "Fused"
    Colour: "{0.7, 0.3, 0.3}"
    Text: 0.5, "centre", 0.95, "half", "Split"
    
    # === Explanation ===
    Select outer viewport: 0, 8, 5.7, 6.8
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.3, 0.3, 0.4}"
    Text: 0.5, "centre", 0.7, "half", "After 2-4 cycles: Tones heard as integrated (one stream)"
    Text: 0.5, "centre", 0.4, "half", "After 8-16 cycles: Segregation emerges (two streams)"
    Text: 0.5, "centre", 0.1, "half", "After 32 cycles: Strong segregation - difficult to hear as one"
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# DEMO 5: Melody Segregation Visualization
# -------------------------
procedure visualizeDemo5
    Erase all
    
    @drawBregmanTitle: "Demo 5: Segregation of Melody from Interference", "Target melody emerges when separated in frequency from distractors"
    
    baseC4 = 261.63
    
    fMin = 200
    fMax = 900
    toneHeight = 40
    toneDur = 0.12
    
    # Melody: E-D-C-D-E-E-E (simple tune)
    # Positions: 4-2-0-2-4-4-4 semitones
    
    # === PANEL A: Mixed (same register) ===
    Select outer viewport: 0, 8, 1.0, 2.8
    Select inner viewport: 0.7, 7.7, 1.2, 2.6
    
    tMax = toneDur * 14
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Draw melody and distractors interleaved
    melodyNotes[1] = 4
    melodyNotes[2] = 2
    melodyNotes[3] = 0
    melodyNotes[4] = 2
    melodyNotes[5] = 4
    melodyNotes[6] = 4
    melodyNotes[7] = 4
    
    for n from 1 to 7
        mHz = baseC4 * (2 ^ (melodyNotes[n] / 12))
        dHz = baseC4 * (2 ^ (randomInteger(0, 4) / 12))
        
        t = (n - 1) * toneDur * 2
        
        # Melody tone
        @drawToneRect: t, t + toneDur * 0.85, mHz - toneHeight/2, mHz + toneHeight/2, "{0.5, 0.5, 0.5}"
        # Distractor
        @drawToneRect: t + toneDur, t + toneDur * 1.85, dHz - toneHeight/2, dHz + toneHeight/2, "{0.5, 0.5, 0.5}"
    endfor
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.5, 0.3, 0.3}"
    Text: tMax / 2, "centre", fMax + 50, "half", "Same register: Melody hidden in noise"
    
    # === PANEL B: Separated (melody higher) ===
    Select outer viewport: 0, 8, 3.0, 4.8
    Select inner viewport: 0.7, 7.7, 3.2, 4.6
    
    fMax = 1200
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    transpose = 7
    
    for n from 1 to 7
        mHz = baseC4 * (2 ^ ((melodyNotes[n] + transpose) / 12))
        dHz = baseC4 * (2 ^ (randomInteger(0, 4) / 12))
        
        t = (n - 1) * toneDur * 2
        
        # Melody tone (higher, colored)
        @drawToneRect: t, t + toneDur * 0.85, mHz - toneHeight/2, mHz + toneHeight/2, streamMelodyColor$
        # Distractor (lower, gray)
        @drawToneRect: t + toneDur, t + toneDur * 1.85, dHz - toneHeight/2, dHz + toneHeight/2, streamDistractorColor$
    endfor
    
    # Connect melody notes
    Colour: streamMelodyColor$
    Line width: 2
    for n from 1 to 6
        mHz1 = baseC4 * (2 ^ ((melodyNotes[n] + transpose) / 12))
        mHz2 = baseC4 * (2 ^ ((melodyNotes[n+1] + transpose) / 12))
        t1 = (n - 1) * toneDur * 2 + toneDur * 0.4
        t2 = n * toneDur * 2 + toneDur * 0.4
        Draw line: t1, mHz1, t2, mHz2
    endfor
    Line width: 1
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.2, 0.6, 0.3}"
    Text: tMax / 2, "centre", fMax + 50, "half", "Transposed +5th: Melody emerges clearly"
    
    # === PANEL C: Further separated ===
    Select outer viewport: 0, 8, 5.0, 6.8
    Select inner viewport: 0.7, 7.7, 5.2, 6.6
    
    fMax = 1400
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    transpose = 12
    
    for n from 1 to 7
        mHz = baseC4 * (2 ^ ((melodyNotes[n] + transpose) / 12))
        dHz = baseC4 * (2 ^ (randomInteger(0, 4) / 12))
        
        t = (n - 1) * toneDur * 2
        
        # Melody tone
        @drawToneRect: t, t + toneDur * 0.85, mHz - toneHeight/2, mHz + toneHeight/2, streamMelodyColor$
        # Distractor
        @drawToneRect: t + toneDur, t + toneDur * 1.85, dHz - toneHeight/2, dHz + toneHeight/2, streamDistractorColor$
    endfor
    
    # Connect melody
    Colour: streamMelodyColor$
    Line width: 2
    for n from 1 to 6
        mHz1 = baseC4 * (2 ^ ((melodyNotes[n] + transpose) / 12))
        mHz2 = baseC4 * (2 ^ ((melodyNotes[n+1] + transpose) / 12))
        t1 = (n - 1) * toneDur * 2 + toneDur * 0.4
        t2 = n * toneDur * 2 + toneDur * 0.4
        Draw line: t1, mHz1, t2, mHz2
    endfor
    Line width: 1
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.2, 0.6, 0.3}"
    Text: tMax / 2, "centre", fMax + 50, "half", "Transposed +octave: Complete segregation"
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# DEMO 6: Telemann Compound Melody Visualization
# -------------------------
procedure visualizeDemo6
    Erase all
    
    @drawBregmanTitle: "Demo 6: Telemann Sonata (Compound Melody)", "Single melodic line creates illusion of two voices through pitch proximity"
    
    toneG5 = 783.99
    toneE5 = 659.25
    toneD5 = 587.33
    toneC5 = 523.25
    toneB4 = 493.88
    toneA4 = 440.00
    toneG4 = 392.00
    
    fMin = 350
    fMax = 900
    toneHeight = 30
    
    # === PANEL A: Slow - heard as one melody ===
    Select outer viewport: 0, 8, 1.0, 3.0
    Select inner viewport: 0.7, 7.7, 1.2, 2.8
    
    slowDur = 0.25
    tMax = slowDur * 8
    
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Pattern: G5-E5-G5-C5-G5-D5-G5-B4
    notes[1] = toneG5
    notes[2] = toneE5
    notes[3] = toneG5
    notes[4] = toneC5
    notes[5] = toneG5
    notes[6] = toneD5
    notes[7] = toneG5
    notes[8] = toneB4
    
    # Draw as one integrated melody
    for n from 1 to 8
        t = (n - 1) * slowDur
        @drawToneRect: t, t + slowDur * 0.85, notes[n] - toneHeight/2, notes[n] + toneHeight/2, "{0.5, 0.5, 0.6}"
    endfor
    
    # Single melodic contour
    Colour: "{0.4, 0.4, 0.5}"
    Line width: 2
    for n from 1 to 7
        t1 = (n - 1) * slowDur + slowDur * 0.4
        t2 = n * slowDur + slowDur * 0.4
        Draw line: t1, notes[n], t2, notes[n+1]
    endfor
    Line width: 1
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: tMax / 2, "centre", fMax + 40, "half", "SLOW tempo: Heard as single arpeggiated melody"
    
    # === PANEL B: Fast - heard as two voices ===
    Select outer viewport: 0, 8, 3.2, 5.2
    Select inner viewport: 0.7, 7.7, 3.4, 5.0
    
    fastDur = 0.1
    tMax = fastDur * 16
    
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Draw 16 notes (two measures)
    fullPattern[1] = toneG5
    fullPattern[2] = toneE5
    fullPattern[3] = toneG5
    fullPattern[4] = toneC5
    fullPattern[5] = toneG5
    fullPattern[6] = toneD5
    fullPattern[7] = toneG5
    fullPattern[8] = toneB4
    fullPattern[9] = toneG5
    fullPattern[10] = toneC5
    fullPattern[11] = toneG5
    fullPattern[12] = toneA4
    fullPattern[13] = toneG5
    fullPattern[14] = toneB4
    fullPattern[15] = toneG5
    fullPattern[16] = toneG4
    
    # Identify upper voice (G5) and lower voice (others)
    for n from 1 to 16
        t = (n - 1) * fastDur
        if fullPattern[n] = toneG5
            @drawToneRect: t, t + fastDur * 0.85, fullPattern[n] - toneHeight/2, fullPattern[n] + toneHeight/2, streamHighColor$
        else
            @drawToneRect: t, t + fastDur * 0.85, fullPattern[n] - toneHeight/2, fullPattern[n] + toneHeight/2, streamLowColor$
        endif
    endfor
    
    # Upper voice contour (pedal G5)
    Colour: streamHighColor$
    Line width: 2
    prevT = -1
    for n from 1 to 16
        if fullPattern[n] = toneG5
            t = (n - 1) * fastDur + fastDur * 0.4
            if prevT >= 0
                Draw line: prevT, toneG5, t, toneG5
            endif
            prevT = t
        endif
    endfor
    
    # Lower voice contour (descending melody)
    Colour: streamLowColor$
    prevT = -1
    prevF = 0
    for n from 1 to 16
        if fullPattern[n] <> toneG5
            t = (n - 1) * fastDur + fastDur * 0.4
            if prevT >= 0
                Draw line: prevT, prevF, t, fullPattern[n]
            endif
            prevT = t
            prevF = fullPattern[n]
        endif
    endfor
    Line width: 1
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: tMax / 2, "centre", fMax + 40, "half", "FAST tempo: Two implied voices emerge"
    
    # === Voice labels ===
    Select outer viewport: 0, 8, 5.4, 6.2
    Axes: 0, 1, 0, 1
    
    Font size: 8
    
    Paint rectangle: streamHighColor$, 0.2, 0.24, 0.5, 0.8
    Colour: "Black"
    Text: 0.26, "left", 0.65, "half", "Upper voice: Sustained G pedal"
    
    Paint rectangle: streamLowColor$, 0.55, 0.59, 0.5, 0.8
    Colour: "Black"
    Text: 0.61, "left", 0.65, "half", "Lower voice: Descending melody"
    
    Colour: "{0.3, 0.3, 0.4}"
    Font size: 7
    Text: 0.5, "centre", 0.15, "half", "This 'pseudo-polyphony' is common in Bach, Telemann, and other Baroque composers"
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# DEMO 7/8: African Xylophone Visualization
# -------------------------
procedure visualizeDemo7_8: .octaveShift
    Erase all
    
    if .octaveShift = 0
        @drawBregmanTitle: "Demo 7: African Xylophone (Interlocking)", "Two players create emergent melody through rhythmic interlocking"
    else
        @drawBregmanTitle: "Demo 8: African Xylophone (Pitch Separation)", "Octave shift reveals the hidden composite melody"
    endif
    
    baseHz = 350
    xyloDur = 0.12
    
    # Equipentatonic scale
    f1 = baseHz
    f2 = baseHz * (2 ^ (240/1200))
    f3 = baseHz * (2 ^ (480/1200))
    f4 = baseHz * (2 ^ (720/1200))
    f5 = baseHz * (2 ^ (960/1200))
    
    if .octaveShift = 1
        f4 = f4 * 2
        f5 = f5 * 2
    endif
    
    fMin = 250
    if .octaveShift = 1
        fMax = 1200
    else
        fMax = 700
    endif
    toneHeight = 40
    
    # === PANEL A: Part A alone ===
    Select outer viewport: 0, 4, 1.0, 2.8
    Select inner viewport: 0.5, 3.8, 1.2, 2.6
    
    tMax = xyloDur * 8
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.98, 0.96, 0.94}", 0, tMax, fMin, fMax
    
    # Part A: f1-gap-f3-gap (×2)
    for cycle from 0 to 1
        offset = cycle * xyloDur * 4
        t = offset
        @drawToneRect: t, t + xyloDur * 0.7, f1 - toneHeight/2, f1 + toneHeight/2, streamAColor$
        t += xyloDur * 2
        @drawToneRect: t, t + xyloDur * 0.7, f3 - toneHeight/2, f3 + toneHeight/2, streamAColor$
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Part A (Player 1)"
    
    # === PANEL B: Part B alone ===
    Select outer viewport: 4, 8, 1.0, 2.8
    Select inner viewport: 4.4, 7.8, 1.2, 2.6
    
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.94, 0.96, 0.98}", 0, tMax, fMin, fMax
    
    # Part B: gap-f4-gap-f5 (×2)
    for cycle from 0 to 1
        offset = cycle * xyloDur * 4
        t = offset + xyloDur
        @drawToneRect: t, t + xyloDur * 0.7, f4 - toneHeight/2, f4 + toneHeight/2, streamBColor$
        t += xyloDur * 2
        @drawToneRect: t, t + xyloDur * 0.7, f5 - toneHeight/2, f5 + toneHeight/2, streamBColor$
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Part B (Player 2)"
    
    # === PANEL C: Combined ===
    Select outer viewport: 0, 8, 3.0, 5.2
    Select inner viewport: 0.7, 7.7, 3.2, 5.0
    
    tMax = xyloDur * 16
    Axes: 0, tMax, fMin, fMax
    Paint rectangle: "{0.97, 0.97, 0.98}", 0, tMax, fMin, fMax
    
    # Draw combined pattern
    for cycle from 0 to 3
        offset = cycle * xyloDur * 4
        
        # A: f1
        t = offset
        @drawToneRect: t, t + xyloDur * 0.7, f1 - toneHeight/2, f1 + toneHeight/2, streamAColor$
        
        # B: f4
        t = offset + xyloDur
        @drawToneRect: t, t + xyloDur * 0.7, f4 - toneHeight/2, f4 + toneHeight/2, streamBColor$
        
        # A: f3
        t = offset + xyloDur * 2
        @drawToneRect: t, t + xyloDur * 0.7, f3 - toneHeight/2, f3 + toneHeight/2, streamAColor$
        
        # B: f5
        t = offset + xyloDur * 3
        @drawToneRect: t, t + xyloDur * 0.7, f5 - toneHeight/2, f5 + toneHeight/2, streamBColor$
    endfor
    
    # Draw emergent melody contour
    if .octaveShift = 0
        # When close in pitch, emergent melody heard
        Colour: "{0.4, 0.7, 0.4}"
        Line width: 2
        for cycle from 0 to 2
            offset = cycle * xyloDur * 4
            Draw line: offset + xyloDur * 0.35, f1, offset + xyloDur * 1.35, f4
            Draw line: offset + xyloDur * 1.35, f4, offset + xyloDur * 2.35, f3
            Draw line: offset + xyloDur * 2.35, f3, offset + xyloDur * 3.35, f5
            if cycle < 2
                Draw line: offset + xyloDur * 3.35, f5, offset + xyloDur * 4.35, f1
            endif
        endfor
        Line width: 1
    else
        # Octave shift - parts segregate
        Colour: streamAColor$
        Line width: 2
        for cycle from 0 to 2
            offset = cycle * xyloDur * 4
            Draw line: offset + xyloDur * 0.35, f1, offset + xyloDur * 2.35, f3
            if cycle < 2
                Draw line: offset + xyloDur * 2.35, f3, offset + xyloDur * 4.35, f1
            endif
        endfor
        
        Colour: streamBColor$
        for cycle from 0 to 2
            offset = cycle * xyloDur * 4
            Draw line: offset + xyloDur * 1.35, f4, offset + xyloDur * 3.35, f5
            if cycle < 2
                Draw line: offset + xyloDur * 3.35, f5, offset + xyloDur * 5.35, f4
            endif
        endfor
        Line width: 1
    endif
    
    @drawFreqTimeAxes: tMax, fMin, fMax, 0
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    if .octaveShift = 0
        Text: tMax / 2, "centre", fMax + 40, "half", "Combined: Emergent melody f1→f4→f3→f5 (ascending pattern)"
    else
        Text: tMax / 2, "centre", fMax + 60, "half", "Octave shift: Parts segregate - two separate streams heard"
    endif
    
    # === Legend & Explanation ===
    Select outer viewport: 0, 8, 5.4, 6.8
    Axes: 0, 1, 0, 1
    
    Font size: 8
    
    Paint rectangle: streamAColor$, 0.1, 0.14, 0.65, 0.85
    Colour: "Black"
    Text: 0.16, "left", 0.75, "half", "Part A (f1, f3)"
    
    Paint rectangle: streamBColor$, 0.35, 0.39, 0.65, 0.85
    Colour: "Black"
    Text: 0.41, "left", 0.75, "half", "Part B (f4, f5)"
    
    if .octaveShift = 0
        Paint rectangle: "{0.4, 0.7, 0.4}", 0.65, 0.69, 0.65, 0.85
        Colour: "Black"
        Text: 0.71, "left", 0.75, "half", "Emergent melody"
    endif
    
    Colour: "{0.3, 0.3, 0.4}"
    Font size: 7
    if .octaveShift = 0
        Text: 0.5, "centre", 0.35, "half", "Amadinda xylophone tradition from Uganda - neither player plays the 'melody'"
        Text: 0.5, "centre", 0.1, "half", "but it emerges from their interlocking patterns (inherent patterns)"
    else
        Text: 0.5, "centre", 0.35, "half", "When Part B is shifted up one octave, stream segregation occurs"
        Text: 0.5, "centre", 0.1, "half", "The emergent melody disappears - you hear two separate rhythmic patterns"
    endif
    
    Font size: 10
    Colour: "Black"
endproc

# -------------------------
# Add spectrogram panel
# -------------------------
procedure addSpectrogram: .soundID, .yTop, .yBot
    if show_spectrogram
        Select outer viewport: 0, 8, .yTop, .yBot
        Select inner viewport: 0.7, 7.7, .yTop + 0.1, .yBot - 0.1
        
        selectObject: .soundID
        To Spectrogram: 0.03, 5000, 0.002, 20, "Gaussian"
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Freq"
        
        removeObject: selected("Spectrogram")
    endif
endproc

# -------------------------
# 1. CORE PROCEDURES (same as before)
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
# 2. EXPERIMENT-SPECIFIC PROCEDURES (same as before)
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
writeInfoLine: "=== Auditory Scene Analysis Demos v2.0 ==="
appendInfoLine: ""

if experiment_Type = 1
    appendInfoLine: "Demo 1: Stream Segregation"
    if show_visualization
        @visualizeDemo1
    endif
    
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
        if show_visualization
            @visualizeDemo2: "Within"
        endif
        @MakeD2Cycle: "Within_Standard"
        Rename: "std"
        @RepeatSound: "std", 15, "PartA"
        @MakeD2Cycle: "Normal"
        Rename: "full"
        @RepeatSound: "full", 15, "PartB"
        finalName$ = "Demo_2_Within"
    else
        appendInfoLine: "Demo 2: Pattern Recognition (Across-Stream)"
        if show_visualization
            @visualizeDemo2: "Across"
        endif
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
        if show_visualization
            @visualizeDemo3: "Large"
        endif
        h3 = 1400
        l3 = 500
    else
        appendInfoLine: "Demo 3: Loss of Rhythm (Small Separation)"
        if show_visualization
            @visualizeDemo3: "Small"
        endif
        h3 = 1400
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
    Rename: "Demo_3_LossOfRhythm"
    finalName$ = "Demo_3_LossOfRhythm"
endif

if experiment_Type = 6
    appendInfoLine: "Demo 4: Cumulative Effects"
    if show_visualization
        @visualizeDemo4
    endif
    
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
    appendInfoLine: "Demo 5: Melody Segregation"
    if show_visualization
        @visualizeDemo5
    endif
    
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
    appendInfoLine: "Demo 6: Telemann Compound Melody"
    if show_visualization
        @visualizeDemo6
    endif
    
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
    baseHz = 350
    xyloDur = 0.120
    
    f1 = baseHz
    f2 = baseHz * (2 ^ (240/1200))
    f3 = baseHz * (2 ^ (480/1200))
    f4 = baseHz * (2 ^ (720/1200))
    f5 = baseHz * (2 ^ (960/1200))
    f6 = baseHz * (2 ^ (1200/1200))
    
    if experiment_Type = 9
        appendInfoLine: "Demo 7: African Xylophone (Interlocking)"
        if show_visualization
            @visualizeDemo7_8: 0
        endif
    else
        appendInfoLine: "Demo 8: African Xylophone (Pitch Separation)"
        if show_visualization
            @visualizeDemo7_8: 1
        endif
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
    
    selectObject: "Sound PartA_Solo", "Sound Gap1", "Sound PartB_Solo", "Sound Gap2", "Sound Duet"
    Remove
endif

# -------------------------
# FINAL OUTPUT
# -------------------------
selectObject: "Sound " + finalName$
Scale peak: 0.99

appendInfoLine: ""
appendInfoLine: "Output: ", finalName$
appendInfoLine: ""

if play_result
    Play
endif

appendInfoLine: "Done!"