-- {"query": "4743.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1138} 

WITH
  HighReputationUsers AS (
    SELECT
      UserId
    FROM
      Badges
    WHERE
      Name LIKE '%Expert%'
      AND Class = 1
  ),
  RecentQuestions AS (
    SELECT
      p.Id AS QuestionId,
      p.OwnerUserId,
      p.Title,
      p.Tags,
      p.CreationDate AS QuestionCreationDate,
      ROW_NUMBER() OVER (
        ORDER BY
          p.CreationDate DESC
      ) AS rn_recent
    FROM
      Posts AS p
    WHERE
      p.PostTypeId = 1
      AND p.CreationDate >= DATE('now', '-30 days')
      AND p.OwnerUserId IN (
        SELECT
          UserId
        FROM
          HighReputationUsers
      )
  ),
  AnswerQuality AS (
    SELECT
      p.ParentId AS QuestionId,
      COUNT(a.Id) AS AnswerCount,
      SUM(CASE WHEN a.Score > 5 THEN 1 ELSE 0 END) AS GoodAnswerCount,
      AVG(a.Score) AS AverageAnswerScore,
      MAX(a.Score) AS MaxAnswerScore
    FROM
      Posts AS a
    WHERE
      a.PostTypeId = 2
      AND a.ParentId IS NOT NULL
    GROUP BY
      a.ParentId
  ),
  UserActivity AS (
    SELECT
      u.Id AS UserId,
      u.DisplayName,
      u.Reputation,
      u.CreationDate AS UserCreationDate,
      (
        SELECT
          COUNT(*)
        FROM
          Posts AS p_user
        WHERE
          p_user.OwnerUserId = u.Id
      ) AS PostCount,
      (
        SELECT
          COUNT(*)
        FROM
          Comments AS c_user
        WHERE
          c_user.UserId = u.Id
      ) AS CommentCount,
      (
        SELECT
          SUM(v.VoteTypeId = 2) -- Count of UpVotes
        FROM
          Votes AS v
        WHERE
          v.UserId = u.Id
      ) AS TotalUpVotesCast,
      (
        SELECT
          SUM(v.VoteTypeId = 3) -- Count of DownVotes
        FROM
          Votes AS v
        WHERE
          v.UserId = u.Id
      ) AS TotalDownVotesCast
    FROM
      Users AS u
    WHERE
      u.Reputation > 1000
  ),
  QuestionAnalysis AS (
    SELECT
      rq.QuestionId,
      rq.Title,
      rq.Tags,
      rq.QuestionCreationDate,
      ua.DisplayName AS OwnerDisplayName,
      ua.Reputation AS OwnerReputation,
      aq.AnswerCount,
      aq.GoodAnswerCount,
      aq.AverageAnswerScore,
      aq.MaxAnswerScore,
      CASE WHEN aq.AnswerCount > 0 THEN CAST(aq.GoodAnswerCount AS REAL) / aq.AnswerCount ELSE 0 END AS GoodAnswerRatio,
      COALESCE(ua.TotalUpVotesCast, 0) - COALESCE(ua.TotalDownVotesCast, 0) AS NetVotesCast
    FROM
      RecentQuestions AS rq
      LEFT JOIN UserActivity AS ua
        ON rq.OwnerUserId = ua.UserId
      LEFT JOIN AnswerQuality AS aq
        ON rq.QuestionId = aq.QuestionId
  )
SELECT
  qa.QuestionId,
  qa.Title,
  qa.Tags,
  qa.QuestionCreationDate,
  qa.OwnerDisplayName,
  qa.OwnerReputation,
  qa.AnswerCount,
  qa.GoodAnswerCount,
  qa.AverageAnswerScore,
  qa.MaxAnswerScore,
  qa.GoodAnswerRatio,
  qa.NetVotesCast,
  UPPER(SUBSTRING(qa.Title, 1, 1)) || SUBSTRING(qa.Title, 2) AS FormattedTitle,
  CASE
    WHEN qa.AverageAnswerScore > 10 THEN 'High'
    WHEN qa.AverageAnswerScore > 5 THEN 'Medium'
    ELSE 'Low'
  END AS AnswerScoreCategory,
  CASE
    WHEN qa.Tags LIKE '%<performance>%' THEN 'Performance Related'
    ELSE 'Other'
  END AS TagCategory
FROM
  QuestionAnalysis AS qa
WHERE
  qa.AverageAnswerScore IS NOT NULL
  AND qa.AnswerCount > 1
  AND LENGTH(qa.Tags) > 5
UNION ALL
SELECT
  NULL,
  'Aggregate Analysis',
  NULL,
  NULL,
  NULL,
  AVG(OwnerReputation),
  SUM(AnswerCount),
  SUM(GoodAnswerCount),
  AVG(AverageAnswerScore),
  MAX(MaxAnswerScore),
  AVG(GoodAnswerRatio),
  SUM(NetVotesCast)
FROM
  QuestionAnalysis
WHERE
  AverageAnswerScore IS NOT NULL
  AND AnswerCount > 1
  AND LENGTH(Tags) > 5;
