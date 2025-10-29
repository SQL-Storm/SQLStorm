-- {"query": "7151.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1938} 
WITH UserActivityStats AS (
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
        MAX(c.CreationDate) as LastCommentDate,
        MAX(b.Date) as LastBadgeDate,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 THEN 
                DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate))
            ELSE NULL 
        END as DaysSinceLastPost,
        COALESCE(SUM(p.Score), 0) as TotalPostScore,
        COALESCE(AVG(p.Score), 0) as AvgPostScore,
        STRING_AGG(DISTINCT p.PostTypeId::VARCHAR, ',') as PostTypesUsed
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id > 0
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes
),
RankedUsers AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (ORDER BY TotalPostScore DESC, Reputation DESC, PostCount DESC) as ScoreRank,
        DENSE_RANK() OVER (ORDER BY Reputation DESC) as RepRank,
        PERCENT_RANK() OVER (ORDER BY Views DESC) as ViewPercentile,
        NTILE(10) OVER (ORDER BY AvgPostScore DESC) as ScoreQuartile
    FROM UserActivityStats
),
TopPosts AS (
    SELECT 
        p.Id as PostId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.PostTypeId,
        p.Tags,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ParentId,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END as PostTypeDesc,
        COALESCE(
            (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id), 
            0
        ) as CommentCountActual,
        COALESCE(
            (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)), 
            0
        ) as VoteCount,
        CASE 
            WHEN p.Tags IS NOT NULL AND p.Tags != '' THEN 
                (SELECT COUNT(*) FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><')) as tag)
            ELSE 0 
        END as TagCount
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) 
        AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 year'
        AND p.Score >= 0
        AND (
            (p.PostTypeId = 1 AND p.AnswerCount >= 0) 
            OR 
            (p.PostTypeId = 2 AND p.ParentId IS NOT NULL)
        )
),
CombinedData AS (
    SELECT 
        ru.UserId,
        ru.DisplayName,
        ru.Reputation,
        ru.Views,
        ru.PostCount,
        ru.CommentCount,
        ru.BadgeCount,
        ru.TotalPostScore,
        ru.AvgPostScore,
        ru.ScoreRank,
        ru.RepRank,
        ru.ViewPercentile,
        ru.ScoreQuartile,
        tp.PostId,
        tp.Title,
        tp.Score as PostScore,
        tp.ViewCount,
        tp.CreationDate as PostCreationDate,
        tp.PostTypeDesc,
        tp.CommentCountActual,
        tp.VoteCount,
        tp.TagCount,
        CASE 
            WHEN tp.PostTypeId = 1 AND tp.AnswerCount > 0 THEN 'Question with Answers'
            WHEN tp.PostTypeId = 1 AND tp.AnswerCount = 0 THEN 'Unanswered Question'
            WHEN tp.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END as QuestionStatus,
        CASE 
            WHEN tp.Score > 10 THEN 'Highly Voted'
            WHEN tp.Score > 0 THEN 'Positive Score'
            WHEN tp.Score = 0 THEN 'Neutral Score'
            ELSE 'Negative Score'
        END as ScoreCategory,
        CASE 
            WHEN tp.TagCount > 3 THEN 'Tag Rich'
            WHEN tp.TagCount > 1 THEN 'Tagged'
            ELSE 'Untagged'
        END as TagStatus,
        CONCAT(tp.PostTypeDesc, ' - ', tp.QuestionStatus, ' - ', tp.ScoreCategory, ' - ', tp.TagStatus) as PostClassification
    FROM RankedUsers ru
    INNER JOIN TopPosts tp ON ru.UserId = tp.OwnerUserId
    WHERE ru.PostCount >= 1 AND ru.Reputation >= 100
),
UserPerformance AS (
    SELECT 
        *,
        LAG(TotalPostScore) OVER (PARTITION BY UserId ORDER BY PostCreationDate) as PrevPostScore,
        LEAD(AvgPostScore) OVER (PARTITION BY UserId ORDER BY ScoreRank) as NextAvgScore,
        AVG(TotalPostScore) OVER (PARTITION BY UserId) as AvgUserScore,
        COUNT(*) OVER (PARTITION BY UserId) as PostCountPerUser
    FROM CombinedData
),
FinalAnalysis AS (
    SELECT 
        *,
        CASE 
            WHEN PrevPostScore IS NOT NULL AND PrevPostScore > 0 THEN 
                ROUND(((TotalPostScore - PrevPostScore) * 100.0 / PrevPostScore), 2)
            ELSE NULL 
        END as ScoreChangePercentage,
        ROW_NUMBER() OVER (ORDER BY TotalPostScore DESC, PostScore DESC) as OverallRank,
        RANK() OVER (ORDER BY AvgUserScore DESC, PostCount DESC) as UserPerformanceRank
    FROM UserPerformance
)
SELECT 
    fa.UserId,
    fa.DisplayName,
    fa.Reputation,
    fa.Views,
    fa.PostCount,
    fa.CommentCount,
    fa.BadgeCount,
    fa.TotalPostScore,
    fa.AvgPostScore,
    fa.ScoreRank,
    fa.RepRank,
    fa.ViewPercentile,
    fa.ScoreQuartile,
    fa.PostId,
    fa.Title,
    fa.PostScore,
    fa.ViewCount,
    fa.PostCreationDate,
    fa.PostTypeDesc,
    fa.CommentCountActual,
    fa.VoteCount,
    fa.TagCount,
    fa.QuestionStatus,
    fa.ScoreCategory,
    fa.TagStatus,
    fa.PostClassification,
    fa.PrevPostScore,
    fa.NextAvgScore,
    fa.AvgUserScore,
    fa.PostCountPerUser,
    fa.ScoreChangePercentage,
    fa.OverallRank,
    fa.UserPerformanceRank,
    CASE 
        WHEN fa.ScoreChangePercentage IS NOT NULL AND fa.ScoreChangePercentage > 50 THEN 'Significant Improvement'
        WHEN fa.ScoreChangePercentage IS NOT NULL AND fa.ScoreChangePercentage > 10 THEN 'Moderate Improvement'
        WHEN fa.ScoreChangePercentage IS NOT NULL AND fa.ScoreChangePercentage < -30 THEN 'Major Decline'
        WHEN fa.ScoreChangePercentage < 0 THEN 'Minor Decline'
        ELSE 'Stable Performance'
    END as PerformanceTrend,
    (
        SELECT COUNT(*) 
        FROM FinalAnalysis fa2 
        WHERE fa2.UserId = fa.UserId 
            AND fa2.PostCreationDate >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    ) as RecentPostsInLastMonth,
    (
        SELECT STRING_AGG(CONCAT('Tag-', tag), ', ') 
        FROM UNNEST(STRING_TO_ARRAY(SUBSTRING(fa.Title, 2, LENGTH(fa.Title)-2), '><')) as tag
        WHERE tag IS NOT NULL AND tag != ''
        LIMIT 5
    ) as SampleTags,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = fa.UserId 
           AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 month'
           AND p.PostTypeId = 1), 
        0
    ) as QuestionsLastMonth,
    COALESCE(
        (SELECT COUNT(*) FROM Posts p 
         WHERE p.OwnerUserId = fa.UserId 
           AND p.CreationDate >= CURRENT_TIMESTAMP - INTERVAL '1 month'
           AND p.PostTypeId = 2), 
        0
    ) as AnswersLastMonth
FROM FinalAnalysis fa
WHERE fa.ScoreChangePercentage IS NOT NULL
    AND fa.Reputation > 500
    AND fa.PostCount > 0
    AND (
        (fa.QuestionStatus IN ('Question with Answers', 'Unanswered Question'))
        OR (fa.PostTypeDesc = 'Answer')
    )
    AND fa.ScoreQuartile BETWEEN 1 AND 5
    AND fa.ViewPercentile > 0.25
ORDER BY fa.TotalPostScore DESC, fa.OverallRank ASC
LIMIT 1000;