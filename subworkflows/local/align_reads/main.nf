include { BWAMEM3_INDEX     } from '../../../modules/nf-core/bwamem3/index/main'
include { BWAMEM3_MEM       } from '../../../modules/nf-core/bwamem3/mem/main'
include { PARABRICKS_FQ2BAM } from '../../../modules/nf-core/parabricks/fq2bam/main'

workflow ALIGN_READS {

    take:
    align_raw_reads // boolean: Whether to align raw reads (true) or trimmed reads (false)
    aligner         // string: Aligner to use for read alignment (e.g. bwa, parabricks)
    reference       // channel: reference fasta read in from --reference
    samplesheet     // channel: samplesheet read in from --input
    trimmed_reads   // channel: trimmed reads
    sort_bam        // boolean: Whether to sort the output BAM file

    main:
    // Define reads to be used for alignment
    def reads_to_align = align_raw_reads ? samplesheet : trimmed_reads

    // Index reference using bwa-mem3
    BWAMEM3_INDEX(reference)
    def bwa_index = BWAMEM3_INDEX.out.index

    // Alignment
    if (aligner == 'bwa-mem3') {
        BWAMEM3_MEM(
            reads_to_align,
            bwa_index,
            reference,
            sort_bam
        )
        aligned_reads       = BWAMEM3_MEM.out.aligned
        aligned_reads_index = BWAMEM3_MEM.out.index
    } else if (aligner == 'parabricks') {
        PARABRICKS_FQ2BAM(
            reads_to_align,
            reference,
            bwa_index,
            [[],[]], // intervals
            [[],[]], // known_sites
            'bam' // output_fmt
        //TODO generate .csi index. pbrun can output .bai - check if .csi also. 
        )
        aligned_reads       = PARABRICKS_FQ2BAM.out.bam
        aligned_reads_index = PARABRICKS_FQ2BAM.out.bai
    }

    emit:
    aligned_reads
    aligned_reads_index

}
