# FaceTrackCAM Codex Instructions

## Goal
This is an iOS camera/webcam application.
The final build is produced by GitHub Actions as an IPA.

## General rules
- Never inspect the entire repository unless required.
- Start by identifying the smallest set of files relevant to the task.
- Do not read unrelated files.
- Do not inspect build artifacts or generated files.
- Do not refactor unrelated working code.
- Preserve existing working functionality unless explicitly asked to change it.
- Make the smallest reliable change that solves the task.

## Bug fixing
When fixing a build failure:

1. Read the failed GitHub Actions job.
2. Find the actual compiler/error messages.
3. Ignore successful build output and irrelevant warnings.
4. Identify the files and line numbers involved.
5. Inspect only those files plus directly related code.
6. Make the smallest necessary fix.
7. Run the existing build workflow.
8. If it fails again, inspect only the new errors.
9. Do not repeatedly rebuild without changing code.

## Feature implementation
Before implementing a feature:

1. Locate the existing implementation related to the feature.
2. Identify the smallest files that require modification.
3. Reuse existing architecture and components where possible.
4. Do not redesign unrelated code.
5. Implement the feature.
6. Check for obvious compile errors.
7. Run the existing GitHub Actions build.
8. Fix only errors caused by the change.

## Context efficiency
- Prefer targeted search over reading entire files.
- Prefer specific symbols and filenames.
- Avoid loading large files when only a small section is needed.
- Do not repeat code already available in context.
- Do not provide long explanations after routine changes.
- Summarize changes briefly.

## GitHub Actions
GitHub Actions is responsible for:
- compilation
- testing
- IPA generation
- artifact generation

Do not manually reproduce work already performed by GitHub Actions.

## Model usage
Use inexpensive models for:
- repository search
- locating files
- reading build logs
- extracting compiler errors
- simple edits
- repetitive changes
- verification

Use stronger reasoning only for:
- architecture decisions
- difficult Swift problems
- AVFoundation/camera problems
- concurrency problems
- bugs involving several systems
- problems that cheaper models failed to solve

## Build failures
A build failure does not automatically require deep reasoning.

First extract:
- error message
- filename
- line number
- relevant function/type

Then investigate only that area.
