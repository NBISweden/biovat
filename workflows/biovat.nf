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
include { REFERENCE_UTILS        } from '../subworkflows/local/utils_reference'
include { READ_QC                } from '../subworkflows/local/read_qc/main'
include { TRIM_READS             } from '../subworkflows/local/trim_reads/main'
include { ALIGN_READS            } from '../subworkflows/local/align_reads/main'
include { MERGE_LIBRARIES        } from '../subworkflows/local/merge_libraries/main'

workflow BIOVAT {

    take:
    ch_samplesheet         // channel: samplesheet read in from --input
    reference              // channel: reference fasta read in from --reference
    enable                 // map: gating flags
    adapter_fasta          // channel: adapter fasta file read in from --adapter_fasta
    aligner                // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    multiqc_config
    multiqc_logo
    multiqc_methods_description
    outdir

    main:
    def ch_versions      = channel.empty()
    def ch_multiqc_files = channel.empty()
    reads_to_process     = ch_samplesheet

    // Reference utilities
    ch_reference_and_fai = channel.empty()
    // TODO: temporarily enabled if a reference is provided...
    // This should be replaced with better logic to handle cases where it is not required
    if ( params.reference ) {
        REFERENCE_UTILS(
            reference
        )
        ch_reference_and_fai = REFERENCE_UTILS.out.ch_reference_and_fai
    }

    // Raw read quality checks
    outputs_raw_read_qc = channel.empty()
    if ( enable.raw_read_qc ) {
        READ_QC(
            reads_to_process
        )
        ch_multiqc_files    = ch_multiqc_files.mix(READ_QC.out.fastqc_zip.map { _meta, file -> file })
        outputs_raw_read_qc = READ_QC.out.fastqc_zip.mix(READ_QC.out.fastqc_html)
    }

    // Trim reads
    outputs_trim_reads = channel.empty()
    if ( enable.trim ) {
        // FASTP takes reads + adapters (if provided)
        def path_adapter_fasta    = adapter_fasta ? file(adapter_fasta, checkIfExists: true) : []
        def ch_reads_and_adapters = reads_to_process.map { meta, reads -> [meta, reads, path_adapter_fasta] }
        // FASTP
        TRIM_READS(
            ch_reads_and_adapters,
            enable
        )
        reads_to_process   = TRIM_READS.out.trimmed_reads
        ch_multiqc_files   = ch_multiqc_files.mix(TRIM_READS.out.fastp_json.map { _meta, file -> file })
        outputs_trim_reads = TRIM_READS.out.mix()
    }

    // Align reads
    ch_library_alignments_indexed = channel.empty()
    outputs_library_alignments    = channel.empty()
    outputs_library_flagstat      = channel.empty()
    outputs_library_riker         = channel.empty()
    outputs_library_qualimap      = channel.empty()
    if ( enable.align ) {
        ALIGN_READS(
            aligner,
            ch_reference_and_fai,
            reads_to_process,
            enable,
            ch_multiqc_files
        )
        ch_library_alignments_indexed = ALIGN_READS.out.ch_library_alignments_indexed
        ch_multiqc_files              = ALIGN_READS.out.ch_multiqc_files
        outputs_library_alignments    = ch_library_alignments_indexed
        outputs_library_flagstat      = ALIGN_READS.out.outputs_library_flagstat
        outputs_library_riker         = ALIGN_READS.out.outputs_library_riker
        outputs_library_qualimap      = ALIGN_READS.out.outputs_library_qualimap
    }

    // Merge sample alignments
    ch_sample_alignments_indexed = channel.empty()
    outputs_sample_flagstat      = channel.empty()
    outputs_sample_riker         = channel.empty()
    outputs_sample_qualimap      = channel.empty()
    if ( enable.merge ) {
        MERGE_LIBRARIES(
            ch_library_alignments_indexed,
            ch_reference_and_fai,
            enable,
            ch_multiqc_files
        )
        ch_sample_alignments_indexed = MERGE_LIBRARIES.out.ch_sample_alignments_indexed
        ch_multiqc_files             = MERGE_LIBRARIES.out.ch_multiqc_files
        outputs_sample_alignments    = ch_sample_alignments_indexed
        outputs_sample_flagstat      = MERGE_LIBRARIES.out.outputs_sample_flagstat
        outputs_sample_riker         = MERGE_LIBRARIES.out.outputs_sample_riker
        outputs_sample_qualimap      = MERGE_LIBRARIES.out.outputs_sample_qualimap
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
    outputs_raw_read_qc        = outputs_raw_read_qc
    outputs_trim_reads         = outputs_trim_reads
    outputs_library_alignments = outputs_library_alignments
    outputs_library_flagstat   = outputs_library_flagstat
    outputs_library_riker      = outputs_library_riker
    outputs_library_qualimap   = outputs_library_qualimap
    outputs_sample_alignments  = outputs_sample_alignments
    outputs_sample_flagstat    = outputs_sample_flagstat
    outputs_sample_riker       = outputs_sample_riker
    outputs_sample_qualimap    = outputs_sample_qualimap
    outputs_multiqc            = outputs_multiqc

}
