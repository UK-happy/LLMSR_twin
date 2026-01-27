#!/usr/bin/env julia

"""
Trace Evolution Lineage

Traces the evolutionary path of the best model across generations
and creates a visualization with LaTeX mathematical expressions.

Usage:
    julia --project=. trace_evolution_lineage.jl --exp-name trial_2
"""

using JSON3
using ArgParse
using Printf

function parse_commandline()
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--exp-name"
            help = "Experiment name"
            arg_type = String
            default = "trial_2"
    end
    return parse_args(s)
end

"""
    load_history(filepath::String)

Load history from JSONL file
"""
function load_history(filepath::String)
    if !isfile(filepath)
        error("History file not found: $filepath")
    end
    
    history = []
    open(filepath, "r") do io
        for line in eachline(io)
            if !isempty(strip(line))
                entry = JSON3.read(line)
                push!(history, entry)
            end
        end
    end
    
    return history
end

"""
    to_latex(formula::String)

Convert Julia formula to LaTeX notation
"""
function to_latex(formula::String)
    latex = formula
    
    # Replace operators
    latex = replace(latex, "*" => " \\cdot ")
    latex = replace(latex, "exp(" => "e^{")
    
    # Handle exponentials - need to add closing braces
    # This is a simplified approach
    count = 0
    result = ""
    i = 1
    while i <= length(latex)
        if i <= length(latex) - 2 && latex[i:i+2] == "e^{"
            result *= "e^{"
            count += 1
            i += 3
        elseif latex[i] == ')'
            if count > 0
                result *= "}"
                count -= 1
            else
                result *= ")"
            end
            i += 1
        else
            result *= string(latex[i])
            i += 1
        end
    end
    latex = result
    
    # Replace power notation
    latex = replace(latex, r"([a-zA-Z0-9]+)\^(\(.*?\))" => s"\1^{\2}")
    latex = replace(latex, r"([a-zA-Z0-9]+)\^(-?[0-9\.]+)" => s"\1^{\2}")
    
    # Replace common functions
    latex = replace(latex, "sqrt(" => "\\sqrt{")
    latex = replace(latex, "tanh(" => "\\tanh(")
    latex = replace(latex, "abs(" => "|")
    latex = replace(latex, r"\\sqrt\{([^}]+)\}" => s"\\sqrt{\1}")
    
    # Handle division
    latex = replace(latex, " / " => " / ")
    
    # Wrap in display math
    latex = "\$\$ \\\\Delta U = " * latex * " \$\$"
    
    return latex
end

"""
    simplified_formula(formula::String)

Create a simplified version of the formula for display
"""
function simplified_formula(formula::String)
    # Extract key structural elements
    simplified = formula
    
    # Highlight key changes
    key_features = String[]
    
    # Check for power law decay
    if occursin(r"x\^(-?[0-9\.]+)", formula)
        m = match(r"x\^(-?[0-9\.]+)", formula)
        push!(key_features, "x^{$(m.captures[1])}")
    end
    
    # Check for TKE terms
    if occursin(r"k\^([0-9\.]+)", formula)
        m = match(r"k\^([0-9\.]+)", formula)
        push!(key_features, "k^{$(m.captures[1])}")
    elseif occursin("sqrt(k)", formula)
        push!(key_features, "\\sqrt{k}")
    elseif occursin("/ (1 + ", formula) && occursin("*k", formula)
        push!(key_features, "TKE term")
    end
    
    # Check for near-wake correction
    if occursin("exp(-x)", formula) || occursin("exp(-c*x)", formula)
        push!(key_features, "near-wake")
    end
    
    return join(key_features, ", ")
end

struct ModelNode
    generation::Int
    id::Int
    formula::String
    score::Float64
    coefficients::Vector{Float64}
    ep_type::String
    reason::String
    parent_generation::Union{Int, Nothing}
    parent_id::Union{Int, Nothing}
end

"""
    build_genealogy_tree(history::Vector)

Build a dictionary mapping (generation, id) to ModelNode
"""
function build_genealogy_tree(history::Vector)
    tree = Dict{Tuple{Int,Int}, ModelNode}()
    
    for h in history
        if haskey(h, :all_models)
            # all_models is sorted by score, so index 1 is best
            for (i, m) in enumerate(h.all_models)
                # Use actual model ID, not the index
                id = haskey(m, :id) ? m.id : i
                
                # Get coefficients, handling JSON3 arrays
                coeffs = Float64[]
                if haskey(m, :coefficients)
                    try
                        if m.coefficients isa AbstractArray
                            coeffs = convert(Vector{Float64}, m.coefficients)
                        else
                            # Handle single value or other types if necessary
                            push!(coeffs, Float64(m.coefficients))
                        end
                    catch e
                        # println("Warning: Could not parse coefficients for Gen $(h.generation) ID $id: $e")
                    end
                end
                
                score = haskey(m, :score) ? m.score : Inf
                parent_gen = haskey(m, :parent_generation) ? m.parent_generation : nothing
                parent_id_val = haskey(m, :parent_id) ? m.parent_id : nothing
                
                node = ModelNode(
                    h.generation,
                    id,
                    haskey(m, :formula) ? m.formula : "",
                    score,
                    coeffs,
                    haskey(m, :ep_type) ? m.ep_type : "Unknown",
                    haskey(m, :reason) ? m.reason : "",
                    parent_gen,
                    parent_id_val
                )
                tree[(h.generation, id)] = node
            end
        end
    end
    return tree
end

"""
    trace_ancestors(tree::Dict, start_node::ModelNode)

Trace back from start_node to the origin
"""
function trace_ancestors(tree::Dict, start_node::ModelNode)
    path = [start_node]
    current = start_node
    
    # Max iterations to prevent infinite loops
    max_iter = 100
    iter = 0
    
    while current.parent_generation !== nothing && iter < max_iter
        parent_key = (current.parent_generation, current.parent_id)
        
        if haskey(tree, parent_key)
            parent = tree[parent_key]
            push!(path, parent)
            current = parent
        else
            @warn "Parent not found: Gen $(current.parent_generation), ID $(current.parent_id)"
            break
        end
        iter += 1
    end
    
    return reverse(path)
end

"""
    trace_lineage(history::Vector)

Trace the lineage of champion models through generations.
If parent info is available, traces the true lineage.
Otherwise, falls back to connecting best models of each generation.
"""
function trace_lineage(history::Vector)
    if isempty(history)
        return []
    end
    
    # Check if we have parent info in the last generation's best model
    last_gen = history[end]
    
    has_parent_info = false
    if haskey(last_gen, :all_models) && !isempty(last_gen.all_models)
        best_model = last_gen.all_models[1]
        if haskey(best_model, :parent_generation) && best_model.parent_generation !== nothing
            has_parent_info = true
        end
    end
    
    if has_parent_info
        println("   ✓ Parent info detected. Tracing true lineage...")
        tree = build_genealogy_tree(history)
        
        # Find final best model node (Gen N, ID 1)
        # Note: ID 1 is usually the best in the generation, but we should verify
        final_gen_data = history[end]
        final_best_model = final_gen_data.all_models[1] # Assumes sorted
        final_id = haskey(final_best_model, :id) ? final_best_model.id : 1
        
        final_key = (last_gen.generation, final_id)
        
        # Find global best model
        global_best_score = Inf
        global_best_key = (-1, -1)
        
        for ((gen, id), node) in tree
            if node.score < global_best_score
                global_best_score = node.score
                global_best_key = (gen, id)
            end
        end
        
        path_final = []
        if haskey(tree, final_key)
            final_node = tree[final_key]
            path_final = trace_ancestors(tree, final_node)
        end
        
        path_global = []
        if haskey(tree, global_best_key)
            global_node = tree[global_best_key]
            path_global = trace_ancestors(tree, global_node)
        end
        
        # Merge paths
        # Use a Set to avoid duplicates based on (gen, id)
        seen_nodes = Set{Tuple{Int,Int}}()
        merged_path = []
        
        for node in [path_final; path_global]
            key = (node.generation, node.id)
            if !(key in seen_nodes)
                push!(seen_nodes, key)
                push!(merged_path, node)
            end
        end
        
        # Sort by generation
        sort!(merged_path, by = x -> x.generation)
        
        # Convert to simple lineage format
        lineage = []
        for node in merged_path
            push!(lineage, (
                generation = node.generation,
                id = node.id, # Add ID to lineage
                formula = node.formula,
                score = node.score,
                coefficients = node.coefficients,
                reason = node.reason,
                ep_type = node.ep_type,
                parent_generation = node.parent_generation,
                parent_id = node.parent_id
            ))
        end
        
        if !isempty(lineage)
            return lineage
        else
            println("   ⚠ No valid lineage path found. Falling back.")
        end
    else
        println("   ℹ No parent info detected. Using sequential best-model tracing.")
    end
    
    # Fallback / Legacy logic
    lineage = []
    for h in history
        push!(lineage, (
            generation = h.generation,
            id = 1, # Default to ID 1 for best model in fallback
            formula = h.best_model.formula,
            score = h.best_score,
            coefficients = get(h.best_model, :coefficients, Float64[]),
            reason = get(h.best_model, :reason, ""),
            ep_type = get(h.best_model, :ep_type, "EP1"),
            parent_generation = nothing,
            parent_id = nothing
        ))
    end
    
    return lineage
end

"""
    convert_to_latex(formula::String)

Convert a plain text formula to LaTeX notation
"""
function convert_to_latex(formula::String)
    latex = formula
    
    # Replace operators
    latex = replace(latex, " * " => " \\cdot ")
    latex = replace(latex, "*" => " \\cdot ")
    
    # Replace exponents: ^(-n) -> ^{-n}, ^(n) -> ^{n}
    latex = replace(latex, r"\^\((-?\d+\.?\d*)\)" => s"^{\1}")
    # For simple exponents without parens, only wrap if needed
    latex = replace(latex, r"\^(-?\d+\.?\d+)" => s"^{\1}")  # decimals need braces
    latex = replace(latex, r"\^(-?\d{2,})" => s"^{\1}")     # multi-digit numbers need braces
    
    return latex
end

"""
    create_evolution_graph(lineage::Vector)

Create a Mermaid graph showing the evolution path
"""
function create_evolution_graph(lineage::Vector)
    graph = "```mermaid\nflowchart TD\n"
    
    # Define nodes
    for l in lineage
        gen = l.generation
        id = l.id
        score = round(l.score * 1000, digits=3)  # Convert to ×10^-3
        
        # Simplified formula for node label
        formula_short = l.formula
        # Truncate if too long (50 characters)
        if length(formula_short) > 50
            formula_short = formula_short[1:47] * "..."
        end
        
        # Escape special characters for Mermaid
        formula_short = replace(formula_short, "\"" => "'")
        
        node_id = "G$(gen)_$(id)"
        # Simplified label with formula
        score_str = @sprintf("%.3f", score)
        
        # Create compact formula representation
        formula_compact = replace(formula_short, " " => "")
        # Further shorten common patterns while preserving structure
        formula_compact = replace(formula_compact, "a*" => "a·")
        formula_compact = replace(formula_compact, "*" => "·")
        formula_compact = replace(formula_compact, ")^(-" => ")^-")
        
        # Two-line label: Gen# Score on first line, formula on second
        # Use <br/> for Mermaid line breaks
        label = "Gen$gen $score_str e-3<br/>$formula_compact"
        
        graph *= "    $node_id[\"$label\"]\n"
    end
    
    graph *= "\n"
    
    # Define edges based on parent info
    # Create a lookup for quick node existence check
    existing_nodes = Set([(l.generation, l.id) for l in lineage])
    
    for l in lineage
        if l.parent_generation !== nothing && l.parent_id !== nothing
            parent_key = (l.parent_generation, l.parent_id)
            
            # Only draw edge if parent is in the lineage
            if parent_key in existing_nodes
                current_node_id = "G$(l.generation)_$(l.id)"
                parent_node_id = "G$(l.parent_generation)_$(l.parent_id)"
                
                edge_style = "-->"
                edge_label = "Improvement"
                
                if l.ep_type == "EP1"
                    edge_style = "~->"
                    edge_label = "New Structure"
                elseif l.ep_type == "EP3"
                    edge_style = "==>"
                    edge_label = "Physics Fix"
                elseif l.ep_type == "EP4"
                    edge_style = "-.->"
                    edge_label = "Simplification"
                end
                
                graph *= "    $parent_node_id $edge_style |$edge_label| $current_node_id\n"
            end
        end
    end
    
    # Find global best model in lineage
    global_best_idx = argmin([l.score for l in lineage])
    global_best_gen = lineage[global_best_idx].generation
    global_best_id = lineage[global_best_idx].id
    
    # Add styling
    graph *= "\n"
    graph *= "    classDef milestone fill:#f96,stroke:#333,stroke-width:4px\n"
    graph *= "    classDef final fill:#9f6,stroke:#333,stroke-width:4px\n"
    graph *= "    classDef globalBest fill:#ff9,stroke:#f60,stroke-width:6px\n"
    
    # Highlight milestones at roughly equal intervals (simple approach for now)
    if length(lineage) > 5
        milestone_indices = [1, div(length(lineage), 4), div(length(lineage), 2), 
                           3 * div(length(lineage), 4)]
        for idx in milestone_indices
            if idx <= length(lineage) && idx > 0
                l = lineage[idx]
                # Don't overwrite final or global best style
                if (l.generation != lineage[end].generation) && (l.generation != global_best_gen || l.id != global_best_id)
                    graph *= "    class G$(l.generation)_$(l.id) milestone\n"
                end
            end
        end
    end
    
    # Highlight final node(s) - usually the last one in the list is the final generation best
    # But with branching, we might have multiple tips. For now, highlight the one from the last generation.
    last_gen = maximum([l.generation for l in lineage])
    for l in lineage
        if l.generation == last_gen
             if (l.generation != global_best_gen || l.id != global_best_id)
                graph *= "    class G$(l.generation)_$(l.id) final\n"
             end
        end
    end
    
    # Highlight global best
    graph *= "    class G$(global_best_gen)_$(global_best_id) globalBest\n"
    
    graph *= "```\n"
    
    return graph
end

"""
    create_lineage_markdown(lineage::Vector, output_path::String)

Create a markdown document showing the evolution lineage
"""
function create_lineage_markdown(lineage::Vector, output_path::String)
    io_buffer = IOBuffer()
    
    println(io_buffer, "# Model Evolution Lineage")
    println(io_buffer, "")
    
    start_gen = isempty(lineage) ? 1 : lineage[1].generation
    end_gen = isempty(lineage) ? 1 : lineage[end].generation
    
    println(io_buffer, "## Evolution Path from Generation $start_gen to $end_gen")
    println(io_buffer, "")
    println(io_buffer, "This document traces the evolutionary path of the champion model,")
    println(io_buffer, "showing how the mathematical structure evolved across generations.")
    println(io_buffer, "")
    
    # Add evolution graph
    println(io_buffer, "## Evolution Graph")
    println(io_buffer, "")
    println(io_buffer, "The following diagram shows the lineage from Generation $start_gen (origin) to Generation $end_gen (final best model).")
    println(io_buffer, "")
    println(io_buffer, "**Edge types** indicate the evolution strategy:")
    println(io_buffer, "- Solid arrow (→): Improvement (EP2)")
    println(io_buffer, "- Dashed arrow (-→): Simplification (EP4)")
    println(io_buffer, "- Bold arrow (⇒): Physics Fix (EP3)")
    println(io_buffer, "- Wavy arrow (~→): New Structure (EP1)")
    println(io_buffer, "")
    println(io_buffer, "**Node colors:**")
    println(io_buffer, "- 🟨 Gold node: Global Best Model (Lowest Score)")
    println(io_buffer, "- 🟩 Green node: Final Best Model (Gen $end_gen)")
    println(io_buffer, "- 🟥 Pink nodes: Key milestones")
    println(io_buffer, "- ⬜ White nodes: Intermediate generations")
    println(io_buffer, "")
    println(io_buffer, create_evolution_graph(lineage))
    println(io_buffer, "")
    
    # Add LaTeX formula table
    println(io_buffer, "## Model Formulas")
    println(io_buffer, "")
    println(io_buffer, "| Generation | Score (×10⁻³) | Formula | Coefficients |")
    println(io_buffer, "|------------|---------------|---------|--------------|")
    for l in lineage
        gen = l.generation
        score = round(l.score * 1000, digits=3)
        score_str = @sprintf("%.3f", score)
        
        # Convert to LaTeX-style formula
        formula_latex = convert_to_latex(l.formula)
        
        # Format coefficients
        coeffs_str = if !isempty(l.coefficients)
            "[" * join([@sprintf("%.4f", c) for c in l.coefficients], ", ") * "]"
        else
            "N/A"
        end
        
        println(io_buffer, "| Gen$gen | $score_str | \$$(formula_latex)\$ | `$coeffs_str` |")
    end
    println(io_buffer, "")
    
    # Track major milestones
    println(io_buffer, "## Major Milestones")
    println(io_buffer, "")
    
    # Identify key transition points
    milestones = [
        (1, "Initial exploration"),
        (3, "Simplified structure"),
        (6, "TKE term refinement"),
        (8, "Near-wake correction added"),
        (10, "Removal of near-wake term"),
        (11, "Re-addition of near-wake term"),
        (13, "TKE power optimization"),
        (17, "Decay rate fine-tuning"),
        (20, "Final convergence")
    ]
    
    for (gen, milestone) in milestones
        if gen <= length(lineage)
            l = lineage[gen]
            println(io_buffer, "### Generation $gen: $milestone")
            println(io_buffer, "")
            println(io_buffer, "**Strategy**: $(l.ep_type)")
            println(io_buffer, "")
            println(io_buffer, "**Score**: $(round(l.score, digits=8))")
            println(io_buffer, "")
            println(io_buffer, "**Formula**:")
            println(io_buffer, "```")
            println(io_buffer, l.formula)
            println(io_buffer, "```")
            println(io_buffer, "")
            println(io_buffer, "**Reasoning**: $(l.reason)")
            println(io_buffer, "")
        end
    end
    
    # Full generation-by-generation history
    println(io_buffer, "## Complete Evolution History")
    println(io_buffer, "")
    
    for (i, l) in enumerate(lineage)
        improvement = if i > 1
            prev_score = lineage[i-1].score
            rel_imp = (prev_score - l.score) / prev_score * 100
            rel_imp > 0 ? " (↓ $(round(rel_imp, digits=2))%)" : " (↑ $(round(-rel_imp, digits=2))%)"
        else
            ""
        end
        
        println(io_buffer, "### Generation $(l.generation)")
        println(io_buffer, "")
        println(io_buffer, "- **Strategy**: $(l.ep_type)")
        println(io_buffer, "- **Score**: $(round(l.score, digits=8))$improvement")
        println(io_buffer, "")
        println(io_buffer, "**Formula**:")
        println(io_buffer, "```")
        println(io_buffer, l.formula)
        println(io_buffer, "```")
        println(io_buffer, "")
        if !isempty(l.reason)
            println(io_buffer, "_$(l.reason)_")
            println(io_buffer, "")
        end
        println(io_buffer, "---")
        println(io_buffer, "")
    end
    
    # Summary table
    println(io_buffer, "## Evolution Summary Table")
    println(io_buffer, "")
    println(io_buffer, "| Gen | Strategy | Score | Key Change |")
    println(io_buffer, "|-----|----------|-------|------------|")
    
    for l in lineage
        key_change = simplified_formula(l.formula)
        @printf(io_buffer, "| %2d | %s | %.6f | %s |\n", 
                l.generation, l.ep_type, l.score, key_change)
    end
    println(io_buffer, "")
    
    # Statistical summary
    println(io_buffer, "## Statistical Summary")
    println(io_buffer, "")
    scores = [l.score for l in lineage]
    initial_score = scores[1]
    final_score = scores[end]
    total_improvement = (initial_score - final_score) / initial_score * 100
    
    println(io_buffer, "- **Initial Score (Gen 1)**: $(round(initial_score, digits=8))")
    println(io_buffer, "- **Final Score (Gen $(length(lineage)))**: $(round(final_score, digits=8))")
    println(io_buffer, "- **Total Improvement**: $(round(total_improvement, digits=2))%")
    println(io_buffer, "- **Best Score**: $(round(minimum(scores), digits=8)) (Gen $(findmin(scores)[2]))")
    println(io_buffer, "")
    
    # Write to file
    content = String(take!(io_buffer))
    mkpath(dirname(output_path))
    write(output_path, content)
    
    @info "Lineage markdown saved to: $output_path"
    
    return content
end

# Main execution
"""
    load_history(filepath::String)

Load evolution history from JSONL file.
"""
function load_history(filepath::String)
    history = []
    for line in eachline(filepath)
        push!(history, JSON3.read(line))
    end
    return history
end

function main()
    args = parse_commandline()
    exp_name = args["exp-name"]
    
    println("\n======================================================================")
    println("📊 Tracing Evolution Lineage")
    println("======================================================================\n")
    println("Experiment: $exp_name\n")
    
    # Load history
    base_dir = joinpath("results", exp_name)
    history_path = joinpath(base_dir, "history.jsonl")
    
    println("📂 Loading history from: $history_path")
    
    if !isfile(history_path)
        println("❌ History file not found!")
        return
    end
    
    history = load_history(history_path)
    println("   ✓ Loaded $(length(history)) generations\n")
    
    println("🔍 Tracing lineage...")
    lineage = trace_lineage(history)
    
    if isempty(lineage)
        println("❌ Failed to trace lineage.")
        return
    end
    
    output_path = joinpath(base_dir, "evolution_lineage.md")
    println("\n📝 Creating lineage markdown...")
    create_lineage_markdown(lineage, output_path)
    println("[ Info: Lineage markdown saved to: $output_path")
    
    println("\n✅ Lineage Analysis Complete!")
    println("\nOutput: $output_path")
    println("======================================================================\n")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
