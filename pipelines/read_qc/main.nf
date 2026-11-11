nextflow.enable.types = true

//
// Read QC pipeline
//

include { FASTQC          } from '../../modules/nf-core/fastqc/main'
include { STAGE_HELP      } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput } from '../../subworkflows/local/utils_stage_help/main'
include { readGroupMeta   } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { sampleToRow     } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { Sample           } from '../../types/samplesheet'

record Reads {
    id   : String     // sample name
    meta : Record     // read group information, requires read_group
    reads: List<Path> // fastq files, in order
}

params {
    samplesheet: Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads      : Channel<Reads>?  // alternative to the samplesheet: reads with their meta record, from a YAML or JSON file or a calling pipeline
    help       : Boolean = false
    help_full  : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/read_qc --samplesheet samplesheet.csv')
    checkStageInput(params.samplesheet, params.reads, 'reads')
    reads = channel.empty()
    if ( params.samplesheet ) {
        reads = params.samplesheet
            // Every row is checked, including the ones this stage skips
            .map { sample -> sampleToRow(sample) }
            .filter { row -> row.meta.input_type == 'fastq' }
            .map { row -> record(id: row.meta.id, meta: readGroupMeta(row.meta), reads: row.files) }
    } else {
        reads = params.reads
    }

    fastqc = FASTQC(
        reads.map { r -> record(id: r.id, meta: r.meta, reads: r.reads, fastqc_args: '--quiet', output_prefix: r.meta.read_group) }
    )

    publish:
    fastqc        = fastqc                                         // record(id, meta, html, zip)
    multiqc_files = fastqc.flatMap { out -> out.zip }

}

output {
    fastqc       : Channel<Record> { path 'fastqc' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
