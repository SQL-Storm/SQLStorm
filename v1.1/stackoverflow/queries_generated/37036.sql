-- {"query": "37036.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1923} 
WITH
-- recent active questions with tag arrays and owner info
Questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.Tags,
         u.Id AS OwnerId, u.DisplayName AS OwnerName, u.Reputation AS OwnerReputation,
         regexp_split_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') AS TagArray
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (current_timestamp - interval '2 years')
),
-- compute per-question aggregate metrics: top answer score, number of distinct commenters, number of edits
AnswerAgg AS (
  SELECT q.Id AS QuestionId,
         COALESCE(MAX(a.Score), 0) FILTER (WHERE a.PostTypeId = 2) AS TopAnswerScore,
         COUNT(DISTINCT c.UserId) FILTER (WHERE c.Id IS NOT NULL) AS DistinctCommenters,
         COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS EditCount
  FROM Questions q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN PostHistory ph ON ph.PostId = q.Id
  GROUP BY q.Id
),
-- tag-centric aggregates over the selected questions
TagExplode AS (
  SELECT q.*, unnest(q.TagArray) AS Tag
  FROM Questions q
),
TagStats AS (
  SELECT t.Tag,
         COUNT(*) AS QuestionsWithTag,
         AVG(q.Score) AS AvgQuestionScore,
         SUM(q.ViewCount) AS TotalViews,
         SUM(COALESCE(aa.TopAnswerScore,0)) AS SumTopAnswerScores,
         COUNT(DISTINCT q.OwnerId) AS DistinctAskers
  FROM TagExplode q
  LEFT JOIN AnswerAgg aa ON aa.QuestionId = q.Id
  GROUP BY t := (Tag)
),
-- user reputation trajectory: first and last activity in the window and badge counts
UserActivity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         MIN(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS FirstPostDate,
         MAX(p.LastActivityDate) AS LastActivityDate,
         u.Reputation,
         COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
         COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
         COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.CreationDate >= (current_timestamp - interval '2 years')
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= (current_timestamp - interval '2 years')
  WHERE u.CreationDate <= current_timestamp
  GROUP BY u.Id, u.DisplayName, u.Reputation
  HAVING COUNT(p.Id) > 0
),
-- compute influential questions: score * log(views+1) * sqrt(answercount+1) adjusted by owner reputation
InfluentialQuestions AS (
  SELECT q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount,
         qa.TopAnswerScore, qa.DistinctCommenters, qa.EditCount,
         q.OwnerId, q.OwnerName, q.OwnerReputation,
         (q.Score::double precision * ln(greatest(q.ViewCount,1)+1) * sqrt(greatest(q.AnswerCount,0)+1)
           + COALESCE(qa.TopAnswerScore,0) * 2
           + (COALESCE(qa.DistinctCommenters,0) * 1.5)
           - (COALESCE(qa.EditCount,0) * 0.5)
         ) * (1 + least(q.OwnerReputation/10000.0, 1)) AS InfluenceScore
  FROM Questions q
  LEFT JOIN AnswerAgg qa ON qa.QuestionId = q.Id
),
-- identify top tags by combined influence of questions bearing them
TagInfluence AS (
  SELECT te.Tag,
         COUNT(*) AS QuestionCount,
         SUM(i.InfluenceScore) AS TagInfluenceScore,
         AVG(i.InfluenceScore) AS AvgInfluencePerQuestion
  FROM TagExplode te
  JOIN InfluentialQuestions i ON i.Id = te.Id
  GROUP BY te.Tag
),
-- recent links and duplicates network analysis: for questions linked as duplicates or linked posts
LinkNetwork AS (
  SELECT pl.PostId AS SourceId, pl.RelatedPostId AS TargetId, lt.Name AS LinkTypeName, pl.CreationDate
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  WHERE pl.CreationDate >= (current_timestamp - interval '2 years')
),
 -- compute for each question: in-degree (linked-to), out-degree (links to), and duplicate flags
LinkAgg AS (
  SELECT q.Id,
         SUM(CASE WHEN ln.TargetId = q.Id THEN 1 ELSE 0 END) AS InboundLinks,
         SUM(CASE WHEN ln.SourceId = q.Id THEN 1 ELSE 0 END) AS OutboundLinks,
         SUM(CASE WHEN ln.LinkTypeName = 'Duplicate' AND ln.TargetId = q.Id THEN 1 ELSE 0 END) AS DuplicateCountAsTarget
  FROM Questions q
  LEFT JOIN LinkNetwork ln ON ln.SourceId = q.Id OR ln.TargetId = q.Id
  GROUP BY q.Id
),
-- final ranking windows: combine influence, tag importance, link centrality and recent activity
FinalRanking AS (
  SELECT i.*,
         COALESCE(la.InboundLinks,0) AS InboundLinks,
         COALESCE(la.OutboundLinks,0) AS OutboundLinks,
         COALESCE(la.DuplicateCountAsTarget,0) AS DuplicateCountAsTarget,
         (i.InfluenceScore * (1 + ln.coalesce_tag_boost)) AS AdjustedInfluence,
         row_number() OVER (ORDER BY (i.InfluenceScore * (1 + ln.coalesce_tag_boost)) DESC) AS RankByAdjustedInfluence
  FROM InfluentialQuestions i
  LEFT JOIN LinkAgg la ON la.Id = i.Id
  LEFT JOIN (
    -- compute a per-question tag-based boost: sum of tag normalized influence ranks for that question's tags
    SELECT q.Id,
           SUM(COALESCE(ti.TagInfluenceScore,0)) / NULLIF(MAX(ti.QuestionCount),0) * 0.0001 AS coalesce_tag_boost
    FROM TagExplode q
    LEFT JOIN TagInfluence ti ON ti.Tag = q.Tag
    GROUP BY q.Id
  ) ln ON ln.Id = i.Id
)
SELECT
  f.RankByAdjustedInfluence,
  f.Id AS QuestionId,
  f.Title,
  f.CreationDate,
  f.Score,
  f.ViewCount,
  f.AnswerCount,
  ROUND(f.InfluenceScore::numeric,4) AS InfluenceScore,
  ROUND(f.AdjustedInfluence::numeric,4) AS AdjustedInfluence,
  f.TopAnswerScore,
  f.DistinctCommenters,
  f.EditCount,
  f.OwnerId,
  f.OwnerName,
  f.OwnerReputation,
  f.InboundLinks,
  f.OutboundLinks,
  f.DuplicateCountAsTarget,
  array_agg(DISTINCT te.Tag) FILTER (WHERE te.Tag IS NOT NULL) AS Tags,
  (SELECT array_agg(ti.Tag ORDER BY ti.TagInfluenceScore DESC LIMIT 3) FROM TagExplode te2 JOIN TagInfluence ti ON ti.Tag = te2.Tag WHERE te2.Id = f.Id) AS Top3TagsByTagInfluence,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.Id AND v.VoteTypeId = 2) AS UpvoteCount,
  (SELECT COUNT(*) FROM Votes v WHERE v.PostId = f.Id AND v.VoteTypeId = 3) AS DownvoteCount
FROM FinalRanking f
LEFT JOIN TagExplode te ON te.Id = f.Id
GROUP BY f.RankByAdjustedInfluence, f.Id, f.Title, f.CreationDate, f.Score, f.ViewCount, f.AnswerCount,
         f.InfluenceScore, f.AdjustedInfluence, f.TopAnswerScore, f.DistinctCommenters, f.EditCount,
         f.OwnerId, f.OwnerName, f.OwnerReputation, f.InboundLinks, f.OutboundLinks, f.DuplicateCountAsTarget
ORDER BY f.RankByAdjustedInfluence
LIMIT 200;