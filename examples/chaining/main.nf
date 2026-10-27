#!/usr/bin/env nextflow
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    Example: chaining BioVAT with a downstream pipeline
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    BioVAT is included as a pipeline. Its outputs are channels of records that the caller
    can pass straight to its own processes. Here the alignments of every sample are given to
    SAMTOOLS_FLAGSTAT, which stands in for any downstream pipeline.

    Run from this directory, so that only this example's nextflow.config is loaded:
        cd examples/chaining
        nextflow run . -profile docker,arm64,test
----------------------------------------------------------------------------------------
*/

nextflow.enable.types = true

include { workflow as BIOVAT } from '../../main.nf'
include { SAMTOOLS_FLAGSTAT  } from '../../modules/nf-core/samtools/flagstat/main'

// A row of the BioVAT samplesheet
record Sample {
    sample     : String
    library_id : String
    flowcell_id: String
    lane       : Integer
    platform   : String
    fastq_1    : Path?
    fastq_2    : Path?
    bam        : Path?
    single_end : Boolean?
}

params {
    samples  : Channel<Sample> // BioVAT samplesheet, loaded by Nextflow as a channel of records
    reference: Path            // reference fasta
}

workflow {

    main:
    // Every other BioVAT param has a default and is omitted here. Parameter validation by nf-schema is
    // switched off, because it would validate the parameters of this pipeline against the schema of BioVAT
    biovat = BIOVAT(
        record(
            samplesheet    : params.samples,
            reference      : params.reference,
            validate_params: false
        )
    )

    // Downstream step, consuming the alignments of every sample. outputs_sample would leave out the samples that
    // had nothing to merge
    flagstat = SAMTOOLS_FLAGSTAT(
        biovat.outputs_alignments.map { aln ->
            record(id: aln.meta.id, meta: aln.meta, bam: aln.alignment, bai: aln.index, output_prefix: "downstream_${aln.meta.id}_${aln.meta.pl}")
        }
    )

    publish:
    biovat_multiqc   = biovat.outputs_multiqc
    biovat_alignment = biovat.outputs_alignments
    downstream_stats = flagstat

}

output {
    biovat_multiqc  : Value<Record> { path 'biovat/multiqc' }
    biovat_alignment: Channel<Record> { path 'biovat/alignments' }
    downstream_stats: Channel<Record> { path 'downstream/flagstat' }
}
