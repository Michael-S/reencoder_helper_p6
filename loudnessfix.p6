# Copyright Mike Swierczek, 2019.
# Licensed under the Lesser GNU Public License version 2.1 or later.
# Please see the included LICENSE file for details.

use JSON::Fast;
 
constant $ffmpeg = 'ffmpeg';

sub USAGE() {
    print Q:c:to/EOH/;
Usage:
    option 1:
         perl6 loudnessfix.p6
         -- interactively prompts you for inputs
    option 2:
         perl6 loudnessfix.p6 --src=foo --dest=bar 
         -- reencodes movie foo to bar with loudness normalization
            applied to the first audio stream in it.  Video
            streams and subtitles, if any, are unchanged.

    The operation uses temporary files, so if you're confident
    in the results it is safe to use the same input and output file name.
EOH
}

multi sub MAIN {

    my Str $src = prompt "Please enter the name of the source film: ";
    my Str $dest = prompt "Please enter the name of the destination film: ";
    say "In the future, you could have invoked this with:";
    say "perl6 loudnessfix.p6 --src=$src --dest=$dest";
    run-process($src, $dest);
}

multi sub MAIN(Str :$src! where $src.chars > 0,
               Str :$dest! where $dest.chars > 0) {
    run-process($src, $dest);
}


sub run-process(Str $src, Str $dest) {
    say "Checking prerequisites.";
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

    if (!$src.IO.f) {
        die "File '$src' does not exist, are you running this from the right location? Did you make a typo?";
    }
    if ($dest.IO.f) {
        die "File '$dest' already exists.  If you're sure you want to replace it, delete it manually before running this program.";
    }
    wrap-loudness-norm-encode($src.IO, $dest);
    say "Finished.";
}

# taken from https://blog.matatu.org/tailgrep
sub spinner() {
  <\ - | - / ->[$++ % 6]
}

sub wrap-loudness-norm-encode(IO::Path $infile, Str $outfile) {
    my $start-time = DateTime.now;
    my $encoding-json = run-first-pass($infile);
    run-second-pass($infile, $outfile, $encoding-json);
    my $finish-time = DateTime.now;
    say "        Finished, took " ~ ($finish-time - $start-time) ~ " s.";
}

#
# target_il  = -24.0
# target_lra = +11.0
# target_tp  = -2.0
# samplerate = '48k'
constant $target_il = -24.0;
constant $target_lra = 11.0;
constant $target_tp = -2.0;
constant $samplerate = "48k";

sub run-first-pass(IO::Path $infile -->Str) {
    my $encode-cmd = Proc::Async.new('ffmpeg', '-i', $infile, '-af',
         "loudnorm=I=$target_il\:LRA=$target_lra\:tp=$target_tp\:print_format=json", '-f', 'null');
    my Str $result = "";
    react {
        whenever $encode-cmd.stdout -> $my-out {
             # print spinner() ~ "\r";
             say $my-out;
        }
        whenever $encode-cmd.stderr -> $my-err {
             # print spinner() ~ "\r";
             $result ~= $my-err;
             say "Capturing: $my-err.";
        }
        whenever signal(SIGINT) {
             say "Received SIGINT, stopping.";
             exit;
        }
        whenever $encode-cmd.start {
             say "    Done pass 1.";
             done # gracefully jump from the react block
        }
   }
   say "Returning result: $result ";
   $result;
}

sub run-second-pass(IO::Path $infile, Str $outfile, Str $encoding-json) {
    my $parsed-json = from-json($encoding-json);
    say "Parsed to $parsed-json.";
    my $input_i = $parsed-json<input_i>;
    my $input_lra = $parsed-json<input_lra>;
    my $input_tp = $parsed-json<input_tp>;
    my $input_thresh = $parsed-json<input_thresh>;
    my $offset = $parsed-json<target_offset>;
    say "Have $input_i $input_lra $input_tp $input_thresh .";
    my $encode-cmd = Proc::Async.new('ffmpeg', '-i', $infile, '-c:v', 'copy', '-c:s', 'copy', 
         '-af',
         "loudnorm=print_format=summary\:I=$target_il\:LRA=$target_lra\:tp=$target_tp\:" ~
         "measured_I=$input_i\:measured_LRA=$input_lra\:measured_tp=$input_tp\:measured_thresh=$input_thresh\:offset=$offset",
         '-ar', $samplerate, $outfile);
    react {
        whenever $encode-cmd.stdout -> $my-out {
             # print spinner() ~ "\r";
             say $my-out;
        }
        whenever $encode-cmd.stderr -> $my-err {
             # print spinner() ~ "\r";
             say $my-err;
        }
        whenever signal(SIGINT) {
             say "Received SIGINT, stopping.";
             exit;
        }
        whenever $encode-cmd.start {
             say "    Done pass 1.";
             done # gracefully jump from the react block
        }
   }
}
