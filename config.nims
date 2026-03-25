switch("path", "src")

# httpffi vendored library link flags for QUIC transport
let httpffi = thisDir() & "/../httpffi"
let ffi = httpffi & "/src/httpffi/ffi"
switch("passC", "-I" & ffi & "/quic/ngtcp2/lib/includes")
switch("passC", "-I" & ffi & "/quic/ngtcp2/build/lib/includes")
switch("passC", "-I" & ffi & "/quic/ngtcp2/crypto/includes")
switch("passL", ffi & "/quic/ngtcp2/build/lib/libngtcp2.a")
switch("passL", ffi & "/quic/ngtcp2/build/crypto/ossl/libngtcp2_crypto_ossl.a")
switch("passL", "-lssl -lcrypto -lpthread")
