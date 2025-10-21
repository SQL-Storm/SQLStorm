-- {"query": "53071.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "grok-4", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2646, "output_tokens": 921} 
WITH TopTags AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
    FROM 
        Tags t
    WHERE 
        t.Count > 1000
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        AVG(p.ViewCount) AS AvgViewCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpvotesReceived,
        COUNT(DISTINCT b.Id) AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN 
        Votes v ON p.Id = v.PostId
    LEFT JOIN 
        Badges b ON u.Id = b.UserId
    WHERE 
        u.Reputation > 1000
        AND p.CreationDate >= '2010-01-01'
    GROUP BY 
        u.Id, u.Reputation
    HAVING 
        COUNT(DISTINCT p.Id) > 50
),
QuestionAnalysis AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.Score AS QuestionScore,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Id END) AS CloseAttempts,
        MAX(ph.CreationDate) AS LastHistoryDate
    FROM 
        Posts p
    LEFT JOIN 
        Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    LEFT JOIN 
        Comments c ON p.Id = c.PostId
    LEFT JOIN 
        PostHistory ph ON p.Id = ph.PostId
    WHERE 
        p.PostTypeId = 1
        AND p.CreationDate >= '2015-01-01'
    GROUP BY 
        p.Id, p.Title, p.Score
    HAVING 
        COUNT(DISTINCT a.Id) > 5
),
TaggedQuestions AS (
    SELECT 
        qa.QuestionId,
        tt.TagId,
        tt.TagName,
        qa.QuestionScore,
        qa.TotalAnswerScore
    FROM 
        QuestionAnalysis qa
    CROSS JOIN 
        TopTags tt
    WHERE 
        EXISTS (
            SELECT 1 
            FROM Posts p2 
            WHERE p2.Id = qa.QuestionId 
            AND p2.Tags LIKE '%' || tt.TagName || '%'
        )
),
UserContributions AS (
    SELECT 
        ua.UserId,
        ua.Reputation,
        tq.TagId,
        COUNT(DISTINCT tq.QuestionId) AS ContributedQuestions,
        SUM(tq.QuestionScore + tq.TotalAnswerScore) AS TotalContributionScore,
        RANK() OVER (PARTITION BY tq.TagId ORDER BY SUM(tq.QuestionScore + tq.TotalAnswerScore) DESC) AS ContributionRank
    FROM 
        UserActivity ua
    INNER JOIN 
        Posts p ON ua.UserId = p.OwnerUserId
    INNER JOIN 
        TaggedQuestions tq ON p.Id = tq.QuestionId OR p.ParentId = tq.QuestionId
    GROUP BY 
        ua.UserId, ua.Reputation, tq.TagId
    HAVING 
        SUM(tq.QuestionScore + tq.TotalAnswerScore) > 100
)
SELECT 
    uc.UserId,
    u.DisplayName,
    uc.Reputation,
    tt.TagName,
    tt.TagRank,
    uc.ContributedQuestions,
    uc.TotalContributionScore,
    uc.ContributionRank,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId IN (SELECT p.Id FROM Posts p WHERE p.OwnerUserId = uc.UserId)) AS LinkedPosts,
    (SELECT AVG(Score) FROM Comments c WHERE c.UserId = uc.UserId) AS AvgCommentScore
FROM 
    UserContributions uc
INNER JOIN 
    Users u ON uc.UserId = u.Id
INNER JOIN 
    TopTags tt ON uc.TagId = tt.TagId
WHERE 
    uc.ContributionRank <= 10
ORDER BY 
    tt.TagRank ASC,
    uc.ContributionRank ASC;