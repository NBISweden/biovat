//
// Trimmed read QC subworkflow
//

include { FASTQC as FASTQC_TRIMMED  } from '../../../modules/nf-core/fastqc/main'

//
// Function that parses fastp json output file to get total number of reads after trimming
//

def getFastpReadsAfterFiltering(json_file ) {

    if ( workflow.stubRun ) { return 1 }

    def json = new groovy.json.JsonSlurper().parseText(json_file.text).get('summary')
    return json['after_filtering']['total_reads'].toLong()
}

workflow TRIMMED_READS_QC {

    take:
    trimmed_reads  // channel: [ val(meta), path(reads) ]

    main:
    // Run FastQC on the trimmed reads
    FASTQC_TRIMMED (
        trimmed_reads
    )
    ch_fastqc_trimmed_html = FASTQC_TRIMMED.out.html
    ch_fastqc_trimmed_zip  = FASTQC_TRIMMED.out.zip

    emit:
    fastqc_trimmed_html = ch_fastqc_trimmed_html   // channel: [ val(meta), path(html) ]
    fastqc_trimmed_zip  = ch_fastqc_trimmed_zip    // channel: [ val(meta), path(zip) ]

}
