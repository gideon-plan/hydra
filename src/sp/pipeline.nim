## pipeline.nim -- PUSH/PULL pattern: load-balanced work distribution.
##
## PUSH: send to one of N connected PULLs (round-robin).
## PULL: recv from any connected PUSH.

{.experimental: "strict_funcs".}

import wire, socket, lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpPush* = ref object
    sock: SpSocket

  SpPull* = ref object
    sock: SpSocket

# =====================================================================================================================
# PUSH
# =====================================================================================================================

proc new_push*(): SpPush =
  SpPush(sock: new_socket(spPush))

proc connect*(push: SpPush, host: string, port: int): Result[void, SpError] =
  try:
    discard push.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc listen*(push: SpPush, port: int): Result[void, SpError] =
  try:
    push.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(push: SpPush): Result[void, SpError] =
  try:
    discard push.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc send*(push: SpPush, data: string): Result[void, SpError] =
  ## Send data to the next PULL peer (round-robin).
  try:
    push.sock.send_round_robin(data)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc close*(push: SpPush) =
  if push != nil and push.sock != nil:
    socket.close(push.sock)

# =====================================================================================================================
# PULL
# =====================================================================================================================

proc new_pull*(): SpPull =
  SpPull(sock: new_socket(spPull))

proc connect*(pull: SpPull, host: string, port: int): Result[void, SpError] =
  try:
    discard pull.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc listen*(pull: SpPull, port: int): Result[void, SpError] =
  try:
    pull.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(pull: SpPull): Result[void, SpError] =
  try:
    discard pull.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc recv*(pull: SpPull): Result[string, SpError] =
  try:
    let (_, data) = pull.sock.recv_any()
    Result[string, SpError].good(data)
  except SpError as e:
    Result[string, SpError].bad(e[])

proc close*(pull: SpPull) =
  if pull != nil and pull.sock != nil:
    socket.close(pull.sock)
