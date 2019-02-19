#!/usr/bin/env nextflow

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
    .fromPath( params.db )
    .collect() // use all files together in the ctx command

n = Channel.fromPath(params.db).count().get()
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

expr = file(params.expr)
tfs = file(params.TFs)
motifs = file(params.motifs)
exprMat = file(params.expr)

GRN_input = Channel.from("""
            function:
                name: GRNinference
                command: pyscenic
                arguments:
                    - grn
                    - ${params.expr}
                    - ${params.TFs}
                parameters:
                    - name: num_workers
                      value: ${params.threads}
                    - name: method
                      value: ${params.grn}
                    - name: cell_id_attribute
                      value: ${params.loom.cell_id_attribute}
                    - name: gene_attribute
                      value: ${params.loom.gene_attribute}
                    - name: output
                      value: adj.tsv
            """.stripIndent()
).log("Input for GRNinference")

process GRNinference {

    input:
    stdin GRN_input
    /* input files can be listed individually as well */

    output:
    stdout into GRN_output
    file 'adj.tsv' into GRN

    """
    porta.sh
    """

}

GRN_output = GRN_output
              .log("Output from GRNinference")

/* *** Example of parsing YAML ***
import org.yaml.snakeyaml.Yaml
Yaml yaml = new Yaml()

GRN_output.map{ 
    def obj = yaml.load(it)
    println("Function: " + obj.function)
}.log("transformed YAML")
*/

cisTarget_input = Channel.from("""
            function:
                name: GRNinference
                command: pyscenic
                arguments:
                    - ctx
                    - adj.tsv
                    - ${params.db}
                parameters:
                    - name: num_workers
                      value: ${params.threads}
                    - name: annotations_fname
                      value: ${params.motifs}
                    - name: expression_mtx_fname
                      value: ${params.expr}
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

process i_cisTarget {

    input:
    stdin cisTarget_input
    file 'adj.tsv' from GRN

    output:
    stdout into cisTarget_output
    file 'reg.csv' into regulons

    """
    porta.sh
    """
}

cisTarget_output = cisTarget_output
                    .log("Output cisTarget")

AUCell_input = Channel.from("""
            function:
                name: GRNinference
                command: pyscenic
                arguments:
                    - aucell
                    - ${params.expr_loom}
                    - reg.csv
                parameters:
                    - name: num_workers
                      value: ${params.threads}
                    - name: cell_id_attribute
                      value: ${params.loom.cell_id_attribute}
                    - name: gene_attribute
                      value: ${params.loom.gene_attribute}
                    - name: output
                      value: auc.loom
            """.stripIndent()
        ).log("AUCell input")

process AUCell {

    input:
    stdin AUCell_input
    file 'reg.csv' from regulons

    output:
    stdout into AUCell_output
    file 'auc.loom' into AUCmat

    """
    porta.sh
    """
}

AUCmat.last().collectFile(storeDir:"${params.output}")

AUCell_output = AUCell_output
              .log("Output from AUCell")

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
