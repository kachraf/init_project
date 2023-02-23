DOCKER_COMPOSE?=docker-compose
EXEC=$(DOCKER_COMPOSE) exec api
CONSOLE=$(EXEC) bin/console
CONSOLE_TEST=$(EXEC) bin/console --env=test
COMPOSER=$(EXEC) composer
VENDOR_BIN=$(EXEC) vendor/bin
DOCKERIZE=$(DOCKER_COMPOSE) run --rm dockerize -timeout 20s
VERSION=main

ifdef MAKEFILE_ENV
	EXEC=$(DOCKER_COMPOSE) exec -T api
endif

.phony: start init stop rm build

init: stop rm build start composer db

start:
	$(DOCKER_COMPOSE) up -d --remove-orphans

stop:
	$(DOCKER_COMPOSE) stop

rm:
	$(DOCKER_COMPOSE) rm -f

build:
	$(DOCKER_COMPOSE) pull
	$(DOCKER_COMPOSE) build --pull --parallel

bash:
	$(EXEC) bash


logs:
	$(DOCKER_COMPOSE) logs --tail 50 --follow --timestamps api
##
## Composer
##---------------------------------------------------------------------------

composer: composer.lock
	$(COMPOSER) install --prefer-dist

##
## Symfony
##---------------------------------------------------------------------------

.phony: cc

cc:
	$(CONSOLE) cache:clear

##
## Tests
##---------------------------------------------------------------------------

.phony: test tu db-test tf cs-fixer phpstan

tests: check-vulnerability cs-fixer phpstan tu tf

db-test: wait-for-db
	$(CONSOLE_TEST) doctrine:database:drop --if-exists --force -n
	$(CONSOLE_TEST) doctrine:database:create -n
	$(CONSOLE_TEST) doctrine:migration:migrate -n
	$(CONSOLE_TEST) hautelook:fixtures:load -n --no-bundles
	$(CONSOLE_TEST) cache:clear

tu:
	$(EXEC) bin/phpunit

tf: db-test
	$(VENDOR_BIN)/behat -f progress

cs-fixer: composer
	$(VENDOR_BIN)/php-cs-fixer fix --diff --dry-run --no-interaction

cs-fixer-no-diff:
	$(VENDOR_BIN)/php-cs-fixer fix --no-interaction

phpstan: composer
	$(VENDOR_BIN)/phpstan -l7 analyse src tests features

check-vulnerability:
	$(EXEC) local-php-security-checker

##
## Database
##---------------------------------------------------------------------------

.PHONY: db db-diff db-migrate db-rollback db-load db-validate wait-for-db db-flush wait-for-db

db: vendor wait-for-db db-flush db-migrate db-load ## Reset the database and load fixtures

wait-for-db:
	$(DOCKERIZE) -wait tcp://db_api:3306

db-flush: vendor
	$(CONSOLE) doctrine:database:drop --if-exists --force -n
	$(CONSOLE) doctrine:database:create -n

db-migrate: vendor ## Migrate database schema to the latest available version
	$(CONSOLE) doctrine:migration:migrate -n

db-rollback: vendor ## Rollback the latest executed migration
	$(CONSOLE) doctrine:migrations:migrate prev -n

db-load: vendor ## Reset the database fixture
	$(CONSOLE) hautelook:fixtures:load -n --no-bundles

db-validate: vendor ## Check the ORM mapping
	$(CONSOLE) doctrine:schema:validate

db-migrate-generate: vendor
	$(CONSOLE) doctrine:migration:diff --filter-expression='~^(?!media)~' ## Reset the database and load fixtures

##
## Artifact
##---------------------------------------------------------------------------

.PHONY: build-artifact

init-artifact:
	$(DOCKER_COMPOSE) -f docker-compose.artifact.yaml stop
	$(DOCKER_COMPOSE) -f docker-compose.artifact.yaml rm -f
	$(DOCKER_COMPOSE) -f docker-compose.artifact.yaml pull
	$(DOCKER_COMPOSE) -f docker-compose.artifact.yaml build --pull --parallel
	$(DOCKER_COMPOSE) -f docker-compose.artifact.yaml up -d --remove-orphans
	$(DOCKER_COMPOSE) -f docker-compose.artifact.yaml exec app composer install --optimize-autoloader --classmap-authoritative --prefer-dist --no-suggest --no-interaction --no-scripts --no-dev

build-artifact:
	rm -rf artifact
	mkdir -p artifact
	git clone git@github.com:kachraf/init_project.git ./artifact
	(cd artifact; git checkout $(VERSION))

	( \
		make -C artifact init-artifact; \
	)
	
	(\
		cd artifact; \
		rm -rf .github assets docker docs features fixtures node_modules tests \
			.env .env.dist .env.test .eslintrc.yaml .gitignore .php_cs.dist \
			behat.yml.dist CHANGELOG docker-compose.artifact.yaml docker-compose.yaml \
			Makefile docker-compose.override.yaml.dist \
			package.json package-lock.json phpstan.neon.dist phpunit.xml.dist README.md \
			supervisord.log supervisord.pid symfony.lock webpack.config.js .git \
			var/cache/* var/log \
	)

	@echo
	@echo "-----------------------------"
	@echo "Artifact API is ready for deploy!"
	@echo "-----------------------------"
