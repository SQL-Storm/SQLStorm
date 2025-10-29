-- {"query": "5562.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 699} 
WITH RecentHot AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Location,
    wt.Name AS WatchType
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT 1 AS dummy, 'hot-network' AS Name
  ) wt ON 1 = 1
  WHERE p.PostTypeId = 1 -- Questions
    AND p.LastActivityDate > cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
Correlation AS (
  SELECT
    r.PostId,
    r.Title,
    r.Tags,
    r.CreationDate,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.LastActivityDate,
    r.CommentCount,
    r.AnswerCount,
    r.FavoriteCount,
    r.ContentLicense,
    r.Reputation,
    r.DisplayName,
    r.Location,
    STRING_AGG(CASE WHEN v.VoteTypeId IN (2,3) THEN 'UP' ELSE NULL END, ',') FILTER (WHERE v.VoteTypeId IN (2,3)) AS UserVotes,
    COUNT(*) OVER (PARTITION BY r.PostId) AS VoteCount
  FROM RecentHot r
  LEFT JOIN Votes v ON v.PostId = r.PostId
  GROUP BY
    r.PostId, r.Title, r.Tags, r.CreationDate, r.Score, r.ViewCount,
    r.OwnerUserId, r.LastActivityDate, r.CommentCount, r.AnswerCount,
    r.FavoriteCount, r.ContentLicense, r.Reputation, r.DisplayName, r.Location
),
WindowAgg AS (
  SELECT
    c.*,
    ROW_NUMBER() OVER (
      PARTITION BY OwnerUserId
      ORDER BY LastActivityDate DESC, Score DESC
    ) AS rn_by_user
  FROM Correlation c
),
Combined AS (
  SELECT
    w.*,
    (SELECT SUM(BountyAmount) FROM Votes v WHERE v.PostId = w.PostId AND v.VoteTypeId = 8) AS BountySum,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = w.PostId) AS LinkCount,
    (SELECT STRING_AGG(pt.Name, '|') FROM PostLinks pl
       JOIN Posts p2 ON pl.RelatedPostId = p2.Id
       JOIN PostTypes pt ON p2.PostTypeId = pt.Id
     WHERE pl.PostId = w.PostId) AS LinkedTypes
  FROM WindowAgg w
)
SELECT
  PostId,
  Title,
  Tags,
  CreationDate,
  Score,
  ViewCount,
  OwnerUserId,
  LastActivityDate,
  CommentCount,
  AnswerCount,
  FavoriteCount,
  ContentLicense,
  Reputation,
  DisplayName,
  Location,
  UserVotes,
  VoteCount,
  BountySum,
  LinkCount,
  LinkedTypes
FROM Combined
WHERE rn_by_user = 1
ORDER BY LastActivityDate DESC, Score DESC
LIMIT 100;