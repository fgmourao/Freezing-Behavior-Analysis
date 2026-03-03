function App_Behavior()
%% App_Behavior

% DESCRIPTION
%   Graphical User Interface (GUI) control center for the behavior analysis
%   pipeline. Provides interactive panels for loading data, configuring
%   parameters, running analysis, and exporting results — without requiring
%   MATLAB App Designer.
%
%   All UI state is managed through a shared 'appData' struct that is
%   accessible by all nested callback functions via closure.

% LAYOUT
%   Panel 1 (top-left)   - Basic Parameters (fs, threshold, duration, baseline)
%   Panel 2 (top-right)  - Block Analysis definitions (up to 5 prefix/size pairs)
%   Panel 3 (middle)     - Events table (editable; loadable from CSV/TXT)
%   Panel 4 (bottom)     - Plot Viewer (dropdown + Show Figure button)
%   Status bar           - Color-coded feedback label
%   Run button           - Triggers the full analysis pipeline
%   Menu > File          - Load data, export Excel, save .mat, save timestamps
%   Menu > Tools         - Launch BehaviorSync (Video/Neural Synchronization GUI)

% WORKFLOW
%   1. Load one or more raw data files via File menu or Run button.
%   2. Fill or load the events table (Name, Onset_s, Offset_s).
%      * Tip: Use Tools > Open BehaviorSync to visually extract these events from video.
%   3. Set basic and block parameters in the panels.
%   4. Click RUN ANALYSIS.
%   5. Use the Plot Viewer or File menu to export results.

% OUTPUTS (via File menu after analysis)
%   <file>_Results.xlsx     - Freeze metrics per epoch per subject
%   <file>_Timestamps.xlsx  - Freeze / non-freeze onset-offset pairs
%   Data_Results.mat        - Full data_results struct (workspace variable)

%   BehaviorSync Output (via Tools menu)  [under construction]
%   <file>_events.csv       - Extracted behavioral events from video through
%                             visual inspection, containing:
%                             Row 1: Metadata (Video fps, Neural Fs, Behavior Fs)
%                             Columns: Frame (sample) onset | Frame (sample) offset |
%                                      Onset (seconds) | Offset (seconds) | Duration (seconds)
%                             * The exported Onset/Offset times can be loaded directly into Panel 3.

%   KNOWN LIMITATIONS:
%   - If the behavioral or neural recording does not start at the same
%     real-world time as the video, a manual Time Offset (s) field will
%     be required for precise alignment. This feature is under development.

%   NOTE: This function BehaviorSync is still under construction.
%           Synchronization issues between signals with different start times
%           will be addressed in future versions.


% REQUIRES
%   Behavior_Analyse.m, detect_bouts.m, Plot_Behavior_Batch.m, BehaviorSync.m

% AUTHOR
%   Flavio Mourao (mourao.fg@gmail.com)
%   Texas A&M University - Department of Psychological and Brain Sciences
%   University of Illinois Urbana-Champaign - Beckman Institute
%   Federal University of Minas Gerais - Brazil

% Started:     12 / 2023
% Last update: 03 / 2026

%%  1. Main Figure

fig = figure('Name',        'Behavior Analysis', ...
             'Position',    [100, 100, 800, 650], ...
             'MenuBar',     'none', ...
             'NumberTitle', 'off', ...
             'Color',       [0.94 0.94 0.94]);

% Shared application state — accessible by all callbacks via closure
appData.file_names   = {};
appData.path_name    = '';
appData.data_results = struct();
appData.P            = struct();


%%  2. File Menu

menuFile        = uimenu(fig, 'Label', 'File');
uimenu(menuFile, 'Label', '1. Load Data Files (.out, .csv)',        'Callback', @loadFiles);
mExport         = uimenu(menuFile, 'Label', '2. Export Results (.xls)',          'Callback', @exportExcel,     'Enable', 'off');
mSaveMat        = uimenu(menuFile, 'Label', '3. Save Results (.mat)',            'Callback', @saveMatFile,     'Enable', 'off');
mSaveTimestamps = uimenu(menuFile, 'Label', '4. Export freeze timestamps (.xls)',  'Callback', @saveTimestamps,  'Enable', 'off');

% 2.1 Tools Menu
menuTools = uimenu(fig, 'Label', 'Tools');
uimenu(menuTools, 'Label', 'Open BehaviorSync (Video/Neural Sync)', 'Callback', @openBehaviorSync);

%% 3. Basic Parameters Panel (top-left)

pnlBasic = uipanel('Parent', fig, 'Title', 'Basic Parameters', ...
                   'Units', 'pixels', 'Position', [20, 480, 370, 150]);

uicontrol(pnlBasic, 'Style', 'text',  'String', 'Sampling Rate (Hz):',    'Position', [10, 100, 140, 20], 'HorizontalAlignment', 'left');
edtFs     = uicontrol(pnlBasic, 'Style', 'edit', 'String', '5',           'Position', [160, 100, 80, 20]);

uicontrol(pnlBasic, 'Style', 'text',  'String', 'Freeze Threshold (%):',  'Position', [10, 70, 140, 20], 'HorizontalAlignment', 'left');
edtThr    = uicontrol(pnlBasic, 'Style', 'edit', 'String', '10',          'Position', [160, 70, 80, 20]);

uicontrol(pnlBasic, 'Style', 'text',  'String', 'Min Freeze Dur. (s):',   'Position', [10, 40, 140, 20], 'HorizontalAlignment', 'left');
edtMinDur = uicontrol(pnlBasic, 'Style', 'edit', 'String', '1',           'Position', [160, 40, 80, 20]);

uicontrol(pnlBasic, 'Style', 'text',  'String', 'Baseline Dur. (s):',     'Position', [10, 10, 140, 20], 'HorizontalAlignment', 'left');
edtBase   = uicontrol(pnlBasic, 'Style', 'edit', 'String', '180',         'Position', [160, 10, 80, 20]);


%%  4. Block Analysis Panel (top-right)
%  Each row defines one block grouping: a prefix string and a block size N.
%  Events whose names start with the prefix are grouped in windows of N.
%  Rows left empty are ignored during analysis.

pnlBlock = uipanel('Parent', fig, 'Title', 'Block Analysis (Prefix / Size)', ...
                   'Units', 'pixels', 'Position', [410, 480, 370, 150]);

uicontrol(pnlBlock, 'Style', 'text', 'String', 'Block 1:', 'Position', [10, 110, 60, 20], 'HorizontalAlignment', 'left');
edtPrefix1 = uicontrol(pnlBlock, 'Style', 'edit', 'String', 'CS',    'Position', [80, 110, 80, 20]);
edtSize1   = uicontrol(pnlBlock, 'Style', 'edit', 'String', '5',     'Position', [180, 110, 60, 20]);

uicontrol(pnlBlock, 'Style', 'text', 'String', 'Block 2:', 'Position', [10, 85, 60, 20], 'HorizontalAlignment', 'left');
edtPrefix2 = uicontrol(pnlBlock, 'Style', 'edit', 'String', 'ITI',   'Position', [80, 85, 80, 20]);
edtSize2   = uicontrol(pnlBlock, 'Style', 'edit', 'String', '5',     'Position', [180, 85, 60, 20]);

uicontrol(pnlBlock, 'Style', 'text', 'String', 'Block 3:', 'Position', [10, 60, 60, 20], 'HorizontalAlignment', 'left');
edtPrefix3 = uicontrol(pnlBlock, 'Style', 'edit', 'String', 'Trial', 'Position', [80, 60, 80, 20]);
edtSize3   = uicontrol(pnlBlock, 'Style', 'edit', 'String', '5',     'Position', [180, 60, 60, 20]);

uicontrol(pnlBlock, 'Style', 'text', 'String', 'Block 4:', 'Position', [10, 35, 60, 20], 'HorizontalAlignment', 'left');
edtPrefix4 = uicontrol(pnlBlock, 'Style', 'edit', 'String', '',      'Position', [80, 35, 80, 20]);
edtSize4   = uicontrol(pnlBlock, 'Style', 'edit', 'String', '',      'Position', [180, 35, 60, 20]);

uicontrol(pnlBlock, 'Style', 'text', 'String', 'Block 5:', 'Position', [10, 10, 60, 20], 'HorizontalAlignment', 'left');
edtPrefix5 = uicontrol(pnlBlock, 'Style', 'edit', 'String', '',      'Position', [80, 10, 80, 20]);
edtSize5   = uicontrol(pnlBlock, 'Style', 'edit', 'String', '',      'Position', [180, 10, 60, 20]);


%% 5. Events Definition Table (middle)
%  Editable table with columns: Event Label | Onset (s) | Offset (s).
%  Can be populated manually or loaded from a CSV/TXT file.
%  Rows with non-numeric or empty onset/offset are ignored at run time.

pnlEvents = uipanel('Parent', fig, 'Title', 'Events Definition (Name, Onset_s, Offset_s)', ...
    'Units', 'pixels', 'Position', [20, 200, 760, 260]);

uicontrol('Parent', pnlEvents, 'Style', 'pushbutton', ...
    'String', 'Load Events File (.txt / .csv)', ...
    'Position', [470, 215, 180, 25], ...
    'Callback', @loadEventsFile, 'FontWeight', 'bold');

% Pre-fill with two example rows so the table is not empty on first launch
default_events       = cell(200, 3);
default_events(1, :) = {'CS1',  180, 190};
default_events(2, :) = {'ITI1', 190, 250};

uitEvents = uitable('Parent', pnlEvents, ...
    'Data',          default_events, ...
    'ColumnName',    {'Event Label', 'Onset (s)', 'Offset (s)'}, ...
    'ColumnEditable', [true, true, true], ...
    'Units', 'pixels', 'Position', [50, 25, 285, 195]);

% Load image
axImg = axes('Parent', pnlEvents, 'Units', 'pixels', 'Position', [400, 35, 320, 140]);
axis(axImg, 'off');

try
    image_ = imread('image.png');
    imshow(image_, 'Parent', axImg);
catch
    text(axImg, 0.5, 0.5, 'A.C.A.B', 'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', [0.5 0.5 0.5]);
end


%% 6. Status Bar & Run Button

lblStatus = uicontrol('Parent', fig, 'Style', 'text', ...
                      'String',           'Status: Waiting for data files...', ...
                      'Position',         [20, 140, 500, 30], ...
                      'ForegroundColor',  'r', ...
                      'FontSize',          10, ...
                      'HorizontalAlignment', 'left', ...
                      'FontWeight',        'bold');

% Run button is disabled until at least one data file is loaded
btnRun = uicontrol('Parent', fig, 'Style', 'pushbutton', ...
                   'String',   'RUN ANALYSIS', ...
                   'Position', [630, 140, 150, 40], ...
                   'Callback', @runAnalysis, ...
                   'Enable',   'off', ...
                   'FontWeight', 'bold');


%% 7. Plot Viewer Panel (bottom)

pnlPlot = uipanel('Parent', fig, 'Title', 'Plot Viewer', ...
                  'Units', 'pixels', 'Position', [20, 20, 760, 100]);

% Dropdown is populated with processed file names after analysis completes
ddFiles = uicontrol('Parent', pnlPlot, 'Style', 'popupmenu', ...
                    'String',   {'Run analysis first...'}, ...
                    'Position', [20, 40, 500, 30], ...
                    'Enable',   'off', 'FontSize', 10);

btnPlot = uicontrol('Parent', pnlPlot, 'Style', 'pushbutton', ...
                    'String',   'SHOW FIGURE', ...
                    'Position', [550, 30, 150, 40], ...
                    'Callback', @showFigure, ...
                    'Enable',   'off', 'FontWeight', 'bold');


%% CALLBACK FUNCTIONS

% openBehaviorSync  -  Launch the BehaviorSync GUI in a separate window
    function openBehaviorSync(~, ~)
        try
            BehaviorSync(); % Chama o arquivo BehaviorSync.m
        catch ME
            errordlg(['Could not open BehaviorSync. Make sure BehaviorSync.m is in the same folder. Error: ' ME.message], 'Launch Error');
        end
    end

% loadFiles  -  Select one or more raw data files

    function loadFiles(~, ~)

        [files, path] = uigetfile( ...
            {'*.out;*.txt;*.csv', 'Data Files (*.out, *.txt, *.csv)'}, ...
            'Select the DATA files', 'MultiSelect', 'on');

        if isequal(files, 0), return; end

        % Wrap single filename in a cell array for uniform indexing
        if ischar(files), files = {files}; end

        appData.file_names = files;
        appData.path_name  = path;

        set(lblStatus, 'String', ...
            sprintf('Status: %d file(s) loaded. Ready to run.', length(files)), ...
            'ForegroundColor', [0 0.5 0]);

        set(btnRun, 'Enable', 'on');

    end


% loadEventsFile  -  Load event definitions from a CSV or TXT file

    function loadEventsFile(~, ~)

        [ev_file, ev_path] = uigetfile( ...
            {'*.csv;*.txt', 'Event Timings File (*.csv, *.txt)'}, ...
            'Select the EVENTS file');

        if isequal(ev_file, 0), return; end

        ev_data = readcell(fullfile(ev_path, ev_file));

        if size(ev_data, 2) < 3
            errordlg('The events file must have 3 columns: Name, Onset, Offset.', 'Format Error');
            return;
        end

        % Parse and validate event rows
        event_names_raw = strip(string(ev_data(:, 1)));
        onsets          = str2double(string(ev_data(:, 2)));
        offsets         = str2double(string(ev_data(:, 3)));

        valid_rows = ~isnan(onsets) & ~isnan(offsets) & (strlength(event_names_raw) > 0);
        num_valid  = sum(valid_rows);

        if num_valid == 0
            errordlg('No valid numeric events found in the file.', 'Data Error');
            return;
        end

        % Build a num_valid-by-3 cell array for the table
        loaded_events       = cell(num_valid, 3);
        loaded_events(:, 1) = cellstr(event_names_raw(valid_rows));
        loaded_events(:, 2) = num2cell(onsets(valid_rows));
        loaded_events(:, 3) = num2cell(offsets(valid_rows));

        % Pad table to at least 200 rows so the user can add events manually
        total_rows_table = max(200, num_valid + 10);
        new_table_data   = cell(total_rows_table, 3);
        new_table_data(1:num_valid, :) = loaded_events;

        set(uitEvents, 'Data', new_table_data);
        set(lblStatus, 'String', ...
            sprintf('Status: Successfully loaded %d events from file.', num_valid), ...
            'ForegroundColor', [0 0 0.8]);

    end


% runAnalysis  -  Collect parameters, run Behavior_Analyse on all files

    function runAnalysis(~, ~)

        set(lblStatus, 'String', 'Status: Running analysis... Please wait.', ...
            'ForegroundColor', 'k');
        drawnow;

        % Collect basic parameters
        P.fs           = str2double(get(edtFs,     'String'));
        P.thr_low      = str2double(get(edtThr,    'String'));
        P.thr_dur      = str2double(get(edtMinDur, 'String'));
        P.baseline_dur = str2double(get(edtBase,   'String'));

        % Collect block definitions (until now ...up to 5)
        % Empty prefix fields will be skipped inside Behavior_Analyse.
        P.block_prefixes = { ...
            strtrim(get(edtPrefix1, 'String')), ...
            strtrim(get(edtPrefix2, 'String')), ...
            strtrim(get(edtPrefix3, 'String')), ...
            strtrim(get(edtPrefix4, 'String')), ...
            strtrim(get(edtPrefix5, 'String'))};

        P.block_sizes = [ ...
            str2double(get(edtSize1, 'String')), ...
            str2double(get(edtSize2, 'String')), ...
            str2double(get(edtSize3, 'String')), ...
            str2double(get(edtSize4, 'String')), ...
            str2double(get(edtSize5, 'String'))];

        % Parse events table
        % Keep only rows with a non-empty label and numeric onset/offset
        tblData = get(uitEvents, 'Data');

        valid_idx = cellfun(@(x) ischar(x) || isstring(x), tblData(:, 1)) & ...
                    cellfun(@isnumeric, tblData(:, 2))                     & ...
                    cellfun(@isnumeric, tblData(:, 3))                     & ...
                    ~cellfun(@isempty,  tblData(:, 1));

        valid_data = tblData(valid_idx, :);

        if isempty(valid_data)
            errordlg('No valid events found in the table. Fill at least one row.', 'Input Error');
            set(lblStatus, 'String', 'Status: Ready.');
            return;
        end

        P.event_names = string(valid_data(:, 1));
        P.events_sec  = cell2mat(valid_data(:, 2:3));
        appData.P     = P;

        % Process each file
        data_results = struct();

        for f = 1:length(appData.file_names)

            file_path = fullfile(appData.path_name, appData.file_names{f});

            % Load raw data and remove the timestamp column (column 1)
            raw_data       = readmatrix(file_path, 'FileType', 'text');
            raw_data(:, 1) = [];

            [data, params_out] = Behavior_Analyse(raw_data, P);

            % Store results under a valid MATLAB field name
            safe_name = matlab.lang.makeValidName(appData.file_names{f});
            data_results.(safe_name) = data;

            % Save shared parameters from the first file only
            if f == 1
                data_results.parameters = params_out;
            end

        end

        appData.data_results = data_results;

        % Export data_results to the base workspace for manual inspection
        assignin('base', 'Data_results', data_results);

        % Update UI after successful analysis
        valid_fields = fieldnames(data_results);
        valid_fields(strcmp(valid_fields, 'parameters')) = [];

        set(ddFiles,         'String', valid_fields, 'Value', 1, 'Enable', 'on');
        set(btnPlot,         'Enable', 'on');
        set(mExport,         'Enable', 'on');
        set(mSaveMat,        'Enable', 'on');
        set(mSaveTimestamps, 'Enable', 'on');

        set(lblStatus, 'String', ...
            'Status: Analysis complete! Data sent to Workspace (Data_results).', ...
            'ForegroundColor', [0 0.5 0]);

    end


% showFigure  -  Generate and display the summary figure for one file

    function showFigure(~, ~)

        list_strings  = get(ddFiles, 'String');
        selected_idx  = get(ddFiles, 'Value');
        selected_file = list_strings{selected_idx};

        % Build a minimal data_results struct containing only the selected file
        % so that Plot_Behavior_Batch renders a single-file figure
        temp_results            = struct();
        temp_results.parameters = appData.P;
        temp_results.(selected_file) = appData.data_results.(selected_file);

        Plot_Behavior_Batch(temp_results);

    end


% saveMatFile  -  Save the full data_results struct to a .mat file
    function saveMatFile(~, ~)

        [file, path] = uiputfile('Behavior_Results.mat', 'Save Data as .mat');

        if isequal(file, 0), return; end

        Data_results = appData.data_results;
        save(fullfile(path, file), 'Data_results', '-v7.3');

        set(lblStatus, 'String', ...
            sprintf('Status: Workspace successfully saved as %s!', file), ...
            'ForegroundColor', [0 0.5 0]);

    end


% exportExcel  -  Export all freeze metrics to per-file Excel workbooks
%
%  behavior_freezing column layout (referenced by index below):
%    {n, 1}  Raw bout durations      (cell per subject)
%    {n, 2}  Mean bout duration      (vector, seconds)
%    {n, 3}  Number of bouts         (vector, count)
%    {n, 4}  Total freeze time       (vector, seconds)
%    {n, 5}  Freeze percentage       (vector, %)
%    {n, 6}  Mean inter-bout delta-T (vector, seconds)
%    {n, 7}  Raw inter-bout delta-T  (cell per subject, seconds)
%
    function exportExcel(~, ~)

        set(lblStatus, 'String', 'Status: Exporting to Excel... Please wait.', ...
            'ForegroundColor', 'b');
        drawnow;

        valid_fields = fieldnames(appData.data_results);
        valid_fields(strcmp(valid_fields, 'parameters')) = [];

        for f = 1:length(valid_fields)

            curr_file    = valid_fields{f};
            data         = appData.data_results.(curr_file);
            n_epochs     = size(data.behavior_freezing, 1);
            num_subjects = length(data.behavior_freezing{1, 2});

            % Build row and column labels
            epoch_labels    = cell(n_epochs, 1);
            epoch_labels{1} = 'Full Session';
            epoch_labels{2} = 'Baseline';
            for e = 3:n_epochs
                epoch_labels{e} = char(appData.P.event_names(e - 2));
            end

            subj_labels = arrayfun(@(x) sprintf('Subject %d', x), 1:num_subjects, 'UniformOutput', false);
            header_row  = ['Epoch', subj_labels];

            % Pre-allocate per-metric export cell arrays
            freeze_cell   = cell(n_epochs, num_subjects);
            bout_cell     = cell(n_epochs, num_subjects);
            dur_cell      = cell(n_epochs, num_subjects);
            mean_dur_cell = cell(n_epochs, num_subjects);
            mean_dt_cell  = cell(n_epochs, num_subjects);
            raw_dt_cell   = cell(n_epochs, num_subjects);

            for n = 1:n_epochs

                % Scalar metrics (one value per subject per epoch)
                freeze_cell(n, :)    = num2cell(data.behavior_freezing{n, 5}');
                bout_cell(n, :)      = num2cell(data.behavior_freezing{n, 3}');
                mean_dur_cell(n, :)  = num2cell(data.behavior_freezing{n, 2}');
                mean_dt_cell(n, :)   = num2cell(data.behavior_freezing{n, 6}');

                % Variable-length per-subject arrays: serialised as comma-separated strings
                for s = 1:num_subjects

                    % Raw bout durations
                    bouts_array = data.behavior_freezing{n, 1}{s};
                    if isempty(bouts_array)
                        dur_cell{n, s} = '0';
                    else
                        dur_cell{n, s} = strjoin(string(round(bouts_array, 2)), ', ');
                    end

                    % Raw inter-bout delta-T values
                    dt_array = data.behavior_freezing{n, 7}{s};
                    if isempty(dt_array)
                        raw_dt_cell{n, s} = 'NaN';
                    else
                        raw_dt_cell{n, s} = strjoin(string(round(dt_array, 2)), ', ');
                    end

                end
            end

            % Resolve output path from original filename
            original_file_name = appData.file_names{f};
            [~, base_name, ~]  = fileparts(original_file_name);
            out_xlsx = fullfile(appData.path_name, [base_name, '_Results.xlsx']);

            % Write standard metric sheets
            writecell([header_row; [epoch_labels, freeze_cell]],   out_xlsx, 'Sheet', '1_Freezing_Percentage');
            writecell([header_row; [epoch_labels, bout_cell]],     out_xlsx, 'Sheet', '2_Total_Bouts');
            writecell([header_row; [epoch_labels, mean_dur_cell]], out_xlsx, 'Sheet', '3_Mean_Bout_Duration(s)');
            writecell([header_row; [epoch_labels, dur_cell]],      out_xlsx, 'Sheet', '4_Bout_Duration(s)');
            writecell([header_row; [epoch_labels, mean_dt_cell]],  out_xlsx, 'Sheet', '5_Mean_Bout_DeltaT(s)');
            writecell([header_row; [epoch_labels, raw_dt_cell]],   out_xlsx, 'Sheet', '6_Bout_DeltaT(s)');

            % Write block analysis sheets (one set per block)

            if isfield(data, 'blocks') && ~isempty(data.blocks)

                block_header = ['Epoch_Block', subj_labels];

                for b_i = 1:length(data.blocks)
                    pref = data.blocks(b_i).prefix;

                    writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).freeze')]], ...
                        out_xlsx, 'Sheet', sprintf('Blk%d_%s_Freezing_Percentage', b_i, pref));

                    writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).bout')]], ...
                        out_xlsx, 'Sheet', sprintf('Blk%d_%s_Total_Bouts', b_i, pref));

                    writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).dur')]], ...
                        out_xlsx, 'Sheet', sprintf('Blk%d_%s_Mean_Bout_Dur(s)', b_i, pref));

                    writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).delta_t')]], ...
                        out_xlsx, 'Sheet', sprintf('Blk%d_%s_Mean_Bout_DeltaT(s)', b_i, pref));
                end

            end

        end

        set(lblStatus, 'String', 'Status: Excel Export Complete!', 'ForegroundColor', [0 0.5 0]);
        msgbox('All Excel files have been successfully exported to the source folder.', 'Export Complete');

    end


% saveTimestamps  -  Export freeze / non-freeze onset-offset pairs to Excel
%
%  Output format (one sheet per type):
%    Each subject occupies 2 columns: [Onset | Offset]
%    Row 1 is the header; rows 2..N contain the index pairs (samples).
%    The number of rows is determined by the subject with the most bouts.
%
    function saveTimestamps(~, ~)

        set(lblStatus, 'String', 'Status: Exporting timestamps... Please wait.', ...
            'ForegroundColor', 'b');
        drawnow;

        valid_fields = fieldnames(appData.data_results);
        valid_fields(strcmp(valid_fields, 'parameters')) = [];

        for f = 1:length(valid_fields)

            curr_file = valid_fields{f};
            data      = appData.data_results.(curr_file);

            if ~isfield(data, 'events_behavior_idx') || isempty(data.events_behavior_idx)
                continue;
            end

            try
                % Full-session index pairs are stored in Row 1 of events_behavior_idx
                base_ts      = data.events_behavior_idx{1, 1};
                num_subjects = size(base_ts, 1);

                % Find the maximum number of bouts across all subjects
                % to determine how many data rows the export tables need
                max_f  = 0;
                max_nf = 0;
                for s = 1:num_subjects
                    if ~isempty(base_ts{s, 1})
                        max_f  = max(max_f,  size(base_ts{s, 1}, 1));
                    end
                    if ~isempty(base_ts{s, 2})
                        max_nf = max(max_nf, size(base_ts{s, 2}, 1));
                    end
                end

                % Pre-allocate export tables: 1 header row + max bout rows,
                % 2 columns per subject (Onset and Offset)
                freeze_export     = cell(max_f  + 1, num_subjects * 2);
                non_freeze_export = cell(max_nf + 1, num_subjects * 2);

                for s = 1:num_subjects

                    % Each subject occupies 2 consecutive columns
                    col_onset  = (s - 1) * 2 + 1;
                    col_offset = (s - 1) * 2 + 2;

                    % Write column headers
                    freeze_export{1, col_onset}      = sprintf('Subj %d Onset',  s);
                    freeze_export{1, col_offset}     = sprintf('Subj %d Offset', s);
                    non_freeze_export{1, col_onset}  = sprintf('Subj %d Onset',  s);
                    non_freeze_export{1, col_offset} = sprintf('Subj %d Offset', s);

                    % Fill freeze onset/offset pairs (global sample indices)
                    if ~isempty(base_ts{s, 1})
                        num_rows = size(base_ts{s, 1}, 1);
                        freeze_export(2:(num_rows + 1), col_onset)  = num2cell(base_ts{s, 1}(:, 1));
                        freeze_export(2:(num_rows + 1), col_offset) = num2cell(base_ts{s, 1}(:, 2));
                    end

                    % Fill non-freeze onset/offset pairs (global sample indices)
                    if ~isempty(base_ts{s, 2})
                        num_rows = size(base_ts{s, 2}, 1);
                        non_freeze_export(2:(num_rows + 1), col_onset)  = num2cell(base_ts{s, 2}(:, 1));
                        non_freeze_export(2:(num_rows + 1), col_offset) = num2cell(base_ts{s, 2}(:, 2));
                    end

                end

                % Save to a per-file timestamps workbook
                original_file_name = appData.file_names{f};
                [~, base_name, ~]  = fileparts(original_file_name);
                out_xlsx = fullfile(appData.path_name, [base_name, '_Timestamps.xlsx']);

                writecell(freeze_export,     out_xlsx, 'Sheet', 'freezing timestamps');
                writecell(non_freeze_export, out_xlsx, 'Sheet', 'non freezing timestamps');

            catch ME
                warning('Could not extract timestamps for %s: %s', curr_file, ME.message);
            end

        end

        set(lblStatus, 'String', 'Status: Timestamps Excel Export Complete!', ...
            'ForegroundColor', [0 0.5 0]);
        msgbox('Freeze timestamps (Onset and Offset for all subjects) exported successfully.', ...
               'Export Complete');

    end

end