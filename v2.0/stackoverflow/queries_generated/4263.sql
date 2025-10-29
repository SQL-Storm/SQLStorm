-- {"query": "4263.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1286} 

WITH
  RankedAnswers AS (
    SELECT
      p.Id AS AnswerId,
      p.ParentId AS QuestionId,
      p.OwnerUserId,
      p.Score,
      ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts AS p
    WHERE
      p.PostTypeId = 2 -- Answers
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
      MAX(ph.CreationDate) AS LastPostHistoryDate,
      SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVoteCount,
      SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users AS u
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId
    LEFT JOIN VoteTypes AS vt
      ON v.VoteTypeId = vt.Id
    GROUP BY
      u.Id,
      u.DisplayName
  ),
  QuestionDetails AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.Tags,
      q.AnswerCount,
      q.FavoriteCount,
      q.ClosedDate,
      q.CommunityOwnedDate,
      q.OwnerUserId AS QuestionOwnerId,
      COALESCE(a.AnswerId, -1) AS BestAnswerId,
      COALESCE(a.Score, 0) AS BestAnswerScore,
      DATEDIFF(day, q.CreationDate, GETDATE()) AS DaysSinceCreation
    FROM Posts AS q
    LEFT JOIN RankedAnswers AS a
      ON q.Id = a.QuestionId AND a.rn = 1
    WHERE
      q.PostTypeId = 1 -- Questions
  )
SELECT
  qd.QuestionId,
  qd.Title,
  qd.Tags,
  qd.QuestionOwnerId,
  ua_q.DisplayName AS QuestionOwnerDisplayName,
  ua_q.Reputation AS QuestionOwnerReputation,
  ua_q.LastPostHistoryDate,
  ua_q.UpVoteCount AS QuestionOwnerUpVotes,
  ua_q.DownVoteCount AS QuestionOwnerDownVotes,
  qd.AnswerCount,
  qd.FavoriteCount,
  qd.BestAnswerId,
  qd.BestAnswerScore,
  qd.ClosedDate,
  qd.CommunityOwnedDate,
  CASE
    WHEN qd.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN qd.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
    WHEN qd.DaysSinceCreation > 365 THEN 'Old'
    ELSE 'Active'
  END AS QuestionStatus,
  (
    SELECT
      COUNT(*)
    FROM Comments AS c
    WHERE
      c.PostId = qd.QuestionId AND c.UserId IS NOT NULL
  ) AS CommentCountOnQuestion,
  (
    SELECT
      COUNT(*)
    FROM PostLinks AS pl
    WHERE
      pl.PostId = qd.QuestionId AND pl.LinkTypeId = 3 -- Duplicate link
  ) AS DuplicateLinkCount,
  COALESCE(qd.Tags, 'No Tags') AS ProcessedTags,
  IIF(ua_q.PostHistoryCount > 100, 'High Activity', 'Normal Activity') AS UserActivityLevel
FROM QuestionDetails AS qd
LEFT JOIN Users AS ua_q
  ON qd.QuestionOwnerId = ua_q.Id
WHERE
  qd.AnswerCount > 0
  AND qd.FavoriteCount > 5
  AND qd.BestAnswerScore > 10
  AND ua_q.Reputation > 10000
  AND EXISTS (
    SELECT
      1
    FROM PostHistory AS ph_exist
    WHERE
      ph_exist.PostId = qd.QuestionId AND ph_exist.PostHistoryTypeId IN (4, 5, 6)
  )
  OR qd.QuestionId % 2 = 0
UNION
SELECT
  NULL AS QuestionId,
  'Summary Row' AS Title,
  NULL AS Tags,
  NULL AS QuestionOwnerId,
  NULL AS QuestionOwnerDisplayName,
  NULL AS QuestionOwnerReputation,
  NULL AS LastPostHistoryDate,
  NULL AS QuestionOwnerUpVotes,
  NULL AS QuestionOwnerDownVotes,
  COUNT(DISTINCT q.Id) AS AnswerCount,
  SUM(q.FavoriteCount) AS FavoriteCount,
  NULL AS BestAnswerId,
  AVG(CAST(q.BestAnswerScore AS DECIMAL(10, 2))) AS BestAnswerScore,
  NULL AS ClosedDate,
  NULL AS CommunityOwnedDate,
  'Overall' AS QuestionStatus,
  SUM(
    (
      SELECT
        COUNT(*)
      FROM Comments AS c
      WHERE
        c.PostId = q.QuestionId AND c.UserId IS NOT NULL
    )
  ) AS CommentCountOnQuestion,
  SUM(
    (
      SELECT
        COUNT(*)
      FROM PostLinks AS pl
      WHERE
        pl.PostId = q.QuestionId AND pl.LinkTypeId = 3
    )
  ) AS DuplicateLinkCount,
  'Aggregated' AS ProcessedTags,
  'Summary' AS UserActivityLevel
FROM QuestionDetails AS q
WHERE
  q.AnswerCount > 0 AND q.BestAnswerScore > 10;
