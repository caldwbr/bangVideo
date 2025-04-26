function clicks(nwb, filePath, outFile)
% clicks: Generate an .mp3 of Harvard‐style clicks for each spike,
% with each unit at a slightly different pitch (6–10 kHz).
%
% USAGE:
%   nwb    = nwbRead(filePath);
%   clicks(nwb, filePath, 'bangClicks.mp3');

    %% Parameters
    fs       = 48000;        % Audio sampling rate (Hz)
    clickDur = 0.001;        % Click duration (s)
    tClick   = 0:1/fs:clickDur;  % Time vector for click

    %% 1) Extract spike times
    flatT = nwb.units.spike_times.data.load();
    idx0  = nwb.units.spike_times_index.data.load();
    idx   = double(idx0) + 1;
    nU    = numel(idx);
    spikeTimes = cell(nU,1);
    for u = 1:nU
        sI = idx(u);
        if u < nU
            eI = idx(u+1) - 1;
        else
            eI = numel(flatT);
        end
        spikeTimes{u} = flatT(sI:eI);
    end

    %% 2) Pre‐compute click waveforms at different pitches
    freqs       = linspace(6000, 10000, nU);       % 6–10 kHz per unit
    env         = hann(numel(tClick))';            % Hann envelope
    clickWaves  = zeros(nU, numel(tClick));
    for u = 1:nU
        clickWaves(u,:) = env .* sin(2*pi*freqs(u)*tClick);
    end

    %% 3) Allocate full audio buffer
    % Handle empty spike cells by treating missing as zero
    allMax = cellfun(@(st) max([st(:);0]), spikeTimes);
    tmax   = max(allMax);
    N      = ceil(tmax * fs) + numel(tClick);
    audio  = zeros(N,1);

    %% 4) Insert clicks at spike times
    for u = 1:nU
        for s = spikeTimes{u}(:)'
            idx0 = round(s * fs) + 1;
            if idx0 <= N
                eI  = min(idx0 + numel(tClick) - 1, N);
                len = eI - idx0 + 1;
                audio(idx0:eI) = audio(idx0:eI) + clickWaves(u,1:len)';
            end
        end
    end

    %% 5) Normalize & write to MP3
    audio = audio / max(abs(audio));
    % audiowrite automatically picks MP3 from .mp3 extension; no BitRate param
    audiowrite(outFile, audio, fs);
    fprintf('Saved Harvard click train to %s (fs=%d Hz)\n', outFile, fs);
end
