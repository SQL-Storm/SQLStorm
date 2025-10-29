-- {"query": "5042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 997}
WITH
DailyUserActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    DATE_TRUNC('day', u.CreationDate) AS CreatedDay,
    SUM(CASE WHEN v.Id IS NOT NULL THEN 1 ELSE 0 END) AS VotesCast,
    SUM(CASE WHEN b.Id IS NOT NULL THEN 1 ELSE 0 END) AS BadgesEarned,
    SUM(CASE WHEN p.Id IS NOT NULL THEN 1 ELSE 0 END) AS PostsCreated,
    AVG(COALESCE(p.Score,0)) AS AvgPostScore
  FROM
    Users u
  LEFT JOIN
    Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN
    Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  LEFT JOIN
    Badges b ON b.UserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, DATE_TRUNC('day', u.CreationDate)
),
TopRelatedPosts AS (
  SELECT
    p1.Id AS PostId,
    p1.Title,
    COUNT(*) AS RelatedCount
  FROM
    Posts p1
  JOIN
    PostLinks pl ON pl.PostId = p1.Id
  JOIN
    Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE
    pl.LinkTypeId = 1
    AND p2.Id <> p1.Id
  GROUP BY
    p1.Id, p1.Title
  ORDER BY
    RelatedCount DESC
  FETCH FIRST 5 ROWS ONLY
),
RankedPostScores AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.Score,
    t.tag,
    ROW_NUMBER() OVER (
      PARTITION BY t.tag
      ORDER BY p.Score DESC NULLS LAST
    ) AS rn
  FROM
    Posts p
    CROSS JOIN LATERAL (
      /* Split tags like '<tag1><tag2>' into rows in a more portable way.
         Replace REGEXP_SPLIT_TO_TABLE with an equivalent function in target dialect if needed.
         The inner SELECT removes empty pieces that can arise from leading/trailing delimiters. */
      SELECT TRIM(tag) AS tag FROM (
        SELECT REGEXP_SPLIT_TO_TABLE(REPLACE(p.Tags, '>', '<'), '<') AS tag
      ) s WHERE TRIM(tag) <> ''
    ) t
  WHERE
    p.PostTypeId = 1
),
BenchmarkPosts AS (
  SELECT
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.CommentCount,
    CASE
      WHEN p.AcceptedAnswerId IS NULL THEN 'NoAccepted'
      ELSE 'HasAccepted'
    END AS HasAcceptedLabel,
    CASE
      WHEN p.LastActivityDate IS NULL THEN p.CreationDate
      ELSE p.LastActivityDate
    END AS ActivityDate,
    (COALESCE(p.ViewCount,0) * 2) + COALESCE(p.Score,0) AS WeightedMetric,
    CASE
      WHEN p.Tags IS NULL THEN NULL
      ELSE (
        /* produce an array-like representation; use string splitting function available in target dialect */
        REGEXP_SPLIT_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><')
      )
    END AS TagArray
  FROM
    Posts p
  LEFT JOIN
    Votes v ON v.PostId = p.Id
  LEFT JOIN
    PostLinks pl ON pl.PostId = p.Id
  WHERE
    p.PostTypeId IN (1,2)
    AND (p.Body IS NOT NULL OR p.Title IS NOT NULL)
    AND (
      p.LastActivityDate > p.CreationDate - INTERVAL '30' DAY
      OR p.LastActivityDate IS NULL
    )
),
FinalRow AS (
  SELECT
    bp.Id AS PostId,
    bp.Title,
    bp.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    bp.ViewCount,
    bp.Score,
    bp.CommentCount,
    bp.HasAcceptedLabel,
    bp.ActivityDate,
    bp.WeightedMetric,
    rp.RelatedCount,
    rt.rn
  FROM
    BenchmarkPosts bp
  LEFT JOIN
    Users u ON u.Id = bp.OwnerUserId
  LEFT JOIN
    TopRelatedPosts rp ON rp.PostId = bp.Id
  LEFT JOIN
    RankedPostScores rt ON rt.Id = bp.Id
  WHERE
    bp.WeightedMetric > (SELECT AVG(b2.WeightedMetric) FROM BenchmarkPosts b2)
  GROUP BY
    bp.Id, bp.Title, bp.OwnerUserId, u.DisplayName, bp.ViewCount, bp.Score, bp.CommentCount,
    bp.HasAcceptedLabel, bp.ActivityDate, bp.WeightedMetric, rp.RelatedCount, rt.rn
)
SELECT
  *
FROM
  FinalRow
ORDER BY
  PostId
FETCH FIRST 100 ROWS ONLY;