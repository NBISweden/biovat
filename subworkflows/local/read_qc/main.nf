//
// Read QC subworkflow
//

include { FASTQC } from '../../../modules/nf-core/fastqc/main'

workflow READ_QC {
    take:
    ch_reads // channel: [ val(meta), path(reads), path(adapter_fasta) ]

    main:
    FASTQC(
        ch_reads
    )

    emit:
    fastqc_html = FASTQC.out.html // channel: [ val(meta), path(html) ]
    fastqc_zip  = FASTQC.out.zip // channel: [ val(meta), path(zip) ]
}
