FROM nginx:latest

RUN useradd -u 1001 -d /app appuser 
    
COPY homework.html /app/
COPY nginx.conf /etc/nginx/

ENV NGINX_PORT=8000