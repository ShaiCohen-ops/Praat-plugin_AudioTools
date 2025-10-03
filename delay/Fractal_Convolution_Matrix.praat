form Fractal Sound Processing
    comment Fractal processing parameters:
    natural fractal_depth 5
    natural convolution_width 3
    comment Scaling parameters:
    positive kernel_divisor 10
    positive amplitude_reduction 0.15
    comment Output options:
    positive scale_peak 0.90
    boolean play_after_processing 1
endform

# Copy the sound object
Copy... soundObj

# Get the number of samples
a = Get number of samples

# Main fractal processing loop
for depth from 1 to fractal_depth
    scaleFactor = 2 ^ depth
    kernelSize = round(a / (kernel_divisor * scaleFactor))
    
    # Fractal convolution kernel
    for kernel from -convolution_width to convolution_width
        kernelWeight = 1 / (1 + abs(kernel))
        kernelShift = kernel * kernelSize
        
        Formula: "self + self [col + 'kernelShift'] * 'kernelWeight' / ('depth' + 2)"
    endfor
    
    # Fractal amplitude scaling
    Formula: "self * (1 - depth * 'amplitude_reduction')"
endfor

# Scale to peak
Scale peak: scale_peak

# Play if requested
if play_after_processing
    Play
endif

