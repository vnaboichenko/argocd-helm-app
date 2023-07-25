#!/usr/bin/env ruby

require 'yaml'
require 'curb'
require 'json'
require 'dnsruby'


module K8s
  METRICS_API = "http://metrics-api-lb.shard-proxy.use.development.k8s.ikarem.io:8000/shards"
  FILE = 'values.yml'
  class Namespace
    def initialize(shard_ids, cluster)
      @shard_ids = shard_ids
      @cluster = cluster
    end


    def prefix_to_region(prefix)
    map = {
      'dal' => "use",
      'vda' => "use",
      'use' => "use",
      'sdg' => "usw",
      'vsd' => "usw",
      'usw' => "usw",
    }
    return map[prefix]
    end

    def resolver(hostname, type='A')
      res = Dnsruby::Resolver.new({:nameserver => ['8.8.8.8']})
      ret = res.query(hostname, type)
      return ret.answer[-1]
    end

    def generate_shard_spare_config(shard_id, cluster)
      hostname = "n#{shard_id}.#{cluster}"
      primary = "n#{shard_id}.#{cluster}"
      spare = "n#{shard_id}-spare.#{cluster}"

      h = {}

      [primary, spare].each do |cname|
        host = resolver(cname, "CNAME").domainname.to_s
        prefix = host[0..2]
        eks_region = prefix_to_region(prefix)

        h[eks_region] = {
          'name' => resolver(cname, "CNAME").domainname.to_s,
          'v4' => resolver(cname, "A").address.to_s,
          'v6' => resolver(cname, "AAAA").address.to_s.downcase,
        }
      end

      return h
    end

    def generate_ns_hash

      hash = {
        @cluster => {
          "proxy_service_prefix" => "production",
          "shards"               => {},
        }
      }

      @shard_ids.each do |s|
        hostname = "n#{s}.#{@cluster}"

        hash[@cluster]["shards"]["n#{s}"] = generate_shard_spare_config(s, @cluster)
      end

      return hash
    end

  end

  class NSWriter
    def initialize(cluster)
      @cluster = cluster
      @api = "#{METRICS_API}/#{cluster}"
      @namespaces = namespaces
      @file = "values.#{cluster}.yml"
    end

    def get_shard_ids
      r = Curl.get(@api)
      result = JSON.parse(r.body)
      return result.keys
    end

    def namespaces
      shard_ids = get_shard_ids
      config = K8s::Namespace.new(shard_ids, @cluster).generate_ns_hash
      return { "clusters" => config }
    end

    def print_to_yaml
      print @namespaces.to_yaml
    end

    def save_to_file
      File.write(@file, @namespaces.to_yaml)
    end


  end
end

CLUSTERS = [
  "sandbox.meraki.com",
]

CLUSTERS.each do |c|
  v = K8s::NSWriter.new(c)
  v.print_to_yaml
  v.save_to_file
end


