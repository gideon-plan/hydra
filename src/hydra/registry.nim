## registry.nim -- URL scheme-based transport selection.
##
## Parse endpoint URLs and dispatch to appropriate transport.
## Schemes: tcp://, ipc://, tls://, shm://, quic://, mqtt://, valkey://, ws://, 9p://

{.experimental: "strict_funcs".}

import std/strutils
import wire, transport

# =====================================================================================================================
# URL parsing
# =====================================================================================================================

type
  SpScheme* {.pure.} = enum
    Tcp
    Ipc
    Tls
    Shm
    Quic
    Mqtt
    Valkey
    Ws
    Ninep

  SpEndpoint* = object
    scheme*: SpScheme
    host*: string
    port*: int
    path*: string  ## For IPC path, SHM channel name, overlay prefix

proc parse_endpoint*(url: string): SpEndpoint {.raises: [SpError].} =
  ## Parse an SP endpoint URL.
  let sep = url.find("://")
  if sep < 0:
    raise newException(SpError, "invalid endpoint URL: missing scheme: " & url)
  let scheme_str = url[0 ..< sep].toLowerAscii()
  let rest = url[sep + 3 ..< url.len]
  let scheme = case scheme_str
    of "tcp": SpScheme.Tcp
    of "ipc": SpScheme.Ipc
    of "tls": SpScheme.Tls
    of "shm": SpScheme.Shm
    of "quic": SpScheme.Quic
    of "mqtt": SpScheme.Mqtt
    of "valkey": SpScheme.Valkey
    of "ws": SpScheme.Ws
    of "9p": SpScheme.Ninep
    else: raise newException(SpError, "unknown scheme: " & scheme_str)
  case scheme
  of SpScheme.Ipc:
    SpEndpoint(scheme: scheme, path: rest)
  of SpScheme.Shm:
    SpEndpoint(scheme: scheme, path: rest)
  else:
    # Parse host:port/path
    var host = ""
    var port = 0
    var path = ""
    let slash_pos = rest.find('/')
    let host_port = if slash_pos >= 0:
      path = rest[slash_pos ..< rest.len]
      rest[0 ..< slash_pos]
    else:
      rest
    let colon_pos = host_port.find(':')
    if colon_pos >= 0:
      host = host_port[0 ..< colon_pos]
      try:
        port = parseInt(host_port[colon_pos + 1 ..< host_port.len])
      except ValueError:
        raise newException(SpError, "invalid port in URL: " & url)
    else:
      host = host_port
      port = case scheme
        of SpScheme.Tcp, SpScheme.Tls: 0
        of SpScheme.Quic: 0
        of SpScheme.Mqtt: 1883
        of SpScheme.Valkey: 6379
        of SpScheme.Ws: 80
        of SpScheme.Ninep: 564
        else: 0
    SpEndpoint(scheme: scheme, host: host, port: port, path: path)

proc dial*(endpoint: SpEndpoint, proto: uint16): SpConn {.raises: [SpError].} =
  ## Dial a TCP or IPC endpoint. For other schemes, use scheme-specific functions.
  case endpoint.scheme
  of SpScheme.Tcp:
    tcp_dial(endpoint.host, endpoint.port, proto)
  of SpScheme.Ipc:
    ipc_dial(endpoint.path, proto)
  else:
    raise newException(SpError, "dial not supported for scheme: " & $endpoint.scheme &
                       " -- use scheme-specific dial function")

proc listen*(endpoint: SpEndpoint, proto: uint16): SpListener {.raises: [SpError].} =
  ## Listen on a TCP or IPC endpoint. For other schemes, use scheme-specific functions.
  case endpoint.scheme
  of SpScheme.Tcp:
    tcp_listen(endpoint.port, proto)
  of SpScheme.Ipc:
    ipc_listen(endpoint.path, proto)
  else:
    raise newException(SpError, "listen not supported for scheme: " & $endpoint.scheme &
                       " -- use scheme-specific listen function")

proc to_url*(ep: SpEndpoint): string =
  ## Reconstruct URL from endpoint.
  let scheme = case ep.scheme
    of SpScheme.Tcp: "tcp"
    of SpScheme.Ipc: "ipc"
    of SpScheme.Tls: "tls"
    of SpScheme.Shm: "shm"
    of SpScheme.Quic: "quic"
    of SpScheme.Mqtt: "mqtt"
    of SpScheme.Valkey: "valkey"
    of SpScheme.Ws: "ws"
    of SpScheme.Ninep: "9p"
  case ep.scheme
  of SpScheme.Ipc, SpScheme.Shm:
    scheme & "://" & ep.path
  else:
    var url = scheme & "://" & ep.host
    if ep.port > 0:
      url &= ":" & $ep.port
    if ep.path.len > 0:
      url &= ep.path
    url
