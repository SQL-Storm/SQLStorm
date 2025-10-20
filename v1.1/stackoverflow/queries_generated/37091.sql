-- {"query": "37091.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2147} 
WITH
-- recent active questions with tag arrays and basic metrics
Questions AS (
  SELECT p.Id, p.CreationDate, p.Title, p.OwnerUserId, p.Score, p.ViewCount,
         COALESCE(p.AnswerCount,0) AS AnswerCount,
         COALESCE(p.CommentCount,0) AS CommentCount,
         COALESCE(p.FavoriteCount,0) AS FavoriteCount,
         CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::varchar[] 
              ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END AS Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - INTERVAL '2 years'
),
-- top answerers: answers in the same period with aggregated stats
AnswersAgg AS (
  SELECT a.ParentId AS QuestionId,
         COUNT(*) FILTER (WHERE a.Score >= 0) AS PosAnswers,
         COUNT(*) FILTER (WHERE a.Score < 0) AS NegAnswers,
         SUM(a.Score) AS TotalAnswerScore,
         MAX(a.Score) AS MaxAnswerScore,
         MIN(a.Score) AS MinAnswerScore,
         AVG(a.Score) AS AvgAnswerScore,
         COUNT(*) AS AnswerRows
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.CreationDate >= now() - INTERVAL '2 years'
  GROUP BY a.ParentId
),
-- compute recent close/reopen/edit events per question from PostHistory
HistoryEvents AS (
  SELECT ph.PostId,
         MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate END) AS LastCloseDate,
         MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate END) AS LastReopenDate,
         MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6,24) THEN ph.CreationDate END) AS LastEditDate,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseVotesRecorded,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS EditCount
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
    AND ph.CreationDate >= now() - INTERVAL '2 years'
  GROUP BY ph.PostId
),
-- compute tag popularity and co-tag matrix partials
TagExplode AS (
  SELECT q.Id AS QuestionId, un.tag AS Tag
  FROM Questions q
  CROSS JOIN LATERAL unnest(q.Tags) AS un(tag)
),
TagStats AS (
  SELECT t.Tag,
         COUNT(*) AS QuestionsWithTag,
         AVG(q.ViewCount) AS AvgViews,
         AVG(q.Score) AS AvgScore,
         SUM(CASE WHEN q.AnswerCount = 0 THEN 1 ELSE 0 END) AS UnansweredCount
  FROM TagExplode t
  JOIN Questions q ON q.Id = t.QuestionId
  GROUP BY t.Tag
),
-- co-tag counts for top N tags to limit skew
TopTags AS (
  SELECT Tag FROM TagStats
  ORDER BY QuestionsWithTag DESC
  LIMIT 50
),
CoTags AS (
  SELECT a.Tag AS TagA, b.Tag AS TagB, COUNT(*) AS CoCount
  FROM TagExplode a
  JOIN TagExplode b ON a.QuestionId = b.QuestionId AND a.Tag < b.Tag
  WHERE a.Tag IN (SELECT Tag FROM TopTags) AND b.Tag IN (SELECT Tag FROM TopTags)
  GROUP BY a.Tag, b.Tag
),
-- compute user-level engagement: badges, votes, posts
UserActivity AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= now()-INTERVAL '2 years') AS QuestionsAsked,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= now()-INTERVAL '2 years') AS AnswersPosted,
         COUNT(b.Id) FILTER (WHERE b.Date >= now()-INTERVAL '2 years') AS RecentBadges,
         SUM(v.BountyAmount) FILTER (WHERE v.BountyAmount IS NOT NULL) AS BountyGiven,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2 AND v.CreationDate >= now()-INTERVAL '2 years') AS UpvotesCast
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.Reputation, u.CreationDate
),
-- identify high-impact questions combining metrics and normalized scores
ScoredQuestions AS (
  SELECT q.*,
         COALESCE(ha.LastCloseDate, to_timestamp(0)) AS LastCloseDate,
         COALESCE(ha.LastReopenDate, to_timestamp(0)) AS LastReopenDate,
         COALESCE(ha.EditCount,0) AS EditCount,
         COALESCE(aa.AnswerRows,0) AS RecentAnswers,
         COALESCE(aa.TotalAnswerScore,0) AS RecentAnswerScore,
         ( (q.ViewCount::numeric / NULLIF((SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ViewCount) FROM Posts WHERE PostTypeId=1 AND CreationDate >= now()-INTERVAL '2 years'),0))
           + (q.Score::numeric / NULLIF((SELECT NULLIF(AVG(Score),0) FROM Posts WHERE PostTypeId=1 AND CreationDate >= now()-INTERVAL '2 years'),1))
           + (GREATEST(q.AnswerCount,1)::numeric / NULLIF((SELECT NULLIF(AVG(AnswerCount),0) FROM Posts WHERE PostTypeId=1 AND CreationDate >= now()-INTERVAL '2 years'),1))
           + (COALESCE(aa.TotalAnswerScore,0)::numeric / NULLIF((SELECT GREATEST(AVG(score),1) FROM Posts WHERE PostTypeId=2 AND CreationDate >= now()-INTERVAL '2 years'),1))
         ) AS CompositeSignal
  FROM Questions q
  LEFT JOIN HistoryEvents ha ON ha.PostId = q.Id
  LEFT JOIN AnswersAgg aa ON aa.QuestionId = q.Id
),
-- pick a challenging sample: top 200 by composite but include long-tail randomization
SampledQuestions AS (
  SELECT sq.*,
         ROW_NUMBER() OVER (ORDER BY sq.CompositeSignal DESC) AS rn,
         random() AS rnd
  FROM ScoredQuestions sq
),
FinalSample AS (
  SELECT * FROM SampledQuestions
  WHERE rn <= 150
  UNION ALL
  SELECT * FROM SampledQuestions
  WHERE rn > 150 AND rnd > 0.999
  ORDER BY CompositeSignal DESC
  LIMIT 200
)
-- final heavy query: aggregate per-sample question with joins to gather diverse data for benchmarking
SELECT fs.Id AS QuestionId,
       fs.Title,
       fs.CreationDate,
       fs.Score AS QuestionScore,
       fs.ViewCount,
       fs.AnswerCount,
       fs.CommentCount,
       fs.FavoriteCount,
       fs.CompositeSignal,
       fs.EditCount,
       fs.RecentAnswers,
       fs.RecentAnswerScore,
       u.Id AS OwnerUserId,
       u.DisplayName AS OwnerName,
       ua.QuestionsAsked,
       ua.AnswersPosted,
       ua.RecentBadges,
       ts.Tag,
       ts.QuestionsWithTag,
       ts.AvgViews AS TagAvgViews,
       ts.AvgScore AS TagAvgScore,
       ts.UnansweredCount AS TagUnanswered,
       ct.CoCount AS CoTagCount,
       ph.LastEditDate,
       ph.CloseVotesRecorded,
       (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fs.Id) AS TotalComments,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fs.Id AND v.VoteTypeId = 2) AS UpvoteCount,
       (SELECT COUNT(*) FROM Votes v WHERE v.PostId = fs.Id AND v.VoteTypeId = 3) AS DownvoteCount,
       (SELECT COUNT(*) FROM Posts p WHERE p.ParentId = fs.Id AND p.Score >= 5) AS HighScoringAnswers,
       (SELECT json_agg(json_build_object('AnswerId', a.Id, 'Score', a.Score, 'OwnerUserId', a.OwnerUserId, 'CreationDate', a.CreationDate) ORDER BY a.Score DESC NULLS LAST LIMIT 5)
         FROM Posts a WHERE a.ParentId = fs.Id AND a.PostTypeId = 2) AS Top5Answers,
       (SELECT json_agg(json_build_object('HistType', ph2.PostHistoryTypeId, 'When', ph2.CreationDate, 'UserId', ph2.UserId) ORDER BY ph2.CreationDate DESC LIMIT 10)
         FROM PostHistory ph2 WHERE ph2.PostId = fs.Id) AS RecentHistory
FROM FinalSample fs
LEFT JOIN Users u ON u.Id = fs.OwnerUserId
LEFT JOIN UserActivity ua ON ua.UserId = u.Id
LEFT JOIN TagExplode te ON te.QuestionId = fs.Id
LEFT JOIN TagStats ts ON ts.Tag = te.Tag
LEFT JOIN CoTags ct ON ct.TagA = ts.Tag
LEFT JOIN PostHistory ph ON ph.PostId = fs.Id
GROUP BY fs.Id, fs.Title, fs.CreationDate, fs.Score, fs.ViewCount, fs.AnswerCount, fs.CommentCount, fs.FavoriteCount, fs.CompositeSignal, fs.EditCount, fs.RecentAnswers, fs.RecentAnswerScore, u.Id, u.DisplayName, ua.QuestionsAsked, ua.AnswersPosted, ua.RecentBadges, ts.Tag, ts.QuestionsWithTag, ts.AvgViews, ts.AvgScore, ts.UnansweredCount, ct.CoCount, ph.LastEditDate, ph.CloseVotesRecorded
ORDER BY fs.CompositeSignal DESC, fs.ViewCount DESC
LIMIT 200;