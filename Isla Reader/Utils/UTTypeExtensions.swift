//
//  UTTypeExtensions.swift
//  LanRead
//
//  Created by AI Assistant on 2025/1/20.
//

import UniformTypeIdentifiers

extension UTType {
    static var epub: UTType {
        UTType("org.idpf.epub-container") ?? UTType(filenameExtension: "epub") ?? UTType.data
    }
}