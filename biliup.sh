#!/usr/bin/env bash
# Bilibili 投稿线路网络测评脚本
# https://github.com/L-aros/bilibili-upload-line-bench
# SPDX-License-Identifier: MIT
# 默认仅执行 DNS、TCP、TLS、HTTP 和小文件下载探测，不会上传文件或创建投稿。

set -uo pipefail

VERSION="1.0.0"
SAMPLES=8
CONNECT_TIMEOUT=5
MAX_TIME=10
IP_VERSION=4
INCLUDE_LEGACY=0
BVID=""
DOWNLOAD_MB=32
NO_COLOR=0
OUTPUT_FILE=""

UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36 bili-line-bench/${VERSION}"
TMP_DIR=""

usage() {
  cat <<'EOF'
用法：
  bash biliup.sh [选项]

选项：
  -n, --samples N          每条投稿线路的探测次数，默认 8
  -t, --timeout SEC        单次探测总超时，默认 10 秒
      --connect-timeout S  建连超时，默认 5 秒
      --ipv4               仅使用 IPv4（默认）
      --ipv6               仅使用 IPv6
      --all-lines          加入项目中标记为“可能已失效”的旧线路
      --bvid BVID          用一个公开 BVID 测试 B站 CDN -> 本机下载质量
      --download-mb MB     BVID 下载采样上限，默认 32 MiB
      --no-color           禁用彩色输出
  -o, --output FILE        同时将完整输出保存到指定文件
  -h, --help               显示帮助
  -v, --version            显示版本

示例：
  bash biliup.sh
  bash biliup.sh -n 15 --all-lines
  bash biliup.sh --bvid BVxxxxxxxxxx --download-mb 64

安全说明：
  默认测试不会登录账号、上传文件或创建投稿。--bvid 只读取公开视频的播放地址，
  并通过 HTTP Range 下载指定大小的数据到 /dev/null。
EOF
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

is_positive_int() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

while (($#)); do
  case "$1" in
    -n|--samples)
      (($# >= 2)) || die "$1 缺少参数"
      SAMPLES="$2"; shift 2 ;;
    -t|--timeout)
      (($# >= 2)) || die "$1 缺少参数"
      MAX_TIME="$2"; shift 2 ;;
    --connect-timeout)
      (($# >= 2)) || die "$1 缺少参数"
      CONNECT_TIMEOUT="$2"; shift 2 ;;
    --ipv4) IP_VERSION=4; shift ;;
    --ipv6) IP_VERSION=6; shift ;;
    --all-lines) INCLUDE_LEGACY=1; shift ;;
    --bvid)
      (($# >= 2)) || die "$1 缺少参数"
      BVID="$2"; shift 2 ;;
    --download-mb)
      (($# >= 2)) || die "$1 缺少参数"
      DOWNLOAD_MB="$2"; shift 2 ;;
    --no-color) NO_COLOR=1; shift ;;
    -o|--output)
      (($# >= 2)) || die "$1 缺少参数"
      OUTPUT_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -v|--version) printf '%s\n' "$VERSION"; exit 0 ;;
    *) die "未知参数：$1（使用 --help 查看帮助）" ;;
  esac
done

is_positive_int "$SAMPLES" || die "samples 必须是正整数"
is_positive_int "$MAX_TIME" || die "timeout 必须是正整数"
is_positive_int "$CONNECT_TIMEOUT" || die "connect-timeout 必须是正整数"
is_positive_int "$DOWNLOAD_MB" || die "download-mb 必须是正整数"
(( CONNECT_TIMEOUT <= MAX_TIME )) || die "connect-timeout 不能大于 timeout"
[[ -z "$BVID" || "$BVID" =~ ^BV[0-9A-Za-z]{10}$ ]] || die "BVID 格式不正确"

if [[ -n "$OUTPUT_FILE" ]]; then
  command -v tee >/dev/null 2>&1 || die "使用 --output 时需要 tee"
  command -v dirname >/dev/null 2>&1 || die "使用 --output 时需要 dirname"
  output_parent="$(dirname -- "$OUTPUT_FILE")"
  [[ -d "$output_parent" ]] || die "输出目录不存在：$output_parent"
  exec > >(tee "$OUTPUT_FILE") 2>&1
fi

command -v curl >/dev/null 2>&1 || die "缺少 curl，请先安装 curl"
command -v awk >/dev/null 2>&1 || die "缺少 awk"
command -v sort >/dev/null 2>&1 || die "缺少 sort"

TMP_DIR="$(mktemp -d 2>/dev/null)" || die "无法创建临时目录"
cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$NO_COLOR" -eq 0 && -t 1 ]]; then
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_YELLOW=""; C_RED=""; C_CYAN=""; C_BOLD=""; C_RESET=""
fi

section() {
  printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"
}

curl_ip=()
if [[ "$IP_VERSION" -eq 4 ]]; then
  curl_ip=(-4)
else
  curl_ip=(-6)
fi

resolve_ip() {
  local host="$1" ip=""
  if command -v getent >/dev/null 2>&1; then
    if [[ "$IP_VERSION" -eq 4 ]]; then
      ip="$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1 {print $1}')"
    else
      ip="$(getent ahostsv6 "$host" 2>/dev/null | awk 'NR==1 {print $1}')"
    fi
  elif command -v dig >/dev/null 2>&1; then
    if [[ "$IP_VERSION" -eq 4 ]]; then
      ip="$(dig +short A "$host" 2>/dev/null | awk 'NR==1')"
    else
      ip="$(dig +short AAAA "$host" 2>/dev/null | awk 'NR==1')"
    fi
  fi
  printf '%s' "${ip:--}"
}

http_check() {
  local name="$1" url="$2" result rc code total ip
  result="$(curl "${curl_ip[@]}" -sS -L -o /dev/null \
    -A "$UA" --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    -w $'%{http_code}\t%{time_total}\t%{remote_ip}' "$url" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    IFS=$'\t' read -r code total ip <<<"$result"
    printf '  %-18s HTTP %-3s  %7.1f ms  %s\n' "$name" "$code" \
      "$(awk -v v="$total" 'BEGIN {printf "%.1f", v*1000}')" "${ip:--}"
  else
    printf '  %-18s %s失败%s（curl=%s）\n' "$name" "$C_RED" "$C_RESET" "$rc"
  fi
}

# host -> UI 线路名称。相同实际主机的线路会合并，避免重复测试污染结果。
declare -A HOST_LABELS=()
declare -a TARGET_HOSTS=()

add_target() {
  local label="$1" host="$2"
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 0
  if [[ -n "${HOST_LABELS[$host]:-}" ]]; then
    case ",${HOST_LABELS[$host]}," in
      *",$label,"*) ;;
      *) HOST_LABELS[$host]="${HOST_LABELS[$host]},$label" ;;
    esac
  else
    HOST_LABELS[$host]="$label"
    TARGET_HOSTS+=("$host")
  fi
}

discover_auto_lines() {
  local json_file="$TMP_DIR/preupload-probe.json"
  local tsv_file="$TMP_DIR/preupload-probe.tsv"
  local url="https://member.bilibili.com/preupload?r=probe"
  local rc=0

  curl "${curl_ip[@]}" -sS -L -A "$UA" \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "$url" -o "$json_file" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 && -s "$json_file" ]] || return 1

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$json_file" >"$tsv_file" 2>/dev/null <<'PY'
import json, sys
from urllib.parse import parse_qs, urlparse

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
if data.get("OK") != 1:
    raise SystemExit(1)
for index, line in enumerate(data.get("lines") or [], 1):
    query = parse_qs(line.get("query") or "")
    zone = (query.get("zone") or [""])[0]
    upcdn = (query.get("upcdn") or [""])[0]
    label = f"auto#{index}"
    if zone and upcdn:
        label += f"({zone}-{upcdn})"
    probe = line.get("probe_url") or ""
    if probe.startswith("//"):
        probe = "https:" + probe
    host = urlparse(probe).hostname or ""
    if host:
        print(label, host, sep="\t")
PY
  else
    # 无 Python 时只提取 probe_url 主机，名称使用 auto#N。
    awk 'BEGIN {RS="probe_url"; n=0}
      NR>1 && match($0, /\/\/[A-Za-z0-9.-]+/) {
        n++; host=substr($0, RSTART+2, RLENGTH-2); print "auto#" n "\t" host
      }' "$json_file" >"$tsv_file"
  fi

  [[ -s "$tsv_file" ]] || return 1
  while IFS=$'\t' read -r label host; do
    [[ -n "$label" && -n "$host" ]] && add_target "$label" "$host"
  done <"$tsv_file"
  return 0
}

add_static_lines() {
  # biliLive-tools 当前界面线路的已知 UPOS 映射；B站可能随时调整，动态 auto 结果优先展示。
  add_target "cs-bda2"   "upos-cs-upcdnbda2.bilivideo.com"
  add_target "cs-bldsa"  "upos-cs-upcdnbldsa.bilivideo.com"
  add_target "cs-tx"     "upos-cs-upcdntx.bilivideo.com"
  add_target "cs-qn"     "upos-cs-upcdntxa.bilivideo.com"
  add_target "cs-cnbldsa" "upos-cs-upcdnbldsa.bilivideo.cn"
  add_target "cs-akbd"   "bb27c891csbd.aikobo.cn"
  add_target "cs-estx"   "e17962d5cstx.esheep.com"
  add_target "cs-cnbd"   "upos-cs-upcdnbd.bilivideo.cn"
  add_target "cs-cntx"   "upos-cs-upcdntx.bilivideo.cn"
  add_target "cs-andsa"  "upos-cs-upcdntxa.bilivideo.com"
  add_target "cs-anbd"   "upos-cs-upcdntxa.bilivideo.com"
  add_target "cs-antx"   "c3350892cstx.anitama.cn"
  add_target "cs-atdsa"  "upos-cs-upcdntxa.bilivideo.com"
  add_target "cs-atbd"   "upos-cs-upcdnalia.bilivideo.com"
  add_target "cs-attx"   "upos-cs-upcdnalia.bilivideo.com"

  if [[ "$INCLUDE_LEGACY" -eq 1 ]]; then
    add_target "cs-txa(旧)"    "upos-cs-upcdntxa.bilivideo.com"
    add_target "cs-alia(旧)"   "upos-cs-upcdnalia.bilivideo.com"
    add_target "jd-bldsa(旧)"  "upos-jd-upcdnbldsa.bilivideo.com"
    add_target "jd-bd(旧)"     "upos-jd-upcdnbd.bilivideo.com"
    add_target "jd-tx(旧)"     "upos-jd-upcdntx.bilivideo.com"
    add_target "jd-txa(旧)"    "upos-jd-upcdntxa.bilivideo.com"
    add_target "jd-alia(旧)"   "upos-jd-upcdnalia.bilivideo.com"
  fi
}

classify() {
  local success="$1" p95="$2" jitter="$3"
  awk -v s="$success" -v p="$p95" -v j="$jitter" 'BEGIN {
    if (s == 100 && p < 800 && j < 180) print "A";
    else if (s == 100 && p < 1600 && j < 450) print "B";
    else if (s >= 90) print "C";
    else print "D";
  }'
}

probe_host() {
  local host="$1" labels="${HOST_LABELS[$1]}" ip metrics="$TMP_DIR/metrics.tsv"
  local i result rc code dns tcp tls ttfb total
  local success=0 codes="" stats grade

  : >"$metrics"
  ip="$(resolve_ip "$host")"
  printf '  测试 %-48s ' "$labels"

  for ((i=1; i<=SAMPLES; i++)); do
    result="$(curl "${curl_ip[@]}" -sS -o /dev/null -A "$UA" \
      --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
      -w $'%{http_code}\t%{time_namelookup}\t%{time_connect}\t%{time_appconnect}\t%{time_starttransfer}\t%{time_total}' \
      "https://${host}/OK" 2>/dev/null)"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      IFS=$'\t' read -r code dns tcp tls ttfb total <<<"$result"
    else
      code="curl:$rc"
    fi

    if [[ "$rc" -eq 0 && "$code" =~ ^[23][0-9][0-9]$ ]]; then
      success=$((success + 1))
      awk -v d="$dns" -v c="$tcp" -v l="$tls" -v f="$ttfb" -v t="$total" \
        'BEGIN {printf "%.3f\t%.3f\t%.3f\t%.3f\t%.3f\n", d*1000, (c-d)*1000, (l-c)*1000, f*1000, t*1000}' \
        >>"$metrics"
    else
      codes="${codes}${codes:+,}${code}"
    fi
    printf '.'
  done

  if (( success > 0 )); then
    stats="$(awk -F '\t' '
      {d+=$1; c+=$2; l+=$3; f+=$4; t+=$5; a[NR]=$5}
      END {
        avg=t/NR; var=0;
        for(i=1;i<=NR;i++) var+=(a[i]-avg)^2;
        printf "%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f", d/NR,c/NR,l/NR,f/NR,avg,sqrt(var/NR)
      }' "$metrics")"
    IFS=$'\t' read -r avg_dns avg_tcp avg_tls avg_ttfb avg_total jitter <<<"$stats"
    p95="$(cut -f5 "$metrics" | sort -n | awk -v n="$success" 'NR==int((n*95+99)/100) {printf "%.1f", $1}')"
  else
    avg_dns="-"; avg_tcp="-"; avg_tls="-"; avg_ttfb="-"; avg_total="-"; p95="999999"; jitter="999999"
  fi

  success_rate="$(awk -v s="$success" -v n="$SAMPLES" 'BEGIN {printf "%.1f", s*100/n}')"
  grade="$(classify "$success_rate" "$p95" "$jitter")"
  printf ' %s%s%s\n' "$C_CYAN" "$grade" "$C_RESET"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$labels" "$host" "$success_rate" "$avg_dns" "$avg_tcp" "$avg_tls" \
    "$avg_ttfb" "$avg_total" "$p95" "$jitter" "$ip" >>"$TMP_DIR/results.tsv"
  [[ -n "$codes" ]] && printf '%s\t%s\n' "$host" "$codes" >>"$TMP_DIR/errors.tsv"
}

print_results() {
  local sorted="$TMP_DIR/results-sorted.tsv" rank=0
  local best_labels best_success best_p95
  sort -t $'\t' -k3,3nr -k9,9n -k10,10n "$TMP_DIR/results.tsv" >"$sorted"

  printf '\n  %-4s %-31s %8s %8s %8s %8s %8s %8s %8s %s\n' \
    "排名" "线路" "成功率" "DNS" "TCP" "TLS" "TTFB" "总耗时" "P95" "评级"
  printf '  %s\n' '-----------------------------------------------------------------------------------------------------------'
  while IFS=$'\t' read -r labels host success dns tcp tls ttfb total p95 jitter ip; do
    rank=$((rank + 1))
    if [[ "$total" == "-" ]]; then
      printf '  %-4s %-31.31s %7s%% %8s %8s %8s %8s %8s %8s %s\n' \
        "$rank" "$labels" "$success" "-" "-" "-" "-" "-" "-" "D"
    else
      grade="$(classify "$success" "$p95" "$jitter")"
      printf '  %-4s %-31.31s %7s%% %7sms %7sms %7sms %7sms %7sms %7sms %s\n' \
        "$rank" "$labels" "$success" "$dns" "$tcp" "$tls" "$ttfb" "$total" "$p95" "$grade"
    fi
    if (( rank <= 3 )); then
      printf '       主机: %s  IP: %s  抖动: %sms\n' "$host" "$ip" "$jitter"
    fi
  done <"$sorted"

  if [[ -s "$TMP_DIR/errors.tsv" ]]; then
    printf '\n  失败摘要（HTTP 状态或 curl 错误码）：\n'
    while IFS=$'\t' read -r host codes; do
      printf '    %-43s %s\n' "$host" "$codes"
    done <"$TMP_DIR/errors.tsv"
    printf '  curl 常见错误：6=DNS，7=连接失败，28=超时，35=TLS，60=证书校验。\n'
  fi

  IFS=$'\t' read -r best_labels _ best_success _ _ _ _ _ best_p95 _ _ <"$sorted"
  if awk -v s="$best_success" 'BEGIN {exit !(s >= 90)}'; then
    printf '\n  当前推荐候选：%s（成功率 %s%%，P95 %sms）\n' \
      "$best_labels" "$best_success" "$best_p95"
  else
    printf '\n  %s没有线路达到 90%% 成功率，不建议据此切换生产配置。%s\n' \
      "$C_RED" "$C_RESET"
  fi
  if (( SAMPLES < 5 )); then
    printf '  %s当前样本少于 5，仅适合验证脚本；正式比较建议使用 10–20 次。%s\n' \
      "$C_YELLOW" "$C_RESET"
  fi
}

download_test() {
  [[ -n "$BVID" ]] || return 0
  command -v python3 >/dev/null 2>&1 || {
    printf '  %s跳过：--bvid 下载测速需要 python3。%s\n' "$C_YELLOW" "$C_RESET"
    return 0
  }

  local page_json="$TMP_DIR/page.json" play_json="$TMP_DIR/play.json"
  local urls_file="$TMP_DIR/download-urls.txt" cid api_url rc=0
  local download_bytes=$((DOWNLOAD_MB * 1024 * 1024))
  local range_end=$((download_bytes - 1))

  curl "${curl_ip[@]}" -sS -L -A "$UA" \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "https://api.bilibili.com/x/player/pagelist?bvid=${BVID}" -o "$page_json" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { printf '  获取 BVID 分P信息失败（curl=%s）\n' "$rc"; return 0; }

  cid="$(python3 - "$page_json" <<'PY' 2>/dev/null
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    obj=json.load(f)
data=obj.get("data") or []
if data:
    print(data[0].get("cid", ""))
PY
)"
  [[ -n "$cid" ]] || { printf '  无法从 BVID 获取 CID，可能被风控或视频不可用。\n'; return 0; }

  api_url="https://api.bilibili.com/x/player/playurl?bvid=${BVID}&cid=${cid}&qn=64&fnval=0&platform=html5"
  rc=0
  curl "${curl_ip[@]}" -sS -L -A "$UA" -e "https://www.bilibili.com/video/${BVID}/" \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    "$api_url" -o "$play_json" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || { printf '  获取播放地址失败（curl=%s）\n' "$rc"; return 0; }

  python3 - "$play_json" >"$urls_file" 2>/dev/null <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    obj=json.load(f)
durl=(obj.get("data") or {}).get("durl") or []
if durl:
    item=durl[0]
    for url in [item.get("url"), *(item.get("backup_url") or [])]:
        if url:
            print(url)
PY
  [[ -s "$urls_file" ]] || { printf '  播放接口未返回可用地址，可能需要登录或触发风控。\n'; return 0; }

  local index=0 url host result code seconds bytes speed remote_ip
  while IFS= read -r url && (( index < 3 )); do
    index=$((index + 1))
    host="$(python3 - "$url" <<'PY'
import sys
from urllib.parse import urlparse
print(urlparse(sys.argv[1]).hostname or "-")
PY
)"
    rc=0
    result="$(curl "${curl_ip[@]}" -sS -L -o /dev/null -A "$UA" \
      -e "https://www.bilibili.com/video/${BVID}/" --range "0-${range_end}" \
      --max-filesize "$download_bytes" \
      --connect-timeout "$CONNECT_TIMEOUT" --max-time 60 \
      -w $'%{http_code}\t%{time_total}\t%{size_download}\t%{speed_download}\t%{remote_ip}' \
      "$url" 2>/dev/null)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      IFS=$'\t' read -r code seconds bytes speed remote_ip <<<"$result"
      printf '  CDN#%-2s %-39s HTTP %s  %7.2f MiB  %7.2f Mbit/s  %6.2fs  %s\n' \
        "$index" "$host" "$code" \
        "$(awk -v b="$bytes" 'BEGIN {print b/1048576}')" \
        "$(awk -v s="$speed" 'BEGIN {print s*8/1000000}')" "$seconds" "$remote_ip"
    else
      printf '  CDN#%-2s %-39s 失败（curl=%s）\n' "$index" "$host" "$rc"
    fi
  done <"$urls_file"
}

printf '%sBilibili 投稿线路网络测评 v%s%s\n' "$C_BOLD" "$VERSION" "$C_RESET"
printf '时间：%s  IP：IPv%s  样本：%s/线路  超时：%ss\n' \
  "$(date '+%F %T %Z' 2>/dev/null || date)" "$IP_VERSION" "$SAMPLES" "$MAX_TIME"
printf '说明：上传方向使用 UPOS /OK 小请求评估建连与稳定性，不会上传文件。\n'

section "[1/5] 系统与基础网络"
printf '  主机名：%s\n' "$(hostname 2>/dev/null || printf '-')"
printf '  系统：%s\n' "$(uname -srm 2>/dev/null || printf '-')"
printf '  出口 IPv%s：' "$IP_VERSION"
if [[ "$IP_VERSION" -eq 4 ]]; then
  ip_echo_url="https://api-ipv4.ip.sb/ip"
else
  ip_echo_url="https://api6.ipify.org"
fi
public_ip="$(curl "${curl_ip[@]}" -sS --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  "$ip_echo_url" 2>/dev/null || true)"
printf '%s\n' "${public_ip:--}"

section "[2/5] B站入口与 API 可达性"
http_check "主站" "https://www.bilibili.com/"
http_check "公共 API" "https://api.bilibili.com/x/web-interface/nav"
http_check "投稿 API" "https://member.bilibili.com/preupload?r=ping"
http_check "静态 CDN" "https://s1.hdslb.com/bfs/static/jinkela/long/images/favicon.ico"

section "[3/5] 动态线路发现"
if discover_auto_lines; then
  printf '  已取得 B站 auto 候选；auto 的顺序可能随时间变化。\n'
  if [[ -s "$TMP_DIR/preupload-probe.tsv" ]]; then
    while IFS=$'\t' read -r label host; do
      printf '  %-20s %s\n' "$label" "$host"
    done <"$TMP_DIR/preupload-probe.tsv"
  fi
else
  printf '  %s未取得动态候选，将使用 biliLive-tools 当前线路的已知主机映射。%s\n' \
    "$C_YELLOW" "$C_RESET"
fi
add_static_lines

section "[4/5] 投稿 UPOS 线路稳定性（机器 -> B站）"
: >"$TMP_DIR/results.tsv"
: >"$TMP_DIR/errors.tsv"
printf '  共 %s 个不同 UPOS 主机，正在执行 %s 次/主机的小请求探测。\n' \
  "${#TARGET_HOSTS[@]}" "$SAMPLES"
for host in "${TARGET_HOSTS[@]}"; do
  probe_host "$host"
done
print_results

section "[5/5] B站 CDN 下载方向（B站 -> 机器）"
if [[ -n "$BVID" ]]; then
  download_test
else
  printf '  基础 CDN 可达性已在第 2 项测试。要测真实吞吐，请提供一个公开 BVID：\n'
  printf '  bash %s --bvid BVxxxxxxxxxx --download-mb %s\n' "${0##*/}" "$DOWNLOAD_MB"
fi

section "结论读取"
cat <<'EOF'
  1. 投稿线路先看成功率，再看 P95 和抖动；不要只看一次请求的最低延迟。
  2. A/B 适合优先试用；C 表示有波动；D 不建议用于长视频投稿。
  3. HTTP 500 表示请求已到达 UPOS，但服务端或链路处理异常，不属于“被墙”。
  4. /OK 是安全的小请求，能比较线路稳定性，但不能完全替代真实分片 PUT 上传。
  5. 若 auto 候选频繁变化，生产环境可固定本次成功率最高且 P95 较低的线路。
EOF

printf '\n完成。建议在业务高峰和低峰各运行一次并保存输出进行对比。\n'
