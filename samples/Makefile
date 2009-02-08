# Copyright (C) 2009 Derek Bruening <iye@alum.mit.edu>
# http://www.burningcutlery.com/derek/bargraph/
# http://code.google.com/p/bargraphgen/

OUTDIR := ../../build/samples

BARGRAPH := ../bargraph.pl

SIZE := 700

SRCS := $(wildcard *.perf)
OBJS := $(patsubst %.perf,$(OUTDIR)/%.png,$(SRCS))

all: mkoutdir $(OBJS)

mkoutdir:
	@(if ! test -e $(OUTDIR); then mkdir -p $(OUTDIR); fi)

%.png: %.tiff
	mogrify -resize ${SIZE}x${SIZE} -format png $<
# older mogrify uses these names:
# rm $@.1
# mv $@.0 $@
	rm $*-1.png
	mv $*-0.png $@
$(OUTDIR)/%.tiff: %.perf $(BARGRAPH)
	$(BARGRAPH) -fig $< | fig2dev -L tiff -m 4 > $@
$(OUTDIR)/%.eps: %.perf $(BARGRAPH)
	$(BARGRAPH) -eps $< > $@

clean:
	-rm $(OBJS)
