-- {"query": "4842.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1678} 
WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM
      PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT p.Id) AS QuestionCount,
      COUNT(CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
      SUM(p.Score) AS TotalScore,
      MAX(p.CreationDate) AS LastPostCreationDate,
      COUNT(DISTINCT c.Id) AS CommentCount,
      SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
      SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
      SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM
      Users AS u
    LEFT JOIN
      Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN
      Comments AS c
      ON u.Id = c.UserId
    LEFT JOIN
      Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.CreationDate AS QuestionCreationDate,
      q.OwnerUserId AS QuestionOwnerUserId,
      q.AnswerCount AS NumberOfAnswers,
      q.AcceptedAnswerId,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViewCount,
      q.Tags AS QuestionTags,
      COALESCE(a.Id, -1) AS FirstAnswerId,
      COALESCE(a.OwnerUserId, -1) AS FirstAnswerOwnerUserId,
      COALESCE(a.Score, 0) AS FirstAnswerScore,
      COALESCE(a.CreationDate, q.CreationDate) AS FirstAnswerCreationDate,
      ua.DisplayName AS QuestionOwnerDisplayName,
      CASE
        WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        ELSE 'Open'
      END AS QuestionStatus
    FROM
      Posts AS q
    LEFT JOIN
      Posts AS a
      ON q.Id = a.ParentId AND a.Id = q.AcceptedAnswerId
    LEFT JOIN
      Users AS ua
      ON q.OwnerUserId = ua.Id
    WHERE
      q.PostTypeId = 1 -- Questions
  ),
  AnswerQuality AS (
    SELECT
      a.Id AS AnswerId,
      a.ParentId AS QuestionId,
      a.OwnerUserId AS AnswerOwnerUserId,
      a.Score AS AnswerScore,
      a.CreationDate AS AnswerCreationDate,
      ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRank,
      CASE
        WHEN q.AcceptedAnswerId = a.Id THEN 1
        ELSE 0
      END AS IsAcceptedAnswer
    FROM
      Posts AS a
    JOIN
      Posts AS q
      ON a.ParentId = q.Id
    WHERE
      a.PostTypeId = 2 -- Answers
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionStatus,
  qd.NumberOfAnswers,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionTags,
  COALESCE(qd.FirstAnswerOwnerUserId, -2) AS FirstAnswerOwnerId, -- Use -2 to distinguish from deleted users
  ua_answer.DisplayName AS FirstAnswerOwnerDisplayName,
  qd.FirstAnswerScore,
  qd.FirstAnswerCreationDate,
  qa.AnswerRank AS BestAnswerRank,
  qa.IsAcceptedAnswer AS IsBestAnswerMarked,
  COUNT(DISTINCT rpe.UserId) AS DistinctEditorsCount,
  SUM(CASE WHEN rpe.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEditCount,
  SUM(CASE WHEN rpe.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEditCount,
  SUM(CASE WHEN rpe.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagsEditCount,
  ua_user.Reputation,
  ua_user.CreationDate AS UserCreationDate,
  ua_user.UpVotes AS UserUpVotes,
  ua_user.DownVotes AS UserDownVotes,
  ua_user.Views AS UserViews,
  CASE
    WHEN qd.QuestionOwnerUserId IS NULL THEN 'Anonymous'
    WHEN ua_user.DisplayName IS NULL THEN 'Deleted User'
    ELSE ua_user.DisplayName
  END AS OriginalQuestionOwner,
  CASE
    WHEN qd.FirstAnswerOwnerUserId IS NULL THEN 'Anonymous'
    WHEN ua_answer.DisplayName IS NULL THEN 'Deleted User'
    ELSE ua_answer.DisplayName
  END AS FirstAnswerOwner
FROM
  QuestionDetails AS qd
LEFT JOIN
  AnswerQuality AS qa
  ON qd.QuestionId = qa.QuestionId AND qa.AnswerRank = 1
LEFT JOIN
  RankedPostEdits AS rpe
  ON qd.QuestionId = rpe.PostId AND rpe.rn = 1
LEFT JOIN
  UserActivity AS ua_user
  ON qd.QuestionOwnerUserId = ua_user.UserId
LEFT JOIN
  UserActivity AS ua_answer
  ON qd.FirstAnswerOwnerUserId = ua_answer.UserId
WHERE
  qd.QuestionScore > 100
  AND qd.NumberOfAnswers >= 2
  AND qd.QuestionViewCount > 5000
  AND CAST(strftime('%Y', qd.QuestionCreationDate) AS INTEGER) >= 2020
  AND qd.QuestionTags LIKE '%<sql>%'
  AND (
    qd.AcceptedAnswerId IS NOT NULL OR qd.FirstAnswerScore >= 5
  )
GROUP BY
  qd.QuestionId,
  qd.Title,
  qd.QuestionOwnerDisplayName,
  qd.QuestionCreationDate,
  qd.QuestionStatus,
  qd.NumberOfAnswers,
  qd.QuestionScore,
  qd.QuestionViewCount,
  qd.QuestionTags,
  FirstAnswerOwnerId,
  ua_answer.DisplayName,
  qd.FirstAnswerScore,
  qd.FirstAnswerCreationDate,
  qa.AnswerRank,
  qa.IsAcceptedAnswer,
  ua_user.Reputation,
  ua_user.CreationDate,
  ua_user.UpVotes,
  ua_user.DownVotes,
  ua_user.Views,
  OriginalQuestionOwner,
  FirstAnswerOwner
ORDER BY
  ua_user.Reputation DESC,
  qd.QuestionViewCount DESC
LIMIT 100;