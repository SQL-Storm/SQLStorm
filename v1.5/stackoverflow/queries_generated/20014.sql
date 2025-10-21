-- {"query": "20014.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1568} 

WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        p.Id AS PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.CreationDate AS PostCreationDate,
        p.Tags,
        p.OwnerUserId,
        CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE p.ParentId END AS QuestionId
    FROM
        Users u
    JOIN
        Posts p ON u.Id = p.OwnerUserId
    WHERE
        u.Reputation > 1000 AND p.PostTypeId IN (1, 2) -- Questions and Answers
        AND p.CommunityOwnedDate IS NULL
        AND u.CreationDate < (CURRENT_TIMESTAMP - INTERVAL '2 year')
),
UserStats AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        UserCreationDate,
        COUNT(PostId) AS TotalPosts,
        SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(Score) AS TotalScore,
        AVG(CASE WHEN PostTypeId = 2 THEN Score ELSE NULL END) AS AvgAnswerScore,
        SUM(CASE WHEN PostTypeId = 1 THEN ViewCount ELSE 0 END) AS TotalQuestionViews,
        SUM(CommentCount) AS TotalCommentCount,
        SUM(COALESCE(FavoriteCount, 0)) AS TotalFavoriteCount
    FROM
        UserActivity
    GROUP BY
        UserId, DisplayName, Reputation, UserCreationDate
),
RankedAnswers AS (
    SELECT
        a.OwnerUserId,
        a.PostId AS AnswerId,
        a.Score AS AnswerScore,
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.ViewCount AS QuestionViewCount,
        q.Tags AS QuestionTags,
        EXTRACT(EPOCH FROM (a.PostCreationDate - q.PostCreationDate)) / 3600.0 AS HoursToAnswer,
        ROW_NUMBER() OVER(PARTITION BY q.Id ORDER BY a.PostCreationDate) AS AnswerChronologicalRank,
        RANK() OVER(PARTITION BY q.Id ORDER BY a.Score DESC, a.PostCreationDate) AS AnswerScoreRank
    FROM
        UserActivity a
    JOIN
        Posts q ON a.QuestionId = q.Id AND q.PostTypeId = 1
    WHERE
        a.PostTypeId = 2 AND a.OwnerUserId IS NOT NULL
),
UserAnswerPerformance AS (
    SELECT
        OwnerUserId,
        AVG(HoursToAnswer) AS AvgHoursToAnswer,
        COUNT(CASE WHEN AnswerChronologicalRank = 1 THEN 1 END) AS FirstAnswerCount,
        SUM(CASE WHEN AnswerScoreRank = 1 THEN 1 ELSE 0 END) AS TopRankedAnswerCount,
        MAX(AnswerScore) AS MaxAnswerScore,
        AVG(QuestionViewCount) AS AvgViewCountOfAnsweredQuestions
    FROM
        RankedAnswers
    WHERE HoursToAnswer > 0
    GROUP BY
        OwnerUserId
),
UserBadgeInfo AS (
    SELECT
        UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MAX(CASE WHEN Name = 'Strunk & White' THEN Date ELSE NULL END) AS StrunkAndWhiteDate
    FROM
        Badges
    GROUP BY
        UserId
)
SELECT
    us.DisplayName,
    us.Reputation,
    us.QuestionCount,
    us.AnswerCount,
    uap.FirstAnswerCount,
    ubi.GoldBadges,
    (
        SELECT STRING_AGG(b.Name, ', ' ORDER BY b.Date DESC)
        FROM (
            SELECT Name, Date FROM Badges WHERE UserId = us.UserId AND Class = 1 LIMIT 3
        ) b
    ) AS LastThreeGoldBadges,
    CAST(us.AvgAnswerScore AS DECIMAL(10, 2)) AS AvgAnswerScore,
    CAST(uap.AvgHoursToAnswer AS DECIMAL(10, 2)) AS AvgHoursToAnswer,
    DENSE_RANK() OVER(ORDER BY (us.Reputation * 0.1 + us.TotalScore * 0.2 + COALESCE(uap.TopRankedAnswerCount, 0) * 100 + COALESCE(ubi.GoldBadges, 0) * 500) DESC) AS OverallRank,
    NTILE(100) OVER(ORDER BY us.Reputation DESC) AS ReputationPercentile,
    CASE
        WHEN us.AnswerCount > us.QuestionCount * 5 AND us.AvgAnswerScore > 10 THEN 'Answer Specialist'
        WHEN us.QuestionCount > us.AnswerCount * 2 AND us.TotalQuestionViews > 1000000 THEN 'Question Prolific'
        WHEN ubi.GoldBadges > 10 THEN 'Badge Collector'
        ELSE 'General Contributor'
    END AS UserProfile,
    (
        SELECT SUBSTRING(q.Tags FROM 2 FOR POSITION('>' IN q.Tags) - 2)
        FROM Posts a
        JOIN Posts q ON a.ParentId = q.Id
        WHERE a.OwnerUserId = us.UserId AND a.Score = uap.MaxAnswerScore
        ORDER BY a.CreationDate DESC
        LIMIT 1
    ) AS TopAnswerPrimaryTag,
    CONCAT('User since ', TO_CHAR(us.UserCreationDate, 'Mon YYYY'), ', ', (CURRENT_DATE - us.UserCreationDate::date) / 365, ' years ago') AS UserTenureSummary
FROM
    UserStats us
LEFT JOIN
    UserAnswerPerformance uap ON us.UserId = uap.OwnerUserId
LEFT JOIN
    UserBadgeInfo ubi ON us.UserId = ubi.UserId
WHERE
    us.AnswerCount > 50
    AND uap.AvgHoursToAnswer < 72
    AND us.Reputation > (SELECT AVG(Reputation) FROM Users)
    AND ubi.GoldBadges > 0
    AND EXISTS (
        SELECT 1
        FROM Comments c
        WHERE c.UserId = us.UserId AND c.Score > 5
    )
ORDER BY
    OverallRank
LIMIT 250;
