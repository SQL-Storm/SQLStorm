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
    SELECT u.Id AS OwnerUserId,
           SUM(u.UpVotes) OVER (PARTITION BY u.Id) AS total_upvotes,
           ROW_NUMBER() OVER (ORDER BY u.Views DESC) AS views_rank,
           u.Views,
           u.UpVotes
      FROM Users u
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
  GROUP BY u.Id, u.Reputation, u.Views, sq1.comment_count, sq1.total_bounty_amount, sq2.total_upvotes, sq2.views_rank
  ORDER BY u.Reputation DESC
)
SELECT *
  FROM final_query
 LIMIT 10;