FROM public.ecr.aws/lambda/python:3.8

# Set up a build argument for the Lambda file name
ARG LAMBDA_FILE

# Install dependencies
COPY requirements.txt ./
RUN pip install -r requirements.txt

# Copy only the specified Lambda function code
COPY lambdas/${LAMBDA_FILE}.py lambda_handler.py

# Set the CMD to the Lambda function handler
CMD ["lambda_handler.lambda_handler"]
