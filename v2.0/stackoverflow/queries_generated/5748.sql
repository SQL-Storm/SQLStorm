-- {"query": "5748.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 902} 
WITH
TopQuestions AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.LastActivityDate,
    p.CommentCount,
    p.AnswerCount,
    p.FavoriteCount,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1 -- Questions
),
TagStats AS (
  SELECT
    t.TagName,
    COUNT(*) AS QuestionCount,
    SUM(q.Score) AS ScoreSum,
    AVG(q.Score) AS ScoreAvg,
    MAX(q.CreationDate) AS LastCreated
  FROM Tags t
  JOIN Posts q ON q.Tags LIKE '%' || t.TagName || '%' AND q.PostTypeId = 1
  GROUP BY t.TagName
),
RecentActivity AS (
  SELECT
    p.Id AS PostId,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    CASE
      WHEN p.ViewCount > 1000 THEN 'Popular'
      ELSE 'Regular'
    END AS ActivityBand,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.PostTypeId = 1
),
JoinedMetrics AS (
  SELECT
    tq.PostId,
    tq.Title,
    tq.OwnerDisplayName,
    tq.OwnerReputation,
    tq.CreationDate,
    tq.LastActivityDate,
    tq.ViewCount,
    COALESCE(bs.ScoreSum, 0) AS TagScoreSum,
    COALESCE(bs.QuestionCount, 0) AS TagQuestionCount,
    COALESCE(vt.UpVotes, 0) AS UpVotes,
    COALESCE(vt.DownVotes, 0) AS DownVotes
  FROM TopQuestions tq
  LEFT JOIN (
    SELECT
      t.TagName,
      COUNT(*) AS QuestionCount,
      SUM(p.Score) AS ScoreSum
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' || t.TagName || '%' AND p.PostTypeId = 1
    GROUP BY t.TagName
  ) bs ON 1 = 1
  LEFT JOIN (
    SELECT PostId, SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Votes
    GROUP BY PostId
  ) vt ON vt.PostId = tq.PostId
  WHERE 1=1
),
FinalPreview AS (
  SELECT
    jm.PostId,
    jm.Title,
    jm.OwnerDisplayName,
    jm.OwnerReputation,
    jm.CreationDate,
    jm.LastActivityDate,
    jm.ViewCount,
    jm.TagScoreSum,
    jm.TagQuestionCount,
    jm.UpVotes,
    jm.DownVotes,
    CONCAT('https://stackoverflow.example/post/', jm.PostId) AS Link,
    CONCAT(CASE WHEN jm.UpVotes >= jm.DownVotes THEN '↑' ELSE '↓' END, ' ', (jm.UpVotes - jm.DownVotes)) AS VoteDelta,
    CASE
      WHEN jm.TagQuestionCount > 0 THEN CONCAT('Top tag impact: ', (jm.TagScoreSum / NULLIF(jm.TagQuestionCount, 0)))
      ELSE 'No tag impact'
    END AS TagImpactMetric
  FROM JoinedMetrics jm
  ORDER BY jm.LastActivityDate DESC
  LIMIT 100
)
SELECT
  PostId,
  Title,
  OwnerDisplayName,
  OwnerReputation,
  CreationDate,
  LastActivityDate,
  ViewCount,
  TagScoreSum,
  TagQuestionCount,
  UpVotes,
  DownVotes,
  Link,
  VoteDelta,
  TagImpactMetric
FROM FinalPreview
WHERE LastActivityDate > NOW() - INTERVAL '90 days'
  AND ViewCount > 100
  AND (UpVotes - DownVotes) > 0
ORDER BY LastActivityDate DESC, ViewCount DESC
;