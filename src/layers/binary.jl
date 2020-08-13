export Binary

struct Binary{T,N} <: AbstractLayer{T,N}
    θ::Array{T,N}
end
Binary{T}(n::Int...) where {T} = Binary(zeros(T, n...))
Binary(n::Int...) = Binary{Float64}(n...)
fields(layer::Binary) = (layer.θ,)
Flux.@functor Binary
effective_β(layer::Binary, β) = Binary(β .* layer.θ)
effective_I(layer::Binary, I) = Binary(layer.θ .+ I)
_transfer_mode(layer::Binary) = eltype(layer.θ).(layer.θ .> 0)
_cgf(layer::Binary) = log1pexp.(layer.θ)
_transfer_mean(layer::Binary) = sigmoid.(layer.θ)
_transfer_mean_abs(layer::Binary) = _transfer_mean(layer)

function _random(layer::Binary{T}) where {T}
    pinv = @. one(layer.θ) + exp(-layer.θ)
    result = (rand_like(pinv) .* pinv .≤ 1)
    return T.(result)
end

function _transfer_std(layer::Binary)
    t = @. exp(-abs(layer.θ) / 2)
    return @. t * inv(one(t) + t^2)
end

function _transfer_var(layer::Binary)
    t = @. exp(-abs(layer.θ))
    return @. t * inv(one(t) + t)^2
end

#= gradients =#

@adjoint function _cgf(layer::Binary)
    ∂θ = sigmoid.(layer.θ)
    return _cgf(layer), Δ -> ((; θ = ∂θ .* Δ),)
end