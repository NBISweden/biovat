//
// Read QC subworkflow
//

include { FASTQC } from '../../../modules/nf-core/fastqc/main'

workflow READ_QC {
    take:
    ch_reads // channel: [ val(meta), path(reads), path(adapter_fasta) ]

    main:
    fastqc_out = FASTQC(
        ch_reads
    )

    emit:
    fastqc_html = fastqc_out.html // channel: [ val(meta), path(html) ]
    fastqc_zip  = fastqc_out.zip // channel: [ val(meta), path(zip) ]
}
