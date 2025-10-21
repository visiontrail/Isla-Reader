//
//  UTTypeExtensions.swift
//  Isla Reader
//
//  Created by AI Assistant on 2025/1/20.
//

import UniformTypeIdentifiers

extension UTType {
    static var epub: UTType {
        UTType(filenameExtension: "epub") ?? UTType.data
    }
}