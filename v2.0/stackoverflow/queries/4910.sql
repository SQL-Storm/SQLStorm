-- {"query": "4910.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2259}
WITH PostEngagement AS (
    SELECT
        p.Id AS PostId,
        pt.Name AS PostType,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.FavoriteCount AS PostFavoriteCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.ClosedDate, DATE '1900-01-01') AS ClosedDate,
        p.CommunityOwnedDate,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.CreationDate > p.CreationDate) AS CommentCountAfterCreation,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2 AND v.CreationDate > p.CreationDate) AS UpVoteCountAfterCreation,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6) AND ph.CreationDate > p.CreationDate) AS EditCountAfterCreation,
        ROW_NUMBER() OVER(PARTITION BY p.OwnerUserId ORDER BY p.LastActivityDate DESC) AS UserPostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1,2)
      AND p.Score > -5
      AND p.CreationDate > DATE '2020-01-01'
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        u.CreationDate AS UserCreationDate,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgeCount,
        (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgeCount,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId = 2) AS InitialBodyEdits,
        (SELECT COUNT(DISTINCT PostId) FROM Comments c WHERE c.UserId = u.Id) AS CommentedPostsCount,
        (SELECT COUNT(DISTINCT PostId) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) AS UpVotedPostsCount,
        CASE WHEN u.WebsiteUrl IS NULL THEN 'No Website' ELSE 'Has Website' END AS WebsiteStatus
    FROM Users u
    WHERE u.Id > 0
),
LaggedScores AS (
    SELECT
        pe.PostId,
        pe.PostScore,
        LAG(pe.PostScore, 1, 0) OVER (PARTITION BY pe.OwnerUserId ORDER BY pe.PostCreationDate) AS PreviousPostScore,
        pe.PostCreationDate,
        pe.OwnerUserId,
        pe.UserPostRank
    FROM PostEngagement pe
    WHERE pe.OwnerUserId IS NOT NULL
)
SELECT
    pe.PostId,
    pe.PostType,
    pe.OwnerDisplayName,
    pe.PostCreationDate,
    pe.PostScore,
    pe.PostViewCount,
    pe.PostFavoriteCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.CommentCountAfterCreation,
    pe.UpVoteCountAfterCreation,
    pe.EditCountAfterCreation,
    pe.ClosedDate,
    CASE
        WHEN pe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN pe.PostScore > 1000 THEN 'High Score'
        WHEN pe.AnswerCount > 10 THEN 'Many Answers'
        ELSE 'Standard'
    END AS PostStatusCategory,
    uas.UserDisplayName AS UserInfoDisplayName,
    uas.Reputation,
    uas.GoldBadgeCount,
    uas.SilverBadgeCount,
    uas.BronzeBadgeCount,
    uas.UserViews,
    uas.UserUpVotes,
    uas.UserDownVotes,
    uas.UserCreationDate,
    uas.InitialBodyEdits,
    uas.CommentedPostsCount,
    uas.UpVotedPostsCount,
    ls.PreviousPostScore,
    ls.PostScore - ls.PreviousPostScore AS ScoreDifferenceFromPrevious,
    (ls.PostScore - ls.PreviousPostScore) * 1.0 / NULLIF(ls.PreviousPostScore, 0) AS RelativeScoreChange,
    CASE
        WHEN LOWER(pe.OwnerDisplayName) LIKE '%john%' THEN 'Contains John'
        WHEN LOWER(pe.OwnerDisplayName) LIKE '%doe%' THEN 'Contains Doe'
        ELSE 'Other Name Pattern'
    END AS OwnerNamePattern,
    CONCAT(
        SUBSTRING(CAST(pe.PostCreationDate AS VARCHAR), 1, 4),
        '-',
        SUBSTRING(CAST(pe.PostCreationDate AS VARCHAR), 6, 2),
        '-',
        SUBSTRING(CAST(pe.PostCreationDate AS VARCHAR), 9, 2)
    ) AS PostCreationDateString,
    CASE
        WHEN pe.ClosedDate <> DATE '1900-01-01' AND uas.Reputation > 10000 THEN 'Closed by High Rep User'
        WHEN pe.ClosedDate <> DATE '1900-01-01' THEN 'Closed'
        WHEN pe.PostScore > 50 AND pe.AnswerCount > 5 THEN 'Popular'
        ELSE 'Less Popular'
    END AS EngagementTier,
    GREATEST(pe.AnswerCount, pe.CommentCount) AS MaxInteractionCount
FROM PostEngagement pe
LEFT JOIN UserActivitySummary uas ON pe.OwnerUserId = uas.UserId
LEFT JOIN LaggedScores ls ON pe.PostId = ls.PostId AND pe.OwnerUserId = ls.OwnerUserId AND pe.UserPostRank = ls.UserPostRank
WHERE (pe.PostScore > 0 OR pe.AnswerCount > 0 OR pe.CommentCount > 0)
   OR uas.Reputation > 5000

UNION ALL

SELECT
    pe.PostId,
    pe.PostType,
    pe.OwnerDisplayName,
    pe.PostCreationDate,
    pe.PostScore,
    pe.PostViewCount,
    pe.PostFavoriteCount,
    pe.AnswerCount,
    pe.CommentCount,
    pe.CommentCountAfterCreation,
    pe.UpVoteCountAfterCreation,
    pe.EditCountAfterCreation,
    pe.ClosedDate,
    CASE
        WHEN pe.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN pe.PostScore > 1000 THEN 'High Score'
        WHEN pe.AnswerCount > 10 THEN 'Many Answers'
        ELSE 'Standard'
    END AS PostStatusCategory,
    uas.UserDisplayName AS UserInfoDisplayName,
    uas.Reputation,
    uas.GoldBadgeCount,
    uas.SilverBadgeCount,
    uas.BronzeBadgeCount,
    uas.UserViews,
    uas.UserUpVotes,
    uas.UserDownVotes,
    uas.UserCreationDate,
    uas.InitialBodyEdits,
    uas.CommentedPostsCount,
    uas.UpVotedPostsCount,
    ls.PreviousPostScore,
    ls.PostScore - ls.PreviousPostScore AS ScoreDifferenceFromPrevious,
    (ls.PostScore - ls.PreviousPostScore) * 1.0 / NULLIF(ls.PreviousPostScore, 0) AS RelativeScoreChange,
    CASE
        WHEN LOWER(pe.OwnerDisplayName) LIKE '%alice%' THEN 'Contains Alice'
        WHEN LOWER(pe.OwnerDisplayName) LIKE '%smith%' THEN 'Contains Smith'
        ELSE 'Other Name Pattern'
    END AS OwnerNamePattern,
    CONCAT(
        SUBSTRING(CAST(pe.PostCreationDate AS VARCHAR), 1, 4),
        '-',
        SUBSTRING(CAST(pe.PostCreationDate AS VARCHAR), 6, 2),
        '-',
        SUBSTRING(CAST(pe.PostCreationDate AS VARCHAR), 9, 2)
    ) AS PostCreationDateString,
    CASE
        WHEN pe.ClosedDate <> DATE '1900-01-01' AND uas.Reputation > 10000 THEN 'Closed by High Rep User'
        WHEN pe.ClosedDate <> DATE '1900-01-01' THEN 'Closed'
        WHEN pe.PostScore > 50 AND pe.AnswerCount > 5 THEN 'Popular'
        ELSE 'Less Popular'
    END AS EngagementTier,
    GREATEST(pe.AnswerCount, pe.CommentCount) AS MaxInteractionCount
FROM PostEngagement pe
JOIN UserActivitySummary uas ON pe.OwnerUserId = uas.UserId
JOIN LaggedScores ls ON pe.PostId = ls.PostId AND pe.OwnerUserId = ls.OwnerUserId AND pe.UserPostRank = ls.UserPostRank
WHERE (pe.PostScore < 0 AND pe.AnswerCount = 0)
   AND uas.Reputation < 5000
ORDER BY PostCreationDate DESC
LIMIT 1000;