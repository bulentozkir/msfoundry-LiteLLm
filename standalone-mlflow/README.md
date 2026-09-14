# Standalone MLflow

**Naming note:** renamed from `standalone-litellm`; the Terraform module and admin script still deploy a LiteLLM container internally (not yet ported to MLflow's gateway architecture). See the root [README.md](../README.md) for details.

Start with [mlflow.md](mlflow.md) for the short resource explanation, five-value deployment setup, parameter-driven admin commands, backups, and staged upgrade/rollback runbook.

This directory is a separate Terraform root. Its reusable child module is under [modules/mlflow/variables.tf](modules/mlflow/variables.tf). It does not use the existing demo stack or state.