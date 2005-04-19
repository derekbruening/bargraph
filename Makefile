BARGRAPH = ~/bin/bargraph.pl

SIZE=700

%.png: %.tiff
	mogrify -resize ${SIZE}x${SIZE} -format png $<
	rm $@.1
	mv $@.0 $@
%.tiff: %.perf $(BARGRAPH)
	bargraph.pl -fig $< | fig2dev -L tiff -m 4 > $@
%.eps: %.perf $(BARGRAPH)
	$(BARGRAPH) -eps $< > $@
