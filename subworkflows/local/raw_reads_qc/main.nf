//
// Raw read QC subworkflow
//

include { FASTQC as FASTQC_RAW  } from '../../../modules/nf-core/fastqc/main'

workflow RAW_READS_QC {

    take:
    ch_reads // channel: [ val(meta), path(reads) ]

    main:
    // FastQC of raw reads
    FASTQC_RAW (
        ch_reads
    )

    emit:
    fastqc_raw_html  = FASTQC_RAW.out.html             // channel: [ val(meta), path(html) ]
    fastqc_raw_zip   = FASTQC_RAW.out.zip              // channel: [ val(meta), path(zip) ]

}
