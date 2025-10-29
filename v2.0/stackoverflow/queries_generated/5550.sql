-- {"query": "5550.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 885} 
WITH ranked_posts AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.LastActivityDate,
    p.PostTypeId,
    COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
    p.OwnerDisplayName,
    p.LastEditorDisplayName,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount + COALESCE(p.CommentCount,0) * 2 DESC,
        p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  LEFT JOIN Tags t ON t.ExcerptPostId = p.Id
  WHERE
    p.PostTypeId IN (1,2) -- Questions and Answers
    AND p.CreationDate >= NOW() - INTERVAL '2 years'
),
correlated_votes AS (
  SELECT
    rp.Id,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.Tags,
    rp.OwnerUserId,
    rp.LastActivityDate,
    rp.PostTypeId,
    rp.AcceptedAnswerId,
    rp.OwnerDisplayName,
    rp.LastEditorDisplayName,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    v.VoteTypeId,
    v.UserId AS VoterUserId,
    v.CreationDate AS VoteDate,
    v.BountyAmount
  FROM ranked_posts rp
  LEFT JOIN Votes v
    ON v.PostId = rp.Id
  WHERE v.VoteTypeId IN (2,3,10,11,12,14,15,16,6) OR v.VoteTypeId IS NULL
),
complex_calc AS (
  SELECT
    cp.Id,
    cp.Title,
    cp.CreationDate,
    cp.Score,
    cp.ViewCount,
    cp.Tags,
    cp.OwnerUserId,
    cp.LastActivityDate,
    cp.PostTypeId,
    cp.AcceptedAnswerId,
    cp.OwnerDisplayName,
    cp.LastEditorDisplayName,
    cp.CommentCount,
    cp.FavoriteCount,
    cp.ContentLicense,
    COUNT(*) OVER (PARTITION BY cp.OwnerUserId) AS PostsByUser,
    MAX(cp.Score) OVER (PARTITION BY cp.OwnerUserId) AS MaxScoreByUser,
    SUM(COALESCE(v.BountyAmount,0)) OVER (PARTITION BY cp.Id) AS TotalBountyOnPost
  FROM correlated_votes cp
  LEFT JOIN Votes v ON v.PostId = cp.Id
)
SELECT
  pc.Id,
  pc.Title,
  pc.CreationDate,
  pc.ViewCount,
  pc.Score,
  pc.TotalBountyOnPost,
  pc.PostTypeId,
  pc.OwnerDisplayName,
  pc.OwnerUserId,
  pc.LastActivityDate,
  pc.Tags,
  pc.CommentCount,
  pc.FavoriteCount,
  pc.ContentLicense,
  CASE
    WHEN pc.PostTypeId = 1 THEN 'Question'
    WHEN pc.PostTypeId = 2 THEN 'Answer'
    ELSE 'Other'
  END AS PostKind,
  ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS TagNames
FROM complex_calc pc
LEFT JOIN Tags t ON t.ExcerptPostId = pc.Id
GROUP BY
  pc.Id,
  pc.Title,
  pc.CreationDate,
  pc.ViewCount,
  pc.Score,
  pc.TotalBountyOnPost,
  pc.PostTypeId,
  pc.OwnerDisplayName,
  pc.OwnerUserId,
  pc.LastActivityDate,
  pc.Tags,
  pc.CommentCount,
  pc.FavoriteCount,
  pc.ContentLicense
HAVING
  pc.rn <= 5
ORDER BY
  pc.PostTypeId,
  pc.Score DESC,
  pc.TotalBountyOnPost DESC
LIMIT 100;