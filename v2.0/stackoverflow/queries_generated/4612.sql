-- {"query": "4612.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1675} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS PostId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn,
      CASE
        WHEN EXISTS (
          SELECT
            1
          FROM
            Posts AS q
          WHERE
            q.Id = p.ParentId AND q.AcceptedAnswerId = p.Id
        )
        THEN 1
        ELSE 0
      END AS IsAcceptedAnswer
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
  ),
  UserAnswerMetrics AS (
    SELECT
      ra.AnswererUserId,
      COUNT(ra.PostId) AS TotalAnswers,
      SUM(ra.IsAcceptedAnswer) AS AcceptedAnswers,
      AVG(
        CASE
          WHEN ra.IsAcceptedAnswer = 1 THEN ra.rn
          ELSE NULL
        END
      ) AS AvgRankOfAcceptedAnswer,
      MAX(
        CASE
          WHEN ra.IsAcceptedAnswer = 1 THEN ra.rn
          ELSE NULL
        END
      ) AS MaxRankOfAcceptedAnswer,
      (
        SELECT
          COUNT(*)
        FROM
          PostHistory AS ph
        WHERE
          ph.UserId = ra.AnswererUserId
          AND ph.PostHistoryTypeId IN (2, 5) -- Initial Body, Edit Body
      ) AS BodyEdits,
      (
        SELECT
          COUNT(DISTINCT ph2.PostId)
        FROM
          PostHistory AS ph2
        WHERE
          ph2.UserId = ra.AnswererUserId
          AND ph2.PostHistoryTypeId IN (1, 4, 7) -- Title changes
      ) AS TitleEdits
    FROM
      RankedAnswers AS ra
    WHERE
      ra.AnswererUserId IS NOT NULL
    GROUP BY
      ra.AnswererUserId
  ),
  QuestionScores AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId AS QuestionerUserId,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      DATEDIFF(
        minute,
        p.CreationDate,
        COALESCE(p.ClosedDate, GETDATE())
      ) AS TimeToCloseMinutes
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1 -- Questions
      AND p.OwnerUserId IS NOT NULL
  ),
  CombinedMetrics AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COALESCE(uam.TotalAnswers, 0) AS TotalAnswersPosted,
      COALESCE(uam.AcceptedAnswers, 0) AS AcceptedAnswersCount,
      uam.AvgRankOfAcceptedAnswer,
      uam.MaxRankOfAcceptedAnswer,
      uam.BodyEdits,
      uam.TitleEdits,
      COUNT(qs.QuestionId) AS QuestionsAsked,
      SUM(qs.QuestionScore) AS TotalQuestionScore,
      SUM(qs.FavoriteCount) AS TotalFavoriteCount,
      AVG(CAST(qs.TimeToCloseMinutes AS FLOAT)) AS AvgTimeToCloseMinutes,
      COUNT(CASE WHEN qs.TimeToCloseMinutes > 30 * 24 * 60 THEN 1 ELSE NULL END) AS QuestionsClosedAfter30Days
    FROM
      Users AS u
      LEFT OUTER JOIN UserAnswerMetrics AS uam ON u.Id = uam.AnswererUserId
      LEFT OUTER JOIN QuestionScores AS qs ON u.Id = qs.QuestionerUserId
    WHERE
      u.Id > 0 -- Exclude community user
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes,
      uam.TotalAnswers,
      uam.AcceptedAnswers,
      uam.AvgRankOfAcceptedAnswer,
      uam.MaxRankOfAcceptedAnswer,
      uam.BodyEdits,
      uam.TitleEdits
  )
SELECT
  cm.UserId,
  cm.DisplayName,
  cm.Reputation,
  cm.UserCreationDate,
  cm.UserViews,
  cm.UserUpVotes,
  cm.UserDownVotes,
  cm.TotalAnswersPosted,
  cm.AcceptedAnswersCount,
  CASE
    WHEN cm.TotalAnswersPosted > 0 THEN CAST(cm.AcceptedAnswersCount AS FLOAT) / cm.TotalAnswersPosted
    ELSE 0
  END AS AcceptanceRate,
  cm.AvgRankOfAcceptedAnswer,
  cm.MaxRankOfAcceptedAnswer,
  cm.BodyEdits,
  cm.TitleEdits,
  cm.QuestionsAsked,
  cm.TotalQuestionScore,
  cm.TotalFavoriteCount,
  cm.AvgTimeToCloseMinutes,
  cm.QuestionsClosedAfter30Days,
  CONCAT(
    CAST(cm.UserId AS VARCHAR),
    '_',
    cm.DisplayName,
    '_',
    CAST(cm.Reputation AS VARCHAR)
  ) AS UserIdentifier,
  CASE
    WHEN cm.Reputation BETWEEN 0 AND 100 THEN 'Novice'
    WHEN cm.Reputation BETWEEN 101 AND 1000 THEN 'Beginner'
    WHEN cm.Reputation BETWEEN 1001 AND 10000 THEN 'Intermediate'
    WHEN cm.Reputation > 10000 THEN 'Expert'
    ELSE 'Unknown'
  END AS ReputationLevel,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = cm.UserId
      AND b.Class = 1
  ) AS GoldBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = cm.UserId
      AND b.Class = 2
  ) AS SilverBadges,
  (
    SELECT
      COUNT(*)
    FROM
      Badges AS b
    WHERE
      b.UserId = cm.UserId
      AND b.Class = 3
  ) AS BronzeBadges,
  (
    SELECT
      SUM(c.Score)
    FROM
      Comments AS c
      JOIN Posts AS p ON c.PostId = p.Id
    WHERE
      c.UserId = cm.UserId
      AND p.OwnerUserId = cm.UserId
  ) AS UserCommentScoreOnOwnPosts,
  (
    SELECT
      COUNT(DISTINCT pl.RelatedPostId)
    FROM
      PostLinks AS pl
      JOIN Posts AS p ON pl.PostId = p.Id
    WHERE
      p.OwnerUserId = cm.UserId
      AND pl.LinkTypeId = 3 -- Duplicate link
  ) AS DuplicateLinksCreated
FROM
  CombinedMetrics AS cm
ORDER BY
  cm.Reputation DESC,
  cm.TotalAnswersPosted DESC,
  cm.QuestionsAsked DESC;
