FROM ghcr.io/mlflow/mlflow:latest

#psycopg2 - postgres adapter 
#boto3 - minio/s3 adapter
RUN pip install psycopg2-binary boto3

CMD ["mlflow", "server"]