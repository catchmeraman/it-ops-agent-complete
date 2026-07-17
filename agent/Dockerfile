FROM public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py agent.py ./
COPY tools/ ./tools/

EXPOSE 8080

CMD ["python", "main.py"]
