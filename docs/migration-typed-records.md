---
title: Migration to typed records and pipeline composition
---

# Migration to static types, records and pipeline composition

This page describes the change from tuple-based processes and subworkflows to statically typed records, and from one monolithic workflow to stage pipelines that can run on their own and be composed with other pipelines. It is written for contributors who know the code from before this change.

- [Why](#why)
- [What changed at a glance](#what-changed-at-a-glance)
- [Processes and modules](#processes-and-modules)
- [Data model between stages](#data-model-between-stages)
- [Stage pipelines](#stage-pipelines)
- [BioVAT](#biovat)
- [Including BioVAT in another pipeline](#including-biovat-in-another-pipeline)
- [Help and the parameter schemas](#help-and-the-parameter-schemas)
- [Configuration](#configuration)
- [Patched nf-core modules](#patched-nf-core-modules)
- [Behaviour changes](#behaviour-changes)
- [Tests and verification](#tests-and-verification)
- [Known limitations and follow-ups](#known-limitations-and-follow-ups)
- [How to add a module or a stage](#how-to-add-a-module-or-a-stage)

## Why

Nextflow 26.10 can include a whole pipeline (its `params` block, entry `workflow` and `output` block) from another pipeline. The `params` block acts as `take:` and the `output` block as `emit:`. This lets BioVAT be one step in a longer analysis, and lets each BioVAT stage be used on its own.

Composition needs the pipeline to be statically typed, to read `params` in one place, to avoid project-level assets (`projectDir`, `bin/`), and to pass tool arguments as process inputs instead of through `conf/modules.config` selectors. This change does that. See the Nextflow docs on [pipeline composition](https://docs.seqera.io/nextflow/workflow-typed#pipeline-composition) and [typed parameters](https://docs.seqera.io/nextflow/typed-parameters).

Requires **Nextflow >= 26.10.0** (`pixi.toml` is updated). Composition is an experimental Nextflow feature and may change.

## What changed at a glance

| Before                                                                                                                      | After                                                                                                                                                                                                                                              |
| --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `main.nf` runs `NBISWEDEN_BIOVAT`, which calls `workflows/biovat.nf`                                                        | `main.nf` is BioVAT: typed params with defaults, stage gates, the stage pipelines, the `output` block. It can be run or included                                                                                                                   |
| `subworkflows/local/{read_qc,trim_reads,align_reads,alignment_qc,merge,mark_duplicates,utils_bam,call_variants,variant_qc}` | `pipelines/{read_qc,trim_reads,align_reads,alignment_qc,merge,mark_duplicates,ingest_bam_or_cram,call_variants,variant_qc}`, each runnable on its own                                                                                              |
| MultiQC and versions inside `BIOVAT`                                                                                        | `pipelines/multiqc`                                                                                                                                                                                                                                |
| Tuples such as `[ meta, bam, bai ]`                                                                                         | Records such as `record(meta: ..., alignment: ..., index: ...)`                                                                                                                                                                                    |
| `ch_versions` and `emit: versions`                                                                                          | `topic:` versions record                                                                                                                                                                                                                           |
| `bin/split_genome_chunks.py`                                                                                                | `modules/local/splitgenome/bin/split_genome_chunks.py`, a plain Python script with argument parsing that the process stages into the task directory with `stage:`. It works for any pipeline that includes the module, and the root `bin/` is gone |
| `conf/modules.config` `ext.args` / `ext.prefix` selectors                                                                   | `<tool>_args` and `output_prefix` fields set by the stage pipelines                                                                                                                                                                                |
| `meta` is a Map                                                                                                             | `meta` is a Record                                                                                                                                                                                                                                 |
| `enable` and `requires` are Maps; stages get a map of gates                                                                 | `enable` and `requires` are Records in `main.nf`. Each stage has its own Boolean params                                                                                                                                                            |
| Param defaults in `nextflow.config`, types in `main.nf`                                                                     | Defaults and types in the `params` block of `main.nf` and of each stage                                                                                                                                                                            |

`subworkflows/local/utils_reference` stays a shared typed subworkflow. `subworkflows/local/utils_stage_help` serves `--help` and checks the input params of the stages. `subworkflows/local/utils_nfcore_biovat_pipeline` keeps the initialisation and the samplesheet checks.

## Processes and modules

Every process follows the same rules.

1. One record as input and one record as output.
2. Versions go to the `versions` topic as `record(process: ..., tool: ..., version: ...)`.
3. The input record has a required `id` String, an optional `meta` Record, an optional `<tool>_args` String per tool call, an optional `output_prefix` String, and then all input files. Optional files use `?`. Required input values that control the process (for example `single_end`) are fields of their own. The process code never reads `meta`: it is passed through so that the caller, and `ext` config, can use it.
4. The output record has `id`, `meta`, and every output of the process.
5. `ext` values are set as independent closure directives in the `ext [ ... ]` list, so they work in all cases, and the script uses `task.ext.args` and `task.ext.prefix`. The default prefix is built from `id`.
6. `ext.when` and the `when:` section are removed, and the pipeline never uses `process.when` for conditional logic: the calling workflow decides, with a gate or an `if` around the call. `process.when` in a user config still works and is meant for excluding samples dynamically, e.g. `process { withName: '.*FASTQC' { when = { id != 'PUN-R-ELF' } } }`.
7. File inputs are `Path`, `List<Path>` when the order matters, and `Bag<Path>` when it does not.

Before:

```groovy
process SAMTOOLS_FLAGSTAT {
    tag "${meta.id}"

    input:
    tuple val(meta), path(bam), path(bai)

    output:
    tuple val(meta), path("*.flagstat"), emit: flagstat
    tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), emit: versions_samtools, topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    samtools flagstat --threads ${task.cpus} ${bam} > ${prefix}.flagstat
    """
}
```

After:

```groovy
nextflow.enable.types = true

process SAMTOOLS_FLAGSTAT {
    tag "${id}"

    ext [
        prefix: { output_prefix ?: "${id}" }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        bam: Path,
        bai: Path,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        flagstat: file("*.flagstat", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'samtools', version: eval("samtools version | sed '1!d;s/.* //'")) >> 'versions'

    script:
    """
    samtools flagstat --threads ${task.cpus} ${bam} > ${task.ext.prefix}.flagstat
    """
}
```

Where a module used to read `meta` in its script, the value is now an explicit input field, and the stage passes it:

| Module                      | Field                                                            | Was                                                        |
| --------------------------- | ---------------------------------------------------------------- | ---------------------------------------------------------- |
| `fastp`                     | `single_end`                                                     | `meta.single_end`                                          |
| `parabricks/fq2bam`         | `single_end`                                                     | `meta.single_end`                                          |
| `qualimap/bamqc`            | `single_end`                                                     | `meta.single_end`                                          |
| `validate_readgroup_header` | `library`, `platform`, `platform_unit` (and `id` for the sample) | `meta.library`, `meta.pl`, `meta.platform_unit`, `meta.id` |

### A module that runs a script of its own

`splitgenome` runs a Python script with argument parsing. The script lives in the module (`modules/local/splitgenome/bin/split_genome_chunks.py`, executable) and is staged into the task directory, so any pipeline that includes the module has it and no root `bin/` is needed:

```groovy
stage:
stageAs file("${moduleDir}/bin/split_genome_chunks.py"), '*'
...
script:
"""
./split_genome_chunks.py --input ${fai} ${chunk_size_cmd} ${min_length_cmd} ${task.ext.args}
"""
```

Notes for each module:

- Reads, BAM lists passed to `samtools cat`/`merge` and their indexes are `List<Path>`, because order matters. Files where order does not matter (MultiQC inputs, parabricks `intervals` and `known_sites`) are `Bag<Path>`.
- Outputs that are `files(...)` globs are `Set<Path>`. When order matters downstream (fastp reads), the stage pipeline converts to a sorted List.
- Modules that used a second input for the reference (`meta2, fasta, fai`) take `fasta` and `fai` as optional fields of the single record.
- `multiqc` returns its own version as a `versions` output field instead of sending it to the topic. MultiQC consumes the topic, so publishing to it would hang the pipeline.
- Typed Nextflow has no `List.minus`, regex `Matcher` or `Record.keySet()`. Where the old code used these, the converted code uses `findAll`, token search and explicit field lists.
- A `List<Path>` that is interpolated into a typed script is rendered as `[a.bam]`. Join it, as in `${bams.join(' ')}`.

## Data model between stages

| Name                      | Shape                                                                                                                    |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Samplesheet row           | `record(meta, files)`. `files` are the reads, or `[ bam ]`                                                               |
| Reads                     | `record(meta, reads)` with `reads: List<Path>`                                                                           |
| BAM/CRAM input            | `record(meta, bam_cram)`                                                                                                 |
| Alignment                 | `record(meta, alignment, index)`                                                                                         |
| Reference                 | The `fasta` and `fai` params of the stages, each a `Value<Path>?`. `fai` is only needed for Riker and CRAM               |
| `enable` (in `main.nf`)   | `record(raw_read_qc, trim, align, align_qc, mark_duplicates, variant_calling, variant_qc, cram_format, riker, qualimap)` |
| `requires` (in `main.nf`) | `record(merge_to_library, merge_to_sample, fai)`                                                                         |

`meta` is a record. Its keys are `id`, `library`, `flowcell`, `lane`, `pl`, `single_end`, `read_group`, `platform_unit` and `input_type`. The merge stage builds a new `meta` with only `id`, `library`, `pl` and `single_end`. At sample level `library` is `null`.

Convert a Map to a record with `record(map)`. Join two record channels on `meta` with `a.join(b, by: 'meta')`. Combine a channel with a value channel with `ch.combine(value)`, then take both in the closure.

## Stage pipelines

Each directory under `pipelines/` is a pipeline with a typed `params` block, an entry `workflow` that reads `params.x`, an `output` block, its own `nextflow.config` and its own `nextflow_schema.json`. A stage can run on its own or be included.

```groovy
nextflow.enable.types = true

include { FASTQC     } from '../../modules/nf-core/fastqc/main'
include { STAGE_HELP } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput } from '../../subworkflows/local/utils_stage_help/main'

record Reads {
    meta : Record     // sample information, requires read_group
    reads: List<Path> // fastq files, in order
}

params {
    samplesheet: Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads    : Channel<Reads>?    // alternative to the samplesheet: reads with their meta record (YAML, JSON or a calling pipeline)
    help     : Boolean = false
    help_full: Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/read_qc --samplesheet samplesheet.csv')
    checkStageInput(params.samplesheet, params.reads, 'reads')
    reads = params.reads ?: params.samplesheet
        .filter { sample -> sample.fastq_1 != null }
        .map { sample -> def row = sampleToRow(sample); record(meta: record(row[0]), reads: row[1]) }

    fastqc = FASTQC(
        reads.map { r -> record(id: r.meta.id, meta: r.meta, reads: r.reads, fastqc_args: '--quiet', output_prefix: r.meta.read_group) }
    )

    publish:
    fastqc        = fastqc
    multiqc_files = fastqc.flatMap { out -> out.zip.toList() }

}

output {
    fastqc       : Channel<Record> { path 'fastqc' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
```

A step is a stage when it can run on an input of its own, a CSV or a records channel. A step that only serves other steps is a shared subworkflow (`utils_reference`, `utils_stage_help`). Quality checks follow the same rule: `read_qc`, `alignment_qc` and `variant_qc` are stages. The alignment stages include `alignment_qc` under their own alias with their `level` (`input`, `readgroup`, `library`, `markdup` or `sample`), and `call_variants` includes `variant_qc` under its own alias. `variant_qc` takes an optional `level` that prefixes its output files, so that calls from different stages do not collide. `call_variants` leaves it unset, which keeps the file names of `dev`.

| Stage                | Data param                      | Other params (defaults)                                                                                                                                                                                                                                                                  | Required `meta` keys                                                                      |
| -------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `read_qc`            | `reads`                         |                                                                                                                                                                                                                                                                                          | `read_group`                                                                              |
| `trim_reads`         | `reads`                         | `adapter_fasta`, `save_trimmed_fail` (false), `save_merged` (false)                                                                                                                                                                                                                      | `read_group`                                                                              |
| `align_reads`        | `reads`                         | `aligner` (bwa-mem3), `fasta`, `fai`, `cram_format`, `align_qc`, `riker`, `qualimap`                                                                                                                                                                                                     | `id`, `library`, `pl`, `platform_unit`, `read_group`                                      |
| `ingest_bam_or_cram` | `bam_cram`                      | `fasta`, `fai`, `cram_format`, `align_qc`, `riker`, `qualimap`                                                                                                                                                                                                                           | `id`, `library`, `pl`, `platform_unit`, `read_group`                                      |
| `merge`              | `alignments`                    | `level` (library), `fasta`, `fai`, `cram_format`, `align_qc`, `riker`, `qualimap`                                                                                                                                                                                                        | `id`, `pl`, `single_end`, `library` (library level)                                       |
| `mark_duplicates`    | `alignments`                    | `duplicate_marker` (samtools), `remove_duplicates`, `optical_distance` (100), `fasta`, `fai`, `cram_format`, `align_qc`, `riker`, `qualimap`                                                                                                                                             | `id`, `library`, `pl`                                                                     |
| `call_variants`      | `alignments`, `sample_metadata` | `variant_caller` (bcftools_multisample), `chunk_size`, `min_length` (1000), `callset_prefix` (all_samples), `group_samples`, `save_mpileup`, `baq`, `multiallelic_caller`, `variants_only`, `bcftools_mpileup_extra`, `bcftools_call_extra`, `fasta`, `fai`, `dict` (GATK), `variant_qc` | `id`, `pl`                                                                                |
| `variant_qc`         | `variant_calls`                 | `fasta`, `level`                                                                                                                                                                                                                                                                         |                                                                                           |
| `alignment_qc`       | `alignments`                    | `level` (required), `fasta`, `fai`, `riker` (true), `qualimap` (false)                                                                                                                                                                                                                   | `id`, `pl`, `single_end`; `read_group` (input, readgroup) or `library` (library, markdup) |
| `multiqc`            | `multiqc_files`                 | `multiqc_config`, `multiqc_logo`, `multiqc_title`, `multiqc_methods_description`, `workflow_summary`                                                                                                                                                                                     |                                                                                           |

### Running a stage on its own

Each stage takes the flat `samplesheet.csv` with `--samplesheet`, so a stage can be run with the same file as BioVAT. `samplesheet` is a `Channel` of a named record type, which Nextflow loads from the CSV (the type has to be named and its files `Path` fields, otherwise the paths stay strings and the process fails with "Not a valid path value"). Empty cells are `null`, and the stage keeps the rows that apply to it and builds `meta` with `sampleToRow()`, the same function BioVAT uses.

| Stage                                                       | `--samplesheet` CSV columns                                                                           | Rows used           |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------- |
| `read_qc`, `trim_reads`, `align_reads`                      | the BioVAT samplesheet (`sample,library_id,flowcell_id,lane,platform,fastq_1,fastq_2,bam,single_end`) | rows with `fastq_1` |
| `ingest_bam_or_cram`                                        | the BioVAT samplesheet                                                                                | rows with `bam`     |
| `merge`, `mark_duplicates`, `call_variants`, `alignment_qc` | `sample,library_id,platform,single_end,alignment,index`                                               | all rows            |
| `variant_qc`                                                | `id,vcf,index`                                                                                        | all rows            |

`--sample_metadata` for `call_variants` is a CSV with the columns `sample,population`. The nested route (`--reads`, `--bam_cram`, `--alignments`, `--variant_calls`, a YAML or JSON file with `meta`) is kept for calling pipelines; give either `--samplesheet` or that param, not both:

```yaml
# reads.yml
- meta:
    {
      id: PUN-R-ELF,
      library: "1",
      flowcell: SRR9309791,
      lane: 1,
      pl: ILLUMINA,
      single_end: false,
      read_group: PUN-R-ELF.1.SRR9309791.1,
    }
  reads: [/data/PUN-R-ELF_1_R1.fastq.gz, /data/PUN-R-ELF_1_R2.fastq.gz]
```

```bash
nextflow run pipelines/read_qc --samplesheet samplesheet.csv -profile docker -output-dir results   # from the repository root
nextflow run pipelines/align_reads --samplesheet samplesheet.csv --fasta ref.fa -profile docker,test -output-dir results
nextflow run pipelines/align_reads --reads trimmed.yml --fasta ref.fa -profile docker,test -output-dir results   # nested route
```

A stage's own `nextflow.config` includes `conf/stage.config` (container profiles, resource labels, `outputDir`). Launched from the repository root, the root `nextflow.config` is loaded as well, which also works. Use `-profile test` on a small machine, because the `test` profile in `conf/stage.config` limits the resources, and `BWAMEM3_MEM` asks for 12 CPUs.

`fasta` and `fai` are `Value<Path>?`. A plain path on the command line becomes a value channel. A calling pipeline can pass the output of another process.

### Rules the pipelines follow

- `params.x` is read only in entry workflows and `output` blocks. Everything else gets values as inputs.
- Data params are nullable so that `--help` works (see below), and the workflow checks them after the help call.
- No `projectDir`, `bin/` or `lib/` in included pipelines. Assets are found with `moduleDir`.
- Typed workflows do not allow `.out`, `set`, `tap`, `|`, implicit closure parameters or the `Channel` factory. Closures declare their parameters.
- `collect()` returns a `Bag`, `channel.topic('versions')` needs `as Channel<Record>`, and `distinct()` is `unique()`.
- A workflow with one published output returns that channel. With several it returns a record, with one field per output.
- Output paths and the layout of the published directory are unchanged (`01_input_checks`, `02_read_trimming`, and so on).

## BioVAT

`main.nf` is BioVAT. It declares the pipeline params and their defaults, builds the `enable` and `requires` records, and calls the stages. Every stage is gated by the same flags as before, so a disabled stage is not called:

| Flag                       | Stage                                          |
| -------------------------- | ---------------------------------------------- |
| `--enable_raw_read_qc`     | `read_qc`                                      |
| `--enable_trim`            | `trim_reads`                                   |
| `--enable_align`           | `align_reads`                                  |
| `--enable_align_qc`        | `alignment_qc`, inside the alignment stages    |
| `--enable_mark_duplicates` | `merge` to library level and `mark_duplicates` |
| `--enable_variant_calling` | `merge` to sample level and `call_variants`    |
| `--enable_variant_qc`      | `variant_qc`, inside `call_variants`           |

`ingest_bam_or_cram` always runs, on the BAM/CRAM rows of the samplesheet. MultiQC always runs.

The samplesheet has two routes:

- `--input samplesheet.csv` is a path. nf-schema validates the file against `assets/schema_input.json`, as before.
- `samplesheet: Channel<Sample>?` is a channel param for a pipeline that includes BioVAT. `Sample` has the columns of the samplesheet. Nextflow converts each row to the record, so empty cells are `null`.

The sample metadata sheet (`--sample_metadata`, a path validated against `assets/schema_sample_metadata.json`) is read the same way and passed to `call_variants` as a channel of `record(id, population)`.

Give one of them. Both routes go through the same row checks (`validateSamplesheetRows`): a library must not mix platforms and merge groups must agree on `single_end`, the sample metadata must be consistent with the samplesheet, stages that consume alignments need an alignment source, variant calling needs ILLUMINA data, and a reference has to be given when a step needs it. The rows are collected, checked, and only then released to the stages.

Param defaults are in the `params` block of `main.nf`. `nextflow.config` keeps only the params that the config itself reads (`outdir`, `publish_dir_mode`, `monochrome_logs`, `trace_report_suffix`, `custom_config_*`, `config_profile_*`, test data paths).

## Including BioVAT in another pipeline

`examples/chaining` includes `main.nf` and gives its sample-level alignments to a downstream process.

```groovy
include { workflow as BIOVAT } from '../../main.nf'

params {
    samples  : Channel<Sample> // BioVAT samplesheet, loaded by Nextflow as a channel of records
    reference: Path
}

workflow {
    main:
    biovat = BIOVAT(
        record(
            samplesheet    : params.samples,
            reference      : params.reference,   // every other param has a default
            validate_params: false
        )
    )
    flagstat = SAMTOOLS_FLAGSTAT(
        biovat.outputs_sample.map { aln -> record(meta: aln.meta, bam: aln.alignment, bai: aln.index, output_prefix: "downstream_${aln.meta.id}") }
    )
    ...
}
```

Run it from its own directory, so only its `nextflow.config` is loaded:

```bash
cd examples/chaining
nextflow run . -profile docker,arm64,test
```

What the including pipeline has to provide:

- `validate_params: false`. nf-schema would otherwise validate the parameters of the calling pipeline against the BioVAT schema. BioVAT skips the validation by itself, with a warning, when a samplesheet channel is given.
- The nf-schema plugin in its config (`plugins { id 'nf-schema@2.8.0' }`). BioVAT uses it for the parameter summary and the MultiQC summary.
- A `manifest`. BioVAT builds the MultiQC methods description and the versions file from the manifest of the pipeline that runs it.
- Container engine, resource limits and `outputDir`. The `nextflow.config` of an included pipeline is not loaded.
- Process selectors with the plain process name (`'SAMTOOLS_SORT'`) still match. The full name is `ALIGN_READS:...`, with the alias of the include as the prefix, and it is only needed to give one stage different behaviour when several stages use the same module (for example `ALIGN_READS:ALIGNMENT_QC:RIKER_MULTI`).

The outputs of BioVAT are the names in the `publish:` section of `main.nf` (`outputs_sample`, `outputs_multiqc`, and so on). The caller decides which of them it publishes.

## Help and the parameter schemas

- **BioVAT.** `nextflow run . --help` prints the options of `nextflow_schema.json` through `PIPELINE_INITIALISATION`, as before. The `samplesheet` channel param is not in the schema, because nf-schema cannot validate it (see below).
- **Stages.** `nextflow run pipelines/<stage> --help` prints the options of the stage's own `nextflow_schema.json`. `conf/stage.config` sets `validation.parametersSchema` to it, and `STAGE_HELP` prints the message and exits. Passing the schema path as an option to `paramsHelp` has no effect in nf-schema 2.8.0. Only the configured schema is used. The stage schemas are written by hand. Update them when the params block of a stage changes.
- **Required params and help.** Nextflow reports a required typed param as missing before the workflow starts, so `--help` would fail on `Parameter 'reads' is required`. Data params are therefore nullable, and the workflow raises the "Missing required parameter" error itself after the help call.
- **In an included pipeline** `help` is `false` and nothing is printed. A stage does not run the parameter summary or the validation.

## Configuration

**Tool arguments.** The stage pipelines set `<tool>_args` and `output_prefix` on the record they pass to each process. `conf/modules.config` is removed, because nothing needs it any more. A selector in user config still overrides the pipeline value:

```groovy
process {
    withName: 'SAMTOOLS_SORT' {
        ext.args = '--output-fmt cram'
    }
}
```

`ext.args` replaces the arguments the pipeline sets. Include any flags the pipeline relies on. Do not add a selector that sets `ext.prefix` or `ext.args` in a config the pipeline loads without a reason: it overrides the input field for every user and hides the value the pipeline passes. This is how `RIKER_MULTI` ended up writing `null.*` files during the migration. Use a `withName` or `withLabel` selector: a generic `process { ext.args = ... }` is weaker than the `ext` directive in the process, so it does not override it.

If a pipeline-wide selector is needed, put it in its own config file and load it with `includeConfig`. Use the plain process name, or the full name with the stage alias (`.*:ALIGN_READS:.*:RIKER_MULTI`) when only one stage should be affected.

**Output location.** `nextflow.config` keeps `outputDir = params.outdir` for now. The composition docs suggest `-output-dir` instead.

## Patched nf-core modules

nf-core modules do not have typed records upstream, so the converted modules are tracked with `nf-core modules patch`. Each patched module has a `<tool>-<name>.diff` file next to `main.nf` and a `patch` entry in `modules.json`. The nf-core subworkflow `utils_nextflow_pipeline` is patched in the same way: its params dump had to skip `Path` values, which Groovy's JSON generator cannot write.

- Edit `main.nf` and the tests in the module, then run `nf-core modules patch <name>`. If the diff already exists, delete the `.diff` file first.
- `nf-core modules update <name>` applies the patch on top of the new upstream version, and reports a conflict if they overlap.
- `modules/nf-core/**/tests` are ignored by the pipeline `nf-test.config`. To run a module test, use a copy of the config without that ignore line:

  ```bash
  NFT_CONFIG=$(mktemp)
  grep -v 'modules/nf-core/\*\*/tests' nf-test.config > "$NFT_CONFIG"
  nf-test test modules/nf-core/samtools/flagstat/tests/main.nf.test --config "$NFT_CONFIG" --profile docker
  ```

- The module tests pass records: `input[0] = channel.of(record(meta: [...], bam: file(...), ...))`. Versions are in the topic, so they are not in `process.out` and not in the snapshots. `process.out[0]` holds the list of records.

## Behaviour changes

Outputs are the same as before for the test profile. The differences are:

- **fastp `discard_trimmed_pass`.** The old code was `discard_trimmed_pass ?: "--out1 ..."`, which passed `true` to fastp when the option was set. It now adds `--out1` only when passing reads are kept.
- **Alignment QC** is the `alignment_qc` stage. `align_reads`, `ingest_bam_or_cram`, `merge` and `mark_duplicates` include it under their own alias with their level, so each stage still runs QC when it runs on its own, and the QC processes keep the stage prefix (`MERGE_TO_LIBRARY:ALIGNMENT_QC:RIKER_MULTI`).
- **Stub runs.** `samtools sormadup` now creates the `.csi`/`.crai` index in stub mode. Before, the stub run silently dropped these alignments in a `join` and skipped the QC after mark duplicates and the merge to sample level. Stub runs now execute more tasks.
- **Required indexes.** An alignment without an index now fails the process with "input cannot be null" instead of being dropped by `join`.
- **`samtools sort` and `samtools merge`** take their BAM lists as `List<Path>`. A single file has to be wrapped as `[ file ]`.
- **`qualimap` stub** uses `task.ext.prefix` and no longer honours `task.ext.suffix`.
- **MultiQC** takes its config as `List<Path>?`. The `[]` convention for "none" is now `null`.
- **Versions** are published in `pipeline_info/` through the `output` block instead of `collectFile(storeDir:)`.
- **Samplesheet checks** run on the collected rows in the entry workflow, not inside `PIPELINE_INITIALISATION`.
- `ch_versions` and the `versions` emits are gone from the pipeline and the modules. The MultiQC stage reads the shared `versions` topic and accepts both `record(process, tool, version)` and the `(process, tool, version)` tuple, so processes of an including pipeline can use either.
- **`ext.when` is no longer supported.** The `when:` section was removed from the modules. A user config with `ext.when = false` has no effect. The calling workflow decides: switch a stage off with its `--enable_*` gate, or put an `if` around the call. `process.when` in a user config still works, for dropping individual samples (the closure sees the input record fields, e.g. `id`), not for switching stages on and off.
- **Process names** now carry the alias of the stage as a prefix (`ALIGN_READS:BWAMEM3_MEM`). Selectors with the plain process name still match. Selectors with the old fully-qualified names (`NBISWEDEN_BIOVAT:BIOVAT:...`) no longer match.
- **Stage options are validated.** `mark_duplicates` rejects an unknown `duplicate_marker` and `merge` rejects an unknown `level`. Before, an unknown marker silently produced nothing.
- **Parabricks with CRAM output** indexes the CRAM. The BAM-only code passed a null into `SAMTOOLS_INDEX`, and `dev` dropped such samples silently.
- **`REFERENCE_VALUE`** creates the fai index when a stage needs it (Riker, CRAM) and only the fasta is given, and stops with a clear error when a stage needs a reference and none is given.
- The `variant_calling` flag runs the variant calling of `dev` (bcftools multi-sample or GATK) as the `call_variants` and `variant_qc` stages.

## Tests and verification

- **Modules.** Every module test is converted to records. The sort and merge snapshots were made with `nft-bam@0.6.0`, because `bam()` and `cram()` fail in `nft-bam@0.7.0`. The parabricks tests need a GPU, so only its stub tests were run.
- **Stages.** Each stage has `pipelines/<stage>/tests/main.nf.test`: a stub run from a generated YAML fixture, and a check that a missing data param fails with "Missing required parameter". Run them with `nf-test test pipelines --profile docker,arm64,test`.
- **Schemas.** `tests/schema_params.nf.test` fails when a `params` block and its `nextflow_schema.json` differ in parameter names, types or defaults. Each stage test file also has a `--help` test. nf-test does not capture the help message, so it only checks that `--help` is reached and exits cleanly.
- **BioVAT.** `tests/default.nf.test` runs the pipeline with the test profile against the snapshot from before the migration, and passes unchanged.
- **Lint.** `nextflow lint -o concise -exclude .pixi -exclude .git -exclude work -exclude .nf-test .` has no errors. The `collectFile` warnings in `pipelines/multiqc` remain.
- **Stub runs.** The published files of the test profile match the pipeline before the migration, apart from the QC outputs described above. Disabling stages with the `--enable_*` flags skips them and the rest still runs. `examples/chaining` runs.

## Known limitations and follow-ups

- Included pipelines need Nextflow 26.10. Composition is experimental.
- nf-schema 2.8.0 and 3.0.0 hang in `validateParameters` when a param is a channel with a value. A fix ([nextflow-io/nf-schema#230](https://github.com/nextflow-io/nf-schema/pull/230), merged 2026-10-05) is not released yet, 3.0.0 (2026-09-29) is the latest release. BioVAT therefore keeps `--input` as a validated path for the command line, and uses the `samplesheet` channel param only for callers, which set `validate_params: false`. With a fixed release, `input` and the schema check could become one typed channel param.
- `subworkflows/local/utils_nfcore_biovat_pipeline` is not typed. It is the nf-core template code (methods description, completion summary) plus the samplesheet checks, which use mutable Groovy collections and `workflow.toMap()` that typed Nextflow does not support. Its functions receive records and plain maps at runtime.
- The schemas are written by hand. `nf-core pipelines schema build` does not read typed `params` blocks, so it cannot update them. `tests/schema_params.nf.test` compares the names, types and defaults of each schema with its `params` block, but not the descriptions.
- `nf-core pipelines lint` is not run. `nextflow lint` is the check.
- The MultiQC pipeline uses `collectFile`, which the linter discourages in typed code.
- The published outputs are still one channel per tool, to keep the published directory layout of `dev`. Joining the outputs of a stage into one wide record per sample would be cleaner for composition, and is a follow-up.
- `groupKey` early release of the variant calling chunks has no typed equivalent, so concatenation waits for every chunk. There is one callset group, so this only changes when the concatenation starts.
- A stage that needs the fai index (Riker, CRAM) takes it as a param. A stage run on its own does not create it.

## How to add a module or a stage

**A module.** Install it with `nf-core modules install`, convert it to the rules above, update its tests, and run `nf-core modules patch`.

**A stage.**

1. Create `pipelines/<stage>/main.nf` with `nextflow.enable.types = true`, a named record type and a nullable `Channel` param for the data, Boolean and String params with defaults for the options, `help` and `help_full`, an entry `workflow` with `STAGE_HELP`, `checkStageInput`, `main:` and `publish:`, and an `output` block.
2. Add `nextflow.config` (include `conf/stage.config`), a hand-written `nextflow_schema.json`, and `tests/main.nf.test` with a stub test.
3. Pass tool arguments and prefixes to the processes in record fields.
4. Add the include and the call to `main.nf`, behind a gate. Give a second call of the same stage its own alias.
5. Mix the stage's `multiqc_files` into the MultiQC input.
6. Add the stage outputs to the `publish:` section and the `output` block of `main.nf`.
