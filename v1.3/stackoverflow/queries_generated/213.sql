-- {"query": "213.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4213} 
WITH parsed_tags AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         lower(tag) AS tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags,2,length(p.Tags)-2), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
comments_q AS (
  SELECT c.PostId, count(*) AS CommentCount, max(c.CreationDate) AS LastComment
  FROM Comments c
  GROUP BY c.PostId
),
badge_counts AS (
  SELECT UserId,
         count(*) FILTER (WHERE Class=1) AS Gold,
         count(*) FILTER (WHERE Class=2) AS Silver,
         count(*) FILTER (WHERE Class=3) AS Bronze
  FROM Badges
  GROUP BY UserId
),
tag_question_stats AS (
  SELECT pt.tag,
         count(distinct pt.QuestionId) AS Questions,
         avg(pt.Score) AS AvgScore,
         sum(coalesce(pq.Answers,0)) AS TotalAnswers
  FROM parsed_tags pt
  LEFT JOIN (
    SELECT p.Id, p.Score, (SELECT count(*) FROM Posts a WHERE a.ParentId = p.Id AND a.PostTypeId=2) AS Answers
    FROM Posts p
    WHERE p.PostTypeId = 1
  ) pq ON pq.Id = pt.QuestionId
  GROUP BY pt.tag
),
question_metrics AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate AS QCreated,
         p.Score AS QScore,
         p.ViewCount,
         p.Tags,
         coalesce(a.AnswersCount,0) AS AnswerCount,
         CASE WHEN a.FirstAnswerDate IS NOT NULL THEN extract(epoch FROM (a.FirstAnswerDate - p.CreationDate))::int ELSE NULL END AS SecondsToFirstAnswer,
         accepted_delta.seconds_to_accept,
         coalesce(c.CommentCount,0) AS CommentCount,
         u.DisplayName AS OwnerName,
         u.Reputation,
         bc.Gold, bc.Silver, bc.Bronze,
         regexp_replace(coalesce(p.Title,''), '\s+', ' ', 'g') AS NormalizedTitle,
         (p.Score::numeric * 0.6 +
          (coalesce(a.AnswersCount,0)::numeric * 0.3) +
          (greatest(coalesce(p.ViewCount,0),1)::numeric/1000) * 0.1 -
          (coalesce(c.CommentCount,0)::numeric * 0.05)
         ) AS PopularityScore
  FROM Posts p
  LEFT JOIN LATERAL (
    SELECT count(*) FILTER (WHERE PostTypeId=2) AS AnswersCount,
           min(CreationDate) FILTER (WHERE PostTypeId=2) AS FirstAnswerDate,
           avg(Score) FILTER (WHERE PostTypeId=2) AS AvgAnswerScore
    FROM Posts a
    WHERE a.ParentId = p.Id
  ) a ON true
  LEFT JOIN LATERAL (
    SELECT extract(epoch FROM (aa.CreationDate - p.CreationDate))::int AS seconds_to_accept
    FROM Posts aa
    WHERE aa.Id = p.AcceptedAnswerId
    LIMIT 1
  ) accepted_delta ON true
  LEFT JOIN comments_q c ON c.PostId = p.Id
  LEFT JOIN Users u ON u.Id = p.OwnerUserId
  LEFT JOIN badge_counts bc ON bc.UserId = u.Id
  WHERE p.PostTypeId = 1
),
ranked_questions AS (
  SELECT qm.*,
         row_number() OVER (PARTITION BY pt.tag ORDER BY PopularityScore DESC NULLS LAST, QScore DESC, AnswerCount DESC) AS TagRank,
         dense_rank() OVER (ORDER BY PopularityScore DESC NULLS LAST, QScore DESC) AS GlobalRank
  FROM question_metrics qm
  LEFT JOIN parsed_tags pt ON pt.QuestionId = qm.QuestionId
),
final_top AS (
  SELECT rq.QuestionId,
         rq.NormalizedTitle,
         rq.QCreated,
         rq.OwnerName,
         rq.Reputation,
         rq.Gold, rq.Silver, rq.Bronze,
         rq.PopularityScore,
         rq.QScore,
         rq.AnswerCount,
         rq.SecondsToFirstAnswer,
         rq.SecondsToAccept,
         rq.CommentCount,
         rq.ViewCount,
         string_agg(distinct pt.tag, ',' ORDER BY pt.tag) FILTER (WHERE pt.tag IS NOT NULL) AS Tags,
         rq.TagRank,
         rq.GlobalRank
  FROM ranked_questions rq
  LEFT JOIN parsed_tags pt ON pt.QuestionId = rq.QuestionId
  GROUP BY rq.QuestionId, rq.NormalizedTitle, rq.QCreated, rq.OwnerName, rq.Reputation, rq.Gold, rq.Silver, rq.Bronze,
           rq.PopularityScore, rq.QScore, rq.AnswerCount, rq.SecondsToFirstAnswer, rq.SecondsToAccept,
           rq.CommentCount, rq.ViewCount, rq.TagRank, rq.GlobalRank
  HAVING (rq.PopularityScore > 1 OR rq.AnswerCount = 0)
),
user_recent_stats AS (
  SELECT u.Id AS UserId,
         count(p.Id) AS RecentPosts,
         avg(p.Score) FILTER (WHERE p.PostTypeId=1) AS AvgQuestionScore,
         avg(p.Score) FILTER (WHERE p.PostTypeId=2) AS AvgAnswerScore,
         max(p.CreationDate) AS LastPostDate,
         (SELECT avg(s) FROM (
            SELECT score AS s FROM Posts p2 WHERE p2.OwnerUserId = u.Id ORDER BY p2.CreationDate DESC LIMIT 5
         ) t) AS AvgLast5Scores
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
)
SELECT ft.QuestionId,
       ft.NormalizedTitle,
       ft.QCreated,
       ft.OwnerName,
       ft.Reputation,
       ft.Gold, ft.Silver, ft.Bronze,
       ft.PopularityScore,
       ft.QScore,
       ft.AnswerCount,
       ft.SecondsToFirstAnswer,
       ft.SecondsToAccept,
       ft.CommentCount,
       ft.ViewCount,
       ft.Tags,
       ft.TagRank,
       ft.GlobalRank,
       urs.RecentPosts, urs.AvgQuestionScore, urs.AvgAnswerScore, urs.AvgLast5Scores,
       (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = ft.QuestionId AND pl.LinkTypeId = 3) AS DuplicateCount
FROM final_top ft
LEFT JOIN user_recent_stats urs ON urs.UserId = (SELECT Id FROM Users WHERE DisplayName = ft.OwnerName LIMIT 1)
WHERE ft.GlobalRank <= 500

UNION ALL

SELECT ft2.QuestionId,
       ft2.NormalizedTitle,
       ft2.QCreated,
       ft2.OwnerName,
       ft2.Reputation,
       ft2.Gold, ft2.Silver, ft2.Bronze,
       ft2.PopularityScore,
       ft2.QScore,
       ft2.AnswerCount,
       ft2.SecondsToFirstAnswer,
       ft2.SecondsToAccept,
       ft2.CommentCount,
       ft2.ViewCount,
       ft2.Tags,
       ft2.TagRank,
       ft2.GlobalRank,
       urs2.RecentPosts, urs2.AvgQuestionScore, urs2.AvgAnswerScore, urs2.AvgLast5Scores,
       (SELECT count(*) FROM PostLinks pl WHERE pl.RelatedPostId = ft2.QuestionId AND pl.LinkTypeId = 3) AS DuplicateCount
FROM (
  SELECT * FROM final_top WHERE AnswerCount = 0 ORDER BY QCreated DESC NULLS LAST LIMIT 200
) ft2
LEFT JOIN user_recent_stats urs2 ON urs2.UserId = (SELECT Id FROM Users WHERE DisplayName = ft2.OwnerName LIMIT 1)

ORDER BY PopularityScore DESC NULLS LAST, AnswerCount DESC, GlobalRank
LIMIT 1000;