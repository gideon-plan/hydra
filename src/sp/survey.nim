## survey.nim -- SURVEY pattern: scatter-gather with deadline.
##
## SURVEYOR: send question to all respondents, collect replies within deadline.
## RESPONDENT: recv question, send reply.

import std/[times, net, locks, tables, nativesockets, posix]
import wire, transport, socket, lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SpSurveyor* = ref object
    sock: SpSocket
    deadline_ms*: int  ## milliseconds to wait for responses

  SpRespondent* = ref object
    sock: SpSocket
    peer_id: PeerId

# =====================================================================================================================
# Socket timeout helper
# =====================================================================================================================

proc set_recv_timeout(conn: SpConn, ms: int) =
  ## Set SO_RCVTIMEO on the underlying socket.
  var tv: Timeval
  tv.tv_sec = posix.Time(ms div 1000)
  tv.tv_usec = Suseconds((ms mod 1000) * 1000)
  discard posix.setsockopt(conn.sock.getFd(), SOL_SOCKET, SO_RCVTIMEO,
                           addr tv, SockLen(sizeof(tv)))

# =====================================================================================================================
# SURVEYOR
# =====================================================================================================================

proc new_surveyor*(deadline_ms: int = 1000): SpSurveyor =
  SpSurveyor(sock: new_socket(spSurveyor), deadline_ms: deadline_ms)

proc listen*(sv: SpSurveyor, port: int): Result[void, SpError] =
  try:
    sv.sock.listen(port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc accept*(sv: SpSurveyor): Result[void, SpError] =
  try:
    discard sv.sock.accept_peer()
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc survey*(sv: SpSurveyor, question: string): Result[seq[string], SpError] =
  ## Send question to all respondents, collect replies within deadline.
  try:
    sv.sock.send_all(question)
  except SpError as e:
    return Result[seq[string], SpError].bad(e[])

  var replies: seq[string] = @[]
  let deadline = getTime() + initDuration(milliseconds = sv.deadline_ms)

  acquire(sv.sock.lock)
  var peer_ids: seq[PeerId] = @[]
  for id in sv.sock.peers.keys:
    peer_ids.add(id)
  release(sv.sock.lock)

  for pid in peer_ids:
    let remaining = (deadline - getTime()).inMilliseconds
    if remaining <= 0:
      break
    acquire(sv.sock.lock)
    let conn = try:
      sv.sock.peers[pid]
    except KeyError:
      release(sv.sock.lock)
      continue
    release(sv.sock.lock)
    set_recv_timeout(conn, int(remaining))
    try:
      let frame = recv_frame(conn)
      replies.add(frame.payload)
    except CatchableError:
      discard  # timeout or error: skip this respondent
    set_recv_timeout(conn, 0)  # reset

  Result[seq[string], SpError].good(replies)

proc close*(sv: SpSurveyor) =
  if sv != nil and sv.sock != nil:
    socket.close(sv.sock)

# =====================================================================================================================
# RESPONDENT
# =====================================================================================================================

proc new_respondent*(): SpRespondent =
  SpRespondent(sock: new_socket(spRespondent), peer_id: 0)

proc connect*(resp: SpRespondent, host: string, port: int): Result[void, SpError] =
  try:
    resp.peer_id = resp.sock.connect(host, port)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc recv*(resp: SpRespondent): Result[string, SpError] =
  try:
    let (_, data) = resp.sock.recv_any()
    Result[string, SpError].good(data)
  except SpError as e:
    Result[string, SpError].bad(e[])

proc respond*(resp: SpRespondent, data: string): Result[void, SpError] =
  try:
    resp.sock.send_to(resp.peer_id, data)
    Result[void, SpError](ok: true)
  except SpError as e:
    Result[void, SpError].bad(e[])

proc close*(resp: SpRespondent) =
  if resp != nil and resp.sock != nil:
    socket.close(resp.sock)
