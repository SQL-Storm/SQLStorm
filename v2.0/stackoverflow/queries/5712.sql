-- {"query": "5712.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 949}
WITH
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
    SUM(CASE WHEN v.VoteTypeId IN (2,16) THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS UpModVotes,
    SUM(CASE WHEN v.VoteTypeId IN (3,10,11,12,14,15,16) THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS ModerationVotes,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS QuestionsCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY u.Id) AS AnswersCount,
    MAX(p.LastActivityDate) OVER (PARTITION BY u.Id) AS LastUserActivity
  FROM
    Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.UserId = u.Id
  WHERE
    u.AccountId IS NOT NULL
),
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
    (us.Reputation * 2
     + COALESCE(
         -- use standard SQL timestamp difference in seconds: extract epoch from timestamps where supported
         -- compute as CAST(EXTRACT(EPOCH FROM last) - EXTRACT(EPOCH FROM first) AS BIGINT)
         COALESCE(
           CAST(EXTRACT(EPOCH FROM us.LastAccessDate) AS BIGINT) - CAST(EXTRACT(EPOCH FROM us.CreationDate) AS BIGINT),
           0
         ),
         0
       )
     + CASE WHEN us.Location IS NOT NULL THEN CHAR_LENGTH(us.Location) ELSE 0 END
     + (CASE WHEN us.QuestionsCount > 0 THEN 1 ELSE 0 END)
    ) AS BenchmarkScore
  FROM
    UserStats us
),
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
    r.UserId,
    r.RankDesc,
    r.Reputation,
    r.Location,
    r.QuestionsCount,
    r.AnswersCount,
    r.BenchmarkScore,
    p.Title,
    p.ViewCount
  HAVING SUM(CASE WHEN p.ViewCount IS NULL THEN 0 ELSE p.ViewCount END) > 0
)
SELECT
  *
FROM
  FinalOutput
ORDER BY
  RankDesc ASC,
  UserId ASC;