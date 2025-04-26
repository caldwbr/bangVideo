% bangFreq.m
function bangFreq(filePath)
% bangFreq  Render population‐spike‐rate movie (50 ms bins, smoothed)
%            into bangFreq.mp4 @25 fps.
%
% USAGE:
%   bangFreq('/path/to/sub-XXX_ses-XXX_behavior+ecephys.nwb');

    %% 0) Load NWB
    nwb = nwbRead(filePath);  % only input is filePath

    %% 1) Extract all spike times
    flatT = nwb.units.spike_times.data.load();
    idx0  = nwb.units.spike_times_index.data.load();
    idx   = double(idx0) + 1;
    nU    = numel(idx);

    % preallocate full vector of spikes
    totalSpikes = numel(flatT);
    allSpikes   = zeros(totalSpikes,1);
    pos = 0;
    for u = 1:nU
        sI = idx(u);
        if u < nU
            eI = idx(u+1) - 1;
        else
            eI = totalSpikes;
        end
        nSp = eI - sI + 1;
        allSpikes(pos + (1:nSp)) = flatT(sI:eI);
        pos = pos + nSp;
    end
    allSpikes = allSpikes(1:pos);        % trim unused tail
    tmax      = max(allSpikes);

    %% 2) Bin & smooth
    binWidth    = 0.05;                  % 50 ms
    edges       = 0:binWidth:(ceil(tmax/binWidth)*binWidth);
    counts      = histcounts(allSpikes, edges);
    smoothCounts = smoothdata(counts, 'gaussian', 11);

    centers = edges(1:end-1) + binWidth/2;

    %% 3) Prepare VideoWriter
    fps     = 25;
    nFrames = ceil(tmax * fps);
    vw      = VideoWriter('bangFreq.mp4','MPEG-4');
    vw.FrameRate = fps;
    open(vw);

    %% 4) Figure & axes setup
    fig = figure('Color','w','Position',[100 100 640 480], ...
                 'MenuBar','none','ToolBar','none');
    ax = axes('Parent', fig);
    hold(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, sprintf('Spikes per %d ms bin', round(binWidth*1000)));
    title(ax, 'Population Spike Rate');
    xlim(ax, [0 tmax]);
    ylim(ax, [0 max(smoothCounts)*1.1]);

    %% 5) Render & record each frame
    for f = 1:nFrames
        t = (f-1)/fps;
        % only plot up to current time
        ix = centers <= t;
        cla(ax);
        plot(ax, centers(ix), smoothCounts(ix), 'LineWidth', 2);
        % highlight current point
        if any(ix)
            plot(ax, centers(find(ix,1,'last')), smoothCounts(find(ix,1,'last')), ...
                 'ro','MarkerFaceColor','r');
        end
        drawnow;
        writeVideo(vw, getframe(fig));
    end

    %% 6) Clean up
    close(vw);
    close(fig);
    fprintf('Saved bangFreq.mp4 (%d frames, %.2f s)\n', nFrames, tmax);
end
