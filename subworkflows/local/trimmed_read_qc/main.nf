//
// Raw read QC subworkflow
//

include { FASTQC as FASTQC_TRIMMED     } from '../../../modules/nf-core/fastqc/main'

workflow TRIMMED_READ_QC {

    take:
    ch_reads        // channel: [ val(meta), path(reads) ]

    main:
    // FastQC of raw reads
    FASTQC_TRIMMED (
        ch_reads
    )

    emit:
    fastqc_html  = FASTQC_TRIMMED.out.html             // channel: [ val(meta), path(html) ]
    fastqc_zip   = FASTQC_TRIMMED.out.zip              // channel: [ val(meta), path(zip) ]

}
