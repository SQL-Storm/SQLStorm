-- {"query": "37064.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2239} 
WITH
-- active questions in last year with tag array
QuestionBase AS (
  SELECT p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount,
         p.OwnerUserId, p.AnswerCount, p.CommentCount,
         COALESCE(
           NULLIF(trim(both ' ' FROM regexp_replace(substr(p.Tags,2,length(p.Tags)-2), '><', ' ' , 'g')), ''),
           ''
         ) AS TagString,
         regexp_split_to_array(substr(coalesce(p.Tags,''),2, greatesT(length(coalesce(p.Tags,''))-2,0)), '><')::text[] AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '1 year'
),
-- top answerers for those questions (by score and accepted)
AnswerAgg AS (
  SELECT q.Id AS QuestionId,
         count(a.Id) FILTER (WHERE a.ParentId = q.Id) AS TotalAnswers,
         max(a.Score) FILTER (WHERE a.ParentId = q.Id) AS MaxAnswerScore,
         sum(a.Score) FILTER (WHERE a.ParentId = q.Id) AS SumAnswerScore,
         count(a.Id) FILTER (WHERE a.ParentId = q.Id AND a.Id = q.AcceptedAnswerId) AS HasAccepted,
         jsonb_agg(jsonb_build_object('AnswerId', a.Id, 'OwnerUserId', a.OwnerUserId, 'Score', a.Score, 'CreationDate', a.CreationDate) ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) FILTER (WHERE a.ParentId = q.Id) AS Answers
  FROM QuestionBase q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  GROUP BY q.Id
),
-- recent activity counts from comments and edits
ActivityAgg AS (
  SELECT qb.Id AS QuestionId,
         count(c.Id) FILTER (WHERE c.CreationDate >= now() - interval '90 days') AS RecentComments,
         count(ph.Id) FILTER (WHERE ph.CreationDate >= now() - interval '90 days') AS RecentEdits,
         max(ph.CreationDate) AS LastEditDate,
         max(c.CreationDate) AS LastCommentDate
  FROM QuestionBase qb
  LEFT JOIN Comments c ON c.PostId = qb.Id
  LEFT JOIN PostHistory ph ON ph.PostId = qb.Id
  GROUP BY qb.Id
),
-- tag popularity snapshot
TagStats AS (
  SELECT t.TagName,
         t.Id AS TagId,
         t.Count AS GlobalCount,
         coalesce(sum(p.ViewCount) FILTER (WHERE p.PostTypeId = 1),0) AS ViewsOnTaggedQuestions,
         coalesce(count(p.Id) FILTER (WHERE p.PostTypeId = 1),0) AS QuestionCount
  FROM Tags t
  LEFT JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE ('%<' || t.TagName || '>%')
  GROUP BY t.TagName, t.Id, t.Count
),
-- per-question tag expansion and enrichment
QuestionTags AS (
  SELECT qb.*, ua.TotalAnswers, ua.MaxAnswerScore, ua.SumAnswerScore, ua.HasAccepted, ua.Answers,
         aa.RecentComments, aa.RecentEdits, aa.LastEditDate, aa.LastCommentDate,
         unnest(qb.TagArray) AS TagName
  FROM QuestionBase qb
  LEFT JOIN AnswerAgg ua ON ua.QuestionId = qb.Id
  LEFT JOIN ActivityAgg aa ON aa.QuestionId = qb.Id
),
-- combine with tag stats and compute weighted metrics
QuestionEnriched AS (
  SELECT qt.*,
         ts.GlobalCount,
         ts.ViewsOnTaggedQuestions,
         ts.QuestionCount,
         -- a composite hotness score that mixes views, score, recent activity, answer stats and tag popularity
         (
           -- normalized view component
           LEAST(1.0, COALESCE(qt.ViewCount::double precision,0) / NULLIF(10000.0,0)) * 0.30
           +
           -- score and answers
           (LEAST(1.0, COALESCE(qt.Score::double precision,0) / NULLIF(50.0,0)) * 0.20)
           +
           (LEAST(1.0, COALESCE(qt.SumAnswerScore::double precision,0) / NULLIF(GREATEST(qt.TotalAnswers,1)*20.0,0)) * 0.10)
           +
           -- recent activity boost
           (LEAST(1.0, COALESCE(qt.RecentComments::double precision,0) / 10.0) * 0.10)
           +
           (LEAST(1.0, COALESCE(qt.RecentEdits::double precision,0) / 5.0) * 0.05)
           +
           -- popularity of tag
           (LEAST(1.0, COALESCE(ts.GlobalCount::double precision,0) / NULLIF(100000.0,0)) * 0.15)
           +
           -- accepted answer boost
           (CASE WHEN qt.HasAccepted > 0 THEN 0.10 ELSE 0 END)
         ) AS HotnessScore
  FROM QuestionTags qt
  LEFT JOIN TagStats ts ON ts.TagName = qt.TagName
),
-- rank tags per question and compute diversity
QuestionTagRank AS (
  SELECT qe.*,
         rank() OVER (PARTITION BY qe.Id ORDER BY qe.GlobalCount DESC NULLS LAST) AS TagRankByPopularity,
         count(*) OVER (PARTITION BY qe.Id) AS TagCountPerQuestion
  FROM QuestionEnriched qe
),
-- aggregate back to questions producing multi-tag summaries and top tags
QuestionFinal AS (
  SELECT q.Id,
         q.Title,
         q.CreationDate,
         q.Score,
         q.ViewCount,
         q.OwnerUserId,
         q.AnswerCount,
         q.CommentCount,
         q.TotalAnswers,
         q.MaxAnswerScore,
         q.SumAnswerScore,
         q.HasAccepted,
         q.RecentComments,
         q.RecentEdits,
         q.LastEditDate,
         q.LastCommentDate,
         q.HotnessScore,
         q.TagCountPerQuestion,
         -- top 3 tags for the question by global popularity
         array_agg(q.TagName ORDER BY q.TagRankByPopularity, q.TagName) FILTER (WHERE q.TagRankByPopularity IS NOT NULL) [1:3] AS TopTags,
         -- least popular tag among its tags (to estimate niche)
         min(q.GlobalCount) AS LeastPopularTagCount,
         -- median popularity of tags (approx using percentile_disc)
         (percentile_disc(0.5) WITHIN GROUP (ORDER BY q.GlobalCount) OVER (PARTITION BY q.Id)) AS MedianTagPopularity,
         -- pick best answer candidate (highest score)
         (CASE WHEN q.Answers IS NOT NULL THEN (q.Answers->0->>'AnswerId')::int ELSE NULL END) AS TopAnswerId
  FROM QuestionTagRank q
  GROUP BY q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId, q.AnswerCount, q.CommentCount,
           q.TotalAnswers, q.MaxAnswerScore, q.SumAnswerScore, q.HasAccepted,
           q.RecentComments, q.RecentEdits, q.LastEditDate, q.LastCommentDate, q.HotnessScore, q.TagCountPerQuestion, q.Answers
),
-- user reputation and recent contributions for owners
OwnerStats AS (
  SELECT u.Id AS UserId, u.DisplayName, u.Reputation,
         count(p.Id) FILTER (WHERE p.PostTypeId = 1 AND p.CreationDate >= now() - interval '1 year') AS QuestionsLastYear,
         count(p.Id) FILTER (WHERE p.PostTypeId = 2 AND p.CreationDate >= now() - interval '1 year') AS AnswersLastYear,
         coalesce(sum(v.VoteTypeId = 2)::int,0) AS UpVotesGiven -- cheap proxy aggregated; may be zero if no join keys
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v ON v.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
  qf.Id AS QuestionId,
  qf.Title,
  qf.CreationDate,
  qf.Score,
  qf.ViewCount,
  qf.AnswerCount,
  qf.CommentCount,
  qf.TotalAnswers,
  qf.HasAccepted,
  qf.HotnessScore,
  qf.TagCountPerQuestion,
  qf.TopTags,
  qf.LeastPopularTagCount,
  qf.MedianTagPopularity,
  os.UserId AS OwnerUserId,
  os.DisplayName AS OwnerName,
  os.Reputation AS OwnerReputation,
  os.QuestionsLastYear,
  os.AnswersLastYear,
  -- correlated info about the top answer (score and owner)
  ta.Score AS TopAnswerScore,
  ta.OwnerUserId AS TopAnswerOwnerId,
  ta.CreationDate AS TopAnswerDate,
  -- related duplicates/links count
  (SELECT count(*) FROM PostLinks pl WHERE pl.PostId = qf.Id AND pl.LinkTypeId = 3) AS DuplicateCount,
  -- tag co-occurrence: number of distinct other tags appearing with the most popular tag
  (SELECT count(DISTINCT other_tag)
   FROM (
     SELECT unnest(regexp_split_to_array(substr(p.Tags,2,length(p.Tags)-2),'><')) AS other_tag
     FROM Posts p
     WHERE p.PostTypeId = 1
       AND p.Tags LIKE ('%<' || (qf.TopTags[1]) || '>%')
       AND p.Id <> qf.Id
   ) t
  ) AS CooccurrenceWithTopTag,
  -- windowed rank by hotness within same tag count bucket
  rank() OVER (PARTITION BY qf.TagCountPerQuestion ORDER BY qf.HotnessScore DESC) AS RankWithinTagCount,
  dense_rank() OVER (ORDER BY qf.HotnessScore DESC) AS GlobalHotRank
FROM QuestionFinal qf
LEFT JOIN OwnerStats os ON os.UserId = qf.OwnerUserId
LEFT JOIN Posts ta ON ta.Id = qf.TopAnswerId
ORDER BY qf.HotnessScore DESC NULLS LAST
LIMIT 200;