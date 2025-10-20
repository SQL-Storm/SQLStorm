WITH GoldBadgeTags AS (
    SELECT 
        b.UserId, 
        t.TagName, 
        COUNT(b.Id) AS GoldBadgesCount
    FROM 
        Badges b
    JOIN 
        Tags t ON b.Name = t.TagName
    WHERE 
        b.Class = 1 AND b.TagBased = TRUE
    GROUP BY 
        b.UserId, t.TagName
    HAVING 
        COUNT(b.Id) >= 1
),
UserAnswersInTags AS (
    SELECT 
        g.UserId, 
        g.TagName, 
        p.Id AS AnswerId, 
        p.Score AS AnswerScore, 
        q.Id AS QuestionId, 
        q.Score AS QuestionScore, 
        q.ViewCount AS QuestionViews,
        ROW_NUMBER() OVER (PARTITION BY g.UserId, g.TagName ORDER BY p.Score DESC) AS RankInTag
    FROM 
        GoldBadgeTags g
    JOIN 
        Posts p ON p.OwnerUserId = g.UserId AND p.PostTypeId = 2
    JOIN 
        Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    WHERE 
        q.Tags LIKE '%' || '<' || g.TagName || '>' || '%'
),
AggregatedUserStats AS (
    SELECT 
        ua.UserId, 
        ua.TagName, 
        COUNT(ua.AnswerId) AS TotalAnswers,
        SUM(ua.AnswerScore) AS TotalAnswerScore,
        AVG(ua.QuestionScore) AS AvgQuestionScore,
        SUM(ua.QuestionViews) AS TotalQuestionViews,
        MAX(ua.RankInTag) AS MaxRank
    FROM 
        UserAnswersInTags ua
    WHERE 
        ua.RankInTag <= 10
    GROUP BY 
        ua.UserId, ua.TagName
),
EditCounts AS (
    SELECT 
        ph.UserId, 
        COUNT(ph.Id) AS EditCount
    FROM 
        PostHistory ph
    WHERE 
        ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY 
        ph.UserId
),
VoteStats AS (
    SELECT 
        v.UserId, 
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvotesGiven
    FROM 
        Votes v
    GROUP BY 
        v.UserId
),
CommentStats AS (
    SELECT 
        c.UserId, 
        COUNT(c.Id) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM 
        Comments c
    GROUP BY 
        c.UserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    aus.TagName,
    aus.TotalAnswers,
    aus.TotalAnswerScore,
    aus.AvgQuestionScore,
    aus.TotalQuestionViews,
    ec.EditCount,
    vs.UpvotesGiven,
    vs.DownvotesGiven,
    cs.CommentCount,
    cs.AvgCommentScore,
    RANK() OVER (ORDER BY aus.TotalAnswerScore DESC) AS OverallRank
FROM 
    AggregatedUserStats aus
JOIN 
    Users u ON aus.UserId = u.Id
LEFT JOIN 
    EditCounts ec ON aus.UserId = ec.UserId
LEFT JOIN 
    VoteStats vs ON aus.UserId = vs.UserId
LEFT JOIN 
    CommentStats cs ON aus.UserId = cs.UserId
WHERE 
    u.Reputation > 10000
ORDER BY 
    OverallRank
LIMIT 100;