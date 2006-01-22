#!/usr/bin/perl

# bargraph.pl: a bar graph builder that supports stacking and clustering.
# Modifies gnuplot's output to fill in bars and add a legend.
#
# Copyright (C) 2004-2006 Derek Bruening <iye@alum.mit.edu>
# http://www.burningcutlery.com/derek/bargraph/
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or (at
# your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307,
# USA.

###########################################################################
###########################################################################

$usage = "Usage: $0 [-gnuplot] [-fig] [-pdf] [-png] [-eps] <graphfile>

File format:
<graph parameters>
<data>

Graph parameter types:
<value_param>=<value>
=<bool_param>
";

# Main features:
# * Stacked bars of 9+ datasets
# * Clustered bars of 8+ datasets
# * Lets you keep your data in table format, or separated but listed in
#   the same file, rather than requiring each dataset to be in a separate file
# * Custom gnuplot command pass-through for fine-grained customization
#    without having a separate tool chain step outside the script
# * Color control
# * Automatic arithmetic or harmonic mean calculation
# * Automatic legend creation
# * Automatic sorting, including sorting into SPEC CPU 2000 integer and 
#   floating point benchmark groups
#
# Multiple data sets can either be separated by =multi,
#   or in a table with =table.  Does support incomplete datasets,
#   but issues warning.
# For complete documentation see
#   http://www.burningcutlery.com/derek/bargraph/

# This is version 2.0, released January 21, 2006.
# Changes in version 2.0:
#    * added pattern fill support
#    * fixed errors in large numbers of datasets:
#      - support > 8 clustered bars
#      - fix > 9 dataset color bug
#      - support > 25 stacked bars

###########################################################################
###########################################################################

# we need special support for bidirectional pipe
use IPC::Open2;

# default is to output eps
$output = "eps";

while ($#ARGV >= 0) {
    if ($ARGV[0] eq '-fig') {
        $output = "fig";
    } elsif ($ARGV[0] eq '-gnuplot') {
        $output = "gnuplot";
    } elsif ($ARGV[0] eq '-pdf') {
        $output = "pdf";
    } elsif ($ARGV[0] eq '-png') {
        $output = "png";
    } elsif ($ARGV[0] eq '-eps') {
        $output = "eps";
    } else {
        $graph = $ARGV[0];
        shift;
        last;
    }
    shift;
}
die $usage if ($#ARGV >= 0 || $graph eq "");
open(IN, "< $graph") || die "Couldn't open $graph";

$multiset = 0;
$stacked = 0;

$dataset = 0;
$table = 0;
# leave $column undefined by default

$title = "";
$xlabel = "";
$ylabel = "";
$usexlabels = 1;

# default is to rotate x labels
# when rotated, need to shift xlabel down, -1 is reasonable:
$xlabelshift = "0,-1";
$xticsopts = "rotate";

$sort = 0;
# sort into SPEC CPU 2000 and JVM98 groups: first, SPECFP, then SPECINT, then JVM
$sortbmarks = 0;
$bmarks_fp = "ammp applu apsi art equake facerec fma3d galgel lucas mesa mgrid sixtrack swim wupwise";
$bmarks_int = "bzip2 crafty eon gap gcc gzip mcf parser perlbmk twolf vortex vpr";
$bmarks_jvm = "check compress jess raytrace db javac mpegaudio mtrt jack checkit";

$ymax = "";
$ymin = 0;
$calc_min = 1;

$lineat = "";
$gridx = "noxtics";
$gridy = "ytics";
$noupperright = 0;

$invert = 0;

$use_mean = 0;
$arithmean = 0; # else, harmonic
# leave $mean_label undefined by default

$percent = 0;
$base1 = 0;
$yformat = "%.0f";

$extra_gnuplot_cmds = "";

# if still 0 later will be initialized to default
$legendx = 0;
$legendy = 0;

# use patterns instead of solid fills?
$patterns = 0;
# there are only 22 patterns that fig supports
$max_patterns = 22;

$custom_colors = 0;

# fig depth: leave enough room for many datasets
# (for stacked bars we subtract 2 for each)
# but max gnuplot terminal depth for fig is 99!
$legend_depth = 100;
$plot_depth = 98;

while (<IN>) {
    next if (/^\#/ || /^\s*$/);
    # line w/ = is a control line (except =>)
    if (/=[^>]/) {
        if (/^=cluster(.)/) {
            $splitby = $1;
            s/=cluster$splitby//;
            chop;
            @legend = split($splitby, $_);
            $multiset = $#legend + 1;
        } elsif (/^=stacked(.)/) {
            $splitby = $1;
            s/=stacked$splitby//;
            chop;
            @legend = split($splitby, $_);
            $multiset = $#legend + 1;
            $stacked = 1;
            # reverse order of datasets
            $dataset = $#legend;
        } elsif (/^=multi/) {
            die "Neither cluster nor stacked specified for multiple dataset"
                if (!$multiset);
            if ($stacked) {
                # reverse order of datasets
                $dataset--;
            } else {
                $dataset++;
            }
        } elsif (/^=patterns/) {
            $patterns = 1;
        } elsif (/^colors=(.*)/) {
            $custom_colors = 1;
            @custom_color = split(',', $1);
        } elsif (/^=table/) {
            $table = 1;
        } elsif (/^column=(\S+)/) {
            $column = $1;
        } elsif (/^=base1/) {
            $base1 = 1;
        } elsif (/^=invert/) {
            $invert = 1;
        } elsif (/^=percent/) {
            $percent = 1;
        } elsif (/^=sortbmarks/) {
            $sort = 1;
            $sortbmarks = 1;
        } elsif (/^=sort/) { # don't prevent match of =sortbmarks
            $sort = 1;
        } elsif (/^=arithmean/) {
            $use_mean = 1;
            $arithmean = 1;
        } elsif (/^=harmean/) {
            $use_mean = 1;
        } elsif (/^meanlabel=(.*)$/) {
            $mean_label = $1;
        } elsif (/^min=([\d\.]+)/) {
            $ymin = $1;
            $calc_min = 0;
        } elsif (/^max=([\d\.]+)/) {
            $ymax = $1;
        } elsif (/^=norotate/) {
            $xticsopts = "";
            # actually looks better at -1 when not rotated, too
            $xlabelshift = "0,-1";
        } elsif (/^xlabelshift=(.+)/) {
            $xlabelshift = $1;
        } elsif (/^title=(.*)$/) {
            $title = $1;
        } elsif (/^=noxlabels/) {
            $usexlabels = 0;
        } elsif (/^xlabel=(.*)$/) {
            $xlabel = $1;
        } elsif (/^ylabel=(.*)$/) {
            $ylabel = $1;
        } elsif (/^yformat=(.*)$/) {
            $yformat = $1;
        } elsif (/^=noupperright/) {
            $noupperright = 1;
        } elsif (/^=gridx/) {
            $gridx = "xtics";
        } elsif (/^=nogridy/) {
            $gridy = "noytics";
        } elsif (/^legendx=(\d+)/) {
            $legendx = $1;
        } elsif (/^legendy=(\d+)/) {
            $legendy = $1;
        } elsif (/^extraops=(.*)/) {
            $extra_gnuplot_cmds .= "$1\n";
        } else {
            die "Unknown command $_\n";
        }
        next;
    }

    # this line must have data on it!
    
    if ($table) {
        # table has to look like this:
        # <bmark1> <dataset1> <dataset2> <dataset3> ...
        # <bmark2> <dataset1> <dataset2> <dataset3> ...
        # ...
        @table_entry = split(' ', $_);
        if ($#table_entry != $multiset) { # not +1 since bmark
            die "Table format error on line $_: $#table_entry vs $multiset\n";
        }
        $bmark = $table_entry[0];
        for ($i=1; $i<=$#table_entry; $i++) {
            if ($stacked) {
                # reverse order of datasets
                $dataset = $multiset-1 - ($i-1);
            } else {
                $dataset = $i-1;
            }
            $val = get_val($table_entry[$i], $dataset);
            if ($stacked && $dataset < $multiset-1) {
                # need to add prev bar to stick above
                $entry{$bmark,$dataset+1} =~ /\s+([\d\.]+)/;
                $val += $1;
            }
            $entry{$bmark,$dataset} = "$bmark  $val\n";
        }
        goto nextiter;
    }

    # support the column= feature
    if (defined($column)) {
        my @columns = split(' ', $_);
        $bmark = $columns[0];
        if ($column eq "last") {
            $val_string = $columns[$#columns];
        } else {
            die "Column $column out of bounds" if ($column > 1 + $#columns);
            $val_string = $columns[$column - 1];
        }
    } elsif (/^\s*(\S+)\s+([\d\.]+)/) {
        $bmark = $1;
        $val_string = $2;
    } else {
        if (/\S+/) {
            print STDERR "WARNING: unexpected, unknown-format line $_";
        }
        next;
    }

    # strip out trailing %
    $val_string =~ s/%$//;
    if ($val_string !~ /^[\d\.]+$/) {
        print STDERR "WARNING: non-numeric value \"$val_string\" for $bmark\n";
    }

    $val = get_val($val_string, $dataset);
    if ($stacked && $dataset < $multiset-1) {
        # need to add prev bar to stick above
        # remember that we're walking backward
        $entry{$bmark,$dataset+1} =~ /\s+([\d\.]+)/;
        $val += $1;
    }
    $entry{$bmark,$dataset} = "$bmark  $val\n";

  nextiter:
    if (!defined($names{$bmark})) {
        $names{$bmark} = $bmark;
        $order{$bmark} = $bmarks_seen++;
    }
}
close(IN);

###########################################################################
###########################################################################

$plotcount = 1;
if ($multiset) {
    $plotcount = $multiset;
}

if ($sort) {
    if ($sortbmarks) {
        @sorted = sort sort_bmarks (keys %names);
    } else {
        @sorted = sort (keys %names);
    }
} else {
    # put into order seen in file
    @sorted = sort {$order{$a} <=> $order{$b}} (keys %names);
}

if ($use_mean) {
    for ($i=0; $i<$plotcount; $i++) {
        if ($stacked) {
            $category = $plotcount-$i;
        } else {
            $category = $i;
        }
        if ($arithmean) {
            die "Error calculating mean: category $category has denom 0"
                if ($harnum[$i] == 0);
            $harmean[$i] = $harsum[$i] / $harnum[$i];
        } else {
            die "Error calculating mean: category $category has denom 0"
                if ($harsum[$i] == 0);
            $harmean[$i] = $harnum[$i] / $harsum[$i];
        }
        if ($percent) {
            $harmean[$i] = ($harmean[$i] - 1) * 100;
        } elsif ($base1) {
            $harmean[$i] = ($harmean[$i] - 1);
        }
    }
    if ($stacked) {
        for ($i=$plotcount-2; $i>=0; $i--) {
            # need to add prev bar to stick above
            # since reversed, prev is +1
            $harmean[$i] += $harmean[$i+1];
        }
    }
}

# x-axis labels
$xtics = "";
$xmax = 1;
foreach $b (@sorted) {
    if ($usexlabels) {
        $xtics .= "\"$b\" $xmax, ";
    } else {
        $xtics .= "\"\" $xmax, ";
    }
    $xmax++;
}
if ($use_mean) {
    if ($usexlabels) {
        if (!defined($mean_label)) {
            if ($arithmean) {
                $mean_label = "mean";
            } else {
                $mean_label = "har_mean";
            }
        }
    } else {
        $xtics .= "\"\" $xmax, ";
    }
    $xtics .= "\"$mean_label\" $xmax, ";
    $xmax++;
}
# lose the last comma-space
chop $xtics;
chop $xtics;

# add space between y-axis label and y tic labels
if ($ylabel ne "") {
    $yformat = "  $yformat";
} else {
    # fix bounding box problem: cutting off tic labels on left if
    # no axis label -- is it gnuplot bug?  we're not mangling these
    $yformat = " $yformat";
}

if ($calc_min) {
    if ($min < 0) {
        # round to next lower int
        if ($min < 0) {
            $min = int($min - 1);
        }
        $ymin = $min;
        $lineat = "f(x)=0,f(x) notitle,"; # put line at 0
    } # otherwise leave ymin at 0
} # otherwise leave ymin at user-specified value

$boxwidth=0.5;
if (!$stacked) {
    if ($plotcount == 2) {
        $boxwidth=0.3;
    } elsif ($plotcount == 3) {
        $boxwidth=0.26;
    } elsif ($plotcount == 4) {
        $boxwidth=0.2;
    } elsif ($plotcount == 5) {
        $boxwidth=0.16;
    } elsif ($plotcount == 6) {
        $boxwidth=0.12;
    } elsif ($plotcount == 7) {
        $boxwidth=0.11;
    } elsif ($plotcount == 8) {
        $boxwidth=0.08;
    } elsif ($plotcount >= 9) {
        $boxwidth=0.75/$plotcount;
    }
}

###########################################################################
###########################################################################

$use_colors=1;

# custom colors are from 32 onward, we insert them into the fig file
# the order here is the order for 9+ datasets
$basefigcolor=32;
$numfigclrs=0;
$figcolor[$numfigclrs]="#000000"; $fig_black=$colornm{'black'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#aaaaff"; $fig_light_blue=$colornm{'light_blue'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#00aa00"; $fig_dark_green=$colornm{'dark_green'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#77ff00"; $fig_light_green=$colornm{'light_green'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#ffff00"; $fig_yellow=$colornm{'yellow'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#ff0000"; $fig_red=$colornm{'red'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#dd00ff"; $fig_magenta=$colornm{'magenta'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#0000ff"; $fig_dark_blue=$colornm{'dark_blue'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#00ffff"; $fig_cyan=$colornm{'cyan'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#dddddd"; $fig_grey=$colornm{'grey'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#6666ff"; $fig_med_blue=$colornm{'med_blue'}=$basefigcolor + $numfigclrs++;
$num_nongrayscale = $numfigclrs;
# for grayscale
$figcolor[$numfigclrs]="#222222"; $fig_grey=$colornm{'grey1'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#444444"; $fig_grey=$colornm{'grey2'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#666666"; $fig_grey=$colornm{'grey3'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#888888"; $fig_grey=$colornm{'grey4'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#aaaaaa"; $fig_grey=$colornm{'grey5'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#cccccc"; $fig_grey=$colornm{'grey6'}=$basefigcolor + $numfigclrs++;
$figcolor[$numfigclrs]="#eeeeee"; $fig_grey=$colornm{'grey7'}=$basefigcolor + $numfigclrs++;

$figcolorins = "";
for ($i=0; $i<=$#figcolor; $i++) {
    $figcolorins .= sprintf("0 %d %s\n", 32+$i, $figcolor[$i]);
}
chomp($figcolorins);

if ($patterns) {
    for ($i=0; $i<$plotcount; $i++) {
        # cycle around at max
        $fillstyle[$i] = 41 + ($i % $max_patterns);
        # FIXME: could combine patterns and colors, we don't bother to support that
        $fillcolor[$i] = 7;
    }
} elsif ($use_colors) {
    # colors: all solid fill
    for ($i=0; $i<$plotcount; $i++) {
        $fillstyle[$i]=20;
    }
    if ($custom_colors) {
        for ($i=0; $i<$plotcount; $i++) {
            $fillcolor[$i]=$colornm{$custom_color[$i]};
        }
    } else {
        # color schemes that I tested as providing good contrast when
        # printed on a non-color printer
        if ($plotcount == 1) {
            $fillcolor[0]=$fig_light_blue;
        } elsif ($plotcount == 2) {
            $fillcolor[0]=$fig_med_blue;
            $fillcolor[1]=$fig_yellow;
        } elsif ($plotcount == 3) {
            $fillcolor[0]=$fig_med_blue;
            $fillcolor[1]=$fig_yellow;
            $fillcolor[2]=$fig_red;
        } elsif ($plotcount == 4) {
            $fillcolor[0]=$fig_med_blue;
            $fillcolor[1]=$fig_yellow;
            $fillcolor[2]=$fig_dark_green;
            $fillcolor[3]=$fig_red;
        } elsif ($plotcount == 5) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_yellow;
            $fillcolor[2]=$fig_red;
            $fillcolor[3]=$fig_med_blue;
            $fillcolor[4]=$fig_grey;
        } elsif ($plotcount == 6) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_yellow;
            $fillcolor[3]=$fig_red;
            $fillcolor[4]=$fig_med_blue;
            $fillcolor[5]=$fig_grey;
        } elsif ($plotcount == 7) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_yellow;
            $fillcolor[3]=$fig_red;
            $fillcolor[4]=$fig_dark_blue;
            $fillcolor[5]=$fig_cyan;
            $fillcolor[6]=$fig_grey;
        } elsif ($plotcount == 8) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_yellow;
            $fillcolor[3]=$fig_red;
            $fillcolor[4]=$fig_magenta;
            $fillcolor[5]=$fig_dark_blue;
            $fillcolor[6]=$fig_cyan;
            $fillcolor[7]=$fig_grey;
        } elsif ($plotcount == 9) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_light_green;
            $fillcolor[3]=$fig_yellow;
            $fillcolor[4]=$fig_red;
            $fillcolor[5]=$fig_magenta;
            $fillcolor[6]=$fig_dark_blue;
            $fillcolor[7]=$fig_cyan;
            $fillcolor[8]=$fig_grey;
        } else {
            for ($i=0; $i<$plotcount; $i++) {
                # FIXME: set to programmatic spread of custom colors
                # for now we simply re-use our set of colors
                $fillcolor[$i]=$basefigcolor + ($i % $num_nongrayscale);
            }
        }
    }
    if ($stacked) {
        # reverse order for stacked since we think of bottom as "first"
        for ($i=0; $i<$plotcount; $i++) {
            $tempcolor[$i]=$fillcolor[$i];
        }
        for ($i=0; $i<$plotcount; $i++) {
            $fillcolor[$i]=$tempcolor[$plotcount-$i-1];
        }
    }
} else {
    # b&w fills
    $bwfill[0]=5;
    $bwfill[1]=10;
    $bwfill[2]=2;
    $bwfill[3]=14;
    $bwfill[4]=7;
    $bwfill[5]=13;
    $bwfill[6]=3;
    $bwfill[7]=9;
    $bwfill[8]=4;
    $bwfill[9]=11;
    $bwfill[10]=6;
    for ($i=0; $i<$plotcount; $i++) {
        if ($stacked) {
            # reverse order for stacked since we think of bottom as "first"
            $fillstyle[$i]=$bwfill[$plotcount-$i-1];
        } else {
            $fillstyle[$i]=$bwfill[$i];
        }
        $fillcolor[$i]=-1;
    }
}

# "set terminal" set the default depth to $plot_depth
# we want bars in front of rest of plot
# though we will violate that rule to fit extra datasets (> 48)
$start_depth = ($plot_depth - 2 - 2*($plotcount-1)) < 0 ?
    2*$plotcount : $plot_depth;
for ($i=0; $i<$plotcount; $i++) {
    $depth[$i] = $start_depth - 2 - 2*$i;
}

###########################################################################
###########################################################################

local (*FIG, *GNUPLOT);

# now process the resulting figure
if ($output eq "gnuplot") {
    $debug_seegnuplot = 1;
} else {
    $debug_seegnuplot = 0;
}

if ($debug_seegnuplot) {
    open(GNUPLOT, "| cat") || die "Couldn't open cat\n";
} else {
    # open a bidirectional pipe to gnuplot to avoid temp files
    # we can read its output back using FIG filehandle
    $pid = open2(\*FIG, \*GNUPLOT, "gnuplot") || die "Couldn't open2 gnuplot\n";
}

printf GNUPLOT "
set title '%s'
# can also pass \"fontsize 12\" to fig terminal
set terminal fig color depth %d
", $title, $plot_depth;

printf GNUPLOT "
set xlabel '%s' %s
set ylabel '%s'
set xtics %s (%s)
set format y \"%s\"
", $xlabel, $xlabelshift, $ylabel, $xticsopts, $xtics, $yformat;

printf GNUPLOT "
set boxwidth %s
set xrange [0:%d]
set yrange[%s:%s]
set grid %s %s
", $boxwidth, $xmax, $ymin, $ymax, $gridx, $gridy;

if ($noupperright) {
    print GNUPLOT "
set xtics nomirror
set ytics nomirror
set border 3
";
}

if ($extra_gnuplot_cmds ne "") {
    print GNUPLOT "\n$extra_gnuplot_cmds\n";
}

# plot data from stdin, separate style for each so can distinguish
# in resulting fig
printf GNUPLOT "plot %s ", $lineat;
for ($i=0; $i<$plotcount; $i++) {
    if ($i != 0) {
        printf GNUPLOT ", ";
    }
    if ($patterns) {
        printf GNUPLOT "'-' notitle with boxes fs pattern %d", ($i % $max_patterns);
    } else {
        printf GNUPLOT "'-' notitle with boxes %d", $i+3;
    }
}
print GNUPLOT "\n";

for ($i=0; $i<$plotcount; $i++) {
    $line = 1;
    foreach $b (@sorted) {
        # support missing values in some datasets
        if (defined($entry{$b,$i})) {
            $xval = get_xval($i, $line);
            print GNUPLOT "$xval,$entry{$b,$i}";
            $line++;
        } else {
            print STDERR "WARNING: missing value for $b in dataset $i\n";
            $line++;
        }
    }
    # skip over missing values to put harmean at end
    $line = $xmax - 1;
    if ($use_mean) {
        $xval = get_xval($i, $line);
        if ($arithmean) {
            print GNUPLOT "$xval,mean  $harmean[$i]\n";
        } else {
            print GNUPLOT "$xval,har_mean  $harmean[$i]\n";
        }
    }
    # an e separates each dataset
    print GNUPLOT "e\n";
}

close(GNUPLOT);

exit if ($debug_seegnuplot);

###########################################################################
###########################################################################

# now process the resulting figure
if ($output eq "fig") {
    $fig2dev = "cat";
} elsif ($output eq "eps") {
    $fig2dev = "fig2dev -L eps -n \"$title\"";
} elsif ($output eq "pdf") {
    $fig2dev = "fig2dev -L pdf -n \"$title\"";
} elsif ($output eq "png") {
    $fig2dev = "fig2dev -L png -m 2 | convert -transparent white - - ";
} else {
    die "Error: unknown output type $output\n";
}

$debug_seefig = 0;
$debug_seefig_unmod = 0;
if ($debug_seefig) {
    $fig2dev = "cat";
}

open(FIG2DEV, "| $fig2dev") || die "Couldn't open $fig2dev\n";

# fig format for polyline:
#   2   1    0    1     -1     -1     10     0     6    0.000    0     0    0    0    0     5
#          line  line  line   fill   depth        fill  dash   join   cap      frwrd back
#          style width color  color               style  gap   style style    arrws? arrws?
# fill style: 0-20: 0=darkest, 20=pure color
# arrows have another line of stats, if present

# fig format for text:
#   4   1    0    0   -1    0     10   1.5708     0    135    1830  1386 2588  Actual text\001
#     just     depth      font  fontsz rotation  flag boundy boundx   x    y
#                                     angle(rads)             
# justification: 0=center, 1=left, 2=right
# flag (or-ed together): 1=rigid, 2=special, 8=hidden
# boundy: 10-pt default latex font: 75 + 30 above + 30 below
#   => 135 if both above and below line chars present, 105 if only above, etc.
# boundx: 10-pt default latex font: M=150, m=120, i=45, ave lowercase=72, ave uppercase=104
#   that's ave over alphabet, a capitalized word seems to be closer to 69 ave
#   if have bounds wrong then fig2dev will get eps bounding box wrong

while (<FIG>) {
    if ($debug_seefig_unmod) {
        print FIG2DEV $_;
        next;
    }

    # Insert our custom fig colors
    s|^1200 2$|1200 2
$figcolorins|;

    # Convert rectangles with line style N to filled rectangles.
    # We put them at depth 40.

    # First 5 are solid lines of colors 2 through 6
    # We subtract 2 from color to get index
    s|^2 1 0 1 ([1-9]) \1 $plot_depth 0 -1     0.000 0 0 0 0 0 5|2 1 0 1 -1  $fillcolor[$1-2]  $depth[$1-2] 0 $fillstyle[$1-2]     0.000 0 0 0 0 0 5|;

    # Next are in groups of 7, each with colors 0 through 6 and
    # with gap of group# * 3.000 => index is (color + 5 + 7*(gap/3 - 1))
    s|^2 1 1 1 ([0-9]) \1 $plot_depth 0 -1 +([0-9]+).000 0 0 0 0 0 5|2 1 0 1 -1  $fillcolor[$1+5+7*($2/3-1)]  $depth[$1+5+7*($2/3-1)] 0 $fillstyle[$1+5+7*($2/3-1)]     0.000 0 0 0 0 0 5|;
    
    # Add commas between 3 digits for text in thousands or millions
    s|^4 (.*\d)(\d{3}\S*)\\001$|4 $1,$2\\001|; 
    s|^4 (.*\d)(\d{3}),(\d{3}\S*)\\001$|4 $1,$2,$3\\001|; 

    print FIG2DEV $_;
}

# add the legend
if ($plotcount > 1) {
    # center top is around lx=3800 ly=900
    # on right: lx=7100 ly=2300
    if ($legendx == 0) {
        $lx=3800;
    } else {
        $lx=$legendx;
    }
    if ($legendy == 0) {
        $ly=1200 - $plotcount*150;
    } else {
        $ly=$legendy;
    }
      
    for ($i=0; $i<$plotcount; $i++) {
        $dy=$i*157;
        printf FIG2DEV
"2 1 0 1 -1 $fillcolor[$i] $legend_depth 0 $fillstyle[$i] 0.000 0 0 0 0 0 5
\t %d %d %d %d %d %d %d %d %d %d  
",  $lx, $ly+200+$dy, $lx, $ly+84+$dy, $lx+121, $ly+84+$dy,
    $lx+121, $ly+200+$dy, $lx, $ly+200+$dy;
    }
    for ($i=0; $i<$plotcount; $i++) {
        # legend was never reversed, reverse it here
        if ($stacked) {
            $legidx = $plotcount - 1 - $i;
        } else {
            $legidx = $i;
        }
        # 9-point so legend not so big
        # estimate text bounds (important if legend on right to get bounding box)
        # use width*70, and assume full height 135 (see fig notes above)
        $leglen = length $legend[$legidx];
        printf FIG2DEV
"4 0 0 %d 0 0 9 0.0000 4 135 %d %d %d %s\\001
", $legend_depth, $leglen*70, $lx+225, $ly+186+157*$i, $legend[$legidx];
    }
}

close(FIG);
close(FIG2DEV);

waitpid($pid, 0);

###########################################################################
###########################################################################

# supporting subroutines

sub get_val($, $)
{
    my ($val, $idx) = @_;
    if ($invert) {
        $val = 1/$val;
    }
    if ($use_mean) {
        if ($arithmean) {
            $harsum[$idx] += $val;
        } else {
            die "Harmonic mean cannot be computed with a value of 0!" if ($val == 0);
            $harsum[$idx] += 1/$val;
        }
        $harnum[$idx]++;
    }
    if ($percent) {
        $val = ($val - 1) * 100;
    } elsif ($base1) {
        $val = ($val - 1);
    }
    if (!defined($min)) {
        $min = $val;
    } elsif ($val < $min) {
        $min = $val;
    }
    return $val;
}

sub get_xval($, $)
{
    # item ranges from 0..plotcount-1
    my ($dset, $item) = @_;
    my ($xvalue);
    if ($stacked || $plotcount == 1) {
        $xvalue = $item;
    } elsif ($plotcount % 2 == 0) {
        # we want the sequence ...,-5/2,-3/2,-1/2,1/2,3/2,5/2,...
        $xvalue = $item + $boxwidth/2 * (2*$dset-($plotcount-1));
    } else {
        # we want the sequence ...,-2,-1,0,1,2,,...
        $xvalue = $item + $boxwidth * ($dset - ($plotcount-1)/2);
    }
    return $xvalue;
}

sub sort_bmarks()
{
    return ((&bmark_group($a) <=> &bmark_group($b)) or ($a cmp $b));
}

sub bmark_group($)
{
    my ($bmark) = @_;
    return 1 if ($bmarks_fp =~ $bmark);
    return 2 if ($bmarks_int =~ $bmark);
    return 3 if ($bmarks_jvm =~ $bmark);
    return 4; # put unknowns at end
}
