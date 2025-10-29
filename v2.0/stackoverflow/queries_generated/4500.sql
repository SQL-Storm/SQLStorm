-- {"query": "4500.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1444} 

WITH
  QuestionInfo AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      u.DisplayName AS OwnerDisplayName,
      u.Reputation AS OwnerReputation,
      u.CreationDate AS OwnerCreationDate,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.OwnerUserId
        ORDER BY
          p.CreationDate DESC
      ) AS rn_user_questions
    FROM
      Posts AS p
      JOIN Users AS u
        ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.OwnerUserId IS NOT NULL
  ),
  AnswerDetails AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      SUM(CASE WHEN a.IsAcceptedAnswer = 1 THEN 1 ELSE 0 END) AS AcceptedAnswers
    FROM
      Posts AS a
      LEFT JOIN Posts AS p
        ON a.Id = p.Id AND p.PostTypeId = 2
    WHERE
      a.PostTypeId = 2
    GROUP BY
      a.ParentId
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS NumComments,
      SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments,
      AVG(CAST(Score AS REAL)) AS AvgCommentScore,
      MAX(CreationDate) AS LastCommentDate
    FROM
      Comments
    WHERE
      UserId IS NOT NULL
    GROUP BY
      UserId
  ),
  RecentPostHistory AS (
    SELECT
      PostId,
      MAX(CreationDate) AS LastHistoryDate
    FROM
      PostHistory
    WHERE
      PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    GROUP BY
      PostId
  )
SELECT
  q.QuestionId,
  q.Title,
  q.OwnerDisplayName,
  q.OwnerReputation,
  q.OwnerCreationDate,
  q.QuestionCreationDate,
  q.QuestionScore,
  q.AnswerCount AS QuestionAnswerCount,
  COALESCE(a.TotalAnswers, 0) AS TotalAnswersPosted,
  COALESCE(a.AcceptedAnswers, 0) AS AcceptedAnswersCount,
  q.FavoriteCount AS QuestionFavoriteCount,
  q.QuestionViewCount,
  ua.NumComments AS UserCommentCount,
  ua.PositiveScoreComments AS UserPositiveScoreComments,
  ua.AvgCommentScore AS UserAvgCommentScore,
  ua.LastCommentDate AS UserLastCommentDate,
  rph.LastHistoryDate AS QuestionLastHistoryActivity,
  CASE
    WHEN q.OwnerReputation > 100000 THEN 'Legendary'
    WHEN q.OwnerReputation > 50000 THEN 'Elite'
    WHEN q.OwnerReputation > 10000 THEN 'Master'
    WHEN q.OwnerReputation > 1000 THEN 'Expert'
    WHEN q.OwnerReputation > 100 THEN 'Experienced'
    ELSE 'Novice'
  END AS OwnerTitle,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = q.OwnerUserId
      AND b.Class = 1 /* Gold Badge */
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = q.OwnerUserId
      AND b.Class = 2 /* Silver Badge */
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = q.OwnerUserId
      AND b.Class = 3 /* Bronze Badge */
  ) AS BronzeBadges,
  IIF(
    q.rn_user_questions = 1,
    'MostRecent',
    'Older'
  ) AS UserQuestionOrder,
  q.QuestionScore * 1.0 / NULLIF(q.QuestionViewCount, 0) AS ScorePerViewRatio,
  SUBSTRING(
    COALESCE(
      (
        SELECT
          GROUP_CONCAT(t.TagName, ', ')
        FROM
          Tags AS t
        WHERE
          t.Id IN (
            SELECT
              CAST(value AS INTEGER)
            FROM
              STRING_SPLIT(REPLACE(REPLACE(q.Tags, '<', ''), '>', ''), ',')
          )
      ),
      'No Tags'
    ),
    1,
    50
  ) AS TopTags,
  CASE
    WHEN q.OwnerUserId = -1 THEN 'Community'
    ELSE 'User'
  END AS OwnerType,
  CASE
    WHEN q.QuestionScore < 0 THEN 'Negative'
    WHEN q.QuestionScore BETWEEN 0 AND 10 THEN 'Low'
    WHEN q.QuestionScore BETWEEN 11 AND 100 THEN 'Medium'
    ELSE 'High'
  END AS ScoreCategory
FROM
  QuestionInfo AS q
LEFT OUTER JOIN AnswerDetails AS a
  ON q.QuestionId = a.QuestionId
LEFT OUTER JOIN UserActivity AS ua
  ON q.OwnerUserId = ua.UserId
LEFT OUTER JOIN RecentPostHistory AS rph
  ON q.QuestionId = rph.PostId
WHERE
  q.QuestionCreationDate >= DATE('now', '-365 day')
  AND q.QuestionScore > 0
  AND q.AnswerCount > 0
  AND q.OwnerReputation > 100
ORDER BY
  q.QuestionScore DESC,
  q.QuestionCreationDate ASC
LIMIT 1000;
