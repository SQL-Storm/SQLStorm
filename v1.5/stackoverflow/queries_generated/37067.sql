-- {"query": "37067.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2141} 
WITH
-- select candidate questions in a recent heavy-activity window
RecentQuestions AS (
  SELECT p.Id, p.CreationDate, p.Title, p.OwnerUserId, p.ViewCount, p.Score, p.AnswerCount, p.Tags
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= (current_timestamp - interval '730 days')
),
-- expand tags into one row per tag for tag-based aggregations
QuestionTags AS (
  SELECT rq.Id AS QuestionId,
         unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) AS Tag
  FROM RecentQuestions rq
),
-- compute per-question engagement metrics from related tables
QuestionMetrics AS (
  SELECT
    q.Id,
    q.CreationDate,
    q.Title,
    q.OwnerUserId,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    COUNT(DISTINCT c.Id) FILTER (WHERE c.CreationDate >= q.CreationDate) AS CommentsSinceCreation,
    COUNT(DISTINCT ph.Id) FILTER (WHERE ph.CreationDate >= q.CreationDate) AS RevisionsSinceCreation,
    MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId IN (2,3)) AS LastVoteDate,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) FILTER (WHERE v.CreationDate >= q.CreationDate) AS VoteDelta,
    COALESCE((SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.Score >= 0),0) AS PositiveAnswers,
    COALESCE((SELECT AVG(a.Score) FROM Posts a WHERE a.ParentId = q.Id),0) AS AvgAnswerScore
  FROM RecentQuestions q
  LEFT JOIN Comments c ON c.PostId = q.Id
  LEFT JOIN PostHistory ph ON ph.PostId = q.Id
  LEFT JOIN Votes v ON v.PostId = q.Id
  GROUP BY q.Id, q.CreationDate, q.Title, q.OwnerUserId, q.ViewCount, q.Score, q.AnswerCount
),
-- compute author reputation and recent activity window
AuthorStats AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate AS UserCreation,
         u.LastAccessDate,
         COUNT(b.Id) FILTER (WHERE b.Date >= current_timestamp - interval '365 days') AS BadgesLastYear,
         SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) FILTER (WHERE p.CreationDate >= current_timestamp - interval '365 days') AS QuestionsLastYear,
         SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE p.CreationDate >= current_timestamp - interval '365 days') AS AnswersLastYear
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.LastAccessDate
),
-- join question metrics with tags and author stats
QuestionEnriched AS (
  SELECT qm.*,
         qt.Tag,
         a.Reputation AS AuthorRep,
         a.BadgesLastYear,
         a.QuestionsLastYear,
         a.AnswersLastYear,
         -- a derived recency-weighted engagement score
         ( (qm.ViewCount::numeric / GREATEST(EXTRACT(EPOCH FROM (current_timestamp - qm.CreationDate))/86400.0, 1)) * 0.25
           + (GREATEST(qm.Score,0)::numeric) * 0.2
           + (GmNormalization := (COALESCE(qm.CommentsSinceCreation,0)::numeric / GREATEST(qm.AnswerCount,1))) * 0.15
           + (COALESCE(qm.RevisionsSinceCreation,0)::numeric) * 0.1
           + (COALESCE(qm.PositiveAnswers,0)::numeric) * 0.2
         ) AS EngagementScore
  FROM QuestionMetrics qm
  JOIN QuestionTags qt ON qt.QuestionId = qm.Id
  LEFT JOIN AuthorStats a ON a.UserId = qm.OwnerUserId
),
-- per-tag aggregates of enriched questions to find "hot" tags by composite metrics
TagAggregates AS (
  SELECT
    qe.Tag,
    COUNT(*) AS QuestionsInWindow,
    AVG(qe.EngagementScore) AS AvgEngagement,
    MAX(qe.EngagementScore) AS TopEngagement,
    SUM(CASE WHEN qe.AnswerCount = 0 THEN 1 ELSE 0 END) AS UnansweredCount,
    AVG(qe.AuthorRep) FILTER (WHERE qe.AuthorRep IS NOT NULL) AS AvgAuthorRep,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY qe.EngagementScore) AS MedianEngagement
  FROM QuestionEnriched qe
  GROUP BY qe.Tag
),
-- rank questions within each tag by engagement with tiebreakers
RankedQuestions AS (
  SELECT
    qe.*,
    ta.QuestionsInWindow,
    ta.AvgEngagement,
    ta.TopEngagement,
    ta.UnansweredCount,
    ta.AvgAuthorRep,
    RANK() OVER (PARTITION BY qe.Tag ORDER BY qe.EngagementScore DESC, qe.Score DESC, qe.ViewCount DESC, qe.CreationDate DESC) AS TagRank
  FROM QuestionEnriched qe
  JOIN TagAggregates ta ON ta.Tag = qe.Tag
),
-- compute network/graph metrics: incoming links and duplicates
LinkMetrics AS (
  SELECT
    p.Id,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedFromCount,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateClaims,
    COUNT(pl.Id) AS TotalOutgoingLinks
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY p.Id
),
-- final selection: pick top N tags then top M questions per tag and enrich with link metrics and recent vote tempo
FinalCandidates AS (
  SELECT
    rq.*,
    rj.Tag,
    rj.TagRank,
    rj.EngagementScore,
    rj.QuestionsInWindow,
    rj.AvgEngagement AS TagAvgEngagement,
    lm.LinkedFromCount,
    lm.DuplicateClaims,
    -- votes in past 30 days for velocity
    COALESCE(vtab.Votes30,0) AS VotesLast30Days,
    -- last activity delta
    EXTRACT(EPOCH FROM (current_timestamp - rq.CreationDate))/86400.0 AS DaysSinceCreation
  FROM RecentQuestions rq
  JOIN RankedQuestions rj ON rj.Id = rq.Id
  LEFT JOIN LinkMetrics lm ON lm.Id = rq.Id
  LEFT JOIN (
    SELECT v.PostId, COUNT(*) AS Votes30
    FROM Votes v
    WHERE v.CreationDate >= (current_timestamp - interval '30 days')
      AND v.VoteTypeId IN (2,3)
    GROUP BY v.PostId
  ) vtab ON vtab.PostId = rq.Id
  WHERE rj.TagRank <= 10
),
-- pick top 25 questions across tags by a combined relevance heuristic
TopSelection AS (
  SELECT *
  FROM FinalCandidates
  WHERE Tag IN (
    SELECT Tag FROM TagAggregates ORDER BY AvgEngagement DESC NULLS LAST LIMIT 25
  )
  ORDER BY (EngagementScore * LEAST(1.0, GREATEST(0.1, 1.0 - (DaysSinceCreation / 365.0)))) DESC,
           VotesLast30Days DESC,
           LinkedFromCount DESC,
           DuplicateClaims ASC
  LIMIT 100
)
-- return an elaborate result set suitable for benchmarking: include JSON aggregates and windowed stats
SELECT
  ts.Id AS QuestionId,
  ts.Title,
  ts.Tag,
  ts.TagRank,
  ts.EngagementScore,
  ts.QuestionsInWindow,
  ts.TagAvgEngagement,
  ts.ViewCount,
  ts.Score,
  ts.AnswerCount,
  ts.UnansweredCount,
  ts.LinkedFromCount,
  ts.DuplicateClaims,
  ts.VotesLast30Days,
  ts.DaysSinceCreation,
  u.DisplayName AS OwnerName,
  u.Reputation AS OwnerReputation,
  -- recent top answers snapshot (top 3 by score)
  (SELECT json_agg(row_to_json(a_row)) FROM (
     SELECT a.Id, a.Score, a.CreationDate, a.OwnerUserId, a.Body
     FROM Posts a
     WHERE a.ParentId = ts.Id AND a.PostTypeId = 2
     ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC
     LIMIT 3
  ) a_row) AS TopAnswers,
  -- recent comments snapshot (up to 5)
  (SELECT json_agg(row_to_json(c_row)) FROM (
     SELECT c.Id, c.UserId, c.UserDisplayName, c.Text, c.CreationDate
     FROM Comments c
     WHERE c.PostId = ts.Id
     ORDER BY c.CreationDate DESC
     LIMIT 5
  ) c_row) AS RecentComments,
  -- per-tag median engagement for comparison
  (SELECT MedianEngagement FROM TagAggregates ta WHERE ta.Tag = ts.Tag) AS TagMedianEngagement,
  -- badge context for owner
  (SELECT json_agg(row_to_json(b_row)) FROM (
     SELECT b.Name, b.Class, b.Date
     FROM Badges b
     WHERE b.UserId = ts.OwnerUserId
     ORDER BY b.Date DESC
     LIMIT 5
  ) b_row) AS OwnerRecentBadges
FROM TopSelection ts
LEFT JOIN Users u ON u.Id = ts.OwnerUserId
ORDER BY ts.EngagementScore DESC, ts.VotesLast30Days DESC;