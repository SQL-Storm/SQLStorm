-- {"query": "7455.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1336} 
WITH UserActivityStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate))
            ELSE NULL 
        END as DaysSinceLastPost,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 1000 THEN 'Veteran'
            WHEN u.Reputation > 100 THEN 'Contributor'
            ELSE 'Newbie'
        END as ReputationTier
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) as RankByReputation,
        RANK() OVER (ORDER BY PostCount DESC) as RankByPostCount,
        DENSE_RANK() OVER (ORDER BY BadgeCount DESC) as RankByBadgeCount
    FROM UserActivityStats
),
QuestionStats AS (
    SELECT 
        p.ParentId as QuestionId,
        p.OwnerUserId,
        COUNT(*) as AnswerCount,
        AVG(p.Score) as AvgAnswerScore,
        MAX(p.CreationDate) as LatestAnswerDate,
        STRING_AGG(p.Body, ' || ') as AllAnswerBodies
    FROM Posts p
    WHERE p.PostTypeId = 2 
    GROUP BY p.ParentId, p.OwnerUserId
),
TagAnalysis AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        AVG(CAST(CHARINDEX('javascript', t.TagName) AS FLOAT)) as HasJavaScriptTag,
        COALESCE(SUBSTRING(t.TagName, 1, 1), 'N/A') as FirstLetter,
        CASE 
            WHEN t.TagName LIKE '%-%' THEN 'Hyphenated'
            WHEN t.TagName LIKE '%.%' THEN 'Dotted'
            ELSE 'Standard'
        END as TagNamingConvention,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as RelatedPostsCount
    FROM Tags t
    WHERE t.Count > 10
    GROUP BY t.TagName, t.Count
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.ReputationTier,
    ru.PostCount,
    ru.CommentCount,
    ru.BadgeCount,
    ru.DaysSinceLastPost,
    ru.RankByReputation,
    ru.RankByPostCount,
    ru.RankByBadgeCount,
    COALESCE(qs.AnswerCount, 0) as AnswerCount,
    COALESCE(qs.AvgAnswerScore, 0) as AvgAnswerScore,
    qs.LatestAnswerDate,
    CASE 
        WHEN ru.PostCount > 0 AND ru.Reputation > 1000 THEN 
            CAST((ru.PostCount * 1.0 / ru.Reputation) * 100 AS DECIMAL(5,2))
        ELSE 0 
    END as PostToReputationRatio,
    COALESCE(SUBSTRING(ru.LastPostDate::VARCHAR, 1, 10), 'No Posts') as LastPostDate,
    ta.TagName,
    ta.TagCount,
    ta.TagNamingConvention,
    ta.RelatedPostsCount,
    CASE 
        WHEN ta.TagCount > 100 THEN 'Popular Tag'
        WHEN ta.TagCount > 50 THEN 'Moderate Tag'
        WHEN ta.TagCount > 10 THEN 'New Tag'
        ELSE 'Niche Tag'
    END as TagCategory,
    DATEDIFF(CURRENT_TIMESTAMP, ta.RelatedPostsCount::TIMESTAMP) as TagRecencyDays,
    ROW_NUMBER() OVER (PARTITION BY ta.TagCategory ORDER BY ta.TagCount DESC) as TagRankInCategory,
    CASE
        WHEN ru.BadgeCount > 50 THEN 'High Achiever'
        WHEN ru.BadgeCount > 25 THEN 'Mid Achiever'
        WHEN ru.BadgeCount > 10 THEN 'Low Achiever'
        ELSE 'Newbie'
    END as AchievementLevel
FROM RankedUsers ru
LEFT JOIN QuestionStats qs ON ru.UserId = qs.OwnerUserId
LEFT JOIN TagAnalysis ta ON ta.TagName LIKE '%' || ru.DisplayName || '%'
WHERE 
    (ru.Reputation > 15000 OR ru.PostCount > 100 OR ru.BadgeCount > 20)
    AND (qs.AnswerCount > 5 OR qs.AnswerCount IS NULL)
    AND (
        ta.TagName IS NULL OR ta.TagCount > 20 
        OR (ru.Reputation > 20000 AND ta.TagCount > 100)
    )
    AND (
        ru.DaysSinceLastPost IS NULL OR ru.DaysSinceLastPost <= 365
    )
    AND ru.DisplayName IS NOT NULL
    AND LENGTH(ru.DisplayName) > 3
    AND ru.Reputation <> 0
    AND (ta.RelatedPostsCount IS NULL OR ta.RelatedPostsCount > 0)
    AND (
        ta.TagCount IS NULL 
        OR (
            ta.TagCount > 50 
            AND (
                SELECT COUNT(*) 
                FROM Posts p 
                WHERE p.Tags LIKE '%' || ta.TagName || '%' 
                AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 YEAR'
            ) > 10
        )
    )
ORDER BY 
    ru.Reputation DESC,
    ru.PostCount DESC,
    ta.TagCount DESC,
    ru.RankByBadgeCount ASC
LIMIT 1000
OFFSET 500;