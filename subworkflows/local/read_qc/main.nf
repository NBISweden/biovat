//
// Read QC subworkflow
//

include { FASTQC as FASTQC  } from '../../../modules/nf-core/fastqc/main'

workflow READ_QC {

    take:
    ch_reads // channel: [ val(meta), path(reads) ]

    main:
    // FastQC of raw reads
    FASTQC (
        ch_reads
    )

    emit:
    fastqc_html  = FASTQC.out.html             // channel: [ val(meta), path(html) ]
    fastqc_zip   = FASTQC.out.zip              // channel: [ val(meta), path(zip) ]

}
