module DataLoader

using CSV
using DataFrames

export load_wake_csv

"""
    load_wake_csv(filepath::String)

Loads and preprocesses the wake data CSV.
- Calculates `deltaU = 1 - u`
- Sets `r = y` (coordinate, can be negative)
- Filters for region of interest (2 <= x <= 15)
"""
function load_wake_csv(filepath::String)
    df = CSV.read(filepath, DataFrame)
    
    # Remove divu if present
    if :divu in names(df)
        select!(df, Not(:divu))
    end
    
    # Calculate deltaU (Velocity Deficit)
    # Assuming U_inf = 1.0
    if !(:deltaU in names(df))
        df.deltaU = 1.0 .- df.u
    end
    
    # Set r (Radial coordinate)
    # We use y as r (assuming 2D or centerline slice)
    # Note: r can be negative here, representing y-coordinate.
    if !("r" in names(df))
        if "y" in names(df)
            df.r = df.y
        elseif "z" in names(df)
            df.r = df.z # Fallback if y not present
        else
            error("Cannot determine radial coordinate (r). No 'y' or 'z' column. Available: $(names(df))")
        end
    end
    
    # Filter Region of Interest (Phase 5 settings)
    # x: [2, 15] (Near wake to Far wake transition)
    # r: [-6, 6] (Wake width)
    mask = (df.x .>= 2) .& (df.x .<= 15) .& (abs.(df.r) .< 6)
    df = df[mask, :]
    
    return df
end

end # module
