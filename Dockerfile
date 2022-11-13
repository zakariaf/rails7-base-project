ARG RUBY_VERSION
ARG IMAGE_FLAVOUR=alpine

FROM ruby:$RUBY_VERSION-$IMAGE_FLAVOUR AS base

# Install system dependencies required both at runtime and build time
ARG NODE_VERSION
ARG YARN_VERSION
RUN apk add --update \
  git \
  postgresql-dev \
  tzdata \
  nodejs=$NODE_VERSION \
  yarn=$YARN_VERSION

# This stage will be responsible for installing gems and npm packages
FROM base AS dependencies

# Install system dependencies required to build some Ruby gems (pg)
RUN apk add --update build-base

COPY .ruby-version Gemfile Gemfile.lock ./

# Install gems
ARG RAILS_ENV
ARG NODE_ENV
ENV RAILS_ENV="${RAILS_ENV}" \
    NODE_ENV="${NODE_ENV}"

RUN if [ "${RAILS_ENV}" != "development" ]; then \
    bundle config set without "development test"; fi
RUN bundle install --jobs "$(nproc)" --retry "$(nproc)"

COPY package.json yarn.lock ./

# Install npm packages
RUN yarn install --frozen-lockfile

###############################################################################

# We're back at the base stage
FROM base AS app

# Create a non-root user to run the app and own app-specific files
RUN adduser -D app

# Switch to this user
USER app

# We'll install the app in this directory
WORKDIR /app

# Copy over gems from the dependencies stage
COPY --from=dependencies /usr/local/bundle/ /usr/local/bundle/

# Copy over npm packages from the dependencies stage
# Note that we have to use `--chown` here
COPY --chown=app --from=dependencies /node_modules/ node_modules/

# Finally, copy over the code
# This is where the .dockerignore file comes into play
# Note that we have to use `--chown` here
COPY --chown=app . ./

# Install assets
ARG RAILS_ENV="production"
ARG NODE_ENV="production"
ENV RAILS_ENV="${RAILS_ENV}" \
    NODE_ENV="${NODE_ENV}"

RUN if [ "${RAILS_ENV}" != "development" ]; then \
  SECRET_KEY_BASE=irrelevant DEVISE_JWT_SECRET_KEY=irrelevant bundle exec rails assets:precompile; fi

# Launch the server
EXPOSE 3000

CMD ["rails", "s"]
