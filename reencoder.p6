# Hooray, Perl6

constant $cpulimit = 'cpulimit';
constant $ffmpeg = 'ffmpeg';

sub MAIN {
    say "Checking prerequisites.";

    my Bool $have-cpulimit = checkcpulimit();

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

    my Str $to-encode-path = prompt "Please enter the name of the directory containing the files to re-encode: ";
    if (!$to-encode-path.IO.d) {
       die "Directory '$to-encode-path' does not exist.";
    }

    my Str $rename-pattern = prompt "Enter a file name pattern to apply to the files (ENTER for none): ";
    if ($rename-pattern.chars > 0) {
       say "    Using '$rename-pattern'.";
    }

    my @mkvs = $to-encode-path.IO.dir: test => /:i '.' mkv $/;
    if (@mkvs.elems == 0) {
       die "Could not find any mkv files in directory '$to-encode-path'.";
    }

    my Str $output-encoded-path = prompt "Please enter the name of the directory for reencoded files: ";
    if ($output-encoded-path === $to-encode-path) {
       die "You cannot select the same input directory and output directory, the files will overwrite each other.";
    }
    if (!$output-encoded-path.IO.d) {
       mkdir $output-encoded-path;
    } else {
       my @previous-mkvs = $output-encoded-path.IO.dir: test => /:i '.' mkv $/;
       if (@previous-mkvs.elems > 0) {
            say "Found existing mkv files in output directory, stopping!";
            die "Please move the files in $output-encoded-path out of the way first.";
       }
    }

    my $cpulimiting-status = launchcpulimiting($have-cpulimit);

    my @sortedmkvs = @mkvs.sort( - *.IO.s);
    my $main-video = @sortedmkvs.shift;
    my $main-output = $rename-pattern.chars > 0 ?? $rename-pattern.uc ~ '.mkv' !! $main-video.IO.basename;
    say "Handling main title.";
    wrap-encode($main-video, $output-encoded-path ~ "/" ~ $main-output);

    for @sortedmkvs -> $mkv {
        say "Handling title $mkv.";
        my $target = $rename-pattern.chars > 0 ?? $rename-pattern ~ '_' ~ $mkv.IO.basename !! $mkv.IO.basename;
        wrap-encode($mkv, $output-encoded-path ~ "/" ~ $target);
    }

    if ($cpulimiting-status.defined && $cpulimiting-status.started) {
        $cpulimiting-status.kill('QUIT');
        say "Closed the cpulimit process.";
    }
    say "Finished.";
} # end MAIN

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

sub launchcpulimiting(Bool $found) returns Proc::Async {
    if ($found) {
        say "Enter a cpulimit rate for movie encoding as a percentage.";
        say "    for example, if you want to designate three full cores then";
        my Int $cpurate = (prompt "    enter 300. Enter 0 for full use of all available CPU cores: ").Int;
        if ($cpurate > 0) {
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
         '-crf', '20', $outfile);
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
   await $encode-cmd.start;
}


