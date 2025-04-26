function blahBlah(filePath, outFile)
% exportRegionLegend: Generate a standalone PNG/JPG legend mapping brain regions to colors
% USAGE:
%   nwb = nwbRead(filePath);
%   exportRegionLegend(filePath, 'brainRegionLegend.png');

% 1) Read NWB and map electrodes → brain regions
nwb      = nwbRead(filePath);
elecIDs  = double(h5read(filePath, '/general/extracellular_ephys/electrodes/id'));
locs     = h5read(filePath, '/general/extracellular_ephys/electrodes/location');
unitEID  = double(h5read(filePath, '/units/electrode_id'));
id2loc   = containers.Map(num2cell(elecIDs), locs(:));

% Build regs list for each unit
nU       = numel(unitEID);
regs     = repmat({'unknown'}, nU, 1);
for u = 1:nU
    if id2loc.isKey(unitEID(u))
        regs{u} = id2loc(unitEID(u));
    end
end

% Unique regions (order preserved)
uniqR = unique(regs, 'stable');
cmap  = lines(numel(uniqR));  % same colormap as bangVideo

% 2) Create legend figure
fig = figure('Color','w', 'MenuBar','none', 'ToolBar','none', 'Visible','off');
ax  = axes('Parent',fig, 'Position',[0 0 1 1], 'Visible','off');

n = numel(uniqR);
for k = 1:n
    y = n - k + 1;
    rectangle(ax, 'Position',[0, y-1, 1, 1], 'FaceColor', cmap(k,:), 'EdgeColor','none');
    text(ax, 1.1, y-0.5, uniqR{k}, 'FontSize', 12, 'VerticalAlignment','middle');
end

axis(ax, 'equal'); axis(ax, 'off');
xlim(ax, [0 3]); ylim(ax, [0 n]);

% 3) Save output based on extension
[~, ~, ext] = fileparts(outFile);
switch lower(ext)
    case '.png'
        print(fig, '-dpng', outFile);
    case {'.jpg', '.jpeg'}
        print(fig, '-djpeg', outFile);
    otherwise
        error('Unsupported output extension: %s', ext);
end

close(fig);
fprintf('Saved legend to %s\n', outFile);
end
