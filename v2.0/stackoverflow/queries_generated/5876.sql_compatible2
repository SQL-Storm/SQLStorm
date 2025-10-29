WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.Tags,
    p.ContentLicense
  FROM Posts p
  WHERE p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '30 days'
),
TopTags AS (
  SELECT
    tag AS TagName,
    SUM(p.Score) AS TagScore,
    COUNT(*) AS PostCount
  FROM (
    SELECT
      p.*,
      TRIM(BOTH '<>' FROM p.Tags) AS tags_trimmed
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.LastActivityDate >= CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '365 days'
  ) p
  CROSS JOIN LATERAL (
    WITH RECURSIVE splitter(tag, rest) AS (
      SELECT
        CASE WHEN pos = 0 THEN p.tags_trimmed ELSE substr(p.tags_trimmed, 1, pos-1) END AS tag,
        CASE WHEN pos = 0 THEN '' ELSE substr(p.tags_trimmed, pos+2) END AS rest
      FROM (
        SELECT p.tags_trimmed,
               (CASE WHEN p.tags_trimmed = '' THEN 0 ELSE POSITION('><' IN p.tags_trimmed) END) AS pos
      ) initial
      UNION ALL
      SELECT
        CASE WHEN POSITION('><' IN rest) = 0 THEN rest ELSE substr(rest, 1, POSITION('><' IN rest)-1) END AS tag,
        CASE WHEN POSITION('><' IN rest) = 0 THEN '' ELSE substr(rest, POSITION('><' IN rest)+2) END AS rest
      FROM splitter
      WHERE rest IS NOT NULL AND rest <> ''
    )
    SELECT tag FROM splitter WHERE tag IS NOT NULL AND tag <> ''
  ) tags(tag)
  GROUP BY tag
),
TagPointBoost AS (
  SELECT
    t.TagName,
    t.TagScore,
    t.PostCount,
    CASE
      WHEN t.PostCount > 50 THEN t.TagScore * 1.25
      WHEN t.PostCount > 20 THEN t.TagScore * 1.15
      ELSE t.TagScore * 1.05
    END AS BoostedScore
  FROM TopTags t
),
EnrichedPosts AS (
  SELECT
    rap.Id,
    rap.Title,
    rap.PostTypeId,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.OwnerUserId,
    rap.ViewCount,
    rap.Score,
    rap.AnswerCount,
    rap.CommentCount,
    rap.Tags,
    rap.ContentLicense,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    ROW_NUMBER() OVER (
      PARTITION BY rap.PostTypeId
      ORDER BY rap.LastActivityDate DESC, rap.Score DESC, rap.ViewCount DESC
    ) AS RN
  FROM RecentActivePosts rap
  LEFT JOIN Users u ON rap.OwnerUserId = u.Id
),
FilteredPosts AS (
  SELECT *
  FROM EnrichedPosts
  WHERE RN <= 100
),
CrossJoined AS (
  SELECT
    fp.Id,
    fp.Title,
    fp.PostTypeId,
    fp.CreationDate,
    fp.LastActivityDate,
    fp.OwnerUserId,
    fp.ViewCount,
    fp.Score,
    fp.AnswerCount,
    fp.CommentCount,
    fp.Tags,
    fp.ContentLicense,
    fp.OwnerReputation,
    fp.RN,
    tpb.TagName,
    tpb.BoostedScore
  FROM FilteredPosts fp
  LEFT JOIN TagPointBoost tpb
    ON POSITION('/' || tpb.TagName || '/' IN '/' || REPLACE(fp.Tags, '><', '/') || '/') > 0
),
ComplexCalculations AS (
  SELECT
    cp.Id,
    cp.Title,
    cp.PostTypeId,
    cp.CreationDate,
    cp.LastActivityDate,
    cp.OwnerUserId,
    cp.ViewCount,
    cp.Score,
    cp.AnswerCount,
    cp.CommentCount,
    cp.Tags,
    cp.ContentLicense,
    cp.OwnerReputation,
    cp.RN,
    cp.TagName,
    cp.BoostedScore,
    (cp.ViewCount * 2) AS ViewBoost,
    (cp.Score + COALESCE((SELECT AVG(p2.Score) FROM Posts p2 WHERE p2.PostTypeId = 1), 0)) AS RelativeScore,
    CASE
      WHEN cp.OwnerReputation > 10000 THEN 'Legendary'
      WHEN cp.OwnerReputation > 1000 THEN 'Expert'
      WHEN cp.OwnerReputation > 100 THEN 'Rising'
      ELSE 'New'
    END AS OwnerTier,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = cp.OwnerUserId AND p2.LastActivityDate > cp.LastActivityDate - INTERVAL '7 days') AS RecentOwnerPosts
  FROM CrossJoined cp
),
Aggregated AS (
  SELECT
    cp.Id,
    cp.Title,
    cp.PostTypeId,
    cp.CreationDate,
    cp.LastActivityDate,
    cp.OwnerUserId,
    cp.ViewCount,
    cp.Score,
    cp.AnswerCount,
    cp.CommentCount,
    cp.Tags,
    cp.ContentLicense,
    cp.OwnerReputation,
    cp.RN,
    cp.TagName,
    cp.BoostedScore,
    cp.ViewBoost,
    cp.RelativeScore,
    cp.OwnerTier,
    cp.RecentOwnerPosts
  FROM ComplexCalculations cp
  ORDER BY cp.LastActivityDate DESC, cp.RelativeScore DESC, cp.BoostedScore DESC
  LIMIT 100
),
FinalOutput AS (
  SELECT
    a.Id,
    a.Title,
    a.PostTypeId,
    a.CreationDate,
    a.LastActivityDate,
    a.OwnerUserId,
    a.OwnerTier,
    a.ViewCount,
    a.Score,
    a.AnswerCount,
    a.CommentCount,
    a.Tags,
    a.ContentLicense,
    a.OwnerReputation,
    a.RecentOwnerPosts,
    a.BoostedScore,
    a.RelativeScore
  FROM Aggregated a
)
SELECT
  *
FROM FinalOutput
ORDER BY LastActivityDate DESC, RelativeScore DESC, BoostedScore DESC;