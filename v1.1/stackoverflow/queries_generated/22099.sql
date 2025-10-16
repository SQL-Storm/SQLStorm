-- {"query": "22099.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 970} 
WITH user_post_stats AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    SUM(COALESCE(p.Score, 0)) AS TotalScore,
    AVG(LENGTH(REPLACE(REPLACE(REPLACE(p.Body, '<', ''), '>', ''), '\n', ''))) AS AvgBodyLength,
    MAX(p.ViewCount) AS MaxViewCount
  FROM Users u
  LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_stats AS (
  SELECT 
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
    STRING_AGG(b.Name, ', ') FILTER (WHERE b.Name IS NOT NULL) AS BadgeList
  FROM Badges b
  GROUP BY b.UserId
),
vote_stats AS (
  SELECT 
    v.UserId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) END) AS TotalBountiesOffered
  FROM Votes v
  WHERE v.UserId IS NOT NULL
  GROUP BY v.UserId
),
comment_stats AS (
  SELECT 
    c.UserId,
    COUNT(*) AS CommentCount,
    AVG(CASE WHEN c.Score IS NOT NULL THEN c.Score ELSE 0 END) AS AvgCommentScore
  FROM Comments c
  WHERE c.UserId IS NOT NULL
  GROUP BY c.UserId
)
SELECT 
  ups.UserId,
  ups.DisplayName,
  ups.Reputation,
  COALESCE(ups.QuestionCount, 0) AS QuestionCount,
  COALESCE(ups.AnswerCount, 0) AS AnswerCount,
  COALESCE(ups.TotalScore, 0) AS TotalScore,
  ROUND(COALESCE(ups.AvgBodyLength, 0), 2) AS AvgBodyLength,
  COALESCE(ups.MaxViewCount, 0) AS MaxViewCount,
  COALESCE(bs.GoldBadges, 0) AS GoldBadges,
  COALESCE(bs.SilverBadges, 0) AS SilverBadges,
  COALESCE(bs.BronzeBadges, 0) AS BronzeBadges,
  bs.BadgeList,
  COALESCE(vs.UpVotesReceived, 0) AS UpVotesReceived,
  COALESCE(vs.DownVotesReceived, 0) AS DownVotesReceived,
  COALESCE(vs.TotalBountiesOffered, 0) AS TotalBountiesOffered,
  COALESCE(cs.CommentCount, 0) AS CommentCount,
  ROUND(COALESCE(cs.AvgCommentScore, 0), 2) AS AvgCommentScore,
  -- Complex calculation for engagement score
  (COALESCE(ups.TotalScore, 0) * 1.5 + COALESCE(bs.GoldBadges * 100, 0) + COALESCE(bs.SilverBadges * 50, 0) + COALESCE(bs.BronzeBadges * 10, 0) + COALESCE(vs.UpVotesReceived * 2, 0) - COALESCE(vs.DownVotesReceived * 1, 0) + COALESCE(vs.TotalBountiesOffered / 10, 0)) AS EngagementScore
FROM user_post_stats ups
FULL OUTER JOIN badge_stats bs ON ups.UserId = bs.UserId
FULL OUTER JOIN vote_stats vs ON ups.UserId = vs.UserId
FULL OUTER JOIN comment_stats cs ON ups.UserId = cs.UserId
WHERE (ups.TotalScore IS NOT NULL OR bs.UserId IS NOT NULL OR vs.UserId IS NOT NULL OR cs.UserId IS NOT NULL)
  AND (bs.BadgeList LIKE '%Guru%' OR bs.BadgeList IS NULL)
WINDOW w AS (PARTITION BY CASE WHEN ups.Reputation > 1000 THEN 'High' ELSE 'Low' END ORDER BY EngagementScore DESC)
ORDER BY EngagementScore DESC NULLS LAST
LIMIT 100;