-- {"query": "22022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 762} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS TotalPosts,
        COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
        COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        AVG(p.Score) AS AvgScore
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate < '2023-01-01'::timestamp
      AND (u.Location IS NOT NULL OR u.WebsiteUrl IS NULL)
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeStats AS (
    SELECT 
        b.UserId,
        COUNT(*) AS BadgeCount,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        STRING_AGG(b.Name, ', ') AS BadgeNames
    FROM Badges b
    GROUP BY b.UserId
),
PostVotes AS (
    SELECT 
        p.Id AS PostId,
        p.OwnerUserId,
        COUNT(v.Id) AS VoteCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN -1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT OUTER JOIN Votes v ON p.Id = v.PostId
    GROUP BY p.Id, p.OwnerUserId
),
CorrelatedSub AS (
    SELECT DISTINCT p.OwnerUserId,
        (SELECT COUNT(*) FROM Comments c WHERE c.UserId = p.OwnerUserId) AS CommentCount
    FROM Posts p
    WHERE p.Score > 10
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.TotalScore,
    ROUND(us.AvgScore, 2) AS AvgScore,
    bs.BadgeCount,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.BadgeNames,
    pv.UpVotes,
    pv.DownVotes,
    cs.CommentCount,
    ROW_NUMBER() OVER (ORDER BY us.Reputation DESC, us.TotalScore DESC) AS RepRank,
    RANK() OVER (PARTITION BY us.Questions > 0 ORDER BY us.Answers DESC) AS AnswerRank,
    CASE 
        WHEN us.TotalPosts = 0 THEN NULL
        ELSE ROUND((us.Answers::float / NULLIF(us.TotalPosts, 0)) * 100, 2)
    END AS AnswerPercentage,
    SUBSTRING(us.DisplayName, 1, 10) || '...' AS ShortName
FROM UserStats us
FULL OUTER JOIN BadgeStats bs ON us.UserId = bs.UserId
LEFT OUTER JOIN PostVotes pv ON us.UserId = pv.OwnerUserId
LEFT OUTER JOIN CorrelatedSub cs ON us.UserId = cs.OwnerUserId
WHERE us.Reputation > 1000
  AND (bs.BadgeCount > 5 OR bs.BadgeCount IS NULL)
  AND EXISTS (SELECT 1 FROM Votes v WHERE v.UserId = us.UserId AND v.VoteTypeId = 2)
ORDER BY RepRank
LIMIT 50;