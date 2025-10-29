-- {"query": "5238.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 959} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.Body,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.LastActivityDate DESC,
        p.CreationDate ASC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
Agg AS (
  SELECT
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.Body,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    MAX(CASE WHEN v.VoteTypeId = 10 THEN 1 ELSE 0 END) AS HasDeletionVote,
    COUNT(DISTINCT c.Id) AS CommentCountDistinct
  FROM RankedPosts rp
  LEFT JOIN Votes v ON v.PostId = rp.Id
  LEFT JOIN Comments c ON c.PostId = rp.Id
  WHERE rp.rn <= 5  -- keep top 5 by the ranking per post type
  GROUP BY
    rp.Id,
    rp.PostTypeId,
    rp.Title,
    rp.CreationDate,
    rp.LastActivityDate,
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.Body,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense
),
WindowCalc AS (
  SELECT
    a.*,
    LEAD(a.LastActivityDate) OVER (PARTITION BY a.PostTypeId ORDER BY a.LastActivityDate) AS NextActivityDate,
    LAG(a.LastActivityDate) OVER (PARTITION BY a.PostTypeId ORDER BY a.LastActivityDate) AS PrevActivityDate,
    SUM(a.UpVotes) OVER (PARTITION BY a.PostTypeId) AS TotalUpVotesInType,
    SUM(a.DownVotes) OVER (PARTITION BY a.PostTypeId) AS TotalDownVotesInType
  FROM Agg a
)
SELECT
  wc.Id AS PostId,
  wc.PostTypeId,
  CASE
    WHEN wc.PostTypeId = 1 THEN CONCAT('[Question] ', wc.Title)
    WHEN wc.PostTypeId = 2 THEN CONCAT('[Answer] ', wc.Title)
    ELSE wc.Title
  END AS TitleWithType,
  wc.OwnerDisplayName,
  wc.Reputation,
  wc.CreationDate,
  wc.LastActivityDate,
  wc.ViewCount,
  wc.Score,
  wc.UpVotes,
  wc.DownVotes,
  wc.CommentCountDistinct AS Comments,
  wc.Tags,
  wc.Body,
  wc.AcceptedAnswerId,
  wc.ParentId,
  wc.NextActivityDate,
  wc.PrevActivityDate,
  wc.TotalUpVotesInType,
  wc.TotalDownVotesInType,
  wc.ContentLicense
FROM WindowCalc wc
LEFT JOIN PostLinks pl ON pl.PostId = wc.Id
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE
  (wc.TotalUpVotesInType - wc.TotalDownVotesInType) > 5
  OR wc.ViewCount > 1000
  OR wc.CommentCountDistinct > 10
ORDER BY
  wc.LastActivityDate DESC,
  wc.Score DESC
LIMIT 100;