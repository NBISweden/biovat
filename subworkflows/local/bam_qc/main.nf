include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'
include { RIKER_MULTI       } from '../../../modules/nf-core/riker/multi/main'
include { QUALIMAP_BAMQC    } from '../../../modules/nf-core/qualimap/bamqc/main'

workflow BAM_QC {

    take:
    ch_alignment_and_index   // channel: aligned reads and their indices to perform QC on
    ch_reference_and_fai     // channel: reference fasta and fai index
    enable_riker             // boolean: Whether to run RIKER for BAM QC
    enable_qualimap          // boolean: Whether to run QUALIMAP for BAM QC

    main:
    // SAMTOOLS_FLAGSTAT
    SAMTOOLS_FLAGSTAT(ch_alignment_and_index)

    // RIKER
    riker_outputs = channel.empty()
    if ( enable_riker ) {
        def ch_riker_input = ch_alignment_and_index // TODO: Potentially support optional inputs, except RNA-seq specific.
            .map { meta, bam, index ->
                [
                    meta, bam, index,
                    [], // path: error_vcf
                    [], // path: error_vcf_idx
                    [], // path: error_intervals
                    [], // path: gcbias_exclude_intervals
                    [], // path: hybcap_baits
                    [], // path: hybcap_targets
                    [], // path: rna_gene_model
                    [], // path: rna_ribosomal_intervals
                    []  // path: wgs_intervals
                ]
            }
        RIKER_MULTI(
            ch_riker_input,
            ch_reference_and_fai
        )
        riker_outputs = (RIKER_MULTI.out - RIKER_MULTI.out.versions_riker)
            .inject(channel.empty()) { acc, ch -> acc.mix(ch) }
    }

    // QUALIMAP
    qualimap_outputs = channel.empty()
    if ( enable_qualimap ) {
        QUALIMAP_BAMQC(
            ch_alignment_and_index.map { meta, bam, _index -> [ meta, bam ] },
            []         //  TODO: Potentially support optional input (gff file)
        )
        qualimap_outputs = QUALIMAP_BAMQC.out.results
    }

    emit:
    flagstat_outputs = SAMTOOLS_FLAGSTAT.out.flagstat
    riker_outputs    = riker_outputs
    qualimap_outputs = qualimap_outputs

}
