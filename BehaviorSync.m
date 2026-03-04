function BehaviorSync()

% BehaviorSync - Interface for Video and Neural Recording Visualization

% DESCRIPTION:
%   GUI tool for synchronized visualization and analysis of behavioral video alongside neural recordings and behavioral time-series data (e.g., Load
%   Cells, VideoFreeze, MED-PC systems).

%   The time vector is built automatically from the number of samples and the user-supplied sample rate (Fs), so the input file does NOT need a time
%   column — only the signal column is required.

%   By default, the script reads the LAST column of the file as the signal, making it robust to files that contain non-numeric leading columns
%   (which readmatrix imports as NaN).

% INPUT FILE FORMAT:
%   - CSV or TXT with at least one numeric column (the signal).
%   - Any number of leading columns is accepted; only the last column is used.
%   - Example (neural,   1000 Hz): one column of voltage samples.
%   - Example (behavior,    5 Hz): one column of position / force samples.

% WORKFLOW:
%   1. Set Fs (Hz) for each recording BEFORE loading the file.
%   2. Load Video → Load Neural → Load Behavior  (order is flexible).
%   3. Use Play/Pause or arrow keys to navigate the video.
%   4. Mark Onset [I] and Offset [O] (or [M] twice) at the desired frames.
%   5. (Optional) Define analysis epochs manually in the table or load from file.
%   6. Run Analysis to compute behavioral metrics per epoch.
%   7. Export results via the File menu (.xlsx or .mat).

% KEYBOARD SHORTCUTS:
%   Space       - Play / Pause
%   I           - Mark Onset
%   O           - Mark Offset
%   M           - Smart toggle: Onset if balanced, Offset otherwise
%   Left/Right  - Step one frame backward / forward
%   Del         - Delete last marked event

% ANALYSIS (Events Definition & Analysis panel):
%   Epochs can be defined manually in the table or loaded from a 3-column file (Label, Onset, Offset). A "Full Session" epoch is always included
%   automatically. For each epoch, the following metrics are computed:

%   - Freezing Percentage  : total time in behavioral bouts / epoch duration (%)
%   - Total Bouts          : number of discrete behavioral episodes
%   - Mean Bout Duration   : average duration of individual bouts (s)
%   - Bout Duration (raw)  : all individual bout durations (s)
%   - Mean Inter-Bout Interval (ΔT) : average gap between consecutive bouts (s)
%   - Inter-Bout Interval (raw)     : all individual inter-bout intervals (s)

% OUTPUT:
%   1. Behavior Timestamps (.csv) — via File menu:
%      Header with metadata (video fps, neural Fs, behavior Fs).
%      Columns: Frame onset | Frame offset | Onset (s) | Offset (s) | Duration (s)
%
%   2. Analysis Results (.xlsx) — via File menu:
%      One sheet per metric, rows = epochs, columns = subjects.
%      Sheets: Freezing_Percentage | Total_Bouts | Mean_Bout_Duration |
%              Bout_Duration | Mean_Bout_DeltaT | Bout_DeltaT

%   3. Analysis Results (.mat) — via File menu:
%      Struct 'Data_results' with all computed metrics.

% REQUIREMENTS:
%   MATLAB R2017b or later  (VideoReader, xline, uicontrol)

% KNOWN LIMITATIONS:
%   - If the behavioral or neural recording does not start at the same real-world time as the video, a manual Time Offset (s) field will
%     be required for precise alignment. This feature is under development.

% NOTE:
%   This function is still under construction.
%   Synchronization issues between signals with different start times will be addressed in future versions.

% AUTHOR:
%   Flavio Mourao  (mourao.fg@gmail.com)
%   Texas A&M University        - Department of Psychological and Brain Sciences
%   Beckman Institute / UIUC    - University of Illinois Urbana-Champaign
%   Federal University of Minas Gerais (UFMG) - Brazil

% Started:     09 / 2019
% Last update: 03 / 2026

%% 1. SHARED STATE VARIABLES


% --- Video ---
videoH        = [];     % VideoReader object
vidImgHandle  = [];     % Handle to the image displayed in axVid
isPlaying     = false;  % Playback loop flag
currFrame     = 1;      % Current frame index (1-based)
totalFrames   = 1;      % Total frames in the loaded video
fps           = 30;     % Video frame rate (updated on load)
videoFileName = '';     % Base filename used for export naming
playbackSpeed = 1;      % Playback speed multiplier

% --- Signal data ---
neuroData = [];  neuroTime = [];  neuroPlotObj = [];
behavData = [];  behavTime = [];  behavPlotObj = [];

% --- Playback cursors (red vertical lines on each axis) ---
cursorNeural = [];
cursorBehav  = [];

% --- Event storage ---
onsets_sec    = [];  onsets_frame  = [];
offsets_sec   = [];  offsets_frame = [];

% --- Graphic handles for event marker lines ---
eventLinesNeural = [];
eventLinesBehav  = [];

% Visible time window around the cursor (seconds)
windowScale = 10;

% Analysis results structure (populated by runAnalysisCalculation)
analysisResults = [];


%% 2. GUI CONSTRUCTION

fig = figure( ...
    'Name',              'BehaviorSync', ...
    'NumberTitle',       'off', ...
    'Position',          [50, 50, 1400, 850], ...
    'MenuBar',           'none', ...
    'ToolBar',           'figure', ...
    'Color',             [0.94 0.94 0.94], ...
    'WindowKeyPressFcn', @keyPressCallback);


% File menu
menuFile = uimenu(fig, 'Label', 'File');
mExport  = uimenu(menuFile, 'Label', '1. Export Results (.xls)',          'Callback', @exportExcel,   'Enable', 'off');
mSaveMat = uimenu(menuFile, 'Label', '2. Save Results (.mat)',            'Callback', @saveMatFile,   'Enable', 'off');
           uimenu(menuFile, 'Label', '4. Export Behavior Timestamps (.csv)', 'Callback', @exportBehavTS);


% Global time-window control
uicontrol('Style', 'text', 'String', 'Time Window (s):', ...
    'Units', 'normalized', 'Position', [0.83, 0.96, 0.10, 0.03], ...
    'HorizontalAlignment', 'right');
editWindow = uicontrol('Style', 'edit', 'String', num2str(windowScale), ...
    'Units', 'normalized', 'Position', [0.935, 0.962, 0.035, 0.03], ...
    'Callback', @updateWindowScale);


% Neural recording axis (top-right)
axNeural = axes('Parent', fig, 'Position', [0.50, 0.70, 0.47, 0.24]);
title(axNeural, 'Neural Recording', ...
    'Units', 'normalized', 'Position', [0, 1.05, 0], ...
    'HorizontalAlignment', 'left');
hold(axNeural, 'on');  box(axNeural, 'off');
xlabel(axNeural, 'Time (s)');  ylabel(axNeural, 'Amplitude');

nY = 0.63;   % Vertical anchor for neural controls row
uicontrol('Style', 'pushbutton', 'String', 'Load Neural (*.CSV / *.TXT)', ...
    'Units', 'normalized', 'Position', [0.50, nY, 0.16, 0.04], ...
    'Callback', {@loadData, 'neuro'});
uicontrol('Style', 'text', 'String', 'Fs (Hz):', ...
    'Units', 'normalized', 'Position', [0.67, nY-0.005, 0.04, 0.03], ...
    'HorizontalAlignment', 'right');
editFsNeuro = uicontrol('Style', 'edit', 'String', '1000', ...
    'Units', 'normalized', 'Position', [0.715, nY, 0.04, 0.03], ...
    'TooltipString', 'Sample rate of the neural recording (Hz)');
uicontrol('Style', 'text', 'String', 'Set Y scale:', ...
    'Units', 'normalized', 'Position', [0.77, nY-0.005, 0.06, 0.03], ...
    'HorizontalAlignment', 'right');
editYNeural = uicontrol('Style', 'edit', 'String', 'Auto', ...
    'Units', 'normalized', 'Position', [0.835, nY, 0.045, 0.03], ...
    'Callback', @updateYAxes, ...
    'TooltipString', 'Symmetric Y limit (e.g. 500). Leave "Auto" for automatic scaling.');


% Behavior recording axis (middle-right)
axBehav = axes('Parent', fig, 'Position', [0.50, 0.35, 0.47, 0.24]);
title(axBehav, 'Behavior Recording', ...
    'Units', 'normalized', 'Position', [0, 1.05, 0], ...
    'HorizontalAlignment', 'left');
hold(axBehav, 'on');  box(axBehav, 'off');
xlabel(axBehav, 'Time (s)');  ylabel(axBehav, 'Amplitude');

bY = 0.28;   % Vertical anchor for behavior controls row
uicontrol('Style', 'pushbutton', 'String', 'Load Behavior (*.CSV / *.TXT)', ...
    'Units', 'normalized', 'Position', [0.50, bY, 0.16, 0.04], ...
    'Callback', {@loadData, 'behav'});
uicontrol('Style', 'text', 'String', 'Fs (Hz):', ...
    'Units', 'normalized', 'Position', [0.67, bY-0.005, 0.04, 0.03], ...
    'HorizontalAlignment', 'right');
editFsBehav = uicontrol('Style', 'edit', 'String', '5', ...
    'Units', 'normalized', 'Position', [0.715, bY, 0.04, 0.03], ...
    'TooltipString', 'Sample rate of the behavioral recording (Hz)');
uicontrol('Style', 'text', 'String', 'Set Y scale:', ...
    'Units', 'normalized', 'Position', [0.77, bY-0.005, 0.06, 0.03], ...
    'HorizontalAlignment', 'right');
editYBehav = uicontrol('Style', 'edit', 'String', 'Auto', ...
    'Units', 'normalized', 'Position', [0.835, bY, 0.045, 0.03], ...
    'Callback', @updateYAxes, ...
    'TooltipString', 'Positive Y limit (e.g. 100). Leave "Auto" for automatic scaling.');


% Video axis and controls (left panel)
axVid = axes('Parent', fig, 'Position', [0.03, 0.45, 0.42, 0.50]);
axis(axVid, 'off');
title(axVid, 'Video');

vY = 0.38;   % Vertical anchor for video controls row
uicontrol('Style', 'pushbutton', 'String', 'Load Video', ...
    'Units', 'normalized', 'Position', [0.03, vY, 0.10, 0.04], ...
    'Callback', @loadVideo);
btnPlay = uicontrol('Style', 'togglebutton', 'String', 'Play / Pause  [Space]', ...
    'Units', 'normalized', 'Position', [0.14, vY, 0.14, 0.04], ...
    'Callback', @togglePlay);
txtTime = uicontrol('Style', 'text', 'String', 'Time: --  /  --', ...
    'Units', 'normalized', 'Position', [0.29, vY-0.01, 0.10, 0.04], ...
    'HorizontalAlignment', 'left');
uicontrol('Style', 'text', 'String', 'Speed:', ...
    'Units', 'normalized', 'Position', [0.35, vY-0.01, 0.04, 0.04], ...
    'HorizontalAlignment', 'right');
popSpeed = uicontrol('Style', 'popupmenu', ...
    'String', {'0.25x', '0.5x', '1x', '2x', '4x', '10x', '20x'}, ...
    'Value', 3, ...   % Default: 1x
    'Units', 'normalized', 'Position', [0.395, vY-0.008, 0.055, 0.04], ...
    'Callback', @changeSpeed);
sliderVid = uicontrol('Style', 'slider', 'Min', 1, 'Max', 2, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.03, 0.33, 0.42, 0.025], ...
    'Callback', @sliderCallback);


% Event marking panel (bottom-left)
pnlEvents = uipanel('Parent', fig, ...
    'Title', ['Event Marking  —  Shortcuts:  I = Onset  |  O = Offset  |' ...
              '  M = Toggle  |  Arrows = Step frame  |  Del = Undo'], ...
    'Units', 'normalized', ...
    'Position', [0.03, 0.02, 0.55, 0.22]);

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'ONSET  [I]', ...
    'Units', 'normalized', 'Position', [0.01, 0.65, 0.18, 0.25], ...
    'BackgroundColor', [0.635, 0.078, 0.184], 'ForegroundColor', [1 1 1], ...
    'FontWeight', 'bold', 'Callback', {@markEvent, 'onset'});

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'OFFSET  [O]', ...
    'Units', 'normalized', 'Position', [0.01, 0.35, 0.18, 0.25], ...
    'BackgroundColor', [0.850, 0.325, 0.098], 'ForegroundColor', [1 1 1], ...
    'FontWeight', 'bold', 'Callback', {@markEvent, 'offset'});

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'Delete Last  [Del]', ...
    'Units', 'normalized', 'Position', [0.01, 0.05, 0.18, 0.25], ...
    'BackgroundColor', [0.8, 0.8, 0.8], 'FontWeight', 'bold', ...
    'Callback', @deleteLastEvent);

% Onset list
uicontrol('Parent', pnlEvents, 'Style', 'text', 'String', 'Onsets (s)', ...
    'Units', 'normalized', 'Position', [0.22, 0.85, 0.22, 0.10]);
listOnset = uicontrol('Parent', pnlEvents, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.22, 0.05, 0.22, 0.80]);

% Offset list
uicontrol('Parent', pnlEvents, 'Style', 'text', 'String', 'Offsets (s)', ...
    'Units', 'normalized', 'Position', [0.48, 0.85, 0.22, 0.10]);
listOffset = uicontrol('Parent', pnlEvents, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.48, 0.05, 0.22, 0.80]);

% Duration list (computed automatically from matched onset/offset pairs)
uicontrol('Parent', pnlEvents, 'Style', 'text', 'String', 'Duration (s)', ...
    'Units', 'normalized', 'Position', [0.74, 0.85, 0.22, 0.10]);
listDuration = uicontrol('Parent', pnlEvents, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.74, 0.05, 0.22, 0.80]);


% Events Definition & Analysis panel (bottom-right)
pnlAnalysis = uipanel('Parent', fig, 'Title', 'Events Definition & Analysis', ...
    'Units', 'normalized', 'Position', [0.60, 0.02, 0.37, 0.22]);

% Editable epoch table (Label | Onset | Offset)
default_events = cell(200, 3);
uitEvents = uitable('Parent', pnlAnalysis, ...
    'Data',           default_events, ...
    'ColumnName',     {'Event Label', 'Onset (s)', 'Offset (s)'}, ...
    'ColumnEditable', [true, true, true], ...
    'Units', 'normalized', 'Position', [0.02, 0.05, 0.55, 0.90]);

uicontrol('Parent', pnlAnalysis, 'Style', 'pushbutton', ...
    'String', 'Load Events File (.txt / .csv)', ...
    'Units', 'normalized', 'Position', [0.60, 0.65, 0.38, 0.25], ...
    'Callback', @loadEventsFile, 'FontWeight', 'bold');

uicontrol('Parent', pnlAnalysis, 'Style', 'pushbutton', ...
    'String', 'RUN ANALYSIS', ...
    'Units', 'normalized', 'Position', [0.60, 0.20, 0.38, 0.35], ...
    'BackgroundColor', [0.8 0.8 0.8], 'ForegroundColor', [0 0 0], ...
    'FontWeight', 'bold', 'Callback', @runAnalysisCalculation);


%% 3. HELPER UTILITIES

% Briefly disable/re-enable a control to return keyboard focus to the figure
    function removeFocus(hObject)
        set(hObject, 'Enable', 'off');
        drawnow;
        set(hObject, 'Enable', 'on');
    end

% Clear all marked events and their corresponding graphic lines
    function resetEvents()
        onsets_sec    = [];  onsets_frame  = [];
        offsets_sec   = [];  offsets_frame = [];
        if ~isempty(eventLinesNeural)
            delete(eventLinesNeural(isgraphics(eventLinesNeural)));
        end
        if ~isempty(eventLinesBehav)
            delete(eventLinesBehav(isgraphics(eventLinesBehav)));
        end
        eventLinesNeural = [];
        eventLinesBehav  = [];
        set(listOnset,    'String', {});
        set(listOffset,   'String', {});
        set(listDuration, 'String', {});
    end


%% 4. CALLBACK FUNCTIONS

% Load video file 
    function loadVideo(hObject, ~)
        removeFocus(hObject);
        [fileStr, pathStr] = uigetfile( ...
            {'*.mp4;*.avi;*.wmv;*.mov', 'Video Files'; '*.*', 'All Files'}, ...
            'Select Video File');
        if isequal(fileStr, 0); return; end

        resetEvents();             % Clear previous events when a new video is loaded
        videoFileName = fileStr;
        videoH        = VideoReader(fullfile(pathStr, fileStr));
        totalFrames   = videoH.NumberOfFrames;
        fps           = videoH.FrameRate;
        currFrame     = 1;

        frame = read(videoH, 1);
        cla(axVid);
        vidImgHandle = image(axVid, frame);
        axis(axVid, 'image');
        axis(axVid, 'off');

        set(sliderVid, ...
            'Min', 1, 'Max', totalFrames, 'Value', 1, ...
            'SliderStep', [1/totalFrames, 10/totalFrames]);
        updateTimeUI();
        syncDataAxes();
    end


% Change playback speed 
    function changeSpeed(src, ~)
        removeFocus(src);
        speedOptions  = [0.25, 0.5, 1, 2, 4, 10, 20];
        playbackSpeed = speedOptions(src.Value);
    end


% Load neural or behavioral signal from file
    function loadData(hObject, ~, type)
        removeFocus(hObject);
        [fileStr, pathStr] = uigetfile( ...
            {'*.csv;*.txt', 'Text Files'; '*.*', 'All Files'}, ...
            'Select Data File');
        if isequal(fileStr, 0); return; end

        rawData = readmatrix(fullfile(pathStr, fileStr));
        if isempty(rawData)
            errordlg('The selected file is empty.', 'Data Error');
            return;
        end

        % Use the last column as signal (robust to NaN-filled leading columns)
        signal = rawData(:, end);
        if all(isnan(signal))
            errordlg('Could not find numeric data in the file.', 'Data Error');
            return;
        end

        numSamples = length(signal);

        if strcmp(type, 'neuro')
            fs = str2double(editFsNeuro.String);
            if isnan(fs) || fs <= 0
                errordlg('Enter a valid Fs (Hz) for the neural recording.', 'Invalid Fs');
                return;
            end
            neuroTime = (0 : numSamples-1)' / fs;
            neuroData = signal;
            if isgraphics(neuroPlotObj); delete(neuroPlotObj); end
            neuroPlotObj = plot(axNeural, neuroTime, neuroData, ...
                'Color', [0, 0.447, 0.741], 'LineWidth', 1);
            if isempty(cursorNeural) || ~isgraphics(cursorNeural)
                cursorNeural = xline(axNeural, 0, ...
                    'Color', [0.635, 0.078, 0.184], 'LineWidth', 2.5);
            end

        else  % behav
            fs = str2double(editFsBehav.String);
            if isnan(fs) || fs <= 0
                errordlg('Enter a valid Fs (Hz) for the behavior recording.', 'Invalid Fs');
                return;
            end
            behavTime = (0 : numSamples-1)' / fs;
            behavData = signal;
            if isgraphics(behavPlotObj); delete(behavPlotObj); end
            behavPlotObj = plot(axBehav, behavTime, behavData, ...
                'Color', [0.5, 0.5, 0.5], 'LineWidth', 1.5);
            if isempty(cursorBehav) || ~isgraphics(cursorBehav)
                cursorBehav = xline(axBehav, 0, ...
                    'Color', [0.635, 0.078, 0.184], 'LineWidth', 2.5);
            end
        end

        updateYAxes();
        syncDataAxes();
    end


% Apply Y-axis limits (fixed value or auto)
    function updateYAxes(~, ~)
        valN = str2double(editYNeural.String);
        if ~isnan(valN) && valN > 0
            ylim(axNeural, [-valN, valN]);
        else
            axis(axNeural, 'auto y');
            editYNeural.String = 'Auto';
        end

        valB = str2double(editYBehav.String);
        if ~isnan(valB) && valB > 0
            ylim(axBehav, [0, valB]);
        else
            axis(axBehav, 'auto y');
            editYBehav.String = 'Auto';
        end
    end


% Play / Pause toggle
    function togglePlay(src, ~)
        removeFocus(src);
        isPlaying = src.Value;
        if isempty(videoH); src.Value = 0; return; end

        while isPlaying && (currFrame < totalFrames) && isgraphics(fig)
            tic;
            currFrame = currFrame + 1;
            set(vidImgHandle, 'CData', read(videoH, currFrame));
            updateTimeUI();
            if mod(currFrame, 3) == 0; syncDataAxes(); end
            drawnow limitrate;
            elapsed     = toc;
            targetDelay = 1 / (fps * playbackSpeed);
            if elapsed < targetDelay; pause(targetDelay - elapsed); end
            isPlaying = btnPlay.Value;
        end

        btnPlay.Value = 0;
        isPlaying     = false;
    end


% Video slider scrubbing
    function sliderCallback(src, ~)
        removeFocus(src);
        if isempty(videoH); return; end
        currFrame = round(src.Value);
        updateFrameManually();
    end


% Update the visible time-window width
    function updateWindowScale(src, ~)
        val = str2double(src.String);
        if ~isnan(val) && val > 0
            windowScale = val;
            syncDataAxes();
        else
            src.String = num2str(windowScale);
        end
    end


% Synchronize data axes to current video time
    function syncDataAxes()
        currTime = (currFrame - 1) / fps;
        if ~isempty(videoH)
            xLimits = [max(0, currTime - windowScale/2), currTime + windowScale/2];
            xlim(axNeural, xLimits);
            xlim(axBehav,  xLimits);
        else
            xlim(axNeural, 'auto');
            xlim(axBehav,  'auto');
        end
        if isgraphics(cursorNeural); set(cursorNeural, 'Value', currTime); end
        if isgraphics(cursorBehav);  set(cursorBehav,  'Value', currTime); end
    end


% Update time label and slider position
    function updateTimeUI()
        if isempty(videoH); return; end
        currTime = (currFrame - 1) / fps;
        set(sliderVid, 'Value', currFrame);
        set(txtTime, 'String', ...
            sprintf('Time: %.2f s  /  %.2f s', currTime, totalFrames/fps));
    end


%% 5. EVENT MARKING FUNCTIONS

% Mark onset or offset at the current frame
    function markEvent(hObject, ~, type)
        if ~isempty(hObject); removeFocus(hObject); end
        if isempty(videoH); return; end

        cTime = (currFrame - 1) / fps;

        if strcmp(type, 'onset')
            onsets_sec(end+1)   = cTime;
            onsets_frame(end+1) = currFrame;
            color = [0.635, 0.078, 0.184];   % Dark red

        elseif strcmp(type, 'offset')
            if length(offsets_sec) >= length(onsets_sec)
                warndlg('Mark an Onset before marking an Offset.', 'Order Error');
                return;
            end
            offsets_sec(end+1)   = cTime;
            offsets_frame(end+1) = currFrame;
            color = [0.850, 0.325, 0.098];   % Orange
        end

        eventLinesNeural(end+1) = xline(axNeural, cTime, 'LineWidth', 2, 'Color', color);
        eventLinesBehav(end+1)  = xline(axBehav,  cTime, 'LineWidth', 2, 'Color', color);
        updateLists();
    end


% Refresh onset / offset / duration listboxes
    function updateLists()
        set(listOnset,  'String', cellstr(num2str(onsets_sec',  '%.3f')));
        set(listOffset, 'String', cellstr(num2str(offsets_sec', '%.3f')));
        nPairs = min(length(onsets_sec), length(offsets_sec));
        if nPairs > 0
            durations = offsets_sec(1:nPairs) - onsets_sec(1:nPairs);
            set(listDuration, 'String', cellstr(num2str(durations', '%.3f')));
        else
            set(listDuration, 'String', {});
        end
    end


% Delete the last marked event
    function deleteLastEvent(hObject, ~)
        if ~isempty(hObject); removeFocus(hObject); end
        if isempty(onsets_sec); return; end

        if length(offsets_sec) < length(onsets_sec)
            onsets_sec(end)   = [];
            onsets_frame(end) = [];
        elseif ~isempty(offsets_sec)
            offsets_sec(end)   = [];
            offsets_frame(end) = [];
        else
            return;
        end

        if ~isempty(eventLinesNeural) && isgraphics(eventLinesNeural(end))
            delete(eventLinesNeural(end));
            eventLinesNeural(end) = [];
        end
        if ~isempty(eventLinesBehav) && isgraphics(eventLinesBehav(end))
            delete(eventLinesBehav(end));
            eventLinesBehav(end) = [];
        end
        updateLists();
    end


% Export behavior event timestamps to CSV (File menu callback)
    function exportBehavTS(hObject, ~)
        removeFocus(hObject);
        if isempty(onsets_sec)
            msgbox('No events to export.', 'Empty');
            return;
        end

        nOnsets = length(onsets_sec);
        os  = onsets_sec;
        ofs = offsets_sec;
        on  = onsets_frame;
        of  = offsets_frame;

        % Pad offsets with NaN if some onsets have no matching offset
        if length(ofs) < nOnsets
            ofs(end+1:nOnsets) = NaN;
            of(end+1:nOnsets)  = NaN;
        end

        dur = ofs - os;

        if isempty(videoFileName)
            defaultName = 'behavior_events.csv';
        else
            [~, nm] = fileparts(videoFileName);
            defaultName = [nm '_events.csv'];
        end

        [file, path] = uiputfile(defaultName, 'Save Events');
        if isequal(file, 0); return; end

        fullFile = fullfile(path, file);
        fid = fopen(fullFile, 'w');
        fprintf(fid, '# BehaviorSync export | Video: %.4f fps', fps);
        if ~isempty(neuroTime)
            fprintf(fid, ' | Neural Fs: %s Hz', editFsNeuro.String);
        end
        if ~isempty(behavTime)
            fprintf(fid, ' | Behavior Fs: %s Hz', editFsBehav.String);
        end
        fprintf(fid, '\n');
        fprintf(fid, 'Frame (sample) onset,Frame (sample) offset,Onset (seconds),Offset (seconds),Duration (seconds)\n');
        fclose(fid);

        T = table(on', of', os', ofs', dur');
        writetable(T, fullFile, 'WriteMode', 'append', 'WriteVariableNames', false);
        msgbox(sprintf('Exported %d event(s) to:\n%s', nOnsets, fullFile), 'Success');
    end


%% 6. KEYBOARD SHORTCUTS

    function keyPressCallback(~, event)
        if isempty(videoH); return; end
        switch event.Key
            case 'space'
                btnPlay.Value = ~btnPlay.Value;
                if btnPlay.Value; togglePlay(btnPlay, []); end
            case 'm'
                % Smart toggle: Onset if pairs are balanced, Offset otherwise
                if length(onsets_sec) == length(offsets_sec)
                    markEvent([], [], 'onset');
                else
                    markEvent([], [], 'offset');
                end
            case 'i';           markEvent([], [], 'onset');
            case 'o';           markEvent([], [], 'offset');
            case 'leftarrow'
                if currFrame > 1
                    currFrame = currFrame - 1;
                    updateFrameManually();
                end
            case 'rightarrow'
                if currFrame < totalFrames
                    currFrame = currFrame + 1;
                    updateFrameManually();
                end
            case {'backspace', 'delete'}
                deleteLastEvent([], []);
        end
    end


% Jump to currFrame and refresh all views
    function updateFrameManually()
        set(vidImgHandle, 'CData', read(videoH, currFrame));
        updateTimeUI();
        syncDataAxes();
    end


%% 7. ANALYSIS & EXPORT FUNCTIONS

% Load epoch/event windows from file
    function loadEventsFile(hObject, ~)
        removeFocus(hObject);
        [ev_file, ev_path] = uigetfile( ...
            {'*.csv;*.txt', 'Event Timings File (*.csv, *.txt)'}, ...
            'Select the Events File');
        if isequal(ev_file, 0); return; end

        ev_data = readcell(fullfile(ev_path, ev_file));
        if size(ev_data, 2) < 3
            errordlg('The events file must have 3 columns: Name, Onset, Offset.', 'Format Error');
            return;
        end

        event_names_raw = strip(string(ev_data(:, 1)));
        onsets_ev       = str2double(string(ev_data(:, 2)));
        offsets_ev      = str2double(string(ev_data(:, 3)));

        valid_rows = ~isnan(onsets_ev) & ~isnan(offsets_ev) & (strlength(event_names_raw) > 0);
        num_valid  = sum(valid_rows);

        if num_valid == 0
            errordlg('No valid numeric events found in the file.', 'Data Error');
            return;
        end

        % Isolate valid rows to avoid compound-indexing issues
        valid_onsets  = onsets_ev(valid_rows);
        valid_offsets = offsets_ev(valid_rows);
        valid_names   = event_names_raw(valid_rows);

        % Populate the epoch table without overwriting manually marked bouts
        loaded_events = cell(num_valid, 3);
        loaded_events(:, 1) = cellstr(valid_names);
        loaded_events(:, 2) = num2cell(valid_onsets');
        loaded_events(:, 3) = num2cell(valid_offsets');

        new_table_data = cell(200, 3);
        new_table_data(1:num_valid, :) = loaded_events;
        set(uitEvents, 'Data', new_table_data);

        % Draw dashed blue lines to visualize epoch boundaries
        for i = 1:num_valid
            xline(axNeural, valid_onsets(i), '--b', 'LineWidth', 1);
            xline(axBehav,  valid_onsets(i), '--b', 'LineWidth', 1);
        end
    end


% Run intersection analysis: bouts × epoch windows
    function runAnalysisCalculation(hObject, ~)
        removeFocus(hObject);

        % 1. Extract behavior bouts (manual onset/offset markings)
        nPairs    = min(length(onsets_sec), length(offsets_sec));
        bouts_on  = onsets_sec(1:nPairs)';
        bouts_off = offsets_sec(1:nPairs)';

        if isempty(bouts_on)
            warndlg('No behavior bouts marked. Use [I] and [O] to mark events first.', 'Warning');
            return;
        end

        % 2. Extract epoch windows from the table
        tblData   = get(uitEvents, 'Data');
        valid_idx = cellfun(@isnumeric, tblData(:, 2)) & ...
                    cellfun(@isnumeric, tblData(:, 3)) & ...
                    ~cellfun(@isempty,  tblData(:, 2));
        valid_data  = tblData(valid_idx, :);
        epochs_name = cellstr(valid_data(:, 1));
        epochs_on   = cell2mat(valid_data(:, 2));
        epochs_off  = cell2mat(valid_data(:, 3));

        % 3. Determine total session duration
        if isempty(videoH) || totalFrames <= 1
            total_video_time = max([bouts_off; epochs_off]);
        else
            total_video_time = totalFrames / fps;
        end

        % Prepend "Full Session" as the first analysis window
        all_epochs_name = [{'Full Session'}; epochs_name];
        all_epochs_on   = [0;               epochs_on];
        all_epochs_off  = [total_video_time; epochs_off];
        nEpochs         = length(all_epochs_name);

        % 4. Initialize results structure
        res               = struct();
        res.epoch_labels  = all_epochs_name;
        res.pct           = zeros(nEpochs, 1);   % Freezing percentage
        res.bouts         = zeros(nEpochs, 1);   % Number of bouts
        res.mean_dur      = zeros(nEpochs, 1);   % Mean bout duration (s)
        res.raw_dur       = cell(nEpochs, 1);    % All individual bout durations (s)
        res.mean_lat      = zeros(nEpochs, 1);   % Mean inter-bout interval (s)
        res.raw_lat       = cell(nEpochs, 1);    % All individual inter-bout intervals (s)

        % 5. Mathematical intersection: bouts ∩ epoch window
        for i = 1:nEpochs
            t_on   = all_epochs_on(i);
            t_off  = all_epochs_off(i);
            ep_dur = t_off - t_on;
            if ep_dur <= 0; continue; end

            % Clip each bout to the epoch boundaries
            adj_on  = max(bouts_on,  t_on);
            adj_off = min(bouts_off, t_off);

            % Keep only bouts that overlap with this epoch
            valid_bouts = adj_on < adj_off;
            v_on  = adj_on(valid_bouts);
            v_off = adj_off(valid_bouts);

            % Compute duration metrics
            durations      = v_off - v_on;
            res.bouts(i)   = length(durations);
            res.pct(i)     = (sum(durations) / ep_dur) * 100;
            res.raw_dur{i} = durations;
            if res.bouts(i) > 0
                res.mean_dur(i) = mean(durations);
            end

            % Compute inter-bout interval (latency) metrics
            if res.bouts(i) > 1
                latencies = v_on(2:end) - v_off(1:end-1);
                latencies = latencies(latencies >= 0);   % Exclude anomalous overlaps
                res.raw_lat{i} = latencies;
                if ~isempty(latencies)
                    res.mean_lat(i) = mean(latencies);
                end
            end
        end

        analysisResults = res;
        msgbox('Analysis complete! Export results to Excel via the File menu.', 'Success');

        % Enable export menu items
        set(mExport,  'Enable', 'on');
        set(mSaveMat, 'Enable', 'on');
    end


% Export analysis results to Excel (File menu callback)
    function exportExcel(~, ~)
        if isempty(analysisResults)
            errordlg('Please run the analysis first!', 'Error');
            return;
        end

        if isempty(videoFileName)
            defaultName = 'BehaviorSync_Results.xlsx';
        else
            [path, nm, ~] = fileparts(videoFileName);
            defaultName   = fullfile(path, [nm '_Results.xlsx']);
        end

        [file, path] = uiputfile(defaultName, 'Save Excel Results');
        if isequal(file, 0); return; end
        out_xlsx = fullfile(path, file);

        res      = analysisResults;
        n_epochs = length(res.epoch_labels);
        header_row = {'Epoch', 'Subject 1'};

        % Pre-allocate output cells
        freeze_cell   = cell(n_epochs, 1);
        bout_cell     = cell(n_epochs, 1);
        mean_dur_cell = cell(n_epochs, 1);
        mean_lat_cell = cell(n_epochs, 1);
        raw_dur_cell  = cell(n_epochs, 1);
        raw_lat_cell  = cell(n_epochs, 1);

        for i = 1:n_epochs
            freeze_cell{i}   = res.pct(i);
            bout_cell{i}     = res.bouts(i);
            mean_dur_cell{i} = res.mean_dur(i);
            mean_lat_cell{i} = res.mean_lat(i);

            if isempty(res.raw_dur{i})
                raw_dur_cell{i} = '0';
            else
                raw_dur_cell{i} = strjoin(string(round(res.raw_dur{i}, 2)), ', ');
            end

            if isempty(res.raw_lat{i})
                raw_lat_cell{i} = 'NaN';
            else
                raw_lat_cell{i} = strjoin(string(round(res.raw_lat{i}, 2)), ', ');
            end
        end

        % Write one sheet per metric
        writecell([header_row; [res.epoch_labels, freeze_cell]],   out_xlsx, 'Sheet', '1_Freezing_Percentage');
        writecell([header_row; [res.epoch_labels, bout_cell]],     out_xlsx, 'Sheet', '2_Total_Bouts');
        writecell([header_row; [res.epoch_labels, mean_dur_cell]], out_xlsx, 'Sheet', '3_Mean_Bout_Duration(s)');
        writecell([header_row; [res.epoch_labels, raw_dur_cell]],  out_xlsx, 'Sheet', '4_Bout_Duration(s)');
        writecell([header_row; [res.epoch_labels, mean_lat_cell]], out_xlsx, 'Sheet', '5_Mean_Bout_DeltaT(s)');
        writecell([header_row; [res.epoch_labels, raw_lat_cell]],  out_xlsx, 'Sheet', '6_Bout_DeltaT(s)');

        msgbox(sprintf('Excel exported successfully to:\n%s', out_xlsx), 'Export Complete');
    end


% Save analysis results to .mat file (File menu callback)
    function saveMatFile(~, ~)
        if isempty(analysisResults); return; end
        [file, path] = uiputfile('BehaviorSync_Results.mat', 'Save Data as .mat');
        if isequal(file, 0); return; end
        Data_results = analysisResults;
        save(fullfile(path, file), 'Data_results');
        msgbox('Results saved to .mat successfully.', 'Success');
    end

end