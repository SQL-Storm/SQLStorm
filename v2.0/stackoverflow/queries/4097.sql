-- {"query": "4097.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1614}
WITH UserPostInteractions AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Question' THEN p.Id ELSE NULL END) AS Questions,
        COUNT(DISTINCT CASE WHEN pt.Name = 'Answer' THEN p.Id ELSE NULL END) AS Answers,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id ELSE NULL END) AS UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id ELSE NULL END) AS DownVotesGiven,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(p.Score) AS AveragePostScore,
        SUM(p.ViewCount) AS TotalViewsOnPosts
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON u.Id = c.UserId AND c.PostId = p.Id
    LEFT JOIN Votes v ON u.Id = v.UserId AND v.PostId = p.Id
    WHERE u.Id BETWEEN 10000 AND 50000
    GROUP BY u.Id, u.DisplayName
),
UserReputationChange AS (
    SELECT
        ph.UserId AS UserId,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS Edits,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId = 12 THEN 1 ELSE 0 END) AS DeleteVotes,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (16, 50) THEN 1 ELSE 0 END) AS CommunityInteractions,
        COUNT(DISTINCT CASE WHEN ph.Comment IS NOT NULL AND ph.Comment <> '' THEN ph.Id ELSE NULL END) AS PostsWithComments
    FROM PostHistory ph
    JOIN Users u ON ph.UserId = u.Id
    WHERE u.Id BETWEEN 10000 AND 50000
    GROUP BY ph.UserId
),
RankedUserActivity AS (
    SELECT
        upi.UserId,
        upi.DisplayName,
        upi.TotalPosts,
        upi.Questions,
        upi.Answers,
        upi.TotalComments,
        upi.UpVotesGiven,
        upi.DownVotesGiven,
        upi.LastPostDate,
        upi.AveragePostScore,
        upi.TotalViewsOnPosts,
        COALESCE(urc.Edits, 0) AS Edits,
        COALESCE(urc.CloseVotes, 0) AS CloseVotes,
        COALESCE(urc.DeleteVotes, 0) AS DeleteVotes,
        COALESCE(urc.CommunityInteractions, 0) AS CommunityInteractions,
        COALESCE(urc.PostsWithComments, 0) AS PostsWithComments,
        ROW_NUMBER() OVER (ORDER BY upi.TotalPosts DESC, upi.LastPostDate DESC) AS PostRank,
        DENSE_RANK() OVER (PARTITION BY CASE WHEN upi.AveragePostScore > 0 THEN 'Positive' WHEN upi.AveragePostScore < 0 THEN 'Negative' ELSE 'Zero' END ORDER BY upi.AveragePostScore DESC) AS ScoreRank,
        LAG(u.reputation, 1, 0) OVER (ORDER BY u.reputation DESC) AS PreviousReputation,
        LEAD(u.reputation, 1, 0) OVER (ORDER BY u.reputation DESC) AS NextReputation,
        u.reputation AS Reputation
    FROM UserPostInteractions upi
    LEFT JOIN UserReputationChange urc ON upi.UserId = urc.UserId
    JOIN Users u ON upi.UserId = u.Id
    GROUP BY
        upi.UserId,
        upi.DisplayName,
        upi.TotalPosts,
        upi.Questions,
        upi.Answers,
        upi.TotalComments,
        upi.UpVotesGiven,
        upi.DownVotesGiven,
        upi.LastPostDate,
        upi.AveragePostScore,
        upi.TotalViewsOnPosts,
        COALESCE(urc.Edits, 0),
        COALESCE(urc.CloseVotes, 0),
        COALESCE(urc.DeleteVotes, 0),
        COALESCE(urc.CommunityInteractions, 0),
        COALESCE(urc.PostsWithComments, 0),
        u.reputation
)
SELECT
    rua.UserId,
    rua.DisplayName,
    rua.TotalPosts,
    rua.Questions,
    rua.Answers,
    rua.TotalComments,
    rua.UpVotesGiven,
    rua.DownVotesGiven,
    rua.AveragePostScore,
    rua.TotalViewsOnPosts,
    rua.Edits,
    rua.CloseVotes,
    rua.DeleteVotes,
    rua.CommunityInteractions,
    rua.PostsWithComments,
    rua.PostRank,
    rua.ScoreRank,
    (rua.NextReputation - rua.PreviousReputation) AS ReputationDifference,
    CASE
        WHEN rua.LastPostDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1' YEAR) THEN 'Inactive'
        WHEN rua.LastPostDate < (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '3' MONTH) THEN 'Semi-Active'
        ELSE 'Active'
    END AS ActivityStatus,
    CASE
        WHEN rua.TotalPosts > 1000 THEN 'High Volume'
        WHEN rua.TotalPosts > 100 THEN 'Medium Volume'
        ELSE 'Low Volume'
    END AS PostingVolume,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rua.UserId AND b.Class = 1) AS GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rua.UserId AND b.Class = 2) AS SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = rua.UserId AND b.Class = 3) AS BronzeBadges,
    UPPER(SUBSTRING(rua.DisplayName FROM 1 FOR 1)) AS FirstInitial,
    CASE WHEN rua.TotalPosts > 0 AND rua.TotalComments > 0 THEN CAST(rua.TotalComments AS NUMERIC) / rua.TotalPosts ELSE 0 END AS CommentToPostRatio,
    COALESCE(p.Tags, 'No Tags') AS SampleTag,
    CASE
        WHEN rua.Edits > rua.CloseVotes AND rua.Edits > rua.DeleteVotes THEN 'Edit-Heavy'
        WHEN rua.CloseVotes > rua.Edits AND rua.CloseVotes > rua.DeleteVotes THEN 'Close-Vote-Heavy'
        WHEN rua.DeleteVotes > rua.Edits AND rua.DeleteVotes > rua.CloseVotes THEN 'Delete-Vote-Heavy'
        ELSE 'Balanced Activity'
    END AS PrimaryActivityType
FROM RankedUserActivity rua
LEFT JOIN Posts p ON rua.UserId = p.OwnerUserId AND p.PostTypeId = 1 AND p.Id = (
    SELECT MIN(p2.Id) FROM Posts p2 WHERE p2.OwnerUserId = rua.UserId AND p2.PostTypeId = 1
)
LEFT JOIN UserPostInteractions upi ON rua.UserId = upi.UserId
WHERE
    rua.TotalPosts > 10
    AND rua.AveragePostScore IS NOT NULL
    AND (rua.NextReputation - rua.PreviousReputation) BETWEEN -1000 AND 1000
ORDER BY rua.PostRank, rua.DisplayName;