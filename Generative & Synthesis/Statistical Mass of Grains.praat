# ============================================================
# Praat AudioTools - Statistical Mass of Grains.praat
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

form Statistical Mass of Grains
    real Duration 5.0
    real Sampling_frequency 44100
    real Grain_density 40.0
    real Base_frequency 150
    real Frequency_spread 400
    choice Distribution_type: 1
    button Gaussian_Cloud
    button Uniform_Field
    button Exponential_Cluster
    button Bimodal_Distribution
    real Density_variation 0.3
    boolean Enable_spatial_distribution yes
endform

echo Creating Statistical Mass of Grains...

total_grains = round(duration * grain_density)
formula$ = "0"

if distribution_type = 1
    echo Using Gaussian Cloud Distribution
    call GaussianCloud
elsif distribution_type = 2
    echo Using Uniform Field Distribution
    call UniformField
elsif distribution_type = 3
    echo Using Exponential Cluster Distribution
    call ExponentialCluster
else
    echo Using Bimodal Distribution
    call BimodalDistribution
endif

Create Sound from formula... grain_mass 1 0 duration sampling_frequency 'formula$'
Scale peak... 0.9

echo Statistical Mass of Grains complete!

procedure GaussianCloud
    for grain to total_grains
        if density_variation > 0
            local_density = grain_density * (1 + density_variation * (randomGauss(0,1)))
            time_spacing = 1 / local_density
        else
            time_spacing = 1 / grain_density
        endif
        
        grain_time = (grain-1) * time_spacing + randomGauss(0, time_spacing/3)
        grain_time = max(0, min(duration-0.1, grain_time))
        
        grain_freq = base_frequency + frequency_spread * randomGauss(0,1)
        grain_freq = max(50, min(5000, grain_freq))
        
        grain_dur = 0.05 + 0.1 * abs(randomGauss(0,1))
        grain_amp = 0.6 * (0.7 + 0.3 * randomGauss(0,1))
        
        if enable_spatial_distribution = 1
            pan = randomGauss(0,0.5)
            grain_amp_left = grain_amp * (0.5 + 0.5 * pan)
            grain_amp_right = grain_amp * (0.5 - 0.5 * pan)
        else
            grain_amp_left = grain_amp
            grain_amp_right = grain_amp
        endif
        
        if grain_time + grain_dur > duration
            grain_dur = duration - grain_time
        endif
        
        if grain_dur > 0.001
            grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
            grain_formula$ = grain_formula$ + " then " + string$(grain_amp_left)
            grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
            grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + "))/2"
            grain_formula$ = grain_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = grain_formula$
            else
                formula$ = formula$ + " + " + grain_formula$
            endif
        endif
        
        if grain mod 100 = 0
            echo Generated 'grain'/'total_grains' grains
        endif
    endfor
endproc

procedure UniformField
    for grain to total_grains
        grain_time = randomUniform(0, duration - 0.1)
        grain_freq = base_frequency + frequency_spread * (randomUniform(0,1) - 0.5)
        grain_dur = randomUniform(0.02, 0.15)
        grain_amp = randomUniform(0.3, 0.8)
        
        if grain_time + grain_dur > duration
            grain_dur = duration - grain_time
        endif
        
        if grain_dur > 0.001
            grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
            grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
            grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
            grain_formula$ = grain_formula$ + " * sin(pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + ")"
            grain_formula$ = grain_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = grain_formula$
            else
                formula$ = formula$ + " + " + grain_formula$
            endif
        endif
    endfor
endproc

procedure ExponentialCluster
    cluster_centers = round(total_grains / 20)
    
    for cluster to cluster_centers
        cluster_time = randomUniform(0, duration)
        cluster_density = grain_density * (2 + 3 * randomUniform(0,1))
        cluster_grains = round(cluster_density * 0.5)
        cluster_freq_center = base_frequency + frequency_spread * (randomUniform(0,1) - 0.5)
        
        for cluster_grain to cluster_grains
            grain_time = cluster_time + randomExponential(1) * 0.1
            grain_time = max(0, min(duration-0.05, grain_time))
            
            grain_freq = cluster_freq_center * (0.8 + 0.4 * randomUniform(0,1))
            grain_dur = 0.03 + randomExponential(1) * 0.04
            grain_amp = 0.7 * exp(-abs(grain_time - cluster_time) / 0.2)
            
            if grain_time + grain_dur > duration
                grain_dur = duration - grain_time
            endif
            
            if grain_dur > 0.001 and grain_amp > 0.1
                grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
                grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
                grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
                grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + "))/2"
                grain_formula$ = grain_formula$ + " else 0 fi"
                
                if formula$ = "0"
                    formula$ = grain_formula$
                else
                    formula$ = formula$ + " + " + grain_formula$
                endif
            endif
        endfor
        
        if cluster mod 5 = 0
            echo Generated cluster 'cluster'/'cluster_centers'
        endif
    endfor
endproc

procedure BimodalDistribution
    low_freq_center = base_frequency * 0.6
    high_freq_center = base_frequency * 2.5
    
    for grain to total_grains
        grain_time = randomUniform(0, duration - 0.1)
        
        if randomUniform(0,1) < 0.4
            grain_freq = low_freq_center + (frequency_spread/3) * randomGauss(0,1)
        else
            grain_freq = high_freq_center + (frequency_spread/3) * randomGauss(0,1)
        endif
        
        grain_freq = max(50, min(5000, grain_freq))
        
        if grain_freq < base_frequency
            grain_dur = 0.1 + 0.2 * randomUniform(0,1)
            grain_amp = 0.8
        else
            grain_dur = 0.02 + 0.05 * randomUniform(0,1)
            grain_amp = 0.5
        endif
        
        if grain_time + grain_dur > duration
            grain_dur = duration - grain_time
        endif
        
        if grain_dur > 0.001
            grain_formula$ = "if x >= " + string$(grain_time) + " and x < " + string$(grain_time + grain_dur)
            grain_formula$ = grain_formula$ + " then " + string$(grain_amp)
            grain_formula$ = grain_formula$ + " * sin(2*pi*" + string$(grain_freq) + "*x)"
            grain_formula$ = grain_formula$ + " * (1 - cos(2*pi*(x-" + string$(grain_time) + ")/" + string$(grain_dur) + "))/2"
            grain_formula$ = grain_formula$ + " else 0 fi"
            
            if formula$ = "0"
                formula$ = grain_formula$
            else
                formula$ = formula$ + " + " + grain_formula$
            endif
        endif
    endfor
endproc
Play