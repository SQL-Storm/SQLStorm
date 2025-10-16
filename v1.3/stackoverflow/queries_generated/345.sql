-- {"query": "345.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 12917} 
WITH
normalized_tags AS (
  SELECT p.Id AS QuestionId,
         t.tag AS Tag
  FROM Posts p
  CROSS JOIN LATERAL regexp_split_to_table(substring(p.Tags, 2, length(p.Tags)-2), '><') AS t(tag)
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
answer_stats AS (
  SELECT q.Id AS QuestionId,
         COUNT(a.Id) FILTER (WHERE a.Id IS NOT NULL) AS AnswerCount,
         AVG(a.Score)::numeric(10,3) AS AvgAnswerScore,
         MAX(a.Score) AS MaxAnswerScore,
         MIN(a.Score) AS MinAnswerScore,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianAnswerScore,
         SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswersWithOwners
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
),
accepted_times AS (
  SELECT q.Id AS QuestionId,
         q.CreationDate AS QuestionCreation,
         aa.Id AS AcceptedAnswerId,
         aa.CreationDate AS AcceptedAnswerCreation,
         CASE WHEN aa.CreationDate IS NOT NULL THEN EXTRACT(EPOCH FROM (aa.CreationDate - q.CreationDate)) / 3600.0 ELSE NULL END AS HoursToAccept
  FROM Posts q
  LEFT JOIN Posts aa ON aa.Id = q.AcceptedAnswerId
  WHERE q.PostTypeId = 1
),
top_answerers AS (
  SELECT q.Id AS QuestionId,
         a.OwnerUserId,
         u.Reputation,
         a.Score AS AnswerScore,
         ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, u.Reputation DESC NULLS LAST) AS rnk
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  LEFT JOIN Users u ON u.Id = a.OwnerUserId
  WHERE q.PostTypeId = 1
),
top_answerer_aggr AS (
  SELECT QuestionId,
         MAX(CASE WHEN rnk = 1 THEN OwnerUserId END) AS TopAnswererUserId,
         MAX(CASE WHEN rnk = 1 THEN Reputation END) AS TopAnswererReputation,
         MAX(CASE WHEN rnk = 1 THEN AnswerScore END) AS TopAnswerScore
  FROM top_answerers
  GROUP BY QuestionId
),
user_aggregates AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
         COALESCE((SELECT COUNT(*) FROM Votes v2 JOIN Posts p2 ON p2.Id = v2.PostId WHERE p2.OwnerUserId = u.Id AND v2.VoteTypeId = 2),0) AS UpVotesReceived,
         COALESCE((SELECT COUNT(*) FROM Votes v3 JOIN Posts p3 ON p3.Id = v3.PostId WHERE p3.OwnerUserId = u.Id AND v3.VoteTypeId = 3),0) AS DownVotesReceived,
         (SELECT COUNT(*) FROM Badges b2 WHERE b2.UserId = u.Id) AS BadgesEarned,
         MAX(p.LastActivityDate) AS LastPostActivity,
         ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
         NTILE(10) OVER (ORDER BY u.Reputation DESC) AS ReputationDecile
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id, u.Reputation
),
tag_popularity AS (
  SELECT nt.Tag,
         COUNT(DISTINCT nt.QuestionId) AS QuestionsWithTag,
         AVG(q.Score)::numeric(10,3) AS AvgQuestionScore,
         MAX(q.ViewCount) AS MaxViews,
         SUM(q.ViewCount) AS TotalViews,
         (SELECT u.Id FROM Users u
          JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
          JOIN normalized_tags nt2 ON nt2.QuestionId = p.Id AND nt2.Tag = nt.Tag
          GROUP BY u.Id ORDER BY SUM(p.Score) DESC NULLS LAST LIMIT 1) AS TopScorerUserId
  FROM normalized_tags nt
  JOIN Posts q ON q.Id = nt.QuestionId
  GROUP BY nt.Tag
),
post_link_stats AS (
  SELECT p.Id AS PostId,
         COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 1) AS OutboundLinks,
         COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
         COUNT(pl.Id) AS TotalLinks
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id
  GROUP BY p.Id
),
comment_activity AS (
  SELECT c.PostId,
         COUNT(*) AS CommentCount,
         AVG(c.Score) AS AvgCommentScore,
         SUM(CASE WHEN c.Text ILIKE '%thank%' OR c.Text ILIKE '%thanks%' THEN 1 ELSE 0 END) AS ThanksMentions,
         MAX(length(c.Text)) AS MaxCommentLength
  FROM Comments c
  GROUP BY c.PostId
),
high_views_low_score AS (
  SELECT p.Id FROM Posts p
  WHERE p.PostTypeId = 1 AND p.ViewCount > 10000 AND (p.Score < 0 OR p.Score BETWEEN 0 AND 1)
),
many_downvotes AS (
  SELECT v.PostId FROM Votes v
  WHERE v.VoteTypeId = 3
  GROUP BY v.PostId HAVING COUNT(*) > 5
),
controversial_questions AS (
  SELECT Id FROM high_views_low_score
  UNION
  SELECT PostId AS Id FROM many_downvotes
  EXCEPT
  SELECT Id FROM Posts WHERE ClosedDate IS NOT NULL
),
question_mega AS (
  SELECT q.Id AS QuestionId,
         q.Title,
         q.CreationDate,
         q.Score AS QuestionScore,
         q.ViewCount,
         q.AnswerCount,
         COALESCE(a.AvgAnswerScore, 0) AS AvgAnswerScore,
         a.MedianAnswerScore,
         at.HoursToAccept,
         tas.TopAnswererUserId,
         tas.TopAnswererReputation,
         uag.Reputation AS OwnerReputation,
         uag.QuestionsPosted,
         uag.AnswersPosted,
         uag.BadgesEarned,
         pls.OutboundLinks,
         pls.DuplicateLinks,
         COALESCE(ca.CommentCount,0) AS CommentCount,
         tp.Tag,
         tpop.QuestionsWithTag,
         tpop.AvgQuestionScore AS TagAvgScore,
         EXISTS (SELECT 1 FROM controversial_questions cq WHERE cq.Id = q.Id) AS IsControversial,
         (SELECT
            COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0)::numeric /
            NULLIF(COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0),0)::numeric
          FROM Votes v
          WHERE v.PostId = q.Id
         ) AS UpDownRatio,
         lower(regexp_replace(coalesce(q.Title,''), '[^a-z0-9]+',' ','g')) AS TitleFingerprint,
         (
           COALESCE(q.Score,0) * 2
           + COALESCE(a.AvgAnswerScore,0) * 3
           + COALESCE(log(NULLIF(q.ViewCount,0))::numeric, 0) * 1.5
           + COALESCE(COALESCE(tpop.QuestionsWithTag,0)::numeric / NULLIF(uag.BadgesEarned,0), 0)
           - COALESCE((SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = q.Id AND v2.VoteTypeId = 3),0) * 1.25
         ) AS HotnessScore
  FROM Posts q
  LEFT JOIN answer_stats a ON a.QuestionId = q.Id
  LEFT JOIN accepted_times at ON at.QuestionId = q.Id
  LEFT JOIN top_answerer_aggr tas ON tas.QuestionId = q.Id
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN user_aggregates uag ON uag.UserId = u.Id
  LEFT JOIN post_link_stats pls ON pls.PostId = q.Id
  LEFT JOIN comment_activity ca ON ca.PostId = q.Id
  LEFT JOIN normalized_tags tp ON tp.QuestionId = q.Id
  LEFT JOIN tag_popularity tpop ON tpop.Tag = tp.Tag
  WHERE q.PostTypeId = 1
),
ranked_questions AS (
  SELECT qm.*,
         ROW_NUMBER() OVER (PARTITION BY qm.Tag ORDER BY qm.HotnessScore DESC NULLS LAST) AS TagHotRank,
         RANK() OVER (ORDER BY qm.HotnessScore DESC NULLS LAST) AS GlobalHotRank,
         PERCENT_RANK() OVER (ORDER BY qm.HotnessScore) AS HotnessPercentile
  FROM question_mega qm
)
SELECT
  rq.QuestionId,
  rq.Title,
  rq.TitleFingerprint,
  rq.Tag,
  rq.QuestionsWithTag,
  rq.TagAvgScore,
  rq.QuestionScore,
  rq.ViewCount,
  rq.AvgAnswerScore,
  rq.MedianAnswerScore,
  rq.HoursToAccept,
  rq.TopAnswererUserId,
  rq.TopAnswererReputation,
  rq.OwnerReputation,
  rq.QuestionsPosted,
  rq.AnswersPosted,
  rq.BadgesEarned,
  rq.OutboundLinks,
  rq.DuplicateLinks,
  rq.CommentCount,
  rq.IsControversial,
  COALESCE(rq.UpDownRatio, 0) AS UpDownRatio,
  rq.HotnessScore,
  rq.GlobalHotRank,
  rq.TagHotRank,
  rq.HotnessPercentile
FROM ranked_questions rq
WHERE (rq.TagHotRank <= 3 OR rq.GlobalHotRank <= 100)
  AND rq.CreationDate > now() - interval '5 years'
ORDER BY rq.GlobalHotRank NULLS LAST, rq.HotnessScore DESC
LIMIT 500;