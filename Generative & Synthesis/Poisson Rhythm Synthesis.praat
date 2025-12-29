# ============================================================
# Praat AudioTools - Poisson Rhythm Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound synthesis or generative algorithm script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================


form Poisson Rhythm Synthesis
    optionmenu Preset: 1
        option Custom
        option Gentle Pulse
        option Nervous Ticks
        option Techno Beat
        option Ambient Drift
        option Glitchy Percussion
        option Heartbeat
        option Rain Drops
        option Industrial Noise
    optionmenu Cannon_mode: 1
        option No Cannon
        option Cannon 2 voices
        option Cannon 3 voices
        option Cannon 4 voices
    real Cannon_delay 1.0
    real Duration 6.0
    real Sampling_frequency 44100
    real Beat_rate 2.0
    real Subdivision_rate 8.0
    real Base_frequency 150
    real Percussive_decay 0.1
endform

echo Building Poisson Rhythm...

# Apply presets
if preset > 1
    if preset = 2
        # Gentle Pulse
        beat_rate = 1.5
        subdivision_rate = 4.0
        base_frequency = 120
        percussive_decay = 0.2
        
    elsif preset = 3
        # Nervous Ticks
        beat_rate = 4.0
        subdivision_rate = 15.0
        base_frequency = 200
        percussive_decay = 0.05
        
    elsif preset = 4
        # Techno Beat
        beat_rate = 2.5
        subdivision_rate = 12.0
        base_frequency = 80
        percussive_decay = 0.08
        
    elsif preset = 5
        # Ambient Drift
        beat_rate = 0.8
        subdivision_rate = 3.0
        base_frequency = 100
        percussive_decay = 0.3
        
    elsif preset = 6
        # Glitchy Percussion
        beat_rate = 3.0
        subdivision_rate = 20.0
        base_frequency = 180
        percussive_decay = 0.04
        
    elsif preset = 7
        # Heartbeat
        beat_rate = 1.2
        subdivision_rate = 6.0
        base_frequency = 60
        percussive_decay = 0.15
        
    elsif preset = 8
        # Rain Drops
        beat_rate = 0.5
        subdivision_rate = 10.0
        base_frequency = 250
        percussive_decay = 0.25
        
    elsif preset = 9
        # Industrial Noise
        beat_rate = 5.0
        subdivision_rate = 25.0
        base_frequency = 140
        percussive_decay = 0.06
    endif
endif

echo Using preset: 'preset'

Create Poisson process: "main_beats", 0, duration, beat_rate
Create Poisson process: "subdivisions", 0, duration, subdivision_rate

selectObject: "PointProcess main_beats"
numberBeats = Get number of points
selectObject: "PointProcess subdivisions"  
numberSubs = Get number of points

formula$ = "0"

# Add main beats
selectObject: "PointProcess main_beats"
for beat to numberBeats
    beatTime = Get time from index: beat
    
    # Inline drum event (no procedure)
    event_dur = 0.15
    if beatTime + event_dur > duration
        event_dur = duration - beatTime
    endif
    
    if event_dur > 0.005
        event_formula$ = "if x >= " + string$(beatTime) + " and x < " + string$(beatTime + event_dur)
        event_formula$ = event_formula$ + " then 0.8"
        event_formula$ = event_formula$ + " * sin(2*pi*" + string$(base_frequency) + "*x)"
        event_formula$ = event_formula$ + " * exp(-" + string$(1/percussive_decay) + "*(x-" + string$(beatTime) + ")/" + string$(event_dur) + ")"
        event_formula$ = event_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = event_formula$
        else
            formula$ = formula$ + " + " + event_formula$
        endif
    endif
endfor

# Add subdivisions
selectObject: "PointProcess subdivisions"
for sub to numberSubs
    subTime = Get time from index: sub
    
    # Inline drum event (no procedure)
    event_dur = 0.08
    if subTime + event_dur > duration
        event_dur = duration - subTime
    endif
    
    if event_dur > 0.005
        event_formula$ = "if x >= " + string$(subTime) + " and x < " + string$(subTime + event_dur)
        event_formula$ = event_formula$ + " then 0.5"
        event_formula$ = event_formula$ + " * sin(2*pi*" + string$(base_frequency * 1.5) + "*x)"
        event_formula$ = event_formula$ + " * exp(-" + string$(1/percussive_decay) + "*(x-" + string$(subTime) + ")/" + string$(event_dur) + ")"
        event_formula$ = event_formula$ + " else 0 fi"
        
        if formula$ = "0"
            formula$ = event_formula$
        else
            formula$ = formula$ + " + " + event_formula$
        endif
    endif
endfor

Create Sound from formula: "poisson_rhythm", 1, 0, duration, sampling_frequency, formula$
Scale peak: 0.9

# Apply cannon effect if selected
if cannon_mode > 1
    cannon_voices = cannon_mode
    total_duration = duration + (cannon_voices - 1) * cannon_delay
    
    # Build left and right channel formulas separately
    left_formula$ = "0"
    right_formula$ = "0"
    
    for voice to cannon_voices
        voice_delay = (voice - 1) * cannon_delay
        
        # Strong panning - voices alternate between hard left and right
        if voice mod 2 = 1
            # Odd voices: hard left with lower frequency
            voice_freq = base_frequency * 0.8
            pan_left = 1.0
            pan_right = 0.0
        else
            # Even voices: hard right with higher frequency  
            voice_freq = base_frequency * 1.2
            pan_left = 0.0
            pan_right = 1.0
        endif
        
        # Build voice formula
        voice_formula$ = "if x >= " + string$(voice_delay) + " and x < " + string$(voice_delay + duration)
        voice_formula$ = voice_formula$ + " then ("
        
        # Add main beats for this voice
        beat_formulas$ = ""
        selectObject: "PointProcess main_beats"
        for beat to numberBeats
            beatTime = Get time from index: beat
            shifted_beatTime = beatTime + voice_delay
            
            if shifted_beatTime < total_duration
                event_dur = 0.15
                if shifted_beatTime + event_dur > total_duration
                    event_dur = total_duration - shifted_beatTime
                endif
                
                if event_dur > 0.005
                    beat_formula$ = "if x >= " + string$(shifted_beatTime) + " and x < " + string$(shifted_beatTime + event_dur)
                    beat_formula$ = beat_formula$ + " then 0.8"
                    beat_formula$ = beat_formula$ + " * sin(2*pi*" + string$(voice_freq) + "*(x-" + string$(voice_delay) + "))"
                    beat_formula$ = beat_formula$ + " * exp(-" + string$(1/percussive_decay) + "*(x-" + string$(shifted_beatTime) + ")/" + string$(event_dur) + ")"
                    beat_formula$ = beat_formula$ + " else 0 fi"
                    
                    if beat_formulas$ = ""
                        beat_formulas$ = beat_formula$
                    else
                        beat_formulas$ = beat_formulas$ + " + " + beat_formula$
                    endif
                endif
            endif
        endfor
        
        # Add subdivisions for this voice
        sub_formulas$ = ""
        selectObject: "PointProcess subdivisions"
        for sub to numberSubs
            subTime = Get time from index: sub
            shifted_subTime = subTime + voice_delay
            
            if shifted_subTime < total_duration
                event_dur = 0.08
                if shifted_subTime + event_dur > total_duration
                    event_dur = total_duration - shifted_subTime
                endif
                
                if event_dur > 0.005
                    sub_formula$ = "if x >= " + string$(shifted_subTime) + " and x < " + string$(shifted_subTime + event_dur)
                    sub_formula$ = sub_formula$ + " then 0.5"
                    sub_formula$ = sub_formula$ + " * sin(2*pi*" + string$(voice_freq * 1.5) + "*(x-" + string$(voice_delay) + "))"
                    sub_formula$ = sub_formula$ + " * exp(-" + string$(1/percussive_decay) + "*(x-" + string$(shifted_subTime) + ")/" + string$(event_dur) + ")"
                    sub_formula$ = sub_formula$ + " else 0 fi"
                    
                    if sub_formulas$ = ""
                        sub_formulas$ = sub_formula$
                    else
                        sub_formulas$ = sub_formulas$ + " + " + sub_formula$
                    endif
                endif
            endif
        endfor
        
        # Combine beats and subs for this voice
        if beat_formulas$ != "" and sub_formulas$ != ""
            voice_formula$ = voice_formula$ + beat_formulas$ + " + " + sub_formulas$
        elsif beat_formulas$ != ""
            voice_formula$ = voice_formula$ + beat_formulas$
        elsif sub_formulas$ != ""
            voice_formula$ = voice_formula$ + sub_formulas$
        else
            voice_formula$ = voice_formula$ + "0"
        endif
        
        voice_formula$ = voice_formula$ + ") else 0 fi"
        
        # Add to left and right channels
        if left_formula$ = "0"
            left_formula$ = "(" + voice_formula$ + ") * " + string$(pan_left)
        else
            left_formula$ = left_formula$ + " + (" + voice_formula$ + ") * " + string$(pan_left)
        endif
        
        if right_formula$ = "0"
            right_formula$ = "(" + voice_formula$ + ") * " + string$(pan_right)
        else
            right_formula$ = right_formula$ + " + (" + voice_formula$ + ") * " + string$(pan_right)
        endif
    endfor
    
    # Create separate left and right sounds
    Create Sound from formula: "cannon_left", 1, 0, total_duration, sampling_frequency, left_formula$
    Create Sound from formula: "cannon_right", 1, 0, total_duration, sampling_frequency, right_formula$
    
    # Combine to stereo
    selectObject: "Sound cannon_left"
    plusObject: "Sound cannon_right"
    Combine to stereo
    Rename: "poisson_rhythm_cannon"
    Scale peak: 0.9
    output_sound = selected("Sound")
    
    # Clean up
    selectObject: "Sound cannon_left"
    plusObject: "Sound cannon_right"
    Remove
    
    # Remove original mono
    selectObject: "Sound poisson_rhythm"
    Remove
    
else
    # No cannon - just use original mono
    selectObject: "Sound poisson_rhythm"
    output_sound = selected("Sound")
endif

selectObject: output_sound
Play

selectObject: "PointProcess main_beats"
plusObject: "PointProcess subdivisions"
Remove

echo Poisson Rhythm complete!
echo Preset: 'preset'
echo Cannon: 'cannon_mode' voices with 'cannon_delay:2' s delay
echo Main beats: 'numberBeats', Subdivisions: 'numberSubs'
echo Beat rate: 'beat_rate:1' Hz, Subdivision rate: 'subdivision_rate:1' Hz