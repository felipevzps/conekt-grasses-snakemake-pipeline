#!/usr/bin/env python

#Usage

#snakemake -p -k --resources load=6 -s Snakefile --cluster "qsub -q all.q -V -cwd -l h={params.server} -pe smp {threads}" --jobs 6 --jobname "{rulename}.{jobid}"

configfile: "config.yaml"

import pandas as pd
from pandas.errors import EmptyDataError
import yaml
import os

GENOTYPE='Sviridis'
SEQTYPE='PAIRED'
samples = pd.read_csv(GENOTYPE+'_samples.csv')
reference_transcriptome = "Sviridis_726_v4.1.transcript_primaryTranscriptOnly.fa"

fastq_dump = config["software"]["fastq-dump"]
bbduk = config["software"]["bbduk"]
salmon = config["software"]["salmon"]
filter_salmon_output = config["software"]["filter_salmon_output"]
jq = config["software"]["jq"]
parse_filter = config["software"]["parse_filter"]

rule all:
	input:
		"preliminar_report.tsv",
		expand("{genotype}_{seqtype}_quantmerge.txt", genotype=GENOTYPE, seqtype=SEQTYPE)

rule download_fastq:
	"""
	Baixa os arquivos brutos (fastq) das leituras 1 e 2 das amostras do genotipo {params.genotype}.
	- Essa regra utiliza o sratoolkit para baixar as leituras
	- Nota: o parametro --defline-seq define o padrao do header das sequencias. Isso eh essencial para o funcionamento das proximas etapas do YATAAP
	"""
	priority: 1
	output:
		R1 = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_1.fastq",
		R2 = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_2.fastq"
	threads: 1
	resources:
		load=3
	params:
		genotype="{genotype}",
		server="figsrv"
	log:
		"datasets_{genotype}/logs/download_fastq/{sample}.log"
	shell:
		"{fastq_dump} --defline-seq '@$sn[_$rn]/$ri' --split-files {wildcards.sample} -O datasets_{params.genotype}/logs/download_fastq/{wildcards.sample}.log 2> {log}"

rule bbduk:
	"""
	Remove os adaptadores de sequenciamento com illumina (adapters.fa) dos arquivos brutos (fastq);
	Remove sequencias de RNA ribossomal (rRNA) dos arquivos brutos (fastq);
	Filtra sequencias por minlength=75 e qualidade < Q20.
	"""
	priority: 1
	input:
		R1 = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_1.fastq",
		R2 = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_2.fastq"
	output:
		R1 = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R1.fastq",
		R2 = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R2.fastq",
		refstats = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.refstats",
		stats = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.stats"
	log:
		"datasets_{genotype}/logs/bbduk/{sample}.log"
	threads: 5
	resources:
		load=2
	params:
		server="figsrv"
	name: "bbduk"
	shell:
		"{bbduk} -Xmx40g threads={threads} in1={input.R1} in2={input.R2} "
		"refstats={output.refstats} stats={output.stats} "
		"out1={output.R1} out2={output.R2} "
		"rref=bbduk_resources/bbmap_35.85/resources/adapters.fa "
		"fref=bbduk_resources/sortmerna-2.1b/rRNA_databases/rfam-5.8s-database-id98.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/silva-bac-16s-id90.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/rfam-5s-database-id98.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/silva-bac-23s-id98.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/silva-arc-16s-id95.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/silva-euk-18s-id95.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/silva-arc-23s-id98.fasta,"
		"bbduk_resources/sortmerna-2.1b/rRNA_databases/silva-euk-28s-id98.fasta "
		"minlength=75 qtrim=w trimq=20 tpe tbo > {log} 2>&1"

rule count_raw_sequences:
	"""
	Conta o numero de sequencias nos arquivos brutos (fastq) das leituras 1 e 2;
	Remove os arquivos brutos (fastq) das leituras 1 e 2.
	"""
	priority: 1
	input:
		R1 = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_1.fastq",
		R2 = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_2.fastq",
		R1_trimmed = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R1.fastq",
		R2_trimmed = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R2.fastq"
	output:
		R1_rawstats = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_1.stats.txt",
		R2_rawstats = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_2.stats.txt"
	threads: 1
	resources:
		load = 1
	params:
		genotype="{genotype}",
		server="figsrv"
	log:
		"datasets_{genotype}/logs/count_raw_sequences/{sample}.log"
	name: "count_raw_sequences"
	shell:
		"""
		cat {input.R1} | grep -c "@SRR" > {output.R1_rawstats} 2>> {log}
		echo "sequences: $(cat {output.R1_rawstats})" > {output.R1_rawstats} 2>> {log}
		rm {input.R1} 2>> {log} 
		
		cat {input.R2} | grep -c "@SRR" > {output.R2_rawstats} 2>> {log}
		echo "sequences: $(cat {output.R2_rawstats})" > {output.R2_rawstats} 2>> {log}
		rm {input.R2} 2>> {log}
		"""

rule salmon_index:
	"""
	Gera um index do salmon para a quantificacao das leituras trimmadas.
	"""
	priority: 1
	input:
		transcriptome=reference_transcriptome
	output:
		salmon_index=directory("datasets_{genotype}/3_salmon/index/")
	params:
		server="figsrv"
	resources:
		load=1
	threads: 1
	#log:
	#	"datasets_{wildcards.genotype}/logs/salmon/index/{wildcards.genotype}.log"
	name: "salmon_index"
	shell:
		"""
		/usr/bin/time -v {salmon} index -t {input.transcriptome} -p {threads} -i {output.salmon_index}
		"""

rule salmon_quant:
	"""
	Quantifica as leituras trimmadas contra o indice do salmon criado anteriormente
	"""
	priority: 1
	input:
		salmon_index = "datasets_{genotype}/3_salmon/index/",
                R1 = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R1.fastq",
                R2 = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R2.fastq"
	output:
		"datasets_{genotype}/3_salmon/quant/{sample}/aux_info/meta_info.json",
		"datasets_{genotype}/3_salmon/quant/{sample}/quant.sf"
	params:
		server="figsrv",
		genotype="{genotype}"	
	resources:
		load=1
	threads: 1
	log:
		"datasets_{genotype}/logs/salmon/quant/{sample}.log"
	name: "salmon_quant"
	shell:
		"""
		/usr/bin/time -v {salmon} quant -i {input.salmon_index} -l A -1 {input.R1} -2 {input.R2} -o datasets_{params.genotype}/3_salmon/quant/{wildcards.sample} > {log} 2>&1
		"""

rule count_trimmed_sequences:
	"""
	Conta o numero de sequencias nos arquivos trimmados (fastq) das leituras 1 e 2 apos o controle de qualidade com bbduk.
	Remove os arquivos trimmados (fastq) das leituras 1 e 2 apos a quantificacao.
	"""
	priority: 1
	input:
		R1 = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R1.fastq",
		R2 = "datasets_{genotype}/2_trimmed_reads/{sample}.trimmed.R2.fastq",
		salmon_quant = "datasets_{genotype}/3_salmon/quant/{sample}/quant.sf",
		R1_rawstats = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_1.stats.txt",
		R2_rawstats = "datasets_{genotype}/1_raw_reads_in_fastq_format/{sample}_2.stats.txt"
	output:
		R1_trimmedstats = "datasets_{genotype}/2_trimmed_reads/{sample}_1.stats.txt",
		R2_trimmedstats = "datasets_{genotype}/2_trimmed_reads/{sample}_2.stats.txt"
	threads: 1
	resources:
		load = 1
	params:
		genotype="{genotype}",
		server="figsrv"
	log:
		"datasets_{genotype}/logs/count_trimmed_sequences/{sample}.log"
	name: "count_trimmed_sequences"
	shell:
		"""
		cat {input.R1} | grep -c "@SRR" > {output.R1_trimmedstats} 2>> {log}
		echo "sequences: $(cat {output.R1_trimmedstats})" > {output.R1_trimmedstats} 2>> {log}
		rm {input.R1} 2>> {log}

		cat {input.R2} | grep -c "@SRR" > {output.R2_trimmedstats} 2>> {log}
		echo "sequences: $(cat {output.R2_trimmedstats})" > {output.R2_trimmedstats} 2>> {log}
		rm {input.R2} 2>> {log}
		"""

rule filter_stranded:
	"""
	Filtra leituras stranded e pareadas (ISR) apos quantificacao
	"""
	priority: 1
	input:
		meta_info = expand("datasets_{genotype}/3_salmon/quant/{sample}/aux_info/meta_info.json", genotype=GENOTYPE, sample=samples),
		R1_trimmedstats = expand("datasets_{genotype}/2_trimmed_reads/{sample}_1.stats.txt", genotype=GENOTYPE, sample=samples),
		R2_trimmedstats = expand("datasets_{genotype}/2_trimmed_reads/{sample}_2.stats.txt", genotype=GENOTYPE, sample=samples)
	output:
		filtered_samples = "datasets_{genotype}/3_salmon/quant/{genotype}_{seqtype}_srrlist.csv"
	threads: 1
	resources:
		load=1
	params:
		seqtype="{seqtype}",
		genotype="{genotype}",
		server="figsrv"
	log:
		"datasets_{genotype}/logs/filter_stranded/{genotype}_{seqtype}.log"
	name: "filter_stranded"
	shell:
		"""
		{jq} -r '.library_types[]' {input.meta_info} > datasets_{params.genotype}/3_salmon/quant/lib.txt 2>> {log}
		ls datasets_{wildcards.genotype}/3_salmon/quant/ | grep SRR > datasets_{params.genotype}/3_salmon/quant/id.txt 2>> {log}
		paste datasets_{params.genotype}/3_salmon/quant/id.txt datasets_{params.genotype}/3_salmon/quant/lib.txt -d, > datasets_{params.genotype}/3_salmon/quant/stranded_status.csv 2>> {log}
		grep .S datasets_{params.genotype}/3_salmon/quant/stranded_status.csv > datasets_{params.genotype}/3_salmon/quant/stranded_samples.csv 2>> {log}
		cut -f1 -d, datasets_{params.genotype}/3_salmon/quant/stranded_samples.csv | paste -s -d, > datasets_{params.genotype}/3_salmon/quant/{params.genotype}_{params.seqtype}_srrlist.csv 2>> {log}
		"""

def get_filter_stranded_samples(wildcards):
	#this file is created by filter_stranded (rule above)
	try:
		with open(f"datasets_{wildcards.genotype}/3_salmon/quant/{wildcards.genotype}_{wildcards.seqtype}_srrlist.csv", "r") as f1:
			stranded_samples = pd.read_csv(f1)
		return stranded_samples
	except EmptyDataError:
		print("Empty file - {f1}")

rule filter_low_mapping_reads:
	"""
	Filtra leituras por mapping_rate e low_perc_mapping com o script filter_salmon_output.py
	"""
	priority: 1
	input:
		expand("datasets_{genotype}/3_salmon/quant/{genotype}_{seqtype}_srrlist.csv",genotype=GENOTYPE, seqtype=SEQTYPE),
		expand("datasets_{genotype}/3_salmon/quant/{sample}/quant.sf", genotype=GENOTYPE, sample=samples),
		expand("datasets_{genotype}/3_salmon/quant/{sample}/aux_info/meta_info.json", genotype=GENOTYPE, sample=samples)
	output:
                "{genotype}_{seqtype}_filter_stats.txt",
		"{genotype}_{seqtype}_srrlist_LowMapping_LowReads.csv"
	threads: 1
	params:
		server="figsrv",
		seqtype="{seqtype}",
		genotype="{genotype}",
		stranded_samples=get_filter_stranded_samples
	resources:
		load=1
	log:
		"datasets_{genotype}/logs/filter_low_mapping/{genotype}_{seqtype}_filter.log"
	name: "filter_low_mapping_reads"
	shell:
		"""
		{filter_salmon_output} --genotype {params.genotype} --stranded_samples datasets_{params.genotype}/3_salmon/quant/{params.genotype}_{params.seqtype}_srrlist.csv > {log} 2>&1
		"""

def get_filter_low_mapping_samples(wildcards):
	salmon_path = f"datasets_{wildcards.genotype}/3_salmon/quant/"
	filter_file = f"{wildcards.genotype}_{wildcards.seqtype}_srrlist_LowMapping_LowReads.csv"
	try:
		with open(filter_file, "r") as f2:
			filter_low_mapping_samples = list(pd.read_csv(f2))
			file_paths = [os.path.join(salmon_path, sample) for sample in filter_low_mapping_samples]
		return ' '.join(file_paths)
	except EmptyDataError:
		print(f"Empty file - {filter_file}")

rule preliminar_report:
	"""
	Gera um relatorio preliminar com as estatisticas das leituras quantificadas
	"""
	priority: 1
	input: 
		accessions = expand("{genotype}_samples.csv", genotype=GENOTYPE),
		paired_srrlist = expand("{genotype}_{seqtype}_srrlist_LowMapping_LowReads.csv",genotype=GENOTYPE, seqtype=SEQTYPE),
		filter_stats = expand("{genotype}_{seqtype}_filter_stats.txt", genotype=GENOTYPE, seqtype=SEQTYPE),
	output:
		"preliminar_report.tsv"
	threads: 1
	resources:
		load = 1
	params: 
		server="figsrv"
	log:
		expand("datasets_{genotype}/logs/preliminar_report/preliminar_report.log", genotype=GENOTYPE)
	name: "preliminar_report"
	conda: "parse_filters.yaml"
	shell:
		"""
		sed -e 's/,/\\n/g' {input.accessions} >> {input.accessions}.temp 2>> {log}
		sed -e 's/,/\\n/g' {input.paired_srrlist} >> {input.paired_srrlist}.temp 2>> {log}
		sed -e 's/\\t/,/g' {input.filter_stats} >> {input.filter_stats}.temp 2>> {log}
		{parse_filter} --accessions {input.accessions}.temp --paired_srrlist {input.paired_srrlist}.temp --filter_stats {input.filter_stats}.temp 2>> {log}
		rm {input.accessions}.temp 2>> {log}
		rm {input.paired_srrlist}.temp 2>> {log}
		rm {input.filter_stats}.temp 2>> {log}
		"""

rule merge_quantification_results:
	"""
	Gera a matriz de expressao com o salmon quantmerge
	"""
	priority: 1
	input:
		expand("{genotype}_{seqtype}_srrlist_LowMapping_LowReads.csv", genotype=GENOTYPE, seqtype=SEQTYPE),
	output:
		"{genotype}_{seqtype}_quantmerge.txt"
	threads: 1
	resources:
		load=1
	params:
		genotype="{genotype}",
		seqtype="{seqtype}",
		server="figsrv",
		datasets = expand("datasets_{genotype}/3_salmon/quant/", genotype=GENOTYPE),
		filter_low_mapping_samples=get_filter_low_mapping_samples
	log:
		"datasets_{genotype}/logs/generate_expression_matrix/{genotype}_{seqtype}_expression_matrix.log"
	name: "merge_quantification_results"
	shell:
		"""
		/usr/bin/time -v {salmon} quantmerge --quants {params.filter_low_mapping_samples} -o {params.genotype}_{params.seqtype}_quantmerge.txt > {log} 2>&1
		"""
