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
	def self.concat(srcPaths, dstPath, additionalOptions)
		srcDir = FileUtil.getDirectoryFromPath(srcPaths[0])
		_tmpList = "#{srcDir}/.tmpList.lst"
		srcPaths.sort!
		escapedSrcPaths=[]
		srcPaths.each do |aSrc|
			aSrc = aSrc.gsub(srcDir+"/", "")
			escapedSrcPaths << "file \'#{Shellwords.escape(aSrc)}\'"
		end
		FileUtil.writeFile(_tmpList, escapedSrcPaths)
		if !escapedSrcPaths.empty? then
			exec_cmd = "ffmpeg -f concat -i #{Shellwords.escape(_tmpList)} -c copy #{Shellwords.escape(dstPath)} #{additionalOptions}"
			ExecUtil.execCmd(exec_cmd, srcDir)
		end
		FileUtils.rm_f(_tmpList)
	end

	def self.getCandidate(srcPath, scanFilter, numOfConcatFiles, isReverseSort=false, isSkipLockedFiles=false)
		path = File.expand_path(srcPath)
		files = []
		FileUtil.iteratePath( path, scanFilter, files, false, false, 1)
		if isSkipLockedFiles then
			_files = []
			files.each do |aFile|
				_files << aFile if !FileUtil.isFileLocked(aFile)
			end
			files = _files
		end
		files = isReverseSort ? files.sort{|a,b| b<=>a} : files.sort{|a,b| a<=>b}
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


	def self.getConcatFilename(srcPaths, isFirstLast=false)
		result = ""
		if isFirstLast then
			result = FileUtil.getFilenameFromPathWithoutExt(srcPaths.first)
			result = result + "_" + FileUtil.getFilenameFromPathWithoutExt(srcPaths.last) if srcPaths.first!=srcPaths.last
		else
			srcPaths.each do |aSrc|
				filename = FileUtil.getFilenameFromPathWithoutExt(aSrc)
				result = result + (result.empty? ? "" : "_") + filename
			end
		end
		commonPart = getCommonFilenamePart(srcPaths)
		if commonPart!="" then
			result = result.gsub(commonPart, "")
			result = result.gsub("__", "_")
			result = "#{commonPart}_#{result}"
		end
		result="#{result}.mp4" if !result.end_with?(".mp4")
		return result
	end


	def self.concatEnumeratedMp4(srcPath, scanFilter, sortMode, numOfConcatFiles, avoidLockedFiles, dstPath, filenameMode, additionalOptions, isDeleteAfterConcat)
		# get concat files
		srcPaths = getCandidate( srcPath, scanFilter, numOfConcatFiles, sortMode=="rerverse", avoidLockedFiles )

		# ensure output path
		dstPath = File.expand_path(dstPath)
		dstDir = FileUtil.getDirectoryFromPath( dstPath )
		FileUtil.ensureDirectory( dstDir ) if dstDir != dstPath
		dstFilename = FileUtil.getFilenameFromPath( dstPath )

		# generate concat filename if no filename specified
		if File.directory?( dstDir+"/"+dstFilename ) then
			# dstPath is directory specified then need to generate output filename
			filename = getConcatFilename(srcPaths, filenameMode=="firstlast")
			dstPath = dstDir + "/" + dstFilename + "/" + filename
			dstFilename = filename
		end

		# do concat
		concat(srcPaths, dstPath, additionalOptions)

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
	:filter => "\\.mp4$",
	:avoidLockedFiles => false,
	:sort => "reverse",
	:numOfConcatFiles => 0,
	:outputPath => "concat.mp4",
	:filenameMode => "all",
	:additionalOptions => nil,
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

	opts.on("-l", "--avoidLockedFiles", "Set if you want to skip locked files (default:#{options[:avoidLockedFiles]})") do
		options[:avoidLockedFiles] = true
	end

	opts.on("-s", "--sort=", "Set sort mode normal or revrese (default:#{options[:sort]})") do |sort|
		options[:sort] = sort.to_s
	end

	opts.on("-n", "--numOfConcatFiles=", "Set number of concat files 0:all (default:#{options[:numOfConcatFiles]})") do |numOfConcatFiles|
		options[:numOfConcatFiles] = numOfConcatFiles.to_i
	end

	opts.on("-o", "--outputPath=", "Set output path. Note that if directory is specified, filename is automatically generated (default:#{options[:outputPath]})") do |outputPath|
		options[:outputPath] = outputPath.to_s
	end

	opts.on("-m", "--filenameMode=", "Set filename mode \"all\" or \"firstlast\" for automated concat filename (default:#{options[:filenameMode]})") do |filenameMode|
		options[:filenameMode] = filenameMode.to_s.downcase
	end

	opts.on("-a", "--additionalOptions=", "Set additional options for ffmpeg (default:#{options[:additionalOptions]})") do |additionalOptions|
		options[:additionalOptions] = additionalOptions
	end

	opts.on("-d", "--deleteAfterConcat", "Set if you want to delete the source files after concat (default:#{options[:deleteAfterConcat]})") do
		options[:deleteAfterConcat] = true
	end
end.parse!

srcPath = options[:sourcePath]
scanFilter = options[:filter]
sortMode = options[:sort]
numOfConcatFiles = options[:numOfConcatFiles]
avoidLockedFiles = options[:avoidLockedFiles]
dstPath = options[:outputPath]
filenameMode = options[:filenameMode]
additionalOptions = options[:additionalOptions]
isDeleteAfterConcat = options[:deleteAfterConcat]

# get concat files
srcPaths = []
if srcPath.include?(",") then
	paths = srcPath.split(",")
	paths.each do |aPath|
		srcPaths << File.expand_path(aPath)
	end
else
	srcPaths = Mp4Concat.getCandidate( srcPath, scanFilter, numOfConcatFiles, sortMode=="rerverse", avoidLockedFiles )
end

# ensure output path
dstPath = File.expand_path(dstPath)
dstDir = FileUtil.getDirectoryFromPath( dstPath )
FileUtil.ensureDirectory( dstDir ) if dstDir != dstPath
dstFilename = FileUtil.getFilenameFromPath( dstPath )

# generate concat filename if no filename specified
if File.directory?( dstDir+"/"+dstFilename ) then
	# dstPath is directory specified then need to generate output filename
	filename = Mp4Concat.getConcatFilename(srcPaths, filenameMode=="firstlast")
	dstPath = dstDir + "/" + dstFilename + "/" + filename
	dstFilename = filename
end

# do concat
Mp4Concat.concat(srcPaths, dstPath, additionalOptions)

# delete files after concat
if File.exist?(dstPath) && File.size(dstPath)!=0 && isDeleteAfterConcat then
	srcPaths.each do |aSrc|
		FileUtils.rm_f(aSrc)
	end
end
