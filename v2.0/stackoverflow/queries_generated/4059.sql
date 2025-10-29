-- {"query": "4059.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1159} 
WITH RankedUserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS ReputationRank,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.DisplayName IS NOT NULL AND u.DisplayName <> ''
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CommentCount,
        p.FavoriteCount,
        pt.Name AS PostType,
        COUNT(c.Id) AS CommenterCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicateLinkCount,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
    WHERE p.Title IS NOT NULL AND p.Title <> '' AND p.Score > 0
    GROUP BY p.Id, p.Title, p.Score, p.CommentCount, p.FavoriteCount, pt.Name, p.ClosedDate
),
UserPostSummary AS (
    SELECT
        rua.UserId,
        rua.DisplayName,
        rua.Reputation,
        rua.ReputationRank,
        rua.PostCount,
        rua.QuestionCount,
        rua.AnswerCount,
        rua.BadgeCount,
        rua.LastPostActivity,
        SUM(pe.Score) AS TotalScoreReceived,
        AVG(pe.CommentCount) AS AvgCommentCount,
        SUM(pe.UpVoteCount) AS TotalUpvotesReceived,
        SUM(pe.DownVoteCount) AS TotalDownvotesReceived,
        COUNT(CASE WHEN pe.IsClosed = 1 THEN pe.PostId ELSE NULL END) AS ClosedPostCount,
        SUM(pe.DuplicateLinkCount) AS TotalDuplicateLinks
    FROM RankedUserActivity rua
    LEFT JOIN PostEngagement pe ON rua.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pe.PostId)
    WHERE rua.ReputationRank <= 1000
    GROUP BY rua.UserId, rua.DisplayName, rua.Reputation, rua.ReputationRank, rua.PostCount, rua.QuestionCount, rua.AnswerCount, rua.BadgeCount, rua.LastPostActivity
)
SELECT
    ups.DisplayName,
    ups.Reputation,
    ups.ReputationRank,
    ups.PostCount,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.BadgeCount,
    ups.LastPostActivity,
    ups.TotalScoreReceived,
    ups.AvgCommentCount,
    ups.TotalUpvotesReceived,
    ups.TotalDownvotesReceived,
    ups.ClosedPostCount,
    ups.TotalDuplicateLinks,
    (SELECT COUNT(*) FROM Users WHERE DownVotes > UpVotes * 2) AS UsersWithDisproportionateDownvotes,
    (SELECT AVG(DATEDIFF(day, CreationDate, LastAccessDate)) FROM Users WHERE AccountId IS NULL) AS AvgDaysBetweenCreationAndLastAccessForNoAccountId,
    (
        SELECT TOP 1
            CONCAT(pt.Name, ' - ', COUNT(*))
        FROM Posts p
        JOIN PostTypes pt ON p.PostTypeId = pt.Id
        GROUP BY pt.Name
        ORDER BY COUNT(*) DESC
    ) AS MostFrequentPostType,
    CASE
        WHEN ups.TotalScoreReceived > (SELECT AVG(TotalScoreReceived) FROM UserPostSummary) THEN 'Above Average'
        WHEN ups.TotalScoreReceived < (SELECT AVG(TotalScoreReceived) FROM UserPostSummary) THEN 'Below Average'
        ELSE 'Average'
    END AS ScorePerformanceCategory,
    COALESCE(ups.TotalDuplicateLinks, 0) AS NonNullDuplicateLinks
FROM UserPostSummary ups
WHERE ups.PostCount > 50
ORDER BY ups.Reputation DESC, ups.TotalScoreReceived DESC
LIMIT 100;