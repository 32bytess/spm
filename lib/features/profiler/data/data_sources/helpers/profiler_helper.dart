import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:spm/core/constants/app_constants.dart';

class ProfilerHelper {
  ({int totalCount, int maxDepth}) analyzeSubtree(Element root) {
    int totalCount = 0;
    int maxDepth = 0;

    void visit(Element el, int currentDepth) {
      totalCount++;
      if (currentDepth > maxDepth) maxDepth = currentDepth;

      el.visitChildren((child) {
        visit(child, currentDepth + 1);
      });
    }

    visit(root, 0);
    return (totalCount: totalCount, maxDepth: maxDepth);
  }

  bool isDescendantOf(Element candidate, Element root) {
    if (candidate == root) return true;
    bool found = false;
    candidate.visitAncestorElements((ancestor) {
      if (ancestor == root) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// Sends the structured profiler events through the Dart VM service using
  /// [developer.postEvent], enabling programmatic capture by the CLI tool.
  void logEvent(Map<String, dynamic> data) =>
      developer.postEvent(AppConstants.vmServiceEventName, data);
}
