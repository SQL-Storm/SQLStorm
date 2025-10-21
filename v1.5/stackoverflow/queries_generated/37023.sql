-- {"query": "37023.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2433} 
WITH
-- recent active questions with tag arrays and owner info
questions AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.Tags,
         COALESCE(u.Id, -1) AS OwnerId,
         COALESCE(u.Reputation, 0) AS OwnerReputation,
         COALESCE(u.CreationDate, '1970-01-01') AS OwnerCreation,
         COALESCE(p.AnswerCount, 0) AS AnswerCount,
         COALESCE(p.CommentCount, 0) AS CommentCount
  FROM Posts p
  LEFT JOIN Users u ON p.OwnerUserId = u.Id
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),

-- top answers per question with scoring and age
answers AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.CreationDate AS AnswerCreation,
         a.Score AS AnswerScore,
         a.OwnerUserId AS AnswerOwnerId,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS rn
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.CreationDate >= now() - interval '2 years'
),

-- select best answer per question and aggregate answer stats
best_answers AS (
  SELECT QuestionId,
         AnswerId,
         AnswerCreation,
         AnswerScore,
         AnswerOwnerId
  FROM answers
  WHERE rn = 1
),

answer_aggregates AS (
  SELECT ParentId AS QuestionId,
         COUNT(*) AS TotalAnswers,
         SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) FILTER (WHERE Score IS NOT NULL) AS PositiveAnswers,
         AVG(CASE WHEN Score IS NOT NULL THEN Score END) AS AvgAnswerScore,
         MAX(Score) AS MaxAnswerScore,
         MIN(Score) AS MinAnswerScore
  FROM Posts
  WHERE PostTypeId = 2
    AND CreationDate >= now() - interval '2 years'
  GROUP BY ParentId
),

-- comments per question and per top answer
comments_q AS (
  SELECT c.PostId,
         COUNT(*) AS QCommentCount,
         SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS QPositiveComments
  FROM Comments c
  WHERE c.CreationDate >= now() - interval '2 years'
  GROUP BY c.PostId
),

comments_answer AS (
  SELECT c.PostId,
         COUNT(*) AS ACommentCount,
         SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS APositiveComments
  FROM Comments c
  WHERE c.CreationDate >= now() - interval '2 years'
  GROUP BY c.PostId
),

-- tag exploded table (extract tags like <tag1><tag2>)
tagged AS (
  SELECT q.QuestionId,
         TRIM(t) AS Tag
  FROM questions q,
       regexp_split_to_table(
         substring(COALESCE(q.Tags, ''), 2, GREATEST(length(COALESCE(q.Tags, ''))-2,0)
       ), '><') t
  WHERE COALESCE(q.Tags, '') <> ''
),

-- compute popularity metrics per tag across recent questions
tag_metrics AS (
  SELECT t.Tag,
         COUNT(DISTINCT q.QuestionId) AS QuestionsInWindow,
         AVG(q.Score) AS AvgQuestionScore,
         SUM(q.ViewCount) AS TotalViews,
         AVG(q.AnswerCount) AS AvgAnswerCount,
         SUM(COALESCE(aagg.TotalAnswers,0)) AS SumAnswers,
         SUM(COALESCE(b.AnswerScore,0)) AS SumTopAnswerScore
  FROM tagged t
  JOIN questions q ON q.QuestionId = t.QuestionId
  LEFT JOIN answer_aggregates aagg ON aagg.QuestionId = q.QuestionId
  LEFT JOIN best_answers b ON b.QuestionId = q.QuestionId
  GROUP BY t.Tag
  HAVING COUNT(DISTINCT q.QuestionId) >= 50
),

-- top active users by recent contributions and reputation velocity
recent_user_activity AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2) AND p.CreationDate >= now() - interval '1 year') AS RecentPosts,
         COUNT(DISTINCT c.Id) FILTER (WHERE c.CreationDate >= now() - interval '1 year') AS RecentComments,
         COUNT(DISTINCT v.Id) FILTER (WHERE v.CreationDate >= now() - interval '1 year' AND v.VoteTypeId = 2) AS RecentUpvotesReceived,
         (u.Reputation::numeric / GREATEST(EXTRACT(EPOCH FROM (now() - u.CreationDate))/86400.0,1)) AS RepPerDay
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
  HAVING COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1,2) AND p.CreationDate >= now() - interval '1 year') >= 5
),

-- compute influence score for questions combining many signals
question_rankings AS (
  SELECT q.QuestionId,
         q.Title,
         q.CreationDate,
         q.Score AS QuestionScore,
         q.ViewCount,
         COALESCE(aa.TotalAnswers,0) AS TotalAnswers,
         COALESCE(cq.QCommentCount,0) AS QCommentCount,
         COALESCE(b.AnswerScore,0) AS TopAnswerScore,
         q.OwnerId,
         q.OwnerReputation,
         -- composite popularity metric
         (
           ln(1 + q.ViewCount) * 0.25
           + (q.Score * 3.0)
           + (COALESCE(aa.TotalAnswers,0) * 5.0)
           + (COALESCE(b.AnswerScore,0) * 2.0)
           + (COALESCE(cq.QCommentCount,0) * 1.5)
           + (CASE WHEN q.AnswerCount > 0 THEN 10 ELSE 0 END)
           + (LEAST(1000, q.OwnerReputation)::numeric / 1000.0 * 2.0)
         ) AS PopularityScore
  FROM questions q
  LEFT JOIN answer_aggregates aa ON aa.QuestionId = q.QuestionId
  LEFT JOIN best_answers b ON b.QuestionId = q.QuestionId
  LEFT JOIN comments_q cq ON cq.PostId = q.QuestionId
),

-- windowed top questions per tag using the composite score, also include diversity and recency penalties
tag_top_questions AS (
  SELECT tm.Tag,
         qr.QuestionId,
         qr.Title,
         qr.CreationDate,
         qr.PopularityScore,
         ROW_NUMBER() OVER (PARTITION BY tm.Tag ORDER BY qr.PopularityScore DESC) AS rn,
         DENSE_RANK() OVER (PARTITION BY tm.Tag ORDER BY qr.OwnerId) AS OwnerDiversity
  FROM tag_metrics tm
  JOIN tagged t ON t.Tag = tm.Tag
  JOIN question_rankings qr ON qr.QuestionId = t.QuestionId
  WHERE qr.CreationDate >= now() - interval '2 years'
),

-- best representative question per tag (top by adjusted score to penalize single-user dominance)
tag_representative AS (
  SELECT Tag,
         QuestionId,
         Title,
         CreationDate,
         PopularityScore,
         OwnerDiversity,
         PopularityScore / GREATEST(1.0, OwnerDiversity::numeric) AS AdjustedScore
  FROM tag_top_questions
  WHERE rn <= 100
),

-- final aggregation combining tag metrics and chosen representatives, with cross-tag similarity via shared top-answer owners
tag_summary AS (
  SELECT tm.Tag,
         tm.QuestionsInWindow,
         tm.AvgQuestionScore,
         tm.TotalViews,
         tm.AvgAnswerCount,
         tm.SumTopAnswerScore,
         tr.QuestionId AS RepresentativeQuestionId,
         tr.Title AS RepresentativeTitle,
         tr.CreationDate AS RepresentativeCreation,
         tr.PopularityScore AS RepresentativePopularity,
         tr.AdjustedScore AS RepresentativeAdjustedScore
  FROM tag_metrics tm
  JOIN LATERAL (
    SELECT *
    FROM tag_representative tr
    WHERE tr.Tag = tm.Tag
    ORDER BY tr.AdjustedScore DESC
    LIMIT 1
  ) tr ON true
),

-- find overlap between top tags by shared highly-scoring users (owners of representative questions)
rep_owners AS (
  SELECT ts.Tag, q.OwnerId AS OwnerId
  FROM tag_summary ts
  JOIN Posts q ON q.Id = ts.RepresentativeQuestionId
  WHERE q.OwnerUserId IS NOT NULL
),

tag_similarity AS (
  SELECT a.Tag AS TagA, b.Tag AS TagB, COUNT(*) AS SharedTopOwners
  FROM rep_owners a
  JOIN rep_owners b ON a.OwnerId = b.OwnerId AND a.Tag <> b.Tag
  GROUP BY a.Tag, b.Tag
),

-- final result: top 50 tags with detailed metrics, representative question, and top 3 similar tags
final_tags AS (
  SELECT ts.*,
         (SELECT json_agg(row_to_json(ss)) FROM (
             SELECT ts2.Tag, ts2.QuestionsInWindow, ts2.TotalViews, ts2.RepresentativeAdjustedScore
             FROM tag_summary ts2
             LEFT JOIN tag_similarity sim ON sim.Taga = ts.Tag AND sim.TagB = ts2.Tag
             WHERE ts2.Tag <> ts.Tag
             ORDER BY COALESCE(sim.SharedTopOwners,0) DESC, ts2.RepresentativeAdjustedScore DESC
             LIMIT 3
         ) ss) AS Top3SimilarTags
  FROM tag_summary ts
  ORDER BY ts.QuestionsInWindow DESC, ts.TotalViews DESC
  LIMIT 50
)

-- select everything for benchmarking: join with recent top users and include many computed columns and sorts
SELECT ft.Tag,
       ft.QuestionsInWindow,
       ft.AvgQuestionScore,
       ft.TotalViews,
       ft.AvgAnswerCount,
       ft.SumTopAnswerScore,
       ft.RepresentativeQuestionId,
       ft.RepresentativeTitle,
       ft.RepresentativeCreation,
       ROUND(ft.RepresentativePopularity,3) AS RepresentativePopularity,
       ROUND(ft.RepresentativeAdjustedScore,3) AS RepresentativeAdjustedScore,
       ft.Top3SimilarTags,
       ru.UserId    AS SampleActiveUserId,
       ru.DisplayName AS SampleActiveUserName,
       ru.Reputation AS SampleActiveUserRep,
       ru.RecentPosts,
       ru.RecentComments,
       ru.RecentUpvotesReceived,
       ROUND(ru.RepPerDay,4) AS SampleUserRepPerDay
FROM final_tags ft
LEFT JOIN LATERAL (
  SELECT rua.*
  FROM recent_user_activity rua
  ORDER BY rua.RecentPosts DESC, rua.RepPerDay DESC
  LIMIT 1
) ru ON true
ORDER BY ft.QuestionsInWindow DESC, ft.TotalViews DESC, ft.RepresentativeAdjustedScore DESC;