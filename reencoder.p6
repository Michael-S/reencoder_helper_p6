# Hooray, Perl6

say "Checking prerequisites.";

constant $cpulimit = 'cpulimit';

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
my Bool $have-cpulimit = checkcpulimit();

constant $ffmpeg = 'ffmpeg';
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
my $cpulimiting-status = launchcpulimiting($have-cpulimit);

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

my @sortedmkvs = @mkvs.sort( - *.IO.s);

for @sortedmkvs -> $mkv {
    my Int $size = $mkv.IO.s;
    my Str $prettysize = prettysize($size);
    say "Starting file '$mkv', $prettysize.";
}

if ($cpulimiting-status.defined && $cpulimiting-status.started) {
    $cpulimiting-status.kill('QUIT');
    say "Closed the cpulimit process.";
}

