//
// Raw read QC subworkflow
//

include { FASTQC as FASTQC_RAW     } from '../../../modules/nf-core/fastqc/main'
include { FASTP as FASTP_QC_REPORT } from '../../../modules/nf-core/fastp/main'

workflow RAW_READ_QC {

    take:
    ch_reads        // channel: [ val(meta), path(reads) ]
    fastp_qc_report // value: boolean

    main:
    // FastQC of raw reads
    FASTQC_RAW (
        ch_reads
    )

    // If fastp_qc_report, run fastP for output report
    if (fastp_qc_report) {
        FASTP_QC_REPORT (
            ch_reads,
            true, // discard_trimmed_pass must be set to true if only a report should be produced
            false,
            false
        )
    }

    emit:
    fastqc_html  = FASTQC_RAW.out.html             // channel: [ val(meta), path(html) ]
    fastqc_zip   = FASTQC_RAW.out.zip              // channel: [ val(meta), path(zip) ]
    trimmed_json = FASTP_QC_REPORT.out.trimmed_json

}
