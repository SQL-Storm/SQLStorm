-- {"query": "7507.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2102, "output_tokens": 1704}
WITH UserPostStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS Questions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS Answers,
        COALESCE(SUM(p.Score), 0) AS TotalScore,
        COALESCE(SUM(p.ViewCount), 0) AS TotalViews,
        MAX(p.CreationDate) AS LastPostDate,
        AVG(CAST(p.Score AS DOUBLE PRECISION)) AS AvgScore,
        STRING_AGG(CASE WHEN p.PostTypeId = 1 THEN p.Title END, '; ') AS QuestionTitles,
        COUNT(DISTINCT b.Id) AS BadgesCount,
        STRING_AGG(b.Name, ', ') AS BadgeNames,
        CASE 
            WHEN COUNT(DISTINCT p.Id) > 0 AND COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) > 0 
            THEN CAST(COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS DOUBLE PRECISION) / COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END)
            ELSE NULL 
        END AS AnswerToQuestionRatio,
        ROW_NUMBER() OVER (ORDER BY COALESCE(SUM(p.Score), 0) DESC) AS RankByScore
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
TopUsers AS (
    SELECT * FROM UserPostStats WHERE RankByScore <= 100
),
PostAnalysis AS (
    SELECT 
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        p.OwnerUserId,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.Tags,
        CASE 
            WHEN p.Tags IS NULL OR p.Tags = '' THEN ARRAY[]::text[]
            ELSE regexp_split_to_array(trim(both '<>' FROM p.Tags), '><')
        END AS TagArray,
        CASE 
            WHEN LENGTH(p.Title) > 100 THEN CONCAT(SUBSTRING(p.Title FROM 1 FOR 97), '...')
            ELSE p.Title 
        END AS ShortTitle,
        FLOOR(EXTRACT(EPOCH FROM (TIMESTAMP '2024-10-01 12:34:56' - p.CreationDate)) / 86400) AS DaysSinceCreation,
        CASE 
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            WHEN p.PostTypeId = 3 THEN 'Wiki'
            ELSE 'Other'
        END AS PostType,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) AS CommentCountSubquery,
        CASE 
            WHEN p.Score > 100 THEN 'HighlyVoted'
            WHEN p.Score > 50 THEN 'ModeratelyVoted'
            WHEN p.Score > 10 THEN 'LowVoted'
            ELSE 'NoVotes'
        END AS VoteCategory,
        CASE 
            WHEN p.ViewCount > 10000 THEN 'Viral'
            WHEN p.ViewCount > 1000 THEN 'Popular'
            WHEN p.ViewCount > 100 THEN 'Moderate'
            ELSE 'Low'
        END AS PopularityLevel
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
ComplexVotes AS (
    SELECT 
        v.PostId,
        v.VoteTypeId,
        vt.Name AS VoteTypeName,
        v.UserId,
        u.DisplayName AS VoterName,
        v.CreationDate,
        v.BountyAmount,
        CASE 
            WHEN v.VoteTypeId IN (1, 2, 3, 5, 8, 9) THEN 'VotingAction'
            WHEN v.VoteTypeId IN (6, 7, 10, 11, 12) THEN 'ModerationAction'
            ELSE 'Other'
        END AS ActionCategory,
        (SELECT COUNT(*) FROM Votes v2 WHERE v2.PostId = v.PostId AND v2.VoteTypeId IN (1, 2, 3, 5)) AS VoteSummary
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Users u ON v.UserId = u.Id
),
TagAnalysis AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COALESCE(p.Title, 'No Title') AS WikiTitle,
        CASE 
            WHEN t.Count > 100 THEN 'HighInterest'
            WHEN t.Count > 50 THEN 'MediumInterest'
            WHEN t.Count > 10 THEN 'LowInterest'
            ELSE 'VeryLowInterest'
        END AS InterestLevel,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM Tags t
    LEFT JOIN Posts p ON t.WikiPostId = p.Id
)
SELECT 
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT CASE WHEN up.RankByScore <= 10 THEN up.UserId END) AS Top10Users,
    COUNT(DISTINCT CASE WHEN pa.PostType = 'Question' THEN pa.PostId END) AS TotalQuestions,
    COUNT(DISTINCT CASE WHEN pa.PostType = 'Answer' THEN pa.PostId END) AS TotalAnswers,
    AVG(pa.Score) AS AverageScore,
    MAX(pa.ViewCount) AS MaxViews,
    MIN(pa.DaysSinceCreation) AS MinDaysSinceCreation,
    (SELECT COUNT(*) FROM TopUsers) + (SELECT COUNT(*) FROM PostAnalysis) AS SetOperatortest,
    SUBSTRING(COALESCE(MAX(pa.Title), 'N/A') || ' - ' || COALESCE(MIN(pa.Title), 'No Title') FROM 1 FOR 100) AS TitleConcat,
    (SELECT AVG(TotalScore) FROM TopUsers) / NULLIF((SELECT AVG(Questions) FROM TopUsers WHERE Questions > 0), 0) AS AvgScorePerQuestion,
    COALESCE(
        (SELECT AVG(pa2.Score) FROM PostAnalysis pa2 WHERE pa2.OwnerUserId = up.UserId), 
        0
    ) AS UserAverageScore,
    (SELECT COUNT(*) FROM TagAnalysis WHERE TagRank <= 50) AS HighInterestTags,
    CASE 
        WHEN COUNT(*) > 0 AND COUNT(DISTINCT u.UserId) > 0 THEN 
            CAST(COUNT(DISTINCT u.PostId) AS DOUBLE PRECISION) / NULLIF(COUNT(*), 0)
        ELSE 0 
    END AS PostsPerUserRatio
FROM (
    SELECT DISTINCT u.UserId, u.PostId FROM (
        SELECT t.UserId, p.Id AS PostId FROM TopUsers t
        JOIN Posts p ON t.UserId = p.OwnerUserId
    ) u
    JOIN PostAnalysis pa ON u.PostId = pa.PostId
    JOIN ComplexVotes cv ON u.PostId = cv.PostId
    JOIN TagAnalysis ta ON (pa.TagArray[1] LIKE '%' || ta.TagName || '%')
    WHERE pa.Score > 0
    AND cv.VoteTypeName IN ('UpMod', 'DownMod', 'Favorite')
) combined_data
JOIN TopUsers up ON up.UserId = combined_data.UserId
JOIN PostAnalysis pa ON pa.PostId = combined_data.PostId
JOIN ComplexVotes cv ON cv.PostId = combined_data.PostId
JOIN TagAnalysis ta ON ta.TagName = ANY(pa.TagArray)
JOIN (
    SELECT u.UserId, p.PostId FROM (
        SELECT t.UserId, p.Id AS PostId FROM TopUsers t JOIN Posts p ON t.UserId = p.OwnerUserId
    ) u JOIN PostAnalysis p ON u.PostId = p.PostId
) u ON u.UserId = combined_data.UserId AND u.PostId = combined_data.PostId
GROUP BY up.UserId, up.DisplayName, up.Reputation, up.TotalPosts, up.Questions, up.Answers, up.TotalScore, up.TotalViews, up.LastPostDate, up.AvgScore, up.QuestionTitles, up.BadgesCount, up.BadgeNames, up.AnswerToQuestionRatio, up.RankByScore, pa.PostId, pa.Title, pa.Body, pa.Score, pa.ViewCount, pa.CreationDate, pa.OwnerName, pa.OwnerUserId, pa.AnswerCount, pa.CommentCount, pa.FavoriteCount, pa.Tags, pa.TagArray, pa.ShortTitle, pa.DaysSinceCreation, pa.PostType, pa.CommentCountSubquery, pa.VoteCategory, pa.PopularityLevel, cv.PostId, cv.VoteTypeId, cv.VoteTypeName, cv.UserId, cv.VoterName, cv.CreationDate, cv.BountyAmount, cv.ActionCategory, cv.VoteSummary, ta.TagId, ta.TagName, ta.TagCount, ta.WikiTitle, ta.InterestLevel, ta.TagRank, u.UserId, u.PostId;