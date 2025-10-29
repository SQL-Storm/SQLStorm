-- {"query": "4729.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1599} 

WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Views,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(CASE WHEN p.Score IS NOT NULL THEN CAST(p.Score AS REAL) ELSE 0 END) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS ReputationRank,
        DENSE_RANK() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.LastAccessDate DESC) AS LocationAccessRank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.Id > 0 AND u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UserUpVotes, u.UserDownVotes, u.Location, u.LastAccessDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.CommentCount,
        p.FavoriteCount,
        COUNT(c.Id) AS CommentCountOnPost,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
        SUM(CASE WHEN p.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS IsAcceptedAnswer,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2) AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.Id, p.Title, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.CommentCount, p.FavoriteCount, p.AcceptedAnswerId
),
UserPostSummary AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.CreationDate,
        rua.Views,
        rua.UserUpVotes,
        rua.UserDownVotes,
        rua.PostCount,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.AvgPostScore,
        rua.LastPostDate,
        rua.ReputationRank,
        rua.LocationAccessRank,
        SUM(pe.PostScore) AS TotalPostScore,
        AVG(pe.PostViewCount) AS AvgPostViewCount,
        COUNT(pe.PostId) FILTER (WHERE pe.CommentCountOnPost > 0) AS PostsWithComments,
        COUNT(pe.PostId) FILTER (WHERE pe.UpVoteCount > 5) AS PostsWithManyUpvotes,
        COUNT(pe.PostId) FILTER (WHERE pe.DuplicateLinkCount > 0) AS PostsLinkedAsDuplicate
    FROM RankedUserActivity rua
    LEFT JOIN PostEngagement pe ON rua.UserId = pe.OwnerUserId
    GROUP BY
        rua.UserId, rua.DisplayName, rua.Reputation, rua.CreationDate, rua.Views, rua.UserUpVotes, rua.UserDownVotes, rua.PostCount, rua.QuestionCount, rua.AnswerCount, rua.AvgPostScore, rua.LastPostDate, rua.ReputationRank, rua.LocationAccessRank
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.Reputation,
    ups.CreationDate,
    ups.Views,
    ups.UserUpVotes,
    ups.UserDownVotes,
    ups.PostCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.AvgPostScore,
    ups.LastPostDate,
    ups.ReputationRank,
    ups.LocationAccessRank,
    ups.TotalPostScore,
    ups.AvgPostViewCount,
    ups.PostsWithComments,
    ups.PostsWithManyUpvotes,
    ups.PostsLinkedAsDuplicate,
    CASE
        WHEN ups.ReputationRank <= 100 THEN 'Top 100'
        WHEN ups.ReputationRank <= 1000 THEN 'Top 1000'
        ELSE 'Other'
    END AS ReputationTier,
    COALESCE(u.Location, 'N/A') AS UserLocation,
    CASE
        WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN 'Has Website'
        ELSE 'No Website'
    END AS WebsiteStatus,
    UPPER(SUBSTRING(COALESCE(u.AboutMe, ''), 1, 30)) AS AbbreviatedAboutMe,
    (
        SELECT COUNT(*)
        FROM Badges b
        WHERE b.UserId = ups.UserId AND b.Class = 1
    ) AS GoldBadgeCount,
    (
        SELECT COUNT(*)
        FROM PostHistory ph
        WHERE ph.UserId = ups.UserId AND ph.PostHistoryTypeId IN (5, 8) -- Edit Body, Rollback Body
    ) AS BodyEditHistoryCount,
    CASE WHEN ups.PostsLinkedAsDuplicate > 0 THEN 'Has Duplicate Links' ELSE 'No Duplicate Links' END AS DuplicateLinkStatus,
    CASE WHEN ups.AvgPostScore > 50 THEN 'High Average Score' ELSE 'Moderate Average Score' END AS ScoreCategory,
    u.EmailHash AS UserEmailHash,
    CASE WHEN u.AccountId IS NULL THEN 'No Account ID' ELSE 'Has Account ID' END AS AccountStatus,
    pht.Name AS LastPostHistoryTypeName
FROM UserPostSummary ups
JOIN Users u ON ups.UserId = u.Id
LEFT JOIN PostHistory ph_last ON u.Id = ph_last.UserId
LEFT JOIN PostHistoryTypes pht ON ph_last.PostHistoryTypeId = pht.Id AND ph_last.CreationDate = (SELECT MAX(CreationDate) FROM PostHistory WHERE UserId = u.Id)
WHERE ups.PostCount > 10
ORDER BY ups.Reputation DESC, ups.Views DESC
LIMIT 1000;
