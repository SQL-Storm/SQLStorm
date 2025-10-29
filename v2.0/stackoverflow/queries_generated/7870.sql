-- {"query": "7870.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 2148} 
SELECT 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) as TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as Answers,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) as TotalQuestionScore,
    COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0) as TotalAnswerScore,
    COUNT(DISTINCT b.Id) as BadgesReceived,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) as GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) as SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) as BronzeBadges,
    COUNT(DISTINCT c.Id) as CommentsMade,
    COUNT(DISTINCT ph.Id) as PostHistoryEntries,
    AVG(p.Score) as AvgPostScore,
    MAX(p.CreationDate) as LastPostDate,
    DATEDIFF(CURRENT_TIMESTAMP, MAX(p.CreationDate)) as DaysSinceLastPost,
    STDEV(p.Score) as ScoreStandardDeviation,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 100.0 / COUNT(DISTINCT p.Id), 2)
        ELSE 0 
    END as AnswerPercentage,
    STRING_AGG(DISTINCT t.TagName, ', ') as TagsUsed,
    COALESCE(
        (SELECT TOP 1 p.Title 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 1 
         ORDER BY p.Score DESC NULLS LAST 
         OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY), 
        'No Questions'
    ) as HighestScoringQuestion,
    COALESCE(
        (SELECT TOP 1 p.Title 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 2 
         ORDER BY p.Score DESC NULLS LAST 
         OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY), 
        'No Answers'
    ) as HighestScoringAnswer,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) = 0 THEN 'No Questions'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) = 0 THEN 'No Answers'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) THEN 'More Answers Than Questions'
        ELSE 'More Questions Than Answers'
    END as PostingBalance,
    COALESCE(
        (SELECT TOP 1 p.Title 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 1 
         AND p.Score > (SELECT AVG(Score) FROM Posts WHERE PostTypeId = 1)
         ORDER BY p.Score DESC 
         OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY), 
        'No High Score Questions'
    ) as AboveAverageQuestion,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 1 AND p.Score > (
            SELECT AVG(Score) 
            FROM Posts 
            WHERE PostTypeId = 1 
            AND OwnerUserId IS NOT NULL
        ) 
        THEN p.Id 
    END) as AboveAverageQuestions,
    COUNT(DISTINCT CASE 
        WHEN p.PostTypeId = 2 AND p.Score > (
            SELECT AVG(Score) 
            FROM Posts 
            WHERE PostTypeId = 2 
            AND OwnerUserId IS NOT NULL
        ) 
        THEN p.Id 
    END) as AboveAverageAnswers,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id 
     AND v.VoteTypeId = 2) as UpvotesReceived,
    (SELECT COUNT(*) 
     FROM Votes v 
     WHERE v.UserId = u.Id 
     AND v.VoteTypeId = 3) as DownvotesReceived,
    COALESCE(
        (SELECT TOP 1 vt.Name 
         FROM VoteTypes vt 
         JOIN Votes v ON vt.Id = v.VoteTypeId 
         WHERE v.UserId = u.Id 
         GROUP BY vt.Name 
         ORDER BY COUNT(*) DESC), 
        'No Votes'
    ) as MostVotedType,
    (CASE 
        WHEN COUNT(DISTINCT ph.PostId) > 0 THEN 
            COUNT(DISTINCT ph.PostId) / NULLIF(COUNT(DISTINCT p.Id), 0)
        ELSE 0 
    END) as HistoryPerPostRatio,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 THEN 
            ROUND(
                (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) * 100.0) / 
                NULLIF(COUNT(DISTINCT p.Id), 0), 2
            )
        ELSE 0 
    END as QuestionPercentage,
    COALESCE(
        (SELECT STRING_AGG(Tags, ', ')
         FROM Posts 
         WHERE OwnerUserId = u.Id 
         AND PostTypeId = 1 
         AND Tags IS NOT NULL
         GROUP BY OwnerUserId
         ORDER BY COUNT(*) DESC 
         OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY), 
        'No Tags'
    ) as MostFrequentTags,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 1 
         AND EXISTS (
             SELECT 1 
             FROM Comments c 
             WHERE c.PostId = p.Id 
             AND c.UserId = u.Id
         )), 
        0
    ) as QuestionsWithUserComments,
    COALESCE(
        (SELECT COUNT(DISTINCT p.Id)
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 2 
         AND EXISTS (
             SELECT 1 
             FROM Posts pa 
             WHERE pa.ParentId = p.Id 
             AND pa.OwnerUserId = u.Id
         )), 
        0
    ) as AnswersToOwnQuestions,
    ROUND(
        COALESCE(
            CAST(SUM(p.ViewCount) AS FLOAT) / NULLIF(COUNT(p.Id), 0), 0
        ), 2
    ) as AvgViewsPerPost,
    COUNT(DISTINCT p.Id) - COALESCE(
        (SELECT COUNT(DISTINCT p2.Id)
         FROM Posts p2 
         WHERE p2.OwnerUserId = u.Id 
         AND p2.ViewCount = 0), 
        0
    ) as PostsWithViews,
    CASE 
        WHEN COUNT(DISTINCT p.Id) > 0 AND AVG(p.Score) > 0 THEN 
            ROUND(
                (COUNT(DISTINCT CASE WHEN p.Score > AVG(p.Score) THEN p.Id END) * 100.0) / 
                NULLIF(COUNT(DISTINCT p.Id), 0), 2
            )
        ELSE 0 
    END as PostsAboveAvgScore,
    COALESCE(
        (SELECT COUNT(DISTINCT p.Id)
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.Score > 0
         AND EXISTS (
             SELECT 1 
             FROM Votes v 
             WHERE v.PostId = p.Id 
             AND (v.VoteTypeId = 2 OR v.VoteTypeId = 3)
         )), 
        0
    ) as ScoredPosts,
    (SELECT AVG(Score) 
     FROM Posts p 
     WHERE p.OwnerUserId = u.Id 
     AND p.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(Score) 
     FROM Posts p 
     WHERE p.OwnerUserId = u.Id 
     AND p.PostTypeId = 2) as AvgAnswerScore,
    COALESCE(
        (SELECT TOP 1 p.Title 
         FROM Posts p 
         WHERE p.OwnerUserId = u.Id 
         AND p.PostTypeId = 1 
         AND p.Score > (
             SELECT AVG(Score) 
             FROM Posts 
             WHERE OwnerUserId = u.Id 
             AND PostTypeId = 1
         )
         ORDER BY p.Score DESC 
         OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY), 
        'No AboveAvg Questions'
    ) as AboveAvgQuestion
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN Tags t ON t.Id IN (
    SELECT Id 
    FROM Tags 
    WHERE TagName IN (
        SELECT TRIM(SUBSTRING(p.Tags, 2, LEN(p.Tags) - 2)) 
        FROM Posts p 
        WHERE p.OwnerUserId = u.Id 
        AND p.Tags IS NOT NULL
        AND p.Tags <> ''
    ) OR TagName LIKE '%' + p.Title + '%'
)
WHERE u.Reputation > 1000
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
ORDER BY 
    (CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 THEN 
            COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) * 1.0 / 
            NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0)
        ELSE 0 
    END) DESC,
    AVG(p.Score) DESC,
    COUNT(DISTINCT b.Id) DESC,
    u.Reputation DESC
OPTION (MAXDOP 1)