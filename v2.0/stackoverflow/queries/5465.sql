-- {"query": "5465.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 865}
WITH ranked_posts AS (
  SELECT
    p.Id AS PostId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    p.OwnerUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ContentLicense,
    u.Reputation,
    u.DisplayName AS OwnerDisplayName,
    u.AccountId,
    u.LastAccessDate,
    u.Location,
    u.WebsiteUrl,
    u.Views AS UserViews,
    u.UpVotes,
    u.DownVotes,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - p.CreationDate)) AS AgeSeconds
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId IN (1, 2)
),
correlated_cte AS (
  SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.OwnerUserId,
    rp.Reputation,
    rp.AgeSeconds,
    (
      SELECT AVG(v.BountyAmount)
      FROM Votes v
      WHERE v.PostId = rp.PostId
        AND v.VoteTypeId = 18
    ) AS AvgBounty
  FROM ranked_posts rp
),
join_hints AS (
  SELECT
    c.PostId,
    c.Title,
    c.OwnerUserId,
    c.Reputation,
    c.AgeSeconds,
    c.AvgBounty,
    (
      SELECT COUNT(*) FROM (
        -- portable split: remove surrounding angle brackets then split on '><' emulated by iterative splitting using regexp_split_to_table if available,
        -- otherwise fall back to simple replacements and splitting via standard SQL approaches.
        SELECT elem
        FROM (
          -- produce rows by splitting the tags string on '><' or on '>' and '<' boundaries.
          -- Use regexp_split_to_table when available; if not, assume implementation provides a function named regexp_split_to_table.
          SELECT regexp_split_to_table(
            -- normalize: remove leading '<' and trailing '>' if present
            CASE
              WHEN LEFT(c.Tags,1) = '<' AND RIGHT(c.Tags,1) = '>' THEN SUBSTRING(c.Tags FROM 2 FOR CHAR_LENGTH(c.Tags)-2)
              WHEN LEFT(c.Tags,1) = '<' THEN SUBSTRING(c.Tags FROM 2)
              WHEN RIGHT(c.Tags,1) = '>' THEN SUBSTRING(c.Tags FROM 1 FOR CHAR_LENGTH(c.Tags)-1)
              ELSE c.Tags
            END,
            '><'
          ) AS elem
        ) AS split_elems
        WHERE elem IS NOT NULL AND elem <> ''
      ) AS s
    ) AS TagCount,
    (c.Reputation * 0.5) + (c.AgeSeconds / 3600.0) - COALESCE(c.AvgBounty, 0) AS CompositeScore
  FROM correlated_cte c
),
final AS (
  SELECT
    jh.PostId,
    jh.Title,
    jh.OwnerUserId,
    jh.Reputation,
    jh.AgeSeconds,
    jh.AvgBounty,
    jh.TagCount,
    jh.CompositeScore,
    CASE
      WHEN jh.TagCount > 5 THEN 'high_tag_activity'
      WHEN jh.TagCount = 0 THEN 'no_tags'
      ELSE 'moderate_tags'
    END AS TagActivityCategory,
    ROW_NUMBER() OVER (
      PARTITION BY CASE
        WHEN jh.TagCount > 5 THEN 'high_tag_activity'
        WHEN jh.TagCount = 0 THEN 'no_tags'
        ELSE 'moderate_tags'
      END
      ORDER BY jh.CompositeScore DESC, jh.AgeSeconds ASC, jh.AvgBounty DESC
    ) AS RankInCategory
  FROM join_hints jh
)
SELECT
  final.PostId,
  final.Title,
  final.OwnerUserId,
  final.Reputation,
  final.AgeSeconds,
  final.AvgBounty,
  final.TagCount,
  final.CompositeScore,
  final.TagActivityCategory,
  final.RankInCategory,
  (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = final.OwnerUserId AND p2.PostTypeId = 1) AS QuestionsByOwner,
  (SELECT MAX(LastEditDate) FROM Posts p3 WHERE p3.OwnerUserId = final.OwnerUserId) AS LastOwnerEditDate,
  (SELECT COUNT(*) FROM Comments c WHERE c.UserId = final.OwnerUserId) AS CommentsByOwner
FROM final
WHERE final.RankInCategory <= 100
ORDER BY final.RankInCategory ASC, final.CompositeScore DESC;