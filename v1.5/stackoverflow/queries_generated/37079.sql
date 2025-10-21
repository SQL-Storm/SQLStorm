-- {"query": "37079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2651} 
WITH
-- compute tag expansion and normalize tag strings to one tag per row
QuestionTags AS (
  SELECT p.Id AS QuestionId,
         trim(both '<>' FROM unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
-- recent activity window
RecentQuestions AS (
  SELECT q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AnswerCount, q.CommentCount, q.FavoriteCount
  FROM Posts q
  WHERE q.PostTypeId = 1
    AND q.CreationDate >= now() - interval '2 years'
),
-- answers with computed acceptance and age
AnswerStats AS (
  SELECT a.ParentId AS QuestionId,
         count(*) FILTER (WHERE a.Id <> q.AcceptedAnswerId) AS OtherAnswerCount,
         count(*) FILTER (WHERE a.Id = q.AcceptedAnswerId) AS IsAcceptedCount,
         avg(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) FILTER (WHERE a.CreationDate IS NOT NULL AND q.CreationDate IS NOT NULL) AS AvgAnswerDelaySeconds,
         max(a.Score) AS MaxAnswerScore,
         sum(CASE WHEN a.Score >= 10 THEN 1 ELSE 0 END) AS HighScoreAnswerCount
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
    AND q.CreationDate >= now() - interval '2 years'
  GROUP BY a.ParentId
),
-- user reputation and activity summary (recent two years)
UserActivity AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         count(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= now() - interval '2 years') AS QuestionsPosted,
         count(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= now() - interval '2 years') AS AnswersPosted,
         count(DISTINCT c.Id) FILTER (WHERE c.CreationDate >= now() - interval '2 years') AS CommentsMade,
         count(DISTINCT b.Id) FILTER (WHERE b.Date >= now() - interval '2 years') AS BadgesEarned
  FROM Users u
  LEFT JOIN Posts p ON (p.OwnerUserId = u.Id)
  LEFT JOIN Comments c ON (c.UserId = u.Id)
  LEFT JOIN Badges b ON (b.UserId = u.Id)
  GROUP BY u.Id, u.Reputation
),
-- tag popularity and median metrics by tag
TagAgg AS (
  SELECT qt.Tag,
         count(DISTINCT q.Id) AS QuestionCount,
         avg(q.Score) AS AvgQuestionScore,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY q.ViewCount) AS MedianViews,
         avg(EXTRACT(EPOCH FROM (now() - q.CreationDate)))/86400.0 AS AvgAgeDays
  FROM QuestionTags qt
  JOIN RecentQuestions q ON q.Id = qt.QuestionId
  GROUP BY qt.Tag
),
-- tag co-occurrence network: for each tag pair compute joint question count and Jaccard-like measure
TagPairs AS (
  SELECT t1.Tag AS TagA, t2.Tag AS TagB,
         count(DISTINCT t1.QuestionId) FILTER (WHERE t1.QuestionId = t2.QuestionId) AS CoQuestionCount
  FROM QuestionTags t1
  JOIN QuestionTags t2 ON t1.QuestionId = t2.QuestionId AND t1.Tag < t2.Tag
  GROUP BY t1.Tag, t2.Tag
),
-- compute tag-to-tag normalized association score
TagAssoc AS (
  SELECT tp.TagA, tp.TagB, tp.CoQuestionCount,
         tp.CoQuestionCount::double precision / GREATEST(1, LEAST( (SELECT QuestionCount FROM TagAgg WHERE Tag = tp.TagA),
                                                                        (SELECT QuestionCount FROM TagAgg WHERE Tag = tp.TagB) )) AS AssociationStrength
  FROM TagPairs tp
),
-- heavy query and view hotness combining many signals
QuestionSignal AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.AnswerCount,
         q.FavoriteCount,
         q.CommentCount,
         ua.Reputation AS OwnerReputation,
         ua.QuestionsPosted,
         ua.AnswersPosted,
         ua.BadgesEarned,
         asg.OtherAnswerCount,
         asg.IsAcceptedCount,
         asg.AvgAnswerDelaySeconds,
         tg.Tag,
         tagAgg.QuestionCount AS TagPopularity,
         tagAgg.MedianViews AS TagMedianViews,
         tagAgg.AvgQuestionScore AS TagAvgScore,
         -- composite hotness score: recency, score, views, answers, favorites, owner rep, tag popularity, accepted answer speed
         (
           -- recency decay: more recent -> higher
           (1.0 / (1.0 + EXTRACT(EPOCH FROM (now() - q.CreationDate))/86400.0/14.0))
           * 0.25
           +
           -- score and favorites
           ( (GREATEST(q.Score,0)::double precision / (1 + GREATEST(q.Score,0))) * 0.2 )
           +
           -- view influence (log-scaled)
           ( LN(1 + GREATEST(q.ViewCount,0)) / (1 + LN(1 + GREATEST(q.ViewCount,0))) * 0.15 )
           +
           -- answer activity (fewer answers + accepted => higher)
           ( (1.0 / (1.0 + COALESCE(asg.OtherAnswerCount,0))) * 0.12 )
           +
           -- favorites and comments
           ( (LN(1 + GREATEST(q.FavoriteCount,0) + GREATEST(q.CommentCount,0)) / (1 + LN(1 + GREATEST(q.FavoriteCount,0) + GREATEST(q.CommentCount,0)))) * 0.08 )
           +
           -- owner reputation influence
           ( (LN(1 + GREATEST(ua.Reputation,0))/ (1 + LN(1 + GREATEST(ua.Reputation,0)))) * 0.06 )
           +
           -- tag popularity dampening (rare tags get multiplier)
           ( (1.0 - (LEAST(tagAgg.QuestionCount::double precision, 1000) / 1000.0)) * 0.04 )
           +
           -- acceptance speed bonus (faster accepted answers -> higher)
           ( CASE WHEN asg.AvgAnswerDelaySeconds IS NOT NULL THEN (1.0 / (1.0 + asg.AvgAnswerDelaySeconds/3600.0/48.0)) * 0.1 ELSE 0 END )
         ) AS HotnessScore
  FROM RecentQuestions q
  LEFT JOIN QuestionTags tg ON tg.QuestionId = q.Id
  LEFT JOIN TagAgg tagAgg ON tagAgg.Tag = tg.Tag
  LEFT JOIN AnswerStats asg ON asg.QuestionId = q.Id
  LEFT JOIN UserActivity ua ON ua.UserId = q.OwnerUserId
),
-- rank questions within each tag and globally
RankedQuestions AS (
  SELECT qs.*,
         row_number() OVER (PARTITION BY qs.Tag ORDER BY qs.HotnessScore DESC NULLS LAST) AS TagRank,
         dense_rank() OVER (ORDER BY qs.HotnessScore DESC NULLS LAST) AS GlobalRank
  FROM QuestionSignal qs
),
-- pick top N per tag and also top global
TopPerTag AS (
  SELECT * FROM RankedQuestions WHERE TagRank <= 5
),
TopGlobal AS (
  SELECT * FROM RankedQuestions WHERE GlobalRank <= 200
),
-- assemble final candidate set with aggregated context: top answers, top comments, related tags and associations
TopCandidates AS (
  SELECT DISTINCT rq.QuestionId, rq.Title, rq.Tag, rq.HotnessScore, rq.TagRank, rq.GlobalRank
  FROM (
    SELECT * FROM TopPerTag
    UNION
    SELECT * FROM TopGlobal
  ) rq
),
-- fetch top answers per question (by score), limit 3
TopAnswers AS (
  SELECT a.ParentId AS QuestionId,
         json_agg(json_build_object('AnswerId', a.Id, 'Score', a.Score, 'CreationDate', a.CreationDate, 'OwnerUserId', a.OwnerUserId) ORDER BY a.Score DESC, a.CreationDate ASC) FILTER (WHERE a.Id IS NOT NULL) AS TopAnswers
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.ParentId IN (SELECT QuestionId FROM TopCandidates)
  GROUP BY a.ParentId
),
-- fetch recent top comments per question, limit 5
TopComments AS (
  SELECT c.PostId AS QuestionId,
         json_agg(json_build_object('CommentId', c.Id, 'Score', c.Score, 'Text', left(c.Text,200), 'CreationDate', c.CreationDate) ORDER BY c.Score DESC, c.CreationDate DESC) FILTER (WHERE c.Id IS NOT NULL) AS TopComments
  FROM Comments c
  WHERE c.PostId IN (SELECT QuestionId FROM TopCandidates)
  GROUP BY c.PostId
),
-- related tags: for each tag pick top 3 associated tags
RelatedTags AS (
  SELECT ta.TagA AS Tag, json_agg(json_build_object('RelatedTag', ta.TagB, 'CoCount', ta.CoQuestionCount, 'Strength', round(ta.AssociationStrength::numeric,4)) ORDER BY ta.AssociationStrength DESC, ta.CoQuestionCount DESC) FILTER (WHERE ta.TagB IS NOT NULL) AS Related
  FROM TagAssoc ta
  GROUP BY ta.TagA
),
-- final enrichment join
Final AS (
  SELECT tc.QuestionId,
         tc.Title,
         tc.Tag,
         tc.HotnessScore,
         tc.TagRank,
         tc.GlobalRank,
         ta.TopAnswers,
         tc2.TopComments,
         rt.Related AS RelatedTags,
         tg.QuestionCount AS TagQuestionCount,
         tg.TagMedianViews,
         tg.TagAvgScore
  FROM TopCandidates tc
  LEFT JOIN TopAnswers ta ON ta.QuestionId = tc.QuestionId
  LEFT JOIN TopComments tc2 ON tc2.QuestionId = tc.QuestionId
  LEFT JOIN RelatedTags rt ON rt.Tag = tc.Tag
  LEFT JOIN TagAgg tg ON tg.Tag = tc.Tag
)
-- final select: order by tag, then rank, include a synthetic computed complexity metric for benchmarking (heavy functions)
SELECT
  f.QuestionId,
  left(f.Title,200) AS Title,
  f.Tag,
  round(f.HotnessScore::numeric,6) AS HotnessScore,
  f.TagRank,
  f.GlobalRank,
  coalesce((f.TopAnswers->0->>'AnswerId')::int, NULL) AS TopAnswerId,
  (SELECT count(*) FROM regexp_split_to_table(coalesce((SELECT Body FROM Posts WHERE Id = f.QuestionId), ''), '\s+') ) AS ApproxWordCount,
  jsonb_build_object(
    'TopAnswers', f.TopAnswers,
    'TopComments', f.TopComments,
    'RelatedTags', f.RelatedTags,
    'TagStats', jsonb_build_object('QuestionCount', f.TagQuestionCount, 'MedianViews', f.TagMedianViews, 'AvgScore', f.TagAvgScore)
  ) AS Payload,
  -- synthetic complexity metric combining multiple aggregates and windowed analytics
  round( (
    f.HotnessScore * 1000
    + (SELECT coalesce(max(score),0) FROM Posts p WHERE p.ParentId = f.QuestionId)
    + (SELECT count(*) FROM Votes v WHERE v.PostId = f.QuestionId AND v.VoteTypeId = 2) * 0.5
    + (SELECT count(*) FROM PostLinks pl WHERE pl.PostId = f.QuestionId) * 0.2
    + (SELECT count(*) FROM PostHistory ph WHERE ph.PostId = f.QuestionId AND ph.PostHistoryTypeId IN (5,6,24)) * 0.1
  )::numeric,4) AS ComplexityScore
FROM Final f
ORDER BY f.Tag, f.TagRank, f.HotnessScore DESC
LIMIT 100;