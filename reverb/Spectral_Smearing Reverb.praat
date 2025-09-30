# VARIATION 3: Spectral Smearing Reverb
# Frequency-dependent delays that blur spectral content

Copy... "reverb_copy"

freq_bands = 20
time_stretch = 0.6
spectral_chaos = 0.12

for band from 1 to freq_bands
    center_freq = 80 * (2 ^ (band/2.5))
    delay_time = time_stretch * (1/sqrt (center_freq/80))
    
    # Frequency-selective amplitude
    freq_response = exp (-((center_freq - 600)/800)^2)
    amplitude = 0.35 * freq_response * randomUniform (0.7, 1.3)
    
    # Spectral modulation
    mod_freq = center_freq / 15
    Formula... self + amplitude * self (x - delay_time) * (0.3 + 0.7*cos (2*pi*x*mod_freq))
endfor
Play