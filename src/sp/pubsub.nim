## pubsub.nim -- PUB/SUB pattern: topic-based fan-out.
##
## PUB: send to all connected subscribers.
## SUB: subscribe with topic prefix filter; recv only matching messages.

{.experimental: "strict_funcs".}

import std/strutils
import wire, socket, lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpPub* = ref object
    sock: SpSocket

  SpSub* = ref object
    sock: SpSocket
    peer_id: PeerId
    filter: string  ## topic prefix filter; empty = receive all

# =====================================================================================================================
# PUB
# =====================================================================================================================

proc new_pub*(): SpPub =
  SpPub(sock: new_socket(spPub))

proc listen*(pub: SpPub, port: int): Result[void, SpError] =
  try:
    pub.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(pub: SpPub): Result[void, SpError] =
  try:
    discard pub.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc publish*(pub: SpPub, data: string): Result[void, SpError] =
  ## Send data to all connected subscribers.
  try:
    pub.sock.send_all(data)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc close*(pub: SpPub) =
  if pub != nil and pub.sock != nil:
    socket.close(pub.sock)

# =====================================================================================================================
# SUB
# =====================================================================================================================

proc new_sub*(filter: string = ""): SpSub =
  SpSub(sock: new_socket(spSub), peer_id: 0, filter: filter)

proc connect*(sub: SpSub, host: string, port: int): Result[void, SpError] =
  try:
    sub.peer_id = sub.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc set_filter*(sub: SpSub, filter: string) =
  sub.filter = filter

proc recv*(sub: SpSub): Result[string, SpError] =
  ## Receive the next message matching the subscription filter.
  ## Blocks until a matching message arrives.
  while true:
    try:
      let (_, data) = sub.sock.recv_any()
      if sub.filter.len == 0 or data.startsWith(sub.filter):
        return Result[string, SpError].good(data)
      # Non-matching message: discard, read next
    except SpError as e:
      return Result[string, SpError].bad(e[])

proc close*(sub: SpSub) =
  if sub != nil and sub.sock != nil:
    socket.close(sub.sock)
