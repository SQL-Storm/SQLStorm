-- {"query": "29076.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2137} 
WITH UserStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.ViewCount,
        COUNT(DISTINCT p.Id) AS PostCount,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        COUNT(DISTINCT c.Id) AS CommentCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        AVG(p.Score) AS AvgPostScore,
        MAX(p.CreationDate) AS LastPostDate,
        STRING_AGG(DISTINCT SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2) FILTER (WHERE p.Tags IS NOT NULL), ';') AS AllTags,
        COUNT(DISTINCT CASE WHEN p.Score > 100 THEN p.Id END) AS HighScorePosts,
        COUNT(DISTINCT CASE WHEN p.Score < 0 THEN p.Id END) AS NegativeScorePosts,
        COUNT(DISTINCT CASE WHEN p.ViewCount > 1000 THEN p.Id END) AS PopularPosts
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId AND p.DeletionDate IS NULL
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    WHERE u.AccountId IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.ViewCount
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.ParentId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.LastEditDate,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        CASE WHEN p.Score > 100 THEN 'High'
             WHEN p.Score > 50 THEN 'Medium'
             WHEN p.Score > 0 THEN 'Low'
             ELSE 'Negative'
        END AS ScoreCategory,
        DATEDIFF(day, p.CreationDate, COALESCE(p.ClosedDate, p.LastActivityDate, CURRENT_TIMESTAMP)) AS AgeInDays,
        CASE WHEN p.Tags IS NOT NULL AND LENGTH(p.Tags) > 10 THEN 'HasTags' ELSE 'NoTags' END AS HasTagsStatus,
        CASE WHEN p.LastActivityDate > DATEADD(day, -7, CURRENT_TIMESTAMP) THEN 1 ELSE 0 END AS IsRecentlyActive,
        COUNT(DISTINCT v.Id) AS VoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVoteCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 5 THEN v.Id END) AS FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS UserPostRank,
        RANK() OVER (ORDER BY p.Score DESC) AS OverallScoreRank,
        DENSE_RANK() OVER (ORDER BY p.CreationDate DESC) AS RecentRank,
        LAG(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS PrevScore,
        LEAD(p.Score, 1, 0) OVER (ORDER BY p.CreationDate) AS NextScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScorePerUser
    FROM Posts p
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.DeletionDate IS NULL
),
CombinedAnalysis AS (
    SELECT 
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.PostCount,
        us.BadgeCount,
        us.CommentCount,
        us.QuestionCount,
        us.AnswerCount,
        us.AvgPostScore,
        us.LastPostDate,
        us.AllTags,
        us.HighScorePosts,
        us.NegativeScorePosts,
        us.PopularPosts,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.PostType,
        pa.HasAcceptedAnswer,
        pa.IsClosed,
        pa.IsCommunityOwned,
        pa.ScoreCategory,
        pa.AgeInDays,
        pa.HasTagsStatus,
        pa.IsRecentlyActive,
        pa.VoteCount,
        pa.UpVoteCount,
        pa.DownVoteCount,
        pa.FavoriteCount,
        pa.UserPostRank,
        pa.OverallScoreRank,
        pa.RecentRank,
        pa.PrevScore,
        pa.NextScore,
        pa.AvgScorePerUser,
        CASE 
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE DeletionDate IS NULL) THEN 'AboveAverage'
            WHEN pa.Score > (SELECT AVG(Score) FROM Posts WHERE DeletionDate IS NULL) * 0.5 THEN 'Average'
            ELSE 'BelowAverage'
        END AS ScoreComparison,
        CASE 
            WHEN pa.ViewCount > 1000 THEN 'VeryPopular'
            WHEN pa.ViewCount > 500 THEN 'Popular'
            WHEN pa.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END AS PopularityLevel,
        CASE 
            WHEN pa.VoteCount > 20 AND pa.UpVoteCount > pa.DownVoteCount THEN 'HighlyUpvoted'
            WHEN pa.VoteCount > 10 AND pa.DownVoteCount > pa.UpVoteCount THEN 'HighlyDownvoted'
            WHEN pa.VoteCount < 5 THEN 'RarelyVoted'
            ELSE 'ModerateVoting'
        END AS VotingPattern,
        LTRIM(RTRIM(SUBSTRING(pa.Tags, 2, LENGTH(pa.Tags)-2))) AS CleanTags,
        COALESCE(
            (SELECT COUNT(*) FROM Posts p2 
             WHERE p2.OwnerUserId = us.UserId 
             AND p2.Score > pa.Score 
             AND p2.DeletionDate IS NULL),
            0
        ) AS BetterThanUsersPosts
    FROM UserStats us
    INNER JOIN PostAnalysis pa ON us.UserId = pa.OwnerUserId
    WHERE us.PostCount > 0
)
SELECT 
    UserId,
    DisplayName,
    Reputation,
    PostCount,
    BadgeCount,
    CommentCount,
    QuestionCount,
    AnswerCount,
    AvgPostScore,
    LastPostDate,
    AllTags,
    HighScorePosts,
    NegativeScorePosts,
    PopularPosts,
    PostId,
    Title,
    Score,
    ViewCount,
    CreationDate,
    PostType,
    HasAcceptedAnswer,
    IsClosed,
    IsCommunityOwned,
    ScoreCategory,
    AgeInDays,
    HasTagsStatus,
    IsRecentlyActive,
    VoteCount,
    UpVoteCount,
    DownVoteCount,
    FavoriteCount,
    UserPostRank,
    OverallScoreRank,
    RecentRank,
    PrevScore,
    NextScore,
    AvgScorePerUser,
    ScoreComparison,
    PopularityLevel,
    VotingPattern,
    CleanTags,
    BetterThanUsersPosts,
    CASE 
        WHEN Reputation > 10000 AND PostCount > 50 AND BadgeCount > 10 THEN 'EliteContributor'
        WHEN Reputation > 5000 AND PostCount > 20 AND BadgeCount > 5 THEN 'ActiveContributor'
        WHEN Reputation > 1000 AND PostCount > 5 THEN 'RegularContributor'
        ELSE 'NewContributor'
    END AS ContributorTier,
    CASE 
        WHEN Score > 100 AND IsClosed = 0 AND HasTagsStatus = 'HasTags' THEN 'HighQualityPost'
        WHEN Score < 0 AND IsClosed = 1 THEN 'LowQualityClosedPost'
        WHEN Score > 0 AND IsClosed = 1 THEN 'ActiveClosedPost'
        ELSE 'RegularPost'
    END AS PostQualityClassification,
    CASE 
        WHEN ViewCount > 5000 AND Score > 50 THEN 'Trending'
        WHEN ViewCount > 1000 AND Score > 20 THEN 'Popular'
        WHEN ViewCount > 100 AND Score > 5 THEN 'Noticeable'
        WHEN ViewCount > 10 AND Score > 0 THEN 'MildlyNotable'
        ELSE 'LowTraffic'
    END AS TrafficClassification,
    DATEDIFF(day, CreationDate, CURRENT_TIMESTAMP) AS DaysSinceCreation,
    ROUND(
        CASE 
            WHEN AgeInDays > 0 THEN (Score * 1.0) / AgeInDays 
            ELSE 0 
        END, 4
    ) AS ScorePerDay,
    COALESCE(
        (SELECT Name FROM PostTypes WHERE Id = PostType),
        'Unknown'
    ) AS PostTypeName
FROM CombinedAnalysis
WHERE PostCount > 0
  AND Reputation > 0
  AND COALESCE(Reputation, 0) + COALESCE(PostCount, 0) > 100
  AND (Score > 0 OR VoteCount > 0 OR ViewCount > 0 OR CommentCount > 0)
  AND DisplayName IS NOT NULL
  AND DisplayName != ''
  AND Title IS NOT NULL
  AND CreationDate IS NOT NULL
  AND ABS(Score) < 10000
ORDER BY 
    Score DESC,
    Reputation DESC,
    PostCount DESC,
    CreationDate DESC
OFFSET 100 ROWS
FETCH NEXT 500 ROWS ONLY;