-- {"query": "21007.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "grok-4-fast-non-reasoning", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2168, "output_tokens": 1342} 

WITH ActiveUsers AS (
    SELECT 
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Location,
        COUNT(DISTINCT CASE WHEN p.Score >= 0 THEN p.Id END) AS PositivePostCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId 
        AND p.PostTypeId IN (1, 2) 
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '1 year'
        AND p.Score IS NOT NULL
    LEFT JOIN Votes v ON p.Id = v.PostId 
        AND v.UserId = u.Id 
        AND v.VoteTypeId IN (2, 3)
    WHERE u.Reputation > 100 
        AND u.LastAccessDate >= CURRENT_DATE - INTERVAL '6 months'
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.Location
    HAVING COUNT(DISTINCT CASE WHEN p.Score >= 0 THEN p.Id END) >= 5
),
QuestionStats AS (
    SELECT 
        p.Id AS QuestionId,
        p.Title,
        p.CreationDate AS QuestionDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        COALESCE(p.AcceptedAnswerId, 0) AS HasAcceptedAnswer,
        LENGTH(p.Tags) - LENGTH(REPLACE(p.Tags, '>', '')) AS TagCount,
        ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM p.CreationDate) 
                          ORDER BY p.ViewCount DESC NULLS LAST) AS ViewRank,
        AVG(p.Score) OVER (PARTITION BY EXTRACT(MONTH FROM p.CreationDate)) AS MonthlyAvgScore,
        LAG(p.Score, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PrevQuestionScore
    FROM Posts p
    WHERE p.PostTypeId = 1 
        AND p.ClosedDate IS NULL
        AND p.CreationDate >= CURRENT_DATE - INTERVAL '2 years'
),
TopContributors AS (
    SELECT 
        au.UserId,
        au.PositivePostCount,
        DENSE_RANK() OVER (ORDER BY au.PositivePostCount DESC, au.UpvoteCount DESC) AS ContributionRank,
        STRING_AGG(DISTINCT SUBSTRING(qs.Title, 1, 50), ' | ' ORDER BY qs.QuestionDate DESC) AS RecentTitles
    FROM ActiveUsers au
    LEFT JOIN QuestionStats qs ON au.UserId = (
        SELECT DISTINCT p.OwnerUserId 
        FROM Posts p 
        WHERE p.Id = qs.QuestionId 
        AND p.OwnerUserId IS NOT NULL
    )
    GROUP BY au.UserId, au.PositivePostCount, au.UpvoteCount
)
SELECT 
    qs.QuestionId,
    qs.Title,
    qs.QuestionDate,
    qs.QuestionScore,
    qs.ViewRank,
    qs.MonthlyAvgScore,
    COALESCE(tc.ContributionRank, 999) AS OwnerRank,
    CASE 
        WHEN qs.HasAcceptedAnswer > 0 THEN 'Accepted'
        WHEN qs.AnswerCount >= 3 THEN 'Well Answered'
        WHEN qs.ViewRank <= 10 THEN 'Popular'
        ELSE 'Standard'
    END AS QuestionStatus,
    CONCAT(
        COALESCE(au.Location, 'Unknown'), 
        CASE WHEN au.Reputation >= 10000 THEN ' (Veteran)' ELSE '' END
    ) AS OwnerInfo,
    GREATEST(
        qs.ViewCount / NULLIF(EXTRACT(EPOCH FROM (CURRENT_DATE - qs.QuestionDate))/86400, 0), 
        1
    ) AS AvgDailyViews,
    (SELECT COUNT(*) 
     FROM Comments c 
     WHERE c.PostId = qs.QuestionId 
     AND LENGTH(c.Text) > 50 
     AND c.Score >= 0) AS MeaningfulComments,
    (SELECT STRING_AGG(DISTINCT t.TagName, ', ') 
     FROM Tags t 
     WHERE POSITION(t.TagName IN qs.Tags) > 0 
     AND t.Count > 1000) AS PopularTags,
    CASE 
        WHEN qs.PrevQuestionScore IS NULL THEN NULL
        WHEN qs.QuestionScore > COALESCE(qs.PrevQuestionScore, 0) * 1.5 THEN 'Improving'
        WHEN qs.QuestionScore < COALESCE(qs.PrevQuestionScore, 0) * 0.7 THEN 'Declining'
        ELSE 'Stable'
    END AS PerformanceTrend
FROM QuestionStats qs
LEFT OUTER JOIN ActiveUsers au ON (
    SELECT p.OwnerUserId FROM Posts p WHERE p.Id = qs.QuestionId
) = au.UserId
LEFT OUTER JOIN TopContributors tc ON au.UserId = tc.UserId
WHERE qs.ViewRank <= 50 
    OR qs.QuestionScore >= qs.MonthlyAvgScore * 1.2
    OR (qs.TagCount >= 5 AND qs.AnswerCount >= 2)
UNION ALL
SELECT 
    NULL AS QuestionId,
    'SUMMARY STATS' AS Title,
    CURRENT_DATE AS QuestionDate,
    COUNT(*) AS QuestionScore,
    NULL AS ViewRank,
    AVG(qs.QuestionScore) AS MonthlyAvgScore,
    MIN(tc.ContributionRank) AS OwnerRank,
    'AGGREGATE' AS QuestionStatus,
    CONCAT('Total Active Users: ', COUNT(DISTINCT au.UserId)) AS OwnerInfo,
    NULL AS AvgDailyViews,
    SUM(qs.AnswerCount) AS MeaningfulComments,
    (SELECT STRING_AGG(TagName, ', ') 
     FROM Tags 
     WHERE Count > (SELECT AVG(Count) FROM Tags) * 2) AS PopularTags,
    NULL AS PerformanceTrend
FROM QuestionStats qs
INNER JOIN ActiveUsers au ON (
    SELECT p.OwnerUserId FROM Posts p WHERE p.Id = qs.QuestionId
) = au.UserId
LEFT JOIN TopContributors tc ON au.UserId = tc.UserId
WHERE qs.QuestionDate >= CURRENT_DATE - INTERVAL '1 year'
ORDER BY 
    CASE WHEN QuestionId IS NULL THEN 0 ELSE 1 END,
    COALESCE(qs.ViewRank, 999),
    qs.QuestionScore DESC NULLS LAST;
