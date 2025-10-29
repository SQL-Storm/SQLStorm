-- {"query": "5904.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 716} 
WITH EliteActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(p.Id) AS PostsCount,
    SUM(p.Score) AS ScoreSum,
    SUM(p.ViewCount) AS ViewSum,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
TagImpact AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
  FROM Posts p
  WHERE p.PostTypeId = 1
),
Flagged AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId AS VoterId,
    v.CreationDate AS VoteDate,
    u.Reputation AS VoterRep,
    u.DisplayName AS VoterName
  FROM Votes v
  JOIN Users u ON v.UserId = u.Id
  WHERE v.VoteTypeId IN (10, 11) -- Deletion/Undeletion
),
OpenQuestions AS (
  SELECT
    p.Id AS QuestionId,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.ViewCount,
    p.Score,
    p.CreationDate,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.ClosedDate IS NULL
),
RecentActivity AS (
  SELECT
    o.QuestionId,
    o.OwnerUserId,
    o.Title,
    o.Tags,
    o.ViewCount,
    o.Score,
    o.CreationDate,
    o.LastActivityDate,
    ROW_NUMBER() OVER (PARTITION BY o.OwnerUserId ORDER BY o.LastActivityDate DESC) AS rn
  FROM OpenQuestions o
),
TopTagInfluence AS (
  SELECT
    ta.PostId,
    ta.tag,
    COUNT(*) AS TagCount,
    AVG(p.Score) AS AvgPostScore
  FROM TagImpact ta
  JOIN Posts p ON p.Id = ta.PostId
  GROUP BY ta.PostId, ta.tag
),
CrossJoinSummary AS (
  SELECT
    e.UserId,
    e.DisplayName,
    e.Reputation,
    e.PostsCount,
    e.ScoreSum,
    e.ViewSum,
    e.LastPostDate,
    tti.TagCount,
    tti.AvgPostScore,
    ROW_NUMBER() OVER (ORDER BY e.Reputation DESC, e.ViewSum DESC NULLS LAST) AS rn
  FROM EliteActivity e
  LEFT JOIN TopTagInfluence tti ON tti.PostId = (SELECT MAX(PostId) FROM TagImpact WHERE tag = tti.tag)
)
SELECT
  cu.UserId,
  cu.DisplayName,
  cu.Reputation,
  cu.PostsCount,
  cu.ScoreSum,
  cu.ViewSum,
  cu.LastPostDate,
  cu.TagCount,
  cu.AvgPostScore,
  cu.rn
FROM CrossJoinSummary cu
LEFT JOIN RecentActivity ra
  ON ra.OwnerUserId = cu.UserId AND ra.rn = 1
WHERE cu.rn <= 100
ORDER BY cu.Reputation DESC, cu.ViewSum DESC
LIMIT 100;