using YAML
using Test
using Streamfall, MetaGraphs

@testset "Bare node creation" begin
    test_node = IHACRESNode{Float64}(;
        node_id="Test",
        area=100.0
    )

    @info "Outflow:" run_node!(test_node, 6.0, 3.0, 50.0, 10.0)
end


@testset "Network creation" begin
    # Ensure specified parameter values are being assigned on node creation
    # Load and generate stream network
    network = YAML.load_file("data/campaspe/campaspe_network.yml")
    mg, g = create_network("Example Network", network)

    target_node = get_prop(mg, 1, :node)

    @test target_node.a == 54.352

    @test target_node.level_params[1] == -3.3502
end


@testset "Interim CMD" begin
    params = (214.6561105573191, 76.6251447, 200.0, 2.0, 0.727)
    current_store, rain, d, d2, alpha = params

    interim_results = [0.0, 0.0, 0.0]
    @ccall IHACRES.calc_ft_interim(interim_results::Ptr{Cdouble},
                                   current_store::Cdouble,
                                   rain::Cdouble,
                                   d::Cdouble,
                                   d2::Cdouble,
                                   alpha::Cdouble)::Cvoid
    
    (mf, e_rainfall, recharge) = interim_results

    @test !isnan(mf)
    @test !isnan(e_rainfall)
    @test !isnan(recharge)
end

@testset "Catchment Moisture Deficit" begin
    cmd = 100.0
    et = 6.22
    e_rain = 6.83380027058404E-06
    recharge = 3.84930005080411E-06
    rain = 0.0000188

    n_cmd = @ccall IHACRES.calc_cmd(cmd::Cdouble, rain::Cdouble, et::Cdouble, e_rain::Cdouble, recharge::Cdouble)::Float64

    @test isapprox(n_cmd, 106.22, atol=0.001)
end


@testset "IHACRES calculations" begin
    area = 1985.73
    a = 54.352
    b = 0.187
    e_rain = 3.421537294474909e-6
    recharge = 3.2121031313153022e-6
    loss = 0.0

    prev_quick = 100.0
    prev_slow = 100.0

    flow_results = [0.0, 0.0, 0.0]
    @ccall IHACRES.calc_ft_flows(
        flow_results::Ptr{Cdouble},
        prev_quick::Cdouble,
        prev_slow::Cdouble,
        e_rain::Cdouble,
        recharge::Cdouble,
        area::Cdouble,
        a::Cdouble,
        b::Cdouble,
        loss::Cdouble
    )::Cvoid

    @info flow_results

    @test flow_results[1] == (1.0 / (1.0 + a) * (prev_quick + (e_rain * area)))

    b2 = 1.0
    slow_store = prev_slow + (recharge * area) - (loss * b2)
    slow_store = 1.0 / (1.0 + b) * slow_store
    @test flow_results[2] == slow_store

    e_rain = 0.0
    recharge = 0.0

    prev_quick = 3.3317177943791187
    prev_slow = 144.32012122323678

    flow_results = [0.0, 0.0, 0.0]
    @ccall IHACRES.calc_ft_flows(
        flow_results::Ptr{Cdouble},
        prev_quick::Cdouble,
        prev_slow::Cdouble,
        e_rain::Cdouble,
        recharge::Cdouble,
        area::Cdouble,
        a::Cdouble,
        b::Cdouble,
        loss::Cdouble
    )::Cvoid

    @info flow_results

    @test flow_results[1] == (1.0 / (1.0 + a) * (prev_quick + (e_rain * area)))

    b2 = 1.0
    slow_store = prev_slow + (recharge * area) - (loss * b2)
    slow_store = 1.0 / (1.0 + b) * slow_store
    @test flow_results[2] == slow_store
end