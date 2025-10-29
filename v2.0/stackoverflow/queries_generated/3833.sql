-- {"query": "3833.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1976} 
WITH 
    UserStats AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            COUNT(b.Id) AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation
    ),
    PostStats AS (
        SELECT 
            p.OwnerUserId AS UserId,
            COUNT(*) AS TotalPosts,
            COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS Questions,
            COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS Answers,
            AVG(p.Score) AS AvgScore,
            MAX(p.CreationDate) AS LastPostDate,
            COALESCE((
                SELECT MAX(p2.Score)
                FROM Posts p2
                WHERE p2.OwnerUserId = p.OwnerUserId
                  AND p2.PostTypeId = 2
            ), 0) AS MaxAnswerScore,
            COALESCE((
                SELECT COUNT(c.Id)
                FROM Comments c
                WHERE c.PostId = p.Id
            ), 0) AS CommentCount
        FROM Posts p
        WHERE p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId
    ),
    TagUsage AS (
        SELECT 
            u.Id AS UserId,
            SUM(
                CASE 
                    WHEN p.Tags IS NOT NULL 
                    THEN (LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '><', '')))/2
                    ELSE 0 
                END
            ) AS TagCount,
            MAX(
                CASE 
                    WHEN p.Tags IS NOT NULL 
                    THEN SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><', 1)
                    ELSE NULL 
                END
            ) AS FirstTag
        FROM Users u
        LEFT JOIN Posts p ON p.OwnerUserId = u.Id
        GROUP BY u.Id
    ),
    RecentVotes AS (
        SELECT 
            v.UserId,
            COUNT(*) AS RecentVoteCount
        FROM Votes v
        WHERE v.CreationDate > CURRENT_TIMESTAMP - INTERVAL '30 days'
        GROUP BY v.UserId
    )

SELECT 
    u.Id,
    u.DisplayName,
    u.Reputation,
    COALESCE(us.BadgeCount,0) AS BadgeCount,
    COALESCE(us.GoldBadges,0) AS GoldBadges,
    COALESCE(us.SilverBadges,0) AS SilverBadges,
    COALESCE(us.BronzeBadges,0) AS BronzeBadges,
    COALESCE(ps.TotalPosts,0) AS TotalPosts,
    COALESCE(ps.Questions,0) AS Questions,
    COALESCE(ps.Answers,0) AS Answers,
    ROUND(COALESCE(ps.AvgScore,0),2) AS AvgScore,
    ps.LastPostDate,
    ps.MaxAnswerScore,
    ps.CommentCount,
    COALESCE(tu.TagCount,0) AS TagCount,
    tu.FirstTag,
    COALESCE(rv.RecentVoteCount,0) AS RecentVoteCount,
    ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, us.GoldBadges DESC) AS Rank
FROM Users u
LEFT JOIN UserStats us ON us.Id = u.Id
LEFT JOIN PostStats ps ON ps.UserId = u.Id
LEFT JOIN TagUsage tu ON tu.UserId = u.Id
LEFT JOIN RecentVotes rv ON rv.UserId = u.Id
WHERE 
    (u.Reputation > 1000 OR COALESCE(us.GoldBadges,0) > 0)
    AND (COALESCE(ps.TotalPosts,0) > 5 OR ps.TotalPosts IS NULL)
ORDER BY Rank
LIMIT 100

UNION ALL

SELECT 
    NULL AS Id,
    'TOTAL' AS DisplayName,
    NULL AS Reputation,
    SUM(COALESCE(us.BadgeCount,0)) AS BadgeCount,
    SUM(COALESCE(us.GoldBadges,0)) AS GoldBadges,
    SUM(COALESCE(us.SilverBadges,0)) AS SilverBadges,
    SUM(COALESCE(us.BronzeBadges,0)) AS BronzeBadges,
    SUM(COALESCE(ps.TotalPosts,0)) AS TotalPosts,
    SUM(COALESCE(ps.Questions,0)) AS Questions,
    SUM(COALESCE(ps.Answers,0)) AS Answers,
    NULL AS AvgScore,
    NULL AS LastPostDate,
    NULL AS MaxAnswerScore,
    NULL AS CommentCount,
    SUM(COALESCE(tu.TagCount,0)) AS TagCount,
    NULL AS FirstTag,
    SUM(COALESCE(rv.RecentVoteCount,0)) AS RecentVoteCount,
    NULL AS Rank
FROM UserStats us
FULL OUTER JOIN PostStats ps ON ps.UserId = us.Id
FULL OUTER JOIN TagUsage tu ON tu.UserId = us.Id
FULL OUTER JOIN RecentVotes rv ON rv.UserId = us.Id;