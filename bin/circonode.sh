#!/bin/bash
# SPDX-License-Identifier: LGPL-3.0-only

BOOT_SCRIPT=$(cat <<-END
    using CircoCore
    using CircoCore.cli
    
    # TODO Move this functionality to CircoCore.cli (needs some code-loading gimmick)
    args = parse_args(ARGS)
    initscript = get(ENV, "CIRCO_INITSCRIPT", "circo.jl") 
    if !haskey(args, :help) && !haskey(args, :version)
        if isfile(initscript)
            include(initscript)
        else
            println(stderr, "Cannot open \$(initscript)")
        end
    end
    circonode(@isdefined(zygote) ? zygote : nothing)
END
)
julia --project -e "$BOOT_SCRIPT" -- "$@"