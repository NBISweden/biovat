//
// Raw read QC subworkflow
//

include { FASTQC as FASTQC_RAW     } from '../../../modules/nf-core/fastqc/main'
include { FASTP as FASTP_REPORT } from '../../../modules/nf-core/fastp/main'

workflow RAW_READ_QC {

    take:
    ch_reads_and_adapters     // channel: [ val(meta), path(reads), path(adapter_fasta) ]
    fastp_report // value: boolean

    main:
    // FastQC of raw reads
    // Remove adapter_fasta from input channel
    ch_reads = ch_reads_and_adapters.map { meta, reads, _adapter_fasta -> [ meta, reads ] }
    FASTQC_RAW (
        ch_reads
    )

    ch_fastp_json = Channel.empty()
    if (fastp_report) {
        // Create a fastp output report without running the trimming
        FASTP_REPORT (
            ch_reads_and_adapters,
            true, // discard_trimmed_pass must be set to true if only a report should be produced
            false,
            false
        )
        ch_fastp_json = FASTP_REPORT.out.json
    }

    emit:
    fastqc_html  = FASTQC_RAW.out.html             // channel: [ val(meta), path(html) ]
    fastqc_zip   = FASTQC_RAW.out.zip              // channel: [ val(meta), path(zip) ]
    fastp_json   = ch_fastp_json                   // channel: [ val(meta), path(json) ]

}
