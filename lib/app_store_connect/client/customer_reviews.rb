# frozen_string_literal: true

module AppStoreConnect
  class Client
    # Customer review methods
    module CustomerReviews
      # Get customer reviews for the app
      def customer_reviews(target_app_id: nil, limit: 20, sort: '-createdDate')
        target_app_id ||= @app_id
        get("/apps/#{target_app_id}/customerReviews?limit=#{limit}&sort=#{sort}")['data'].map do |review|
          {
            id: review['id'],
            rating: review.dig('attributes', 'rating'),
            title: review.dig('attributes', 'title'),
            body: review.dig('attributes', 'body'),
            reviewer_nickname: review.dig('attributes', 'reviewerNickname'),
            created_date: review.dig('attributes', 'createdDate'),
            territory: review.dig('attributes', 'territory')
          }
        end
      end

      # Get the response to a customer review
      def customer_review_response(review_id:)
        result = get("/customerReviews/#{review_id}/response")['data']
        return nil unless result

        {
          id: result['id'],
          response_body: result.dig('attributes', 'responseBody'),
          last_modified_date: result.dig('attributes', 'lastModifiedDate'),
          state: result.dig('attributes', 'state')
        }
      rescue ApiError => e
        return nil if e.message.include?('Not found')

        raise
      end

      # Respond to a customer review
      def create_customer_review_response(review_id:, response_body:)
        post('/customerReviewResponses', body: {
               data: {
                 type: 'customerReviewResponses',
                 attributes: {
                   responseBody: response_body
                 },
                 relationships: {
                   review: {
                     data: {
                       type: 'customerReviews',
                       id: review_id
                     }
                   }
                 }
               }
             })
      end

      # Delete a customer review response
      def delete_customer_review_response(response_id:)
        delete("/customerReviewResponses/#{response_id}")
      end
    end
  end
end
