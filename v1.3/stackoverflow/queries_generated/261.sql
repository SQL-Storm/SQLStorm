-- {"query": "261.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 6279} 
WITH recent_questions AS (
  SELECT p.*
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= current_timestamp - INTERVAL '730 days'
),
tag_expanded AS (
  SELECT q.Id AS QuestionId,
         trim(tag) AS Tag
  FROM recent_questions q
  CROSS JOIN LATERAL (
    SELECT unnest(
      string_to_array(
        substring(coalesce(q.Tags, '') from 2 for GREATEST(length(coalesce(q.Tags, '')) - 2,0)
        ), '><'
      )
    ) AS tag
  ) s
),
answers AS (
  SELECT a.*
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.ParentId IN (SELECT Id FROM recent_questions)
),
answer_stats AS (
  SELECT a.ParentId AS QuestionId,
         count(*) FILTER (WHERE a.Score >= 0) AS AnswerCount_Pos,
         count(*) AS AnswerCount_Total,
         avg(a.Score) AS AvgAnswerScore,
         max(a.Score) FILTER (WHERE a.OwnerUserId IS NOT NULL) AS MaxAnswerScore,
         sum(CASE WHEN a.OwnerUserId IS NULL THEN 0 ELSE 1 END) AS AnswerOwnerCount
  FROM answers a
  GROUP BY a.ParentId
),
vote_agg AS (
  SELECT v.PostId,
         sum(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS VoteScore,
         count(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
         count(*) AS VoteCount
  FROM Votes v
  GROUP BY v.PostId
),
comment_agg AS (
  SELECT c.PostId,
         count(*) AS CommentCount,
         max(c.CreationDate) AS LastCommentDate,
         count(distinct c.UserId) AS Commenters
  FROM Comments c
  GROUP BY c.PostId
),
history_last_edit AS (
  SELECT ph.PostId,
         ph.CreationDate AS EditDate,
         ph.UserId AS EditorId,
         ph.Text,
         row_number() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (4,5,6)
),
last_edits AS (
  SELECT h.PostId, h.EditDate, h.EditorId, h.Text
  FROM history_last_edit h
  WHERE h.rn = 1
),
user_scores AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         u.Reputation,
         u.CreationDate,
         u.Views,
         u.UpVotes,
         u.DownVotes,
         ntile(10) OVER (ORDER BY u.Reputation DESC NULLS LAST) AS RepDecile,
         rank() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS RepRank,
         dense_rank() OVER (PARTITION BY date_trunc('year', u.CreationDate) ORDER BY u.Reputation DESC NULLS LAST) AS YearlyRank
  FROM Users u
),
tag_user_agg AS (
  SELECT t.Tag, a.OwnerUserId AS UserId, count(*) AS AnswersForTag, sum(a.Score) AS AnswerScoreSum
  FROM tag_expanded t
  LEFT JOIN Posts a ON a.ParentId = t.QuestionId AND a.PostTypeId = 2
  WHERE a.OwnerUserId IS NOT NULL
  GROUP BY t.Tag, a.OwnerUserId
),
tag_top_users AS (
  SELECT Tag, UserId, AnswersForTag, AnswerScoreSum,
         rank() OVER (PARTITION BY Tag ORDER BY AnswerScoreSum DESC NULLS LAST) AS TagRank
  FROM tag_user_agg
),
engagement AS (
  SELECT p.Id AS PostId,
         COALESCE(v.VoteScore,0) * 1.5
           + COALESCE(c.CommentCount,0) * 0.8
           + (COALESCE(p.ViewCount,0)::numeric / NULLIF(GREATEST(1,p.ViewCount + 100),0)) * 0.2
           + COALESCE(ph.EditCount,0) * 1.2 AS EngagementScore,
         COALESCE(v.VoteScore,0) AS VoteScore,
         COALESCE(c.CommentCount,0) AS CommentCount,
         COALESCE(p.ViewCount,0) AS Views,
         COALESCE(ph.EditCount,0) AS EditCount
  FROM Posts p
  LEFT JOIN vote_agg v ON v.PostId = p.Id
  LEFT JOIN comment_agg c ON c.PostId = p.Id
  LEFT JOIN (
    SELECT PostId, count(*) AS EditCount FROM PostHistory WHERE PostHistoryTypeId IN (4,5,6) GROUP BY PostId
  ) ph ON ph.PostId = p.Id
),
duplicates AS (
  SELECT pl.PostId, pl.RelatedPostId, pl.LinkTypeId,
         row_number() OVER (PARTITION BY pl.PostId ORDER BY pl.CreationDate DESC) AS rn
  FROM PostLinks pl
  WHERE pl.LinkTypeId = 3
),
hot_candidates AS (
  SELECT p.Id, p.Title, p.CreationDate, e.EngagementScore, e.Views, v.VoteScore
  FROM Posts p
  LEFT JOIN engagement e ON e.PostId = p.Id
  LEFT JOIN vote_agg v ON v.PostId = p.Id
  WHERE p.PostTypeId = 1
    AND (COALESCE(e.EngagementScore,0) > 10 OR COALESCE(v.VoteScore,0) > 5)
),
hot_posts AS (
  SELECT * FROM hot_candidates
  UNION
  SELECT p.Id, p.Title, p.CreationDate, e.EngagementScore, e.Views, v.VoteScore
  FROM Posts p
  JOIN Posts q ON q.AcceptedAnswerId = p.Id
  LEFT JOIN engagement e ON e.PostId = p.Id
  LEFT JOIN vote_agg v ON v.PostId = p.Id
  WHERE p.PostTypeId = 2
)
SELECT
  q.Id AS QuestionId,
  CASE WHEN length(coalesce(q.Title,'')) > 200 THEN substring(q.Title from 1 for 197) || '...' ELSE q.Title END AS ShortTitle,
  q.Title AS FullTitle,
  q.CreationDate,
  q.OwnerUserId,
  u.DisplayName,
  COALESCE(u.Reputation,0) AS OwnerReputation,
  COALESCE(ts.AnswerCount_Total,0) AS AnswerCount_Total,
  COALESCE(ts.AvgAnswerScore,0) AS AvgAnswerScore_FromAnswers,
  COALESCE(v.VoteScore,0) AS QuestionVoteScore,
  COALESCE(c.CommentCount,0) AS QuestionComments,
  COALESCE(e.EngagementScore,0) AS Engagement,
  string_agg(DISTINCT te.Tag, ', ') FILTER (WHERE te.Tag IS NOT NULL) AS Tags,
  COALESCE(ts.MaxAnswerScore,0) AS MaxAnswerScoreAmongAnswers,
  le.EditDate AS LastEditDate,
  CASE
    WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN q.AcceptedAnswerId IS NOT NULL THEN 'AnsweredAccepted'
    WHEN COALESCE(q.AnswerCount,0) > 0 THEN 'Answered'
    ELSE 'Unanswered'
  END AS Status,
  dup.RelatedPostId AS LatestDuplicateOf,
  (SELECT count(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
  (SELECT avg(a.Score) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) AS AvgAnswerScore_Correlated,
  (SELECT sum(CASE WHEN v2.VoteTypeId=2 THEN 1 WHEN v2.VoteTypeId=3 THEN -1 ELSE 0 END) FROM Votes v2 WHERE v2.PostId = q.Id) AS LiveVoteScore,
  COALESCE(us.RepDecile,11) AS OwnerRepDecile,
  (CASE WHEN u.DisplayName IS NULL THEN '(' || coalesce(u.EmailHash, 'no-hash') || ')' ELSE u.DisplayName END) AS OwnerLabel,
  rank() OVER (ORDER BY COALESCE(e.EngagementScore,0) DESC) AS EngagementRank,
  CASE WHEN q.Tags IS NULL OR q.Tags = '' THEN 1 ELSE 0 END AS HasNoTags,
  (SELECT string_agg(bx.Name || '::' || to_char(bx.Date,'YYYY-MM-DD'), ' | ')
     FROM (SELECT b.Name, b.Date FROM Badges b WHERE b.UserId = u.Id ORDER BY b.Date DESC LIMIT 5) bx
  ) AS RecentBadges,
  (SELECT au.UserId
     FROM tag_top_users au
     JOIN tag_expanded te2 ON te2.Tag = au.Tag AND te2.QuestionId = q.Id
     ORDER BY au.AnswerScoreSum DESC NULLS LAST
     LIMIT 1
  ) AS TopTagUserId,
  CASE WHEN EXISTS (SELECT 1 FROM Posts p2 WHERE p2.ParentId = q.Id AND p2.Score > q.Score) THEN true ELSE false END AS HasHigherScoringAnswer
FROM recent_questions q
LEFT JOIN tag_expanded te ON te.QuestionId = q.Id
LEFT JOIN answer_stats ts ON ts.QuestionId = q.Id
LEFT JOIN vote_agg v ON v.PostId = q.Id
LEFT JOIN comment_agg c ON c.PostId = q.Id
LEFT JOIN engagement e ON e.PostId = q.Id
LEFT JOIN last_edits le ON le.PostId = q.Id
LEFT JOIN duplicates dup ON dup.PostId = q.Id AND dup.rn = 1
LEFT JOIN Users u ON u.Id = q.OwnerUserId
LEFT JOIN user_scores us ON us.UserId = u.Id
GROUP BY
  q.Id, q.Title, q.CreationDate, q.OwnerUserId, u.DisplayName, u.Reputation,
  ts.AnswerCount_Total, ts.AvgAnswerScore, v.VoteScore, c.CommentCount,
  e.EngagementScore, le.EditDate, ts.MaxAnswerScore, q.ClosedDate, q.AcceptedAnswerId,
  q.AnswerCount, dup.RelatedPostId, us.RepDecile, u.EmailHash, q.Tags
ORDER BY COALESCE(e.EngagementScore,0) DESC NULLS LAST, q.CreationDate DESC
LIMIT 250;