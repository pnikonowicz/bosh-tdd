#                          __                       __      __
#     _______  ______     / /____  ____ ___  ____  / /___ _/ /____
#    / ___/ / / / __ \   / __/ _ \/ __ `__ \/ __ \/ / __ `/ __/ _ \
#   / /  / /_/ / / / /  / /_/  __/ / / / / / /_/ / / /_/ / /_/  __/
#  /_/   \__,_/_/ /_/   \__/\___/_/ /_/ /_/ .___/_/\__,_/\__/\___/
#                                        /_/
# Expands a bosh template by binding a manifest and release
# USAGE: run_template <job_name> <manifest_filename> <template_name>
# job_name: the name of the job that contains your template that you want to run
# manifest_filename: the manifest that would be used to deploy your release. eg: bosh -d <deployment> manifest <vm>
# template_name: not the file_name, but the name that the file will expand into
#
# Notes: If a Links default value cannot be found, a generated default value will be put in its place.
#        Any other missing params will result in an error

require 'bosh/template'
require 'yaml'
require 'json'
require 'erb'

class PropertyHelper
  include Bosh::Template::PropertyHelper
end

def parse_args args
  abort "USAGE: run_template <job_name> <manifest_filename> <template_name>" unless args.length == 3

  return args[0], args[1], args[2]
end

def get_spec release_path, job_name
  spec_path = File.join(release_path, 'jobs', job_name, 'spec')
  YAML.load_file(spec_path)
end

def get_manifest_value(manifest, property_name)
  property_value = PropertyHelper.new.lookup_property(manifest, property_name)
  return false if property_value.nil?
  property_value.to_s
end

def get_spec_value(spec, property_name)
  property_value = spec["properties"][property_name]
  return false if property_value.nil?
  default_property_value = property_value['default']
  return "no default value for #{property_name}" if default_property_value.nil?
  default_property_value.to_s
end

def get_link(provides, manifest, spec)

  name = provides['name']
  address = 'fake_address'
  properties = {}

  provides['properties'].each do |v|
    property_value = get_manifest_value(manifest,v) || get_spec_value(spec,v)  || raise("could not find property #{v}")
    PropertyHelper.new.set_property(properties, v, property_value)
  end

  return Bosh::Template::Test::Link.new(
      name: name,
      instances: [Bosh::Template::Test::LinkInstance.new(address: address)],
      properties: properties
  )
end

def get_links(job_name, release_path, manifest)
  spec = get_spec(release_path, job_name)

  return [] if spec['provides'].nil? || spec['provides'].empty?
  raise NotImplementedError.new("currently only supports one provides per spec") if spec['provides'].length > 1

  provides = spec['provides']
  return provides.map { |p| get_link p, manifest,spec }
end

def get_jobs release_path
  jobs_path = File.join(release_path, "jobs")
  Dir.glob("#{jobs_path}/*")
      .select {|f| File.directory? f}
      .map {|x| File.basename x}
end

def get_links_from_job(release_path, job_names, manifest)
  job_names.map do |job_name|
    get_links(job_name, release_path, manifest)
  end.flatten
end

def get_consumes release_path, job_name
  spec = get_spec release_path, job_name
  spec['consumes'].map {|x| x['name']}
end

def get_manifest_properties manifest, job_name
  instance_group = manifest['instance_groups'].find do |instance_group|
    instance_group["jobs"].any? {|x| x["name"] == job_name}
  end
  raise "there is a problem with the manifest. could not find job #{job_name} in #{manifest['instance_groups'].map {|x| x["jobs"].map {|y| y["name"]}}.flatten}" if instance_group.nil?
  instance_group["jobs"].find {|x| x["name"] == job_name }['properties']
end

job_name, manifest_filename, template_name = parse_args ARGV

release_path = File.join(File.dirname(__FILE__), '..')
jobs = get_jobs release_path
manifest = YAML.load_file(manifest_filename)
manifest_properties = get_manifest_properties manifest, job_name

all_links = get_links_from_job(release_path, jobs, manifest_properties)
consumes = get_consumes release_path, job_name
links = all_links.select {|link| consumes.include?(link.name) }

release = Bosh::Template::Test::ReleaseDir.new(release_path)
job = release.job(job_name)
template = job.template(template_name)

puts template.render(manifest_properties, consumes: links)


