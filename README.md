# Fork

This fork uses [Portash](https://github.com/data-intuitive/Portash) as the 
entrypoint for the container. The [original pySCENIC 
image](https://hub.docker.com/r/aertslab/pyscenic) has therefore been adapted 
to include Portash and its dependencies.

As a result, the 3 steps in the pipeline are in fact very similar. Standard 
input and standard output is used for configuration of Portash. Reference files 
have to be made available for input and output is stored on the filesystem at 
completion.

Please note that the way to run this workflow is slightly different from the 
one in hte original pipeline (see below). In the original one, Nextflow is used 
to map the appropriate data volume (whole `home` directory). This ensures that 
the data is mapped automagically during a pipeline run and works for local and 
Docker runs. But it does not work for Kubernetes runs, for instance. We start 
from the idea that the user should put (reference) data in a directory and that 
this directory should be mapped to the container. This is consistent with the 
use of data using a _persistent volume_ and can be used in all possible 
scenarios.

There's a lot of room for improvement.

# SCENIC Nextflow pipeline using containers

A basic pipeline for running (py)SCENIC implemented in Nextflow.

## Requirements
    
* [Nextflow](https://www.nextflow.io/)
* A container system, either of:
  * [Docker](https://docs.docker.com/)
  * [Singularity](https://www.sylabs.io/singularity/)

The following container images will be pulled by nextflow as needed:
* Docker: [aertslab/pyscenic:latest](https://cloud.docker.com/u/aertslab/repository/docker/aertslab/pyscenic).
* Singularity: [aertslab/pySCENIC:latest](https://www.singularity-hub.org/collections/2033).
* [See also here.](https://github.com/aertslab/pySCENIC#docker-and-singularity-images)


## Parameters: input files and databases

Requires the same support files as [pySCENIC](https://github.com/aertslab/pySCENIC).
These can be passed as command line parameters to nextflow.

    --expr = expression matrix, (either in tsv format (must end in .tsv), or loom format (.loom))
    --TFs = file containing transcription factors, one per line
    --motifs = Motif annotation database, tbl format.
    --db = Ranking databases, feather format. If using a glob pattern to select multiple database files, this parameter must be enclosed in quotes (i.e. --db "/path/to/dbs/hg19*feather").
    --threads = Number of threads to use.
    --output = Name of the output file, (either in tsv format (must end in .tsv), or loom format (.loom)).
    --grn = GRN inference method, either "grnboost2" or "genie3" (optional, default: grnboost2)

Optional parameters for reading from loom files:

    --cell_id_attribute = which column attributes to use for the cell id (default: "CellID").
    --gene_attribute = which row attributes for use for the gene names (default: "Gene").

## Running the pipeline on the example dataset

### Download testing dataset

Download a minimum set of SCENIC database files for a human dataset (approximately 75 MB).
This small test dataset takes approiximately 30s to run using 6 threads on a standard desktop computer.

    mkdir example && cd example/
    # Transcription factors:
    wget https://raw.githubusercontent.com/aertslab/containerizedGRNboost/master/example/input/allTFs_hg38.txt
    # Motif to TF annotation database:
    wget https://raw.githubusercontent.com/aertslab/scenic-nf/master/example/motifs.tbl
    # Ranking databases:
    wget https://raw.githubusercontent.com/aertslab/scenic-nf/master/example/genome-ranking.feather
    # Finally, get a small sample expression matrix (loom format):
    wget https://raw.githubusercontent.com/aertslab/scenic-nf/master/example/expr_mat.loom
    # Alternatively, in tsv format:
    wget https://raw.githubusercontent.com/aertslab/scenic-nf/master/example/expr_mat.tsv


### Running the example pipeline

#### Docker

    nextflow run aertslab/scenic-nf \
        -profile docker \
        --expr expr_mat.loom \
        --TFs allTFs_hg38.txt \
        --motifs motifs.tbl \
        --db *feather

#### Singularity

    nextflow run aertslab/scenic-nf \
        -profile singularity \
        --expr expr_mat.loom \
        --TFs allTFs_hg38.txt \
        --motifs motifs.tbl \
        --db *feather

### Expected output

If a loom was provided as input, a new loom file will be created as output containing:
* The expression matrix from the original loom file
* AUC matrix (output of AUCell)
* List of regulons embedded in the loom meta data

If a tsv expression matrix was provided as input, the AUC matrix will be written out (csv format).
An example of the AUC matrix showing the regulon enrichment values in each cell (actual numerical values may differ due to the stochastic nature of the pySCENIC algorithms):

    Cell,GABPB1(+)
    CTGCGGAGTTCGCGAC-1,0.08
    GAATGAACACACTGCG-1,0.045714285714285714
    ATGCGATTCAGCATGT-1,0.10285714285714286
    TTCGAAGGTAGCGATG-1,0.09714285714285714
    CGTAGGCGTCGGCACT-1,0.10857142857142857
    CCGGGATGTAAAGTCA-1,0.06285714285714286
    ACTTGTTTCTCTTATG-1,0.08
    ATCCACCGTCGGCACT-1,0.08571428571428572
    GTACTTTTCGGCTACG-1,0.0

## To run with extra reporting enabled

    nextflow run aertslab/scenic-nf -with-report report.html -with-timeline timeline.html -with-dag dag.png -profile [docker|singularity]




