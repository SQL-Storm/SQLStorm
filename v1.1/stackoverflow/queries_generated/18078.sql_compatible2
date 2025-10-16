WITH RECURSIVE UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score END) AS AveragePostScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotes,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS RankByReputation,
        u.AboutMe,
        u.WebsiteUrl
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.AboutMe, u.WebsiteUrl
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        pt.Name AS PostTypeName,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Score AS PostScore,
        COALESCE(c.CommentCountTotal, 0) AS TotalCommentsOnPost,
        COALESCE(ans.AnswerCountTotal, 0) AS TotalAnswersToPost,
        COALESCE(votes.UpVoteCountTotal, 0) AS TotalUpVotesOnPost,
        COALESCE(votes.DownVoteCountTotal, 0) AS TotalDownVotesOnPost,
        COALESCE(ph.EditCount, 0) AS EditHistoryCount,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Active'
        END AS PostStatus,
        ua.RankByReputation AS OwnerRankByReputation,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PreviousPostScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextPostScore,
        CASE
            WHEN p.Score > LAG(p.Score, 1, -1) OVER (ORDER BY p.CreationDate) THEN 'Score Increased'
            WHEN p.Score < LAG(p.Score, 1, -1) OVER (ORDER BY p.CreationDate) THEN 'Score Decreased'
            ELSE 'Score Unchanged'
        END AS ScoreTrend,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostNumber,
        p.OwnerUserId
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCountTotal
        FROM Comments
        GROUP BY PostId
    ) c ON p.Id = c.PostId
    LEFT JOIN (
        SELECT ParentId, COUNT(*) AS AnswerCountTotal
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY ParentId
    ) ans ON p.Id = ans.ParentId
    LEFT JOIN (
        SELECT PostId,
               COUNT(CASE WHEN VoteTypeId = 2 THEN 1 END) AS UpVoteCountTotal,
               COUNT(CASE WHEN VoteTypeId = 3 THEN 1 END) AS DownVoteCountTotal
        FROM Votes
        GROUP BY PostId
    ) votes ON p.Id = votes.PostId
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS EditCount
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
        GROUP BY PostId
    ) ph ON p.Id = ph.PostId
    LEFT JOIN UserActivity ua ON p.OwnerUserId = ua.UserId
)
SELECT
    ua.DisplayName AS UserDisplayName,
    ua.Reputation AS UserReputation,
    ua.RankByReputation AS UserRank,
    pe.Title AS PostTitle,
    pe.PostTypeName,
    pe.PostScore,
    pe.AnswerCount AS DirectAnswerCount,
    pe.TotalAnswersToPost AS TotalAnswersReceived,
    pe.CommentCount AS DirectCommentCount,
    pe.TotalCommentsOnPost AS TotalCommentsReceived,
    pe.FavoriteCount AS BookmarkCount,
    pe.TotalUpVotesOnPost,
    pe.TotalDownVotesOnPost,
    pe.EditHistoryCount,
    pe.PostStatus,
    pe.PostCreationDate,
    ua.LastPostDate,
    ua.AveragePostScore,
    ua.BadgeCount,
    pe.PreviousPostScore,
    pe.NextPostScore,
    pe.ScoreTrend,
    pe.UserPostNumber,
    CASE
        WHEN pe.PostScore > 0 AND pe.TotalUpVotesOnPost > pe.TotalDownVotesOnPost THEN 'Positive Sentiment'
        WHEN pe.PostScore < 0 AND pe.TotalDownVotesOnPost > pe.TotalUpVotesOnPost THEN 'Negative Sentiment'
        WHEN ua.Reputation > 100000 AND pe.PostScore > 500 THEN 'High Impact User, High Score Post'
        WHEN ua.CreationDate < DATE '2010-01-01' AND pe.PostCreationDate < DATE '2011-01-01' THEN 'Early Contributor Activity'
        ELSE 'Standard Activity'
    END AS ActivityCategory,
    LOWER(SUBSTRING(pe.Title FROM 1 FOR 3)) AS FirstThreeCharsOfTitle,
    CASE WHEN ua.DisplayName ~ '[^a-zA-Z0-9 ]' THEN 'Contains Special Chars' ELSE 'Alphanumeric Only' END AS DisplayNameCharType,
    COALESCE(ua.UpVotes, 0) AS UserTotalUpvotes,
    COALESCE(ua.DownVotes, 0) AS UserTotalDownvotes,
    (COALESCE(ua.UpVotes, 0) - COALESCE(ua.DownVotes, 0)) AS UserNetVotes,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM PostLinks pl
            WHERE pl.PostId = pe.PostId AND pl.LinkTypeId = 3
        ) THEN 'IsDuplicateLink'
        ELSE 'NotDuplicateLink'
    END AS DuplicateLinkStatus,
    COALESCE(LENGTH(COALESCE(ua.AboutMe, '')), 0) AS AboutMeLength,
    CASE
        WHEN ua.WebsiteUrl IS NULL OR ua.WebsiteUrl = '' THEN 'No Website'
        WHEN ua.WebsiteUrl LIKE '%stackoverflow.com%' THEN 'Stack Overflow Site'
        ELSE 'External Website'
    END AS WebsiteCategory,
    (COALESCE(ua.TotalPosts, 0) + COALESCE(ua.QuestionCount, 0) + COALESCE(ua.AnswerCount, 0)) AS CombinedPostCount,
    ua.CreationDate AS UserCreationDate,
    (pe.PostTypeName || '_' || pe.PostStatus) AS CompositeKey,
    ua.UserId,
    pe.OwnerUserId
FROM UserActivity ua
FULL OUTER JOIN PostEngagement pe
    ON ua.UserId = pe.OwnerUserId
WHERE ua.Reputation > 100
GROUP BY
    ua.DisplayName,
    ua.Reputation,
    ua.RankByReputation,
    pe.Title,
    pe.PostTypeName,
    pe.PostScore,
    pe.AnswerCount,
    pe.TotalAnswersToPost,
    pe.CommentCount,
    pe.TotalCommentsOnPost,
    pe.FavoriteCount,
    pe.TotalUpVotesOnPost,
    pe.TotalDownVotesOnPost,
    pe.EditHistoryCount,
    pe.PostStatus,
    pe.PostCreationDate,
    ua.LastPostDate,
    ua.AveragePostScore,
    ua.BadgeCount,
    pe.PreviousPostScore,
    pe.NextPostScore,
    pe.ScoreTrend,
    pe.UserPostNumber,
    pe.PostId,
    ua.CreationDate,
    ua.UpVotes,
    ua.DownVotes,
    ua.AboutMe,
    ua.WebsiteUrl,
    ua.TotalPosts,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.UserId,
    pe.OwnerUserId
ORDER BY ua.Reputation DESC NULLS LAST, pe.PostScore DESC NULLS LAST
LIMIT 1000;