push!(LOAD_PATH,"../src/")

# using Pkg

# pkg"activate .."

using Documenter, Streamfall


makedocs(sitename="Streamfall Documentation",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true"
    ),
    pages = [
        "index.md",
        "primer.md",
        "Examples" => [
            "examples/examples.md",
            "Model evaluation" => [
                "examples/simple_showcase.md",
                "examples/model_comparison.md",
                # "examples/multisystem_showcase.md",
            ],
            "Calibration" => [
                # "examples/calibration_setup.md",
                "examples/calibration.md",
            ]
        ],
        "metrics.md",
        "API" => [
            "Nodes" => [
                "API/nodes/Node.md",
                "API/nodes/IHACRES.md",
                "API/nodes/HyMod.md",
                "API/nodes/GR4J.md",
                "API/nodes/SYMHYD.md",
                "API/nodes/Dam.md"
            ],
            "API/network.md",
            "API/use_methods.md"
        ]
    ]
)

deploydocs(
    repo = "github.com/ConnectedSystems/Streamfall.jl.git",
    devbranch = "main",
    target="build",
    deps=nothing,
    make=nothing
)
