WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Body,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.CommentCount,
    p.AnswerCount,
    p.LastActivityDate,
    p.LastEditDate,
    p.PostTypeId,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    u.CreationDate AS OwnerCreationDate,
    u.LastAccessDate AS OwnerLastAccessDate,
    COALESCE(b.Class, 3) AS BadgeClass,
    b.Date AS BadgeDate,
    b.Name AS BadgeName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC
    ) AS rn
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
    AND p.ClosedDate IS NULL
    AND p.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '365 days'
),
Aggregated AS (
  SELECT
    rp.OwnerUserId,
    rp.OwnerDisplayName,
    rp.Reputation,
    COUNT(*) AS question_count,
    SUM(rp.Score) AS total_score,
    SUM(rp.ViewCount) AS total_views,
    AVG(rp.CommentCount) AS avg_comments,
    MAX(rp.LastActivityDate) AS last_active,
    MAX(rp.BadgeDate) AS last_badge_date,
    STRING_AGG(DISTINCT rp.Tags, ',') AS combined_tags
  FROM RankedPosts rp
  WHERE rp.rn = 1 -- most recent by owner in each partition
  GROUP BY rp.OwnerUserId, rp.OwnerDisplayName, rp.Reputation
),
TopTags AS (
  -- split tags by comma into rows in a dialect-neutral way using a recursive CTE
  SELECT tag AS TagName
  FROM (
    SELECT p.Id, p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) src,
  LATERAL (
    SELECT TRIM(value) AS tag
    FROM (
      SELECT regexp_split_to_table(src.Tags, ',') AS value
    ) s
  ) split
  GROUP BY tag
  ORDER BY COUNT(*) DESC
  LIMIT 10
),
ContextualActivity AS (
  SELECT
    v.PostId,
    v.VoteTypeId,
    v.UserId,
    v.CreationDate,
    v.BountyAmount,
    CASE
      WHEN vt.Name ILIKE '%Up%' THEN 'positive'
      WHEN vt.Name ILIKE '%Down%' THEN 'negative'
      WHEN vt.Name ILIKE '%Close%' THEN 'moderation'
      ELSE 'other'
    END AS activity_context
  FROM Votes v
  JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  WHERE v.CreationDate >= CAST('2024-10-01' AS date) - INTERVAL '30 days'
),
CrossJoinSample AS (
  SELECT
    a.OwnerUserId,
    a.OwnerDisplayName,
    a.total_score,
    a.total_views,
    a.combined_tags,
    a.last_active,
    t.TagName
  FROM Aggregated a
  CROSS JOIN TopTags t
)
SELECT
  c.OwnerUserId,
  c.OwnerDisplayName,
  c.total_score,
  c.total_views,
  c.combined_tags,
  c.last_active,
  c.TagName AS most_frequent_tag,
  (SELECT COUNT(*) FROM ContextualActivity ca WHERE ca.UserId = c.OwnerUserId) AS recent_actions_count,
  (SELECT AVG(v.BountyAmount)
   FROM ContextualActivity ca
   JOIN Votes v ON ca.PostId = v.PostId
   WHERE ca.UserId = c.OwnerUserId AND v.BountyAmount IS NOT NULL) AS avg_bounty,
  (SELECT COUNT(*) FROM ContextualActivity ca WHERE ca.UserId = c.OwnerUserId AND ca.activity_context = 'positive') AS positive_votes_last_month
FROM CrossJoinSample c
ORDER BY c.total_score DESC, c.total_views DESC
LIMIT 100;