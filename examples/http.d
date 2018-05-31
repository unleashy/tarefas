/+ dub.sdl:
    name "tarefas-http-example"
    dependency "tarefas" path=".."
    dependency "requests" version="~>0.8.0"
    versions "StdLoggerDisableLogging"
+/

import std.stdio;

import tarefas;
import requests;

void main()
{
    auto tarefas = new Tarefas().start();

    string content;
    auto req = tarefas.perform({
        content = getContent("http://httpbin.org/get").toString();
    });

    while (!req.done) { /* await until completion */ }

    tarefas.stop();

    // it's done!
    writeln(content);
}
