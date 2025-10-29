-- {"query": "4822.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1844}
WITH RankedUserVotes AS (
    SELECT
        v.UserId,
        v.PostId,
        v.VoteTypeId,
        ROW_NUMBER() OVER(PARTITION BY v.UserId ORDER BY v.CreationDate DESC) AS vote_rank
    FROM Votes v
    WHERE v.VoteTypeId IN (2, 3)
),
PostVoteSummary AS (
    SELECT
        p.Id AS PostId,
        COUNT(CASE WHEN r.VoteTypeId = 2 THEN 1 END) AS UpVoteCount,
        COUNT(CASE WHEN r.VoteTypeId = 3 THEN 1 END) AS DownVoteCount,
        SUM(CASE WHEN r.VoteTypeId = 2 THEN 1 ELSE -1 END) AS NetVoteScore
    FROM Posts p
    LEFT JOIN RankedUserVotes r ON p.Id = r.PostId
    GROUP BY p.Id
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT ph.PostId) AS PostHistoryCount,
        MAX(ph.CreationDate) AS LastPostHistoryDate,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM Users u
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
CTE_PostDetails AS (
    SELECT
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.CommunityOwnedDate,
        pvs.UpVoteCount,
        pvs.DownVoteCount,
        pvs.NetVoteScore,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        LOWER(REPLACE(REPLACE(REPLACE(p.Tags, '><', '|'), '<', ''), '>', '')) AS FormattedTags,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Yes' ELSE 'No' END AS HasAcceptedAnswer
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN PostVoteSummary pvs ON p.Id = pvs.PostId
    WHERE p.PostTypeId IN (1, 2)
),
UserContributionAnalysis AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.UserCreationDate,
        ua.PostHistoryCount,
        ua.LastPostHistoryDate,
        ua.QuestionCount,
        ua.AnswerCount,
        COALESCE(SUM(CASE WHEN cp.PostTypeId = 1 THEN cp.NetVoteScore ELSE 0 END), 0) AS TotalQuestionNetScore,
        COALESCE(SUM(CASE WHEN cp.PostTypeId = 2 THEN cp.NetVoteScore ELSE 0 END), 0) AS TotalAnswerNetScore,
        COALESCE(AVG(CASE WHEN cp.PostTypeId = 1 THEN cp.UpVoteCount ELSE NULL END), 0) AS AvgQuestionUpvotes,
        COALESCE(AVG(CASE WHEN cp.PostTypeId = 2 THEN cp.DownVoteCount ELSE NULL END), 0) AS AvgAnswerDownvotes,
        COALESCE(SUM(CASE WHEN cp.HasAcceptedAnswer = 'Yes' THEN 1 ELSE 0 END), 0) AS AcceptedAnswersCount,
        COUNT(DISTINCT cp.Id) AS TotalPostsContributed,
        RANK() OVER (ORDER BY ua.Reputation DESC, ua.UserCreationDate ASC) AS UserRankByReputation
    FROM UserActivity ua
    LEFT JOIN CTE_PostDetails cp ON ua.UserId = cp.OwnerUserId
    GROUP BY ua.UserId, ua.DisplayName, ua.Reputation, ua.UserCreationDate, ua.PostHistoryCount, ua.LastPostHistoryDate, ua.QuestionCount, ua.AnswerCount
)
SELECT
    MAX(COALESCE(ucp.TotalQuestionNetScore, 0)) AS MaxTotalQuestionNetScore,
    MIN(COALESCE(ucp.AvgAnswerDownvotes, 0)) AS MinAvgAnswerDownvotes,
    AVG(ucp.AcceptedAnswersCount) AS AvgAcceptedAnswers,
    SUM(ucp.PostHistoryCount) AS TotalPostHistoryEntriesAcrossAllUsers,
    COUNT(DISTINCT ucp.UserId) AS DistinctUsersAnalyzed,
    SUM(CASE WHEN ucp.Reputation > 50000 THEN 1 ELSE 0 END) AS EliteUsersCount,
    SUM(CASE WHEN ucp.TotalPostsContributed > 1000 THEN 1 ELSE 0 END) AS PowerUsersCount,
    (SELECT COUNT(*) FROM PostLinks WHERE LinkTypeId = 3) AS TotalDuplicateLinks,
    (SELECT COUNT(DISTINCT UserId) FROM Badges WHERE Name LIKE '%_Master' AND Class = 1) AS GoldBadgeMastersCount,
    (
        SELECT COUNT(DISTINCT p.Id)
        FROM Posts p
        JOIN Comments c ON p.Id = c.PostId
        WHERE c.Score > 10
        AND p.Score < 0
        AND p.PostTypeId = 1
        AND p.CreationDate < (cast('2024-10-01' as date) - INTERVAL '1 year')
    ) AS OldPostsWithLowScoreButHighCommentScore,
    (
        SELECT COUNT(DISTINCT ph.PostId)
        FROM PostHistory ph
        WHERE ph.PostHistoryTypeId IN (4, 5)
        AND ph.UserId IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM Users u
            WHERE u.Id = ph.UserId
            AND u.DownVotes > 1000
        )
    ) AS EditsByUsersWithManyDownvotes,
    MAX(ucp.UserRankByReputation) AS HighestUserRank,
    (
        SELECT COUNT(DISTINCT p.Id)
        FROM Posts p
        WHERE (p.Title IS NULL OR TRIM(p.Title) = '')
        AND p.PostTypeId = 1
    ) AS QuestionsWithNullOrEmptyTitle,
    SUM(CASE WHEN ucp.UserCreationDate < (cast('2024-10-01' as date) - INTERVAL '5 years') AND ucp.AnswerCount > 1000 THEN 1 ELSE 0 END) AS OldHighVolumeAnswerers,
    (
        SELECT COUNT(DISTINCT p.Id)
        FROM Posts p
        LEFT JOIN PostLinks pl ON p.Id = pl.PostId
        WHERE pl.Id IS NULL
        AND p.PostTypeId = 1
        AND p.CreationDate < (cast('2024-10-01' as date) - INTERVAL '3 years')
        AND p.AnswerCount = 0
        AND p.CommentCount = 0
    ) AS UnlinkedOldQuestionsWithNoAnswersOrComments,
    AVG(ucp.Reputation) AS AverageUserReputation
FROM UserContributionAnalysis ucp
WHERE ucp.Reputation > 0
GROUP BY ucp.UserId, ucp.DisplayName, ucp.Reputation, ucp.UserCreationDate, ucp.PostHistoryCount, ucp.LastPostHistoryDate, ucp.QuestionCount, ucp.AnswerCount, ucp.TotalQuestionNetScore, ucp.TotalAnswerNetScore, ucp.AvgQuestionUpvotes, ucp.AvgAnswerDownvotes, ucp.AcceptedAnswersCount, ucp.TotalPostsContributed, ucp.UserRankByReputation
HAVING ucp.AnswerCount > 0 OR ucp.QuestionCount > 0;