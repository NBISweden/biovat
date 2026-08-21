//
// Read trimming subworkflow
//

include { FASTP } from '../../../modules/nf-core/fastp/main'

workflow TRIM_READS {

    take:
    ch_reads                 // channel: [ val(meta), path(reads), path(adapter_fasta) ]
    val_save_trimmed_fail    // Save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
    val_save_merged          // Save all merged reads to a file ending in *.merged.fastq.gz

    main:
    // Run fastp for read trimming
    FASTP (
        ch_reads,
        false,                 // Never write any reads that pass trimming thresholds. This can be used to use fastp for the output report only
        val_save_trimmed_fail, // Whether to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
        val_save_merged        // Whether to save all merged reads to a file ending in *.merged.fastq.gz
    )

    emit:
    trimmed_reads        = FASTP.out.reads         // channel: [ val(meta), path(reads) ]
    fastp_json           = FASTP.out.json          // channel: [ val(meta), path(json) ]
    fastp_html           = FASTP.out.html          // channel: [ val(meta), path(html) ]
    fastp_log            = FASTP.out.log           // channel: [ val(meta), path(log) ]
    trimmed_reads_fail   = FASTP.out.reads_fail    // channel: [ val(meta), path(fastq.gz) ]
    trimmed_reads_merged = FASTP.out.reads_merged  // channel: [ val(meta), path(fastq.gz) ]

}
