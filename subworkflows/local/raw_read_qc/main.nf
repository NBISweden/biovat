//
// Raw read QC subworkflow
//

include { FASTQC as FASTQC_RAW } from '../../../modules/nf-core/fastqc/main'

workflow RAW_READ_QC {
    take:
    ch_reads // channel: [ val(meta), path(reads), path(adapter_fasta) ]

    main:
    FASTQC_RAW(
        ch_reads
    )

    emit:
    fastqc_html = FASTQC_RAW.out.html // channel: [ val(meta), path(html) ]
    fastqc_zip  = FASTQC_RAW.out.zip // channel: [ val(meta), path(zip) ]
}
