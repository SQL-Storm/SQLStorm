-- {"query": "154.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 1212} 
WITH RankedPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
    COUNT(DISTINCT pl.RelatedPostId) AS RelatedCount,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.LastActivityDate DESC NULLS LAST
    ) AS rn
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY
    p.Id,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount
),
OwnerBadges AS (
  SELECT
    u.Id AS UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
)
SELECT
  rp.Id,
  rp.Title,
  rp.PostTypeId,
  rp.OwnerUserId,
  u.DisplayName,
  rp.CreationDate,
  rp.LastActivityDate,
  rp.Score,
  rp.ViewCount,
  rp.UpVotes,
  rp.DownVotes,
  rp.RelatedCount,
  ob.GoldBadges,
  ob.SilverBadges
FROM RankedPosts rp
JOIN Users u ON u.Id = rp.OwnerUserId
LEFT JOIN OwnerBadges ob ON ob.UserId = u.Id
WHERE rp.rn <= 100
  AND (rp.Score > 0 OR rp.UpVotes > 5)
ORDER BY rp.Score DESC NULLS LAST, rp.ViewCount DESC NULLS LAST, rp.LastActivityDate DESC NULLS LAST;