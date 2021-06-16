# Import common packages and functions
include("_obj_func_definition.jl")


"""Example calibration function.

Illustrate model calibration using the BlackBoxOptim package.
"""
function calibrate(sn, v_id, climate, calib_data)

    # Fitness of model is dependent on next node.
    ins = inlets(sn, v_id)
    next_node_id = outlets(sn, v_id)[1]

    # Recurse through and calibrate all nodes upstream
    if !isempty(ins)
        for nid in ins
            calibrate(sn, nid, climate, calib_data)
        end
    end

    this_node = get_node(sn, v_id)

    # Create new optimization function (see definition inside `_obj_func_definition.jl`)
    opt_func = x -> obj_func(x, climate, sn, v_id, next_node_id, calib_data)

    # Get node parameters (default values and bounds)
    x0, param_bounds = param_info(this_node; with_level=false)
    opt = bbsetup(opt_func; SearchRange=param_bounds,
                  Method=:adaptive_de_rand_1_bin_radiuslimited,
                  MaxTime=2400.0,  # time in seconds to spend
                  TraceInterval=30.0,
                  PopulationSize=75,
                  )
    
    res = bboptimize(opt)

    bs = best_candidate(res)
    @info "Calibrated $(v_id) ($(this_node.node_id)), with score: $(best_fitness(res))"
    @info "Best Params:" collect(bs)

    # Update node with calibrated parameters
    update_params!(this_node, bs...)

    return res, opt
end


v_id, node = get_gauge(sn, "406219")
@info "Starting calibration..."
res, opt = calibrate(sn, v_id, climate, hist_data)

best_params = best_candidate(res)

@info best_fitness(res)
@info best_params


using Plots

update_params!(node, best_params...)
dam_id, dam_node = get_gauge(sn, "406000")
Streamfall.run_node!(sn, dam_id, climate; water_order=hist_dam_releases)

h_data = hist_data["406000"]
n_data = dam_node.level

nnse_score = Streamfall.NNSE(h_data, n_data)
nse_score = Streamfall.NSE(h_data, n_data)
rmse_score = Streamfall.RMSE(h_data, n_data)

@info "Downstream Dam Level NNSE:" nnse_score
@info "Downstream Dam Level RMSE:" rmse_score

reset!(dam_node)

nse = round(nse_score, digits=4)
rmse = round(rmse_score, digits=4)

plot(h_data,
     legend=:bottomleft,
     title="Calibrated IHACRES\n(NSE: $(nse); RMSE: $(rmse))",
     label="Historic", xlabel="Day", ylabel="Dam Level [mAHD]")

plot!(n_data, label="IHACRES")

savefig("calibration_ts_comparison.png")

# 1:1 Plot
scatter(h_data, n_data, legend=false, 
        markerstrokewidth=0, markerstrokealpha=0, alpha=0.2)
plot!(h_data, h_data, color=:red, markersize=.1, markerstrokewidth=0,
      xlabel="Historic [mAHD]", ylabel="IHACRES [mAHD]", title="Historic vs Modelled")

savefig("calibration_1to1.png")


# Best candidate found: [54.9098, 0.135862, 1.22086, 2.99995, 0.309896, 0.0861618, 0.977643, 0.869782]