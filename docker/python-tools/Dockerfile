FROM python:3.12
LABEL authors="michael"

#ENTRYPOINT ["top", "-b"]

# Install the application dependencies
COPY ../../scripts/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

ENTRYPOINT ["python3"]
#
#FROM python:3.12
#WORKDIR /usr/local/work


#
## Copy in the source code
#COPY src ./src
#EXPOSE 5000
#
## Setup an app user so the container doesn't run as the root user
#RUN useradd app
#USER app
#
#CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]