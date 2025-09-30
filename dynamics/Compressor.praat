form Compressor
natural Compression_(1-100_%) 25
endform

if compression > 100
    compression = 100
endif
comp = compression/100

s$ = selected$("Sound")
wrk = Copy... compressed
Formula... self / (1 + abs(self) * 'comp' * 10)
Scale peak... 0.99
Play