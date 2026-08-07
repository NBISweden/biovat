# BioVAT: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### `Added`

- Reference file channel
- Alignment subworkflow using bwa-mem3, can be run either on raw or trimmed reads. Readgroup tagging is drawn from `meta`
- Initial test data & samplesheet
- pixi tasks for testing & development
- Initial test profile `conf/test.config`
- Added `steps` param for overall control of modular execution

### `Fixed`

- Samplesheet schema enforces platform & (temporarily) fastq2

### `Dependencies`

- updated nf-core to 4.1.0
- Updated the pixi lock file to v7

## v0.0.1 - [date]

Initial release of BioVAT, created with the [nf-core](https://nf-co.re/) template.

### `Added`

### `Fixed`

### `Dependencies`

### `Deprecated`
