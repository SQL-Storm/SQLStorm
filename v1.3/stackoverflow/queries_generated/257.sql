-- {"query": "257.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "medium", "input_tokens": 2026, "output_tokens": 5305} 
WITH
user_posts AS (
  SELECT u.Id AS UserId,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
         AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
         AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
         SUM(COALESCE(p.ViewCount,0)) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionViews,
         MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
user_badges AS (
  SELECT b.UserId,
         COUNT(*) AS BadgeCount,
         MAX(b.Date) AS LastBadgeDate,
         STRING_AGG(b.Name || '(' || b.Class || ')', ', ' ORDER BY b.Date DESC) AS BadgesList,
         (SELECT b2.Name FROM Badges b2 WHERE b2.UserId = b.UserId ORDER BY b2.Class, b2.Date DESC LIMIT 1) AS TopBadge
  FROM Badges b
  GROUP BY b.UserId
),
tag_questions AS (
  SELECT t.tag AS TagName,
         COUNT(*) AS QCount,
         AVG(p.Score) AS AvgScore,
         AVG(p.ViewCount) AS AvgViews,
         COUNT(DISTINCT p.OwnerUserId) AS UniqueAskers,
         SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS WithAcceptedAnswer
  FROM Posts p
  CROSS JOIN LATERAL (
    SELECT UNNEST(string_to_array(substring(p.Tags,2, length(p.Tags)-2), '><')) AS tag
  ) t
  WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
  GROUP BY t.tag
),
user_top_tag AS (
  SELECT up.UserId, up.tag, up.cnt,
         ROW_NUMBER() OVER (PARTITION BY up.UserId ORDER BY up.cnt DESC, up.tag) AS rn
  FROM (
    SELECT p.OwnerUserId AS UserId,
           UNNEST(string_to_array(substring(p.Tags,2, length(p.Tags)-2), '><')) AS tag,
           COUNT(*) AS cnt
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, tag
  ) up
),
post_votes AS (
  SELECT v.PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS NetVotes,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         COUNT(*) AS TotalVotes
  FROM Votes v
  GROUP BY v.PostId
),
duplicate_rel AS (
  SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkType,
         p1.Score AS PostScore, p2.Score AS RelatedScore,
         ABS(COALESCE(p1.Score,0)-COALESCE(p2.Score,0)) AS ScoreDiff
  FROM PostLinks pl
  LEFT JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
  LEFT JOIN Posts p1 ON p1.Id = pl.PostId
  LEFT JOIN Posts p2 ON p2.Id = pl.RelatedPostId
  WHERE pl.LinkTypeId = 3 OR lt.Name ILIKE '%duplicate%'
),
recent_activity AS (
  SELECT u.Id AS UserId,
         GREATEST(COALESCE(u.LastAccessDate,'epoch'::timestamp), COALESCE(u.CreationDate,'epoch'::timestamp)) AS Anchor,
         COUNT(p.Id) FILTER (WHERE p.CreationDate > now() - INTERVAL '90 days') AS PostsLast90,
         COUNT(c.Id) FILTER (WHERE c.CreationDate > now() - INTERVAL '90 days') AS CommentsLast90,
         ROW_NUMBER() OVER (ORDER BY COUNT(p.Id) FILTER (WHERE p.CreationDate > now() - INTERVAL '365 days') DESC) AS ActivityRankYear
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  LEFT JOIN Comments c ON c.UserId = u.Id
  GROUP BY u.Id
),
hot_posts AS (
  SELECT Id FROM Posts WHERE Score >= 50
  UNION
  SELECT Id FROM Posts WHERE ViewCount >= 100000
),
very_hot_posts AS (
  SELECT Id FROM Posts WHERE Score >= 200
  INTERSECT
  SELECT Id FROM Posts WHERE ViewCount >= 500000
),
niche_users AS (
  SELECT Id FROM Users WHERE Reputation > 10000
  EXCEPT
  SELECT Id FROM Users WHERE UpVotes < 10
)
SELECT
  u.Id,
  COALESCE(u.DisplayName, '<anon>') || ' [' || COALESCE(ub.TopBadge, 'none') || ']' AS Label,
  COALESCE(up.Questions,0) AS Questions,
  COALESCE(up.Answers,0) AS Answers,
  COALESCE(up.AvgQuestionScore,0)::numeric(10,2) AS AvgQuestionScore,
  COALESCE(up.AvgAnswerScore,0)::numeric(10,2) AS AvgAnswerScore,
  COALESCE(ub.BadgeCount,0) AS BadgeCount,
  ut.tag AS TopTag,
  COALESCE(tq.AvgScore,0)::numeric(10,2) AS TopTagAvgScore,
  COALESCE(tq.QCount,0) AS TopTagQCount,
  (SELECT p.Title FROM Posts p WHERE p.OwnerUserId = u.Id AND p.Score = (SELECT MAX(p2.Score) FROM Posts p2 WHERE p2.OwnerUserId = u.Id) LIMIT 1) AS TopPostTitle,
  (SELECT COUNT(*) FROM Posts a WHERE a.PostTypeId = 2 AND a.OwnerUserId = u.Id AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = a.Id)) AS AcceptedAnswersCount,
  (SELECT COUNT(*) FROM hot_posts hp JOIN Posts p ON p.Id = hp.Id WHERE p.OwnerUserId = u.Id) AS HotPostCount,
  (SELECT COUNT(*) FROM very_hot_posts vhp JOIN Posts p ON p.Id = vhp.Id WHERE p.OwnerUserId = u.Id) AS VeryHotCount,
  (SELECT COUNT(*) FROM duplicate_rel dr WHERE dr.PostId IN (SELECT p3.Id FROM Posts p3 WHERE p3.OwnerUserId = u.Id)) AS DuplicatesInvolved,
  COALESCE(up.Questions,0)*1.5 + COALESCE(up.Answers,0)*2.5 + COALESCE(up.AvgAnswerScore,0)*3 + COALESCE(ub.BadgeCount,0)*0.5 AS WeightedScore,
  ra.ActivityRankYear,
  CASE WHEN EXISTS (SELECT 1 FROM niche_users n WHERE n.Id = u.Id) THEN true ELSE false END AS IsEstablished,
  -- a slightly contrived complex expression mixing NULL logic, string ops and arithmetic
  CASE
    WHEN COALESCE(up.Answers,0) = 0 AND COALESCE(up.Questions,0) > 0 THEN 'asker-only'
    WHEN COALESCE(up.Answers,0) > COALESCE(up.Questions,0) THEN 'answerer-dominant'
    WHEN COALESCE(up.Answers,0) = COALESCE(up.Questions,0) AND COALESCE(up.Questions,0) > 0 THEN 'balanced'
    ELSE 'lurker'
  END || '|' || COALESCE(NULLIF(ub.BadgesList,''),'no-badges') AS ProfileSummary
FROM Users u
LEFT JOIN user_posts up ON up.UserId = u.Id
LEFT JOIN user_badges ub ON ub.UserId = u.Id
LEFT JOIN user_top_tag ut ON ut.UserId = u.Id AND ut.rn = 1
LEFT JOIN tag_questions tq ON tq.TagName = ut.tag
LEFT JOIN recent_activity ra ON ra.UserId = u.Id
WHERE COALESCE(up.Questions,0) + COALESCE(up.Answers,0) > 0 OR ub.BadgeCount IS NOT NULL
ORDER BY WeightedScore DESC NULLS LAST, BadgeCount DESC, HotPostCount DESC
LIMIT 100;