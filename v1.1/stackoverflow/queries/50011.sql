-- {"query": "50011.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 982} 
WITH UserAnswerStats AS (
    -- Aggregate answer-level statistics for each user, including up/down votes
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalAnswerScore,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        AVG(p.CommentCount) AS AvgAnswerCommentCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId = 2 -- Answers
    AND p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 50 -- Only consider users with a significant number of answers
),
QuestionDetails AS (
    -- Correlate answers to their parent questions to get question-specific metrics
    SELECT
        ans.OwnerUserId,
        q.ViewCount,
        q.FavoriteCount,
        q.Tags,
        (ans.CreationDate - q.CreationDate) AS TimeToAnswer,
        CASE WHEN q.AcceptedAnswerId = ans.Id THEN 1 ELSE 0 END AS IsAcceptedAnswer
    FROM Posts ans
    JOIN Posts q ON ans.ParentId = q.Id
    WHERE ans.PostTypeId = 2
    AND q.PostTypeId = 1
    AND ans.OwnerUserId IS NOT NULL
),
AggregatedQuestionStats AS (
    -- Aggregate the question-related metrics for each user
    SELECT
        OwnerUserId,
        AVG(ViewCount) AS AvgQuestionViewCount,
        SUM(FavoriteCount) AS TotalParentQuestionFavorites,
        SUM(IsAcceptedAnswer) AS AcceptedAnswerCount,
        AVG(EXTRACT(EPOCH FROM TimeToAnswer)) AS AvgTimeToAnswerSeconds
    FROM QuestionDetails
    GROUP BY OwnerUserId
),
UserBadgeRank AS (
    -- Rank users based on their badge acquisition time for a specific, difficult badge
    SELECT
        UserId,
        Name AS BadgeName,
        Date AS BadgeDate,
        RANK() OVER(PARTITION BY Name ORDER BY Date ASC) AS BadgeRank
    FROM Badges
    WHERE Class = 1 -- Gold Badges
    AND TagBased = 'f'
)
-- Final SELECT to join all CTEs and compute final rankings
SELECT
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    uas.TotalAnswers,
    aqs.AcceptedAnswerCount,
    CAST(aqs.AcceptedAnswerCount AS DECIMAL) / uas.TotalAnswers AS AcceptanceRatio,
    (uas.TotalUpVotes - uas.TotalDownVotes) AS NetVoteScore,
    aqs.AvgQuestionViewCount,
    aqs.AvgTimeToAnswerSeconds,
    (
        -- Subquery to find the most common tag the user has answered
        SELECT t.TagName
        FROM Posts p
        JOIN Tags t ON p.Tags LIKE '%' || t.TagName || '%'
        WHERE p.OwnerUserId = u.Id AND p.PostTypeId = 2
        GROUP BY t.TagName
        ORDER BY COUNT(*) DESC
        LIMIT 1
    ) AS PrimaryTag,
    ubr.BadgeName AS FirstGoldBadge,
    ubr.BadgeDate AS FirstGoldBadgeDate
FROM Users u
JOIN UserAnswerStats uas ON u.Id = uas.OwnerUserId
JOIN AggregatedQuestionStats aqs ON u.Id = aqs.OwnerUserId
LEFT JOIN UserBadgeRank ubr ON u.Id = ubr.UserId AND ubr.BadgeRank = 1
WHERE
    u.Reputation > (SELECT AVG(Reputation) FROM Users) -- More reputable than average
    AND uas.TotalDownVotes > 0 -- To avoid division by zero and ensure some controversy
    AND (CAST(uas.TotalUpVotes AS DECIMAL) / uas.TotalDownVotes) BETWEEN 50 AND 100 -- High but not perfect up/down vote ratio
    AND aqs.AcceptedAnswerCount > uas.TotalAnswers * 0.2 -- Acceptance rate > 20%
ORDER BY
    (u.Reputation / EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - u.CreationDate))), -- Reputation gain rate
    AcceptanceRatio DESC
LIMIT 200;