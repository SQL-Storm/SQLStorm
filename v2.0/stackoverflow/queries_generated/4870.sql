-- {"query": "4870.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1695} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS RowNum,
        SUM(COALESCE(c.Score, 0)) OVER(PARTITION BY p.Id) AS TotalCommentScore
    FROM Posts AS p
    JOIN PostTypes AS pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments AS c ON p.Id = c.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.OwnerUserId, p.Title, p.CreationDate, pt.Name
),
UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(Score) AS AveragePostScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL AND OwnerUserId > 0
    GROUP BY OwnerUserId
),
UserContributions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(upc.TotalPosts, 0) AS TotalPosts,
        COALESCE(upc.QuestionCount, 0) AS TotalQuestions,
        COALESCE(upc.AnswerCount, 0) AS TotalAnswers,
        COALESCE(u.Reputation, 0) AS UserReputation,
        COALESCE(u.UpVotes, 0) AS UserUpVotes,
        COALESCE(u.DownVotes, 0) AS UserDownVotes,
        COALESCE(ph.EditCount, 0) AS TotalEdits,
        COALESCE(ph.CommentVoteCount, 0) AS TotalCommentVotes,
        COALESCE(b.BadgeCount, 0) AS TotalBadges
    FROM Users AS u
    LEFT JOIN UserPostCounts AS upc ON u.Id = upc.OwnerUserId
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(*) AS EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6)
        GROUP BY UserId
    ) AS ph ON u.Id = ph.UserId
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(*) AS CommentVoteCount
        FROM Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY UserId
    ) AS cv ON u.Id = cv.UserId
    LEFT JOIN (
        SELECT
            UserId,
            COUNT(*) AS BadgeCount
        FROM Badges
        GROUP BY UserId
    ) AS b ON u.Id = b.UserId
    WHERE u.AccountId IS NOT NULL AND u.DisplayName IS NOT NULL AND u.DisplayName <> ''
)
SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeName,
    rp.PostCreationDate,
    uc.DisplayName AS OwnerDisplayName,
    uc.UserReputation,
    uc.TotalPosts,
    uc.TotalQuestions,
    uc.TotalAnswers,
    rp.TotalCommentScore,
    CASE
        WHEN rp.RowNum <= 5 THEN 'Top 5 Recent'
        WHEN rp.RowNum <= 20 THEN 'Next 15 Recent'
        ELSE 'Older'
    END AS RecentPostCategory,
    CASE
        WHEN uc.TotalEdits > 100 THEN 'Prolific Editor'
        WHEN uc.TotalEdits BETWEEN 10 AND 100 THEN 'Active Editor'
        ELSE 'Infrequent Editor'
    END AS EditorActivityLevel,
    CASE
        WHEN uc.TotalCommentVotes > 500 THEN 'High Upvote/Downvote Activity'
        WHEN uc.TotalCommentVotes BETWEEN 100 AND 500 THEN 'Moderate Upvote/Downvote Activity'
        ELSE 'Low Upvote/Downvote Activity'
    END AS VoteActivityLevel,
    uc.UserUpVotes - uc.UserDownVotes AS NetVoteDifference,
    uc.TotalBadges,
    CASE
        WHEN uc.TotalBadges >= 10 AND uc.UserReputation > 10000 THEN 'Highly Decorated Power User'
        WHEN uc.TotalBadges >= 3 AND uc.UserReputation > 1000 THEN 'Decorated Contributor'
        ELSE 'Standard Contributor'
    END AS UserBadgeTier,
    UPPER(SUBSTRING(rp.Title, 1, 3)) AS TitlePrefix,
    (rp.PostCreationDate + INTERVAL '7 day') AS PostPlusOneWeek
FROM RankedPosts AS rp
JOIN UserContributions AS uc ON rp.OwnerUserId = uc.UserId
WHERE rp.PostTypeName <> 'TagWikiExcerpt' AND rp.PostTypeName <> 'TagWiki'
  AND uc.UserReputation > 100
  AND rp.TotalCommentScore BETWEEN 0 AND 1000
  AND uc.TotalPosts BETWEEN 5 AND 50
UNION
SELECT
    rp.PostId,
    rp.Title AS PostTitle,
    rp.PostTypeName,
    rp.PostCreationDate,
    uc.DisplayName AS OwnerDisplayName,
    uc.UserReputation,
    uc.TotalPosts,
    uc.TotalQuestions,
    uc.TotalAnswers,
    rp.TotalCommentScore,
    CASE
        WHEN rp.RowNum <= 5 THEN 'Top 5 Recent'
        WHEN rp.RowNum <= 20 THEN 'Next 15 Recent'
        ELSE 'Older'
    END AS RecentPostCategory,
    CASE
        WHEN uc.TotalEdits > 100 THEN 'Prolific Editor'
        WHEN uc.TotalEdits BETWEEN 10 AND 100 THEN 'Active Editor'
        ELSE 'Infrequent Editor'
    END AS EditorActivityLevel,
    CASE
        WHEN uc.TotalCommentVotes > 500 THEN 'High Upvote/Downvote Activity'
        WHEN uc.TotalCommentVotes BETWEEN 100 AND 500 THEN 'Moderate Upvote/Downvote Activity'
        ELSE 'Low Upvote/Downvote Activity'
    END AS VoteActivityLevel,
    uc.UserUpVotes - uc.UserDownVotes AS NetVoteDifference,
    uc.TotalBadges,
    CASE
        WHEN uc.TotalBadges >= 10 AND uc.UserReputation > 10000 THEN 'Highly Decorated Power User'
        WHEN uc.TotalBadges >= 3 AND uc.UserReputation > 1000 THEN 'Decorated Contributor'
        ELSE 'Standard Contributor'
    END AS UserBadgeTier,
    UPPER(SUBSTRING(rp.Title, 1, 3)) AS TitlePrefix,
    (rp.PostCreationDate + INTERVAL '7 day') AS PostPlusOneWeek
FROM RankedPosts AS rp
JOIN UserContributions AS uc ON rp.OwnerUserId = uc.UserId
WHERE rp.PostTypeName <> 'TagWikiExcerpt' AND rp.PostTypeName <> 'TagWiki'
  AND uc.UserReputation <= 100
  AND rp.TotalCommentScore > 1000
  AND uc.TotalPosts > 50
ORDER BY UserReputation DESC, PostCreationDate DESC;
