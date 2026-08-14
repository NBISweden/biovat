include { BWAMEM3_INDEX     } from '../../../modules/nf-core/bwamem3/index/main'
include { BWAMEM3_MEM       } from '../../../modules/nf-core/bwamem3/mem/main'
include { BWA_INDEX         } from '../../../modules/nf-core/bwa/index/main'
include { PARABRICKS_FQ2BAM } from '../../../modules/nf-core/parabricks/fq2bam/main'
include { SAMTOOLS_INDEX    } from '../../../modules/nf-core/samtools/index/main'

workflow ALIGN_READS {

    take:
    aligner         // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    reference       // channel: reference fasta read in from --reference
    reads           // channel: reads to align
    sort_bam        // boolean: Whether to sort the output BAM file

    main:
    // Alignment
    if (aligner == 'bwa-mem3') {
        BWAMEM3_INDEX(reference)
        BWAMEM3_MEM(
            reads,
            BWAMEM3_INDEX.out.index,
            reference,
            sort_bam
        )
        aligned_reads       = BWAMEM3_MEM.out.aligned
        aligned_reads_index = BWAMEM3_MEM.out.index
    } else if (aligner == 'parabricks') {
        // Parabricks requires BWA v0.7.x indexes
        BWA_INDEX(reference)
        PARABRICKS_FQ2BAM(
            reads,
            reference,
            BWA_INDEX.out.index,
            [[],[]], // intervals
            [[],[]], // known_sites
            'bam'    // output_fmt
        )
        SAMTOOLS_INDEX(PARABRICKS_FQ2BAM.out.bam)
        aligned_reads       = PARABRICKS_FQ2BAM.out.bam
        aligned_reads_index = SAMTOOLS_INDEX.out.index
    }

    emit:
    aligned_reads
    aligned_reads_index

}
