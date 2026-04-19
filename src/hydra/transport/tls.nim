## tls.nim -- TLS over TCP transport for SP.
##
## Uses LibreSSL's libtls for the TLS layer.

{.experimental: "strict_funcs".}

import std/net
import ../wire
import ../transport
import libressl/tls as libtls
import basis/code/choice

proc get_fd(sock: Socket): cint =
  ## Extract the file descriptor from a Nim Socket.
  sock.getFd().cint

# =====================================================================================================================
# TLS dial/listen
# =====================================================================================================================

proc tls_dial*(host: string, port: int, proto: uint16,
               cert_file: string = "", key_file: string = ""
              ): SpConn {.raises: [SpError].} =
  ## Connect to a TLS endpoint and perform SP handshake.
  result = SpConn(kind: TransportKind.Tcp)
  try:
    result.sock = newSocket()
    result.sock.connect(host, Port(port))
  except CatchableError as e:
    raise newException(SpError, "tls dial: " & e.msg)

  # Set up libtls client
  let cfg = tls_config_new()
  if cfg == nil:
    raise newException(SpError, "tls dial: tls_config_new failed")
  tls_config_insecure_noverifycert(cfg)
  tls_config_insecure_noverifyname(cfg)

  let ctx = tls_client()
  if ctx == nil:
    tls_config_free(cfg)
    raise newException(SpError, "tls dial: tls_client failed")

  if tls_configure(ctx, cfg) != 0:
    let err = error_string(ctx)
    tls_free(ctx)
    tls_config_free(cfg)
    raise newException(SpError, "tls dial: " & err)

  if tls_connect_socket(ctx, get_fd(result.sock), "localhost") != 0:
    let err = error_string(ctx)
    tls_free(ctx)
    tls_config_free(cfg)
    raise newException(SpError, "tls dial: " & err)

  # Complete handshake
  var hs: cint
  for _ in 0 ..< 1000:
    hs = tls_handshake(ctx)
    if hs == 0: break
    if hs != TLS_WANT_POLLIN and hs != TLS_WANT_POLLOUT:
      let err = error_string(ctx)
      tls_free(ctx)
      tls_config_free(cfg)
      raise newException(SpError, "tls dial handshake: " & err)

  result.tls_ctx = ctx
  tls_config_free(cfg)
  do_handshake(result, proto)

type
  SpTlsListener* = ref object
    ## TLS-capable listener wrapping a TCP listener.
    inner*: SpListener
    srv_ctx*: TlsCtx
    cfg*: TlsConfig

proc tls_listen*(port: int, proto: uint16,
                 cert_file: string, key_file: string
                ): SpTlsListener {.raises: [SpError].} =
  ## Bind and listen on a TLS port.
  let inner = tcp_listen(port, proto)

  let cfg = tls_config_new()
  if cfg == nil:
    raise newException(SpError, "tls listen: tls_config_new failed")

  if tls_config_set_keypair_file(cfg, cstring(cert_file), cstring(key_file)) != 0:
    let err = config_error_string(cfg)
    tls_config_free(cfg)
    raise newException(SpError, "tls listen: " & err)

  let ctx = tls_server()
  if ctx == nil:
    tls_config_free(cfg)
    raise newException(SpError, "tls listen: tls_server failed")

  if tls_configure(ctx, cfg) != 0:
    let err = error_string(ctx)
    tls_free(ctx)
    tls_config_free(cfg)
    raise newException(SpError, "tls listen: " & err)

  result = SpTlsListener(inner: inner, srv_ctx: ctx, cfg: cfg)

proc tls_accept*(listener: SpTlsListener): SpConn {.raises: [SpError].} =
  ## Accept a TLS connection.
  var client: Socket
  try:
    listener.inner.sock.accept(client)
  except CatchableError as e:
    raise newException(SpError, "tls accept: " & e.msg)

  var accepted_ctx: TlsCtx
  if tls_accept_socket(listener.srv_ctx, addr accepted_ctx, get_fd(client)) != 0:
    let err = error_string(listener.srv_ctx)
    raise newException(SpError, "tls accept: " & err)

  # Complete handshake
  var hs: cint
  for _ in 0 ..< 1000:
    hs = tls_handshake(accepted_ctx)
    if hs == 0: break
    if hs != TLS_WANT_POLLIN and hs != TLS_WANT_POLLOUT:
      let err = error_string(accepted_ctx)
      tls_free(accepted_ctx)
      raise newException(SpError, "tls accept handshake: " & err)

  result = SpConn(kind: TransportKind.Tcp, sock: client, tls_ctx: accepted_ctx)
  do_handshake(result, listener.inner.proto)

proc close*(listener: SpTlsListener) {.raises: [].} =
  if listener != nil:
    if listener.srv_ctx != nil:
      tls_free(listener.srv_ctx)
    if listener.cfg != nil:
      tls_config_free(listener.cfg)
    close(listener.inner)

# =====================================================================================================================
# Choice overloads (non-raising)
# =====================================================================================================================

proc try_tls_dial*(host: string, port: int, proto: uint16,
                   cert_file: string = "", key_file: string = ""
                  ): Choice[SpConn] =
  ## Connect to a TLS endpoint, returning Choice instead of raising.
  try: good(tls_dial(host, port, proto, cert_file, key_file))
  except SpError as e: bad[SpConn]("sp", e.msg)

proc try_tls_listen*(port: int, proto: uint16,
                     cert_file: string, key_file: string
                    ): Choice[SpTlsListener] =
  ## Bind and listen on a TLS port, returning Choice instead of raising.
  try: good(tls_listen(port, proto, cert_file, key_file))
  except SpError as e: bad[SpTlsListener]("sp", e.msg)

proc try_tls_accept*(listener: SpTlsListener): Choice[SpConn] =
  ## Accept a TLS connection, returning Choice instead of raising.
  try: good(tls_accept(listener))
  except SpError as e: bad[SpConn]("sp", e.msg)
