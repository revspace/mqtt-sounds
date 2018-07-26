#!/usr/bin/perl -w

use strict;
use warnings;
use 5.010;

use Time::HiRes qw(sleep time);
use LWP::Simple qw(get);
use Net::MQTT::Simple;
use Getopt::Long qw(GetOptions);
use List::Util qw(min);
use FindBin qw($RealBin);
chdir $RealBin;

my $mqtt = Net::MQTT::Simple->new("mosquitto.space.revspace.nl");
my @topics = ("revspace/state", "revspace/button/#", "revspace/bank/#");

my %players = (
    mp3 => ["mpv", "--volume=70", "--" ],
    wav => ["mpv", "--volume=70", "--" ],
);
my $squeeze_volume = 30;

sub set_squeeze_volume {
    my ($volume) = @_;
    get "http://squeezebox.space.revspace.nl:9000/Classic/status_header.html?p0=mixer&p1=volume&p2=$volume&player=be%3Ae0%3Ae6%3A04%3A46%3A38";
}

my $setpause = 'http://squeezebox.space.revspace.nl:9000/Classic/status_header.html?p0=pause&p1=1&player=be%3Ae0%3Ae6%3A04%3A46%3A38';
my $setplay = 'http://squeezebox.space.revspace.nl:9000/Classic/status_header.html?p0=pause&p1=0&player=be%3Ae0%3Ae6%3A04%3A46%3A38';

sub play_sounds {
    my ($path) = @_;

    ($path) = $path =~ m[^([\x20-\x7e]+)$] or do {
        warn "Ignoring non-ascii path.\n";
        return;
    };
    if (grep { $_ eq "." or $_ eq ".." } split m[/], $path) {
        warn "Ignoring path with relative element.\n";
        return;
    }

    my $extensions = join ",", keys %players;
    my $glob = "sounds/$path/*.{$extensions}";
    print "Looking for sounds in $glob... ";
    my @files = glob $glob or do {
        print "none found.\n";
        return;
    };
    print scalar(@files), " found.\n";

    my $file = $files[rand @files];
    
    my $player = $players{ (split /\./, $file)[-1] } or return;
    print "Playing $file using $player->[0]...\n";

    my $old_squeeze_volume = `perl squeeze-volume.pl`;
    set_squeeze_volume $squeeze_volume if $old_squeeze_volume > $squeeze_volume;
    system @$player, $file;
    set_squeeze_volume $old_squeeze_volume if $old_squeeze_volume > $squeeze_volume;
}

sub handle_mqtt {
    my ($topic, $message, $retain) = @_;
    print "Received $topic ($message)\n";
    if ($retain) {
        print "...but ignoring it because it's a retained message.\n";
        return;
    }

    play_sounds("$topic/$message") if length $message;
    play_sounds($topic);

    sleep 1;
}

$mqtt->run(map { $_ => \&handle_mqtt } @topics);
