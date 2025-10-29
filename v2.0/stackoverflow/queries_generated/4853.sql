-- {"query": "4853.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1102} 

WITH RankedUserBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) as rn
    FROM Badges b
    WHERE b.TagBased = 0
),
UserContribution AS (
    SELECT
        p.OwnerUserId,
        COUNT(p.Id) AS PostCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        SUM(CASE WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts accepted_p WHERE accepted_p.Id = p.Id AND accepted_p.ParentId = p.Id) THEN 1 ELSE 0 END) AS AcceptedAnswerCount,
        SUM(p.Score) AS TotalScore
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
HighEngagementUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        uc.PostCount,
        uc.QuestionCount,
        uc.AnswerCount,
        uc.AcceptedAnswerCount,
        uc.TotalScore,
        rub.BadgeName AS MostRecentNamedBadge,
        CASE
            WHEN u.Views > 1000000 THEN 'Very High'
            WHEN u.Views > 100000 THEN 'High'
            WHEN u.Views > 10000 THEN 'Medium'
            ELSE 'Low'
        END AS ViewEngagementLevel,
        CASE
            WHEN DATEDIFF(day, u.CreationDate, GETDATE()) < 365 THEN 'New'
            WHEN DATEDIFF(day, u.CreationDate, GETDATE()) < 365 * 5 THEN 'Established'
            ELSE 'Veteran'
        END AS TenureCategory
    FROM Users u
    JOIN UserContribution uc ON u.Id = uc.OwnerUserId
    LEFT JOIN RankedUserBadges rub ON u.Id = rub.UserId AND rub.rn = 1
    WHERE uc.PostCount > 100 AND uc.AcceptedAnswerCount > 5
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicateLinksCount,
        AVG(CAST(p.Score AS FLOAT)) AS AveragePostScore,
        MAX(p.CommentCount) AS MaxCommentsOnLinkedPost
    FROM PostLinks pl
    JOIN Posts p ON pl.RelatedPostId = p.Id
    GROUP BY pl.PostId
)
SELECT
    heu.UserId,
    heu.DisplayName,
    heu.Reputation,
    heu.PostCount,
    heu.QuestionCount,
    heu.AnswerCount,
    heu.AcceptedAnswerCount,
    heu.TotalScore,
    heu.MostRecentNamedBadge,
    heu.ViewEngagementLevel,
    heu.TenureCategory,
    COALESCE(pla.LinkedPostsCount, 0) AS TotalLinkedPosts,
    COALESCE(pla.DuplicateLinksCount, 0) AS TotalDuplicateLinks,
    COALESCE(pla.AveragePostScore, 0.0) AS AvgScoreOfLinkedPosts,
    COALESCE(pla.MaxCommentsOnLinkedPost, 0) AS MaxCommentsOnRelatedPosts,
    (SELECT COUNT(*) FROM Comments c WHERE c.UserId = heu.UserId AND c.Score > 10) AS HighScoringComments,
    IIF(EXISTS(SELECT 1 FROM Badges b WHERE b.UserId = heu.UserId AND b.Name = 'Great Question'), 'Yes', 'No') AS HasGreatQuestionBadge,
    LTRIM(RTRIM(SUBSTRING(heu.DisplayName, 1, CHARINDEX(' ', heu.DisplayName + ' ') - 1))) AS FirstName,
    CASE
        WHEN heu.TenureCategory = 'Veteran' AND heu.Reputation > 50000 THEN 'Highly Valued Veteran'
        WHEN heu.TenureCategory = 'Established' AND heu.AcceptedAnswerCount > 20 THEN 'Proactive Contributor'
        ELSE 'Standard User'
    END AS UserTier
FROM HighEngagementUsers heu
LEFT JOIN PostLinkAnalysis pla ON heu.UserId = pla.PostId
WHERE heu.Reputation BETWEEN 1000 AND 100000
ORDER BY heu.Reputation DESC, heu.PostCount DESC
LIMIT 100;
