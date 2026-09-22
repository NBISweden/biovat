include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'
include { RIKER_MULTI       } from '../../../modules/nf-core/riker/multi/main'
include { QUALIMAP_BAMQC    } from '../../../modules/nf-core/qualimap/bamqc/main'

workflow ALIGNMENT_QC {
    take:
    ch_alignment_and_index        // channel: aligned reads and their indices to perform QC on
    ch_reference_and_optional_fai // channel: reference fasta and (optional) fai index
    enable                        // map: stage/tool gating flags
    level                         // string: QC level, used as the output prefix ('readgroup'/'library'/'markdup'/'sample')

    main:
    // Tag each record with a level-scoped prefix so a single modules.config selector covers every call site
    ch_qc_input = ch_alignment_and_index.map { meta, alignment, index ->
        // Read-group-level records still carry all meta, library/markdup have readgroups merged to library level
        // sample-level merging groups on {id, pl}, dropping library
        def prefix = level == 'readgroup'
            ? meta.read_group
            : level == 'sample'
                ? "${meta.id}_${meta.pl}"
                : "${meta.id}_${meta.library}_${meta.pl}" // else 'library' or 'markdup'
        [meta + [qc_prefix: "${level}_${prefix}"], alignment, index]
    }

    // SAMTOOLS_FLAGSTAT
    samtools_flagstat_out = SAMTOOLS_FLAGSTAT(ch_qc_input)

    // RIKER
    riker_outputs = channel.empty()
    if (enable.riker) {
        def ch_riker_input = ch_qc_input // TODO: Potentially support optional inputs, except RNA-seq specific.
            .map { meta, alignment, index ->
                [
                    meta, alignment, index,
                    [], // path: error_vcf
                    [], // path: error_vcf_idx
                    [], // path: error_intervals
                    [], // path: gcbias_exclude_intervals
                    [], // path: hybcap_baits
                    [], // path: hybcap_targets
                    [], // path: rna_gene_model
                    [], // path: rna_ribosomal_intervals
                    [], // path: wgs_intervals
                ]
            }
        riker_multi_out = RIKER_MULTI(
            ch_riker_input,
            ch_reference_and_optional_fai,
        )
        riker_outputs = (riker_multi_out - riker_multi_out.versions_riker).inject(channel.empty()) { acc, ch -> acc.mix(ch) }
    }

    // QUALIMAP
    qualimap_outputs = channel.empty()
    if (enable.qualimap) {
        qualimap_bamqc_out = QUALIMAP_BAMQC(
            ch_qc_input.map { meta, alignment, _index -> [meta, alignment] },
            [], // TODO: Potentially support optional input (gff file)
        )
        qualimap_outputs = qualimap_bamqc_out.results
    }

    emit:
    flagstat_outputs = samtools_flagstat_out.flagstat
    riker_outputs    = riker_outputs
    qualimap_outputs = qualimap_outputs
}
