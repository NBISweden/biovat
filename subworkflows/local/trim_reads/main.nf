//
// Read trimming subworkflow
//

include { FASTP } from '../../../modules/nf-core/fastp/main'

workflow TRIM_READS {

    take:
    ch_reads                 // channel: [ val(meta), path(reads), path(adapter_fasta) ]
    val_discard_trimmed_pass // value: boolean
    val_save_trimmed_fail    // value: boolean
    val_save_merged          // value: boolean

    main:
    // Run fastp for read trimming
    FASTP (
        ch_reads,
        val_discard_trimmed_pass,
        val_save_trimmed_fail,
        val_save_merged
    )

    emit:
    trimmed_reads        = FASTP.out.reads         // channel: [ val(meta), path(reads) ]
    trimmed_json         = FASTP.out.json          // channel: [ val(meta), path(json) ]
    trimmed_html         = FASTP.out.html          // channel: [ val(meta), path(html) ]
    trimmed_log          = FASTP.out.log           // channel: [ val(meta), path(log) ]
    trimmed_reads_fail   = FASTP.out.reads_fail    // channel: [ val(meta), path(fastq.gz) ]
    trimmed_reads_merged = FASTP.out.reads_merged  // channel: [ val(meta), path(fastq.gz) ]

}
