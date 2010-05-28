BARGRAPH := ../bargraph.pl
# avoid gnuplot bug that truncates x labels if graph scaled
ARGS := -gnuplot-path /home/derek/bargraph/gnuplot-4.2.0-derek/install/bin/gnuplot
#ARGS := -gnuplot-path /home/derek/bargraph/gnuplot-4.0.0/install/bin/gnuplot
MAGNIFY := 4

SIZE := 700

SRCS := $(shell ls *.perf)
IMGS := $(subst perf,png,$(SRCS))

HTML := all.html

default: $(IMGS) $(HTML)

$(HTML): Makefile $(SRCS)
	@(rm $(HTML); echo -e "<body bgcolor=\"#bbeeee\">\n" >> $(HTML); \
	for i in $(SRCS); do \
	echo -e "<p>$$i</p><table><tr>\n" >> $(HTML); \
	echo -e "<td><img src=\"$${i/perf/png}\"></td><td>&nbsp;</td>\n" >> $(HTML); \
	echo -e "<td><img src=\"prev/$${i/perf/png}\"></td>\n" >> $(HTML); \
	echo -e "</tr></table></body>\n" >> $(HTML); \
	done)

# newer gnuplot patterns have lines that are much closer together, and w/
# high magnification they shrink down into gray splatter (can't see individual
# lines): x2 is much better than x4+ (x1 is blocky)
cluster-pattern.tiff: MAGNIFY := 2

%.png: %.tiff
	mogrify -resize ${SIZE}x${SIZE} -format png $<
# older mogrify uses these names:
# rm $@.1
# mv $@.0 $@
	rm $*-1.png
	mv $*-0.png $@
%.tiff: %.perf $(BARGRAPH)
	$(BARGRAPH) $(ARGS) -fig $< | fig2dev -L tiff -m $(MAGNIFY) > $@
%.eps: %.perf $(BARGRAPH)
	$(BARGRAPH) $(ARGS) -eps $< > $@

clean:
	-rm $(IMGS) *.tiff
