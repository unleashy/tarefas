module tarefas;

@system unittest
{
    import core.thread : seconds, Thread;

    auto tarefas = new Tarefas().start(); // the background loop starts here
    scope(exit) tarefas.stop();          // and it stops when we exit

    shared string result1;
    auto tarefa1 = tarefas.perform({
        // perform "work"
        Thread.sleep(1.seconds);
        result1 = "done";
    });

    shared string result2;
    auto tarefa2 = tarefas.perform({
        // perform "work"
        Thread.sleep(1.seconds);
        result2 = "what up";
    });

    // do some "stuff" in parallel
    Thread.sleep(2.seconds);

    // oh look, it finished in the background.
    assert(tarefa1.done);
    assert(result1 == "done");

    assert(tarefa2.done);
    assert(result2 == "what up");
}

final shared class Tarefa
{
    import core.atomic : atomicStore, atomicLoad;

    alias Function = void delegate();
    private Function fun_;
    private bool done_;

    this(Function fun)
    {
        fun_ = fun;
    }

    void perform()
    {
        if (done) return;

        synchronized (this) {
            fun_();
        }

        atomicStore(done_, true);
    }

    bool done() @nogc @property @safe const pure
    {
        return atomicLoad(done_);
    }
}

final class Tarefas
{
    import core.atomic     : atomicStore, atomicLoad;
    import core.thread     : Thread;
    import core.sync.mutex : Mutex;

    private Thread[4] pool_;
    private shared Tarefa[] queue_;
    private shared bool running_;
    private shared Mutex queueMutex_;

    this()
    {
        queueMutex_ = new shared Mutex();
        pool_ = [
            new Thread(&performAvailable),
            new Thread(&performAvailable),
            new Thread(&performAvailable),
            new Thread(&performAvailable)
        ];
    }

    Tarefas start()
    {
        assert(!running, "Tarefas is already running.");
        atomicStore(running_, true);

        foreach (ref thread; pool_) {
            thread.start();
        }

        return this;
    }

    Tarefas stop()
    {
        assert(running, "Tarefas must be running to stop.");
        atomicStore(running_, false);

        foreach (ref thread; pool_) {
            thread.join();
        }

        return this;
    }

    shared(Tarefa) perform(Tarefa.Function fun)
    {
        auto tarefa = new shared Tarefa(fun);

        {
            queueMutex_.lock();
            scope(exit) queueMutex_.unlock();

            queue_ ~= tarefa;
        }

        return tarefa;
    }

    private void performAvailable()
    {
        while (running) {
            shared(Tarefa) tarefa = null;

            if (queueMutex_.tryLock()) {
                scope(exit) queueMutex_.unlock();

                if (queue_.length) {
                    tarefa = queue_[0]; // get the first one you see
                    queue_ = queue_[1 .. $]; // pop it off
                }
            }

            if (tarefa) tarefa.perform();
        }
    }

    bool running() @nogc @property @safe const pure
    {
        return atomicLoad(running_);
    }
}
