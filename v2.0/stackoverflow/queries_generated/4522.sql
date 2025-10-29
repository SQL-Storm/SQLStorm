-- {"query": "4522.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1390} 

WITH
  RankedPostHistory AS (
    SELECT
      PostId,
      PostHistoryTypeId,
      UserId,
      CreationDate,
      LAG(CreationDate, 1, '1970-01-01') OVER (PARTITION BY PostId ORDER BY CreationDate) AS PreviousCreationDate,
      ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) AS rn
    FROM PostHistory
    WHERE
      PostHistoryTypeId IN (4, 5, 6) /* Edit Title, Edit Body, Edit Tags */
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
      CASE
        WHEN ph.UserId = p.OwnerUserId THEN 1
        ELSE 0
      END AS IsOwnerEdit,
      (
        ph.CreationDate - ph.PreviousCreationDate
      ) AS EditInterval
    FROM RankedPostHistory AS ph
    JOIN Posts AS p
      ON ph.PostId = p.Id
    WHERE
      ph.rn <= 5 /* Consider the 5 most recent edits */
  ),
  TagUsage AS (
    SELECT
      Tag,
      COUNT(*) AS TagCount
    FROM Posts
    CROSS APPLY string_to_array(
      substring(Tags, 2, length(Tags) - 2),
      '><'
    ) AS Tag
    WHERE
      PostTypeId = 1 /* Questions */
    GROUP BY
      Tag
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
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.PostId = p.Id
      ) AS CommentCount,
      (
        SELECT
          COUNT(*)
        FROM PostLinks AS pl
        WHERE
          pl.PostId = p.Id AND pl.LinkTypeId = 3 /* Duplicate */
      ) AS DuplicateLinkCount,
      (
        SELECT
          COUNT(*)
        FROM PostLinks AS pl
        WHERE
          pl.PostId = p.Id AND pl.LinkTypeId = 1 /* Linked */
      ) AS LinkedLinkCount
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 /* Questions */
  ),
  UserPerformance AS (
    SELECT
      ue.UserId,
      COUNT(DISTINCT ue.PostId) AS EditedPostsCount,
      AVG(ue.EditInterval) AS AvgEditInterval,
      SUM(ue.IsOwnerEdit) AS OwnerEdits,
      COUNT(*) FILTER (WHERE ue.IsOwnerEdit = 0) AS NonOwnerEdits,
      MAX(ue.CreationDate) AS LastEditDate
    FROM UserEdits AS ue
    GROUP BY
      ue.UserId
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
  DATEDIFF(
    'day',
    u.CreationDate,
    qd.QuestionCreationDate
  ) AS DaysSinceUserCreation,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = qd.OwnerUserId AND b.Class = 1 /* Gold Badge */
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = qd.OwnerUserId AND b.Class = 2 /* Silver Badge */
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM Badges AS b
    WHERE
      b.UserId = qd.OwnerUserId AND b.Class = 3 /* Bronze Badge */
  ) AS BronzeBadges,
  CASE
    WHEN qd.Tags LIKE '%<sql>%' THEN 'SQL Related'
    WHEN qd.Tags LIKE '%<performance>%' THEN 'Performance Related'
    ELSE 'Other'
  END AS TagCategory,
  ts.TagCount AS TotalTagCountForQuestionTags
FROM QuestionDetails AS qd
LEFT JOIN Users AS u
  ON qd.OwnerUserId = u.Id
LEFT JOIN UserPerformance AS up
  ON qd.OwnerUserId = up.UserId
LEFT JOIN (
  SELECT DISTINCT
    qd_inner.QuestionId,
    SUM(tu.TagCount) AS TagCount
  FROM QuestionDetails AS qd_inner
  CROSS APPLY string_to_array(
    substring(qd_inner.Tags, 2, length(qd_inner.Tags) - 2),
    '><'
  ) AS Tag
  JOIN TagUsage AS tu
    ON Tag = tu.Tag
  GROUP BY
    qd_inner.QuestionId
) AS ts
  ON qd.QuestionId = ts.QuestionId
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
