//
// Raw read QC subworkflow
//

include { FASTQC  } from '../../../modules/nf-core/fastqc/main'

workflow RAW_READS_QC {

    take:
    ch_reads // channel: [ val(meta), path(reads) ]

    main:
    // FastQC of raw reads
    FASTQC (
        ch_reads
    )

    emit:
    fastqc_raw_html  = FASTQC.out.html             // channel: [ val(meta), path(html) ]
    fastqc_raw_zip   = FASTQC.out.zip              // channel: [ val(meta), path(zip) ]

}