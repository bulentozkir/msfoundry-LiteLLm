# Standalone MLflow

This directory is an essential, self-contained Terraform root for deploying an AI gateway in a customer environment.

**Implementation note:** this package currently deploys the same hardened LiteLLM gateway baseline used in the standalone LiteLLM package. The folder is retained as a dedicated standalone entry point for MLflow-track users while the fully distinct standalone MLflow runtime module evolves.

Start with [mlflow.md](mlflow.md) for the short resource explanation, core deployment setup, parameter-driven admin commands, backups, and staged upgrade/rollback runbook.

This directory is a separate Terraform root. Its reusable child module is under [modules/mlflow/variables.tf](modules/mlflow/variables.tf). It does not use the existing demo stack or state.