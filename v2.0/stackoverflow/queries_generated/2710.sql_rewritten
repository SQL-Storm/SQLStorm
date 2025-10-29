-- {"query": "2710.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1523} 
WITH 
-- Get users with their badge summary and rank by reputation
UserBadgeSummary AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        RANK() OVER (ORDER BY u.Reputation DESC) AS ReputationRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
-- Filter top 100 users by reputation
TopUsers AS (
    SELECT * FROM UserBadgeSummary WHERE ReputationRank <= 100
),
-- Aggregate posts info per user (questions and answers), with window function
UserPostStats AS (
    SELECT 
        p.OwnerUserId AS UserId,
        COUNT(*) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(*) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.ViewCount) FILTER (WHERE p.PostTypeId = 1) AS MaxQuestionViewCount,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalFavorites,
        SUM(COALESCE(p.AnswerCount,0)) FILTER (WHERE p.PostTypeId = 1) AS SumAnswerCounts,
        -- Rank user answers by score descending
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS AnswerRank
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId, p.PostTypeId, p.Id, p.Score, p.ViewCount, p.FavoriteCount, p.AnswerCount
),
-- Select top 3 highest scored answers for each user
TopAnswers AS (
    SELECT ups.UserId, p.Id AS AnswerId, p.Score, p.CreationDate, p.ParentId AS QuestionId
    FROM UserPostStats ups
    JOIN Posts p ON p.OwnerUserId = ups.UserId AND p.PostTypeId = 2
    WHERE ups.AnswerRank <= 3
),
-- Get title and tags of questions related to top answers
AnswerQuestions AS (
    SELECT ta.AnswerId, q.Title, q.Tags,
    -- Total number of comments on question and answers via correlated subquery
        (
            SELECT COUNT(*) FROM Comments c WHERE c.PostId IN (ta.QuestionId, ta.AnswerId)
        ) AS TotalComments,
    -- Whether the question is closed (has closedDate) with COALESCE for NULL logic
        COALESCE(q.ClosedDate IS NOT NULL, FALSE) AS IsClosed
    FROM TopAnswers ta
    JOIN Posts q ON q.Id = ta.QuestionId
),
-- Get latest edit date and last editor info for user's posts
UserPostEditInfo AS (
    SELECT
        p.OwnerUserId AS UserId,
        MAX(p.LastEditDate) AS LatestEditDate,
        STRING_AGG(DISTINCT COALESCE(u.DisplayName, p.LastEditorDisplayName), ', ') AS Editors
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.LastEditorUserId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
-- Rank tags by count and select top 5 tags among questions of top users
TopUserTags AS (
    SELECT 
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) AS TagName,
        COUNT(*) AS TagCount
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.OwnerUserId IN (SELECT UserId FROM TopUsers)
      AND p.Tags IS NOT NULL
    GROUP BY TagName
    ORDER BY TagCount DESC
    LIMIT 5
),
-- Combine all info per top user including posts, badges, edits, and tags
FinalUserReport AS (
    SELECT 
        tu.UserId,
        tu.DisplayName,
        tu.Reputation,
        tu.GoldBadges,
        tu.SilverBadges,
        tu.BronzeBadges,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AvgPostScore,
        ups.MaxQuestionViewCount,
        ups.TotalFavorites,
        ups.SumAnswerCounts,
        COALESCE(upedit.LatestEditDate, '1970-01-01') AS LatestEditDate,
        COALESCE(upedit.Editors, 'No Editors') AS Editors,
        ARRAY_AGG(DISTINCT tut.TagName) FILTER (WHERE tut.TagName IS NOT NULL) AS FavoriteTags
    FROM TopUsers tu
    LEFT JOIN (
        SELECT 
            OwnerUserId, 
            COUNT(*) FILTER (WHERE PostTypeId = 1) AS QuestionCount,
            COUNT(*) FILTER (WHERE PostTypeId = 2) AS AnswerCount,
            AVG(Score) FILTER (WHERE PostTypeId IN (1,2)) AS AvgPostScore,
            MAX(ViewCount) FILTER (WHERE PostTypeId = 1) AS MaxQuestionViewCount,
            SUM(FavoriteCount) FILTER (WHERE PostTypeId =1) AS TotalFavorites,
            SUM(COALESCE(AnswerCount,0)) FILTER (WHERE PostTypeId =1) AS SumAnswerCounts
        FROM Posts
        WHERE OwnerUserId IN (SELECT UserId FROM TopUsers)
        GROUP BY OwnerUserId
    ) ups ON ups.OwnerUserId = tu.UserId
    LEFT JOIN UserPostEditInfo upedit ON upedit.UserId = tu.UserId
    LEFT JOIN TopUserTags tut ON TRUE
    GROUP BY tu.UserId, tu.DisplayName, tu.Reputation, tu.GoldBadges, tu.SilverBadges, tu.BronzeBadges,
        ups.QuestionCount, ups.AnswerCount, ups.AvgPostScore, ups.MaxQuestionViewCount, ups.TotalFavorites,
        ups.SumAnswerCounts, upedit.LatestEditDate, upedit.Editors
)
SELECT 
    fur.*,
    -- Compute a complex metric combining reputation, badges, post activity, and recency
    (fur.Reputation * 0.5) + 
    (fur.GoldBadges * 15) + 
    (fur.SilverBadges * 7) + 
    (fur.BronzeBadges * 3) + 
    (COALESCE(fur.QuestionCount,0) * 2) + 
    (COALESCE(fur.AnswerCount,0) * 3) + 
    (COALESCE(fur.TotalFavorites,0) * 4) -
    (EXTRACT(EPOCH FROM (cast('2024-10-01 12:34:56' as timestamp) - fur.LatestEditDate))/86400 * 0.1) AS UserScore
FROM FinalUserReport fur
ORDER BY UserScore DESC, Reputation DESC
LIMIT 50;