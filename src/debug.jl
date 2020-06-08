module Debug

struct Run a::UInt8 end 
struct Step a::UInt8 end 
struct Stop a::UInt8 end

export Run, Step, Stop

end