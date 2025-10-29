WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title AS QuestionTitle,
      p.OwnerUserId,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      p.ViewCount AS QuestionViewCount,
      p.Tags AS QuestionTags,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 day'
  ),
  TopAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId AS AnswererUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      p.Id AS OriginalAnswerId,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS answer_rank
    FROM Posts p
    WHERE
      p.PostTypeId = 2
      AND p.ParentId IN (SELECT QuestionId FROM RecentQuestions)
  ),
  QuestionAnswerStats AS (
    SELECT
      rq.QuestionId,
      rq.QuestionTitle,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionViewCount,
      rq.OwnerUserId,
      rq.QuestionTags,
      (
        SELECT
          COUNT(*)
        FROM Comments c
        WHERE
          c.PostId = rq.QuestionId
      ) AS QuestionCommentCount,
      (
        SELECT
          COUNT(DISTINCT ph.UserId)
        FROM PostHistory ph
        WHERE
          ph.PostId = rq.QuestionId
          AND ph.PostHistoryTypeId IN (1, 3, 4, 5, 6)
      ) AS QuestionEditorCount,
      MAX(ta.AnswerScore) AS MaxAnswerScore,
      AVG(ta.AnswerScore) AS AvgAnswerScore,
      SUM(ta.AnswerScore) AS TotalAnswerScore,
      COUNT(ta.AnswerId) AS TotalAnswersProvided
    FROM RecentQuestions rq
    LEFT JOIN TopAnswers ta
      ON rq.QuestionId = ta.QuestionId
    WHERE
      rq.rn <= 1000
    GROUP BY
      rq.QuestionId,
      rq.QuestionTitle,
      rq.QuestionCreationDate,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.QuestionViewCount,
      rq.OwnerUserId,
      rq.QuestionTags
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      u.Views AS UserViews,
      u.UpVotes AS UserUpVotes,
      u.DownVotes AS UserDownVotes,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
      SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
      SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
      (
        SELECT
          COUNT(*)
        FROM Badges b
        WHERE
          b.UserId = u.Id
          AND b.Class = 1
      ) AS GoldBadges,
      (
        SELECT
          COUNT(*)
        FROM Badges b
        WHERE
          b.UserId = u.Id
          AND b.Class = 2
      ) AS SilverBadges,
      (
        SELECT
          COUNT(*)
        FROM Badges b
        WHERE
          b.UserId = u.Id
          AND b.Class = 3
      ) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p
      ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.Views,
      u.UpVotes,
      u.DownVotes
  ),
  PostVoteSummary AS (
    SELECT
      pv.PostId,
      COUNT(CASE WHEN pv.VoteTypeId = 2 THEN 1 END) AS UpVotes,
      COUNT(CASE WHEN pv.VoteTypeId = 3 THEN 1 END) AS DownVotes,
      COUNT(CASE WHEN pv.VoteTypeId = 5 THEN 1 END) AS Favorites
    FROM Votes pv
    WHERE
      pv.PostId IN (SELECT QuestionId FROM RecentQuestions)
      OR pv.PostId IN (SELECT AnswerId FROM TopAnswers)
    GROUP BY
      pv.PostId
  )
SELECT
  qas.QuestionId,
  qas.QuestionTitle,
  qas.QuestionCreationDate,
  qas.QuestionScore,
  qas.AnswerCount,
  qas.FavoriteCount AS QuestionFavoriteCount,
  qas.QuestionViewCount,
  qas.QuestionCommentCount,
  qas.QuestionEditorCount,
  qas.MaxAnswerScore,
  qas.AvgAnswerScore,
  qas.TotalAnswerScore,
  qas.TotalAnswersProvided,
  CASE
    WHEN qas.QuestionTags LIKE '%<sql>%' THEN 'SQL Related'
    WHEN qas.QuestionTags LIKE '%<performance>%' THEN 'Performance Related'
    WHEN qas.QuestionTags LIKE '%<optimization>%' THEN 'Optimization Related'
    ELSE 'Other'
  END AS TagCategory,
  ue.DisplayName AS QuestionOwnerDisplayName,
  ue.Reputation AS QuestionOwnerReputation,
  ue.UserCreationDate AS QuestionOwnerCreationDate,
  ue.GoldBadges AS QuestionOwnerGoldBadges,
  ue.SilverBadges AS QuestionOwnerSilverBadges,
  ue.BronzeBadges AS QuestionOwnerBronzeBadges,
  pvs_q.UpVotes AS QuestionUpVotes,
  pvs_q.DownVotes AS QuestionDownVotes,
  pvs_q.Favorites AS QuestionFavorites,
  (
    SELECT
      COUNT(*)
    FROM PostLinks pl
    WHERE
      pl.PostId = qas.QuestionId
      AND pl.LinkTypeId = 3
  ) AS DuplicateLinksCount,
  (
    SELECT
      ph.CreationDate
    FROM PostHistory ph
    WHERE
      ph.PostId = qas.QuestionId
      AND ph.PostHistoryTypeId IN (4, 5, 6)
    ORDER BY
      ph.CreationDate DESC
    LIMIT 1
  ) AS LastQuestionEditDate
FROM QuestionAnswerStats qas
LEFT JOIN UserEngagement ue
  ON qas.OwnerUserId = ue.UserId
LEFT JOIN PostVoteSummary pvs_q
  ON qas.QuestionId = pvs_q.PostId
WHERE
  qas.QuestionScore > 0
  OR qas.TotalAnswersProvided > 0
  OR qas.QuestionViewCount > 1000
ORDER BY
  qas.QuestionCreationDate DESC
LIMIT 500;