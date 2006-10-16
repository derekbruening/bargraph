BARGRAPH = ~/bin/bargraph.pl

SIZE=700

%.png: %.tiff
	mogrify -resize ${SIZE}x${SIZE} -format png $<
# older mogrify uses these names:
# rm $@.1
# mv $@.0 $@
	rm $*-1.png
	mv $*-0.png $@
%.tiff: %.perf $(BARGRAPH)
	bargraph.pl -fig $< | fig2dev -L tiff -m 4 > $@
%.eps: %.perf $(BARGRAPH)
	$(BARGRAPH) -eps $< > $@
