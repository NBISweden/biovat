nextflow.enable.types = true

process GATK4_HAPLOTYPECALLER {
    tag "${id}"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ce/ce8f4142326abbb74e28b97633a200b09439c54480803343b1cf13dc19e51ae5/data'
        : 'community.wave.seqera.io/library/gatk4-lite:4.7.0.0--79918b8b2632f4b1'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { gatk4_haplotypecaller_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        input: Path,
        input_index: Path?,
        intervals: Path?,
        dragstr_model: Path?,
        fasta: Path,
        fai: Path?,
        dict: Path?,
        dbsnp: Path?,
        dbsnp_tbi: Path?,
        gatk4_haplotypecaller_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        vcf: file("*.vcf.gz"),
        tbi: file("*.tbi", optional: true),
        bam: file("*.realigned.bam", optional: true)
    )

    topic:
    record(process: "${task.process}", tool: 'gatk4', version: eval("gatk --version | sed -n '/GATK.*v/s/.*v//p'")) >> 'versions'

    script:
    def dbsnp_command = dbsnp ? "--dbsnp ${dbsnp}" : ""
    def interval_command = intervals ? "--intervals ${intervals}" : ""
    def dragstr_command = dragstr_model ? "--dragstr-params-path ${dragstr_model}" : ""
    def bamout_command = task.ext.args.contains("--bam-writer-type") ? "--bam-output ${task.ext.prefix.replaceAll('.g\\s*$', '')}.realigned.bam" : ""

    def avail_mem = 3072
    if (!task.memory) {
        log.info('[GATK HaplotypeCaller] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.')
    }
    else {
        avail_mem = (task.memory.toMega() * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        HaplotypeCaller \\
        --input ${input} \\
        --output ${task.ext.prefix}.vcf.gz \\
        --reference ${fasta} \\
        --native-pair-hmm-threads ${task.cpus} \\
        ${dbsnp_command} \\
        ${interval_command} \\
        ${dragstr_command} \\
        ${bamout_command} \\
        --tmp-dir . \\
        ${task.ext.args}
    """

    stub:
    def bamout_command = task.ext.args.contains("--bam-writer-type") ? "--bam-output ${task.ext.prefix.replaceAll('.g\\s*$', '')}.realigned.bam" : ""

    def stub_realigned_bam = bamout_command ? "touch ${task.ext.prefix.replaceAll('.g\\s*$', '')}.realigned.bam" : ""
    """
    echo "" | gzip > ${task.ext.prefix}.vcf.gz
    touch ${task.ext.prefix}.vcf.gz.tbi
    ${stub_realigned_bam}
    """
}
