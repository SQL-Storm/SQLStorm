-- {"query": "5419.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 656} 
WITH TopActiveUsers AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    COUNT(p.Id) AS PostCount,
    SUM(p.Score) AS ScoreSum,
    MIN(p.CreationDate) AS FirstPostDate,
    STRING_AGG(DISTINCT t.Name, ',') AS PostTypes
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
  HAVING COUNT(p.Id) > 0
),
RecentActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    MAX(v.CreationDate) AS LastVoteDate,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpvotesGiven,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownvotesGiven,
    MAX(p.LastActivityDate) AS LastPostActivity
  FROM Users u
  LEFT JOIN Votes v ON v.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName
),
TagEngagement AS (
  SELECT
    u.Id AS UserId,
    COUNT(tt.Id) AS TagCount,
    STRING_AGG(t.TagName, ',') AS Tags
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Tags t ON t.Id = ANY(string_to_array(p.Tags, '><')::int[])
  LEFT JOIN Tags tt ON tt.Id = t.Id
  GROUP BY u.Id
),
Combined AS (
  SELECT
    t.UserId,
    t.DisplayName AS UserName,
    t.Reputation,
    t.CreationDate AS UserCreation,
    t.LastAccessDate AS UserLastAccess,
    t.Location,
    r.LastVoteDate,
    r.UpvotesGiven,
    r.DownvotesGiven,
    r.LastPostActivity,
    ta.TagCount,
    ta.Tags,
    hu.PostCount,
    hu.ScoreSum,
    hu.PostTypes
  FROM TopActiveUsers hu
  JOIN RecentActivity r ON r.UserId = hu.UserId
  LEFT JOIN TagEngagement ta ON ta.UserId = hu.UserId
)
SELECT
  UserId,
  UserName,
  Reputation,
  UserCreation,
  UserLastAccess,
  Location,
  LastVoteDate,
  UpvotesGiven,
  DownvotesGiven,
  LastPostActivity,
  TagCount,
  Tags,
  PostCount,
  ScoreSum,
  PostTypes
FROM Combined
WHERE
  (ScoreSum > 100 OR PostCount > 20)
  AND (TagCount IS NULL OR TagCount > 0)
ORDER BY
  ScoreSum DESC NULLS LAST,
  PostCount DESC NULLS LAST
LIMIT 100;