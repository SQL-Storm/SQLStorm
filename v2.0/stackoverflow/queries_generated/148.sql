-- {"query": "148.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3795} 
WITH
q AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.OwnerUserId,
    p.CreationDate AS QuestionCreationDate,
    p.Score AS QuestionScore,
    p.ViewCount,
    p.Tags,
    COALESCE(p.AnswerCount, 0) AS AnswerCount
  FROM Posts p
  WHERE p.PostTypeId = 1
),
a AS (
  SELECT
    pa.Id AS AnswerId,
    pa.ParentId AS QuestionId,
    pa.OwnerUserId AS AnswerOwnerId,
    pa.Score AS AnswerScore,
    pa.CreationDate AS AnswerCreationDate
  FROM Posts pa
  WHERE pa.PostTypeId = 2
),
user_core AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.Location,
    u.UpVotes,
    u.DownVotes
  FROM Users u
),
-- Aggregate user badge stats
user_badges AS (
  SELECT
    b.UserId,
    COUNT(*) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    MIN(b.Date) AS FirstBadgeDate,
    MAX(b.Date) AS LastBadgeDate
  FROM Badges b
  GROUP BY b.UserId
),
-- Votes per post and type
post_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
    SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount,
    SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteCount,
    SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyTotal,
    COUNT(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
-- First comment date per question
first_comment AS (
  SELECT
    c.PostId AS QuestionId,
    MIN(c.CreationDate) AS FirstCommentDate,
    COUNT(*) AS CommentCount
  FROM Comments c
  GROUP BY c.PostId
),
-- Duplicate and linked relationships
links AS (
  SELECT
    pl.PostId,
    pl.RelatedPostId,
    pl.LinkTypeId,
    lt.Name AS LinkTypeName
  FROM PostLinks pl
  JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
-- Close events and reasons from PostHistory (JSON/text field in Comment)
close_events AS (
  SELECT
    ph.PostId,
    MIN(ph.CreationDate) AS FirstCloseDate,
    COUNT(*) AS CloseEvents,
    MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment END) AS AnyCloseReasonRaw
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10
  GROUP BY ph.PostId
),
-- Tag explode (Postgres-compatible using string_to_array)
question_tags AS (
  SELECT
    q.QuestionId,
    TRIM(t) AS Tag
  FROM q
  CROSS JOIN LATERAL UNNEST(
    CASE
      WHEN q.Tags IS NULL THEN ARRAY[]::varchar[]
      WHEN length(q.Tags) <= 2 THEN ARRAY[]::varchar[]
      ELSE string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')
    END
  ) AS t
),
-- Tag popularity lookup
tag_stats AS (
  SELECT
    t.TagName,
    t.Count AS TagCount,
    t.IsModeratorOnly,
    t.IsRequired
  FROM Tags t
),
-- Rolling answerer performance per question
answerer_perf AS (
  SELECT
    a.QuestionId,
    a.AnswerOwnerId,
    COUNT(*) AS AnswersByUserToQuestion,
    SUM(a.AnswerScore) AS SumAnswerScoreToQuestion,
    MIN(a.AnswerCreationDate) AS FirstAnswerByUserToQuestion
  FROM a
  GROUP BY a.QuestionId, a.AnswerOwnerId
),
-- Windowed ranking of answers per question by score and recency
answer_rank AS (
  SELECT
    a.QuestionId,
    a.AnswerId,
    a.AnswerOwnerId,
    a.AnswerScore,
    a.AnswerCreationDate,
    ROW_NUMBER() OVER (PARTITION BY a.QuestionId ORDER BY a.AnswerScore DESC NULLS LAST, a.AnswerCreationDate ASC) AS rn_score,
    ROW_NUMBER() OVER (PARTITION BY a.QuestionId ORDER BY a.AnswerCreationDate ASC) AS rn_time
  FROM a
),
-- Accepted answer join for convenience
accepted AS (
  SELECT
    q.QuestionId,
    p.AcceptedAnswerId
  FROM q
  JOIN Posts p ON p.Id = q.QuestionId
),
-- Per-question aggregates with complex predicates
question_agg AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.OwnerUserId,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    pv.UpvoteCount AS QUpvotes,
    pv.DownvoteCount AS QDownvotes,
    pv.FavoriteCount AS QFavorites,
    pv.BountyTotal AS QBounty,
    fc.FirstCommentDate,
    fc.CommentCount,
    ce.FirstCloseDate,
    ce.CloseEvents,
    ce.AnyCloseReasonRaw,
    SUM(CASE WHEN l.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinks,
    SUM(CASE WHEN l.LinkTypeId = 1 THEN 1 ELSE 0 END) AS RelatedLinks,
    COUNT(DISTINCT qt.Tag) AS DistinctTagCount,
    MAX(CASE WHEN qt.Tag ILIKE '%sql%' THEN 1 ELSE 0 END) AS HasSqlTag,
    MAX(CASE WHEN qt.Tag ILIKE '%postgres%' THEN 1 ELSE 0 END) AS HasPostgresTag
  FROM q
  LEFT JOIN post_votes pv ON pv.PostId = q.QuestionId
  LEFT JOIN first_comment fc ON fc.QuestionId = q.QuestionId
  LEFT JOIN close_events ce ON ce.PostId = q.QuestionId
  LEFT JOIN links l ON l.PostId = q.QuestionId
  LEFT JOIN question_tags qt ON qt.QuestionId = q.QuestionId
  GROUP BY
    q.QuestionId, q.Title, q.OwnerUserId, q.QuestionCreationDate, q.QuestionScore, q.ViewCount, q.AnswerCount,
    pv.UpvoteCount, pv.DownvoteCount, pv.FavoriteCount, pv.BountyTotal,
    fc.FirstCommentDate, fc.CommentCount,
    ce.FirstCloseDate, ce.CloseEvents, ce.AnyCloseReasonRaw
),
-- Compute user-level aggregates and ratios
user_agg AS (
  SELECT
    uc.UserId,
    uc.DisplayName,
    uc.Reputation,
    uc.UserCreationDate,
    uc.Location,
    uc.UpVotes,
    uc.DownVotes,
    COALESCE(ub.TotalBadges, 0) AS TotalBadges,
    COALESCE(ub.GoldBadges, 0) AS GoldBadges,
    COALESCE(ub.SilverBadges, 0) AS SilverBadges,
    COALESCE(ub.BronzeBadges, 0) AS BronzeBadges,
    ub.FirstBadgeDate,
    ub.LastBadgeDate,
    NULLIF(uc.UpVotes,0) AS UpVotesNZ,
    NULLIF(uc.DownVotes,0) AS DownVotesNZ
  FROM user_core uc
  LEFT JOIN user_badges ub ON ub.UserId = uc.UserId
),
-- Windowed per-user post counts and recency
user_posting AS (
  SELECT
    p.OwnerUserId AS UserId,
    COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAuthored,
    COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswersAuthored,
    MAX(p.CreationDate) AS LastPostDate
  FROM Posts p
  WHERE p.OwnerUserId IS NOT NULL
  GROUP BY p.OwnerUserId
),
-- Combine question with top answers and accepted answer metadata
question_answer_rollup AS (
  SELECT
    qa.QuestionId,
    qa.Title,
    qa.OwnerUserId,
    qa.QuestionCreationDate,
    qa.QuestionScore,
    qa.ViewCount,
    qa.AnswerCount,
    qa.QUpvotes,
    qa.QDownvotes,
    qa.QFavorites,
    qa.QBounty,
    qa.FirstCommentDate,
    qa.CommentCount,
    qa.FirstCloseDate,
    qa.CloseEvents,
    qa.AnyCloseReasonRaw,
    qa.DuplicateLinks,
    qa.RelatedLinks,
    qa.DistinctTagCount,
    qa.HasSqlTag,
    qa.HasPostgresTag,
    ac.AcceptedAnswerId,
    ar_best.AnswerId AS TopScoreAnswerId,
    ar_best.AnswerOwnerId AS TopScoreAnswerOwnerId,
    ar_best.AnswerScore AS TopScoreAnswerScore,
    ar_fast.AnswerId AS FirstAnswerId,
    ar_fast.AnswerOwnerId AS FirstAnswerOwnerId,
    ar_fast.AnswerCreationDate AS FirstAnswerDate
  FROM question_agg qa
  LEFT JOIN accepted ac ON ac.QuestionId = qa.QuestionId
  LEFT JOIN answer_rank ar_best ON ar_best.QuestionId = qa.QuestionId AND ar_best.rn_score = 1
  LEFT JOIN answer_rank ar_fast ON ar_fast.QuestionId = qa.QuestionId AND ar_fast.rn_time = 1
),
-- Normalize close reason id if numeric in Comment (NULL-safe numeric extraction)
close_reason AS (
  SELECT
    qar.QuestionId,
    CASE
      WHEN qar.AnyCloseReasonRaw ~ '^[0-9]+$' THEN qar.AnyCloseReasonRaw
      ELSE NULL
    END::int AS CloseReasonId
  FROM question_answer_rollup qar
),
-- Bring in human-readable close reason
close_reason_named AS (
  SELECT
    cr.QuestionId,
    crt.Name AS CloseReasonName
  FROM close_reason cr
  LEFT JOIN CloseReasonTypes crt ON crt.Id = cr.CloseReasonId
),
-- Derive composite metrics and windowed ranks across questions
metrics AS (
  SELECT
    qar.*,
    crn.CloseReasonName,
    -- engagement score with null handling
    COALESCE(qar.QUpvotes,0) - COALESCE(qar.QDownvotes,0) + COALESCE(qar.QFavorites,0) + GREATEST(COALESCE(qar.CommentCount,0)::int, 0) AS EngagementScore,
    CASE
      WHEN COALESCE(qar.AnswerCount,0) = 0 THEN NULL
      ELSE COALESCE(qar.ViewCount,0)::numeric / NULLIF(qar.AnswerCount,0)
    END AS ViewsPerAnswer,
    CASE
      WHEN qar.TopScoreAnswerId IS NOT NULL THEN 1
      ELSE 0
    END AS HasTopAnswer,
    CASE
      WHEN qar.AcceptedAnswerId IS NOT NULL THEN 1
      ELSE 0
    END AS HasAcceptedAnswer,
    -- time to first answer
    EXTRACT(EPOCH FROM (qar.FirstAnswerDate - qar.QuestionCreationDate)) / 60.0 AS MinutesToFirstAnswer
  FROM question_answer_rollup qar
  LEFT JOIN close_reason_named crn ON crn.QuestionId = qar.QuestionId
),
-- enrich with owner and top answerer user stats
owner_enriched AS (
  SELECT
    m.*,
    ua.DisplayName AS OwnerName,
    ua.Reputation AS OwnerReputation,
    ua.Location AS OwnerLocation,
    ua.TotalBadges AS OwnerBadges,
    up.QuestionsAuthored AS OwnerQuestions,
    up.AnswersAuthored AS OwnerAnswers,
    up.LastPostDate AS OwnerLastPostDate
  FROM metrics m
  LEFT JOIN user_agg ua ON ua.UserId = m.OwnerUserId
  LEFT JOIN user_posting up ON up.UserId = m.OwnerUserId
),
top_answerer_enriched AS (
  SELECT
    oe.*,
    ua2.DisplayName AS TopAnswererName,
    ua2.Reputation AS TopAnswererReputation,
    ua2.TotalBadges AS TopAnswererBadges,
    up2.AnswersAuthored AS TopAnswererAnswersAuthored
  FROM owner_enriched oe
  LEFT JOIN user_agg ua2 ON ua2.UserId = oe.TopScoreAnswerOwnerId
  LEFT JOIN user_posting up2 ON up2.UserId = oe.TopScoreAnswerOwnerId
),
-- Build a per-tag rollup for each question (string aggregation + top tag by global popularity)
tag_rollup AS (
  SELECT
    qt.QuestionId,
    string_agg(qt.Tag, ',' ORDER BY ts.TagCount DESC NULLS LAST, qt.Tag) AS TagsCSV,
    (ARRAY_AGG(qt.Tag ORDER BY ts.TagCount DESC NULLS LAST, qt.Tag))[1] AS TopTag,
    MAX(CASE WHEN ts.IsModeratorOnly THEN 1 ELSE 0 END) AS AnyModOnlyTag,
    MAX(CASE WHEN ts.IsRequired THEN 1 ELSE 0 END) AS AnyRequiredTag
  FROM question_tags qt
  LEFT JOIN tag_stats ts ON ts.TagName = qt.Tag
  GROUP BY qt.QuestionId
),
final_scores AS (
  SELECT
    tae.*,
    COALESCE(tr.TagsCSV, '') AS TagsCSV,
    tr.TopTag,
    tr.AnyModOnlyTag,
    tr.AnyRequiredTag,
    -- composite final score mixing engagement, bounty, views per answer, and penalties for closures
    (
      COALESCE(tae.EngagementScore, 0)
      + COALESCE(tae.QBounty, 0) / 50.0
      + COALESCE(tae.ViewsPerAnswer, 0) * 0.1
      + CASE WHEN tae.HasAcceptedAnswer = 1 THEN 2 ELSE 0 END
      + CASE WHEN tae.HasTopAnswer = 1 THEN 1 ELSE 0 END
      - CASE WHEN tae.FirstCloseDate IS NOT NULL THEN 3 ELSE 0 END
    ) AS CompositeScore
  FROM top_answerer_enriched tae
  LEFT JOIN tag_rollup tr ON tr.QuestionId = tae.QuestionId
),
-- Rank questions by multiple dimensions
ranked AS (
  SELECT
    fs.*,
    ROW_NUMBER() OVER (ORDER BY fs.CompositeScore DESC NULLS LAST, fs.ViewCount DESC NULLS LAST) AS rn_composite,
    RANK() OVER (ORDER BY fs.EngagementScore DESC NULLS LAST) AS r_engagement,
    RANK() OVER (ORDER BY fs.MinutesToFirstAnswer ASC NULLS LAST) AS r_fastest_answer,
    DENSE_RANK() OVER (ORDER BY COALESCE(fs.QUpvotes,0) - COALESCE(fs.QDownvotes,0) DESC) AS r_net_votes
  FROM final_scores fs
),
-- Correlated subquery: measure how often the owner answers their own question
owner_self_answer AS (
  SELECT
    r.QuestionId,
    EXISTS (
      SELECT 1
      FROM a
      WHERE a.QuestionId = r.QuestionId AND a.AnswerOwnerId = r.OwnerUserId
    ) AS OwnerSelfAnswered
  FROM ranked r
)
SELECT
  r.QuestionId,
  r.Title,
  r.OwnerUserId,
  r.OwnerName,
  r.OwnerReputation,
  r.OwnerLocation,
  r.OwnerBadges,
  r.OwnerQuestions,
  r.OwnerAnswers,
  r.OwnerLastPostDate,
  r.QuestionCreationDate,
  r.QuestionScore,
  r.ViewCount,
  r.AnswerCount,
  r.QUpvotes,
  r.QDownvotes,
  r.QFavorites,
  r.QBounty,
  r.FirstCommentDate,
  r.CommentCount,
  r.FirstCloseDate,
  r.CloseEvents,
  r.CloseReasonName,
  r.DuplicateLinks,
  r.RelatedLinks,
  r.DistinctTagCount,
  r.HasSqlTag,
  r.HasPostgresTag,
  r.AcceptedAnswerId,
  r.TopScoreAnswerId,
  r.TopScoreAnswerOwnerId,
  r.TopScoreAnswerScore,
  r.FirstAnswerId,
  r.FirstAnswerOwnerId,
  r.FirstAnswerDate,
  r.EngagementScore,
  r.ViewsPerAnswer,
  ROUND(r.MinutesToFirstAnswer::numeric, 2) AS MinutesToFirstAnswer,
  r.TagsCSV,
  r.TopTag,
  r.AnyModOnlyTag,
  r.AnyRequiredTag,
  r.CompositeScore,
  r.rn_composite,
  r.r_engagement,
  r.r_fastest_answer,
  r.r_net_votes,
  osa.OwnerSelfAnswered
FROM ranked r
LEFT JOIN owner_self_answer osa ON osa.QuestionId = r.QuestionId
WHERE
  -- Complicated predicate combining tags, votes, closure, and null logic
  (
    (r.HasSqlTag = 1 OR r.HasPostgresTag = 1 OR COALESCE(r.TopTag,'') ILIKE '%database%')
    AND COALESCE(r.QUpvotes,0) - COALESCE(r.QDownvotes,0) >= 0
  )
  OR
  (
    r.CompositeScore > 10
    AND (r.FirstCloseDate IS NULL OR r.CloseReasonName IS DISTINCT FROM 'Duplicate')
  )
  OR
  (
    r.AnswerCount = 0
    AND r.ViewCount > 0
    AND r.FirstCloseDate IS NULL
  )
ORDER BY
  r.rn_composite
FETCH FIRST 250 ROWS WITH TIES;