nextflow.enable.types = true

//
// MultiQC report and software versions of the pipeline
//

include { MULTIQC                } from '../../../modules/nf-core/multiqc/main'
include { workflowVersionToYAML  } from '../../nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../utils_nfcore_biovat_pipeline'
include { versionEntryToLine     } from '../utils_nfcore_biovat_pipeline'

workflow MULTIQC_REPORT {

    take:
    multiqc_files              : Channel<Path> // files to report on
    multiqc_config             : Path?         // MultiQC config file
    multiqc_logo               : Path?         // MultiQC logo
    multiqc_title              : String?       // MultiQC report title
    multiqc_methods_description: Path?         // MultiQC methods description template
    workflow_summary           : String        // MultiQC-formatted summary of the pipeline parameters

    main:
    // Collate software versions from the versions topic
    versions_strings = (channel.topic('versions') as Channel<Record>)
        .unique()
        .map { entry -> versionEntryToLine(entry) }
        .groupBy()
        .map { process, tool_versions -> "${process}:\n${tool_versions.toSet().toList().toSorted().join('\n')}" }
        .mix(channel.of(workflowVersionToYAML()))
    versions = versions_strings.collectFile(name: 'biovat_software_mqc_versions.yml', sort: true, newLine: true)

    // MultiQC
    config              = multiqc_config ?: file("${moduleDir}/../../../assets/multiqc_config.yml", checkIfExists: true)
    methods_description = methodsDescriptionText(
        multiqc_methods_description ?: file("${moduleDir}/../../../assets/biovat_methods_description.yml", checkIfExists: true)
    )
    summary_files = channel.of(workflow_summary).collectFile(name: 'workflow_summary_mqc.yaml')
        .mix(channel.of(methods_description).collectFile(name: 'methods_description_mqc.yaml'))
    multiqc = MULTIQC(
        multiqc_files
            .mix(versions)
            .mix(summary_files)
            .collect()
            .map { files ->
                record(
                    id            : 'biovat',
                    meta          : null,
                    multiqc_files : files,
                    multiqc_config: [ config ],
                    multiqc_logo  : multiqc_logo,
                    replace_names : null,
                    sample_names  : null,
                    multiqc_args  : multiqc_title ? "--title \"${multiqc_title}\"" : null,
                    output_prefix : null
                )
            }
    )

    emit:
    multiqc : Value<Record> = multiqc.map { out -> record(meta: out.meta, report: out.report, data: out.data, plots: out.plots) }
    versions: Channel<Path> = versions
}
