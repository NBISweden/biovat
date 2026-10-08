# BioVAT: Usage

> _Documentation of pipeline parameters is generated automatically from the pipeline schema and can no longer be found in markdown files._

## Introduction

<!-- TODO nf-core: Add documentation about anything specific to running your pipeline. For general topics, please point to (and add to) the main nf-core website. -->

## Samplesheet input

You will need to create a samplesheet with information about the samples you would like to analyse before running the pipeline. Add it to the parameter file to specify its location (an [example parameter file](../assets/nf-params.yml) has been provided with the pipeline) or use this parameter.

```bash
--input '[path to samplesheet file]'
```

The samplesheet can have as many columns as you desire, however, it must contain the columns defined in the table below. It has to contain a header row as shown in the example below.

The `sample` identifiers have to be the same when you have re-sequenced the same sample more than once e.g. to increase sequencing depth. Sequencing library IDs, flowcell IDs, and lane numbers are specified in the columns `library_id`,
`flowcell_id`, and `lane`. Each combination of `sample`, `library_id`, `flowcell_id`, and `lane` has to be unique. When deduplication is enabled, alignments belonging to the same sample and library are first merged and deduplicated. If variant calling is enabled, libraries are further merged to sample level.

A library is prepared for a single sequencing platform, so all read groups of a library must share the same `platform`. A sample may combine libraries from different platforms; these are merged per platform.

Each row must provide raw reads via `fastq_1` (optionally `fastq_2`), **or** an already-aligned `BAM`/`CRAM` file via `bam`. If providing `BAM`/`CRAM`, users must also fill-out the `single_end` column (`false` for paired-end reads). When providing pre-aligned files, trimming and alignment are skipped. All read groups of a library, and all libraries of a sample, must agree on `single_end` (mixing single- and paired-end reads at the same merge level is rejected).

Each `BAM`/`CRAM` file is treated as a single read group, and its `@RG` header is checked against its samplesheet row. The pipeline expects `ID` and `PU` to be GATK format (`<flowcell_id>.<lane>.<sample>_<library_id>`), `SM` to be `sample`, `LB` to be `library_id`, and `PL` to be `platform`. `PL` is matched case-insensitively (the SAM specification asks tools to accept lowercase `PL` values); all other tags must match exactly. This is the read group the pipeline writes itself when aligning `fastq` rows. Consequently:

- A file with **no** `@RG` line is accepted with a warning. The pipeline builds the read group from the samplesheet row and tags every read with it.
- A file with **more than one** `@RG` line is rejected. Split it by read group (e.g. `samtools split`) and give each part its own samplesheet row.
- A file whose `@RG` line is missing any of the tags, or disagrees with the samplesheet, is rejected. Correct the samplesheet, or the file with e.g. `samtools addreplacerg -m overwrite_all -r '@RG\tID:...'`.

A final samplesheet file consisting of paired-end data for 7 samples may look something like the one below. A single library of sample `S1` has been sequenced across three lanes. Two independent libraries of sample `S6` have been sequenced. Sample `S7` supplies a pre-aligned CRAM instead of raw reads.

```csv title="samplesheet.csv"
sample,library_id,flowcell_id,lane,platform,fastq_1,fastq_2,bam,single_end
S1,1,AEG588A1,2,ILLUMINA,/data/AEG588A1_S1_L002_R1_001.fastq.gz,/data/AEG588A1_S1_L002_R2_001.fastq.gz,,
S1,1,AEG588A1,3,ILLUMINA,/data/AEG588A1_S1_L003_R1_001.fastq.gz,/data/AEG588A1_S1_L003_R2_001.fastq.gz,,
S1,1,AEG588A1,4,ILLUMINA,/data/AEG588A1_S1_L004_R1_001.fastq.gz,/data/AEG588A1_S1_L004_R2_001.fastq.gz,,
S2,1,AEG588A2,2,ILLUMINA,/data/AEG588A2_S2_L002_R1_001.fastq.gz,/data/AEG588A2_S2_L002_R2_001.fastq.gz,,
S3,1,AEG588A3,2,ILLUMINA,/data/AEG588A3_S3_L002_R1_001.fastq.gz,/data/AEG588A3_S3_L002_R2_001.fastq.gz,,
S4,1,AEG588A4,3,ILLUMINA,/data/AEG588A4_S4_L003_R1_001.fastq.gz,/data/AEG588A4_S4_L003_R2_001.fastq.gz,,
S5,1,AEG588A5,3,ILLUMINA,/data/AEG588A5_S5_L003_R1_001.fastq.gz,/data/AEG588A5_S5_L003_R2_001.fastq.gz,,
S6,1,AEG588A6,3,ILLUMINA,/data/AEG588A6_S6_L003_R1_001.fastq.gz,/data/AEG588A6_S6_L003_R2_001.fastq.gz,,
S6,2,AEG588A6,4,ILLUMINA,/data/AEG588A6_S6_L004_R1_001.fastq.gz,/data/AEG588A6_S6_L004_R2_001.fastq.gz,,
S7,1,AEG588A7,2,ILLUMINA,,,/data/AEG588A7_S7_L002.cram,false
```

| Column        | Description                                                                                                                                                                                                    |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sample`      | Unique sample identifier. This entry will be identical for multiple sequencing libraries or runs from the same sample                                                                                          |
| `library_id`  | Unique sequencing library identifier                                                                                                                                                                           |
| `flowcell_id` | Unique identifier/barcode of the flowcell used for this sample library                                                                                                                                         |
| `lane`        | The flow cell lane number as a positive integer                                                                                                                                                                |
| `platform`    | Sequencing platform, one of the SAM specification `@RG PL` values in uppercase: `CAPILLARY`, `DNBSEQ`, `ELEMENT`, `HELICOS`, `ILLUMINA`, `IONTORRENT`, `LS454`, `ONT`, `PACBIO`, `SINGULAR`, `SOLID`, `ULTIMA` |
| `fastq_1`     | Full path to FastQ file for Illumina short reads 1. File has to be gzipped and have the extension ".fastq.gz" or ".fq.gz". Mutually exclusive with `bam`                                                       |
| `fastq_2`     | Full path to FastQ file for Illumina short reads 2. File has to be gzipped and have the extension ".fastq.gz" or ".fq.gz". Optional - omit for single-end reads                                                |
| `bam`         | Full path to a pre-aligned `.bam` or `.cram` file, provided instead of `fastq_1`/`fastq_2`. Requires `single_end` on the same row; CRAM additionally requires `--reference`                                    |
| `single_end`  | Required only when `bam` is set: `true` for single-end data, `false` for paired-end. Not required for `fastq_1`/`fastq_2` rows - it's inferred from whether `fastq_2` is present                               |

An [example samplesheet](../assets/samplesheet.csv) has been provided with the pipeline.

### Sample metadata

Information describing a whole sample rather than a single sequencing run, such as its population, is supplied in a separate, optional samplesheet via `--sample_metadata`. It has one row per sample, keyed on the `sample` column of `--input`:

```csv title="sample_metadata.csv"
sample,population
S1,popA
S2,popA
S3,popB
```

| Column       | Description                                                                                    |
| ------------ | ---------------------------------------------------------------------------------------------- |
| `sample`     | Sample identifier, matching the `sample` column of `--input`. Each sample may appear only once |
| `population` | Population identifier for grouping of samples. Required for every sample when used             |

Providing `--sample_metadata` turns on population grouping in variant calling (`bcftools call --group-samples`, which applies the HWE assumption within but not across populations), and so requires a `population` for every sample in `--input`. It is ignored when `--enable_variant_calling` is off. Samples listed in `--sample_metadata` but not in `--input` are ignored with a warning. An [example sample metadata sheet](../assets/sample_metadata.csv) has been provided with the pipeline.

## Configuring the pipeline

Pipeline settings and parameters can be provided on the command-line but for better reproducibility and documentation, an example parameter file is provided in `assets/nf-params.yml`.

Here, input and output options are specified, the pipeline stages are selected, and stage- and tool-specific parameters are defined.

For a full list of available parameters and their defaults, run:

```bash
nextflow main.nf --help
```

### Variant calling

Variant calling runs when `--enable_variant_calling` is set (default `true`) and needs a `--reference`.

- `--variant_caller` selects the caller
- `--enable_variant_qc` (default `true`) runs quality checks on the final VCF

#### Genome chunking

Variant calling is parallelised over genome chunks. The reference `.fai` index is split into chunks by grouping whole chromosomes/scaffolds, in reference order, until a chunk reaches `--chunk_size` bp; each chunk is then called as a separate task and the results are concatenated into one VCF. Chromosomes are never split across chunks, so reads spanning a chunk boundary can't affect calls. As a result, chunk sizes vary.

- `--chunk_size` defaults to the length of the longest chromosome, which gives the most chunks (and parallel tasks) possible. It can only be raised: a value below the longest chromosome is reset to that length, with a warning in the `SPLITGENOME` task log. Raise it to run fewer, larger chunks; a value at or above the total genome size gives a single chunk.
- `--min_length` (default `1000`) excludes chromosomes/scaffolds shorter than this many bp from variant calling, so they won't appear in the VCF. Set it to `0` to keep everything. Excluded regions are listed in `07_variant_calls/genome_chunk_bed_files/excluded_regions.tsv` (next to the `chunk_*.bed` files listing the regions that were kept) and summarised in the "Genome chunking" table of the MultiQC report. If they make up more than 5% of the reference, the pipeline also prints a warning on the console.

#### BCFtools multi-sample calling

Alignments are first merged to one per sample and platform (see [Samplesheet input](#samplesheet-input)). All samples are called jointly: for each genome chunk, `bcftools mpileup` computes genotype likelihoods for every sample, `bcftools call` turns them into genotypes, and the chunks are then concatenated into a single multi-sample VCF, published as `07_variant_calls/<dataset_name>.vcf.gz`.

The pipeline sets the reference, the genome-chunk regions, output types and file names itself.

- `--dataset_name` (default `all_samples`) sets the file name prefix of the joint VCF and its index.
- `--sample_metadata` groups samples into populations during calling; see [Sample metadata](#sample-metadata) and [`bcftools call`](#bcftools-call).

**bcftools mpileup**

Computes per-sample genotype likelihoods from the alignments. It writes the per-sample (`FORMAT`) tags `PL` (genotype likelihoods) and `AD` (allelic depths) by default. The pipeline also adds `DP` (read depth, `--annotate FORMAT/DP`).

- `--bcftools_mpileup_extra` (default `--no-BAQ`) is passed to `bcftools mpileup`, e.g. `'--no-BAQ --min-BQ 20 --min-MQ 20'` to filter on base and mapping quality. Further `--annotate` tags given here are added to the tags above rather than replacing them.
- `--enable_save_mpileup` (default `false`) also saves the intermediate `bcftools mpileup` output (BCF with genotype likelihoods for all sites), one file per genome chunk. These files can get very large.

**bcftools call**

Calls genotypes from the likelihoods, adding the per-sample `GT` (genotype) tag and the per-site `AC`/`AN` (allele count/number) tags. The pipeline always uses the multiallelic caller (`--multiallelic-caller`), and adds `--group-samples` when `--sample_metadata` is given.

- `--bcftools_call_extra` (default `--variants-only`) is passed to `bcftools call`. Keep `--variants-only` unless you want every site (including invariant ones) in the VCF, which makes it far larger. All sites are called as diploid unless you add `--ploidy` or `--ploidy-file`.

## Running the pipeline

The typical command for running the pipeline is as follows:

```bash
nextflow run NBISweden/biovat -params-file assets/nf-params.yml -profile docker -r 0.0.1
```

This will launch the pipeline (version 0.0.1) with the `docker` configuration profile. Pipeline settings and parameters are applied as specified in `assets/nf-params.yml` as described above. See below for more information about profiles and reproducibility.

Note that the pipeline will create the following files in your working directory:

```bash
work                # Directory containing the nextflow working files
<OUTDIR>            # Finished results in specified location (defined via outdir in nf-params.yml)
.nextflow_log       # Log file from Nextflow
# Other nextflow hidden files, eg. history of pipeline runs and old logs.
```

> [!WARNING]
> Do not use `-c <file>` to specify parameters as this will result in errors. Custom config files specified with `-c` must only be used for [tuning process resource specifications](https://nf-co.re/docs/running/run-pipelines#configuring-pipelines), other infrastructural tweaks (such as output directories), or module arguments (args).

### Updating the pipeline

When you run the above command, Nextflow automatically pulls the pipeline code from GitHub and stores it as a cached version. When running the pipeline after this, it will always use the cached version if available - even if the pipeline has been updated since. To make sure that you're running the latest version of the pipeline, make sure that you regularly update the cached version of the pipeline:

```bash
nextflow pull NBISweden/biovat
```

### Reproducibility

It is a good idea to specify the pipeline version when running the pipeline on your data. This ensures that a specific version of the pipeline code and software are used when you run your pipeline. If you keep using the same tag, you'll be running the same version of the pipeline, even if there have been changes to the code since.

First, go to the [BioVAT releases page](https://github.com/NBISweden/biovat/releases) and find the latest pipeline version - numeric only (eg. `1.3.1`). Then specify this when running the pipeline with `-r` (one hyphen) - eg. `-r 1.3.1`. Of course, you can switch to another version by changing the number after the `-r` flag.

This version number will be logged in reports when you run the pipeline, so that you'll know what you used when you look back in the future. For example, at the bottom of the MultiQC reports.

To further assist in reproducibility, you can use share and reuse [parameter files](#running-the-pipeline) to repeat pipeline runs with the same settings without having to write out a command with every single parameter.

> [!TIP]
> If you wish to share such profile (such as upload as supplementary material for academic publications), make sure to NOT include cluster specific paths to files, nor institutional specific profiles.

## Core Nextflow arguments

> [!NOTE]
> These options are part of Nextflow and use a _single_ hyphen (pipeline parameters use a double-hyphen)

### `-profile`

Use this parameter to choose a configuration profile. Profiles can give configuration presets for different compute environments.

Several generic profiles are bundled with the pipeline which instruct the pipeline to use software packaged using different methods (Docker, Singularity, Podman, Shifter, Charliecloud, Apptainer, Conda) - see below.

> [!IMPORTANT]
> We highly recommend the use of Docker or Singularity containers for full pipeline reproducibility, however when this is not possible, Conda is also supported.

The pipeline also dynamically loads configurations from [https://github.com/nf-core/configs](https://github.com/nf-core/configs) when it runs, making multiple config profiles for various institutional clusters available at run time. For more information and to check if your system is supported, please see the [nf-core/configs documentation](https://github.com/nf-core/configs#documentation).

Note that multiple profiles can be loaded, for example: `-profile test,docker` - the order of arguments is important!
They are loaded in sequence, so later profiles can overwrite earlier profiles.

If `-profile` is not specified, the pipeline will run locally and expect all software to be installed and available on the `PATH`. This is _not_ recommended, since it can lead to different results on different machines dependent on the computer environment.

- `test`
  - A profile with a complete configuration for automated testing
  - Includes links to test data so needs no other parameters
- `docker`
  - A generic configuration profile to be used with [Docker](https://docker.com/)
- `singularity`
  - A generic configuration profile to be used with [Singularity](https://sylabs.io/docs/)
- `podman`
  - A generic configuration profile to be used with [Podman](https://podman.io/)
- `shifter`
  - A generic configuration profile to be used with [Shifter](https://nersc.gitlab.io/development/shifter/how-to-use/)
- `charliecloud`
  - A generic configuration profile to be used with [Charliecloud](https://charliecloud.io/)
- `apptainer`
  - A generic configuration profile to be used with [Apptainer](https://apptainer.org/)
- `wave`
  - A generic configuration profile to enable [Wave](https://seqera.io/wave/) containers. Use together with one of the above (requires Nextflow ` 24.03.0-edge` or later).
- `conda`
  - A generic configuration profile to be used with [Conda](https://conda.io/docs/). Please only use Conda as a last resort i.e. when it's not possible to run the pipeline with Docker, Singularity, Podman, Shifter, Charliecloud, or Apptainer.
- `gpu`
  - A generic configuration profile to enable GPU capable processes

### `-resume`

Specify this when restarting a pipeline. Nextflow will use cached results from any pipeline stages where the inputs are the same, continuing from where it got to previously. For input to be considered the same, not only the names must be identical but the files' contents as well. For more info about this parameter, see [this blog post](https://www.nextflow.io/blog/2019/demystifying-nextflow-resume.html).

You can also supply a run name to resume a specific run: `-resume [run-name]`. Use the `nextflow log` command to show previous run names.

### `-c`

Specify the path to a specific config file (this is a core Nextflow command). See the [nf-core website documentation](https://nf-co.re/usage/configuration) for more information.

## Custom configuration

### Resource requests

Whilst the default requirements set within the pipeline will hopefully work for most people and with most input data, you may find that you want to customise the compute resources that the pipeline requests. Each stage in the pipeline has a default set of requirements for number of CPUs, memory and time. For most of the pipeline stages, if the job exits with any of the error codes specified [here](https://github.com/nf-core/rnaseq/blob/4c27ef5610c87db00c3c5a3eed10b1d161abf575/conf/base.config#L18) it will automatically be resubmitted with higher resources request (2 x original, then 3 x original). If it still fails after the third attempt then the pipeline execution is stopped.

To change the resource requests, please see the [max resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#set-max-resources) and [customise process resources](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#customize-process-resources) section of the nf-core website.

### Custom Containers

In some cases, you may wish to change the container or conda environment used by a pipeline stage for a particular tool. By default, nf-core pipelines use containers and software from the [biocontainers](https://biocontainers.pro/) or [bioconda](https://bioconda.github.io/) projects. However, in some cases the pipeline specified version maybe out of date.

To use a different container from the default container or conda environment specified in a pipeline, please see the [updating tool versions](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#update-tool-versions) section of the nf-core website.

### Custom Tool Arguments

A pipeline might not always support every possible argument or option of a particular tool used in pipeline. Fortunately, nf-core pipelines provide some freedom to users to insert additional parameters that the pipeline does not include by default.

To learn how to provide additional arguments to a particular tool of the pipeline, please see the [customising tool arguments](https://nf-co.re/docs/running/configuration/nextflow-for-your-system#modifying-tool-arguments) section of the nf-core website.

### nf-core/configs

In most cases, you will only need to create a custom config as a one-off but if you and others within your organisation are likely to be running nf-core pipelines regularly and need to use the same settings regularly it may be a good idea to request that your custom config file is uploaded to the `nf-core/configs` git repository. Before you do this please can you test that the config file works with your pipeline of choice using the `-c` parameter. You can then create a pull request to the `nf-core/configs` repository with the addition of your config file, associated documentation file (see examples in [`nf-core/configs/docs`](https://github.com/nf-core/configs/tree/master/docs)), and amending [`nfcore_custom.config`](https://github.com/nf-core/configs/blob/master/nfcore_custom.config) to include your custom profile.

See the main [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) for more information about creating your own configuration files.

If you have any questions or issues please send us a message on [Slack](https://nf-co.re/join/slack) on the [`#configs` channel](https://nfcore.slack.com/channels/configs).

### GPU resource allocation

Apply the `gpu` profile to request GPUs; for SLURM submissions, combine it with an institutional profile (e.g. `uppmax`). To request per-process GPU resources, provide a local configuration file on the command line.

Example:

```bash
nextflow run main.nf \
  -profile gpu,uppmax \
  --project <PROJECT> \
  -params-file params.yaml \
  -c assets/gpu_configuration.config
```

In `assets/gpu_configuration.config`:

```nextflow
process {
    withName: 'PARABRICKS_FQ2BAM' {
        accelerator = [ type: 'h100', request: 1 ]
    }
}
```

For other examples, [see the Uppmax documentation](https://github.com/nf-core/configs/blob/master/docs/uppmax.md#using-gpus-on-pelle)

The `gpu` profile only sets the `accelerator` directive. Container runtime flags (`--gpus all` for Docker, `--nv` for Singularity/Apptainer) are left to whichever layer knows the execution environment: an institutional profile (e.g. `uppmax`, see Pelle's setup linked above), or your own local config, gated on `task.accelerator` and `workflow.containerEngine`:

```nextflow
process {
    withLabel: process_gpu {
        containerOptions = {
            if (task.accelerator) {
                if (workflow.containerEngine in ['singularity', 'apptainer']) {
                    '--nv'
                } else if (workflow.containerEngine == 'docker') {
                    '--gpus all'
                } else {
                    null
                }
            }
        }
    }
}
```

## Running in the background

Nextflow handles job submissions and supervises the running jobs. The Nextflow process must run until the pipeline is finished.

The Nextflow `-bg` flag launches Nextflow in the background, detached from your terminal so that the workflow does not stop if you log out of your session. The logs are saved to a file.

Alternatively, you can use `screen` / `tmux` or similar tool to create a detached session which you can log back into at a later time.
Some HPC setups also allow you to run nextflow within a cluster job submitted your job scheduler (from where it submits more jobs).

## Nextflow memory requirements

In some cases, the Nextflow Java virtual machines can start to request a large amount of memory.
We recommend adding the following line to your environment to limit this (typically in `~/.bashrc` or `~./bash_profile`):

```bash
NXF_OPTS='-Xms1g -Xmx4g'
```
