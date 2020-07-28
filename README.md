# Deploy ![Deploy](https://github.com/jswny/deploy/workflows/CI/badge.svg)
A [GitHub Action](https://github.com/features/actions) to deploy apps to any server.

## Features
- Automatic deployment from GitHub actions
- Supports separate release channels
- Automatically injects necessary environment variables based on the release channel
- Only requires SSH and Docker packaging of your app

## Requirements
- **A server with SSH, Docker, and Docker Compose** for the app to be deployed to
  - An SSH key to be used for deployment which has been added to an appropriate user on the server. The key can **not** have a password.
- **Something to build and push a Docker image** for your app. [This Action](https://github.com/marketplace/actions/build-and-push-docker-images) is recommended.
- **A GitHub Actions workflow** to run this Action

## Usage
1. Include this Action in your workflow. For example, see [the demo version run in this repository under the `deploy` job here](https://github.com/jswny/deploy/blob/master/.github/workflows/ci.yml).
2. Encrypt your private deployment SSH key into using OpenSSL `aes-256-cbc` and commit **the encrypted version** to your repository: `openssl enc -aes-256-cbc -salt -in deploy_key -out deploy_key.enc -k "<encryption key>`. You can decrypt it if needed with `openssl enc -aes-256-cbc -d -in deploy_key.enc -out deploy_key -k "<encryption key>"`.
3. Fill in the inputs as noted below.
4. Create a `Dockerfile` for your app, use any environment variables that you need injected as you would usually.
5. Copy the default `docker-compose.yml` file from `app/docker-compose.yml` or use your own. Make sure the Compose file you use conforms to the following:
    - `$IMAGE` will be injected automatically in the `.env` file for your Compose file to use, but you can hard-code your image name if you know it will not change.
    - `$CONTAINER_NAME` will be generated by the Action, so you must ensure that your Compose file uses this as the container name.
    - Any environment variables you need to pass through to your various app services are included under the `environment` key.
6. Ensure any environment variables specified in the `env_var_prefixes` input are passed into the Action via the `env` key (see the input below, and examples).
7. Make sure the Action is only triggered on the appropriate events using [`jobs.<job_id>.if`](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions#jobsjob_idif).

## Inputs
### `deploy_server`
| Required | Description |
| --- | --- |
| **Yes** | The IP address of the SSH-enabled server to deploy to. |

### `deploy_username`
| Required | Description |
| --- | --- |
| **Yes** | The username of the account associated with the provided SSH key to access on the deploy server. |

### `deploy_root_dir`
| Required | Default | Description |
| --- | --- | --- |
| **Yes** | N/A | The root directory to deploy the app to on the deploy server. A subdirectory will be created inside this directory based on the release channel and the repository name. The root directory will be created if it doesn't already exist. |

### `encrypted_deploy_key_encryption_key`
| Required | Default | Description |
| --- | --- | --- |
| **Yes** | N/A | The key to decrypt the encrypted SSH deploy key for the deploy server. |

### `path`
| Required | Default | Description |
| --- | --- | --- |
| No | `.` | The path to the directory containing your app. Relative to the current directory of your repository. |

### `stable_branch`
| Required | Default | Description |
| --- | --- | --- |
| No | `master` | The branch which represents the stable version of the app. If `ANY` is specified, any branch will be used. |

### `beta_branch`
| Required | Default | Description |
| --- | --- | --- |
| No | `develop` | The branch which represents the beta version of the app. If `ANY` is specified, any branch will be used. If `ANY` is specified for `stable_branch`, this condition will never be cheked. |

### `env_var_prefixes`
| Required | Default | Description |
| --- | --- | --- |
| No | Empty string | A comma-separated string list of environment variable prefixes which, when suffixed with the deploy channel, represent the environment variables required to be injected into the app. For example, if `FOO,BAR` was passed in and the release channel was matched to `beta`, the following environment variables names would be pulled from the Action environment: `FOO_BETA`, `BAR_BETA`. |

### `debug`
| Required | Default | Description |
| --- | --- | --- |
| No | `0` | Print extra debugging info. Specify `0` for false or `1` for true. |

## How it Works
1. Determines the release channel based on the options passed in via the appropriate inputs.
2. Finds the local Docker image in the Actions runner built by a previous step in your workflow containing the name of your repository.
3. Generates an appropriate container name based on the local image name and the release channel.
4. Sets up the SSH agent inside the Actions runner using the provided SSH key.
5. Pushes the image to Docker Hub.
6. Populates a `.env` file with the appropriate environment variables required by your app depending on the release channel, and a few other environment variables such as the ones required by the Compose file.
7. Creates a directory on the remote server for the app given the current deploy channel using the provided deploy root directory.
8. Uses SCP to send the `.env` file and the `docker-compose.yml` file to the remote server.
9. Pulls the Docker image on the remote server.
10. Brings the app up with Docker Compose in detatched mode. This will automatically restart the app if the image has changed.

## Release Channels
Release channels are determined by the [Git reference](https://git-scm.com/book/en/v2/Git-Internals-Git-References), the rules below, and the appropriate options passed in via inputs.

### Rules
Rules are matched in the following order:
1. Check if the current Git reference is a branch, if not, error out.
2. Check `stable_branch`. If set to `ANY`, set release channel to **`stable`**.
3. Otherwise, check if the current branch matches `stable_branch`, and if so, set release channel to **`stable`**.
4. Otherwise, check `beta_branch`. If set to `ANY`, set release channel to **`beta`**.
5. Otherwise, check if the current branch matches `beta_branch`, and if so, set release channel to **`stable`**.
6. Otherwise, error out.

## Running Locally
You can simulate running the action locally by manually building and running the appropriate Docker images.
1. Build the demo Docker image from `app/`:
```shell
docker build --tag jswny/deploy app/
```
1. Create a `.env` file with the required environment variables for the Action corresponding to the inputs (which need to be prefixed with `INPUT_`, and uppercase, and the GitHub environment variables (you need to add variables for all inputs, even inputs that aren't required):
```shell
GITHUB_REPOSITORY=jswny/deploy
GITHUB_WORKSPACE=/github/workspace
GITHUB_REF=refs/heads/master
HOME=/github/HOME
CI=true
INPUT_DEPLOY_SERVER=1.1.1.1
INPUT_DEPLOY_USERNAME=user1
INPUT_DEPLOY_ROOT_DIR=/srv
INPUT_ENCRYPTED_DEPLOY_KEY_ENCRYPTION_KEY=abc123
INPUT_PATH=app
INPUT_STABLE_BRANCH=master
INPUT_BETA_BRANCH=ANY
INPUT_DEBUG=1
INPUT_ENV_VAR_PREFIXES=FOO,BAR
FOO_BETA=foo123
BAR_BETA=bar123
```
3. Create a `.env` file with the required environment variables for the demo app:
```shell
DOCKER_IMAGE=jswny/dotfiles
DOCKER_CONTAINER_NAME=jswny-dotfiles-beta
TOKEN=abc123
DEBUG=1
```
4. Build and run the Action Docker image:
```shell
docker build --tag jswny/deploy-action . && docker run -v "<local path to this repository>":"/github/workspace" -v "/var/run/docker.sock":"/var/run/docker.sock" --env-file=.env jswny/deploy-action
```