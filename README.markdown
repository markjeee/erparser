# Overview

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

# Requirements

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

# Usage

You will probably need a mirror of the entire site. I didn't designed
the parsing with on-demand downloading. I believe that is just going
to take forever to finish.

Anyway, if you don't have the entire site, don't worry, there's
actually no need to have anymore, though having it, saves you the time
from downloading.

# Scripts

There are 3 kinds of scripts in this package.

*bin/parse_clusters*

This is used to parse the HTML files to produce the list of clusters
and their heirarchy in the region.

Sample execution:

       bin/parse_clusters electionresults.ibanangayon.ph/ \
                          var/parsed_clusters.csv

The mirror directory must exist and contains enough HTML files, like
the region, province, town and clusters HTML file to generate the
complete list of clusters. You don't need all the HTML files,
specially the HTML files per cluster with the vote data.

The second argument is the output CSV file.

*bin/download_clusters*

If you have an already parsed clusters, like the one that comes with
this package, and you don't have a mirror, you can use this script to
download the files. This script also supports incremental downloads.

It downloads 100 (configurable) urls at the same time, per
batch. Checks if the files were modified since last run and only
download updated ones.

This script *requires* a parsed_cluster.csv file.

Sample execution:

       bin/download_clusters electionresults.ibanangayon.ph/ \
                             var/parsed_clusters.csv 1

1 here signifies the batch. Just in case you want to start downloading
in the middle of the entire list. It's optional. If it's not
specified, it will start with batch no. 1.

The first argument points to the mirror directory where to check and
save the downloaded HTML files. And the second one, is the
parsed_clusters.csv. It should exists.

There's already parsed_clusters.csv file that comes with this repo,
you'll have to ungzip it before you can use it.

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

       bin/parse_positions electionresults.ibanangayon.ph/ \
                           var/parsed_clusters.csv \
                           var/all_postions.csv \
                           var/all_positions_candidates.csv

The first 2 arguments are inputs and should exist already. Depending
on how much files you have in your mirror, that's also the amount of
data that will be parsed. The last two files are the output files.

# What else?

I don't know. The codes published here are given as is. It's good if
you can take it, do something with it, improve it, modify it, do
whatever you want from it. You'll need to know Ruby, a bit of working
in the Unix world (since it uses fork, threading, curl, whatever kind
of approach). No plans to support other OSes, but you're free to hack
it to make it work. :)

Another thing, this package on purpose don't contain all the parsed
data. The generated data is very big. And i don't think i can put them
on github. It will probably just overwhelmed this repo.

If you encounter problems, the code is there. Go ahead and read it. If
you can't read the code, please have someone who know how to read the
code read for you, or better have someone who can use it, run it,
produce the data you need do it.

# Why do this?

With the first ever automated election, i never expected COMELEC will
release the results in a public medium. And since they did it, it was
almost automatic that having access to such amount of data is
interesting. I can imagine if more people have access to the data,
more people can view the data in different perspective. The data don't
change, it don't lie. It is as it is, and anyone who has some skills
related to parsing CSV, import it to a database (mySQL), can run
statistics against it, and see some trends. Instead of giving a few
people access to this data, how about the entire country, and everyone
who can type a code in a screen can do their own analysis. For
me, that's a bit exciting. For sometime, we always wonder how the
election turns out in a particular town, what's the vote
distribution. It would have been nice if the precinct level where kept
as they were, since we could have been looking at a more detailed
level of statistics.

Anyway, let's not get over excited ourselves. It took a while to parse
the data, and i'm happy i was able to do it. Hopefully, something good
will turn out from this.

For the paranoid, this doesn't change any of the election data. It
will create a copy of the data that is already published
publicly. Nothing it can do to change the data inside COMELEC's
servers.

