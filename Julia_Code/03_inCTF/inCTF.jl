using FFTW, LinearAlgebra;
using Plots, ColorSchemes
using CSV, Tables, DataFrames

# 1 D object
obj_Amplitute_1d = CSV.read("C://.../TestObjectAmplitude.csv", DataFrame, header=false);
obj_Amplitute_1d = Matrix(obj_Amplitute_1d);
plot(obj_Amplitute_1d, legend=false, title="Input Object", ylabel="Amplitude", xlabel="Index")
# 1D Object as a diagonal 2D matrix
obj_Amplitute = Diagonal(vec(obj_Amplitute_1d));
        ######################################

# set up the coherent imaging system (parameters)
λ = 0.5e-6;            # wavelength
k0 = 2*pi/λ;      # wave number
PS = 0.5e-6;           # Pixel size of image sensor
NA = 0.2;              # Numerical aperture of objective lens
CutOffFreq = NA*k0;    # CutOff Frequency

# simulate low pass filtering process of imaging system
FT_obj_Intensity = fftshift(fft(obj_Amplitute));
m = size(obj_Amplitute)[1];
n = size(obj_Amplitute)[2];
pips = (π/PS);
k_x = (-pips):(2*pips/(n-1)):pips;
k_y = (-pips):(2*pips/(n-1)):pips;

#=
duplicate of matlab meshgrid function [Source:https://discourse.julialang.org/t/meshgrid-function-in-julia/48679/3]
=#
function meshgrid(xin,yin)
    nx=length(xin)
    ny=length(yin)
    xout=zeros(ny,nx)
    yout=zeros(ny,nx)
    for jx=1:nx
        for ix=1:ny
            xout[ix,jx]=xin[jx]
            yout[ix,jx]=yin[ix]
        end
    end
    return (x=xout, y=yout)
end

(k_xm, k_ym) = meshgrid(k_x, k_y);
CohTransFunc = (k_ym.^2 + k_xm.^2).<CutOffFreq^2;

cohPSF = fftshift(ifft(ifftshift(CohTransFunc)));
incohPSF = (abs.(cohPSF)).^2;
incohTransFunc = abs.(fftshift(fft(ifftshift(incohPSF))));  #incoherent transfer function
incohTransFunc = incohTransFunc./(maximum(incohTransFunc));

heatmap(incohTransFunc, title="Incoherent Transfer Function"
        ,aspect_ratio=1, grid=false, lims=(0,res_obj),framestyle = :box);
savefig("C://.../inCTF.png")

output_FT = incohTransFunc.*FT_obj_Intensity;
heatmap(log.(abs.(output_FT)), title="Log of absolute of Output in Fourier space",      aspect_ratio=1, grid=false, lims=(0,res_obj),framestyle = :box)
savefig("C://.../LogAbsOutputinFS.png")

output_Int = ifft(ifftshift(output_FT));
output_Amp = abs.(output_Int);

output1D = diag(output_Amp);
input1D = vec(obj_Amplitute_1d);
plot(normalize(input1D), label="Input")
plot!(normalize(output1D), label="Output", marker=true, markersize=2, linestyle=:dash)
plot!(title="Comparing input-output", ylabel="Amplitude", xlabel="Index", legend=:bottomright)
savefig("C://.../inCTF_ComparingInputOutput.png")

    #############################

# Error
error = abs.(normalize(output1D) .- normalize(input1D));
plot(error)
