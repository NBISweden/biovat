/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-schema'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_biovat_pipeline'
include { RAW_READS_QC           } from '../subworkflows/local/raw_reads_qc/main'
include { TRIM_READS             } from '../subworkflows/local/trim_reads/main'
include { ALIGN_READS            } from '../subworkflows/local/align_reads/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow BIOVAT {

    take:
    ch_samplesheet           // channel: samplesheet read in from --input
    adapter_fasta            // channel: adapter fasta file read in from --adapter_fasta
    val_discard_trimmed_pass // boolean: Whether to write any reads that pass trimming thresholds. This can be used to use fastp for the output report only
    val_save_trimmed_fail    // boolean: Whether to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
    val_save_merged          // boolean: Whether to save all merged reads to a file ending in *.merged.fastq.gz
    reference                // channel: reference fasta read in from --reference
    steps                    // string: Comma-separated list of steps (subworkflows) to run
    align_raw_reads          // boolean: Whether to align raw reads (true) or trimmed reads (false)
    sort_bam                 // boolean: Whether to sort the output BAM file
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    // Requested workflow steps
    workflow_steps = steps.tokenize(",")

    def ch_versions = channel.empty()
    def ch_multiqc_files = channel.empty()

    // Raw reads quality checks
    if ('read_qc' in workflow_steps) {
        RAW_READS_QC (
            ch_samplesheet,
            multiqc_config,
            multiqc_logo
        )
        ch_multiqc_files = ch_multiqc_files.mix(RAW_READS_QC.out.fastqc_raw_zip.map{ _meta, file -> file })
    }

    def trimmed_reads = channel.empty()

    // Trim reads
    if ( 'trim' in workflow_steps ) {
        // Create ch_reads from ch_samplesheet and adapter_fasta for TRIM_READS subworkflow
        // channel: [ val(meta), path(reads), path(adapter_fasta) ]
        def ch_adapter_fasta = adapter_fasta ? file(adapter_fasta, checkIfExists: true) : []
        def ch_reads = ch_samplesheet
            .map { meta, reads -> [ meta, reads, ch_adapter_fasta ] }

        // FASTP
        TRIM_READS (
            ch_reads,
            val_discard_trimmed_pass,
            val_save_trimmed_fail,
            val_save_merged
        )
        trimmed_reads = TRIM_READS.out.trimmed_reads
    }

    // Align reads (raw or trimmed)
    if ( 'align' in workflow_steps ) {
        ALIGN_READS (
            reference,
            trimmed_reads,
            ch_samplesheet,
            align_raw_reads,
            sort_bam
        )
        aligned_reads       = ALIGN_READS.out.aligned_reads
        aligned_reads_index = ALIGN_READS.out.aligned_reads_index
    }

    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    def ch_collated_versions = softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${outdir}/pipeline_info",
            name:  'biovat_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        )

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/biovat_methods_description.yml", checkIfExists: true)
    def ch_methods_description = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
    MULTIQC(
        ch_multiqc_files.flatten().collect().map { files ->
            [
                [id: 'biovat'],
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
    emit:multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
