module ReasonScorer

export score_reason

"""
    score_reason(reason::String)

Evaluates the quality of the 'reason' provided by the LLM.
Returns a score between 0.0 (poor) and 1.0 (excellent).
"""
function score_reason(reason::String)
    score = 0.4 # Base score (lowered slightly to emphasize bonuses)
    
    reason_lower = lowercase(reason)
    
    # 1. Keywords Check (Physics terms)
    keywords = ["turbulence", "viscosity", "decay", "gaussian", "profile", "momentum", "energy", "wake", "recovery", "expansion", "symmetry", "asymptotic"]
    keyword_count = sum(occursin(k, reason_lower) for k in keywords)
    
    if keyword_count >= 3
        score += 0.2
    elseif keyword_count >= 1
        score += 0.1
    end
    
    # 2. Penalty Awareness Check (Phase 6 Requirement)
    # Check if the reason mentions P1-P4 or penalties
    penalty_keywords = ["p1", "p2", "p3", "p4", "penalty", "constraint", "violation"]
    if any(occursin(k, reason_lower) for k in penalty_keywords)
        score += 0.2
    end
    
    # 3. Specificity Check
    # Penalize vague terms like "adjusted", "optimized", "better" without context
    vague_terms = ["adjusted", "tweaked", "random", "guess", "somehow"]
    if any(occursin(v, reason_lower) for v in vague_terms)
        score -= 0.1
    end
    
    # 4. Length Check (Too short is bad)
    if length(reason) < 20
        score -= 0.2
    end
    
    # Clamp score
    return clamp(score, 0.1, 1.0)
end

end # module
