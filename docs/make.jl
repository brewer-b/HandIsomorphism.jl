using HandIsomorphism
using Documenter

DocMeta.setdocmeta!(HandIsomorphism, :DocTestSetup, :(using HandIsomorphism); recursive=true)

makedocs(;
    modules=[HandIsomorphism],
    authors="Brian Brewer bbrewer.email@gmail.com",
    sitename="HandIsomorphism.jl",
    format=Documenter.HTML(;
        canonical="https://brewer-b.github.io/HandIsomorphism.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/brewer-b/HandIsomorphism.jl",
    devbranch="main",
)
