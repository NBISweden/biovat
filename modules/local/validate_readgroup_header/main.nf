process VALIDATE_READGROUP_HEADER {
    tag "${meta.id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container
        ? 'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/e9/e994bf4eb3731150511a14f5706b7bdfd64df1b6d40898fff334286c027e0859/data'
        : 'community.wave.seqera.io/library/htslib_samtools:1.24--d697cfb9dce007cd'}"

    input:
    tuple val(meta), path(bam_cram)

    output:
    tuple val(meta), path(bam_cram), emit: validated
    tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Check every @RG tag (see conf/modules.config) against the samplesheet
    def platform_unit = "${meta.flowcell}.${meta.lane}.${meta.id}_${meta.library}"
    """
    samtools view -H ${bam_cram} > header.sam

    check_tag() {
        local tag="\$1" expected="\$2"
        awk -F'\\t' -v tag="\${tag}:" -v expected="\${expected}" '
            \$1 == "@RG" {
                for (i = 2; i <= NF; i++) {
                    if (index(\$i, tag) == 1) {
                        value = substr(\$i, length(tag) + 1)
                        if (value != expected) print tag value
                    }
                }
            }
        ' header.sam | sort -u
    }

    mismatches=\$(
        {
            check_tag "ID" "${platform_unit}"
            check_tag "SM" "${meta.id}"
            check_tag "LB" "${meta.library}"
            check_tag "PU" "${platform_unit}"
            check_tag "PL" "${meta.pl}"
        }
    )

    if [ -n "\${mismatches}" ]; then
        echo "ERROR: @RG header of '${bam_cram}' disagrees with the samplesheet row for sample '${meta.id}', library '${meta.library}' (expected ID/PU:${platform_unit} SM:${meta.id} LB:${meta.library} PL:${meta.pl}):" >&2
        echo "\${mismatches}" | sed 's/^/  found /' >&2
        exit 1
    fi
    """

    stub:
    """
    """
}
