#!/bin/sh
# 让服务端用 libcurl 访问签发方的应用连上 *.localhost 上的签发方：在同网络命名空间里把
# 127.0.0.1 和 [::1] 的签发方端口 TCP 直转到签发方，Host 头原样带给核心。
# 套件文件，插件不改；compose 写法见 README 的“服务端用 libcurl 的应用”。
set -eu

issuer="${WONTON_OIDC_ISSUER:?WONTON_OIDC_ISSUER 没设置}"
scheme="${issuer%%://*}"
case "$scheme" in
  http) port=80 ;;
  https) port=443 ;;
  *) echo "签发方不是 http/https 地址：$issuer" >&2; exit 1 ;;
esac
authority="${issuer#*://}"
authority="${authority%%/*}"
case "$authority" in
  \[*\]:*) host="${authority%%]*}"; host="${host#\[}"; port="${authority##*:}" ;;
  \[*\]) host="${authority%%]*}"; host="${host#\[}" ;;
  *:*) host="${authority%:*}"; port="${authority##*:}" ;;
  *) host="$authority" ;;
esac
[ -n "$host" ] || { echo "签发方里没有主机：$issuer" >&2; exit 1; }
case "$port" in '' | *[!0-9]*) echo "签发方端口不是数字：$issuer" >&2; exit 1 ;; esac

# curl 7.78 起把 localhost 和一切 *.localhost 当回环，不查 DNS；只有这类主机要转发。
loopback=1
case "$host" in
  *.localhost | localhost)
    ;;
  *) loopback=0 ;;
esac

# 健康检查：有监听时连一下本机端口；不转发时空转也算健康。
if [ "${1:-}" = check ]; then
  if [ "$loopback" -eq 0 ]; then exit 0; fi
  socat -u /dev/null TCP:127.0.0.1:"$port" 2>/dev/null ||
    socat -u /dev/null TCP6:"[::1]":"$port" 2>/dev/null
  exit
fi

if [ "$loopback" -eq 0 ]; then
  echo "签发方不在 .localhost 下，不用转发"
  # sleep 在后台，壳留着接 TERM；前台跑的话容器要等满宽限才被 SIGKILL。
  trap 'exit 0' TERM
  sleep infinity &
  wait
fi

# 容器停止时安静退出；任一 socat 退出就让整个服务跟着退出，监听失败时补一句原因。
# 信号从子壳发给主壳：POSIX sh 的子壳里 $$ 仍是主壳的 pid，主壳这时只在 wait 上。
trap 'exit 0' TERM
trap 'echo "应用占用了签发方端口 $port，转发起不来" >&2; exit 1' USR1
(
  if socat TCP-LISTEN:"$port",bind=127.0.0.1,fork,reuseaddr TCP:"$host":"$port"; then
    kill -TERM $$
  else
    kill -USR1 $$
  fi
) &
(
  if socat TCP6-LISTEN:"$port",bind=::1,ipv6only=1,fork,reuseaddr TCP:"$host":"$port"; then
    kill -TERM $$
  else
    kill -USR1 $$
  fi
) &
wait

