-- {"query": "4674.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1155} 

WITH RankedAnswers AS (
    SELECT
        p.Id AS PostId,
        p.ParentId AS QuestionId,
        p.OwnerUserId AS AnswererUserId,
        p.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER(PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM Posts p
    WHERE p.PostTypeId = 2 -- Answers
),
HighReputationUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation > 10000
    GROUP BY u.Id, u.DisplayName, u.Reputation
    HAVING COUNT(DISTINCT b.Id) > 5
),
QuestionStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Score AS QuestionScore,
        COALESCE(d.DisplayName, 'Community') AS QuestionOwnerDisplayName,
        LAG(q.CreationDate, 1, q.CreationDate) OVER (ORDER BY q.CreationDate) AS PreviousQuestionCreationDate,
        SUM(COALESCE(c.Score, 0)) OVER (PARTITION BY q.Id) AS TotalCommentScoreOnQuestion,
        COUNT(DISTINCT l.RelatedPostId) AS NumberOfLinkedPosts,
        CASE
            WHEN q.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN q.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
            ELSE 'Open'
        END AS QuestionStatus
    FROM Posts q
    LEFT JOIN Users d ON q.OwnerUserId = d.Id
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN PostLinks l ON q.Id = l.PostId AND l.LinkTypeId = 1 -- Linked
    WHERE q.PostTypeId = 1 -- Questions
    GROUP BY
        q.Id,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        q.AnswerCount,
        q.FavoriteCount,
        q.ViewCount,
        q.Score,
        d.DisplayName,
        q.ClosedDate,
        q.CommunityOwnedDate
),
UserContribution AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswerCount,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    GROUP BY u.Id, u.DisplayName
)
SELECT
    qs.QuestionId,
    qs.Title AS QuestionTitle,
    qs.QuestionCreationDate,
    qs.QuestionOwnerUserId,
    COALESCE(u.DisplayName, qs.QuestionOwnerDisplayName) AS ActualQuestionOwnerName,
    qs.AnswerCount,
    qs.FavoriteCount,
    qs.ViewCount,
    qs.QuestionScore,
    qs.QuestionStatus,
    hru.DisplayName AS HighReputationDisplayName,
    hru.Reputation AS HighReputationUserReputation,
    ra.AnswererUserId AS TopAnswererId,
    ra.AnswerCreationDate AS TopAnswerDate,
    (qs.ViewCount * 1.5 + qs.FavoriteCount * 3) AS WeightedEngagement,
    CASE
        WHEN qs.QuestionCreationDate < qs.PreviousQuestionCreationDate THEN 'Earlier Than Previous'
        ELSE 'Later Than Or Same As Previous'
    END AS TimeRelativeToPrevious,
    qs.TotalCommentScoreOnQuestion,
    qs.NumberOfLinkedPosts,
    uc.QuestionCount AS UserTotalQuestions,
    uc.AnswerCount AS UserTotalAnswers,
    uc.TotalPostScore AS UserTotalScore,
    uc.LastPostDate AS UserLastPostActivity,
    CASE
        WHEN qs.AnswerCount > 0 AND qs.QuestionScore > 0 AND qs.ViewCount > 100 THEN 'Popular & Answered'
        WHEN qs.AnswerCount = 0 AND qs.QuestionScore < 0 THEN 'Unanswered & Negative Score'
        ELSE 'Other'
    END AS QuestionCategorization
FROM QuestionStats qs
LEFT JOIN RankedAnswers ra ON qs.QuestionId = ra.QuestionId AND ra.rn = 1
LEFT JOIN HighReputationUsers hru ON qs.QuestionOwnerUserId = hru.UserId
LEFT JOIN UserContribution uc ON qs.QuestionOwnerUserId = uc.UserId
ORDER BY qs.QuestionCreationDate DESC
LIMIT 100;
