struct MsgTemplate <: Plugins.TemplateStyle end
Plugins.TemplateStyle(::Type{AbstractMsg}) = MsgTemplate()

Plugins.typedef(::MsgTemplate, spec) = quote
    struct TYPE_NAME{TBody} <: CircoCore.AbstractMsg{TBody}
        sender::CircoCore.Addr
        target::CircoCore.Addr
        body::TBody
        $(Plugins.structfields(spec))
    end;
    TYPE_NAME(sender::CircoCore.Addr, target, body, args...; kwargs...) =
        TYPE_NAME{typeof(body)}(sender, target, body, $(msgfieldcalls(spec)...))
    TYPE_NAME(sender::CircoCore.Actor, target, body, args...; kwargs...) =
        TYPE_NAME{typeof(body)}(CircoCore.addr(sender), target, body, $(msgfieldcalls(spec)...))
    TYPE_NAME
end

msgfieldcalls(spec) = map(field -> :($(field.constructor)(sender, target, body, args...; kwargs...)), spec.fields)

sender(m::AbstractMsg) = m.sender::Addr
target(m::AbstractMsg) = m.target::Addr
body(m::AbstractMsg) = m.body
redirect(m::AbstractMsg, to::Addr) = (typeof(m))(target(m), to, body(m))
