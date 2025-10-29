-- {"query": "5797.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 917} 
WITH tagged_activity AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.CreationDate AS PostCreationDate,
    p.OwnerUserId,
    p.Title,
    p.Tags,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.AcceptedAnswerId,
    pv.CreationDate AS VoteDate,
    v.VoteTypeId,
    u.Reputation,
    u.DisplayName AS UserName,
    b.Name AS BadgeName
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN (SELECT PostId, MIN(CreationDate) AS CreationDate FROM Votes GROUP BY PostId) pv ON pv.PostId = p.Id
  WHERE p.PostTypeId IN (1,2)
),
recent_tags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
),
windowed AS (
  SELECT
    a.PostId,
    a.PostTypeId,
    a.PostCreationDate,
    a.OwnerUserId,
    a.Title,
    a.Tags,
    a.Score,
    a.ViewCount,
    a.LastActivityDate,
    a.LastEditDate,
    a.AcceptedAnswerId,
    ROW_NUMBER() OVER (
      PARTITION BY a.PostTypeId
      ORDER BY a.Score DESC, a.ViewCount DESC, a.LastActivityDate DESC
    ) AS rn
  FROM tagged_activity a
  WHERE a.PostTypeId = 1
),
correlated AS (
  SELECT
    w1.PostId,
    w1.Title,
    w1.Score,
    w1.ViewCount,
    w1.LastActivityDate,
    w1.OwnerUserId,
    w1.PostTypeId,
    w1.rn,
    (SELECT AVG(Score) FROM windowed w2 WHERE w2.PostTypeId = w1.PostTypeId) AS AvgScoreByType,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = w1.PostId AND v.VoteTypeId = 2) AS UpVotesOnPost,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = w1.PostId AND v.VoteTypeId = 3) AS DownVotesOnPost,
    (SELECT MAX(CreationDate) FROM Votes v WHERE v.PostId = w1.PostId) AS LastVoteDate
  FROM windowed w1
  WHERE w1.rn = 1
),
extra AS (
  SELECT
    c.PostId,
    c.Title,
    c.Score,
    c.ViewCount,
    c.LastActivityDate,
    c.OwnerUserId,
    c.PostTypeId,
    c.AvgScoreByType,
    c.UpVotesOnPost,
    c.DownVotesOnPost,
    c.LastVoteDate,
    (CASE
      WHEN c.LastActivityDate > c.LastVoteDate THEN 'Active'
      ELSE 'Stagnant'
    END) AS ActivityStatus,
    (SELECT STRING_AGG(b.Name, ',') FROM Badges b WHERE b.UserId = c.OwnerUserId) AS BadgesOnOwner
  FROM correlated c
)
SELECT
  e.PostId,
  e.Title,
  e.Score,
  e.ViewCount,
  e.LastActivityDate,
  e.OwnerUserId,
  e.PostTypeId,
  e.AvgScoreByType,
  e.UpVotesOnPost,
  e.DownVotesOnPost,
  e.LastVoteDate,
  e.ActivityStatus,
  e.BadgesOnOwner,
  (SELECT COALESCE(MIN(CreationDate), TIMESTAMP '1900-01-01') FROM Votes v WHERE v.PostId = e.PostId) AS FirstVoteDate,
  (SELECT COUNT(*) FROM Comments cm WHERE cm.PostId = e.PostId) AS CommentCount,
  (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = e.PostId) AS LinkCount
FROM extra e
WHERE e.ActivityStatus = 'Active'
  AND (e.ViewCount > 1000 OR e.AvgScoreByType > 0)
ORDER BY e.LastActivityDate DESC, e.Score DESC
LIMIT 100;