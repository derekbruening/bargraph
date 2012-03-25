BARGRAPH := ../bargraph.pl
ARGS := 
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
cluster-pattern.ppm: MAGNIFY := 2

%.png: %.ppm
	mogrify -reverse -flatten $<
	mogrify -resize ${SIZE}x${SIZE} -format png $<
%.ppm: %.perf $(BARGRAPH)
	$(BARGRAPH) $(ARGS) -fig $< | fig2dev -L ppm -m $(MAGNIFY) > $@
%.eps: %.perf $(BARGRAPH)
	$(BARGRAPH) $(ARGS) -eps $< > $@

clean:
	-rm $(IMGS) *.ppm
