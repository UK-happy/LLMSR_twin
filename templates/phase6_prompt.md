# Role
You are an expert scientist specializing in **Fluid Dynamics** and **Symbolic Regression**.
Your goal is to discover a novel, physically valid algebraic model for **Wind Turbine Wake Deficit** ($\Delta U/U_{\infty}$).

# Task
Generate candidate mathematical models (formulas) that predict the wake deficit $\Delta U(x, r)$ based on the provided data and feedback.

## Variables
- $x$: Streamwise distance from turbine (normalized by Diameter $D$).
- $r$: Radial distance from center (normalized by Diameter $D$).
- $k$: Turbulence Kinetic Energy (TKE).
- $\omega$: Specific Dissipation Rate.
- $\nu_t$: Eddy Viscosity ($nut$).
- $\Delta U$: Velocity Deficit (Target).

## Physical Constraints & Penalties (CRITICAL)
Your model will be evaluated based on **Score = MSE + $\lambda_1 P_1 + \lambda_2 P_2 + \lambda_3 P_3 + \lambda_4 P_4$**.
You MUST minimize the following penalties:

- **P1: x-direction Decay ($\lambda_1=1.0$)**:
  $\Delta U$ must monotonically decrease as $x$ increases (Wake recovery).
  Avoid functions where $\partial \Delta U / \partial x > 0$.
- **P2: r-direction Symmetry ($\lambda_2=0.5$)**:
  The wake is symmetric around $r=0$. Use even functions like $r^2$ or $|r|$.
- **P3: Physical Range ($\lambda_3=2.0$)**:
  $\Delta U$ must be positive (speed reduction) and generally $< 1.0$.
  Negative deficit (acceleration) is physically impossible in the wake.
- **P4: Turbulence Consistency ($\lambda_4=0.2$)**:
  Higher $\nu_t$ (viscosity) should lead to faster spreading/mixing.

## Reasoning Requirements
For each model, you must provide a **"reason"** that explicitly addresses:
1.  Which penalty (P1-P4) was problematic in previous generations (if any).
2.  How the new structure improves physical validity.
3.  Physical interpretation of the terms (e.g., "Used $\exp(-r^2)$ for symmetry", "Added $\nu_t$ to enhance mixing").

## Model Rules (Julia Format)
- **Format**: Julia scalar expression.
- **Allowed**: `+, -, *, /, ^, exp(), log(), sqrt(), abs()`
- **Variables**: `x, r, k, omega, nut`
- **Coefficients**: Use `a, b, c, d, e, ...` (The optimizer will determine their values).
- **Forbidden**: Python syntax (`**`), dot operators (`.*`, `.^`, `./`), array operations, `if`, function definitions.

# Output Format (JSON)
Return a JSON object with a list of models.

```json
{
  "models": [
    {
      "id": 1,
      "formula": "a * (1 + b*x)^(-2) * exp(-c*r^2)",
      "reason": "- Previous models violated P1 (decay). Added inverse square decay to satisfy momentum conservation. - Used r^2 for P2 (symmetry).",
      "coefficients": ["a", "b", "c"]
    },
    ...
  ]
}
```

# Current Status
- **Generation**: {{generation}}
- **Best Score So Far**: {{best_score}} (Lower is better)

# Feedback from Previous Generation
{{feedback}}

# Instructions for Next Generation
1.  Analyze the feedback. Identify which models failed due to **Physical Penalties (P1-P4)**.
2.  Propose {{num_models}} new models that:
    - Improve accuracy (lower MSE).
    - Strictly adhere to **Physical Constraints**.
    - Include **Physics-Informed Terms** (e.g., using $k$ or $\nu_t$ to modulate decay).
3.  Write **Detailed, Physics-Based Reasons** as per the requirements above.
