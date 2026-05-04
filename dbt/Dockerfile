FROM python:3.11-slim

ARG DBT_VERSION=1.8.2

RUN pip install --no-cache-dir dbt-bigquery==${DBT_VERSION}

WORKDIR /dbt

# Copy only project files — profiles.yml is never baked into the image.
# At runtime it is injected via Secret Manager (mounted at /secrets/profiles.yml).
COPY dbt_project.yml  .
COPY profiles/        profiles/
COPY models/          models/
COPY macros/          macros/
COPY seeds/           seeds/

ENV DBT_PROFILES_DIR=/secrets

ENTRYPOINT ["dbt"]
CMD ["run"]
