-- {"query": "34062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1313} 

WITH RecursiveUserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        b.Name AS BadgeName,
        b.Class,
        b.Date,
        1 AS BadgeCount
    FROM 
        Users u
    LEFT JOIN 
        Badges b ON u.Id = b.UserId

    UNION ALL

    SELECT 
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.BadgeName,
        r.Class,
        r.Date,
        r.BadgeCount + 1
    FROM 
        RecursiveUserBadges r
    JOIN 
        Badges b ON r.UserId = b.UserId AND b.Date > r.Date
    WHERE 
        r.BadgeCount < 5
),
TopBadgedUsers AS (
    SELECT
        UserId,
        DisplayName,
        Reputation,
        MAX(CASE WHEN Class = 1 THEN BadgeName ELSE NULL END) AS GoldBadge,
        MAX(CASE WHEN Class = 2 THEN BadgeName ELSE NULL END) AS SilverBadge,
        MAX(CASE WHEN Class = 3 THEN BadgeName ELSE NULL END) AS BronzeBadge,
        COUNT(DISTINCT BadgeName) AS TotalDistinctBadges
    FROM 
        RecursiveUserBadges
    GROUP BY
        UserId, DisplayName, Reputation
    HAVING 
        COUNT(DISTINCT BadgeName) >= 3
),
QuestionStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS TotalQuestions,
        AVG(p.Score) AS AvgQuestionScore,
        SUM(p.ViewCount) AS TotalViews,
        COUNT(DISTINCT EXTRACT(YEAR FROM p.CreationDate)) AS ActiveYearsWithQuestions
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 1
    GROUP BY
        p.OwnerUserId
),
AnswerStats AS (
    SELECT
        p.OwnerUserId,
        COUNT(*) AS TotalAnswers,
        AVG(p.Score) AS AvgAnswerScore,
        COUNT(DISTINCT p.ParentId) AS DistinctQuestionsAnswered
    FROM 
        Posts p
    WHERE 
        p.PostTypeId = 2
    GROUP BY
        p.OwnerUserId
),
UserActivity AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COALESCE(qs.TotalQuestions, 0) AS TotalQuestions,
        COALESCE(qs.AvgQuestionScore, 0) AS AvgQuestionScore,
        COALESCE(qs.TotalViews, 0) AS TotalQuestionViews,
        COALESCE(qs.ActiveYearsWithQuestions, 0) AS ActiveYearsWithQuestions,
        COALESCE(ans.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(ans.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(ans.DistinctQuestionsAnswered, 0) AS DistinctQuestionsAnswered,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate
    FROM 
        Users u
    LEFT JOIN 
        QuestionStats qs ON u.Id = qs.OwnerUserId
    LEFT JOIN 
        AnswerStats ans ON u.Id = ans.OwnerUserId
    WHERE
        u.Reputation > 1000 -- Filtering users with some reputation
),
TopPostsWithLinks AS (
    SELECT
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        pl.RelatedPostId,
        plt.Name AS LinkTypeName,
        rp.Score AS RelatedPostScore,
        u.DisplayName AS OwnerName
    FROM 
        Posts p
    JOIN 
        PostLinks pl ON p.Id = pl.PostId
    JOIN 
        LinkTypes plt ON pl.LinkTypeId = plt.Id
    JOIN 
        Posts rp ON rp.Id = pl.RelatedPostId
    JOIN 
        Users u ON u.Id = p.OwnerUserId
    WHERE 
        p.PostTypeId = 1
        AND p.Score >= 10
        AND rp.Score >= 5
),
UserCommentStats AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    WHERE
        c.UserId IS NOT NULL
    GROUP BY
        c.UserId
),
FinalResult AS (
    SELECT 
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.TotalQuestions,
        ua.AvgQuestionScore,
        ua.TotalQuestionViews,
        ua.ActiveYearsWithQuestions,
        ua.TotalAnswers,
        ua.AvgAnswerScore,
        ua.DistinctQuestionsAnswered,
        COALESCE(ucs.CommentCount, 0) AS CommentCount,
        COALESCE(ucs.AvgCommentScore, 0) AS AvgCommentScore,
        ubb.GoldBadge,
        ubb.SilverBadge,
        ubb.BronzeBadge,
        ubb.TotalDistinctBadges,
        MAX(tpl.Score) AS HighestLinkedQuestionScore,
        COUNT(DISTINCT tpl.RelatedPostId) AS UniqueLinkedPostsCount
    FROM 
        UserActivity ua
    LEFT JOIN 
        UserCommentStats ucs ON ua.UserId = ucs.UserId
    LEFT JOIN 
        TopBadgedUsers ubb ON ua.UserId = ubb.UserId
    LEFT JOIN 
        TopPostsWithLinks tpl ON ua.UserId = tpl.OwnerName -- Intentional join on DisplayName to provoke complexity
    GROUP BY 
        ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalQuestions, ua.AvgQuestionScore, ua.TotalQuestionViews, ua.ActiveYearsWithQuestions,
        ua.TotalAnswers, ua.AvgAnswerScore, ua.DistinctQuestionsAnswered, ucs.CommentCount, ucs.AvgCommentScore,
        ubb.GoldBadge, ubb.SilverBadge, ubb.BronzeBadge, ubb.TotalDistinctBadges
    HAVING 
        ua.TotalQuestions > 5 AND ua.TotalAnswers > 10 AND ubb.TotalDistinctBadges >= 3
)
SELECT 
    *
FROM 
    FinalResult
ORDER BY 
    Reputation DESC, HighestLinkedQuestionScore DESC
LIMIT 50;
