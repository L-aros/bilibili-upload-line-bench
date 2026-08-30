# Security policy

## Data handling

The default benchmark does not request or read Bilibili account credentials, cookies, access tokens, or local biliLive-tools configuration.

The optional `--bvid` mode calls public playback APIs. Playback URLs are written only to a newly created temporary directory, are never printed in full, and are removed when the process exits normally or receives `INT`/`TERM`.

The script does not upload media, initialize UPOS multipart uploads, merge chunks, create drafts, or publish submissions. UPOS testing uses small HTTPS `GET /OK` requests.

## Reporting a vulnerability

When reporting a vulnerability, do not attach account cookies, signed playback URLs, biliLive-tools configuration files, or complete logs that contain private identifiers. Include the script version, operating system, command-line options, and a redacted reproduction.
