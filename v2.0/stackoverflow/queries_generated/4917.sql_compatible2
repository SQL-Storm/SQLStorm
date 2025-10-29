WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS PostCount,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      COUNT(DISTINCT c.Id) AS CommentCount,
      COUNT(DISTINCT v.Id) AS VoteCount,
      MAX(p.CreationDate) AS LastPostDate,
      ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, MAX(p.CreationDate) DESC) AS RankByReputation
    FROM
      Users u
    LEFT JOIN
      Posts p
      ON u.Id = p.OwnerUserId
    LEFT JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    LEFT JOIN
      Comments c
      ON u.Id = c.UserId AND c.PostId = p.Id
    LEFT JOIN
      Votes v
      ON u.Id = v.UserId AND v.PostId = p.Id
    WHERE
      u.CreationDate >= DATE '2023-01-01'
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  TopQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.Title,
      p.Score,
      p.AnswerCount,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.AnswerCount DESC) AS Rank
    FROM
      Posts p
    JOIN
      PostTypes pt
      ON p.PostTypeId = pt.Id
    WHERE
      pt.Name = 'Question' AND p.Score > 100
  ),
  QuestionAnswers AS (
    SELECT
      a.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(a.Score) AS TotalAnswerScore,
      AVG(a.Score) AS AvgAnswerScore,
      MAX(a.CreationDate) AS LastAnswerDate
    FROM
      Posts a
    JOIN
      PostTypes pt
      ON a.PostTypeId = pt.Id
    WHERE
      pt.Name = 'Answer'
    GROUP BY
      a.ParentId
  ),
  ClosedQuestions AS (
    SELECT
      p.Id AS QuestionId,
      COUNT(DISTINCT ph.Id) AS CloseVoteCount,
      MAX(ph.CreationDate) AS LastCloseVoteDate,
      STRING_AGG(DISTINCT crt.Name, ', ') AS CloseReasons
    FROM
      Posts p
    JOIN
      PostHistory ph
      ON p.Id = ph.PostId
    JOIN
      PostHistoryTypes pht
      ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN
      CloseReasonTypes crt
      ON CASE
           WHEN ph.Comment ~ '^[0-9]+$' THEN CAST(ph.Comment AS INTEGER)
           ELSE NULL
         END = crt.Id
    WHERE
      pht.Name = 'Post Closed'
      AND p.PostTypeId = 1
    GROUP BY
      p.Id
  )
SELECT
  ua.DisplayName,
  ua.Reputation,
  ua.PostCount,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.CommentCount,
  ua.VoteCount,
  tq.Title AS TopQuestionTitle,
  tq.Score AS TopQuestionScore,
  qa.AnswerCount AS QuestionAnswerCount,
  qa.TotalAnswerScore,
  qa.AvgAnswerScore,
  cq.CloseVoteCount,
  cq.CloseReasons,
  CASE
    WHEN ua.LastPostDate IS NULL THEN 'Never Posted'
    WHEN ua.LastPostDate < (CAST('2024-10-01' AS date) - INTERVAL '30' DAY) THEN 'Inactive'
    ELSE 'Active'
  END AS UserActivityStatus,
  COALESCE(ua.DisplayName, 'Anonymous') AS DisplayNameOrAnonymous,
  ua.RankByReputation,
  tq.Rank AS TopQuestionRank
FROM
  UserActivity ua
LEFT JOIN
  TopQuestions tq
  ON tq.Rank = 1
    AND ua.RankByReputation <= 5
LEFT JOIN
  QuestionAnswers qa
  ON tq.QuestionId = qa.QuestionId
LEFT JOIN
  ClosedQuestions cq
  ON tq.QuestionId = cq.QuestionId
WHERE
  ua.Reputation > 1000
UNION ALL
SELECT
  'Community User' AS DisplayName,
  MAX(u.Reputation) AS Reputation,
  COUNT(DISTINCT p.Id) AS PostCount,
  SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
  SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
  COUNT(DISTINCT c.Id) AS CommentCount,
  COUNT(DISTINCT v.Id) AS VoteCount,
  NULL AS TopQuestionTitle,
  NULL AS TopQuestionScore,
  NULL AS QuestionAnswerCount,
  NULL AS TotalAnswerScore,
  NULL AS AvgAnswerScore,
  NULL AS CloseVoteCount,
  NULL AS CloseReasons,
  'Community' AS UserActivityStatus,
  'Community User' AS DisplayNameOrAnonymous,
  NULL AS RankByReputation,
  NULL AS TopQuestionRank
FROM
  Users u
LEFT JOIN
  Posts p
  ON u.Id = p.OwnerUserId
LEFT JOIN
  PostTypes pt
  ON p.PostTypeId = pt.Id
LEFT JOIN
  Comments c
  ON u.Id = c.UserId AND c.PostId = p.Id
LEFT JOIN
  Votes v
  ON u.Id = v.UserId AND v.PostId = p.Id
WHERE
  u.DisplayName = 'Community'
GROUP BY
  u.DisplayName;