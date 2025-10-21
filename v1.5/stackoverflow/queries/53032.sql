-- {"query": "53032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 932} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsPosted,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersPosted,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
CommentStats AS (
    SELECT 
        UserId,
        COUNT(Id) AS TotalComments,
        AVG(Score) AS AverageCommentScore
    FROM Comments
    GROUP BY UserId
),
VoteStats AS (
    SELECT 
        UserId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM Votes
    WHERE UserId IS NOT NULL
    GROUP BY UserId
),
EditStats AS (
    SELECT 
        UserId,
        COUNT(Id) AS TotalEdits,
        COUNT(DISTINCT PostId) AS UniquePostsEdited
    FROM PostHistory
    WHERE PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
    GROUP BY UserId
),
TopTags AS (
    SELECT 
        pp.OwnerUserId AS UserId,
        t.TagName,
        COUNT(*) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY pp.OwnerUserId ORDER BY COUNT(*) DESC) AS TagRank
    FROM Posts pp
    CROSS JOIN LATERAL UNNEST(string_to_array(substring(pp.Tags, 2, length(pp.Tags) - 2), '><')) AS tag
    JOIN Tags t ON t.TagName = tag
    WHERE pp.PostTypeId = 1
    GROUP BY pp.OwnerUserId, t.TagName
),
AggregatedTags AS (
    SELECT 
        UserId,
        STRING_AGG(TagName || ' (' || TagCount || ')', ', ' ORDER BY TagCount DESC) AS Top5Tags
    FROM TopTags
    WHERE TagRank <= 5
    GROUP BY UserId
)
SELECT 
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.TotalPosts,
    us.QuestionsPosted,
    us.AnswersPosted,
    us.AveragePostScore,
    us.LastPostDate,
    us.TotalBadges,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    COALESCE(cs.TotalComments, 0) AS TotalComments,
    COALESCE(cs.AverageCommentScore, 0) AS AverageCommentScore,
    COALESCE(vs.UpvotesGiven, 0) AS UpvotesGiven,
    COALESCE(vs.DownvotesGiven, 0) AS DownvotesGiven,
    COALESCE(es.TotalEdits, 0) AS TotalEdits,
    COALESCE(es.UniquePostsEdited, 0) AS UniquePostsEdited,
    COALESCE(tt.Top5Tags, '') AS Top5Tags,
    RANK() OVER (ORDER BY us.Reputation DESC) AS ReputationRank,
    RANK() OVER (ORDER BY us.TotalPosts DESC) AS PostsRank,
    RANK() OVER (ORDER BY us.GoldBadges DESC) AS GoldBadgesRank
FROM UserStats us
LEFT JOIN CommentStats cs ON cs.UserId = us.UserId
LEFT JOIN VoteStats vs ON vs.UserId = us.UserId
LEFT JOIN EditStats es ON es.UserId = us.UserId
LEFT JOIN AggregatedTags tt ON tt.UserId = us.UserId
ORDER BY us.Reputation DESC;