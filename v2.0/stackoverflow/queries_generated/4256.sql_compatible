WITH UserPostInteractions AS (
    SELECT
        u.Id AS UserId,
        p.Id AS PostId,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.Score) AS MaxPostScore,
        MIN(p.CreationDate) AS FirstPostCreation,
        AVG(p.AnswerCount) AS AvgAnswerCountForUserPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON p.Id = c.PostId AND u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId AND u.Id = v.UserId
    WHERE p.PostTypeId = 1 AND p.CreationDate > DATE '2023-01-01'
    GROUP BY u.Id, p.Id
),
RankedPostInteractions AS (
    SELECT
        UPI.UserId,
        UPI.PostId,
        UPI.CommentCount,
        UPI.UpVoteCount,
        UPI.DownVoteCount,
        UPI.MaxPostScore,
        UPI.FirstPostCreation,
        UPI.AvgAnswerCountForUserPosts,
        ROW_NUMBER() OVER(PARTITION BY UPI.UserId ORDER BY UPI.UpVoteCount DESC, UPI.CommentCount DESC) AS UserPostRank,
        LAG(UPI.MaxPostScore, 1, 0) OVER(PARTITION BY UPI.UserId ORDER BY UPI.FirstPostCreation) AS PreviousPostScore
    FROM UserPostInteractions UPI
),
UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN p.Score > 100 THEN 1 ELSE 0 END) AS HighScorePostCount,
        MAX(u.Reputation) AS MaxReputation,
        CAST(EXTRACT(EPOCH FROM (MAX(u.LastAccessDate) - MIN(u.CreationDate))) / 86400 AS INTEGER) AS AccountLifespanDays,
        SUM(CASE WHEN u.WebsiteUrl IS NOT NULL THEN 1 ELSE 0 END) AS HasWebsite
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id < 100000
    GROUP BY u.Id, u.DisplayName
),
PostMetrics AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        pt.Name AS PostType,
        u.DisplayName AS OwnerDisplayName,
        p.OwnerUserId,
        COUNT(c.Id) AS NumberOfComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.CreationDate BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
    GROUP BY p.Id, p.Title, p.CreationDate, pt.Name, u.DisplayName, p.ClosedDate, p.CommunityOwnedDate, p.OwnerUserId
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.QuestionCount,
    ue.AnswerCount,
    ue.BadgeCount,
    ue.HighScorePostCount,
    ue.MaxReputation,
    ue.AccountLifespanDays,
    ue.HasWebsite,
    rpi.UserPostRank,
    rpi.PreviousPostScore,
    SUM(pm.TotalUpvotes) OVER(PARTITION BY ue.UserId ORDER BY pm.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeUpvotes,
    MAX(pm.NumberOfComments) OVER(PARTITION BY ue.UserId) AS MaxCommentsOnAnyPost,
    CASE
        WHEN pm.IsClosed = 1 AND pm.IsCommunityOwned = 0 THEN 'Active'
        WHEN pm.IsClosed = 1 AND pm.IsCommunityOwned = 1 THEN 'Community Archive'
        ELSE 'Standard'
    END AS PostStatus,
    ('User Performance Report: ' || ue.DisplayName || ' (' || ue.UserId || ')') AS ReportTitle
FROM UserEngagement ue
LEFT JOIN RankedPostInteractions rpi ON ue.UserId = rpi.UserId AND rpi.UserPostRank = 1
LEFT JOIN PostMetrics pm ON ue.UserId = pm.OwnerUserId
WHERE ue.AnswerCount > 5 OR ue.QuestionCount > 10

UNION ALL

SELECT
    NULL AS UserId,
    'Overall Metrics' AS DisplayName,
    COUNT(DISTINCT p.Id) AS QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
    COUNT(DISTINCT b.Id) AS BadgeCount,
    SUM(CASE WHEN p.Score > 100 THEN 1 ELSE 0 END) AS HighScorePostCount,
    MAX(u.Reputation) AS MaxReputation,
    CAST(EXTRACT(EPOCH FROM (MAX(u.LastAccessDate) - MIN(u.CreationDate))) / 86400 AS INTEGER) AS AccountLifespanDays,
    SUM(CASE WHEN u.WebsiteUrl IS NOT NULL THEN 1 ELSE 0 END) AS HasWebsite,
    NULL AS UserPostRank,
    NULL AS PreviousPostScore,
    NULL AS CumulativeUpvotes,
    NULL AS MaxCommentsOnAnyPost,
    NULL AS PostStatus,
    NULL AS ReportTitle
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
WHERE u.Id < 100000;