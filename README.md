# Freezing Behavior Analysis Pipeline

A MATLAB pipeline for automated detection and quantification of freezing behavior from raw movement signals (threshold voltages from load cells and/or video-based threshold analysis, e.g., MED-PC boxes and/or VideoFreeze systems). Supports multi-subject batch processing, block-averaged analyses, and interactive visualization through a graphical interface.

---

## Overview

This pipeline processes raw movement signals recorded during fear conditioning or related behavioral paradigms. Each session is segmented into user-defined epochs (baseline, CS, ITI, or any custom event), and freezing bouts are detected within each epoch using a threshold-and-duration criterion. All detection is performed globally on the full session first and then mapped to individual epochs, ensuring that bout identities are consistent across the entire recording.

The pipeline runs either interactively through a GUI (`App_Behavior`) or programmatically through a batch wrapper (`Batch_Behavior_Analyse`), making it suitable for both exploratory use and automated processing of large datasets.

`BehaviorSync` is a companion standalone GUI for video-synchronized event annotation. It can be launched from within `App_Behavior` main menu or independently.

---

## Repository Structure

```
.
├── App_Behavior.m              GUI control center for the full pipeline
├── BehaviorSync.m              Standalone video/neural synchronization GUI for event annotation
├── Batch_Behavior_Analyse.m    Batch wrapper: loads files, runs analysis, exports Excel
├── Behavior_Analyse.m          Core analysis function (multi-subject, block analysis)
├── detect_bouts.m              Low-level bout detection from a binary signal
└── Plot_Behavior_Batch.m       Figure generation and export
```

---

## Dependencies

All functions are self-contained MATLAB scripts with no external toolboxes required. The only inter-file dependency is `detect_bouts.m`, which must be on the MATLAB path or in the same folder as `Behavior_Analyse.m`.

Tested on MATLAB R2021a and later. The `writecell` and `exportgraphics` functions used in export routines require R2020a or later. `BehaviorSync` requires MATLAB R2017b or later (`VideoReader`, `xline`, `uicontrol`).

---

## Quick Start

### Interactive Mode (GUI)

```matlab
App_Behavior()
```

1. Use **File > Load Data Files** to select one or more raw movement files (`.out`, `.txt`, or `.csv`).
2. *(Optional)* Use **Tools > Open BehaviorSync** to load the corresponding video alongside neural or behavioral recordings, navigate frame by frame, and visually annotate event onsets and offsets. Export the result as `<file>_events.csv` and load it directly into the Events table in step 3.
3. Load or manually fill the Events table (columns: Name, Onset in seconds, Offset in seconds).
4. Set basic parameters (sampling rate, freeze threshold, minimum duration, baseline duration) and up to five block grouping definitions.
5. Click **RUN ANALYSIS**.
6. Use **File > Export Results** or the **Plot Viewer** panel to inspect and export results.

### Batch Mode (Command Line)

```matlab
data_results = Batch_Behavior_Analyse();
```

A series of dialogs will guide file selection and parameter entry. Results are saved as Excel files alongside the input data.

### Standalone Analysis

```matlab
[data, parameters] = Behavior_Analyse(raw_signal);
```

A dialog is shown for parameter entry. For automated pipelines, pass a pre-built parameter struct as the second argument to skip the dialog.

### BehaviorSync (Standalone)

```matlab
BehaviorSync()
```

Launches the video synchronization and event annotation GUI independently, with no dependency on `App_Behavior` or any other pipeline function. See the [BehaviorSync](#behaviorsync) section for full details.

---

## Input Format

### Raw Data Files

Each data file should be a numeric matrix where:

- **Column 1** is the timestamp (automatically removed by the batch and GUI wrappers).
- **Remaining columns** are movement signals, one column per subject.

Accepted formats: `.out`, `.txt`, `.csv`. Files are loaded with `readmatrix(..., 'FileType', 'text')`.

### Events File

A plain-text or CSV file with exactly three columns and no header row:

```
EventName   Onset_s   Offset_s
CS1         180       190
ITI1        190       220
CS2         220       230
```

---

## Parameters

| Parameter | Description | Default |
|---|---|---|
| Sampling rate (Hz) | Samples per second of the input signal | 1000 |
| Freeze threshold (%) | Samples at or below this normalised movement value are classified as frozen | 5 |
| Min freeze duration (s) | Bouts shorter than this after epoch clipping are discarded | 1 |
| Baseline duration (s) | Duration of the pre-event period (Row 2 in all outputs) | 180 |
| Block prefix | String prefix used to identify events belonging to a block (e.g., `CS`) | — |
| Block size | Number of consecutive matching events to average into one block | — |

The signal is normalised independently per subject to 0–100% of its own maximum movement before any threshold is applied, making the freeze threshold comparable across animals and sessions.

---

## Output Structure

All results are returned in the `data` struct. Cell array rows follow a consistent indexing convention:

- **Row 1** — Full session (entire recording)
- **Row 2** — Baseline (samples 1 to `baseline_dur * fs`)
- **Rows 3 to N** — Experimental events (one row per event defined in the events table)

### data.behavior_freezing (N rows × 7 columns)

| Column | Content | Type |
|---|---|---|
| 1 | Raw bout durations | S-by-1 cell; each entry is a 1-by-B vector (seconds) |
| 2 | Mean bout duration | S-by-1 vector (seconds) |
| 3 | Number of bouts | S-by-1 vector (count) |
| 4 | Total freeze time | S-by-1 vector (seconds) |
| 5 | Freeze percentage | S-by-1 vector (%) |
| 6 | Mean inter-bout interval (ΔT) | S-by-1 vector (seconds); NaN if fewer than 2 bouts |
| 7 | Raw inter-bout interval (ΔT) | S-by-1 cell; each entry is a 1-by-(B-1) vector (seconds) |

S = number of subjects, B = number of valid bouts in the epoch.

### data.behavior_nonfreezing (N rows × 1 column)

Each cell contains an S-by-1 cell array where each entry is a vector of non-freeze bout durations in seconds for one subject.

### data.events_behavior_idx (N rows × 1 column)

Each cell contains an S-by-3 cell array:

- Column 1 — Freeze index pairs: B-by-2 matrix `[start, end]` in global sample indices. Contains only bouts that started within this epoch.
- Column 2 — Non-freeze index pairs: B-by-2 matrix `[start, end]` in global sample indices.
- Column 3 — Binary freeze mask: 1-by-M logical vector for this epoch (1 = frozen, 0 = moving).

Global indices are directly usable to slice any co-recorded signal of the same length (LFP, pupil, etc.).

### data.behavior_epochs (N rows × 1 column)

Each cell contains an S-by-M matrix of the normalised movement signal for the corresponding epoch. Useful for epoch-level visualisation and sanity checks.

### data.blocks (Struct Array)

One element per active block definition. Fields:

| Field | Content |
|---|---|
| prefix | Matched event prefix string |
| size | Block size (number of events per block) |
| labels | 1-by-B cell of label strings (e.g., `CS 1-5`) |
| freeze | S-by-B matrix of mean freeze percentage per block |
| bout | S-by-B matrix of summed bout count per block |
| dur | S-by-B matrix of mean bout duration per block |
| delta_t | S-by-B matrix of mean inter-bout ΔT per block |

---

## Excel Export

Running the export (either via the GUI menu or automatically in batch mode) produces one workbook per input file, saved in the same folder as the source data.

### Standard Sheets

| Sheet | Content |
|---|---|
| 1_Freezing_Percentage | Freeze % per epoch per subject |
| 2_Total_Bouts | Number of freeze bouts per epoch per subject |
| 3_Mean_Bout_Duration(s) | Mean bout duration per epoch per subject |
| 4_Bout_Duration(s) | All individual bout durations (comma-separated) |
| 5_Mean_Bout_DeltaT(s) | Mean inter-bout ΔT per epoch per subject |
| 6_Bout_DeltaT(s) | All individual ΔT values (comma-separated) |

### Block Sheets

One set of three sheets per active block definition, named using the format `Blk<N>_<Prefix>_<Metric>` (e.g., `Blk1_CS_Freezing_Percentage`). Sheet names are kept short to comply with Excel's 31-character limit.

### Timestamp Export

A separate workbook (`<file>_Timestamps.xlsx`) contains the raw onset and offset sample indices for every freeze and non-freeze bout across all subjects. Each subject occupies two columns (Onset and Offset). This file is suitable for cross-referencing with other simultaneously recorded signals.

---

## Figures

Calling `Plot_Behavior_Batch(data_results)` or using the GUI's Plot Viewer generates one figure per file. Figure height scales automatically with the number of active block analyses.

- **Row 1** — Full-session smoothed movement traces (individual subjects in grey, group median in black), freeze threshold reference line, and per-subject freeze raster above the movement axis.
- **Row 2** — Event-by-event freeze percentage (individual subjects + mean ± SEM) and two summary pie charts (total bout count and mean bout duration across all epochs).
- **Rows 3 and beyond** — One row per block analysis: block-averaged freeze percentage line plot and two pie charts summarising bouts and duration by block.

Figures are exported as 300 dpi PNG files to the current working directory.

---

## Freeze Detection Logic

Detection follows a two-step approach designed to ensure consistency across epochs:

1. A binary freeze mask is computed for the full session by thresholding the normalised signal at `thr_low`. `detect_bouts` then finds all contiguous runs of frozen samples that meet the minimum duration criterion.
2. During per-epoch processing, each globally detected bout is intersected with the epoch boundaries. Bouts that straddle a boundary are clipped to the epoch. Clipped fragments shorter than the minimum duration are discarded. Statistics (total freeze time, percentage) use clipped durations from all valid bouts, including those that started in a previous epoch, so that freeze time is never under-reported at epoch boundaries. However, `events_behavior_idx` records only bouts that started within the epoch, preventing double-counting across epochs.

---

## Block Analysis

Block analysis groups consecutive events that share a common name prefix (e.g., all events starting with `CS`) into windows of a fixed size and computes aggregate statistics per window. Up to five independent block definitions can be active simultaneously.

Aggregation rules:

- Freeze percentage — mean across events in the block
- Bout count — sum across events (total bouts in the block)
- Mean bout duration — mean across events (NaN values from epochs with no freezing are excluded; result is set to 0 if all values are NaN)
- Mean ΔT — same NaN-safe mean as duration

Block labels follow the format `<Prefix> <first>-<last>` (e.g., `CS 1-5`, `CS 6-10`).

---

## BehaviorSync

BehaviorSync is a **standalone** companion GUI for synchronized visualization and annotation of behavioral events directly from video, alongside simultaneously recorded neural or behavioral signals (e.g., LFP, EMG, load cell output).

It can be launched independently from the command line or from within `App_Behavior` via **Tools > Open BehaviorSync**:

```matlab
BehaviorSync()
```

### Features

**Video playback**
- Load and play video files (`.mp4`, `.avi`, `.wmv`, `.mov`).
- Adjustable playback speed: 0.25×, 0.5×, 1×, 2×, 4×, 10×, 20×.
- Frame-by-frame navigation via arrow keys or the timeline slider.

**Signal visualization**
- Load neural and behavioral recordings independently (`.csv` or `.txt`; the last column is used as the signal, making the function robust to non-numeric leading columns).
- Time vectors are built automatically from sample count and user-supplied Fs — input files do **not** require a time column.
- Scrolling time-window view on both signal axes, synchronized with video playback.
- Adjustable time window width and independent Y-axis scaling for each signal.
- Red cursor line tracks video time in real time on both signal axes.

**Event annotation**
- Mark Onset and Offset events frame by frame via buttons or keyboard shortcuts.
- Smart toggle key [M]: marks Onset if pairs are balanced, Offset otherwise.
- Live listboxes showing all marked onsets, offsets, and computed durations.
- Delete last marked event at any time with [Del].
- Export annotated events to CSV — fully compatible with the Events table in `App_Behavior`.

**Epoch-based analysis**
- Define analysis epochs manually in the built-in table (Label | Onset | Offset) or load them from a 3-column `.csv` / `.txt` file.
- Epoch boundaries are drawn as dashed blue lines on both signal axes for visual reference.
- A "Full Session" epoch is always included automatically.
- Epochs can be named freely to match the experimental design — typical examples include `Baseline`, `CS1`, `ITI1`, `CS2`, or any custom label. Each named epoch is analyzed independently, so trial-by-trial metrics (e.g., freezing on CS1 vs CS2, or across ITI periods) are directly available in the output without any post-processing.
- Run Analysis computes the following metrics per epoch, using the manually marked bouts:

| Metric | Description |
|---|---|
| Freezing Percentage | Total time in behavioral bouts / epoch duration (%) |
| Total Bouts | Number of discrete behavioral episodes |
| Mean Bout Duration | Average duration of individual bouts (s) |
| Bout Duration (raw) | All individual bout durations (s) |
| Mean Inter-Bout Interval (ΔT) | Average gap between consecutive bouts (s) |
| Inter-Bout Interval (raw) | All individual inter-bout intervals (s) |

### Output Files

| Format | Content | How to export |
|---|---|---|
| `.csv` | Annotated event timestamps (frame + time, onset/offset/duration) with metadata header | File > Export Behavior Timestamps |
| `.xlsx` | One sheet per metric, rows = epochs, one column per subject | File > Export Results |
| `.mat` | Struct `Data_results` with all computed metrics | File > Save Results |

**CSV format:**
```
# BehaviorSync export | Video: 30.0000 fps | Neural Fs: 1000 Hz | Behavior Fs: 5 Hz
Frame (sample) onset, Frame (sample) offset, Onset (seconds), Offset (seconds), Duration (seconds)
```

### Keyboard Shortcuts

| Key | Action |
|---|---|
| Space | Play / Pause |
| I | Mark Onset |
| O | Mark Offset |
| M | Smart toggle (Onset if balanced, Offset otherwise) |
| ← / → | Step one frame backward / forward |
| Del | Delete last marked event |

### Known Limitations

> Synchronization between signals with different recording start times is not yet supported. A Time Offset field per signal is planned for a future version.

---

## Author

Flavio Mourao (mourao.fg@gmail.com)

Maren Lab, Department of Psychological and Brain Sciences, Texas A&M University  
Beckman Institute, University of Illinois Urbana-Champaign  
Federal University of Minas Gerais, Brazil

Development started: December 2023  
Last update: March 2026
