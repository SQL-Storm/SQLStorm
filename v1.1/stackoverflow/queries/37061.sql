WITH
questions AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.Tags,
         (CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN CAST(ARRAY[] AS varchar[]) ELSE string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><') END) AS TagArray,
         p.AnswerCount,
         p.CommentCount,
         p.FavoriteCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
answers AS (
  SELECT a.Id AS AnswerId,
         a.ParentId AS QuestionId,
         a.OwnerUserId AS AnswererId,
         a.CreationDate AS AnswerDate,
         a.Score AS AnswerScore,
         a.CommentCount AS AnswerCommentCount,
         a.Body AS AnswerBody
  FROM Posts a
  WHERE a.PostTypeId = 2
),
best_answer AS (
  SELECT DISTINCT ON (q.QuestionId)
         q.QuestionId,
         a.AnswerId,
         a.AnswererId,
         a.AnswerDate,
         a.AnswerScore
  FROM questions q
  JOIN answers a ON a.QuestionId = q.QuestionId
  ORDER BY q.QuestionId, a.AnswerScore DESC, a.AnswerDate ASC
),
activity_windows AS (
  SELECT q.QuestionId,
         count(DISTINCT a.AnswerId) FILTER (WHERE a.AnswerDate >= q.CreationDate AND a.AnswerDate < q.CreationDate + interval '7 days') AS Answers_7d,
         count(DISTINCT a.AnswerId) FILTER (WHERE a.AnswerDate >= q.CreationDate AND a.AnswerDate < q.CreationDate + interval '30 days') AS Answers_30d,
         count(DISTINCT v.Id) FILTER (WHERE v.CreationDate >= q.CreationDate AND v.CreationDate < q.CreationDate + interval '30 days' AND v.VoteTypeId = 2) AS Upvotes_30d,
         count(c.Id) FILTER (WHERE c.CreationDate >= q.CreationDate AND c.CreationDate < q.CreationDate + interval '30 days') AS Comments_30d
  FROM questions q
  LEFT JOIN answers a ON a.QuestionId = q.QuestionId
  LEFT JOIN Votes v ON v.PostId = q.QuestionId
  LEFT JOIN Comments c ON c.PostId = q.QuestionId
  GROUP BY q.QuestionId
),
tag_pairs AS (
  SELECT t1.tag AS tag,
         t2.tag AS co_tag,
         count(*) AS pair_count,
         avg(q.Score) AS avg_question_score
  FROM (
    SELECT QuestionId, unnest(TagArray) AS tag
    FROM questions
  ) t1
  JOIN (
    SELECT QuestionId, unnest(TagArray) AS tag
    FROM questions
  ) t2 ON t1.QuestionId = t2.QuestionId AND t1.tag <> t2.tag
  JOIN questions q ON q.QuestionId = t1.QuestionId
  GROUP BY t1.tag, t2.tag
),
answerer_stats AS (
  SELECT a.OwnerUserId AS UserId,
         count(*) FILTER (WHERE a.Score >= 5) AS HighScoreAnswers,
         count(*) AS TotalAnswers,
         avg(a.Score) AS AvgAnswerScore,
         max(a.Score) AS MaxAnswerScore,
         percentile_cont(0.75) WITHIN GROUP (ORDER BY a.Score) AS P75Score
  FROM Posts a
  WHERE a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
  GROUP BY a.OwnerUserId
),
ranked_questions AS (
  SELECT q.QuestionId,
         q.Title,
         q.CreationDate,
         q.OwnerUserId,
         q.Score,
         q.ViewCount,
         q.Tags,
         q.TagArray,
         q.AnswerCount,
         q.CommentCount,
         q.FavoriteCount,
         bw.Answers_7d,
         bw.Answers_30d,
         bw.Upvotes_30d,
         bw.Comments_30d,
         ba.AnswerId AS BestAnswerId,
         ba.AnswererId,
         ba.AnswerScore AS BestAnswerScore,
         COALESCE(ansr.HighScoreAnswers,0) AS AnswererHighScoreAnswers,
         COALESCE(ansr.TotalAnswers,0) AS AnswererTotalAnswers,
         COALESCE(ansr.AvgAnswerScore,0) AS AnswererAvgScore,
         (
           GREATEST(q.Score,0) * 1.5
           + GREATEST(q.ViewCount,0) / NULLIF(GREATEST(EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - q.CreationDate))/86400,1),0) * 0.05
           + (bw.Answers_7d * 3.0) + (bw.Answers_30d * 1.0)
           + bw.Upvotes_30d * 2.0
           + bw.Comments_30d * 0.8
           + COALESCE(ba.AnswerScore,0) * 2.5
           + COALESCE(ansr.AvgAnswerScore,0) * 1.2
           + LEAST(COALESCE(ansr.HighScoreAnswers,0),20) * 0.7
         ) AS HotnessScore
  FROM questions q
  LEFT JOIN activity_windows bw ON bw.QuestionId = q.QuestionId
  LEFT JOIN best_answer ba ON ba.QuestionId = q.QuestionId
  LEFT JOIN answerer_stats ansr ON ansr.UserId = ba.AnswererId
),
question_tag_signals AS (
  SELECT q.QuestionId,
         (SELECT array_agg(tp.co_tag ORDER BY tp.pair_count DESC, tp.avg_question_score DESC)
          FROM (
            SELECT co_tag, pair_count, avg_question_score
            FROM tag_pairs tp
            WHERE tp.tag = (SELECT unnest(q.TagArray) LIMIT 1)
            ORDER BY pair_count DESC
            LIMIT 10
          ) tp
         ) AS TopCoTags
  FROM questions q
  GROUP BY q.QuestionId, q.TagArray
)
SELECT q.QuestionId,
       q.Title,
       q.CreationDate,
       q.OwnerUserId,
       q.Score,
       q.ViewCount,
       q.TagArray,
       r.Answers_7d,
       r.Answers_30d,
       r.Upvotes_30d,
       r.Comments_30d,
       r.BestAnswerId,
       r.AnswererId,
       r.BestAnswerScore,
       r.AnswererHighScoreAnswers,
       r.AnswererAvgScore,
       q.FavoriteCount,
       q.AnswerCount,
       q.CommentCount,
       (q.Tags IS NOT NULL) AS HasBody,
       (SELECT count(*) FROM PostLinks pl WHERE pl.PostId = q.QuestionId) AS OutboundLinks,
       (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = q.QuestionId) AS InboundLinks,
       qs.TopCoTags,
       r.HotnessScore,
       row_number() OVER (PARTITION BY date_trunc('week', q.CreationDate) ORDER BY r.HotnessScore DESC, q.ViewCount DESC) AS WeeklyRank,
       dense_rank() OVER (ORDER BY r.HotnessScore DESC NULLS LAST) AS GlobalDenseRank
FROM ranked_questions r
JOIN questions q ON q.QuestionId = r.QuestionId
LEFT JOIN question_tag_signals qs ON qs.QuestionId = q.QuestionId
WHERE q.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - interval '365 days'
  AND (r.HotnessScore IS NOT NULL AND r.HotnessScore > 5)
GROUP BY q.QuestionId,
         q.Title,
         q.CreationDate,
         q.OwnerUserId,
         q.Score,
         q.ViewCount,
         q.TagArray,
         r.Answers_7d,
         r.Answers_30d,
         r.Upvotes_30d,
         r.Comments_30d,
         r.BestAnswerId,
         r.AnswererId,
         r.BestAnswerScore,
         r.AnswererHighScoreAnswers,
         r.AnswererAvgScore,
         q.FavoriteCount,
         q.AnswerCount,
         q.CommentCount,
         q.Tags,
         qs.TopCoTags,
         r.HotnessScore
ORDER BY date_trunc('week', q.CreationDate) DESC, r.HotnessScore DESC
LIMIT 500;