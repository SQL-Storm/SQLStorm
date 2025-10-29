-- {"query": "7568.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1937} 
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswer,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 AND p.Score > 0 THEN p.Id END) AS HighScoredAnswers,
    AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount END) AS AvgQuestionViews,
    AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
    COUNT(DISTINCT b.Id) AS BadgesCount,
    MAX(b.Date) AS LastBadgeDate,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT ph.Id) AS PostHistoryCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS UserTags,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
        THEN ROUND(
            CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS FLOAT) / 
            NULLIF(COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END), 0) * 100, 2)
        ELSE 0 
    END AS AnswerToQuestionRatio,
    COALESCE(
        (SELECT COUNT(*) 
         FROM Posts p2 
         WHERE p2.ParentId = p.Id 
         AND p2.PostTypeId = 2 
         AND p2.Score > 0 
         AND p2.CreationDate >= '2022-01-01'), 0) AS RecentHighScoredAnswers,
    (
        SELECT STRING_AGG(
            CONCAT(
                ph2.PostHistoryTypeId, ': ', 
                CASE WHEN ph2.PostHistoryTypeId IN (10, 11, 12, 13) THEN 'Status Change' 
                     WHEN ph2.PostHistoryTypeId = 1 THEN 'Initial Title' 
                     WHEN ph2.PostHistoryTypeId = 2 THEN 'Initial Body' 
                     WHEN ph2.PostHistoryTypeId = 3 THEN 'Initial Tags' 
                     WHEN ph2.PostHistoryTypeId = 4 THEN 'Edit Title' 
                     ELSE 'Other' END
            ), '; ') 
        FROM PostHistory ph2 
        WHERE ph2.PostId = p.Id 
        AND ph2.CreationDate >= '2021-01-01'
        ORDER BY ph2.CreationDate
    ) AS RecentHistorySummary,
    ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.CreationDate DESC) AS PostRank,
    DENSE_RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank,
    PERCENT_RANK() OVER (ORDER BY u.Reputation) AS ReputationPercentile,
    NTILE(4) OVER (ORDER BY u.Reputation) AS ReputationQuartile,
    LAG(p.CreationDate, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS PreviousPostDate,
    LEAD(p.CreationDate, 1) OVER (PARTITION BY u.Id ORDER BY p.CreationDate) AS NextPostDate,
    CASE 
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 100 
        THEN 'High Activity'
        WHEN COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 50 
        THEN 'Medium Activity'
        ELSE 'Low Activity'
    END AS UserActivityLevel,
    ABS(
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END), 0) - 
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END), 0)
    ) AS ScoreDifference,
    (
        SELECT COUNT(*) 
        FROM Votes v 
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (1, 2, 3)
    ) AS VotingActivity,
    (
        SELECT COUNT(*) 
        FROM Comments c2 
        WHERE c2.UserId = u.Id 
        AND c2.CreationDate >= '2023-01-01'
    ) AS RecentComments,
    (
        SELECT STRING_AGG(
            CONCAT(p3.Title, ' (', p3.Score, ')'),
            '; '
            ORDER BY p3.Score DESC
        ) 
        FROM Posts p3 
        WHERE p3.OwnerUserId = u.Id 
        AND p3.PostTypeId = 1 
        AND p3.CreationDate >= '2022-01-01'
        AND p3.Score > 0
        LIMIT 5
    ) AS RecentHighScoredQuestions,
    (
        SELECT STRING_AGG(
            CASE 
                WHEN v.VoteTypeId = 1 THEN 'Accepted'
                WHEN v.VoteTypeId = 2 THEN 'Upvote'
                WHEN v.VoteTypeId = 3 THEN 'Downvote'
                ELSE 'Other'
            END, 
            ', '
        )
        FROM Votes v
        WHERE v.UserId = u.Id 
        AND v.VoteTypeId IN (1, 2, 3)
    ) AS VoteTypesUsed,
    (
        SELECT COUNT(*)
        FROM Posts p4
        WHERE p4.OwnerUserId = u.Id
        AND p4.PostTypeId = 1
        AND p4.CreationDate >= '2023-01-01'
        AND p4.AnswerCount >= 5
    ) AS HighAnswerCountQuestions,
    (
        SELECT COUNT(*)
        FROM Posts p5
        WHERE p5.OwnerUserId = u.Id
        AND p5.PostTypeId = 2
        AND p5.CreationDate >= '2023-01-01'
        AND p5.Score >= 20
    ) AS HighScoredAnswersLastYear,
    (
        SELECT STRING_AGG(
            CONCAT(
                ph3.PostHistoryTypeId, ': ',
                SUBSTRING(ph3.Text, 1, 50), '...'
            ), 
            ' | '
            ORDER BY ph3.CreationDate DESC
        )
        FROM PostHistory ph3
        WHERE ph3.UserId = u.Id
        AND ph3.CreationDate >= '2023-01-01'
        AND ph3.PostHistoryTypeId IN (1, 2, 3, 4, 5, 6)
        LIMIT 3
    ) AS RecentEditsSummary,
    (
        SELECT MAX(p6.CreationDate)
        FROM Posts p6
        WHERE p6.OwnerUserId = u.Id
        AND p6.PostTypeId = 1
        AND p6.CreationDate >= '2023-01-01'
    ) AS LatestQuestionDate,
    (
        SELECT MIN(p7.CreationDate)
        FROM Posts p7
        WHERE p7.OwnerUserId = u.Id
        AND p7.PostTypeId = 1
    ) AS FirstQuestionDate,
    (
        SELECT AVG(DATEDIFF(day, p8.CreationDate, p8.LastEditDate))
        FROM Posts p8
        WHERE p8.OwnerUserId = u.Id
        AND p8.PostTypeId = 1
        AND p8.LastEditDate IS NOT NULL
    ) AS AvgDaysToEdit,
    (
        SELECT AVG(p9.ViewCount)
        FROM Posts p9
        WHERE p9.OwnerUserId = u.Id
        AND p9.PostTypeId = 1
    ) AS AvgQuestionViewsAllTime
FROM Users u
LEFT JOIN Posts p ON u.Id = p.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN Comments c ON u.Id = c.UserId
LEFT JOIN PostHistory ph ON u.Id = ph.UserId
LEFT JOIN (
    SELECT DISTINCT p1.Id, t1.TagName
    FROM Posts p1
    JOIN (
        SELECT DISTINCT Id, UNNEST(string_to_array(SUBSTRING(Tags, 2, LENGTH(Tags) - 2), '><')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags != ''
    ) t1 ON t1.Id = p1.Id
    WHERE p1.PostTypeId = 1
) t ON t.Id = p.Id
WHERE u.CreationDate >= '2020-01-01'
GROUP BY u.Id, u.DisplayName, u.Reputation
HAVING COUNT(DISTINCT p.Id) > 0
AND (
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0
    OR COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) > 0
)
ORDER BY u.Reputation DESC, TotalPosts DESC
LIMIT 1000