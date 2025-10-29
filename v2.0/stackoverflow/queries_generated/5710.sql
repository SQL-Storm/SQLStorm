-- {"query": "5710.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 898} 
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.LastActivityDate,
    p.Tags,
    p.Body,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName,
    u.Id AS UserId,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY
        p.Score DESC,
        p.ViewCount DESC,
        p.CreationDate ASC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.PostTypeId IN (1,2)
),
complex_metrics AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.CreationDate,
    rp.Score,
    rp.ViewCount,
    rp.OwnerUserId,
    rp.DisplayName,
    rp.Reputation,
    rp.Tags,
    rp.Body,
    rp.AcceptedAnswerId,
    rp.ParentId,
    rp.CommentCount,
    rp.FavoriteCount,
    rp.ContentLicense,
    -- window function: running sum of score by tag (simulated via Tags field parsing)
    SUM(CASE WHEN t.tag = ANY (string_to_array(rp.Tags, '>_<')) THEN 1 ELSE 0 END) OVER (PARTITION BY rp.PostId) AS tag_group_score
  FROM ranked_posts rp
  CROSS APPLY (
    SELECT unnest(string_to_array(
      regexp_replace(rp.Tags, '^\\(|\\)$', '', 'g'), '><') AS tag
  ) t
  WHERE rp.PostTypeId = 1
),
corr AS (
  SELECT
    cm.PostId,
    cm.Title,
    cm.CreationDate,
    cm.Score,
    cm.ViewCount,
    cm.OwnerUserId,
    cm.DisplayName,
    cm.Reputation,
    cm.Tags,
    cm.Body,
    cm.AcceptedAnswerId,
    cm.ParentId,
    cm.CommentCount,
    cm.FavoriteCount,
    cm.ContentLicense,
    cm.tag_group_score,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cm.PostId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = cm.PostId AND v.VoteTypeId = 3) AS Downvotes,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = cm.PostId) AS CommentCountTotal
  FROM complex_metrics cm
),
latest_activity AS (
  SELECT
    c.PostId,
    MAX(c.CreationDate) AS LastUserInteraction
  FROM corr c
  LEFT JOIN Comments com ON com.PostId = c.PostId
  GROUP BY c.PostId
),
link_summary AS (
  SELECT
    l.PostId,
    COUNT(*) FILTER (WHERE lt.Name ILIKE '%duplicate%') AS DupLinkCount,
    COUNT(*) AS TotalLinks
  FROM PostLinks l
  JOIN LinkTypes lt ON l.LinkTypeId = lt.Id
  GROUP BY l.PostId
)
SELECT
  c.PostId,
  c.Title,
  c.CreationDate,
  c.Score,
  c.ViewCount,
  c.OwnerUserId AS UserId,
  c.DisplayName,
  c.Reputation,
  c.Tags,
  c.Body,
  c.AcceptedAnswerId,
  c.ParentId,
  c.CommentCount,
  c.FavoriteCount,
  c.ContentLicense,
  c.Upvotes,
  c.Downvotes,
  c.CommentCountTotal,
  la.LastUserInteraction,
  ls.DupLinkCount,
  ls.TotalLinks,
  CASE
    WHEN c.Score > 50 THEN 'Hot'
    WHEN c.ViewsCount > 10000 THEN 'Popular'
    ELSE 'Normal'
  END AS ActivityLabel
FROM corr c
LEFT JOIN latest_activity la ON la.PostId = c.PostId
LEFT JOIN link_summary ls ON ls.PostId = c.PostId
ORDER BY c.Score DESC NULLS LAST, c.ViewCount DESC;