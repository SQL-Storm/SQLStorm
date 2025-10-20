-- {"query": "53006.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 883} 
WITH QuestionTags AS (
    SELECT 
        p.Id AS QuestionId,
        t.Tag AS TagName
    FROM 
        Posts p
    CROSS JOIN LATERAL unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS t(Tag)
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= '2020-01-01'
),
TagStats AS (
    SELECT 
        qt.TagName,
        COUNT(DISTINCT qt.QuestionId) AS QuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews
    FROM 
        QuestionTags qt
    JOIN 
        Posts p ON qt.QuestionId = p.Id
    GROUP BY 
        qt.TagName
    HAVING 
        COUNT(DISTINCT qt.QuestionId) > 1000
),
AnswerStats AS (
    SELECT 
        qt.TagName,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(v.BountyAmount) FILTER (WHERE v.VoteTypeId = 9) AS TotalBounties
    FROM 
        QuestionTags qt
    JOIN 
        Posts a ON a.ParentId = qt.QuestionId AND a.PostTypeId = 2
    LEFT JOIN 
        Votes v ON v.PostId = a.Id
    GROUP BY 
        qt.TagName
),
UserContributions AS (
    SELECT 
        qt.TagName,
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS QuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS AnswersGiven,
        SUM(p.Score) AS TotalScore,
        ROW_NUMBER() OVER (PARTITION BY qt.TagName ORDER BY SUM(p.Score) DESC) AS Rank
    FROM 
        QuestionTags qt
    JOIN 
        Posts p ON (p.Id = qt.QuestionId AND p.PostTypeId = 1) OR (p.ParentId = qt.QuestionId AND p.PostTypeId = 2)
    JOIN 
        Users u ON p.OwnerUserId = u.Id
    WHERE 
        u.Reputation > 10000
    GROUP BY 
        qt.TagName, u.Id
),
TopUsersPerTag AS (
    SELECT 
        TagName,
        UserId,
        QuestionsAsked,
        AnswersGiven,
        TotalScore
    FROM 
        UserContributions
    WHERE 
        Rank = 1
),
BadgeCounts AS (
    SELECT 
        qt.TagName,
        COUNT(b.Id) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges
    FROM 
        QuestionTags qt
    JOIN 
        Posts p ON p.Id = qt.QuestionId
    JOIN 
        Badges b ON b.UserId = p.OwnerUserId AND b.TagBased = TRUE AND lower(b.Name) = lower(qt.TagName)
    WHERE 
        b.Class IN (1, 2)
    GROUP BY 
        qt.TagName
)
SELECT 
    ts.TagName,
    ts.QuestionCount,
    ts.AvgQuestionScore,
    ts.TotalViews,
    ans.AnswerCount,
    ans.AvgAnswerScore,
    ans.TotalBounties,
    tut.UserId AS TopUserId,
    tut.QuestionsAsked AS TopUserQuestions,
    tut.AnswersGiven AS TopUserAnswers,
    tut.TotalScore AS TopUserScore,
    bc.GoldBadges,
    bc.SilverBadges,
    (SELECT COUNT(DISTINCT ph.Id) 
     FROM PostHistory ph 
     JOIN Posts p ON ph.PostId = p.Id 
     WHERE p.Tags LIKE '%' || ts.TagName || '%' 
     AND ph.PostHistoryTypeId IN (4,5,6)) AS EditCount
FROM 
    TagStats ts
JOIN 
    AnswerStats ans ON ts.TagName = ans.TagName
JOIN 
    TopUsersPerTag tut ON ts.TagName = tut.TagName
LEFT JOIN 
    BadgeCounts bc ON ts.TagName = bc.TagName
ORDER BY 
    ts.TotalViews DESC
LIMIT 50;