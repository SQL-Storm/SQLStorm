-- {"query": "7051.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2595} 
WITH
-- recent high-activity questions with normalized tag array
Q AS (
  SELECT
    p.Id AS QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    COALESCE(p.ViewCount,0) AS Views,
    COALESCE(p.AnswerCount,0) AS AnswerCount,
    COALESCE(p.FavoriteCount,0) AS Favorites,
    p.OwnerUserId,
    -- split tags from form '<tag1><tag2>' into array elements; handles NULL/empty
    CASE WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
         ELSE string_to_array(substring(p.Tags, 2, char_length(p.Tags)-2), '><')
    END AS TagArray
  FROM Posts p
  WHERE p.PostTypeId = 1
    AND p.CreationDate >= now() - interval '2 years'
),
-- aggregate user stats and recent activity window
U AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreated,
    COALESCE(u.Views,0) AS ProfileViews,
    COALESCE(u.UpVotes,0) AS UpVotes,
    COALESCE(u.DownVotes,0) AS DownVotes,
    -- last 3 posts scores avg (correlated subquery)
    (SELECT AVG(coalesce(p.Score,0)) FROM Posts p WHERE p.OwnerUserId = u.Id ORDER BY p.CreationDate DESC LIMIT 3) AS AvgScoreLast3,
    -- badge breakdown pivot-ish
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) FILTER (WHERE b.Id IS NOT NULL) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) FILTER (WHERE b.Id IS NOT NULL) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) FILTER (WHERE b.Id IS NOT NULL) AS BronzeBadges
  FROM Users u
  LEFT JOIN Badges b ON b.UserId = u.Id
  GROUP BY u.Id
),
-- answers with windowed rank and time-to-answer calculation using parent question creation time
A AS (
  SELECT
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    a.OwnerUserId AS AnswererId,
    a.CreationDate AS AnswerDate,
    a.Score AS AnswerScore,
    a.CommentCount AS AnswerComments,
    row_number() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerRankByScore,
    -- time to answer in seconds (nullable)
    EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) AS SecondsToAnswer
  FROM Posts a
  LEFT JOIN Posts q ON q.Id = a.ParentId
  WHERE a.PostTypeId = 2
),
-- compute link/social graph metrics: outgoing links from question -> related posts, duplicate counts
L AS (
  SELECT
    pl.PostId,
    COUNT(*) FILTER (WHERE lt.Name = 'Linked') AS NumLinked,
    COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS NumDuplicates,
    MAX(pl.CreationDate) AS LastLinkDate
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  GROUP BY pl.PostId
),
-- top tags by total views and avg score across recent questions
TagStats AS (
  SELECT
    t.TagName,
    t.Id AS TagId,
    SUM(q.Views) AS TotalViews,
    AVG(q.Score) AS AvgScore,
    COUNT(*) AS QuestionCount,
    MAX(q.CreationDate) AS MostRecentQuestion
  FROM Tags t
  JOIN Posts p ON p.Tags IS NOT NULL AND position('<' || t.TagName || '>' IN p.Tags) > 0 AND p.PostTypeId = 1
  JOIN Q q ON q.QuestionId = p.Id
  GROUP BY t.TagName, t.Id
  HAVING COUNT(*) > 5
),
-- compute per-question aggregated vote breakdown with correlated subquery and NULL logic
V AS (
  SELECT
    q.QuestionId,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END),0) AS UpVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END),0) AS DownVotes,
    COALESCE(SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END),0) AS Favorites,
    COALESCE(SUM(CASE WHEN v.VoteTypeId IN (8,9) THEN COALESCE(v.BountyAmount,0) ELSE 0 END),0) AS TotalBounty
  FROM Q q
  LEFT JOIN Votes v ON v.PostId = q.QuestionId
  GROUP BY q.QuestionId
),
-- compute complex scoring expression combining many signals
Scored AS (
  SELECT
    q.*,
    COALESCE(v.UpVotes,0) AS VUp,
    COALESCE(v.DownVotes,0) AS VDown,
    COALESCE(l.NumLinked,0) AS NumLinked,
    COALESCE(l.NumDuplicates,0) AS NumDuplicates,
    COALESCE(u.Reputation, 0) AS OwnerReputation,
    COALESCE(u.AvgScoreLast3, 0) AS OwnerAvgScore3,
    -- tag diversity and popular tag boost (exists correlated)
    (SELECT COUNT(DISTINCT tg) FROM unnest(q.TagArray) AS tg) AS TagCount,
    (SELECT SUM(ts.TotalViews) FROM TagStats ts WHERE ts.TagName = ANY(q.TagArray)) AS SumTagViews,
    -- composite score: weighted and nonlinear, using NULL-safe math and LEAST/GREATEST
    (
      -- base: question score and views
      GREATEST(1, LOG(GREATEST(1,q.Views)) * 1.2 + q.Score * 3)
      -- owner quality multiplier
      * (1 + LEAST(2, COALESCE(u.Reputation,0) / NULLIF(GREATEST(100, u.Reputation),0) * 0.01))
      -- answers and favorites
      + (q.AnswerCount * 5)
      + (COALESCE(v.Favorites,0) * 4)
      -- tag popularity boost (dampen)
      + COALESCE(LOG(GREATEST(1, (SELECT COALESCE(SUM(ts.TotalViews),0) FROM TagStats ts WHERE ts.TagName = ANY(q.TagArray))), 10), 0) * 2
      -- penalty for duplicates or too many linked posts (possible noise)
      - GREATEST(0, COALESCE(l.NumDuplicates,0) * 10)
    ) AS CompositeScore
  FROM Q q
  LEFT JOIN V v ON v.QuestionId = q.QuestionId
  LEFT JOIN L l ON l.PostId = q.QuestionId
  LEFT JOIN Users u ON u.Id = q.OwnerUserId
),
-- select top N per tag using window functions and lateral correlated subquery for sample comments
TopPerTag AS (
  SELECT
    ts.TagName,
    s.QuestionId,
    s.Title,
    s.CreationDate,
    s.Views,
    s.Score,
    s.AnswerCount,
    s.CompositeScore,
    s.TagCount,
    s.SumTagViews,
    u.DisplayName AS OwnerName,
    -- pick the top answer by score for this question (left join may be null)
    a_top.AnswerId,
    a_top.AnswerScore,
    a_top.SecondsToAnswer,
    -- sample a latest comment text (complex string manipulation to demonstrate expressions)
    COALESCE(
      (SELECT substr(c.Text,1,200) FROM Comments c WHERE c.PostId = s.QuestionId ORDER BY c.CreationDate DESC LIMIT 1),
      '<<no comments>>'
    ) AS LatestCommentSnippet,
    row_number() OVER (PARTITION BY ts.TagName ORDER BY s.CompositeScore DESC, s.CreationDate DESC) AS RankInTag
  FROM TagStats ts
  JOIN Scored s ON s.TagArray && ARRAY[ts.TagName]::text[]
  LEFT JOIN Users u ON u.Id = s.OwnerUserId
  LEFT JOIN LATERAL (
    SELECT a.AnswerId, a.AnswerScore, a.SecondsToAnswer
    FROM A a
    WHERE a.QuestionId = s.QuestionId
    ORDER BY a.AnswerScore DESC NULLS LAST, a.AnswerDate ASC
    LIMIT 1
  ) a_top ON TRUE
)
-- final selection: pick top 3 per tag, union with global top questions, and include some set ops and ordering complexity
SELECT
  t.TagName,
  t.RankInTag,
  t.QuestionId,
  t.Title,
  t.CreationDate,
  t.Views,
  t.Score,
  t.AnswerCount,
  t.CompositeScore,
  t.TagCount,
  t.SumTagViews,
  t.OwnerName,
  t.AnswerId,
  t.AnswerScore,
  t.SecondsToAnswer,
  t.LatestCommentSnippet
FROM TopPerTag t
WHERE t.RankInTag <= 3

UNION

-- include a few extreme edge cases: highest bounty questions and recently closed duplicates (set operator)
SELECT
  '(GlobalHighBounty)'::text AS TagName,
  0 AS RankInTag,
  q2.QuestionId,
  q2.Title,
  q2.CreationDate,
  q2.Views,
  q2.Score,
  q2.AnswerCount,
  q2.CompositeScore,
  q2.TagCount,
  q2.SumTagViews,
  u2.DisplayName AS OwnerName,
  at.AnswerId,
  at.AnswerScore,
  at.SecondsToAnswer,
  COALESCE((SELECT substr(c.Text,1,120) FROM Comments c WHERE c.PostId = q2.QuestionId ORDER BY c.CreationDate DESC LIMIT 1), '<<no comments>>') AS LatestCommentSnippet
FROM Scored q2
LEFT JOIN Users u2 ON u2.Id = q2.OwnerUserId
LEFT JOIN LATERAL (
  SELECT a.AnswerId, a.AnswerScore, a.SecondsToAnswer
  FROM A a
  WHERE a.QuestionId = q2.QuestionId
  ORDER BY a.AnswerScore DESC NULLS LAST, a.AnswerDate ASC
  LIMIT 1
) at ON TRUE
WHERE q2.QuestionId IN (
  SELECT v.PostId FROM Votes v WHERE v.VoteTypeId IN (8,9) AND v.BountyAmount IS NOT NULL
)
ORDER BY CompositeScore DESC
LIMIT 10

UNION

SELECT
  '(RecentDuplicates)'::text AS TagName,
  0 AS RankInTag,
  ph.PostId AS QuestionId,
  p.Title,
  p.CreationDate,
  p.ViewCount,
  p.Score,
  p.AnswerCount,
  0.0 AS CompositeScore,
  0 AS TagCount,
  0 AS SumTagViews,
  u3.DisplayName AS OwnerName,
  NULL::int AS AnswerId,
  NULL::int AS AnswerScore,
  NULL::double precision AS SecondsToAnswer,
  COALESCE(ph.Comment, 'duplicate') AS LatestCommentSnippet
FROM PostHistory ph
JOIN PostHistoryTypes pht ON pht.Id = ph.PostHistoryTypeId
JOIN Posts p ON p.Id = ph.PostId
LEFT JOIN Users u3 ON u3.Id = ph.UserId
WHERE ph.PostHistoryTypeId = 10 -- Post Closed (old schema mapping; or closed)
  AND ph.CreationDate >= now() - interval '30 days'
  AND EXISTS (
    SELECT 1 FROM PostLinks pl WHERE pl.PostId = ph.PostId AND pl.LinkTypeId = (SELECT Id FROM LinkTypes WHERE Name = 'Duplicate' LIMIT 1)
  )
ORDER BY ph.CreationDate DESC
LIMIT 5

ORDER BY TagName NULLS LAST, RankInTag, CompositeScore DESC, Views DESC;