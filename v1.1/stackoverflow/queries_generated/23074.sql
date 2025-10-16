-- {"query": "23074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 785} 
WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(COALESCE(p.Tags, ''), '|') AS AllTags
    FROM Users u
    LEFT OUTER JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1, 2)  -- Questions and Answers
    GROUP BY u.Id, u.Reputation
    HAVING COUNT(p.Id) > 0 OR u.Reputation > 100
),
BadgeStats AS (
    SELECT 
        UserId,
        COUNT(Id) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        RANK() OVER (PARTITION BY UserId ORDER BY Date DESC) AS BadgeRank
    FROM Badges
    GROUP BY UserId
),
TopVotedPosts AS (
    SELECT 
        PostId,
        VoteTypeId,
        COUNT(Id) AS VoteCount,
        ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate) AS VoteRow
    FROM Votes
    WHERE VoteTypeId IN (2, 3)  -- Upvotes and Downvotes
    GROUP BY PostId, VoteTypeId
),
ComplexQuery AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        ua.PostCount,
        ua.AvgPostScore,
        bs.BadgeCount,
        bs.GoldBadges,
        COALESCE((SELECT COUNT(c.Id) FROM Comments c WHERE c.UserId = ua.UserId), 0) AS CommentCount,
        (SELECT MAX(v.VoteCount) FROM TopVotedPosts v INNER JOIN Posts p ON v.PostId = p.Id WHERE p.OwnerUserId = ua.UserId AND v.VoteTypeId = 2) AS MaxUpvotes,
        CASE 
            WHEN ua.AllTags LIKE '%sql%' THEN 'SQL Expert'
            WHEN ua.AllTags IS NULL THEN 'No Tags'
            ELSE SUBSTRING(ua.AllTags, 1, 50)
        END AS TagCategory,
        DENSE_RANK() OVER (ORDER BY ua.Reputation DESC NULLS LAST) AS RepRank
    FROM UserActivity ua
    FULL OUTER JOIN BadgeStats bs ON ua.UserId = bs.UserId
    WHERE ua.LastPostDate > '2020-01-01' OR bs.BadgeRank = 1
    UNION
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        0 AS PostCount,
        0 AS AvgPostScore,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        0 AS CommentCount,
        0 AS MaxUpvotes,
        'Inactive' AS TagCategory,
        NULL AS RepRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE NOT EXISTS (SELECT 1 FROM Posts p WHERE p.OwnerUserId = u.Id)
    GROUP BY u.Id, u.Reputation
)
SELECT 
    cq.*,
    (SELECT COUNT(pl.Id) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = cq.UserId)) AS LinkCount,
    COALESCE(NULLIF(cq.BadgeCount, 0) / NULLIF(cq.PostCount, 0), 0) AS BadgesPerPost
FROM ComplexQuery cq
WHERE cq.RepRank <= 100 OR cq.TagCategory = 'SQL Expert'
ORDER BY cq.Reputation DESC, cq.MaxUpvotes DESC;