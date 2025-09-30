Copy... tmp
ntimes = 20
delay = randomInteger(0,1000)
for i from 1 to ntimes
	Formula... self +0.5*self[col-'delay']
endfor
Scale peak: 0.99
Play
