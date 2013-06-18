su-lip
======

輸入臺語ê webservice, coded in OPA (compile into Node.js)

Installing OPA
==============

See
https://github.com/MLstate/opalang/wiki/Getting-started#ubuntu-linux-debian-linux

Configuring Su-lip
=================

Just set the path to the datafile in src/config.opa
The file is plain text containing one word on each line, with 漢字 and TRS separated by '\t'

Running the server
==================
Simply launch to compile and launch the project (on port 8080)
make run


Loading the Data
================
while the server is running, make  request on 

http://localhost:8080/build_db
 
 (build_db will only run once, you need to manually drop the mongodb base "IME" to reload the data)

Testing
=======

Just make some query using POST and json.

curl localhost:8080/_ws_/ -d '{"query":"su-jip"}'







