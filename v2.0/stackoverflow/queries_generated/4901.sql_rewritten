-- {"query": "4901.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1548} 
WITH UserPostCounts AS (
    SELECT
        OwnerUserId,
        COUNT(Id) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN Score > 500 THEN 1 ELSE 0 END) AS HighScorePosts,
        AVG(Score) AS AverageScore
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
    GROUP BY OwnerUserId
),
PostCreationLag AS (
    SELECT
        Id,
        OwnerUserId,
        CreationDate,
        LAG(CreationDate, 1, CreationDate) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate) AS PreviousPostDate
    FROM Posts
    WHERE OwnerUserId IS NOT NULL
),
InterPostTime AS (
    SELECT
        Id,
        OwnerUserId,
        CreationDate,
        CASE
            WHEN CreationDate = PreviousPostDate THEN INTERVAL '0 seconds'
            ELSE CreationDate - PreviousPostDate
        END AS TimeSinceLastPost
    FROM PostCreationLag
),
UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        upc.TotalPosts,
        upc.QuestionCount,
        upc.AnswerCount,
        upc.HighScorePosts,
        upc.AverageScore,
        CASE
            WHEN upc.TotalPosts > 1000 THEN 'Prolific'
            WHEN upc.TotalPosts > 100 THEN 'Active'
            ELSE 'Developing'
        END AS ActivityLevel,
        COALESCE(ipt.AverageTimeBetweenPosts, INTERVAL '0 seconds') AS AverageTimeBetweenPosts,
        COALESCE(bh.BadgeCount, 0) AS BronzeBadges,
        COALESCE(sh.BadgeCount, 0) AS SilverBadges,
        COALESCE(gh.BadgeCount, 0) AS GoldBadges
    FROM Users u
    LEFT JOIN UserPostCounts upc ON u.Id = upc.OwnerUserId
    LEFT JOIN (
        SELECT OwnerUserId, AVG(TimeSinceLastPost) AS AverageTimeBetweenPosts
        FROM InterPostTime
        GROUP BY OwnerUserId
    ) ipt ON u.Id = ipt.OwnerUserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 3 GROUP BY UserId
    ) bh ON u.Id = bh.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 2 GROUP BY UserId
    ) sh ON u.Id = sh.UserId
    LEFT JOIN (
        SELECT UserId, COUNT(*) AS BadgeCount FROM Badges WHERE Class = 1 GROUP BY UserId
    ) gh ON u.Id = gh.UserId
    WHERE upc.TotalPosts IS NOT NULL
),
RecentQuestionActivity AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate AS QuestionCreationDate,
        p.AnswerCount,
        p.CommentCount,
        p.Score AS QuestionScore,
        ROW_NUMBER() OVER (ORDER BY p.CreationDate DESC) AS RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1
    AND p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '30 days'
),
TopAnswerersForRecentQuestions AS (
    SELECT
        rqa.QuestionId,
        rqa.Title AS QuestionTitle,
        rqa.QuestionCreationDate,
        rqa.AnswerCount AS TotalAnswers,
        rqa.QuestionScore,
        c.UserId AS AnswererUserId,
        u.DisplayName AS AnswererDisplayName,
        COUNT(c.Id) AS AnswersToThisQuestion,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreAnswers,
        MAX(c.CreationDate) AS LastAnswerDate
    FROM RecentQuestionActivity rqa
    JOIN Comments c ON rqa.QuestionId = c.PostId
    JOIN Users u ON c.UserId = u.Id
    WHERE c.UserId IS NOT NULL
    GROUP BY rqa.QuestionId, rqa.Title, rqa.QuestionCreationDate, rqa.AnswerCount, rqa.QuestionScore, c.UserId, u.DisplayName
    HAVING COUNT(c.Id) > 0
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.ActivityLevel,
    uas.AverageScore,
    uas.AverageTimeBetweenPosts,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    COALESCE(ta.QuestionTitle, 'No Recent Activity') AS LastAnsweredQuestionTitle,
    COALESCE(ta.AnswererDisplayName, 'N/A') AS LastAnswerer,
    COALESCE(ta.AnswersToThisQuestion, 0) AS AnswersToLastAnsweredQuestion,
    COALESCE(ta.QuestionScore, 0) AS ScoreOfLastAnsweredQuestion,
    CASE
        WHEN ta.QuestionCreationDate IS NOT NULL THEN
            CASE
                WHEN ta.QuestionCreationDate < cast('2024-10-01 12:34:56' as timestamp) - INTERVAL '7 days' THEN 'Older Than A Week'
                ELSE 'Within A Week'
            END
        ELSE 'No Recent Questions'
    END AS QuestionAgeCategory
FROM UserActivitySummary uas
LEFT JOIN (
    SELECT
        taq.*,
        ROW_NUMBER() OVER (PARTITION BY taq.AnswererUserId ORDER BY taq.LastAnswerDate DESC) AS RN
    FROM TopAnswerersForRecentQuestions taq
) ta ON uas.UserId = ta.AnswererUserId AND ta.RN = 1
WHERE uas.TotalPosts > 10 AND uas.AverageScore IS NOT NULL
UNION
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.ActivityLevel,
    uas.AverageScore,
    uas.AverageTimeBetweenPosts,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    'No Answers Provided' AS LastAnsweredQuestionTitle,
    'N/A' AS LastAnswerer,
    0 AS AnswersToLastAnsweredQuestion,
    0 AS ScoreOfLastAnsweredQuestion,
    'No Recent Questions' AS QuestionAgeCategory
FROM UserActivitySummary uas
WHERE uas.UserId NOT IN (SELECT DISTINCT AnswererUserId FROM TopAnswerersForRecentQuestions)
AND uas.TotalPosts > 10 AND uas.AverageScore IS NOT NULL
ORDER BY Reputation DESC, UserId;