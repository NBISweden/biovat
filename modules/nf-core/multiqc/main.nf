nextflow.enable.types = true

process MULTIQC {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/c8/c8e346f4f6080eadf1253505e6ff09ef004454fc18e8d672006fd7b222cc412e/data'
        : 'community.wave.seqera.io/library/multiqc:1.35--c17fb751507e9dfc'}"

    ext [
        prefix: { output_prefix ?: '' },
        args: { multiqc_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        multiqc_files: Bag<Path>,
        multiqc_config: List<Path>?,
        multiqc_logo: Path?,
        replace_names: Path?,
        sample_names: Path?,
        multiqc_args: String?,
        output_prefix: String?
    )

    stage:
    stageAs multiqc_files, '?/*'
    stageAs multiqc_config, '?/*'

    output:
    record(
        id: id,
        meta: meta,
        report: file("*.html"),
        data: file("*_data"),
        plots: file("*_plots", optional: true),
        // MultiQC should not push its versions to the `versions` topic. Its input depends on the versions topic to be resolved thus outputting to the topic will let the pipeline hang forever
        versions: record(process: "${task.process}", tool: 'multiqc', version: eval('multiqc --version | sed "s/.* //g"'))
    )

    script:
    def prefix = task.ext.prefix ? "--filename ${task.ext.prefix}.html" : ''
    def config = multiqc_config ? "--config ${multiqc_config.join(' --config ')}" : ""
    def logo = multiqc_logo ? "--cl-config 'custom_logo: \"${multiqc_logo}\"'" : ''
    def replace = replace_names ? "--replace-names ${replace_names}" : ''
    def samples = sample_names ? "--sample-names ${sample_names}" : ''
    """
    multiqc \\
        --force \\
        ${task.ext.args} \\
        ${config} \\
        ${prefix} \\
        ${logo} \\
        ${replace} \\
        ${samples} \\
        .
    """

    stub:
    """
    mkdir multiqc_data
    touch multiqc_data/.stub
    mkdir multiqc_plots
    touch multiqc_plots/.stub
    touch multiqc_report.html
    """
}
