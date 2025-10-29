-- {"query": "4376.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1071} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.PostHistoryTypeId,
      ph.CreationDate,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
  ),
  UserContribution AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      AVG(p.Score) FILTER (
        WHERE
          p.Score IS NOT NULL
      ) AS AvgPostScore
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  TagPopularity AS (
    SELECT
      t.TagName,
      t.Count AS TagCount,
      (
        SELECT
          COUNT(*)
        FROM Posts AS p
        WHERE
          p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
      ) AS TaggedQuestionCount
    FROM Tags AS t
    ORDER BY
      t.Count DESC
    LIMIT 10
  ),
  HighActivityPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.CreationDate,
      p.OwnerUserId,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.PostId = p.Id AND c.Score > 5
      ) AS HighScoringCommentCount,
      p.Score AS PostScore
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 /* Questions */ AND p.CreationDate >= '2023-01-01' AND p.ViewCount > 1000
  )
SELECT
  hap.PostId,
  hap.Title,
  hap.CreationDate AS QuestionCreationDate,
  uc.DisplayName AS OwnerDisplayName,
  hap.PostScore,
  hap.AnswerCount,
  hap.CommentCount,
  hap.FavoriteCount,
  hap.HighScoringCommentCount,
  COALESCE(rpe.PostHistoryTypeId, 0) AS LastEditType,
  rpe.CreationDate AS LastEditDate,
  tp.TagName,
  tp.TagCount AS GlobalTagCount,
  tp.TaggedQuestionCount,
  CASE
    WHEN uc.AvgPostScore > 50 THEN 'High Performer'
    WHEN uc.AvgPostScore > 20 THEN 'Medium Performer'
    ELSE 'Standard Performer'
  END AS UserPerformanceCategory,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM Votes AS v
      WHERE
        v.PostId = hap.PostId AND v.VoteTypeId = 2 /* UpMod */ AND v.UserId = hap.OwnerUserId
    ) THEN 'Owner Upvoted'
    ELSE 'Owner Did Not Upvote'
  END AS OwnerUpvoteStatus,
  CASE
    WHEN hap.OwnerUserId IS NULL THEN 'Community Owned'
    ELSE 'User Owned'
  END AS OwnershipStatus,
  'BenchmarkQuery' AS QueryOrigin
FROM HighActivityPosts AS hap
LEFT JOIN UserContribution AS uc
  ON hap.OwnerUserId = uc.UserId
LEFT JOIN RankedPostEdits AS rpe
  ON hap.PostId = rpe.PostId AND rpe.rn = 1
LEFT JOIN (
  SELECT DISTINCT
    hap_inner.PostId,
    tp_inner.TagName
  FROM HighActivityPosts AS hap_inner
  CROSS JOIN TagPopularity AS tp_inner
  WHERE
    hap_inner.Title LIKE '%' || tp_inner.TagName || '%' OR hap_inner.Title LIKE '%' || LOWER(tp_inner.TagName) || '%'
) AS tp
  ON hap.PostId = tp.PostId
WHERE
  uc.BadgeCount > 10
  AND hap.FavoriteCount > 5
  AND (
    hap.CommentCount > 5 OR hap.AnswerCount > 3
  )
ORDER BY
  hap.FavoriteCount DESC,
  hap.PostScore DESC;
