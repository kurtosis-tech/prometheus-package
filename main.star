CONFIG_DIR = "/config"
CONFIG_FILENAME = "prometheus-config.yml"
DEFAULT_SCRAPE_INTERVAL = "15s"

def run(plan, 
        metrics_jobs=[], 
        min_cpu=10,
        max_cpu=1000,
        min_memory=128,
        max_memory=2048,
        node_selectors={},
):
    """ Starts a Prometheus server that scrapes metrics off the provided prometheus metrics configurations.

    Args:
        metrics_jobs(json): A list of prometheus metrics configs to scrape metrics from. 
           More info on scrape config here: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config
           eg.
           ```
           metrics_jobs: [
                {
                    # name of metrics job
                    Name: "" , 

                    # endpoint to scrape metrics from,eg. <services ip address>:<exposed metrics port>
                    Endpoint: "", 

                    # labels to associate with scraped metrics (eg. { "service_type": "api" } )
                    # optional
                    Labels:{}, 

                    # http path to scrape metrics from
                    # optional
                    MetricsPath: "/metrics", 

                    # how frequently to scrape targets from this job
                    # optional
                    ScrapeInterval: "15s"
                },
                { 
                    ...
                },
            ]
           ```
        min_cpu(int): min cpu for prometheus instance
        max_cpu(int): max cpu for prometheus instance
        min_memory(int): min memory for prometheus instance
        max_memory(int): max memory for prometheus instance
        node_selectors(dict): set node_selectors for running this instance on a particular node (kubernetes only)
    Returns:
        prometheus_url: endpoint to prometheus service inside the enclave (eg. 123.123.212:9090)
    """
    prometheus_config_template = read_file(src="./static-files/prometheus.yml.tmpl")

    prometheus_config_data = {
        "MetricsJobs": get_metrics_jobs(metrics_jobs)
    }

    prom_config_files_artifact = plan.render_templates(
        config = {
            CONFIG_FILENAME: struct(
                template=prometheus_config_template,
                data=prometheus_config_data,
            )
        },
        name="prometheus-config",
    )

    config_file_path= CONFIG_DIR + "/" + CONFIG_FILENAME

    prometheus_service = plan.add_service(name="prometheus", config=ServiceConfig(
        image="prom/prometheus:latest",
        ports={
            "http": PortSpec(
                number=9090,
                transport_protocol="TCP",
                application_protocol="http",
            )
        },
        files={
            CONFIG_DIR:prom_config_files_artifact,
        },
        cmd=[
            "--config.file=" + config_file_path,
            "--storage.tsdb.path=/prometheus",
            "--storage.tsdb.retention.time=1d",
            "--storage.tsdb.retention.size=512MB",
            "--storage.tsdb.wal-compression",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
            "--web.enable-lifecycle",
        ],
        min_cpu=min_cpu,
        max_cpu=max_cpu,
        min_memory=min_memory,
        max_memory=max_memory,
        node_selectors=node_selectors,
    ))

    prometheus_service_ip_address = prometheus_service.ip_address
    prometheus_service_http_port = prometheus_service.ports["http"].number

    return "http://{0}:{1}".format(prometheus_service_ip_address, prometheus_service_http_port)
    
def get_metrics_jobs(service_metrics_configs):
    metrics_jobs = []
    for metrics_config in service_metrics_configs:
        if "Name" not in metrics_config:
            fail("Name not provided in metrics config.")
        if "Endpoint" not in metrics_config:
            fail("Endpoint not provided in metrics config")
        
        labels = {}
        if "Labels" in metrics_config:
            lables = metrics_config["Labels"]

        metrics_path = "/metrics"
        if "MetricsPath" in metrics_config:
            metrics_path = metrics_config["MetricsPath"]

        scrape_interval = DEFAULT_SCRAPE_INTERVAL
        if "ScrapeInterval" in metrics_config:
            scrape_interval = metrics_config["ScrapeInterval"]

        metrics_jobs.append({
            "Name": metrics_config["Name"],
            "Endpoint": metrics_config["Endpoint"],
            "Labels": labels,
            "MetricsPath": metrics_path,
            "ScrapeInterval": scrape_interval,
        })
        
    return metrics_jobs
