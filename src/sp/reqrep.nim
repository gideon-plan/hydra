## reqrep.nim -- REQ/REP pattern: request-response.
##
## REQ: send request, wait for reply. Includes 4-byte request ID in header.
## REP: recv request (with ID), send reply (with same ID).

{.experimental: "strict_funcs".}

import std/atomics
import wire, socket, lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpReq* = ref object
    sock: SpSocket
    next_req_id: Atomic[int]
    peer_id: PeerId

  SpRep* = ref object
    sock: SpSocket
    peer_id: PeerId

# =====================================================================================================================
# Request ID encoding
# =====================================================================================================================

proc encode_req_id(id: uint32): string =
  result = newString(4)
  result[0] = char((id shr 24) and 0xFF)
  result[1] = char((id shr 16) and 0xFF)
  result[2] = char((id shr 8) and 0xFF)
  result[3] = char(id and 0xFF)

proc decode_req_id(data: string): (uint32, string) =
  ## Split a received message into (request_id, payload).
  if data.len < 4:
    return (0'u32, data)
  let id = (uint32(uint8(data[0])) shl 24) or
           (uint32(uint8(data[1])) shl 16) or
           (uint32(uint8(data[2])) shl 8) or
           uint32(uint8(data[3]))
  return (id, data[4 .. ^1])

# =====================================================================================================================
# REQ
# =====================================================================================================================

proc new_req*(): SpReq =
  result = SpReq(sock: new_socket(spReq), peer_id: 0)
  result.next_req_id.store(1)

proc connect*(req: SpReq, host: string, port: int): Result[void, SpError] =
  try:
    req.peer_id = req.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc request*(req: SpReq, data: string): Result[string, SpError] =
  ## Send a request and wait for the reply.
  let rid = uint32(req.next_req_id.fetchAdd(1))
  let msg = encode_req_id(rid) & data
  try:
    req.sock.send_to(req.peer_id, msg)
    let (_, resp) = req.sock.recv_any()
    let (resp_id, payload) = decode_req_id(resp)
    if resp_id != rid:
      return Result[string, SpError].bad(SpError(msg: "request ID mismatch"))
    Result[string, SpError].good(payload)
  except SpError as e:
    Result[string, SpError].bad(e[])

proc close*(req: SpReq) =
  if req != nil and req.sock != nil:
    socket.close(req.sock)

# =====================================================================================================================
# REP
# =====================================================================================================================

proc new_rep*(): SpRep =
  SpRep(sock: new_socket(spRep), peer_id: 0)

proc listen*(rep: SpRep, port: int): Result[void, SpError] =
  try:
    rep.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(rep: SpRep): Result[void, SpError] =
  try:
    rep.peer_id = rep.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc recv_request*(rep: SpRep): Result[(uint32, string), SpError] =
  ## Receive a request. Returns (request_id, payload).
  try:
    let (_, data) = rep.sock.recv_any()
    let (rid, payload) = decode_req_id(data)
    Result[(uint32, string), SpError].good((rid, payload))
  except SpError as e:
    Result[(uint32, string), SpError].bad(e[])

proc send_reply*(rep: SpRep, req_id: uint32, data: string): Result[void, SpError] =
  ## Send a reply with the matching request ID.
  let msg = encode_req_id(req_id) & data
  try:
    rep.sock.send_to(rep.peer_id, msg)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc close*(rep: SpRep) =
  if rep != nil and rep.sock != nil:
    socket.close(rep.sock)
