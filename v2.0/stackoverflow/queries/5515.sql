-- {"query": "5515.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 865}
WITH enriched AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName AS UserName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.AccountId,
    p.Id AS PostId,
    p.PostTypeId,
    p.Title,
    p.Body,
    p.Tags,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    p.LastActivityDate,
    p.AcceptedAnswerId,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    p.OwnerDisplayName,
    p.LastEditorUserId,
    p.LastEditDate,
    p.LastEditorDisplayName,
    p.ContentLicense,
    CASE
      WHEN p.Score > 10 AND p.ViewCount > 1000 THEN true
      ELSE false
    END AS HighlyVisible,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.UserId IS NOT NULL) AS CommentCountOnPost,
    ROW_NUMBER() OVER (
      PARTITION BY p.PostTypeId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS PostTypeRank
  FROM
    Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
),
tags_expanded AS (
  SELECT
    e.*,
    t.TagName AS PrimaryTag
  FROM enriched e
  LEFT JOIN LATERAL (
    SELECT unnest(string_to_array(substr(e.Tags, 2, length(e.Tags)-2), '><')) AS TagName
  ) t ON true
),
all_posts AS (
  SELECT
    te.*,
    (SELECT COUNT(*) FROM PostHistory ph
     WHERE ph.PostId = te.PostId AND ph.PostHistoryTypeId IN (5,6,10,16,24)) AS EditImpactCount,
    (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = te.PostId AND v.VoteTypeId = 8) AS BountyTotal
  FROM tags_expanded te
)
SELECT
  ap.PostId,
  ap.PostTypeId,
  (SELECT pt.Name FROM PostTypes pt WHERE pt.Id = ap.PostTypeId) AS PostTypeName,
  ap.Title,
  ap.OwnerDisplayName AS PostOwner,
  ap.UserName,
  ap.Reputation,
  ap.PostCreationDate,
  ap.LastActivityDate,
  ap.ViewCount,
  ap.Score,
  ap.CommentCount,
  ap.FavoriteCount,
  ap.PrimaryTag,
  (ap.Score * 1.5 + ap.ViewCount * 0.75 + COALESCE(ap.EditImpactCount,0) * 2.0 +
   COALESCE(ap.BountyTotal,0)) AS BenchmarkScore,
  CONCAT_WS(' | ', ap.Title, COALESCE(ap.OwnerDisplayName, ''), ap.PrimaryTag) AS TitleWithTag,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = ap.OwnerUserId AND p2.Id <> ap.PostId) AS OtherPostsByOwner,
  CASE
    WHEN ap.HighlyVisible = true THEN 'High visibility'
    ELSE 'Normal visibility'
  END AS VisibilityCategory,
  ap.PostTypeRank
FROM all_posts ap
WHERE
  ap.Score IS NOT NULL
  AND ap.ViewCount >= 0
  AND (ap.Tags IS NULL OR ap.PrimaryTag IS NOT NULL)
ORDER BY
  BenchmarkScore DESC,
  ap.PostCreationDate DESC
LIMIT 100;