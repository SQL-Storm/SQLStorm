WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE 0 END) AS TotalQuestionScore,
        SUM(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE 0 END) AS TotalAnswerScore,
        MAX(b.Date) AS LastBadgeEarnedDate,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesReceived,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesReceived,
        ROW_NUMBER() OVER (ORDER BY (COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) + COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END)) DESC) AS Rank
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    WHERE u.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01' AS DATE) - INTERVAL '1 year')
    GROUP BY u.Id, u.DisplayName
),
RecentTopQuestions AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.ViewCount,
        p.AnswerCount,
        p.Score,
        p.OwnerUserId,
        ph.CreationDate AS LastEditedDate
    FROM Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (5, 8)
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= DATE_TRUNC('month', CAST('2024-10-01' AS DATE) - INTERVAL '6 months')
    ORDER BY p.Score DESC
    LIMIT 100
)
SELECT 
    ua.UserId,
    ua.DisplayName,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.TotalQuestionScore,
    ua.TotalAnswerScore,
    ua.LastBadgeEarnedDate,
    ua.UpVotesReceived,
    ua.DownVotesReceived,
    rtq.QuestionId,
    rtq.Title,
    rtq.ViewCount,
    rtq.AnswerCount,
    rtq.Score,
    rtq.LastEditedDate
FROM UserActivity ua
LEFT JOIN RecentTopQuestions rtq ON ua.UserId = rtq.OwnerUserId
WHERE ua.Rank <= 10
ORDER BY ua.Rank, rtq.Score DESC;