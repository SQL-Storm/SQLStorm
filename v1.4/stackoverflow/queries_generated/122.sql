-- {"query": "122.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1767} 
WITH
UserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = u.Id) AS PostCountByUser,
    (SELECT AVG(p.Score) FROM Posts p WHERE p.OwnerUserId = u.Id) AS AvgPostScoreByUser
  FROM Users u
),
PostStats AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    pt.Name AS PostTypeName,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    COUNT(v.Id) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(v.CreationDate) AS LastVoteDate,
    p.Tags
  FROM Posts p
  LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY
    p.Id, p.Title, pt.Name, p.OwnerUserId, p.OwnerDisplayName,
    p.Score, p.ViewCount, p.CreationDate, p.Tags
),
TaggedLike AS (
  SELECT p.*
  FROM PostStats p
  WHERE p.Tags LIKE '%<sql>%'
),
TopDiscussion AS (
  SELECT
    p.PostId,
    p.Title,
    p.PostTypeName,
    p.OwnerDisplayName AS Owner,
    p.Score,
    p.ViewCount,
    p.VoteCount,
    p.UpVotes,
    p.DownVotes,
    p.LastVoteDate,
    p.CreationDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeName
      ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.LastVoteDate DESC NULLS LAST
    ) AS rn
  FROM TaggedLike p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeName = 'Question'
    AND p.OwnerUserId IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = p.PostId
        AND pl.LinkTypeId = 1
    )
    AND EXISTS (
      SELECT 1
      FROM Tags t
      WHERE t.WikiPostId = NULL -- placeholder to involve another table in correlated subquery
        OR t.Id IS NOT NULL
    )
),
SecondaryFilter AS (
  SELECT
    p.PostId,
    p.Title,
    p.PostTypeName,
    p.Owner,
    p.Score,
    p.ViewCount,
    p.VoteCount,
    p.UpVotes,
    p.DownVotes,
    p.LastVoteDate,
    p.CreationDate,
    p.rn
  FROM TopDiscussion p
  WHERE p.rn <= 50
)
SELECT
  SF.PostId,
  SF.Title,
  SF.PostTypeName,
  SF.Owner,
  SF.Score,
  SF.ViewCount,
  SF.VoteCount,
  SF.UpVotes,
  SF.DownVotes,
  SF.LastVoteDate,
  SF.CreationDate
FROM SecondaryFilter SF
ORDER BY SF.rn
UNION ALL
SELECT
  p.PostId,
  p.Title,
  p.PostTypeName,
  p.Owner,
  p.Score,
  p.ViewCount,
  p.VoteCount,
  p.UpVotes,
  p.DownVotes,
  p.LastVoteDate,
  p.CreationDate
FROM PostStats p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.OwnerUserId IS NULL
ORDER BY CreationDate DESC
LIMIT 100;