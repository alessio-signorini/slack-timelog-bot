# syntax=docker/dockerfile:1

# Build stage
FROM ruby:3.3-alpine AS builder

RUN apk add --no-cache \
    build-base \
    sqlite-dev \
    git

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local path 'vendor/bundle' && \
    bundle config set --local without 'development test' && \
    bundle config set --local force_ruby_platform true && \
    bundle install --jobs 4

# Production stage
FROM ruby:3.3-alpine

RUN apk add --no-cache \
    sqlite-libs \
    sqlite \
    tzdata \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

# Copy bundle from builder
COPY --from=builder /app/vendor/bundle vendor/bundle
COPY --from=builder /usr/local/bundle/config /usr/local/bundle/config

# Copy application
COPY --chown=app:app . .

# Create data directory with correct permissions
RUN mkdir -p /data && chown -R app:app /data

# Set ownership
RUN chown -R app:app /app

USER app

ENV RACK_ENV=production
ENV PORT=8080

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

# Start server
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
