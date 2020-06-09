#!/bin/bash
# Uses globally installed local-web-server (npm i local-web-server -g), currently needs to be started as "docs/docsdev.sh"

julia --project -e 'include("docs/make.jl")'

cd docs/build && ws -p 8001