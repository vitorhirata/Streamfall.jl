using Statistics
using StatsBase


"""
Bounds given metric between -1.0 and 1.0, where 1.0 is perfect fit.

Suitable for use with any metric that ranges from 1 to -∞.

# References
1. Mathevet, T., Michel, C., Andréassian, V., Perrin, C., 2006. 
    A bounded version of the Nash-Sutcliffe criterion for better model 
    assessment on large sets of basins. 
    IAHS-AISH Publication 307, 211–219.
    https://iahs.info/uploads/dms/13614.21--211-219-41-MATHEVET.pdf

# Example
```julia
julia> import Streamfall: @bound, KGE
julia> @bound KGE([1,2], [3,2])
-0.35653767993482094
```
"""
macro bound(metric)
    tmp = :($metric)
    return :($tmp / (2.0 - $tmp))
end


"""
Normalizes given metric between 0.0 and +∞, where 0.0 is perfect fit.

Suitable for use with any metric that ranges from 1 to -∞.

# References
1. Nossent, J., Bauwens, W., 2012.
    Application of a normalized Nash-Sutcliffe efficiency to improve the 
    accuracy of the Sobol’ sensitivity analysis of a hydrological model.
    EGU General Assembly Conference Abstracts 237.

# Example
```julia
julia> import Streamfall: @normalize, KGE
julia> @normalize KGE([1,2], [3,2])
0.1111111111111111
```
"""
macro normalize(metric)
    return :(1.0 / (2.0 - $metric))
end


"""
Applies mean inverse approach to a metric.

Suitable for use with any metric that ranges from 1 to -∞.

If using with other macros such as `@normalize` or `@bound`, 
these must come first.

# References
1. Garcia, F., Folton, N., Oudin, L., 2017.
    Which objective function to calibrate rainfall–runoff
        models for low-flow index simulations?
    Hydrological Sciences Journal 62, 1149–1166.
    https://doi.org/10.1080/02626667.2017.1308511

# Example
```julia
julia> import Streamfall: @normalize, @mean_inverse, KGE
julia> @normalize @mean_inverse KGE [1,2] [3,2]
0.3193505947991363
```
"""
macro mean_inverse(metric, obs, sim)
    obj, o, s = eval(metric), eval(obs), eval(sim)
    q = obj(o, s)
    q2 = obj(1.0 ./ o, 1.0 ./ s)
    return mean([q, q2])
end


"""
Applies split meta metric approach

If using with other macros such as `@normalize` or `@bound`, 
these must come first.

# References
1. Fowler, K., Peel, M., Western, A., Zhang, L., 2018. 
    Improved Rainfall-Runoff Calibration for Drying Climate: 
    Choice of Objective Function. 
    Water Resources Research 54, 3392–3408. 
    https://doi.org/10.1029/2017WR022466

# Example
```julia
julia> using Statistics
julia> import Streamfall: @normalize, @split, KGE
julia> @normalize @split KGE repeat([1,2], 365) repeat([3,2], 365) 365 mean
0.3217309561946589
```
"""
macro split(metric, obs, sim, n, agg_func=mean)
    obj, o, s, t, func = eval(metric), eval(obs), eval(sim), eval(n), eval(agg_func)
    return naive_split_metric(o, s; n_members=t, metric=obj, comb_method=func)
end


"""The Nash-Sutcliffe Efficiency score"""
NSE(obs, sim) = 1.0 - sum((obs .- sim).^2) / sum((obs .- mean(obs)).^2)


"""Normalized Nash-Sutcliffe Efficiency score (bounded between 0 and 1).

# References
1. Nossent, J., Bauwens, W., 2012.
    Application of a normalized Nash-Sutcliffe efficiency to improve the accuracy of the Sobol’ sensitivity analysis of a hydrological model.
    EGU General Assembly Conference Abstracts 237.
"""
NNSE(obs, sim) = 1.0 / (2.0 - NSE(obs, sim))


"""Root Mean Square Error"""
RMSE(obs, sim) = (sum((sim .- obs).^2)/length(sim))^0.5


"""Coefficient of determination (R^2)

Aliases `NSE()`
"""
function R2(obs, sim)::Float64
    return NSE(obs, sim)
end


"""Determine adjusted R^2

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
- `p::Int` : number of explanatory variables
"""
function ADJ_R2(obs, sim, p::Int64)::Float64
    n = length(obs)
    adj_r2 = 1 - (1 - R2(obs, sim)) * ((n - 1) / (n - p - 1))

    return adj_r2
end


"""
Mean Absolute Error
"""
MAE(obs, sim) = mean(abs.(obs .- sim))


"""
    PBIAS(obs::Vector, sim::Vector)::Float64

Percent bias between `sim` and `obs`

Model performance for streamflow can be determined to be
satisfactory if the Nash-Sutcliffe Efficiency (NSE)
score > 0.5, the RMSE standard deviation ratio (RSR) < 0.7
and percent bias (PBIAS) is +/- 25% (see [1]).

# References
1. Moriasi, D.N., Arnold, J.G., Liew, M.W.V., Bingner, R.L.,
    Harmel, R.D., Veith, T.L., 2007.
    Model Evaluation Guidelines for Systematic Quantification
    of Accuracy in Watershed Simulations.
    Transactions of the ASABE 50, 885–900.
    https://doi.org/10.13031/2013.23153
"""
PBIAS(obs, sim) = (sum(obs .- sim) * 100) / sum(obs)


"""
    RSR(obs::Vector, sim::Vector)::Float64

The RMSE-observations standard deviation ratio (RSR).

Varies between 0 and a large positive value, where 0
indicates an RMSE value of 0.

# References
1. Moriasi, D.N., Arnold, J.G., Liew, M.W.V., Bingner, R.L.,
    Harmel, R.D., Veith, T.L., 2007.
    Model Evaluation Guidelines for Systematic Quantification
    of Accuracy in Watershed Simulations.
    Transactions of the ASABE 50, 885–900.
    https://doi.org/10.13031/2013.23153
"""
function RSR(obs, sim)::Float64
    rmse = RMSE(obs, sim)
    σ_obs = std(obs)
    rsr = rmse / σ_obs
    return rsr
end


"""
    KGE(obs::Vector, sim::Vector; scaling::Tuple=nothing)::Float64

Calculate the 2009 Kling-Gupta Efficiency (KGE) metric.

A KGE score of 1 means perfect fit.
A score < -0.41 indicates that the mean of observations
provides better estimates (see Knoben et al., 2019).

The `scaling` argument expects a three-valued tuple
which scales `r`, `α` and `β` factors respectively.
If not specified, defaults to `1`.

Note: Although similar, NSE and KGE cannot be directly compared.

# References
1. Gupta, H.V., Kling, H., Yilmaz, K.K., Martinez, G.F., 2009.
    Decomposition of the mean squared error and NSE performance criteria:
    Implications for improving hydrological modelling.
    Journal of Hydrology 377, 80–91.
    https://doi.org/10.1016/j.jhydrol.2009.08.003

2. Knoben, W.J.M., Freer, J.E., Woods, R.A., 2019.
    Technical note: Inherent benchmark or not? Comparing Nash-Sutcliffe and Kling-Gupta efficiency scores (preprint).
    Catchment hydrology/Modelling approaches.
    https://doi.org/10.5194/hess-2019-327

3. Mizukami, N., Rakovec, O., Newman, A.J., Clark, M.P., Wood, A.W.,
    Gupta, H.V., Kumar, R., 2019.
    On the choice of calibration metrics for “high-flow”
        estimation using hydrologic models.
    Hydrology and Earth System Sciences 23, 2601–2614.
    https://doi.org/10.5194/hess-23-2601-2019
"""
function KGE(obs, sim; scaling=nothing)::Float64
    if isnothing(scaling)
        scaling = (1, 1, 1)
    end

    r = Statistics.cor(obs, sim)
    if isnan(r)
        r = 0.0
    end

    α = std(sim) / std(obs)
    β = mean(sim) / mean(obs)

    rs = scaling[1]
    as = scaling[2]
    bs = scaling[3]

    kge = 1 - sqrt(rs*(r - 1)^2 + as*(α - 1)^2 + bs*(β - 1)^2)

    return kge
end


"""Bounded KGE, bounded between -1 and 1.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
"""
function BKGE(obs, sim)::Float64
    kge = KGE(obs, sim)
    return kge / (2 - kge)
end


"""Normalized KGE between 0 and 1.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
"""
function NKGE(obs, sim; scaling=nothing)::Float64
    return 1 / (2 - KGE(obs, sim; scaling=scaling))
end


"""Calculate the modified KGE metric (2012).

Also known as KGE prime (KGE').

# Arguments
- `obs::Vector`: observations
- `sim::Vector` : modeled results
- `scaling::Tuple` : scaling factors in order of timing (r), magnitude (β), variability (γ).
                     Defaults to (1,1,1).

# References
1. Kling, H., Fuchs, M., Paulin, M., 2012.
    Runoff conditions in the upper Danube basin under an ensemble of climate change scenarios.
    Journal of Hydrology 424–425, 264–277.
    https://doi.org/10.1016/j.jhydrol.2012.01.011
"""
function mKGE(obs, sim; scaling=nothing)::Float64
    if isnothing(scaling)
        scaling = (1,1,1)
    end

    # Timing
    r = Statistics.cor(obs, sim)
    if isnan(r)
        r = 0.0
    end

    # Variability
    cv_s = StatsBase.variation(sim)
    if isnan(cv_s)
        cv_s = 0.0
    end

    cv_o = StatsBase.variation(obs)
    if isnan(cv_o)
        cv_o = 1.0
    end
    γ = cv_s / cv_o

    # Magnitude
    β = mean(sim) / mean(obs)

    rs = scaling[1]
    βs = scaling[2]
    γs = scaling[3]

    mod_kge = 1 - sqrt(rs*(r - 1)^2 + βs*(β - 1)^2 + γs*(γ - 1)^2)

    return mod_kge
end


"""Bounded modified KGE between -1 and 1.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
"""
function BmKGE(obs, sim; scaling=nothing)::Float64
    mkge = mKGE(obs, sim; scaling=scaling)
    return mkge / (2 - mkge)
end


"""Normalized modified KGE between 0 and 1.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
"""
function NmKGE(obs, sim; scaling=nothing)::Float64
    return 1 / (2 - mKGE(obs, sim; scaling=scaling))
end


"""
Mean Inverse NmKGE

Said to produce better fits for low-flow indices
compared to mKGE (see [1]).

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results

# References
1. Garcia, F., Folton, N., Oudin, L., 2017.
    Which objective function to calibrate rainfall–runoff
        models for low-flow index simulations?
    Hydrological Sciences Journal 62, 1149–1166.
    https://doi.org/10.1080/02626667.2017.1308511
"""
mean_NmKGE(obs, sim; scaling=nothing) = mean([Streamfall.NmKGE(obs, sim; scaling=scaling), Streamfall.NmKGE(1.0 ./ obs, 1.0 ./ sim; scaling=scaling)])


"""Calculate the non-parametric Kling-Gupta Efficiency (KGE) metric.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled
- `scaling::Tuple` : scaling factors for timing (s), variability (α), magnitude (β)

# References
1. Pool, S., Vis, M., Seibert, J., 2018.
    Evaluating model performance: towards a non-parametric variant of the Kling-Gupta efficiency.
    Hydrological Sciences Journal 63, 1941–1953.
    https://doi.org/10.1080/02626667.2018.1552002

"""
function npKGE(obs, sim; scaling=nothing)::Float64
    if isnothing(scaling)
        scaling = (1,1,1)
    end

    # flow duration curves
    μ_s = mean(sim)
    if μ_s == 0.0
        fdc_sim = repeat([0.0], length(sim))
    else
        x = length(sim) * μ_s
        fdc_sim = sort(sim / x)
    end

    μ_o = mean(obs)
    x = length(obs) * μ_o
    fdc_obs = sort(obs / x)

    α = 1 - 0.5 * sum(abs.(fdc_sim - fdc_obs))
    if μ_o == 0.0
        β = 0.0
    else
        β = μ_s / μ_o
    end

    r = StatsBase.corspearman(fdc_obs, fdc_sim)
    if isnan(r)
        r = 0.0
    end

    rs = scaling[1]
    αs = scaling[2]
    βs = scaling[3]

    kge = 1 - sqrt(rs*(r - 1)^2 + αs*(α - 1)^2 + βs*(β - 1)^2)

    return kge
end


"""Bounded non-parametric KGE between -1 and 1.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
"""
function BnpKGE(obs, sim; scaling=nothing)::Float64
    npkge = npKGE(obs, sim; scaling=scaling)
    return npkge / (2 - npkge)
end


"""Normalized non-parametric KGE between 0 and 1.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results
"""
function NnpKGE(obs, sim; scaling=nothing)::Float64
    return 1 / (2 - npKGE(obs, sim; scaling=scaling))
end


"""Liu Mean Efficiency metric.

# Arguments
- `obs::Vector` : observations
- `sim::Vector` : modeled results

# References
1. Liu, D., 2020.
    A rational performance criterion for hydrological model.
    Journal of Hydrology 590, 125488.
    https://doi.org/10.1016/j.jhydrol.2020.125488
"""
function LME(obs, sim)::Float64
    μ_o = mean(obs)
    μ_s = mean(sim)
    β = (μ_s / μ_o)

    r = Statistics.cor(obs, sim)
    σ_s = std(sim)
    σ_o = std(obs)
    k_1 = r * (σ_s / σ_o)

    LME = 1 - sqrt((k_1 - 1)^2 + (β - 1)^2)

    return LME
end


function naive_split_metric(obs::Vector, sim::Vector, n_members::Int, metric::Function=NNSE)
    obs_chunks = collect(Iterators.partition(obs, n_members))
    sim_chunks = collect(Iterators.partition(sim, n_members))
    scores = Array{Float64, 1}(undef, length(obs_chunks))

    for (idx, h_chunk) in enumerate(obs_chunks)
        scores[idx] = metric(h_chunk, sim_chunks[idx])
    end

    return scores
end


"""Naive approach to split metrics.

Split metrics are a meta-objective optimization approach which segments data
into subperiods. The objective function is calculated for each subperiod and
then recombined. The approach addresses the lack of consideration of dry years
with least-squares.

In Fowler et al., [1] the subperiod is one year. This method is "naive" in
that the time series is partitioned into `N` chunks of `n_members` and does
not consider date/time.

# Arguments
- `obs::Vector` : Historic observations to compare against
- `sim::Vector` : Modeled time series
- `n_members::Int` : number of members per chunk, defaults to 365
- `metric::Function` : Objective function to apply, defaults to NNSE
- `comb_method::Function` : Recombination method, defaults to `mean`

# References
1. Fowler, K., Peel, M., Western, A., Zhang, L., 2018.
    Improved Rainfall-Runoff Calibration for Drying Climate: Choice of Objective Function.
    Water Resources Research 54, 3392–3408.
    https://doi.org/10.1029/2017WR022466
"""
function naive_split_metric(obs, sim; n_members::Int=365, metric::Function=NNSE, comb_method::Function=mean)
    scores = naive_split_metric(obs, sim, n_members, metric)
    return comb_method(scores)
end


"""
    inverse_metric(obs, sim; metric, comb_method::Function=mean)

A meta-objective function which combines the performance of the
given metric as applied to the discharge and the inverse of the
discharge.

By default, the combination method is to take the mean.

# References
1. Garcia, F., Folton, N., Oudin, L., 2017.
    Which objective function to calibrate rainfall–runoff models
        for low-flow index simulations?
    Hydrological Sciences Journal 62, 1149–1166.
    https://doi.org/10.1080/02626667.2017.1308511
"""
function inverse_metric(obs, sim; metric, comb_method::Function=mean)
    return comb_method([metric(obs, sim), metric(1.0 ./ obs, 1.0 ./ sim)])
end
