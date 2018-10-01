# Hooray, Perl6

say "Checking prerequisites.";

my $have-cpulimit = False;
my $cpulimit = 'cpulimit';

try {
   my $cpulimitcheck = run 'which', $cpulimit, :out;
   for $cpulimitcheck.out.lines -> $line {
       say "Found $cpulimit '$line'.";
   }
   $cpulimitcheck.out.close();
   $have-cpulimit = True;
   CATCH {
       when X::Proc::Unsuccessful {
           say "Warning: $cpulimit not found. CPU rate limiting not possible.";
           say "You may wish to install $cpulimit.";
           .resume
       }
   }
}

my $ffmpeg = 'ffmpeg';
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

my @mkvs = $to-encode-path.IO.dir: test => /:i '.' mkv $/;
if (@mkvs.elems == 0) {
   die "Could not find any mkv files in directory '$to-encode-path'.";
}

my Str $output-encoded-path = prompt "Please enter the name of the directory for reencoded files: ";
if (!$output-encoded-path.IO.d) {
   mkdir $output-encoded-path;
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
my $cpulimiting-status = launchcpulimiting($have-cpulimit);

if ($cpulimiting-status.defined && $cpulimiting-status.started) {
    $cpulimiting-status.kill('QUIT');
    say "Closed the cpulimit process.";
}

