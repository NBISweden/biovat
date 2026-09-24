# Monkeyflower data set

Reference sequence and fastq files with read data from study "Widespread selection and gene flow shape the genomic landscape during a radiation of monkeyflowers" by Stankowski et al, PLoS Biology, 2019.

The tiny monkeyflower data set was downloaded from https://github.com/NBISweden/pgip-data/tree/main/data/monkeyflower/tiny. This github repository contains reference sequence and read data for 37 monkeyflower individuals for the region LG4:12,000,000-12,100,000.

For testing, six samples of the subspecies Diplacus puniceus were selected, representing the red and the yellow ecotype:

| Sample     | Run        | ScientificName    | SampleName      | AuthorSample | SampleAlias  | Taxon                  | Latitude | Longitude | % Reads aligned | Seq. Depth |
|------------|------------|-------------------|-----------------|--------------|--------------|------------------------|----------|-----------|-----------------|------------|
| SRS4979264 | SRR9309788 | Diplacus puniceus | PUN-BCRD11-2016 | BCRD         | PUN-Y-BCRD   | ssp. puniceus, yellow  | 32.9496  | -116.638  | 94.6            | 20.85      |
| SRS4979261 | SRR9309791 | Diplacus puniceus | PUN-ELF11-2016  | ELF          | PUN-R-ELF    | ssp. puniceus, red     | 33.086   | -117.1453 | 93              | 18.2       |
| SRS4979263 | SRR9309790 | Diplacus puniceus | PUN-INJ10-2016  | INJ          | PUN-Y-INJ    | ssp. puniceus, yellow  | 33.0979  | -116.6643 | 93.1            | 18.83      |
| SRS4979223 | SRR9309467 | Diplacus puniceus | PUN-JMC19-2016  | JMC          | PUN-R-JMC    | ssp. puniceus, red     | 32.7373  | -116.9541 | 93.8            | 19.06      |
| SRS4979222 | SRR9309469 | Diplacus puniceus | PUN-LO4-2016    | LO           | PUN-Y-LO     | ssp. puniceus, yellow  | 32.6767  | -116.3312 | 93.4            | 18.04      |
| SRS4979221 | SRR9309470 | Diplacus puniceus | PUN-MT10-2016   | MT           | PUN-R-MT     | ssp. puniceus, red     | 32.821   | -117.0618 | 93.7            | 20.85      |

Note that sample PUN-LO4-2016 (PUN-Y-LO) was duplicated twice, each with edited QNAMEs, to be able to test sample merging.
One duplicate represents a distinct library that should not be deduplicated with respect to the others.
The other represents repeat sequencing of a library on a distinct flowcell.
In this case biological replicates should be deduplicated between the pair.

Samples PUN-ELF11-2016 (PUN-R-ELF) and PUN-MT10-2016 (PUN-R-MT) each additionally carry a row whose reads
were duplicated from their own fastq data and converted to an already-aligned BAM/CRAM, to test BAM/CRAM
samplesheet input (`bam` column). As with PUN-Y-LO above, QNAMEs were edited (`L2:`/`l1rep1:` prefixes) so
they don't collide with the sibling row they get merged with. PUN-R-ELF's row is a distinct second library
(`PUN-R-ELF_2.bam`); PUN-R-MT's is repeat sequencing of library 1 on a second flowcell (`PUN-R-MT_1_repeat2.cram`).

Files follow the naming convention `<sample>_<library_id>_R1/R2.fastq.gz`. Where a library has more than one
row (repeat sequencing on a different flowcell/lane, e.g. PUN-Y-LO library 2 and PUN-R-MT library 1), a
`repeat1`/`repeat2` tag is inserted before the read suffix: `<sample>_<library_id>_repeatN_R1/R2.fastq.gz`.
BAM/CRAM fixtures drop the `_R1`/`_R2` suffix.
