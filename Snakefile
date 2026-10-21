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
        f"{OUTDIR}/{SAMPLE}_RMdb/genome_RMdb.nsq",
        f"{OUTDIR}/{SAMPLE}_RMdb/genome_RMdb.nin",
        f"{OUTDIR}/{SAMPLE}_RMdb/genome_RMdb.nhr",
        f"{OUTDIR}/{SAMPLE}_RMdb/genome_RMdb.nnd",
    log:
        f"logs/{SAMPLE}.builddatabase.log",
    threads: 1
    conda:
        "workflow/envs/repeatmodeler.yaml"
    shell:
        r"""
        mkdir -p $(dirname {output[0]})
        BuildDatabase -name {OUTDIR}/{SAMPLE}_RMdb/genome_RMdb {input.genome} > {log} 2>&1
        """


rule repeatmodeler:
    input:
        db=f"{OUTDIR}/{SAMPLE}_RMdb/genome_RMdb.nsq",
    output:
        library=f"{OUTDIR}/{SAMPLE}_RMdb/RMdb-families.fa",
        
    threads: THREADS
    conda:
        "workflow/envs/repeatmodeler.yaml"
    log:
        f"logs/{SAMPLE}.repeatmodeler.log",
    params:
        engine=RM_ENGINE,
        ltr_struct=RM_LTR_STRUCT,
    shell:
        r"""
        RepeatModeler -database {input.db} \
            -engine {params.engine} \
            -threads {threads} \
            $([ "{params.ltr_struct}" = "True" ] && echo "-LTRStruct") \
            > {log} 2>&1
        # RepeatModeler writes its results to the database directory
        """


rule repeatmasker:
    input:
        genome=config["genome_fasta"],
        library=f"{OUTDIR}/{SAMPLE}_RMdb/RMdb-families.fa",
    output:
        gff=f"{OUTDIR}/{SAMPLE}.repeatmasker.gff",
        out=f"{OUTDIR}/{SAMPLE}.repeatmasker.out",
        tbl=f"{OUTDIR}/{SAMPLE}.repeatmasker.tbl",
        masked=f"{OUTDIR}/{SAMPLE}.masked.fa",
    threads: MASK_PARALLEL
    conda:
        "workflow/envs/repeatmasker.yaml"
    log:
        f"logs/{SAMPLE}.repeatmasker.log",
    params:
        engine=MASK_ENGINE,
        species=MASK_SPECIES,
    shell:
        r"""
        cp {input.genome} {output.masked}
        FAMDB_DATA_DIR="$CONDA_PREFIX/share/RepeatMasker/Libraries"
        RepeatMasker -lib {input.library} \
            -engine {params.engine} \
            -gccalc \
            -s -noisy \
            -gff \
            -pa {threads} \
            -dir $(dirname {output.gff}) \
            $([ -n "{params.species}" ] && [ "{params.species}" != "None" ] && echo "-species {params.species}") \
            {output.masked} > {log} 2>&1
        mv -vf {output.masked}.out {output.out}
        mv -vf {output.masked}.out.gff {output.gff}
        mv -vf {output.masked}.tbl {output.tbl}
        """
