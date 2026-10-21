nextflow.enable.types = true

process VCFTOOLS {
    tag "${id}"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/vcftools:0.1.17--pl5321h077b44d_0' :
        'quay.io/biocontainers/vcftools:0.1.17--pl5321h077b44d_0' }"

    ext [
        prefix: { output_prefix ?: "${id}" },
        args: { vcftools_args ?: '' }
    ]

    input:
    // Owing to the nature of vcftools we here provide solutions to working with optional bed files and optional
    // alternative variant files, for use with the 'diff' suite of tools.
    // Other optional input files can be utilised in a similar way to below but we do not exhaustively iterate through all
    // possible options. Instead we leave that to the user.
    record(
        id: String,
        meta: Record?,
        variant_file: Path,
        bed: Path?,
        diff_variant_file: Path?,
        vcftools_args: String?,
        output_prefix: String?
    )

    output:
    record(
        id: id,
        meta: meta,
        vcf: file("*.vcf", optional: true),
        bcf: file("*.bcf", optional: true),
        frq: file("*.frq", optional: true),
        frq_count: file("*.frq.count", optional: true),
        idepth: file("*.idepth", optional: true),
        ldepth: file("*.ldepth", optional: true),
        ldepth_mean: file("*.ldepth.mean", optional: true),
        gdepth: file("*.gdepth", optional: true),
        hap_ld: files("*.hap.ld", optional: true),
        geno_ld: files("*.geno.ld", optional: true),
        geno_chisq: file("*.geno.chisq", optional: true),
        list_hap_ld: file("*.list.hap.ld", optional: true),
        list_geno_ld: file("*.list.geno.ld", optional: true),
        interchrom_hap_ld: file("*.interchrom.hap.ld", optional: true),
        interchrom_geno_ld: file("*.interchrom.geno.ld", optional: true),
        tstv: file("*.TsTv", optional: true),
        tstv_summary: file("*.TsTv.summary", optional: true),
        tstv_count: file("*.TsTv.count", optional: true),
        tstv_qual: file("*.TsTv.qual", optional: true),
        filter_summary: file("*.FILTER.summary", optional: true),
        sites_pi: file("*.sites.pi", optional: true),
        windowed_pi: file("*.windowed.pi", optional: true),
        weir_fst: file("*.weir.fst", optional: true),
        heterozygosity: file("*.het", optional: true),
        hwe: file("*.hwe", optional: true),
        tajima_d: file("*.Tajima.D", optional: true),
        freq_burden: file("*.ifreqburden", optional: true),
        lroh: file("*.LROH", optional: true),
        relatedness: file("*.relatedness", optional: true),
        relatedness2: file("*.relatedness2", optional: true),
        lqual: file("*.lqual", optional: true),
        missing_individual: file("*.imiss", optional: true),
        missing_site: file("*.lmiss", optional: true),
        snp_density: file("*.snpden", optional: true),
        kept_sites: file("*.kept.sites", optional: true),
        removed_sites: file("*.removed.sites", optional: true),
        singeltons: file("*.singletons", optional: true),
        indel_hist: file("*.indel.hist", optional: true),
        hapcount: file("*.hapcount", optional: true),
        mendel: file("*.mendel", optional: true),
        format: file("*.FORMAT", optional: true),
        info: file("*.INFO", optional: true),
        genotypes_matrix: file("*.012", optional: true),
        genotypes_matrix_individual: file("*.012.indv", optional: true),
        genotypes_matrix_position: file("*.012.pos", optional: true),
        impute_hap: file("*.impute.hap", optional: true),
        impute_hap_legend: file("*.impute.hap.legend", optional: true),
        impute_hap_indv: file("*.impute.hap.indv", optional: true),
        ldhat_sites: file("*.ldhat.sites", optional: true),
        ldhat_locs: file("*.ldhat.locs", optional: true),
        beagle_gl: file("*.BEAGLE.GL", optional: true),
        beagle_pl: file("*.BEAGLE.PL", optional: true),
        ped: file("*.ped", optional: true),
        map_: file("*.map", optional: true),
        tped: file("*.tped", optional: true),
        tfam: file("*.tfam", optional: true),
        diff_sites_in_files: file("*.diff.sites_in_files", optional: true),
        diff_indv_in_files: file("*.diff.indv_in_files", optional: true),
        diff_sites: file("*.diff.sites", optional: true),
        diff_indv: file("*.diff.indv", optional: true),
        diff_discd_matrix: file("*.diff.discordance.matrix", optional: true),
        diff_switch_error: file("*.diff.switch", optional: true),
    )

    topic:
    record(process: "${task.process}", tool: 'vcftools', version: eval('vcftools --version 2>&1 | sed "s/^.*VCFtools (//;s/).*//"')) >> 'versions'

    script:
    def bed_arg  = (task.ext.args.contains('--bed')) ? "--bed ${bed}" :
        (task.ext.args.contains('--exclude-bed')) ? "--exclude-bed ${bed}" :
        (task.ext.args.contains('--hapcount')) ? "--hapcount ${bed}" :
        (task.ext.args.contains('--positions')) ? "--positions ${bed}" :
        (task.ext.args.contains('--exclude-positions')) ? "--exclude-positions ${bed}"  : ''

    def diff_variant_arg = (task.ext.args.contains('--diff')) ? "--diff ${diff_variant_file}" :
        (task.ext.args.contains('--gzdiff')) ? "--gzdiff ${diff_variant_file}" :
        (task.ext.args.contains('--diff-bcf')) ? "--diff-bcf ${diff_variant_file}" : ''

    // The flags that take the bed and diff files are given through those inputs, so they are dropped from the other arguments
    def file_flags = ['--bed', '--exclude-bed', '--hapcount', '--positions', '--exclude-positions', '--diff', '--gzdiff', '--diff-bcf']
    def args_list = task.ext.args.tokenize().findAll { arg -> !file_flags.any { flag -> arg.contains(flag) } }

    def input_file = (variant_file.name.endsWith(".vcf")) ? "--vcf ${variant_file}" :
        (variant_file.name.endsWith(".vcf.gz")) ? "--gzvcf ${variant_file}" :
        (variant_file.name.endsWith(".bcf")) ? "--bcf ${variant_file}" : ''

    """
    vcftools \\
        ${input_file} \\
        --out ${task.ext.prefix} \\
        ${args_list.join(' ')} \\
        ${bed_arg} \\
        ${diff_variant_arg}
    """

    stub:
    """
    touch ${task.ext.prefix}.vcf
    touch ${task.ext.prefix}.bcf
    touch ${task.ext.prefix}.frq
    touch ${task.ext.prefix}.frq.count
    touch ${task.ext.prefix}.idepth
    touch ${task.ext.prefix}.ldepth
    touch ${task.ext.prefix}.ldepth.mean
    touch ${task.ext.prefix}.gdepth
    touch ${task.ext.prefix}.hap.ld
    touch ${task.ext.prefix}.geno.ld
    touch ${task.ext.prefix}.geno.chisq
    touch ${task.ext.prefix}.list.hap.ld
    touch ${task.ext.prefix}.list.geno.ld
    touch ${task.ext.prefix}.interchrom.hap.ld
    touch ${task.ext.prefix}.interchrom.geno.ld
    touch ${task.ext.prefix}.TsTv
    touch ${task.ext.prefix}.TsTv.summary
    touch ${task.ext.prefix}.TsTv.count
    touch ${task.ext.prefix}.TsTv.qual
    touch ${task.ext.prefix}.FILTER.summary
    touch ${task.ext.prefix}.sites.pi
    touch ${task.ext.prefix}.windowed.pi
    touch ${task.ext.prefix}.weir.fst
    touch ${task.ext.prefix}.het
    touch ${task.ext.prefix}.hwe
    touch ${task.ext.prefix}.Tajima.D
    touch ${task.ext.prefix}.ifreqburden
    touch ${task.ext.prefix}.LROH
    touch ${task.ext.prefix}.relatedness
    touch ${task.ext.prefix}.relatedness2
    touch ${task.ext.prefix}.lqual
    touch ${task.ext.prefix}.imiss
    touch ${task.ext.prefix}.lmiss
    touch ${task.ext.prefix}.snpden
    touch ${task.ext.prefix}.kept.sites
    touch ${task.ext.prefix}.removed.sites
    touch ${task.ext.prefix}.singletons
    touch ${task.ext.prefix}.indel.hist
    touch ${task.ext.prefix}.hapcount
    touch ${task.ext.prefix}.mendel
    touch ${task.ext.prefix}.FORMAT
    touch ${task.ext.prefix}.INFO
    touch ${task.ext.prefix}.012
    touch ${task.ext.prefix}.012.indv
    touch ${task.ext.prefix}.012.pos
    touch ${task.ext.prefix}.impute.hap
    touch ${task.ext.prefix}.impute.hap.legend
    touch ${task.ext.prefix}.impute.hap.indv
    touch ${task.ext.prefix}.ldhat.sites
    touch ${task.ext.prefix}.ldhat.locs
    touch ${task.ext.prefix}.BEAGLE.GL
    touch ${task.ext.prefix}.BEAGLE.PL
    touch ${task.ext.prefix}.ped
    touch ${task.ext.prefix}.map
    touch ${task.ext.prefix}.tped
    touch ${task.ext.prefix}.tfam
    touch ${task.ext.prefix}.diff.sites_in_files
    touch ${task.ext.prefix}.diff.indv_in_files
    touch ${task.ext.prefix}.diff.sites
    touch ${task.ext.prefix}.diff.indv
    touch ${task.ext.prefix}.diff.discordance.matrix
    touch ${task.ext.prefix}.diff.switch
    """
}
