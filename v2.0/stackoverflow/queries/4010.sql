-- {"query": "4010.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1023}
WITH RankedPosts AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.OwnerUserId,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate,
    p.ClosedDate,
    ROW_NUMBER() OVER (ORDER BY p.ViewCount DESC, p.Score DESC) AS RowNum
  FROM Posts p
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  WHERE
    p.PostTypeId = 1 -- Questions
),
TagContribution AS (
  SELECT
    p.Id AS PostId,
    t.TagName,
    COUNT(ph.Id) AS HistoryCount,
    SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits
  FROM Posts p
  JOIN PostHistory ph
    ON p.Id = ph.PostId
  JOIN Tags t
    ON t.TagName = ANY(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))
  WHERE
    p.PostTypeId = 1 AND ph.PostHistoryTypeId IN (3, 6, 9) -- Initial Tags, Edit Tags, Rollback Tags
  GROUP BY
    p.Id,
    t.TagName
),
UserPostActivity AS (
  SELECT
    p.OwnerUserId,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(p.Score) AS TotalScore,
    SUM(p.ViewCount) AS TotalViews,
    AVG(CAST(p.FavoriteCount AS NUMERIC)) AS AvgFavorites,
    MAX(p.CreationDate) AS LastPostDate
  FROM Posts p
  WHERE
    p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
  GROUP BY
    p.OwnerUserId
)
SELECT
  rp.PostId,
  rp.Title,
  rp.Score,
  rp.ViewCount,
  rp.AnswerCount,
  rp.CommentCount,
  rp.FavoriteCount,
  rp.OwnerDisplayName,
  rp.CreationDate,
  COALESCE(tca.TagName, 'No Tags') AS PrimaryTag,
  COALESCE(tca.HistoryCount, 0) AS TagHistoryCount,
  COALESCE(tca.TagEdits, 0) AS TagEditCount,
  upa.TotalPosts AS OwnerTotalPosts,
  upa.TotalScore AS OwnerTotalScore,
  upa.TotalViews AS OwnerTotalViews,
  upa.AvgFavorites AS OwnerAvgFavorites,
  upa.LastPostDate AS OwnerLastPostDate,
  CASE
    WHEN rp.ViewCount > 1000000 THEN 'High Traffic'
    WHEN rp.Score > 1000 AND rp.AnswerCount > 100 THEN 'Highly Rated & Answered'
    WHEN rp.FavoriteCount > 500 THEN 'Very Popular'
    ELSE 'Standard'
  END AS PerformanceCategory,
  CASE
    WHEN EXISTS (
      SELECT 1
      FROM PostLinks pl
      WHERE pl.PostId = rp.PostId AND pl.LinkTypeId = 3 -- Duplicate Link
    ) THEN 'Is Duplicate'
    ELSE 'Not Marked as Duplicate'
  END AS DuplicateStatus,
  CASE
    WHEN rp.ClosedDate IS NOT NULL THEN 'Closed'
    ELSE 'Open'
  END AS PostStatus,
  CASE
    WHEN (
      SELECT COUNT(*)
      FROM Comments c
      WHERE c.PostId = rp.PostId AND c.UserId IS NULL
    ) > 0 THEN 'Has Community Comments'
    ELSE 'No Community Comments'
  END AS CommunityCommentPresence
FROM RankedPosts rp
LEFT JOIN (
  SELECT
    PostId,
    TagName,
    HistoryCount,
    TagEdits,
    ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY HistoryCount DESC) AS rn
  FROM TagContribution
) tca
  ON rp.PostId = tca.PostId AND tca.rn = 1
LEFT JOIN UserPostActivity upa
  ON rp.OwnerUserId = upa.OwnerUserId
WHERE
  rp.RowNum <= 1000 -- Limit to top 1000 posts by view count and score
ORDER BY
  rp.RowNum;