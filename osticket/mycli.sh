#!/usr/bin/env bash

mycli --ssh-host localhost --ssh-port 2222 --ssh-user root --ssh-password pass -P 3306 -u osticket -ppassword -D osticket
