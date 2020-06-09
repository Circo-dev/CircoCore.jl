# An Example

When you install & run the system, on [http://localhost:8000](http://localhost:8000) soon you will see something like the following:

![The sample loaded in Camera Diserta](assets/sample1.png)

This is the tool "Camera Diserta" monitoring the default example: A linked list of 4000 actors,
that - when started - will run a reduce operation (a sum by default) repeatedly.

To try out the example, you have to send a "Run" message to the test coordinator:

- Click "coordinators" in the upper left corner to filter only the test coordinator
- Click the coordinator to select it
- The commands accepted by the coordinator will be queried from it
- Click "Run" when it appears
- Click "all" to see all the actors again
- Wait for the magic to happen
- Check the logs of the backend to see the speedup

The source code of the sample is at [examples/linkedlist.jl](https://github.com/Circo-dev/CircoCore/blob/master/examples/linkedlist.jl)
