# Bilibili Upload Line Benchmark

[中文](README.md) | [English](README_EN.md)

`biliup.sh` benchmarks the network path between a Linux VPS and Bilibili, with a focus on the UPOS endpoints used by upload tools such as biliLive-tools.

By default, it does not sign in, upload media, or create a submission. It checks:

- reachability of Bilibili web, API, member/preupload, and static CDN endpoints;
- dynamic upload candidates returned by Bilibili's `preupload` probe;
- DNS, TCP, TLS, TTFB, total latency, P95, jitter, and success rate for known UPOS endpoints;
- optional, size-limited download throughput from a public BVID.

## Quick start

```bash
chmod +x biliup.sh
./biliup.sh
```

Download from GitHub:

```bash
curl --proto '=https' --tlsv1.2 -fsSLO \
  https://raw.githubusercontent.com/L-aros/bilibili-upload-line-bench/main/biliup.sh
chmod +x biliup.sh
./biliup.sh
```

Use more samples and include legacy routes:

```bash
./biliup.sh --samples 15 --all-lines
```

Test the Bilibili CDN-to-server direction with a public video:

```bash
./biliup.sh --bvid BVxxxxxxxxxx --download-mb 64
```

Save the report:

```bash
./biliup.sh --samples 15 --output bili-bench-$(date +%F-%H%M).log
```

## Requirements

Bash 4+, curl, awk, sort, and standard GNU userland tools are required. Python 3 is recommended for robust parsing of dynamic routes and public BVID playback URLs.

Run `./biliup.sh --help` for every option. IPv4 is used by default.

## Reading the result

Compare success rate first, then P95 and jitter. A tiny `/OK` request is safe and useful for comparing DNS, connection, TLS, and service stability, but it does not reproduce a complete multipart PUT upload.

Run the benchmark during both peak and off-peak hours before changing a production upload route. See [docs/METRICS.md](docs/METRICS.md) for the methodology and limitations.

## Privacy and safety

The default benchmark does not request account cookies. Signed playback URLs obtained with `--bvid` are kept in a temporary directory and deleted on exit. See [SECURITY.md](SECURITY.md).

## License

MIT. This project is not affiliated with Bilibili.
