-- {"query": "5063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1018} 
WITH
RecentTopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.ViewCount,
    p.Score,
    p.OwnerUserId,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.ClosedDate IS NULL
),
TopContributors AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.Location,
    u.EmailHash,
    u.WebsiteUrl,
    u.AboutMe,
    (SELECT COUNT(*) FROM Posts t WHERE t.OwnerUserId = u.Id AND t.PostTypeId = 1) AS QuestionCount,
    (SELECT COUNT(*) FROM Posts a WHERE a.OwnerUserId = u.Id AND a.PostTypeId = 2) AS AnswerCount
  FROM Users u
  WHERE u.Reputation > 1000
),
TagActivity AS (
  SELECT
    t.TagName,
    COUNT(*) AS TagQuestionCount,
    AVG(p.ViewCount) AS AvgViewsPerQuestion,
    MAX(p.Score) AS MaxScore
  FROM Posts p
  CROSS APPLY (SELECT value AS TagName FROM string_split(p.Tags, '>')) AS st
  CROSS APPLY (VALUES (REPLACE(REPLACE(st.TagName, '<', ''), '>', ''))) AS t2(TagName)
  JOIN Tags tg ON tg.TagName = t2.TagName
  GROUP BY t.TagName
),
ComplexBenchmark AS (
  SELECT
    ro.Id AS PostId,
    ro.Title,
    ro.CreationDate,
    ro.LastEditDate,
    ro.OwnerUserId,
    ro.Tags,
    COALESCE(vc.BountyAmount, 0) AS Bounty,
    vc.CreationDate AS BountyDate,
    vtn.VoteCount
  FROM Posts ro
  LEFT JOIN Votes v ON v.PostId = ro.Id AND v.VoteTypeId = 2
  LEFT JOIN Votes v2 ON v2.PostId = ro.Id AND v2.VoteTypeId = 3
  LEFT JOIN (
    SELECT PostId, MAX(CreationDate) AS CreationDate, SUM(BountyAmount) AS BountyAmount
    FROM Votes
    GROUP BY PostId
  ) vc ON vc.PostId = ro.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS VoteCount
    FROM Votes
    GROUP BY PostId
  ) vtn ON vtn.PostId = ro.Id
  WHERE ro.PostTypeId IN (1,2)
)
SELECT
  -- Outer join example: combine top contributors with their most viewed questions
  t.UserId,
  t.DisplayName,
  t.Reputation,
  t.QuestionCount,
  t.AnswerCount,
  rcp.PostId AS MostViewedQuestionId,
  rcp.Title AS MostViewedQuestionTitle,
  rcp.ViewCount AS MostViewedQuestionViews,
  rcp.CreationDate AS MostViewedQuestionDate,
  -- Window function on recent top questions per user
  q.PostId AS QPostId,
  q.Title AS QTitle,
  q.ViewCount AS QViews,
  q.CreationDate AS QCreationDate,
  q.rn AS RankForUser,
  -- Tag activity metrics
  ta.TagName,
  ta.TagQuestionCount,
  ta.AvgViewsPerQuestion,
  ta.MaxScore,
  -- Complex benchmark fields
  cb.PostId AS BenchmarkPostId,
  cb.Title AS BenchmarkPostTitle,
  cb.Bounty,
  cb.BountyDate,
  cb.VoteCount
FROM TopContributors t
LEFT JOIN (
  SELECT
    p.OwnerUserId,
    p.Id AS PostId,
    p.Title,
    p.ViewCount,
    p.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount DESC, p.CreationDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
) q ON q.OwnerUserId = t.UserId
LEFT JOIN (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId
  FROM Posts p
  ORDER BY p.ViewCount DESC
  LIMIT 1
) rcp ON rcp.OwnerUserId = t.UserId
LEFT JOIN TagActivity ta ON 1=1
LEFT JOIN ComplexBenchmark cb ON cb.PostId = rcp.PostId
ORDER BY t.Reputation DESC, t.UserId
LIMIT 100;