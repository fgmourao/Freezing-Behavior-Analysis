function BehaviorSync()

% BehaviorSync - Unified Interface for Video and Neural Recording Visualization

% DESCRIPTION:
%   GUI tool for visualizing behavioral video alongside neural recordings
%   and behavioral time-series data (e.g., Load Cells, VideoFreeze -
%   MED-PC systems).

%   The time vector is built automatically from the number of samples and
%   the user-supplied sample rate (Fs), so the input file does NOT need a
%   time column. Only the signal column is required.
%   By default the script reads the LAST column of the file as the signal,
%   making it robust to files that contain non-numeric leading columns
%   (which readmatrix imports as NaN).

% INPUT FILE FORMAT:
%   - CSV or TXT with at least one numeric column (the signal).
%   - Any number of leading columns is accepted; only the last column is used.
%   - Example (neural, 1000 Hz):   one column of voltage samples
%   - Example (behavior, 5 Hz):    one column of position / force samples

% WORKFLOW:
%   1. Set Fs (Hz) for each recording BEFORE loading the file.
%   2. Load Video  ->  Load Neural  ->  Load Behavior (order is flexible).
%   3. Use Play/Pause or arrow keys to navigate the video.
%   4. Mark Onset [I] and Offset [O] at the desired frames.
%   5. Export Events to CSV.

% KEYBOARD SHORTCUTS:
%   Space      - Play / Pause
%   I          - Mark Onset
%   O          - Mark Offset
%   M          - Smart toggle: Onset if balanced, Offset otherwise
%   Left/Right - Step one frame backward / forward
%   Del        - Delete last marked event

% OUTPUT (CSV):
%   Header line with metadata (video fps, neural Fs, behavior Fs).
%   Columns: Frame onset | Frame offset | Onset (s) | Offset (s) | Duration (s)

% REQUIREMENTS:
%   MATLAB R2017b or later (VideoReader, xline, uicontrol)

% KNOWN LIMITATIONS:
%   - If the behavioral or neural recording does not start at the same
%     real-world time as the video, a manual Time Offset (s) field will
%     be required for precise alignment. This feature is under development.

% NOTE: This function is still under construction.
%       Synchronization issues between signals with different start times
%       will be addressed in future versions.

% AUTHOR:
%   Flavio Mourao (mourao.fg@gmail.com)
%   Texas A&M University - Department of Psychological and Brain Sciences
%   University of Illinois Urbana-Champaign - Beckman Institute
%   Federal University of Minas Gerais - Brazil

% Started:     09 / 2019
% Last update: 02 / 2026


%% 1. SHARED STATE VARIABLES

% Video
videoH        = [];       % VideoReader object
vidImgHandle  = [];       % Handle to the image displayed in axVid
isPlaying     = false;    % Playback loop flag
currFrame     = 1;        % Current frame index (1-based)
totalFrames   = 1;        % Total frames in the loaded video
fps           = 30;       % Video frame rate (updated on load)
videoFileName = '';       % Base filename used for export naming
playbackSpeed = 1;        % Playback Speed

% Signal data
neuroData = [];  neuroTime = [];  neuroPlotObj = [];
behavData = [];  behavTime = [];  behavPlotObj = [];

% Playback cursors (red vertical lines on each axis)
cursorNeural = [];
cursorBehav  = [];

% Event storage
onsets_sec    = [];  onsets_frame  = [];
offsets_sec   = [];  offsets_frame = [];

% Graphic handles for event marker lines
eventLinesNeural = [];
eventLinesBehav  = [];

% Visible time window around the cursor (seconds)
windowScale = 10;


%% 2. GUI CONSTRUCTION

fig = figure( ...
    'Name',              'BehaviorSync', ...
    'NumberTitle',       'off', ...
    'Position',          [50, 50, 1400, 850], ...
    'MenuBar',           'none', ...
    'ToolBar',           'figure', ...
    'Color',             [0.94 0.94 0.94], ...
    'WindowKeyPressFcn', @keyPressCallback);

% Global: time-window control
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

nY = 0.63;   % vertical anchor for neural controls row
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

bY = 0.28;   % vertical anchor for behavior controls row
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

vY = 0.38;   % vertical anchor for video controls row
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
popSpeed = uicontrol('Style', 'popupmenu', 'String', {'0.25x', '0.5x', '1x', '2x', '4x'}, ...
    'Value', 3, ... % Option 3 ('1x') - Default
    'Units', 'normalized', 'Position', [0.395, vY-0.008, 0.055, 0.04], ...
    'Callback', @changeSpeed);
sliderVid = uicontrol('Style', 'slider', 'Min', 1, 'Max', 2, 'Value', 1, ...
    'Units', 'normalized', 'Position', [0.03, 0.33, 0.42, 0.025], ...
    'Callback', @sliderCallback);

% Event marking panel (bottom strip)
pnlEvents = uipanel('Parent', fig, ...
    'Title', ['Event Marking  —  Shortcuts:  I = Onset  |  O = Offset  |' ...
    '  M = Toggle  |  Arrows = Step frame  |  Del = Undo'], ...
    'Units', 'normalized', ...
    'Position', [0.03, 0.02, 0.94, 0.22]);

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'ONSET  [I]', ...
    'Units', 'normalized', 'Position', [0.01, 0.65, 0.10, 0.25], ...
    'BackgroundColor', [0.635, 0.078, 0.184], 'ForegroundColor', [1 1 1], ...
    'FontWeight', 'bold', 'Callback', {@markEvent, 'onset'});

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'OFFSET  [O]', ...
    'Units', 'normalized', 'Position', [0.01, 0.35, 0.10, 0.25], ...
    'BackgroundColor', [0.850, 0.325, 0.098], 'ForegroundColor', [1 1 1], ...
    'FontWeight', 'bold', 'Callback', {@markEvent, 'offset'});

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'Delete Last  [Del]', ...
    'Units', 'normalized', 'Position', [0.01, 0.05, 0.10, 0.25], ...
    'BackgroundColor', [0.6, 0.6, 0.6], 'FontWeight', 'bold', ...
    'Callback', @deleteLastEvent);

% Onset list
uicontrol('Parent', pnlEvents, 'Style', 'text', 'String', 'Onsets (s)', ...
    'Units', 'normalized', 'Position', [0.13, 0.85, 0.12, 0.10]);
listOnset = uicontrol('Parent', pnlEvents, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.13, 0.05, 0.12, 0.80]);

% Offset list
uicontrol('Parent', pnlEvents, 'Style', 'text', 'String', 'Offsets (s)', ...
    'Units', 'normalized', 'Position', [0.27, 0.85, 0.12, 0.10]);
listOffset = uicontrol('Parent', pnlEvents, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.27, 0.05, 0.12, 0.80]);

% Duration list (computed automatically from matched pairs)
uicontrol('Parent', pnlEvents, 'Style', 'text', 'String', 'Duration (s)', ...
    'Units', 'normalized', 'Position', [0.41, 0.85, 0.12, 0.10]);
listDuration = uicontrol('Parent', pnlEvents, 'Style', 'listbox', 'String', {}, ...
    'Units', 'normalized', 'Position', [0.41, 0.05, 0.12, 0.80]);

% Export button
uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', 'String', 'Export Events  (CSV)', ...
    'Units', 'normalized', 'Position', [0.56, 0.06, 0.16, 0.25], ...
    'Callback', @exportEvents);


%% 3. HELPER UTILITIES

% Briefly disable/re-enable a control to return keyboard focus to the figure
    function removeFocus(hObject)
        set(hObject, 'Enable', 'off');
        drawnow;
        set(hObject, 'Enable', 'on');
    end

% Clear all marked events and their graphic lines
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

% Load video
    function loadVideo(hObject, ~)
        removeFocus(hObject);
        [fileStr, pathStr] = uigetfile( ...
            {'*.mp4;*.avi;*.wmv;*.mov', 'Video Files'; '*.*', 'All Files'}, ...
            'Select Video File');
        if isequal(fileStr, 0); return; end

        resetEvents();  % Clear previous events when a new video is loaded

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
        speedOptions = [0.25, 0.5, 1, 2, 4];
        playbackSpeed = speedOptions(src.Value);
    end

% Load neural or behavioral signal
%   Reads the LAST column of the file as the signal.
%   Builds the time vector as (0 : N-1) / Fs, so no time column is needed.
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

            % Build time vector starting at t = 0
            neuroTime = (0 : numSamples-1)' / fs;
            neuroData = signal;

            if isgraphics(neuroPlotObj); delete(neuroPlotObj); end
            neuroPlotObj = plot(axNeural, neuroTime, neuroData, ...
                'Color', [0, 0.447, 0.741], 'LineWidth', 1);

            % Create cursor line if not already present
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
        % Neural: symmetric around zero
        valN = str2double(editYNeural.String);
        if ~isnan(valN) && valN > 0
            ylim(axNeural, [-valN, valN]);
        else
            axis(axNeural, 'auto y');
            editYNeural.String = 'Auto';
        end

        % Behavior: positive range from zero
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
            if mod(currFrame, 3) == 0; syncDataAxes(); end   % sync every 3 frames
            drawnow limitrate;
            elapsed = toc;
            targetDelay = 1 / (fps * playbackSpeed);
            if elapsed < targetDelay; pause(targetDelay - elapsed); end
            isPlaying = btnPlay.Value;
        end

        btnPlay.Value = 0;
        isPlaying = false;
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
            src.String = num2str(windowScale);  % revert invalid input
        end
    end

% Synchronize data axes to current video time
%    Time is derived from frame index to avoid VideoReader drift.
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
            color = [0.635, 0.078, 0.184];   % dark red

        elseif strcmp(type, 'offset')
            % Prevent orphan offsets
            if length(offsets_sec) >= length(onsets_sec)
                warndlg('Mark an Onset before marking an Offset.', 'Order Error');
                return;
            end
            offsets_sec(end+1)   = cTime;
            offsets_frame(end+1) = currFrame;
            color = [0.850, 0.325, 0.098];   % orange
        end

        % Draw vertical marker on both axes
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
%    Removes an unmatched onset first; otherwise removes the last offset.
    function deleteLastEvent(hObject, ~)
        if ~isempty(hObject); removeFocus(hObject); end
        if isempty(onsets_sec); return; end

        if length(offsets_sec) < length(onsets_sec)
            % Remove unmatched onset
            onsets_sec(end)   = [];
            onsets_frame(end) = [];
        elseif ~isempty(offsets_sec)
            % Remove last offset
            offsets_sec(end)   = [];
            offsets_frame(end) = [];
        else
            return;
        end

        % Remove corresponding marker lines
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

% Export events to CSV
    function exportEvents(hObject, ~)
        removeFocus(hObject);
        if isempty(onsets_sec)
            msgbox('No events to export.', 'Empty');
            return;
        end

        nOnsets = length(onsets_sec);

        % Pad offsets with NaN for any onset that was never closed
        os  = onsets_sec;
        ofs = offsets_sec;
        on  = onsets_frame;
        of  = offsets_frame;
        if length(ofs) < nOnsets
            ofs(end+1:nOnsets) = NaN;
            of(end+1:nOnsets)  = NaN;
        end

        dur = ofs - os;   % duration in seconds (NaN for unclosed events)

        % Default export filename derived from the loaded video name
        if isempty(videoFileName)
            defaultName = 'behavior_events.csv';
        else
            [~, nm] = fileparts(videoFileName);
            defaultName = [nm '_events.csv'];
        end

        [file, path] = uiputfile(defaultName, 'Save Events');
        if isequal(file, 0); return; end

        fullFile = fullfile(path, file);

        % Write metadata header
        fid = fopen(fullFile, 'w');
        fprintf(fid, '# BehaviorSync export | Video: %.4f fps', fps);
        if ~isempty(neuroTime)
            fprintf(fid, ' | Neural Fs: %s Hz', editFsNeuro.String);
        end
        if ~isempty(behavTime)
            fprintf(fid, ' | Behavior Fs: %s Hz', editFsBehav.String);
        end
        fprintf(fid, '\n');

        % Write column headers
        fprintf(fid, ...
            'Frame (sample) onset,Frame (sample) offset,Onset (seconds),Offset (seconds),Duration (seconds)\n');
        fclose(fid);

        % Append data (suppress MATLAB's automatic variable-name row)
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
                % Smart toggle: onset if counts are balanced, else offset
                if length(onsets_sec) == length(offsets_sec)
                    markEvent([], [], 'onset');
                else
                    markEvent([], [], 'offset');
                end

            case 'i';  markEvent([], [], 'onset');
            case 'o';  markEvent([], [], 'offset');

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

end