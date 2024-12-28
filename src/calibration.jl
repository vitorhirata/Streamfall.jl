using Serialization
using BlackBoxOptim
using Distributed


"""Assess the specified node in network."""
function obj_func(
    params, climate::Climate, sn::StreamfallNetwork, v_id::Int, calib_data::Array;
    metric::Function, inflow=nothing, extraction=nothing, exchange=nothing
)
    return obj_func(params, climate, sn[v_id], calib_data; metric=metric, inflow=inflow, extraction=extraction, exchange=exchange)
end


"""Assess current node on its outflow."""
function obj_func(
    params, climate::Climate, node::NetworkNode, calib_data::Array;
    metric::F, inflow=nothing, extraction=nothing, exchange=nothing
) where {F}
    update_params!(node, params...)

    metric_func = (sim, obs) -> handle_missing(metric, sim, obs; handle_missing=:skip)

    run_node!(node, climate; inflow=inflow, extraction=extraction, exchange=exchange)
    score = metric_func(node.outflow, calib_data)

    # Reset to clear stored values
    reset!(node)

    return score
end

"""Assess current node on its outflow."""
function level_obj_func(
    params, climate::Climate, node::NetworkNode, calib_data::Array;
    metric::F=Streamfall.RMSE, inflow=nothing, extraction=nothing, exchange=nothing
) where {F}
    update_params!(node, params...)

    metric_func = (sim, obs) -> handle_missing(metric, sim, obs; handle_missing=:skip)

    run_node!(node, climate; inflow=inflow, extraction=extraction, exchange=exchange)
    score = metric_func(node.level, calib_data)

    # Reset to clear stored values
    reset!(node)

    return score
end


"""
    dependent_obj_func(
        params, climate::Climate, this_node::NetworkNode, next_node::NetworkNode, calib_data::DataFrame;
        metric::F, weighting=0.5, inflow=nothing, extraction=nothing, exchange=nothing
    ) where {F}

Objective function which considers performance of next node and current node.
The weighting factor places equal emphasis on both nodes by default (0.5).
The weighting value places a \$x\$ weight on the current node, and \$1 - x\$ on the next
node.
"""
function dependent_obj_func(
    params, climate::Climate, this_node::NetworkNode, next_node::NetworkNode, calib_data::DataFrame;
    metric::F, weighting=0.5, inflow=nothing, extraction=nothing, exchange=nothing
) where {F}
    update_params!(this_node, params...)

    # Run dependent nodes
    run_node!(
        this_node, climate;
        inflow=inflow, extraction=extraction, exchange=exchange
    )
    run_node!(
        next_node, climate;
        inflow=this_node.outflow, extraction=extraction, exchange=exchange
    )

    metric_func = (sim, obs) -> handle_missing(metric, sim, obs; handle_missing=:skip)

    # Alias data as necessary
    if typeof(next_node) <: DamNode
        # Calibrate against both outflow and dam levels
        sim_data = next_node.level
        obs_data = calib_data[:, next_node.name]

        if weighting == 0.0
            # All emphasis is on dam levels
            score = metric_func(obs_data, sim_data)
        elseif weighting < 1.0
            # Use a mix
            dam_score = metric_func(obs_data, sim_data)

            sim_data = this_node.outflow
            obs_data = calib_data[:, this_node.name]

            flow_score = metric_func(obs_data, sim_data)

            # Use weighted average of the two
            score = (flow_score * weighting) + (dam_score * (1.0 - weighting))
        else
            # Use just outflows
            sim_data = this_node.outflow
            obs_data = calib_data[:, this_node.name]

            score = metric_func(obs_data, sim_data)
        end
    elseif typeof(this_node) <: DamNode
        # Don't bother calibrating DamNodes as they only hold information at this stage.
        score = 0.0  # metric_func(obs_data, sim_data)
    else
        # Calibrate against outflows only
        sim_data = this_node.outflow
        obs_data = calib_data[:, this_node.name]

        score = metric_func(obs_data, sim_data)
    end

    reset!(this_node)
    reset!(next_node)

    return score
end

"""
    _merge_defaults(kwargs)

Combine provided arguments with default arguments.
"""
function _merge_defaults(kwargs)
    defaults = (;
        MaxTime=300,
        # TargetFitness=0.12,
        TraceInterval=30
    )
    kwargs = merge(defaults, kwargs)

    return kwargs
end

"""
    create_callback(kwargs)

Create a custom callback for Streamflow calibration.

Currently, if `MaxTime` is defined for BlackBoxOptim, it will ignore most other settings
assuming calibration should be run for the defined amount of time.

In the Streamflow context, it is useful to define an `OR` condition, where calibration is
allowed to continue for `MaxTime` *or* until a given fitness level is reached.
"""
function create_callback(kwargs)
    target_fitness = get(kwargs, :TargetFitness, nothing)

    if isnothing(target_fitness)
        return (oc) -> nothing
    end

    function callback(oc)
        current_best = best_fitness_of_run(oc)
        if current_best < target_fitness
            BlackBoxOptim.shutdown!(oc)
        end
    end

    return callback
end

"""
    calibrate!(
        sn::StreamfallNetwork, v_id::Int64, climate::Climate, calib_data::DataFrame;
        metric::Function=Streamfall.RMSE, kwargs...
    )

Calibrate just the specified node using the BlackBoxOptim package.
Assumes all nodes upstream have already been calibrated.

Default behavior is to calibrate for 5 mins (300 seconds).

# Arguments
- `sn` : Streamfall Network
- `v_id` : node identifier
- `climate` : Climate data
- `calib_data` : Calibration data for target node by its name.
- `metric` : Optimization function to use. Defaults to RMSE.
- `kwargs` : Additional calibration arguments.
             BlackBoxOptim arguments will be passed through.
"""
function calibrate!(
    sn::StreamfallNetwork, v_id::Int64, climate::Climate, calib_data::DataFrame, metric::Dict{String,F};
    kwargs...
) where {F}
    kwargs = _merge_defaults(kwargs)

    # Fitness of model is dependent on upstream node.
    ins = inlets(sn, v_id)

    if get(kwargs, :calibrate_all, true)
        # Recurse through and calibrate all nodes upstream
        if !isempty(ins)
            for nid in ins
                calibrate!(sn, nid, climate, calib_data, metric; kwargs...)
            end
        end
    end

    this_node = sn[v_id]
    next_node = try
        sn[first(outlets(sn, this_node.name))]
    catch err
        if !(err isa BoundsError)
            throw(err)
        end

        nothing
    end

    extraction = get(kwargs, :extraction, nothing)
    exchange = get(kwargs, :exchange, nothing)

    # Create context-specific optimization function
    if typeof(next_node) <: DamNode
        metric_func = (sim, obs) -> handle_missing(metric[next_node.name], sim, obs; handle_missing=:skip)

        # If the next node represents a dam, attempt to calibrate considering the outflows
        # from the current node and the Dam Levels of the next node.
        weighting = get(kwargs, :weighting, 0.5)
        opt_func = x -> next_node.obj_func(
            x, climate, this_node, next_node, calib_data;
            metric=metric_func, extraction=extraction, exchange=exchange, weighting=weighting
        )
    elseif typeof(this_node) <: DamNode
        metric_func = (sim, obs) -> handle_missing(metric[this_node.name], sim, obs; handle_missing=:skip)
        opt_func = x -> level_obj_func(
            x, climate, this_node, calib_data[:, this_node.name];
            metric=metric_func, extraction=extraction, exchange=exchange
        )
    else
        metric_func = (sim, obs) -> handle_missing(metric[this_node.name], sim, obs; handle_missing=:skip)
        opt_func = x -> this_node.obj_func(
            x, climate, this_node, calib_data[:, this_node.name];
            metric=metric_func, extraction=extraction, exchange=exchange
        )
    end

    # Get node parameters (default values and bounds)
    param_names, x0, param_bounds = param_info(this_node; with_level=false)

    opt = bbsetup(
        opt_func;
        parameters=x0,
        SearchRange=param_bounds,
        CallbackFunction=create_callback(kwargs),
        kwargs...
    )

    @info "Calibrating $(this_node.name)"
    res = bboptimize(opt)

    bs = best_candidate(res)
    @info "Calibrated $(v_id) ($(this_node.name)), with score: $(best_fitness(res))"
    @info "Best Params:" collect(bs)

    # Update node with calibrated parameters
    update_params!(this_node, bs...)

    return res, opt
end

"""
    calibrate!(
        node::NetworkNode, climate::Climate, calib_data::AbstractArray;
        metric::Function=Streamfall.RMSE, kwargs...
    )

Calibrate a given node using the BlackBoxOptim package.

# Arguments
- `node::NetworkNode` : Streamfall node
- `climate` : Climate data
- `calib_data` : calibration data for target node by its id
- `extractor::Function` : Calibration extraction method, define a custom one to change behavior
- `metric::Function` : Optimization function to use. Defaults to RMSE.
"""
function calibrate!(
    node::NetworkNode, climate::Climate, calib_data::AbstractArray, metric::Dict{String,F};
    kwargs...
) where {F}
    _merge_defaults(kwargs)

    next_node = sn[first(outlets(sn, node.name))]

    extraction = get(kwargs, :extraction, nothing)
    exchange = get(kwargs, :exchange, nothing)

    # Create context-specific optimization function
    if next_node <: DamNode
        # If the next node represents a dam, attempt to calibrate considering the outflows
        # from the current node and the Dam Levels of the next node.
        opt_func = x -> next_node.obj_func(x, climate, node, next_node, calib_data; metric=metric[next_node.name], extraction=extraction, exchange=exchange)
    else
        opt_func = x -> node.obj_func(x, climate, node, calib_data; metric=metric[node.name], extraction=extraction, exchange=exchange)
    end

    # Get node parameters (default values and bounds)
    param_names, x0, param_bounds = param_info(node; with_level=false)
    opt = bbsetup(
        opt_func;
        parameters=x0,
        SearchRange=param_bounds,
        x0=x0,
        CallbackFunction=create_callback(kwargs),
        kwargs...
    )

    @info "Calibrating $(node.name)"
    res = bboptimize(opt)

    bs = best_candidate(res)
    @info "Calibrated Node ($(node.name)), with score: $(best_fitness(res))"
    @info "Best Params:" collect(bs)

    # Update node with calibrated parameters
    update_params!(node, bs...)

    return res, opt
end

"""
    calibrate!(
        node::NetworkNode, climate::Climate, calib_data::DataFrame;
        metric::Function=Streamfall.RMSE, kwargs...
    )

Calibrate a given node using the BlackBoxOptim package.

# Arguments
- `node::NetworkNode` : Streamfall node
- `climate` : Climate data
- `calib_data` : Calibration data for target node, where column names indicate node names
- `metric::Function` : Optimization function to use. Defaults to RMSE.
"""
function calibrate!(
    node::NetworkNode, climate::Climate, calib_data::DataFrame, metric::Dict{String,F};
    kwargs...
) where {F}
    return calibrate!(node, climate, calib_data[:, node.name], metric; kwargs...)
end
# function calibrate!(
#     node::NetworkNode, climate::Climate, calib_data::DataFrame;
#     metric::Function=Streamfall.RMSE, kwargs...
# )
#     return calibrate!(node, climate, calib_data[:, node.name]; metric=metric, kwargs...)
# end

"""
    calibrate!(
        sn::StreamfallNetwork, climate::Climate, calib_data::DataFrame;
        metric::Dict{String,F}=Streamfall.RMSE, kwargs...
    )

Calibrate a stream network.
"""
function calibrate!(
    sn::StreamfallNetwork, climate::Climate, calib_data::DataFrame, metric::Dict{String,F};
    kwargs...
) where {F}
    _, outlets = find_inlets_and_outlets(sn)
    for out in outlets
        calibrate!(sn, out, climate, calib_data, metric; kwargs...)
    end

    return nothing
end


"""
Serialize calibration results and optimization object to disk.
"""
function save_calibration!(res, optobj, fn=nothing)
    if isnothing(fn)
        fn = "./temp" * string(rand(1:Int(1e8))) * ".tmp"
    end

    fh = open(fn, "w")
    serialize(fh, (res, optobj))
    close(fh)

    return fn
end


"""
Deserialize calibration results and optimization object from disk.
"""
function load_calibration(fn)
    fh = open(fn, "r")
    (res, optobj) = deserialize(fh)
    close(fh)

    return (res, optobj)
end
