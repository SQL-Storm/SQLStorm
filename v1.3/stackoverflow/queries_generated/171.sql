-- {"query": "171.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2865} 
WITH
-- explode tags into one row per tag per question
tag_split AS (
  SELECT
    p.Id AS PostId,
    TRIM(t) AS Tag
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), E'><')) AS t
  ) s
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),

-- basic per-question aggregates including accepted answer info and last editor
question_base AS (
  SELECT
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    q.LastActivityDate,
    q.ClosedDate,
    q.FavoriteCount,
    COALESCE(u.DisplayName, '<<deleted>>') AS OwnerName,
    COALESCE(le.DisplayName, '<<none>>') AS LastEditorName
  FROM Posts q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  LEFT JOIN Users le ON q.LastEditorUserId = le.Id
  WHERE q.PostTypeId = 1
),

-- vote breakdown per post including percent upvotes (NULL-safe)
post_votes AS (
  SELECT
    v.PostId,
    SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
    SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes,
    COUNT(*) FILTER (WHERE vt.Name IN ('UpMod','DownMod')) AS UpDownCount,
    SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS Favorites
  FROM Votes v
  LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
  GROUP BY v.PostId
),

-- compute tag popularity and recent trending score
tag_pop AS (
  SELECT
    ts.Tag,
    COUNT(DISTINCT ts.PostId) AS QuestionCount,
    SUM(q.Score) AS TotalScore,
    AVG(q.ViewCount) AS AvgViews,
    -- trending: weight recent questions higher (within 30 days)
    SUM( GREATEST(0, 30 - EXTRACT(day FROM now() - q.CreationDate)) )::numeric AS TrendingWeight
  FROM tag_split ts
  JOIN Posts q ON q.Id = ts.PostId
  GROUP BY ts.Tag
),

-- user badge summary using windowed ranking per user
user_badges AS (
  SELECT
    b.UserId,
    COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    COUNT(*) AS TotalBadges,
    ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY COUNT(*) DESC) AS rn -- trivial, for demo
  FROM Badges b
  GROUP BY b.UserId
),

-- recent activity per user (most recent post or comment)
user_recent AS (
  SELECT
    u.Id AS UserId,
    GREATEST(
      COALESCE(MAX(p.LastActivityDate), '1970-01-01'::timestamp),
      COALESCE(MAX(c.CreationDate), '1970-01-01'::timestamp)
    ) AS MostRecentActivity
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  GROUP BY u.Id
),

-- rank questions by composite hotness score (using window functions and null-safe math)
question_hotness AS (
  SELECT
    qb.*,
    COALESCE(pv.UpVotes,0) AS UpVotes,
    COALESCE(pv.DownVotes,0) AS DownVotes,
    COALESCE(pv.Favorites,0) AS Favorites,
    COALESCE(tp.TrendingWeight,0) AS TagTrending,
    -- composite score: score * log(views+1) + favorites*5 + (up-down)*2 + tag trending
    (qb.Score * LN(GREATEST(qb.ViewCount,1) + 1)
      + COALESCE(pv.Favorites,0) * 5
      + (COALESCE(pv.UpVotes,0) - COALESCE(pv.DownVotes,0)) * 2
      + COALESCE(tp.TrendingWeight,0)
    )::numeric AS HotScore,
    ROW_NUMBER() OVER (ORDER BY
      (qb.Score * LN(GREATEST(qb.ViewCount,1) + 1)
        + COALESCE(pv.Favorites,0) * 5
        + (COALESCE(pv.UpVotes,0) - COALESCE(pv.DownVotes,0)) * 2
        + COALESCE(tp.TrendingWeight,0)
      ) DESC NULLS LAST
    ) AS HotRank
  FROM question_base qb
  LEFT JOIN post_votes pv ON pv.PostId = qb.Id
  LEFT JOIN (
    SELECT ts.PostId, SUM(tp.TrendingWeight) AS TrendingWeight
    FROM tag_split ts
    LEFT JOIN tag_pop tp ON tp.Tag = ts.Tag
    GROUP BY ts.PostId
  ) tp ON tp.PostId = qb.Id
),

-- correlated subquery to compute answer stats per question (min/max/median score of answers)
answer_stats AS (
  SELECT
    q.Id AS QuestionId,
    COALESCE(a.AnswerCount,0) AS AnswerCount,
    COALESCE(a.MinScore,0) AS MinAnswerScore,
    COALESCE(a.MaxScore,0) AS MaxAnswerScore,
    COALESCE(a.AvgScore,0)::numeric(10,2) AS AvgAnswerScore,
    a.MedianScore
  FROM question_base q
  LEFT JOIN LATERAL (
    SELECT
      COUNT(*) AS AnswerCount,
      MIN(p.Score) AS MinScore,
      MAX(p.Score) AS MaxScore,
      AVG(p.Score) AS AvgScore,
      -- approximate median via percentile_cont for answers
      (percentile_cont(0.5) WITHIN GROUP (ORDER BY p.Score))::int AS MedianScore
    FROM Posts p
    WHERE p.ParentId = q.Id AND p.PostTypeId = 2
  ) a ON true
),

-- combine hot questions with answer stats and top tag names (string aggregation)
question_enriched AS (
  SELECT
    qh.Id,
    qh.Title,
    qh.OwnerUserId,
    qh.OwnerName,
    qh.CreationDate,
    qh.Score,
    qh.ViewCount,
    qh.AnswerCount AS DeclaredAnswerCount,
    COALESCE(qs.AnswerCount,0) AS ActualAnswerCount,
    qs.MinAnswerScore,
    qs.MaxAnswerScore,
    qs.AvgAnswerScore,
    qs.MedianScore,
    qh.UpVotes,
    qh.DownVotes,
    qh.Favorites,
    qh.TagTrending,
    qh.HotScore,
    qh.HotRank,
    -- top 3 tags concatenated
    (SELECT string_agg(distinct ts.Tag, ',' ORDER BY COUNT(*) DESC)
     FROM tag_split ts
     WHERE ts.PostId = qh.Id
     GROUP BY ts.PostId
     LIMIT 1
    ) AS Tags,
    -- flag duplicates (posts that have a PostLinks row with LinkType=3 pointing to this question)
    EXISTS(
      SELECT 1 FROM PostLinks pl
      JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
      WHERE pl.RelatedPostId = qh.Id AND lt.Name ILIKE '%duplicate%'
    ) AS HasDuplicates,
    -- time since creation in days, safe divide
    EXTRACT(epoch FROM (now() - qh.CreationDate))/86400.0 AS DaysSinceCreation
  FROM question_hotness qh
  LEFT JOIN answer_stats qs ON qs.QuestionId = qh.Id
),

-- select top N hot questions and enrich with a correlated subquery that finds top answerers for the question
top_hot_with_contributors AS (
  SELECT
    qe.*,
    -- top 3 answerers for the question by sum(score)
    (SELECT string_agg(u.DisplayName || ':' || s.TotalScore::text, '|')
     FROM (
       SELECT p.OwnerUserId, SUM(p.Score) AS TotalScore
       FROM Posts p
       WHERE p.ParentId = qe.Id AND p.PostTypeId = 2 AND p.OwnerUserId IS NOT NULL
       GROUP BY p.OwnerUserId
       ORDER BY TotalScore DESC
       LIMIT 3
     ) s
     LEFT JOIN Users u ON u.Id = s.OwnerUserId
    ) AS TopAnswerers,
    -- whether the accepted answer is by the OP (self-accepted)
    CASE WHEN qe.AcceptedAnswerId IS NOT NULL
      AND EXISTS(
        SELECT 1 FROM Posts a WHERE a.Id = qe.AcceptedAnswerId AND a.OwnerUserId = qe.OwnerUserId
      ) THEN true ELSE false END AS AcceptedByOP
  FROM question_enriched qe
  WHERE qe.HotRank <= 250 -- limit to 250 hot questions for benchmarking focus
)

-- final union section: top questions plus synthetic rows summarizing tag popularity and a null-ish row to exercise null logic
SELECT
  'Q' AS RowType,
  thwc.Id::text AS EntityId,
  thwc.Title,
  thwc.OwnerName,
  thwc.CreationDate,
  thwc.Score,
  thwc.ViewCount,
  thwc.DeclaredAnswerCount,
  thwc.ActualAnswerCount,
  thwc.MinAnswerScore,
  thwc.MaxAnswerScore,
  thwc.AvgAnswerScore,
  thwc.MedianScore,
  thwc.UpVotes,
  thwc.DownVotes,
  thwc.Favorites,
  thwc.TagTrending,
  ROUND(thwc.HotScore::numeric,2) AS HotScore,
  thwc.HotRank,
  COALESCE(thwc.Tags, '<<no-tags>>') AS Tags,
  COALESCE(thwc.TopAnswerers,'<<none>>') AS TopAnswerers,
  thwc.HasDuplicates,
  thwc.AcceptedByOP,
  NULL::text AS SummaryTag,
  NULL::int AS TagQuestionCount,
  NULL::numeric AS TagAvgViews,
  NULL::timestamp AS SyntheticDate,
  -- complex expression to stress string and null logic
  (CASE WHEN thwc.Favorites > 0 THEN 'fav:'||thwc.Favorites::text
        WHEN thwc.UpVotes - thwc.DownVotes > 10 THEN 'hotly-upvoted'
        WHEN thwc.ViewCount IS NULL OR thwc.ViewCount = 0 THEN 'no-views'
        ELSE concat('vs:', COALESCE(NULLIF((thwc.UpVotes - thwc.DownVotes)::text,''),'0'))
   END) AS StatusNote
FROM top_hot_with_contributors thwc

UNION ALL

-- tag summaries (top 50 tags)
SELECT
  'T' AS RowType,
  NULL::text AS EntityId,
  NULL::text AS Title,
  NULL::text AS OwnerName,
  NULL::timestamp AS CreationDate,
  NULL::int AS Score,
  NULL::int AS ViewCount,
  NULL::int AS DeclaredAnswerCount,
  NULL::int AS ActualAnswerCount,
  NULL::int AS MinAnswerScore,
  NULL::int AS MaxAnswerScore,
  NULL::numeric AS AvgAnswerScore,
  NULL::int AS MedianScore,
  NULL::int AS UpVotes,
  NULL::int AS DownVotes,
  NULL::int AS Favorites,
  NULL::numeric AS TagTrending,
  NULL::numeric AS HotScore,
  NULL::int AS HotRank,
  tp.Tag AS Tags,
  NULL::text AS TopAnswerers,
  NULL::boolean AS HasDuplicates,
  NULL::boolean AS AcceptedByOP,
  tp.Tag AS SummaryTag,
  tp.QuestionCount AS TagQuestionCount,
  ROUND(tp.AvgViews::numeric,2) AS TagAvgViews,
  now() - (tp.QuestionCount || ' days')::interval AS SyntheticDate,
  -- status note for tags
  CASE WHEN tp.TrendingWeight > 10 THEN 'trending' WHEN tp.QuestionCount > 1000 THEN 'popular' ELSE 'niche' END AS StatusNote
FROM tag_pop tp
ORDER BY RowType DESC, HotRank NULLS LAST, TagQuestionCount DESC
LIMIT 350;