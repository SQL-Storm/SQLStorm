WITH user_post_stats AS (
  SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS QuestionCount,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS AnswerCount,
    SUM(COALESCE(p.Score, 0)) AS TotalScore,
    AVG(LENGTH(REPLACE(REPLACE(REPLACE(COALESCE(p.Body, ''), '<', ''), '>', ''), CHR(10), ''))) AS AvgBodyLength,
    MAX(p.ViewCount) AS MaxViewCount
  FROM Users u
  LEFT JOIN Posts p ON u.Id = p.OwnerUserId
  GROUP BY u.Id, u.DisplayName, u.Reputation
),
badge_stats AS (
  SELECT 
    b.UserId,
    COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
    COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
    COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
    -- Use a generic string aggregation function name for wider compatibility; some DBs use LISTAGG, others use STRING_AGG.
    -- Here we provide a PostgreSQL-compatible STRING_AGG; if unavailable, replace with appropriate DB function.
    STRING_AGG(b.Name, ', ') FILTER (WHERE b.Name IS NOT NULL) AS BadgeList
  FROM Badges b
  GROUP BY b.UserId
),
vote_stats AS (
  SELECT 
    v.UserId,
    COUNT(CASE WHEN v.VoteTypeId = 2 THEN 1 END) AS UpVotesReceived,
    COUNT(CASE WHEN v.VoteTypeId = 3 THEN 1 END) AS DownVotesReceived,
    SUM(CASE WHEN v.VoteTypeId = 8 THEN COALESCE(v.BountyAmount, 0) ELSE 0 END) AS TotalBountiesOffered
  FROM Votes v
  WHERE v.UserId IS NOT NULL
  GROUP BY v.UserId
),
comment_stats AS (
  SELECT 
    c.UserId,
    COUNT(*) AS CommentCount,
    AVG(COALESCE(c.Score, 0)) AS AvgCommentScore
  FROM Comments c
  WHERE c.UserId IS NOT NULL
  GROUP BY c.UserId
)
SELECT 
  COALESCE(ups.UserId, bs.UserId, vs.UserId, cs.UserId) AS UserId,
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
  (COALESCE(ups.TotalScore, 0) * 1.5
   + COALESCE(bs.GoldBadges, 0) * 100
   + COALESCE(bs.SilverBadges, 0) * 50
   + COALESCE(bs.BronzeBadges, 0) * 10
   + COALESCE(vs.UpVotesReceived, 0) * 2
   - COALESCE(vs.DownVotesReceived, 0) * 1
   + COALESCE(vs.TotalBountiesOffered, 0) / 10.0) AS EngagementScore
FROM user_post_stats ups
FULL OUTER JOIN badge_stats bs ON ups.UserId = bs.UserId
FULL OUTER JOIN vote_stats vs ON COALESCE(ups.UserId, bs.UserId) = vs.UserId
FULL OUTER JOIN comment_stats cs ON COALESCE(ups.UserId, bs.UserId, vs.UserId) = cs.UserId
WHERE (ups.TotalScore IS NOT NULL OR bs.UserId IS NOT NULL OR vs.UserId IS NOT NULL OR cs.UserId IS NOT NULL)
  AND (bs.BadgeList LIKE '%Guru%' OR bs.BadgeList IS NULL)
-- Include all non-aggregated and window-used columns in GROUP BY if aggregation is added; here ROW-level select only.
ORDER BY EngagementScore DESC NULLS LAST
LIMIT 100;