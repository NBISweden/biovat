//
// Read trimming subworkflow
//

include { FASTP } from '../../../modules/nf-core/fastp/main'

workflow TRIM_READS {

    take:
    ch_reads                 // channel: [ val(meta), path(reads), path(adapter_fasta) ]
    val_discard_trimmed_pass // Do not write any reads that pass trimming thresholds. This can be used to use fastp for the output report only
    val_save_trimmed_fail    // Save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
    val_save_merged          // Save all merged reads to a file ending in *.merged.fastq.gz

    main:
    // Run fastp for read trimming
    FASTP (
        ch_reads,
        val_discard_trimmed_pass, // Do not write any reads that pass trimming thresholds. This can be used to use fastp for the output report only
        val_save_trimmed_fail, // Save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
        val_save_merged  // Save all merged reads to a file ending in *.merged.fastq.gz
    )

    emit:
    fastq        = FASTP.out.reads
    json         = FASTP.out.json
    html         = FASTP.out.html
    trim_log     = FASTP.out.log
    reads_fail   = FASTP.out.reads_fail
    reads_merged = FASTP.out.reads_merged
}
