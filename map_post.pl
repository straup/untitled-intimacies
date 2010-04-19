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

{
        &main();
        exit;
}

sub main {

    	# FIX ME: use Pod::Usage

        my %opts = ();
        getopts('c:u:l:g:z:p:P:i:h:w:', \%opts);

        my $cfg = Config::Simple->new($opts{'c'});

        #
        # Hello world?
        #

        my $tmp_crp = &mk_crop($cfg, \%opts);

        if (! -f $tmp_crp){
            return 0;
        }

        #
        # Some details...
        #

        my ($lat, $lon) = split(",", $opts{'l'});

        $lat = trim($lat);
        $lon = trim($lon);

        my ($w, $h) = imgsize($tmp_crp);

        my $zoom = $opts{'z'} || 14;

        #
        # Hello, ModestMaps
        #

        my $height = $opts{'h'} || 1024;
        my $width = $opts{'w'} || 1024;

        my %args = (
            'provider' => 'YAHOO_AERIAL',
            'method' => 'center',
            'latitude' => $lat, 
            'longitude' => $lon,
            'zoom' => $zoom,
            'height' => $height,
            'width' => $width,
            'filter' => 'atkinson',
            'bleed' => 1,
            'noshadow' => 1,
            'marker' => "twitter,$lat,$lon,$w,$h,file://$tmp_crp",
        );

        print "map post\n";

        print Dumper(\%args);

        my $mm = Net::ModestMaps->new();
        my $data = $mm->draw(\%args);
        
        if (! -f $data->{'path'}){
            warn "failed to generate a (modest) map!";
            return 0;
        }

        # use Data::Dumper;
        # print Dumper($data);
        # return;

        #
        # Now post to Flickr
        #

        print "post map $data->{'path'}\n";

        my %fl_args = ('key' => $cfg->param("flickr.api_key"),
                       'secret' => $cfg->param("flickr.api_secret"));

        #
        # FIX ME: N:F:API should just wrap this...
        #

        my $ua = Flickr::Upload->new(\%fl_args);

        my ($pub, $fr, $fa) = &photo_perms($cfg, \%opts);

        my $tw_id = post_id(\%opts);

        my $id = $ua->upload('photo' => $data->{'path'},
                             'auth_token' => $cfg->param("flickr.auth_token"),
                             'title' => "Untitled Intimacy #$tw_id",
                             'tags' => 'twitter modestmaps',
                             'is_public' => $pub,
                             'is_friend' => $fr,
                             'is_family' => $fa,
            );

        print "FLICKR ID $id\n";

        print "geotag post: $lat, $lon\n";

        my $fl = Net::Flickr::API->new($cfg);

        $fl->api_call({'method' => 'flickr.photos.geo.setLocation',
                       'args' => {'lat' => $lat, 'lon' => $lon, 'photo_id' => $id}});

        my ($gpub, $gcon, $gfr, $gfa) = &geo_perms($cfg, \%opts);
        print "set geo perms: $gpub, $gcon, $gfr, $gfr\n";

        $fl->api_call({'method' => 'flickr.photos.geo.setPerms',
                       'args' => {'is_public' => $gpub, 'is_friend' => $gfr, 'is_family' => $gfa, 'is_contact' => $gcon, 'photo_id' => $id}});


        #

        my $context = $opts{'g'};

        print "set context : $context\n";

        if ($context){
            $fl->api_call({'method' => 'flickr.photos.geo.setContext',
                           'args' => {'context' => $context, 'photo_id' => $id}});
        }

        unlink($tmp_crp);
        unlink($data->{'path'});

        return;
}


sub trim {
    my $str = shift;
    $str =~ s/^\s+//g;
    $str =~ s/\s+$//g;
    return $str;
}

sub mk_crop {
    my $cfg = shift;
    my $opts = shift;

    my $tw_url = $opts->{'u'};

    #
    # In the event of a screenshot or something like it...
    #

    if (-f $tw_url){
        return $tw_url;
    }

    my $tw_screenname = $cfg->param("twitter.screenname");
    my $tw_username = $cfg->param("twitter.username");
    my $tw_password = $cfg->param("twitter.password");
    
    my $wkpython = $cfg->param("bin.webkit2png_python");

    my $prog_dir = dirname($0);
    my $webkit2png = File::Spec->catfile($prog_dir, "webkit2png.py");
    my $fetch =  File::Spec->catfile($prog_dir, "fetch_tweet.pl");
    my $crop =  File::Spec->catfile($prog_dir, "crop_tweet.py");
    
    my $tmp = File::Temp::tempdir();

    my $tw = "tw-" . time();
    my $tmp_nam = File::Spec->catfile($tmp, $tw);
    my $tmp_png = File::Spec->catfile($tmp, "$tw-full.png");
    my $tmp_crp = File::Spec->catfile($tmp, "$tw-cr.png");
    my $tmp_html = File::Spec->catfile($tmp, "$tw.html");
    
    $tw_url =~ m!status/(\d+)/?!;
    my $tw_id = $1;
            
    # fetch the html

    print "fetch post #$tw_id\n";

    my $fetch_cmd = "$fetch -c $opts->{'c'} -o $tmp_html -u $tw_url";
    print $fetch_cmd . "\n";

    system($fetch_cmd);
    
    if (! -f $tmp_html){
        return 0;
    }

    # render the html

    print "render post\n";
    
    my $wk2png = "$wkpython $webkit2png --full -o $tmp_nam file://$tmp_html";
    system($wk2png);
            
    # crop the image
            
    my $cmd = "$crop $tmp_png $tmp_crp";
    print $cmd . "\n";
    
    system($cmd);

    # 

    unlink($tmp_png);
    unlink($tmp_html);

    return $tmp_crp;
}

sub post_id {
    my $opts = shift;

    if (my $id = $opts->{'i'}){
        return $id;
    }

    if ($opts->{'u'} =~ m!status/(\d+)/?!){
        return $1;
    }

    return time();
}

sub photo_perms {
    my $cfg = shift;
    my $opts = shift;

    if (! $opts->{'p'}){
        my $pub = $cfg->param("flickr.is_public") || 0;
        my $fr = $cfg->param("flickr.is_friend") || 0;
        my $fa = $cfg->param("flickr.is_family") || 0;
        
        return ($pub, $fr, $fa);
    }

    if ($opts->{'p'} =~ /^pri/){
        return (0, 0, 0);
    }

    if ($opts->{'p'} =~ /^pub/){
        return (1, 0, 0);
    }

    if ($opts->{'p'} =~ /^fr/){
        return (0, 1, 0);
    }

    if ($opts->{'p'} =~ /^fa/){
        return (0, 0, 1);
    }

    if ($opts->{'p'} =~ /^ff/){
        return (0, 1, 1);
    }

    return (0, 0, 0);
}

sub geo_perms {
    my $cfg = shift;
    my $opts = shift;

    if (! $opts->{'P'}){
        my $pub = $cfg->param("flickr.geo_is_public") || 0;
        my $con = $cfg->param("flickr.geo_is_contact") || 0;
        my $fr = $cfg->param("flickr.geo_is_friend") || 0;
        my $fa = $cfg->param("flickr.geo_is_family") || 0;
        
        return ($pub, $con, $fr, $fa);
    }

    if ($opts->{'P'} =~ /^pri/){
        return (0, 0, 0, 0);
    }

    if ($opts->{'P'} =~ /^pub/){
        return (1, 0, 0, 0);
    }

    if ($opts->{'P'} =~ /^con/){
        return (0, 1, 0, 0);
    }

    if ($opts->{'P'} =~ /^fr/){
        return (0, 0, 1, 0);
    }

    if ($opts->{'P'} =~ /^fa/){
        return (0, 0, 0, 1);
    }

    if ($opts->{'P'} =~ /^ff/){
        return (0, 0, 1, 1);
    }

    return (0, 0, 0, 0);
}

__END__
