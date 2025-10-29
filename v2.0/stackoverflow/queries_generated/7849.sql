-- {"query": "7849.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2702} 
WITH RankedPosts AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) as rn,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as prev_score,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) as next_score,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) as avg_score,
        NTILE(4) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score) as quintile
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2)
),
QuestionStats AS (
    SELECT 
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.CommentCount,
        q.FavoriteCount,
        q.CreationDate,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        (SELECT COUNT(*) FROM Posts a WHERE a.ParentId = q.Id AND a.PostTypeId = 2) as AnswerCountActual,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) as CommentCountActual,
        CASE 
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 1 
            ELSE 0 
        END as HasAcceptedAnswer,
        CASE 
            WHEN q.ClosedDate IS NOT NULL THEN 1 
            ELSE 0 
        END as IsClosed,
        CASE 
            WHEN q.CommunityOwnedDate IS NOT NULL THEN 1 
            ELSE 0 
        END as IsCommunityOwned,
        COALESCE(q.Title, '(no title)') as CleanTitle,
        REVERSE(SUBSTRING(q.Tags, 2, LENGTH(q.Tags) - 2)) as ReversedTags,
        LENGTH(q.Tags) as TagLength,
        ABS(q.Score - COALESCE((SELECT AVG(Score) FROM Posts p2 WHERE p2.OwnerUserId = q.OwnerUserId AND p2.PostTypeId = 1), 0)) as ScoreDeviation,
        IIF(q.ViewCount > 1000, 'High', IIF(q.ViewCount > 100, 'Medium', 'Low')) as ViewCategory,
        CASE 
            WHEN q.Tags LIKE '%<c>%' OR q.Tags LIKE '%<java>%' OR q.Tags LIKE '%<python>%' THEN 'Programming'
            WHEN q.Tags LIKE '%<mathematics>%' OR q.Tags LIKE '%<physics>%' OR q.Tags LIKE '%<chemistry>%' THEN 'Science'
            ELSE 'Other'
        END as TopicCategory,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 3) as Downvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 5) as Favorites,
        DATEDIFF(day, q.CreationDate, GETDATE()) as AgeInDays
    FROM Posts q
    JOIN Users u ON q.OwnerUserId = u.Id
    WHERE q.PostTypeId = 1
),
AnswerStats AS (
    SELECT 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        a.CreationDate,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        a.LastEditDate,
        CASE 
            WHEN a.LastEditDate IS NOT NULL THEN DATEDIFF(day, a.CreationDate, a.LastEditDate)
            ELSE NULL 
        END as EditAge,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) as CommentCount,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 2) as Upvotes,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = a.Id AND v.VoteTypeId = 3) as Downvotes,
        IIF(a.Score > 10, TRUE, FALSE) as HighScore,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) as RankInQuestion,
        AVG(a.Score) OVER (PARTITION BY a.ParentId) as AvgScoreInQuestion
    FROM Posts a
    JOIN Users u ON a.OwnerUserId = u.Id
    WHERE a.PostTypeId = 2
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count as TagCount,
        t.ExcerptPostId,
        t.WikiPostId,
        (SELECT COUNT(*) FROM Posts p WHERE p.Tags LIKE '%' + t.TagName + '%') as PostsWithTag,
        AVG(p.Score) as AvgScoreForTag,
        AVG(p.ViewCount) as AvgViewsForTag,
        AVG(DATEDIFF(day, p.CreationDate, GETDATE())) as AvgAgeForTag,
        CASE 
            WHEN t.Count > 1000 THEN 'Very Popular'
            WHEN t.Count > 100 THEN 'Popular'
            WHEN t.Count > 10 THEN 'Moderate'
            ELSE 'Rare'
        END as PopularityLevel
    FROM Tags t
    LEFT JOIN Posts p ON p.Tags LIKE '%' + t.TagName + '%'
    GROUP BY t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId
),
UserActivity AS (
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
        COUNT(DISTINCT v.Id) as VoteCount,
        AVG(p.Score) as AvgPostScore,
        MAX(p.CreationDate) as LastPostDate,
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        MAX(v.CreationDate) as LastVoteDate,
        (
            SELECT TOP 1 p2.Id 
            FROM Posts p2 
            WHERE p2.OwnerUserId = u.Id 
            ORDER BY p2.CreationDate DESC
        ) as MostRecentPostId,
        (
            SELECT TOP 1 p3.Id 
            FROM Posts p3 
            WHERE p3.OwnerUserId = u.Id 
            ORDER BY p3.Score DESC
        ) as HighestScoringPostId,
        IIF(u.Views > 5000, TRUE, FALSE) as HighProfileUser,
        IIF(u.UpVotes > u.DownVotes * 2, TRUE, FALSE) as PositiveReputationUser,
        DATEDIFF(day, u.CreationDate, GETDATE()) as AccountAgeInDays
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.CreationDate
),
ComplexAnalysis AS (
    SELECT 
        qs.QuestionId,
        qs.Title,
        qs.OwnerName,
        qs.OwnerReputation,
        qs.Score,
        qs.ViewCount,
        qs.AnswerCountActual,
        qs.CommentCountActual,
        qs.HasAcceptedAnswer,
        qs.IsClosed,
        qs.IsCommunityOwned,
        qs.TopicCategory,
        qs.TagLength,
        qs.ScoreDeviation,
        qs.ViewCategory,
        qs.Upvotes,
        qs.Downvotes,
        qs.Favorites,
        qs.AgeInDays,
        asa.QuestionId as AnswerQuestionId,
        asa.OwnerName as AnswerOwnerName,
        asa.Score as AnswerScore,
        asa.RankInQuestion,
        asa.AvgScoreInQuestion,
        asa.EditAge,
        asa.CommentCount as AnswerCommentCount,
        asa.Upvotes as AnswerUpvotes,
        asa.Downvotes as AnswerDownvotes,
        asa.HighScore,
        CASE 
            WHEN asa.RankInQuestion = 1 THEN 'Top Answer'
            WHEN asa.RankInQuestion <= 3 THEN 'High Rank Answer'
            ELSE 'Regular Answer'
        END as AnswerRankCategory,
        CASE 
            WHEN (qs.Score - qs.ScoreDeviation) > 10 THEN 'Highly Deviated'
            WHEN qs.ScoreDeviation > 5 THEN 'Moderately Deviated'
            ELSE 'Low Deviation'
        END as ScoreDeviationCategory,
        CASE 
            WHEN qs.AgeInDays < 30 THEN 'New Question'
            WHEN qs.AgeInDays < 365 THEN 'Medium Age Question'
            ELSE 'Old Question'
        END as QuestionAgeCategory,
        CASE 
            WHEN qs.AnswerCountActual > 10 THEN 'High Answer Count'
            WHEN qs.AnswerCountActual > 5 THEN 'Medium Answer Count'
            ELSE 'Low Answer Count'
        END as AnswerCountCategory,
        IIF(qs.TagLength > 100, TRUE, FALSE) as LongTagList,
        IIF(qs.AnswerCountActual > 0 AND qs.HasAcceptedAnswer = 1, TRUE, FALSE) as HasAnswersWithAccept,
        IIF(qs.AnswerCountActual > 0 AND qs.IsClosed = 1, TRUE, FALSE) as ClosedWithAnswers,
        IIF(qs.ViewCount > qs.AnswerCountActual * 50, TRUE, FALSE) as WellViewed
    FROM QuestionStats qs
    LEFT JOIN AnswerStats asa ON qs.QuestionId = asa.QuestionId
    WHERE qs.Score > 0
)
SELECT 
    ca.QuestionId,
    ca.Title,
    ca.OwnerName,
    ca.OwnerReputation,
    ca.Score,
    ca.ViewCount,
    ca.AnswerCountActual,
    ca.CommentCountActual,
    ca.HasAcceptedAnswer,
    ca.IsClosed,
    ca.IsCommunityOwned,
    ca.TopicCategory,
    ca.TagLength,
    ca.ScoreDeviation,
    ca.ViewCategory,
    ca.Upvotes,
    ca.Downvotes,
    ca.Favorites,
    ca.AgeInDays,
    ca.AnswerQuestionId,
    ca.AnswerOwnerName,
    ca.AnswerScore,
    ca.RankInQuestion,
    ca.AvgScoreInQuestion,
    ca.EditAge,
    ca.AnswerCommentCount,
    ca.AnswerUpvotes,
    ca.AnswerDownvotes,
    ca.HighScore,
    ca.AnswerRankCategory,
    ca.ScoreDeviationCategory,
    ca.QuestionAgeCategory,
    ca.AnswerCountCategory,
    ca.LongTagList,
    ca.HasAnswersWithAccept,
    ca.ClosedWithAnswers,
    ca.WellViewed,
    DENSE_RANK() OVER (ORDER BY ca.Score DESC) as GlobalScoreRank,
    PERCENT_RANK() OVER (ORDER BY ca.Score) as ScorePercentile,
    CUME_DIST() OVER (ORDER BY ca.Score) as ScoreCumulativeDistribution,
    NTILE(10) OVER (ORDER BY ca.Score) as ScoreDecile,
    ROW_NUMBER() OVER (PARTITION BY ca.TopicCategory ORDER BY ca.Score DESC) as CategoryScoreRow,
    RANK() OVER (PARTITION BY ca.OwnerReputation ORDER BY ca.Score DESC) as ReputationScoreRank,
    IIF(ca.Score > (SELECT AVG(Score) FROM QuestionStats), TRUE, FALSE) as AboveAverageScore,
    IIF(ca.ViewCount > (SELECT AVG(ViewCount) FROM QuestionStats) AND ca.AnswerCountActual > 1, TRUE, FALSE) as PopularWithAnswers,
    IIF(ca.Favorites > 0 AND ca.Upvotes > 0, TRUE, FALSE) as WellLiked,
    IIF(ca.AgeInDays < 30 AND ca.Score > 100, TRUE, FALSE) as NewHighScoring,
    IIF(ca.AnswerCountActual = 0 AND ca.IsClosed = 1, TRUE, FALSE) as NoAnswersButClosed,
    IIF(ca.TopicCategory = 'Programming' AND ca.AgeInDays < 60, TRUE, FALSE) as RecentProgrammingQuestion
FROM ComplexAnalysis ca
WHERE ca.QuestionId IS NOT NULL
HAVING COUNT(*) > 0
ORDER BY ca.Score DESC, ca.ViewCount DESC
OFFSET 100 ROWS
FETCH NEXT 100 ROWS ONLY
OPTION (RECOMPILE);