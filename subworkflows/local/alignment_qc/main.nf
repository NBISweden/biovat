nextflow.enable.types = true

include { SAMTOOLS_FLAGSTAT } from '../../../modules/nf-core/samtools/flagstat/main'
include { RIKER_MULTI       } from '../../../modules/nf-core/riker/multi/main'
include { QUALIMAP_BAMQC    } from '../../../modules/nf-core/qualimap/bamqc/main'

workflow ALIGNMENT_QC {

    take:
    alignments: Channel<Record> // record(meta, alignment, index): aligned reads and their indices to perform QC on
    reference : Value<Record>   // record(meta, fasta, fai): reference fasta and (optional) fai index
    riker     : Boolean         // run Riker
    qualimap  : Boolean         // run Qualimap
    level     : String          // QC level, used as the output prefix ('input'/'readgroup'/'library'/'markdup'/'sample')

    main:
    // Tag each alignment with a level-scoped prefix so each output file is named by its level and read group/library/sample
    qc_input = alignments
        .map { aln ->
            // Input (user BAM/CRAM) and read-group-level records still carry all meta, library/markdup have readgroups
            // merged to library level, sample-level merging groups on {id, pl}, dropping library
            def prefix = level in [ 'input', 'readgroup' ]
                ? aln.meta.read_group
                : level == 'sample'
                    ? "${aln.meta.id}_${aln.meta.pl}"
                    : "${aln.meta.id}_${aln.meta.library}_${aln.meta.pl}" // else 'library' or 'markdup'
            record(meta: aln.meta, alignment: aln.alignment, index: aln.index, qc_prefix: "${level}_${prefix}")
        }

    // SAMTOOLS_FLAGSTAT
    flagstat = SAMTOOLS_FLAGSTAT(
        qc_input.map { qc -> record(id: qc.meta.id, meta: qc.meta, bam: qc.alignment, bai: qc.index, output_prefix: qc.qc_prefix) }
    )

    // RIKER
    riker_out = channel.empty()
    if ( riker ) {
        riker_out = RIKER_MULTI(
            qc_input
                .combine(reference)
                .map { qc, ref ->
                    record(
                        id                      : qc.meta.id,
                        meta                    : qc.meta,
                        bam                     : qc.alignment,
                        bai                     : qc.index,
                        error_vcf               : null,
                        error_vcf_idx           : null,
                        error_intervals         : null,
                        gcbias_exclude_intervals: null,
                        hybcap_baits            : null,
                        hybcap_targets          : null,
                        rna_gene_model          : null,
                        rna_ribosomal_intervals : null,
                        wgs_intervals           : null, // TODO: Potentially support optional inputs, except RNA-seq specific.
                        fasta                   : ref.fasta,
                        fai                     : ref.fai,
                        riker_multi_args        : '--tools alignment basic isize wgs gcbias',
                        output_prefix           : qc.qc_prefix
                    )
                }
        )
    }

    // QUALIMAP
    qualimap_out = channel.empty()
    if ( qualimap ) {
        qualimap_out = QUALIMAP_BAMQC(
            qc_input.map { qc ->
                record(
                    id                  : qc.meta.id,
                    meta                : qc.meta,
                    single_end          : qc.meta.single_end,
                    bam                 : qc.alignment,
                    gff                 : null, // TODO: Potentially support optional input (gff file)
                    qualimap_bamqc_args : null,
                    output_prefix       : qc.qc_prefix
                )
            }
        )
    }

    // Every QC file, for MultiQC
    multiqc_files = flagstat
        .map { out -> out.flagstat }
        .mix(riker_out.flatMap { out -> rikerFiles(out) })
        .mix(qualimap_out.map { out -> out.results })

    emit:
    flagstat      : Channel<Record> = flagstat      // record(meta, flagstat)
    riker         : Channel<Record> = riker_out     // record(meta, <riker metric files>)
    qualimap      : Channel<Record> = qualimap_out  // record(meta, results)
    multiqc_files : Channel<Path>   = multiqc_files
}

def rikerFiles(riker: Record) {
    def single = [
        riker.alignment_metrics, riker.base_dist, riker.error_indel, riker.error_mismatch, riker.error_overlap,
        riker.gcbias_detail, riker.gcbias_summary, riker.hybcap_metrics, riker.hybcap_per_target,
        riker.isize_histogram, riker.isize_metrics, riker.mean_qual, riker.qual_dist, riker.rna_biotype,
        riker.rna_insert_size_histogram, riker.rna_insert_size, riker.rna_metrics, riker.wgs_coverage, riker.wgs_metrics
    ].findAll { file -> file != null }
    return single + riker.hybcap_per_base.toList() + riker.pdf.toList()
}
