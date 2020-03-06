#!/bin/bash
julia --project -e "using CircoCore.cli;circonode()" -- "$@"