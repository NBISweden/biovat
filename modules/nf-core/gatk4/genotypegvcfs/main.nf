nextflow.enable.types = true

process GATK4_GENOTYPEGVCFS {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/ce/ce8f4142326abbb74e28b97633a200b09439c54480803343b1cf13dc19e51ae5/data'
        : 'community.wave.seqera.io/library/gatk4-lite:4.7.0.0--79918b8b2632f4b1'}"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { gatk4_genotypegvcfs_args ?: '' }
    ]

    input:
    record(
        id: String,
        meta: Record?,
        input: Path,
        gvcf_index: Path?,
        intervals: Path?,
        intervals_index: Path?,
        fasta: Path,
        fai: Path,
        dict: Path,
        dbsnp: Path?,
        dbsnp_tbi: Path?,
        gatk4_genotypegvcfs_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        vcf: file("*.vcf.gz"),
        tbi: file("*.tbi")
    )

    topic:
    record(process: "${task.process}", tool: 'gatk4', version: eval("gatk --version | sed -n '/GATK.*v/s/.*v//p'")) >> 'versions'

    script:
    def input_command = input.name.endsWith(".vcf") || input.name.endsWith(".vcf.gz") ? "${input}" : "gendb://${input}"
    def dbsnp_command = dbsnp ? "--dbsnp ${dbsnp}" : ""
    def interval_command = intervals ? "--intervals ${intervals}" : ""

    def avail_mem = 3072
    if (!task.memory) {
        log.info('[GATK GenotypeGVCFs] Available memory not known - defaulting to 3GB. Specify process memory requirements to change this.')
    }
    else {
        avail_mem = (task.memory.toMega() * 0.8).intValue()
    }
    """
    gatk --java-options "-Xmx${avail_mem}M -XX:-UsePerfData" \\
        GenotypeGVCFs \\
        --variant ${input_command} \\
        --output ${task.ext.prefix}.vcf.gz \\
        --reference ${fasta} \\
        ${interval_command} \\
        ${dbsnp_command} \\
        --tmp-dir . \\
        ${task.ext.args}
    """

    stub:
    """
    echo "" | gzip > ${task.ext.prefix}.vcf.gz
    touch ${task.ext.prefix}.vcf.gz.tbi
    """
}
