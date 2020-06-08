# Default CircoCore script.
# Overwrite this file with your program or set CIRCO_INITSCRIPT environment variable before starting the node/cluster

const FILE_TO_INCLUDE = "examples/linkedlist.jl"

println("circo.jl: including $(FILE_TO_INCLUDE)")

include(FILE_TO_INCLUDE)
