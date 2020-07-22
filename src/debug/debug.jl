module Debug

using ..CircoCore

export Run, Step, Stop, MsgStats

struct Run a::UInt8 end 
struct Step a::UInt8 end 
struct Stop a::UInt8 end

for command in (Run, Step, Stop)
    registermsg(command; ui = true)
end

include("msgstats.jl")

end