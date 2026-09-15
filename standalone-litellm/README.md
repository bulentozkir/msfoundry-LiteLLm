# Standalone LiteLLM

This directory deploys LiteLLM on its own Azure Container Apps platform (separate root, separate state).

Start with [litellm.md](litellm.md). It includes:

- how to deploy LiteLLM as an independent container app stack
- how to connect LiteLLM to two Foundry models (Mini + Phi) with managed identity
- how to update or upgrade LiteLLM safely with Stage/Promote/Rollback
- rollback and backup/recovery guidance

The reusable child module is under [modules/litellm/variables.tf](modules/litellm/variables.tf).