-- {"query": "4300.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1185} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.CreationDate) AS LatestPostDate,
        AVG(p.Score) AS AveragePostScore,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        pt.Name AS PostType,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        COALESCE(ua.DisplayName, p.OwnerDisplayName) AS OriginalOwnerDisplayName,
        COALESCE(ua.Reputation, 0) AS OriginalOwnerReputation,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
        (SELECT STRING_AGG(CONCAT(c.UserDisplayName, ':', c.Score), '; ') FROM Comments c WHERE c.PostId = p.Id) AS CommentSummary
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers
),
PostPerformance AS (
    SELECT
        pe.PostId,
        pe.Title,
        pe.PostType,
        pe.CreationDate,
        pe.Score,
        pe.ViewCount,
        pe.AnswerCount,
        pe.CommentCount,
        pe.IsClosed,
        pe.OriginalOwnerDisplayName,
        pe.OriginalOwnerReputation,
        pe.DuplicateLinkCount,
        pe.CommentSummary,
        ROW_NUMBER() OVER (PARTITION BY pe.PostType ORDER BY pe.Score DESC) AS ScoreRank,
        AVG(pe.Score) OVER (PARTITION BY pe.PostType) AS AvgScoreByType,
        SUM(pe.ViewCount) OVER (PARTITION BY pe.PostType) AS TotalViewsByType,
        (
            SELECT COUNT(DISTINCT ph.UserId)
            FROM PostHistory ph
            WHERE ph.PostId = pe.PostId
            AND ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
            AND ph.UserId IS NOT NULL
        ) AS EditorCount
    FROM PostEngagement pe
)
SELECT
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CommentCount,
    ua.GoldBadgeCount,
    ua.SilverBadgeCount,
    ua.BronzeBadgeCount,
    pp.Title AS TopPostTitle,
    pp.Score AS TopPostScore,
    pp.ViewCount AS TopPostViewCount,
    pp.AvgScoreByType AS AverageScoreForUserPostType,
    pp.TotalViewsByType AS TotalViewsForUserPostType,
    pp.EditorCount AS EditorsOfTopPost,
    CASE
        WHEN ua.LatestPostDate IS NULL THEN 'Never Posted'
        WHEN ua.LatestPostDate < NOW() - INTERVAL '1 year' THEN 'Inactive'
        ELSE 'Active'
    END AS UserActivityStatus,
    COALESCE(ua.DisplayName, 'Anonymous') AS SanitizedDisplayName,
    LENGTH(ua.AboutMe) AS AboutMeLength,
    CASE WHEN ua.WebsiteUrl IS NULL OR ua.WebsiteUrl = '' THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus,
    (ua.UpVotes - ua.DownVotes) AS NetVotes,
    pp.CommentSummary
FROM UserActivity ua
LEFT JOIN PostPerformance pp
    ON ua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = (SELECT PostId FROM PostPerformance WHERE ScoreRank = 1 AND PostType = 'Question'))
    AND pp.ScoreRank = 1
    AND pp.PostType = 'Question'
WHERE ua.Reputation > 1000
ORDER BY ua.Reputation DESC, ua.TotalPosts DESC;
