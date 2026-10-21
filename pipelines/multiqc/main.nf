nextflow.enable.types = true

//
// MultiQC and software versions pipeline
//

include { MULTIQC                } from '../../modules/nf-core/multiqc/main'
include { STAGE_HELP             } from '../../subworkflows/local/utils_stage_help/main'
include { workflowVersionToYAML  } from '../../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'
include { versionEntryToLine     } from '../../subworkflows/local/utils_nfcore_biovat_pipeline'

record QcFile {
    file: Path // a file to report on
}

params {
    multiqc_files              : Channel<QcFile>? // files to report on, from a samplesheet file (CSV, JSON or YAML) or a calling pipeline
    multiqc_config             : Path?            // MultiQC config file
    multiqc_logo               : Path?            // MultiQC logo
    multiqc_title              : String?          // MultiQC report title
    multiqc_methods_description: Path?            // MultiQC methods description template
    workflow_summary           : String = ''      // MultiQC-formatted summary of the pipeline parameters
    help                       : Boolean = false
    help_full                  : Boolean = false
}

workflow {

    main:
    STAGE_HELP(params.help, params.help_full, "${moduleDir}/nextflow_schema.json", 'nextflow run pipelines/multiqc --multiqc_files files.yml')
    if ( !params.multiqc_files ) {
        error "Missing required parameter --multiqc_files"
    }

    // Collate software versions from the versions topic
    versions_strings = (channel.topic('versions') as Channel<Record>)
        .unique()
        .map { entry -> versionEntryToLine(entry) }
        .groupBy()
        .map { process, tool_versions -> "${process}:\n${tool_versions.toSet().toList().toSorted().join('\n')}" }
        .mix(channel.of(workflowVersionToYAML()))
    versions = versions_strings.collectFile(name: 'biovat_software_mqc_versions.yml', sort: true, newLine: true)

    // MultiQC
    multiqc_config      = params.multiqc_config ?: file("${moduleDir}/../../assets/multiqc_config.yml", checkIfExists: true)
    methods_description = methodsDescriptionText(
        params.multiqc_methods_description ?: file("${moduleDir}/../../assets/biovat_methods_description.yml", checkIfExists: true)
    )
    summary_files = channel.of(params.workflow_summary).collectFile(name: 'workflow_summary_mqc.yaml')
        .mix(channel.of(methods_description).collectFile(name: 'methods_description_mqc.yaml'))
    multiqc = MULTIQC(
        params.multiqc_files
            .map { qc -> qc.file }
            .mix(versions)
            .mix(summary_files)
            .collect()
            .map { files ->
                record(
                    id            : 'biovat',
                    meta          : null,
                    multiqc_files : files,
                    multiqc_config: [ multiqc_config ],
                    multiqc_logo  : params.multiqc_logo,
                    replace_names : null,
                    sample_names  : null,
                    multiqc_args  : params.multiqc_title ? "--title \"${params.multiqc_title}\"" : null,
                    output_prefix : null
                )
            }
    )

    publish:
    multiqc  = multiqc.map { out -> record(meta: out.meta, report: out.report, data: out.data, plots: out.plots) }
    versions = versions

}

output {
    multiqc : Value<Record> { path 'multiqc' }
    versions: Channel<Path> { path 'pipeline_info' }
}
