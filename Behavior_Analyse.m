function [data, parameters] = Behavior_Analyse(raw_signal, params)
%% Behavior_Analyse
%
% DESCRIPTION
%   Identifies and quantifies freezing and non-freezing bouts from a raw
%   movement signal. Natively supports MULTIPLE SUBJECTS (columns) and
%   includes optional Block Analysis for grouping consecutive events.
%
%   Each subject's signal is normalised independently to 0-100% of its own
%   maximum movement. Freezing bouts are detected once globally per subject
%   and then mapped to each epoch, ensuring consistency across all outputs.
%
% USAGE
%   [data, parameters] = Behavior_Analyse(raw_signal)
%   [data, parameters] = Behavior_Analyse(raw_signal, params)
%
% INPUT
%   raw_signal - M-by-S numeric matrix: M samples, S subjects.
%                Single-subject vectors (1-by-M or M-by-1) are accepted
%                and reshaped to M-by-1 internally.
%   params     - (optional) struct with pre-defined analysis parameters.
%                If omitted, an input dialog is shown (standalone mode).
%                Required fields when provided:
%                  .fs             Sampling rate (Hz)
%                  .thr_low        Freeze threshold (% movement)
%                  .thr_dur        Minimum freeze duration (s)
%                  .baseline_dur   Baseline duration (s)
%                  .events_sec     E-by-2 matrix [onset_s, offset_s]
%                  .event_names    E-by-1 string array of event labels
%                Optional fields (for block analysis):
%                  .block_prefixes Cell array of prefix strings (up to 5)
%                  .block_sizes    Numeric array of block sizes (N events)
%
% OUTPUT ORGANIZATION
%   All cell arrays share a consistent row indexing:
%     Row 1       - Full Session  (entire recording)
%     Row 2       - Baseline      (pre-event period)
%     Rows 3..N   - Experimental Events (one row per event in events_sec)
%
%   data.behavior_freezing  (Cell Array, N rows x 7 cols)
%   {Row, 1}  Raw bout durations  : S-by-1 cell, each entry is 1-by-B vector (s)
%   {Row, 2}  Mean bout duration  : S-by-1 vector (s); 0 if no freezing
%   {Row, 3}  Number of bouts     : S-by-1 vector (count)
%   {Row, 4}  Total freeze time   : S-by-1 vector (s)
%   {Row, 5}  Freeze percentage   : S-by-1 vector (%)
%   {Row, 6}  Mean Interval between freeze bout Delta T   : S-by-1 vector (s); NaN if fewer than 2 bouts
%               Interval in seconds between consecutive freeze bouts.
%   {Row, 7}  Interval between freeze bout (Delta T)      : S-by-1 cell, each entry is 1-by-(B-1) vector (s)
%
%   data.behavior_nonfreezing  (Cell Array, N rows x 1 col)
%   {Row, 1}  S-by-1 cell, each entry is 1-by-B vector of non-freeze durations (s)
%
%   data.events_behavior_idx  (Cell Array, N rows x 1 col)
%   {Row, 1}  S-by-3 cell array per epoch:
%               {s, 1}  Freeze index pairs     : B-by-2 [start, end] (global)
%               {s, 2}  Non-freeze index pairs : B-by-2 [start, end] (global)
%               {s, 3}  Binary freeze mask     : 1-by-M logical vector
%
%   data.behavior_epochs  (Cell Array, N rows x 1 col)
%   {Row, 1}  S-by-M matrix of normalised signal segments for each epoch.
%
%   data.blocks  (Struct Array, one element per active block definition)
%   .prefix   Matched event prefix string
%   .size     Block size (N events averaged together)
%   .labels   1-by-B cell of block label strings (e.g., 'CS 1-5')
%   .freeze   S-by-B matrix of mean freeze % per block
%   .bout     S-by-B matrix of summed bout count per block
%   .dur      S-by-B matrix of mean bout duration per block
%   .delta_t  S-by-B matrix of mean Delta T per block
%
%   parameters  (Struct)
%   .fs, .thr_low, .thr_dur, .baseline_dur, .events_sec, .events_idx,
%   .event_names, .block_prefixes, .block_sizes
%
% REQUIRES
%   detect_bouts.m  must be on the MATLAB path or in the same folder.
%
% AUTHOR
%   Flavio Mourao (mourao.fg@gmail.com)
%   Texas A&M University - Department of Psychological and Brain Sciences
%   University of Illinois Urbana-Champaign - Beckman Institute
%   Federal University of Minas Gerais - Brazil
%
% Started:     12/2023
% Last update: 02/2026

%% 1. Input Handling & Normalisation

% Reshape single-subject vectors to a column vector (M-by-1)
if isvector(raw_signal)
    raw_signal = raw_signal(:);
end

[n_samples, num_subjects] = size(raw_signal);
raw_signal = double(raw_signal);

% Normalise each subject independently to 0-100% of their own max movement.
% Vectorised across subjects (min/max operate column-wise).
min_vals   = min(raw_signal,   [], 1);
max_vals   = max(raw_signal,   [], 1);
range_vals = max_vals - min_vals;
range_vals(range_vals == 0) = 1;   % guard against flat (zero-range) signals
raw_signal = 100 * (raw_signal - min_vals) ./ range_vals;


%% 2. Parameters

if nargin < 2
    % Input dialog
    prompt  = { ...
        'Sampling rate (Hz):', ...
        'Freeze threshold (% movement):', ...
        'Minimum freeze duration (s):', ...
        'Baseline duration (s):'};
    default = {'1000', '5', '1', '180'};
    answer  = inputdlg(prompt, 'Behavior Analysis Parameters', [1 50], default);

    if isempty(answer)
        return;
    end

    P.fs           = str2double(answer{1});
    P.thr_low      = str2double(answer{2});
    P.thr_dur      = str2double(answer{3});
    P.baseline_dur = str2double(answer{4});
    P.events_sec   = [];
    P.event_names  = [];

else
    % Batch mode: use pre-defined parameter struct
    P = params;
end

% Convert minimum freeze duration from seconds to samples
min_samples = round(P.thr_dur * P.fs);

% Build epoch boundary matrix [start_sample, end_sample]:
%   Row 1 : Full session
%   Row 2 : Baseline
%   Row 3+: Experimental events (if provided)
if ~isempty(P.events_sec)
    P.events_idx       = round(P.events_sec * P.fs);
    P.events_idx(:, 1) = P.events_idx(:, 1) + 1;   % convert to 1-based onset
    epoch_bounds = [1, n_samples;                    ...
                    1, round(P.baseline_dur * P.fs); ...
                    P.events_idx];
else
    epoch_bounds = [1, n_samples;                    ...
                    1, round(P.baseline_dur * P.fs)];
end

n_epochs = size(epoch_bounds, 1);


%% 3. Global Freeze Detection (per subject)

% Build a binary freeze mask for the entire session (M-by-S logical matrix).
% Samples at or below thr_low are classified as frozen.
freeze_mask_global = raw_signal <= P.thr_low;

% Detect all freeze bouts globally for each subject.
% Results are stored in a cell array so each subject can have a different
% number of bouts. detect_bouts returns a 3-by-B matrix per subject.
all_freezing_bouts = cell(1, num_subjects);
for s = 1:num_subjects
    all_freezing_bouts{s} = detect_bouts(freeze_mask_global(:, s)', min_samples, P.fs);
end


%% 4. Output Pre-allocation

% behavior_freezing column layout:
%   1 = raw bout durations  (cell per subject)
%   2 = mean bout duration  (vector, seconds)
%   3 = number of bouts     (vector, count)
%   4 = total freeze time   (vector, seconds)
%   5 = freeze percentage   (vector, %)
%   6 = mean Delta T        (vector, seconds; NaN if fewer than 2 bouts)
%   7 = raw Delta T         (cell per subject, seconds)
data.behavior_freezing    = cell(n_epochs, 7);
data.behavior_nonfreezing = cell(n_epochs, 1);
data.events_behavior_idx  = cell(n_epochs, 1);
data.behavior_epochs      = cell(n_epochs, 1);


%%  5. Per-Epoch Processing Loop

for i = 1:n_epochs

    % Epoch boundaries and duration
    start_sample = epoch_bounds(i, 1);
    end_sample   = epoch_bounds(i, 2);

    % Validate epoch bounds against actual data length
    if end_sample > n_samples || start_sample > n_samples
        error('Behavior_Analyse:EpochOutOfBounds', ...
              'Epoch %d [%d, %d] exceeds data length (%d samples).', ...
              i, start_sample, end_sample, n_samples);
    end

    epoch_len_s = (end_sample - start_sample + 1) / P.fs;

    % Store the normalised signal segment for all subjects (S-by-M)
    data.behavior_epochs{i, 1} = raw_signal(start_sample:end_sample, :)';

    % Per-subject accumulators
    % Initialise result containers for this epoch (one entry per subject)
    bf_raw_dur  = cell(num_subjects, 1);    % raw bout durations (s)
    bf_mean     = zeros(num_subjects, 1);   % mean bout duration (s)
    bf_num      = zeros(num_subjects, 1);   % number of bouts
    bf_tot      = zeros(num_subjects, 1);   % total freeze time (s)
    bf_freeze   = zeros(num_subjects, 1);   % freeze percentage (%)
    bf_mean_dt  = zeros(num_subjects, 1);   % mean inter-bout Delta T (s)
    bf_raw_dt   = cell(num_subjects, 1);    % raw inter-bout Delta T (s)

    bnf_dur = cell(num_subjects, 1);        % non-freeze durations (s)
    ev_idx  = cell(num_subjects, 3);        % index pairs and binary mask

    % Inner loop: process each subject
    for s = 1:num_subjects

        subj_f_bouts   = all_freezing_bouts{s};
        f_pairs_for_nf = zeros(0, 2);       % default: no freeze pairs

        if ~isempty(subj_f_bouts) && epoch_len_s > 0

            % Compute global end sample for each bout (onset + duration - 1)
            all_bout_ends = subj_f_bouts(1,:) + subj_f_bouts(2,:) - 1;

            % Find bouts that overlap with this epoch
            overlap_idx = (subj_f_bouts(1,:) <= end_sample) & (all_bout_ends >= start_sample);
            raw_f_bouts = subj_f_bouts(:, overlap_idx);
            raw_f_ends  = all_bout_ends(overlap_idx);

            if ~isempty(raw_f_bouts)

                % Clip bout boundaries to the current epoch
                act_starts_clip = max(raw_f_bouts(1,:), start_sample);
                act_ends_clip   = min(raw_f_ends, end_sample);
                dur_smp_clip    = act_ends_clip - act_starts_clip + 1;

                % Discard clipped fragments shorter than the minimum duration
                valid_clip = dur_smp_clip >= min_samples;

                if any(valid_clip)

                    % Unclipped onset/offset for valid bouts
                    starts_orig_valid = raw_f_bouts(1, valid_clip);
                    ends_orig_valid   = raw_f_ends(valid_clip);

                    % events_behavior_idx{s,1}: only bouts that STARTED in this epoch.
                    % Inherited bouts are excluded to avoid cross-epoch double-counting.
                    is_new_bout  = starts_orig_valid >= start_sample;
                    ev_idx{s, 1} = [starts_orig_valid(is_new_bout)', ...
                                    ends_orig_valid(is_new_bout)'  ];

                    % Clipped data for ALL valid bouts (new + inherited).
                    % Used for statistics and non-freeze gap computation.
                    starts_clip_valid = act_starts_clip(valid_clip);
                    dur_clip_valid    = dur_smp_clip(valid_clip);

                    % Freeze statistics
                    bf_raw_dur{s} = dur_clip_valid / P.fs;
                    bf_mean(s)    = mean(bf_raw_dur{s});
                    bf_num(s)     = length(dur_clip_valid);
                    bf_tot(s)     = sum(dur_clip_valid) / P.fs;

                    % Delta T: time between the end of one bout and the start of the next.
                    % Requires at least 2 bouts; set to NaN otherwise.
                    if length(starts_clip_valid) > 1
                        dt_smp        = starts_clip_valid(2:end) - ...
                                        (starts_clip_valid(1:end-1) + dur_clip_valid(1:end-1) - 1);
                        bf_raw_dt{s}  = dt_smp / P.fs;
                        bf_mean_dt(s) = mean(bf_raw_dt{s});
                    else
                        bf_raw_dt{s}  = [];
                        bf_mean_dt(s) = NaN;
                    end

                    % Clipped freeze pairs for non-freeze gap computation
                    f_pairs_for_nf = [starts_clip_valid', ...
                                     (starts_clip_valid + dur_clip_valid - 1)'];

                else
                    % All clipped fragments too short — treat as no freezing
                    ev_idx{s, 1}  = zeros(0, 2);
                    bf_raw_dt{s}  = [];
                    bf_mean_dt(s) = NaN;
                end

            else
                % No globally detected bouts overlap this epoch
                ev_idx{s, 1}  = zeros(0, 2);
                bf_raw_dt{s}  = [];
                bf_mean_dt(s) = NaN;
            end

        else
            % Subject has no bouts, or epoch has zero duration
            ev_idx{s, 1}  = zeros(0, 2);
            bf_raw_dt{s}  = [];
            bf_mean_dt(s) = NaN;
        end

        % Binary freeze mask for this epoch and subject (local indices)
        ev_idx{s, 3} = freeze_mask_global(start_sample:end_sample, s)';

        % Freeze percentage (guard against zero-length epochs)
        if epoch_len_s > 0
            bf_freeze(s) = (bf_tot(s) / epoch_len_s) * 100;
        end

        % Non-freeze index pairs (global indices, based on all clipped freeze fragments)
        ev_idx{s, 2} = get_nf_pairs(f_pairs_for_nf, start_sample, end_sample, min_samples);

        % Non-freeze bout durations (seconds)
        if ~isempty(ev_idx{s, 2})
            bnf_dur{s} = (ev_idx{s, 2}(:,2) - ev_idx{s, 2}(:,1) + 1)' / P.fs;
        end

    end % end subject loop

    % Store epoch-level results
    data.behavior_freezing{i, 1} = bf_raw_dur;
    data.behavior_freezing{i, 2} = bf_mean;
    data.behavior_freezing{i, 3} = bf_num;
    data.behavior_freezing{i, 4} = bf_tot;
    data.behavior_freezing{i, 5} = bf_freeze;
    data.behavior_freezing{i, 6} = bf_mean_dt;
    data.behavior_freezing{i, 7} = bf_raw_dt;

    data.behavior_nonfreezing{i, 1} = bnf_dur;
    data.events_behavior_idx{i, 1}  = ev_idx;

end


%% 6. Block Analysis (Optional)
%
%  Groups consecutive events that share a common prefix into blocks of
%  size N, then computes per-block aggregates across subjects.
%
%  Example: prefix='CS', size=5 groups CS1-CS5 as Block 1, CS6-CS10 as Block 2.
%
%  Aggregation rules per metric:
%    freeze %   -> mean across events in block
%    bout count -> sum  across events in block (total bouts)
%    duration   -> mean across events (NaN-safe; replaced with 0 if all NaN)
%    Delta T    -> mean across events (NaN-safe; replaced with 0 if all NaN)

data.blocks = [];

if isfield(P, 'block_prefixes') && isfield(P, 'block_sizes') && ~isempty(P.event_names)

    block_idx = 1;   % running index into the data.blocks struct array

    for b_i = 1:length(P.block_prefixes)

        pref = P.block_prefixes{b_i};
        sz   = P.block_sizes(b_i);

        % Skip this entry if the prefix is empty or the block size is invalid
        if isempty(pref) || isnan(sz) || sz <= 0
            continue;
        end

        % Find events whose names start with the target prefix (case-insensitive)
        match_idx   = find(startsWith(P.event_names, pref, 'IgnoreCase', true));
        num_matches = length(match_idx);

        if num_matches == 0
            continue;
        end

        num_blocks = ceil(num_matches / sz);

        % Pre-allocate block result matrices (subjects x blocks)
        block_freeze  = zeros(num_subjects, num_blocks);
        block_bout    = zeros(num_subjects, num_blocks);
        block_dur     = zeros(num_subjects, num_blocks);
        block_delta_t = zeros(num_subjects, num_blocks);
        block_labels  = cell(1, num_blocks);

        for b = 1:num_blocks

            % Slice of matched events belonging to this block
            idx_start    = (b - 1) * sz + 1;
            idx_end      = min(b * sz, num_matches);
            curr_matches = match_idx(idx_start:idx_end);

            % Epoch rows are offset by 2 (Row 1 = Full, Row 2 = Baseline, Row 3+ = Events)
            curr_epochs = curr_matches + 2;

            % Collect per-epoch statistics for all subjects in this block
            temp_freeze  = zeros(num_subjects, length(curr_epochs));
            temp_bout    = zeros(num_subjects, length(curr_epochs));
            temp_dur     = zeros(num_subjects, length(curr_epochs));
            temp_delta_t = zeros(num_subjects, length(curr_epochs));

            for k = 1:length(curr_epochs)
                temp_freeze(:,  k) = data.behavior_freezing{curr_epochs(k), 5};
                temp_bout(:,   k)  = data.behavior_freezing{curr_epochs(k), 3};
                temp_dur(:,    k)  = data.behavior_freezing{curr_epochs(k), 2};
                temp_delta_t(:, k) = data.behavior_freezing{curr_epochs(k), 6};
            end

            % Aggregate across events within the block
            block_freeze(:, b) = mean(temp_freeze, 2);
            block_bout(:, b)   = sum(temp_bout,   2);

            dur_tmp = mean(temp_dur,     2, 'omitnan');
            dt_tmp  = mean(temp_delta_t, 2, 'omitnan');
            dur_tmp(isnan(dur_tmp)) = 0;
            dt_tmp(isnan(dt_tmp))   = 0;
            block_dur(:,     b) = dur_tmp;
            block_delta_t(:,  b) = dt_tmp;

            % Label: '<Prefix> <first>-<last>'  e.g. 'CS 1-5'
            block_labels{b} = sprintf('%s %d-%d', pref, idx_start, idx_end);

        end % end block loop

        % Append this block definition to the struct array
        data.blocks(block_idx).freeze   = block_freeze;
        data.blocks(block_idx).bout     = block_bout;
        data.blocks(block_idx).dur      = block_dur;
        data.blocks(block_idx).delta_t  = block_delta_t;
        data.blocks(block_idx).labels   = block_labels;
        data.blocks(block_idx).prefix   = pref;
        data.blocks(block_idx).size     = sz;

        block_idx = block_idx + 1;

    end % end block definition loop

end % end block analysis


parameters = P;

end

%% Helper function: get_nf_pairs

function nf = get_nf_pairs(f_pairs, ep_start, ep_end, min_dur)

% get_nf_pairs  Build non-freeze [start, end] pairs within an epoch.

% Produces global-index pairs for three types of non-freeze intervals:
%   1. Segment from epoch start to the first freeze onset
%   2. Gaps between consecutive freeze bouts
%   3. Segment from the last freeze offset to epoch end

% Inputs:
%   f_pairs  - B-by-2 matrix of freeze [start, end] pairs (global indices).
%              Should include ALL clipped fragments (including inherited bouts)
%              so that gaps at epoch boundaries are temporally accurate.
%   ep_start - Global index of the first sample in this epoch.
%   ep_end   - Global index of the last sample in this epoch.
%   min_dur  - Minimum segment length in samples; shorter segments are discarded.

% Output:
%   nf       - K-by-2 matrix of non-freeze [start, end] pairs (global indices).

% Special case: no freezing — entire epoch is one non-freeze segment
if isempty(f_pairs)
    if (ep_end - ep_start + 1) >= min_dur
        nf = [ep_start, ep_end];
    else
        nf = zeros(0, 2);
    end
    return;
end

% Sort by onset to guarantee chronological order
f_pairs = sortrows(f_pairs, 1);

% Build candidate non-freeze intervals from the spaces around freeze bouts:
%   nf_s(1)    = epoch start
%   nf_s(2:B)  = each freeze offset + 1  (gap after each bout)
%   nf_e(1:B)  = each freeze onset - 1   (gap before each bout)
%   nf_e(end)  = epoch end
nf_s = [ep_start;       f_pairs(:,2) + 1];
nf_e = [f_pairs(:,1)-1; ep_end          ];

nf_raw = [nf_s, nf_e];

% Clip to epoch boundaries (guards against inherited bouts at epoch edges)
nf_raw(:,1) = max(nf_raw(:,1), ep_start);
nf_raw(:,2) = min(nf_raw(:,2), ep_end);

% Retain only segments meeting the minimum duration (end - start + 1 >= min_dur)
valid = (nf_raw(:,2) - nf_raw(:,1) + 1) >= min_dur;
nf    = nf_raw(valid, :);

end