-- {"query": "4060.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1291} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate AS EditDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) AND ph.UserId IS NOT NULL
  ),
  LatestPostInfo AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate AS PostCreationDate,
      p.LastEditDate,
      p.Score AS PostScore,
      COALESCE(u.DisplayName, 'Deleted User') AS OwnerDisplayName,
      COALESCE(
        (
          SELECT
            COUNT(*)
          FROM
            Comments AS c
          WHERE
            c.PostId = p.Id AND c.Score > 0
        ),
        0
      ) AS PositiveCommentCount
    FROM
      Posts AS p
      LEFT JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 -- Questions only
  ),
  UserPostActivity AS (
    SELECT
      lp.PostId,
      lp.OwnerUserId,
      lp.PostCreationDate,
      lp.LastEditDate,
      lp.PostScore,
      lp.OwnerDisplayName,
      lp.PositiveCommentCount,
      rpe.UserId AS LastEditorId,
      rpe.EditDate AS LastEditTimestamp,
      DATEDIFF(
        day,
        lp.PostCreationDate,
        COALESCE(lp.LastEditDate, lp.PostCreationDate)
      ) AS DaysSinceCreationOrLastEdit,
      CASE WHEN lp.LastEditDate IS NOT NULL THEN 1 ELSE 0 END AS WasEdited
    FROM
      LatestPostInfo AS lp
      LEFT JOIN RankedPostEdits AS rpe
      ON lp.PostId = rpe.PostId AND rpe.rn = 1
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      COALESCE(
        (
          SELECT
            SUM(p.Score)
          FROM
            Posts AS p
            INNER JOIN Tags AS t_inner
            ON p.Id = t_inner.WikiPostId -- Approximation for tag relevance
          WHERE
            t_inner.TagName = t.TagName
        ),
        0
      ) AS TagScoreSum
    FROM
      Tags AS t
    WHERE
      t.IsModeratorOnly = 0
  )
SELECT
  upa.PostId,
  upa.OwnerDisplayName,
  upa.PostScore,
  upa.PositiveCommentCount,
  upa.DaysSinceCreationOrLastEdit,
  upa.WasEdited,
  tp.TagName,
  tp.TagCount,
  tp.TagScoreSum,
  CASE
    WHEN upa.PostScore > 1000 AND upa.PositiveCommentCount > 50 THEN 'High Engagement'
    WHEN upa.DaysSinceCreationOrLastEdit > 365 THEN 'Aging'
    WHEN upa.WasEdited = 1 AND upa.LastEditTimestamp < DATEADD(day, -30, GETDATE()) THEN 'Stale Edit'
    ELSE 'Standard'
  END AS PostCategory,
  COALESCE(
    (
      SELECT
        COUNT(DISTINCT ph_late.UserId)
      FROM
        PostHistory AS ph_late
      WHERE
        ph_late.PostId = upa.PostId
        AND ph_late.CreationDate > DATEADD(day, -7, upa.PostCreationDate) -- Last 7 days
        AND ph_late.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Moderation actions
    ),
    0
  ) AS RecentModerationCount,
  CASE
    WHEN LENGTH(upa.OwnerDisplayName) > 20 THEN SUBSTRING(upa.OwnerDisplayName, 1, 17) || '...'
    ELSE upa.OwnerDisplayName
  END AS TruncatedOwnerName,
  CASE
    WHEN tp.TagCount > 10000 THEN 'Very Popular'
    WHEN tp.TagCount > 1000 THEN 'Popular'
    ELSE 'Less Common'
  END AS TagPopularityLevel,
  UPPER(tp.TagName) AS UppercaseTagName
FROM
  UserPostActivity AS upa
  LEFT OUTER JOIN Posts AS p_tags
  ON upa.PostId = p_tags.Id
  LEFT OUTER JOIN LATERAL (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      t.TagScoreSum
    FROM
      TagPopularity AS t
    WHERE
      t.TagName IN (
        SELECT
          TRIM(value)
        FROM
          STRING_SPLIT(REPLACE(REPLACE(p_tags.Tags, '<', ''), '>', ''), '')
      )
    ORDER BY
      t.TagCount DESC
    LIMIT 1
  ) AS tp
ON TRUE
WHERE
  upa.PostScore >= 0 -- Only consider posts with non-negative scores
  AND tp.TagName IS NOT NULL -- Ensure the post has at least one tag
  AND tp.TagCount > 10 -- Filter out very niche tags
ORDER BY
  upa.PostScore DESC,
  tp.TagCount DESC
LIMIT 100;
