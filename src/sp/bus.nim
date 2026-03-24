## bus.nim -- BUS pattern: full mesh broadcast.
##
## Every node sees every message from every other node.
## Send broadcasts to all peers. Recv from any peer.

{.experimental: "strict_funcs".}

import wire, socket, lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpBus* = ref object
    sock: SpSocket

# =====================================================================================================================
# BUS
# =====================================================================================================================

proc new_bus*(): SpBus =
  SpBus(sock: new_socket(spBus))

proc connect*(bus: SpBus, host: string, port: int): Result[void, SpError] =
  try:
    discard bus.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc listen*(bus: SpBus, port: int): Result[void, SpError] =
  try:
    bus.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(bus: SpBus): Result[void, SpError] =
  try:
    discard bus.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc send*(bus: SpBus, data: string): Result[void, SpError] =
  ## Broadcast data to all peers.
  try:
    bus.sock.send_all(data)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc recv*(bus: SpBus): Result[string, SpError] =
  ## Receive from any peer.
  try:
    let (_, data) = bus.sock.recv_any()
    Result[string, SpError].good(data)
  except SpError as e:
    Result[string, SpError].bad(e[])

proc close*(bus: SpBus) =
  if bus != nil and bus.sock != nil:
    socket.close(bus.sock)
