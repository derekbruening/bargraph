# Copyright (C) 2009-2012 Derek Bruening <iye@alum.mit.edu>
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

%.png: %.ppm
	mogrify -reverse -flatten $<
	mogrify -resize ${SIZE}x${SIZE} -format png $<
$(OUTDIR)/%.ppm: %.perf $(BARGRAPH)
	$(BARGRAPH) -fig $< | fig2dev -L ppm -m 4 > $@
$(OUTDIR)/%.eps: %.perf $(BARGRAPH)
	$(BARGRAPH) -eps $< > $@

clean:
	-rm $(OBJS)
