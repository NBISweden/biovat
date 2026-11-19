nextflow.enable.types = true

process GATK4_GENOMICSDBIMPORT {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ce/ce8f4142326abbb74e28b97633a200b09439c54480803343b1cf13dc19e51ae5/data'
        : 'community.wave.seqera.io/library/gatk4-lite:4.7.0.0--79918b8b2632f4b1'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { gatk4_genomicsdbimport_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        vcf: List<Path>,
        tbi: Bag<Path>?,
        interval_file: Path?,
        interval_value: String?,
        wspace: Path?,
        run_intlist: Boolean,
        run_updatewspace: Boolean,
        input_map: Boolean,
        gatk4_genomicsdbimport_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        genomicsdb: file(task.ext.prefix, optional: true),
        updatedb: run_updatewspace ? file("${wspace}", optional: true) : null,
        intervallist: file("*.interval_list", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'gatk4', version: eval("gatk --version | sed -n '/GATK.*v/s/.*v//p'")) >> 'versions'

    script:
    // settings for running default create gendb mode
    def input_command = input_map ? "--sample-name-map ${vcf[0]}" : vcf.collect { vcf_ -> "--variant ${vcf_}" }.join(' ')

    def genomicsdb_command = "--genomicsdb-workspace-path ${task.ext.prefix}"
    def interval_command = interval_file ? "--intervals ${interval_file}" : "--intervals ${interval_value}"

    // settings changed for running get intervals list mode if run_intlist is true
    if (run_intlist) {
        genomicsdb_command = "--genomicsdb-update-workspace-path ${wspace}"
        interval_command = "--output-interval-list-to-file ${task.ext.prefix}.interval_list"
    }

    // settings changed for running update gendb mode. input_command same as default, the updated workspace is emitted as updatedb
    if (run_updatewspace) {
        genomicsdb_command = "--genomicsdb-update-workspace-path ${wspace}"
        interval_command = ''
    }

    def avail_mem = 3072
    if (!task.memory) {
        log.info('[GATK GenomicsDBImport] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.')
    }
    else {
        avail_mem = (task.memory.toMega() * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        GenomicsDBImport \\
        ${input_command} \\
        ${genomicsdb_command} \\
        ${interval_command} \\
        --tmp-dir . \\
        ${task.ext.args}
    """

    stub:
    def genomicsdb_command = "--genomicsdb-workspace-path ${task.ext.prefix}"
    def interval_command = interval_file ? "--intervals ${interval_file}" : "--intervals ${interval_value}"

    // settings changed for running get intervals list mode if run_intlist is true
    if (run_intlist) {
        genomicsdb_command = "--genomicsdb-update-workspace-path ${wspace}"
        interval_command = "--output-interval-list-to-file ${task.ext.prefix}.interval_list"
    }

    // settings changed for running update gendb mode. The updated workspace is emitted as updatedb
    if (run_updatewspace) {
        genomicsdb_command = "--genomicsdb-update-workspace-path ${wspace}"
        interval_command = ''
    }

    def stub_genomicsdb = genomicsdb_command == "--genomicsdb-workspace-path ${task.ext.prefix}" ? "touch ${task.ext.prefix}" : ""
    def stub_interval = interval_command == "--output-interval-list-to-file ${task.ext.prefix}.interval_list" ? "touch ${task.ext.prefix}.interval_list" : ""
    def stub_update = run_updatewspace ? "touch ${wspace}" : ""

    """
    ${stub_genomicsdb}
    ${stub_interval}
    ${stub_update}
    """
}
