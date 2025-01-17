# Use the latest version of the Amazon Linux base image
FROM amazonlinux:2023

# Avoid interactive prompts (if any)
ENV TERM=xterm \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Define build arguments
ARG PERSONAL_ACCESS_TOKEN
ARG GITHUB_USERNAME
ARG REPOSITORY_NAME
ARG RDS_ENDPOINT
ARG RDS_DB_NAME
ARG RDS_DB_USERNAME
ARG RDS_DB_PASSWORD
ARG CAPTCHA_SITEKEY
ARG CAPTCHA_SECRET

# Set environment variables from build arguments 
ENV PERSONAL_ACCESS_TOKEN=${PERSONAL_ACCESS_TOKEN}
ENV GITHUB_USERNAME=${GITHUB_USERNAME}
ENV REPOSITORY_NAME=${REPOSITORY_NAME}
ENV RDS_ENDPOINT=${RDS_ENDPOINT}
ENV RDS_DB_NAME=${RDS_DB_NAME}
ENV RDS_DB_USERNAME=${RDS_DB_USERNAME}
ENV RDS_DB_PASSWORD=${RDS_DB_PASSWORD}
ENV CAPTCHA_SITEKEY=${CAPTCHA_SITEKEY}
ENV CAPTCHA_SECRET=${CAPTCHA_SECRET}

# Install server dependencies: Node.js, MariaDB client, Nginx, Git, plus Python3 & pip
RUN curl -sL https://rpm.nodesource.com/setup_20.x | bash - \
  && dnf install -y nodejs mariadb105 nginx git python3-pip \
  && pip3 install --no-cache-dir supervisor \
  && dnf clean all

# Set working directory (where the app code will live)
WORKDIR /app/${REPOSITORY_NAME}

# Clone the GitHub repository containing the application code
RUN git clone https://${PERSONAL_ACCESS_TOKEN}@github.com/${GITHUB_USERNAME}/${REPOSITORY_NAME}.git .

# Install project dependencies
RUN npm install -g npm@latest pm2 \
  && npm install mysql2 \
  && npm audit fix --force

# Update variables in the config.env file
RUN sed -i "/^DB_HOST=/ s|=.*$|=${RDS_ENDPOINT}|" config.env \
  && sed -i "/^DB_DATABASE=/ s|=.*$|=${RDS_DB_NAME}|" config.env \
  && sed -i "/^DB_USERNAME=/ s|=.*$|=${RDS_DB_USERNAME}|" config.env \
  && sed -i "/^DB_PASSWORD=/ s|=.*$|=${RDS_DB_PASSWORD}|" config.env \
  && sed -i "/^CAPTCHA_SITEKEY=/ s|=.*$|=${CAPTCHA_SITEKEY}|" config.env \
  && sed -i "/^CAPTCHA_SECRET=/ s|=.*$|=${CAPTCHA_SECRET}|" config.env

# Copy your custom Nginx config
COPY chatvia.conf /etc/nginx/conf.d/chatvia.conf

# Copy your supervisord.conf file into the container
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose port 80 for Nginx
EXPOSE 80

# Launch supervisord, which will start Nginx & PM2
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
