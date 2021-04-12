using Distributed
using Evolutionary

using Infiltrator

# addprocs(2, exeflags="--project=../")

include("_obj_func_definition.jl")


function calibrate(mg, g, v_id, climate, calib_data)

    inlets = inneighbors(g, v_id)
    if !isempty(inlets)
        for ins in inlets
            calibrate(g, mg, ins, climate, calib_data)
        end
    end

    outs = outneighbors(g, v_id)
    @assert length(outs) == 1 || throw("Streamfall currently only supports a single outlet.")
    outs = outs[1]

    this_node = get_prop(mg, v_id, :node)
    next_node = get_prop(mg, outs, :node)
    next_id = next_node.node_id

    # Create new optimization function
    opt_func = x -> obj_func(x, climate, mg, g, v_id, outs, calib_data)

    # Get node parameters
    x0, param_bounds = param_info(this_node; with_level=false)
    lower, upper = collect(zip(param_bounds...))
    lower, upper = collect(lower), collect(upper)

    cnst = BoxConstraints(lower, upper)
    res = Evolutionary.optimize(opt_func, cnst, x0, 
                                DE(), # CMAES()
                                Evolutionary.Options(iterations=Int(1e5), abstol=1e-32)
    )

    bs = Evolutionary.minimizer(res)
    @info "Calibrated $(v_id) ($(this_node.node_id)), with score: $(Evolutionary.minimum(res))"
    @info "Best Params:" bs

    # Update node with calibrated parameters
    update_params!(this_node, bs...)

    return res
end


v_id, node = get_gauge(mg, "406219")
@info "Starting calibration..."
res = calibrate(mg, g, v_id, climate, hist_data)

@info best_fitness(res)
@info best_candidate(res)

@info node


using Plots

dam_id, dam_node = get_gauge(mg, "406000")
timesteps = sim_length(climate)
for ts in (1:timesteps)
    run_node!(mg, g, dam_id, climate, ts; water_order=hist_dam_releases)
end

h_data = hist_dam_levels[:, "Dam Level [mAHD]"]
n_data = dam_node.level

@info "NNSE:" Streamfall.NNSE(h_data, n_data)
@info "RMSE:" Streamfall.RMSE(h_data, n_data)

plot(h_data)
plot!(n_data)


# timesteps = sim_length(climate)
# for ts in (1:timesteps)
#     run_node!(mg, g, 2, climate, ts; water_order=hist_dam_releases)
# end

# node = get_prop(mg, 2, :node)
# plot(node.level)
# plot!(hist_dam_levels[:, "Dam Level [mAHD]"])
