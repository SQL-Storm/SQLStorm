-- {"query": "29024.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1820} 
WITH UserStats AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        COUNT(DISTINCT p.Id) as PostCount,
        COUNT(DISTINCT c.Id) as CommentCount,
        COUNT(DISTINCT b.Id) as BadgeCount,
        MAX(p.CreationDate) as LastPostDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC) as ReputationRank,
        CASE 
            WHEN u.Reputation > 10000 THEN 'Elite'
            WHEN u.Reputation > 5000 THEN 'Expert'
            WHEN u.Reputation > 1000 THEN 'Advanced'
            ELSE 'Beginner'
        END as ReputationLevel
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.CreationDate > '2010-01-01'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.Tags,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as PostType,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC) as ScoreRank,
        CASE 
            WHEN p.Score > 100 THEN 'High Impact'
            WHEN p.Score > 50 THEN 'Medium Impact'
            ELSE 'Low Impact'
        END as ImpactLevel
    FROM Posts p
    WHERE p.CreationDate > '2020-01-01'
      AND p.Score > 0
),
PostActivity AS (
    SELECT 
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        CASE 
            WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN 'Title/Tag Edit'
            WHEN ph.PostHistoryTypeId IN (2, 5) THEN 'Body Edit'
            WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'State Change'
            ELSE 'Other'
        END as ActivityType,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) as PreviousActivityDate,
        DATEDIFF(day, LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate), ph.CreationDate) as DaysSinceLastActivity
    FROM PostHistory ph
    WHERE ph.CreationDate > '2020-01-01'
),
TagUsage AS (
    SELECT 
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        CASE 
            WHEN t.Count > 1000 THEN 'Popular'
            WHEN t.Count > 100 THEN 'Moderate'
            ELSE 'Niche'
        END as PopularityLevel,
        NTILE(4) OVER (ORDER BY t.Count) as Quartile,
        RANK() OVER (ORDER BY t.Count DESC) as PopularityRank
    FROM Tags t
),
UserEngagement AS (
    SELECT 
        u.Id as UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL THEN p.Id END) as PostedQuestions,
        COUNT(DISTINCT CASE WHEN p.Id IS NOT NULL AND p.PostTypeId = 2 THEN p.Id END) as PostedAnswers,
        COUNT(DISTINCT CASE WHEN v.PostId IS NOT NULL AND v.VoteTypeId IN (2, 3) THEN v.PostId END) as VotedPosts,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) as UpvotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) as DownvotesReceived,
        COUNT(DISTINCT CASE WHEN b.Id IS NOT NULL THEN b.Id END) as BadgesEarned
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId IN (1, 2)
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
ComplexQuery AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.ViewCount,
        us.PostCount,
        us.CommentCount,
        us.BadgeCount,
        us.ReputationRank,
        us.ReputationLevel,
        tp.Title,
        tp.Score,
        tp.ViewCount,
        tp.PostType,
        tp.ScoreRank,
        tp.ImpactLevel,
        pa.ActivityType,
        pa.DaysSinceLastActivity,
        tu.TagName,
        tu.Count,
        tu.PopularityLevel,
        uen.PostedQuestions,
        uen.PostedAnswers,
        uen.VotedPosts,
        uen.UpvotesReceived,
        uen.DownvotesReceived,
        uen.BadgesEarned,
        CASE 
            WHEN us.PostCount > 0 THEN (us.CommentCount * 100.0 / NULLIF(us.PostCount, 0))
            ELSE 0
        END as CommentsPerPost,
        CASE 
            WHEN us.ViewCount > 0 THEN (us.PostCount * 100.0 / NULLIF(us.ViewCount, 0))
            ELSE 0
        END as PostsPerView,
        COALESCE(
            CASE 
                WHEN tp.ScoreRank <= 10 THEN 'Top Scoring Post'
                WHEN tp.ScoreRank <= 50 THEN 'High Scoring Post'
                ELSE 'Regular Post'
            END,
            'No Posts'
        ) as PostPerformance,
        CASE 
            WHEN pa.DaysSinceLastActivity IS NOT NULL AND pa.DaysSinceLastActivity > 30 THEN 'Inactive'
            WHEN pa.DaysSinceLastActivity IS NOT NULL AND pa.DaysSinceLastActivity <= 30 THEN 'Active'
            ELSE 'New User'
        END as ActivityStatus
    FROM UserStats us
    LEFT JOIN TopPosts tp ON us.UserId = tp.OwnerUserId
    LEFT JOIN PostActivity pa ON us.UserId = pa.UserId
    LEFT JOIN TagUsage tu ON tu.TagName IN (
        SELECT unnest(string_to_array(tp.Tags, '<>')) 
        WHERE tp.PostTypeId = 1 AND tp.Tags IS NOT NULL
    )
    LEFT JOIN UserEngagement uen ON us.UserId = uen.UserId
    WHERE us.Reputation > 500
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    ViewCount,
    PostCount,
    CommentCount,
    BadgeCount,
    ReputationRank,
    ReputationLevel,
    Title,
    Score,
    ViewCount,
    PostType,
    ScoreRank,
    ImpactLevel,
    ActivityType,
    DaysSinceLastActivity,
    TagName,
    Count,
    PopularityLevel,
    PostedQuestions,
    PostedAnswers,
    VotedPosts,
    UpvotesReceived,
    DownvotesReceived,
    BadgesEarned,
    CommentsPerPost,
    PostsPerView,
    PostPerformance,
    ActivityStatus
FROM ComplexQuery
WHERE 
    (PostPerformance IN ('Top Scoring Post', 'High Scoring Post') OR PostPerformance IS NULL)
    AND (
        (ActivityStatus = 'Active' AND DaysSinceLastActivity <= 30) 
        OR 
        (ActivityStatus = 'Inactive' AND DaysSinceLastActivity > 30)
        OR 
        ActivityStatus IS NULL
    )
    AND (
        (PopularityLevel IN ('Popular', 'Moderate') OR PopularityLevel IS NULL)
        OR 
        (PopularityLevel = 'Niche' AND BadgesEarned >= 5)
    )
    AND (
        (ReputationLevel = 'Elite' AND PostsPerView >= 0.5)
        OR 
        (ReputationLevel = 'Expert' AND PostsPerView >= 0.3)
        OR 
        (ReputationLevel = 'Advanced' AND PostsPerView >= 0.1)
        OR 
        ReputationLevel = 'Beginner'
    )
ORDER BY Reputation DESC, Score DESC, Count DESC
LIMIT 1000;