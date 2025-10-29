-- {"query": "4911.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1392}
WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        pt.Name AS PostTypeName,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL AND p.PostTypeId IN (1, 2)
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AvgPostScore
    FROM Users u
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostContributionScore AS (
    SELECT
        rp.PostId,
        rp.Title,
        rp.PostTypeName,
        rp.PostScore,
        rp.OwnerUserId,
        ua.UserId,
        ua.UserName,
        ua.Reputation,
        ua.CommentCount,
        ua.UpVoteCount,
        ua.DownVoteCount,
        rp.PostCreationDate,
        ua.AvgPostScore,
        (ua.Reputation * 0.5) + (ua.UpVoteCount * 0.2) - (ua.DownVoteCount * 0.1) + COALESCE(ua.AvgPostScore, 0) * 0.3 AS ContributionScore,
        CASE
            WHEN rp.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year') THEN 'Old'
            WHEN rp.PostCreationDate >= (cast('2024-10-01' as date) - INTERVAL '1 year') AND rp.PostCreationDate < (cast('2024-10-01' as date) - INTERVAL '6 months') THEN 'Medium'
            ELSE 'Recent'
        END AS PostAgeGroup
    FROM RankedPosts rp
    JOIN UserActivity ua ON rp.OwnerUserId = ua.UserId
    WHERE rp.rn <= 5
)
SELECT
    pcs.PostId,
    pcs.Title AS PostTitle,
    pcs.PostTypeName,
    pcs.PostScore,
    pcs.UserId AS PostOwnerId,
    pcs.UserName AS PostOwnerName,
    pcs.Reputation AS OwnerReputation,
    pcs.CommentCount AS OwnerCommentCount,
    pcs.UpVoteCount AS OwnerUpVoteCount,
    pcs.DownVoteCount AS OwnerDownVoteCount,
    pcs.PostCreationDate,
    pcs.AvgPostScore AS OwnerAvgPostScore,
    pcs.ContributionScore,
    pcs.PostAgeGroup,
    COALESCE(pl.LinkTypeId, 0) AS LinkTypeId,
    CASE
        WHEN pcs.PostTypeName = 'Question' THEN
            (SELECT COUNT(Id) FROM Comments WHERE PostId = pcs.PostId AND UserId = pcs.UserId)
        ELSE 0
    END AS OwnerCommentsOnHisQuestion,
    (SELECT COUNT(*) FROM Votes WHERE PostId = pcs.PostId AND UserId = pcs.UserId AND VoteTypeId = 2) AS OwnerUpvotesOnHisPost,
    CASE
        WHEN pcs.PostScore > 100 THEN 'HighScore'
        WHEN pcs.PostScore BETWEEN 10 AND 100 THEN 'MediumScore'
        ELSE 'LowScore'
    END AS PostScoreCategory,
    UPPER(SUBSTRING(pcs.Title FROM 1 FOR 3)) AS TitlePrefix,
    REPLACE(pcs.UserName, ' ', '_') AS NormalizedUserName
FROM PostContributionScore pcs
LEFT JOIN PostLinks pl ON pcs.PostId = pl.PostId AND pl.LinkTypeId = 3
WHERE pcs.ContributionScore > (
    SELECT AVG(ContributionScore) FROM PostContributionScore
)
UNION ALL
SELECT
    pcs.PostId,
    pcs.Title AS PostTitle,
    pcs.PostTypeName,
    pcs.PostScore,
    pcs.UserId AS PostOwnerId,
    pcs.UserName AS PostOwnerName,
    pcs.Reputation AS OwnerReputation,
    pcs.CommentCount AS OwnerCommentCount,
    pcs.UpVoteCount AS OwnerUpVoteCount,
    pcs.DownVoteCount AS OwnerDownVoteCount,
    pcs.PostCreationDate,
    pcs.AvgPostScore AS OwnerAvgPostScore,
    pcs.ContributionScore,
    pcs.PostAgeGroup,
    COALESCE(pl.LinkTypeId, 0) AS LinkTypeId,
    CASE
        WHEN pcs.PostTypeName = 'Question' THEN
            (SELECT COUNT(Id) FROM Comments WHERE PostId = pcs.PostId AND UserId = pcs.UserId)
        ELSE 0
    END AS OwnerCommentsOnHisQuestion,
    (SELECT COUNT(*) FROM Votes WHERE PostId = pcs.PostId AND UserId = pcs.UserId AND VoteTypeId = 2) AS OwnerUpvotesOnHisPost,
    CASE
        WHEN pcs.PostScore > 100 THEN 'HighScore'
        WHEN pcs.PostScore BETWEEN 10 AND 100 THEN 'MediumScore'
        ELSE 'LowScore'
    END AS PostScoreCategory,
    UPPER(SUBSTRING(pcs.Title FROM 1 FOR 3)) AS TitlePrefix,
    REPLACE(pcs.UserName, ' ', '_') AS NormalizedUserName
FROM PostContributionScore pcs
LEFT JOIN PostLinks pl ON pcs.PostId = pl.RelatedPostId AND pl.LinkTypeId = 3
WHERE pcs.ContributionScore <= (
    SELECT AVG(ContributionScore) FROM PostContributionScore
);