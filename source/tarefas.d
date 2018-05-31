module tarefas;

@system unittest
{
    import core.thread : seconds, Thread;

    auto tarefas = new Tarefas().start(); // the background loop starts here
    scope(exit) tarefas.stop();          // and it stops when we exit

    __gshared string result1;
    auto tarefa1 = tarefas.perform({
        // perform "work"
        Thread.sleep(1.seconds);
        result1 = "done";
    });

    __gshared string result2;
    auto tarefa2 = tarefas.perform({
        // perform "work"
        Thread.sleep(1.seconds);
        result2 = "what up";
    });

    // do some "stuff" concurrently
    Thread.sleep(2.seconds);

    // oh look, it finished in the background.
    assert(result1 == "done");
    assert(result2 == "what up");
}

final class Tarefa
{
    alias Function = void delegate();
    private Function fun_;
    private bool done_;

    this(Function fun)
    {
        fun_ = fun;
    }

    void perform()
    {
        if (done_) return;

        fun_();
        done_ = true;
    }

    bool done() @nogc @property @safe const pure
    {
        return done_;
    }
}

@safe:

final class Tarefas
{
    import core.atomic     : atomicStore, atomicLoad;
    import core.thread     : Thread;
    import core.sync.mutex : Mutex;

    private Thread[4] pool_;
    private shared Tarefa[] queue_;
    private shared bool running_;
    private shared Mutex queueMutex_;

    this() @system
    {
        queueMutex_ = new shared Mutex();
        pool_ = [
            new Thread(&performAvailable).start(),
            new Thread(&performAvailable).start(),
            new Thread(&performAvailable).start(),
            new Thread(&performAvailable).start()
        ];
    }

    Tarefas start()
    {
        assert(!atomicLoad(running_), "Tarefas is already running.");
        atomicStore(running_, true);
        return this;
    }

    Tarefas stop()
    {
        assert(atomicLoad(running_), "Tarefas must be running to stop.");
        atomicStore(running_, false);
        return this;
    }

    Tarefa perform(Tarefa.Function fun) @trusted
    {
        auto tarefa = new Tarefa(fun);
        this.queueMutexed!((ref q) => q ~= cast(shared) tarefa);
        return tarefa;
    }

    private void performAvailable() @system
    {
        while (atomicLoad(running_)) {
            if (this.queueMutexed!((ref q) => q.length)) {
                Tarefa tarefa;

                this.queueMutexed!((ref q) {
                    tarefa = cast(Tarefa) q[0];
                    q = q[1 .. $];
                });

                tarefa.perform();
            }
        }
    }

    bool running() @nogc @property const pure
    {
        return atomicLoad(running_);
    }
}

// helper for Tarefas -- lock queue, exec fun, unlock
private auto queueMutexed(alias fun)(Tarefas t) @trusted
{
    t.queueMutex_.lock();
    scope(exit) t.queueMutex_.unlock();

    static if (is(fun == void)) {
        fun(t.queue_);
    } else {
        return fun(t.queue_);
    }
}
