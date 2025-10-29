-- {"query": "4006.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1589} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.CreationDate AS EditDate,
        ph.PostHistoryTypeId,
        ph.Comment,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.UserId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
),
UserContributionSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AveragePostScore,
        MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName
),
HighReputationContributors AS (
    SELECT
        UserId,
        DisplayName,
        TotalPosts,
        QuestionsAsked,
        AnswersGiven,
        BadgesEarned,
        GoldBadges,
        SilverBadges,
        BronzeBadges,
        TotalPostScore,
        AveragePostScore,
        LastPostDate
    FROM UserContributionSummary
    WHERE TotalPosts > 100 AND AveragePostScore > 5
),
RecentClosedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionCreationDate,
        p.ClosedDate,
        u.DisplayName AS CloserDisplayName,
        crt.Name AS CloseReason,
        DATEDIFF(day, p.CreationDate, p.ClosedDate) AS TimeToCloseDays,
        ROW_NUMBER() OVER(PARTITION BY p.Id ORDER BY ph.CreationDate DESC) as rn_close
    FROM Posts p
    JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId = 10
    LEFT JOIN Users u ON ph.UserId = u.Id
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE p.PostTypeId = 1 AND p.ClosedDate IS NOT NULL AND DATEDIFF(day, p.CreationDate, GETDATE()) < 30
),
AnswerQuality AS (
    SELECT
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score AS AnswerScore,
        ROW_NUMBER() OVER(PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate ASC) as rank_in_question,
        CASE
            WHEN a.Score > (SELECT AVG(Score) FROM Posts WHERE ParentId = a.ParentId AND PostTypeId = 2) THEN 'Above Average'
            WHEN a.Score < (SELECT AVG(Score) FROM Posts WHERE ParentId = a.ParentId AND PostTypeId = 2) THEN 'Below Average'
            ELSE 'Average'
        END AS ScoreCategory
    FROM Posts a
    WHERE a.PostTypeId = 2
),
QuestionMetrics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.Score AS QuestionScore,
        q.AnswerCount,
        q.FavoriteCount,
        q.CreationDate AS QuestionCreationDate,
        aq.AnswerId AS BestAnswerId,
        aq.AnswerScore AS BestAnswerScore,
        DATEDIFF(hour, q.CreationDate, q.LastActivityDate) AS TimeToLastActivityHours,
        CASE
            WHEN q.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Exists'
            ELSE 'No Accepted Answer'
        END AS AcceptanceStatus,
        COALESCE(aq.ScoreCategory, 'No Answers') AS TopAnswerQuality
    FROM Posts q
    LEFT JOIN AnswerQuality aq ON q.Id = aq.QuestionId AND aq.rank_in_question = 1
    WHERE q.PostTypeId = 1
)
SELECT
    q.QuestionId,
    q.Title,
    q.QuestionCreationDate,
    q.QuestionScore,
    q.AnswerCount,
    q.FavoriteCount,
    q.AcceptanceStatus,
    q.TopAnswerQuality,
    q.BestAnswerId,
    q.BestAnswerScore,
    q.TimeToLastActivityHours,
    rcq.ClosedDate,
    rcq.CloserDisplayName,
    rcq.CloseReason,
    rcq.TimeToCloseDays,
    COALESCE(hrc.DisplayName, 'N/A') AS HighReputationOwner,
    CASE
        WHEN q.BestAnswerScore > 50 AND q.QuestionScore > 100 THEN 'Highly Rated Question with High Quality Answer'
        WHEN q.AnswerCount > 10 AND q.FavoriteCount > 5 THEN 'Popular Question'
        WHEN q.AcceptanceStatus = 'No Accepted Answer' AND q.AnswerCount > 0 AND q.QuestionScore < 0 THEN 'Unaccepted Answered Question with Negative Score'
        ELSE 'Standard Question'
    END AS QuestionProfile,
    LOWER(SUBSTRING(q.Title, 1, 10)) AS TitlePrefix,
    q.QuestionScore + COALESCE(q.BestAnswerScore, 0) AS TotalEngagementScore,
    CASE
        WHEN q.BestAnswerScore IS NULL THEN 'No Answers Provided'
        WHEN q.BestAnswerScore BETWEEN 0 AND 10 THEN 'Low Score Answer'
        WHEN q.BestAnswerScore > 10 AND q.BestAnswerScore <= 50 THEN 'Medium Score Answer'
        WHEN q.BestAnswerScore > 50 THEN 'High Score Answer'
    END AS AnswerScoreBucket
FROM QuestionMetrics q
LEFT JOIN RecentClosedQuestions rcq ON q.QuestionId = rcq.QuestionId AND rcq.rn_close = 1
LEFT JOIN HighReputationContributors hrc ON q.QuestionId = (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = hrc.UserId AND p.PostTypeId = 1 ORDER BY p.CreationDate DESC LIMIT 1)
WHERE q.QuestionScore > 0 OR q.AnswerCount > 0
ORDER BY q.QuestionCreationDate DESC
LIMIT 100;
