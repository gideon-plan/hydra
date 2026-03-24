## pair.nim -- PAIR pattern: bidirectional 1:1.
##
## Exactly one peer. Send and recv are symmetric.

{.experimental: "strict_funcs".}

import wire, socket, lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpPair* = ref object
    sock: SpSocket
    peer_id: PeerId

# =====================================================================================================================
# Constructor
# =====================================================================================================================

proc new_pair*(): SpPair =
  SpPair(sock: new_socket(spPair), peer_id: 0)

proc connect*(pair: SpPair, host: string, port: int): Result[void, SpError] =
  try:
    pair.peer_id = pair.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc listen*(pair: SpPair, port: int): Result[void, SpError] =
  try:
    pair.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(pair: SpPair): Result[void, SpError] =
  try:
    pair.peer_id = pair.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc send*(pair: SpPair, data: string): Result[void, SpError] =
  try:
    pair.sock.send_to(pair.peer_id, data)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc recv*(pair: SpPair): Result[string, SpError] =
  try:
    let (_, data) = pair.sock.recv_any()
    Result[string, SpError].good(data)
  except SpError as e:
    Result[string, SpError].bad(e[])

proc close*(pair: SpPair) =
  if pair != nil and pair.sock != nil:
    socket.close(pair.sock)
