//
// Read trimming subworkflow
//

include { FASTP } from '../../../modules/nf-core/fastp/main'

workflow TRIM_READS {
    take:
    ch_reads // channel: [ val(meta), path(reads), path(adapter_fasta) ]
    enable // map: stage/tool gating flags

    main:
    // Run fastp for read trimming
    fastp_out = FASTP(
        ch_reads,
        false,
        enable.save_trimmed_fail,
        enable.save_merged,
    )

    emit:
    trimmed_reads        = fastp_out.reads // channel: [ val(meta), path(reads) ]
    fastp_json           = fastp_out.json // channel: [ val(meta), path(json) ]
    fastp_html           = fastp_out.html // channel: [ val(meta), path(html) ]
    fastp_log            = fastp_out.log // channel: [ val(meta), path(log) ]
    trimmed_reads_fail   = fastp_out.reads_fail // channel: [ val(meta), path(fastq.gz) ]
    trimmed_reads_merged = fastp_out.reads_merged // channel: [ val(meta), path(fastq.gz) ]
}
