-- {"query": "1723.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3126} 

WITH UserSummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.Views,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        DATE_PART('day', NOW() - u.LastAccessDate) AS DaysSinceLastAccess,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE 0 END), 0) AS TotalQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(c.Score), 0) AS TotalCommentScoreMade,
        SUM(CASE WHEN v.VoteTypeId = 2 AND p_for_votes.OwnerUserId = u.Id AND v.UserId != u.Id THEN 1 ELSE 0 END) AS TotalUpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 AND p_for_votes.OwnerUserId = u.Id AND v.UserId != u.Id THEN 1 ELSE 0 END) AS TotalDownVotesReceived,
        MAX(p.CreationDate) AS LatestPostDate,
        MIN(p.CreationDate) AS EarliestPostDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON p.Id = v.PostId -- Joining all votes on this user's posts
    LEFT JOIN Posts p_for_votes ON v.PostId = p_for_votes.Id AND p_for_votes.OwnerUserId = u.Id -- Ensure votes are for *this user's* posts
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.Views, u.UpVotes, u.DownVotes, u.LastAccessDate
),
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        COUNT(b.Id) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostEditAndCloseHistory AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditCount, -- Edit Title, Body, Tags
        MAX(CASE WHEN ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105) THEN 1 ELSE 0 END) AS WasClosed, -- Any close reason
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS WasReopened,
        (SELECT MIN(ph_inner.CreationDate)
         FROM PostHistory ph_inner
         WHERE ph_inner.PostId = ph.PostId
           AND ph_inner.PostHistoryTypeId IN (4, 5, 6) -- First actual edit date
        ) AS FirstEditDate
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostTagParsing AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS TagArray,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.Title,
        p.Body,
        (SELECT COUNT(c.Id) FROM Comments c WHERE c.PostId = p.Id AND c.Score >= 1) AS PositiveCommentCountOnPost
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only questions have tags
      AND p.CreationDate >= (NOW() - INTERVAL '3 years') -- Limit data for performance
),
RankedTagContributions AS (
    SELECT
        ptp.OwnerUserId AS UserId,
        UNNEST(ptp.TagArray) AS TagName,
        SUM(ptp.Score) AS UserTagScore,
        COUNT(ptp.PostId) AS UserTagPostCount,
        RANK() OVER (PARTITION BY UNNEST(ptp.TagArray) ORDER BY SUM(ptp.Score) DESC, COUNT(ptp.PostId) DESC) AS RankInTagByScore,
        ROW_NUMBER() OVER (PARTITION BY UNNEST(ptp.TagArray) ORDER BY COUNT(ptp.PostId) DESC, SUM(ptp.Score) DESC) AS RankInTagByPosts
    FROM PostTagParsing ptp
    GROUP BY ptp.OwnerUserId, UNNEST(ptp.TagArray)
    HAVING SUM(ptp.Score) > 0 AND COUNT(ptp.PostId) > 1
),
UserOverallMetrics AS (
    SELECT
        us.UserId,
        us.DisplayName,
        us.Reputation,
        us.Views,
        us.TotalPosts,
        us.TotalQuestions,
        us.TotalAnswers,
        us.TotalPostScore,
        us.TotalQuestionViews,
        us.TotalCommentsMade,
        us.TotalCommentScoreMade,
        us.TotalUpVotesGiven,
        us.TotalDownVotesGiven,
        us.TotalUpVotesReceived,
        us.TotalDownVotesReceived,
        us.DaysSinceLastAccess,
        COALESCE(bc.GoldBadges, 0) AS GoldBadges,
        COALESCE(bc.SilverBadges, 0) AS SilverBadges,
        COALESCE(bc.BronzeBadges, 0) AS BronzeBadges,
        COALESCE(bc.TotalBadges, 0) AS TotalBadges,
        COALESCE(CAST(us.TotalUpVotesReceived AS DECIMAL) / NULLIF(us.TotalDownVotesReceived, 0), 0) AS UpDownVoteRatioReceived,
        COALESCE(CAST(us.TotalQuestions AS DECIMAL) / NULLIF(us.TotalAnswers, 0), 0) AS QARatio,
        -- Complex Weighted Influence Score Calculation with NULL handling
        (
            (us.Reputation * 0.05) +
            (us.TotalPostScore * 0.3) +
            (us.TotalCommentsMade * 0.1) +
            (us.TotalUpVotesReceived * 0.6) +
            (COALESCE(bc.GoldBadges, 0) * 40) +
            (COALESCE(bc.SilverBadges, 0) * 15) +
            (COALESCE(bc.BronzeBadges, 0) * 3) -
            (us.DaysSinceLastAccess * 0.005) -- Penalize for inactivity, max 1.8 penalty per year
        ) AS InfluenceScore,
        LAG(us.TotalPostScore, 1, 0) OVER (PARTITION BY us.UserId ORDER BY us.LatestPostDate) AS PreviousPostScoreForLag,
        FIRST_VALUE(us.EarliestPostDate) OVER (PARTITION BY us.UserId ORDER BY us.EarliestPostDate) AS UserFirstActivityDate
    FROM UserSummary us
    LEFT JOIN BadgeCounts bc ON us.UserId = bc.UserId
    WHERE us.Reputation > 500 AND us.TotalPosts > 10 AND us.DaysSinceLastAccess < 730 -- Filter for active users
),
ExtendedPostDetails AS (
    SELECT
        ptp.PostId,
        ptp.OwnerUserId,
        ptp.CreationDate AS PostCreationDate,
        ptp.Score AS PostScore,
        ptp.ViewCount,
        ptp.Title,
        ptp.Body,
        ptp.PositiveCommentCountOnPost,
        pech.EditCount,
        pech.WasClosed,
        pech.WasReopened,
        pech.FirstEditDate,
        -- Calculate time to first edit, handling potential NULLs
        COALESCE(DATE_PART('hour', pech.FirstEditDate - ptp.CreationDate), 0) AS HoursToFirstEdit,
        -- Correlated Subquery: Get the body length of the accepted answer, if any
        (SELECT LENGTH(aa.Body) FROM Posts aa WHERE aa.Id = ptp.AcceptedAnswerId) AS AcceptedAnswerBodyLength,
        -- Correlated Subquery: Check if the owner user ever commented on *this specific question*
        (SELECT EXISTS (
            SELECT 1 FROM Comments c_inner WHERE c_inner.PostId = ptp.PostId AND c_inner.UserId = ptp.OwnerUserId
        )) AS OwnerCommentedOnOwnQuestion,
        -- Complicated string expression for title analysis
        LENGTH(ptp.Title) - LENGTH(REPLACE(LOWER(ptp.Title), 'sql', '')) AS SqlKeywordCountInTitle,
        LOWER(SUBSTRING(ptp.Title FROM 1 FOR 15)) AS TitlePrefixSample,
        -- Example of a complicated predicate/expression
        COALESCE(ptp.Score * (1 + (ptp.ViewCount::NUMERIC / NULLIF(pech.EditCount, 0)) * 0.05), 0) AS PostQualityMetric,
        LENGTH(ptp.Body) - LENGTH(REPLACE(ptp.Body, '<code>', '')) AS CodeBlockCount
    FROM PostTagParsing ptp
    LEFT JOIN PostEditAndCloseHistory pech ON ptp.PostId = pech.PostId
    WHERE ptp.PostTypeId = 1 -- Ensure it's a question
      AND ptp.Score > 0 -- Only highly regarded questions
)
-- Final Selection: Combine user metrics, extended post details, and ranking
SELECT
    uom.UserId,
    uom.DisplayName,
    uom.Reputation,
    uom.InfluenceScore,
    uom.TotalPosts,
    uom.TotalQuestions,
    uom.TotalAnswers,
    uom.GoldBadges,
    uom.SilverBadges,
    uom.BronzeBadges,
    epd.PostId,
    epd.PostCreationDate,
    epd.PostScore,
    epd.ViewCount,
    epd.EditCount,
    epd.WasClosed,
    epd.WasReopened,
    epd.HoursToFirstEdit,
    epd.AcceptedAnswerBodyLength,
    epd.OwnerCommentedOnOwnQuestion,
    epd.SqlKeywordCountInTitle,
    epd.CodeBlockCount,
    epd.PostQualityMetric,
    -- Join with ranked tags for specific insights
    COALESCE(rt.TagName, 'Untagged/Minor') AS TopTagName,
    rt.RankInTagByScore,
    rt.UserTagPostCount,
    ROW_NUMBER() OVER (ORDER BY uom.InfluenceScore DESC, uom.Reputation DESC, epd.PostQualityMetric DESC) AS OverallUserPostRank,
    NTILE(5) OVER (ORDER BY uom.InfluenceScore DESC) AS InfluenceQuintile,
    CASE
        WHEN uom.Reputation >= 20000 AND uom.GoldBadges >= 10 AND epd.PostScore >= 50 THEN 'Guru'
        WHEN uom.Reputation >= 5000 AND uom.TotalPosts >= 100 AND epd.PostScore >= 20 THEN 'ExpertContributor'
        WHEN uom.TotalUpVotesReceived > uom.TotalDownVotesReceived * 3 AND uom.TotalPosts > 50 THEN 'HighlyRegarded'
        ELSE 'ActiveMember'
    END AS UserEngagementTier,
    UPPER(LEFT(uom.DisplayName, 4)) || '-' || TO_CHAR(epd.PostCreationDate, 'MMDDYY') || '-' || LPAD(epd.PostId::TEXT, 7, '0') AS UniquePostIdentifier
FROM UserOverallMetrics uom
INNER JOIN ExtendedPostDetails epd ON uom.UserId = epd.OwnerUserId
LEFT JOIN RankedTagContributions rt ON uom.UserId = rt.UserId AND rt.RankInTagByScore = 1 -- Only the user's top tag by score
WHERE
    uom.InfluenceScore > 1000
    AND epd.PostScore >= 10
    AND epd.ViewCount >= 1000
    AND epd.PostCreationDate >= (NOW() - INTERVAL '2 year')
    AND epd.WasClosed = 0 -- Only open questions
    AND (
        epd.TitlePrefixSample LIKE 'how do i%'
        OR epd.TitlePrefixSample LIKE 'what is the%'
        OR epd.SqlKeywordCountInTitle > 2
        OR epd.CodeBlockCount > 0
    )
    AND uom.UpDownVoteRatioReceived > 1.5 -- More upvotes than downvotes received
ORDER BY OverallUserPostRank ASC, epd.PostId DESC
LIMIT 5000;
