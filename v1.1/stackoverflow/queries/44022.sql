-- {"query": "44022.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "claude-3-haiku", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 50468, "output_tokens": 20175} 
WITH cte AS (
    SELECT 
        p.Id, 
        p.PostTypeId, 
        p.CreationDate, 
        p.Score, 
        p.AnswerCount, 
        p.CommentCount, 
        p.FavoriteCount, 
        u.Reputation, 
        u.Views, 
        u.UpVotes, 
        u.DownVotes,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostType,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS PostStatus
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
)
SELECT
    PostType,
    PostStatus,
    AVG(Score) AS AvgScore,
    AVG(AnswerCount) AS AvgAnswers,
    AVG(CommentCount) AS AvgComments,
    AVG(FavoriteCount) AS AvgFavorites,
    AVG(Reputation) AS AvgReputation,
    AVG(Views) AS AvgViews,
    AVG(UpVotes) AS AvgUpvotes,
    AVG(DownVotes) AS AvgDownvotes,
    COUNT(*) AS TotalPosts
FROM cte
GROUP BY PostType, PostStatus
ORDER BY TotalPosts DESC;