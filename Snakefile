configfile: "config/config.yaml"

import os
from pathlib import Path

SAMPLE = Path(config["genome_fasta"]).stem
OUTDIR = config["outdir"]
THREADS = config["threads"]

RM_ENGINE = config["repeatmodeler"]["engine"]
RM_LTR_STRUCT = config["repeatmodeler"]["ltr_struct"]

MASK_ENGINE = config["repeatmasker"]["search_engine"]
MASK_SPECIES = config["repeatmasker"]["species"]
MASK_PARALLEL = config["repeatmasker"]["parallel"]


rule all:
    input:
        f"{OUTDIR}/{SAMPLE}.repeatmasker.gff",
        f"{OUTDIR}/{SAMPLE}.repeatmasker.out",
        f"{OUTDIR}/{SAMPLE}.repeatmasker.tbl",
        f"{OUTDIR}/{SAMPLE}.masked.fa",


rule index_genome:
    input:
        genome=config["genome_fasta"],
    output:
        directory(f"{OUTDIR}/{SAMPLE}_RMdb"),
    log:
        f"{OUTDIR}/logs/{SAMPLE}.builddatabase.log",
    threads: 1
    conda:
        "workflow/envs/repeatmodeler.yaml"
    shell:
        r"""
        mkdir -p $(dirname {log})
        BuildDatabase -name {output} {input.genome} > {log} 2>&1
        """


rule repeatmodeler:
    input:
        db=directory(f"{OUTDIR}/{SAMPLE}_RMdb"),
    output:
        library=f"{OUTDIR}/{SAMPLE}-families.fa",
        directory(f"{OUTDIR}/RM_{SAMPLE}_run"),
    output:
    threads: THREADS
    conda:
        "workflow/envs/repeatmodeler.yaml"
    log:
        f"{OUTDIR}/logs/{SAMPLE}.repeatmodeler.log",
    params:
        engine=RM_ENGINE,
        ltr_struct=RM_LTR_STRUCT,
    shell:
        r"""
        mkdir -p $(dirname {log})
        RepeatModeler -database {input.db} \
            -engine {params.engine} \
            -threads {threads} \
            $([ "{params.ltr_struct}" = "True" ] && echo "-LTRStruct") \
            > {log} 2>&1
        # RepeatModeler writes its results to a new RM_* directory; move the
        # consensus library into place and keep the run directory as output.
        rm -f {output.library}
        cp $(find {OUTDIR} -maxdepth 1 -type d -name 'RM_*' -newer {input.db} | sort | tail -n1)/consensi.fa.classified {output.library}
        """


rule repeatmasker:
    input:
        genome=config["genome_fasta"],
        library=f"{OUTDIR}/{SAMPLE}-families.fa",
    output:
        gff=f"{OUTDIR}/{SAMPLE}.repeatmasker.gff",
        out=f"{OUTDIR}/{SAMPLE}.repeatmasker.out",
        tbl=f"{OUTDIR}/{SAMPLE}.repeatmasker.tbl",
        masked=f"{OUTDIR}/{SAMPLE}.masked.fa",
    threads: MASK_PARALLEL
    conda:
        "workflow/envs/repeatmasker.yaml"
    log:
        f"{OUTDIR}/logs/{SAMPLE}.repeatmasker.log",
    params:
        engine=MASK_ENGINE,
        species=MASK_SPECIES,
    shell:
        r"""
        mkdir -p $(dirname {log})
        cp {input.genome} {output.masked}
        RepeatMasker -lib {input.library} \
            -engine {params.engine} \
            -parallel {threads} \
            -dir $(dirname {output.gff}) \
            $([ -n "{params.species}" ] && [ "{params.species}" != "None" ] && echo "-species {params.species}") \
            {output.masked} > {log} 2>&1
        mv {output.masked}.out {output.out}
        mv {output.masked}.out.gff {output.gff}
        mv {output.masked}.tbl {output.tbl}
        """
