-- {"query": "4158.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1465} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY DATE_PART('year', u.CreationDate) ORDER BY u.Reputation DESC) AS YearlyReputationRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PreviousUserReputation
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCountActual,
        SUM(CASE WHEN cp.VoteTypeId = 2 THEN 1 ELSE 0 END) AS PostUpVotes,
        SUM(CASE WHEN cp.VoteTypeId = 3 THEN 1 ELSE 0 END) AS PostDownVotes,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS UserPostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes cp ON p.Id = cp.PostId
    WHERE p.Title IS NOT NULL AND LENGTH(p.Title) > 5
    GROUP BY p.Id, p.Title, p.PostTypeId, pt.Name, p.OwnerUserId, p.CreationDate, p.Score, p.CommentCount, p.FavoriteCount, p.AnswerCount, p.ClosedDate, p.CommunityOwnedDate, p.LastActivityDate
),
RecentQuestions AS (
    SELECT
        pe.PostId,
        pe.Title,
        pe.OwnerUserId,
        pe.PostCreationDate,
        pe.Score,
        pe.PostUpVotes,
        pe.PostDownVotes,
        pe.CommentCountActual,
        pe.AnswerCount,
        pe.PostStatus,
        rua.DisplayName AS OwnerDisplayName,
        rua.Reputation AS OwnerReputation,
        ROW_NUMBER() OVER (ORDER BY pe.PostCreationDate DESC) AS RecentQuestionRank
    FROM PostEngagement pe
    JOIN RankedUserActivity rua ON pe.OwnerUserId = rua.UserId
    WHERE pe.PostTypeId = 1 AND pe.PostStatus = 'Open' AND pe.PostCreationDate > NOW() - INTERVAL '30 days'
)
SELECT
    'Performance Benchmark Query' AS QueryDescription,
    rq.RecentQuestionRank,
    rq.Title AS QuestionTitle,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.PostCreationDate,
    rq.Score AS QuestionScore,
    rq.PostUpVotes AS QuestionUpVotes,
    rq.PostDownVotes AS QuestionDownVotes,
    rq.CommentCountActual AS QuestionCommentCount,
    rq.AnswerCount AS QuestionAnswerCount,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = rq.PostId AND pl.LinkTypeId = 3 -- Duplicate links
    ) AS DuplicateLinksCount,
    (
        SELECT TOP 1 v.CreationDate
        FROM Votes v
        WHERE v.PostId = rq.PostId AND v.VoteTypeId = 8 -- BountyStart
        ORDER BY v.CreationDate DESC
    ) AS LastBountyDate,
    CASE
        WHEN rq.OwnerReputation > 10000 THEN 'High Reputation'
        WHEN rq.OwnerReputation > 1000 THEN 'Medium Reputation'
        ELSE 'Low Reputation'
    END AS ReputationTier,
    (
        SELECT STRING_AGG(Name, ', ')
        FROM Badges b
        WHERE b.UserId = rq.OwnerUserId AND b.Class = 1 AND b.TagBased = 0 -- Gold named badges
    ) AS TopBadges,
    (
        SELECT pt2.Name
        FROM PostHistory ph
        JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        JOIN PostTypes pt2 ON ph.PostTypeId = pt2.Id -- Rejoining PostTypes for clarity on history post type
        WHERE ph.PostId = rq.PostId
          AND ph.PostHistoryTypeId = 1 -- Initial Title
        ORDER BY ph.CreationDate ASC
        LIMIT 1
    ) AS OriginalPostTypeForHistory,
    'User joined on ' || TO_CHAR(rua.UserCreationDate, 'YYYY-MM-DD') AS UserJoinDate,
    COALESCE(rq.Score, 0) + COALESCE(rq.PostUpVotes, 0) - COALESCE(rq.PostDownVotes, 0) AS NetScore,
    CASE WHEN rq.OwnerReputation BETWEEN 500 AND 5000 THEN 'Mid-Tier User' ELSE 'Other Tier' END AS CustomUserSegment
FROM RecentQuestions rq
LEFT JOIN RankedUserActivity rua ON rq.OwnerUserId = rua.UserId
LEFT JOIN PostEngagement pe_alias ON rq.PostId = pe_alias.PostId -- Alias for potential self-join or multiple uses
WHERE rq.OwnerReputation > 100 AND rq.AnswerCount > 0
ORDER BY rq.RecentQuestionRank;
