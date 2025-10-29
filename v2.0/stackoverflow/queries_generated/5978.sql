-- {"query": "5978.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 748} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate > NOW() - INTERVAL '90 days'
),
TopAuthors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.LastAccessDate DESC) AS rn
  FROM Users u
  JOIN Posts p ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND u.Reputation IS NOT NULL
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS Upvotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS Downvotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS NetVotes,
    AVG(p.Score) AS AvgPostScore,
    COUNT(DISTINCT p.Id) AS PostCount
  FROM (
    SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName, p.Id
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.ClosedDate IS NULL
  ) t
  LEFT JOIN Votes v ON v.PostId = t.Id
  LEFT JOIN Posts p ON p.Id = t.Id
  GROUP BY t.TagName
),
ExpandedTop AS (
  SELECT
    r.PostId,
    r.Title,
    r.CreationDate AS PostDate,
    r.ViewCount,
    r.Score,
    r.OwnerUserId,
    r.Tags,
    a.DisplayName AS OwnerName,
    a.Reputation AS OwnerReputation,
    t.TagName,
    t.Upvotes,
    t.Downvotes,
    t.NetVotes,
    t.AvgPostScore,
    t.PostCount,
    -- Complex computed column: score-adjusted popularity
    (r.Score * 1.0 + r.ViewCount * 0.1 + COALESCE(t.NetVotes,0) * 2.0) AS Popularity
  FROM RecentTopQuestions r
  LEFT JOIN TopAuthors a ON a.UserId = r.OwnerUserId
  LEFT JOIN TagActivity t ON t.TagName = (SELECT TagName FROM unnest(string_to_array(substring(r.Tags, 2, length(r.Tags)-2), '><')) AS TagName LIMIT 1)
  WHERE r.rn <= 50
)
SELECT
  e.PostId,
  e.Title,
  e.PostDate,
  e.ViewCount,
  e.Score,
  e.OwnerName,
  e.OwnerReputation,
  e.Tags,
  e.TagName,
  e.Upvotes,
  e.Downvotes,
  e.NetVotes,
  e.AvgPostScore,
  e.PostCount,
  e.Popularity
FROM ExpandedTop e
ORDER BY e.Popularity DESC
LIMIT 100;