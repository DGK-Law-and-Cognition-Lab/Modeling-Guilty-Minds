# Inferring Criminal Mental States from Behavioral Evidence

**Laypeople distinguish Model Penal Code categories but treat knowledge as qualitatively distinct**

David G. Kamper, Andrew Bistras, Keith J. Holyoak, & Jaime Castrellon  
Department of Psychology, University of California, Los Angeles

---

This repository contains all data, experimental materials, analysis code, and publication figures for the study described in Kamper, Bistras, Holyoak, & Castrellon (2025). A companion landing page is hosted at **[dgk-law-and-cognition-lab.github.io/Modeling-Guilty-Minds](https://dgk-law-and-cognition-lab.github.io/Modeling-Guilty-Minds/)**.

## Repository Structure

```
├── index.html                  ← GitHub Pages landing page
├── data/
│   └── modeling_mental_states_analysis_part3.csv
├── experiment/
│   ├── index.html              ← jsPsych experiment entry point
│   ├── experiment.js           ← Task logic and timeline
│   ├── style.css               ← Experiment styling
│   ├── trialMinimisation.js    ← Adaptive trial selection algorithm
│   └── mensReaVignettes_binary.json  ← Vignette stimuli (64 configurations)
├── analysis/
│   ├── MPC_MainAnalysis_Updated.Rmd          ← Cumulative link mixed models (R source)
│   ├── MPC_MainAnalysis_Updated.html         ← Rendered report (viewable in browser)
│   ├── MPC_PowerAnalysis.Rmd                 ← Power analysis (R source)
│   ├── MPC_PowerAnalysis.html                ← Rendered report (viewable in browser)
│   ├── MPC_NLP_SHAP_Analysis_2_0.ipynb       ← NLP, Random Forest, SHAP, RSA (Python source)
│   └── MPC_NLP_SHAP_Analysis_New_CleanedforHTML_2_0.html  ← Rendered report (viewable in browser)
└── figures/
    ├── fig1_judgment_distribution.pdf
    ├── fig2_risk_by_judgment.pdf
    ├── fig3_predicted_probabilities.pdf
    ├── fig4_forest_plot.pdf
    ├── fig5_proportional_odds.pdf
    ├── fig_shap_*.pdf
    ├── fig_rf_confusion_matrix.pdf
    ├── fig_rsa_scatter.pdf
    └── ...  (color and black-and-white variants)
```

## Overview

The Model Penal Code (MPC) distinguishes four levels of criminal culpability -- purpose, knowledge, recklessness, and negligence -- yet whether laypeople can reliably make these distinctions through genuine inference remains unclear. Prior studies either presented participants with explicitly labeled mental states or asked for self-assessed judgments under artificial precision. We addressed this gap by requiring 212 participants to infer a protagonist's mental state from behavioral evidence in contraband smuggling vignettes with six systematically varied binary features.

Cumulative link mixed models showed that participants' risk assessments strongly predicted their categorizations, and that payment was the only vignette feature to independently shift judgments toward higher culpability after correction for multiple comparisons. Critically, knowledge judgments were associated with *lower* risk ratings than recklessness judgments, and the proportional odds assumption was violated at the knowledge threshold. A features-only Random Forest with SHAP analysis revealed that knowledge was the only category where the type of contraband rather than payment dominated feature importance. These results indicate that laypeople can systematically distinguish MPC mental states through inferential reasoning, but that knowledge functions as a qualitatively distinct category driven by categorical inference rather than extreme risk perception.

## Rendered Analysis Reports

The `analysis/` folder contains both source code and pre-rendered HTML reports that can be viewed directly in the browser via the landing page:

- **[Main Analysis](https://dgk-law-and-cognition-lab.github.io/Modeling-Guilty-Minds/analysis/MPC_MainAnalysis_Updated.html)** -- Cumulative link mixed models, threshold-specific diagnostics, and proportional odds tests
- **[NLP, SHAP, & RSA Analysis](https://dgk-law-and-cognition-lab.github.io/Modeling-Guilty-Minds/analysis/MPC_NLP_SHAP_Analysis_New_CleanedforHTML_2_0.html)** -- Random Forest classification, SHAP feature importance, representational similarity analysis, and BERTopic
- **[Power Analysis](https://dgk-law-and-cognition-lab.github.io/Modeling-Guilty-Minds/analysis/MPC_PowerAnalysis.html)** -- Sample size justification and simulation-based power estimates

## Preregistration

The study design is preregistered on the Open Science Framework: **[osf.io/72eg9](https://osf.io/72eg9)**

## Ethics

This study was approved by the University of California, Los Angeles Institutional Review Board (IRB-25-0295). All participants provided informed consent prior to participation.

## Citation

Kamper, D. G., Bistras, A., Holyoak, K. J., & Castrellon, J. (2025). Inferring criminal mental states from behavioral evidence: Laypeople distinguish Model Penal Code categories but treat knowledge as qualitatively distinct. *Manuscript in preparation.* University of California, Los Angeles.

```bibtex
@article{kamper2025inferring,
  title     = {Inferring criminal mental states from behavioral evidence: Laypeople distinguish Model Penal Code categories but treat knowledge as qualitatively distinct},
  author    = {Kamper, David G. and Bistras, Andrew and Holyoak, Keith J. and Castrellon, Jaime},
  year      = {2025},
  note      = {Manuscript in preparation},
  institution = {University of California, Los Angeles}
}
```

## Contact

Correspondence: David G. Kamper (davidgkamper@ucla.edu) · [DGK Law & Cognition Lab](https://github.com/DGK-Law-and-Cognition-Lab) · UCLA Department of Psychology
