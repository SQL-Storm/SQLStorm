-- {"query": "1896.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3470} 

WITH UserReputationRank AS (
    -- CTE 1: Ranks users by reputation within their creation year cohort
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC, u.Id) AS ReputationRankYearly,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.Id) AS OverallReputationRank
    FROM Users u
    WHERE u.Reputation > 1000 -- Focus on more established users
),
PostTaggingInfo AS (
    -- CTE 2: Extracts individual tags from posts and provides post metrics per tag
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        TRIM(UNNEST(string_to_array(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'))) AS TagName
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId IN (1, 2) -- Only questions and answers
),
PostEditActivity AS (
    -- CTE 3: Calculates edit frequency and time differences for posts
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        ph.CreationDate AS EditDate,
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEditDate,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn_latest_edit,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate ASC) AS rn_first_edit
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
),
PostEditSummary AS (
    -- CTE 4: Summarizes total edits and average time between edits for each post
    SELECT
        pea.PostId,
        COUNT(pea.EditDate) AS TotalEdits,
        AVG(EXTRACT(EPOCH FROM (pea.EditDate - pea.PreviousEditDate))) AS AvgSecondsBetweenEdits, -- In seconds
        MAX(CASE WHEN pea.rn_latest_edit = 1 THEN pea.EditDate END) AS LastEditDate,
        MAX(CASE WHEN pea.rn_first_edit = 1 THEN pea.EditDate END) AS FirstEditDate
    FROM PostEditActivity pea
    GROUP BY pea.PostId
),
UserPostStats AS (
    -- CTE 5: Calculates various statistics for users based on their posts
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score END) AS AvgAnswerScore,
        SUM(p.FavoriteCount) AS TotalFavoriteCounts,
        COUNT(DISTINCT p.AcceptedAnswerId) AS AcceptedAnswersCount,
        SUM(CASE WHEN p.ClosedDate IS NOT NULL AND p.PostTypeId = 1 THEN 1 ELSE 0 END) AS ClosedQuestionsByOwnerCount,
        SUM(CASE WHEN p.Body LIKE '%http://%' OR p.Body LIKE '%https://%' THEN 1 ELSE 0 END) AS PostsWithLinksInBody,
        SUM(CASE WHEN p.ContentLicense LIKE '%CC BY-SA 4.0%' THEN 1 ELSE 0 END) AS PostsWithSpecificLicense
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserBadgeSummary AS (
    -- CTE 6: Summarizes badge counts and finds specific badge milestones for users
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        MIN(CASE WHEN b.Class = 1 THEN b.Date ELSE NULL END) AS FirstGoldBadgeDate,
        MAX(CASE WHEN b.Class = 2 THEN b.Date ELSE NULL END) AS LatestSilverBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
UserPostEditAggregates AS (
    -- CTE 7: Aggregates post edit summary data per user
    SELECT
        p.OwnerUserId AS UserId,
        SUM(pes.TotalEdits) AS UserTotalPostEdits,
        AVG(pes.AvgSecondsBetweenEdits) AS UserAvgSecondsBetweenEdits,
        MAX(pes.LastEditDate) AS UserLatestPostEditDate
    FROM Posts p
    INNER JOIN PostEditSummary pes ON p.Id = pes.PostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserVoteActivity AS (
    -- CTE 8: Summarizes user's voting activity (both given and received)
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN v_given.VoteTypeId = 2 THEN 1 END) AS TotalUpVotesGiven,
        COUNT(CASE WHEN v_given.VoteTypeId = 3 THEN 1 END) AS TotalDownVotesGiven,
        COUNT(CASE WHEN v_given.VoteTypeId = 4 THEN 1 END) AS TotalOffensiveVotesGiven,
        COUNT(CASE WHEN v_rec.VoteTypeId = 2 THEN 1 END) AS TotalUpVotesReceivedOnPosts,
        COUNT(CASE WHEN v_rec.VoteTypeId = 3 THEN 1 END) AS TotalDownVotesReceivedOnPosts
    FROM Users u
    LEFT JOIN Votes v_given ON u.Id = v_given.UserId
    LEFT JOIN Posts p_rec ON u.Id = p_rec.OwnerUserId
    LEFT JOIN Votes v_rec ON p_rec.Id = v_rec.PostId AND v_rec.VoteTypeId IN (2,3)
    GROUP BY u.Id
),
UserPostLinks AS (
    -- CTE 9: Summarizes linked and duplicate posts involving user's owned posts
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pl.Id) AS TotalLinkedPostsCreated,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 AND p.PostTypeId = 1 THEN pl.RelatedPostId END) AS TotalDuplicateSourcesCreated
    FROM Posts p
    JOIN PostLinks pl ON p.Id = pl.PostId OR p.Id = pl.RelatedPostId -- Posts owned by user are involved in links
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    u.Id AS UserIdentifier,
    u.DisplayName,
    urr.Reputation,
    urr.CreationDate AS UserCreationDate,
    urr.ReputationRankYearly,
    COALESCE(ups.TotalPosts, 0) AS TotalPosts,
    COALESCE(ups.TotalQuestions, 0) AS TotalQuestions,
    COALESCE(ups.TotalAnswers, 0) AS TotalAnswers,
    COALESCE(ROUND(ups.AvgQuestionScore, 2), 0.00) AS AverageQuestionScore,
    COALESCE(ROUND(ups.AvgAnswerScore, 2), 0.00) AS AverageAnswerScore,
    COALESCE(ubs.GoldBadges, 0) AS GoldBadges,
    COALESCE(ubs.SilverBadges, 0) AS SilverBadges,
    COALESCE(ubs.BronzeBadges, 0) AS BronzeBadges,
    ubs.FirstGoldBadgeDate,
    ubs.LatestSilverBadgeDate,
    (
        -- Correlated subquery: Find the most active tag for the user
        SELECT pti_max.TagName
        FROM PostTaggingInfo pti_max
        WHERE pti_max.OwnerUserId = u.Id
        GROUP BY pti_max.TagName
        ORDER BY COUNT(pti_max.PostId) DESC, pti_max.TagName
        LIMIT 1
    ) AS MostActiveTagName,
    (
        -- Correlated subquery: Count user's closed questions that also received favorites
        SELECT COUNT(p_closed.Id)
        FROM Posts p_closed
        WHERE p_closed.OwnerUserId = u.Id
          AND p_closed.PostTypeId = 1
          AND p_closed.ClosedDate IS NOT NULL
          AND p_closed.FavoriteCount > 0
    ) AS UserClosedFavoritedQuestionsCount,
    COALESCE(uva.TotalUpVotesGiven, 0) AS TotalUpVotesGiven,
    COALESCE(uva.TotalDownVotesGiven, 0) AS TotalDownVotesGiven,
    COALESCE(uva.TotalUpVotesReceivedOnPosts, 0) AS TotalUpVotesReceivedOnPosts,
    COALESCE(uva.TotalDownVotesReceivedOnPosts, 0) AS TotalDownVotesReceivedOnPosts,
    COALESCE(upea.UserTotalPostEdits, 0) AS TotalPostEditsByOwner,
    COALESCE(ROUND(upea.UserAvgSecondsBetweenEdits / 3600, 2), 0.00) AS AvgHoursBetweenPostEdits,
    upea.UserLatestPostEditDate,
    NULLIF(u.Views, 0) AS UserViewsNormalized, -- NULLIF example
    LOWER(SUBSTRING(COALESCE(u.Location, 'Unknown Location'), 1, 20)) AS UserLocationSnippet, -- String functions and NULL logic
    CASE -- Complicated CASE expression for user bio category
        WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 100 AND u.AboutMe LIKE '%stack%' THEN 'Long & Stack-related Bio'
        WHEN u.AboutMe IS NOT NULL AND u.AboutMe LIKE '%developer%' THEN 'Developer Bio'
        WHEN u.AboutMe IS NOT NULL AND LENGTH(u.AboutMe) > 0 THEN 'Short Generic Bio'
        ELSE 'No Bio'
    END AS AboutMeCategory,
    (
        -- Correlated subquery with ARRAY_AGG: Collect distinct tags from user's questions
        SELECT ARRAY_AGG(DISTINCT pti_inner.TagName ORDER BY pti_inner.TagName)
        FROM PostTaggingInfo pti_inner
        WHERE pti_inner.OwnerUserId = u.Id
          AND pti_inner.PostTypeId = 1
        GROUP BY pti_inner.OwnerUserId
    ) AS UserQuestionTags,
    LAG(u.LastAccessDate) OVER (ORDER BY u.CreationDate, u.Id) AS PreviousUserLastAccessDate, -- Window function: previous user's last access date
    RANK() OVER (PARTITION BY (COALESCE(ubs.GoldBadges,0) > 0) ORDER BY urr.Reputation DESC, u.Id) AS RankByReputationAmongBadgeHolders, -- Window function with complex partition
    (
        -- Correlated subquery: Title of the latest question's accepted answer
        SELECT p_acc.Title
        FROM Posts p_acc
        WHERE p_acc.Id = (
            SELECT p_q.AcceptedAnswerId
            FROM Posts p_q
            WHERE p_q.OwnerUserId = u.Id AND p_q.PostTypeId = 1 AND p_q.AcceptedAnswerId IS NOT NULL
            ORDER BY p_q.CreationDate DESC
            LIMIT 1
        )
        LIMIT 1
    ) AS LatestAcceptedAnswerTitle,
    COALESCE(upl.TotalLinkedPostsCreated, 0) AS TotalLinkedPostsCreated,
    COALESCE(upl.TotalDuplicateSourcesCreated, 0) AS TotalDuplicateSourcesCreated
FROM
    Users u
INNER JOIN
    UserReputationRank urr ON u.Id = urr.UserId
LEFT JOIN
    UserPostStats ups ON u.Id = ups.UserId
LEFT JOIN
    UserBadgeSummary ubs ON u.Id = ubs.UserId
LEFT JOIN
    UserPostEditAggregates upea ON u.Id = upea.UserId
LEFT JOIN
    UserVoteActivity uva ON u.Id = uva.UserId
LEFT JOIN
    UserPostLinks upl ON u.Id = upl.UserId
WHERE
    urr.ReputationRankYearly <= 100 -- Filter for top 100 users by reputation in their creation year
    AND COALESCE(ubs.GoldBadges, 0) >= 1 -- Only users with at least one gold badge
    AND COALESCE(ups.TotalPosts, 0) >= 5 -- Only users with at least 5 posts
    AND u.LastAccessDate >= (NOW() - INTERVAL '1 year') -- Active users in the last year
    AND (u.DisplayName LIKE '%dev%' OR u.DisplayName IS NULL) -- String pattern or NULL logic
GROUP BY
    u.Id, u.DisplayName, urr.Reputation, urr.CreationDate, urr.ReputationRankYearly,
    ups.TotalPosts, ups.TotalQuestions, ups.TotalAnswers, ups.AvgQuestionScore, ups.AvgAnswerScore,
    ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, ubs.FirstGoldBadgeDate, ubs.LatestSilverBadgeDate,
    upea.UserTotalPostEdits, upea.UserAvgSecondsBetweenEdits, upea.UserLatestPostEditDate,
    u.Views, u.Location, u.AboutMe, u.LastAccessDate, urr.OverallReputationRank,
    uva.TotalUpVotesGiven, uva.TotalDownVotesGiven, uva.TotalUpVotesReceivedOnPosts, uva.TotalDownVotesReceivedOnPosts,
    upl.TotalLinkedPostsCreated, upl.TotalDuplicateSourcesCreated
HAVING
    (SELECT COUNT(DISTINCT pti_inner_having.TagName) FROM PostTaggingInfo pti_inner_having WHERE pti_inner_having.OwnerUserId = u.Id) > 2 -- Having clause with correlated subquery: active in more than 2 tags
    AND COALESCE(uva.TotalOffensiveVotesGiven, 0) = 0 -- Users who have never cast an 'Offensive' vote
    AND (COALESCE(uva.TotalUpVotesReceivedOnPosts, 0) + COALESCE(uva.TotalDownVotesReceivedOnPosts, 0)) > 10 -- Received at least 10 votes (up or down)
ORDER BY
    urr.OverallReputationRank ASC, u.Id
LIMIT 500;
