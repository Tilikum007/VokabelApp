FROM python:3.12-slim

WORKDIR /app

COPY Backend/vokabel_backend.py /app/Backend/vokabel_backend.py
COPY Sources/VokabelCore/Resources/MASTER_vokabelheft_norwegisch.csv /app/Sources/VokabelCore/Resources/MASTER_vokabelheft_norwegisch.csv

ENV VOKABEL_BACKEND_HOST=0.0.0.0
ENV VOKABEL_BACKEND_PORT=8080
ENV VOKABEL_BACKEND_DATA_DIR=/data

EXPOSE 8080

CMD ["python", "/app/Backend/vokabel_backend.py"]
