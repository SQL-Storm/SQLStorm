-- {"query": "22079.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "grok-code-fast", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2204, "output_tokens": 1368} 
WITH user_activity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        COALESCE(u.Reputation, 0) AS Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 
            CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE -1 END 
            ELSE 0 END) AS NetVotesReceived,
        CASE WHEN u.LastAccessDate > NOW() - INTERVAL '30 days' THEN 1 ELSE 0 END AS RecentActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2,3)
    WHERE u.CreationDate < NOW() - INTERVAL '1 year'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
),
badge_stats AS (
    SELECT 
        UserId,
        COUNT(*) AS BadgeCount,
        SUM(CASE WHEN Class = 1 THEN 10 WHEN Class = 2 THEN 5 ELSE 1 END) AS BadgeScore,
        MAX(CASE WHEN Name LIKE '%Nice%' THEN 1 ELSE 0 END) AS HasNiceBadge
    FROM Badges
    GROUP BY UserId
),
comment_activity AS (
    SELECT 
        UserId,
        COUNT(*) AS CommentCount,
        AVG(LENGTH(Text)) AS AvgCommentLength,
        SUM(CASE WHEN Score > 0 THEN 1 ELSE 0 END) AS PositiveComments
    FROM Comments
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
post_edit_history AS (
    SELECT 
        ph.PostId,
        COUNT(*) AS EditCount,
        MAX(ph.CreationDate) AS LastEdit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6) -- Edit Title, Body, Tags
    GROUP BY ph.PostId
),
linked_posts AS (
    SELECT 
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 1 -- Linked
    GROUP BY pl.PostId
),
ranked_users AS (
    SELECT 
        ua.Id,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalPosts,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.AvgPostScore,
        ua.NetVotesReceived,
        ua.RecentActivity,
        COALESCE(bs.BadgeCount, 0) AS BadgeCount,
        COALESCE(bs.BadgeScore, 0) AS BadgeScore,
        COALESCE(bs.HasNiceBadge, 0) AS HasNiceBadge,
        COALESCE(ca.CommentCount, 0) AS CommentCount,
        COALESCE(ca.AvgCommentLength, 0) AS AvgCommentLength,
        COALESCE(ca.PositiveComments, 0) AS PositiveComments,
        ROW_NUMBER() OVER (ORDER BY ua.Reputation DESC, ua.TotalPosts DESC) AS RepRank,
        RANK() OVER (ORDER BY ua.NetVotesReceived DESC) AS VoteRank,
        DENSE_RANK() OVER (ORDER BY COALESCE(bs.BadgeScore, 0) DESC) AS BadgeRank,
        PERCENT_RANK() OVER (ORDER BY ua.AvgPostScore DESC) AS PostScorePercentile,
        NVL2(ua.DisplayName, UPPER(LEFT(ua.DisplayName, 5)), 'ANON') AS DisplayNamePreview,
        CASE 
            WHEN ua.TotalPosts > 100 AND ua.RecentActivity = 1 THEN 'PowerUser'
            WHEN ua.BadgeCount > 10 THEN 'BadgeCollector'
            ELSE 'Casual' 
        END AS UserCategory
    FROM user_activity ua
    LEFT JOIN badge_stats bs ON ua.Id = bs.UserId
    LEFT JOIN comment_activity ca ON ua.Id = ca.UserId
    WHERE ua.TotalPosts > 0 OR COALESCE(bs.BadgeCount, 0) > 0
),
top_posts_per_user AS (
    SELECT 
        p.OwnerUserId,
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRankInUser,
        p.Tags
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.OwnerUserId IS NOT NULL
),
final_stats AS (
    SELECT 
        ru.*,
        tp.Title AS TopQuestionTitle,
        tp.Score AS TopQuestionScore,
        tp.ViewCount AS TopQuestionViews,
        EXTRACT(YEAR FROM AGE(NOW(), u.CreationDate)) AS AccountAgeYears,
        CASE 
            WHEN ru.NetVotesReceived > 0 THEN ru.NetVotesReceived / NULLIF(ru.TotalPosts, 0)
            ELSE -1
        END AS VotesPerPost,
        CASE WHEN ru.HasNiceBadge = 1 AND ru.RepRank <= 100 THEN 'Elite' ELSE NULL END AS EliteStatus
    FROM ranked_users ru
    INNER JOIN Users u ON ru.Id = u.Id
    LEFT JOIN top_posts_per_user tp ON ru.Id = tp.OwnerUserId AND tp.PostRankInUser = 1
    LEFT JOIN linked_posts lp ON lp.PostId IN (SELECT Id FROM top_posts_per_user WHERE OwnerUserId = ru.Id AND PostRankInUser <= 3)
    LEFT JOIN post_edit_history peh ON peh.PostId IN (SELECT Id FROM top_posts_per_user WHERE OwnerUserId = ru.Id)
    WHERE ru.Reputation > 10 OR ru.TotalPosts > 5
)
SELECT * FROM final_stats fs
WHERE fs.UserCategory IN ('PowerUser', 'BadgeCollector')
    AND EXISTS (
        SELECT 1 FROM Comments c 
        WHERE c.UserId = fs.Id AND LENGTH(c.Text) > 50
    )
UNION ALL
SELECT * FROM final_stats fs
WHERE fs.EliteStatus IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM Votes v WHERE v.UserId = fs.Id AND v.VoteTypeId IN (4,12) -- Offensive or Spam
    )
ORDER BY RepRank ASC, VoteRank ASC
LIMIT 50;