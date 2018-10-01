# reencoder_helper_p6

A Perl 6 command line utility to assist in reencoding Blu Ray rips to save on disk space.

When I purchase a new DVD or Blu Ray disk, I use the MakeMKV software (http://www.makemkv.com/) to copy the contents to disk.

Then I run the video encoding software 'ffmpeg' to change the video codec from the original MPEG2 (in DVDs) or H.264 (in Blu Rays) to H.265.  Eventually there may be better options for the video codec, like AV1, but my existing media players can handle the H.265 format.

The WebM format was a consideration, and it makes some forms of streaming over the web easier.  But I always preserve all subtitles in my films so I can catch all dialog even while watching in noisy environments.  WebM doesn't support subtitles, so that rules it out.

The license is LGPL 2.1+, same as ffmpeg, in the unlikely event someone else wants to package the two together.

The goal for use is for the user to run: ``perl6 reencoderhelper.p6 <some directory full of mkv files>`` and wait a few days and then have the finished files in an output directory.  Nothing too fancy.
