-- {"query": "44064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2294, "output_tokens": 747}
Here is an elaborate SQL query for performance benchmarking:

WITH question_stats AS (
  SELECT p.Id, p.CreationDate, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ViewCount, p.Score, 
         u.Reputation, u.UpVotes, u.DownVotes, u.Views,
         CAST(DATEDIFF(CURRENT_TIMESTAMP, p.CreationDate) AS DECIMAL) / 365.25 AS age_years,
         CASE WHEN p.ClosedDate IS NULL THEN 0 ELSE 1 END AS is_closed,
         CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS is_community_owned
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
),
answer_stats AS (
  SELECT p.ParentId, COUNT(*) AS answer_count
  FROM Posts p
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
badges_stats AS (
  SELECT b.UserId, COUNT(*) AS badge_count, 
         SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold_badges,
         SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver_badges,
         SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze_badges
  FROM Badges b
  GROUP BY b.UserId
)
SELECT q.Id, q.CreationDate, q.AnswerCount, q.CommentCount, q.FavoriteCount, q.ViewCount, q.Score, 
       q.Reputation, q.UpVotes, q.DownVotes, q.Views, q.age_years, q.is_closed, q.is_community_owned,
       a.answer_count, 
       b.badge_count, b.gold_badges, b.silver_badges, b.bronze_badges
FROM question_stats q
LEFT JOIN answer_stats a ON q.Id = a.ParentId
LEFT JOIN badges_stats b ON q.Reputation = b.UserId
ORDER BY q.CreationDate DESC
LIMIT 1000;

This query retrieves a set of performance-related statistics for the most recent 1,000 questions, including:

- Question-level statistics (creation date, answer/comment/favorite/view counts, score, etc.)
- User-level statistics (reputation, upvotes/downvotes, total views)
- Question age in years
- Whether the question is closed or community-owned
- The number of answers for each question
- The number and types of badges the question owner has

The use of common table expressions (CTEs) allows the query to efficiently calculate these aggregated statistics without repetitive subqueries. The final result is sorted by the most recent questions and limited to 1,000 rows for performance reasons.
