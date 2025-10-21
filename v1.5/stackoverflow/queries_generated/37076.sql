-- {"query": "37076.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1985, "output_tokens": 1819} 
WITH
-- recent active questions with tag arrays and computed metrics
Questions AS (
  SELECT
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.OwnerUserId,
    p.Tags,
    -- normalize tags to one row per tag
    regexp_split_to_table(substring(p.Tags,2,length(p.Tags)-2), E'><') AS Tag
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - INTERVAL '2 years'
),
-- pick top N active questions by combined weight
TopQuestions AS (
  SELECT q.*
  FROM Questions q
  ORDER BY (q.Score * 4 + COALESCE(q.ViewCount,0) / GREATEST(NULLIF(q.AnswerCount,0),1) + COALESCE(q.FavoriteCount,0) * 10) DESC
  LIMIT 2000
),
-- aggregate answers and answerer stats for those questions
AnswersAgg AS (
  SELECT
    a.ParentId AS QuestionId,
    COUNT(*) FILTER (WHERE a.Score >= 0) AS PositiveAnswers,
    COUNT(*) FILTER (WHERE a.Score < 0) AS NegativeAnswers,
    AVG(a.Score) AS AvgAnswerScore,
    MAX(a.Score) AS MaxAnswerScore,
    MIN(a.Score) AS MinAnswerScore,
    BOOL_OR(a.AcceptedAnswerId IS NOT NULL) AS HasAcceptedFlagPlaceholder -- always false on answers but kept for symmetry
  FROM Posts a
  WHERE a.PostTypeId = 2
    AND a.ParentId IN (SELECT Id FROM TopQuestions)
  GROUP BY a.ParentId
),
-- compute recent comment activity per question and its answers
CommentsAgg AS (
  SELECT
    c.PostId,
    COUNT(*) AS CommentCountRecent,
    MAX(c.CreationDate) AS LastCommentDate,
    COUNT(*) FILTER (WHERE c.CreationDate >= now()-INTERVAL '30 days') AS Comments30d
  FROM Comments c
  WHERE c.CreationDate >= now() - INTERVAL '1 year'
    AND c.PostId IN (
      SELECT Id FROM TopQuestions
      UNION
      SELECT Id FROM Posts WHERE PostTypeId = 2 AND ParentId IN (SELECT Id FROM TopQuestions)
    )
  GROUP BY c.PostId
),
-- badge counts and seniority of owners
OwnerStats AS (
  SELECT
    u.Id AS OwnerUserId,
    u.Reputation,
    COUNT(b.Id) AS BadgeCount,
    COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
    COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
    EXTRACT(EPOCH FROM (now() - MIN(u.CreationDate)))/86400 AS DaysSinceJoin
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM TopQuestions WHERE OwnerUserId IS NOT NULL)
  GROUP BY u.Id, u.Reputation, u.CreationDate
),
-- identify duplicate and linked posts relationships density
LinkDensity AS (
  SELECT
    tl.PostId AS QuestionId,
    COUNT(*) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
    COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount,
    COUNT(*) AS TotalLinks
  FROM PostLinks tl
  JOIN LinkTypes lt ON lt.Id = tl.LinkTypeId
  WHERE tl.PostId IN (SELECT Id FROM TopQuestions)
  GROUP BY tl.PostId
),
-- collect vote distributions for questions
VoteDist AS (
  SELECT
    v.PostId,
    COUNT(*) FILTER (WHERE vt.Name = 'UpMod') AS UpVotes,
    COUNT(*) FILTER (WHERE vt.Name = 'DownMod') AS DownVotes,
    COUNT(*) FILTER (WHERE vt.Name = 'Favorite') AS Favorites,
    COUNT(*) FILTER (WHERE vt.Name = 'AcceptedByOriginator') AS AcceptedByOwnerFlag,
    COUNT(*) AS TotalVotes
  FROM Votes v
  JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
  WHERE v.PostId IN (SELECT Id FROM TopQuestions)
  GROUP BY v.PostId
),
-- assemble final metrics per question
QuestionMetrics AS (
  SELECT
    tq.Id AS QuestionId,
    tq.Title,
    tq.CreationDate,
    tq.Score AS QuestionScore,
    tq.ViewCount,
    tq.AnswerCount,
    tq.FavoriteCount,
    tq.Tag,
    COALESCE(aa.PositiveAnswers,0) AS PositiveAnswers,
    COALESCE(aa.NegativeAnswers,0) AS NegativeAnswers,
    COALESCE(aa.AvgAnswerScore,0) AS AvgAnswerScore,
    COALESCE(ca.CommentCountRecent,0) AS RecentComments,
    COALESCE(ca.Comments30d,0) AS Comments30d,
    COALESCE(ld.LinkedCount,0) AS LinkedCount,
    COALESCE(ld.DuplicateCount,0) AS DuplicateCount,
    COALESCE(vd.UpVotes,0) AS UpVotes,
    COALESCE(vd.DownVotes,0) AS DownVotes,
    COALESCE(vd.TotalVotes,0) AS TotalVotes,
    ow.Reputation AS OwnerReputation,
    ow.BadgeCount AS OwnerBadgeCount,
    ow.GoldBadges,
    ow.SilverBadges,
    ow.BronzeBadges,
    ow.DaysSinceJoin,
    -- composite hotness score (intended to be expensive to compute)
    ((tq.Score * 5)::double precision
      + GREATEST(LEAST(LOG(NULLIF(tq.ViewCount,0)+1), 50), 0) * 3
      + COALESCE(aa.AvgAnswerScore,0) * 4
      + COALESCE(vd.UpVotes - vd.DownVotes, 0) * 2
      + COALESCE(tq.FavoriteCount,0) * 10
      + COALESCE(ca.Comments30d,0) * 6
      + (ow.Reputation::double precision / GREATEST(1, NULLIF(ow.DaysSinceJoin,0))) * 0.5
      - COALESCE(ld.DuplicateCount,0) * 8
    ) AS HotnessScore
  FROM TopQuestions tq
  LEFT JOIN AnswersAgg aa ON aa.QuestionId = tq.Id
  LEFT JOIN CommentsAgg ca ON ca.PostId = tq.Id
  LEFT JOIN LinkDensity ld ON ld.QuestionId = tq.Id
  LEFT JOIN VoteDist vd ON vd.PostId = tq.Id
  LEFT JOIN OwnerStats ow ON ow.OwnerUserId = tq.OwnerUserId
)
-- final result: top tags and dense stats, plus windowed rank and percentile buckets
SELECT
  qm.QuestionId,
  qm.Title,
  qm.Tag,
  qm.CreationDate,
  qm.QuestionScore,
  qm.ViewCount,
  qm.AnswerCount,
  qm.PositiveAnswers,
  qm.NegativeAnswers,
  qm.AvgAnswerScore,
  qm.RecentComments,
  qm.Comments30d,
  qm.LinkedCount,
  qm.DuplicateCount,
  qm.UpVotes,
  qm.DownVotes,
  qm.TotalVotes,
  qm.OwnerReputation,
  qm.OwnerBadgeCount,
  qm.GoldBadges,
  qm.SilverBadges,
  qm.BronzeBadges,
  ROUND(qm.HotnessScore::numeric,2) AS HotnessScore,
  -- rank within same tag by hotness
  RANK() OVER (PARTITION BY qm.Tag ORDER BY qm.HotnessScore DESC) AS TagHotRank,
  -- percentile across all selected questions
  NTILE(100) OVER (ORDER BY qm.HotnessScore DESC) AS HotnessPercentile,
  -- moving averages of hotness over tag partition (expensive window)
  ROUND(AVG(qm.HotnessScore) OVER (PARTITION BY qm.Tag ORDER BY qm.HotnessScore DESC ROWS BETWEEN 4 PRECEDING AND CURRENT ROW)::numeric,2) AS TagHot_MA_5,
  ROUND(STDDEV_SAMP(qm.HotnessScore) OVER (PARTITION BY qm.Tag)::numeric,2) AS TagHot_STDDEV
FROM QuestionMetrics qm
WHERE qm.HotnessScore IS NOT NULL
ORDER BY qm.HotnessScore DESC
LIMIT 500;