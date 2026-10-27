# BioVAT: Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### `Added`

- Created BioVAT with the [nf-core](https://nf-co.re/) template
- Reference file channel (optional input)
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
- Reference utilities subworkflow for creating generic reference supplementary files used across many subworkflows (currently gated on `params.reference`)
- BAM QC workflow
- Test dataset composed of reference and multiple samples per population
- Variant calling workflow with BCFtools (multi-sample variant calling)
- Genome chunking support for parallelized variant calling; `--chunk_size` defaults to the largest of either: 1) the longest chromosome or 2) 1/50 of the genome (after min-length removal). This is to avoid excessive chunk count for highly fragmented assemblies. Regions excluded by `--min_length` are published (`excluded_regions.tsv`), summarised in MultiQC, and warned about on the console when over 5% of the reference
- Variant QC workflow
- Optional sample-level metadata sheet (`--sample_metadata`, one row per sample) kept separate from the samplesheet; currently holds `population`. When provided with variant calling enabled, samples are grouped into populations in `bcftools call` (`--group-samples`), replacing a dedicated `--enable_group_samples` flag
- BAM/CRAM samplesheet input (`bam` column): each file's `@RG` header is validated against its samplesheet row; files with no `@RG` line get one built from the samplesheet (`samtools addreplacerg`), and files with several `@RG` lines or missing/mismatched tags are rejected (`PL` is matched case-insensitively, per the SAM spec)
- Samplesheet `platform` restricted to the uppercase SAM spec `@RG PL` values (e.g. `ILLUMINA`)
- Each analysis stage is now a pipeline under `pipelines/` (`read_qc`, `trim_reads`, `align_reads`, `alignment_qc`, `ingest_bam_or_cram`, `merge`, `mark_duplicates`, `multiqc`) with its own typed `params` block, `output` block, `nextflow.config`, `nextflow_schema.json` (for `--help`) and nf-test. Each stage can run on its own with a samplesheet file (CSV, JSON or YAML) as input, and be composed with other pipelines (pipeline composition, Nextflow 26.10)
- Every stage pipeline accepts `--samplesheet` with a flat CSV (the BioVAT samplesheet for the read and BAM/CRAM stages; `sample,library_id,platform,single_end,alignment,index` for merge, mark_duplicates and call_variants; `id,vcf,index` for variant_qc; the same columns as merge plus `--level` for alignment_qc). The nested YAML/JSON params are kept for calling pipelines. `--sample_metadata` columns are now `sample,population`
- `samplesheet` channel param for pipelines that include BioVAT, as an alternative to `--input`

- `examples/chaining`: includes BioVAT (`main.nf`) and passes its alignments to a downstream process
- `docs/migration-typed-records.md`: migration guide for the typed records and pipeline composition change
- `readSamplesheet()` function for reading the samplesheet outside of `PIPELINE_INITIALISATION`
- GATK4 joint variant calling (`--variant_caller gatk`), following the GATK germline short variant Best Practices: per-sample `HaplotypeCaller` in GVCF mode, then `GenomicsDBImport` and `GenotypeGVCFs`, each run per genome chunk. The reference sequence dictionary is created by `REFERENCE_UTILS` when needed. Output is not yet filtered
- Genome chunk concatenation is shared by all variant callers, and the joint VCF and its variant QC outputs are named after the caller (`<callset_prefix>.<variant_caller>.vcf.gz`)
- Bcftools mpileup output: change from the pattern used by nf-core. Instead of bgzipping compressed output, output uncompressed, then recompress with bcftools. This leads to equivalent compression on the test files, plus it's directly readable by bcftools (previously it had to be unzipped and piped into bcftools)

### `Changed`

- All processes use static types and follow the module spec: one record as input, one record as output, a required `id` and an optional `meta` that the process code never reads, `ext [ ... ]` closure directives, and and software versions sent to the `versions` topic as `record(process, tool, version)`. nf-core modules are converted locally and tracked with `nf-core modules patch` (`*.diff` files next to each module)
- Tool arguments and output prefixes are passed to processes as input record fields (`<tool>_args`, `output_prefix`) by the stage pipelines instead of `conf/modules.config`, which is removed. `ext.args`/`ext.prefix` set in user config still take precedence
- Removed the `when:` section from converted modules. `ext.when` no longer has an effect: the calling workflow decides, with the stage gates or an `if` around the call. `process.when` in a user config still works for excluding samples
- The variant calling subworkflows are the stage pipelines `call_variants` and `variant_qc`, and the new modules (`splitgenome`, `bcftools/*`, `vcftools`, `gatk4/*`) use records. `bin/split_genome_chunks.py` moved into the `splitgenome` module (`modules/local/splitgenome/bin`) and is staged into the task with `stage:`
- `REFERENCE_VALUE` creates the fai index for a stage that needs it, and `mark_duplicates` and `merge` reject unknown option values
- The `versions` topic consumer accepts records and tuples. Process names carry the stage as a prefix, so fully-qualified selectors need updating
- `main.nf` composes the stage pipelines directly, and can be run or included by other pipelines. `workflows/biovat.nf` is removed. The stages are still gated by the `--enable_*` flags
- Param defaults moved from `nextflow.config` to the `params` block of `main.nf`. `nextflow.config` keeps only the params that the config reads
- The samplesheet checks (single-end/paired-end mix, reference required) run on the collected rows in the entry workflow
- The nf-core subworkflow `utils_nextflow_pipeline` is patched so that the params dump handles `Path` params
- Software versions and MultiQC files are collected by the `multiqc` pipeline; the versions file is published through the `output` block instead of `collectFile(storeDir:)`

### `Fixed`

- Samplesheet schema enforces platform & (temporarily) fastq2
- nf-test CI failures: missing pipeline snapshot, relative test-data paths not resolving under nf-test, and test-profile memory limit exceeding GitHub Actions runner capacity (#37)
- Regenerated stale container/conda-lock configs and synced `linting.yml` with the nf-core template (#37)
- Prettier formatting drift; excluded `pixi.lock` from prettier since its format is owned by pixi (#37)
- Sample/library_id/flowcell/lane uniqueness is now enforced via nf-schema's `uniqueEntries` keyword instead of custom dedup code (#43)
- Experimental: switches to typed params

### `Dependencies`

- Nextflow >=26.10.0 (pipeline composition)
- updated nf-core to 4.1.0
- Updated the pixi lock file to v7
