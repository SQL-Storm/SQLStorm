WITH GoldBadgeUsers AS (
    SELECT DISTINCT
        b.UserId
    FROM 
        Badges b
    WHERE 
        b.Class = 1
),
UserYearlyActivity AS (
    SELECT
        p.OwnerUserId,
        EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersGiven,
        SUM(p.Score) AS TotalScore,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavorites,
        AVG(p.CommentCount) AS AvgCommentsPerPost,
        MAX(LENGTH(p.Body)) AS LongestPostBody,
        STRING_AGG(SUBSTRING(t.TagName FROM 1 FOR 15), ', ') FILTER (WHERE t.TagName IS NOT NULL) AS TopTagsUsedSample
    FROM
        Posts p
    INNER JOIN 
        GoldBadgeUsers gbu ON p.OwnerUserId = gbu.UserId
    LEFT JOIN
        Tags t ON p.Id = t.ExcerptPostId
    WHERE 
        p.CreationDate IS NOT NULL 
        AND p.OwnerUserId IS NOT NULL
    GROUP BY
        p.OwnerUserId,
        EXTRACT(YEAR FROM p.CreationDate)
),
RankedUserActivity AS (
    SELECT
        uya.OwnerUserId,
        uya.ActivityYear,
        uya.TotalPosts,
        uya.QuestionsAsked,
        uya.AnswersGiven,
        uya.TotalScore,
        uya.TotalFavorites,
        uya.AvgCommentsPerPost,
        uya.LongestPostBody,
        uya.TopTagsUsedSample,
        ROW_NUMBER() OVER (
            PARTITION BY uya.OwnerUserId 
            ORDER BY uya.TotalPosts DESC, uya.TotalScore DESC, uya.TotalFavorites DESC
        ) as ActivityRank,
        uya.TotalPosts - LAG(uya.TotalPosts, 1, 0) OVER (
            PARTITION BY uya.OwnerUserId 
            ORDER BY uya.ActivityYear
        ) AS PostCountChangeFromPrevYear
    FROM
        UserYearlyActivity uya
),
SiteAverages AS (
    SELECT
        EXTRACT(YEAR FROM p.CreationDate) AS ActivityYear,
        AVG(p.Score) AS SiteAvgScorePerPost,
        COUNT(DISTINCT p.Id) * 1.0 / NULLIF(COUNT(DISTINCT p.OwnerUserId), 0) AS AvgPostsPerUserSiteWide
    FROM
        Posts p
    WHERE
        p.CreationDate > (SELECT MIN(CreationDate) FROM Users)
    GROUP BY
        EXTRACT(YEAR FROM p.CreationDate)
)
SELECT
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    COALESCE(u.Location, 'N/A') AS Location,
    rya.ActivityYear AS PeakActivityYear,
    rya.TotalPosts AS PeakYearPosts,
    rya.QuestionsAsked AS PeakYearQuestions,
    rya.AnswersGiven AS PeakYearAnswers,
    CAST(rya.QuestionsAsked AS DECIMAL) / GREATEST(rya.AnswersGiven, 1) AS PeakYearQaRatio,
    rya.TotalScore AS PeakYearTotalScore,
    rya.PostCountChangeFromPrevYear,
    sa.SiteAvgScorePerPost AS SiteAvgScoreInPeakYear,
    CAST(rya.TotalScore AS DECIMAL) / GREATEST(rya.TotalPosts, 1) - COALESCE(sa.SiteAvgScorePerPost, 0) AS PerformanceDelta,
    rya.TopTagsUsedSample,
    (SELECT 
        p_sub.Title 
     FROM 
        Posts p_sub 
     WHERE 
        p_sub.OwnerUserId = rya.OwnerUserId 
        AND EXTRACT(YEAR FROM p_sub.CreationDate) = rya.ActivityYear
        AND p_sub.PostTypeId = 2
     ORDER BY 
        p_sub.Score DESC, p_sub.CreationDate DESC 
     LIMIT 1
    ) AS TopAnswerTitleInPeakYear,
    CASE
        WHEN u.AboutMe IS NULL THEN 'No bio provided.'
        WHEN LENGTH(u.AboutMe) > 200 THEN CONCAT('Long bio (', LENGTH(u.AboutMe), ' chars), starts with: ', SUBSTRING(u.AboutMe FROM 1 FOR 50), '...')
        ELSE 'Short bio.'
    END AS BioAnalysis,
    NTILE(100) OVER (ORDER BY u.Reputation DESC) AS ReputationPercentile
FROM
    RankedUserActivity rya
JOIN
    Users u ON rya.OwnerUserId = u.Id
LEFT JOIN
    SiteAverages sa ON rya.ActivityYear = sa.ActivityYear
WHERE
    rya.ActivityRank = 1
    AND rya.TotalPosts > 10
    AND u.DisplayName NOT LIKE 'user%'
ORDER BY
    PerformanceDelta DESC,
    u.Reputation DESC
LIMIT 100;