namespace :parallel do
  desc "prepare parallel test running by calling db:reset for every test database needed with parallel:prepare[num_cpus]"
  task :prepare, :count do |t,args|
    require File.join(File.dirname(__FILE__), '..', 'lib', "parallel_tests")

    pids = []
    num_processes = (args[:count] || 2).to_i
    num_processes.times do |i|
      puts "Preparing database #{i + 1}"
      pids << Process.fork do
        `export TEST_ENV_NUMBER=#{ParallelTests.test_env_number(i)} ; export RAILS_ENV=test ; rake db:reset`
      end
    end
    
    ParallelTests.wait_for_processes(pids)
  end

  %w[spec test].each do |type|
    desc "run specs in parallel with parallel:spec[num_cpus]"
    task type, :count, :path_prefix do |t,args|
      require File.join(File.dirname(__FILE__), '..', 'lib', "parallel_#{type}s")
      klass = eval("Parallel#{type.capitalize}s")

      start = Time.now

      num_processes = (args[:count] || ParallelTests.get_processors_number).to_i
      groups = klass.tests_in_groups(File.join(RAILS_ROOT,type,args[:path_prefix].to_s), num_processes)
      num_tests = groups.sum { |g| g.size }
      puts "#{num_processes} processes for #{num_tests} #{type}s, ~ #{num_tests / num_processes} #{type}s per process"

      #run each of the groups
      pids = []
      read, write = IO.pipe
      groups.each_with_index do |files, process_number|
        pids << Process.fork do
          write.puts klass.run_tests(files, process_number)
        end
      end

      klass.wait_for_processes(pids)

      #parse and print results
      write.close
      results = klass.find_results(read.read)
      read.close
      puts ""
      puts "Results:"
      results.each{|r| puts r}

      #report total time taken
      puts ""
      puts "Took #{Time.now - start} seconds"

      #exit with correct status code
      exit klass.failed?(results) ? 1 : 0
    end
  end
end


#backwards compatability
#spec:parallel:prepare
#spec:parallel
#test:parallel
namespace :spec do
  namespace :parallel do
    task :prepare, :count do |t,args|
      Rake::Task['parallel:prepare'].invoke(args[:count])
    end
  end

  task :parallel, :count do |t,args|
    Rake::Task['parallel:spec'].invoke(args[:count])
  end
end
namespace :test do
  task :parallel, :count do |t,args|
    Rake::Task['parallel:test'].invoke(args[:count])
  end
end