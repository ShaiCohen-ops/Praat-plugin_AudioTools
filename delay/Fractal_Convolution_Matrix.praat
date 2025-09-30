Copy... soundObj

a = Get number of samples
fractalDepth = 5
convolutionWidth = 3

for depth from 1 to fractalDepth
    scaleFactor = 2 ^ depth
    kernelSize = round(a / (10 * scaleFactor))
    
    # Fractal convolution kernel
    for kernel from -convolutionWidth to convolutionWidth
        kernelWeight = 1 / (1 + abs(kernel))
        kernelShift = kernel * kernelSize
        
        Formula: "self + self [col + 'kernelShift'] * 'kernelWeight' / ('depth' + 2)"
    endfor
    
    # Fractal amplitude scaling
    Formula: "self * (1 - depth * 0.15)"
endfor
Scale peak: 0.90
Play

