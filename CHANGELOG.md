# Changelog

## 1.0.0 (2026-11-13)


### Features

* **ci-failure-comment:** mention a bot on the pull request whose CI failed ([82de0e9](https://github.com/lcnascimento/gh-workflows/commit/82de0e9e99e41bf1ab3076084017617f3a2a75d7))
* **ci:** optional test levels, coverage artifact and doppler (HLB-206) ([4eac7ea](https://github.com/lcnascimento/gh-workflows/commit/4eac7ea24de79edfe0d3c13552e587cc520314fc))
* **ci:** run setup, lint, format and test.unit of the Makefile Contract ([6cfb021](https://github.com/lcnascimento/gh-workflows/commit/6cfb0210d59ed5ca9b396e165a84f1a798cd9fe7))
* **lint-workflows:** run actionlint and zizmor over the caller workflows ([19c8920](https://github.com/lcnascimento/gh-workflows/commit/19c892047df80f245a870f68531def49f38b4881))
* **renovate:** add the shared Renovate preset extended by consumers and this repo ([8cac33f](https://github.com/lcnascimento/gh-workflows/commit/8cac33f3a929a983af1b5a5151cfe37609f861bf))
* reusable workflows v1.0.0 ([6904686](https://github.com/lcnascimento/gh-workflows/commit/690468671f08fd65f78c5bf674b4423ae59c1476))
* **setup-runtime:** install Node, uv and OpenTofu from their manifests ([b5bcd44](https://github.com/lcnascimento/gh-workflows/commit/b5bcd4487f93c04c7f299aaec5dd51bd20a33826))
* **sonarqube:** add sonarqube.yml and nest it in ci.yml ([6aaad3a](https://github.com/lcnascimento/gh-workflows/commit/6aaad3af793a2b07f10d34f3d09701226025e9fd))


### Bug Fixes

* **ci:** lint the workflows at the repository root ([ea4daf0](https://github.com/lcnascimento/gh-workflows/commit/ea4daf05e0d77b0f8f316901d3f0cc0c22f256e6))
* **ci:** pass the Doppler token only to the doppler run step ([0f86165](https://github.com/lcnascimento/gh-workflows/commit/0f86165e485630e38cf8ea0a40081a4c546f99cf))
* **examples:** accept the workflow_run trigger of ci-failure ([b9b0c20](https://github.com/lcnascimento/gh-workflows/commit/b9b0c2014f220ac503f12679cae5c6c31838241e))
* **sonarqube:** download each coverage prefix into its own directory ([34e16f7](https://github.com/lcnascimento/gh-workflows/commit/34e16f7220834dc762fdfd3ad1e7e2a9013acc23))
* **sonarqube:** resolve the project key once in sonar-args ([f56beaa](https://github.com/lcnascimento/gh-workflows/commit/f56beaacc25fcca4988594bd7772d93035f724e8))
* **sonarqube:** tolerate a run without coverage artifacts ([6e2ab09](https://github.com/lcnascimento/gh-workflows/commit/6e2ab09e286d69a9176a7f669fef646e5873c4e2))
