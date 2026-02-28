function data_results = Batch_Behavior_Analyse()
%% Batch_Behavior_Analyse
%
% DESCRIPTION 
%   Batch wrapper for Behavior_Analyse. Processes multiple raw movement
%   files sequentially, exports per-subject results to Excel, and
%   optionally generates summary plots.
%
%   Workflow:
%     1. User selects one or more raw data files (.out / .txt / .csv).
%     2. User selects an events file with columns: [Name, Onset_s, Offset_s].
%     3. Analysis parameters and up to 3 block groupings are entered via dialog.
%     4. Each file is passed to Behavior_Analyse, and results are saved to
%        a per-file Excel workbook with one sheet per metric.
%
% INPUTS (interactive)
%   Data files   - Raw movement files; time column is automatically removed.
%   Events file  - CSV/TXT with columns: EventName | Onset (s) | Offset (s).
%   Dialog       - Sampling rate, freeze threshold, minimum duration,
%                  baseline duration, up to 3 block prefix + size pairs,
%                  and plot generation flag.
%
% OUTPUT
%   data_results - Struct with one field per processed file (valid MATLAB
%                  field name derived from filename), plus a shared
%                  'parameters' field populated from the first file.
%
% EXCEL OUTPUT (saved alongside each input file)
%   Sheet 1_Freezing_Percentage     - Freeze % per epoch per subject
%   Sheet 2_Total_Bouts             - Number of freeze bouts per epoch
%   Sheet 3_Mean_Bout_Duration      - Mean bout duration per epoch
%   Sheet 4_Raw_Bout_Durations      - All individual bout durations (comma-separated)
%   Sheet Blk<N>_<Prefix>_freeze    - Block-averaged freeze % (one sheet per block)
%   Sheet Blk<N>_<Prefix>_Bouts     - Block-averaged bout count
%   Sheet Blk<N>_<Prefix>_Dur       - Block-averaged bout duration
%
% REQUIRES 
%   Behavior_Analyse.m, detect_bouts.m, Plot_Behavior_Batch.m
%
% NOTE 
%   Excel sheet names are capped at 31 characters (Excel limitation).
%   Block sheet names use the short format 'Blk<N>_<Prefix>_<Metric>'
%   to stay within this limit.
%
% AUTHOR
%   Flavio Mourao (mourao.fg@gmail.com)
%   Texas A&M University - Department of Psychological and Brain Sciences
%   University of Illinois Urbana-Champaign - Beckman Institute
%   Federal University of Minas Gerais - Brazil
%
% Started:     12/2023
% Last update: 02/2026

%%  1. File Selection - Data Files


[file_names, path_name] = uigetfile( ...
    {'*.out;*.txt;*.csv', 'Data Files (*.out, *.txt, *.csv)'}, ...
    '1. Select the DATA files', 'MultiSelect', 'on');

if isequal(file_names, 0)
    disp('Data file selection cancelled.');
    return;
end

% Wrap single filename in a cell array for uniform indexing below
if ischar(file_names)
    file_names = {file_names};
end


%%  2. File Selection - Events File

[ev_file, ev_path] = uigetfile( ...
    {'*.csv;*.txt', 'Event Timings File (*.csv, *.txt)'}, ...
    '2. Select the EVENTS file (Name, Onset, Offset)');

if isequal(ev_file, 0)
    disp('Event file selection cancelled.');
    return;
end

% Read event table and validate column count
ev_data = readcell(fullfile(ev_path, ev_file));

if size(ev_data, 2) < 3
    errordlg('The events file must have at least 3 columns: Name | Onset | Offset.', 'Format Error');
    return;
end

% Parse event names and timings; discard rows with non-numeric onset/offset
event_names_raw = strip(string(ev_data(:, 1)));
onsets          = str2double(string(ev_data(:, 2)));
offsets         = str2double(string(ev_data(:, 3)));

valid_rows = ~isnan(onsets) & ~isnan(offsets);


%%  3. Analysis Parameters - Input Dialog


prompt = { ...
    'Sampling rate (Hz):', ...
    'Freeze threshold (% movement):', ...
    'Minimum freeze duration (s):', ...
    'Baseline duration (s):', ...
    'Block 1 - Target Prefix (e.g., CS):', ...
    'Block 1 - Block Size (N events):', ...
    'Block 2 - Target Prefix (e.g., ITI):', ...
    'Block 2 - Block Size:', ...
    'Block 3 - Target Prefix (e.g., Trial):', ...
    'Block 3 - Block Size:', ...
    'Generate Plots (0 = No, 1 = Yes):'};

default = {'5', '10', '1', '180', 'CS', '5', 'ITI', '5', 'Trial(CS+ITI)', '5', '1'};

answer = inputdlg(prompt, 'Batch Analysis Parameters', [1 55], default);

if isempty(answer)
    disp('Analysis cancelled.');
    return;
end

% Populate parameters struct

P.fs           = str2double(answer{1});
P.thr_low      = str2double(answer{2});
P.thr_dur      = str2double(answer{3});
P.baseline_dur = str2double(answer{4});

% Store up to 3 block definitions as parallel lists.
% Empty prefix entries will be ignored during block analysis.
P.block_prefixes = {strtrim(answer{5}), strtrim(answer{7}), strtrim(answer{9})};
P.block_sizes    = [str2double(answer{6}), str2double(answer{8}), str2double(answer{10})];

% Event timings and names (rows with invalid onset/offset already filtered out)
P.events_sec  = [onsets(valid_rows), offsets(valid_rows)];
P.event_names = event_names_raw(valid_rows);

do_plot = str2double(answer{11});


%%  4. Batch Processing Loop

num_files    = length(file_names);
data_results = struct();

for f = 1:num_files

    fprintf('\n[%d/%d] Processing file: %s\n', f, num_files, file_names{f});

    % Load raw data and remove time column (column 1) 
    file_path = fullfile(path_name, file_names{f});
    raw_data  = readmatrix(file_path, 'FileType', 'text');
    raw_data(:, 1) = [];   % first column is assumed to be timestamps

    % Run core analysis 
    [data, parameters_out] = Behavior_Analyse(raw_data, P);

    % Store results using a valid MATLAB field name derived from the filename
    safe_filename = matlab.lang.makeValidName(file_names{f});
    data_results.(safe_filename) = data;

    % Save shared parameters from the first file only (same for all files)
    if f == 1
        data_results.parameters = parameters_out;
    end

    % Export results to Excel 
    fprintf('  -> Exporting results to Excel...\n');

    [~, base_name, ~] = fileparts(file_names{f});
    out_xlsx = fullfile(path_name, [base_name, '_Results.xlsx']);

    n_epochs     = size(data.behavior_freezing, 1);
    num_subjects = length(data.behavior_freezing{1, 2});   % inferred from first epoch

    % Build epoch row labels (Full Session, Baseline, then event names)
    epoch_labels = cell(n_epochs, 1);
    epoch_labels{1} = 'Full Session';
    epoch_labels{2} = 'Baseline';
    for e = 3:n_epochs
        epoch_labels{e} = char(P.event_names(e - 2));
    end

    % Build subject column labels
    subj_labels = arrayfun(@(x) sprintf('Subject %d', x), 1:num_subjects, 'UniformOutput', false);
    header_row  = ['Epoch', subj_labels];

    % Pre-allocate per-metric cell arrays (epochs x subjects)
    freeze_cell      = cell(n_epochs, num_subjects);
    bout_cell        = cell(n_epochs, num_subjects);
    dur_cell         = cell(n_epochs, num_subjects);
    mean_dur_cell    = cell(n_epochs, num_subjects);

    for n = 1:n_epochs
        % behavior_freezing column layout:
        %   {n,1} = raw bout durations (cell per subject)
        %   {n,2} = mean bout duration per subject
        %   {n,3} = total number of bouts per subject
        %   {n,5} = freeze percentage per subject
        freeze_cell(n, :)      = num2cell(data.behavior_freezing{n, 5}');
        bout_cell(n, :)        = num2cell(data.behavior_freezing{n, 3}');
        mean_dur_cell(n, :)    = num2cell(data.behavior_freezing{n, 2}');

        % Raw bout durations: join multiple values as a comma-separated string
        for s = 1:num_subjects
            bouts_array = data.behavior_freezing{n, 1}{s};
            if isempty(bouts_array)
                dur_cell{n, s} = '0';
            else
                dur_cell{n, s} = strjoin(string(round(bouts_array, 2)), ', ');
            end
        end
    end

    % Write standard metric sheets
    writecell([header_row; [epoch_labels, freeze_cell]],   out_xlsx, 'Sheet', '1_Freezing_Percentage');
    writecell([header_row; [epoch_labels, bout_cell]],     out_xlsx, 'Sheet', '2_Total_Bouts');
    writecell([header_row; [epoch_labels, mean_dur_cell]], out_xlsx, 'Sheet', '3_Mean_Bout_Duration');
    writecell([header_row; [epoch_labels, dur_cell]],      out_xlsx, 'Sheet', '4_Raw_Bout_Durations');

    % Export block-averaged results (one set of sheets per block)
    % Each block groups consecutive events matching a prefix (e.g., 'CS1'..'CS5').
    % Sheet names are truncated to 31 characters to comply with Excel's limit.
    if isfield(data, 'blocks') && ~isempty(data.blocks)

        block_header = ['Epoch_Block', subj_labels];

        for b_i = 1:length(data.blocks)

            pref = data.blocks(b_i).prefix;

            writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).freeze')]], ...
                out_xlsx, 'Sheet', sprintf('Blk%d_%s_freeze',   b_i, pref));

            writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).bout')]], ...
                out_xlsx, 'Sheet', sprintf('Blk%d_%s_Bouts', b_i, pref));

            writecell([block_header; [data.blocks(b_i).labels', num2cell(data.blocks(b_i).dur')]], ...
                out_xlsx, 'Sheet', sprintf('Blk%d_%s_Dur',   b_i, pref));

        end
    end

end


%%  5. Optional Plot Generation


fprintf('\nBatch analysis completed successfully!\n');

if do_plot == 1
    fprintf('\nGenerating and saving plots...\n');
    Plot_Behavior_Batch(data_results);
end

end