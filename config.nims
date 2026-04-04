switch("path", "src")
switch("outdir", ".out")
switch("path", thisDir() & "/../libressl/src")

import std/os

# httpffi vendored library link flags for QUIC transport
let httpffi = thisDir() & "/../httpffi"
let ffi = httpffi & "/src/httpffi/ffi"
switch("passC", "-I" & ffi & "/quic/ngtcp2/lib/includes")
switch("passC", "-I" & ffi & "/quic/ngtcp2/build/lib/includes")
switch("passC", "-I" & ffi & "/quic/ngtcp2/crypto/includes")
switch("passL", ffi & "/quic/ngtcp2/build/lib/libngtcp2.a")
switch("passL", ffi & "/quic/ngtcp2/build/crypto/quictls/libngtcp2_crypto_libressl.a")

# Vendored LibreSSL (4.2.1)
let libresslDir = getEnv("HOME") & "/.local/opt/libressl"
switch("passC", "-I" & libresslDir & "/include")
switch("passL", libresslDir & "/lib/libtls.a")
switch("passL", libresslDir & "/lib/libssl.a")
switch("passL", libresslDir & "/lib/libcrypto.a")
switch("passL", "-lpthread")

when file_exists("nimble.paths"):
  include "nimble.paths"
# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config
