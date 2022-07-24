%% Equations:
%{
2.2
G_output (kx, ky) = H_coh (kx,ky) * G_object (kx - kxn, ky - kyn)
    G_object = object spectrum in the Fourier domain
    G_output = output spectrum of the microscope platform
    H_coh = coherent transfer function of the microscope platform
%}

%% simulate the forward imaging process of Fourier ptychography
% simulate the high resolution complex object

objectAmplitude = double(imread('cameraman.tif'));
phase = double(imread('westconcordorthophoto.png'));
phase = pi*imresize(phase,[256 256])./max(max(phase));
object = objectAmplitude.*exp(1i.*phase);
imshow(abs(object),[]); title('Input complex object');

% Generate the wave vectors for the LED matrix [20-35]
arraysize = 15; % size of LED array
xlocation = zeros(1, arraysize^2);
ylocation = zeros(1, arraysize^2);
LEDgap = 4;     % 4mm gap between adjacent LEDs
LEDheight = 90; % 90mm distance between LED matrix and sample

% generates the spatial positions of the LED elements
for i=1:arraysize % from top left to bottom right
    % ? can I replace 15 with arraysize below ?
    xlocation(1, 1+arraysize*(i-1):15+arraysize*(i-1)) = (-(arraysize-1)/2 : 1 : (arraysize-1)/2)*LEDgap;
    ylocation(1, 1+arraysize*(i-1):15+arraysize*(i-1)) = ((arraysize-1)/2 -(i-1))*LEDgap;
end
% view the spatial positions of the LED elements
% scatter(xlocation, ylocation); 
% title('spatial positions of the LED elements')

% generate incident wave vectors for the 15 x 15 LED elements, assuming the
% object is placed at the (0,0) position
kx_relative = -sin(atan(xlocation/LEDheight));
ky_relative = -sin(atan(ylocation/LEDheight));

%% set up the parameters for the coherent imaging system 
waveLength = 0.63e-6;
k0 = 2*pi/waveLength;
spsize = 2.75e-6;   % sampling pixel size of the CCD
psize = spsize / 4;   % pixel size of the final reconstructed super-resolution image
NA = 0.08;

%% generate the low-pass filtered images
[m,n] = size(object);   % image size of the high resolution object
% [next 3 lines] : Initiaze the low-resolution output 'imSeqLowRes' which is an
% image stack with the dimensions of 64 x 64 x 225
m1 = m/(spsize/psize);
n1 = n/(spsize/psize);  % image size of the final output
imSeqLowRes = zeros(m1, n1, arraysize^2); % output low-res image sequence
% We use 'imSeqLowRes' to store the simulated low-resolution output images
% corresponding to the 225 different LED elements.

kx = k0 * kx_relative;
ky = k0 * ky_relative;
dkx = 2*pi/(psize*n);
dky = 2*pi/(psize*m);
cutoffFrequency = NA *k0;
kmax = pi/spsize;
[kxm, kym] = meshgrid(-kmax:kmax/((n1-1)/2):kmax,-kmax:kmax/((n1-1)/2):kmax);

CTF = ((kxm.^2 + kym.^2)< cutoffFrequency^2);  % coherent transfer function

objectFT = fftshift(fft2(object));
%{ 
In the for loop, we generate the filtered low-resolution images for 
 different LED elements using the equation (2.2) 
%}

for tt = 1:arraysize^2
    kxc = round((n+1)/2+kx(1,tt)/dkx);
    kyc = round((m+1)/2+ky(1,tt)/dky);
    ky1 = round(kyc - (m1-1)/2);
    kyh = round(kyc + (m1-1)/2);
    kx1 = round(kxc - (n1-1)/2);
    kxh = round(kxc + (n1-1)/2);

    % scaling factor to normalise the Fourier magnitude when changing the image size
    imSeqLowFT = (m1/m)^2 * objectFT(ky1:kyh,kx1:kxh).*CTF;   

    % We take the absolute value of the output complex signal, as we lose the phase information in the recording process
    imSeqLowRes(:,:,tt) = abs(ifft2(ifftshift(imSeqLowFT)));    
end

figure; 
subplot(1, 3, 1), imshow(imSeqLowRes(:,:,1),[]), title('1st low res image');
subplot(1, 3, 2), imshow(imSeqLowRes(:,:,113),[]), title('113rd low res image');
subplot(1, 3, 3), imshow(imSeqLowRes(:,:,225),[]), title('225th low res image');

%{
    Output image:
    -   64 x 64
    -   contains only amplitude information, and the phase information is
    lost in the recording process
%}

%% recover the high resolution image
%{
Goal of FP is to recover the high-resolution complex object using the
low-resolution intensity measurements.
%}

% define the order of recovery, we start from the center (113rd image) to 
% the edge of the spectrum (225th image)
seq = gseq(arraysize);  

% I. The FP method makes an initial guess of the high resolution object in the
% spatial domain, sqrt(Ih * exp(i*phi_h))
objectRecover = ones(m,n); % initial guess of object

% Initial guess is transformed to the Fourier domain
objectRecoverFT = fftshift(fft2(objectRecover));

loop = 5;

%{
    V. Steps II - IV are repeated until we acheive a self-consistent 
    solution. 
%}
for tt = 1:loop
     %{
        IV. Repeat II. and III. for different incident angles (select a
        small circular region of the Fourier space and update it with
        measured image data). Each shifted sub-region corresponds to a
        unique, low-resolution intensity measurement I_lm (k_xi, k_yi), and
        each sub-region must overlap with neighbouring sub-regions to
        assure convergence. This iterative updating process continues for
        all N images, at which point the entire high-resolution image in
        the Fourier space has been modified with all low-resolution
        intensity measurements.
     %}
    for i3 = 1:arraysize^2 
        i2 = seq(i3);
        %{
        II. next 8 lines: we select a small sub-region of the initial 
        guess's Fourier spectrum, equivalent to a low-pass filter of the 
        coherent imaging system, and apply the inverse Fourier 
        transformation to generate a low-resolution target image 
        sqrt(I_l * exp(i*phi_l)).
        The position of the low-pass filter is selected to correspond to a
        particular angle of illumination.

        %}
        % next 6 lines: We define the sub-region of the initial guess's
        % Fourier spectrum.
        kxc = round((n+1)/2+kx(1,i2)/dkx);
        kyc = round((m+1)/2+ky(1,i2)/dky);
        ky1 = round(kyc - (m1-1)/2);
        kyh = round(kyc + (m1-1)/2);
        kx1 = round(kxc - (n1-1)/2);
        kxh = round(kxc + (n1-1)/2);
        % We multiply the selected spectrum with the low-pass filter
        lowResFT = (m1/m)^2 * objectRecoverFT(ky1:kyh, kx1:kxh).*CTF;
        % Convert the filtered spectrum back to the spatial domain and
        % generate the low-resolution target image.
        im_lowRes = ifft2(ifftshift(lowResFT));

        %{
        III. next 3 lines: following phase retrival concepts, we replace 
        the target image's amplitude component sqrt(I_l) with the square 
        root of the low-resolution measurement obtained under the 
        illumination angle i, sqrt(I_lm), to form an updated, low-
        resolution target image sqrt(I_lm)*exp(i*phi_l). We then apply 
        Fourier transformation to this updated target image and replace its
        corresponding sub-region of the sample estimates's Fourier spectrum
        %}
        im_lowRes = (m/m1)^2 *imSeqLowRes(:,:,i2) .*exp(1i.*angle(im_lowRes));
        % Transform the updated target image back to Fourier domain
        lowResFT = fftshift(fft2(im_lowRes)).*CTF;
        % Update the corresponding region of the sample estimate's Fourier
        % spectrum
        objectRecoverFT(ky1:kyh, kx1:kxh) = (1-CTF) .* objectRecoverFT(ky1:kyh, kx1:kxh) + lowResFT;
    end
end

%{
 The converged solution in the Fourier space is transformed back to the
 spatial domain to recover a high-resolution field sqrt(I_h)*exp(i*phi_h),
 offering an accurate image of the 2D complex sample.
%}
objectRecover = ifft2(ifftshift(objectRecoverFT));
figure;
subplot(1,3,1)
imshow(abs(objectRecover),[]), title('Fig 2.6: Object Recovered');
subplot(1,3,2)
imshow(angle(objectRecover), []), title('Phase Recovered');
subplot(1,3,3)
imshow(log(objectRecoverFT),[]), title('Recovered Spectrum')


%% Functions
% gseq: to configure the updating sequence of reconstruction

function seqf = gseq(arraysize)

    n = (arraysize+1)/2;
    arraysize = 2*n-1;
    sequence = zeros(2, arraysize^2);
    sequence(1,1) = n;
    sequence(2,1) = n;
    dx=+1;
    dy=-1;
    stepx=+1;
    stepy=-1;
    direction=+1;
    counter = 0;
    
    for i=2:arraysize^2
        counter = counter+1;

        if (direction==+1)
            sequence(1,i) = sequence(1,i-1) + dx;
            sequence(2,i) = sequence(2,i-1);

            if (counter==abs(stepx))
                counter = 0;
                direction = direction*-1;
                dx = dx*-1;
                stepx = stepx*-1;

                if stepx>0
                    stepx = stepx + 1;
                else
                    stepx = stepx - 1;
                end
            end
        else
            sequence(1,i) = sequence(1,i-1);
            sequence(2,i) = sequence(2,i-1) + dy;

            if (counter==abs(stepy))
            
                counter = 0;
                direction = direction*-1;
                dy = dy*-1;
                stepy = stepy*-1;

                if (stepy>0)
                    stepy = stepy+1;
                else
                    stepy = stepy -1;
                end

            end

        end

    end

    seq = (sequence(1,:) - 1)*arraysize + sequence(2,:);
    seqf(1,1:arraysize^2) = seq;

end
