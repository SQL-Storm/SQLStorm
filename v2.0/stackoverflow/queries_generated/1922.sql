-- {"query": "1922.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3845} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.Location,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT v.Id) AS TotalVotesCast,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesCastByUserId,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesCastByUserId,
        MAX(COALESCE(p.LastActivityDate, c.CreationDate, v.CreationDate, u.LastAccessDate)) AS LatestActivityGlobally
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl, u.Location, u.Views, u.UpVotes, u.DownVotes
),
PostDetailsAndHistory AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        -- Calculate number of unique tags for questions
        ARRAY_LENGTH(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1) AS NumberOfTags,
        -- Count post history events
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9) THEN 1 ELSE 0 END) AS TotalEditEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS TotalCloseEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS TotalReopenEvents,
        -- Correlated subquery: check if post was ever edited by its original owner
        EXISTS (
            SELECT 1
            FROM PostHistory ph_owner_edit
            WHERE ph_owner_edit.PostId = p.Id
              AND ph_owner_edit.UserId = p.OwnerUserId
              AND ph_owner_edit.PostHistoryTypeId IN (4, 5, 6)
        ) AS EditedByOwnerFlag,
        -- Correlated subquery: Count linked posts of type 'Linked'
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostsOutCount,
        -- Correlated subquery: Count linked posts of type 'Duplicate'
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS DuplicatePostsOutCount
    FROM
        Posts p
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE
        p.PostTypeId IN (1, 2) -- Focus on Questions and Answers
        AND p.OwnerUserId IS NOT NULL -- Exclude community-owned posts without a real owner
    GROUP BY
        p.Id, p.OwnerUserId, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.LastEditDate, p.LastActivityDate, p.Title, p.Tags
),
UserPostAggregates AS (
    SELECT
        pdh.OwnerUserId AS UserId,
        COUNT(DISTINCT pdh.PostId) AS TotalAnalyzedPosts,
        SUM(pdh.PostScore) AS TotalPostsScoreSum,
        AVG(pdh.PostScore) AS AveragePostScore,
        MAX(pdh.PostViewCount) AS MaxPostViewCount,
        SUM(pdh.AnswerCount) AS TotalAnswersOnQuestions,
        AVG(pdh.AnswerCount) AS AvgAnswersOnQuestions,
        SUM(pdh.TotalEditEvents) AS TotalPostEditEvents,
        SUM(pdh.TotalCloseEvents) AS TotalPostCloseEvents,
        SUM(pdh.TotalReopenEvents) AS TotalPostReopenEvents,
        SUM(CASE WHEN pdh.EditedByOwnerFlag THEN 1 ELSE 0 END) AS PostsEditedByOwnerCount,
        -- Use LATERAL UNNEST for tag parsing and then count distinct tags per user
        COUNT(DISTINCT t.TagName) AS UniqueTagsUsedInQuestions,
        SUM(pdh.LinkedPostsOutCount) AS TotalLinkedPostsOutgoing,
        SUM(pdh.DuplicatePostsOutCount) AS TotalDuplicatePostsOutgoing
    FROM
        PostDetailsAndHistory pdh
    LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(pdh.Tags, 2, LENGTH(pdh.Tags)-2), '><')) AS t(TagName)
        ON pdh.PostTypeId = 1 AND pdh.Tags IS NOT NULL AND LENGTH(pdh.Tags) > 2 -- Only analyze tags for questions
    GROUP BY
        pdh.OwnerUserId
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadgesCount,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadgesCount,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM
        Badges b
    GROUP BY
        b.UserId
),
CombinedUserData AS (
    SELECT
        ue.UserId,
        ue.DisplayName,
        ue.Reputation,
        ue.UserCreationDate,
        ue.LastAccessDate,
        ue.WebsiteUrl,
        ue.Location,
        ue.UserProfileViews,
        ue.UserUpVotesGiven,
        ue.UserDownVotesGiven,
        ue.TotalPostsOwned,
        ue.TotalQuestionsOwned,
        ue.TotalAnswersOwned,
        ue.TotalCommentsMade,
        ue.TotalVotesCast,
        ue.UpVotesCastByUserId,
        ue.DownVotesCastByUserId,
        ue.LatestActivityGlobally,
        COALESCE(upa.TotalAnalyzedPosts, 0) AS TotalAnalyzedPosts,
        COALESCE(upa.TotalPostsScoreSum, 0) AS TotalPostsScoreSum,
        COALESCE(upa.AveragePostScore, 0.0) AS AveragePostScore,
        COALESCE(upa.MaxPostViewCount, 0) AS MaxPostViewCount,
        COALESCE(upa.TotalAnswersOnQuestions, 0) AS TotalAnswersOnQuestions,
        COALESCE(upa.AvgAnswersOnQuestions, 0.0) AS AvgAnswersOnQuestions,
        COALESCE(upa.TotalPostEditEvents, 0) AS TotalPostEditEvents,
        COALESCE(upa.TotalPostCloseEvents, 0) AS TotalPostCloseEvents,
        COALESCE(upa.TotalPostReopenEvents, 0) AS TotalPostReopenEvents,
        COALESCE(upa.PostsEditedByOwnerCount, 0) AS PostsEditedByOwnerCount,
        COALESCE(upa.UniqueTagsUsedInQuestions, 0) AS UniqueTagsUsedInQuestions,
        COALESCE(upa.TotalLinkedPostsOutgoing, 0) AS TotalLinkedPostsOutgoing,
        COALESCE(upa.TotalDuplicatePostsOutgoing, 0) AS TotalDuplicatePostsOutgoing,
        COALESCE(ubs.TotalBadgesEarned, 0) AS TotalBadgesEarned,
        COALESCE(ubs.GoldBadgesCount, 0) AS GoldBadgesCount,
        COALESCE(ubs.SilverBadgesCount, 0) AS SilverBadgesCount,
        COALESCE(ubs.BronzeBadgesCount, 0) AS BronzeBadgesCount,
        ubs.LastBadgeAwardDate,
        -- Complex calculation for user activity score (weighted sum)
        (ue.Reputation * 0.15) + (ue.TotalPostsOwned * 0.7) + (ue.TotalCommentsMade * 0.25) +
        (COALESCE(upa.AveragePostScore, 0) * 0.9) + (COALESCE(upa.UniqueTagsUsedInQuestions, 0) * 0.4) +
        (COALESCE(ubs.GoldBadgesCount, 0) * 10) + (COALESCE(ubs.SilverBadgesCount, 0) * 4) + (COALESCE(ubs.BronzeBadgesCount, 0) * 1) +
        (EXTRACT(EPOCH FROM (NOW() - ue.UserCreationDate)) / 31536000.0 * 0.01) -- Age factor
        AS ActivityScore
    FROM
        UserEngagement ue
    LEFT JOIN UserPostAggregates upa ON ue.UserId = upa.UserId
    LEFT JOIN UserBadgeSummary ubs ON ue.UserId = ubs.UserId
),
RankedUserData AS (
    SELECT
        *,
        -- Window function: Rank users by their overall activity score
        RANK() OVER (ORDER BY ActivityScore DESC, Reputation DESC, LatestActivityGlobally DESC) AS OverallActivityRank,
        -- Window function: Calculate average activity score for users in the same reputation tier
        AVG(ActivityScore) OVER (PARTITION BY FLOOR(Reputation / 5000) * 5000) AS AvgActivityScoreInRepTier,
        -- Window function: Compare current user's activity score to the immediately preceding user in rank
        LAG(ActivityScore, 1, 0.0) OVER (ORDER BY ActivityScore DESC) AS PreviousRankActivityScore,
        -- Window function: DENSE_RANK based on badge counts within the same user creation year
        DENSE_RANK() OVER (PARTITION BY EXTRACT(YEAR FROM UserCreationDate) ORDER BY GoldBadgesCount DESC, SilverBadgesCount DESC, BronzeBadgesCount DESC) AS BadgeRankWithinCreationYear
    FROM
        CombinedUserData cud
    WHERE
        cud.TotalPostsOwned > 0 OR cud.TotalCommentsMade > 0 OR cud.TotalVotesCast > 0 OR cud.TotalBadgesEarned > 0
)
-- Main query to select and combine data using UNION ALL for different user segments
-- Segment 1: Highly active and influential users based on overall rank and significant contributions
SELECT
    rud.UserId,
    rud.DisplayName,
    rud.Reputation,
    rud.OverallActivityRank,
    rud.ActivityScore,
    rud.TotalPostsOwned,
    rud.TotalCommentsMade,
    rud.TotalBadgesEarned,
    rud.GoldBadgesCount,
    rud.SilverBadgesCount,
    rud.BronzeBadgesCount,
    rud.LatestActivityGlobally,
    rud.AvgActivityScoreInRepTier,
    rud.TotalPostCloseEvents,
    rud.TotalPostReopenEvents,
    rud.TotalLinkedPostsOutgoing,
    rud.UniqueTagsUsedInQuestions,
    rud.Location,
    rud.WebsiteUrl,
    rud.PreviousRankActivityScore,
    rud.BadgeRankWithinCreationYear,
    -- Complicated string expression with NULL handling and conditional formatting
    COALESCE(
        CASE
            WHEN rud.WebsiteUrl IS NOT NULL AND LENGTH(rud.WebsiteUrl) > 8 AND rud.WebsiteUrl LIKE 'http%'
                THEN 'Web: ' || UPPER(SUBSTRING(rud.WebsiteUrl, POSITION('//' IN rud.WebsiteUrl) + 2, 5)) || '...'
            WHEN rud.Location IS NOT NULL AND LENGTH(rud.Location) > 5
                THEN 'Loc: ' || INITCAP(SUBSTRING(rud.Location, 1, 8)) || '...'
            ELSE 'No Public Contact Info'
        END,
        'Info Not Available'
    ) AS FormattedContactInfo
FROM
    RankedUserData rud
WHERE
    rud.OverallActivityRank <= 250 -- Top 250 overall active users
    AND rud.Reputation > 5000
    AND rud.LatestActivityGlobally >= NOW() - INTERVAL '6 months' -- Active in last 6 months
    AND (rud.UniqueTagsUsedInQuestions > 10 OR rud.TotalPostEditEvents > 20) -- Diverse tagging or active editor
    AND (rud.Location IS NOT NULL OR rud.WebsiteUrl IS NOT NULL) -- Has some public info
    AND NOT EXISTS (
        SELECT 1 FROM Posts p_check WHERE p_check.OwnerUserId = rud.UserId AND p_check.ClosedDate IS NOT NULL AND p_check.PostTypeId = 1
        GROUP BY p_check.OwnerUserId HAVING COUNT(p_check.Id) > 5 -- User doesn't have too many closed questions
    )

UNION ALL

-- Segment 2: Users who are less overall active but recently awarded significant badges and contribute to specific tech tags
SELECT
    rud.UserId,
    rud.DisplayName,
    rud.Reputation,
    rud.OverallActivityRank,
    rud.ActivityScore,
    rud.TotalPostsOwned,
    rud.TotalCommentsMade,
    rud.TotalBadgesEarned,
    rud.GoldBadgesCount,
    rud.SilverBadgesCount,
    rud.BronzeBadgesCount,
    rud.LatestActivityGlobally,
    rud.AvgActivityScoreInRepTier,
    rud.TotalPostCloseEvents,
    rud.TotalPostReopenEvents,
    rud.TotalLinkedPostsOutgoing,
    rud.UniqueTagsUsedInQuestions,
    rud.Location,
    rud.WebsiteUrl,
    rud.PreviousRankActivityScore,
    rud.BadgeRankWithinCreationYear,
    COALESCE(
        CASE
            WHEN rud.WebsiteUrl IS NOT NULL AND LENGTH(rud.WebsiteUrl) > 8 AND rud.WebsiteUrl LIKE 'http%'
                THEN 'Web: ' || UPPER(SUBSTRING(rud.WebsiteUrl, POSITION('//' IN rud.WebsiteUrl) + 2, 5)) || '...'
            WHEN rud.Location IS NOT NULL AND LENGTH(rud.Location) > 5
                THEN 'Loc: ' || INITCAP(SUBSTRING(rud.Location, 1, 8)) || '...'
            ELSE 'No Public Contact Info'
        END,
        'Info Not Available'
    ) AS FormattedContactInfo
FROM
    RankedUserData rud
WHERE
    rud.LastBadgeAwardDate >= NOW() - INTERVAL '3 months' -- Recently awarded a badge
    AND rud.GoldBadgesCount > 0 -- Has at least one gold badge
    AND rud.Reputation BETWEEN 1000 AND 10000 -- Mid-range reputation
    AND rud.TotalQuestionsOwned > 0 -- Must have asked at least one question
    AND EXISTS ( -- Correlated subquery: Check if user has questions tagged with specific keywords
        SELECT 1
        FROM Posts p_inner
        LEFT JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p_inner.Tags, 2, LENGTH(p_inner.Tags)-2), '><')) AS t_inner(TagName)
            ON p_inner.PostTypeId = 1 AND p_inner.Tags IS NOT NULL AND LENGTH(p_inner.Tags) > 2
        WHERE p_inner.OwnerUserId = rud.UserId
          AND t_inner.TagName ILIKE ANY (ARRAY['%java%', '%python%', '%javascript%', '%c#%', '%node.js%', '%react%'])
    )
ORDER BY
    OverallActivityRank ASC, LatestActivityGlobally DESC, ActivityScore DESC
LIMIT 1000;
