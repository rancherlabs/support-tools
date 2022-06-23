# Opni Support Agent

Github repo for the CLI tool is https://github.com/dbason/opni-supportagent.
Agent can be downloaded from the Releases page in multiple architectures.

There are two main commands you will use; publish and delete
```bash
opni-supportagent publish rke|rke2|k3s --case-number number --username opensearch-username [--node-name node]
```

```bash
opni-supportagent delete --case-number number --username opensearch-username
```

The CLI has a help option with `--help` or by entering an incomplete command.  When running the command you should be in the root of an extracted log bundle as the CLI is looking for an expected directory structure.  It will index the logs to Opensearch, and the Opni microservices will then process the uploaded logs.  Logs will be deleted after 7 days.

## Opensearch UI
The Opensearch Dashboards UI is available at https://dashboards-support.opni.xyz

This is where you can access the Opni UI, and also use the standard Opensearch/Elasticsearch tools to review the logs for your case.

## Support
Any questions/comments/concerts please reach out to the Opni team in the discuss-opni Slack channel.  Any problems with your user account; e.g. password resets please contact Dan Bason.