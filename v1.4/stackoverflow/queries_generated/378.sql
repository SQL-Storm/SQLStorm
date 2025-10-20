-- {"query": "378.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17646} 
WITH PostStats AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    pt.Name AS PostTypeName,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
    p.Tags,
    p.Body,
    COALESCE(v.TotalVotes, 0) AS TotalVotes,
    COALESCE(c.CommentCount, 0) AS CommentCount,
    COALESCE(b.TotalBadges, 0) AS BadgesOwned,
    (p.AcceptedAnswerId IS NOT NULL) AS HasAcceptedAnswer,
    (regexp_split_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))[1] AS PrimaryTag,
    COALESCE((SELECT AVG(u2.Reputation)
              FROM Comments c2
              JOIN Users u2 ON c2.UserId = u2.Id
              WHERE c2.PostId = p.Id), 0) AS AvgCommenterRep,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC, p.Score DESC) AS rn
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (SELECT PostId, COUNT(*) AS TotalVotes FROM Votes GROUP BY PostId) v ON p.Id = v.PostId
  LEFT JOIN (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) c ON p.Id = c.PostId
  LEFT JOIN (SELECT UserId, COUNT(*) AS TotalBadges FROM Badges GROUP BY UserId) b ON p.OwnerUserId = b.UserId
)
SELECT
  Id,
  Title,
  PostTypeName,
  OwnerName,
  OwnerUserId,
  Score,
  ViewCount,
  AnswerCount,
  CommentCount,
  TotalVotes,
  BadgesOwned,
  HasAcceptedAnswer,
  CreationDate,
  LastActivityDate,
  PrimaryTag,
  substr(Body, 1, 200) AS BodySnippet,
  rn,
  (Score * 3.0 + (ViewCount::float / 1000) * 2.0 + AnswerCount * 4.0 +
   TotalVotes * 1.5 + BadgesOwned * 2.0 +
   CASE WHEN HasAcceptedAnswer THEN 50 ELSE 0 END) AS HotScore
FROM PostStats
WHERE PostTypeId = 1
  AND rn <= 100

UNION ALL

SELECT
  Id,
  Title,
  PostTypeName,
  OwnerName,
  OwnerUserId,
  Score,
  ViewCount,
  AnswerCount,
  CommentCount,
  TotalVotes,
  BadgesOwned,
  HasAcceptedAnswer,
  CreationDate,
  LastActivityDate,
  PrimaryTag,
  substr(Body, 1, 200) AS BodySnippet,
  rn,
  (Score * 3.0 + (ViewCount::float / 1000) * 2.0 + AnswerCount * 4.0 +
   TotalVotes * 1.5 + BadgesOwned * 2.0 +
   CASE WHEN HasAcceptedAnswer THEN 50 ELSE 0 END) AS HotScore
FROM PostStats
WHERE PostTypeId = 2
  AND rn <= 100
ORDER BY HotScore DESC
LIMIT 200;