function bangVideo(nwb)
% bangVideo  Render full-session 640×480 @25 fps MP4 with:
%   • Top panel: eye‐trace if present, else TTL pulses  
%   • Bottom panel: 5 s sliding-window spike‐raster  
%
% Usage:
%   nwb = nwbRead('/path/to/your.nwb');
%   bangVideo(nwb);
%
% Requires MatNWB on your MATLAB path.

    %% 1) Extract spikes & regions
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

    if isprop(nwb.units,'brain_region')
        regs = cellstr(nwb.units.brain_region.data.load());
    else
        regs = repmat({'unknown'},nU,1);
    end
    uniqR = unique(regs);
    cmap  = lines(numel(uniqR));
    mapR  = containers.Map(uniqR, num2cell(cmap,2));

    %% 2) Locate eye‐tracking interface
    et = [];
    try
        behMap = nwb.processing('behavior').data_interfaces;
        for key = behMap.keys
            cand = behMap(key{1});
            if isprop(cand,'timestamps') && isprop(cand,'x') && isprop(cand,'y')
                et = cand; break;
            end
        end
    catch; end

    if isempty(et)
        try
            spMap = nwb.stimulus_presentation;
            for key = spMap.keys
                cand = spMap(key{1});
                if isprop(cand,'timestamps') && isprop(cand,'x') && isprop(cand,'y')
                    et = cand; break;
                end
            end
        catch; end
    end

    hasEye = ~isempty(et);
    if hasEye
        eyeTS = et.timestamps.data.load();
        eyeX  = et.x.data.load();
        eyeY  = et.y.data.load();
    else
        % fallback to TTL pulses under acquisition
        ttl = [];
        aq  = nwb.acquisition;          % types.untyped.Group
        ak  = aq.keys;                  % cell array of key names
        if any(strcmp(ak,'events_ttl'))
            ttl = aq.get('events_ttl');
        end
        if isempty(ttl)
            error('Neither eye‐tracking nor events_ttl found in NWB.');
        end
        % robust TTL timestamp loading
        try
            ttlTS = ttl.timestamps.data.load();
        catch
            ttlTS = ttl.timestamps.load();
        end
    end

    %% 3) Compute tmax
    tMaxSpike = 0;
    for u = 1:nU
        st = spikeTimes{u};
        if ~isempty(st)
            tMaxSpike = max(tMaxSpike, max(st));
        end
    end
    if hasEye
        tMaxEye = eyeTS(end);
    else
        tMaxEye = ttlTS(end);
    end
    tmax = min(tMaxSpike, tMaxEye);
    if tmax <= 0
        error('No valid data found to render.');
    end

    %% 4) VideoWriter setup
    fps     = 25;
    outName = 'bangVideo.mp4';
    vw      = VideoWriter(outName,'MPEG-4');
    vw.FrameRate = fps;
    open(vw);

    %% 5) Figure & axes (640×480)
    fig = figure('Color','w','Position',[100 100 640 480], ...
                 'MenuBar','none','ToolBar','none');
    axTop = axes('Parent',fig,'Position',[0.05 0.55 0.90 0.40]);
    hold(axTop,'on');
    if hasEye
        axis(axTop,'off');
        title(axTop,'Eye Trace');
    else
        axis(axTop,'on');
        xlabel(axTop,'Time (s)');
        ylabel(axTop,'TTL');
        title(axTop,'TTL Pulses');
    end

    axR = axes('Parent',fig,'Position',[0.05 0.05 0.90 0.40]);
    hold(axR,'on'); axR.YDir = 'reverse';
    xlabel(axR,'Time (s)'); ylabel(axR,'Unit #');
    title(axR,'Spike Raster (5 s window)');

    %% 6) Render loop (full session)
    win     = 5;    % s sliding window for raster
    tailDur = 0.5;  % s fading tail for eye trace
    nFrames = ceil(tmax * fps);

    for f = 1:nFrames
        t = (f-1)/fps;

        % --- Top panel ---
        cla(axTop);
        if hasEye
            idxTail = eyeTS >= t-tailDur & eyeTS <= t;
            ages    = t - eyeTS(idxTail);
            alphas  = max(0,1 - ages/tailDur);
            for k = 1:numel(ages)
                scatter(axTop, eyeX(idxTail(k)), eyeY(idxTail(k)), ...
                        20, 'r','filled','MarkerFaceAlpha',alphas(k));
            end
            [~,iC] = min(abs(eyeTS - t));
            scatter(axTop, eyeX(iC), eyeY(iC), 50, 'r','filled');
        else
            t0  = max(0, t - win/2);
            t1  = t0 + win;
            sel = ttlTS >= t0 & ttlTS <= t1;
            if any(sel)
                plot(axTop, ttlTS(sel), ones(nnz(sel),1), '|k', 'MarkerSize',10);
            end
            xlim(axTop,[t0 t1]);
            ylim(axTop,[0 2]);
        end

        % --- Bottom panel (spikes) ---
        cla(axR);
        t0 = max(0, t - win/2);
        t1 = t0 + win;
        for u = 1:nU
            st  = spikeTimes{u};
            sel = st >= t0 & st <= t1;
            if any(sel)
                plot(axR, st(sel), u*ones(nnz(sel),1), '|', ...
                     'Color', mapR(regs{u}), 'MarkerSize',6);
            end
        end
        xlim(axR,[t0 t1]);
        ylim(axR,[0 nU+1]);

        drawnow;
        writeVideo(vw, getframe(fig));
    end

    close(vw);
    close(fig);
    fprintf('Saved %s (%d frames, up to %.1f s)\n', outName, nFrames, tmax);
end
