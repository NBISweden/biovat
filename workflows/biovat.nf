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
include { REFERENCE_UTILS             } from '../subworkflows/local/utils_reference'
include { READ_QC                     } from '../subworkflows/local/read_qc/main'
include { TRIM_READS                  } from '../subworkflows/local/trim_reads/main'
include { ALIGN_READS                 } from '../subworkflows/local/align_reads/main'
include { BAM_QC                      } from '../subworkflows/local/bam_qc/main'

workflow BIOVAT {

    take:
    ch_samplesheet         // channel: samplesheet read in from --input
    reference              // channel: reference fasta read in from --reference
    enable_raw_read_qc     // boolean: Whether to run quality checks on raw reads
    enable_trim            // boolean: Whether to run the trimming stage
    enable_align           // boolean: Whether to run the alignment stage
    enable_bam_qc          // boolean: Whether to run quality checks on BAM files
    adapter_fasta          // channel: adapter fasta file read in from --adapter_fasta
    save_trimmed_fail      // boolean: Whether to save files that failed to pass trimming thresholds ending in *.fail.fastq.gz
    save_merged            // boolean: Whether to save all merged reads to a file ending in *.merged.fastq.gz
    aligner                // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    sort_bam               // boolean: Whether to sort the output BAM file
    enable_riker           // boolean: Whether to run RIKER for BAM QC
    enable_qualimap        // boolean: Whether to run QUALIMAP for BAM QC
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:
    def ch_versions         = channel.empty()
    def ch_multiqc_files    = channel.empty()
    reads_to_process        = ch_samplesheet

    // Reference utilities
    ch_reference_and_fai    = channel.empty()
    if ( params.reference && enable_align ) {
        REFERENCE_UTILS(reference)
        ch_reference_and_fai = REFERENCE_UTILS.out.ch_reference_and_fai
    }

    // Raw read quality checks
    outputs_raw_read_qc     = channel.empty()
    if ( enable_raw_read_qc ) {
        READ_QC (
            reads_to_process,
        )
        ch_multiqc_files    = ch_multiqc_files.mix(READ_QC.out.fastqc_zip.map{ _meta, file -> file })
        outputs_raw_read_qc = READ_QC.out.fastqc_zip.mix(READ_QC.out.fastqc_html)
    }

    // Trim reads
    outputs_trim_reads      = channel.empty()
    if ( enable_trim ) {
        // FASTP takes reads + adapters (if provided)
        def path_adapter_fasta    = adapter_fasta ? file(adapter_fasta, checkIfExists: true) : []
        def ch_reads_and_adapters = reads_to_process
            .map { meta, reads -> [ meta, reads, path_adapter_fasta ] }
        // FASTP
        TRIM_READS (
            ch_reads_and_adapters,
            save_trimmed_fail,
            save_merged
        )
        reads_to_process    = TRIM_READS.out.trimmed_reads
        ch_multiqc_files    = ch_multiqc_files.mix(TRIM_READS.out.fastp_json.map{ _meta, file -> file })
        outputs_trim_reads  = TRIM_READS.out.mix()
    }

    // Align reads
    outputs_align_reads      = channel.empty()
    outputs_library_flagstat = channel.empty()
    outputs_library_riker    = channel.empty()
    outputs_library_qualimap = channel.empty()
    if ( enable_align ) {
        ALIGN_READS (
            aligner,
            ch_reference_and_fai,
            reads_to_process,
            sort_bam,
            enable_bam_qc,
            enable_riker,
            enable_qualimap,
            ch_multiqc_files
        )
        ch_alignment_and_index   = ALIGN_READS.out.ch_alignment_and_index
        ch_multiqc_files         = ALIGN_READS.out.ch_multiqc_files
        outputs_align_reads      = ALIGN_READS.out.ch_alignment_and_index
        outputs_library_flagstat = ALIGN_READS.out.outputs_library_flagstat
        outputs_library_riker    = ALIGN_READS.out.outputs_library_riker
        outputs_library_qualimap = ALIGN_READS.out.outputs_library_qualimap
    }

    // Collate and save software versions
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

    // MultiQC
    ch_multiqc_files                          = ch_multiqc_files.mix(ch_collated_versions)
    def ch_summary_params                     = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    def ch_workflow_summary                   = channel.value(paramsSummaryMultiqc(ch_summary_params))
    ch_multiqc_files                          = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    def ch_multiqc_custom_methods_description = multiqc_methods_description
        ? file(multiqc_methods_description, checkIfExists: true)
        : file("${projectDir}/assets/biovat_methods_description.yml", checkIfExists: true)
    def ch_methods_description                = channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files                          = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: true))
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
    outputs_multiqc = MULTIQC.out.report
        .mix(MULTIQC.out.data)
        .mix(MULTIQC.out.plots)

    emit:
    outputs_raw_read_qc      = outputs_raw_read_qc
    outputs_trim_reads       = outputs_trim_reads
    outputs_align_reads      = outputs_align_reads
    outputs_library_flagstat = outputs_library_flagstat
    outputs_library_riker    = outputs_library_riker
    outputs_library_qualimap = outputs_library_qualimap
    outputs_multiqc          = outputs_multiqc

}
