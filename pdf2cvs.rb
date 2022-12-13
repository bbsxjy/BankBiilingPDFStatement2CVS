#!/usr/bin/env ruby
# chasepdf2csv -- Convert Chase credit card statements from PDF to CSV. Written
# to easily import older statements into QuickBooks Online/Self-Employed. Chase
# unfortunately only offers statements up to 6 months in the past, making it a
# huge chore to synchronize past transactions.
#
# How to Use
# ----------
# This script requires Ruby >2.0.0 and pdftotext. Copy this script somewhere and
# make it executable. Run it like any other command.
#
# ISC License
# -----------
# Copyright (c) 2018-2020 Ivy Evans <ivy@ivyevans.net>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

require 'csv'
require 'optparse'

def error(msg)
  STDERR.puts("error: #{msg}")
end

def fatal(msg)
  error(msg)
  exit 1
end

class Statement
  CHASE_DUE_DATE_PATTERN = %r{
    Payment\s+Due\s+Date:?
    \s+
    (?<month>\d{2})/(?<day>\d{2})/(?<year>\d{2})
  }x

  AMEX_DUE_DATE_PATTERN = %r{
    Payment\s+Due\s+Date?
    \s+
    (?<month>\d{2})/(?<day>\d{2})/(?<year>\d{2})
  }x

  DISCOVER_DUE_DATE_PATTERN = %r{
    Payment\s+Due\s+Date?
    \s+
    (?<month>\w+)\s(?<day>\d{2}),\s(?<year>\d{4})
  }x

  BOA_DUE_DATE_PATTERN = %r{
    Ending\s+balance\s+on?
    \s+
    (?<month>\w+)\s(?<day>\d{2}),\s(?<year>\d{4})
  }x

  class Transaction
    # Regex for matching transactions in a Chase credit statement.
    #
    # Edge Case: Amazon orders
    #
    #   01/23 AMAZON MKTPLACE PMTS AMZN.COM/BILL WA 12.34\n
    #   Order Number 123-4567890-1234567\n
    #
    # Edge Case: Rewards points
    #
    #   01/23 AMAZON MARKETPLACE AMZN.COM/BILLWA 4.56 7,890
    #
    CHASE_LINE_ITEM_PATTERN = %r{
      (?<date>\d{2}/\d{2})
      \s+
      (?<description>.+)
      \s+
      (?<amount>-?[\d,]+\.\d{2})
      (
        [ ]
        (?<points>[1-9][\d,]+)?
        |
        \s*
        Order\s+Number\s+
        (?<order_num>[^\s]+)
      )?
    }x

    AMEX_LINE_ITEM_PATTERN = %r{
      (?<date>\d{2}/\d{2}/\d{2})\*?
      \s+
      (?<description>[^$].*)
      \s+
      (?<amount>-?\$[\d,]+\.\d{2})
      (
        [ ]
        (?<points>[1-9][\d,]+)?
        |
        \s*
        Order\s+Number\s+
        (?<order_num>[^\s]+)
      )?
    }x

    AMEX_LINE_ITEM_PATTERN2 = %r{
      (?<date>\d{2}/\d{2}/\d{2})\*?
      \s+
      (?<description>[^$].*)
    }x

    DISCOVER_LINE_ITEM_PATTERN = %r{
      (?<date>\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|(Nov|Dec)(?:ember)?)\s\d{1,2})
      \s+ (\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|(Nov|Dec)(?:ember)?)\s\d{1,2})\s+
      (?<description>.+)
      \s+
      (?<amount>-?[\d,]+\.\d{2})
      (
        [ ]
        (?<points>[1-9][\d,]+)?
        |
        \s*
        Order\s+Number\s+
        (?<order_num>[^\s]+)
      )?
    }x

    DISCOVER_LINE_ITEM_PATTERN2 = %r{
(INTEREST CHARGE ON PURCHASES \$)\s(-?[\d,]+\.\d{2})
    }x

    BOA_LINE_ITEM_PATTERN = %r{
      (?<date>\d{2}/\d{2}/\d{2})
      \s+
      (?<description>.+)
      \s+
      (?<amount>-?[\d,]+\.\d{2})
      (
        [ ]
        (?<points>[1-9][\d,]+)?
        |
        \s*
        Order\s+Number\s+
        (?<order_num>[^\s]+)
      )?
    }x

    BOA_LINE_ITEM_PATTERN2 = %r{
      (?<date>\d{2}/\d{2}/\d{2})\*?
      \s+
      (?<description>[^$].*)
    }x

    def self.scan(output, year)

      #puts output

      # Chase
      # output.to_enum(:scan, CHASE_LINE_ITEM_PATTERN).collect {
      #   Transaction.new(Regexp.last_match, year, true)
      # }

      transactions = []
      last_data = nil
      last_descriptions = ""

      # Amex
      # output.split("\n").each { |s|
      #   s[AMEX_LINE_ITEM_PATTERN]
      #   data = Regexp.last_match
      #   unless data.nil?
      #     last_data = nil
      #     last_descriptions = ""
      #     transactions.push(Transaction.new(data, year))
      #     next
      #   end
      #
      #   s[AMEX_LINE_ITEM_PATTERN2]
      #   data = Regexp.last_match
      #   unless data.nil?
      #     s[/Account Ending/]
      #     skipped_data = Regexp.last_match
      #     unless skipped_data.nil?
      #       next
      #     end
      #     last_data = data
      #     last_descriptions = last_data[:description]
      #     next
      #   end
      #
      #   unless last_data.nil?
      #     s[/-?\$[\d,]+\.\d{2}/]
      #     money_data = Regexp.last_match
      #     unless money_data.nil?
      #       result = {}
      #       result[:date] = last_data[:date]
      #       result[:description] = last_descriptions
      #       result[:amount] = money_data
      #       transactions.push(Transaction.new(result, year))
      #       last_data = nil
      #       last_descriptions = ""
      #       next
      #     end
      #     last_descriptions += " " + s
      #   end
      # }

      # Discover
      # last_date = nil
      # output.to_enum(:scan, DISCOVER_LINE_ITEM_PATTERN).collect {
      #   data = Regexp.last_match
      #   result = {}
      #   result[:description] = data[:description]
      #   result[:amount] = data[:amount]
      #   new_date = data[:date].split("\s")
      #   result[:date] = Date::ABBR_MONTHNAMES.index(new_date[0]).to_s + "/" + new_date[1]
      #   last_date = result[:date]
      #   transactions.push(Transaction.new(result, year, true))
      # }
      #
      #
      # output.split("\n").each { |s|
      #   s[/(?<description>INTEREST CHARGE ON PURCHASES \$)\s+(?<amount>-?[\d,]+\.\d{2})/]
      #   data = Regexp.last_match
      #   unless data.nil?
      #     result = {}
      #     result[:description] = data[:description]
      #     result[:amount] = data[:amount]
      #     result[:date] = last_date
      #     transactions.push(Transaction.new(result, year, true))
      #   end
      # }

      # Boa
      output.split("\n").each { |s|
        s[BOA_LINE_ITEM_PATTERN]
        data = Regexp.last_match
        unless data.nil?
          last_data = nil
          last_descriptions = ""
          transactions.push(Transaction.new(data, year))
          next
        end

        s[BOA_LINE_ITEM_PATTERN2]
        data = Regexp.last_match
        unless data.nil?
          puts data
          last_data = data
          last_descriptions = last_data[:description]
          next
        end

        unless last_data.nil?
          s[/^-?(?:0|[1-9]\d{0,2}(?:,?\d{3})*)(?:\.\d{2})?$/]
          money_data = Regexp.last_match
          unless money_data.nil?
            result = {}
            result[:date] = last_data[:date]
            result[:description] = last_descriptions
            result[:amount] = money_data
            transactions.push(Transaction.new(result, year))
            last_data = nil
            last_descriptions = ""
            next
          end
          last_descriptions += " " + s
        end
      }

      return transactions
    end

    def initialize(data, year, isNeedAppendYear=false)
      if isNeedAppendYear
        @date = data[:date]+"/#{year}"
      else
        @date = data[:date]
      end
      @description = data[:description]
      @amount = data[:amount]
      @points = data[:points]
      @order_num = data[:order_num]
    end

    attr_reader :date, :amount, :points, :order_num
    alias rewards? points
    alias order_num? order_num

    def description
      order_num? ? "#{@description} ##{order_num}" : @description
    end

    def to_hash
      {
        date: date,
        description: description,
        amount: amount,
        points: points,
        order_num: order_num,
      }
    end
    alias to_h to_hash
  end

  attr_reader :line_items

  def self.parse(path)
    output = `pdftotext -raw #{path} -`
    unless $?.success?
      fatal "pdftotext: failed to parse #{path} (exit code #{$?})"
    end

    #puts(output)

    unless m = (output.match(CHASE_DUE_DATE_PATTERN) or output.match(AMEX_DUE_DATE_PATTERN) or output.match(DISCOVER_DUE_DATE_PATTERN) or output.match(BOA_DUE_DATE_PATTERN))
      fatal "parse error: could not match due date in #{path}"
    end

    new(Transaction.scan(output, m[:year]))
  end

  def initialize(line_items)
    @line_items = line_items
  end

  def each_line_item(&block)
    line_items.each(&block)
  end
end

def main(args = ARGV)
  # unless system('command -v pdftotext >/dev/null 2>&1')
  #   fatal "error: pdftotext not found!"
  # end

  outfile = STDOUT
  options = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] FILE..."

    opts.on('-o', '--output=FILE', 'Output to file') do |path|
      outfile = File.open(path, 'w')
    end
    opts.on('-h', '--help', 'Show this message') do
      puts opts
      exit
    end
  end
  options.parse!(args)

  if ARGV.empty?
    fatal "error: no files specified"
    exit 1
  end

  csv = CSV.new(
    outfile, headers: %w[Date Description Amount], write_headers: true,
    )

  ARGV.each do |file|
    Statement.parse(file).each_line_item do |line_item|
      #p line_item
      next if line_item.rewards?
      csv << [
        line_item.date, line_item.description, line_item.amount
      ]
    end
  end
end

if $0 == __FILE__
  main
end