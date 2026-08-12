//
// Raw read QC subworkflow
//

include { FASTQC  } from '../../../modules/nf-core/fastqc/main'
include { MULTIQC } from '../../../modules/nf-core/multiqc/main'

workflow RAW_READS_QC {

    take:
    ch_reads            // channel: [ val(meta), path(reads) ]
    multiqc_config
    multiqc_logo

    main:

    // FastQC of raw reads
    FASTQC (
        ch_reads
    )

    // Run MultiQC on FastQC output
    def ch_multiqc_files = channel.empty().mix(FASTQC.out.zip.map{ _meta, file -> file })
    MULTIQC (
        ch_multiqc_files.collect().map { files ->
            [
                [id: 'raw_reads_qc'],
                files,
                multiqc_config
                    ? file(multiqc_config, checkIfExists: true)
                    : file("${projectDir}/assets/multiqc_config.yml", checkIfExists: true),
                multiqc_logo ? file(multiqc_logo, checkIfExists: true) : [],
                [],
                [],
            ]
        }
    )

    emit:
    fastqc_raw_html  = FASTQC.out.html             // channel: [ val(meta), path(html) ]
    fastqc_raw_zip   = FASTQC.out.zip              // channel: [ val(meta), path(zip) ]
    multiqc_report   = MULTIQC.out.report.toList() // channel: [ val(meta), path(report) ]

}