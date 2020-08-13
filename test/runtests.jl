using SafeTestsets

@time @safetestset "util" begin include("utils/util.jl") end
@time @safetestset "tensor" begin include("utils/tensor.jl") end
@time @safetestset "zygote rules" begin include("utils/zygote_rules.jl") end

@time @safetestset "truncnorm" begin include("truncnorm/truncnorm.jl") end
@time @safetestset "truncnorm rejection" begin include("truncnorm/rejection.jl") end

@time @safetestset "data" begin include("data.jl") end

@time @safetestset "layers" begin include("layers/layers.jl") end
@time @safetestset "binary" begin include("layers/binary.jl") end
@time @safetestset "potts" begin include("layers/potts.jl") end
@time @safetestset "gaussian" begin include("layers/gaussian.jl") end
@time @safetestset "relu" begin include("layers/relu.jl") end
@time @safetestset "drelu" begin include("layers/drelu.jl") end
@time @safetestset "rbm" begin include("rbm.jl") end
@time @safetestset "dbm" begin include("dbm.jl") end
@time @safetestset "gauge" begin include("gauge.jl") end
@time @safetestset "regularize" begin include("regularize.jl") end
@time @safetestset "pseudolikelihood" begin include("pseudolikelihood.jl") end