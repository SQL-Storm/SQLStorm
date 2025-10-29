-- {"query": "1032.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3348} 

WITH UserPostSummary AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(p.Score) AS TotalPostScore,
        SUM(COALESCE(p.ViewCount, 0)) AS TotalPostViews,
        -- Count of questions owned by this user that have an accepted answer
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswerCount,
        -- Count of answers owned by this user that have been accepted by a question owner
        SUM(CASE WHEN p.PostTypeId = 2 AND EXISTS (SELECT 1 FROM Posts q WHERE q.AcceptedAnswerId = p.Id) THEN 1 ELSE 0 END) AS AnswersAcceptedByOthersCount
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalComments,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
UserVoteMetrics AS ( -- Votes given by the user
    SELECT
        v.UserId AS VoterId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesGiven,
        SUM(CASE WHEN v.VoteTypeId = 8 THEN v.BountyAmount ELSE 0 END) AS TotalBountyGiven
    FROM Votes v
    WHERE v.UserId IS NOT NULL
    GROUP BY v.UserId
),
PostVoteAgg AS ( -- Votes received on posts owned by the user
    SELECT
        p.OwnerUserId AS UserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived,
        SUM(CASE WHEN v.VoteTypeId = 9 THEN v.BountyAmount ELSE 0 END) AS TotalBountyReceived
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    WHERE p.OwnerUserId IS NOT NULL AND v.VoteTypeId IN (2, 3, 5, 9)
    GROUP BY p.OwnerUserId
),
QuestionTagPerformance AS (
    SELECT
        TRIM(unnested_tags.TagName) AS TagName,
        COUNT(p.Id) AS TaggedQuestionCount,
        AVG(p.Score) AS AvgQuestionScore,
        AVG(CAST(p.ViewCount AS NUMERIC)) AS AvgQuestionViewCount,
        SUM(COALESCE(p.AnswerCount, 0)) AS TotalAnswersOnTaggedQuestions
    FROM Posts p
    CROSS JOIN LATERAL (
        SELECT UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2), '><')) AS TagName
    ) AS unnested_tags
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
    GROUP BY TRIM(unnested_tags.TagName)
),
UserRecentBadgeMetrics AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Date >= (CURRENT_TIMESTAMP - INTERVAL '1 year') THEN 1 ELSE 0 END) AS RecentBadges
    FROM Badges b
    GROUP BY b.UserId
),
ComplexPostHistoryAnalysis AS (
    SELECT
        ph.PostId,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE NULL END) AS EditCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE NULL END) AS ReopenCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS LastClosedDate,
        MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS LastReopenedDate,
        (
            SELECT crt.Name
            FROM PostHistory ph_inner
            LEFT JOIN CloseReasonTypes crt ON ph_inner.Comment::smallint = crt.Id
            WHERE ph_inner.PostId = ph.PostId
              AND ph_inner.PostHistoryTypeId = 10
              AND ph_inner.Comment ~ '^[0-9]+$' -- Ensure comment is numeric
            ORDER BY ph_inner.CreationDate DESC
            LIMIT 1
        ) AS LastCloseReasonName -- Correlated subquery for close reason
    FROM PostHistory ph
    GROUP BY ph.PostId
),
PostLinkDiversity AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS TotalRelatedLinks,
        COUNT(DISTINCT pl.RelatedPostId) AS UniqueRelatedLinks,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS DuplicateLinksCount,
        SUM(CASE WHEN pl.LinkTypeId = 1 THEN 1 ELSE 0 END) AS LinkedFromOtherPostsCount
    FROM PostLinks pl
    GROUP BY pl.PostId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate AS UserCreationDate,
    u.LastAccessDate,
    COALESCE(u.Location, 'Unknown') AS UserLocation,
    COALESCE(u.AboutMe, '') AS UserAboutMeExcerpt,
    COALESCE(ups.TotalPosts, 0) AS UserTotalPosts,
    COALESCE(ups.TotalQuestions, 0) AS UserTotalQuestions,
    COALESCE(ups.TotalAnswers, 0) AS UserTotalAnswers,
    COALESCE(uca.TotalComments, 0) AS UserTotalComments,
    COALESCE(pva.UpVotesReceived, 0) AS UserUpVotesReceived,
    COALESCE(pva.DownVotesReceived, 0) AS UserDownVotesReceived,
    COALESCE(pva.FavoritesReceived, 0) AS UserFavoritesReceived,
    COALESCE(uvm.UpVotesGiven, 0) AS UserUpVotesGiven,
    COALESCE(uvm.DownVotesGiven, 0) AS UserDownVotesGiven,
    COALESCE(urbm.TotalBadges, 0) AS TotalBadges,
    COALESCE(urbm.GoldBadges, 0) AS GoldBadges,
    COALESCE(urbm.RecentBadges, 0) AS RecentBadgesLastYear,
    ROUND(CAST(COALESCE(ups.TotalPostScore, 0) AS NUMERIC) / GREATEST(COALESCE(ups.TotalPosts, 1), 1), 2) AS AvgPostScorePerPost,
    ROUND(CAST(COALESCE(ups.AnswersAcceptedByOthersCount, 0) AS NUMERIC) / GREATEST(COALESCE(ups.TotalAnswers, 1), 1), 2) AS AnswerAcceptanceRate,
    u.Views AS UserProfileViews,
    CASE
        WHEN u.Reputation > 50000 AND COALESCE(urbm.GoldBadges, 0) > 2 AND COALESCE(ups.TotalQuestions,0) > 10 THEN 'Elite Contributor'
        WHEN u.Reputation > 10000 AND COALESCE(urbm.GoldBadges, 0) > 0 THEN 'High Impact User'
        WHEN u.Reputation BETWEEN 1000 AND 10000 THEN 'Active Contributor'
        ELSE 'Casual User'
    END AS UserCategory,
    ph_q.Id AS TopQuestionId,
    ph_q.Title AS TopQuestionTitle,
    ph_q.CreationDate AS TopQuestionDate,
    ph_q.Score AS TopQuestionScore,
    ROUND(CAST(ph_q.Score AS NUMERIC) / GREATEST(COALESCE(ph_q.ViewCount, 1), 1), 4) AS QuestionScorePerView,
    COALESCE(cpha.EditCount, 0) AS TopQuestionEditCount,
    COALESCE(cpha.CloseCount, 0) AS TopQuestionCloseCount,
    cpha.LastCloseReasonName AS TopQuestionLastCloseReason,
    COALESCE(pld.TotalRelatedLinks, 0) AS TopQuestionTotalRelatedLinks,
    COALESCE(pld.DuplicateLinksCount, 0) AS TopQuestionDuplicateLinksCount,
    -- Window functions
    RANK() OVER (ORDER BY u.Reputation DESC, COALESCE(ups.TotalPosts, 0) DESC, COALESCE(u.Views, 0) DESC) AS OverallUserRank,
    ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown') ORDER BY u.LastAccessDate DESC, u.Reputation DESC) AS RecentUserInLocationRank,
    AVG(COALESCE(ups.TotalPostScore, 0)) OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate)) AS AvgTotalPostScoreForUsersCreatedInYear,
    MAX(ph_q.Score) OVER (ORDER BY u.Reputation DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS MaxQuestionScoreUpToCurrentRepUser,
    -- Correlated Subquery for latest comment text on a user's most recent post
    (
        SELECT SUBSTRING(c.Text, 1, 100) || '...'
        FROM Comments c
        WHERE c.PostId = ph_q.Id AND c.UserId = u.Id
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS LatestCommentExcerptOnUserQuestion,
    -- Another correlated subquery to find the user's most active tag (by post count) with good average question score
    (
        SELECT qtp.TagName
        FROM Posts p_tag
        CROSS JOIN LATERAL (SELECT TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p_tag.Tags FROM 2 FOR LENGTH(p_tag.Tags)-2), '><'))) AS TagName) AS unnested_tags
        JOIN QuestionTagPerformance qtp ON unnested_tags.TagName = qtp.TagName
        WHERE p_tag.OwnerUserId = u.Id AND p_tag.PostTypeId = 1 AND p_tag.Tags IS NOT NULL AND LENGTH(p_tag.Tags) > 2
        GROUP BY qtp.TagName, qtp.AvgQuestionScore
        ORDER BY COUNT(p_tag.Id) DESC, qtp.AvgQuestionScore DESC
        LIMIT 1
    ) AS MostActiveTagWithBestAvgScore,
    -- Complex string expression and NULL logic
    LENGTH(COALESCE(u.AboutMe, '')) - LENGTH(REPLACE(LOWER(COALESCE(u.AboutMe, '')), 'sql', '')) AS AboutMeSqlKeywordCount,
    CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl LIKE '%stackexchange.com%' THEN 'StackExchange Website'
         WHEN u.WebsiteUrl IS NOT NULL THEN 'External Website'
         ELSE 'No Website'
    END AS UserWebsiteStatus,
    COALESCE(pva.TotalBountyReceived, 0) AS TotalBountyReceived,
    COALESCE(uvm.TotalBountyGiven, 0) AS TotalBountyGiven
FROM Users u
LEFT JOIN UserPostSummary ups ON u.Id = ups.UserId
LEFT JOIN UserCommentActivity uca ON u.Id = uca.UserId
LEFT JOIN UserVoteMetrics uvm ON u.Id = uvm.VoterId
LEFT JOIN PostVoteAgg pva ON u.Id = pva.UserId
LEFT JOIN UserRecentBadgeMetrics urbm ON u.Id = urbm.UserId
LEFT JOIN Posts ph_q ON u.Id = ph_q.OwnerUserId
                       AND ph_q.PostTypeId = 1
                       AND ph_q.Score > 50
                       AND ph_q.ViewCount > 500
                       AND ph_q.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '3 years')
                       AND ph_q.Id = (
                           SELECT p_inner.Id
                           FROM Posts p_inner
                           WHERE p_inner.OwnerUserId = u.Id AND p_inner.PostTypeId = 1
                           ORDER BY p_inner.Score DESC, p_inner.ViewCount DESC, p_inner.CreationDate DESC
                           LIMIT 1
                       ) -- Correlated subquery to pick the *single best* question by the user
LEFT JOIN ComplexPostHistoryAnalysis cpha ON ph_q.Id = cpha.PostId
LEFT JOIN PostLinkDiversity pld ON ph_q.Id = pld.PostId
WHERE
    u.Reputation > 1000
    AND u.LastAccessDate >= (CURRENT_TIMESTAMP - INTERVAL '1 year')
    AND (u.Location IS NOT NULL AND (LOWER(u.Location) LIKE '%london%' OR LOWER(u.Location) LIKE '%paris%' OR LOWER(u.Location) LIKE '%berlin%')) -- Filter by specific locations
    AND (ph_q.Id IS NOT NULL OR COALESCE(ups.TotalPosts, 0) > 50) -- Must have a 'top' question or be a prolific poster
    AND COALESCE(uca.TotalComments, 0) > 5
    AND COALESCE(urbm.RecentBadges, 0) >= 0 -- At least 0 recent badges (i.e., exists in badge metrics)
    AND u.CreationDate >= (CURRENT_TIMESTAMP - INTERVAL '10 years') -- Filter out very old accounts if data is too sparse
ORDER BY
    u.Reputation DESC,
    UserTotalPosts DESC,
    AvgPostScorePerPost DESC
LIMIT 10000;
