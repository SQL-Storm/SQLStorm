-- {"query": "4190.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1476} 
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS UpVoteCountForPost,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        u.DisplayName AS OwnerDisplayName,
        u.Reputation AS OwnerReputation,
        COALESCE(p.ViewCount, 0) AS SafeViewCount,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        p.Title,
        p.Tags
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        rp.OwnerUserId,
        COUNT(DISTINCT rp.PostId) AS TotalPosts,
        SUM(rp.PostScore) AS TotalScore,
        AVG(rp.PostScore) AS AvgScore,
        SUM(rp.CommentCountForPost) AS TotalComments,
        SUM(rp.UpVoteCountForPost) AS TotalUpVotes,
        COUNT(DISTINCT CASE WHEN rp.PostStatus = 'Closed' THEN rp.PostId ELSE NULL END) AS ClosedPosts,
        MAX(rp.OwnerReputation) AS MaxReputation
    FROM RankedPosts rp
    GROUP BY rp.OwnerUserId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostStatus,
    rp.OwnerDisplayName,
    COALESCE(ua.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ua.AvgScore, 0) AS UserAvgPostScore,
    COALESCE(ua.TotalUpVotes, 0) AS UserTotalUpVotes,
    COALESCE(ua.ClosedPosts, 0) AS UserClosedPosts,
    COALESCE(ua.MaxReputation, 0) AS UserMaxReputation,
    CASE
        WHEN rp.PostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1) * 1.5 THEN 'High Score Question'
        WHEN rp.CommentCountForPost > (SELECT AVG(CommentCount) FROM Posts WHERE PostTypeId = 1) * 2 THEN 'Highly Commented Question'
        WHEN rp.SafeViewCount > 10000 THEN 'High Traffic'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 3)) AS DisplayNamePrefix,
    rp.rn AS UserPostRank,
    rp.PreviousPostScore,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Anonymous'
        WHEN rp.OwnerReputation < 1000 THEN 'New User'
        WHEN rp.OwnerReputation BETWEEN 1000 AND 10000 THEN 'Intermediate User'
        ELSE 'Experienced User'
    END AS UserExperienceLevel,
    COALESCE(pht.EditCount, 0) AS PostEditCount
FROM RankedPosts rp
JOIN UserActivity ua ON rp.OwnerUserId = ua.OwnerUserId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6)
    GROUP BY PostId
) pht ON rp.PostId = pht.PostId
WHERE rp.rn <= 10 AND rp.PostTypeId = 1
UNION
SELECT
    rp.PostId,
    rp.Title,
    rp.Tags,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostStatus,
    rp.OwnerDisplayName,
    COALESCE(ua.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ua.AvgScore, 0) AS UserAvgPostScore,
    COALESCE(ua.TotalUpVotes, 0) AS UserTotalUpVotes,
    COALESCE(ua.ClosedPosts, 0) AS UserClosedPosts,
    COALESCE(ua.MaxReputation, 0) AS UserMaxReputation,
    CASE
        WHEN rp.PostScore > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 2) * 1.2 THEN 'High Score Answer'
        WHEN rp.CommentCountForPost > (SELECT AVG(CommentCount) FROM Posts WHERE PostTypeId = 2) * 1.5 THEN 'Highly Commented Answer'
        ELSE 'Standard'
    END AS PostEngagementCategory,
    UPPER(SUBSTRING(rp.OwnerDisplayName, 1, 3)) AS DisplayNamePrefix,
    rp.rn AS UserPostRank,
    rp.PreviousPostScore,
    CASE
        WHEN rp.OwnerUserId IS NULL THEN 'Anonymous'
        WHEN rp.OwnerReputation < 100 THEN 'New User'
        WHEN rp.OwnerReputation BETWEEN 100 AND 1000 THEN 'Intermediate User'
        ELSE 'Experienced User'
    END AS UserExperienceLevel,
    COALESCE(pht.EditCount, 0) AS PostEditCount
FROM RankedPosts rp
JOIN UserActivity ua ON rp.OwnerUserId = ua.OwnerUserId
LEFT JOIN (
    SELECT PostId, COUNT(*) AS EditCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (5, 8)
    GROUP BY PostId
) pht ON rp.PostId = pht.PostId
WHERE rp.rn <= 20 AND rp.PostTypeId = 2 AND rp.HasAcceptedAnswer = 1;