# 🌾 Conekt Grasses – Snakemake Pipeline

This repository contains a Snakemake pipeline for reproducing the analysis of the Conekt Grasses dataset - from raw data to gene expression matrices and reports.

---

## 🚀 Getting Started - Testing with Example Samples
Follow the steps below to reproduce the pipeline:

1. Clone this repository
```bash
git clone https://github.com/felipevzps/conekt-grasses-snakemake-pipeline.git
cd conekt-grasses-snakemake-pipeline

# before starting, note that we have some example samples:
ls datasets_Sviridis/1_raw_reads_in_fastq_format/
SRR7771987_1.fastq  SRR7771990_1.fastq  SRR7771991_1.fastq
SRR7771987_2.fastq  SRR7771990_2.fastq  SRR7771991_2.fastq
```

2. Set up the Conda environment  
Create the environment using conda with all dependencies (including `Snakemake v7.25.0`):
```bash
# installing conda env - this might take some time...
conda env create -n conekt-grasses-snakemake-pipeline -f environment.yaml

# activating the environment
conda activate conekt-grasses-snakemake-pipeline
```

3. Prepare files  
Uncompress the required resources:

```bash
tar -xzvf bbduk_resources.tar.gz
gunzip Sviridis_726_v4.1.transcript_primaryTranscriptOnly.fa.gz
```

4. Run the pipeline  
Start with a dry run to make sure everything is set up correctly:
```bash
snakemake -np
```
>[!NOTE]
>This will list all planned steps, from downloading raw reads to generating quantification matrices and reports.

Once it looks good, run the pipeline:
```bash
qsub Snakefile.sh
```

---

## NOTE 01

On the first run, the pipeline will fail with the example samples, since they contain only a small subset of 2,500 reads.  

You can see it here:
```bash
cat Snakefile.sh.e*
```

Because of this, `Salmon` classifies these samples with the library type "IU", while our pipeline is configured to filter only samples classified as "ISR", which results in no samples being included in the final matrix.

To hack this process and make the example samples compatible, we manually change the library type from "IU" to "ISR" in the `meta_info.json` files:

```bash
# substitute "IU" for "ISR"
for file in datasets_Sviridis/3_salmon/quant/SRR7771987/aux_info/meta_info.json datasets_Sviridis/3_salmon/quant/SRR7771990/aux_info/meta_info.json datasets_Sviridis/3_salmon/quant/SRR7771991/aux_info/meta_info.json; do sed -i 's/"IU"/"ISR"/g' "$file"; done

# remove generated files with "IU" library type
rm datasets_Sviridis/3_salmon/quant/*.txt datasets_Sviridis/3_salmon/quant/*.csv
```
After that, re-running the pipeline will work as expected and produce the final expression matrix.  
Just run it again:

```bash
qsub Snakefile.sh
```

>[!IMPORTANT]
>This is only a quick hack to allow the pipeline to complete with these small demonstration samples.  
>For real RNA-seq data, this step is not necessary. It is meant solely to demonstrate the pipeline using a tiny subset of reads.

---

## NOTE 02

In this test, we deliberately lowered the filtering thresholds in [filter_salmon_output.py](https://github.com/felipevzps/conekt-grasses-snakemake-pipeline/blob/main/filter_salmon_output.py) so that all example samples are included, even though they have extremely low mapping rates and TPM expression.

We modified the filter as follows:

```python
if (data['percent_mapped'] <= 1) or (perc_low_tpm >= 99.9):  # relaxed filter for testing
    pass
else:
    good_quality_samples.append(sample_name)
```
This allows the example samples to pass the quality check step, enabling the rest of the pipeline to run normally.   **These thresholds should not be used with real RNA-seq data.**

>[!IMPORTANT]
>For real RNA-seq data, you must set appropriate thresholds to retain only high-quality samples.

Recommended default values:

```python
if (data['percent_mapped'] <= 40) or (perc_low_tpm >= 60):
    pass
else:
    good_quality_samples.append(sample_name)
```
These thresholds ensure that only samples with good mapping rates and expression profiles are retained in the final matrix.
