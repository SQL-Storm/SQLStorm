-- {"query": "4942.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1050}
WITH
  RecentQuestions AS (
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
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN Users u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= cast('2024-10-01' as date) - INTERVAL '365 days'
  ),
  TopAnswers AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(a.Score) AS TotalAnswerScore,
      AVG(a.Score) AS AverageAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY SUM(a.Score) DESC) AS answer_rn
    FROM Posts a
    WHERE
      a.PostTypeId = 2
    GROUP BY
      a.ParentId
  ),
  QuestionActivity AS (
    SELECT
      ph.PostId AS QuestionId,
      COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 6) THEN 1 END) AS EditCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 END) AS CloseCount,
      COUNT(CASE WHEN ph.PostHistoryTypeId = 14 THEN 1 END) AS LockCount,
      MAX(ph.CreationDate) AS LastActivityDate
    FROM PostHistory ph
    WHERE
      ph.PostId IN (SELECT QuestionId FROM RecentQuestions)
    GROUP BY
      ph.PostId
  ),
  UserEngagement AS (
    SELECT
      u.Id AS UserId,
      COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
      COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      u.CreationDate AS UserCreationDate,
      u.LastAccessDate AS UserLastAccessDate
    FROM Users u
    LEFT JOIN Votes v
      ON u.Id = v.UserId
    LEFT JOIN Badges b
      ON u.Id = b.UserId
    WHERE
      u.Id IN (SELECT OwnerUserId FROM RecentQuestions)
    GROUP BY
      u.Id,
      u.CreationDate,
      u.LastAccessDate
  )
SELECT
  rq.QuestionId,
  rq.Title,
  rq.QuestionCreationDate,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  rq.AnswerCount AS QuestionAnswerCount,
  rq.FavoriteCount AS QuestionFavoriteCount,
  rq.QuestionViewCount,
  ta.TotalAnswerScore,
  ta.AverageAnswerScore,
  COALESCE(qa.EditCount, 0) AS TotalEdits,
  COALESCE(qa.CloseCount, 0) AS TotalCloseVotes,
  COALESCE(qa.LockCount, 0) AS TotalLockEvents,
  ue.UpVoteCount AS OwnerUpVotes,
  ue.DownVoteCount AS OwnerDownVotes,
  ue.BadgeCount AS OwnerBadgeCount,
  CASE
    WHEN rq.QuestionScore > 0 AND ta.TotalAnswerScore > 0 THEN ROUND(CAST(rq.QuestionScore AS NUMERIC) / ta.TotalAnswerScore, 2)
    WHEN rq.QuestionScore IS NULL THEN 0
    ELSE 0
  END AS ScoreRatio,
  CASE
    WHEN rq.QuestionCreationDate > ue.UserCreationDate THEN 'Experienced'
    ELSE 'New'
  END AS UserExperience,
  (rq.QuestionViewCount * (ue.BadgeCount + 1)) % 100 AS CalculatedMetric
FROM RecentQuestions rq
LEFT JOIN TopAnswers ta
  ON rq.QuestionId = ta.QuestionId
LEFT JOIN QuestionActivity qa
  ON rq.QuestionId = qa.QuestionId
LEFT JOIN UserEngagement ue
  ON rq.OwnerUserId = ue.UserId
WHERE
  rq.rn <= 100
GROUP BY
  rq.QuestionId,
  rq.Title,
  rq.QuestionCreationDate,
  rq.OwnerDisplayName,
  rq.OwnerReputation,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.QuestionViewCount,
  ta.TotalAnswerScore,
  ta.AverageAnswerScore,
  qa.EditCount,
  qa.CloseCount,
  qa.LockCount,
  ue.UpVoteCount,
  ue.DownVoteCount,
  ue.BadgeCount,
  ue.UserCreationDate,
  rq.QuestionScore,
  rq.FavoriteCount
ORDER BY
  rq.QuestionScore DESC,
  rq.FavoriteCount DESC
LIMIT 100;