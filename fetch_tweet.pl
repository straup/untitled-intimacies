#!/usr/bin/env perl
# -*-cperl-*-

# usage: fetch_tweet.pl -c /yer/ini.cfg -o tw.html -u http://twitter.com/you/status/9999999

use strict;

use Getopt::Std;
use Config::Simple;

use WWW::Mechanize;
use IO::AtomicFile;

{
        &main();
        exit;
}

sub main {

        my %opts = ();
        getopts('c:o:u:', \%opts);

        my $cfg = Config::Simple->new($opts{'c'});

        #

        my $m = WWW::Mechanize->new();
        $m->get("http://www.twitter.com");

        my %login = ("session[username_or_email]"  => $cfg->param("twitter.username"),
                     "session[password]" => $cfg->param("twitter.password"));

        $m->submit_form(
                        form_number => 1,
                        fields    => \%login,
                        button    => ""
                       );

        my $r = $m->get($opts{'u'});

        if (! $r->is_success()){
                warn "failed to retrieve $opts{'u'} with error code: ". $r->code();
                return 0;
        }

        my $fh = IO::AtomicFile->open($opts{'o'}, "w");
        binmode $fh, ":utf8";

        $fh->print($r->decoded_content());
        $fh->close();

        return 1;
}
