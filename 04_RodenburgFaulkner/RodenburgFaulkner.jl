using FFTW, LinearAlgebra, Plots, ColorSchemes, StatsBase

## Reference:
#=
    A Phase retrival algorithm for shifting illumination
        J. M. Rodenburg and H. M. L. Faulkner
        15 November 2004
        Applied Physics Letters
        Vol. 85
        No. 20
        https://aip.scitation.org/doi/10.1063/1.1823034
=#

include(".../02_ForwardModel/ForwardModel.jl");

# Setting up system and directory
cd(".../04_RodenburgFaulkner")

#= imports:    
    ω: freq domain
    Δω: resolution of ω
    t: time domain
    Δt: resolution of t

    object: object ∈ ℂ
    obj_amp: object Amplitude
    obj_phase: object phase
    Probe_set : set of dimension 1:2001 × -m_end:m_end
    Int_Measured : Set of internsity measurements 1:2001 × -m_end:m_end
=#

#=
Algorithm
   7. Move to the next position of 𝐑, for which the illumination in part overlaps
        with that of the previous position.
    8. Repeat (2) - (7) until the sum squared error (SSE) is sufficiently small. 
        The SSE is measured in the diffraction plane as
            SSE = (|Ψ(𝐤,𝐑)|²-|Ψᵧ,ₙ(𝐤,𝐑)|²)²/N
        where N is the number of pixels in the array representing the wave function.  
=#

# Initial vectors and variables
N = length(ω);  # number of pixels in the array

#O_i_amp = peak₋₂ .+ peak₋₁ .+ peak₂; #initial guess of object
obj_amp = abs.(object);
int_of_change = Int64(floor(N/5)):2:Int64(floor(4*N/5));
min_obj_amp = minimum(obj_amp[int_of_change])
O_i_amp = obj_amp;

#=
a = 1.0;    # height of peak
b = 0.04;    # centre of peak
c² = 0.01;   # c = standard deviation : controls width

phase_i = normalize(Gaussian(ω, a, b.+(m*Δω), c²));
=#
phase_i = obj_phase;

for i in int_of_change
    global phase_i[i] = phase_i[i] + rand(-0.2:0.00001:0.2);
    global O_i_amp[i] = O_i_amp[i] + rand(-min_obj_amp:0.00001:0.02);
end

#2.0 .*tanh.(7.0.*ω);

#= Step 1:
    Start with an initial guess of the object function. 𝑂_1 ∈ ℝ?  
=#
O_1 = O_i_amp.*exp.(im.*phase_i);  

#plot initial object guess
p_O_amp = plot(ω, O_i_amp
    , ylabel="|O₁(ω)|", xlabel="ω"
    , label=false, title="Initial object's amplitude"
    , linewidth = 2
    );
p_O_phase = plot(ω, phase_i
    , ylabel="θ₁(ω)", xlabel="ω"
    , label=false, title="Initial object's phase"
    , linewidth = 2
    );
plot(p_O_amp, p_O_phase, layout=2, size=(1800, 600))
#savefig("RF_Alg_InitialObject.png")

probe_offset_0 = -m_end; #Offset of Probe
probe_offset_end = m_end;

# create an object matrix to store updated objects
Object = zeros(N, M_max) + im .*zeros(N, M_max);
Object = OffsetArray(Object,1:N, -m_end: m_end);
Object[:, probe_offset_0] = O_1;


"""
    O_new(O_old, P, α, β, ψ_c, ψ_g)
    
    O_old   is 𝑂ᵧ,ₙ(𝐫) 
    P       is the probe [P(𝐫-𝐑)]
    α       ∈ ℝ⁺
    β       ∈ ℝ⁺
    ψ_c     is the corrected ψ [ψc,n(r,𝐑)]
    ψ_g     is the guessed ψ [ψᵧ,ₙ(r,𝐑)]
Update function for object
        Update the guessed object wave function in the area covered by the probe, using the update function
              𝑂ᵧ,ₙ₊₁(𝐫) = 𝑂ᵧ,ₙ(𝐫) + (|P(𝐫-𝐑)|/|Pₘₐₓ(𝐫-𝐑)|)(P*(𝐫-𝐑)/(|P(𝐫-𝐑)|²+α)) 
                          × β(ψc,n(r,𝐑)- ψᵧ,ₙ(r,𝐑))
"""
function O_new(O_old, P, α, β, ψ_c, ψ_g)
    P = vec(P);
    O_old = vec(O_old);
    ψ_c = vec(ψ_c);
    ψ_g = vec(ψ_g);
    a = abs.(P)/(maximum(abs.(P))); # a = (|P(𝐫-𝐑)|/|Pₘₐₓ(𝐫-𝐑)|)
    b = (1/(norm(P)^2+α)).*conj.(P); #b = (P*(𝐫-𝐑)/(|P(𝐫-𝐑)|²+α))
    c = β.*(ψ_c-ψ_g);  # c = β(ψc,n(𝐫,𝐑)- ψᵧ,ₙ(𝐤,𝐑))             
    return O_old + a.*b.*c
end

"""
    SSqE(Ψ, Ψ_g, len_N)

Sum squared error
SSE = (|Ψ(𝐤,𝐑)|²-|Ψᵧ,ₙ(𝐤,𝐑)|²)²/N
"""
function SSqE(Ψ, Ψ_g, len_N)
    Ψ = vec(Ψ);
    Ψ_g = vec(Ψ_g);
    return ((norm(Ψ)^2 - norm(Ψ_g)^2)^2)/(len_N);   
end

# vector storing SSE
SSqE_it = zeros(size(Probe_set)[2],2);
SSqE_it = OffsetArray(SSqE_it,probe_offset_0:probe_offset_end,0:1);


# setting parameters
alpha = 0.0;
beta = 5.0;
ϵ = 1.0e-9;

i= probe_offset_0;  #begining of loop
i_end = probe_offset_end;   # end of loop (maximum i)

while i<=probe_offset_end
    probe_offset = i;
    # current probe 
    Probe_i = Probe_set[:,probe_offset];
    # Associated sqrt of intensity reading
    mod_read_i = sqrt.(Int_Measured[:, probe_offset]);
    
    # Step 1: Current guess for object
    O_i = Object[:,i];

    #= Step 2:
    Produce the guessed exit wave function for position 𝐑,
        ψᵧ,ₙ(𝐫,𝐑) = 𝑂ᵧ,ₙ(𝐫).𝑃(𝐫-𝐑) =#
    ψ_i = O_i .* Probe_i;
    
    #= Step 3:
    Transform ψᵧ,ₙ(𝐫,𝐑) to get the wave function in the diffraction space plane
        Ψᵧ,ₙ(𝐤,𝐑) = ℱ[ψᵧ,ₙ(𝐫,𝐑)]
    Ψ is a "guessed" version of the actual wave function in diffraction space. =#
    Ψ_γ_i = fftshift(fft(ψ_i));
    # Decompose into Amplitude and Phase 
    abs_Ψ_γ_i = abs.(Ψ_γ_i);        # Amplitude of guess
    phase_Ψ_γ_i = angle.(Ψ_γ_i);    # phase of guess
    
    #= Step 4:
    Correct the intensities of the guessed wave function to known values,
        Ψc,n(𝐤,𝐑) = |Ψ(𝐤,𝐑)|exp(iθᵧ,ₙ(𝐤,𝐑))
    where |Ψ(𝐤,𝐑)| is known modulus. =#
    Ψ_c_i = mod_read_i.*exp.(im*phase_Ψ_γ_i);
    
    #= Step 5
    Inverse transform back to real space to obtain the new and improved guess at 
    the exit wave function
        ψc,n(𝐫,𝐑) = ℱ ⁻¹[Ψc,n(𝐤,𝐑)] =#
    ψ_c_i = ifftshift(ifft(Ψ_c_i));
    
    #= Step 6
    Update the guessed object wave function in the area covered by the probe, using the update function
        𝑂ᵧ,ₙ₊₁(𝐫) = 𝑂ᵧ,ₙ(𝐫) + (|P(𝐫-𝐑)|/|Pₘₐₓ(𝐫-𝐑)|)(P*(𝐫-𝐑)/(|P(𝐫-𝐑)|²+α)) 
                    × β(ψc,n(𝐫,𝐑)- ψᵧ,ₙ(𝐤,𝐑))
    =#
    O_iplus1 = O_new(O_i, Probe_i, alpha, beta, ψ_c_i, ψ_i);
    
    # calculate the SSE 
    SSE = SSqE(Ψ_c_i, Ψ_γ_i, N);
    if i<probe_offset_end
        global Object[:,i+1] = O_iplus1; #update object array
        global SSqE_it[i,1] = SSE; #update SSE vector
    end
    # check if SSE is satisfied
    if SSE<ϵ
        global i_end = i;
        global i = probe_offset_end+10;
    else
        global i=i+1;
    end

    println(i)

end
print("Loop Over")
#=
#plot final, true and initial phase
pot(ω, (angle.(Object[:,i_end]))
    , label="final"
    , legend=:topleft
    , color=:red
    , alpha = 0.8)
plot!(ω, (angle.(object))
    , label="true"
    , color=:green
    , linewidth = 2)
#=
    plot!(ω, (angle.(Object[:,probe_offset_0]))
    , label = "initial guess"
    , color=:blue
    , linewidth = 1.8
    , linestyle=:dashdot
    , alpha = 0.5)
    =#
plot!(title="Object phase; α="*string(alpha)*", β="*string(beta)
    , ylabel="θ(ω)", xlabel= "ω"
    , legendfontsize=12)
plot!(size=(1500,600))
l
#savefig("RF_Output_ObjPhase.png")

#plot final, true and initial amplitude
plot(ω, (abs.(Object[:,i_end]))
    , label="final"
    , legend=:topleft
    , color=:red
    , alpha = 0.8
    , linewidth = 2)
plot!(ω, (abs.(object))
    , label="true"
    , color=:green
    , linewidth = 2)
#=plot!(ω, (abs.(Object[:,probe_offset_0]))
    , label = "initial guess"
    , color=:blue
    , linestyle=:dot
    , linewidth = 2)
    =#
plot!(title="Object amplitude; α="*string(alpha)*", β="*string(beta)
    , ylabel="|O(ω)|", xlabel="ω"
    , legendfontsize=12, legend=:top)
plot!(size=(1500,600))

#savefig("RF_Output_ObjAmp.png")

=#

# Plotting the SSE
SSqE_it = vec(SSqE_it[:,1]);
end_SSqE = round(SSqE_it[end-1],digits=7);
plot(SSqE_it[probe_offset_0:(i_end-1)]
    , size = (1400,600)
    , title = "SSE"
    , legendtitle = "[α,β]"
    , label = string("[",alpha,",",beta,"]")
    , xticks = 1.0:1.0:length(SSqE_it)
    , xlabel = "Iteration (n)"
    , ylabel = "SSE(n)"
    , marker = true
    #, color = :red
    )
# annotate the last point
annotate!(i_end-1.3,SSqE_it[i_end]+0.0002,string(end_SSqE))

#savefig("SSE_RF_Alg_alphabeta_multi.png")    
