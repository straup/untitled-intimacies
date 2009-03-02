#!/usr/bin/env perl

use strict;

use Getopt::Std;
use Config::Simple;

use File::Spec;
use File::Temp;
use File::Basename;

use Data::Dumper;

use Flickr::Upload;
use Net::Flickr::API;
use Net::ModestMaps;

use Image::Size;
use LWP::Simple;

{
        &main();
        exit;
}

sub main {

        my %opts = ();
        getopts('c:u:l:g:z:', \%opts);

        my $cfg = Config::Simple->new($opts{'c'});

        my $tw_screenname = $cfg->param("twitter.screenname");
        my $tw_username = $cfg->param("twitter.username");
        my $tw_password = $cfg->param("twitter.password");

        my $tw_url = $opts{'u'};

        my ($lat, $lon) = split(",", $opts{'l'});

        $lat = trim($lat);
        $lon = trim($lon);

        my $wkpython = $cfg->param("bin.webkit2png_python");

        my $prog_dir = dirname($0);
        my $webkit2png = File::Spec->catfile($prog_dir, "webkit2png.py");
        my $crop =  File::Spec->catfile($prog_dir, "crop_tweet.py");

        my $tmp = File::Temp::tempdir();

        my $tw = "tw-" . time();
        my $tmp_nam = File::Spec->catfile($tmp, $tw);
        my $tmp_png = File::Spec->catfile($tmp, "$tw-full.png");
        my $tmp_crp = File::Spec->catfile($tmp, "$tw-cr.png");
        my $tmp_html = File::Spec->catfile($tmp, "$tw.html");

        print "fetch post\n";
        
        my $tw_auth = "$tw_username:$tw_password";

        my $url = $tw_url;
        $url =~ s!^(http://)!$1$tw_auth\@!;

        $tw_url =~ m!status/(\d+)/?!;
        my $tw_id = $1;

        if (! getstore($url, $tmp_html)){
            warn "failed to retrieve '$tw_url', $!";
            return 0;
        }
        
        #
        
        print "render post\n";
        
        my $wk2png = "$wkpython $webkit2png --full -o $tmp_nam file://$tmp_html";
        
        system($wk2png);

        # 

        my $cmd = "$crop $tmp_png $tmp_crp";
        print $cmd . "\n";

        system($cmd);

        # 

        my ($w, $h) = imgsize($tmp_crp);

        my $zoom = $opts{'z'} || 14;

        my %args = (
            'provider' => 'MICROSOFT_AERIAL',
            'method' => 'center',
            'latitude' => $lat, 
            'longitude' => $lon,
            'zoom' => $zoom,
            'height' => 1024,
            'width' => 1024,
            'filter' => 'atkinson',
            'bleed' => 1,
            'marker' => "twitter,$lat,$lon,$w,$h,file://$tmp_crp",
        );

        print "map post\n";

        my $mm = Net::ModestMaps->new();
        my $data = $mm->draw(\%args);
        
        print Dumper($data);

        print "post map\n";

        my %fl_args = ('key' => $cfg->param("flickr.api_key"),
                       'secret' => $cfg->param("flickr.api_secret"));

        #
        # FIX ME: N:F:API should just wrap this...
        #

        my $ua = Flickr::Upload->new(\%fl_args);

        #
        # FIX ME: make me cli opts too...
        #

        my $pub = $cfg->param("flickr.is_public");
        my $fr = $cfg->param("flickr.is_friend");
        my $fa = $cfg->param("flickr.is_family");

        my $id = $ua->upload('photo' => $data->{'path'},
                             'auth_token' => $cfg->param("flickr.auth_token"),
                             'title' => "Untitled Intimacy #$tw_id",
                             'tags' => 'twitter modestmaps',
                             'is_public' => $pub,
                             'is_friend' => $fr,
                             'is_family' => $fa,
            );

        print "FLICKR ID $id\n";

        print "geotag post\n";

        my $fl = Net::Flickr::API->new($cfg);

        $fl->api_call({'method' => 'flickr.photos.geo.setLocation',
                       'args' => {'lat' => $lat, 'lon' => $lon, 'photo_id' => $id}});

        print "set perms\n";

        $fl->api_call({'method' => 'flickr.photos.geo.setPerms',
                       'args' => {'is_public' => 1, 'is_friend' => 0, 'is_family' => 0, 'is_contact' => 0, 'photo_id' => $id}});


        #

        my $context = $opts{'g'};

        print "set context : $context\n";

        if ($context){
            $fl->api_call({'method' => 'flickr.photos.geo.setContext',
                           'args' => {'context' => $context, 'photo_id' => $id}});
        }

        unlink($tmp_crp);
        unlink($tmp_png);
        unlink($tmp_html);
        unlink($data->{'path'});

        return;
}

sub trim {
    my $str = shift;
    $str =~ s/^\s+//g;
    $str =~ s/\s+$//g;
    return $str;
}

__END__
