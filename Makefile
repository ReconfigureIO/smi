# variable definitions
NAME := smi
VERSION := $(shell git describe --tags --always --dirty)
GOVERSION := $(shell go version)
BUILDTIME := $(shell date -u +"%Y-%m-%dT%H:%M:%SZ")
BUILDDATE := $(shell date -u +"%B %d, %Y")
BUILDER := $(shell echo "`git config user.name` <`git config user.email`>")
PKG_RELEASE ?= 1
PROJECT_URL := "https://github.com/ReconfigureIO/$(NAME)"

.PHONY: test all clean pkg

CMD_SOURCES := $(shell go list ./... | grep /cmd/)
TARGETS := $(patsubst github.com/ReconfigureIO/smi/cmd/%,build/bin/%,$(CMD_SOURCES))

all: ${TARGETS} build/verilog

pkg: dist/${NAME}-${TRAVIS_TAG}-${TARGET}.tar.gz

lint:
	find verilog -name "*.v" | xargs -L1 verilator --lint-only -Iverilog --report-unoptflat

test:
	go test -v $$(go list ./... | grep -v /vendor/ | grep -v /cmd/)

build:
	mkdir -p build

build/verilog: verilog | build
	mkdir -p build/verilog
	cp -r verilog/* build/verilog

build/bin/%: cmd/% | build
	go build -ldflags "$(LDFLAGS)" -o $@ github.com/ReconfigureIO/smi/$<

dist/${NAME}-${TRAVIS_TAG}-${TARGET}.tar.gz: all
	mkdir -p dist
	cd build && tar czf ../$@ *

clean:
	rm -rf dist build
