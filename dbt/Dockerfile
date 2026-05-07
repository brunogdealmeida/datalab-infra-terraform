FROM python:3.11-slim

ARG DBT_VERSION=1.8.2

RUN pip install --no-cache-dir dbt-bigquery==${DBT_VERSION}

WORKDIR /dbt

COPY dbt_project.yml .
COPY models/ models/
COPY macros/ macros/
COPY seeds/ seeds/

ENV DBT_PROFILES_DIR=/secrets

ENTRYPOINT ["dbt"]
CMD ["run"]