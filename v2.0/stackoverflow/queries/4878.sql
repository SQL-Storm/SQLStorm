WITH
  RankedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 AND p.ParentId IS NOT NULL
  ),
  QuestionStats AS (
    SELECT
      q.Id AS QuestionId,
      q.OwnerUserId AS QuestionerId,
      q.Title AS QuestionTitle,
      q.Tags AS QuestionTags,
      q.CreationDate AS QuestionCreationDate,
      q.ViewCount AS QuestionViews,
      q.AnswerCount AS QuestionAnswerCount,
      q.FavoriteCount AS QuestionFavorites,
      q.Score AS QuestionScore,
      q.ClosedDate AS QuestionClosedDate,
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.PostId = q.Id
      ) AS CommentCountOnQuestion,
      (
        SELECT
          COUNT(DISTINCT v.UserId)
        FROM Votes AS v
        WHERE
          v.PostId = q.Id AND v.VoteTypeId = 2
      ) AS UniqueUpvotersOnQuestion,
      (
        SELECT
          COUNT(DISTINCT v.UserId)
        FROM Votes AS v
        WHERE
          v.PostId = q.Id AND v.VoteTypeId = 3
      ) AS UniqueDownvotersOnQuestion,
      (
        SELECT
          MAX(ph.CreationDate)
        FROM PostHistory AS ph
        WHERE
          ph.PostId = q.Id AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS LastEditDateForQuestion,
      (
        SELECT
          COUNT(*)
        FROM PostLinks AS pl
        WHERE
          pl.PostId = q.Id AND pl.LinkTypeId = 3
      ) AS DuplicateLinkCount
    FROM Posts AS q
    WHERE
      q.PostTypeId = 1
  ),
  TopAnswerDetails AS (
    SELECT
      ra.QuestionId,
      ra.AnswerId AS TopAnswerId,
      ra.AnswererId,
      (
        SELECT
          u.DisplayName
        FROM Users AS u
        WHERE
          u.Id = ra.AnswererId
      ) AS TopAnswererDisplayName,
      (
        SELECT
          COUNT(*)
        FROM Comments AS c
        WHERE
          c.PostId = ra.AnswerId
      ) AS CommentCountOnTopAnswer,
      (
        SELECT
          COUNT(DISTINCT v.UserId)
        FROM Votes AS v
        WHERE
          v.PostId = ra.AnswerId AND v.VoteTypeId = 2
      ) AS UniqueUpvotersOnTopAnswer,
      (
        SELECT
          COUNT(DISTINCT v.UserId)
        FROM Votes AS v
        WHERE
          v.PostId = ra.AnswerId AND v.VoteTypeId = 3
      ) AS UniqueDownvotersOnTopAnswer,
      (
        SELECT
          MAX(ph.CreationDate)
        FROM PostHistory AS ph
        WHERE
          ph.PostId = ra.AnswerId AND ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS LastEditDateForTopAnswer,
      p_ans.Score AS TopAnswerScore,
      p_ans.CreationDate AS TopAnswerCreationDate
    FROM RankedAnswers AS ra
    JOIN Posts AS p_ans
      ON ra.AnswerId = p_ans.Id
    WHERE
      ra.rn = 1
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(p.Id) AS TotalPostsOwned,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
      MAX(p.CreationDate) AS LastPostCreationDate,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  PostWithUserActivity AS (
    SELECT
      qs.QuestionId,
      qs.QuestionerId,
      qs.QuestionTitle,
      qs.QuestionTags,
      qs.QuestionCreationDate,
      qs.QuestionViews,
      qs.QuestionAnswerCount,
      qs.QuestionFavorites,
      qs.QuestionScore,
      qs.QuestionClosedDate,
      qs.CommentCountOnQuestion,
      qs.UniqueUpvotersOnQuestion,
      qs.UniqueDownvotersOnQuestion,
      qs.LastEditDateForQuestion,
      qs.DuplicateLinkCount,
      tad.TopAnswerId,
      tad.AnswererId,
      tad.TopAnswererDisplayName,
      tad.CommentCountOnTopAnswer,
      tad.UniqueUpvotersOnTopAnswer,
      tad.UniqueDownvotersOnTopAnswer,
      tad.LastEditDateForTopAnswer,
      tad.TopAnswerScore,
      tad.TopAnswerCreationDate,
      ua.Reputation AS QuestionerReputation,
      ua.UserCreationDate AS QuestionerCreationDate,
      ua.GoldBadges AS QuestionerGoldBadges,
      ua.SilverBadges AS QuestionerSilverBadges,
      ua.BronzeBadges AS QuestionerBronzeBadges,
      ua.TotalPostsOwned AS QuestionerTotalPosts,
      ua.AcceptedAnswersGiven AS QuestionerAcceptedAnswers,
      CASE
        WHEN qs.QuestionClosedDate IS NOT NULL THEN 'Closed'
        WHEN qs.QuestionScore > 100 THEN 'High Score'
        WHEN qs.QuestionAnswerCount > 10 THEN 'Popular'
        ELSE 'Standard'
      END AS QuestionCategorization
    FROM QuestionStats AS qs
    LEFT JOIN TopAnswerDetails AS tad
      ON qs.QuestionId = tad.QuestionId
    LEFT JOIN UserActivity AS ua
      ON qs.QuestionerId = ua.UserId
  )
SELECT
  pwua.QuestionId,
  pwua.QuestionTitle,
  pwua.QuestionTags,
  pwua.QuestionCreationDate,
  pwua.QuestionViews,
  pwua.QuestionScore,
  pwua.QuestionFavorites,
  pwua.QuestionAnswerCount,
  pwua.QuestionClosedDate,
  pwua.CommentCountOnQuestion,
  pwua.UniqueUpvotersOnQuestion,
  pwua.UniqueDownvotersOnQuestion,
  pwua.DuplicateLinkCount,
  pwua.LastEditDateForQuestion,
  pwua.TopAnswerId,
  pwua.AnswererId,
  pwua.TopAnswererDisplayName,
  pwua.TopAnswerScore,
  pwua.TopAnswerCreationDate,
  pwua.CommentCountOnTopAnswer,
  pwua.UniqueUpvotersOnTopAnswer,
  pwua.UniqueDownvotersOnTopAnswer,
  pwua.LastEditDateForTopAnswer,
  pwua.QuestionerId,
  pwua.QuestionerReputation,
  pwua.QuestionerCreationDate,
  pwua.QuestionerGoldBadges,
  pwua.QuestionerSilverBadges,
  pwua.QuestionerBronzeBadges,
  pwua.QuestionerTotalPosts,
  pwua.QuestionerAcceptedAnswers,
  pwua.QuestionCategorization,
  COALESCE(pwua.QuestionScore, 0) * COALESCE(pwua.QuestionAnswerCount, 0) AS ScoreAnswerProduct,
  CAST(COALESCE(pwua.QuestionClosedDate, TIMESTAMP '2024-10-01 12:34:56') AS TIMESTAMP) - CAST(pwua.QuestionCreationDate AS TIMESTAMP) AS DaysToClose_interval,
  EXTRACT(EPOCH FROM (CAST(COALESCE(pwua.QuestionClosedDate, TIMESTAMP '2024-10-01 12:34:56') AS TIMESTAMP) - CAST(pwua.QuestionCreationDate AS TIMESTAMP)))/86400 AS DaysToClose,
  pwua.QuestionTitle || ' - Tags: ' || pwua.QuestionTags AS TitleAndTags,
  CASE
    WHEN pwua.TopAnswererDisplayName IS NULL THEN 'No Answer Provided'
    WHEN pwua.TopAnswerScore < 0 THEN 'Negatively Scored Answer'
    WHEN pwua.TopAnswererDisplayName = 'Community' THEN 'Community Answer'
    ELSE 'User Answer'
  END AS AnswererType,
  CASE
    WHEN pwua.QuestionerId = pwua.AnswererId THEN 'Self-Answered'
    ELSE 'Answered by Others'
  END AS AnswerOrigin
FROM PostWithUserActivity AS pwua
WHERE
  pwua.QuestionCreationDate >= DATE '2023-01-01'
  AND pwua.QuestionScore > -5
  AND (
    pwua.QuestionTags LIKE '%<sql>%' OR pwua.QuestionTags LIKE '%<performance>%'
  )
  AND COALESCE(pwua.QuestionAnswerCount, 0) > 0
  AND EXISTS (
    SELECT
      1
    FROM Users AS u
    WHERE
      u.Id = pwua.AnswererId AND u.Reputation > 10000
  )
UNION
SELECT
  pwua.QuestionId,
  pwua.QuestionTitle,
  pwua.QuestionTags,
  pwua.QuestionCreationDate,
  pwua.QuestionViews,
  pwua.QuestionScore,
  pwua.QuestionFavorites,
  pwua.QuestionAnswerCount,
  pwua.QuestionClosedDate,
  pwua.CommentCountOnQuestion,
  pwua.UniqueUpvotersOnQuestion,
  pwua.UniqueDownvotersOnQuestion,
  pwua.DuplicateLinkCount,
  pwua.LastEditDateForQuestion,
  pwua.TopAnswerId,
  pwua.AnswererId,
  pwua.TopAnswererDisplayName,
  pwua.TopAnswerScore,
  pwua.TopAnswerCreationDate,
  pwua.CommentCountOnTopAnswer,
  pwua.UniqueUpvotersOnTopAnswer,
  pwua.UniqueDownvotersOnTopAnswer,
  pwua.LastEditDateForTopAnswer,
  pwua.QuestionerId,
  pwua.QuestionerReputation,
  pwua.QuestionerCreationDate,
  pwua.QuestionerGoldBadges,
  pwua.QuestionerSilverBadges,
  pwua.QuestionerBronzeBadges,
  pwua.QuestionerTotalPosts,
  pwua.QuestionerAcceptedAnswers,
  pwua.QuestionCategorization,
  COALESCE(pwua.QuestionScore, 0) * COALESCE(pwua.QuestionAnswerCount, 0) AS ScoreAnswerProduct,
  CAST(COALESCE(pwua.QuestionClosedDate, TIMESTAMP '2024-10-01 12:34:56') AS TIMESTAMP) - CAST(pwua.QuestionCreationDate AS TIMESTAMP) AS DaysToClose_interval,
  EXTRACT(EPOCH FROM (CAST(COALESCE(pwua.QuestionClosedDate, TIMESTAMP '2024-10-01 12:34:56') AS TIMESTAMP) - CAST(pwua.QuestionCreationDate AS TIMESTAMP)))/86400 AS DaysToClose,
  pwua.QuestionTitle || ' - Tags: ' || pwua.QuestionTags AS TitleAndTags,
  CASE
    WHEN pwua.TopAnswererDisplayName IS NULL THEN 'No Answer Provided'
    WHEN pwua.TopAnswerScore < 0 THEN 'Negatively Scored Answer'
    WHEN pwua.TopAnswererDisplayName = 'Community' THEN 'Community Answer'
    ELSE 'User Answer'
  END AS AnswererType,
  CASE
    WHEN pwua.QuestionerId = pwua.AnswererId THEN 'Self-Answered'
    ELSE 'Answered by Others'
  END AS AnswerOrigin
FROM PostWithUserActivity AS pwua
WHERE
  pwua.QuestionCreationDate < DATE '2023-01-01'
  AND pwua.QuestionScore > 0
  AND pwua.QuestionAnswerCount > 5
ORDER BY
  QuestionScore DESC,
  QuestionCreationDate ASC
LIMIT 100;