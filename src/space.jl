# SPDX-License-Identifier: LGPL-3.0-only

struct Infoton
    sourcepos::Pos
    energy::Float16
end

const INFO = 1.0 # Informational constant. TODO define it meaningfully

function apply_infoton(actor::AbstractActor, infoton::Infoton)
    
end