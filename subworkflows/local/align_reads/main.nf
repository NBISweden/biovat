include { BWAMEM3_INDEX     } from '../../../modules/nf-core/bwamem3/index/main'
include { BWAMEM3_MEM       } from '../../../modules/nf-core/bwamem3/mem/main'
include { BWA_INDEX         } from '../../../modules/nf-core/bwa/index/main'
include { PARABRICKS_FQ2BAM } from '../../../modules/nf-core/parabricks/fq2bam/main'
include { SAMTOOLS_INDEX    } from '../../../modules/nf-core/samtools/index/main'
include { ALIGNMENT_QC      } from '../alignment_qc/main'

workflow ALIGN_READS {

    take:
    aligner               // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    ch_reference_and_fai  // value channel: reference fasta and fai index
    reads                 // channel: reads to align
    enable                // map: stage/tool gating flags
    ch_multiqc_files      // channel: MultiQC files

    main:
    reference = ch_reference_and_fai.map { meta, fasta, _fai -> [ meta, fasta ] }

    // Alignment
    if ( aligner == 'bwa-mem3' ) {
        BWAMEM3_INDEX(reference)
        BWAMEM3_MEM(
            reads,
            BWAMEM3_INDEX.out.index,
            reference,
            enable.sort_alignments
        )
        ch_library_alignments_indexed = BWAMEM3_MEM.out.aligned.join(BWAMEM3_MEM.out.index)
    } else if ( aligner == 'parabricks' ) {
        // Parabricks requires BWA v0.7.x indexes
        BWA_INDEX(reference)
        PARABRICKS_FQ2BAM(
            reads,
            reference,
            BWA_INDEX.out.index,
            [[],[]], // intervals
            [[],[]], // known_sites
            enable.cram_format ? 'cram' : 'bam'
        )
        SAMTOOLS_INDEX(PARABRICKS_FQ2BAM.out.bam)
        ch_library_alignments_indexed = PARABRICKS_FQ2BAM.out.bam.join(SAMTOOLS_INDEX.out.index)
    }

    // ALIGN_READS:ALIGNMENT_QC
    outputs_library_flagstat = channel.empty()
    outputs_library_riker    = channel.empty()
    outputs_library_qualimap = channel.empty()
    if ( enable.align_qc ) {
        ALIGNMENT_QC(
            ch_library_alignments_indexed,
            ch_reference_and_fai,
            enable
        )
        ch_multiqc_files = ch_multiqc_files
            .mix(
                ALIGNMENT_QC.out.flagstat_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.riker_outputs.map{ _meta, file -> file },
                ALIGNMENT_QC.out.qualimap_outputs.map{ _meta, file -> file }
            )
        outputs_library_flagstat = ALIGNMENT_QC.out.flagstat_outputs
        outputs_library_riker    = ALIGNMENT_QC.out.riker_outputs
        outputs_library_qualimap = ALIGNMENT_QC.out.qualimap_outputs
    }

    emit:
    ch_library_alignments_indexed    // channel: <Map> meta, <Path> bam, <Path> csi
    outputs_library_flagstat
    outputs_library_riker
    outputs_library_qualimap
    ch_multiqc_files

}
