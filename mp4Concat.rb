#!/usr/bin/env ruby

# Copyright 2023 hidenory
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'optparse'
require 'shellwords'
require_relative 'ExecUtil'
require_relative 'FileUtil'

class Mp4Concat
	def self.concat(srcPaths, dstPath)
		escapedSrcPaths=[]
		srcPaths.sort!
		srcPaths.each do |aSrc|
			escapedSrcPaths << Shellwords.escape(aSrc)
		end
		exec_cmd = "ffmpeg -i \"concat:#{escapedSrcPaths.join("|")}\" -c copy #{Shellwords.escape(dstPath)}"
		srcDir = FileUtil.getDirectoryFromPath(srcPaths[0])
		ExecUtil.execCmd(exec_cmd, srcDir)
	end

	def self.getCandidate(srcPath, scanFilter, numOfConcatFiles)
		path = File.expand_path(srcPath)
		files = []
		FileUtil.iteratePath( srcPath, scanFilter, files, false, false, 1)
		files = files.sort{|a,b| b<=>a}
		files = files.slice(0, numOfConcatFiles) if numOfConcatFiles!=0
		return files
	end

	def self.getCommonFilenamePart(srcPaths)
		result = ""
		paths = []
		srcPaths.each do |aSrc|
			paths << FileUtil.getFilenameFromPathWithoutExt(aSrc)
		end

		commonPath = paths[0].to_s
		commonPathLen = commonPath.length
		for i in 1..commonPathLen do
			theCommonPart = commonPath.slice(0, i)
			isFound = true
			paths.each do |aPath|
				if aPath.index(theCommonPart) != 0 then
					isFound = false
					break
				end
			end
			if isFound then
				result = theCommonPart
			else
				break
			end
		end
		return result
	end


	def self.getConcatFilename(srcPaths)
		result = ""
		srcPaths.each do |aSrc|
			filename = FileUtil.getFilenameFromPathWithoutExt(aSrc)
			result = result + (result.empty? ? "" : "_") + filename
		end
		commonPart = getCommonFilenamePart(srcPaths)
		if commonPart!="" then
			result = result.gsub(commonPart, "")
			result = result.gsub("__", "_")
			result = "#{commonPart}_#{result}\.mp4"
		end
		return result
	end

	def self.concatEnumeratedMp4(srcPath, scanFilter, numOfConcatFiles, dstPath, isDeleteAfterConcat)
		srcPaths = getCandidate( srcPath, scanFilter, numOfConcatFiles )
		dstPath = File.expand_path(dstPath)
		dstDir = FileUtil.getDirectoryFromPath( dstPath )
		FileUtil.ensureDirectory( dstDir ) if dstDir != dstPath
		dstFilename = FileUtil.getFilenameFromPath( dstPath )
		if File.directory?( dstDir+"/"+dstFilename ) then
			# dstPath is directory specified then need to generate output filename
			filename = getConcatFilename(srcPaths)
			dstPath = dstDir + "/" + dstFilename + "/" + filename
			dstFilename = filename
		end
		# do concat
		concat(srcPaths, dstPath)
		# delete files after concat
		if File.exist?(dstPath) && File.size(dstPath)!=0 && isDeleteAfterConcat then
			srcPaths.each do |aSrc|
				FileUtils.rm_f(aSrc)
			end
		end
	end
end

options = {
	:sourcePath => ".",
	:filter => "\.mp4$",
	:sort => "reverse",
	:numOfConcatFiles => 0,
	:outputPath => "concat.mp4",
	:deleteAfterConcat => false
}

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: -s /media/data/camera -f \"[0-9]+\.mp4\""

	opts.on("-i", "--sourcePath=", "Set source path (default:#{options[:sourcePath]})") do |sourcePath|
		options[:sourcePath] = sourcePath.to_s
	end

	opts.on("-f", "--filter=", "Set source regexp file filter (default:#{options[:filter]})") do |filter|
		options[:filter] = filter.to_s
	end

	opts.on("-s", "--sort=", "Set sort mode normal or revrese (default:#{options[:sort]})") do |sort|
		options[:sort] = sort.to_s
	end

	opts.on("-n", "--numOfConcatFiles=", "Set number of concat files 0:all (default:#{options[:numOfConcatFiles]})") do |numOfConcatFiles|
		options[:numOfConcatFiles] = numOfConcatFiles.to_i
	end

	opts.on("-o", "--outputPath=", "Set output path (default:#{options[:outputPath]})") do |outputPath|
		options[:outputPath] = outputPath.to_s
	end

	opts.on("-d", "--deleteAfterConcat", "Set if you want to delete the source files after concat (default:#{options[:deleteAfterConcat]})") do
		options[:deleteAfterConcat] = true
	end
end.parse!

Mp4Concat.concatEnumeratedMp4( options[:sourcePath], options[:filter], options[:numOfConcatFiles], options[:outputPath], options[:deleteAfterConcat] )
