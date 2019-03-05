#!/usr/bin/env nextflow

ISDRY = true

/*
   Extend the DataflowQueue class with a `log` method for easier logging
*/
groovyx.gpars.dataflow.DataflowQueue.metaClass.log() { String str ->

  if (params.debug) {
    return delegate.view{"*** ${str}: ***\n${it}"}
  } else {
    return delegate
  }

}

/*
   A simple logging function for everything that is not a queue
*/
def log(str) {
  if (params.debug) {
    println( "*** Parameters in use: ***")
    params.each { println "${it}" }
    println()
  }
}

// channel for SCENIC databases resources:
featherDB = Channel
    .fromPath( params.reference.db )
    .collect() // use all files together in the ctx command

n = Channel.fromPath(params.reference.db).count().get()
if( n==1 ) {
    println( """*** WARNING: only using a single feather database: ${featherDB.get()[0]}.
            |To include all database files using pattern matching, make sure the value for the
            |'--db' parameter is enclosed in quotes!
            """.stripMargin().stripIndent())
} else {
    println( "*** Using $n feather databases: ***")
      featherDB.get().each {
        println "  ${it}"
      }
}

/*
    GRN Inference
*/

GRN_std_input = Channel.from("""
            function:
                name: GRNinference
                command: pyscenic
                arguments:
                    - grn
                    - ${params.input.expr_loom}
                    - ${params.reference.TFs}
                parameters:
                    - name: num_workers
                      value: ${params.config.threads}
                    - name: method
                      value: ${params.config.grn}
                    - name: cell_id_attribute
                      value: ${params.loom.cell_id_attribute}
                    - name: gene_attribute
                      value: ${params.loom.gene_attribute}
                    - name: output
                      value: adj.tsv
            """.stripIndent()
).log("Input for GRNinference")

GRN_input = file("${params.input.expr_loom}")

GRN_dry = ISDRY ? "dry-run | tee adj.tsv" : ""

process GRNinference {

    container 'tverbeiren/pyscenic'

    // publishDir "${params.output.dir}", mode: 'copy', overwrite: false

    input:
    stdin GRN_std_input
    // file GRN_input

    output:
    stdout into GRN_output
    file 'adj.tsv' into GRN

    """
    porta.sh $GRN_dry
    """

}

GRN_output = GRN_output
              .log("Output from GRNinference")

/*
    i-cis Target
*/

cisTarget_input = Channel.from("""
            function:
                name: GRNinference
                command: pyscenic
                arguments:
                    - ctx
                    - adj.tsv
                    - ${params.reference.db}
                parameters:
                    - name: num_workers
                      value: ${params.config.threads}
                    - name: annotations_fname
                      value: ${params.reference.motifs}
                    - name: expression_mtx_fname
                      value: ${params.input.expr_loom}
                    - name: mode
                      value: dask_multiprocessing
                    - name: cell_id_attribute
                      value: ${params.loom.cell_id_attribute}
                    - name: gene_attribute
                      value: ${params.loom.gene_attribute}
                    - name: output
                      value: reg.csv
            """.stripIndent()
).log("cisTarget input")

cisTarget_dry = ISDRY ? "dry-run | tee reg.csv" : ""

process i_cisTarget {

    container 'tverbeiren/pyscenic'

    input:
    stdin cisTarget_input
    file 'adj.tsv' from GRN

    output:
    stdout into cisTarget_output
    file 'reg.csv' into regulons

    """
    porta.sh $cisTarget_dry
    """
}

cisTarget_output = cisTarget_output
                    .log("Output cisTarget")


/*
    AUCell
*/

AUCell_input = Channel.from("""
            function:
                name: GRNinference
                command: pyscenic
                arguments:
                    - aucell
                    - ${params.input.expr_loom}
                    - reg.csv
                parameters:
                    - name: num_workers
                      value: ${params.config.threads}
                    - name: cell_id_attribute
                      value: ${params.loom.cell_id_attribute}
                    - name: gene_attribute
                      value: ${params.loom.gene_attribute}
                    - name: output
                      value: auc.loom
            """.stripIndent()
        ).log("AUCell input")

AUCell_dry = ISDRY ? "dry-run | tee auc.loom" : ""

process AUCell {

    container 'tverbeiren/pyscenic'

    input:
    stdin AUCell_input
    file 'reg.csv' from regulons

    output:
    stdout into AUCell_output
    file 'auc.loom' into AUCmat

    """
    porta.sh $AUCell_dry
    """
}

AUCell_output = AUCell_output
              .log("Output from AUCell")

/*
    filter
*/

filter_input = Channel.from("""
        function:
            name: filter
            pre-hook: ls -al .
            command: python3 /home/app/code/filter.py
            parameters:
                - name: input-file
                  value: auc.loom
                - name: meta-data
                  value: ${params.filter.metadata}
                - name: output-file
                  value: output-filter.loom
            """.stripIndent()
        ).log("filter input")

filter_dry = ISDRY ? "dry-run | tee ${params.filter.output}" : ""

process filter {

    container 'filter'

    input:
    stdin filter_input
    file 'auc.loom' from AUCmat

    output:
    stdout into filter_output
    file "output-filter.loom" into filterOut

    """
    porta.sh 
    """
}

filter_output = filter_output
              .log("Output from filter")

filterOut.last().collectFile(storeDir:"${params.output.file}")

workflow.onComplete {
  // Display complete message
  log.info "Container used: " + workflow.container
  log.info "Completed at :  " + workflow.complete
  log.info "Duration    :   " + workflow.duration
  log.info "Success     :   " + workflow.success
  log.info "Exit status :   " + workflow.exitStatus
  log.info "Error report:   " + (workflow.errorReport ?: '-')
}

workflow.onError {
  // Display error message
  log.info "Workflow execution stopped with the following message:"
  log.info "  " + workflow.errorMessage
}
