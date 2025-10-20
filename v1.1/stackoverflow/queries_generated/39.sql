-- {"query": "39.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 273} 
WITH subquery1 AS (
    SELECT p.OwnerUserId,
           COUNT(DISTINCT c.Id) AS comment_count,
           SUM(v.BountyAmount) AS total_bounty_amount
      FROM Posts p
           LEFT JOIN Comments c ON p.Id = c.PostId
           LEFT JOIN Votes v ON p.Id = v.PostId
     WHERE p.Score > 5
       AND p.PostTypeId = 1
  GROUP BY p.OwnerUserId
),
subquery2 AS (
    SELECT DISTINCT OwnerUserId,
                    SUM(UpVotes) OVER (PARTITION BY OwnerUserId) AS total_upvotes,
                    ROW_NUMBER() OVER (ORDER BY Views DESC) AS views_rank
        FROM Users
),
final_query AS (
    SELECT u.Id AS user_id,
           u.Reputation,
           u.Views,
           sq1.comment_count,
           COALESCE(sq1.total_bounty_amount, 0) AS total_bounty_amount,
           COALESCE(sq2.total_upvotes, 0) AS total_upvotes,
           sq2.views_rank
      FROM Users u
           LEFT JOIN subquery1 sq1 ON u.Id = sq1.OwnerUserId
           LEFT JOIN subquery2 sq2 ON u.Id = sq2.OwnerUserId
  ORDER BY u.Reputation DESC
)
SELECT *
  FROM final_query
 LIMIT 10;