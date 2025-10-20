-- {"query": "37059.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 2614} 
WITH
-- recent active questions with tag arrays and derived metrics
Questions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    p.ViewCount,
    p.Score,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    -- split tags '<tag1><tag2>' -> array of tag names
    CASE WHEN p.Tags IS NULL THEN ARRAY[]::varchar[] 
         ELSE string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') END AS TagArray,
    p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
-- compute user statistics (reputation, tenure, activity)
UserStats AS (
  SELECT
    u.Id AS UserId,
    u.Reputation,
    u.CreationDate,
    EXTRACT(EPOCH FROM (now() - u.CreationDate))/86400 AS DaysSinceSignup,
    u.Views AS ProfileViews,
    u.UpVotes,
    u.DownVotes,
    COALESCE(b.BadgeCounts, h.BadgeCounts) FILTER (WHERE b.BadgeCounts IS NOT NULL OR h.BadgeCounts IS NOT NULL) AS BadgeCounts
  FROM Users u
  LEFT JOIN (
    SELECT UserId, jsonb_build_object('gold', COALESCE(SUM((Class=1)::int),0), 'silver', COALESCE(SUM((Class=2)::int),0), 'bronze', COALESCE(SUM((Class=3)::int),0)) AS BadgeCounts
    FROM Badges
    GROUP BY UserId
  ) b ON b.UserId = u.Id
  LEFT JOIN (
    SELECT Id AS UserId, jsonb_build_object('gold',0,'silver',0,'bronze',0) AS BadgeCounts FROM Users LIMIT 0
  ) h ON h.UserId = u.Id
),
-- posts with aggregated vote breakdown and recent comment activity
PostEngagement AS (
  SELECT
    p.Id AS PostId,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END),0) AS Favorites,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END),0) AS AcceptedCount,
    MAX(v.CreationDate) FILTER (WHERE v.CreationDate IS NOT NULL) AS LastVoteDate,
    COUNT(c.Id) FILTER (WHERE c.CreationDate >= now() - interval '90 days') AS RecentComments90d,
    COUNT(c.Id) AS TotalComments
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  LEFT JOIN Comments c ON c.PostId = p.Id
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
-- link topology: count duplicates, inbound/outbound links, and compute simple PageRank-like score (iterative approximation)
LinkCounts AS (
  SELECT
    p.Id AS PostId,
    COALESCE(SUM(CASE WHEN l.LinkTypeId = 3 AND l.PostId = p.Id THEN 1 ELSE 0 END),0) AS DuplicateOutCount, -- p cites duplicate -> outgoing duplicate
    COALESCE(SUM(CASE WHEN l.LinkTypeId = 3 AND l.RelatedPostId = p.Id THEN 1 ELSE 0 END),0) AS DuplicateInCount,
    COALESCE(SUM(CASE WHEN l.LinkTypeId = 1 AND l.PostId = p.Id THEN 1 ELSE 0 END),0) AS OutboundLinks,
    COALESCE(SUM(CASE WHEN l.LinkTypeId = 1 AND l.RelatedPostId = p.Id THEN 1 ELSE 0 END),0) AS InboundLinks
  FROM Posts p
  LEFT JOIN PostLinks l ON (l.PostId = p.Id OR l.RelatedPostId = p.Id)
  WHERE p.PostTypeId = 1
  GROUP BY p.Id
),
-- derive tag popularity and co-occurrence matrix (top tags only)
TagExplode AS (
  SELECT q.Id AS PostId, unnest(q.TagArray) AS Tag
  FROM Questions q
),
TopTags AS (
  SELECT Tag, COUNT(*) AS TagCount
  FROM TagExplode
  GROUP BY Tag
  ORDER BY TagCount DESC
  LIMIT 100
),
TagCooccur AS (
  SELECT t1.Tag AS TagA, t2.Tag AS TagB, COUNT(*) AS CoCount
  FROM (
    SELECT PostId, array_agg(Tag) AS Tags
    FROM TagExplode
    WHERE Tag IN (SELECT Tag FROM TopTags)
    GROUP BY PostId
  ) te, unnest(Tags) WITH ORDINALITY AS a(Tag, i), unnest(Tags) WITH ORDINALITY AS b(Tag, j)
  JOIN TopTags tt1 ON tt1.Tag = a.Tag
  JOIN TopTags tt2 ON tt2.Tag = b.Tag
  WHERE a.i < b.i
  GROUP BY t1.Tag, t2.Tag
  -- placeholder aliases to be swapped in final select
  , LATERAL (SELECT a.Tag) t1(Tag)
  , LATERAL (SELECT b.Tag) t2(Tag)
),
-- compute a combined score for questions using many signals
QuestionScores AS (
  SELECT
    q.*,
    pe.UpVotes, pe.DownVotes, pe.Favorites, pe.AcceptedCount, pe.RecentComments90d, pe.TotalComments,
    lc.DuplicateInCount, lc.DuplicateOutCount, lc.InboundLinks, lc.OutboundLinks,
    us.Reputation AS OwnerReputation,
    us.DaysSinceSignup,
    -- engagement and quality heuristics
    GREATEST(0.0,
      -- base popularity
      (COALESCE(pe.UpVotes,0) * 2.0)
      + (COALESCE(pe.Favorites,0) * 1.5)
      + (COALESCE(pe.RecentComments90d,0) * 0.8)
      + (LOG(GREATEST(1,q.ViewCount)) * 1.2)
      + (COALESCE(q.AnswerCount,0) * 1.1)
      - (COALESCE(pe.DownVotes,0) * 1.0)
      + (COALESCE(lc.InboundLinks,0) * 0.5)
      - (COALESCE(lc.DuplicateOutCount,0) * 0.7)
      + (LEAST(1.0, GREATEST(0.0, us.Reputation/10000.0)) * 1.0)
    ) AS RawScore
  FROM Questions q
  LEFT JOIN PostEngagement pe ON pe.PostId = q.Id
  LEFT JOIN LinkCounts lc ON lc.PostId = q.Id
  LEFT JOIN UserStats us ON us.UserId = q.OwnerUserId
),
-- rank and window aggregates for diverse sampling
RankedQuestions AS (
  SELECT
    qs.*,
    ROW_NUMBER() OVER (ORDER BY qs.RawScore DESC NULLS LAST) AS RankByScore,
    RANK() OVER (PARTITION BY (qs.AnswerCount > 0)::int ORDER BY qs.RawScore DESC) AS RankByAnsweredGroup,
    PERCENT_RANK() OVER (ORDER BY qs.RawScore) AS PercentRank,
    NTILE(10) OVER (ORDER BY qs.RawScore DESC) AS Decile
  FROM QuestionScores qs
)
-- final selection: heavy aggregation, cross apply-like subqueries, JSON construction and joins for benchmark complexity
SELECT
  r.RankByScore,
  r.Id AS QuestionId,
  r.Title,
  r.CreationDate,
  r.LastActivityDate,
  r.ViewCount,
  r.Score,
  r.AnswerCount,
  r.FavoriteCount,
  r.TagArray,
  r.RawScore,
  r.Decile,
  r.PercentRank,
  r.OwnerUserId,
  us.Reputation AS OwnerReputation,
  COALESCE(bc.BadgeCounts, jsonb_build_object('gold',0,'silver',0,'bronze',0)) AS OwnerBadges,
  pe.UpVotes, pe.DownVotes, pe.Favorites AS VoteFavorites,
  pe.RecentComments90d,
  lc.InboundLinks, lc.OutboundLinks, lc.DuplicateInCount, lc.DuplicateOutCount,
  -- fetch top 3 answers by score for each question as JSON
  (SELECT jsonb_agg(jsonb_build_object('AnswerId', a.Id, 'Score', a.Score, 'CreationDate', a.CreationDate, 'OwnerId', a.OwnerUserId) ORDER BY a.Score DESC NULLS LAST)
   FROM Posts a
   WHERE a.ParentId = r.Id AND a.PostTypeId = 2
   LIMIT 3
  ) AS TopAnswers,
  -- recent activity timeline: counts per month for last 12 months
  (SELECT jsonb_agg(jsonb_build_object(month_label, cnt) ORDER BY month_label)
   FROM (
     SELECT to_char(dt, 'YYYY-MM') AS month_label, COUNT(*) AS cnt
     FROM generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') dt
     LEFT JOIN Posts p2 ON p2.PostTypeId = 1 AND date_trunc('month', COALESCE(p2.LastActivityDate, p2.CreationDate)) = dt AND p2.Id = r.Id
     GROUP BY dt
     ORDER BY dt
   ) t
  ) AS ActivityByMonth,
  -- tag neighbors: top 5 co-occurring top tags with aggregated co-count
  (SELECT jsonb_agg(jsonb_build_object('Tag', tc.TagB, 'CoCount', tc.CoCount) ORDER BY tc.CoCount DESC) FROM TagCooccur tc WHERE tc.TagA = ANY(r.TagArray) LIMIT 5) AS TopTagNeighbors,
  -- estimated hotness (decay model: upvotes in last 7 days weighted higher)
  (
    SELECT
      SUM(
        CASE
          WHEN v.CreationDate >= now() - interval '7 days' THEN 3.0
          WHEN v.CreationDate >= now() - interval '30 days' THEN 1.5
          ELSE 0.5
        END * CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END
      )
    FROM Votes v
    WHERE v.PostId = r.Id
  ) AS RecentHotnessScore,
  -- windowed aggregate: median RawScore within same decile (approx via percentile_cont)
  percentile_cont(0.5) WITHIN GROUP (ORDER BY qs.RawScore) OVER (PARTITION BY r.Decile) AS MedianRawScoreInDecile,
  -- correlate owner reputation percentile among owners of questions
  (SELECT PERCENT_RANK() OVER (ORDER BY Reputation) FROM Users u2 WHERE u2.Id = r.OwnerUserId) AS OwnerReputationPercentile
FROM RankedQuestions r
LEFT JOIN PostEngagement pe ON pe.PostId = r.Id
LEFT JOIN LinkCounts lc ON lc.PostId = r.Id
LEFT JOIN Users us ON us.Id = r.OwnerUserId
LEFT JOIN (
  SELECT UserId, jsonb_build_object('gold', COALESCE(SUM((Class=1)::int),0), 'silver', COALESCE(SUM((Class=2)::int),0), 'bronze', COALESCE(SUM((Class=3)::int),0)) AS BadgeCounts
  FROM Badges
  GROUP BY UserId
) bc ON bc.UserId = us.Id
LEFT JOIN QuestionScores qs ON qs.Id = r.Id
WHERE r.RankByScore <= 1000
ORDER BY r.RawScore DESC, r.LastActivityDate DESC
LIMIT 1000;