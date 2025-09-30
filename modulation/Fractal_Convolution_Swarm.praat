# Fractal Convolution Swarm — defaults baked in
# Assumes a Sound is selected.

fractalDepth = 5
convolutionWidth = 3

Copy... soundObj
selectObject: "Sound soundObj"
a = Get number of samples

for depth from 1 to 'fractalDepth'
    scaleFactor = 2 ^ depth
    kernelSize = round(a / (10 * scaleFactor))
    for kernel from -'convolutionWidth' to 'convolutionWidth'
        kernelWeight = 1 / (1 + abs(kernel))
        kernelShift = kernel * kernelSize
        Formula... self + self [max(1, min(ncol, col + 'kernelShift'))] * 'kernelWeight' / ('depth' + 2)
    endfor
    Formula... self * (1 - 'depth' * 0.15)
endfor

Scale peak... 0.90
Rename... fractal_convolution_swarm
Play

