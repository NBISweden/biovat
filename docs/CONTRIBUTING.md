---
title: Contributing
markdownPlugin: checklist
---

# `BioVAT`: Contributing guidelines

Thanks for taking an interest in improving BioVAT.

This page describes the recommended way to contribute to BioVAT, 
based on general recommendations for nf-core pipelines. 

## Contribution quick start for BioVAT project members

To contribute code to the pipeline:

- [ ] Ensure you have Nextflow, nf-core tools, and nf-test installed. See the [nf-core/tools repository](https://github.com/nf-core/tools) for instructions.
- [ ] Check whether a GitHub [issue](https://github.com/BioVAT/issues) about your idea already exists. If an issue does not exist, create one so that others are aware you are working on it.
- [ ] Create a branch from `dev` and make your changes following [pipeline conventions](#pipeline-contribution-conventions) (if applicable).
- [ ] Update relevant documentation within the `docs/` folder, use nf-core/tools to update `nextflow_schema.json`, and update `CITATIONS.md`.
- [ ] Run and/or update tests. See [Testing](#testing) for more information.
- [ ] [Lint](#lint-tests) your code with nf-core/tools.
- [ ] Submit a pull request (PR) against the `dev` branch and request a review.

If you are not used to this workflow with Git, see the 
[GitHub documentation](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests) 
or [Git resources](https://try.github.io/) for more information. 

## Contribution quick start for external contributions

To contribute code to the pipeline:

- [ ] Ensure you have Nextflow, nf-core tools, and nf-test installed. See the [nf-core/tools repository](https://github.com/nf-core/tools) for instructions.
- [ ] Check whether a GitHub [issue](https://github.com/BioVAT/issues) about your idea already exists. If an issue does not exist, create one so that others are aware you are working on it.
- [ ] [Fork](https://help.github.com/en/github/getting-started-with-github/fork-a-repo) the [BioVAT repository](https://github.com/BioVAT) to your GitHub account.
- [ ] Create a branch on your forked repository and make your changes following [pipeline conventions](#pipeline-contribution-conventions) (if applicable).
- [ ] To fix major bugs, name your branch `patch` and follow the [patch release](#patch-release) process.
- [ ] Update relevant documentation within the `docs/` folder, use nf-core/tools to update `nextflow_schema.json`, and update `CITATIONS.md`.
- [ ] Run and/or update tests. See [Testing](#testing) for more information.
- [ ] [Lint](#lint-tests) your code with nf-core/tools.
- [ ] Submit a pull request (PR) against the `dev` branch and request a review.

If you are not used to this workflow with Git, see the 
[GitHub documentation](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests) 
or [Git resources](https://try.github.io/) for more information. 

## Testing

Once you have made your changes, run the pipeline with nf-test 
to test them locally.For additional information, use the `--verbose` 
flag to view the Nextflow console log output. 

```bash
nf-test test --tag test --profile +docker --verbose
```

If you have added new functionality, ensure you update the 
test assertions in the `.nf.test` files in the `tests/` 
directory. Update the snapshots with the following command: 

```bash
nf-test test --tag test --profile +docker --verbose --update-snapshots
```

When you create a pull request with changes, GitHub Actions 
will run automatic tests. Pull requests are typically reviewed 
when these tests are passing. 

Two types of tests are typically run:

### Lint tests

nf-core has a [set of guidelines](https://nf-co.re/docs/specifications/overview) 
which all pipelines must follow. To enforce these, run 
linting with nf-core/tools: 

```bash
nf-core pipelines lint <pipeline_directory>
```

If you encounter failures or warnings, follow the linked 
documentation printed to screen. For more information about 
linting tests, see 
[nf-core/tools API documentation](https://nf-co.re/docs/nf-core-tools/api_reference/latest/pipeline_lint_tests/actions_awsfulltest).

### Pipeline tests

The BioVAT pipeline will be set up with a minimal set of 
test data. GitHub Actions will run the pipeline on this data 
to ensure it runs through and exits successfully.  
If there are any failures then the automated tests will fail. 
These tests will be run with the latest available version of 
Nextflow and the minimum required version specified in 
the pipeline code. 

## Pipeline contribution conventions

We are following nf-core guidelines to write code and other 
contributions to make the BioVAT code and processing logic 
more understandable for new contributors and to ensure quality. 

### Add a new pipeline step

To contribute a new step to the pipeline, follow the general 
nf-core coding procedure. Please also refer to the 
[pipeline-specific contribution guidelines](#pipeline-specific-contribution-guidelines): 

- [ ] Define the corresponding [input channel](#channel-naming-schemes) into your new process from the expected previous process channel.
- [ ] Install a module with nf-core/tools, or write a local module (see [default processes resource requirements](#default-processes-resource-requirements)), and add it to the target `<workflow>.nf`.
- [ ] Define the output channel if needed. Mix the version output channel into `ch_versions` and relevant files into `ch_multiqc`.
- [ ] Add new or updated parameters to `nextflow.config` with a [default value](#default-parameter-values).
- [ ] Add new or updated parameters and relevant help text to `nextflow_schema.json` with [nf-core/tools](#default-parameter-values).
- [ ] Add validation for relevant parameters to the pipeline utilisation section of `utils_nfcore_\_pipeline/main.nf` subworkflow.
- [ ] Perform local tests to validate that the new code works as expected.
  - [ ] If applicable, add a new test in the `tests` directory.
- [ ] Update `usage.md`, `output.md`, and `citation.md` as appropriate.
- [ ] [Lint](lint) the code with nf-core/tools.
- [ ] Update any diagrams or pipeline images as necessary.
- [ ] Update MultiQC config `assets/multiqc_config.yml` so relevant suffixes, file name cleanup, and module plots are in the appropriate order.
- [ ] If applicable, create a [MultiQC](https://seqera.io/multiqc/) module.
- [ ] Add a description of the output files and, if relevant, images from the MultiQC report to `docs/output.md`.

To update the minimum required Nextflow version, see the 
[Nextflow version bumping](#nextflow-version-bumping) section 
below. For more information about pipeline contributions, see 
[pipeline-specific contribution guidelines](#pipeline-specific-contribution-guidelines).

### Channel naming schemes

Use the following naming schemes for channels to make the 
channel flow easier to understand: 

- Initial process channel: `ch_output_from_<process>`
- Intermediate and terminal channels: `ch_<previousprocess>_for_<nextprocess>`

### Default parameter values

Parameters should be initialised and defined with default 
values within the `params` scope in `nextflow.config`. 
They should also be documented in the pipeline JSON schema. 

To update `nextflow_schema.json`, run: 

```bash
nf-core pipelines schema build
```

The schema builder interface that loads in your browser 
should automatically update the defaults in the parameter 
documentation. 

### Default processes resource requirements

If you write a local module, specify a default set of 
resource requirements for the process.

Sensible defaults for process resource requirements (CPUs, 
memory, time) should be defined in `conf/base.config`. 
Specify these with generic `withLabel:` selectors, so they 
can be shared across multiple processes and steps of the 
pipeline.

Values assigned within these labels can be dynamically passed 
to a tool using the the `${task.cpus}` and `${task.memory}` 
Nextflow variables in the `script:` block of a module (see 
an example in the [modules repository](https://github.com/nf-core/modules/blob/bd1b6a40f55933d94b8c9ca94ec8c1ea0eaf4b82/modules/nf-core/samtools/bam2fq/main.nf#L30)).

### Nextflow version bumping

If you use a new feature from core Nextflow, bump the minimum 
required Nextflow version in the pipeline with: 

```bash
nf-core pipelines bump-version --nextflow . <min_nf_version>
```

## BioVAT specific contribution guidelines

<!-- TODO: Add any BioVAT specific contribution guidelines here, such as coding styles, procedures, checklists etc. -->

### Issues 

- Always assign issues to pipeline developers and to pull requests
- Please use the issue template (to be added)
- Use issue labels and milestones

### Pull requests and code reviewing

- The main branch is protected and expected to be stable. It will be only allowed to get pull requests from dev 
- Please use pull requests and avoid direct merging of branches 
- Always assign one of the main contributors to BioVAT for code review of your pull request
- Please use the pull request template to describe your proposed changes (to be added)

### Best practices

- Please follow these best practice recommendations for Nextflow pipelines: https://nbisweden.github.io/Training-Tech-shorts/posts/2025-12-11-nextflow-best-practices/ 
