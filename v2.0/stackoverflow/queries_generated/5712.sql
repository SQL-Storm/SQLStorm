-- {"query": "5712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 949} 
WITH
-- Sample derived metrics per user for benchmarking
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.DisplayName,
    u.AccountId,
    -- activity score using windowed accumulations
    SUM(CASE WHEN v.VoteTypeId IN (2,16) THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS UpModVotes,
    SUM(CASE WHEN v.VoteTypeId IN (3,10,11,12,14,15,16) THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS ModerationVotes,
    -- created posts count (including different types)
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS QuestionsCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS AnswersCount,
    -- latest activity per user
    MAX(p.LastActivityDate) OVER (PARTITION BY u.Id) AS LastUserActivity
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  WHERE
    u.AccountId IS NOT NULL
),
-- Complex cross-join style benchmarking set: simulate heavy correlation with tag wiki and post history
BenchmarkBase AS (
  SELECT
    us.UserId,
    us.Reputation,
    us.LastAccessDate,
    us.Location,
    us.QuestionsCount,
    us.AnswersCount,
    us.UpModVotes,
    us.ModerationVotes,
    us.LastUserActivity,
    -- compute a synthetic composite metric using various data types, NULLs, and expressions
    (us.Reputation * 2
     + COALESCE(DATEDIFF(second, us.CreationDate, us.LastAccessDate), 0)
     + CASE
         WHEN us.Location IS NOT NULL THEN LENGTH(us.Location)
         ELSE 0
       END
     + (CASE WHEN us.QuestionsCount > 0 THEN 1 ELSE 0 END)
    ) AS BenchmarkScore
  FROM
    UserStats us
),
-- A set operation to create a union with a derived subset
BenchmarkUnion AS (
  SELECT *
  FROM BenchmarkBase
  UNION ALL
  SELECT
    b.UserId,
    b.Reputation,
    b.LastAccessDate,
    b.Location,
    b.QuestionsCount,
    b.AnswersCount,
    b.UpModVotes,
    b.ModerationVotes,
    b.LastUserActivity,
    b.BenchmarkScore * 3 AS BenchmarkScore
  FROM BenchmarkBase b
  WHERE b.QuestionsCount >= 5
),
-- Window function heavy calculation over a ranking of users by BenchmarkScore
Ranked AS (
  SELECT
    bu.UserId,
    bu.Reputation,
    bu.LastAccessDate,
    bu.Location,
    bu.QuestionsCount,
    bu.AnswersCount,
    bu.UpModVotes,
    bu.ModerationVotes,
    bu.LastUserActivity,
    bu.BenchmarkScore,
    ROW_NUMBER() OVER (ORDER BY bu.BenchmarkScore DESC, bu.LastAccessDate ASC) AS RankDesc
  FROM BenchmarkUnion bu
),
-- Final aggregation with outer join to Posts to force semi-structured relationships
FinalOutput AS (
  SELECT
    r.UserId,
    r.RankDesc,
    r.Reputation,
    r.Location,
    r.QuestionsCount,
    r.AnswersCount,
    r.BenchmarkScore,
    COALESCE(p.Title, '(no post)') AS LastPostTitle,
    COALESCE(p.ViewCount, 0) AS LastPostViews
  FROM Ranked r
  LEFT JOIN Posts p ON p.OwnerUserId = r.UserId
  WHERE r.RankDesc <= 100
  GROUP BY
    r.UserId, r.RankDesc, r.Reputation, r.Location, r.QuestionsCount, r.AnswersCount, r.BenchmarkScore, p.Title, p.ViewCount
  HAVING SUM(CASE WHEN p.ViewCount IS NULL THEN 0 ELSE p.ViewCount END) > 0
)
SELECT
  *
FROM
  FinalOutput
ORDER BY
  RankDesc ASC,
  UserId ASC
;