nextflow.enable.types = true

//
// Read trimming pipeline
//

include { FASTP           } from '../../modules/nf-core/fastp/main'
include { STAGE_HELP      } from '../../subworkflows/local/utils_stage_help/main'
include { checkStageInput } from '../../subworkflows/local/utils_stage_help/main'
include { sampleToRow     } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'

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
    samplesheet      : Channel<Sample>? // BioVAT samplesheet (CSV). Rows with a bam instead of fastq files are skipped
    reads            : Channel<Reads>?  // alternative to the samplesheet: reads with their meta record, from a YAML or JSON file or a calling pipeline
    adapter_fasta    : Path?           // adapter fasta file, if provided
    save_trimmed_fail: Boolean = false // save files that failed to pass trimming thresholds
    save_merged      : Boolean = false // save all merged reads
    help             : Boolean = false
    help_full        : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/trim_reads --samplesheet samplesheet.csv')
    checkStageInput(params.samplesheet, params.reads, 'reads')
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

    // Run fastp for read trimming
    fastp = FASTP(
        reads.map { r ->
            record(
                id                  : r.meta.id,
                meta                : r.meta,
                single_end          : r.meta.single_end,
                reads               : r.reads,
                adapter_fasta       : params.adapter_fasta,
                discard_trimmed_pass: false,                      // Never discard reads that pass trimming thresholds, so fastp can still be used for the report only
                save_trimmed_fail   : params.save_trimmed_fail,   // Whether to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
                save_merged         : params.save_merged,         // Whether to save all merged reads to a file ending in *.merged.fastq.gz
                fastp_args          : null,
                output_prefix       : r.meta.read_group
            )
        }
    )

    publish:
    fastp         = fastp                                                                                                     // record(meta, reads, json, html, log, reads_fail, reads_merged)
    trimmed_reads = fastp.map { out -> record(meta: out.meta, reads: out.reads.toList().toSorted { a, b -> a.name <=> b.name }) } // record(meta, reads)
    multiqc_files = fastp.map { out -> out.json }

}

output {
    fastp        : Channel<Record> { path 'fastp' }
    trimmed_reads: Channel<Record> { path 'trimmed_reads' }
    multiqc_files: Channel<Path> { path 'multiqc_files' }
}
