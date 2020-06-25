# Copyright Mike Swierczek, 2019.
# Licensed under the Lesser GNU Public License version 2.1 or later.
# Please see the included LICENSE file for details.

# Hooray, Raku

constant $cpulimit = 'cpulimit';
constant $ffmpeg = 'ffmpeg';

sub USAGE() {
    print Q:c:to/EOH/;
Usage:
    option 1:
         raku reencoder.raku
         -- interactively prompts you for inputs
    option 2:
         raku reencoder.raku --srcdir=foo --destdir=bar --cpulimit=200 --name=Some_Movie
         -- reencodes all mkv files from directory 'foo' into directory 'bar',
            limiting CPU usage to 200 (two full cores), and putting Some_Movie into
            the film names.
         -- the cpulimit and name inputs are optional
EOH
}

multi sub MAIN {

    my Str $srcdirin = prompt "Please enter the name of the directory containing the files to re-encode: ";
    my Str $destdirin = prompt "Please enter the name of the directory for reencoded files: ";
    my Str $namein = prompt "Enter a file name pattern to apply to the files (ENTER for none): ";
    my Str $cpulimit-string = prompt "Enter a value for CPU limiting. 0 or ENTER for none: ";
    my Int $cpulimitin = $cpulimit-string ~~ /\d+/ ?? $cpulimit-string.Int !! 0;
    say "In the future, you could have invoked this with:";
    if ($cpulimitin > 0) {
        say "raku reencoder.raku --srcdir=$srcdirin --destdir=$destdirin --cpulimit=$cpulimit-string --name=$namein";
    } else {
        say "raku reencoder.raku --srcdir=$srcdirin --destdir=$destdirin --name=$namein";
    }
    run-process($srcdirin, $destdirin, $cpulimitin, $namein);
}

multi sub MAIN(Str :$srcdir! where $srcdir.chars > 0,
               Str :$destdir! where $destdir.chars > 0,
               Int :$cpulimit = 0,
               Str :$name = "") {
    run-process($srcdir, $destdir, $cpulimit, $name);
}


sub run-process(Str $srcdir, Str $destdir, Int $cpulimit, Str $name) {
    say "Checking prerequisites.";
    #say "srcdir $srcdir, destdir $destdir, cpulimit $cpulimit, name $name.";
    my Bool $using-cpulimit = $cpulimit > 0 && checkcpulimit();
    try {
        my $ffmpegcheck = run 'which', $ffmpeg, :out;
        for $ffmpegcheck.out.lines -> $line {
            say "Found $ffmpeg at '$line'.";
        }
        $ffmpegcheck.out.close();

        CATCH {
            when X::Proc::Unsuccessful {
                die "$ffmpeg is required for this script, please install it and try again.";
            }
        }
    }

    if (!$srcdir.IO.d) {
        die "Directory '$srcdir' does not exist.";
    }
    my @mkvs = $srcdir.IO.dir: test => /:i '.' mkv $/;
    if (@mkvs.elems == 0) {
       die "Could not find any mkv files in directory '$srcdir'.";
    }
    if ($name.chars > 0) {
       say "    Using video name '$name'.";
    }
    if ($destdir === $srcdir) {
       die "You cannot select the same input directory and output directory, the files will overwrite each other.";
    }
    if (!$destdir.IO.d) {
       mkdir $destdir;
    } else {
       my @previous-mkvs = $destdir.IO.dir: test => /:i '.' mkv $/;
       if (@previous-mkvs.elems > 0) {
            say "Found existing mkv files in output directory, stopping!";
            die "Please move the files in $destdir out of the way first.";
       }
    }
    my $cpulimiting-status = launchcpulimiting($using-cpulimit, $cpulimit);
    my @sortedmkvs = @mkvs.sort( - *.IO.s);
    my $main-video = @sortedmkvs.shift;
    my $main-output = $name.chars > 0 ?? $name.uc ~ '.mkv' !! $main-video.IO.basename;
    say "Handling main title.";
    wrap-encode($main-video, $destdir ~ "/" ~ $main-output);

    for @sortedmkvs -> $mkv {
        say "Handling title $mkv.";
        my $target = $name.chars > 0 ?? $name ~ '_' ~ $mkv.IO.basename !! $mkv.IO.basename;
        wrap-encode($mkv, $destdir ~ "/" ~ $target);
    }

    if ($cpulimiting-status.defined && $cpulimiting-status.started) {
        $cpulimiting-status.kill('QUIT');
        say "Closed the cpulimit process.";
    }
    say "Finished.";

}


sub checkcpulimit() returns Bool {
    try {
       my $cpulimitcheck = run 'which', $cpulimit, :out;
       for $cpulimitcheck.out.lines -> $line {
           say "Found $cpulimit '$line'.";
       }
       $cpulimitcheck.out.close();
       return True;
       CATCH {
           when X::Proc::Unsuccessful {
               say "Warning: $cpulimit not found. CPU rate limiting not possible.";
               say "You may wish to install $cpulimit.";
               .resume
           }
       }
    }
    False;
}

sub launchcpulimiting(Bool $found, Int $cpurate) returns Proc::Async {
    if ($found && $cpurate > 0) {
        try {
            my $cpulimiting = Proc::Async.new('cpulimit', '-l', $cpurate, '-e', $ffmpeg);
            $cpulimiting.stdout.tap(-> $buf { }); # ignored
            $cpulimiting.stderr.tap(-> $buf { }); # ignored
            say "    Starting the cpulimit process.";
            $cpulimiting.start;
            return $cpulimiting;
            CATCH {
                default { .Str.say; }
            }
        }
    }
    Nil
}

sub prettysize(Int $size) returns Str {
    my @portions = $size.polymod(1024, 1024, 1024);
    if (@portions[3] != 0) {
        sprintf "%d.%d gb", @portions[3], round(@portions[2] / 10);
    } elsif (@portions[2] != 0) {
        sprintf "%d mb", @portions[2];
    } else {
        # probably never happen, few media files are this small
        "$size bytes";
    }
}

# taken from https://blog.matatu.org/tailgrep
sub spinner() {
  <\ - | - / ->[$++ % 6]
}

sub wrap-encode(IO::Path $infile, Str $outfile) {
    say "    Reencoding $infile to $outfile.";
    my $start-time = DateTime.now;
    run-encode($infile, $outfile);
    my $finish-time = DateTime.now;
    say "        Finished, took " ~ ($finish-time - $start-time) ~ " s.";
    say "        Original file was " ~ prettysize($infile.s) ~ ", new file is " ~ prettysize($outfile.IO.s) ~ ".";
}


sub run-encode(IO::Path $infile, Str $outfile) {
    my $encode-cmd = Proc::Async.new('ffmpeg', '-i', $infile, '-c:a', 'copy', '-c:s', 'copy', '-c:v', 'libx265',
         '-crf', '19', '-preset', 'slow', '-max_muxing_queue_size', '9999', $outfile);
    react {
        whenever $encode-cmd.stdout -> $my-out {
             # $my-out intentionally ignored
             print spinner() ~ "\r";
        }
        whenever $encode-cmd.stderr -> $my-err {
             # $my-err intentionally ignored
             print spinner() ~ "\r";
        }
        whenever signal(SIGINT) {
             say "Received SIGINT, stopping.";
             exit;
        }
        whenever $encode-cmd.start {
             say "    Done encode.";
             done # gracefully jump from the react block
        }
   }
}


