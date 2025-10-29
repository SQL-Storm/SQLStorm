-- {"query": "4522.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1390}
WITH
  RankedPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      CreationDate,
      LAG(CreationDate, 1, TIMESTAMP '1970-01-01') OVER (PARTITION BY PostId ORDER BY CreationDate) AS PreviousCreationDate,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6)
  ),
  UserEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      p.OwnerUserId,
      p.PostTypeId,
      p.Tags,
      ph.PreviousCreationDate,
      ph.rn,
      CASE WHEN ph.UserId = p.OwnerUserId THEN 1 ELSE 0 END AS IsOwnerEdit,
      (ph.CreationDate - ph.PreviousCreationDate) AS EditInterval
    FROM RankedPostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    WHERE
      ph.rn <= 5
  ),
  -- Expand tags by turning the delimited string into rows using a set-returning approach compatible with multiple dialects:
  PostTags AS (
    SELECT
      p.Id AS PostId,
      TRIM(tag) AS Tag
    FROM Posts AS p
    CROSS JOIN LATERAL (
      SELECT
        regexp_split_to_table(
          CASE
            WHEN p.Tags IS NULL THEN ''
            ELSE substring(p.Tags FROM 2 FOR (char_length(p.Tags) - 2))
          END,
          '><'
        ) AS tag
    ) t
    WHERE p.PostTypeId = 1
  ),
  TagUsage AS (
    SELECT
      Tag,
      COUNT(*) AS TagCount
    FROM PostTags
    GROUP BY Tag
  ),
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.ViewCount AS QuestionViewCount,
      p.FavoriteCount,
      p.Tags,
      COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
      (SELECT COUNT(*) FROM Comments AS c WHERE c.PostId = p.Id) AS CommentCount,
      (SELECT COUNT(*) FROM PostLinks AS pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
      (SELECT COUNT(*) FROM PostLinks AS pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedLinkCount
    FROM Posts AS p
    WHERE p.PostTypeId = 1
  ),
  UserPerformance AS (
    SELECT
      ue.UserId,
      COUNT(DISTINCT ue.PostId) AS EditedPostsCount,
      AVG(EXTRACT(EPOCH FROM ue.EditInterval)) * INTERVAL '1 second' AS AvgEditInterval,
      SUM(ue.IsOwnerEdit) AS OwnerEdits,
      SUM(CASE WHEN ue.IsOwnerEdit = 0 THEN 1 ELSE 0 END) AS NonOwnerEdits,
      MAX(ue.CreationDate) AS LastEditDate
    FROM UserEdits AS ue
    GROUP BY ue.UserId
  ),
  QuestionTagCounts AS (
    SELECT
      qd.QuestionId,
      SUM(tu.TagCount) AS TagCount
    FROM QuestionDetails AS qd
    JOIN LATERAL (
      SELECT regexp_split_to_table(
        CASE WHEN qd.Tags IS NULL THEN '' ELSE substring(qd.Tags FROM 2 FOR (char_length(qd.Tags) - 2)) END,
        '><'
      ) AS tag
    ) t ON true
    JOIN TagUsage AS tu
      ON t.tag = tu.Tag
    GROUP BY qd.QuestionId
  )
SELECT
  qd.QuestionId,
  qd.QuestionScore,
  qd.AnswerCount,
  qd.QuestionViewCount,
  qd.FavoriteCount,
  qd.AcceptedAnswerId,
  qd.CommentCount,
  qd.DuplicateLinkCount,
  qd.LinkedLinkCount,
  u.DisplayName AS OwnerDisplayName,
  up.EditedPostsCount,
  up.AvgEditInterval,
  up.OwnerEdits,
  up.NonOwnerEdits,
  EXTRACT(DAY FROM (qd.QuestionCreationDate - u.CreationDate)) AS DaysSinceUserCreation,
  (SELECT COUNT(*) FROM Badges AS b WHERE b.UserId = qd.OwnerUserId AND b.Class = 1) AS GoldBadges,
  (SELECT COUNT(*) FROM Badges AS b WHERE b.UserId = qd.OwnerUserId AND b.Class = 2) AS SilverBadges,
  (SELECT COUNT(*) FROM Badges AS b WHERE b.UserId = qd.OwnerUserId AND b.Class = 3) AS BronzeBadges,
  CASE
    WHEN qd.Tags LIKE '%<sql>%' THEN 'SQL Related'
    WHEN qd.Tags LIKE '%<performance>%' THEN 'Performance Related'
    ELSE 'Other'
  END AS TagCategory,
  qtc.TagCount AS TotalTagCountForQuestionTags
FROM QuestionDetails AS qd
LEFT JOIN Users AS u
  ON qd.OwnerUserId = u.Id
LEFT JOIN UserPerformance AS up
  ON qd.OwnerUserId = up.UserId
LEFT JOIN QuestionTagCounts AS qtc
  ON qd.QuestionId = qtc.QuestionId
WHERE
  qd.QuestionScore > 10
  AND qd.AnswerCount > 0
  AND qd.QuestionViewCount > 1000
  AND qd.OwnerUserId IS NOT NULL
  AND qd.AcceptedAnswerId <> -1
  AND up.AvgEditInterval IS NOT NULL
  AND up.AvgEditInterval < INTERVAL '7 days'
ORDER BY
  qd.QuestionScore DESC,
  qd.QuestionViewCount DESC
LIMIT 100;