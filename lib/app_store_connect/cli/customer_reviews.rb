# frozen_string_literal: true

module AppStoreConnect
  class CLI
    # Customer review CLI commands
    module CustomerReviews
      def cmd_customer_reviews
        puts "\e[1mCustomer Reviews\e[0m"
        puts '=' * 50
        puts

        reviews = client.customer_reviews(limit: 20)

        if reviews.empty?
          puts 'No customer reviews found.'
          return
        end

        reviews.each_with_index do |review, i|
          stars = "\e[33m#{'★' * review[:rating]}#{'☆' * (5 - review[:rating])}\e[0m"
          created = review[:created_date] ? Time.parse(review[:created_date]).strftime('%Y-%m-%d') : 'N/A'

          puts "#{i + 1}. #{stars} (#{review[:territory]})"
          puts "   \e[1m#{review[:title]}\e[0m"
          puts "   #{review[:body][0..200]}#{'...' if review[:body].length > 200}" if review[:body]
          puts "   By: #{review[:reviewer_nickname]} on #{created}"
          puts "   ID: #{review[:id]}"

          # Check for existing response
          begin
            response = client.customer_review_response(review_id: review[:id])
            if response
              puts "   \e[32m-> Response:\e[0m #{response[:response_body][0..100]}#{'...' if response[:response_body].length > 100}"
            end
          rescue ApiError
            # No response or error fetching
          end
          puts
        end
      end

      def cmd_respond_review
        if @options.length < 2
          puts "\e[31mUsage: asc respond-review <review_id> \"Your response\"\e[0m"
          puts 'Example: asc respond-review abc123 "Thank you for your feedback!"'
          puts
          puts "Use 'asc customer-reviews' to find review IDs."
          exit 1
        end

        review_id = @options[0]
        response_body = @options[1..].join(' ')

        # Check if response already exists
        existing = client.customer_review_response(review_id: review_id)
        if existing
          puts "\e[33mThis review already has a response:\e[0m"
          puts "  #{existing[:response_body]}"
          puts
          print 'Delete existing response and create new one? (y/N): '
          confirm = $stdin.gets.chomp.downcase

          if confirm == 'y'
            client.delete_customer_review_response(response_id: existing[:id])
            puts "\e[32mDeleted existing response.\e[0m"
          else
            puts 'Cancelled.'
            return
          end
        end

        client.create_customer_review_response(review_id: review_id, response_body: response_body)
        puts "\e[32mResponse posted successfully!\e[0m"
        puts "  Review ID: #{review_id}"
        puts "  Response: #{response_body}"
      end
    end
  end
end
