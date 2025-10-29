WITH
  QuestionMetrics AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate AS QuestionCreationDate,
      p.Score AS QuestionScore,
      p.ViewCount AS QuestionViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS RowNum
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
      LEFT JOIN Comments c
        ON p.Id = c.PostId
      LEFT JOIN Votes v
        ON p.Id = v.PostId
      LEFT JOIN VoteTypes vt
        ON v.VoteTypeId = vt.Id
    WHERE
      pt.Name = 'Question'
      AND p.OwnerUserId IS NOT NULL
    GROUP BY
      p.Id,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.FavoriteCount,
      p.ClosedDate
  ),
  AnswerMetrics AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.CreationDate AS AnswerCreationDate,
      p.Score AS AnswerScore,
      p.OwnerUserId AS AnswerOwnerUserId,
      ROW_NUMBER() OVER (
        PARTITION BY
          p.ParentId
        ORDER BY
          p.Score DESC,
          p.CreationDate ASC
      ) AS AnswerRank
    FROM
      Posts p
      JOIN PostTypes pt
        ON p.PostTypeId = pt.Id
    WHERE
      pt.Name = 'Answer'
      AND p.ParentId IS NOT NULL
  ),
  UserReputation AS (
    SELECT
      Id AS UserId,
      DisplayName,
      Reputation,
      CreationDate,
      ROW_NUMBER() OVER (
        ORDER BY
          Reputation DESC
      ) AS ReputationRank
    FROM
      Users
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS PostCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
      COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
      SUM(COALESCE(p.Score, 0)) AS TotalScore,
      SUM(COALESCE(p.ViewCount, 0)) AS TotalViews,
      MAX(u.LastAccessDate) AS LastAccess
    FROM
      Users u
      LEFT JOIN Posts p
        ON u.Id = p.OwnerUserId
    GROUP BY
      u.Id,
      u.DisplayName
  )
SELECT
  qm.QuestionId,
  qm.Title AS QuestionTitle,
  qm.QuestionCreationDate,
  qm.QuestionScore,
  qm.QuestionViewCount,
  qm.AnswerCount AS TotalAnswers,
  qm.CommentCount AS QuestionComments,
  qm.UpVoteCount AS QuestionUpVotes,
  qm.DownVoteCount AS QuestionDownVotes,
  CASE WHEN qm.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS QuestionStatus,
  ur.DisplayName AS QuestionOwnerDisplayName,
  ur.Reputation AS QuestionOwnerReputation,
  ur.ReputationRank AS QuestionOwnerReputationRank,
  COALESCE(ua.PostCount, 0) AS QuestionOwnerTotalPosts,
  COALESCE(ua.QuestionCount, 0) AS QuestionOwnerTotalQuestions,
  COALESCE(ua.AnswerCount, 0) AS QuestionOwnerTotalAnswers,
  COALESCE(ua.TotalScore, 0) AS QuestionOwnerTotalScore,
  COALESCE(ua.TotalViews, 0) AS QuestionOwnerTotalViews,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks pl
    WHERE
      pl.PostId = qm.QuestionId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks,
  (
    SELECT
      -- Use ARRAY_AGG of text-converted scores and then join to a string for portability
      array_to_string(ARRAY_AGG(CAST(am.AnswerScore AS TEXT) ORDER BY am.AnswerScore DESC), ', ')
    FROM
      AnswerMetrics am
    WHERE
      am.QuestionId = qm.QuestionId
      AND am.AnswerRank <= 3
  ) AS Top3AnswerScores,
  (
    SELECT
      COUNT(DISTINCT ph.UserId)
    FROM
      PostHistory ph
    WHERE
      ph.PostId = qm.QuestionId
      AND ph.PostHistoryTypeId IN (4, 5, 6)
  ) AS EditorCount,
  qm.RowNum AS QuestionSequence
FROM
  QuestionMetrics qm
  LEFT JOIN UserReputation ur
    ON qm.OwnerUserId = ur.UserId
  LEFT JOIN UserActivity ua
    ON qm.OwnerUserId = ua.UserId
WHERE
  (
    qm.QuestionScore > 10
    AND qm.QuestionViewCount > 1000
    AND qm.AnswerCount BETWEEN 2 AND 10
    AND qm.QuestionCreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
  )
  OR qm.FavoriteCount > 50
ORDER BY
  qm.QuestionCreationDate DESC
LIMIT 100;