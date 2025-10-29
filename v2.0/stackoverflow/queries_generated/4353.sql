-- {"query": "4353.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1715} 

WITH
  RankedUserQuestions AS (
    SELECT
      p.Id AS PostId,
      p.OwnerUserId,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1
  ),
  UserStats AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.Views,
      u.CreationDate AS UserCreationDate,
      COALESCE(q.QuestionCount, 0) AS QuestionCount,
      COALESCE(a.AnswerCount, 0) AS AnswerCount,
      COALESCE(c.CommentCount, 0) AS CommentCount,
      COALESCE(b.BadgeCount, 0) AS BadgeCount,
      MAX(CASE WHEN pht.Name = 'Post Closed' THEN 1 ELSE 0 END) AS HasClosedPosts,
      SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived
    FROM
      Users AS u
    LEFT JOIN (
      SELECT
        OwnerUserId,
        COUNT(*) AS QuestionCount
      FROM
        Posts
      WHERE
        PostTypeId = 1
      GROUP BY
        OwnerUserId
    ) AS q
      ON u.Id = q.OwnerUserId
    LEFT JOIN (
      SELECT
        OwnerUserId,
        COUNT(*) AS AnswerCount
      FROM
        Posts
      WHERE
        PostTypeId = 2
      GROUP BY
        OwnerUserId
    ) AS a
      ON u.Id = a.OwnerUserId
    LEFT JOIN (
      SELECT
        UserId,
        COUNT(*) AS CommentCount
      FROM
        Comments
      GROUP BY
        UserId
    ) AS c
      ON u.Id = c.UserId
    LEFT JOIN (
      SELECT
        UserId,
        COUNT(*) AS BadgeCount
      FROM
        Badges
      GROUP BY
        UserId
    ) AS b
      ON u.Id = b.UserId
    LEFT JOIN PostHistory AS ph
      ON u.Id = ph.UserId
    LEFT JOIN PostHistoryTypes AS pht
      ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN Votes AS v
      ON u.Id = v.UserId AND v.VoteTypeId = 2
    GROUP BY
      u.Id,
      u.DisplayName,
      u.Reputation,
      u.UpVotes,
      u.DownVotes,
      u.Views,
      u.CreationDate,
      q.QuestionCount,
      a.AnswerCount,
      c.CommentCount,
      b.BadgeCount
  ),
  TopQuestions AS (
    SELECT
      p.Id,
      p.Title,
      p.OwnerUserId,
      u.DisplayName AS OwnerDisplayName,
      p.CreationDate,
      p.Score,
      p.ViewCount,
      p.AnswerCount,
      p.Tags,
      ROW_NUMBER() OVER (ORDER BY p.Score DESC, p.ViewCount DESC) AS Rank
    FROM
      Posts AS p
    JOIN Users AS u
      ON p.OwnerUserId = u.Id
    WHERE
      p.PostTypeId = 1
      AND p.Score > 100
      AND p.ViewCount > 1000
      AND p.OwnerUserId IS NOT NULL
  ),
  UserQuestionDetails AS (
    SELECT
      rq.OwnerUserId,
      COUNT(rq.PostId) AS TotalQuestions,
      AVG(rq.Score) AS AvgQuestionScore,
      SUM(rq.ViewCount) AS TotalQuestionViews,
      MAX(rq.Score) AS MaxQuestionScore,
      MIN(rq.Score) AS MinQuestionScore,
      COUNT(CASE WHEN rq.rn <= 5 THEN rq.PostId ELSE NULL END) AS Top5QuestionsCount
    FROM
      RankedUserQuestions AS rq
    GROUP BY
      rq.OwnerUserId
  )
SELECT
  us.UserId,
  us.DisplayName,
  us.Reputation,
  us.UserCreationDate,
  us.QuestionCount,
  us.AnswerCount,
  us.CommentCount,
  us.BadgeCount,
  us.HasClosedPosts,
  us.TotalUpvotesReceived,
  COALESCE(uqd.TotalQuestions, 0) AS TotalQuestionsAnsweredByStats,
  COALESCE(uqd.AvgQuestionScore, 0) AS AverageScoreOfUserQuestions,
  COALESCE(uqd.TotalQuestionViews, 0) AS TotalViewsOfUserQuestions,
  COALESCE(uqd.MaxQuestionScore, 0) AS HighestScoreOfUserQuestion,
  COALESCE(uqd.MinQuestionScore, 0) AS LowestScoreOfUserQuestion,
  uqd.Top5QuestionsCount,
  CASE
    WHEN us.Reputation > 10000 THEN 'High Rep'
    WHEN us.Reputation > 1000 THEN 'Medium Rep'
    ELSE 'Low Rep'
  END AS ReputationTier,
  CASE
    WHEN us.UserCreationDate < '2010-01-01' THEN 'Early Adopter'
    ELSE 'Later Adopter'
  END AS UserEra,
  CASE
    WHEN us.DownVotes > us.UpVotes * 2 THEN 'High Negative Bias'
    WHEN us.UpVotes > us.DownVotes * 2 THEN 'High Positive Bias'
    ELSE 'Balanced Bias'
  END AS VoteBias,
  CONCAT(us.DisplayName, ' (', us.Reputation, ')') AS DisplayNameWithRep,
  tq.Title AS ExampleTopQuestionTitle,
  tq.Score AS ExampleTopQuestionScore,
  tq.ViewCount AS ExampleTopQuestionViews,
  CASE
    WHEN tq.Id IS NOT NULL THEN 'Has Top Question'
    ELSE 'No Prominent Question'
  END AS HasProminentQuestion,
  (
    SELECT
      COUNT(*)
    FROM
      Comments AS c_sub
    WHERE
      c_sub.UserId = us.UserId
      AND c_sub.CreationDate BETWEEN us.UserCreationDate AND DATE_TRUNC('day', CURRENT_TIMESTAMP)
  ) AS CommentsSinceAccountCreation,
  CASE
    WHEN EXISTS (
      SELECT
        1
      FROM
        Badges AS b_sub
      WHERE
        b_sub.UserId = us.UserId
        AND b_sub.Name LIKE '%Master%'
    ) THEN 'Has Master Badge'
    ELSE 'No Master Badge'
  END AS HasMasterBadgeStatus
FROM
  UserStats AS us
LEFT JOIN UserQuestionDetails AS uqd
  ON us.UserId = uqd.OwnerUserId
LEFT JOIN TopQuestions AS tq
  ON us.UserId = tq.OwnerUserId AND tq.Rank = 1
WHERE
  us.Reputation > 0
  AND us.QuestionCount > 5
  AND us.AnswerCount > 10
  AND us.DisplayName IS NOT NULL
  AND us.DisplayName NOT LIKE '%[bot]%'
  AND uqd.TotalQuestions > 10
ORDER BY
  us.Reputation DESC,
  us.TotalUpvotesReceived DESC,
  us.DisplayName;
