using CircoCore

const VERSION = v"0.1.0"
doc = """Start a Circo cluster node.

Usage:
  circonode [--roots CIRCO_POSTCODE1,...]

Options:
  -h --help     Show this screen.
  --version     Show version.
  -r --roots    Connect to an existing cluster using one of the listed nodes.

Examples:
  circonode --roots tcp://192.168.193.2:24721,tcp://192.168.193.3:24721
"""
function usage()
    println(doc)
end

function parse_args(args)
    shorts = Dict([("-h", "help"), ("-r", "roots"),("--root", "roots")])
    longs = Set(["help", "roots", "version"])
    parsed = Dict()
    key = nothing
    for arg in args
        if isnothing(key)
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

function main()
    try
        args = parse_args(ARGS)
        roots = nothing
        haskey(args, "help") && (println(doc); return 0)
        haskey(args, "version") && (println(VERSION); return 0)
        haskey(args, "roots") && (roots = parseroots(args["roots"]))
        if isnothing(roots)
            startfirstnode()
        else
            startnodeandconnect(roots)
        end
    catch e
        e isa String ? (println(stderr, e);return -1) : rethrow()
    end
end

function parseroots(rootstr)
    isnothing(rootstr) && throw("No root given after --roots (aka -r)")
    parts = map(s -> Address(String(s)), split(rootstr, ","))
    @show parts
end

function startfirstnode()
    root = ClusterActor("First Node")
    scheduler = ActorScheduler([root])
    println("First node started. To join to this cluster, use the address:")
    println(address(root))
    scheduler()
end

function startnodeandconnect(roots)
    root = ClusterActor(NodeInfo("Another Node"), roots)
    scheduler = ActorScheduler([root])
    println("Node started.")
    scheduler()
end

main()