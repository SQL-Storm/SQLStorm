WITH ranked_questions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Tags,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    p.OwnerUserId,
    u.Reputation,
    u.DisplayName AS OwnerName,
    ROW_NUMBER() OVER (
      PARTITION BY p.OwnerUserId
      ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate ASC
    ) AS rn_by_author
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
recent_activity AS (
  SELECT
    rp.Id AS PostId,
    rp.OwnerUserId,
    rp.Title,
    rp.Tags,
    rp.CreationDate,
    rp.ViewCount,
    rp.Score,
    rp.CommentCount,
    u2.Reputation AS OwnerReputation,
    r_rank.rank AS recent_rank,
    COUNT(v.Id) AS total_votes,
    MAX(v.CreationDate) AS last_vote_date
  FROM Posts rp
  JOIN Votes v ON v.PostId = rp.Id
  LEFT JOIN Users u2 ON rp.OwnerUserId = u2.Id
  LEFT JOIN (
    SELECT p.OwnerUserId, ROW_NUMBER() OVER (ORDER BY MAX(p.LastActivityDate) DESC) AS rank
    FROM Posts p
    GROUP BY p.OwnerUserId
  ) r_rank ON r_rank.OwnerUserId = rp.OwnerUserId
  WHERE rp.PostTypeId = 1
  GROUP BY rp.Id, rp.OwnerUserId, rp.Title, rp.Tags, rp.CreationDate, rp.ViewCount, rp.Score, rp.CommentCount, u2.Reputation, r_rank.rank
),
complex_derived AS (
  SELECT
    ra.PostId,
    ra.OwnerUserId,
    ra.Title,
    ra.Tags,
    ra.CreationDate,
    ra.ViewCount,
    ra.Score,
    ra.CommentCount,
    ra.OwnerReputation,
    CASE
      WHEN ra.total_votes > 50 THEN 'High Engagement'
      WHEN ra.total_votes BETWEEN 20 AND 50 THEN 'Medium Engagement'
      ELSE 'Low Engagement'
    END AS EngagementBand,
    CASE
      WHEN ra.Tags IS NOT NULL THEN
        (
          SELECT STRING_AGG(tg.TagName, ',')
          FROM (
            SELECT TRIM(tg_raw) AS tg_raw
            FROM UNNEST(STRING_TO_ARRAY(ra.Tags, '<>')) AS t(tg_raw)
          ) split_tags
          LEFT JOIN Tags tg ON LOWER(split_tags.tg_raw) = LOWER(tg.TagName)
          WHERE tg.TagName IS NOT NULL
        )
      ELSE NULL
    END AS TagList,
    ra.total_votes
  FROM recent_activity ra
)
SELECT
  c.PostId,
  c.Title,
  c.Tags,
  c.CreationDate,
  c.ViewCount,
  c.Score,
  c.CommentCount,
  /* OwnerName was used in earlier CTEs but not carried through; use NULL if unavailable */
  NULL AS OwnerName,
  c.OwnerReputation,
  c.EngagementBand,
  c.TagList,
  c.total_votes
FROM complex_derived c
LEFT JOIN PostLinks pl ON pl.PostId = c.PostId
LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
WHERE
  c.EngagementBand <> 'Low Engagement'
  OR c.TagList IS NOT NULL
ORDER BY c.EngagementBand DESC, c.total_votes DESC
LIMIT 200;