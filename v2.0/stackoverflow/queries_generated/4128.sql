-- {"query": "4128.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1177} 

WITH
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      COUNT(DISTINCT p.Id) AS TotalPosts,
      SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
      SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
      SUM(CASE WHEN c.Id IS NOT NULL THEN 1 ELSE 0 END) AS CommentCount,
      COUNT(DISTINCT b.Id) AS BadgeCount,
      MAX(p.CreationDate) AS LastPostDate
    FROM
      Users AS u
      LEFT JOIN Posts AS p
      ON u.Id = p.OwnerUserId
      LEFT JOIN PostTypes AS pt
      ON p.PostTypeId = pt.Id
      LEFT JOIN Comments AS c
      ON u.Id = c.UserId
      LEFT JOIN Badges AS b
      ON u.Id = b.UserId
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation
  ),
  QuestionMetrics AS (
    SELECT
      q.Id AS QuestionId,
      q.Title,
      q.Score AS QuestionScore,
      q.ViewCount AS QuestionViews,
      q.AnswerCount AS AnswerCount,
      COALESCE(a.Score, 0) AS BestAnswerScore,
      COALESCE(a.CommentCount, 0) AS BestAnswerCommentCount,
      ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS RankByScore,
      AVG(CAST(c.Score AS DECIMAL(10, 2))) OVER (PARTITION BY q.Id) AS AvgCommentScore,
      COUNT(DISTINCT ph.Id) FILTER (
        WHERE
          ph.PostHistoryTypeId IN (4, 5, 6)
      ) AS EditCount
    FROM
      Posts AS q
      LEFT JOIN PostTypes AS ptq
      ON q.PostTypeId = ptq.Id
      LEFT JOIN Posts AS a
      ON q.AcceptedAnswerId = a.Id
      LEFT JOIN Comments AS c
      ON q.Id = c.PostId
      LEFT JOIN PostHistory AS ph
      ON q.Id = ph.PostId
    WHERE
      ptq.Name = 'Question'
      AND q.ClosedDate IS NULL
    GROUP BY
      q.Id,
      q.Title,
      q.Score,
      q.ViewCount,
      q.AnswerCount,
      a.Score,
      a.CommentCount
  ),
  UserEngagement AS (
    SELECT
      ua.UserId,
      ua.DisplayName,
      ua.Reputation,
      ua.TotalPosts,
      ua.QuestionCount,
      ua.AnswerCount,
      ua.CommentCount,
      ua.BadgeCount,
      CASE
        WHEN ua.LastPostDate > CURRENT_TIMESTAMP - INTERVAL '1 year' THEN 'Active'
        ELSE 'Inactive'
      END AS ActivityStatus,
      RANK() OVER (ORDER BY ua.Reputation DESC) AS ReputationRank
    FROM
      UserActivity AS ua
  )
SELECT
  ue.UserId,
  ue.DisplayName,
  ue.Reputation,
  ue.ActivityStatus,
  ue.ReputationRank,
  qm.Title AS TopQuestionTitle,
  qm.QuestionScore,
  qm.QuestionViews,
  qm.AnswerCount AS QuestionAnswerCount,
  qm.BestAnswerScore,
  qm.BestAnswerCommentCount,
  qm.AvgCommentScore,
  qm.EditCount,
  CASE
    WHEN qm.RankByScore <= 10 THEN 'Top 10 by Score/Views'
    WHEN qm.RankByScore <= 50 THEN 'Top 50 by Score/Views'
    ELSE 'Other'
  END AS QuestionTier,
  COALESCE(
    (
      SELECT
        SUM(v.BountyAmount)
      FROM
        Votes AS v
      WHERE
        v.PostId = qm.QuestionId AND v.VoteTypeId = 8
    ),
    0
  ) AS TotalBountyAmount,
  (
    SELECT
      COUNT(*)
    FROM
      PostLinks AS pl
    WHERE
      pl.PostId = qm.QuestionId AND pl.LinkTypeId = 3
  ) AS DuplicateLinks
FROM
  UserEngagement AS ue
  LEFT JOIN QuestionMetrics AS qm
  ON ue.UserId = (
    SELECT
      OwnerUserId
    FROM
      Posts
    WHERE
      Id = (
        SELECT
          Id
        FROM
          Posts
        WHERE
          OwnerUserId = ue.UserId
          AND PostTypeId = 1
        ORDER BY
          Score DESC,
          ViewCount DESC
        LIMIT 1
      )
  )
WHERE
  ue.Reputation > 1000
  AND ue.TotalPosts > 10
  AND ue.ActivityStatus = 'Active'
ORDER BY
  ue.Reputation DESC,
  ue.TotalPosts DESC
LIMIT 100;
