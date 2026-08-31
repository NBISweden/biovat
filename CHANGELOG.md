# BioVAT: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### `Added`

- Created BioVAT with the [nf-core](https://nf-co.re/) template
- Reference file channel
- Alignment subworkflow using bwa-mem3, can be run either on raw or trimmed reads. Readgroup tagging is drawn from `meta`
- Parabricks `fq2bam` alignment, matches bwamem3 output (sorted, read group tagged, csi indexed)
- Initial test data & samplesheet
- pixi tasks for testing & development
- Initial test profile `conf/test.config`
- Added stage specific boolean params for overall control of modular execution
- Trimming subworkflow using fastp
- ADR issue template and CONTRIBUTING.md pointer documenting that architecture decisions are recorded as labelled GitHub issues (#39)
- Raw read quality check subworkflow using FastQC added as raw_read_qc stage
- Implemented workflow outputs (replaced publishDir)
- nft-bam plugin for BAM content snapshots

### `Fixed`

- Samplesheet schema enforces platform & (temporarily) fastq2
- nf-test CI failures: missing pipeline snapshot, relative test-data paths not resolving under nf-test, and test-profile memory limit exceeding GitHub Actions runner capacity (#37)
- Regenerated stale container/conda-lock configs and synced `linting.yml` with the nf-core template (#37)
- Prettier formatting drift; excluded `pixi.lock` from prettier since its format is owned by pixi (#37)
- Sample/library_id/flowcell/lane uniqueness is now enforced via nf-schema's `uniqueEntries` keyword instead of custom dedup code (#43)
- Experimental: switches to typed params

### `Dependencies`

- updated nf-core to 4.1.0
- Updated the pixi lock file to v7
