-- {"query": "4028.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1610} 

WITH
  QuestionDetails AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.CreationDate AS QuestionCreationDate,
      u.DisplayName AS QuestionOwnerDisplayName,
      pt.Name AS QuestionType,
      COALESCE(p.AnswerCount, 0) AS AnswerCount,
      COALESCE(p.CommentCount, 0) AS CommentCount,
      COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
      COALESCE(p.Score, 0) AS QuestionScore,
      COALESCE(p.ViewCount, 0) AS QuestionViewCount,
      CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        ELSE 'Open'
      END AS QuestionStatus,
      DATEDIFF(
        'minute',
        p.CreationDate,
        p.LastActivityDate
      ) AS MinutesSinceLastActivity,
      (
        SELECT
          COUNT(*)
        FROM
          Comments c
        WHERE
          c.PostId = p.Id
          AND c.CreationDate >= p.CreationDate
      ) AS CommentCountOnQuestion
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
  ),
  AnswerDetails AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      u.DisplayName AS AnswerOwnerDisplayName,
      COALESCE(p.Score, 0) AS AnswerScore,
      COALESCE(p.CommentCount, 0) AS AnswerCommentCount,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.ParentId
        ORDER BY
          p.Score DESC,
          p.CreationDate ASC
      ) AS RankByScore,
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM
            Posts q
          WHERE
            q.Id = p.ParentId
            AND q.AcceptedAnswerId = p.Id
        ) THEN 1
        ELSE 0
      END AS IsAcceptedAnswer
    FROM
      Posts p
      JOIN PostTypes pt ON p.PostTypeId = pt.Id
      LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 2
  ),
  UserActivity AS (
    SELECT
      UserId,
      COUNT(Id) AS TotalPosts,
      SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
      SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
      SUM(Score) AS TotalScore
    FROM
      Posts
    WHERE
      OwnerUserId IS NOT NULL
      AND OwnerUserId > 0
    GROUP BY
      UserId
  ),
  PostLinkInfo AS (
    SELECT
      pl.PostId,
      COUNT(pl.Id) AS LinkedPostCount
    FROM
      PostLinks pl
    GROUP BY
      pl.PostId
  ),
  FinalResult AS (
    SELECT
      qd.QuestionId,
      qd.QuestionTitle,
      qd.QuestionCreationDate,
      qd.QuestionOwnerDisplayName,
      qd.QuestionType,
      qd.AnswerCount,
      qd.CommentCount,
      qd.FavoriteCount,
      qd.QuestionScore,
      qd.QuestionViewCount,
      qd.QuestionStatus,
      qd.MinutesSinceLastActivity,
      ad.AnswerId,
      ad.AnswerOwnerDisplayName,
      ad.AnswerScore,
      ad.AnswerCommentCount,
      ad.RankByScore,
      ad.IsAcceptedAnswer,
      ua.TotalPosts AS OwnerTotalPosts,
      ua.TotalQuestions AS OwnerTotalQuestions,
      ua.TotalAnswers AS OwnerTotalAnswers,
      ua.TotalScore AS OwnerTotalScore,
      COALESCE(pli.LinkedPostCount, 0) AS NumberOfLinks
    FROM
      QuestionDetails qd
      LEFT JOIN AnswerDetails ad ON qd.QuestionId = ad.QuestionId
      LEFT JOIN UserActivity ua ON qd.OwnerUserId = ua.UserId
      LEFT JOIN PostLinkInfo pli ON qd.QuestionId = pli.PostId
  )
SELECT
  fr.QuestionId,
  fr.QuestionTitle,
  fr.QuestionCreationDate,
  fr.QuestionOwnerDisplayName,
  fr.QuestionType,
  fr.QuestionScore,
  fr.QuestionViewCount,
  fr.QuestionStatus,
  fr.AnswerCount,
  fr.FavoriteCount,
  fr.OwnerTotalPosts,
  fr.OwnerTotalQuestions,
  fr.OwnerTotalAnswers,
  fr.OwnerTotalScore,
  fr.MinutesSinceLastActivity,
  fr.AnswerId,
  fr.AnswerOwnerDisplayName,
  fr.AnswerScore,
  fr.IsAcceptedAnswer,
  fr.AnswerCommentCount,
  fr.NumberOfLinks,
  CASE
    WHEN fr.QuestionScore > 1000 THEN 'High Score'
    WHEN fr.QuestionScore BETWEEN 100 AND 1000 THEN 'Medium Score'
    WHEN fr.QuestionScore > 0 THEN 'Low Score'
    ELSE 'Zero Score'
  END AS ScoreCategory,
  (
    SELECT
      AVG(ad_inner.AnswerScore)
    FROM
      AnswerDetails ad_inner
    WHERE
      ad_inner.QuestionId = fr.QuestionId
  ) AS AverageAnswerScore,
  (
    SELECT
      COUNT(*)
    FROM
      Comments c_inner
    WHERE
      c_inner.PostId = fr.QuestionId
      AND c_inner.Text ILIKE '%great%'
  ) AS CommentsContainingGreat,
  UPPER(
    SUBSTRING(fr.QuestionTitle FROM 1 FOR 3)
  ) AS FirstThreeCharsOfTitle
FROM
  FinalResult fr
WHERE
  fr.QuestionScore > 0
  AND fr.QuestionViewCount > 100
  AND fr.OwnerTotalScore IS NOT NULL
  OR fr.AnswerScore > 50
GROUP BY
  fr.QuestionId,
  fr.QuestionTitle,
  fr.QuestionCreationDate,
  fr.QuestionOwnerDisplayName,
  fr.QuestionType,
  fr.QuestionScore,
  fr.QuestionViewCount,
  fr.QuestionStatus,
  fr.AnswerCount,
  fr.FavoriteCount,
  fr.OwnerTotalPosts,
  fr.OwnerTotalQuestions,
  fr.OwnerTotalAnswers,
  fr.OwnerTotalScore,
  fr.MinutesSinceLastActivity,
  fr.AnswerId,
  fr.AnswerOwnerDisplayName,
  fr.AnswerScore,
  fr.IsAcceptedAnswer,
  fr.AnswerCommentCount,
  fr.NumberOfLinks
HAVING
  COUNT(fr.AnswerId) > 0
ORDER BY
  fr.QuestionCreationDate DESC,
  fr.QuestionScore DESC;
