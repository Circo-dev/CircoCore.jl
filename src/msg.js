struct MsgTemplate <: Plugins.TemplateStyle end
Plugins.TemplateStyle(::Type{AbstractMsg}) = MsgTemplate()

msgfieldcalls(spec) = map(field -> :($(field.constructor)(sender, target, body, args...; kwargs...)), spec.fields)

Plugins.typedef(::MsgTemplate, spec) = quote
    struct $(spec.name){TBody} <: AbstractMsg{TBody}
        sender::Addr
        target::Addr
        body::TBody
        $(Plugins.structfields(spec))
    end;
    $(spec.name)(sender::Addr, target, body, args...; kwargs...) = $(spec.name){typeof(body)}(sender, target, body, $(msgfieldcalls(spec)...))
    $(spec.name)(sender::AbstractActor, target, body, args...; kwargs...) = $(spec.name){typeof(body)}(addr(sender), target, body, $(msgfieldcalls(spec)...))
    $(spec.name)
end

sender(m::AbstractMsg) = m.sender::Addr
target(m::AbstractMsg) = m.target::Addr
body(m::AbstractMsg) = m.body
redirect(m::AbstractMsg, to::Addr) = (typeof(m))(target(m), to, body(m))
