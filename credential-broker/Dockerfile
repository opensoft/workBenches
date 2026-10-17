FROM python:3.13-slim
WORKDIR /app
COPY credential-broker/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --uid 10001 --create-home broker
COPY credential-broker/*.py /app/
COPY scripts/company_sync.py /app/company_sync.py
RUN chmod -R a+rX /app
USER 10001:10001
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
EXPOSE 8080
CMD ["gunicorn", "--bind=0.0.0.0:8080", "--workers=1", "--threads=4", "--timeout=120", "--access-logfile=/dev/null", "app:create_app()"]
