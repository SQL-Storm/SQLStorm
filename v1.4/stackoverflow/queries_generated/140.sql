-- {"query": "140.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1395} 
WITH 
RecentQuestions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.Tags,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    u.Reputation,
    u.DisplayName AS OwnerName,
    p.PostTypeId
  FROM Posts p
  JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate > DATEADD(year, -2, GETDATE())
),
UpDown AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 6 THEN 1 ELSE 0 END) AS CloseVotes
  FROM Votes v
  GROUP BY v.PostId
),
LinkStats AS (
  SELECT
    pl.PostId,
    COUNT(*) AS LinkCount,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM PostLinks pl
  WHERE pl.LinkTypeId IN (1, 3)
  GROUP BY pl.PostId
),
CommentCount AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
TagInfo AS (
  SELECT
    t.Id,
    t.TagName,
    t.Count
  FROM Tags t
  WHERE t.IsModeratorOnly = 0
)
SELECT TOP (100)
  rq.Id,
  rq.Title,
  rq.CreationDate,
  rq.LastActivityDate,
  rq.Tags,
  rq.ViewCount,
  rq.Score,
  rq.Reputation AS OwnerReputation,
  rq.OwnerName,
  COALESCE(ud.UpVotes, 0) AS UpVotes,
  COALESCE(ud.DownVotes, 0) AS DownVotes,
  COALESCE(ud.CloseVotes, 0) AS CloseVotes,
  COALESCE(ls.LinkCount, 0) AS LinkCount,
  COALESCE(cc.CommentCount, 0) AS CommentCount,
  (COALESCE(ud.UpVotes,0) - COALESCE(ud.DownVotes,0)) AS NetVotes,
  (SELECT STRING_AGG(t.TagName, ',') WITHIN GROUP (ORDER BY t.TagName)
     FROM Tags t
     WHERE t.Id IN (
       SELECT CAST(value AS int) FROM STRING_SPLIT(REPLACE(rq.Tags, '><', ','), ',')
     )
  ) AS TagSnapshot
FROM RecentQuestions rq
LEFT JOIN UpDown ud ON ud.PostId = rq.Id
LEFT JOIN LinkStats ls ON ls.PostId = rq.Id
LEFT JOIN CommentCount cc ON cc.PostId = rq.Id
ORDER BY NetVotes DESC, rq.LastActivityDate DESC;