
WITH RankedUsers AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        @row_number := IF(@prev_reputation = u.Reputation, @row_number, @row_number + 1) AS UserRank,
        @prev_reputation := u.Reputation
    FROM Users u, (SELECT @row_number := 0, @prev_reputation := NULL) AS vars
    ORDER BY u.Reputation DESC
),
PopularPosts AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.ViewCount,
        COUNT(c.Id) AS CommentCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    WHERE p.PostTypeId = 1 /* Questions only */
    GROUP BY p.Id, p.Title, p.Score, p.CreationDate, p.ViewCount
),
MostDiscussedPosts AS (
    SELECT 
        pp.PostId,
        pp.Title,
        pp.Score,
        pp.CreationDate,
        pp.ViewCount,
        pp.CommentCount,
        @discussion_rank := IF(@prev_comment_count = pp.CommentCount, @discussion_rank, @discussion_rank + 1) AS DiscussionRank,
        @prev_comment_count := pp.CommentCount
    FROM PopularPosts pp, (SELECT @discussion_rank := 0, @prev_comment_count := NULL) AS vars
    ORDER BY pp.CommentCount DESC
)
SELECT 
    ru.DisplayName,
    ru.Reputation,
    pp.Title AS MostDiscussedPostTitle,
    pp.Score AS PostScore,
    pp.ViewCount AS PostViewCount,
    pp.CommentCount AS TotalComments,
    pp.CreationDate AS PostCreationDate,
    pp.DiscussionRank
FROM RankedUsers ru
JOIN MostDiscussedPosts pp ON ru.UserId = pp.PostId
WHERE ru.UserRank <= 10 /* Top 10 users by reputation */
ORDER BY pp.DiscussionRank
