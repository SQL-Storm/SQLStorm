-- {"query": "18093.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1695} 
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(p.Id) AS PostCount,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS PreviousReputation,
        LEAD(u.Reputation, 1, 0) OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS NextReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate < '2023-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
HighReputationUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        ReputationRank,
        (Reputation - PreviousReputation) AS ReputationDeltaFromPrevious,
        (NextReputation - Reputation) AS ReputationDeltaToNext
    FROM RankedUserActivity
    WHERE ReputationRank BETWEEN 50 AND 150
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            ELSE 'Open'
        END AS PostStatus,
        COUNT(c.Id) AS CommentCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCountForPost,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCountForPost,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS AvgPostScoreLastThree
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.CreationDate >= '2022-01-01'
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.ClosedDate
),
UserPostSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT ph.PostId) AS TotalPostsEdited,
        MAX(ph.CreationDate) AS LastEditDate,
        AVG(ph.Id) AS AveragePostHistoryId
    FROM Users u
    JOIN PostHistory ph ON u.Id = ph.UserId
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
    GROUP BY u.Id, u.DisplayName, u.Reputation
)
SELECT
    hru.UserId,
    hru.DisplayName,
    hru.Reputation,
    hru.ReputationRank,
    hru.ReputationDeltaFromPrevious,
    hru.ReputationDeltaToNext,
    pe.PostId,
    pe.PostTypeDescription,
    pe.PostStatus,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCountForPost,
    pe.UpVoteCountForPost,
    pe.DownVoteCountForPost,
    CASE
        WHEN pe.PostScore > 100 THEN 'Highly Valued'
        WHEN pe.PostScore BETWEEN 50 AND 100 THEN 'Moderately Valued'
        WHEN pe.PostScore < 0 THEN 'Negatively Valued'
        ELSE 'Neutral'
    END AS ScoreCategory,
    ups.TotalPostsEdited,
    ups.LastEditDate,
    COALESCE(ups.AveragePostHistoryId, 0) AS AvgHistoryId,
    CONCAT(hru.DisplayName, ' - ', pe.PostTypeDescription) AS UserPostIdentifier,
    (pe.PostScore * 1.0 / NULLIF(pe.PostViewCount, 0)) AS ScoreToViewRatio,
    pe.AvgPostScoreLastThree,
    CASE
        WHEN hru.DisplayName IS NULL THEN 'Anonymous High Rep User'
        ELSE 'Identified High Rep User'
    END AS UserIdentificationStatus,
    ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostScore DESC) AS PostRankForOwner
FROM HighReputationUsers hru
INNER JOIN PostEngagement pe ON hru.UserId = pe.OwnerUserId
LEFT OUTER JOIN UserPostSummary ups ON hru.UserId = ups.UserId
WHERE pe.PostViewCount > 1000
UNION ALL
SELECT
    hru.UserId,
    hru.DisplayName,
    hru.Reputation,
    hru.ReputationRank,
    hru.ReputationDeltaFromPrevious,
    hru.ReputationDeltaToNext,
    pe.PostId,
    pe.PostTypeDescription,
    pe.PostStatus,
    pe.PostScore,
    pe.PostViewCount,
    pe.AnswerCount,
    pe.CommentCountForPost,
    pe.UpVoteCountForPost,
    pe.DownVoteCountForPost,
    CASE
        WHEN pe.PostScore > 100 THEN 'Highly Valued'
        WHEN pe.PostScore BETWEEN 50 AND 100 THEN 'Moderately Valued'
        WHEN pe.PostScore < 0 THEN 'Negatively Valued'
        ELSE 'Neutral'
    END AS ScoreCategory,
    ups.TotalPostsEdited,
    ups.LastEditDate,
    COALESCE(ups.AveragePostHistoryId, 0) AS AvgHistoryId,
    CONCAT(hru.DisplayName, ' - ', pe.PostTypeDescription) AS UserPostIdentifier,
    (pe.PostScore * 1.0 / NULLIF(pe.PostViewCount, 0)) AS ScoreToViewRatio,
    pe.AvgPostScoreLastThree,
    CASE
        WHEN hru.DisplayName IS NULL THEN 'Anonymous High Rep User'
        ELSE 'Identified High Rep User'
    END AS UserIdentificationStatus,
    ROW_NUMBER() OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostScore DESC) AS PostRankForOwner
FROM HighReputationUsers hru
RIGHT JOIN PostEngagement pe ON hru.UserId = pe.OwnerUserId
LEFT OUTER JOIN UserPostSummary ups ON hru.UserId = ups.UserId
WHERE pe.PostScore < 0 AND pe.AnswerCount > 5;