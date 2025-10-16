-- {"query": "23077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2685, "output_tokens": 931} 

WITH TopUsers AS (
    SELECT 
        u.Id, 
        u.Reputation, 
        u.DisplayName, 
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) AS Rank,
        COALESCE((SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1), 0) AS GoldBadges
    FROM Users u
    WHERE u.Reputation > 1000
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId, 
        p.Title, 
        p.ViewCount, 
        p.OwnerUserId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes
    FROM Posts p
    LEFT OUTER JOIN Comments c ON c.PostId = p.Id
    LEFT OUTER JOIN Votes v ON v.PostId = p.Id
    WHERE p.PostTypeId = 1 AND p.ViewCount IS NOT NULL
    GROUP BY p.Id, p.Title, p.ViewCount, p.OwnerUserId
    HAVING COUNT(DISTINCT c.Id) > 5 OR SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 10
),
TaggedQuestions AS (
    SELECT 
        qs.QuestionId, 
        qs.Title, 
        qs.ViewCount, 
        qs.OwnerUserId, 
        qs.CommentCount, 
        qs.Upvotes,
        STRING_AGG(t.TagName, ', ') AS TagsList
    FROM QuestionStats qs
    INNER JOIN Posts p ON p.Id = qs.QuestionId
    CROSS JOIN LATERAL STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS tag_array(tag)
    INNER JOIN Tags t ON t.TagName = tag_array.tag
    WHERE t.Count > 100
    GROUP BY qs.QuestionId, qs.Title, qs.ViewCount, qs.OwnerUserId, qs.CommentCount, qs.Upvotes
),
UserActivity AS (
    SELECT 
        tu.Id AS UserId, 
        tu.DisplayName, 
        tu.Reputation, 
        tu.Rank, 
        tu.GoldBadges,
        COALESCE(SUM(tq.ViewCount), 0) AS TotalViews,
        COALESCE(MAX(tq.Upvotes), 0) AS MaxUpvotes,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = tu.Id AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > '2020-01-01') AS EditCount
    FROM TopUsers tu
    LEFT OUTER JOIN TaggedQuestions tq ON tq.OwnerUserId = tu.Id
    GROUP BY tu.Id, tu.DisplayName, tu.Reputation, tu.Rank, tu.GoldBadges
)
SELECT 
    ua.UserId, 
    ua.DisplayName, 
    ua.Reputation, 
    ua.Rank, 
    ua.GoldBadges, 
    ua.TotalViews, 
    ua.MaxUpvotes, 
    ua.EditCount,
    CASE 
        WHEN ua.TotalViews > 100000 THEN 'High Impact' 
        WHEN ua.TotalViews BETWEEN 10000 AND 100000 THEN 'Medium Impact' 
        WHEN ua.TotalViews IS NULL OR ua.TotalViews = 0 THEN 'Low Impact' 
        ELSE 'Unknown' 
    END AS ImpactLevel,
    (SELECT STRING_AGG(pl.RelatedPostId::text, '; ') 
     FROM PostLinks pl 
     WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = ua.UserId AND p.PostTypeId = 1) 
     AND pl.LinkTypeId = 3) AS DuplicateLinks
FROM UserActivity ua
WHERE ua.Rank <= 100
UNION ALL
SELECT 
    u.Id AS UserId, 
    u.DisplayName, 
    u.Reputation, 
    0 AS Rank, 
    0 AS GoldBadges, 
    0 AS TotalViews, 
    0 AS MaxUpvotes, 
    0 AS EditCount, 
    'Inactive' AS ImpactLevel, 
    NULL AS DuplicateLinks
FROM Users u
LEFT OUTER JOIN Posts p ON p.OwnerUserId = u.Id
WHERE p.Id IS NULL AND u.CreationDate < '2010-01-01'
ORDER BY Reputation DESC
LIMIT 200;
