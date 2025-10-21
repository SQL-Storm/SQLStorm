-- {"query": "37060.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1885} 
WITH
-- recent active questions with tags exploded
questions AS (
  SELECT p.Id AS QuestionId,
         p.Title,
         p.CreationDate,
         p.OwnerUserId,
         p.Score,
         p.ViewCount,
         p.AnswerCount,
         p.FavoriteCount,
         regexp_split_to_table(substring(coalesce(p.Tags,''),2,length(coalesce(p.Tags,''))-2), '><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
-- top answer per question (by score, tie-breaker: most recent)
top_answers AS (
  SELECT a.ParentId AS QuestionId,
         a.Id AS AnswerId,
         a.OwnerUserId AS AnswerOwner,
         a.Score AS AnswerScore,
         a.CreationDate AS AnswerCreationDate,
         row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate DESC, a.Id) AS rn
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.CreationDate >= now() - interval '2 years'
),
top_answer_selected AS (
  SELECT * FROM top_answers WHERE rn = 1
),
-- recent comments aggregated per post
comments_agg AS (
  SELECT c.PostId,
         count(*) FILTER (WHERE c.CreationDate >= now() - interval '30 days') AS RecentComments30d,
         count(*) FILTER (WHERE c.CreationDate >= now() - interval '365 days') AS RecentComments365d,
         max(c.CreationDate) AS LastCommentDate,
         string_agg(DISTINCT substring(coalesce(c.UserDisplayName, (SELECT DisplayName FROM Users u WHERE u.Id = c.UserId)::text),1,30), ', ' ORDER BY max(c.CreationDate) DESC) AS RecentCommentersSample
  FROM Comments c
  GROUP BY c.PostId
),
-- votes breakdown per post
votes_agg AS (
  SELECT v.PostId,
         count(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
         count(*) FILTER (WHERE v.VoteTypeId = 1) AS AcceptedByOwner,
         count(*) AS TotalVotes,
         max(v.CreationDate) AS LastVoteDate
  FROM Votes v
  WHERE v.CreationDate >= now() - interval '2 years' OR v.CreationDate IS NULL
  GROUP BY v.PostId
),
-- link relationships: duplicates and linked counts
links_agg AS (
  SELECT pl.PostId,
         count(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateTargetCount,
         count(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedOutCount,
         count(*) AS TotalLinks
  FROM PostLinks pl
  GROUP BY pl.PostId
),
-- user summary statistics
user_stats AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate AS UserCreated,
         u.LastAccessDate,
         u.Views AS ProfileViews,
         count(distinct b.Id) FILTER (WHERE b.Date >= now() - interval '365 days') AS BadgesLastYear,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= now() - interval '2 years') AS QuestionsLast2y,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= now() - interval '2 years') AS AnswersLast2y,
         coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) FILTER (WHERE v.CreationDate >= now() - interval '2 years') AS UpVotesCast2y
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  LEFT JOIN Posts p ON (p.OwnerUserId = u.Id)
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
-- tag popularity over last 2 years (questions only)
tag_stats AS (
  SELECT q.Tag,
         count(*) AS QuestionsCount,
         avg(q.Score) AS AvgQuestionScore,
         avg(q.ViewCount) AS AvgQuestionViews,
         count(distinct q.OwnerUserId) AS DistinctAskers
  FROM questions q
  GROUP BY q.Tag
),
-- assemble primary dataset: questions joined to top answers, votes, comments, links, and user stats
base AS (
  SELECT q.QuestionId,
         q.Title,
         q.Tag,
         q.CreationDate AS QuestionCreation,
         q.OwnerUserId,
         q.Score AS QuestionScore,
         q.ViewCount AS QuestionViews,
         q.AnswerCount,
         q.FavoriteCount,
         ta.AnswerId,
         ta.AnswerOwner,
         ta.AnswerScore,
         ta.AnswerCreationDate,
         coalesce(vu.UpVotes,0) AS QuestionUpVotes,
         coalesce(vu.DownVotes,0) AS QuestionDownVotes,
         coalesce(ca.RecentComments30d,0) AS RecentComments30d,
         coalesce(ca.RecentComments365d,0) AS RecentComments365d,
         coalesce(la.DuplicateTargetCount,0) AS DuplicateTargetCount,
         coalesce(ts.QuestionsCount,0) AS TagQuestionsCount,
         us.DisplayName AS AskerName,
         us.Reputation AS AskerReputation,
         us.BadgesLastYear
  FROM questions q
  LEFT JOIN top_answer_selected ta ON ta.QuestionId = q.QuestionId
  LEFT JOIN votes_agg vu ON vu.PostId = q.QuestionId
  LEFT JOIN comments_agg ca ON ca.PostId = q.QuestionId
  LEFT JOIN links_agg la ON la.PostId = q.QuestionId
  LEFT JOIN tag_stats ts ON ts.Tag = q.Tag
  LEFT JOIN user_stats us ON us.UserId = q.OwnerUserId
),
-- identify "fast answered" questions: first answer within 24 hours
first_answer AS (
  SELECT a.ParentId AS QuestionId,
         min(a.CreationDate) AS FirstAnswerDate,
         min(a.CreationDate) - q.CreationDate AS TimeToFirstAnswer
  FROM Posts a
  JOIN Posts q ON q.Id = a.ParentId AND q.PostTypeId = 1
  WHERE a.PostTypeId = 2
    AND q.CreationDate >= now() - interval '2 years'
  GROUP BY a.ParentId
),
fast_answered AS (
  SELECT fa.QuestionId
  FROM first_answer fa
  WHERE fa.TimeToFirstAnswer <= interval '24 hours'
),
-- scoring function to rank questions for benchmarking (complex expression)
ranked AS (
  SELECT b.*,
         ( -- composite score with non-linear weights and penalizations
           0.35 * (log(1 + greatest(b.QuestionViews,0)) / log(10))  -- view-driven term
           + 0.25 * (power(greatest(b.QuestionScore,0), 0.8))      -- score-driven term
           + 0.20 * (coalesce(b.AnswerScore,0) * 0.7)             -- top answer contribution
           + 0.10 * (case when b.DuplicateTargetCount > 0 then -2 else 1 end)  -- duplicates penalized
           + 0.10 * (least(1.0, greatest(b.BadgesLastYear::numeric / NULLIF(b.TagQuestionsCount,0), 0))) -- asker provenance normalized
         )
         * (case when fa.QuestionId IS NOT NULL then 1.25 else 1 end) -- boost if fast answered
         AS CompositeScore
  FROM base b
  LEFT JOIN fast_answered fa ON fa.QuestionId = b.QuestionId
)
SELECT
  r.QuestionId,
  left(r.Title,200) AS TitleSample,
  r.Tag,
  r.QuestionCreation,
  r.AskerName,
  r.AskerReputation,
  r.QuestionScore,
  r.QuestionViews,
  r.AnswerId,
  r.AnswerScore,
  r.RecentComments30d,
  r.RecentComments365d,
  r.DuplicateTargetCount,
  r.TagQuestionsCount,
  round(r.CompositeScore::numeric,4) AS CompositeScore,
  dense_rank() OVER (PARTITION BY r.Tag ORDER BY r.CompositeScore DESC) AS TagRank,
  rank() OVER (ORDER BY r.CompositeScore DESC) AS GlobalRank
FROM ranked r
WHERE r.QuestionViews IS NOT NULL
ORDER BY r.CompositeScore DESC, r.QuestionViews DESC
LIMIT 1000;