-- {"query": "48041.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 788} 
WITH PostInteraction AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT ph.Id) AS HistoryCount,
        COUNT(DISTINCT pl.Id) AS LinkCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId
    GROUP BY
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT pi.PostId) AS PostsCreated,
        SUM(CASE WHEN pi.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN pi.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        SUM(pi.VoteCount) AS TotalVotesReceivedOnPosts,
        SUM(pi.CommentCount) AS TotalCommentsOnPosts,
        SUM(pi.HistoryCount) AS TotalEditsByOthers,
        SUM(pi.LinkCount) AS TotalLinksInvolvingPosts
    FROM Users u
    JOIN PostInteraction pi ON u.Id = pi.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id,
        u.Reputation,
        u.CreationDate
)
SELECT
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostsCreated,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.BadgesEarned,
    ua.TotalVotesReceivedOnPosts,
    ua.TotalCommentsOnPosts,
    ua.TotalEditsByOthers,
    ua.TotalLinksInvolvingPosts,
    AVG(pi.VoteCount) AS AvgVotesPerPost,
    AVG(pi.CommentCount) AS AvgCommentsPerPost,
    AVG(pi.HistoryCount) AS AvgHistoryEntriesPerPost,
    AVG(pi.LinkCount) AS AvgLinksPerPost,
    COUNT(DISTINCT pi.PostId) AS TotalPostsInteractedWith
FROM UserActivity ua
JOIN PostInteraction pi ON ua.UserId = pi.OwnerUserId
GROUP BY
    ua.UserId,
    ua.Reputation,
    ua.UserCreationDate,
    ua.PostsCreated,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.BadgesEarned,
    ua.TotalVotesReceivedOnPosts,
    ua.TotalCommentsOnPosts,
    ua.TotalEditsByOthers,
    ua.TotalLinksInvolvingPosts
HAVING
    ua.PostsCreated > 10 AND ua.Reputation > 1000
ORDER BY
    ua.Reputation DESC,
    ua.UserCreationDate ASC,
    TotalPostsInteractedWith DESC
LIMIT 100;