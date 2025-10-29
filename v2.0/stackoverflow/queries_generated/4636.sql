-- {"query": "4636.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1039} 

WITH UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgeCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgeCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgeCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVoteCount,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostSequence
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.OwnerUserId IS NOT NULL
),
UserPerformance AS (
    SELECT
        uc.UserId,
        uc.DisplayName,
        uc.QuestionCount,
        uc.AnswerCount,
        uc.TotalAnswerScore,
        uc.CommentCount,
        uc.GoldBadgeCount,
        uc.SilverBadgeCount,
        uc.BronzeBadgeCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = uc.UserId)) AS LinkedPostsCount,
        CASE
            WHEN uc.AnswerCount > 0 THEN CAST(uc.TotalAnswerScore AS REAL) / uc.AnswerCount
            ELSE 0
        END AS AverageAnswerScore,
        CASE
            WHEN uc.QuestionCount > 0 THEN uc.AnswerCount * 1.0 / uc.QuestionCount
            ELSE 0
        END AS AnswerToQuestionRatio
    FROM UserContribution uc
)
SELECT
    up.DisplayName,
    up.QuestionCount,
    up.AnswerCount,
    up.TotalAnswerScore,
    up.CommentCount,
    up.GoldBadgeCount,
    up.SilverBadgeCount,
    up.BronzeBadgeCount,
    up.AverageAnswerScore,
    up.AnswerToQuestionRatio,
    pe.Title AS LatestQuestionTitle,
    pe.PostType AS LatestPostType,
    pe.UpVoteCount AS LatestPostUpVotes,
    pe.DownVoteCount AS LatestPostDownVotes,
    pe.FavoriteCount AS LatestPostFavorites,
    CASE
        WHEN up.TotalAnswerScore > 1000 AND up.AnswerCount > 50 AND up.GoldBadgeCount > 2 THEN 'Top Performer'
        WHEN up.AverageAnswerScore > 5 AND up.AnswerToQuestionRatio > 0.5 THEN 'High Quality Contributor'
        WHEN up.CommentCount > 100 THEN 'Active Commenter'
        WHEN up.BronzeBadgeCount >= 5 THEN 'Emerging Contributor'
        ELSE 'Standard Contributor'
    END AS PerformanceTier
FROM UserPerformance up
LEFT JOIN PostEngagement pe
    ON up.UserId = pe.OwnerUserId AND pe.PostSequence = 1
WHERE
    up.AnswerCount > 0 OR up.QuestionCount > 0
    AND up.DisplayName NOT LIKE '%[bot]%'
    AND up.DisplayName IS NOT NULL
    AND LOWER(up.DisplayName) NOT LIKE '%anonymous%'
ORDER BY
    up.TotalAnswerScore DESC,
    up.AverageAnswerScore DESC,
    up.AnswerCount DESC
LIMIT 100;
