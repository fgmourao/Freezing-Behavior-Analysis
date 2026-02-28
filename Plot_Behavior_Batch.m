function Plot_Behavior_Batch(data_results)
%% Plot_Behavior_Batch
%
% DESCRIPTION
%   Generates and saves one summary figure per processed file.
%   The figure layout scales dynamically with the number of block analyses:
%     Row 1         - Full-session movement trace (median + individual) and freeze raster
%     Row 2         - Event-by-event freeze % line plot + three pie charts (bouts / duration / delta T)
%     Rows 3..N     - One row per block analysis (line plot + three pie charts)
%
% USAGE
%   Plot_Behavior_Batch(data_results)
%
% INPUT
%   data_results - Struct returned by Batch_Behavior_Analyse.
%                  Must contain a 'parameters' field and one field per file.
%
% OUTPUT
%   One PNG file per subject file, saved in the current working directory.
%   Filename format: '<field_name>_Plot.png'  (300 dpi)
%
% FIGURE LAYOUT
%   Each row uses a 5-column subplot grid:
%     Row 1         : cols 1-5  (full-width trace + raster)
%     Row 2         : cols 1-2  (line plot), col 3 (pie bouts), col 4 (pie duration), col 5 (pie delta T)
%     Row 3+ (blocks): same 5-column pattern as Row 2
%
% REQUIRES
%   data_results must include data.behavior_freezing, data.behavior_epochs,
%   data.events_behavior_idx, and optionally data.blocks.
%
% AUTHOR
%   Flavio Mourao (mourao.fg@gmail.com)
%   Texas A&M University - Department of Psychological and Brain Sciences
%   University of Illinois Urbana-Champaign - Beckman Institute
%   Federal University of Minas Gerais - Brazil
%
% Started:     12/2023
% Last update: 02/2026

%%  1. Validate Input and Extract Shared Parameters
if isfield(data_results, 'parameters')
    P = data_results.parameters;
else
    error('Plot_Behavior_Batch:MissingParameters', ...
          'Parameters field not found in data_results.');
end

% Get file field names, excluding the shared 'parameters' field
file_names = fieldnames(data_results);
file_names(strcmp(file_names, 'parameters')) = [];

%% 2. Per-File Plotting Loop
for f = 1:length(file_names)
    curr_file = file_names{f};
    data      = data_results.(curr_file);
    fprintf('Plotting and saving %s...\n', curr_file);

    % Shared signal data
    % Row 1 of behavior_epochs contains the full-session signal (S-by-M)
    raw_matrix   = data.behavior_epochs{1, 1};
    [num_subjects, n_samples] = size(raw_matrix);

    % Time vector (seconds)
    t = (0:n_samples - 1) / P.fs;

    % Smooth each subject's trace with a 1-second moving average window
    smooth_win      = round(P.fs);
    smoothed_matrix = movmean(raw_matrix, smooth_win, 2);
    median_trace    = median(smoothed_matrix, 1);

    % Event onset/offset times for shaded regions
    ev_on_s  = P.events_sec(:, 1);
    ev_off_s = P.events_sec(:, 2);

    % Dynamic figure height
    % Base layout has 2 rows; each block analysis adds one additional row.
    % Minimum height is 800 px; each row contributes 350 px.
    if isfield(data, 'blocks') && ~isempty(data.blocks)
        num_block_types = length(data.blocks);
    else
        num_block_types = 0;
    end
    total_rows = 2 + num_block_types;
    fig_height = max(800, total_rows * 350);

    fig = figure('Color', 'w', ...
                 'Position', [100, 50, 1600, fig_height], ...
                 'Visible', 'on');
    
    sgtitle(strrep(curr_file, '_', '\_'), 'FontSize', 16, 'FontWeight', 'bold');

    %% Row 1: Full-Session Movement Trace + Freeze Raster
    %
    %  Top panel spans all 5 subplot columns. It shows:
    %    - Individual smoothed traces (light grey)
    %    - Group median trace (black)
    %    - Freeze threshold line (dashed)
    %    - Shaded event regions
    %    - Per-subject freeze raster above the y=100 line

    ax1 = subplot(total_rows, 5, 1:5);
    hold(ax1, 'on');

    % Raster is drawn above the 0-100% movement axis
    raster_start_y = 110;
    raster_height  = 100;
    raster_step    = raster_height / num_subjects;
    max_y_axis     = raster_start_y + raster_height + 10;

    % Shaded event regions (light red)
    for ii = 1:numel(ev_on_s)
        fill(ax1, ...
             [ev_on_s(ii), ev_off_s(ii), ev_off_s(ii), ev_on_s(ii)], ...
             [0, 0, max_y_axis, max_y_axis], ...
             [1 0.8 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.4);
    end

    % Individual traces (semi-transparent grey)
    plot(ax1, t, smoothed_matrix', 'Color', [0.8 0.8 0.8 0.5], 'LineWidth', 0.5);

    % Group median trace
    plot(ax1, t, median_trace, 'k', 'LineWidth', 2);

    % Freeze threshold reference line
    h_thres = yline(ax1, P.thr_low, 'k--', 'LineWidth', 1.2);

    % Freeze raster: one horizontal tick mark per freeze bout per subject
    for s = 1:num_subjects
        y_val   = raster_start_y + (s * raster_step);
        f_pairs = data.events_behavior_idx{1, 1}{s, 1};   % global freeze index pairs
        
        % Subject label to the right of the raster
        text(ax1, t(end) + 2, y_val, num2str(s), ...
             'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.4 0.4 0.4]);

        if ~isempty(f_pairs)
            plot(ax1, ...
                 [t(f_pairs(:,1)); t(f_pairs(:,2))], ...
                 [y_val * ones(1, size(f_pairs,1)); y_val * ones(1, size(f_pairs,1))], ...
                 '-', 'LineWidth', max(1.5, raster_step * 0.7), 'Color', [0.6 0 0]);
        end
    end

    xlabel(ax1, 'Time (s)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel(ax1, 'Movement (%)  Bouts', 'FontSize', 12, 'FontWeight', 'bold');
    xlim(ax1, [t(1) - 2, t(end) + 15]);
    ylim(ax1, [0, max_y_axis]);
    yticks(ax1, 0:20:100);

    % Custom Legend
    h_subj = plot(nan, nan, 'Color', [0.8 0.8 0.8], 'LineWidth', 1);
    h_med  = plot(nan, nan, 'k', 'LineWidth', 2);
    h_ev   = fill(nan, nan, [1 0.8 0.8], 'FaceAlpha', 0.4);
    h_frez = plot(nan, nan, '-', 'Color', [0.6 0 0], 'LineWidth', 2);
    legend(ax1, [h_subj, h_med, h_ev, h_frez, h_thres], ...
        {'Raw mov.', 'Mov. Median', 'Events', 'Freeze Bouts', 'Freezing Threshold'}, ...
        'NumColumns', 5, 'Location', 'southoutside', 'Box', 'off');

    %% Row 2: Event-by-Event Freeze % + Summary Pie Charts
    %
    %  Left panel (cols 1-2): individual + mean±SEM line plot across all epochs.
    %  Right panels (cols 3-5): pie charts for total bout count, mean duration, and Delta T.
    
    % Line plot: freeze % per epoch
    ax2 = subplot(total_rows, 5, [6 7]);
    hold(ax2, 'on');

    n_epochs   = size(data.behavior_freezing, 1);
    num_events = n_epochs - 1;   % subtract 1 for Full Session (Row 1 is not plotted here)

    % Collect freeze % and build x-axis labels for Baseline + all events
    freeze_matrix = zeros(num_subjects, num_events);
    x_labels   = cell(1, num_events);

    for e = 2:n_epochs
        freeze_matrix(:, e-1) = data.behavior_freezing{e, 5};
        if e == 2
            x_labels{e-1} = 'Baseline';
        else
            x_labels{e-1} = char(P.event_names(e - 2));
        end
    end

    % Individual subject lines (semi-transparent grey)
    h_sub = plot(ax2, 1:num_events, freeze_matrix', ...
                 '-', 'Color', [0.8 0.8 0.8 0.6], 'LineWidth', 1);

    % Group mean ± SEM
    h_med = errorbar(ax2, 1:num_events, ...
                     mean(freeze_matrix, 1), ...
                     std(freeze_matrix, 0, 1) / sqrt(num_subjects), ...
                     '-ko', 'LineWidth', 2, 'MarkerSize', 8, ...
                     'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');

    ylabel(ax2, 'Freezing (%)', 'FontSize', 12, 'FontWeight', 'bold');
    title(ax2, 'Event-by-Event', 'FontSize', 12);
    xticks(ax2, 1:num_events);
    xticklabels(ax2, x_labels);
    xlim(ax2, [0.5, num_events + 0.5]);
    ylim(ax2, [-5, 105]);
    legend(ax2, [h_sub(1), h_med], {'Individual', 'Mean \pm SEM'}, ...
           'Location', 'southoutside', 'Box', 'off');

    % Pie chart: total bout count across all events
    ax3 = subplot(total_rows, 5, 8);
    bouts_sum = zeros(1, num_events);
    for e = 2:n_epochs
        bouts_sum(e-1) = sum(data.behavior_freezing{e, 3});
    end

    if sum(bouts_sum) > 0
        idx   = bouts_sum > 0;
        val   = bouts_sum(idx);
        tmp_l = x_labels(idx);
        lab   = cell(1, sum(idx));
        for k = 1:length(val)
            lab{k} = sprintf('%s (%d)', tmp_l{k}, val(k));
        end
        pie(ax3, val / sum(val), lab);
        title(ax3, 'Total Bouts (All)', 'FontSize', 12, 'FontWeight', 'bold');
        colormap(ax3, pink);
    else
        axis(ax3, 'off');
    end

    % Pie chart: mean bout duration across all events
    ax4 = subplot(total_rows, 5, 9);
    mean_dur_sum = zeros(1, num_events);
    for e = 2:n_epochs
        mean_dur_sum(e-1) = mean(data.behavior_freezing{e, 2}, 'omitnan');
    end
    mean_dur_sum(isnan(mean_dur_sum)) = 0;

    if sum(mean_dur_sum) > 0
        idx   = mean_dur_sum > 0;
        val   = mean_dur_sum(idx);
        tmp_l = x_labels(idx);
        lab   = cell(1, sum(idx));
        for k = 1:length(val)
            lab{k} = sprintf('%s (%.1fs)', tmp_l{k}, val(k));
        end
        pie(ax4, val / sum(val), lab);
        title(ax4, 'Bouts Mean Dur. (All)', 'FontSize', 12, 'FontWeight', 'bold');
        colormap(ax4, pink);
    else
        axis(ax4, 'off');
    end

    % Pie chart: mean Delta T across all events
    ax5 = subplot(total_rows, 5, 10);
    mean_dt_sum = zeros(1, num_events);
    for e = 2:n_epochs
        mean_dt_sum(e-1) = mean(data.behavior_freezing{e, 6}, 'omitnan');
    end
    mean_dt_sum(isnan(mean_dt_sum)) = 0;

    if sum(mean_dt_sum) > 0
        idx   = mean_dt_sum > 0;
        val   = mean_dt_sum(idx);
        tmp_l = x_labels(idx);
        lab   = cell(1, sum(idx));
        for k = 1:length(val)
            lab{k} = sprintf('%s (%.1fs)', tmp_l{k}, val(k));
        end
        pie(ax5, val / sum(val), lab);
        title(ax5, 'Bouts Mean Delta T (All)', 'FontSize', 12, 'FontWeight', 'bold');
        colormap(ax5, pink);
    else
        axis(ax5, 'off');
    end

    %% Rows 3+: Dynamic Block Analysis Rows
    %
    %  One row is added per active block definition (up to 3).
    %  Each row follows the same 5-column pattern as Row 2:
    %    Cols 1-2 : mean±SEM freeze % per block
    %    Col  3   : pie chart of total bouts per block
    %    Col  4   : pie chart of mean duration per block
    %    Col  5   : pie chart of mean Delta T per block
    %
    %  Subplot index formula:
    %    Row r starts at subplot index (r-1)*5 + 1.
    %    For block b_i, r = 2 + b_i  →  start_idx = (1 + b_i) * 5 + 1

    if num_block_types > 0
        for b_i = 1:num_block_types
            curr_b = data.blocks(b_i);
            num_b  = length(curr_b.labels);

            % Row index for this block (rows 3, 4, or 5)
            r = 2 + b_i;

            % First subplot index in this row within the total_rows x 5 grid
            start_idx = (r - 1) * 5 + 1;

            % Line plot: block freeze
            ax_L = subplot(total_rows, 5, [start_idx, start_idx + 1]);
            hold(ax_L, 'on');

            % Individual subject lines (semi-transparent grey)
            plot(ax_L, 1:num_b, curr_b.freeze', ...
                 '-', 'Color', [0.8 0.8 0.8 0.6], 'LineWidth', 1);

            % Group mean ± SEM
            errorbar(ax_L, 1:num_b, ...
                     mean(curr_b.freeze, 1), ...
                     std(curr_b.freeze, 0, 1) / sqrt(num_subjects), ...
                     '-ko', 'LineWidth', 2, 'MarkerSize', 8, ...
                     'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'k');

            ylabel(ax_L, 'Freezing (%)', 'FontSize', 12, 'FontWeight', 'bold');
            title(ax_L, sprintf('Block: %s', curr_b.prefix), 'FontSize', 12);
            xticks(ax_L, 1:num_b);
            xticklabels(ax_L, curr_b.labels);
            xtickangle(ax_L, 20);
            xlim(ax_L, [0.5, num_b + 0.5]);
            ylim(ax_L, [-5, 105]);

            % Pie chart: total bouts per block
            ax_P1 = subplot(total_rows, 5, start_idx + 2);
            b_sum = sum(curr_b.bout, 1);   % sum across subjects for each block

            if sum(b_sum) > 0
                idx   = b_sum > 0;
                val   = b_sum(idx);
                tmp_l = curr_b.labels(idx);
                lab   = cell(1, sum(idx));
                for k = 1:length(val)
                    lab{k} = sprintf('%s (%d)', tmp_l{k}, val(k));
                end
                pie(ax_P1, val / sum(val), lab);
                title(ax_P1, sprintf('Total Bouts (%s)', curr_b.prefix), ...
                      'FontSize', 12, 'FontWeight', 'bold');
                colormap(ax_P1, pink);
            else
                axis(ax_P1, 'off');
            end

            % Pie chart: mean duration per block
            ax_P2 = subplot(total_rows, 5, start_idx + 3);
            d_mean = mean(curr_b.dur, 1, 'omitnan');
            d_mean(isnan(d_mean)) = 0;

            if sum(d_mean) > 0
                idx   = d_mean > 0;
                val   = d_mean(idx);
                tmp_l = curr_b.labels(idx);
                lab   = cell(1, sum(idx));
                for k = 1:length(val)
                    lab{k} = sprintf('%s (%.1fs)', tmp_l{k}, val(k));
                end
                pie(ax_P2, val / sum(val), lab);
                title(ax_P2, sprintf('Bouts Mean Dur. (%s)', curr_b.prefix), ...
                      'FontSize', 12, 'FontWeight', 'bold');
                colormap(ax_P2, pink);
            else
                axis(ax_P2, 'off');
            end
            
            % Pie chart: mean Delta T per block
            ax_P3 = subplot(total_rows, 5, start_idx + 4);
            dt_mean = mean(curr_b.delta_t, 1, 'omitnan');
            dt_mean(isnan(dt_mean)) = 0;

            if sum(dt_mean) > 0
                idx   = dt_mean > 0;
                val   = dt_mean(idx);
                tmp_l = curr_b.labels(idx);
                lab   = cell(1, sum(idx));
                for k = 1:length(val)
                    lab{k} = sprintf('%s (%.1fs)', tmp_l{k}, val(k));
                end
                pie(ax_P3, val / sum(val), lab);
                title(ax_P3, sprintf('Bouts Mean Delta T (%s)', curr_b.prefix), ...
                      'FontSize', 12, 'FontWeight', 'bold');
                colormap(ax_P3, pink);
            else
                axis(ax_P3, 'off');
            end
            
        end
    end

    %% Export Figure
    desktop_path = fullfile(char(java.lang.System.getProperty('user.home')), 'Desktop');
    file_name = sprintf('%s_Plot.png', curr_file);
    out_filename = fullfile(desktop_path, file_name);
    exportgraphics(fig, out_filename, 'Resolution', 300);

end

fprintf('All plots successfully generated and saved!\n');

end