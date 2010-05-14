== Overview ==

Alrighty, here's a quick overview. This is a small script designed to
spider the Election results website published by COMELEC, where you
can find here: http://electionresults.ibanangayon.ph.

If you noticed, it's all in HTML with a combination of Flash charts
built with FusionChart (http://fusioncharts.com), which feeds from XML
data.

From the website, it's easy to imagine that a program wrote all the
HTML files, instead of a person hand-coding all the numbers. And from
that, if the files were produced by a software, then a pattern can be
determined and a reverse engineer to parse the data is possible.

== Requirements ==

The script is built using Ruby, and uses the following standard
libraries:

* fileutils
* benchmark
* parsedate
* rubygems

Which any vanilla Ruby installation has. Also i'm using Ruby 1.8.7,
which is now the default Ruby interpreter for the Ubuntu Lucid (10.4)
release. So you might want to use that as well.

Then for the gems, you'll need the following:

* nokogiri - sudo gem install nokogiri
* fastercsv - sudo gem install fastercsv
* typhoeus - sudo gem install typhoeus

These are publicly available gems which anyone can use. Some of these
gems require additional libraries installed in your system, like the
libxml2, libxslt, libcurl. When you install these gems, it will also
notify you either with a message or a horrofic fatal error, if you
don't have these libraries.

== Usage ==

You will probably need a mirror of the entire site. I didn't designed
the parsing with on-demand downloading. I believe that is just going
to take forever to finish.

Anyway, if you don't have the entire site, don't worry, there's
actually no need to have anymore, though having it, saves you the time
from downloading.

== 3 types of scripts ==

There are 3 kinds of scripts in this package.

*bin/parse_clusters*

This is used to parse the HTML files to produce the list of clusters
and their heirarchy in the region.

Sample execution:

# bin/parse_clusters electionresults.ibanangayon.ph/ var/parsed_clusters.csv

*bin/download_clusters*

If you have an already parsed clusters, like the one that comes with
this package, and you don't have a mirror, you can use this script to
download the files. This script also supports incremental downloads.

It downloads 100 (configurable) urls at the same time, per
batch. Checks if the files were modified since last run and only
download updated ones.

This script *requires* a parsed_cluster.csv file.

Sample execution:

# bin/download_clusters electionresults.ibanangayon.ph/ var/parsed_clusters.csv 1

1 here signifies the batch. Just in case you want to start downloading
in the middle of the entire list. It's optional. If it's not
specified, it will start with batch no. 1.

*bin/parse_positions*

This is used to parse the HTML files and produce the list of positions
per clusters, their candidates and their votes. This scripts create
two kinds of files, the all_positions.csv and
all_positions_candidates.csv file. the all_positions.csv file contains
the list of positions per cluster and their position title. The
all_positions_candidates.csv file contains the clusters, position_id,
candidate and vote count data.

This script *requires* a parsed_cluster.csv file.

Sample execution:

# bin/parse_positions electionresults.ibanangayon.ph/ \
                      var/parsed_clusters.csv \
                      var/all_postions.csv \
                      var/all_positions_candidates.csv
