-- {"query": "37019.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2174} 
WITH
-- 1) recent active questions with parsed tags
Questions AS (
  SELECT p.Id, p.Title, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount,
         p.Tags,
         regexp_split_to_table(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= current_date - interval '2 years'
),
-- 2) aggregate answers stats per question
AnswerAgg AS (
  SELECT q.Id AS QuestionId,
         COUNT(a.Id) FILTER (WHERE a.Score >= 0) AS Answers_Positive,
         COUNT(a.Id) FILTER (WHERE a.Score < 0) AS Answers_Negative,
         AVG(a.Score) FILTER (WHERE a.Score IS NOT NULL) AS Avg_Answer_Score,
         MAX(a.Score) AS Max_Answer_Score,
         SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS Answered_By_Registered
  FROM Questions q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  GROUP BY q.Id
),
-- 3) recent comment dynamics per question (last 90 days)
CommentAgg AS (
  SELECT p.Id AS QuestionId,
         COUNT(c.Id) AS TotalComments_90d,
         COUNT(DISTINCT c.UserId) AS DistinctCommenters_90d,
         MAX(c.CreationDate) AS LastCommentDate_90d
  FROM Posts p
  LEFT JOIN Comments c ON c.PostId = p.Id AND c.CreationDate >= current_timestamp - interval '90 days'
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
-- 4) badge signals for askers (last year)
AskerBadges AS (
  SELECT u.Id AS UserId,
         COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges_Last,
         COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges_Last,
         COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges_Last,
         MAX(b.Date) AS LastBadgeDate
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id AND b.Date >= current_timestamp - interval '1 year'
  GROUP BY u.Id
),
-- 5) duplicate/linked relationships and reciprocal links
LinkAgg AS (
  SELECT pl.PostId AS QuestionId,
         COUNT(*) FILTER (WHERE lt.Name = 'Duplicate' OR lt.Name = 'Linked') AS OutgoingLinks,
         COUNT(*) FILTER (WHERE lt.Name = 'Duplicate' AND EXISTS (
             SELECT 1 FROM PostLinks pl2 WHERE pl2.PostId = pl.RelatedPostId AND pl2.RelatedPostId = pl.PostId AND pl2.LinkTypeId = pl.LinkTypeId
         )) AS ReciprocalLinks,
         COUNT(DISTINCT pl.RelatedPostId) AS DistinctRelated
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
-- 6) voting pressure and community attention
VoteAgg AS (
  SELECT p.Id AS QuestionId,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 1) AS AcceptedCount,
         COUNT(v.Id) FILTER (WHERE v.VoteTypeId IN (8,9)) AS BountyEvents,
         MAX(v.CreationDate) AS LastVoteDate
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
-- 7) historical edit velocity and rollback signals
HistoryAgg AS (
  SELECT ph.PostId AS QuestionId,
         COUNT(ph.Id) AS TotalRevisions,
         COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (5,8,24)) AS BodyEdits,
         COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (4,7)) AS TitleEdits,
         COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10,12,13)) AS ClosureRelated,
         MAX(ph.CreationDate) AS LastRevisionDate
  FROM PostHistory ph
  WHERE ph.PostId IS NOT NULL
  GROUP BY ph.PostId
),
-- 8) tag popularity and expert signal: tag-level aggregated metrics over the last 2 years
TagStats AS (
  SELECT t.TagName,
         COUNT(DISTINCT q.Id) FILTER (WHERE q.CreationDate >= current_date - interval '2 years') AS Questions_Last2y,
         AVG(q.Score) FILTER (WHERE q.Score IS NOT NULL) AS AvgQuestionScore,
         SUM(COALESCE(aAgg.Answers_Positive,0) + COALESCE(aAgg.Answers_Negative,0)) AS TotalAnswersForTag,
         COUNT(DISTINCT CASE WHEN q.OwnerUserId IS NOT NULL THEN q.OwnerUserId END) AS DistinctAskers
  FROM Tags t
  LEFT JOIN Questions q ON q.Tag = t.TagName
  LEFT JOIN AnswerAgg aAgg ON aAgg.QuestionId = q.Id
  GROUP BY t.TagName
),
-- 9) rank candidate questions by a composite score combining recency, activity, quality and friction
RankedQuestions AS (
  SELECT q.*,
         aa.Answers_Positive, aa.Answers_Negative, aa.Avg_Answer_Score, aa.Max_Answer_Score, aa.Answered_By_Registered,
         ca.TotalComments_90d, ca.DistinctCommenters_90d, ca.LastCommentDate_90d,
         va.UpVotes, va.DownVotes, va.AcceptedCount, va.BountyEvents, va.LastVoteDate,
         ha.TotalRevisions, ha.BodyEdits, ha.TitleEdits, ha.ClosureRelated, ha.LastRevisionDate,
         la.OutgoingLinks, la.ReciprocalLinks, la.DistinctRelated,
         ab.GoldBadges_Last, ab.SilverBadges_Last, ab.BronzeBadges_Last,
         ts.Questions_Last2y, ts.AvgQuestionScore AS TagAvgScore, ts.TotalAnswersForTag,
         -- composite scoring (arbitrary weights) to induce varied execution plans
         (
           (EXTRACT(epoch FROM (current_timestamp - q.CreationDate)) / 86400.0) * -0.02
           + GREATEST(LOG(NULLIF(GREATEST(abs(q.Score),1),0)),0) * 1.5
           + (COALESCE(aa.Answers_Positive,0) * 2.0)
           - (COALESCE(aa.Answers_Negative,0) * 1.5)
           + (COALESCE(ca.DistinctCommenters_90d,0) * 0.8)
           + (COALESCE(va.UpVotes,0) * 1.2) - (COALESCE(va.DownVotes,0) * 1.0)
           + (COALESCE(ha.TotalRevisions,0) * 0.5)
           + (CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN -5 ELSE 3 END)
           + (GREATEST(0, 10 - COALESCE(q.ViewCount,0)/100.0)) * 0.3
           + (COALESCE(la.ReciprocalLinks,0) * 1.8)
           + (COALESCE(ab.GoldBadges_Last,0) * 2.5 + COALESCE(ab.SilverBadges_Last,0) * 1.2 + COALESCE(ab.BronzeBadges_Last,0) * 0.6)
           + (COALESCE(ts.Questions_Last2y,0) * -0.05)
         ) AS CompositeScore
  FROM Questions q
  LEFT JOIN AnswerAgg aa ON aa.QuestionId = q.Id
  LEFT JOIN CommentAgg ca ON ca.QuestionId = q.Id
  LEFT JOIN VoteAgg va ON va.QuestionId = q.Id
  LEFT JOIN HistoryAgg ha ON ha.QuestionId = q.Id
  LEFT JOIN LinkAgg la ON la.QuestionId = q.Id
  LEFT JOIN AskerBadges ab ON ab.UserId = q.OwnerUserId
  LEFT JOIN TagStats ts ON ts.TagName = q.Tag
)
SELECT
  rq.Id,
  rq.Title,
  rq.OwnerUserId,
  rq.CreationDate,
  rq.Score,
  rq.ViewCount,
  rq.AnswerCount,
  rq.FavoriteCount,
  rq.Tag,
  rq.Answers_Positive,
  rq.Answers_Negative,
  ROUND(rq.Avg_Answer_Score::numeric,2) AS Avg_Answer_Score,
  rq.Max_Answer_Score,
  rq.TotalComments_90d,
  rq.DistinctCommenters_90d,
  rq.UpVotes,
  rq.DownVotes,
  rq.AcceptedCount,
  rq.BountyEvents,
  rq.TotalRevisions,
  rq.BodyEdits,
  rq.TitleEdits,
  rq.ClosureRelated,
  rq.OutgoingLinks,
  rq.ReciprocalLinks,
  rq.GoldBadges_Last,
  rq.SilverBadges_Last,
  rq.BronzeBadges_Last,
  rq.Questions_Last2y,
  ROUND(rq.CompositeScore::numeric,4) AS CompositeScore,
  -- enrich with percentile ranking window functions across the candidate set
  PERCENT_RANK() OVER (ORDER BY rq.CompositeScore DESC) AS Composite_PctRank,
  NTILE(10) OVER (ORDER BY rq.CompositeScore DESC) AS Decile,
  ROW_NUMBER() OVER (ORDER BY rq.CompositeScore DESC, rq.ViewCount DESC) AS RankOverall
FROM RankedQuestions rq
WHERE rq.CompositeScore IS NOT NULL
ORDER BY rq.CompositeScore DESC, rq.ViewCount DESC
LIMIT 100;