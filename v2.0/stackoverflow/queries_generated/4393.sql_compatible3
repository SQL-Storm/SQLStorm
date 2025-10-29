WITH
  RankedPosts AS (
    SELECT
      p.Id AS PostId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.CommentCount,
      p.FavoriteCount,
      p.ViewCount,
      pt.Name AS PostTypeName,
      ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS rn,
      p.PostTypeId,
      p.LastEditDate,
      p.Tags
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
    WHERE
      p.Score > 0 AND p.OwnerUserId IS NOT NULL
  ),
  UserPostStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(p.Id) AS TotalPosts,
      SUM(p.Score) AS TotalScore,
      AVG(CAST(p.AnswerCount AS DECIMAL(10, 2))) AS AvgAnswerCount,
      MAX(p.CreationDate) AS LastPostDate,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title AS QuestionTitle,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.CreationDate AS QuestionCreationDate,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.AnswerCount AS QuestionAnswerCount,
      q.FavoriteCount AS QuestionFavoriteCount,
      a.Id AS AnswerId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      u_q.DisplayName AS QuestionOwnerDisplayName,
      u_a.DisplayName AS AnswerOwnerDisplayName,
      CASE
        WHEN q.AcceptedAnswerId = a.Id THEN 'Yes'
        ELSE 'No'
      END AS IsAcceptedAnswer,
      ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank
    FROM
      Posts q
      JOIN Posts a
        ON q.Id = a.ParentId
      JOIN Users u_q
        ON q.OwnerUserId = u_q.Id
      JOIN Users u_a
        ON a.OwnerUserId = u_a.Id
    WHERE
      q.PostTypeId = 1
      AND a.PostTypeId = 2
      AND q.ClosedDate IS NULL
      AND a.ClosedDate IS NULL
  ),
  TagWisePostCount AS (
    SELECT
      t.TagName,
      COUNT(p.Id) AS PostCount,
      AVG(CAST(p.Score AS DECIMAL(10, 2))) AS AvgScore,
      SUM(p.ViewCount) AS TotalViews
    FROM
      Tags t
      JOIN Posts p
        ON POSITION(t.TagName IN COALESCE(p.Tags, '')) > 0
    WHERE
      p.PostTypeId = 1 AND p.Tags IS NOT NULL
    GROUP BY
      t.TagName
  )
SELECT
  'Performance Benchmark Query' AS QueryDescription,
  rp.PostId,
  rp.Title,
  rp.PostTypeName,
  rp.Score,
  rp.ViewCount,
  rp.FavoriteCount,
  rp.AnswerCount,
  rp.CommentCount,
  rps.DisplayName AS OwnerDisplayName,
  rps.TotalPosts,
  rps.TotalScore,
  rps.AvgAnswerCount,
  rps.QuestionCount,
  rps.AnswerCount AS UserAnswerCount,
  CASE
    WHEN rp.Score > 1000 THEN 'High Score'
    WHEN rp.Score > 100 THEN 'Medium Score'
    ELSE 'Low Score'
  END AS ScoreCategory,
  CASE
    WHEN ud.AnswerRank = 1 AND ud.IsAcceptedAnswer = 'Yes' THEN ud.AnswerOwnerDisplayName
    ELSE NULL
  END AS BestAcceptedAnswerer,
  COALESCE(twpc.TagName, 'Uncategorized') AS PrimaryTag,
  COALESCE(twpc.PostCount, 0) AS TagPostCount,
  COALESCE(twpc.AvgScore, 0.0) AS TagAvgScore,
  COALESCE(twpc.TotalViews, 0) AS TagTotalViews,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c
    WHERE
      c.PostId = rp.PostId
      AND LENGTH(c.Text) > 100
  ) AS LongCommentCount,
  (
    SELECT
      AVG(CAST(sub_p.Score AS DECIMAL(10, 2)))
    FROM
      Posts sub_p
    WHERE
      sub_p.OwnerUserId = rp.OwnerUserId
      AND sub_p.PostTypeId = 1
  ) AS AvgUserQuestionScore,
  CASE
    WHEN rp.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5' YEAR) THEN 'Old'
    WHEN rp.CreationDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) THEN 'Established'
    ELSE 'Recent'
  END AS PostAgeCategory,
  (rp.PostTypeName || '-' || CAST(rp.Score AS VARCHAR) || '-' || CAST(rp.ViewCount AS VARCHAR)) AS PostIdentifier,
  CASE
    WHEN rp.LastEditDate IS NULL THEN rp.CreationDate
    ELSE rp.LastEditDate
  END AS EffectiveLastActivityDate
FROM
  RankedPosts rp
LEFT OUTER JOIN UserPostStats rps
  ON rp.OwnerUserId = rps.UserId
LEFT OUTER JOIN QuestionDetails ud
  ON rp.PostId = ud.QuestionId AND ud.AnswerRank = 1
LEFT OUTER JOIN TagWisePostCount twpc
  ON (rp.Title ILIKE ('%' || twpc.TagName || '%')) OR (COALESCE(rp.Tags, '') ILIKE ('%' || twpc.TagName || '%'))
WHERE
  rp.rn <= 100
  AND rps.TotalPosts > 10
  AND rp.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
  AND rp.OwnerUserId NOT IN (SELECT Id FROM Users WHERE DisplayName LIKE 'Community%')
  AND rp.PostTypeName <> 'TagWikiExcerpt'
  AND rp.PostTypeName <> 'TagWiki'
UNION ALL
SELECT
  'Performance Benchmark Query' AS QueryDescription,
  NULL AS PostId,
  NULL AS Title,
  NULL AS PostTypeName,
  NULL AS Score,
  NULL AS ViewCount,
  NULL AS FavoriteCount,
  NULL AS AnswerCount,
  NULL AS CommentCount,
  NULL AS OwnerDisplayName,
  NULL AS TotalPosts,
  NULL AS TotalScore,
  NULL AS AvgAnswerCount,
  NULL AS QuestionCount,
  NULL AS UserAnswerCount,
  NULL AS ScoreCategory,
  NULL AS BestAcceptedAnswerer,
  NULL AS PrimaryTag,
  NULL AS TagPostCount,
  NULL AS TagAvgScore,
  NULL AS TagTotalViews,
  NULL AS LongCommentCount,
  NULL AS AvgUserQuestionScore,
  NULL AS PostAgeCategory,
  NULL AS PostIdentifier,
  NULL AS EffectiveLastActivityDate
WHERE
  1 = 0;