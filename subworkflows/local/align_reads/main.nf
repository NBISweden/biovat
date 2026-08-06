include { BWAMEM3_INDEX } from '../../../modules/nf-core/bwamem3/index/main'
include { BWAMEM3_MEM   } from '../../../modules/nf-core/bwamem3/mem/main'

workflow ALIGN_READS {

    take:
    reference       // channel: reference fasta read in from --reference
    trimmed_reads   // channel: trimmed reads
    samplesheet     // channel: samplesheet read in from --input
    align_raw_reads // boolean: Whether to align raw reads (true) or trimmed reads (false)
    sort_bam        // boolean: Whether to sort the output BAM file

    main:
    // Define reads to be used for alignment
    def reads_to_align = align_raw_reads ? samplesheet : trimmed_reads

    // Index reference using bwa-mem3
    BWAMEM3_INDEX(reference)
    def ch_index = BWAMEM3_INDEX.out.index

    // Align reads
    BWAMEM3_MEM(
        reads_to_align,
        ch_index,
        reference,
        sort_bam
    )
    aligned_reads       = BWAMEM3_MEM.out.aligned
    aligned_reads_index = BWAMEM3_MEM.out.index

    emit:
    aligned_reads
    aligned_reads_index

}
