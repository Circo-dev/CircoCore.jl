# Troubleshooting

**CircoCore is in early alpha stage. Several stability issues are known. Please file an issue if you cannot find the workaround here!**

## The frontend fails to display the correct number of schedulers

Open the JavaScript console (F12) and reload the page. You should see exactly one connection error message, and for every scheduler a log about "actor registration". If not, then

- You may need to restart your browser
- Possibly some schedulers remained alive from a previous run

## Stopping the scheduler processes

You can stop `circonode.sh` and `localcluster.sh` by pressing Crtl-C (SIGINT). In the cluster case some processes may not get stopped. Please check this with `ps` and kill them if needed.

