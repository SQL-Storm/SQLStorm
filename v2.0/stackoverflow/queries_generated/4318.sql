-- {"query": "4318.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1484} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      p.Tags,
      DENSE_RANK() OVER (ORDER BY p.Score DESC) AS ScoreRank,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS QuestionSequenceForUser
    FROM Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
  ),
  AnswerDetails AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId,
      au.DisplayName AS OwnerDisplayName,
      a.CreationDate AS AnswerCreationDate,
      a.Score AS AnswerScore,
      a.CommentCount AS AnswerCommentCount,
      a.ContentLicense,
      CASE
        WHEN a.Id = q.AcceptedAnswerId THEN 1
        ELSE 0
      END AS IsAcceptedAnswer,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRankForQuestion,
      LAG(a.Score, 1, 0) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS PreviousAnswerScore,
      LEAD(a.Score, 1, 0) OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate) AS NextAnswerScore
    FROM Posts AS a
    JOIN Users AS au
      ON a.OwnerUserId = au.Id
    LEFT JOIN QuestionDetails AS q
      ON a.ParentId = q.QuestionId
    WHERE
      a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
  ),
  TopAnswers AS (
    SELECT
      AnswerId,
      QuestionId,
      OwnerUserId,
      OwnerDisplayName,
      AnswerCreationDate,
      AnswerScore,
      IsAcceptedAnswer,
      AnswerCommentCount,
      ContentLicense,
      ROW_NUMBER() OVER (ORDER BY AnswerScore DESC) AS OverallAnswerRank
    FROM AnswerDetails
    WHERE
      AnswerRankForQuestion <= 5
  ),
  UserPostActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName AS UserDisplayName,
      COUNT(p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      AVG(p.Score) AS AverageScore,
      MAX(p.CreationDate) AS LastPostDate,
      COUNT(DISTINCT pf.PostId) AS FavoriteCount,
      COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Posts AS pf
      ON u.Id = pf.OwnerUserId AND pf.FavoriteCount > 0
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    WHERE
      u.Id > 0 AND u.DisplayName IS NOT NULL
    GROUP BY
      u.Id,
      u.DisplayName
    HAVING
      COUNT(p.Id) > 10
  )
SELECT
  qd.QuestionTitle,
  qd.OwnerDisplayName AS QuestionOwner,
  qd.QuestionScore,
  qd.ScoreRank,
  qd.AnswerCount AS TotalAnswers,
  ta.AnswerId,
  ta.OwnerDisplayName AS AnswerOwner,
  ta.AnswerScore,
  ta.IsAcceptedAnswer,
  ta.AnswerCommentCount,
  upa.TotalPosts AS QuestionOwnerTotalPosts,
  upa.AverageScore AS QuestionOwnerAvgScore,
  upa.BadgeCount AS QuestionOwnerBadges,
  COALESCE(
    REPLACE(qd.Tags, '><', ';'),
    'No Tags'
  ) AS FormattedTags,
  DATEDIFF(
    'day',
    qd.QuestionCreationDate,
    COALESCE(qd.ClosedDate, CURRENT_TIMESTAMP)
  ) AS DaysOpenOrClosed,
  CASE
    WHEN qd.QuestionScore > 100 AND qd.AnswerCount > 10 AND ta.IsAcceptedAnswer = 1 THEN 'Highly Rated & Answered'
    WHEN qd.QuestionScore < 0 THEN 'Negatively Scored'
    WHEN qd.AnswerCount = 0 THEN 'Unanswered'
    ELSE 'Standard'
  END AS QuestionStatus,
  CASE
    WHEN ta.AnswerScore > (
      SELECT
        AVG(AnswerScore)
      FROM AnswerDetails
      WHERE
        QuestionId = qd.QuestionId
    ) THEN 'Above Average Answer'
    WHEN ta.AnswerScore < (
      SELECT
        AVG(AnswerScore)
      FROM AnswerDetails
      WHERE
        QuestionId = qd.QuestionId
    ) THEN 'Below Average Answer'
    ELSE 'Average Answer'
  END AS AnswerQuality,
  CONCAT(
    qd.OwnerDisplayName,
    ' | ',
    upa.UserDisplayName
  ) AS OwnerPair,
  ua.UserDisplayName AS PopularUserWhoAnswered
FROM QuestionDetails AS qd
JOIN TopAnswers AS ta
  ON qd.QuestionId = ta.QuestionId
LEFT JOIN UserPostActivity AS upa
  ON qd.OwnerUserId = upa.UserId
LEFT JOIN (
  SELECT DISTINCT
    ad.QuestionId,
    au.DisplayName AS UserDisplayName
  FROM AnswerDetails AS ad
  JOIN Users AS au
    ON ad.OwnerUserId = au.Id
  WHERE
    ad.AnswerScore > 50
) AS ua
  ON qd.QuestionId = ua.QuestionId
WHERE
  qd.QuestionScore > 0 AND qd.QuestionViewCount > 1000 AND qd.QuestionCreationDate >= '2023-01-01' AND COALESCE(qd.Tags, '') <> '' AND ta.AnswerScore >= 0
ORDER BY
  qd.QuestionScore DESC,
  ta.AnswerScore DESC
LIMIT 100;
