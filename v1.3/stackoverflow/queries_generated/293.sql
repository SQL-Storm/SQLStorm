-- {"query": "293.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6537} 
WITH recent_questions AS (
  SELECT p.*
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '365 days'
),
answers_agg AS (
  SELECT ParentId AS QuestionId,
         count(*) AS AnswerCountAll,
         avg(score) AS AvgAnswerScore,
         max(score) AS MaxAnswerScore
  FROM Posts
  WHERE PostTypeId = 2
  GROUP BY ParentId
),
tag_exploded AS (
  SELECT rq.Id AS QuestionId,
         unnest(string_to_array(substring(rq.Tags,2,length(rq.Tags)-2), '><')) AS Tag
  FROM recent_questions rq
  WHERE rq.Tags IS NOT NULL AND rq.Tags <> ''
),
tag_stats AS (
  SELECT te.Tag,
         count(*) AS QuestionsWithTag,
         sum(rq.ViewCount) AS TotalViews,
         avg(rq.Score) AS AvgScore
  FROM tag_exploded te
  JOIN recent_questions rq ON rq.Id = te.QuestionId
  GROUP BY te.Tag
),
user_stats AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.DisplayName,
         count(distinct p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
         count(distinct p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
         coalesce(sum(v_up.cnt),0) AS UpVotesReceived,
         coalesce(sum(v_down.cnt),0) AS DownVotesReceived,
         max(p.LastActivityDate) AS LastActivityOnPost,
         (SELECT count(*) FROM Comments c WHERE c.UserId = u.Id) AS CommentsMade,
         (SELECT count(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN (SELECT PostId, count(*) AS cnt FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) v_up ON v_up.PostId = p.Id
  LEFT JOIN (SELECT PostId, count(*) AS cnt FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) v_down ON v_down.PostId = p.Id
  GROUP BY u.Id, u.Reputation, u.DisplayName
),
post_history_agg AS (
  SELECT ph.PostId,
         count(*) FILTER (WHERE PostHistoryTypeId IN (4,5,6)) AS EditCount,
         max(ph.CreationDate) AS LastEditDate,
         bool_or(PostHistoryTypeId = 10) AS EverClosed
  FROM PostHistory ph
  GROUP BY ph.PostId
),
votes_summary AS (
  SELECT PostId,
         sum(case when VoteTypeId = 2 then 1 else 0 end) AS UpVotes,
         sum(case when VoteTypeId = 3 then 1 else 0 end) AS DownVotes,
         sum(case when VoteTypeId = 5 then 1 else 0 end) AS Favorites
  FROM Votes
  GROUP BY PostId
),
linked_counts AS (
  SELECT PostId,
         sum(case when LinkTypeId = 1 then 1 else 0 end) AS LinksOut,
         sum(case when LinkTypeId = 3 then 1 else 0 end) AS Duplicates
  FROM PostLinks
  GROUP BY PostId
),
question_ranked AS (
  SELECT rq.Id AS QuestionId,
         rq.Title,
         rq.CreationDate,
         rq.Score AS QuestionScore,
         rq.ViewCount,
         rq.OwnerUserId,
         COALESCE(ans.AnswerCountAll,0) AS AnswerCount,
         COALESCE(ans.AvgAnswerScore,0) AS AvgAnswerScore,
         COALESCE(ans.MaxAnswerScore,0) AS MaxAnswerScore,
         COALESCE(vs.UpVotes,0) AS UpVotes,
         COALESCE(vs.DownVotes,0) AS DownVotes,
         COALESCE(lc.LinksOut,0) AS LinksOut,
         COALESCE(lc.Duplicates,0) AS DuplicateLinks,
         COALESCE(pha.EditCount,0) AS EditCount,
         COALESCE(pha.EverClosed,false) AS EverClosed,
         COALESCE(u.QuestionsPosted,0) AS OwnerQuestions,
         u.DisplayName AS OwnerName,
         u.Reputation AS OwnerReputation,
         (string_to_array(substring(rq.Tags,2,length(rq.Tags)-2), '><'))[1] AS PrimaryTag,
         (SELECT id FROM Posts pa WHERE pa.ParentId = rq.Id ORDER BY pa.Score DESC NULLS LAST LIMIT 1) AS TopAnswerId,
         (SELECT pa.Score FROM Posts pa WHERE pa.ParentId = rq.Id ORDER BY pa.Score DESC NULLS LAST LIMIT 1) AS TopAnswerScore,
         (((COALESCE(rq.Score,0)::numeric * 2)
           + COALESCE(ans.AvgAnswerScore,0)
           + COALESCE(rq.ViewCount,0) / GREATEST(NULLIF(COALESCE(ans.AnswerCountAll,0),0),1)
          ) * (CASE WHEN rq.ViewCount > 1000 THEN 1.2 ELSE 1 END)
         )::numeric AS PopularityScore,
         ROW_NUMBER() OVER (PARTITION BY (string_to_array(substring(rq.Tags,2,length(rq.Tags)-2), '><'))[1] ORDER BY rq.Score DESC NULLS LAST) AS TagRank
  FROM recent_questions rq
  LEFT JOIN answers_agg ans ON ans.QuestionId = rq.Id
  LEFT JOIN votes_summary vs ON vs.PostId = rq.Id
  LEFT JOIN linked_counts lc ON lc.PostId = rq.Id
  LEFT JOIN post_history_agg pha ON pha.PostId = rq.Id
  LEFT JOIN Users u ON u.Id = rq.OwnerUserId
)
SELECT
  'RECENT' AS Cohort,
  qr.QuestionId,
  qr.Title,
  COALESCE(qr.PrimaryTag,'<no-tag>') AS PrimaryTag,
  qr.TagRank,
  qr.QuestionScore,
  qr.ViewCount,
  qr.AnswerCount,
  qr.AvgAnswerScore,
  qr.MaxAnswerScore,
  qr.TopAnswerId,
  qr.TopAnswerScore,
  qr.PopularityScore,
  qr.UpVotes,
  qr.DownVotes,
  qr.LinksOut,
  qr.DuplicateLinks,
  qr.EditCount,
  qr.EverClosed,
  qr.OwnerName,
  qr.OwnerReputation,
  us.CommentsMade,
  ts.QuestionsWithTag,
  ts.TotalViews AS TagTotalViews,
  left(qr.Title,50) || case when length(qr.Title) > 50 then '...' else '' end AS TitleSnippet
FROM question_ranked qr
LEFT JOIN user_stats us ON us.UserId = qr.OwnerUserId
LEFT JOIN tag_stats ts ON ts.Tag = qr.PrimaryTag
WHERE qr.TagRank <= 5

UNION ALL

SELECT
  'ALLTIME' AS Cohort,
  p.Id AS QuestionId,
  p.Title,
  COALESCE((string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'))[1],'<no-tag>') AS PrimaryTag,
  NULL::int AS TagRank,
  p.Score AS QuestionScore,
  p.ViewCount,
  COALESCE(a.AnswerCountAll,0) AS AnswerCount,
  COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
  COALESCE(a.MaxAnswerScore,0) AS MaxAnswerScore,
  (SELECT id FROM Posts pa WHERE pa.ParentId = p.Id ORDER BY pa.Score DESC NULLS LAST LIMIT 1) AS TopAnswerId,
  (SELECT pa.Score FROM Posts pa WHERE pa.ParentId = p.Id ORDER BY pa.Score DESC NULLS LAST LIMIT 1) AS TopAnswerScore,
  -- alternative popularity metric using logarithm and null-safe operations
  (COALESCE(p.Score,0)
   + COALESCE(LOG(NULLIF(p.ViewCount,0)),0) * 3
   + COALESCE(a.MaxAnswerScore,0) / GREATEST(COALESCE(a.AnswerCountAll,1),1)
  )::numeric AS PopularityScore,
  COALESCE(vs.UpVotes,0) AS UpVotes,
  COALESCE(vs.DownVotes,0) AS DownVotes,
  COALESCE(lc.LinksOut,0) AS LinksOut,
  COALESCE(lc.Duplicates,0) AS DuplicateLinks,
  COALESCE(pha.EditCount,0) AS EditCount,
  COALESCE(pha.EverClosed,false) AS EverClosed,
  u.DisplayName AS OwnerName,
  u.Reputation AS OwnerReputation,
  (SELECT count(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentsMade,
  ts.QuestionsWithTag,
  ts.TotalViews AS TagTotalViews,
  left(p.Title,50) || case when length(p.Title) > 50 then '...' else '' end AS TitleSnippet
FROM Posts p
LEFT JOIN answers_agg a ON a.QuestionId = p.Id
LEFT JOIN votes_summary vs ON vs.PostId = p.Id
LEFT JOIN linked_counts lc ON lc.PostId = p.Id
LEFT JOIN post_history_agg pha ON pha.PostId = p.Id
LEFT JOIN Users u ON u.Id = p.OwnerUserId
LEFT JOIN tag_stats ts ON ts.Tag = (string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><'))[1]
WHERE p.PostTypeId = 1
ORDER BY Cohort, PopularityScore DESC NULLS LAST
LIMIT 200;