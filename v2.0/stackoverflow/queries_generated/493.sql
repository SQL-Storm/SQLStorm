-- {"query": "493.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3235} 
WITH
-- Active users and their activity windows
active_users AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.UpVotes,
    u.DownVotes,
    u.Views,
    COUNT(b.Id) AS BadgeCount,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
    DATE_TRUNC('month', u.CreationDate) AS CohortMonth
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
-- Posts enriched with question/answer role and tag array
enriched_posts AS (
  SELECT
    p.Id,
    p.PostTypeId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.ClosedDate,
    p.Title,
    p.Tags,
    NULLIF(TRIM(p.OwnerDisplayName), '') AS OwnerDisplayName,
    CASE WHEN p.PostTypeId = 1 THEN 'Question'
         WHEN p.PostTypeId = 2 THEN 'Answer'
         ELSE 'Other' END AS PostRole,
    CASE
      WHEN p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) >= 2
      THEN string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
      ELSE ARRAY[]::varchar[]
    END AS TagArray
  FROM Posts p
),
-- Votes aggregated per post
post_vote_agg AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 2) AS UpVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 3) AS DownVotes,
    COUNT(*) FILTER (WHERE v.VoteTypeId = 5) AS Favorites,
    COUNT(*) FILTER (WHERE v.VoteTypeId IN (8,9)) AS BountyEvents,
    SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END) AS BountyAmount
  FROM Votes v
  GROUP BY v.PostId
),
-- Close reasons per question via PostHistory
question_close_reasons AS (
  SELECT
    ph.PostId,
    MAX(ph.CreationDate) AS LastClosedAt,
    MAX(CASE
          WHEN ph.PostHistoryTypeId = 10 THEN
            CASE
              WHEN ph.Comment ~ '^[0-9]+$' THEN ph.Comment
              ELSE NULL
            END
        END) AS LastCloseReasonId
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId = 10
  GROUP BY ph.PostId
),
-- Link graph metrics (duplicates and general links)
link_graph AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks,
    COUNT(*) FILTER (WHERE pl.LinkTypeId = 1) AS RelatedLinks
  FROM PostLinks pl
  GROUP BY pl.PostId
),
-- Commenter diversity per post
comment_diversity AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCount,
    COUNT(DISTINCT COALESCE(c.UserId, -c.Id)) AS DistinctCommenters
  FROM Comments c
  GROUP BY c.PostId
),
-- Identify hot question windows via PostHistory
hot_windows AS (
  SELECT
    ph.PostId,
    MIN(CASE WHEN ph.PostHistoryTypeId = 52 THEN ph.CreationDate END) AS FirstHotAt,
    MAX(CASE WHEN ph.PostHistoryTypeId = 53 THEN ph.CreationDate END) AS LastHotRemovedAt
  FROM PostHistory ph
  WHERE ph.PostHistoryTypeId IN (52,53)
  GROUP BY ph.PostId
),
-- Rank answers per question by score and creation date
answer_rank AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC, a.Id ASC) AS RankByScore,
    ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.CreationDate ASC, a.Id ASC) AS RankByTime
  FROM enriched_posts a
  WHERE a.PostRole = 'Answer'
),
-- Per-question aggregates including acceptance and answer dynamics
question_agg AS (
  SELECT
    q.Id AS QuestionId,
    q.OwnerUserId AS AskerId,
    q.Title,
    q.CreationDate AS AskedAt,
    q.Score AS QuestionScore,
    q.ViewCount,
    q.AnswerCount,
    q.ClosedDate,
    q.TagArray,
    COALESCE(pva.UpVotes,0) AS QUpVotes,
    COALESCE(pva.DownVotes,0) AS QDownVotes,
    COALESCE(pva.Favorites,0) AS QFavorites,
    COALESCE(lg.DuplicateLinks,0) AS DuplicateLinks,
    COALESCE(lg.RelatedLinks,0) AS RelatedLinks,
    COALESCE(cd.CommentCount,0) AS QCommentCount,
    COALESCE(cd.DistinctCommenters,0) AS QDistinctCommenters,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAccepted,
    CASE WHEN q.AcceptedAnswerId IS NOT NULL THEN q.AcceptedAnswerId END AS AcceptedAnswerId,
    qc.LastClosedAt,
    qc.LastCloseReasonId::int AS LastCloseReasonId,
    hw.FirstHotAt,
    hw.LastHotRemovedAt
  FROM enriched_posts q
  LEFT JOIN post_vote_agg pva ON pva.PostId = q.Id
  LEFT JOIN link_graph lg ON lg.PostId = q.Id
  LEFT JOIN comment_diversity cd ON cd.PostId = q.Id
  LEFT JOIN question_close_reasons qc ON qc.PostId = q.Id
  LEFT JOIN hot_windows hw ON hw.PostId = q.Id
  WHERE q.PostRole = 'Question'
),
-- Time-to-accept and answer metrics
answer_metrics AS (
  SELECT
    qa.QuestionId,
    MIN(a.CreationDate) AS FirstAnswerAt,
    COUNT(*) AS AnswerTotal,
    SUM(CASE WHEN ar.RankByScore = 1 THEN 1 ELSE 0 END) AS HasTopScoringAnswer,
    MAX(a.Score) AS MaxAnswerScore,
    AVG(a.Score::numeric) AS AvgAnswerScore,
    MIN(CASE WHEN qa.AcceptedAnswerId = a.Id THEN a.CreationDate END) AS AcceptedAt,
    MIN(CASE WHEN ar.RankByTime = 1 THEN a.CreationDate END) AS EarliestAnswerAt
  FROM question_agg qa
  JOIN enriched_posts a ON a.ParentId = qa.QuestionId AND a.PostRole = 'Answer'
  JOIN answer_rank ar ON ar.AnswerId = a.Id
  GROUP BY qa.QuestionId
),
-- Compute per-user rolling stats over time for questions
user_question_windows AS (
  SELECT
    qa.AskerId AS UserId,
    qa.QuestionId,
    qa.AskedAt,
    qa.QuestionScore,
    COUNT(*) OVER (PARTITION BY qa.AskerId ORDER BY qa.AskedAt ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumeQuestionsAsked,
    AVG(qa.QuestionScore) OVER (PARTITION BY qa.AskerId ORDER BY qa.AskedAt ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS AvgScoreLast10,
    SUM(CASE WHEN qa.HasAccepted = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY qa.AskerId ORDER BY qa.AskedAt) AS CumeAcceptedQuestions
  FROM question_agg qa
),
-- Tag popularity snapshot for questions
tag_popularity AS (
  SELECT
    t.TagName,
    t.Count AS GlobalTagCount
  FROM Tags t
),
-- Expand tags per question
question_tags AS (
  SELECT
    qa.QuestionId,
    LOWER(TRIM(tag)) AS TagName
  FROM question_agg qa
  CROSS JOIN LATERAL UNNEST(qa.TagArray) AS tag
),
-- Per-question tag signals
question_tag_signals AS (
  SELECT
    qt.QuestionId,
    COUNT(*) AS TagCount,
    SUM(CASE WHEN tp.GlobalTagCount > 0 THEN 1 ELSE 0 END) AS KnownTagCount,
    MAX(tp.GlobalTagCount) AS MaxTagGlobalCount,
    AVG(tp.GlobalTagCount::numeric) AS AvgTagGlobalCount
  FROM question_tags qt
  LEFT JOIN tag_popularity tp ON tp.TagName = qt.TagName
  GROUP BY qt.QuestionId
),
-- Build a union set for questions that are either hot, closed, or have duplicates
interesting_questions AS (
  SELECT qa.QuestionId FROM question_agg qa WHERE qa.FirstHotAt IS NOT NULL
  UNION
  SELECT qa.QuestionId FROM question_agg qa WHERE qa.ClosedDate IS NOT NULL
  UNION
  SELECT qa.QuestionId FROM question_agg qa WHERE qa.DuplicateLinks > 0
),
-- Correlated subquery for last editor display on the question or accepted answer
last_editor_snapshot AS (
  SELECT
    qa.QuestionId,
    (
      SELECT COALESCE(pq.LastEditorDisplayName, pa.OwnerDisplayName, pq.OwnerDisplayName)
      FROM enriched_posts pq
      LEFT JOIN enriched_posts pa ON pa.Id = qa.AcceptedAnswerId
      WHERE pq.Id = qa.QuestionId
    ) AS LastKnownEditorDisplay
  FROM question_agg qa
),
-- Window function for global ranking by composite score
global_rank AS (
  SELECT
    qa.QuestionId,
    DENSE_RANK() OVER (
      ORDER BY
        COALESCE(qa.QFavorites,0)*3
        + COALESCE(qa.QUpVotes,0)*2
        - COALESCE(qa.QDownVotes,0)
        + COALESCE(qa.ViewCount/100,0)
        + COALESCE(qts.KnownTagCount,0)
        + COALESCE(aem.MaxAnswerScore,0)
        DESC,
        qa.AskedAt DESC
    ) AS PopularityRank
  FROM question_agg qa
  LEFT JOIN question_tag_signals qts ON qts.QuestionId = qa.QuestionId
  LEFT JOIN answer_metrics aem ON aem.QuestionId = qa.QuestionId
),
-- Users merged with activity
user_enriched AS (
  SELECT
    au.*,
    uqw.CumeQuestionsAsked,
    uqw.AvgScoreLast10,
    uqw.CumeAcceptedQuestions
  FROM active_users au
  LEFT JOIN LATERAL (
    SELECT
      uq.CumeQuestionsAsked,
      uq.AvgScoreLast10,
      uq.CumeAcceptedQuestions
    FROM user_question_windows uq
    WHERE uq.UserId = au.UserId
    ORDER BY uq.AskedAt DESC
    LIMIT 1
  ) uqw ON TRUE
)
SELECT
  qa.QuestionId,
  qa.Title,
  qa.AskedAt,
  qa.QuestionScore,
  qa.ViewCount,
  qa.QUpVotes,
  qa.QDownVotes,
  qa.QFavorites,
  qa.AnswerCount,
  qa.HasAccepted,
  qa.AcceptedAnswerId,
  qa.LastClosedAt,
  qa.LastCloseReasonId,
  qa.FirstHotAt,
  qa.LastHotRemovedAt,
  qa.DuplicateLinks,
  qa.RelatedLinks,
  qa.QCommentCount,
  qa.QDistinctCommenters,
  COALESCE(aem.FirstAnswerAt, qa.AskedAt) AS FirstAnswerAt,
  aem.AcceptedAt,
  EXTRACT(EPOCH FROM (aem.AcceptedAt - qa.AskedAt))/3600.0 AS HoursToAccept,
  aem.AnswerTotal,
  aem.MaxAnswerScore,
  ROUND(aem.AvgAnswerScore::numeric, 2) AS AvgAnswerScore,
  qts.TagCount,
  qts.KnownTagCount,
  qts.MaxTagGlobalCount,
  ROUND(qts.AvgTagGlobalCount::numeric, 2) AS AvgTagGlobalCount,
  ue.UserId AS AskerId,
  ue.DisplayName AS AskerDisplayName,
  ue.Reputation AS AskerReputation,
  ue.BadgeCount AS AskerBadges,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ue.CohortMonth,
  ue.CumeQuestionsAsked,
  ue.AvgScoreLast10,
  ue.CumeAcceptedQuestions,
  les.LastKnownEditorDisplay,
  gr.PopularityRank,
  CASE
    WHEN qa.ClosedDate IS NOT NULL THEN 'Closed'
    WHEN qa.FirstHotAt IS NOT NULL THEN 'Hot'
    WHEN qa.DuplicateLinks > 0 THEN 'Duplicate-linked'
    ELSE 'Normal'
  END AS StatusBucket,
  CASE
    WHEN qa.Title IS NULL OR LENGTH(TRIM(qa.Title)) = 0 THEN '[untitled]'
    ELSE INITCAP(SUBSTRING(qa.Title FROM 1 FOR 120))
  END AS NormalizedTitle,
  CASE
    WHEN array_length(qa.TagArray,1) IS NULL THEN '(no-tags)'
    WHEN array_length(qa.TagArray,1) = 1 THEN qa.TagArray[1]
    ELSE qa.TagArray[1] || ' +' || (array_length(qa.TagArray,1)-1)::text || ' more'
  END AS TagSummary
FROM question_agg qa
LEFT JOIN answer_metrics aem ON aem.QuestionId = qa.QuestionId
LEFT JOIN question_tag_signals qts ON qts.QuestionId = qa.QuestionId
LEFT JOIN user_enriched ue ON ue.UserId = qa.AskerId
LEFT JOIN last_editor_snapshot les ON les.QuestionId = qa.QuestionId
LEFT JOIN global_rank gr ON gr.QuestionId = qa.QuestionId
WHERE qa.QuestionId IN (SELECT QuestionId FROM interesting_questions)
  AND COALESCE(qa.ViewCount,0) > 0
  AND (
    qa.LastCloseReasonId IS NULL
    OR qa.LastCloseReasonId NOT IN (20) -- excluding "Noise or pointless" on Meta if present
  )
  AND (
    qa.TagArray IS NULL
    OR NOT EXISTS (
      SELECT 1
      FROM UNNEST(qa.TagArray) t(tag)
      WHERE LOWER(tag) LIKE '%homework%'
         OR LOWER(tag) LIKE '%survey%'
    )
  )
ORDER BY gr.PopularityRank NULLS LAST, qa.AskedAt DESC
LIMIT 500;