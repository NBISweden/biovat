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
    rg_status=\$(
        samtools view -H ${bam_cram} | awk -F'\\t' \\
            -v id="${meta.platform_unit}" -v sm="${meta.id}" -v lb="${meta.library}" -v pl="${meta.pl}" '
            BEGIN { want["ID"] = id; want["SM"] = sm; want["LB"] = lb; want["PU"] = id; want["PL"] = pl }
            \$1 == "@RG" {
                n_rg++
                for (i = 2; i <= NF; i++) if (\$i ~ /^[A-Za-z][A-Za-z0-9]:/) found[substr(\$i, 1, 2)] = substr(\$i, 4)
            }
            END {
                if (n_rg > 1) {
                    print "ERROR: \\047${bam_cram}\\047 has " n_rg " @RG header lines; expected at most 1 (one read group per samplesheet row)" > "/dev/stderr"
                    exit 1
                }
                if (n_rg == 0) { print "missing"; exit 0 }
                split("ID SM LB PU PL", tags, " ")
                for (t = 1; t <= 5; t++) {
                    tag = tags[t]
                    if (!(tag in found)) { problems = problems "\\n  missing " tag; continue }
                    got = (tag == "PL") ? toupper(found[tag]) : found[tag]
                    if (got != want[tag]) problems = problems "\\n  found " tag ":" found[tag]
                }
                if (problems) {
                    print "ERROR: @RG header of \\047${bam_cram}\\047 is missing tags or disagrees with the samplesheet row for sample \\047${meta.id}\\047, library \\047${meta.library}\\047 (expected ID/PU:${meta.platform_unit} SM:${meta.id} LB:${meta.library} PL:${meta.pl}):" problems > "/dev/stderr"
                    exit 1
                }
                print "present"
            }'
    )
    """

    stub:
    """
    rg_status=present
    """
}
