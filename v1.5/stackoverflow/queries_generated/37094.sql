-- {"query": "37094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2361} 
WITH
-- tag explosion: explode Tags into one tag per row
QuestionTags AS (
  SELECT p.Id AS QuestionId,
         p.CreationDate,
         p.Score,
         p.ViewCount,
         p.OwnerUserId,
         regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), '><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
-- aggregate per tag: top questions and activity windows
TagQuestionStats AS (
  SELECT
    qt.Tag,
    count(*) AS QuestionCount,
    avg(qt.Score) AS AvgScore,
    avg(qt.ViewCount) AS AvgViews,
    max(qt.Score) FILTER (WHERE qt.CreationDate >= now() - interval '30 days') AS MaxScoreLast30d,
    count(*) FILTER (WHERE qt.CreationDate >= now() - interval '30 days') AS QuestionsLast30d
  FROM QuestionTags qt
  GROUP BY qt.Tag
),
-- compute user engagement per tag: answers, comments, votes
Answers AS (
  SELECT a.Id AS AnswerId, a.ParentId AS QuestionId, a.CreationDate, a.Score, a.OwnerUserId
  FROM Posts a
  WHERE a.PostTypeId = 2
),
TagAnswers AS (
  SELECT qt.Tag, a.AnswerId, a.QuestionId, a.CreationDate, a.Score, a.OwnerUserId
  FROM Answers a
  JOIN QuestionTags qt ON qt.QuestionId = a.QuestionId
),
TagAnswerStats AS (
  SELECT
    ta.Tag,
    count(*) AS AnswerCount,
    avg(ta.Score) AS AvgAnswerScore,
    count(*) FILTER (WHERE ta.CreationDate >= now() - interval '30 days') AS AnswersLast30d,
    count(DISTINCT ta.OwnerUserId) AS DistinctAnswerers
  FROM TagAnswers ta
  GROUP BY ta.Tag
),
-- comment activity: comments on questions and answers per tag
PostComments AS (
  SELECT c.Id AS CommentId, c.PostId, c.CreationDate, c.UserId
  FROM Comments c
),
TagComments AS (
  SELECT qt.Tag, pc.CommentId, pc.PostId, pc.CreationDate, pc.UserId
  FROM PostComments pc
  JOIN QuestionTags qt ON qt.QuestionId = pc.PostId
),
TagCommentStats AS (
  SELECT
    tc.Tag,
    count(*) AS CommentCount,
    count(DISTINCT tc.UserId) AS DistinctCommenters,
    count(*) FILTER (WHERE tc.CreationDate >= now() - interval '7 days') AS CommentsLast7d
  FROM TagComments tc
  GROUP BY tc.Tag
),
-- vote summaries for posts under each tag
PostVotes AS (
  SELECT v.Id AS VoteId, v.PostId, v.VoteTypeId, v.UserId, v.CreationDate
  FROM Votes v
),
TagVoteStats AS (
  SELECT
    qt.Tag,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) AS UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) AS DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) AS Favorites,
    count(*) AS TotalVotes,
    sum(case when v.CreationDate >= now() - interval '30 days' AND v.VoteTypeId IN (2,3) then 1 else 0 end) AS VotesLast30d
  FROM QuestionTags qt
  JOIN PostVotes v ON v.PostId = qt.QuestionId
  GROUP BY qt.Tag
),
-- badge signals: top badge recipients per tag (tag-based badges only)
TagBadges AS (
  SELECT t.TagName AS Tag, b.UserId, b.Date
  FROM Badges b
  JOIN Tags t ON t.TagName = substring(b.Name from '^[^ ]+')
  WHERE b.TagBased = 1 AND t.TagName IS NOT NULL
),
BadgeCounts AS (
  SELECT tb.Tag, count(*) AS BadgeCount, count(DISTINCT tb.UserId) AS BadgeHolders
  FROM TagBadges tb
  GROUP BY tb.Tag
),
-- heavy join: combine all per-tag metrics
TagRollup AS (
  SELECT
    ts.Tag,
    ts.QuestionCount,
    ts.AvgScore,
    ts.AvgViews,
    ts.MaxScoreLast30d,
    ts.QuestionsLast30d,
    COALESCE(ta.AnswerCount,0) AS AnswerCount,
    COALESCE(ta.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(ta.AnswersLast30d,0) AS AnswersLast30d,
    COALESCE(ta.DistinctAnswerers,0) AS DistinctAnswerers,
    COALESCE(tc.CommentCount,0) AS CommentCount,
    COALESCE(tc.DistinctCommenters,0) AS DistinctCommenters,
    COALESCE(tc.CommentsLast7d,0) AS CommentsLast7d,
    COALESCE(tv.UpVotes,0) AS UpVotes,
    COALESCE(tv.DownVotes,0) AS DownVotes,
    COALESCE(tv.Favorites,0) AS Favorites,
    COALESCE(tv.TotalVotes,0) AS TotalVotes,
    COALESCE(tv.VotesLast30d,0) AS VotesLast30d,
    COALESCE(bc.BadgeCount,0) AS BadgeCount,
    COALESCE(bc.BadgeHolders,0) AS BadgeHolders
  FROM TagQuestionStats ts
  LEFT JOIN TagAnswerStats ta ON ta.Tag = ts.Tag
  LEFT JOIN TagCommentStats tc ON tc.Tag = ts.Tag
  LEFT JOIN TagVoteStats tv ON tv.Tag = ts.Tag
  LEFT JOIN BadgeCounts bc ON bc.Tag = ts.Tag
),
-- identify rising tags: high recent question rate vs historical average and high engagement
RisingTags AS (
  SELECT
    tr.*,
    CASE WHEN tr.QuestionCount > 0 THEN (tr.QuestionsLast30d::double precision / (tr.QuestionCount::double precision/ (date_part('year', now()) - date_part('year', min_q.CreationYear) + 1))) ELSE 0 END AS RecentRateNormalized
  FROM (
    SELECT Tag, QuestionCount, AvgScore, AvgViews, MaxScoreLast30d, QuestionsLast30d,
           AnswerCount, AvgAnswerScore, AnswersLast30d, DistinctAnswerers,
           CommentCount, DistinctCommenters, CommentsLast7d,
           UpVotes, DownVotes, Favorites, TotalVotes, VotesLast30d,
           BadgeCount, BadgeHolders
    FROM TagRollup
  ) tr
  JOIN (
    SELECT qt.Tag, min(date_part('year', qt.CreationDate)) AS CreationYear
    FROM QuestionTags qt
    GROUP BY qt.Tag
  ) min_q ON min_q.Tag = tr.Tag
),
-- final selection: compute composite score and return rich detail, include expensive windowing and subqueries for benchmarking
FinalRanking AS (
  SELECT
    rt.Tag,
    rt.QuestionCount,
    rt.QuestionsLast30d,
    rt.AnswerCount,
    rt.AnswersLast30d,
    rt.CommentCount,
    rt.CommentsLast7d,
    rt.UpVotes,
    rt.VotesLast30d,
    rt.BadgeCount,
    rt.BadgeHolders,
    rt.AvgViews,
    rt.AvgScore,
    rt.AvgAnswerScore,
    rt.DistinctAnswerers,
    rt.DistinctCommenters,
    rt.RecentRateNormalized,
    -- composite score: weighted and non-linear to create varied CPU work
    (ln(1 + coalesce(rt.QuestionsLast30d,0)) * 3.0
     + sqrt(1 + coalesce(rt.AnswersLast30d,0)) * 2.5
     + (coalesce(rt.VotesLast30d,0) * 0.8)
     + (coalesce(rt.CommentsLast7d,0) * 0.6)
     + (coalesce(rt.BadgeHolders,0) * 1.2)
     + (coalesce(rt.AvgViews,0)/greatest(1, coalesce(rt.QuestionCount,1)) * 0.01)
    ) * greatest(1, rt.RecentRateNormalized) AS CompositeScore,
    -- heavy window functions: rank by multiple criteria, moving averages
    rank() OVER (ORDER BY (ln(1 + coalesce(rt.QuestionsLast30d,0)) * 3.0 + sqrt(1 + coalesce(rt.AnswersLast30d,0)) * 2.5 + coalesce(rt.VotesLast30d,0)) DESC) AS SimpleRank,
    dense_rank() OVER (ORDER BY (rt.RecentRateNormalized DESC, rt.VotesLast30d DESC, rt.AvgViews DESC)) AS DensityRank,
    avg(rt.QuestionsLast30d) OVER () AS GlobalAvgQuestionsLast30d,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY rt.CompositeScore) OVER () AS MedianComposite
  FROM RisingTags rt
)
SELECT
  f.Tag,
  f.QuestionCount,
  f.QuestionsLast30d,
  f.AnswerCount,
  f.AnswersLast30d,
  f.CommentCount,
  f.CommentsLast7d,
  f.UpVotes,
  f.VotesLast30d,
  f.BadgeCount,
  f.BadgeHolders,
  round(f.CompositeScore::numeric,4) AS CompositeScore,
  f.SimpleRank,
  f.DensityRank,
  round(f.GlobalAvgQuestionsLast30d::numeric,4) AS GlobalAvgQuestionsLast30d,
  round(f.MedianComposite::numeric,4) AS MedianComposite,
  -- include heavy correlated subquery: sample top question title per tag by score and most recent activity
  (SELECT p.Title FROM Posts p
   JOIN QuestionTags qt ON qt.QuestionId = p.Id
   WHERE qt.Tag = f.Tag
   ORDER BY (p.Score * 2 + COALESCE(p.ViewCount,0)::double precision/1000.0 + EXTRACT(EPOCH FROM (now() - p.LastActivityDate))/86400.0 * -1) DESC
   LIMIT 1) AS TopQuestionTitle,
  (SELECT json_agg(row_to_json(x)) FROM (
     SELECT u.Id AS UserId, u.DisplayName, u.Reputation, count(p.Id) AS QuestionsAsked
     FROM Users u
     JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
     JOIN QuestionTags qt2 ON qt2.QuestionId = p.Id
     WHERE qt2.Tag = f.Tag
     GROUP BY u.Id,u.DisplayName,u.Reputation
     ORDER BY QuestionsAsked DESC, u.Reputation DESC
     LIMIT 5
  ) x) AS TopAskersSample
FROM FinalRanking f
ORDER BY f.CompositeScore DESC
LIMIT 50;