-- {"query": "18055.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1152} 
WITH RECURSIVE TagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.TagName AS FullPath,
        1 AS Level
    FROM Tags t
    WHERE t.TagName LIKE 'c#%'
    UNION ALL
    SELECT
        t.Id,
        t.TagName,
        TH.FullPath || '/' || t.TagName,
        TH.Level + 1
    FROM Tags t
    JOIN TagHierarchy TH ON TH.TagName LIKE '%' || t.TagName || '%'
    WHERE TH.Level < 3
),
PostTagCounts AS (
    SELECT
        p.Id AS PostId,
        COUNT(DISTINCT pt.TagName) AS TagCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.Score) AS AverageScore,
        MAX(p.CreationDate) AS LatestPostDate
    FROM Posts p
    LEFT JOIN Tags pt ON pt.TagName IN (SELECT TagName FROM TagHierarchy) AND p.Tags LIKE '%' || pt.TagName || '%'
    WHERE p.PostTypeId = 1 -- Questions
    GROUP BY p.Id
),
UserPostActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalQuestions,
        COUNT(DISTINCT a.Id) AS TotalAnswers,
        SUM(CASE WHEN p.AcceptedAnswerId = a.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        MAX(p.CreationDate) AS LatestQuestionDate,
        MAX(a.CreationDate) AS LatestAnswerDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id, u.DisplayName
),
CommentSentiment AS (
    SELECT
        c.PostId,
        COUNT(CASE WHEN c.Score > 0 THEN 1 ELSE NULL END) AS PositiveComments,
        COUNT(CASE WHEN c.Score < 0 THEN 1 ELSE NULL END) AS NegativeComments,
        COUNT(CASE WHEN c.Score = 0 THEN 1 ELSE NULL END) AS NeutralComments,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%excellent%' OR LOWER(c.Text) LIKE '%great%' THEN 1 ELSE 0 END) AS PositiveKeywords,
        SUM(CASE WHEN LOWER(c.Text) LIKE '%terrible%' OR LOWER(c.Text) LIKE '%bad%' THEN 1 ELSE 0 END) AS NegativeKeywords
    FROM Comments c
    GROUP BY c.PostId
),
RankedPosts AS (
    SELECT
        ptc.PostId,
        ptc.TagCount,
        ptc.TotalScore,
        ptc.AverageScore,
        ptc.LatestPostDate,
        ROW_NUMBER() OVER (ORDER BY ptc.TotalScore DESC, ptc.AverageScore DESC) AS ScoreRank,
        ROW_NUMBER() OVER (ORDER BY ptc.TagCount DESC, ptc.LatestPostDate DESC) AS TagRank
    FROM PostTagCounts ptc
    WHERE ptc.TagCount > 0 AND ptc.TotalScore > 100
)
SELECT
    rp.PostId,
    rp.TotalScore,
    rp.ScoreRank,
    rp.TagRank,
    upa.DisplayName AS OwnerDisplayName,
    upa.TotalQuestions,
    upa.TotalAnswers,
    upa.AcceptedAnswersCount,
    CASE
        WHEN upa.TotalQuestions > 1000 THEN 'Prolific'
        WHEN upa.TotalQuestions > 100 THEN 'Experienced'
        WHEN upa.TotalQuestions > 10 THEN 'Active'
        ELSE 'Newbie'
    END AS UserActivityLevel,
    cs.PositiveComments,
    cs.NegativeComments,
    cs.PositiveKeywords,
    cs.NegativeKeywords,
    CASE
        WHEN cs.PositiveKeywords > cs.NegativeKeywords THEN 'Mostly Positive'
        WHEN cs.NegativeKeywords > cs.PositiveKeywords THEN 'Mostly Negative'
        ELSE 'Mixed/Neutral'
    END AS CommentSentiment,
    p.Title,
    p.CreationDate,
    p.LastActivityDate,
    COALESCE(p.FavoriteCount, 0) AS Favorites,
    CASE WHEN p.ClosedDate IS NOT NULL THEN 'Closed' ELSE 'Open' END AS PostStatus,
    p.Tags,
    p.OwnerUserId,
    p.LastEditorUserId,
    CASE WHEN p.OwnerUserId = p.LastEditorUserId THEN 'Self-Edited' ELSE 'Collaborative Edit' END AS EditHistoryType
FROM RankedPosts rp
JOIN Posts p ON rp.PostId = p.Id
LEFT JOIN UserPostActivity upa ON p.OwnerUserId = upa.UserId
LEFT JOIN CommentSentiment cs ON rp.PostId = cs.PostId
WHERE rp.ScoreRank <= 50 OR rp.TagRank <= 50
ORDER BY rp.ScoreRank, rp.TagRank;