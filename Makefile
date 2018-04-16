.PHONY: help install-hook clean info update server

SHELL = /bin/bash
ENV_FILE = .env

# import variables in env file as make variables
include ${ENV_FILE}

# export make variables as environment variables so any subcommand will have access to them.
export $(shell sed 's/=.*//' ${ENV_FILE})
export PIPENV_VENV_IN_PROJECT=true

default: help

help:
	@echo "This project assumes that an active Python virtualenv is present."
	@echo "The following targets are available:"
	@echo "  update        update python dependencies"
	@echo "  update-all    update python dependencies (including test only)"
	@echo "  install-hook  install git pre-commit hook for python"
	@echo "  clean         remove unwanted files"
	@echo "  lint          run linter (prospector) to ensure the source code meets coding standards"
	@echo "  security      run security tools to ensure the source code meets security standards"
	@echo "  test          run unit tests"
	@echo "  integration   run integration tests"
	@echo "  selenium      run web UI tests"
	@echo "  ci            run unit, integration and codecov"
	@echo "  all           refresh and run all tests and generate coverage reports"
	@echo "  server        start the Flask server"

info:
	@uname -a
	@docker --version
	@${MAKE} --version | head -n1
	@python --version
	@pip --version
	@virtualenv --version
	@pipenv --version

clean:
	@find . -name __pycache__ -prune -exec rm -rfv {} +
	@find . -name "*.pyc" -prune -exec rm -rfv {} +
	@find . -name .cache -prune -exec rm -rfv {} +
	@rm -rf dist/ build/ *egg-info/
	@rm -fv .coverage
	@rm -rfv ${CI_ARTIFACTS_DIR}

pristine: clean
	@rm -frv .tox
	@rm -frv .venv

precommit:
	pipenv run pre-commit run --all-files

lint:
	@pipenv run prospector ${args}

security-bandit:
	@pipenv run bandit -r . -f html -o ${CI_ARTIFACTS_DIR}/security/bandit.html

security-safety:
	@pipenv run safety check --full-report | tee ${CI_ARTIFACTS_DIR}/security/safety.txt

security-depcheck:
	@pipenv run dependency-check \
		--project ${CI_PROJECT_NAME} \
		--scan . \
		--exclude **/.tox/** --exclude **/.venv/** --exclude **/__pycache__/** **/.git/** \
		--failOnCVSS ${CI_SECURITY_DEPCHECK_FAILONCVSS} \
		--enableExperimental \
		--log ${CI_ARTIFACTS_DIR}/security/depcheck.log \
		--format HTML \
		--out ${CI_ARTIFACTS_DIR}/security/depcheck.html

security: security-bandit security-safety security-depcheck

tox:
	@pipenv run tox

test-unit:
	@mkdir -p ${CI_ARTIFACTS_DIR}/tests/unit
	@pipenv run pytest ${args} \
		--verbose \
		--numprocesses=auto \
		--boxed \
		--junit-xml=${CI_ARTIFACTS_DIR}/tests/unit/${CI_PROJECT_NAME}.xml \
		--html=${CI_ARTIFACTS_DIR}/tests/unit/${CI_PROJECT_NAME}.html \
		--self-contained-html


test-integration:
	@mkdir -p ${CI_ARTIFACTS_DIR}/tests/integration
	@pipenv run pytest \
		-m integration \
		--verbose \
		--numprocesses=auto \
		--boxed \
		--junit-xml=${CI_ARTIFACTS_DIR}/tests/integration/${CI_PROJECT_NAME}.xml

test-web: docker-up
	@mkdir -p ${CI_ARTIFACTS_DIR}/tests/web
	$(eval DRIVER_IP := $(shell ./wait_for_ip.sh))
	DRIVER_IP=$(DRIVER_IP) pipenv run pytest \
		-m web \
		--verbose \
		--junit-xml=${CI_ARTIFACTS_DIR}/tests/web/${CI_PROJECT_NAME}.xml
	docker-compose stop

test: clean test-unit test-integration test-web

coverage:
	@pipenv run pytest \
		--verbose \
		--numprocesses=auto \
		--cov-branch \
		--cov-fail-under=${CI_COVERAGE_FAIL_UNDER} \
		--cov-report=html:${CI_ARTIFACTS_DIR}/coverage/htmlcov \
		--cov-report=xml:${CI_ARTIFACTS_DIR}/coverage/coverage.xml \
		--cov-report=term-missing \
		--cov ${args}

ci: update info clean coverage webtest
	CODECOV_TOKEN=$$(cat .codecov-token) codecov

all: clean update lint security test-all

docker-clean:
	-@docker rm -vf $$(docker ps -aq -f "status=exited")
	-@docker rmi $$(docker images -aq -f "dangling=true")

docker-build:
	@docker-compose build

docker-up: docker-down
	@docker-compose pull --parallel
	@docker-compose up -d; docker-compose logs -f

docker-down:
	@docker-compose down -v

server:
	python manage.py server

uwsgi:
	uwsgi --socket 127.0.0.1:5080 --wsgi-file wsgi.py

init:
	pip install --user -U pip pipenv
	pipenv install --dev
	pipenv run pre-commit install

update:
	pipenv run pre-commit autoupdate
	pipenv update --dev
