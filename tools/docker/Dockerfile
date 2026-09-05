# Lua 5.1 + luacheck + busted, the same pair CI runs, for local gate checks on
# a machine with no admin rights. Build once:  docker build -t lootpath-lua tools/docker
# Run:  docker run --rm -v "${PWD}:/work" lootpath-lua busted
FROM alpine:3.21
RUN apk add --no-cache lua5.1 lua5.1-dev luarocks5.1 build-base git \
    && luarocks-5.1 install luacheck \
    && luarocks-5.1 install busted
WORKDIR /work
