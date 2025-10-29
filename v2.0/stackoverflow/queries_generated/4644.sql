-- {"query": "4644.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1091} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS AnswerCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.Id > 0 -- Exclude community user for this analysis
    GROUP BY u.Id, u.DisplayName
),
PostEngagement AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        pt.Name AS PostType,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountOnPost,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVotesOnPost,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownVotesOnPost,
        ROW_NUMBER() OVER(PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreAndViews
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.PostTypeId IN (1, 2) -- Questions and Answers only
),
UserPostSummary AS (
    SELECT
        ua.UserId,
        ua.DisplayName,
        ua.TotalPosts,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.UpVoteCount,
        ua.DownVoteCount,
        CASE
            WHEN ua.TotalPosts > 1000 THEN 'Prolific'
            WHEN ua.TotalPosts > 100 THEN 'Active'
            WHEN ua.TotalPosts > 10 THEN 'Regular'
            ELSE 'Newbie'
        END AS ActivityLevel,
        COALESCE(Users.CreationDate, '1970-01-01') AS UserCreationDate -- Handle potential NULL CreationDate
    FROM UserActivity ua
    LEFT JOIN Users ON ua.UserId = Users.Id
)
SELECT
    ups.UserId,
    ups.DisplayName,
    ups.ActivityLevel,
    ups.UserCreationDate,
    ups.TotalPosts,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.CommentCount,
    ups.UpVoteCount AS UserUpVotes,
    ups.DownVoteCount AS UserDownVotes,
    pe.PostId,
    pe.Title,
    pe.PostType,
    pe.CreationDate AS PostCreationDate,
    pe.Score AS PostScore,
    pe.ViewCount AS PostViewCount,
    pe.FavoriteCount AS PostFavoriteCount,
    pe.CommentCountOnPost,
    pe.UpVotesOnPost,
    pe.DownVotesOnPost,
    pe.RankByScoreAndViews,
    CASE
        WHEN pe.Score > 100 THEN 'High Score'
        WHEN pe.Score > 20 THEN 'Medium Score'
        ELSE 'Low Score'
    END AS ScoreCategory,
    IIF(pe.ViewCount > (SELECT AVG(ViewCount) FROM PostEngagement WHERE PostTypeId = pe.PostTypeId), 'Above Average Views', 'Below Average Views') AS ViewCategory,
    COALESCE(pht.Id, -1) AS LastEditHistoryTypeId, -- Use -1 for NULL
    pht.Comment AS LastEditComment
FROM UserPostSummary ups
JOIN PostEngagement pe ON ups.UserId = (SELECT OwnerUserId FROM Posts WHERE Id = pe.PostId) -- Correlated subquery to get owner
LEFT JOIN PostHistory pht ON pe.PostId = pht.PostId AND pht.PostHistoryTypeId = 5 -- Edit Body
WHERE ups.TotalPosts > 5 -- Filter for users with more than 5 posts
AND pe.RankByScoreAndViews <= 10 -- Top 10 posts by score/views for each user
ORDER BY ups.UserId, pe.RankByScoreAndViews;