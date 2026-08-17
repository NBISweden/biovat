/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                     } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap            } from 'plugin/nf-schema'
include { paramsSummaryMultiqc        } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML      } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText      } from '../subworkflows/local/utils_nfcore_biovat_pipeline'
include { RAW_READ_QC                 } from '../subworkflows/local/raw_read_qc/main'
include { TRIM_READS                  } from '../subworkflows/local/trim_reads/main'
include { TRIMMED_READ_QC             } from '../subworkflows/local/enable_trimmed_read_qc/main'
include { ALIGN_READS                 } from '../subworkflows/local/align_reads/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow BIOVAT {

    take:
    ch_samplesheet         // channel: samplesheet read in from --input
    reference              // channel: reference fasta read in from --reference
    enable_raw_read_qc     // boolean: Whether to run quality checks on raw reads
    enable_trim            // boolean: Whether to run the trimming stage
    enable_trimmed_read_qc // boolean: Whether to run quality checks on trimmed reads
    enable_align           // boolean: Whether to run the alignment stage
    adapter_fasta          // channel: adapter fasta file read in from --adapter_fasta
    fastp_report           // boolean: Run FastP to generate an output report even when trimming is disabled
    save_trimmed_fail      // boolean: Whether to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
    save_merged            // boolean: Whether to save all merged reads to a file ending in *.merged.fastq.gz
    aligner                // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    sort_bam               // boolean: Whether to sort the output BAM file
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:

    def ch_versions      = channel.empty()
    def ch_multiqc_files = channel.empty()
    reads_to_process     = ch_samplesheet      // Initialise reads_to_process channel with raw reads

    // If adapter path provided, add to reads for FASTP module
    def path_adapter_fasta = adapter_fasta ? file(adapter_fasta, checkIfExists: true) : []
    def ch_reads_and_adapters = reads_to_process
        .map { meta, reads -> [ meta, reads, path_adapter_fasta ] }

    // Raw read quality checks
    if ( enable_raw_read_qc ) {
        RAW_READ_QC (
            reads_to_process,
            fastp_report
        )
        ch_multiqc_files = ch_multiqc_files.mix(RAW_READ_QC.out.fastqc_zip.map{ _meta, file -> file })

        // Run FASTP but only produce a report, do not write trimmed reads to file
        // TODO: If fastp_report and enable_trim are set to true, FASTP is run twice.
        //       Implement a check so that it can only be run once here, with nf-schema
        //       or in utils_nfcore_biovat_pipeline.
        if (fastp_report) {
            ch_multiqc_files = ch_multiqc_files.mix(RAW_READ_QC.out.trimmed_json.map{ _meta, file -> file })
        }
    }

    // Trim reads
    if ( enable_trim ) {
        // FASTP
        TRIM_READS (
            ch_reads_and_adapters,
            false, // discard_trimmed_pass must be false when running read trimming
            save_trimmed_fail,
            save_merged
        )
        reads_to_process = TRIM_READS.out.trimmed_reads

        // Trimmed read quality checks
        if ( enable_trimmed_read_qc ) {
            TRIMMED_READ_QC (
                reads_to_process
            )
            ch_multiqc_files = ch_multiqc_files.mix(TRIM_READS.out.trimmed_json.map{ _meta, file -> file })
            ch_multiqc_files = ch_multiqc_files.mix(TRIMMED_READS_QC.out.fastqc_zip.map{ _meta, file -> file })
        }
    }

    // Align reads
    if ( enable_align ) {
        ALIGN_READS (
            aligner,
            reference,
            reads_to_process,
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

    emit:
    multiqc_report = MULTIQC.out.report.map { _meta, report -> [report] }.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                                                   // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
