-- {"query": "1064.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2528} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id ELSE NULL END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id ELSE NULL END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        MIN(p.CreationDate) AS FirstPostDate,
        MAX(p.CreationDate) AS LastPostDate,
        COALESCE(AVG(p.Score), 0) AS AvgScoreOfOwnedPosts,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpvotesReceivedOnPosts,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownvotesReceivedOnPosts,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS TotalFavoritesReceivedOnPosts,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6) AND p.OwnerUserId != ph.UserId) AS UniqueEditorsOnOwnPosts
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId
    LEFT JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND p.OwnerUserId != ph.UserId AND ph.PostHistoryTypeId IN (4,5,6)
    GROUP BY
        u.Id
),
PostPerformanceMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        EXTRACT(YEAR FROM p.CreationDate) AS CreationYear,
        EXTRACT(MONTH FROM p.CreationDate) AS CreationMonth,
        COALESCE(p.ViewCount, 0) AS TotalViews,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.AnswerCount, 0) AS AnswerCountForQuestion,
        CASE
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.AcceptedAnswerId IS NOT NULL THEN 1.0
            WHEN p.PostTypeId = 1 AND p.AnswerCount > 0 AND p.AcceptedAnswerId IS NULL THEN 0.5
            ELSE 0.0
        END AS AcceptanceIndicator,
        COALESCE(AVG(c.Score), 0) AS AverageCommentScore,
        MAX(ph.CreationDate) AS LatestEditTimestamp,
        COUNT(DISTINCT ph.UserId) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)) AS DistinctEditorCount,
        MAX(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS HasDuplicateLink,
        LENGTH(p.Body) - LENGTH(REPLACE(p.Body, ' ', '')) + 1 AS BodyWordCount,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalUpDownVotesOnPost
    FROM
        Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN PostLinks pl ON p.Id = pl.PostId AND pl.LinkTypeId = 3
    LEFT JOIN Votes v ON p.Id = v.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.ViewCount, p.Score, p.AnswerCount, p.AcceptedAnswerId, p.Body
),
TagAnalysis AS (
    SELECT
        p.OwnerUserId AS UserId,
        TRIM(REPLACE(REPLACE(LOWER(SUBSTRING(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')), 1, 50)), ' ', '-'), '.', '-')) AS TagName,
        COUNT(p.Id) AS PostCountInTag,
        AVG(p.Score) AS AvgScoreInTag
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY
        p.OwnerUserId, TRIM(REPLACE(REPLACE(LOWER(SUBSTRING(unnest(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')), 1, 50)), ' ', '-'), '.', '-'))
),
BaseUserMetrics AS (
    SELECT
        u.Id AS UserID,
        u.DisplayName AS UserName,
        u.Reputation,
        uas.TotalQuestions,
        uas.TotalAnswers,
        uas.TotalCommentsMade,
        uas.AvgScoreOfOwnedPosts,
        uas.HasGoldBadge,
        COALESCE(SUM(ppm.TotalViews), 0) AS TotalViewsOnOwnPosts,
        COALESCE(SUM(ppm.PostScore), 0) AS TotalScoreOnOwnPosts,
        COALESCE(SUM(ppm.TotalUpDownVotesOnPost), 0) AS TotalUpDownVotesOnOwnPosts,
        u.CreationDate AS UserCreationDate,
        uas.FirstPostDate,
        uas.LastPostDate,
        AGE(CURRENT_TIMESTAMP, u.LastAccessDate) AS TimeSinceLastAccess,
        (SELECT COUNT(DISTINCT b.Name) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadgesCount,
        (SELECT COUNT(DISTINCT b.Name) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadgesCount,
        (SELECT COUNT(DISTINCT b.Name) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadgesCount,
        NTILE(5) OVER (ORDER BY u.Reputation DESC) AS ReputationQuintile,
        RANK() OVER (ORDER BY u.UpVotes DESC, u.DownVotes ASC) AS UpvoteRank,
        LAG(u.Reputation, 1, 0) OVER (ORDER BY u.CreationDate) AS PrevUserReputationByCreationOrder,
        AVG(u.Reputation) OVER (ORDER BY u.CreationDate ROWS BETWEEN 10 PRECEDING AND 10 FOLLOWING) AS RollingAvgReputationAroundCreationDate,
        (SELECT COALESCE(AVG(p_corr.Score), 0)
         FROM Posts p_corr
         WHERE p_corr.OwnerUserId = u.Id
           AND EXTRACT(YEAR FROM p_corr.CreationDate) = EXTRACT(YEAR FROM u.CreationDate)
           AND p_corr.PostTypeId IN (1, 2)
        ) AS AvgScoreInFirstYearPosts,
        EXISTS (
            SELECT 1
            FROM Posts p_sql
            WHERE p_sql.OwnerUserId = u.Id
              AND p_sql.Body ILIKE '%SQL%'
              AND p_sql.Tags ILIKE '%<database>%'
        ) AS HasSqlDatabasePosts,
        STRING_AGG(DISTINCT ta.TagName, ', ') FILTER (WHERE ta.PostCountInTag > 5) AS TopTags,
        CASE
            WHEN uas.TotalQuestions > 100 AND uas.TotalAnswers > 200 AND u.Reputation > 5000 AND uas.HasGoldBadge = 1 THEN 'Veteran Power User'
            WHEN uas.TotalQuestions + uas.TotalAnswers > 50 AND u.Reputation > 1000 THEN 'Active Contributor'
            WHEN u.Reputation > 500 THEN 'Established Member'
            ELSE 'Casual User'
        END AS UserTierClassification,
        COALESCE(u.Location, 'Unknown Location') AS UserLocation,
        NULLIF(u.UpVotes, 0) * 1.0 / NULLIF(u.DownVotes, 0) AS UpvoteDownvoteRatio,
        CASE
            WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 THEN SUBSTRING(u.AboutMe, 1, 100) || '...'
            ELSE COALESCE(u.AboutMe, '(No AboutMe provided)')
        END AS AboutMeSnippet
    FROM
        Users u
    LEFT JOIN UserActivitySummary uas ON u.Id = uas.UserId
    LEFT JOIN Posts p_main ON u.Id = p_main.OwnerUserId
    LEFT JOIN PostPerformanceMetrics ppm ON p_main.Id = ppm.PostId
    LEFT JOIN TagAnalysis ta ON u.Id = ta.UserId
    WHERE
        u.CreationDate >= (CURRENT_DATE - INTERVAL '5 year')
        AND u.Reputation > 100
        AND (uas.TotalQuestions > 5 OR uas.TotalAnswers > 10 OR uas.TotalCommentsMade > 20 OR uas.HasGoldBadge = 1)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, uas.TotalQuestions, uas.TotalAnswers, uas.TotalCommentsMade,
        uas.AvgScoreOfOwnedPosts, uas.HasGoldBadge, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes,
        uas.FirstPostDate, uas.LastPostDate, u.Location, u.AboutMe
)
SELECT
    UserID,
    UserName,
    Reputation,
    UserTierClassification,
    GoldBadgesCount,
    SilverBadgesCount,
    BronzeBadgesCount,
    TotalQuestions,
    TotalAnswers,
    TotalCommentsMade,
    TotalScoreOnOwnPosts,
    TotalViewsOnOwnPosts,
    TopTags,
    'Top Gold/High Rep User' AS CategoryRank
FROM
    BaseUserMetrics
WHERE
    GoldBadgesCount > 0 AND Reputation > 10000
    AND TotalAnswers > 50
ORDER BY Reputation DESC, GoldBadgesCount DESC
LIMIT 500
UNION ALL
SELECT
    UserID,
    UserName,
    Reputation,
    UserTierClassification,
    GoldBadgesCount,
    SilverBadgesCount,
    BronzeBadgesCount,
    TotalQuestions,
    TotalAnswers,
    TotalCommentsMade,
    TotalScoreOnOwnPosts,
    TotalViewsOnOwnPosts,
    TopTags,
    'High Answer Count/No Gold' AS CategoryRank
FROM
    BaseUserMetrics
WHERE
    GoldBadgesCount = 0 AND TotalAnswers > 100 AND Reputation > 500
ORDER BY TotalAnswers DESC, Reputation DESC
LIMIT 500;
