//
// Raw read QC subworkflow
//

include { FASTQC as FASTQC_RAW  } from '../../../modules/nf-core/fastqc/main'

//
// Function that parses fastp json output file to get total number of reads after trimming
//

def getFastpReadsAfterFiltering(json_file ) {

    if ( workflow.stubRun ) { return 1 }

    def json = new groovy.json.JsonSlurper().parseText(json_file.text).get('summary')
    return json['after_filtering']['total_reads'].toLong()
}

workflow READ_QC {

    take:
    ch_reads            // channel: [ val(meta), path(reads), path(adapter_fasta) ]
    trimmed_reads       // channel: [ val(meta), path(reads) ]
    steps               // string: Comma-separated list of steps (subworkflows) to run

    main:

    // Requested workflow steps
    def workflow_steps = steps.tokenize(",")

    // FastQC of raw reads
    // Split input channel for reads-only operations
    ch_reads_only = ch_reads.map { meta, reads, _adapter_fasta -> [ meta, reads ] }

    FASTQC_RAW (
        ch_reads_only
    )
    ch_fastqc_raw_html = FASTQC_RAW.out.html
    ch_fastqc_raw_zip  = FASTQC_RAW.out.zip

    if ( 'trim' in workflow_steps ) {
        FASTQC_TRIM (
            trimmed_reads
        )
        ch_fastqc_trim_html = FASTQC_TRIM.out.html
        ch_fastqc_trim_zip  = FASTQC_TRIM.out.zip

        // FastP for statistics on raw reads if trimming not run
        FASTP_STATS (
            ch_reads,
            true,
            false,
            false
        )
        ch_trim_stats_json   = FASTP_STATS.out.json
        ch_trim_stats_html   = FASTP_STATS.out.html
        ch_trim_stats_log    = FASTP_STATS.out.log
    }

    emit:
    fastqc_raw_html  = ch_fastqc_raw_html    // channel: [ val(meta), path(html) ]
    fastqc_raw_zip   = ch_fastqc_raw_zip     // channel: [ val(meta), path(zip) ]
    fastqc_trim_html = ch_fastqc_trim_html   // channel: [ val(meta), path(html) ]
    fastqc_trim_zip  = ch_fastqc_trim_zip    // channel: [ val(meta), path(zip) ]
    trim_stats_json  = ch_trim_stats_json    // channel: [ val(meta), path(json) ]
    trim_stats_html  = ch_trim_stats_html    // channel: [ val(meta), path(html) ]
    trim_stats_log   = ch_trim_stats_log     // channel: [ val(meta), path(log) ]
}