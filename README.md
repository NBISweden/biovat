# BioVAT

[![Pixi Badge](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/prefix-dev/pixi/main/assets/badge/v0.json)](https://pixi.sh)
[![Nextflow](https://img.shields.io/badge/Nextflow-v26.04.3-brightgreen)]

[![run with conda](http://img.shields.io/badge/run%20with-conda-3EB049?labelColor=000000&logo=anaconda)](https://docs.conda.io/en/latest/)
[![run with docker](https://img.shields.io/badge/run%20with-docker-0db7ed?labelColor=000000&logo=docker)](https://www.docker.com/)
[![run with singularity](https://img.shields.io/badge/run%20with-singularity-1d355c.svg?labelColor=000000)](https://sylabs.io/docs/)

## Introduction

`BioVAT` (Biodiversity Variant Analysis Toolkit) is a modular 
Nextflow pipeline for mapping, variant calling, data filtering 
and downstream analyses of population-level whole genome 
resequencing data. 

<!-- TODO:
   Complete this sentence with a 2-3 sentence summary of what types of data the pipeline ingests, a brief overview of the
   major pipeline sections and the types of output it produces. For an example, see https://github.com/nf-core/rnaseq/blob/master/README.md#introduction
-->

<!-- TODO: Include biovat figure, replace later with "tube map" design for that. See https://nf-co.re/docs/community/brand/workflow-schematics#examples for examples.   -->
<!-- TODO: Fill in short bullet-pointed list of the default steps in the pipeline , e.g. 

1. Read QC ([`FastQC`](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/))
2. Present QC for raw reads ([`MultiQC`](http://multiqc.info/))
-->

## Usage

<!-- TODO: Describe the minimum required steps to execute the pipeline, e.g. how to prepare samplesheets.
     Explain what rows and columns represent. For instance (please edit as appropriate):

First, prepare a samplesheet with your input data that looks as follows:

`samplesheet.csv`:

```csv
sample,fastq_1,fastq_2
CONTROL_REP1,AEG588A1_S1_L002_R1_001.fastq.gz,AEG588A1_S1_L002_R2_001.fastq.gz
```

Each row represents a fastq file (single-end) or a pair of fastq files (paired end).

-->

Now, you can run the pipeline using:

<!-- TODO: update the following command to include all required parameters for a minimal example -->

```bash
nextflow run biovat \
   -profile <docker/singularity/.../institute> \
   --input samplesheet.csv \
   --outdir <OUTDIR>
```

> [!WARNING]
> Please provide pipeline parameters via the CLI or Nextflow `-params-file` option. Custom config files including those provided by the `-c` Nextflow option can be used to provide any configuration _**except for parameters**_; see [docs](https://nf-co.re/docs/running/run-pipelines#using-parameter-files).

## Credits

BioVAT was originally written by Verena Kutschera, Mahesh 
Binzer-Panchal, Cormac Kinsella, André Soares, Jason Hill, 
Lorena Ament, Per Unneberg, and Lucile Soler.

We thank the following people for their extensive assistance 
in the development of this pipeline:

Filip Thörn 
Henrik Lantz 
Jacob Höglund 
Jesper Boman 
José Cerca 
Mafalda Ferreira 
Niclas Backström 


## Contributions and Support

If you would like to contribute to this pipeline, please 
see the [contributing guidelines](docs/CONTRIBUTING.md).

## Citations

<!-- TODO: Add citation for pipeline after first release. -->
<!-- If you use biovat for your analysis, please cite it using the following doi: [10.5281/zenodo.XXXXXX](https://doi.org/10.5281/zenodo.XXXXXX) -->

<!-- TODO: Add bibliography of tools and data used in your pipeline -->

An extensive list of references for the tools used by the 
pipeline can be found in the [`CITATIONS.md`](CITATIONS.md) 
file.
