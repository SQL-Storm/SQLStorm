-- {"query": "260.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 4168} 
WITH
-- Base sets
questions AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 1
),
answers AS (
  SELECT *
  FROM Posts
  WHERE PostTypeId = 2
),
-- Expand tags into one row per (question, tag)
tag_expanded AS (
  SELECT
    q.Id AS QuestionId,
    trim(t.tag) AS Tag
  FROM questions q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags, 2, length(q.Tags) - 2),'><')) AS tag
  ) t
  WHERE q.Tags IS NOT NULL AND length(q.Tags) > 2
),
-- Basic aggregated info per question from answers and comments and votes
answer_aggregates AS (
  SELECT
    q.Id AS QuestionId,
    COUNT(a.Id) AS AnswerCountAll,
    COUNT(DISTINCT a.OwnerUserId) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS DistinctAnswerers,
    MIN(a.CreationDate) AS FirstAnswerDate,
    AVG(a.Score)::numeric(10,3) AS AvgAnswerScore,
    COALESCE(STDDEV_POP(a.Score),0)::numeric(10,3) AS StdDevAnswerScore,
    MAX(a.Score) AS MaxAnswerScore,
    SUM(CASE WHEN a.Score < 0 THEN 1 ELSE 0 END) AS NegativeScoreAnswers
  FROM questions q
  LEFT JOIN answers a ON a.ParentId = q.Id
  GROUP BY q.Id
),
-- Votes summary per post (questions and answers)
votes_summary AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) AS AcceptedByOriginator,
    COUNT(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- Links summary (duplicates/linked)
link_summary AS (
  SELECT
    pl.PostId,
    SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksTo,
    SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedPosts
  FROM PostLinks pl
  GROUP BY pl.PostId
),
-- Comments count per post
comments_summary AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
-- User badge weighting and recency
user_badge_score AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    COALESCE(SUM(
      CASE
        WHEN b.Class = 1 THEN 5
        WHEN b.Class = 2 THEN 3
        WHEN b.Class = 3 THEN 1
        ELSE 0
      END
    ),0) AS BadgeWeight,
    MAX(b.Date) AS LastBadgeDate,
    EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - MAX(u.LastAccessDate))) / 86400.0 AS DaysSinceLastAccess
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.Reputation
),
-- Candidate question set for benchmarking: mix of high-score and moderate-score questions
candidate_questions AS (
  (SELECT Id FROM questions WHERE Score >= 15 ORDER BY random() LIMIT 200)
  UNION ALL
  (SELECT Id FROM questions WHERE Score BETWEEN 5 AND 14 ORDER BY random() LIMIT 200)
),
-- For each question compute the top answer, accepted answer, and performance metrics using lateral/correlated subqueries
per_question AS (
  SELECT
    q.Id AS QuestionId,
    q.Title,
    LEFT(coalesce(q.Body, ''), 400) AS Snippet,
    q.CreationDate AS QuestionCreated,
    q.Score AS QuestionScore,
    q.ViewCount,
    COALESCE(vs.UpVotes,0) AS QuestionUpVotes,
    COALESCE(vs.DownVotes,0) AS QuestionDownVotes,
    COALESCE(ls.DuplicateLinksTo,0) AS DuplicateLinksTo,
    COALESCE(cs.CommentCount,0) AS QuestionCommentCount,
    fa.FirstAnswerDate,
    fa.AnswerCountAll,
    fa.AvgAnswerScore,
    fa.StdDevAnswerScore,
    fa.MaxAnswerScore,
    fa.NegativeScoreAnswers,
    -- time to first answer in seconds
    CASE WHEN fa.FirstAnswerDate IS NOT NULL THEN EXTRACT(EPOCH FROM (fa.FirstAnswerDate - q.CreationDate)) ELSE NULL END AS SecondsToFirstAnswer,
    -- correlated: number of upvotes in 30 days after question creation
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2 AND v.CreationDate BETWEEN q.CreationDate AND q.CreationDate + INTERVAL '30 days') AS UpVotesFirst30Days,
    -- top answer by score (ties broken by earlier creation)
    top_ans.TopAnswerId,
    top_ans.TopAnswerScore,
    top_ans.TopAnswerOwner,
    -- accepted answer info
    acc.Id AS AcceptedAnswerId,
    acc.Score AS AcceptedAnswerScore,
    acc.OwnerUserId AS AcceptedAnswerOwner,
    -- flagged duplicate by posthistory or links
    CASE
      WHEN EXISTS (SELECT 1 FROM PostHistory ph WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId IN (10,35) LIMIT 1) THEN true
      WHEN COALESCE(ls.DuplicateLinksTo,0) > 0 THEN true
      ELSE false
    END AS IsClosedOrDuplicate,
    -- some textual complexity: longest word in title (simple)
    (SELECT substring(unnest(regexp_split_to_array(coalesce(q.Title,''),'[^A-Za-z0-9]+')) FROM 1 FOR 100) ORDER BY char_length(unnest) DESC LIMIT 1) AS LongestTitleToken
  FROM questions q
  LEFT JOIN votes_summary vs ON vs.PostId = q.Id
  LEFT JOIN link_summary ls ON ls.PostId = q.Id
  LEFT JOIN comments_summary cs ON cs.PostId = q.Id
  LEFT JOIN answer_aggregates fa ON fa.QuestionId = q.Id
  LEFT JOIN LATERAL (
    SELECT a.Id AS TopAnswerId, a.Score AS TopAnswerScore, a.OwnerUserId AS TopAnswerOwner
    FROM answers a
    WHERE a.ParentId = q.Id
    ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC NULLS LAST
    LIMIT 1
  ) top_ans ON true
  LEFT JOIN Posts acc ON acc.Id = q.AcceptedAnswerId
  WHERE q.Id IN (SELECT Id FROM candidate_questions)
),
-- tag-level ranking for question within each tag
tagged_ranked AS (
  SELECT
    tq.QuestionId,
    te.Tag,
    pq.Title,
    pq.QuestionScore,
    pq.ViewCount,
    pq.AnswerCountAll,
    pq.SecondsToFirstAnswer,
    ROW_NUMBER() OVER (PARTITION BY te.Tag ORDER BY pq.ViewCount DESC NULLS LAST, pq.QuestionScore DESC NULLS LAST) AS TagViewRank,
    DENSE_RANK() OVER (PARTITION BY te.Tag ORDER BY pq.QuestionScore DESC NULLS LAST) AS TagScoreDenseRank
  FROM per_question pq
  JOIN tag_expanded te ON te.QuestionId = pq.QuestionId
  JOIN per_question tq ON tq.QuestionId = pq.QuestionId -- self-join to demonstrate extra plan complexity
),
-- compute per-user expertise: answers provided to candidate questions and average score
user_expertise AS (
  SELECT
    COALESCE(a.OwnerUserId, -1) AS UserId,
    COUNT(a.Id) FILTER (WHERE a.ParentId IN (SELECT QuestionId FROM per_question)) AS CandidateAnswerCount,
    AVG(a.Score) FILTER (WHERE a.ParentId IN (SELECT QuestionId FROM per_question))::numeric(10,3) AS AvgScoreOnCandidateQuestions,
    COUNT(DISTINCT a.ParentId) FILTER (WHERE a.ParentId IN (SELECT QuestionId FROM per_question)) AS QuestionsAnsweredCount
  FROM answers a
  GROUP BY COALESCE(a.OwnerUserId, -1)
),
-- final join: combine question, tag, and user-level metrics with windowed aggregates and some expressions
final_prep AS (
  SELECT
    tr.*,
    pq.Snippet,
    pq.QuestionCreated,
    pq.QuestionUpVotes,
    pq.QuestionDownVotes,
    pq.UpVotesFirst30Days,
    pq.TopAnswerId,
    pq.TopAnswerScore,
    pq.TopAnswerOwner,
    pq.AcceptedAnswerId,
    pq.AcceptedAnswerScore,
    pq.IsClosedOrDuplicate,
    ub.BadgeWeight AS OwnerBadgeWeight,
    ue.CandidateAnswerCount AS OwnerCandidateAnswers,
    ue.AvgScoreOnCandidateQuestions,
    -- window: percent rank of question score among candidate set
    PERCENT_RANK() OVER (ORDER BY pq.QuestionScore) AS PercentRankOverall,
    NTILE(10) OVER (ORDER BY pq.ViewCount DESC NULLS LAST) AS ViewDecile,
    -- composite complexity score for benchmarking (arbitrary formula)
    (COALESCE(pq.QuestionScore,0) * 2.3
     + COALESCE(pq.ViewCount,0) / NULLIF(GREATEST(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pq.QuestionCreated))/86400.0,1),0)
     + COALESCE(pq.AnswerCountAll,0) * 4
     + COALESCE(ub.BadgeWeight,0) * 1.5
     - COALESCE(pq.IsClosedOrDuplicate::int,0) * 50
     + COALESCE(pq.UpVotesFirst30Days,0) * 0.5
    )::numeric(12,3) AS ComplexityScore
  FROM tagged_ranked tr
  JOIN per_question pq ON pq.QuestionId = tr.QuestionId
  LEFT JOIN Users u ON u.Id = pq.TopAnswerOwner
  LEFT JOIN user_badge_score ub ON ub.UserId = COALESCE(pq.TopAnswerOwner, pq.AcceptedAnswerOwner, -1)
  LEFT JOIN user_expertise ue ON ue.UserId = COALESCE(pq.TopAnswerOwner, -1)
)
SELECT
  fp.Tag,
  fp.QuestionId,
  LEFT(fp.Title,200) AS Title,
  fp.Snippet,
  fp.QuestionCreated,
  fp.QuestionScore,
  fp.ViewCount,
  fp.AnswerCountAll,
  fp.SecondsToFirstAnswer,
  fp.FirstAnswerDate,
  fp.TopAnswerId,
  fp.TopAnswerScore,
  fp.AcceptedAnswerId,
  fp.AcceptedAnswerScore,
  fp.IsClosedOrDuplicate,
  fp.OwnerBadgeWeight,
  fp.OwnerCandidateAnswers,
  fp.AvgScoreOnCandidateQuestions,
  fp.TagViewRank,
  fp.TagScoreDenseRank,
  fp.PercentRankOverall,
  fp.ViewDecile,
  fp.ComplexityScore,
  -- string expression example: synthetic tag_summary combining tag and top tokens
  concat(fp.Tag, '::', coalesce(fp.LongestTitleToken,'-'), '::S', fp.ViewDecile::text) AS TagSummary,
  -- NULL logic example: favorite indicator when high score and many views but no accepted answer
  CASE
    WHEN fp.AcceptedAnswerId IS NULL AND fp.QuestionScore > 20 AND fp.ViewCount > 10000 THEN 'HighAttentionNoAccepted'
    WHEN fp.AcceptedAnswerId IS NULL AND fp.QuestionScore > 5 THEN 'NeedsAcceptance'
    ELSE NULL
  END AS AttentionFlag,
  -- correlation: does top answer owner have high badge weight?
  CASE WHEN fp.OwnerBadgeWeight > 10 THEN true ELSE false END AS TopOwnerIsWellBadged
FROM final_prep fp
ORDER BY fp.ComplexityScore DESC NULLS LAST, fp.TagScoreDenseRank ASC
LIMIT 100;