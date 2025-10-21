-- {"query": "26.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-3.5-turbo", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2003, "output_tokens": 152} 
WITH ranked_users AS (
  SELECT Id, Reputation, DENSE_RANK() OVER (ORDER BY Reputation DESC) AS rank
  FROM Users
),
top_ten_percent AS (
  SELECT *
  FROM ranked_users
  WHERE rank <= (SELECT COUNT(*) * 0.1 FROM Users)
)
SELECT DISTINCT p.Id, p.Title, p.Score,
  CONCAT(u.DisplayName, ' (', u.Location, ')') AS UserLocation,
  (
    SELECT COUNT(*)
    FROM Posts a
    WHERE a.ParentId = p.Id AND a.PostTypeId = 2
  ) AS AnswerCount
FROM Posts p
JOIN top_ten_percent ttp ON p.OwnerUserId = ttp.Id
JOIN Users u ON p.OwnerUserId = u.Id;