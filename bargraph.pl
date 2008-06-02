#!/usr/bin/perl

# bargraph.pl: a bar graph builder that supports stacking and clustering.
# Modifies gnuplot's output to fill in bars and add a legend.
#
# Copyright (C) 2004-2008 Derek Bruening <iye@alum.mit.edu>
# http://www.burningcutlery.com/derek/bargraph/
# Error bar code contributed by Mohammad Ansari.
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

$usage = "
Usage: $0 [-gnuplot] [-fig] [-pdf] [-png [-non-transparent]] [-eps]
  [-gnuplot-path <path>] [-fig2dev-path <path>] <graphfile>

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
# * Clusters of stacked bars
# * Lets you keep your data in table format, or separated but listed in
#   the same file, rather than requiring each dataset to be in a separate file
# * Custom gnuplot command pass-through for fine-grained customization
#    without having a separate tool chain step outside the script
# * Color control
# * Font face control and limited font size control
# * Automatic arithmetic or harmonic mean calculation
# * Automatic legend creation
# * Automatic sorting, including sorting into SPEC CPU 2000 integer and 
#   floating point benchmark groups
#
# Multiple data sets can either be separated by =multi,
#   or in a table with =table.  Does support incomplete datasets,
#   but issues warning.
# For clusters of stacked bars, separate your stacked data for each
#   cluster with =multi or place in a table, and separate (and optionally
#   name) each cluster with multimulti=
# For complete documentation see
#   http://www.burningcutlery.com/derek/bargraph/

# This is version 4.3.
# Changes in version 4.3, released June 1, 2008:
#    * added errorbar support (from Mohammad Ansari)
#    * added support for multiple colors in a single dataset
#    * added -non-transparent option to disable png transparency
#    * added option to disable the legend
#    * added datascale and datasub options
# Changes in version 4.2, released May 25, 2007:
#    * handle gnuplot 4.2 fig terminal output
# Changes in version 4.1, released April 1, 2007:
#    * fixed bug in handling scientific notation
#    * fixed negative offset font handling bug
# Changes in version 4.0, released October 16, 2006:
#    * added support for clusters of stacked bars
#    * added support for font face and size changes
#    * added support for negative maximum values
# Changes in version 3.0, released July 15, 2006:
#    * added support for spaces and quotes in x-axis labels
#    * added support for missing values in table format
#    * added support for custom table delimiter
#    * added an option to suppress adding of commas
# Changes in version 2.0, released January 21, 2006:
#    * added pattern fill support
#    * fixed errors in large numbers of datasets:
#      - support > 8 clustered bars
#      - fix > 9 dataset color bug
#      - support > 25 stacked bars

# we need special support for bidirectional pipe
use IPC::Open2;

###########################################################################
###########################################################################

# The full set of Postscript fonts supported by FIG
%fig_font = (
    'Default'                            => -1,      
    'Times Roman'                        =>  0,      
    # alias
    'Times'                              =>  0,      
    'Times Italic'                       =>  1,      
    'Times Bold'                         =>  2,      
    'Times Bold Italic'                  =>  3,      
    'AvantGarde Book'                    =>  4,      
    'AvantGarde Book Oblique'            =>  5,      
    'AvantGarde Demi'                    =>  6,      
    'AvantGarde Demi Oblique'            =>  7,      
    'Bookman Light'                      =>  8,      
    'Bookman Light Italic'               =>  9,      
    'Bookman Demi'                       => 10,      
    'Bookman Demi Italic'                => 11,      
    'Courier'                            => 12,      
    'Courier Oblique'                    => 13,      
    'Courier Bold'                       => 14,      
    'Courier Bold Oblique'               => 15,      
    'Helvetica'                          => 16,      
    'Helvetica Oblique'                  => 17,      
    'Helvetica Bold'                     => 18,      
    'Helvetica Bold Oblique'             => 19,      
    'Helvetica Narrow'                   => 20,      
    'Helvetica Narrow Oblique'           => 21,      
    'Helvetica Narrow Bold'              => 22,      
    'Helvetica Narrow Bold Oblique'      => 23,      
    'New Century Schoolbook Roman'       => 24,      
    'New Century Schoolbook Italic'      => 25,      
    'New Century Schoolbook Bold'        => 26,      
    'New Century Schoolbook Bold Italic' => 27,      
    'Palatino Roman'                     => 28,      
    'Palatino Italic'                    => 29,      
    'Palatino Bold'                      => 30,      
    'Palatino Bold Italic'               => 31,      
    'Symbol'                             => 32,      
    'Zapf Chancery Medium Italic'        => 33,      
    'Zapf Dingbats'                      => 34,      
);

###########################################################################
###########################################################################

# default is to output eps
$output = "eps";
$gnuplot_path = "gnuplot";
$fig2dev_path = "fig2dev";
$debug_seefig_unmod = 0;
$png_transparent = 1;

while ($#ARGV >= 0) {
    if ($ARGV[0] eq '-fig') {
        $output = "fig";
    } elsif ($ARGV[0] eq '-rawfig') {
        $output = "fig";
        $debug_seefig_unmod = 1;
    } elsif ($ARGV[0] eq '-gnuplot') {
        $output = "gnuplot";
    } elsif ($ARGV[0] eq '-pdf') {
        $output = "pdf";
    } elsif ($ARGV[0] eq '-png') {
        $output = "png";
    } elsif ($ARGV[0] eq '-non-transparent') {
        $png_transparent = 0;
    } elsif ($ARGV[0] eq '-eps') {
        $output = "eps";
    } elsif ($ARGV[0] eq '-gnuplot-path') {
        die $usage if ($#ARGV <= 0);
        shift;
        $gnuplot_path = $ARGV[0];
    } elsif ($ARGV[0] eq '-fig2dev-path') {
        die $usage if ($#ARGV <= 0);
        shift;
        $fig2dev_path = $ARGV[0];
    } else {
        $graph = $ARGV[0];
        shift;
        last;
    }
    shift;
}
die $usage if ($#ARGV >= 0 || $graph eq "");
open(IN, "< $graph") || die "Couldn't open $graph";

# support for clusters and stacked
$stacked = 0;
$stackcount = 1;
$clustercount = 1;
$plotcount = 1; # multi datasets to cycle colors through
$dataset = 0;
$table = 0;
# leave $column undefined by default

# support for clusters of stacked
$stackcluster = 0;
$groupcount = 1;
$grouplabels = 0;
$groupset = 0;

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

$datascale = 1;
$datasub = 0;
$percent = 0;
$base1 = 0;
$yformat = "%.0f";

$extra_gnuplot_cmds = "";

# if still 0 later will be initialized to default
$use_legend = 1;
$legendx = 0;
$legendy = 0;

# use patterns instead of solid fills?
$patterns = 0;
# there are only 22 patterns that fig supports
$max_patterns = 22;

$custom_colors = 0;
$color_per_datum = 0;

# fig depth: leave enough room for many datasets
# (for stacked bars we subtract 2 for each)
# but max gnuplot terminal depth for fig is 99!
$legend_depth = 100;
$plot_depth = 98;

$add_commas = 1;

$font_face = $fig_font{'Default'};
$font_size = 10.0;
# let user have some control over font bounding box heuristic
$bbfudge = 1.0;

# yerrorbar support
$yerrorbars = 0;

while (<IN>) {
    next if (/^\#/ || /^\s*$/);
    # line w/ = is a control line (except =>)
    if (/=[^>]/) {
        if (/^=cluster(.)/) {
            $splitby = $1;
            s/=cluster$splitby//;
            chop;
            @legend = split($splitby, $_);
            $clustercount = $#legend + 1;
            $plotcount = $clustercount;
        } elsif (/^=stacked(.)/) {
            $splitby = $1;
            s/=stacked$splitby//;
            chop;
            @legend = split($splitby, $_);
            $stackcount = $#legend + 1;
            $plotcount = $stackcount;
            $stacked = 1;
            # reverse order of datasets
            $dataset = $#legend;
        } elsif (/^=stackcluster(.)/) {
            $splitby = $1;
            s/=stackcluster$splitby//;
            chop;
            @legend = split($splitby, $_);
            $stackcount = $#legend + 1;
            $plotcount = $stackcount;
            $stackcluster = 1;
            # reverse order of datasets
            $dataset = $#legend;
            # FIXME: two types of means: for stacked (mean bar per cluster)
            # or for cluster (cluster of stacked bars)
            $use_mean = 0;
        } elsif (/^multimulti=(.*)/) {
            if (!($groupset == 0 && $dataset == $stackcount-1)) {
                $groupset++;
                $dataset = $stackcount-1;
            }
            $groupname[$groupset] = $1;
            $grouplabels = 1 if ($groupname[$groupset] ne "");
        } elsif (/^=multi/) {
            die "Neither cluster nor stacked specified for multiple dataset"
                if ($plotcount == 1);
            if ($stacked || $stackcluster) {
                # reverse order of datasets
                $dataset--;
            } else {
                $dataset++;
            }
        } elsif (/^=patterns/) {
            $patterns = 1;
        } elsif (/^=color_per_datum/) {
            $color_per_datum = 1;
        } elsif (/^colors=(.*)/) {
            $custom_colors = 1;
            @custom_color = split(',', $1);
        } elsif (/^=table/) {
            $table = 1;
            if (/^=table(.)/) {
                $table_splitby = $1;
            } else {
                $table_splitby = ' ';
            }
        } elsif (/^column=(\S+)/) {
            $column = $1;
        } elsif (/^=base1/) {
            $base1 = 1;
        } elsif (/^=invert/) {
            $invert = 1;
        } elsif (/^datascale=(.*)/) {
            $datascale = $1;
        } elsif (/^datasub=(.*)/) {
            $datasub = $1;
        } elsif (/^=percent/) {
            $percent = 1;
        } elsif (/^=sortbmarks/) {
            $sort = 1;
            $sortbmarks = 1;
        } elsif (/^=sort/) { # don't prevent match of =sortbmarks
            $sort = 1;
        } elsif (/^=arithmean/) {
            die "Stacked-clustered does not suport mean" if ($stackcluster);
            $use_mean = 1;
            $arithmean = 1;
        } elsif (/^=harmean/) {
            die "Stacked-clustered does not suport mean" if ($stackcluster);
            $use_mean = 1;
        } elsif (/^meanlabel=(.*)$/) {
            $mean_label = $1;
        } elsif (/^min=([-\d\.]+)/) {
            $ymin = $1;
            $calc_min = 0;
        } elsif (/^max=([-\d\.]+)/) {
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
        } elsif (/^=nolegend/) {
            $use_legend = 0;
        } elsif (/^legendx=(\d+)/) {
            $legendx = $1;
        } elsif (/^legendy=(\d+)/) {
            $legendy = $1;
        } elsif (/^extraops=(.*)/) {
            $extra_gnuplot_cmds .= "$1\n";
        } elsif (/^=nocommas/) {
            $add_commas = 0;
        } elsif (/^font=(.+)/) {
            if (defined($fig_font{$1})) {
                $font_face = $fig_font{$1};
            } else {
                @known_fonts = keys(%fig_font);
                die "Unknown font \"$1\": known fonts are @known_fonts";
            }
        } elsif (/^fontsz=(.+)/) {
            $font_size = $1;
        } elsif (/^bbfudge=(.+)/) {
            $bbfudge = $1;
        } elsif (/^=yerrorbars/) {
            $table = 0;
            $yerrorbars = 1;
            if (/^=yerrorbars(.)/) {
                $yerrorbars_splitby = $1;
            } else {
                $yerrorbars_splitby = ' ';
            }
        } else {
            die "Unknown command $_\n";
        }
        next;
    }

    # compatibility checks
    die "Graphs of type stacked or stackcluster do not suport yerrorbars"
        if ($yerrorbars  && ($stacked || $stackcluster));

    # this line must have data on it!
    
    if ($table) {
        # table has to look like this, separated by $table_splitby (default ' '):
        # <bmark1> <dataset1> <dataset2> <dataset3> ...
        # <bmark2> <dataset1> <dataset2> <dataset3> ...
        # ...

        # perl split has a special case for literal ' ' to collapse adjacent
        # spaces
        if ($table_splitby eq ' ') {
            @table_entry = split(' ', $_);
        } else {
            @table_entry = split($table_splitby, $_);
        }
        if ($#table_entry != $plotcount) { # not +1 since bmark
            print STDERR "WARNING: table format error on line $_: found $#table_entry entries, expecting $plotcount entries\n";
        }
        # remove leading and trailing spaces, and escape quotes
        $table_entry[0] =~ s/^\s*//;
        $table_entry[0] =~ s/\s*$//;
        $table_entry[0] =~ s/\"/\\\"/g;
        $bmark = $table_entry[0];
        for ($i=1; $i<=$#table_entry; $i++) {
            $table_entry[$i] =~ s/^\s*//;
            $table_entry[$i] =~ s/\s*$//;
            if ($stacked || $stackcluster) {
                # reverse order of datasets
                $dataset = $stackcount-1 - ($i-1);
            } else {
                $dataset = $i-1;
            }
            $val = get_val($table_entry[$i], $dataset);
            if (($stacked || $stackcluster) && $dataset < $stackcount-1) {
                # need to add prev bar to stick above
                $entry{$groupset,$bmark,$dataset+1} =~ /([-\d\.eE]+)/;
                $val += $1;
            }
            if ($val ne '') {
                $entry{$groupset,$bmark,$dataset} = "$val";
            } # else, leave undefined
        }
        goto nextiter;
    }

    if ($yerrorbars) {
        # yerrorbars has to look like this, separated by $yerrorbars_splitby (default ' '):
        # <bmark1> <dataset1> <dataset2> <dataset3> ...
        # <bmark2> <dataset1> <dataset2> <dataset3> ...
        # ...

        # perl split has a special case for literal ' ' to collapse adjacent
        # spaces
        if ($yerrorbars_splitby eq ' ') {
            @yerrorbars_entry = split(' ', $_);
        } else {
            @yerrorbars_entry = split($yerrorbars_splitby, $_);
        }
        if ($#yerrorbars_entry != $plotcount) { # not +1 since bmark
            print STDERR "WARNING: yerrorbars format error on line $_: found $#yerrorbars_entry entries, expecting $plotcount entries\n";
        }
        # remove leading and trailing spaces, and escape quotes
        $yerrorbars_entry[0] =~ s/^\s*//;
        $yerrorbars_entry[0] =~ s/\s*$//;
        $yerrorbars_entry[0] =~ s/\"/\\\"/g;
        $bmark = $yerrorbars_entry[0];
        for ($i=1; $i<=$#yerrorbars_entry; $i++) {
            $yerrorbars_entry[$i] =~ s/^\s*//;
            $yerrorbars_entry[$i] =~ s/\s*$//;
            if ($stacked || $stackcluster) {
                # reverse order of datasets
                $dataset = $stackcount-1 - ($i-1);
            } else {
                $dataset = $i-1;
            }
            $val = get_val($yerrorbars_entry[$i], $dataset);
            if (($stacked || $stackcluster) && $dataset < $stackcount-1) {
                # need to add prev bar to stick above
                $yerror_entry{$groupset,$bmark,$dataset+1} =~ /([-\d\.eE]+)/;
                $val += $1;
            }
            if ($val ne '') {
                $yerror_entry{$groupset,$bmark,$dataset} = "$val";
            } # else, leave undefined
        }
        goto nextiter;
    }

    # support the column= feature
    if (defined($column)) {
        # only support separation by spaces
        my @columns = split(' ', $_);
        $bmark = $columns[0];
        if ($column eq "last") {
            $val_string = $columns[$#columns];
        } else {
            die "Column $column out of bounds" if ($column > 1 + $#columns);
            $val_string = $columns[$column - 1];
        }
    } elsif (/^\s*(.+)\s+([-\d\.]+)\s*$/) {
        $bmark = $1;
        $val_string = $2;
        # remove leading spaces, and escape quotes
        $bmark =~ s/\s+$//;
        $bmark =~ s/\"/\\\"/g;
    } else {
        if (/\S+/) {
            print STDERR "WARNING: unexpected, unknown-format line $_";
        }
        next;
    }

    # strip out trailing %
    $val_string =~ s/%$//;
    if ($val_string !~ /^[-\d\.]+$/) {
        print STDERR "WARNING: non-numeric value \"$val_string\" for $bmark\n";
    }

    $val = get_val($val_string, $dataset);
    if (($stacked || $stackcluster) && $dataset < $stackcount-1) {
        # need to add prev bar to stick above
        # remember that we're walking backward
        $entry{$groupset,$bmark,$dataset+1} =~ /([-\d\.]+)/;
        $val += $1;
    }
    $entry{$groupset,$bmark,$dataset} = "$val";

  nextiter:
    if (!defined($names{$bmark})) {
        $names{$bmark} = $bmark;
        $order{$bmark} = $bmarks_seen++;
    }
}
close(IN);

###########################################################################
###########################################################################

$groupcount = $groupset + 1;

$clustercount = $bmarks_seen if ($stackcluster);

# FIXME: absolute boxwidth doesn't work well w/ logarithmic axes
$boxwidth=0.5;
if (!$stacked) {
    if ($clustercount == 2) {
        $boxwidth=0.3;
    } elsif ($clustercount == 3) {
        $boxwidth=0.26;
    } elsif ($clustercount == 4) {
        $boxwidth=0.2;
    } elsif ($clustercount == 5) {
        $boxwidth=0.16;
    } elsif ($clustercount == 6) {
        $boxwidth=0.12;
    } elsif ($clustercount == 7) {
        $boxwidth=0.11;
    } elsif ($clustercount == 8) {
        $boxwidth=0.09;
    } elsif ($clustercount >= 9) {
        $boxwidth=0.75/$clustercount;
    }
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
        if ($stacked || $stackcluster) {
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
    if ($stacked || $stackcluster) {
        for ($i=$plotcount-2; $i>=0; $i--) {
            # need to add prev bar to stick above
            # since reversed, prev is +1
            $harmean[$i] += $harmean[$i+1];
        }
    }
}

# x-axis labels
$xtics = "";
for ($g=0; $g<$groupcount; $g++) {
    $item = 1;
    foreach $b (@sorted) {
        if ($stackcluster) {
            $xval = get_xval($g, $item, $item);
        } else {
            $xval = $item;
        }
        if ($usexlabels) {
            $label = $b;
        } else {
            if ($stackcluster && $grouplabels && $item==&ceil($bmarks_seen/2)) {
                $label = $groupname[$g];
            } else {
                $label = "";
            }
        }
        $xtics .= "\"$label\" $xval, ";
        $item++;
    }
    if ($stackcluster && $grouplabels && $usexlabels) {
        $label = sprintf("set label \"%s\" at %d,0 center",
                         $groupname[$g], $g+1);
        $extra_gnuplot_cmds .= "$label\n";
    }
}
# For stackcluster we need to find the y value for the group labels
# so we look where gnuplot put the x label.  If the user specifies none,
# we add our own.
$unique_xlabel = "UNIQUEVALUETOLOOKFOR";
if ($stackcluster && $xlabel eq "") {
    $xlabel = $unique_xlabel;
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
        $xtics .= "\"\" $item, ";
    }
    if ($stackcluster) {
        $xval = get_xval($g, $item, $item);
    } else {
        $xval = $item;
    }
    $xtics .= "\"$mean_label\" $xval, ";
    $item++;
}
$xmax = &ceil($xval);

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

$colorcount = $plotcount; # re-set for color_per_datum below
if ($patterns) {
    $colorcount = $max_patterns if ($color_per_datum);
    for ($i=0; $i<$colorcount; $i++) {
        # cycle around at max
        $fillstyle[$i] = 41 + ($i % $max_patterns);
        # FIXME: could combine patterns and colors, we don't bother to support that
        $fillcolor[$i] = 7;
    }
} elsif ($use_colors) {
    $colorcount = $num_nongrayscale if ($color_per_datum);
    # colors: all solid fill
    for ($i=0; $i<$colorcount; $i++) {
        $fillstyle[$i]=20;
    }
    if ($custom_colors) {
        $colorcount = $#custom_color+1 if ($color_per_datum);
        for ($i=0; $i<$colorcount; $i++) {
            $fillcolor[$i]=$colornm{$custom_color[$i]};
        }
    } else {
        # color schemes that I tested as providing good contrast when
        # printed on a non-color printer.
        if ($yerrorbars && $colorcount >= 5) {
            # for yerrorbars we avoid using black since the errorbars are black.
            # a hack where we take the next-highest set and then remove black:
            $colorcount++;
        }
        if ($colorcount == 1) {
            $fillcolor[0]=$fig_light_blue;
        } elsif ($colorcount == 2) {
            $fillcolor[0]=$fig_med_blue;
            $fillcolor[1]=$fig_yellow;
        } elsif ($colorcount == 3) {
            $fillcolor[0]=$fig_med_blue;
            $fillcolor[1]=$fig_yellow;
            $fillcolor[2]=$fig_red;
        } elsif ($colorcount == 4) {
            $fillcolor[0]=$fig_med_blue;
            $fillcolor[1]=$fig_yellow;
            $fillcolor[2]=$fig_dark_green;
            $fillcolor[3]=$fig_red;
        } elsif ($colorcount == 5) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_yellow;
            $fillcolor[2]=$fig_red;
            $fillcolor[3]=$fig_med_blue;
            $fillcolor[4]=$fig_grey;
        } elsif ($colorcount == 6) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_yellow;
            $fillcolor[3]=$fig_red;
            $fillcolor[4]=$fig_med_blue;
            $fillcolor[5]=$fig_grey;
        } elsif ($colorcount == 7) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_yellow;
            $fillcolor[3]=$fig_red;
            $fillcolor[4]=$fig_dark_blue;
            $fillcolor[5]=$fig_cyan;
            $fillcolor[6]=$fig_grey;
        } elsif ($colorcount == 8) {
            $fillcolor[0]=$fig_black;
            $fillcolor[1]=$fig_dark_green;
            $fillcolor[2]=$fig_yellow;
            $fillcolor[3]=$fig_red;
            $fillcolor[4]=$fig_magenta;
            $fillcolor[5]=$fig_dark_blue;
            $fillcolor[6]=$fig_cyan;
            $fillcolor[7]=$fig_grey;
        } elsif ($colorcount == 9) {
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
            for ($i=0; $i<$colorcount; $i++) {
                # FIXME: set to programmatic spread of custom colors
                # for now we simply re-use our set of colors
                $fillcolor[$i]=$basefigcolor + ($i % $num_nongrayscale);
            }
        }
        if ($yerrorbars) {
            if ($colorcount >= 5) {
                # a hack where we take the next-highest set and remove black,
                # which we assume to be first
                die "Internal color assumption error"
                    if ($colorcount == 5 || $fillcolor[0] != $fig_black);
                $colorcount--;
                for ($i=0; $i<$colorcount; $i++) {
                    $fillcolor[$i] = $fillcolor[$i+1];
                }
            }
            # double-check we have no conflicts w/ the black error bars
            for ($i=0; $i<$colorcount; $i++) {
                die "Internal color assumption error"
                    if ($fillcolor[i] == $fig_black);
            }
        }
    }
    if ($stacked || $stackcluster) {
        # reverse order for stacked since we think of bottom as "first"
        for ($i=0; $i<$colorcount; $i++) {
            $tempcolor[$i]=$fillcolor[$i];
        }
        for ($i=0; $i<$colorcount; $i++) {
            $fillcolor[$i]=$tempcolor[$colorcount-$i-1];
        }
    }
} else {
    $colorcount = 10 if ($color_per_datum);
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
    for ($i=0; $i<$colorcount; $i++) {
        if ($stacked || $stackcluster) {
            # reverse order for stacked since we think of bottom as "first"
            $fillstyle[$i]=$bwfill[$colorcount-$i-1];
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
    $pid = open2(\*FIG, \*GNUPLOT, "$gnuplot_path") || die "Couldn't open2 gnuplot\n";
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
for ($g=0; $g<$groupcount; $g++) {
    for ($i=0; $i<$plotcount; $i++) {
        if ($i != 0 || $g != 0) {
            printf GNUPLOT ", ";
        }
        if ($patterns) {
            printf GNUPLOT "'-' notitle with boxes fs pattern %d", ($i % $max_patterns);
        } else {
            printf GNUPLOT "'-' notitle with boxes %d", $i+3;
        }
    }
}

if ($yerrorbars) {
    for ($g=0; $g<$groupcount; $g++) {
        for ($i=0; $i<$plotcount; $i++) {
            print GNUPLOT ", '-' notitle with yerrorbars 0";
        }
    }
}
print GNUPLOT "\n";
for ($g=0; $g<$groupcount; $g++) {
    for ($i=0; $i<$plotcount; $i++) {
        $line = 1;
        foreach $b (@sorted) {
            # support missing values in some datasets
            if (defined($entry{$g,$b,$i})) {
                $xval = get_xval($g, $i, $line);
                print GNUPLOT "$xval, $entry{$g,$b,$i}\n";
                $line++;
            } else {
                print STDERR "WARNING: missing value for $b in dataset $i\n";
                $line++;
            }
        }
        # skip over missing values to put harmean at end
        $line = $xmax - 1;
        if ($use_mean) {
            $xval = get_xval($g, $i, $line);
            print GNUPLOT "$xval, $harmean[$i]\n";
        }
        # an e separates each dataset
        print GNUPLOT "e\n";
    }
}
if ($yerrorbars) {
    for ($g=0; $g<$groupcount; $g++) {
        for ($i=0; $i<$plotcount; $i++) {
            $line = 1; 
            foreach $b (@sorted) {
                # support missing values in some datasets
                if (defined($entry{$g,$b,$i})) {
                    $xval = get_xval($g, $i, $line);
                    print GNUPLOT "$xval, $entry{$g,$b,$i}, $yerror_entry{$g,$b,$i}\n";
                    $line++;
                } else {
                    print STDERR "WARNING: missing value for $b in dataset $i\n";
                    $line++;
                }
            }
            # skip over missing values to put harmean at end
            $line = $xmax - 1;
            # an e separates each dataset
            print GNUPLOT "e\n";
        }
    }
}

close(GNUPLOT);

exit if ($debug_seegnuplot);

###########################################################################
###########################################################################

# now process the resulting figure
if ($output eq "fig") {
    $fig2dev = "cat";
} elsif ($output eq "eps") {
    $fig2dev = "$fig2dev_path -L eps -n \"$title\"";
} elsif ($output eq "pdf") {
    $fig2dev = "$fig2dev_path -L pdf -n \"$title\"";
} elsif ($output eq "png") {
    $fig2dev = "$fig2dev_path -L png -m 2";
    $fig2dev .= " | convert -transparent white - - " if ($png_transparent);
} else {
    die "Error: unknown output type $output\n";
}

$debug_seefig = 0;
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
# flag (or-ed together): 1=rigid, 2=special, 4=PS fonts, 8=hidden
# boundy and boundx: should be calculated from X::TextExtents but
#   users won't have X11::Lib installed so we use heuristics:
#  boundy: 10-pt default Times font: 75 + 30 above + 30 below
#          Helvetica is 90 base
#          FIXME: what about Courier?
#   => 135 if both above and below line chars present, 105 if only above, etc.
#  boundx: 10-pt default latex font: M=150, m=120, i=45, ave lowercase=72, ave uppercase=104
#   that's ave over alphabet, a capitalized word seems to be closer to 69 ave
#   if have bounds wrong then fig2dev will get eps bounding box wrong
# font size: y increases by 15 per 2-point font increase

if ($stackcluster && $grouplabels && $usexlabels) {
    # For stackcluster we need to find the y value for the group labels
    # FIXME: we assume an ordering: xlabel followed by each group label, in
    # that order, else we'll mess up and need multiple passes here!
    $grouplabel_y = 0;
    $groupset = 0;
}

$set = -1;
$set_raw = "";
while (<FIG>) {
    if ($debug_seefig_unmod) {
        print FIG2DEV $_;
        next;
    }

    # Insert our custom fig colors
    s|^1200 2$|1200 2
$figcolorins|;

    # Convert rectangles with line style N to filled rectangles.
    # We put them at depth $plot_depth.
    # Look for '^2 1 ... 5' to indicate a full box w/ 5 points.
    if (/^2 1 \S+ \S+ (\S+) \1 $plot_depth 0 -1(\s+\S+){6}\s+5/) {
        # Rather than hardcode the styles that gnuplot uses for fig (which has
        # changed), we assume the plots are in sequential order.
        # We assume that the coordinates are all on the subsequent line,
        # so that we can use the entire first line as our key (else we should pull
        # out at least line style, line color, and dash gap).
        $cur_raw = $_;
        # We need to not convert the plot outline, so we assume that
        # the first plot box never has a fill of 0 or -1.
        $cur_fill = $1;
        if ($set == -1 && ($cur_fill == 0 || $cur_fill == -1)) {
            # ignore: it's the plot outline
        } else {
            if ($cur_raw ne $set_raw || $set == -1) {
                $set++;
                $set_raw = $cur_raw;
                if ($set < $plotcount) {
                    # For repeats, match the entire line
                    $xlate{$_} = $set;
                }
            }
            # There are some polylines past the last plot
            if ($set < $plotcount) {
                $color_idx = $color_per_datum ? ($itemcount++ % ($#fillcolor+1)) :
                    $set;
                s|^2 1 \S+ \S+ (\S+) \1 $plot_depth 0 -1 +([0-9]+).000|2 1 0 1 -1 $fillcolor[$color_idx] $depth[$set] 0 $fillstyle[$color_idx]     0.000|;
            } elsif (defined($xlate{$_})) {
                $repeat = $xlate{$_};
                $color_idx = $color_per_datum ? ($itemcount++ % ($#fillcolor+1)) :
                    $repeat;
                # Handle later repeats, like for cluster of stacked
                s|^2 1 \S+ \S+ (\S+) \1 $plot_depth 0 -1 +([0-9]+).000|2 1 0 1 -1 $fillcolor[$color_idx] $depth[$repeat] 0 $fillstyle[$color_idx]     0.000|;
            }
        }
    }

    if ($yerrorbars) {
        s|^2 1 (\S+) 1 0 0 $plot_depth 0 -1     4.000 0 (\S+) 0 0 0 2|2 1 $1 1 0 0 10 0 -1     0.000 0 $2 0 0 0 2|;
    }

    if ($stackcluster && $grouplabels && $usexlabels) {
        if (/^4\s+.*\s+(\d+)\s+$xlabel\\001/) {
            $grouplabel_y = $1;
            if ($xlabel eq $unique_xlabel) {
                s/^.*$//; # remove
            } else {
                # HACK to push below
                $newy = $grouplabel_y + 160 + &font_bb_diff_y($font_size-1);
                s/(\s+)\d+(\s+$xlabel\\001)/\1$newy\2/;
            }
        }
        if (/^4\s+.*$groupname[$groupset]\\001/) {
            s/(\s+)\d+(\s+$groupname[$groupset]\\001)/\1$grouplabel_y\2/;
            $groupset++;
        }
    }

    # Custom fonts
    if (/^(4\s+\d+\s+[-\d]+\s+\d+\s+[-\d]+)\s+[-\d]+\s+([\d\.]+)\s+([\d\.]+)\s+(\d+)\s+([\d\.]+)\s+([\d\.]+)(\s+[-\d\.]+\s+[-\d\.]+) (.*)\\001/) {
        $prefix = $1;
        $oldsz = $2;
        $orient = $3;
        $flags = $4;
        $szy = $5;
        $szx = $6;
        $text = $8; # $7 is position
        $textlen = length($text);
        $newy = $szy + &font_bb_diff_y($oldsz);
        $newx = $szx + $textlen * &font_bb_diff_x($oldsz);
        s|^$prefix\s+[-\d]+\s+$oldsz\s+$orient\s+$flags\s+$szy\s+$szx|$prefix $font_face $font_size $orient $flags $newy $newx|;
    } elsif (/^4/) {
        print STDERR "WARNING: unknown font element $_";
    }

    if ($add_commas) {
        # Add commas between 3 digits for text in thousands or millions
        s|^4 (.*\d)(\d{3}\S*)\\001$|4 $1,$2\\001|; 
        s|^4 (.*\d)(\d{3}),(\d{3}\S*)\\001$|4 $1,$2,$3\\001|; 
    }

    # With gnuplot 4.2, I get a red x axis in some plots w/ negative values (but
    # not all: FIXME: why?): I'm turning it to black
    s|^2 1 0 1 4 4 $plot_depth|2 1 0 1 0 0 $plot_depth|;

    print FIG2DEV $_;
}

# add the legend
if ($use_legend && $plotcount > 1) {
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
        if ($stacked || $stackcluster) {
            $legidx = $plotcount - 1 - $i;
        } else {
            $legidx = $i;
        }
        # 9-point so legend not so big
        # estimate text bounds (important if legend on right to get bounding box)
        # use width*70, and assume full height 135 (see fig notes above)
        $leglen = length $legend[$legidx];
        printf FIG2DEV
"4 0 0 %d 0 %d %d 0.0000 4 %d %d %d %d %s\\001
", $legend_depth, $font_face, $font_size - 1,
135 + &font_bb_diff_y(9), $leglen * (70 + &font_bb_diff_x(9)),
$lx+225, $ly+186+157*$i, $legend[$legidx];
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
    if ($datasub != 0) {
        $val -= $datasub;
    }
    if ($datascale != 1) {
        $val *= $datascale;
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

sub get_xval($, $, $)
{
    # item ranges from 0..plotcount-1
    my ($gset, $dset, $item) = @_;
    my $xvalue;
    if ($stacked || $clustercount == 1) {
        $xvalue = $item;
    } elsif ($stackcluster) {
        $xvalue = &cluster_xval($gset+1, $item-1);
    } else {
        $xvalue = &cluster_xval($item, $dset);
    }
    return $xvalue;
}

sub cluster_xval($, $)
{
    my ($base, $dset) = @_;
    if ($clustercount % 2 == 0) {
        # we want the sequence ...,-5/2,-3/2,-1/2,1/2,3/2,5/2,...
        $xvalue = $base + $boxwidth/2 * (2*$dset-($clustercount-1));
    } else {
        # we want the sequence ...,-2,-1,0,1,2,,...
        $xvalue = $base + $boxwidth * ($dset - ($clustercount-1)/2);
    }
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

sub font_bb_diff_y($)
{
    my ($oldsz) = @_;
    # This is an inadequate hack: font bounding boxes vary
    # by 15 per 2-point font size change for smaller chars, but up
    # to 30 per 2-point font size for larger chars.  We try to use a
    # single value here for all chars.  Overestimating is better than under.
    # And of course any error accumulates over larger sizes.
    # The real way is to call XTextExtents.
    $diff = ($font_size - $oldsz)*15*$bbfudge;
    if ($font_face >= $fig_font{'Helvetica'} &&
        $font_face <= $fig_font{'Helvetica Narrow Bold Oblique'}) {
        $diff += 15*$bbfudge; # extra height for Helvetica
    }
    return &ceil($diff);
}

sub font_bb_diff_x($)
{
    my ($oldsz) = @_;
    # This is an inadequate hack: font bounding boxes vary
    # by 15 per 2-point font size change for smaller chars, but up
    # to 30 per 2-point font size for larger chars.  We try to use a
    # single value here for all chars.  Overestimating is better than under.
    # And of course any error accumulates over larger sizes.
    # The real way is to call XTextExtents.
    return &ceil(($font_size - $oldsz)*10*$bbfudge);
}

sub ceil {
    my ($n) = @_;
    return int($n + ($n <=> 0));
}
