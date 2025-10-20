-- {"query": "37097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1981} 
WITH
-- recent active questions with tags exploded
QuestionBase AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.CommentCount,
         p.OwnerUserId,
         p.AcceptedAnswerId,
         COALESCE(p.Tags, '') AS TagsRaw
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '5 years'
),
ExplodedTags AS (
  SELECT q.*,
         trim(both '<>' FROM tag) AS Tag
  FROM QuestionBase q,
       unnest(string_to_array(substring(q.TagsRaw from 2 for greatest(length(q.TagsRaw)-2,0)), '><')) AS tag
),
-- tag popularity and median score per tag
TagStats AS (
  SELECT et.Tag,
         count(*) AS QuestionCount,
         avg(et.Score) AS AvgScore,
         percentile_cont(0.5) WITHIN GROUP (ORDER BY et.Score) AS MedianScore,
         sum(et.ViewCount) AS TotalViews,
         sum(et.AnswerCount) AS TotalAnswers
  FROM ExplodedTags et
  GROUP BY et.Tag
  HAVING count(*) >= 50
),
-- user aggregates: reputation, activity, badges, answers accepted ratio, vote behavior
UserActivity AS (
  SELECT u.Id AS UserId,
         u.Reputation,
         u.CreationDate,
         u.DisplayName,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
         count(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesCast,
         count(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesCast,
         coalesce(sum(case when a.OwnerUserId = u.Id AND q.AcceptedAnswerId = a.Id then 1 else 0 end),0) AS AcceptedAsAnswerCount,
         coalesce(count(a.Id),0) FILTER (WHERE a.OwnerUserId = u.Id) AS TotalAnswersByUser,
         -- ratio of accepted answers among user's answers (null-safe)
         CASE WHEN count(a.Id) FILTER (WHERE a.OwnerUserId = u.Id) = 0 THEN 0
              ELSE coalesce(sum(case when a.OwnerUserId = u.Id AND q.AcceptedAnswerId = a.Id then 1 else 0 end),0)::numeric
                   / count(a.Id) FILTER (WHERE a.OwnerUserId = u.Id)
         END AS AcceptedAnswerRatio,
         max(p.LastActivityDate) AS LastActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.PostTypeId = 2 AND a.OwnerUserId = u.Id
  LEFT JOIN Posts q ON q.PostTypeId = 1 AND q.AcceptedAnswerId = a.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName
),
-- compute per-user tag expertise by counting answers per tag and average score of those answers
UserTagExpertise AS (
  SELECT ua.UserId,
         et.Tag,
         count(a.Id) AS AnswersForTag,
         avg(a.Score) AS AvgAnswerScoreForTag,
         max(a.CreationDate) AS LastAnsweredAt
  FROM ExplodedTags et
  JOIN Posts q ON q.Id = et.QuestionId
  JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  JOIN Users ua ON ua.Id = a.OwnerUserId
  GROUP BY ua.UserId, et.Tag
  HAVING count(a.Id) >= 5
),
-- combine tag top experts
TopExpertsPerTag AS (
  SELECT ute.Tag,
         ute.UserId,
         ute.AnswersForTag,
         ute.AvgAnswerScoreForTag,
         ua.Reputation,
         ua.AcceptedAnswerRatio,
         row_number() OVER (PARTITION BY ute.Tag ORDER BY ute.AnswersForTag DESC, ute.AvgAnswerScoreForTag DESC, ua.Reputation DESC) AS RankInTag
  FROM UserTagExpertise ute
  JOIN UserActivity ua ON ua.UserId = ute.UserId
),
-- interesting post links: duplicates and referenced posts graph (two-hop)
DirectLinks AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId
  FROM PostLinks pl
  WHERE pl.CreationDate >= now() - interval '5 years'
),
TwoHopLinks AS (
  SELECT d1.PostId AS SourcePost,
         d2.RelatedPostId AS TwoHopTarget,
         count(*) AS TwoHopPaths
  FROM DirectLinks d1
  JOIN DirectLinks d2 ON d1.RelatedPostId = d2.PostId
  WHERE d1.PostId <> d2.RelatedPostId
  GROUP BY d1.PostId, d2.RelatedPostId
  HAVING count(*) >= 2
),
-- posts with rich signals: score, views, comments, recent activity, hotness heuristic
Hotness AS (
  SELECT p.Id,
         p.Title,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.CommentCount,
         p.AnswerCount,
         p.OwnerUserId,
         (p.Score * 3 + coalesce(p.ViewCount,0)::numeric/100 + coalesce(p.CommentCount,0)*2 + coalesce(p.AnswerCount,0)*5)
           / greatest(1, extract(epoch from (now() - p.CreationDate))/3600) AS HotnessScore
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
-- assemble final heavy join: for popular tags pick top questions, attach top experts, link graph stats and recent history edits
RecentHistoryEdits AS (
  SELECT ph.PostId,
         ph.UserId AS EditorUserId,
         ph.PostHistoryTypeId,
         ph.CreationDate AS EditDate,
         ph.Comment AS EditComment,
         row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  WHERE ph.CreationDate >= now() - interval '1 year'
),
TopTagQuestions AS (
  SELECT ts.Tag, q.*
  FROM TagStats ts
  JOIN ExplodedTags et ON et.Tag = ts.Tag
  JOIN Posts q ON q.Id = et.QuestionId
  WHERE q.PostTypeId = 1
    AND q.Score >= (SELECT percentile_cont(0.75) WITHIN GROUP (ORDER BY p.Score) FROM Posts p WHERE p.PostTypeId = 1)
),
-- final selection with multiple window functions, aggregates and lateral computations
Final AS (
  SELECT tt.Tag,
         tt.Id AS QuestionId,
         tt.Title,
         tt.CreationDate,
         tt.Score,
         tt.ViewCount,
         tt.AnswerCount,
         tt.CommentCount,
         ts.QuestionCount AS TagQuestionCount,
         ts.AvgScore AS TagAvgScore,
         ts.MedianScore AS TagMedianScore,
         he.HotnessScore,
         -- top 3 experts for the tag as a comma separated summary
         (SELECT string_agg(format('%s(%s answers, rep=%s, acc=%.2f)', u.DisplayName, te.AnswersForTag, ua.Reputation, ua.AcceptedAnswerRatio), '; ')
          FROM TopExpertsPerTag te
          JOIN Users u ON u.Id = te.UserId
          JOIN UserActivity ua ON ua.UserId = te.UserId
          WHERE te.Tag = tt.Tag AND te.RankInTag <= 3
         ) AS TopExpertsSummary,
         th.TwoHopTargets,
         ph.EditorsLastYear,
         row_number() OVER (PARTITION BY tt.Tag ORDER BY he.HotnessScore DESC NULLS LAST) AS RankInTagByHotness,
         dense_rank() OVER (ORDER BY ts.QuestionCount DESC) AS TagPopularityRank
  FROM TopTagQuestions tt
  JOIN TagStats ts ON ts.Tag = tt.Tag
  LEFT JOIN Hotness he ON he.Id = tt.Id
  LEFT JOIN LATERAL (
     SELECT count(*) AS TwoHopTargets
     FROM TwoHopLinks thl
     WHERE thl.SourcePost = tt.Id
  ) th ON true
  LEFT JOIN LATERAL (
     SELECT string_agg(distinct u.DisplayName || ':' || to_char(rnph.EditDate, 'YYYY-MM-DD'), ', ') AS EditorsLastYear
     FROM (
       SELECT ph.PostId, ph.UserId, ph.CreationDate AS EditDate, row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rnph
       FROM PostHistory ph
       WHERE ph.PostId = tt.Id
         AND ph.CreationDate >= now() - interval '1 year'
     ) ph
     JOIN Users u ON u.Id = ph.UserId
     WHERE ph.rnph <= 5
  ) ph ON true
)
SELECT *
FROM Final
ORDER BY TagPopularityRank, Tag, RankInTagByHotness
LIMIT 100;