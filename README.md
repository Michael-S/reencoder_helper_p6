# reencoder_helper_p6

A Raku command line utility to assist in reencoding Blu Ray rips to save on disk space.  I've written it to support a relatively recent Rakudo Star Raku6 release (2018 or so) on Linux, and it probably won't work properly out of the box on macOs or Microsoft Windows.

I chose Raku for fun.

When I purchase a new DVD or Blu Ray disk, I use the MakeMKV software (http://www.makemkv.com/) to copy the contents to disk.

Then I run the video encoding software 'ffmpeg' to change the video codec from the original MPEG2 (in DVDs) or H.264 (in Blu Rays) to H.265.  Eventually there may be better options for the video codec, like AV1, but my existing media players can handle the H.265 format.  I hard-code the ffmpeg parameters in my conversion, though it wouldn't be too hard to prompt for those or store them in a config file.

The WebM format was a consideration, and it makes some forms of streaming over the web easier.  But I always preserve all subtitles in my films so I can catch all dialog even while watching in noisy environments.  WebM doesn't support subtitles, so that rules it out.

**Note 2023-11-04**: I now use the [JellyFin](https://jellyfin.org/) media server to serve movies to Roku, iOS, Windows, Linux, Mac, Android, and web browsers.  JellyFin can transcode video files on the flyto support all client types, but for maximum picture quality it's best to have the files in the format the client can support natively. In that case JellyFin just streams the file as-is and maximum quality is preserved. For maximum quality with on-the-fly transcoding, you need a pretty powerful JellyFin server and even then it can only support a few streams at a time before picture quality degrades. As far as I can tell, the only universally supported file format is MP4 files with the H.264 video codec and the EAC3 audio codec. So I no longer use this reencoder as-is.  In order to avoid transcoding by JellyFin to include subtitles on-the-fly, I also burn the subtitles directly into the video stream.  The typical command is:

`ffmpeg -i /path/to/file/with/a/subtitle/file.mkv -filter_complex [0:v][0:s]overlay[v] -map [v] -map 0:a:0 -c:v libx264 -crf 15 -preset veryslow  -c:a eac3 -b:a 320k /path/to/output/file.mp4`

The license is LGPL 2.1+, same as ffmpeg, in the unlikely event someone else wants to package the two together.

The goal for use is for the user to run: ``raku reencoder.raku``, follow the prompts to get it started, and then wait a few days and then have the finished files in an output directory.  Nothing too fancy, but far less manual work than running ffmpeg commands by hand every time you rip a Blu Ray.
