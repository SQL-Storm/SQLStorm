-- {"query": "16033.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "claude-4.5-sonnet", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2335, "output_tokens": 1933}

WITH RECURSIVE user_activity_metrics AS (
  SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    COALESCE(u.UpVotes, 0) - COALESCE(u.DownVotes, 0) AS NetVotes,
    EXTRACT(YEAR FROM u.CreationDate) AS JoinYear,
    CASE 
      WHEN u.Reputation >= 10000 THEN 'Elite'
      WHEN u.Reputation >= 1000 THEN 'Advanced'
      WHEN u.Reputation >= 100 THEN 'Intermediate'
      ELSE 'Novice'
    END AS UserTier
  FROM Users u
  WHERE u.CreationDate >= '2015-01-01'
),
post_statistics AS (
  SELECT 
    p.Id AS PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    LENGTH(p.Body) AS BodyLength,
    CASE 
      WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 
      ELSE 0 
    END AS HasAcceptedAnswer,
    ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS UserPostRank,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgUserScore,
    COUNT(*) OVER (PARTITION BY p.OwnerUserId, EXTRACT(YEAR FROM p.CreationDate)) AS PostsPerYear,
    DENSE_RANK() OVER (ORDER BY p.ViewCount DESC NULLS LAST) AS ViewRank
  FROM Posts p
  WHERE p.PostTypeId IN (1, 2)
    AND p.CreationDate >= '2018-01-01'
),
badge_aggregates AS (
  SELECT 
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
    COUNT(DISTINCT b.Name) AS UniqueBadges,
    STRING_AGG(DISTINCT CASE WHEN b.Class = 1 THEN b.Name END, ', ') AS GoldBadgeNames
  FROM Badges b
  GROUP BY b.UserId
  HAVING COUNT(CASE WHEN b.Class = 1 THEN 1 END) > 0
),
tag_expertise AS (
  SELECT 
    p.OwnerUserId,
    t.TagName,
    COUNT(*) AS TagPostCount,
    AVG(p.Score) AS AvgTagScore,
    MAX(p.ViewCount) AS MaxTagViews
  FROM Posts p
  CROSS JOIN LATERAL string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') AS tag_array(tag)
  INNER JOIN Tags t ON t.TagName = tag_array.tag
  WHERE p.PostTypeId = 1
    AND p.Tags IS NOT NULL
  GROUP BY p.OwnerUserId, t.TagName
),
top_tag_per_user AS (
  SELECT DISTINCT ON (OwnerUserId)
    OwnerUserId,
    TagName AS TopTag,
    TagPostCount,
    AvgTagScore
  FROM tag_expertise
  WHERE OwnerUserId IS NOT NULL
  ORDER BY OwnerUserId, TagPostCount DESC, AvgTagScore DESC
)
SELECT 
  uam.DisplayName,
  uam.UserTier,
  uam.Reputation,
  uam.NetVotes,
  COALESCE(ba.GoldBadges, 0) AS GoldCount,
  COALESCE(ba.SilverBadges, 0) AS SilverCount,
  COALESCE(ba.BronzeBadges, 0) AS BronzeCount,
  ba.GoldBadgeNames,
  ttpu.TopTag,
  ttpu.TagPostCount AS TopTagPosts,
  ROUND(ttpu.AvgTagScore::numeric, 2) AS TopTagAvgScore,
  COUNT(DISTINCT ps.PostId) AS TotalPosts,
  ROUND(AVG(ps.Score)::numeric, 2) AS OverallAvgScore,
  MAX(ps.Score) AS MaxPostScore,
  SUM(COALESCE(ps.ViewCount, 0)) AS TotalViews,
  ROUND(AVG(ps.BodyLength)::numeric, 0) AS AvgBodyLength,
  SUM(ps.HasAcceptedAnswer) AS AcceptedAnswers,
  COALESCE((
    SELECT COUNT(*)
    FROM Comments c
    WHERE c.UserId = uam.Id
      AND c.Score >= 5
  ), 0) AS HighScoredComments,
  COALESCE((
    SELECT COUNT(DISTINCT v.PostId)
    FROM Votes v
    INNER JOIN Posts p ON v.PostId = p.Id
    WHERE v.UserId = uam.Id
      AND v.VoteTypeId = 5
      AND p.PostTypeId = 1
  ), 0) AS FavoritedQuestions,
  CASE 
    WHEN EXISTS (
      SELECT 1 
      FROM PostHistory ph 
      WHERE ph.UserId = uam.Id 
        AND ph.PostHistoryTypeId IN (4, 5, 6)
    ) THEN 'Active Editor'
    ELSE 'Non-Editor'
  END AS EditorStatus,
  EXTRACT(DAYS FROM (NOW() - uam.CreationDate)) AS DaysSinceJoined,
  ROUND(
    (COUNT(DISTINCT ps.PostId)::numeric / NULLIF(EXTRACT(DAYS FROM (NOW() - uam.CreationDate)), 0)) * 365, 
    2
  ) AS PostsPerYear
FROM user_activity_metrics uam
LEFT OUTER JOIN post_statistics ps ON ps.OwnerUserId = uam.Id AND ps.UserPostRank <= 100
LEFT OUTER JOIN badge_aggregates ba ON ba.UserId = uam.Id
LEFT OUTER JOIN top_tag_per_user ttpu ON ttpu.OwnerUserId = uam.Id
WHERE uam.Reputation > 500
  AND (ba.GoldBadges > 0 OR COUNT(DISTINCT ps.PostId) >= 10)
GROUP BY 
  uam.Id, uam.DisplayName, uam.UserTier, uam.Reputation, uam.NetVotes, 
  uam.CreationDate, ba.GoldBadges, ba.SilverBadges, ba.BronzeBadges, 
  ba.GoldBadgeNames, ttpu.TopTag, ttpu.TagPostCount, ttpu.AvgTagScore
HAVING COUNT(DISTINCT ps.PostId) >= 5
  AND AVG(ps.Score) > 1
ORDER BY 
  COALESCE(ba.GoldBadges, 0) * 3 + COALESCE(ba.SilverBadges, 0) * 2 + COALESCE(ba.BronzeBadges, 0) DESC,
  uam.Reputation DESC,
  COUNT(DISTINCT ps.PostId) DESC
LIMIT 500;
