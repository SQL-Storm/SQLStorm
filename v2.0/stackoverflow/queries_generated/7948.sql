-- {"query": "7948.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2596} 
WITH UserPostStats AS (
    SELECT 
        u.Id as UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) as TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) as QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) as AnswerCount,
        SUM(p.Score) as TotalScore,
        MAX(p.CreationDate) as LatestPostDate,
        AVG(p.Score) as AvgScore,
        STRING_AGG(p.Tags, ' | ') as AllTags,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 2) as UpVoteCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 3) as DownVoteCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END) / NULLIF(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0), 0) as AvgQuestionViews,
        CASE 
            WHEN COUNT(p.Id) > 0 THEN 
                (SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(p.Id)) 
            ELSE 0 
        END as QuestionPercentage
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.CreationDate >= '2010-01-01'
    GROUP BY u.Id, u.Reputation, u.DisplayName
),
TopTags AS (
    SELECT 
        TagName,
        Count,
        ExcerptPostId,
        WikiPostId,
        IsModeratorOnly,
        IsRequired,
        ROW_NUMBER() OVER (ORDER BY Count DESC) as TagRank
    FROM Tags
    WHERE Count > 1000
),
PostActivityAnalysis AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostType,
        CASE 
            WHEN p.Score >= 100 THEN 'High'
            WHEN p.Score >= 50 THEN 'Medium'
            ELSE 'Low'
        END as ScoreLevel,
        DATEDIFF(day, p.CreationDate, CURRENT_TIMESTAMP) as DaysSinceCreation,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) as DaysActive,
        CASE 
            WHEN p.ViewCount > 1000 THEN 'Viral'
            WHEN p.ViewCount > 500 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Noticeable'
            ELSE 'Unknown'
        END as ViewCategory,
        COALESCE(p.AcceptedAnswerId, 0) as HasAcceptedAnswer,
        COALESCE(p.AnswerCount, 0) as AnswerCount,
        COALESCE(p.CommentCount, 0) as CommentCount,
        COALESCE(p.FavoriteCount, 0) as FavoriteCount,
        p.Tags,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            WHEN p.Score < 0 THEN 'Negative Score'
            ELSE 'Active'
        END as PostStatus,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
        (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10, 11, 12, 13)) as EditCount
    FROM Posts p
    WHERE p.CreationDate >= '2012-01-01'
),
CombinedMetrics AS (
    SELECT 
        ups.UserId,
        ups.Reputation,
        ups.DisplayName,
        ups.TotalPosts,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.TotalScore,
        ups.LatestPostDate,
        ups.AvgScore,
        ups.AllTags,
        ups.UpVoteCount,
        ups.DownVoteCount,
        ups.AvgQuestionViews,
        ups.QuestionPercentage,
        pa.PostId,
        pa.Title,
        pa.Score,
        pa.ViewCount,
        pa.CreationDate,
        pa.PostTypeId,
        pa.PostType,
        pa.ScoreLevel,
        pa.DaysSinceCreation,
        pa.DaysActive,
        pa.ViewCategory,
        pa.HasAcceptedAnswer,
        pa.AnswerCount as PostAnswerCount,
        pa.CommentCount as PostCommentCount,
        pa.FavoriteCount,
        pa.Tags,
        pa.PostStatus,
        pa.UpVotes,
        pa.DownVotes,
        pa.EditCount,
        CASE 
            WHEN pa.Score > ups.AvgScore AND pa.ViewCount > ups.AvgQuestionViews THEN 'High Performer'
            WHEN pa.Score > ups.AvgScore OR pa.ViewCount > ups.AvgQuestionViews THEN 'Above Average'
            ELSE 'Below Average'
        END as PerformanceTier
    FROM UserPostStats ups
    INNER JOIN PostActivityAnalysis pa ON ups.UserId = pa.OwnerUserId
    WHERE pa.Score IS NOT NULL
),
RankedUsers AS (
    SELECT 
        UserId,
        Reputation,
        DisplayName,
        TotalPosts,
        QuestionCount,
        AnswerCount,
        TotalScore,
        LatestPostDate,
        AvgScore,
        AllTags,
        UpVoteCount,
        DownVoteCount,
        AvgQuestionViews,
        QuestionPercentage,
        ROW_NUMBER() OVER (ORDER BY TotalScore DESC, Reputation DESC) as UserRank,
        AVG(TotalScore) OVER (PARTITION BY QuestionPercentage) as AvgScoreByQuestionRatio
    FROM CombinedMetrics
)
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPosts,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalScore,
    ru.AvgScore,
    ru.QuestionPercentage,
    ru.UserRank,
    cm.PostId,
    cm.Title,
    cm.Score,
    cm.ViewCount,
    cm.PostType,
    cm.ScoreLevel,
    cm.ViewCategory,
    cm.PostStatus,
    cm.PerformanceTier,
    cm.DaysSinceCreation,
    cm.UpVotes,
    cm.DownVotes,
    cm.EditCount,
    COALESCE(NULLIF(cm.Tags, ''), 'No Tags') as CleanedTags,
    CASE 
        WHEN cm.ViewCategory = 'Viral' AND cm.Score > 100 THEN 'Trending High-Performing'
        WHEN cm.ViewCategory = 'Popular' AND cm.Score > 50 THEN 'Popular High-Performing'
        WHEN cm.ViewCategory = 'Noticeable' AND cm.Score > 25 THEN 'Noticeable High-Performing'
        WHEN cm.Score > 100 THEN 'High Score'
        ELSE 'Standard'
    END as PostCategory,
    (SELECT STRING_AGG(bt.Name, ', ') 
     FROM Badges bt 
     WHERE bt.UserId = ru.UserId 
     AND bt.Date >= '2020-01-01') as RecentBadges,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = ru.UserId 
         AND p2.PostTypeId = 1 
         AND p2.CreationDate BETWEEN '2020-01-01' AND '2024-12-31'), 0) as Questions2020_2024,
    CASE 
        WHEN ru.UserRank <= 10 AND ru.QuestionCount > 100 THEN 'Elite Contributor'
        WHEN ru.UserRank <= 50 AND ru.QuestionCount > 50 THEN 'Top Contributor'
        WHEN ru.UserRank <= 100 THEN 'Active Contributor'
        ELSE 'Regular Contributor'
    END as UserRecognition,
    COUNT(*) OVER (PARTITION BY ru.UserRank) as UsersPerRank,
    AVG(cm.Score) OVER (PARTITION BY cm.PostType) as AvgScoreByPostType,
    RANK() OVER (ORDER BY cm.ViewCount DESC) as ViewRank,
    DENSE_RANK() OVER (ORDER BY cm.Score DESC) as ScoreRank,
    ROW_NUMBER() OVER (ORDER BY cm.CreationDate) as ChronologicalOrder
FROM RankedUsers ru
INNER JOIN CombinedMetrics cm ON ru.UserId = cm.UserId
WHERE cm.Score >= 0 
    AND cm.ViewCount >= 0
    AND cm.PostType IN ('Question', 'Answer')
    AND (cm.ViewCategory IN ('Viral', 'Popular') OR cm.Score >= 50)
    AND cm.DaysSinceCreation <= 365
    AND cm.PostStatus NOT IN ('Closed', 'Community Owned')
ORDER BY 
    cm.Score DESC,
    cm.ViewCount DESC,
    ru.UserRank ASC
LIMIT 1000
EXCEPT
SELECT 
    ru.UserId,
    ru.DisplayName,
    ru.Reputation,
    ru.TotalPosts,
    ru.QuestionCount,
    ru.AnswerCount,
    ru.TotalScore,
    ru.AvgScore,
    ru.QuestionPercentage,
    ru.UserRank,
    cm.PostId,
    cm.Title,
    cm.Score,
    cm.ViewCount,
    cm.PostType,
    cm.ScoreLevel,
    cm.ViewCategory,
    cm.PostStatus,
    cm.PerformanceTier,
    cm.DaysSinceCreation,
    cm.UpVotes,
    cm.DownVotes,
    cm.EditCount,
    COALESCE(NULLIF(cm.Tags, ''), 'No Tags') as CleanedTags,
    CASE 
        WHEN cm.ViewCategory = 'Viral' AND cm.Score > 100 THEN 'Trending High-Performing'
        WHEN cm.ViewCategory = 'Popular' AND cm.Score > 50 THEN 'Popular High-Performing'
        WHEN cm.ViewCategory = 'Noticeable' AND cm.Score > 25 THEN 'Noticeable High-Performing'
        WHEN cm.Score > 100 THEN 'High Score'
        ELSE 'Standard'
    END as PostCategory,
    (SELECT STRING_AGG(bt.Name, ', ') 
     FROM Badges bt 
     WHERE bt.UserId = ru.UserId 
     AND bt.Date >= '2020-01-01') as RecentBadges,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.OwnerUserId = ru.UserId 
         AND p2.PostTypeId = 1 
         AND p2.CreationDate BETWEEN '2020-01-01' AND '2024-12-31'), 0) as Questions2020_2024,
    CASE 
        WHEN ru.UserRank <= 10 AND ru.QuestionCount > 100 THEN 'Elite Contributor'
        WHEN ru.UserRank <= 50 AND ru.QuestionCount > 50 THEN 'Top Contributor'
        WHEN ru.UserRank <= 100 THEN 'Active Contributor'
        ELSE 'Regular Contributor'
    END as UserRecognition,
    COUNT(*) OVER (PARTITION BY ru.UserRank) as UsersPerRank,
    AVG(cm.Score) OVER (PARTITION BY cm.PostType) as AvgScoreByPostType,
    RANK() OVER (ORDER BY cm.ViewCount DESC) as ViewRank,
    DENSE_RANK() OVER (ORDER BY cm.Score DESC) as ScoreRank,
    ROW_NUMBER() OVER (ORDER BY cm.CreationDate) as ChronologicalOrder
FROM RankedUsers ru
INNER JOIN CombinedMetrics cm ON ru.UserId = cm.UserId
WHERE cm.Score < 0 
    OR cm.ViewCount < 0
    OR cm.PostType NOT IN ('Question', 'Answer')
    OR cm.DaysSinceCreation > 365
ORDER BY 
    cm.Score ASC,
    cm.ViewCount ASC,
    ru.UserRank DESC
LIMIT 500;