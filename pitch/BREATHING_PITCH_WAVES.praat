# ====== BREATHING PITCH WAVES ======
# Simulates intense emotional breathing with dramatic pitch swells
breath_rate = 0.3
pitch_depth = 18
micro_flutter = 4
emotional_intensity = 2.5
timestep = 0.005
floor = 50
ceil = 900

orig_sr = Get sampling frequency
Copy... breath_tmp
To Manipulation: timestep, floor, ceil
Extract pitch tier
Rename... breath_pitch

select PitchTier breath_pitch
Remove points between... 0 0
xmin = Get start time
xmax = Get end time
dur = xmax - xmin

npoints = 350
for i from 0 to npoints-1
    t = xmin + (i / (npoints-1)) * dur
    phase = (t - xmin) / dur * 2 * pi * breath_rate
    
    # Deep emotional breathing with multiple harmonics
    breath_fundamental = sin(phase)^3
    breath_harmonic = 0.6 * sin(phase * 2)^5
    breath_subharmonic = 0.3 * sin(phase * 0.5)^2
    breath_curve = breath_fundamental + breath_harmonic + breath_subharmonic
    
    # Intense micro-fluctuations with chaos
    flutter_phase = phase * 12
    chaos_phase = phase * 23.7
    flutter_component1 = sin(flutter_phase) * randomUniform(0.6, 1.4)
    flutter_component2 = 0.5 * sin(chaos_phase) * randomUniform(0.8, 1.2)
    flutter = micro_flutter * 0.15 * (flutter_component1 + flutter_component2)
    
    # Emotional tremor and gasping effects
    tremor = 0.8 * sin(phase * 7.3) * cos(phase * 2.1)
    gasp_trigger = sin(phase * 3)^8
    gasp = 3 * gasp_trigger * randomUniform(0.5, 1.5)
    
    # Build intensity over time
    time_factor = (t - xmin) / dur
    intensity_envelope = 1 + emotional_intensity * time_factor^1.5
    
    total_shift = pitch_depth * (breath_curve + flutter + tremor + gasp) * intensity_envelope
    ratio = exp((ln(2)/12) * total_shift)
    
    Add point... t ratio
endfor

select Manipulation breath_tmp
plus PitchTier breath_pitch
Replace pitch tier
select Manipulation breath_tmp
Get resynthesis (overlap-add)
Rename... breath_result
Resample... 44100 50
Play

# Clean up
select Manipulation breath_tmp
plus PitchTier breath_pitch
Remove