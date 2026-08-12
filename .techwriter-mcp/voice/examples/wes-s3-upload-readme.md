<!-- Copied verbatim from ~/projects/writing-samples/Wes Roberts/s3-upload-readme.md (hand-written, per that repo's README). -->

<!-- README of s3-upload, a pre-AI project by this repo's author; hand-written voice reference -->
# S3 Upload

Replace [CloudApp](https://www.getcloudapp.com/) and [Droplr](https://droplr.com/) for **sharing files, screenshots, and videos** with friends and co-workers.

With a little set-up, you can:

- Auto-upload files the cloud for free.
- Easily anotate image uploads with your preferred graphics software.
- Copy sharable URLs to clipboard automatically.

For more information on how to easily set this up, check out the [automation section](#user-content-automation).

## Benefits

With this guide, you can replace your screenshot sharing tool with something better:

- 5GB completely free.
- Configure auto-expire or not.
- 100% free and open source software.
- About 3x to 10x faster than competing services.
- Bring your own annotation / graphics software like Gimp, Sketch, or Photoshop.
- Get links to direct files. No intermediary pages. No tracking.

## Install

Simply copy the `s3-upload` executable to your `PATH`. For example:

```sh
wget https://raw.githubusercontent.com/jchook/s3-upload/master/bin/s3-upload
chmod +x s3-upload
sudo mv s3-upload /usr/local/bin
```

You can repeat the same process for upgrades to a newer version.

### Platforms

So far I have only tested this on Ubuntu 18.04 but I expect it will work on:

- Linux, BSD, etc
- Mac OS X
- Windows 10 (with [WSL](https://docs.microsoft.com/en-us/windows/wsl/install-win10))

### Requirements

- `bash` and `curl` (usually built-in)
- [Amazon S3 account](https://aws.amazon.com/s3/) (free)

## Usage

To upload, simply pass file path(s) to the executeable, e.g.

```sh
s3-upload aww-yeah.gif
```

For a deeper understanding of the usage:

```sh
s3-upload [options] [--] [<file> | -] ...
```

A sharable URL link for the uploaded file will print to standard output. You can use the `--copy` option to copy it to clipboard, or the `--quiet` option to suppress this behavior.

## Config file

The first time you run `s3-upload`, it will guide you through configuring your S3 details. However, you can opt to manage the config file manually.

You can configure almost all option defaults. Simply edit the file `~/.config/s3-upload`:

```sh
AWS_ACCESS_KEY_ID="XXX"
AWS_ACCESS_KEY_SECRET="YYY"
S3_BUCKET_NAME="ZZZ"
COPY=1
NOTIFY=1
QUIET=
```


## Options

Command-line options allow you to override all configuration at the call site.

```
  -c, --config <file>
    Load a custom configuration file.

  -C, --copy
    Copy the share URL to clipboard.

  -N, --notify
    Notify successful upload via notify-send.

  -n, --name <name>
    Choose custom name(s) for an uploaded file.
    Use multiple times (in order) for multiple files.
    Most useful when piping data into s3-upload via STDIN.

  -k, --key <access-key-id>
    Use a specific IAM access key.

  -p, --secret <secret-key>
    Use a specific IAM access secret. Use empty string to prompt.

  -q, --quiet
    Don't print any information to STDOUT.

  --stdin
    Read a newline-separated file list from STDIN.

  -u, --username <username>
    Use a specific username.

  <file> ...
    Path(s) to the file(s) you want to upload.
    Specify a hyphen (-) to pipe data from stdin.
```

## Examples

- Upload multiple files
```sh
  s3-upload file1.txt file2.mp3
```

- Upload from STDIN with a custom name
```sh
  curl api.ipify.org | s3-upload --name ip.txt -
```

- Upload a file and copy the url to the system clipboard
```sh
  s3-upload --copy file.png
```



<a id="Recipes"></a>
## Automation

I found some really great ways to integrate this tool into my workflow:

* [Upload screenshots and screencast](docs/recipes/auto-upload-screenshots.md)
* [Annotate screenshots](docs/recipes/annotate-screenshots.md)


## License

MIT.


## See also

- [`s3cmd`](https://s3tools.org/s3cmd)
- [`s3put`](https://manpages.debian.org/jessie/libnet-amazon-s3-tools-perl/s3put.1p.en.html)
