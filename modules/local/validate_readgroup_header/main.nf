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
    tuple val(meta), path(bam_cram), env('rg_status'), emit: validated // rg_status: 'present' or 'missing' (no @RG line, filled downstream)
    tuple val("${task.process}"), val('samtools'), eval("samtools version | sed '1!d;s/.* //'"), topic: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    # Each samplesheet row is one read group. Several @RG lines is an error. No @RG line -> will be filled downstream from the samplesheet.
    samtools view -H ${bam_cram} > header.txt
    grep '^@RG' header.txt > rg_lines.txt || true
    n_rg=\$(wc -l < rg_lines.txt)
    if [ "\$n_rg" -gt 1 ]; then
        echo "ERROR: '${bam_cram}' has \$n_rg @RG header lines; expected at most 1 (one read group per samplesheet row)" >&2
        exit 1
    fi

    if [ "\$n_rg" -eq 0 ]; then
        rg_status=missing
    else
        # One tag per line. PL is compared case-insensitively, so also match against an uppercased copy of it
        tr '\\t' '\\n' < rg_lines.txt | sed 1d > header_tags.txt
        grep '^PL:' header_tags.txt | tr a-z A-Z > header_pl.txt || true
        printf '%s\\n' "ID:${meta.platform_unit}" "SM:${meta.id}" "LB:${meta.library}" "PU:${meta.platform_unit}" "PL:${meta.pl}" > expected_tags.txt

        # Expected tags with no exact match in the header: report what the header holds for that tag, or that it is absent
        grep -vxF -f header_tags.txt -f header_pl.txt expected_tags.txt | while IFS=: read -r tag _; do
            if grep -q "^\${tag}:" header_tags.txt; then
                echo "  found \$(grep -m1 "^\${tag}:" header_tags.txt)"
            else
                echo "  missing \${tag}"
            fi
        done > problems.txt || true

        if [ -s problems.txt ]; then
            {
                echo "ERROR: @RG header of '${bam_cram}' is missing tags or disagrees with the samplesheet row for sample '${meta.id}', library '${meta.library}' (expected ID/PU:${meta.platform_unit} SM:${meta.id} LB:${meta.library} PL:${meta.pl}):"
                cat problems.txt
            } >&2
            exit 1
        fi
        rg_status=present
    fi
    """

    stub:
    """
    rg_status=present
    """
}
