-- {"query": "191.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1267} 
WITH UserAgg AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS PostCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
    COUNT(DISTINCT c.Id) AS CommentCount
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
Ranked AS (
  SELECT
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    UpVotesReceived,
    DownVotesReceived,
    CommentCount,
    (Reputation + UpVotesReceived - DownVotesReceived) AS Score
  FROM UserAgg
),
Final AS (
  SELECT
    *,
    DENSE_RANK() OVER (ORDER BY Score DESC) AS Rank
  FROM Ranked
)
SELECT
  UserId,
  DisplayName,
  Reputation,
  PostCount,
  UpVotesReceived,
  DownVotesReceived,
  CommentCount,
  Score,
  Rank
FROM Final
WHERE Rank <= 100
ORDER BY Rank, UserId;