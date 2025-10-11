# Start from Python slim image
FROM python:3.12-slim

# Install dependencies for Java and .NET
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    openjdk-17-jdk \
    mono-complete \
    apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# Install .NET SDK (optional if you need .NET 8 compilation)
RUN wget https://packages.microsoft.com/config/debian/12/packages-microsoft-prod.deb -O packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y dotnet-sdk-8.0

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY . .

# Expose port
EXPOSE 8000

# Start FastAPI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
