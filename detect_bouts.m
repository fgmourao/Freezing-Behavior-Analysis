function bouts = detect_bouts(binary_signal, min_dur_samples, sample_rate)
%% Detect Bouts
%
% DESCRIPTION 
%   Finds all contiguous runs of ones (active bouts) in a binary signal
%   and returns those that meet or exceed a minimum duration threshold.
%
%   Edge detection is performed via diff() on a zero-padded copy of the
%   signal, so bouts that begin at sample 1 or end at the last sample
%   are correctly captured without special-case handling.
%
% USAGE 
%   bouts = detect_bouts(binary_signal, min_dur_samples, sample_rate)
%
% INPUT 
%   binary_signal    - 1-by-N or N-by-1 logical or numeric vector (0s and 1s).
%                      Any orientation is accepted (transposed internally).
%   min_dur_samples  - Minimum bout length in samples.
%                      Bouts shorter than this are discarded.
%   sample_rate      - Sampling rate in Hz.
%                      Used only to convert bout duration to seconds (row 3).
%
% OUTPUT
%   bouts  - 3-by-B matrix, where B is the number of qualifying bouts.
%              Row 1 : onset index    (samples, 1-based)
%              Row 2 : duration       (samples)
%              Row 3 : duration       (seconds)
%            Returns zeros(3, 0) if no qualifying bouts are found.
%
% EXAMPLE
%   signal = [0 0 1 1 1 0 1 0 0 1 1 1 1 0];
%   bouts  = detect_bouts(signal, 3, 1);
%
%   % Two bouts meet the 3-sample minimum:
%   %   Bout 1: onset=3,  duration=3 samples, 3.0 s
%   %   Bout 2: onset=10, duration=4 samples, 4.0 s
%   %
%   %   bouts =
%   %     3   10        <- row 1: onset (samples)
%   %     3    4        <- row 2: duration (samples)
%   %     3.0  4.0      <- row 3: duration (seconds)
%
% AUTHOR
%   Flavio Mourao (mourao.fg@gmail.com)
%   Texas A&M University - Department of Psychological and Brain Sciences
%   University of Illinois Urbana-Champaign - Beckman Institute
%   Federal University of Minas Gerais - Brazil
%
% Started:     12/2023
% Last update: 02/2026

%% 1. Input Guard

% Return empty result immediately if signal is empty or contains no active samples
if isempty(binary_signal) || ~any(binary_signal(:))
    bouts = zeros(3, 0);
    return
end

% Force logical row vector for consistent edge detection below
sig = (binary_signal(:).' > 0);


%% 2. Edge Detection

% Pad with false on both sides so that bouts starting at index 1
% or ending at the last sample are detected as proper rising/falling edges.
edges = diff([false, sig, false]);

% Rising edge  (+1): sample where the signal transitions 0 -> 1 (bout onset)
% Falling edge (-1): sample AFTER the last 1, so subtract 1 to get bout end
starts    = find(edges ==  1);
ends      = find(edges == -1) - 1;
durations = ends - starts + 1;


%%  3. Minimum Duration Filter

keep = durations >= min_dur_samples;

if ~any(keep)
    bouts = zeros(3, 0);
    return
end

s = starts(keep);
d = durations(keep);

% Assemble output: onset (samples) | duration (samples) | duration (seconds)
bouts = [s; d; d ./ sample_rate];

end