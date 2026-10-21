nextflow.enable.types = true

//
// Read QC pipeline
//

include { FASTQC     } from '../../modules/nf-core/fastqc/main'
include { STAGE_HELP } from '../../subworkflows/local/utils_stage_help/main'
include { sampleToRow } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'

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

record Reads {
    meta : Record     // sample information, requires read_group
    reads: List<Path> // fastq files, in order
}

params {
    samplesheet: Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads      : Channel<Reads>?  // alternative to the samplesheet: reads with their meta record, from a YAML or JSON file or a calling pipeline
    help     : Boolean = false
    help_full: Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/read_qc --samplesheet samplesheet.csv')
    if ( params.samplesheet && params.reads ) {
        error "Provide either --samplesheet or --reads, not both"
    }
    if ( !params.samplesheet && !params.reads ) {
        error "Missing required parameter --samplesheet"
    }
    reads = channel.empty()
    if ( params.samplesheet ) {
        reads = params.samplesheet
            .filter { sample -> sample.fastq_1 != null }
            .map { sample ->
                def row = sampleToRow(sample)
                record(meta: record(row[0]), reads: row[1])
            }
    } else {
        reads = params.reads
    }

    fastqc = FASTQC(
        reads.map { r -> record(id: r.meta.id, meta: r.meta, reads: r.reads, fastqc_args: '--quiet', output_prefix: r.meta.read_group) }
    )

    publish:
    fastqc        = fastqc                                         // record(meta, html, zip)
    multiqc_files = fastqc.flatMap { out -> out.zip.toList() }

}

output {
    fastqc       : Channel<Record> { path 'fastqc' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
