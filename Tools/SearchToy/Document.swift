//
//  Document.swift
//  SearchToy
//
//  Created by Darren Ford on 9/6/18.
//  Copyright © 2018 Darren Ford. All rights reserved.
//
//  MIT license
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//  documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial
//  portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
//  OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
//  OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

import Cocoa

import DFSearchKit

class Document: NSDocument {
	
	@IBOutlet weak var urlField: NSTextField!
	@IBOutlet var docContentView: NSTextView!
	
	@IBOutlet weak var filesTable: NSTableView!

	@IBOutlet weak var queryField: NSTextField!
	@IBOutlet var queryResultView: NSTextView!

	private var index: DFSearchIndexData = DFSearchIndexData.create()!
	private var indexer: DFSearchIndexAsyncController?

	@objc dynamic fileprivate var operationCount: Int = 0
	@objc dynamic fileprivate var files: [URL] = []

	override init() {
		super.init()

		// Create a blank index for empty documents
		self.indexer = DFSearchIndexAsyncController.init(index: index, delegate: self)

	}

	override var windowNibName: NSNib.Name? {
		// Returns the nib file name of the document
		// If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this property and override -makeWindowControllers instead.
		return NSNib.Name("Document")
	}

	override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
		self.updateFiles()
	}
}

// MARK: - Read/Write

extension Document
{
	override func data(ofType typeName: String) throws -> Data
	{
		return self.index.save()!
	}
	
	override func read(from data: Data, ofType typeName: String) throws
	{
		self.index = DFSearchIndexData.load(from: data)!
		self.indexer = DFSearchIndexAsyncController.init(index: index, delegate: self)
	}
}

// MARK: - Add text

extension Document
{
	@IBAction func addText(_ sender: NSButton)
	{
		if let url = URL(string: self.urlField.stringValue)
		{
			let text = self.docContentView.string
			self.addTextOperation([DFSearchIndexAsyncController.TextTask(url: url, text: text)])
		}
	}
	
	@objc func addTextOperation(_ textTasks: [DFSearchIndexAsyncController.TextTask])
	{
		self.indexer?.addText(async: textTasks, complete: { [weak self] textTasks in
			if let blockSelf = self {
				DispatchQueue.main.async {
					blockSelf.undoManager?.registerUndo(withTarget: blockSelf, selector:#selector(blockSelf.removeTextOperation), object:textTasks)
					blockSelf.undoManager?.setActionName("Add Text")
					blockSelf.updateFiles()
				}
			}
		})
	}
	
	@objc func removeTextOperation(_ textTasks: [DFSearchIndexAsyncController.TextTask])
	{
		self.indexer?.removeText(async: textTasks, complete: { [weak self] textTasks in
			if let blockSelf = self {
				DispatchQueue.main.async {
					blockSelf.undoManager?.registerUndo(withTarget: blockSelf, selector:#selector(blockSelf.addTextOperation), object:textTasks)
					blockSelf.undoManager?.setActionName("Remove Text")
					blockSelf.updateFiles()
				}
			}
		})
	}
}

// MARK: - Add files

extension Document
{
	@IBAction func addFiles(_ sender: Any)
	{
		let panel = NSOpenPanel()
		panel.showsResizeIndicator    = true;
		panel.canChooseDirectories    = true;
		panel.canCreateDirectories    = true;
		panel.allowsMultipleSelection = true;
		let window = self.windowControllers[0].window
		panel.beginSheetModal(for: window!) { (result) in
			if result == NSApplication.ModalResponse.OK
			{
				self.addURLs(DFSearchIndexAsyncController.FilesTask(panel.urls))
			}
		}
	}
	
	@objc func addURLs(_ fileTask: DFSearchIndexAsyncController.FilesTask)
	{
		self.indexer?.addURLs(async: fileTask, flushWhenComplete: true, complete: { [weak self] fileTask in
			if let blockSelf = self {
				DispatchQueue.main.async {
					blockSelf.undoManager?.registerUndo(withTarget: blockSelf, selector:#selector(blockSelf.removeURLs), object:fileTask)
					blockSelf.undoManager?.setActionName("Add \(fileTask.urls.count) Documents")
					blockSelf.updateFiles()
				}
			}
		})
	}
	
	@objc func removeURLs(_ fileTask: DFSearchIndexAsyncController.FilesTask) {
		self.indexer?.removeURLs(async: fileTask, flushWhenComplete: true, complete: { [weak self] fileTask in
			if let blockSelf = self {
				DispatchQueue.main.async {
					blockSelf.undoManager?.registerUndo(withTarget: blockSelf, selector:#selector(blockSelf.addURLs), object:fileTask)
					blockSelf.undoManager?.setActionName("Remove \(fileTask.urls.count) Documents")
					blockSelf.updateFiles()
				}
			}
		})
	}
}

// MARK: - Search

extension Document
{

	func searchNext(_ searchTask: DFSearchIndexAsyncController.SearchTask)
	{
		searchTask.next(10) { [weak self] (searchTask, results) in

			if results.moreResultsAvailable
			{
				self?.searchNext(searchTask)
			}
		}
	}

	@IBAction func searchText(_ sender: NSButton)
	{
		let searchText = self.queryField.stringValue

		self.index.flush()

		if searchText.count > 0 {
			let result = index.search(searchText)

			var str: String = ""
			result.forEach {
				str += "\($0.url) - (\($0.score))\n"
			}

			self.queryResultView.string = str
		}
		else
		{
			let result = index.documents()
			var str: String = ""
			result.forEach {
				str += "\($0)\n"
			}
			self.queryResultView.string = str
		}
	}
}

extension Document: DFSearchIndexAsyncControllerProtocol
{
	func queueDidEmpty(_ indexer: DFSearchIndexAsyncController)
	{
	}

	func queueDidChange(_ indexer: DFSearchIndexAsyncController, count: Int)
	{
		DispatchQueue.main.async { [weak self] in
			self?.operationCount = count
		}
	}

	func updateFiles()
	{
		self.files = self.index.documents(termState: .NotEmpty)
	}
}

