WITH
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.AnswerCount,
      p.FavoriteCount,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    WHERE
      p.PostTypeId = 1 AND p.CreationDate > DATE '2023-01-01'
  ),
  TopAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score AS AnswerScore,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS answer_rank
    FROM Posts p
    WHERE
      p.PostTypeId = 2
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT ph.Id) AS PostHistoryCount,
      SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6) THEN 1 ELSE 0 END) AS EditHistoryCount,
      MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastCloseVoteDate,
      CASE
        WHEN EXISTS (
          SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%gold%'
        ) THEN 'Gold'
        WHEN EXISTS (
          SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Name LIKE '%silver%'
        ) THEN 'Silver'
        ELSE 'Bronze'
      END AS TopBadgeClass
    FROM Users u
    LEFT JOIN PostHistory ph
      ON u.Id = ph.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate
  ),
  QuestionEngagement AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
      rq.rn
    FROM RecentQuestions rq
    LEFT JOIN Comments c
      ON rq.QuestionId = c.PostId
    LEFT JOIN Votes v
      ON rq.QuestionId = v.PostId
    GROUP BY
      rq.QuestionId,
      rq.Title,
      rq.QuestionScore,
      rq.AnswerCount,
      rq.FavoriteCount,
      rq.rn
  ),
  PostData AS (
    SELECT
      qe.QuestionId,
      qe.Title AS QuestionTitle,
      qe.QuestionScore,
      qe.AnswerCount,
      qe.FavoriteCount,
      qe.CommentCount,
      qe.UpVoteCount AS QuestionUpVotes,
      qe.DownVoteCount AS QuestionDownVotes,
      ta.AnswerId,
      ta.AnswerScore,
      ta.OwnerUserId AS AnswerOwnerUserId,
      ua.DisplayName AS AnswererDisplayName,
      ua.Reputation AS AnswererReputation,
      ua.UserCreationDate AS AnswererCreationDate,
      ua.PostHistoryCount AS AnswererPostHistoryCount,
      ua.EditHistoryCount AS AnswererEditHistoryCount,
      ua.LastCloseVoteDate AS AnswererLastCloseVoteDate,
      ua.TopBadgeClass AS AnswererTopBadgeClass,
      CASE
        WHEN ta.answer_rank = 1 THEN 'Best'
        WHEN ta.answer_rank BETWEEN 2 AND 5 THEN 'Good'
        ELSE 'Other'
      END AS AnswerQualityRank,
      CASE
        WHEN qe.QuestionScore < 0 THEN 'Negative'
        WHEN qe.QuestionScore BETWEEN 0 AND 10 THEN 'Low'
        ELSE 'High'
      END AS QuestionScoreCategory,
      qe.rn,
      ta.answer_rank
    FROM QuestionEngagement qe
    LEFT JOIN TopAnswers ta
      ON qe.QuestionId = ta.QuestionId AND ta.answer_rank <= 5
    LEFT JOIN UserActivity ua
      ON ta.OwnerUserId = ua.UserId
    WHERE
      qe.rn <= 100
  )
SELECT
  pd.QuestionTitle,
  pd.QuestionScore,
  pd.AnswerCount,
  pd.FavoriteCount,
  pd.QuestionUpVotes,
  pd.QuestionDownVotes,
  pd.AnswerId,
  pd.AnswerScore,
  pd.AnswerOwnerUserId,
  pd.AnswererDisplayName,
  pd.AnswererReputation,
  COALESCE(pd.AnswererCreationDate, DATE '1970-01-01') AS AnswererCreationDate,
  pd.AnswererPostHistoryCount,
  pd.AnswererEditHistoryCount,
  CASE
    WHEN pd.AnswererLastCloseVoteDate IS NULL THEN NULL
    ELSE CAST(pd.AnswererLastCloseVoteDate AS DATE)
  END AS AnswererLastCloseVoteDate,
  pd.AnswererTopBadgeClass,
  pd.AnswerQualityRank,
  pd.QuestionScoreCategory,
  CASE
    WHEN pd.AnswererReputation > 10000 THEN 'Expert'
    WHEN pd.AnswererReputation > 1000 THEN 'Intermediate'
    ELSE 'Beginner'
  END AS AnswererExperienceLevel,
  LENGTH(pd.QuestionTitle) AS TitleLength,
  UPPER(SUBSTRING(pd.QuestionTitle FROM 1 FOR 1)) AS FirstLetterOfTitle,
  CASE WHEN pd.AnswerId IS NULL THEN 'No Answer' ELSE 'Answered' END AS AnswerStatus,
  (pd.QuestionScore + COALESCE(pd.AnswerScore, 0)) * pd.FavoriteCount AS EngagementMetric,
  pd.rn,
  pd.answer_rank
FROM PostData pd
WHERE
  pd.AnswererReputation IS NOT NULL

UNION ALL

SELECT
  pd.QuestionTitle,
  pd.QuestionScore,
  pd.AnswerCount,
  pd.FavoriteCount,
  pd.QuestionUpVotes,
  pd.QuestionDownVotes,
  NULL AS AnswerId,
  NULL AS AnswerScore,
  NULL AS AnswerOwnerUserId,
  NULL AS AnswererDisplayName,
  NULL AS AnswererReputation,
  CAST(NULL AS TIMESTAMP) AS AnswererCreationDate,
  NULL AS AnswererPostHistoryCount,
  NULL AS AnswererEditHistoryCount,
  CAST(NULL AS TIMESTAMP) AS AnswererLastCloseVoteDate,
  NULL AS AnswererTopBadgeClass,
  'No Answer' AS AnswerQualityRank,
  pd.QuestionScoreCategory,
  NULL AS AnswererExperienceLevel,
  LENGTH(pd.QuestionTitle) AS TitleLength,
  UPPER(SUBSTRING(pd.QuestionTitle FROM 1 FOR 1)) AS FirstLetterOfTitle,
  'No Answer' AS AnswerStatus,
  pd.QuestionScore * pd.FavoriteCount AS EngagementMetric,
  pd.rn,
  NULL AS answer_rank
FROM PostData pd
WHERE
  pd.AnswerId IS NULL

ORDER BY
  QuestionScore DESC,
  FavoriteCount DESC;