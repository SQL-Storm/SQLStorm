-- {"query": "220.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3607} 
WITH
-- explode tags from question posts
tag_expansion AS (
  SELECT
    q.Id AS QuestionId,
    TRIM(tag) AS TagName
  FROM Posts q
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(q.Tags FROM 2 FOR char_length(q.Tags)-2), '><')) AS tag
  ) AS t
  WHERE q.PostTypeId = 1 AND q.Tags IS NOT NULL
),
-- per-tag aggregates
tag_stats AS (
  SELECT
    te.TagName,
    COUNT(*) AS QuestionsWithTag,
    AVG(q.ViewCount) AS AvgViewsPerQuestion,
    SUM(CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAccepted,
    MAX(q.CreationDate) FILTER (WHERE q.CreationDate IS NOT NULL) AS MostRecentQuestion
  FROM tag_expansion te
  JOIN Posts q ON q.Id = te.QuestionId
  GROUP BY te.TagName
),
-- user badge summary
user_badges AS (
  SELECT
    b.UserId,
    COUNT(*) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS Gold,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS Silver,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS Bronze,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
-- post-level edit/comment/vote aggregates
post_edits AS (
  SELECT
    ph.PostId,
    COUNT(*) AS EditCount,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS ContentEdits,
    MAX(ph.CreationDate) AS LastEditDate,
    MIN(ph.CreationDate) AS FirstEditDate
  FROM PostHistory ph
  GROUP BY ph.PostId
),
comment_stats AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount,
    MAX(c.CreationDate) AS LastCommentDate,
    -- latest comment text per post via DISTINCT ON style using window
    (ARRAY_AGG(c.Text ORDER BY c.CreationDate DESC NULLS LAST))[1] AS LastCommentText
  FROM Comments c
  GROUP BY c.PostId
),
vote_stats AS (
  SELECT
    v.PostId,
    COUNT(*) AS VoteCount,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS BountyStartedTotal,
    SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS BountyClosedTotal,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),
link_graph AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS OutboundLinks,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS OutboundDuplicates,
    COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM PostLinks pl2 WHERE pl2.RelatedPostId = pl.PostId AND pl2.LinkTypeId = 1)) AS InboundLinksHeuristic
  FROM PostLinks pl
  GROUP BY pl.PostId
),
-- answers aggregated per question (correlated subquery style inside CTE for time-to-first-answer)
answer_agg AS (
  SELECT
    q.Id AS QuestionId,
    COUNT(a.Id) AS AnswerCount,
    AVG(a.Score) AS AvgAnswerScore,
    SUM(CASE WHEN a.OwnerUserId IS NOT NULL THEN 1 ELSE 0 END) AS AnswerersKnown,
    MIN(a.CreationDate) AS FirstAnswerDate,
    MAX(a.Score) FILTER (WHERE a.CreationDate IS NOT NULL) AS MaxAnswerScore,
    (SELECT COUNT(DISTINCT a2.OwnerUserId) FROM Posts a2 WHERE a2.ParentId = q.Id AND a2.OwnerUserId IS NOT NULL) AS DistinctAnswerers
  FROM Posts q
  LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
  WHERE q.PostTypeId = 1
  GROUP BY q.Id
),
-- recent activity ranking window functions across posts
recent_activity AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0) AS NetVotes,
    COALESCE(ps.CommentCount,0) AS CommentCount,
    COALESCE(pe.EditCount,0) AS EditCount,
    COALESCE(la.InboundLinksHeuristic,0) AS InboundLinks,
    ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.LastActivityDate DESC NULLS LAST) AS RecentRankByType,
    RANK() OVER (ORDER BY COALESCE(p.Score,0) DESC, COALESCE(p.ViewCount,0) DESC) AS ScoreRankOverall,
    -- recency score: exponential decay weight on last activity (days)
    EXP(-(EXTRACT(EPOCH FROM (NOW() - COALESCE(p.LastActivityDate,p.CreationDate)))/86400.0)/30.0) AS RecencyDecay
  FROM Posts p
  LEFT JOIN vote_stats vs ON vs.PostId = p.Id
  LEFT JOIN comment_stats ps ON ps.PostId = p.Id
  LEFT JOIN post_edits pe ON pe.PostId = p.Id
  LEFT JOIN link_graph la ON la.PostId = p.Id
),
-- candidates: union of top questions by score and top by recency/activity to create a diverse set (set operators)
top_by_score AS (
  SELECT q.Id AS PostId FROM Posts q WHERE q.PostTypeId = 1 ORDER BY q.Score DESC NULLS LAST LIMIT 150
),
top_by_activity AS (
  SELECT r.Id AS PostId FROM recent_activity r WHERE r.PostTypeId = 1 ORDER BY r.RecentRankByType ASC LIMIT 150
),
candidates AS (
  SELECT PostId FROM top_by_score
  UNION
  SELECT PostId FROM top_by_activity
  -- EXCEPT posts closed recently (use PostHistory type 10 for close)
  EXCEPT
  SELECT ph.PostId FROM PostHistory ph WHERE ph.PostHistoryTypeId = 10 AND ph.CreationDate > NOW() - INTERVAL '30 days'
),
-- assemble final rich record per question candidate
rich_questions AS (
  SELECT
    q.Id,
    q.Title,
    q.Tags,
    q.CreationDate,
    q.LastActivityDate,
    q.ViewCount,
    q.Score AS QuestionScore,
    COALESCE(a.AnswerCount,0) AS AnswerCount,
    COALESCE(a.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(a.DistinctAnswerers,0) AS DistinctAnswerers,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAccepted,
    COALESCE(vs.VoteCount,0) AS TotalVotes,
    COALESCE(vs.UpVotes,0) AS UpVotes,
    COALESCE(vs.DownVotes,0) AS DownVotes,
    COALESCE(vs.Favorites,0) AS Favorites,
    COALESCE(ps.CommentCount,0) AS Comments,
    COALESCE(pe.EditCount,0) AS Edits,
    COALESCE(lb.BadgeCount,0) AS OwnerBadges,
    COALESCE(u.Reputation,0) AS OwnerReputation,
    u.DisplayName AS OwnerDisplayName,
    -- compute time to first answer (days), with NULL logic (if none, use now - creation)
    COALESCE(EXTRACT(EPOCH FROM (COALESCE(a.FirstAnswerDate, NOW()) - q.CreationDate))/86400.0, NULL) AS DaysToFirstAnswer,
    -- composite heuristic score mixing popularity, quality, recency, and owner reputation
    (
      (COALESCE(q.Score,0) * 1.5)
      + (COALESCE(a.AvgAnswerScore,0) * 2.0)
      + (LEAST(COALESCE(q.ViewCount,0), 100000)::double precision / 1000.0)
      + (GREATEST(COALESCE(u.Reputation,0), 0)::double precision / 1000.0)
      + (CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 20 ELSE 0 END)
      + (COALESCE(vs.Favorites,0) * 3)
      - (COALESCE(a.AnswerCount,0) * 0.5)
      + (COALESCE(ps.CommentCount,0) * 0.2)
    ) * COALESCE(ra.RecencyDecay, 1.0) AS CompositeScore,
    -- textual small fingerprint: first 100 chars of body-safe title + tag list summary
    LEFT(COALESCE(q.Title, ''), 100) || COALESCE(' [' || (SELECT string_agg(distinct te.TagName, ', ' ORDER BY te.TagName) FROM tag_expansion te WHERE te.QuestionId = q.Id) || ']', '') AS TitleFingerprint,
    -- boolean flags and null-safe indicators
    (q.ClosedDate IS NOT NULL) AS IsClosed,
    (q.CommunityOwnedDate IS NOT NULL) AS IsCommunityOwned,
    -- last significant activity: prefer last edit, then last activity, then last comment
    COALESCE(pe.LastEditDate, q.LastActivityDate, ps.LastCommentDate) AS LastSignificantActivity
  FROM Posts q
  JOIN candidates c ON c.PostId = q.Id
  LEFT JOIN answer_agg a ON a.QuestionId = q.Id
  LEFT JOIN vote_stats vs ON vs.PostId = q.Id
  LEFT JOIN comment_stats ps ON ps.PostId = q.Id
  LEFT JOIN post_edits pe ON pe.PostId = q.Id
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
  LEFT JOIN user_badges lb ON lb.UserId = u.Id
  LEFT JOIN recent_activity ra ON ra.Id = q.Id
),
-- final ranking and enrichment with correlated subqueries and window functions
final_ranked AS (
  SELECT
    rq.*,
    -- percentile ranks within candidate set
    PERCENT_RANK() OVER (ORDER BY rq.CompositeScore DESC) AS CompositePercentile,
    ROW_NUMBER() OVER (ORDER BY rq.CompositeScore DESC, rq.ViewCount DESC NULLS LAST) AS CompositeRank,
    -- correlated subquery: example of heavier work: top 3 answerers by total score for this question
    (
      SELECT string_agg(ans_info, '; ' ORDER BY total_score DESC)
      FROM (
        SELECT u2.DisplayName || COALESCE(' (+' || SUM(a2.Score)::text || ')','') AS ans_info, SUM(a2.Score) AS total_score
        FROM Posts a2
        LEFT JOIN Users u2 ON u2.Id = a2.OwnerUserId
        WHERE a2.ParentId = rq.Id AND a2.PostTypeId = 2
        GROUP BY u2.DisplayName
        ORDER BY total_score DESC NULLS LAST
        LIMIT 3
      ) AS sub
    ) AS Top3AnswerersSummary,
    -- correlated scalar: median answer score (approx via ORDER BY OFFSET)
    (
      SELECT AVG(x.score) FROM (
        SELECT a3.Score FROM Posts a3 WHERE a3.ParentId = rq.Id AND a3.PostTypeId = 2 ORDER BY a3.Score NULLS LAST
        LIMIT 2 OFFSET GREATEST(0, (SELECT COUNT(*) FROM Posts a4 WHERE a4.ParentId = rq.Id AND a4.PostTypeId = 2) / 2 - 1)
      ) x
    ) AS MedianAnswerScore
  FROM rich_questions rq
)
-- final selection: top 50 by composite score plus a small intersect with high-visibility tags
SELECT
  fr.CompositeRank,
  fr.CompositeScore,
  fr.CompositePercentile,
  fr.Id AS QuestionId,
  fr.Title,
  fr.TitleFingerprint,
  fr.Tags,
  fr.ViewCount,
  fr.QuestionScore,
  fr.AnswerCount,
  fr.AvgAnswerScore,
  fr.MedianAnswerScore,
  fr.DaysToFirstAnswer,
  fr.HasAccepted,
  fr.UpVotes,
  fr.DownVotes,
  fr.Favorites,
  fr.Comments,
  fr.Edits,
  fr.OwnerDisplayName,
  fr.OwnerReputation,
  fr.OwnerBadges,
  fr.IsClosed,
  fr.IsCommunityOwned,
  fr.LastSignificantActivity,
  fr.Top3AnswerersSummary
FROM final_ranked fr
WHERE fr.CompositeRank <= 50
ORDER BY fr.CompositeScore DESC, fr.ViewCount DESC
;