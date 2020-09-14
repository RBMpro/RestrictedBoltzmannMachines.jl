export RBM, vdims, hdims, ndvis, ndhid, vsize, hsize, flip_layers
export energy, free_energy
export inputs_h_to_v, inputs_v_to_h
export sample_v_from_h, sample_h_from_v
export sample_v_from_v, sample_h_from_h
export reconstruction_error

struct RBM{V<:AbstractLayer, H<:AbstractLayer, W<:AbstractArray}
    vis::V
    hid::H
    weights::W
    function RBM{V,H,W}(v::V, h::H, w::W) where {T,V<:AbstractLayer{T},H<:AbstractLayer{T},W<:AbstractArray{T}}
        size(w) == (size(v)..., size(h)...) || dimserror()
        new{V,H,W}(v, h, w)
    end
end
RBM(v::AbstractLayer, h::AbstractLayer, w::AbstractArray) =
    RBM{typeof(v), typeof(h), typeof(w)}(v, h, w)
function RBM(v::AbstractLayer{T}, h::AbstractLayer{T}) where {T}
    w = zeros(T, size(v)..., size(h)...)
    RBM(v, h, w)
end

# Make RBM parameters reachable via `Flux.params`
Flux.@functor RBM

vdims(rbm::RBM) = OneHot.tuplen(Val(ndims(rbm.vis)))
hdims(rbm::RBM) = OneHot.tuplen(Val(ndims(rbm.hid))) .+ ndims(rbm.vis)
vsize(rbm::RBM) = size(rbm.vis)
hsize(rbm::RBM) = size(rbm.hid)
vis_type(::RBM{V,H,W}) where {V,H,W} = V

function checkdims(rbm::RBM, v::AbstractArray, h::AbstractArray)
    checkdims(rbm.vis, v)
    checkdims(rbm.hid, h)
    batchsize(rbm.vis, v) == batchsize(rbm.hid, h) || dimserror()
end

"""
    flip_layers(rbm)

Returns a new RBM where the visible and hidden layers have been
interchanged.
"""
flip_layers(rbm::RBM) = RBM(rbm.hid, rbm.vis, permutedims(rbm.weights, (hdims(rbm)..., vdims(rbm)...)))

"""
    energy(rbm, v, h)

Energy of the rbm in the configuration (v,h).
"""
function energy(rbm::RBM, v::AbstractArray, h::AbstractArray)
    checkdims(rbm, v, h)
    Ev = energy(rbm.vis, v)
    Eh = energy(rbm.hid, h)
    Ew = interaction_energy(rbm, v, h)
    Ev + Eh + Ew
end

"""
    interaction_energy(rbm, v, h)

Weight mediated interaction energy.
"""
function interaction_energy(rbm::RBM, v::AbstractArray, h::AbstractArray)
    checkdims(rbm, v, h)
    -tensordot(v, rbm.weights, h)
end

"""
    sample_h_from_v(rbm, v, β=1)

Samples a hidden configuration conditional on the visible configuration `v`.
"""
function sample_h_from_v(rbm::RBM, v::AbstractArray, β=1)
    Ih = inputs_v_to_h(rbm, v)
    random(rbm.hid, Ih, β)
end

"""
    sample_v_from_h(rbm, h, β=1)

Samples a visible configuration conditional on the hidden configuration `h`.
"""
function sample_v_from_h(rbm::RBM, h::AbstractArray, β=1)
    Iv = inputs_h_to_v(rbm, h)
    random(rbm.vis, Iv, β)
end

"""
    sample_v_from_v(rbm, v, β=1)

Samples a visible configuration conditional on another visible configuration `v`.
"""
function sample_v_from_v(rbm::RBM, v::AbstractArray, β=1; steps=1)
    for step in 1:steps
        h = sample_h_from_v(rbm, v, β)
        v = sample_v_from_h(rbm, h, β)
    end
    return v
end

"""
    sample_h_from_h(rbm, h, β=1)

Samples a hidden configuration conditional on another hidden configuration `h`.
"""
function sample_h_from_h(rbm::RBM, h::AbstractArray, β=1; steps=1)
    for step in 1:steps
        v = sample_v_from_h(rbm, h, β)
        h = sample_h_from_v(rbm, v, β)
    end
    return h
end

"""
    free_energy(rbm, v, β=1)

Free energy of visible configuration (after marginalizing hidden configurations).
"""
function free_energy(rbm::RBM, v::AbstractArray, β=1)
    Ev = energy(rbm.vis, v)
    Ih = inputs_v_to_h(rbm, v)
    Γh = cgf(rbm.hid, Ih, β)
    return Ev - Γh
end

"""
    reconstruction_error(rbm, v, β=1)

Stochastic reconstruction error of `v`.
"""
function reconstruction_error(rbm::RBM, v::AbstractArray, β=1)
    mean(abs.(v .- sample_v_from_v(rbm, v, β)))
end

"""
    inputs_v_to_h(rbm, v)

Interaction inputs from visible to hidden layer.
"""
inputs_v_to_h(rbm::RBM, v::AbstractArray) =
    _inputs_v_to_h(rbm.weights, v, Val(ndims(rbm.vis)))

"""
    inputs_h_to_v(rbm, h)

Interaction inputs from hidden to visible layer, considering all hidden units.
"""
inputs_h_to_v(rbm::RBM, h::AbstractArray, hsel::Nothing = nothing) =
    _inputs_h_to_v(rbm.weights, h, Val(ndims(rbm.hid)))

"""
    inputs_h_to_v(rbm, h, hsel::CartesianIndices)

Interaction inputs from hidden to visible layer. Pass `hsel` (CartesianIndices)
to consider the contributions of a subset of hidden units only.
"""
function inputs_h_to_v(rbm::RBM, h::AbstractArray, hsel::CartesianIndices)
    vsel = CartesianIndices(size(rbm.vis))
    bidx = batchindices(rbm.hid, h)
    _inputs_h_to_v(rbm.weights, h, Val(ndims(rbm.hid)), vsel, hsel, bidx)
end

#= gradients =#

# https://github.com/FluxML/Zygote.jl/issues/692
_inputs_v_to_h(w, v, ::Val{dims}) where {dims} = tensormul_ff(w, v, Val(dims))
_inputs_h_to_v(w, h, ::Val{dims}) where {dims} = tensormul_lf(w, h, Val(dims))
_inputs_h_to_v(w, h, ::Val{dims}, vidx, hidx, bidx) where {dims} =
    tensormul_lf(w[vidx, hidx], h[hidx, bidx], Val(dims))

@adjoint function _inputs_v_to_h(w, v, ::Val{dims}) where {dims}
    back(Δ) = (tensormul_ll(v, Δ, Val(ndims(v) - dims)), nothing, nothing)
    _inputs_v_to_h(w, v, Val(dims)), back
end

@adjoint function _inputs_h_to_v(w, h, ::Val{dims}) where {dims}
    back(Δ) = (tensormul_ll(Δ, h, Val(ndims(h) - dims)), nothing, nothing)
    _inputs_h_to_v(w, h, Val(dims)), back
end

@adjoint function _inputs_h_to_v(w, h, ::Val{dims}, vidx, hidx, bidx) where {dims}
    function back(Δ)
        ∂w = zero(w)
        ∂w[vidx, hidx] .= tensormul_ll(Δ, h[hidx, bidx], Val(ndims(h) - dims))
        return (∂w, nothing, nothing, nothing, nothing, nothing)
    end
    _inputs_h_to_v(w, h, Val(dims), vidx, hidx, bidx), back
end
