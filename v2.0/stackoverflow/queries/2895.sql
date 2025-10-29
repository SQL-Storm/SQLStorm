-- {"query": "2895.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1428} 
WITH RecursiveUserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        COUNT(b.Id) AS BadgeCount,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Class) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, b.Class
),
RankedPosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.AcceptedAnswerId,
        COALESCE(p.Tags, '') AS Tags,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.CreationDate ASC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS TotalPostsByUser
    FROM Posts p
    WHERE p.PostTypeId IN (1,2) -- only Questions and Answers
),
PostHistoryLatestEdits AS (
    SELECT DISTINCT ON (ph.PostId)
        ph.PostId,
        ph.CreationDate AS LastEditDate,
        ph.UserId AS EditorUserId,
        ph.Comment,
        ph.PostHistoryTypeId
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9) -- edits of titles, bodies, tags and rollbacks
    ORDER BY ph.PostId, ph.CreationDate DESC
),
DuplicateLinksCTE AS (
    SELECT DISTINCT pl.PostId, pl.RelatedPostId
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3 -- duplicate link type
),
UserPostAggregates AS (
    SELECT
        p.OwnerUserId,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
        SUM(p.FavoriteCount) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionFavorites,
        MAX(p.Score) FILTER (WHERE p.PostTypeId = 2) AS MaxAnswerScore
    FROM Posts p
    GROUP BY p.OwnerUserId
),
ComplexUserSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(ups.QuestionCount,0) AS Questions,
        COALESCE(ups.AnswerCount,0) AS Answers,
        COALESCE(ups.AvgQuestionScore,0) AS AvgQScore,
        COALESCE(ups.AvgAnswerScore,0) AS AvgAScore,
        COALESCE(ups.TotalQuestionFavorites,0) AS FavCount,
        COALESCE(ups.MaxAnswerScore,0) AS MaxAnswer,
        COALESCE(rubs.BadgeCount, 0) AS GoldBadges,
        (SELECT COUNT(ph.Id)
         FROM PostHistory ph
         WHERE ph.UserId = u.Id
           AND ph.PostHistoryTypeId = 10 -- Post Closed
           AND ph.CreationDate > cast('2024-10-01' as date) - INTERVAL '365 days') AS ClosuresPastYear
    FROM Users u
    LEFT JOIN UserPostAggregates ups ON u.Id = ups.OwnerUserId
    LEFT JOIN (
        SELECT UserId, SUM(CASE WHEN Class = 1 THEN BadgeCount ELSE 0 END) AS BadgeCount
        FROM RecursiveUserBadgeSummary
        GROUP BY UserId
    ) rubs ON u.Id = rubs.UserId
),
TagExtraction AS (
    SELECT p.Id AS PostId, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS Tag
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL
),
TagPopularityWindow AS (
    SELECT
        Tag,
        COUNT(*) AS QuestionCount,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS PopularityRank
    FROM TagExtraction
    GROUP BY Tag
),
TopTags AS (
    SELECT Tag FROM TagPopularityWindow WHERE PopularityRank <= 10
),
QuestionsWithTopTags AS (
    SELECT DISTINCT p.*
    FROM Posts p
    JOIN TagExtraction t ON p.Id = t.PostId
    JOIN TopTags tt ON t.Tag = tt.Tag
    WHERE p.PostTypeId = 1
),
ComplexQueryFinal AS (
    SELECT
        c.UserId,
        c.DisplayName,
        c.Questions,
        c.Answers,
        c.AvgQScore,
        c.AvgAScore,
        c.FavCount,
        c.MaxAnswer,
        c.GoldBadges,
        c.ClosuresPastYear,
        COUNT(DISTINCT p.Id) FILTER (
            WHERE p.Id IN (SELECT AcceptedAnswerId FROM Posts WHERE AcceptedAnswerId IS NOT NULL)
        ) AS AcceptedAnswersByUser,
        COUNT(DISTINCT dl.RelatedPostId) AS DuplicateCountLinked,
        AVG(p.Score) FILTER (WHERE p.PostTypeId = 1 AND p.LastActivityDate > cast('2024-10-01' as date) - INTERVAL '180 days') AS RecentQuestionAvgScore,
        STRING_AGG(DISTINCT tt.Tag, ', ') AS TopTagsUsed,
        MAX(phl.LastEditDate) AS MostRecentEditDate,
        MAX(COALESCE(u.LastAccessDate, u.CreationDate)) AS UserLastSeenDate
    FROM ComplexUserSummary c
    LEFT JOIN Posts p ON p.OwnerUserId = c.UserId
    LEFT JOIN DuplicateLinksCTE dl ON dl.PostId = p.Id
    LEFT JOIN QuestionsWithTopTags qtt ON qtt.OwnerUserId = c.UserId
    LEFT JOIN TagExtraction tt ON tt.PostId = p.Id
    LEFT JOIN PostHistoryLatestEdits phl ON phl.PostId = p.Id
    LEFT JOIN Users u ON u.Id = c.UserId
    GROUP BY c.UserId, c.DisplayName, c.Questions, c.Answers, c.AvgQScore, c.AvgAScore, c.FavCount, c.MaxAnswer, c.GoldBadges, c.ClosuresPastYear
)
SELECT *
FROM ComplexQueryFinal
WHERE
    (Answers > 5 OR Questions > 2)
    AND (GoldBadges > 0 OR FavCount > 10)
    AND (RecentQuestionAvgScore > 2 OR AcceptedAnswersByUser > 1)
ORDER BY GoldBadges DESC NULLS LAST, FavCount DESC, Answers DESC
LIMIT 100;