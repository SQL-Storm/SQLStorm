-- {"query": "4701.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1283} 
WITH UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.OwnerUserId
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(DISTINCT c.Id) AS TotalComments,
        AVG(c.Score) AS AverageCommentScore,
        COUNT(DISTINCT CASE WHEN c.Score < 0 THEN c.Id ELSE NULL END) AS NegativeScoreComments
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
HighReputationUsers AS (
    SELECT
        u.Id
    FROM Users u
    WHERE u.Reputation > 50000
),
UserActivitySummary AS (
    SELECT
        upc.OwnerUserId,
        upc.TotalPosts,
        upc.QuestionCount,
        upc.AnswerCount,
        upc.AverageScore,
        upc.LastPostDate,
        COALESCE(ucs.TotalComments, 0) AS TotalComments,
        COALESCE(ucs.AverageCommentScore, 0) AS AverageCommentScore,
        CASE WHEN u.DisplayName LIKE '%[a-z]%' THEN 'ContainsAlphabetic' ELSE 'NoAlphabetic' END AS DisplayNameType,
        DATEDIFF(day, u.CreationDate, GETDATE()) AS AccountAgeDays,
        ROW_NUMBER() OVER (ORDER BY upc.TotalPosts DESC, upc.AverageScore DESC) AS PostRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) AS PreviousReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation) AS NextReputation
    FROM UserPostCounts upc
    JOIN Users u ON upc.OwnerUserId = u.Id
    LEFT JOIN UserCommentStats ucs ON upc.OwnerUserId = ucs.UserId
    WHERE u.Id IN (SELECT Id FROM HighReputationUsers)
    AND upc.TotalPosts > 100
    AND upc.AverageScore > 5
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate,
        pt.Name AS PostType,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'CommunityOwned'
            ELSE 'Active'
        END AS PostStatus,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpVotes,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownVotes,
        (p.AnswerCount * 1.5) + p.CommentCount + p.FavoriteCount AS EngagementScore
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId != -1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.CreationDate, pt.Name, p.ClosedDate, p.CommunityOwnedDate
),
RankedPostEngagement AS (
    SELECT
        pe.*,
        ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.EngagementScore DESC, pe.Score DESC) AS UserPostEngagementRank
    FROM PostEngagement pe
)
SELECT
    uas.OwnerUserId,
    uas.DisplayNameType,
    uas.AccountAgeDays,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.AverageScore,
    uas.TotalComments,
    uas.AverageCommentScore,
    uas.PreviousReputation,
    uas.NextReputation,
    rpe.PostId AS TopEngagedPostId,
    rpe.Title AS TopEngagedPostTitle,
    rpe.PostType AS TopEngagedPostType,
    rpe.Score AS TopEngagedPostScore,
    rpe.ViewCount AS TopEngagedPostViewCount,
    rpe.EngagementScore AS TopEngagedPostEngagementScore,
    rpe.PostStatus AS TopEngagedPostStatus,
    rp.PostId AS SecondRankedPostId,
    rp.Score AS SecondRankedPostScore,
    rp.EngagementScore AS SecondRankedPostEngagementScore
FROM UserActivitySummary uas
JOIN RankedPostEngagement rpe ON uas.OwnerUserId = rpe.OwnerUserId AND rpe.UserPostEngagementRank = 1
LEFT JOIN RankedPostEngagement rp ON uas.OwnerUserId = rp.OwnerUserId AND rp.UserPostEngagementRank = 2
WHERE uas.PostRank BETWEEN 5 AND 10
ORDER BY uas.PostRank;