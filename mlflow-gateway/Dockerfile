FROM python:3.12-slim

RUN pip install --no-cache-dir \
    "mlflow[genai,auth]==3.16.0" \
    psycopg2-binary==2.9.10 \
    azure-identity==1.19.0 \
    requests==2.32.3

COPY refresh_secrets.py /app/refresh_secrets.py
WORKDIR /app

EXPOSE 5000

# Sidecar refresh_secrets.py is launched as a second container in the same
# Container Apps revision (see terraform/mlflow-gateway.tf); this image is
# shared by both containers, selected via the pod command override.
CMD ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000"]
