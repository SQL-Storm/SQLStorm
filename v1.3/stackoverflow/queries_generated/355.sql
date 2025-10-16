-- {"query": "355.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 15560} 
WITH
post_tags AS (
  SELECT p.Id AS PostId,
         lower(sub.tg) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags FROM 2 FOR char_length(p.Tags)-2), '><')) AS tg
  ) AS sub
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND char_length(p.Tags) > 2
),
tag_popularity AS (
  SELECT Tag, count(*) AS TagCount
  FROM post_tags
  GROUP BY Tag
),
votes_agg AS (
  SELECT v.PostId,
         sum(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         sum(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         sum(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
         sum(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyTotal,
         count(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
comments_agg AS (
  SELECT c.PostId,
         count(*) AS CommentCount,
         sum(COALESCE(c.Score,0)) AS CommentScoreSum,
         max(c.CreationDate) AS LastCommentDate,
         substring(max(c.Text) FROM 1 FOR 200) AS LastCommentSnippet
  FROM Comments c
  GROUP BY c.PostId
),
answers_agg AS (
  SELECT p.ParentId AS QuestionId,
         count(*) FILTER (WHERE p.Score > 0) AS PositiveAnswers,
         count(*) FILTER (WHERE p.Score <= 0) AS NonPositiveAnswers,
         max(p.Score) AS MaxAnswerScore,
         sum(p.Score) AS SumAnswerScore,
         avg(p.Score) AS AvgAnswerScore,
         count(*) AS AnswerCountAll,
         min(p.CreationDate) AS FirstAnswerDate,
         max(p.CreationDate) AS LastAnswerDate
  FROM Posts p
  WHERE p.PostTypeId = 2
  GROUP BY p.ParentId
),
post_history_latest AS (
  SELECT ph.PostId,
         ph.PostHistoryTypeId,
         pht.Name AS PostHistoryTypeName,
         ph.CreationDate AS LastHistoryDate,
         ph.UserId AS LastHistoryUserId,
         ph.Text AS LastHistoryText
  FROM (
    SELECT *,
           row_number() OVER (PARTITION BY PostId ORDER BY CreationDate DESC NULLS LAST, Id DESC) AS rn
    FROM PostHistory
  ) ph
  LEFT JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
  WHERE ph.rn = 1
),
user_posts AS (
  SELECT OwnerUserId AS UserId,
         count(*) FILTER (WHERE PostTypeId = 1) AS QuestionsAsked,
         count(*) FILTER (WHERE PostTypeId = 2) AS AnswersGiven,
         coalesce(sum(Score),0) AS TotalPostScore
  FROM Posts
  WHERE OwnerUserId IS NOT NULL
  GROUP BY OwnerUserId
),
user_badges AS (
  SELECT UserId,
         max(Date) AS LastBadgeDate,
         array_to_string(array_agg(DISTINCT Name), ', ') AS Badges
  FROM Badges
  GROUP BY UserId
),
user_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         coalesce(up.QuestionsAsked,0) AS QuestionsAsked,
         coalesce(up.AnswersGiven,0) AS AnswersGiven,
         coalesce(up.TotalPostScore,0) AS TotalPostScore,
         ub.LastBadgeDate,
         ub.Badges
  FROM Users u
  LEFT JOIN user_posts up ON up.UserId = u.Id
  LEFT JOIN user_badges ub ON ub.UserId = u.Id
),
top_answer_metrics AS (
  SELECT p.Id AS AnswerId,
         p.ParentId AS QuestionId,
         p.OwnerUserId,
         p.Score AS AnswerScore,
         coalesce(vs.UpVotes,0) AS AnswerUpVotes,
         coalesce(vs.DownVotes,0) AS AnswerDownVotes,
         q.Title as QuestionTitle,
         row_number() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC) AS AnswerRank
  FROM Posts p
  LEFT JOIN votes_agg vs ON vs.PostId = p.Id
  LEFT JOIN Posts q ON q.Id = p.ParentId
  WHERE p.PostTypeId = 2
),
question_metrics AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.OwnerUserId,
         COALESCE(u.DisplayName, p.OwnerDisplayName) AS OwnerName,
         p.Score,
         p.ViewCount,
         coalesce(va.UpVotes,0) AS UpVotes,
         coalesce(va.DownVotes,0) AS DownVotes,
         coalesce(va.Favorites,0) AS Favorites,
         coalesce(va.BountyTotal,0) AS BountyTotal,
         coalesce(ca.CommentCount,0) AS CommentCount,
         coalesce(aa.AnswerCountAll,0) AS AnswerCount,
         coalesce(aa.MaxAnswerScore,0) AS MaxAnswerScore,
         coalesce(aa.SumAnswerScore,0) AS SumAnswerScore,
         coalesce(aa.FirstAnswerDate,p.CreationDate) AS FirstAnswerDate,
         coalesce(phlt.PostHistoryTypeName, 'None') AS LastHistoryType,
         phlt.LastHistoryDate,
         t.tags AS TagsArray,
         t.tag_count AS TagCount,
         t.tag_popularity_sum,
         greatest(extract(epoch from (now() - p.CreationDate))/86400.0, 0.0001) AS AgeDays,
         (
           ln(coalesce(p.ViewCount,0)+1) * (coalesce(p.Score,0)+1) * sqrt(coalesce(p.AnswerCount,0)+1)
         ) / greatest(extract(epoch from (now() - p.CreationDate))/86400.0, 1/86400.0)
           + (coalesce(va.BountyTotal,0) * 10)
           + ((coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0)) * 0.5)
           + (coalesce(ca.CommentCount,0) * 0.2)
           + (coalesce(aa.MaxAnswerScore,0) * 0.1)
           + (coalesce(t.tag_popularity_sum,0) * 0.05) AS HotnessRaw,
         coalesce( (coalesce(p.Score,0)::numeric) / nullif(us.TotalPostScore,0), 0) AS UserScoreShare,
         (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateAsTarget,
         (SELECT count(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateAsSource,
         (SELECT count(DISTINCT a2.OwnerUserId) FROM Posts a2 WHERE a2.ParentId = p.Id AND a2.PostTypeId = 2 AND a2.OwnerUserId IS NOT NULL) AS DistinctAnswerers,
         (SELECT count(*) FROM Comments c2 WHERE c2.PostId = p.Id AND c2.Text ILIKE '%thank%') AS ThankComments,
         (SELECT avg(char_length(ph2.Text)) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.Text IS NOT NULL) AS AvgRevisionLength
  FROM Posts p
  LEFT JOIN votes_agg va ON va.PostId = p.Id
  LEFT JOIN comments_agg ca ON ca.PostId = p.Id
  LEFT JOIN answers_agg aa ON aa.QuestionId = p.Id
  LEFT JOIN post_history_latest phlt ON phlt.PostId = p.Id
  LEFT JOIN user_stats us ON us.UserId = p.OwnerUserId
  LEFT JOIN (
    SELECT pt.PostId,
           array_agg(pt.Tag ORDER BY pt.Tag) AS tags,
           count(pt.Tag) AS tag_count,
           sum(tp.TagCount) AS tag_popularity_sum
    FROM post_tags pt
    LEFT JOIN tag_popularity tp ON tp.Tag = pt.Tag
    GROUP BY pt.PostId
  ) t ON t.PostId = p.Id
  WHERE p.PostTypeId = 1
),
ranked_questions AS (
  SELECT qm.*,
         rank() OVER (ORDER BY qm.HotnessRaw DESC NULLS LAST) AS GlobalRank,
         row_number() OVER (PARTITION BY (CASE WHEN qm.TagsArray IS NULL THEN '' ELSE qm.TagsArray[1] END) ORDER BY qm.HotnessRaw DESC NULLS LAST) AS TagTopRank,
         dense_rank() OVER (PARTITION BY qm.OwnerUserId ORDER BY qm.HotnessRaw DESC NULLS LAST) AS OwnerHotRank,
         avg(qm.HotnessRaw) OVER (PARTITION BY qm.OwnerUserId) AS OwnerHotAvg,
         sum(qm.CommentCount) OVER (PARTITION BY qm.OwnerUserId) AS OwnerCommentSum
  FROM question_metrics qm
),
hot_slices AS (
  SELECT QuestionId FROM ranked_questions ORDER BY HotnessRaw DESC NULLS LAST LIMIT 200
  UNION ALL
  SELECT QuestionId FROM ranked_questions WHERE AgeDays < 30 ORDER BY HotnessRaw DESC NULLS LAST LIMIT 200
),
qa_pairs AS (
  SELECT
    COALESCE(rq.QuestionId, ta.QuestionId) AS QuestionId,
    COALESCE(rq.Title, ta.QuestionTitle) AS Title,
    rq.CreationDate,
    rq.OwnerUserId,
    rq.OwnerName,
    rq.Score,
    rq.ViewCount,
    rq.UpVotes,
    rq.DownVotes,
    rq.Favorites,
    rq.BountyTotal,
    rq.CommentCount,
    rq.AnswerCount,
    rq.MaxAnswerScore,
    rq.TagsArray,
    rq.TagCount,
    rq.tag_popularity_sum,
    rq.HotnessRaw,
    rq.GlobalRank,
    rq.TagTopRank,
    rq.UserScoreShare,
    rq.DuplicateAsTarget,
    rq.DuplicateAsSource,
    rq.DistinctAnswerers,
    rq.ThankComments,
    rq.AvgRevisionLength,
    rq.LastHistoryType,
    rq.LastHistoryDate,
    ta.AnswerId,
    ta.AnswerScore,
    ta.AnswerUpVotes,
    ta.AnswerDownVotes,
    ta.AnswerRank
  FROM ranked_questions rq
  FULL OUTER JOIN (
    SELECT * FROM top_answer_metrics WHERE AnswerRank = 1
  ) ta ON rq.QuestionId = ta.QuestionId
)
SELECT
  (CASE WHEN qa.AnswerId IS NULL THEN 'question' ELSE 'qa_pair' END) AS item_kind,
  qa.QuestionId,
  qa.Title,
  qa.OwnerUserId,
  qa.OwnerName,
  qa.Score,
  qa.ViewCount,
  qa.UpVotes,
  qa.DownVotes,
  qa.Favorites,
  qa.BountyTotal,
  qa.CommentCount,
  qa.AnswerCount,
  qa.MaxAnswerScore,
  qa.TagsArray,
  qa.TagCount,
  qa.tag_popularity_sum,
  qa.HotnessRaw,
  qa.GlobalRank,
  qa.TagTopRank,
  qa.UserScoreShare,
  qa.DuplicateAsTarget,
  qa.DuplicateAsSource,
  qa.DistinctAnswerers,
  qa.ThankComments,
  qa.AvgRevisionLength,
  qa.LastHistoryType,
  qa.LastHistoryDate,
  qa.AnswerId,
  qa.AnswerScore,
  qa.AnswerUpVotes,
  qa.AnswerDownVotes,
  qa.AnswerRank
FROM qa_pairs qa
WHERE (
        qa.HotnessRaw IS NOT NULL AND qa.HotnessRaw > 0
      ) OR (
        qa.AnswerScore IS NOT NULL AND qa.AnswerScore >= (SELECT COALESCE(max(AnswerScore),0) FROM top_answer_metrics) / 4
      ) OR (
        qa.QuestionId IN (SELECT QuestionId FROM hot_slices)
      )
ORDER BY qa.HotnessRaw DESC NULLS LAST, qa.AnswerScore DESC NULLS LAST
LIMIT 500;