//
//  TimeInterval+Cache.swift
//  Harbor
//
//  Created by Javier Manzo on 05/07/2025.
//

import Foundation

public extension TimeInterval {
    /// No expiration time (uses default from cache manager).
    static var noExpiration: TimeInterval? { nil }
    
    /// One minute cache expiration.
    static var oneMinute: TimeInterval { 60 }
    
    /// Five minutes cache expiration.
    static var fiveMinutes: TimeInterval { 5 * 60 }
    
    /// Fifteen minutes cache expiration.
    static var fifteenMinutes: TimeInterval { 15 * 60 }
    
    /// Thirty minutes cache expiration.
    static var thirtyMinutes: TimeInterval { 30 * 60 }
    
    /// One hour cache expiration.
    static var oneHour: TimeInterval { 60 * 60 }
    
    /// Six hours cache expiration.
    static var sixHours: TimeInterval { 6 * 60 * 60 }
    
    /// Twelve hours cache expiration.
    static var twelveHours: TimeInterval { 12 * 60 * 60 }
    
    /// One day cache expiration.
    static var oneDay: TimeInterval { 24 * 60 * 60 }
    
    /// Three days cache expiration.
    static var threeDays: TimeInterval { 3 * 24 * 60 * 60 }
    
    /// One week cache expiration.
    static var oneWeek: TimeInterval { 7 * 24 * 60 * 60 }
    
    /// One month cache expiration (30 days).
    static var oneMonth: TimeInterval { 30 * 24 * 60 * 60 }
    
    /// Three months cache expiration (90 days).
    static var threeMonths: TimeInterval { 90 * 24 * 60 * 60 }
    
    /// Six months cache expiration (180 days).
    static var sixMonths: TimeInterval { 180 * 24 * 60 * 60 }
    
    /// One year cache expiration (365 days).
    static var oneYear: TimeInterval { 365 * 24 * 60 * 60 }
}
