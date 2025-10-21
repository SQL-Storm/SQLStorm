-- {"query": "37093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2168} 
WITH
-- Popular active questions with tag arrays and computed metrics
QuestionBase AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    COALESCE(p.Tags, '') AS RawTags,
    -- split tags string like '<sql><performance>' into array of tag names
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
         ELSE regexp_split_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')
    END AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '5 years'
    AND p.ViewCount IS NOT NULL
),
-- top N tags by total views across recent questions
TagAggregates AS (
  SELECT
    unnest(TagArray) AS Tag,
    SUM(ViewCount) AS TotalViews,
    COUNT(*) AS QuestionCount,
    AVG(Score) AS AvgScore
  FROM QuestionBase
  GROUP BY unnest(TagArray)
  ORDER BY TotalViews DESC
  LIMIT 50
),
-- questions that belong to top tags, with join to users and aggregates
QWithUsers AS (
  SELECT
    q.*,
    u.Reputation AS OwnerRep,
    u.CreationDate AS OwnerCreation,
    u.Views AS OwnerProfileViews,
    array_to_string(ta.TagsTop, ',') AS MatchingTopTags
  FROM (
    SELECT qb.*,
           (SELECT array_agg(t Tag ORDER BY t) FROM (
              SELECT t
              FROM unnest(qb.TagArray) t
              WHERE t IN (SELECT Tag FROM TagAggregates)
           ) AS sub(t)
           ) AS TagsTop
    FROM QuestionBase qb
  ) q
  LEFT JOIN Users u ON q.OwnerUserId = u.Id
  WHERE TagsTop IS NOT NULL
),
-- gather answer stats: median and top answer scores, answerer reputation, and whether accepted
AnswerStats AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(*) FILTER (WHERE a.Score IS NOT NULL) AS AnswersCount,
    MAX(a.Score) AS MaxAnswerScore,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.Score) AS MedianAnswerScore,
    SUM(CASE WHEN a.Id = p.AcceptedAnswerId THEN 1 ELSE 0 END) AS HasAccepted,
    -- highest reputation among answer owners
    MAX(u.Reputation) AS MaxAnswererRep,
    MIN(a.CreationDate) AS FirstAnswerDate,
    MAX(a.CreationDate) AS LastAnswerDate
  FROM Posts a
  LEFT JOIN Posts p ON a.ParentId = p.Id
  LEFT JOIN Users u ON a.OwnerUserId = u.Id
  WHERE a.PostTypeId = 2
    AND a.ParentId IS NOT NULL
    AND a.CreationDate >= now() - interval '5 years'
  GROUP BY a.ParentId
),
-- recent activity from comments and edits aggregated per question
ActivityWindow AS (
  SELECT
    ph.PostId AS QuestionId,
    MAX(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,24)) AS LastEdit,
    COUNT(*) FILTER (WHERE ph.CreationDate >= now() - interval '90 days') AS RecentRevisions,
    COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (10,11,12,13)) AS CloseReopenEvents
  FROM PostHistory ph
  GROUP BY ph.PostId
),
-- link graph metrics: inbound backlinks, duplicates, outbound links
LinkMetrics AS (
  SELECT
    p.Id AS QuestionId,
    COUNT(pl.Id) FILTER (WHERE pl.RelatedPostId = p.Id) AS InboundLinks,
    COUNT(pl.Id) FILTER (WHERE pl.PostId = p.Id) AS OutboundLinks,
    COUNT(pl.Id) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicateLinks
  FROM Posts p
  LEFT JOIN PostLinks pl ON pl.PostId = p.Id OR pl.RelatedPostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
-- badge pressure: counts of gold/silver/bronze recently awarded to owners
OwnerBadgeCounts AS (
  SELECT
    b.UserId AS OwnerUserId,
    COUNT(*) FILTER (WHERE b.Class = 1 AND b.Date >= now() - interval '365 days') AS GoldLastYear,
    COUNT(*) FILTER (WHERE b.Class = 2 AND b.Date >= now() - interval '365 days') AS SilverLastYear,
    COUNT(*) FILTER (WHERE b.Class = 3 AND b.Date >= now() - interval '365 days') AS BronzeLastYear
  FROM Badges b
  GROUP BY b.UserId
),
-- combined enriched view
EnrichedQuestions AS (
  SELECT
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.OwnerUserId,
    q.OwnerRep,
    q.ViewCount,
    q.Score,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.TagArray,
    q.MatchingTopTags,
    COALESCE(asn.AnswersCount,0) AS AnswersObserved,
    asn.MaxAnswerScore,
    asn.MedianAnswerScore,
    COALESCE(asn.HasAccepted,0) AS HasAcceptedAnswer,
    COALESCE(asn.MaxAnswererRep,0) AS TopAnswererRep,
    COALESCE(aw.LastEdit, q.CreationDate) AS LastEdit,
    COALESCE(aw.RecentRevisions,0) AS RecentRevisions,
    COALESCE(lm.InboundLinks,0) AS InboundLinks,
    COALESCE(lm.OutboundLinks,0) AS OutboundLinks,
    COALESCE(lm.DuplicateLinks,0) AS DuplicateLinks,
    COALESCE(ob.GoldLastYear,0) AS OwnerGoldLastYear,
    COALESCE(ob.SilverLastYear,0) AS OwnerSilverLastYear,
    COALESCE(ob.BronzeLastYear,0) AS OwnerBronzeLastYear,
    -- composite score to rank for benchmarking complexity
    (
      -- normalize roughly by log metrics to avoid extremes
      COALESCE(q.ViewCount,0)::double precision * 0.4
      + GREATEST(COALESCE(q.Score,0),0) * 10
      + GREATEST(COALESCE(asn.MaxAnswerScore,0),0) * 20
      + COALESCE(asn.AnswersCount,0) * 15
      + COALESCE(aw.RecentRevisions,0) * 25
      + (COALESCE(lm.InboundLinks,0) - COALESCE(lm.OutboundLinks,0)) * 5
      + (COALESCE(ob.GoldLastYear,0) * 50)
      - (EXTRACT(epoch FROM (now() - q.CreationDate))/86400.0) * 0.02
    ) AS CompositeScore
  FROM QWithUsers q
  LEFT JOIN AnswerStats asn ON asn.QuestionId = q.QuestionId
  LEFT JOIN ActivityWindow aw ON aw.QuestionId = q.QuestionId
  LEFT JOIN LinkMetrics lm ON lm.QuestionId = q.QuestionId
  LEFT JOIN OwnerBadgeCounts ob ON ob.OwnerUserId = q.OwnerUserId
),
-- pick top 200 by composite score and build heavy analytic result set
TopCandidates AS (
  SELECT *
  FROM EnrichedQuestions
  ORDER BY CompositeScore DESC NULLS LAST
  LIMIT 200
)
-- final selection: heavy aggregations, windowed computations and lateral expansions
SELECT
  t.QuestionId,
  t.Title,
  t.CreationDate,
  t.OwnerUserId,
  t.OwnerRep,
  t.ViewCount,
  t.Score,
  t.AnswersObserved,
  t.MaxAnswerScore,
  t.MedianAnswerScore,
  t.HasAcceptedAnswer,
  t.TopAnswererRep,
  t.LastEdit,
  t.RecentRevisions,
  t.InboundLinks,
  t.OutboundLinks,
  t.DuplicateLinks,
  t.OwnerGoldLastYear,
  t.OwnerSilverLastYear,
  t.OwnerBronzeLastYear,
  t.CompositeScore,
  -- windowed ranks within matching top tag groups
  rank() OVER (PARTITION BY unnest(t.TagArray) ORDER BY t.CompositeScore DESC) AS RankPerTag,
  dense_rank() OVER (ORDER BY t.CompositeScore DESC) AS GlobalDenseRank,
  row_number() OVER (ORDER BY t.CompositeScore DESC) AS GlobalRowNum,
  -- compute rolling averages of views and scores over the top candidate set
  avg(t.ViewCount) OVER (ORDER BY t.CompositeScore DESC ROWS BETWEEN 9 PRECEDING AND CURRENT ROW) AS RollingAvgViewsTop10,
  avg(t.Score) OVER (ORDER BY t.CompositeScore DESC ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) AS RollingAvgScoreTop50,
  -- correlate owner reputation with top answerer reputation
  CASE WHEN t.OwnerRep > 0 THEN round((t.TopAnswererRep::numeric / GREATEST(t.OwnerRep,1::int))::numeric, 3) ELSE NULL END AS AnswererToOwnerRepRatio,
  -- tag popularity snapshot via lateral join (top 3 co-occurring top tags with counts)
  tag_cooccurrence.top_cooccurring
FROM TopCandidates t
LEFT JOIN LATERAL (
  SELECT array_agg(tg ORDER BY cnt DESC, tg) AS top_cooccurring
  FROM (
    SELECT tg AS tg, COUNT(*) AS cnt
    FROM (
      SELECT unnest(tc.TagArray) AS tg
      FROM TopCandidates tc
    ) s
    WHERE tg <> ALL (t.TagArray) AND tg IS NOT NULL
    GROUP BY tg
    ORDER BY cnt DESC
    LIMIT 3
  ) x
) tag_cooccurrence ON true
ORDER BY t.CompositeScore DESC, t.QuestionId
;