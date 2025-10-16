-- {"query": "383.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 16909} 
WITH
questions AS (
  SELECT p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.Tags,
         COALESCE(p.AnswerCount,0) AS AnswerCount, p.AcceptedAnswerId, p.CommentCount, p.FavoriteCount, p.ClosedDate
  FROM Posts p
  WHERE p.PostTypeId = 1
),
tags_expanded AS (
  SELECT q.*, lower(trim(t.tag)) AS tag
  FROM questions q
  CROSS JOIN LATERAL regexp_split_to_table(substring(q.Tags from 2 for char_length(q.Tags)-2), '><') AS t(tag)
  WHERE q.Tags IS NOT NULL AND q.Tags <> ''
),
answers AS (
  SELECT a.Id, a.ParentId AS QuestionId, a.OwnerUserId, a.CreationDate, a.Score, a.CommentCount
  FROM Posts a
  WHERE a.PostTypeId = 2
),
answer_aggs AS (
  SELECT a.QuestionId,
         COUNT(*) AS AnswerCount,
         SUM(CASE WHEN a.Score > 0 THEN 1 ELSE 0 END) AS PositiveAnswers,
         SUM(CASE WHEN a.Score < 0 THEN 1 ELSE 0 END) AS NegativeAnswers,
         AVG(a.Score) AS AvgAnswerScore,
         MAX(a.Score) AS MaxAnswerScore,
         MIN(a.CreationDate) AS FirstAnswerDate,
         COUNT(DISTINCT a.OwnerUserId) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS DistinctAnswerers
  FROM answers a
  GROUP BY a.QuestionId
),
answer_latency AS (
  SELECT a.QuestionId,
         AVG(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgLatencySecs,
         MIN(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS FastestAnswerSecs,
         MAX(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS SlowestAnswerSecs
  FROM answers a
  JOIN questions q ON q.Id = a.QuestionId
  GROUP BY a.QuestionId
),
votes_agg AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOwner,
         COUNT(*) AS TotalVotes,
         SUM(COALESCE(v.BountyAmount,0)) AS TotalBounty
  FROM Votes v
  GROUP BY v.PostId
),
comments_agg AS (
  SELECT c.PostId,
         COUNT(*) AS CommentCount,
         AVG(length(c.Text))::int AS AvgCommentLength,
         COUNT(*) FILTER (WHERE c.UserId IS NULL) AS AnonymousComments
  FROM Comments c
  GROUP BY c.PostId
),
badges_by_user AS (
  SELECT b.UserId,
         COUNT(*) FILTER (WHERE b.Class = 1) AS Gold,
         COUNT(*) FILTER (WHERE b.Class = 2) AS Silver,
         COUNT(*) FILTER (WHERE b.Class = 3) AS Bronze,
         COUNT(*) AS TotalBadges
  FROM Badges b
  GROUP BY b.UserId
),
user_summary AS (
  SELECT u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Views, u.UpVotes AS UserUpVotes, u.DownVotes AS UserDownVotes,
         COALESCE(b.Gold,0) AS Gold, COALESCE(b.Silver,0) AS Silver, COALESCE(b.Bronze,0) AS Bronze, COALESCE(b.TotalBadges,0) AS TotalBadges
  FROM Users u
  LEFT JOIN badges_by_user b ON b.UserId = u.Id
),
post_history_agg AS (
  SELECT ph.PostId,
         COUNT(*) AS HistoryEvents,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseEvents,
         COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 11) AS ReopenEvents,
         MAX(ph.CreationDate) AS LastHistoryDate,
         MIN(ph.CreationDate) AS FirstHistoryDate
  FROM PostHistory ph
  GROUP BY ph.PostId
),
links_agg AS (
  SELECT pl.PostId,
         COUNT(*) AS TotalLinks,
         SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS OutboundLinks,
         SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks,
         COUNT(DISTINCT pl.RelatedPostId) AS UniqueRelated
  FROM PostLinks pl
  GROUP BY pl.PostId
),
suspected_orphans AS (
  (SELECT q.Id FROM questions q WHERE COALESCE(q.AnswerCount,0) = 0 AND COALESCE(q.Score,0) <= 0)
  UNION
  (SELECT q.Id FROM questions q WHERE q.ClosedDate IS NOT NULL AND COALESCE(q.AnswerCount,0) = 0)
  EXCEPT
  (SELECT fv.PostId FROM Votes fv WHERE fv.VoteTypeId = 5)
),
tag_summary AS (
  SELECT te.tag,
         COUNT(DISTINCT te.Id) AS QuestionsWithTag,
         SUM(COALESCE(qa.AnswerCount,0)) AS TotalAnswersForTag,
         SUM(COALESCE(vs.UpVotes,0)) AS TotalUpVotes,
         SUM(COALESCE(vs.DownVotes,0)) AS TotalDownVotes,
         AVG(COALESCE(qa.AvgAnswerScore,0)) AS AvgPerQuestionAnswerScore,
         SUM(CASE WHEN so.Id IS NOT NULL THEN 1 ELSE 0 END) AS SuspectedOrphansCount
  FROM tags_expanded te
  LEFT JOIN answer_aggs qa ON qa.QuestionId = te.Id
  LEFT JOIN votes_agg vs ON vs.PostId = te.Id
  LEFT JOIN suspected_orphans so ON so.Id = te.Id
  GROUP BY te.tag
),
rich_questions AS (
  SELECT te.Id AS QuestionId,
         te.tag,
         te.Title,
         te.OwnerUserId,
         te.CreationDate,
         te.Score,
         te.ViewCount,
         COALESCE(aa.AnswerCount,0) AS AnswerCount,
         COALESCE(aa.PositiveAnswers,0) AS PositiveAnswers,
         COALESCE(aa.MaxAnswerScore,0) AS MaxAnswerScore,
         COALESCE(al.AvgLatencySecs, 999999) AS AvgLatencySecs,
         COALESCE(vs.UpVotes,0) AS QUpVotes,
         COALESCE(vs.DownVotes,0) AS QDownVotes,
         COALESCE(ca.CommentCount,0) AS CommentCount,
         COALESCE(ls.TotalLinks,0) AS TotalLinks,
         COALESCE(ph.HistoryEvents,0) AS HistoryEvents,
         us.Reputation AS OwnerReputation,
         COALESCE(us.Gold,0) AS OwnerGold,
         COALESCE(us.Silver,0) AS OwnerSilver,
         COALESCE(us.Bronze,0) AS OwnerBronze,
         te.AcceptedAnswerId AS AcceptedAnswerId,
         CASE WHEN te.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
         CASE WHEN COALESCE(ph.CloseEvents,0) > 0 THEN 1 ELSE 0 END AS WasEverClosed,
         ( COALESCE(vs.UpVotes,0)
           - COALESCE(vs.DownVotes,0) * 0.75
           + COALESCE(aa.MaxAnswerScore,0) * 0.5
           + LOG(GREATEST(1, COALESCE(te.ViewCount,0))) * 0.2
           - GREATEST(0, COALESCE(ph.CloseEvents,0)) * 3
           + LEAST(10, COALESCE(us.Gold, 0)) * 1.5
           - COALESCE(ca.AnonymousComments,0) * 0.5
         ) AS BaseScore
  FROM tags_expanded te
  LEFT JOIN answer_aggs aa ON aa.QuestionId = te.Id
  LEFT JOIN answer_latency al ON al.QuestionId = te.Id
  LEFT JOIN votes_agg vs ON vs.PostId = te.Id
  LEFT JOIN comments_agg ca ON ca.PostId = te.Id
  LEFT JOIN links_agg ls ON ls.PostId = te.Id
  LEFT JOIN post_history_agg ph ON ph.PostId = te.Id
  LEFT JOIN user_summary us ON us.Id = te.OwnerUserId
),
scaled_and_ranked AS (
  SELECT rq.*,
         (rq.BaseScore * (1 + LOG(GREATEST(1, ts.QuestionsWithTag)))) / NULLIF(1 + (rq.AvgLatencySecs / 3600.0), 0) AS CompositeScore,
         row_number() OVER (PARTITION BY rq.tag ORDER BY (rq.BaseScore * (1 + LOG(GREATEST(1, ts.QuestionsWithTag)))) / NULLIF(1 + (rq.AvgLatencySecs / 3600.0), 0) DESC) AS RankWithinTag,
         rank() OVER (ORDER BY (rq.BaseScore * (1 + LOG(GREATEST(1, ts.QuestionsWithTag)))) / NULLIF(1 + (rq.AvgLatencySecs / 3600.0), 0) DESC) AS GlobalRank
  FROM rich_questions rq
  LEFT JOIN tag_summary ts ON ts.tag = rq.tag
),
top_per_tag AS (
  SELECT * FROM scaled_and_ranked WHERE RankWithinTag <= 3
),
top_global AS (
  SELECT * FROM scaled_and_ranked WHERE GlobalRank <= 200
),
answer_top_contributors AS (
  SELECT atc.QuestionId, atc.OwnerUserId AS AnswererId, atc.AnswersByUserOnQuestion, atc.SumAnswerScore,
         RANK() OVER (PARTITION BY atc.QuestionId ORDER BY atc.SumAnswerScore DESC) AS RankByScore
  FROM (
    SELECT a.QuestionId, a.OwnerUserId, COUNT(*) AS AnswersByUserOnQuestion, SUM(a.Score) AS SumAnswerScore
    FROM answers a
    GROUP BY a.QuestionId, a.OwnerUserId
  ) atc
),
top_contributor_by_question AS (
  SELECT atc.QuestionId, atc.AnswererId, atc.SumAnswerScore
  FROM answer_top_contributors atc
  WHERE atc.RankByScore = 1
),
interesting_set AS (
  (SELECT QuestionId FROM top_global WHERE HasAcceptedAnswer = 1)
  INTERSECT
  (SELECT QuestionId FROM top_per_tag WHERE AnswerCount > 0)
  EXCEPT
  (SELECT Id FROM suspected_orphans)
),
final AS (
  SELECT sg.tag,
         sg.QuestionsWithTag,
         sg.TotalAnswersForTag,
         sg.TotalUpVotes,
         sg.TotalDownVotes,
         tpg.QuestionId,
         tpg.Title,
         tpg.OwnerUserId,
         tpg.Score AS QuestionScore,
         tpg.ViewCount,
         tpg.AnswerCount,
         tpg.PositiveAnswers,
         tpg.MaxAnswerScore,
         tpg.HasAcceptedAnswer,
         tpg.AvgLatencySecs,
         tpg.QUpVotes,
         tpg.QDownVotes,
         tpg.CommentCount,
         tpg.TotalLinks,
         tpg.HistoryEvents,
         tpg.OwnerReputation,
         tpg.OwnerGold,
         tpg.OwnerSilver,
         tpg.CompositeScore,
         tpg.RankWithinTag,
         tpg.GlobalRank,
         tc.AnswererId AS TopAnswererId,
         u.DisplayName AS TopAnswererName,
         (SELECT COUNT(*) FROM Posts ap JOIN Users au ON au.Id = ap.OwnerUserId WHERE ap.ParentId = tpg.QuestionId AND ap.PostTypeId = 2 AND au.Reputation > 5000) AS HighRepAnswerCount,
         (SELECT COALESCE(SUM(CASE WHEN a.Score >= COALESCE((SELECT p2.Score FROM Posts p2 WHERE p2.Id = tpg.AcceptedAnswerId), -999999) THEN 1 ELSE 0 END)::float / NULLIF(COUNT(*),0),0)
            FROM Posts a WHERE a.ParentId = tpg.QuestionId AND a.PostTypeId = 2) AS FractionAnswersAtLeastAccepted,
         EXISTS(SELECT 1 FROM Comments c WHERE c.PostId = tpg.QuestionId AND c.UserId = tpg.OwnerUserId) AS OwnerCommented,
         CASE WHEN char_length(tpg.Title) > 120 THEN substr(tpg.Title,1,117) || '...' ELSE tpg.Title END AS ShortTitle
  FROM tag_summary sg
  JOIN top_per_tag tpg ON tpg.tag = sg.tag
  LEFT JOIN top_contributor_by_question tc ON tc.QuestionId = tpg.QuestionId
  LEFT JOIN Users u ON u.Id = tc.AnswererId
  WHERE tpg.QuestionId IS NOT NULL
)
SELECT *
FROM final
WHERE CompositeScore IS NOT NULL
ORDER BY CompositeScore DESC NULLS LAST, QuestionsWithTag DESC
LIMIT 100;