-- {"query": "238.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 3517} 
WITH
-- explode tags from question posts
tags_expanded AS (
  SELECT
    p.Id AS PostId,
    unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><'))::varchar(100) AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),

-- aggregate votes per post with conditional sums and first/last vote dates
votes_agg AS (
  SELECT
    v.PostId,
    COUNT(*) AS TotalVotes,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) FILTER (WHERE v.VoteTypeId IS NOT NULL) AS UpVotes,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
    MIN(v.CreationDate) AS FirstVoteDate,
    MAX(v.CreationDate) AS LastVoteDate
  FROM Votes v
  GROUP BY v.PostId
),

-- comments per post and top commenter (correlated subquery inside)
comments_agg AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount,
    MAX(c.Score) AS MaxCommentScore,
    (SELECT u.DisplayName
     FROM Users u
     WHERE u.Id = (SELECT c2.UserId FROM Comments c2 WHERE c2.PostId = c.PostId AND c2.UserId IS NOT NULL ORDER BY c2.Score DESC NULLS LAST, c2.CreationDate ASC LIMIT 1)
    ) AS TopCommenterName
  FROM Comments c
  GROUP BY c.PostId
),

-- badge counts for post owners (left join target might be null)
badges_agg AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    BOOL_OR(b.TagBased) AS HasTagBadges
  FROM Badges b
  GROUP BY b.UserId
),

-- post links aggregated by link type (duplicates, linked)
links_agg AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedCount,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateCount,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM PostLinks pl
  GROUP BY pl.PostId
),

-- last meaningful post history entry per post
history_last AS (
  SELECT DISTINCT ON (ph.PostId)
    ph.PostId,
    ph.PostHistoryTypeId,
    ph.CreationDate AS HistoryDate,
    ph.UserId AS HistoryUserId,
    ph.Comment AS HistoryComment,
    ph.Text AS HistoryText
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IS NOT NULL
  ORDER BY ph.PostId, ph.CreationDate DESC
),

-- answer-level stats and ranking per question
answers AS (
  SELECT
    a.Id,
    a.ParentId AS QuestionId,
    a.OwnerUserId AS AnswerOwner,
    a.Score AS AnswerScore,
    a.CreationDate AS AnswerCreation,
    COALESCE(vs.UpVotes,0) AS AnswerUpVotes,
    COALESCE(vs.DownVotes,0) AS AnswerDownVotes,
    CASE WHEN q.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END AS IsAccepted,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankByScore,
    RANK() OVER (PARTITION BY a.ParentId ORDER BY COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0) DESC) AS AnswerRankByNetVotes,
    LENGTH(COALESCE(a.Body,'')) AS AnswerBodyLength
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  LEFT JOIN votes_agg vs ON vs.PostId = a.Id
  WHERE a.PostTypeId = 2
),

-- per-question summary combining many aggregates
question_core AS (
  SELECT
    q.Id,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.FavoriteCount,
    COALESCE(va.UpVotes,0) AS QuestionUpVotes,
    COALESCE(va.DownVotes,0) AS QuestionDownVotes,
    COALESCE(ca.CommentCount,0) AS QuestionCommentCount,
    COALESCE(la.LinkedCount,0) AS LinkedCount,
    COALESCE(la.DuplicateCount,0) AS DuplicateCount,
    COALESCE(hh.PostHistoryTypeId, NULL) AS LastHistoryType,
    COALESCE(hh.HistoryDate, q.LastActivityDate) AS LastActivityTracked,
    (SELECT COUNT(*) FROM answers a WHERE a.ParentId = q.Id) AS ComputedAnswerCount,
    (SELECT AVG(a.Score) FROM answers a WHERE a.ParentId = q.Id) AS AvgAnswerScore,
    (SELECT MAX(a.Score) FROM answers a WHERE a.ParentId = q.Id) AS MaxAnswerScore,
    (SELECT SUM(COALESCE(vs.UpVotes,0) - COALESCE(vs.DownVotes,0)) FROM Posts p JOIN votes_agg vs ON vs.PostId = p.Id WHERE p.ParentId = q.Id) AS AnswersNetVotes,
    -- correlated: most recent editor name if any
    (SELECT u.DisplayName FROM Users u WHERE u.Id = q.LastEditorUserId) AS LastEditorName
  FROM Posts q
  LEFT JOIN votes_agg va ON va.PostId = q.Id
  LEFT JOIN comments_agg ca ON ca.PostId = q.Id
  LEFT JOIN links_agg la ON la.PostId = q.Id
  LEFT JOIN history_last hh ON hh.PostId = q.Id
  WHERE q.PostTypeId = 1
),

-- combine question core with owner info, badges, tags aggregated and compute composite quality score
question_enriched AS (
  SELECT
    qc.*,
    u.DisplayName AS OwnerName,
    u.Reputation AS OwnerReputation,
    COALESCE(bg.GoldBadges,0) AS OwnerGold,
    COALESCE(bg.SilverBadges,0) AS OwnerSilver,
    COALESCE(bg.BronzeBadges,0) AS OwnerBronze,
    COALESCE(string_agg(DISTINCT te.Tag, ',' ORDER BY te.Tag), '') AS TagList,
    -- quality score: weighted combination with NULL-safe operations and non-linear transforms
    (
      COALESCE(qc.QuestionScore,0)::numeric * 0.5
      + COALESCE(qc.ViewCount,0)::numeric / NULLIF(GREATEST(EXTRACT(EPOCH FROM (now() - qc.CreationDate)) / 86400.0, 1),0) * 0.1
      + COALESCE(qc.AvgAnswerScore,0)::numeric * 0.3
      + GREATEST(LEAST(COALESCE(qc.FavoriteCount,0),50),0)::numeric * 0.02
      + (CASE WHEN qc.MaxAnswerScore IS NOT NULL THEN POWER(COALESCE(qc.MaxAnswerScore,0)+1, 0.5) ELSE 0 END) * 0.08
      - (COALESCE(qc.DuplicateCount,0)::numeric * 0.5)
      + (CASE WHEN qc.LinkedCount > 0 THEN 0.2 ELSE 0 END)
    ) AS RawQuality,
    -- normalized quality per tag later
    COALESCE(qc.LastActivityTracked, qc.CreationDate) AS EffectiveLastActivity
  FROM question_core qc
  LEFT JOIN Users u ON u.Id = qc.OwnerUserId
  LEFT JOIN badges_agg bg ON bg.UserId = qc.OwnerUserId
  LEFT JOIN tags_expanded te ON te.PostId = qc.Id
  GROUP BY qc.Id, qc.Title, qc.CreationDate, qc.OwnerUserId, qc.QuestionScore, qc.ViewCount, qc.AnswerCount, qc.FavoriteCount,
           qc.QuestionUpVotes, qc.QuestionDownVotes, qc.QuestionCommentCount, qc.LinkedCount, qc.DuplicateCount,
           qc.LastHistoryType, qc.LastActivityTracked, qc.ComputedAnswerCount, qc.AvgAnswerScore, qc.MaxAnswerScore, qc.AnswersNetVotes,
           qc.LastEditorName, u.DisplayName, u.Reputation, bg.GoldBadges, bg.SilverBadges, bg.BronzeBadges
),

-- normalize RawQuality within each tag and also compute percentile across all questions
quality_windows AS (
  SELECT
    qe.*,
    PERCENT_RANK() OVER (ORDER BY qe.RawQuality) AS GlobalQualityPercentile,
    ROW_NUMBER() OVER (PARTITION BY t.Tag ORDER BY qe.RawQuality DESC NULLS LAST) AS TagRankForQuality,
    COUNT(*) OVER (PARTITION BY t.Tag) AS TagTotalQuestions,
    AVG(qe.RawQuality) OVER (PARTITION BY t.Tag) AS AvgQualityPerTag
  FROM question_enriched qe
  LEFT JOIN tags_expanded t ON t.PostId = qe.Id
),

-- pick the top answer per question with correlated subquery fallback
top_answers AS (
  SELECT
    a.*
  FROM answers a
  WHERE a.AnswerRankByScore = 1
),

-- final selection: join everything, include some computed textual summaries and unusual predicates
final_selection AS (
  SELECT
    qw.Id AS QuestionId,
    qw.Title,
    COALESCE(qw.TagList, '<untagged>') AS Tags,
    qw.OwnerName,
    COALESCE(qw.OwnerReputation,0) AS OwnerRep,
    qw.ComputedAnswerCount AS AnswerCount,
    COALESCE(ta.Id, NULL) AS TopAnswerId,
    COALESCE(ta.AnswerScore,0) AS TopAnswerScore,
    COALESCE(qw.QuestionCommentCount,0) AS Comments,
    qw.RawQuality,
    ROUND(qw.GlobalQualityPercentile::numeric, 4) AS GlobalPct,
    qw.TagRankForQuality,
    qw.TagTotalQuestions,
    qw.AvgQualityPerTag,
    -- crafty string expression mixing null logic and concatenation
    (CASE
       WHEN qw.OwnerName IS NULL THEN 'anon'
       ELSE substr(coalesce(qw.OwnerName,''),1,24) || ' (' || COALESCE(NULLIF(qw.OwnerRep,0)::text, '0') || ')'
     END) AS OwnerSummary,
    -- datetime difference expressions and null-safe checks
    AGE(now(), qw.EffectiveLastActivity) AS TimeSinceLastActivity,
    -- complex predicate example: detect likely "hot" question (many views and recent activity) using boolean expression
    (CASE WHEN qw.ViewCount > 10000 AND now() - qw.EffectiveLastActivity < interval '30 days' THEN TRUE ELSE FALSE END) AS IsHot,
    -- fuzzy tag pattern match using LIKE (string may contain tags concatenated by comma)
    (CASE WHEN qw.TagList ILIKE '%sql%' OR qw.TagList ILIKE '%postgres%' THEN TRUE ELSE FALSE END) AS IsSqlRelated,
    -- JSON-ish summary built via concatenation (not json function to keep general SQL)
    ('{q:' || qw.Id::text || ',qscore:' || COALESCE(qw.QuestionScore,0)::text || ',rawQ:' || ROUND(qw.RawQuality::numeric,2)::text || ',tags:"' || REPLACE(COALESCE(qw.TagList,''),'"','''') || '"}') AS CompactSummary
  FROM quality_windows qw
  LEFT JOIN top_answers ta ON ta.QuestionId = qw.Id
  WHERE qw.ComputedAnswerCount IS NOT NULL
    AND (qw.RawQuality IS NOT NULL OR qw.QuestionScore > 0)
)

-- final deliverable: main set unioned with a synthetic set of closed/duplicate questions to exercise set operators
SELECT *
FROM final_selection

UNION ALL

SELECT
  fs.QuestionId,
  fs.Title || ' (CLOSED/DUPE)' AS Title,
  fs.Tags,
  fs.OwnerName,
  fs.OwnerRep,
  fs.AnswerCount,
  fs.TopAnswerId,
  fs.TopAnswerScore,
  fs.Comments,
  fs.RawQuality * 0.1 AS RawQuality,
  fs.GlobalPct,
  fs.TagRankForQuality,
  fs.TagTotalQuestions,
  fs.AvgQualityPerTag,
  fs.OwnerSummary,
  fs.TimeSinceLastActivity,
  FALSE AS IsHot,
  fs.IsSqlRelated,
  fs.CompactSummary || '/*closed-synthetic*/' AS CompactSummary
FROM final_selection fs
JOIN question_core qc ON qc.Id = fs.QuestionId
WHERE qc.DuplicateCount > 0 OR qc.LastHistoryType IN (10,12,35) -- include closed/duplicate/migrated markers
ORDER BY RawQuality DESC NULLS LAST
LIMIT 250;