-- {"query": "5414.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 903}
WITH rapid_activity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.PostTypeId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.WebsiteUrl,
    t.Name AS PostTypeName,
    pc.Name AS CloseReasonName,
    vt.Name AS LastVoteType,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountTotal,
    (SELECT MAX(v2.CreationDate) FROM Votes v2 WHERE v2.PostId = p.Id) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN PostTypes t ON p.PostTypeId = t.Id
  LEFT JOIN PostHistory h ON h.PostId = p.Id
  LEFT JOIN CloseReasonTypes pc ON CAST(h.Comment AS varchar(100)) ILIKE '%' || CAST(pc.Id AS varchar)
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE p.LastActivityDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '90 days')
    AND (p.ViewCount > 0 OR p.Score <> 0)
),
enhanced AS (
  SELECT
    ra.*,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ra.OwnerUserId AND p2.CreationDate > ra.CreationDate) AS NewerPostsByOwner,
    (
      SELECT ARRAY_AGG(DISTINCT tg.TagName)
      FROM Posts p3
      JOIN LATERAL (
        SELECT regexp_replace(t, '^<|>$', '') AS tagname
        FROM regexp_split_to_table(p3.Tags, '><') AS t
      ) AS split_tags ON true
      JOIN Tags tg ON tg.TagName = split_tags.tagname
      WHERE p3.OwnerUserId = ra.OwnerUserId AND p3.Id <> ra.PostId
    ) AS OwnerTagBreadth,
    CASE
      WHEN ra.Score >= 20 THEN 'HighImpact'
      WHEN ra.Score >= 5 THEN 'Moderate'
      ELSE 'Low'
    END AS ImpactBand,
    CASE
      WHEN ra.ViewCount > 1000 THEN true
      ELSE false
    END AS IsPopular
  FROM rapid_activity ra
),
final AS (
  SELECT
    e.PostId,
    e.Title,
    e.CreationDate,
    e.LastActivityDate,
    e.OwnerUserId,
    e.Reputation,
    e.OwnerDisplayName,
    e.Score,
    e.ViewCount,
    e.Tags,
    e.PostTypeName,
    e.CloseReasonName,
    e.LastVoteType,
    e.CommentCountTotal,
    e.LastVoteDate,
    e.NewerPostsByOwner,
    e.OwnerTagBreadth,
    e.ImpactBand,
    e.IsPopular,
    ROW_NUMBER() OVER (
      PARTITION BY e.PostTypeName
      ORDER BY e.Score DESC, e.ViewCount DESC, e.LastActivityDate DESC
    ) AS rn_by_type,
    SUM(CASE WHEN e.ImpactBand = 'HighImpact' THEN 1 ELSE 0 END) OVER () AS HighImpactCount
  FROM enhanced e
)
SELECT
  PostId,
  Title,
  CreationDate,
  LastActivityDate,
  OwnerUserId,
  Reputation,
  OwnerDisplayName,
  Score,
  ViewCount,
  Tags,
  PostTypeName,
  CloseReasonName,
  LastVoteType,
  CommentCountTotal,
  LastVoteDate,
  NewerPostsByOwner,
  OwnerTagBreadth,
  ImpactBand,
  IsPopular,
  HighImpactCount,
  rn_by_type
FROM final
WHERE rn_by_type = 1
  AND IsPopular = true
  AND (OwnerTagBreadth IS NULL OR cardinality(OwnerTagBreadth) > 0)
ORDER BY PostTypeName, Score DESC, LastActivityDate DESC
LIMIT 100;