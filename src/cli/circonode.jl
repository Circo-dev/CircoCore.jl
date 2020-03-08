# SPDX-License-Identifier: LGPL-3.0-only
module cli
using CircoCore

const VERSION = v"0.1.0"
doc = """Start a Circo cluster node.

Usage:
  circonode.sh [--roots CIRCO_POSTCODE1,...]

Options:
  -r --roots      Connect to an existing cluster using one of the listed nodes.
  -f --rootsfile  Read the list of roots from a file. Separator: comma or newline.
  -a --add        Add the address of this node to the roots file, create the file if missing.
  -h --help       Show this screen.
  --version       Show version.

Examples:
  circonode.sh --roots tcp://192.168.1.11:24721/345d60e5554274be,tcp://192.168.1.11:24722/9e1e5b208732de32 
  Starts a node and connects it to the cluster through one of the listed roots

  circonode -f roots.txt -a
  Starts a node using the roots read from roots.txt and appends its own adress to the file.
  Also creates the file (-a) if it does not exists.

  A single root is enough to build a cluster but you can use as many as you want.
"""
function usage()
    println(doc)
end

function parse_args(args)
    longs = Set(["roots", "rootsfile", "add", "help", "version"])
    shorts = Dict([("-r", "roots"), ("--root", "roots"), ("-f", "rootsfile"),
     ("-a", "add"), ("-h", "help")])
    parsed = Dict()
    key = nothing
    for arg in args
        if isnothing(key) || startswith(arg, "-") 
            try
                key = startswith(arg, "--") ? arg[3:end] : arg
                key in longs || (key = shorts[arg])
                parsed[key] = nothing
            catch
                throw("Invalid argument: $arg")
            end
        else
            parsed[key] = arg
            key = nothing
        end
    end
    return parsed
end

function circonode()
    try
        args = parse_args(ARGS)
        roots = []
        rootsfilename = nothing
        addmetoroots = false
        haskey(args, "help") && (println(doc); return 0)
        haskey(args, "version") && (println(VERSION); return 0)
        haskey(args, "roots") && (append!(roots, parseroots(args["roots"])))
        addmetoroots = haskey(args, "add") && args["add"] != "false"
        if haskey(args, "rootsfile")
            rootsfilename = args["rootsfile"]
            isnothing(rootsfilename) && throw("No roots file provided for --rootsfile or -f")
            append!(roots, readroots(rootsfilename;allow_missing=addmetoroots))
        end
        if isempty(roots)
            startfirstnode(rootsfilename)
        else
            startnodeandconnect(roots; rootsfilename=rootsfilename, addmetoroots=addmetoroots)
        end
    catch e
        e isa String ? (println(stderr, e);return -1) : rethrow()
    end
end

function parseroots(rootstr)
    isnothing(rootstr) && throw("No root given after --roots (aka -r)")
    parts = map(s -> Address(String(s)), split(rootstr, ","))
    return parts
end

function readroots(rootsfilename; allow_missing=false)
    if !isfile(rootsfilename)
        allow_missing ? (return []) : (throw("'$rootsfilename' is not a file. Use --add to create it."))
    end
    roots = []
    open(rootsfilename) do f
        for line in eachline(f)
            line = strip(line)
            length(line) > 0 && !startswith(line, "#") || continue
            append!(roots, parseroots(line))
        end
    end
    return roots
end

function appendaddress(filename, address)
    open(filename, "a") do f
        write(f, "$address\n")
    end
end

function startfirstnode(rootsfilename)
    root = ClusterActor("First Node")
    scheduler = ActorScheduler([root])
    println("Starting first node. To add nodes to this cluster, run:")
    if isnothing(rootsfilename)
        println("./circonode.sh --roots $(address(root))")
    else
        appendaddress(rootsfilename, address(root))
        println("./circonode.sh --rootsfile $rootsfilename")
    end
    scheduler()
end

function startnodeandconnect(roots; rootsfilename=nothing, addmetoroots=false)
    root = ClusterActor(NodeInfo("Another Node"), roots)
    scheduler = ActorScheduler([root])
    if addmetoroots
        appendaddress(rootsfilename, address(root))
    end
    println("Node started. Address of this node $(addmetoroots ? "(added to $rootsfilename)" : ""):")
    println(address(root))
    scheduler()
end

export circonode

end