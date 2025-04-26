% bangVideo.m
function bangVideo(nwb, filePath)
% bangVideo  Render full‐session 640×480 @25 fps MP4 (silent) with:
%   • Top: eye‐trace (or TTL), fixed 1280×1024 bounds
%   • Bottom: 5 s right‐aligned sliding‐window spike raster over all units
%
% USAGE:
%   nwb = nwbRead(filePath);
%   bangVideo(nwb, filePath);

    %% 1) Extract spike times
    flatT = nwb.units.spike_times.data.load();
    idx0  = nwb.units.spike_times_index.data.load();
    idx   = double(idx0) + 1;
    nU    = numel(idx);
    fprintf('Detected %d units\n', nU);
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

    %% 2) Map electrodes → brain regions
    elecIDs = double( h5read(filePath, '/general/extracellular_ephys/electrodes/id') );
    locs    =       h5read(filePath, '/general/extracellular_ephys/electrodes/location');
    unitEID = double( h5read(filePath, '/units/electrode_id') );
    id2loc  = containers.Map(num2cell(elecIDs), locs(:));
    regs    = repmat({'unknown'}, nU,1);
    for u = 1:nU
        if id2loc.isKey(unitEID(u))
            regs{u} = id2loc(unitEID(u));
        end
    end
    uniqR = unique(regs,'stable');
    cmap  = lines(numel(uniqR));
    mapR  = containers.Map(uniqR, num2cell(cmap,2));

    %% 3) Eye‐tracking or TTL
    hasEye = false;
    ttlTS  = [];
    try
        D    = h5read(filePath, '/processing/behavior/EyeTracking/SpatialSeries/data');
        t0   = h5read(filePath, '/processing/behavior/EyeTracking/SpatialSeries/starting_time');
        rate = h5readatt(filePath,'/processing/behavior/EyeTracking/SpatialSeries/starting_time','rate');
        nP   = size(D,2);
        eyeTS = t0 + (0:nP-1)'/rate;
        eyeX  = D(1,:);
        eyeY  = D(2,:);
        hasEye    = true;
        screenW   = 1280; screenH = 1024;
    catch
        aq = nwb.acquisition;
        if any(strcmp(aq.keys','events_ttl'))
            ttl = aq.get('events_ttl');
            ttlTS = ttl.timestamps.data.load();
        else
            error('No EyeTracking or events_ttl found.');
        end
    end

    %% 4) Compute duration
    tMaxSpike = 0;
    for u=1:nU
        st = spikeTimes{u};
        if ~isempty(st)
            tMaxSpike = max(tMaxSpike, max(st));
        end
    end
    if hasEye
        tRef = eyeTS(end);
    else
        tRef = ttlTS(end);
    end
    tmax = min(tMaxSpike, tRef);
    assert(tmax>0,'No data to render.');

    %% 5) VideoWriter
    fps     = 25;
    vw      = VideoWriter('bangVideo.mp4','MPEG-4');
    vw.FrameRate = fps;
    open(vw);

    %% 6) Figure & Axes
    fig   = figure('Color','w','Position',[100 100 640 480], 'MenuBar','none','ToolBar','none');
    axTop = axes('Parent',fig,'Position',[0.05 0.55 0.90 0.40]); hold(axTop,'on');
    if hasEye
        axis(axTop,'off');
        set(axTop,'XLim',[0 screenW],'YLim',[0 screenH],'YDir','reverse');
        title(axTop,'Eye Trace');
    else
        axis(axTop,'on'); xlabel(axTop,'Time (s)'); ylabel(axTop,'TTL');
        title(axTop,'TTL Pulses');
    end
    axBot = axes('Parent',fig,'Position',[0.05 0.05 0.90 0.40]); hold(axBot,'on');
    axBot.YDir = 'reverse';
    xlabel(axBot,'Time (s)'); ylabel(axBot,'Unit #');
    title(axBot,'Spike Raster (5 s window)');

    %% 7) Render loop (right‐aligned window)
    win     = 5;           
    tailDur = 0.5;         
    nFrames = ceil(tmax*fps);
    for f = 1:nFrames
        t   = (f-1)/fps;
        t0r = t - win;      % right‐aligned
        t1r = t;

        % Top
        cla(axTop);
        if hasEye
            sel  = eyeTS>=t-tailDur & eyeTS<=t;
            ages = t - eyeTS(sel);
            alps = max(0,1 - ages/tailDur);
            for k=1:numel(ages)
                scatter(axTop, eyeX(sel(k)), eyeY(sel(k)),20,'r','filled','MarkerFaceAlpha',alps(k));
            end
            [~,ic] = min(abs(eyeTS - t));
            scatter(axTop, eyeX(ic), eyeY(ic),50,'r','filled');
        else
            sel = ttlTS>=t0r & ttlTS<=t1r;
            if any(sel)
                plot(axTop, ttlTS(sel), ones(nnz(sel),1),'|k','MarkerSize',10);
            end
            xlim(axTop,[t0r t1r]); ylim(axTop,[0 2]);
        end

        % Bottom grid
        cla(axBot);
        for u=1:nU
            plot(axBot, [t0r t1r],[u u],':','Color',[0.7 0.7 0.7]);
        end

        % Spikes
        for u=1:nU
            st = spikeTimes{u};
            in = st>=t0r & st<=t1r;
            if any(in)
                scatter(axBot, st(in), u*ones(nnz(in),1), 10, mapR(regs{u}),'filled');
            end
        end
        xlim(axBot,[t0r t1r]); ylim(axBot,[0 nU+1]);

        drawnow;
        writeVideo(vw, getframe(fig));
    end

    close(vw);
    close(fig);
    fprintf('Saved bangVideo.mp4 (%d frames, up to %.1f s)\n', nFrames, tmax);
end

% makeSpikeAudio.m
function makeSpikeAudio(nwb, filePath, outAudioFile)
% makeSpikeAudio  Generate 24 kHz Harvard‐style click train for all spikes
%
% USAGE:
%   nwb = nwbRead(filePath);
%   makeSpikeAudio(nwb, filePath, 'bangAudio.wav');

    %% Extract spike times
    flatT = nwb.units.spike_times.data.load();
    idx0  = nwb.units.spike_times_index.data.load();
    idx   = double(idx0) + 1;
    nU    = numel(idx);
    spikeTimes = cell(nU,1);
    for u = 1:nU
        sI = idx(u);
        if u<nU
            eI = idx(u+1)-1;
        else
            eI = numel(flatT);
        end
        spikeTimes{u} = flatT(sI:eI);
    end

    %% Compute total duration
    tmax = max(cellfun(@(st) max(st(:)), spikeTimes));
    fs   = 24000;
    N    = ceil(tmax*fs) + fs;
    audio = zeros(N,1);

    %% Harvard click: 1 ms Hann‐windowed 3 kHz burst
    tClick = 0:1/fs:0.001;
    click  = (hann(numel(tClick)).*sin(2*pi*3000*tClick))';
    click  = click(:);

    %% Scatter clicks
    for u = 1:nU
        for s = spikeTimes{u}(:)'
            idx0 = round(s*fs) + 1;
            if idx0 <= N
                eI  = min(idx0+numel(click)-1, N);
                len = eI - idx0 + 1;
                audio(idx0:eI) = audio(idx0:eI) + click(1:len);
            end
        end
    end

    %% Normalize & write
    audio = audio / max(abs(audio));
    audiowrite(outAudioFile, audio, fs);
    fprintf('Saved audio to %s (fs=%d Hz)\n', outAudioFile, fs);
end
