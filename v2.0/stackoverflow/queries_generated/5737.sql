-- {"query": "5737.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 590} 
WITH
RecentActivePosts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC) AS rn
  FROM Posts p
  WHERE p.LastActivityDate IS NOT NULL
),
TopQuestions AS (
  SELECT
    rap.Id AS QuestionId,
    rap.Title,
    rap.OwnerUserId,
    rap.CreationDate,
    rap.LastActivityDate,
    rap.Score,
    rap.ViewCount,
    rap.Tags,
    COALESCE(sqrt(ABS(rap.Score)) * 1.5, 0) +
      (SELECT AVG(vt.BountyAmount) FROM Votes vt WHERE vt.PostId = rap.Id AND vt.VoteTypeId = 8) AS QualityScore
  FROM RecentActivePosts rap
  WHERE rap.PostTypeId = 1 -- Questions
    AND rap.rn <= 50
),
TopTags AS (
  SELECT
    t.TagName,
    t.Count,
    t.ExcerptPostId,
    t.WikiPostId
  FROM Tags t
  WHERE t.Count > 100
),
TagEngagement AS (
  SELECT
    tt.TagName,
    COUNT(*) AS QuestionCount,
    AVG(p.Score) AS AvgQuestionScore,
    SUM(CASE WHEN p.ViewCount > 1000 THEN 1 ELSE 0 END) AS HighViewQuestions
  FROM TopQuestions q
  JOIN UNNEST(string_to_array(q.Tags, '><')) AS t(TagName) ON true
  GROUP BY tt.TagName
)
SELECT
  q.QuestionId,
  q.Title AS QuestionTitle,
  u.DisplayName AS OwnerName,
  q.CreationDate,
  q.LastActivityDate,
  q.Score AS QuestionScore,
  q.ViewCount AS Views,
  q.Tags,
  (SELECT STRING_AGG(CASE WHEN v.VoteTypeId = 2 THEN 'Up' WHEN v.VoteTypeId = 3 THEN 'Down' END, ',')
   FROM Votes v WHERE v.PostId = q.QuestionId) AS VoteSummary,
  CASE
    WHEN q.Score > 0 THEN 'Positive'
    WHEN q.Score = 0 THEN 'Neutral'
    ELSE 'Negative'
  END AS ScoreTone,
  ta.QuestionCount,
  ta.AvgQuestionScore,
  ta.HighViewQuestions
FROM TopQuestions q
LEFT JOIN Users u ON q.OwnerUserId = u.Id
LEFT JOIN TagEngagement ta ON TRUE
WHERE q.QuestionId IN (SELECT QuestionId FROM TopQuestions)
ORDER BY q.LastActivityDate DESC, q.Score DESC
LIMIT 100;