#!/usr/bin/perl

use warnings;
use strict;

my @files = @ARGV;

print "<body bgcolor=\"#bbeeee\">\n";
foreach my $perf (@files) {
    my $img = $perf;
    $img =~ s/\.perf$/.png/;
    print "<p>$perf</p><table><tr>\n";
    print "<td><img src=\"$img\"></td><td>&nbsp;</td>\n";
    print "</tr></table>\n";
}
print "</body>\n";
