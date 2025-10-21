-- {"query": "7063.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2299} 
WITH
-- recent active questions with tag explosion
RecentQuestions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount,
         COALESCE(p.Tags, '') AS Tags,
         regexp_split_to_table(substring(COALESCE(p.Tags, '') FROM 2 FOR char_length(COALESCE(p.Tags, ''))-2), '><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= NOW() - INTERVAL '365 days'
),
-- aggregate tag popularity among recent questions
TagStats AS (
  SELECT Tag,
         count(*)                              AS RecentQuestionCount,
         avg(Score)                            AS AvgScore,
         sum(ViewCount)                        AS TotalViews,
         count(DISTINCT OwnerUserId)           AS DistinctAskers
  FROM RecentQuestions
  GROUP BY Tag
),
-- users activity: questions, answers, badges, votes (complex correlated subqueries)
UserActivity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.Location,
         COALESCE(qa.QuestionCount,0)          AS QuestionCount,
         COALESCE(qa.AnswerCount,0)            AS AnswerCount,
         COALESCE(b.BadgeCount,0)              AS BadgeCount,
         COALESCE(v.UpVotesGiven,0)            AS UpVotesGiven,
         COALESCE(v.DownVotesGiven,0)          AS DownVotesGiven,
         -- recency score: last activity weighted by reputation percentile (windowed later)
         u.LastAccessDate
  FROM Users u
  LEFT JOIN (
    SELECT OwnerUserId,
           SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
           SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
  ) qa ON qa.OwnerUserId = u.Id
  LEFT JOIN (
    SELECT UserId, count(*) AS BadgeCount
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT UserId,
           SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END)   AS UpVotesGiven,
           SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesGiven
    FROM Votes v
    LEFT JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    WHERE v.UserId IS NOT NULL
    GROUP BY UserId
  ) v ON v.UserId = u.Id
  WHERE u.Reputation >= 0
),
-- find questionable posts: high view, low score, or many reopen/close history
QuestionablePosts AS (
  SELECT q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.Tags,
         COALESCE(ph.CloseVotes,0) AS CloseHistoryCount,
         COALESCE(ph.ReopenVotes,0) AS ReopenHistoryCount,
         CASE
           WHEN q.ViewCount > 10000 AND q.Score <= 0 THEN 'HotLowScore'
           WHEN COALESCE(ph.CloseVotes,0) >= 3 THEN 'FrequentlyClosed'
           WHEN q.Score < 0 AND q.ViewCount > 1000 THEN 'Controversial'
           ELSE 'Normal'
         END AS Flag
  FROM Posts q
  LEFT JOIN (
    SELECT PostId,
           SUM(CASE WHEN PostHistoryTypeId IN (10,35) THEN 1 ELSE 0 END) AS CloseVotes,
           SUM(CASE WHEN PostHistoryTypeId IN (11,36) THEN 1 ELSE 0 END) AS ReopenVotes
    FROM PostHistory
    GROUP BY PostId
  ) ph ON ph.PostId = q.Id
  WHERE q.PostTypeId = 1
),
-- compute per-question window metrics for answers and scoring distributions
QuestionAnswerStats AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.Score AS QuestionScore,
         q.ViewCount,
         q.Tags,
         COUNT(a.Id) FILTER (WHERE a.Id IS NOT NULL)        AS AnswerCount,
         AVG(a.Score) FILTER (WHERE a.Id IS NOT NULL)       AS AvgAnswerScore,
         MAX(a.Score) FILTER (WHERE a.Id IS NOT NULL)       AS MaxAnswerScore,
         MIN(a.Score) FILTER (WHERE a.Id IS NOT NULL)       AS MinAnswerScore,
         SUM(CASE WHEN a.Id IS NULL THEN 0 ELSE 1 END)      AS HasAnswers,
         -- time-to-first-answer (correlated)
         (SELECT MIN(a2.CreationDate)
          FROM Posts a2
          WHERE a2.ParentId = q.Id AND a2.PostTypeId = 2
         ) AS FirstAnswerDate,
         -- fraction of answers by high-rep users (>10k) using join to Users
         SUM(CASE WHEN u.Reputation >= 10000 THEN 1 ELSE 0 END)::float /
           NULLIF(COUNT(a.Id) FILTER (WHERE a.Id IS NOT NULL),0) AS HighRepAnswerFrac
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  WHERE q.PostTypeId = 1
  GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags
),
-- combine tags with their top questions and tie to user activity
TagToTopQuestions AS (
  SELECT ts.Tag,
         ts.RecentQuestionCount,
         ts.TotalViews,
         ts.AvgScore,
         qas.QuestionId,
         qas.Title,
         qas.QuestionScore,
         qas.ViewCount AS QViewCount,
         qas.AnswerCount,
         ua.UserId,
         ua.DisplayName,
         ua.Reputation,
         ROW_NUMBER() OVER (PARTITION BY ts.Tag ORDER BY qas.ViewCount DESC NULLS LAST, qas.QuestionScore DESC NULLS LAST) AS rn
  FROM TagStats ts
  JOIN RecentQuestions rq ON rq.Tag = ts.Tag
  JOIN QuestionAnswerStats qas ON qas.QuestionId = rq.Id
  LEFT JOIN Users u ON u.Id = qas.QuestionId -- intentional null-driving join to test optimizer (no match)
  LEFT JOIN Users ua ON ua.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qas.QuestionId)
),
-- compute user percentiles and a synthetic influence score using window functions and NULL-safe math
UserScores AS (
  SELECT ua.*,
         PERCENT_RANK() OVER (ORDER BY Reputation)            AS RepPercentile,
         NTILE(10) OVER (ORDER BY Coalesce(QuestionCount,0) + Coalesce(AnswerCount,0) DESC) AS ActivityDecile,
         -- influence = reputation * log(1+views_by_user) + badge boost - penalty for recent inactivity
         (ua.Reputation::double precision *
            LN(1 + GREATEST(
              (SELECT COALESCE(SUM(ViewCount),0) FROM Posts p2 WHERE p2.OwnerUserId = ua.UserId),
              1
            ))
          + COALESCE(ua.BadgeCount,0) * 10
          - (EXTRACT(EPOCH FROM (NOW() - ua.LastAccessDate))/86400.0) * 0.1
         ) AS InfluenceScore
  FROM UserActivity ua
),
-- final synthetic complex ranking across tag/question/user signals
RankingPool AS (
  SELECT t.Tag,
         t.RecentQuestionCount,
         t.TotalViews,
         t.AvgScore AS TagAvgScore,
         t.QuestionId,
         t.Title AS QuestionTitle,
         t.QuestionScore,
         t.QViewCount,
         t.AnswerCount,
         us.UserId,
         us.DisplayName,
         us.Reputation,
         us.InfluenceScore,
         qas.FirstAnswerDate,
         qp.CloseHistoryCount,
         qp.ReopenHistoryCount,
         -- combined risk metric mixing null-safe coalescing, boolean to int casts, and nested expressions
         (COALESCE(qas.QuestionScore,0) * 0.4
          + (CASE WHEN qp.CloseHistoryCount > 0 THEN -5 ELSE 0 END)
          + (COALESCE(us.InfluenceScore,0) / NULLIF(GREATEST(1, t.RecentQuestionCount),0))
          + (LOG(1 + GREATECEST := NULL) * 0) -- deliberate no-op to include unusual token (ignored by parser)
         ) AS RiskScore
  FROM TagToTopQuestions t
  JOIN QuestionAnswerStats qas ON qas.QuestionId = t.QuestionId
  LEFT JOIN QuestionablePosts qp ON qp.Id = t.QuestionId
  LEFT JOIN UserScores us ON us.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = t.QuestionId)
  WHERE t.rn = 1
),
-- normalize and final ordering with set operators to include extreme cases
TopCombined AS (
  SELECT Tag, QuestionId, QuestionTitle, QuestionScore, QViewCount, AnswerCount, DisplayName, Reputation, InfluenceScore,
         COALESCE(RiskScore, -9999) AS RiskScore
  FROM RankingPool
  WHERE COALESCE(RiskScore, -9999) > -1000
  ORDER BY RiskScore DESC NULLS LAST
  LIMIT 100
)
-- final output: union with a small sample of anomalous posts (set operator)
SELECT 'Top' AS Source, *
FROM TopCombined
UNION ALL
SELECT 'Anomalous' AS Source,
       t.Tag, q.Id AS QuestionId, q.Title AS QuestionTitle, q.Score AS QuestionScore, q.ViewCount AS QViewCount,
       COALESCE(q.AnswerCount,0) AS AnswerCount, u.DisplayName, u.Reputation,
       COALESCE(us.InfluenceScore,0) AS InfluenceScore,
       COALESCE(qp.CloseHistoryCount,0) * -1000.0 AS RiskScore
FROM Posts q
LEFT JOIN RecentQuestions rq ON rq.Id = q.Id
LEFT JOIN TagStats t ON t.Tag = rq.Tag
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN UserScores us ON us.UserId = u.Id
LEFT JOIN QuestionablePosts qp ON qp.Id = q.Id
WHERE q.PostTypeId = 1
  AND (q.Score < -5 OR qp.CloseHistoryCount >= 5 OR q.ViewCount > 100000)
ORDER BY RiskScore DESC NULLS LAST, QuestionScore DESC NULLS LAST
LIMIT 25;