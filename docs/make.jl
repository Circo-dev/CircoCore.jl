using Documenter, CircoCore

makedocs(;
    modules=[CircoCore],
    format=Documenter.HTML(),
    pages=[
        "index.md",
        "install.md",
        "reference.md"
    ],
    repo="https://github.com/Circo-dev/CircoCore/blob/{commit}{path}#L{line}",
    sitename="CircoCore",
    authors="Krisztián Schaffer",
    assets=String[],
)

deploydocs(;
    repo="github.com/Circo-dev/CircoCore",
)
