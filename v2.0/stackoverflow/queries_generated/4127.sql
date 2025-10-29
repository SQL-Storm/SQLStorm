-- {"query": "4127.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1173} 

WITH
  RankedPostEdits AS (
    SELECT
      ph.PostId,
      ph.UserId,
      ph.CreationDate,
      ph.PostHistoryTypeId,
      ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
  ),
  PostEditCounts AS (
    SELECT
      ph.UserId,
      COUNT(DISTINCT ph.PostId) AS TotalEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 4 THEN 1 ELSE 0 END) AS TitleEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 5 THEN 1 ELSE 0 END) AS BodyEdits,
      SUM(CASE WHEN ph.PostHistoryTypeId = 6 THEN 1 ELSE 0 END) AS TagEdits,
      MAX(ph.CreationDate) AS LatestEditDate
    FROM PostHistory AS ph
    WHERE
      ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
      ph.UserId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(u.LastAccessDate) AS LastAccessDate
    FROM Users AS u
    LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
    LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.CreationDate,
      u.LastAccessDate
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.Title,
      p.CreationDate,
      p.Score,
      p.AnswerCount,
      p.Tags,
      ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS QuestionRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 1 AND p.CreationDate > DATE('now', '-30 day')
  ),
  HighRatedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS AnswerRank
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 AND p.Score > 5
  )
SELECT
  ua.UserId,
  ua.DisplayName,
  ua.Reputation,
  ua.UserCreationDate,
  ua.TotalPosts,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.BadgeCount,
  ua.LastAccessDate,
  COALESCE(pec.TotalEdits, 0) AS TotalEdits,
  COALESCE(pec.TitleEdits, 0) AS TotalTitleEdits,
  COALESCE(pec.BodyEdits, 0) AS TotalBodyEdits,
  COALESCE(pec.TagEdits, 0) AS TotalTagEdits,
  pec.LatestEditDate,
  rq.Title AS LatestQuestionTitle,
  rq.Score AS LatestQuestionScore,
  rq.AnswerCount AS LatestQuestionAnswerCount,
  rq.Tags AS LatestQuestionTags,
  rq.QuestionRank,
  ha.AnswerId AS TopAnswerForLatestQuestion,
  ha.Score AS TopAnswerScore,
  ha.AnswerRank
FROM UserActivity AS ua
LEFT JOIN PostEditCounts AS pec
  ON ua.UserId = pec.UserId
LEFT JOIN (
  SELECT
    *
  FROM RankedPostEdits
  WHERE
    rn = 1
) AS latest_edit
  ON ua.UserId = latest_edit.UserId
LEFT JOIN RecentQuestions AS rq
  ON ua.UserId = rq.OwnerUserId AND rq.QuestionRank <= 5
LEFT JOIN HighRatedAnswers AS ha
  ON rq.PostId = ha.QuestionId AND ha.AnswerRank = 1
WHERE
  ua.Reputation > 1000 AND ua.TotalPosts > 10
  AND (
    pec.TotalEdits > 0 OR rq.PostId IS NOT NULL
  )
  AND ua.DisplayName NOT LIKE '%[^a-zA-Z0-9 ]%'
  AND LENGTH(ua.DisplayName) > 3
  AND ua.LastAccessDate > DATE('now', '-1 year')
ORDER BY
  ua.Reputation DESC,
  ua.LastAccessDate DESC
LIMIT 100;
