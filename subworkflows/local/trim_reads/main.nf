//
// Read trimming subworkflow
//

include { FASTP } from '../../../modules/nf-core/fastp/main'

workflow TRIM_READS {

    take:
    ch_reads // channel: [ val(meta), path(reads), path(adapter_fasta) ]

    main:
    // Run fastp for read trimming
    FASTP (
        ch_reads,
        false, // discard_trimmed_pass: specify true to not write any reads that pass trimming thresholds. This can be used to use fastp for the output report only.
        false, // save_trimmed_fail: specify true to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
        false  // save_merged: specify true to save all merged reads to a file ending in *.merged.fastq.gz
    )

    emit:
    trimmed_reads        = FASTP.out.reads         // channel: [ val(meta), path(reads) ]
    trimmed_json         = FASTP.out.json          // channel: [ val(meta), path(json) ]
    trimmed_html         = FASTP.out.html          // channel: [ val(meta), path(html) ]
    trimmed_log          = FASTP.out.log           // channel: [ val(meta), path(log) ]
    trimmed_reads_merged = FASTP.out.reads_merged  // channel: [ val(meta), path(fastq.gz) ]

}
