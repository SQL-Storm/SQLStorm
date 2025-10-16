-- {"query": "336.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 17137} 
WITH
dates AS (
  SELECT generate_series(date_trunc('month', current_date) - interval '11 months',
                         date_trunc('month', current_date),
                         interval '1 month')::date AS month_start
),
recent_posts AS (
  SELECT p.*
  FROM Posts p
  WHERE p.CreationDate >= (current_date - interval '365 days')::timestamp
),
post_tags AS (
  SELECT rp.Id AS PostId,
         lower(trim(t.TagName)) AS TagName
  FROM recent_posts rp
  LEFT JOIN LATERAL unnest(coalesce(string_to_array(substring(rp.Tags,2,length(rp.Tags)-2),'><'), '{}'::text[])) AS t(TagName) ON true
),
all_post_tags AS (
  SELECT p.Id AS PostId,
         lower(trim(t.TagName)) AS TagName,
         p.OwnerUserId
  FROM Posts p
  LEFT JOIN LATERAL unnest(coalesce(string_to_array(substring(p.Tags,2,length(p.Tags)-2),'><'), '{}'::text[])) AS t(TagName) ON true
),
user_posts AS (
  SELECT u.Id AS UserId,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS Questions,
         COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS Answers,
         SUM(COALESCE(p.Score,0)) AS TotalScore,
         AVG(COALESCE(p.Score,0)) AS AvgPostScore,
         SUM(COALESCE(p.ViewCount,0)) AS TotalViews,
         MAX(p.CreationDate) AS LastPostDate,
         MIN(p.CreationDate) AS FirstPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY u.Id
),
badge_counts AS (
  SELECT b.UserId,
         SUM(CASE WHEN b.Class=1 THEN 1 ELSE 0 END) AS GoldBadges,
         SUM(CASE WHEN b.Class=2 THEN 1 ELSE 0 END) AS SilverBadges,
         SUM(CASE WHEN b.Class=3 THEN 1 ELSE 0 END) AS BronzeBadges,
         SUM(CASE WHEN b.TagBased THEN 1 ELSE 0 END) AS TagBadges
  FROM Badges b
  GROUP BY b.UserId
),
votes_agg AS (
  SELECT p.Id AS PostId,
         SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
         SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
         SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS Favorites,
         COUNT(v.Id) AS TotalVotes
  FROM Posts p
  LEFT JOIN Votes v ON v.PostId = p.Id
  GROUP BY p.Id
),
top_answers AS (
  SELECT a.*,
         ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank,
         RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST) AS AnswerRankTie
  FROM Posts a
  WHERE a.PostTypeId = 2
),
user_question_posts AS (
  SELECT p.Id as PostId, p.OwnerUserId
  FROM Posts p
  WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
user_tag_peers AS (
  SELECT DISTINCT uq.OwnerUserId AS UserId,
         pt.TagName,
         p2.OwnerUserId AS PeerUserId
  FROM user_question_posts uq
  JOIN all_post_tags pt ON pt.PostId = uq.PostId
  JOIN all_post_tags pt2 ON pt2.TagName = pt.TagName
  JOIN Posts p2 ON p2.Id = pt2.PostId
  WHERE p2.OwnerUserId IS NOT NULL AND p2.OwnerUserId <> uq.OwnerUserId
),
peer_metrics AS (
  SELECT utp.UserId,
         COUNT(DISTINCT utp.PeerUserId) AS DistinctPeerCount,
         AVG(COALESCE(pe.TotalScore,0)) AS AvgPeerTotalScore,
         SUM(COALESCE(pe.TotalScore,0)) AS SumPeerTotalScore
  FROM user_tag_peers utp
  LEFT JOIN (
     SELECT p.OwnerUserId AS OwnerUserId, SUM(COALESCE(p.Score,0)) AS TotalScore
     FROM Posts p
     GROUP BY p.OwnerUserId
  ) pe ON pe.OwnerUserId = utp.PeerUserId
  GROUP BY utp.UserId
),
user_summary AS (
  SELECT u.Id AS UserId,
         u.DisplayName,
         COALESCE(up.Questions,0) AS Questions,
         COALESCE(up.Answers,0) AS Answers,
         COALESCE(up.TotalScore,0) AS TotalScore,
         COALESCE(bc.GoldBadges,0) AS GoldBadges,
         COALESCE(bc.SilverBadges,0) AS SilverBadges,
         COALESCE(bc.BronzeBadges,0) AS BronzeBadges,
         COALESCE(bc.TagBadges,0) AS TagBadges,
         COALESCE(pm.DistinctPeerCount,0) AS PeerCount,
         COALESCE(pm.AvgPeerTotalScore,0) AS AvgPeerScore,
         u.Reputation,
         u.CreationDate,
         u.LastAccessDate
  FROM Users u
  LEFT JOIN user_posts up ON up.UserId = u.Id
  LEFT JOIN badge_counts bc ON bc.UserId = u.Id
  LEFT JOIN peer_metrics pm ON pm.UserId = u.Id
),
top_by_rep AS (
  SELECT Id AS UserId
  FROM Users
  ORDER BY Reputation DESC NULLS LAST
  LIMIT 250
),
top_by_score AS (
  SELECT UserId
  FROM user_posts
  ORDER BY TotalScore DESC NULLS LAST
  LIMIT 250
),
top_union AS (
  SELECT UserId FROM top_by_rep
  UNION
  SELECT UserId FROM top_by_score
),
top_intersect AS (
  SELECT UserId FROM top_by_rep
  INTERSECT
  SELECT UserId FROM top_by_score
),
top_except AS (
  SELECT UserId FROM top_by_rep
  EXCEPT
  SELECT UserId FROM top_by_score
),
total_tags AS (
  SELECT COUNT(DISTINCT TagName) AS TotalTags
  FROM all_post_tags
  WHERE TagName IS NOT NULL
),
user_enriched AS (
  SELECT us.*,
         COALESCE(us.TotalScore::numeric / NULLIF(us.Questions,0),0) AS ScorePerQuestion,
         (EXTRACT(EPOCH FROM (current_timestamp - COALESCE(us.LastAccessDate, us.CreationDate)))/86400) AS DaysSinceLastAccess,
         (
           2 * LN(1 + GREATEST(us.Questions,0)) +
           1.5 * LN(1 + GREATEST(us.Answers,0)) +
           SQRT(GREATEST(us.TotalScore,0) + 1)
         ) * EXP(- (EXTRACT(EPOCH FROM (current_timestamp - COALESCE(us.LastAccessDate, us.CreationDate)))/86400) / 365) + (us.Reputation::numeric / 1000) AS ActivityIndex,
         (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 2 ORDER BY p.Score DESC NULLS LAST, p.CreationDate ASC LIMIT 1) AS TopAnswerId,
         (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.PostTypeId = 1 ORDER BY p.ViewCount DESC NULLS LAST, p.Score DESC NULLS LAST LIMIT 1) AS TopQuestionId,
         (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = us.UserId) AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
         (SELECT AVG(LENGTH(c.Text)) FROM Comments c WHERE c.PostId IN (SELECT p2.Id FROM Posts p2 WHERE p2.OwnerUserId = us.UserId)) AS AvgCommentLength,
         (SELECT COUNT(DISTINCT apt.TagName) FROM all_post_tags apt WHERE apt.OwnerUserId = us.UserId AND apt.TagName IS NOT NULL) AS DistinctTagsUsed,
         (SELECT TagName FROM all_post_tags apt WHERE apt.OwnerUserId = us.UserId AND apt.TagName IS NOT NULL GROUP BY TagName ORDER BY COUNT(*) DESC NULLS LAST LIMIT 1) AS MostUsedTag,
         (SELECT COUNT(DISTINCT pl.PostId) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = us.UserId)) AS PostsWithLinks,
         EXISTS (SELECT 1 FROM top_union tu WHERE tu.UserId = us.UserId) AS InTopUnion,
         EXISTS (SELECT 1 FROM top_intersect ti WHERE ti.UserId = us.UserId) AS InTopIntersect,
         EXISTS (SELECT 1 FROM top_except tx WHERE tx.UserId = us.UserId) AS InTopExcept,
         (SELECT COUNT(*) FROM Posts p WHERE p.OwnerUserId = us.UserId AND p.CreationDate >= current_date - interval '30 days') AS PostsLast30Days,
         (SELECT COUNT(*) FROM Votes v WHERE v.UserId = us.UserId AND v.VoteTypeId = 2 AND v.CreationDate >= current_date - interval '90 days') AS UpVotesCastLast90Days
  FROM user_summary us
)
SELECT
  ue.UserId,
  COALESCE(ue.DisplayName,'<deleted>') AS DisplayName,
  ue.Reputation,
  ue.Questions,
  ue.Answers,
  ue.TotalScore,
  ue.ScorePerQuestion,
  COALESCE(ue.DistinctTagsUsed,0) AS DistinctTagsUsed,
  COALESCE(ue.MostUsedTag,'<none>') AS MostUsedTag,
  ue.TopAnswerId,
  ue.TopQuestionId,
  ue.AvgCommentLength,
  ue.DuplicateLinkCount,
  ue.PeerCount,
  ue.AvgPeerScore,
  ue.GoldBadges,
  ue.SilverBadges,
  ue.BronzeBadges,
  ue.TagBadges,
  ue.PostsLast30Days,
  ue.UpVotesCastLast90Days,
  ue.ActivityIndex,
  ROW_NUMBER() OVER (ORDER BY ue.ActivityIndex DESC NULLS LAST) AS ActivityRank,
  RANK() OVER (ORDER BY ue.Reputation DESC NULLS LAST) AS ReputationRank,
  DENSE_RANK() OVER (ORDER BY ue.TotalScore DESC NULLS LAST) AS ScoreRank,
  CASE WHEN ue.InTopIntersect THEN 'both' WHEN ue.InTopUnion THEN 'either' ELSE 'other' END AS TopSetMembership,
  ((COALESCE(ue.DistinctTagsUsed,0)::numeric / NULLIF(t.TotalTags,0)) * 100)::numeric(5,2) AS TagCoveragePercent,
  concat(
    COALESCE(ue.DisplayName,'<deleted>'),
    ' :: rep=', COALESCE(ue.Reputation::text,'0'),
    ' :: Q=', COALESCE(ue.Questions::text,'0'),
    ' A=', COALESCE(ue.Answers::text,'0')
  ) AS SummaryLabel,
  (ue.PostsWithLinks > 0 OR ue.DuplicateLinkCount > 0) AS HasLinkIssues,
  substring(md5(COALESCE(ue.DisplayName,'') || COALESCE(ue.Reputation::text,'')) for 8) AS IdentityHash
FROM user_enriched ue
CROSS JOIN total_tags t
WHERE ue.Reputation >= 0
ORDER BY ue.ActivityIndex DESC NULLS LAST, ue.TotalScore DESC NULLS LAST
LIMIT 500;