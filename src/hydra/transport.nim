## transport.nim -- TCP and IPC transport: dial, listen, accept.
##
## All connections are blocking. Under atomicArc, SpConn is a ref object
## safely shared across threads.

{.experimental: "strict_funcs".}

import std/net
import wire
import libressl/tls as libtls

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  TransportKind* = enum
    tkTcp
    tkIpc

  SpConn* = ref object
    ## A single SP transport connection. ref-counted under atomicArc.
    sock*: Socket
    tls_ctx*: TlsCtx       ## non-nil when TLS is active
    kind*: TransportKind
    peer_proto*: uint16

# =====================================================================================================================
# Low-level I/O
# =====================================================================================================================

proc sp_recv*(conn: SpConn, n: int): string {.raises: [SpError].} =
  ## Read exactly n bytes.
  result = ""
  if conn.tls_ctx != nil:
    while result.len < n:
      var buf: array[4096, byte]
      let want = min(n - result.len, buf.len)
      let r = libtls.tls_read(conn.tls_ctx, addr buf[0], csize_t(want))
      if r == TLS_WANT_POLLIN or r == TLS_WANT_POLLOUT:
        continue
      if r <= 0:
        raise newException(SpError, "tls recv: " & error_string(conn.tls_ctx))
      for i in 0 ..< r:
        result.add(char(buf[i]))
  else:
    while result.len < n:
      let buf = try:
        conn.sock.recv(n - result.len)
      except OSError as e:
        raise newException(SpError, "recv error: " & e.msg)
      except TimeoutError as e:
        raise newException(SpError, "recv timeout: " & e.msg)
      if buf.len == 0:
        raise newException(SpError, "connection closed")
      result.add(buf)

proc sp_send*(conn: SpConn, data: string) {.raises: [SpError].} =
  ## Send all bytes.
  if conn.tls_ctx != nil:
    var pos = 0
    while pos < data.len:
      let w = libtls.tls_write(conn.tls_ctx, unsafeAddr data[pos], csize_t(data.len - pos))
      if w == TLS_WANT_POLLIN or w == TLS_WANT_POLLOUT:
        continue
      if w <= 0:
        raise newException(SpError, "tls send: " & error_string(conn.tls_ctx))
      pos += w
  else:
    try:
      conn.sock.send(data)
    except OSError as e:
      raise newException(SpError, "send error: " & e.msg)

# =====================================================================================================================
# Frame send/recv
# =====================================================================================================================

proc send_frame*(conn: SpConn, frame: SpFrame) {.raises: [SpError].} =
  ## Encode and send an SP frame.
  sp_send(conn, encode_frame(frame))

proc recv_frame*(conn: SpConn): SpFrame {.raises: [SpError].} =
  ## Read one SP frame from the connection.
  let size_buf = sp_recv(conn, 8)
  var pos = 0
  let size = int(decode_size(size_buf, pos))
  if size > 0:
    let body = sp_recv(conn, size)
    result = SpFrame(header: "", payload: body)
  else:
    result = SpFrame(header: "", payload: "")

# =====================================================================================================================
# Handshake
# =====================================================================================================================

proc do_handshake*(conn: SpConn, my_proto: uint16) {.raises: [SpError].} =
  ## Perform SP handshake: send our protocol, receive and validate peer's.
  sp_send(conn, encode_handshake(my_proto))
  let resp = sp_recv(conn, spHandshakeLen)
  var pos = 0
  let peer = decode_handshake(resp, pos)
  let expected = peer_protocol(my_proto)
  if peer != expected and peer != my_proto:
    raise newException(SpError, "protocol mismatch: expected " & $expected & " got " & $peer)
  conn.peer_proto = peer

# =====================================================================================================================
# TCP transport
# =====================================================================================================================

proc tcp_dial*(host: string, port: int, proto: uint16): SpConn {.raises: [SpError].} =
  ## Connect to a TCP endpoint and perform SP handshake.
  result = SpConn(kind: tkTcp)
  try:
    result.sock = newSocket()
    result.sock.connect(host, Port(port))
  except CatchableError as e:
    raise newException(SpError, "tcp dial: " & e.msg)
  do_handshake(result, proto)

type
  SpListener* = ref object
    ## Listens for incoming SP connections.
    sock*: Socket
    kind*: TransportKind
    proto*: uint16

proc tcp_listen*(port: int, proto: uint16): SpListener {.raises: [SpError].} =
  ## Bind and listen on a TCP port.
  result = SpListener(kind: tkTcp, proto: proto)
  try:
    result.sock = newSocket()
    result.sock.setSockOpt(OptReuseAddr, true)
    result.sock.bindAddr(Port(port))
    result.sock.listen()
  except CatchableError as e:
    raise newException(SpError, "tcp listen: " & e.msg)

proc accept*(listener: SpListener): SpConn {.raises: [SpError].} =
  ## Accept one incoming connection and perform SP handshake.
  result = SpConn(kind: listener.kind)
  var client: Socket
  try:
    listener.sock.accept(client)
  except CatchableError as e:
    raise newException(SpError, "accept: " & e.msg)
  result.sock = client
  do_handshake(result, listener.proto)

proc close*(conn: SpConn) {.raises: [].} =
  if conn != nil:
    if conn.tls_ctx != nil:
      discard libtls.tls_close(conn.tls_ctx)
      libtls.tls_free(conn.tls_ctx)
      conn.tls_ctx = nil
    if conn.sock != nil:
      try: conn.sock.close() except CatchableError: discard

proc close*(listener: SpListener) {.raises: [].} =
  if listener != nil and listener.sock != nil:
    try: listener.sock.close() except CatchableError: discard

# =====================================================================================================================
# IPC transport (Unix domain sockets)
# =====================================================================================================================

proc ipc_dial*(path: string, proto: uint16): SpConn {.raises: [SpError].} =
  ## Connect to a Unix domain socket and perform SP handshake.
  result = SpConn(kind: tkIpc)
  try:
    result.sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    result.sock.connectUnix(path)
  except CatchableError as e:
    raise newException(SpError, "ipc dial: " & e.msg)
  do_handshake(result, proto)

proc ipc_listen*(path: string, proto: uint16): SpListener {.raises: [SpError].} =
  ## Bind and listen on a Unix domain socket.
  result = SpListener(kind: tkIpc, proto: proto)
  try:
    result.sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    result.sock.bindUnix(path)
    result.sock.listen()
  except CatchableError as e:
    raise newException(SpError, "ipc listen: " & e.msg)
