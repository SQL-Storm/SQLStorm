-- {"query": "43057.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "nova-premier", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2135, "output_tokens": 865} 

WITH UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersProvided,
        SUM(p.Score) AS TotalPostScore,
        AVG(p.Score) AS AvgPostScore,
        COUNT(DISTINCT ph.Id) AS EditCount,
        MAX(ph.CreationDate) AS LastEditDate,
        RANK() OVER (ORDER BY SUM(p.Score) DESC) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    WHERE u.CreationDate > '2020-01-01'
    GROUP BY u.Id, u.DisplayName
),
TopQuestions AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        p.ViewCount,
        p.Score,
        p.Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS QuestionRank
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.CreationDate > '2022-01-01'
),
PerformanceData AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.BadgeCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.TotalPosts,
        ua.QuestionsAsked,
        ua.AnswersProvided,
        ua.TotalPostScore,
        ua.AvgPostScore,
        ua.EditCount,
        ua.LastEditDate,
        tq.PostId,
        tq.Title,
        tq.ViewCount AS TopQuestionViewCount,
        tq.Score AS TopQuestionScore,
        tq.Tags AS TopQuestionTags
    FROM UserActivity ua
    LEFT JOIN TopQuestions tq ON ua.UserId = tq.OwnerUserId AND tq.QuestionRank = 1
    WHERE ua.UserRank <= 100
)
SELECT 
    pd.UserId,
    pd.DisplayName,
    pd.BadgeCount,
    pd.GoldBadges,
    pd.SilverBadges,
    pd.BronzeBadges,
    pd.TotalPosts,
    pd.QuestionsAsked,
    pd.AnswersProvided,
    pd.TotalPostScore,
    pd.AvgPostScore,
    pd.EditCount,
    pd.LastEditDate,
    pd.PostId,
    pd.Title,
    pd.TopQuestionViewCount,
    pd.TopQuestionScore,
    STRING_TO_ARRAY(SUBSTRING(pd.TopQuestionTags, 2, LENGTH(pd.TopQuestionTags)-2), '><') AS TagList
FROM PerformanceData pd
ORDER BY pd.TotalPostScore DESC, pd.EditCount DESC;
