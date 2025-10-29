-- {"query": "2965.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1674} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        1 AS Level,
        ARRAY[t.TagName] AS Ancestors
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
    UNION ALL
    SELECT
        t2.Id,
        t2.TagName,
        r.Level + 1,
        r.Ancestors || t2.TagName
    FROM Tags t2
    JOIN RecursiveTagHierarchy r ON t2.WikiPostId = r.Id
    WHERE r.Level < 3
),
UserPostStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
        AVG(COALESCE(p.Score,0)) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        SUM(COALESCE(vt2.UpVotes, 0)) AS TotalUpVotes,
        SUM(COALESCE(vt2.DownVotes, 0)) AS TotalDownVotes,
        MAX(b.Date) FILTER (WHERE b.Class = 1) AS LastGoldBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 2) AS LastSilverBadgeDate,
        MAX(b.Date) FILTER (WHERE b.Class = 3) AS LastBronzeBadgeDate,
        COALESCE(u.Location, 'Unknown') AS Location
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId IN (1, 2)
    LEFT JOIN (
        SELECT 
            v.UserId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.UserId
    ) vt2 ON vt2.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Location
),
PostWithRanks AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (
            PARTITION BY p.OwnerUserId, p.PostTypeId 
            ORDER BY p.Score DESC NULLS LAST, p.ViewCount DESC NULLS LAST, p.CreationDate DESC
        ) AS RankByUserPostType,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId, p.PostTypeId) AS TotalPostsByUserAndType
    FROM Posts p
    WHERE p.PostTypeId IN (1,2)
),
TopPostsPerUser AS (
    SELECT *
    FROM PostWithRanks
    WHERE RankByUserPostType = 1
),
CorrelationCTE AS (
    SELECT
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.DisplayName,
        (
            SELECT COUNT(*)
            FROM Comments c
            WHERE c.PostId = p.Id AND c.CreationDate > p.CreationDate
              AND (c.UserId IS NULL OR c.UserId <> p.OwnerUserId)
        ) AS CommentsCountAfterPost,
        EXISTS (
            SELECT 1 
            FROM Votes v
            JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
            WHERE v.PostId = p.Id AND vt.Name = 'Favorite'
        ) AS HasFavoriteVote,
        COALESCE(p.Tags, '') AS Tags,
        -- Extract array of tags from the string pattern '<tag1><tag2><tag3>'
        regexp_split_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><') AS TagArray
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 1
),
UserTagPerformance AS (
    SELECT
        u.Id AS UserId,
        t.TagName,
        COUNT(c.Id) FILTER (WHERE c.PostTypeId = 1) AS QuestionCount,
        AVG(c.Score) FILTER (WHERE c.PostTypeId = 1) AS AvgQuestionScore,
        AVG(c.ViewCount) FILTER (WHERE c.PostTypeId = 1) AS AvgQuestionViews,
        COUNT(c.Id) FILTER (WHERE c.PostTypeId = 2) AS AnswerCount,
        AVG(c.Score) FILTER (WHERE c.PostTypeId = 2) AS AvgAnswerScore
    FROM Users u
    LEFT JOIN Posts c ON c.OwnerUserId = u.Id
    LEFT JOIN RecursiveTagHierarchy t ON t.TagName = ANY(regexp_split_to_array(substring(c.Tags from 2 for char_length(c.Tags)-2), '><'))
    GROUP BY u.Id, t.TagName
),
CombinedResults AS (
    SELECT 
        ups.UserId,
        ups.DisplayName,
        ups.QuestionCount,
        ups.AnswerCount,
        ups.AvgPostScore,
        ups.TotalUpVotes,
        ups.TotalDownVotes,
        ups.LastGoldBadgeDate,
        ups.LastSilverBadgeDate,
        ups.LastBronzeBadgeDate,
        ups.Location,
        utp.TagName,
        utp.QuestionCount AS TagQuestionCount,
        utp.AvgQuestionScore,
        utp.AvgQuestionViews,
        utp.AnswerCount AS TagAnswerCount,
        utp.AvgAnswerScore,
        tp.Id AS TopPostId,
        tp.Title AS TopPostTitle,
        tp.Score AS TopPostScore,
        tp.ViewCount AS TopPostViews
    FROM UserPostStats ups
    LEFT JOIN UserTagPerformance utp ON utp.UserId = ups.UserId
    LEFT JOIN TopPostsPerUser tp ON tp.OwnerUserId = ups.UserId AND tp.RankByUserPostType = 1
    WHERE ups.QuestionCount > 5
        AND (utp.TagName IS NOT NULL OR utp.TagName IS NULL)
)
SELECT 
    cr.UserId,
    cr.DisplayName,
    cr.Location,
    CONCAT(cr.QuestionCount, ' questions / ', cr.AnswerCount, ' answers') AS PostRatio,
    ROUND(cr.AvgPostScore, 2) AS AveragePostScore,
    cr.TotalUpVotes,
    cr.TotalDownVotes,
    COALESCE(cr.LastGoldBadgeDate::date::text, 'No Gold Badge') AS LastGoldBadgeDate,
    COALESCE(cr.LastSilverBadgeDate::date::text, 'No Silver Badge') AS LastSilverBadgeDate,
    COALESCE(cr.LastBronzeBadgeDate::date::text, 'No Bronze Badge') AS LastBronzeBadgeDate,
    COALESCE(cr.TagName, 'No specific tag') AS FavoriteTag,
    COALESCE(cr.TagQuestionCount, 0) AS TagQuestions,
    ROUND(COALESCE(cr.AvgQuestionScore,0), 2) AS AvgQuestionScoreForTag,
    ROUND(COALESCE(cr.AvgQuestionViews,0), 2) AS AvgQuestionViewsForTag,
    COALESCE(cr.TagAnswerCount, 0) AS TagAnswers,
    ROUND(COALESCE(cr.AvgAnswerScore,0), 2) AS AvgAnswerScoreForTag,
    cr.TopPostId,
    LEFT(cr.TopPostTitle, 100) AS TopPostTitleSnippet,
    cr.TopPostScore,
    cr.TopPostViews
FROM CombinedResults cr
WHERE cr.TopPostScore IS NOT NULL
ORDER BY cr.AvgPostScore DESC NULLS LAST, cr.TotalUpVotes DESC, cr.QuestionCount DESC
LIMIT 100;
