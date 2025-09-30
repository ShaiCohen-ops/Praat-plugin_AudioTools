#Get Sound
s1 = selected("Sound",1)
s1$ = selected$("Sound",1)
t = Get total duration

#set parameters for vocoding
numberOfBands = 16
lowerLim = 50
upperLim = 11000
sr = 2 * upperLim + 1000


clearinfo
blowerLim = hertzToBark(lowerLim)
bupperLim = hertzToBark(upperLim)
step = (bupperLim - blowerLim)/numberOfBands


for i from 1 to numberOfBands
#for adding previous bands
if i > 1
j = i - 1
select Sound band'j'
Rename... previous
endif
#get limits for band
bandUpper = blowerLim + i * step
bandLower = bandUpper - step
temp1 = round(barkToHertz(bandLower))
temp2 = round(barkToHertz(bandUpper))
#information about band to window
printline band 'i' from 'temp1' to 'temp2'
# account for filtersmoothing
temp1 = temp1 + 25
temp2 = temp2 - 25
#generate estimate of ENERGY in band of SOURCE
select 's1'
Filter (pass Hann band)... 'temp1' 'temp2' 50
#get overall rms in band
rms_SOURCE = Get root-mean-square... 0 0
Rename... temp
#get intensity contour
To Intensity... 100 0 yes
Down to IntensityTier
#create a noise-band sound
Create Sound... noise 0 't' 'sr' randomGauss(0,0.1)
Filter (pass Hann band)... 'temp1' 'temp2' 50
#add intensity contour of source
plus IntensityTier temp
Multiply... no
#adjust overall amplitude
rms_IS = Get root-mean-square... 0 0
Multiply... rms_SOURCE/rms_IS
Rename... band'i'
#add previous bands
if i > 1
Formula... self[col] + Sound_previous[col]
endif
select all
minus 's1'
minus Sound band'i'
Remove
endfor
