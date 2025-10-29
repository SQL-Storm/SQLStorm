-- {"query": "1359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2940} 

WITH UserActivitySummary AS (
    -- Aggregates various post and comment statistics for each user
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestionsAsked,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswersPosted,
        SUM(COALESCE(p.Score, 0)) AS SumPostScores,
        AVG(CASE WHEN p.Score IS NOT NULL THEN p.Score ELSE 0 END) AS AvgPostScore,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        SUM(COALESCE(c.Score, 0)) AS SumCommentScores,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MIN(p.CreationDate) AS FirstPostCreationDate,
        DATE_PART('day', u.LastAccessDate - u.CreationDate) AS DaysActive,
        SUM(CASE WHEN q.AcceptedAnswerId = p.Id AND p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AcceptedAnswersCount,
        COUNT(DISTINCT p.AcceptedAnswerId) FILTER (WHERE p.PostTypeId = 1) AS QuestionsWithAcceptedAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1 -- To link answers back to questions for accepted status
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
UserBadgeMilestones AS (
    -- Summarizes badge information for each user
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalBadgesAwarded,
        COUNT(CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        MIN(b.Date) AS EarliestBadgeDate,
        (SELECT COUNT(DISTINCT Name) FROM Badges b_sub WHERE b_sub.UserId = b.UserId AND b_sub.TagBased = TRUE) AS UniqueTagBadges
    FROM Badges b
    GROUP BY b.UserId
),
UserContentHistory AS (
    -- Tracks post history actions by users, focusing on edits and moderator actions
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEdited,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditActionsCount, -- Title, Body, Tags
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN ph.Id END) AS ModerationActivityCount, -- Closed, Reopened, Deleted, Undeleted, Locked, Unlocked
        MAX(ph.CreationDate) AS LastHistoryAction
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TopTagsByUser AS (
    -- Identifies the most frequently used tag for questions asked by each user
    WITH UserTagCounts AS (
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))) AS TagName,
            COUNT(*) AS TagFrequency
        FROM Posts p
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, TRIM(UNNEST(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')))
    )
    SELECT
        utc.UserId,
        utc.TagName AS PrimaryTag,
        utc.TagFrequency AS PrimaryTagPostCount
    FROM UserTagCounts utc
    QUALIFY ROW_NUMBER() OVER (PARTITION BY utc.UserId ORDER BY utc.TagFrequency DESC, utc.TagName ASC) = 1
),
PostLinkAnalysis AS (
    -- Counts incoming and outgoing links for posts owned by each user
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pl_out.RelatedPostId) AS OutgoingLinksCount, -- Posts by this user link to other posts
        COUNT(DISTINCT pl_in.PostId) AS IncomingLinksCount, -- Other posts link to posts by this user
        COUNT(DISTINCT CASE WHEN pl_out.LinkTypeId = 3 THEN pl_out.RelatedPostId END) AS DuplicateLinksCount
    FROM Posts p
    LEFT JOIN PostLinks pl_out ON p.Id = pl_out.PostId
    LEFT JOIN PostLinks pl_in ON p.Id = pl_in.RelatedPostId
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UserCreationDate,
    uas.LastAccessDate,
    uas.TotalPostsCreated,
    uas.TotalQuestionsAsked,
    uas.TotalAnswersPosted,
    uas.AvgPostScore,
    uas.TotalCommentsMade,
    ubm.GoldBadges,
    ubm.SilverBadges,
    ubm.TotalBadgesAwarded,
    uch.EditActionsCount,
    uch.ModerationActivityCount,
    tta.PrimaryTag,
    tta.PrimaryTagPostCount,
    pla.OutgoingLinksCount,
    pla.IncomingLinksCount,
    pla.DuplicateLinksCount,
    uas.AcceptedAnswersCount AS UserAcceptedAnswers,
    -- Complex calculated user score based on various metrics
    CAST(
        (uas.Reputation * 0.5) +
        (uas.SumPostScores * 0.8) +
        (uas.UserProfileViews * 0.1) +
        (uas.TotalUpVotesGiven * 0.3) -
        (uas.TotalDownVotesGiven * 0.15) +
        (ubm.GoldBadges * 50) +
        (ubm.SilverBadges * 15) +
        (ubm.BronzeBadges * 5) +
        (uch.EditActionsCount * 2) +
        (uch.ModerationActivityCount * -10) + -- Negative impact for moderator actions on own posts
        (uas.AcceptedAnswersCount * 25) +
        (uas.QuestionsWithAcceptedAnswers * 10) +
        (COALESCE(tta.PrimaryTagPostCount, 0) * 0.5)
    AS DECIMAL(18, 2)) AS ComprehensiveUserScore,
    -- Window function: Rank users by reputation
    RANK() OVER (ORDER BY uas.Reputation DESC, uas.LastAccessDate DESC) AS ReputationRank,
    -- Window function: Calculate the difference in reputation from the user with the next highest score
    LAG(uas.Reputation, 1, 0) OVER (ORDER BY uas.Reputation DESC) - uas.Reputation AS RepDiffFromHigherRank,
    -- Window function: Assign users to percentiles based on their calculated score
    NTILE(10) OVER (ORDER BY (
        (uas.Reputation * 0.5) +
        (uas.SumPostScores * 0.8) +
        (uas.UserProfileViews * 0.1) +
        (uas.TotalUpVotesGiven * 0.3) -
        (uas.TotalDownVotesGiven * 0.15) +
        (ubm.GoldBadges * 50) +
        (ubm.SilverBadges * 15) +
        (ubm.BronzeBadges * 5) +
        (uch.EditActionsCount * 2) +
        (uch.ModerationActivityCount * -10) +
        (uas.AcceptedAnswersCount * 25) +
        (uas.QuestionsWithAcceptedAnswers * 10) +
        (COALESCE(tta.PrimaryTagPostCount, 0) * 0.5)
    ) DESC) AS EngagementScoreDecile,
    -- Conditional categorization of users
    CASE
        WHEN uas.Reputation >= 10000 AND ubm.GoldBadges >= 3 AND uas.AcceptedAnswersCount >= 10 THEN 'Legendary Contributor'
        WHEN uas.Reputation >= 5000 AND ubm.SilverBadges >= 5 THEN 'Distinguished Expert'
        WHEN uas.Reputation >= 1000 AND uas.TotalPostsCreated >= 50 THEN 'Active Contributor'
        WHEN uas.Reputation >= 200 AND uas.TotalPostsCreated >= 10 THEN 'Engaged Participant'
        ELSE 'Emerging User'
    END AS UserCategory,
    -- Correlated subquery: Check if the user has any posts closed as a duplicate
    EXISTS (
        SELECT 1
        FROM PostHistory ph_dup
        JOIN PostHistoryTypes pht_dup ON ph_dup.PostHistoryTypeId = pht_dup.Id
        WHERE ph_dup.UserId = uas.UserId
          AND pht_dup.Name = 'Post Closed'
          AND ph_dup.Comment LIKE '%101%' -- Assuming '101' is close reason for 'Duplicate'
    ) AS HasDuplicateClosedPost,
    -- Correlated subquery: Calculate the average score of comments for posts owned by this user
    (
        SELECT AVG(COALESCE(c_post.Score, 0))
        FROM Comments c_post
        JOIN Posts p_owned ON c_post.PostId = p_owned.Id
        WHERE p_owned.OwnerUserId = uas.UserId
          AND c_post.CreationDate BETWEEN uas.UserCreationDate AND uas.LastAccessDate
          AND c_post.Text IS NOT NULL AND LENGTH(c_post.Text) > 10
    ) AS AvgCommentScoreOnOwnPosts
FROM UserActivitySummary uas
LEFT JOIN UserBadgeMilestones ubm ON uas.UserId = ubm.UserId
LEFT JOIN UserContentHistory uch ON uas.UserId = uch.UserId
LEFT JOIN TopTagsByUser tta ON uas.UserId = tta.UserId
LEFT JOIN PostLinkAnalysis pla ON uas.UserId = pla.UserId
WHERE
    uas.TotalPostsCreated > 0 -- Ensure user has at least one post
    AND uas.Reputation IS NOT NULL
    AND uas.DaysActive > 30 -- Filter for users active for more than 30 days
    AND (
        (uas.DisplayName LIKE 'Stack%' AND uas.UserProfileViews > 100)
        OR (uas.TotalCommentsMade >= 50 AND uas.SumPostScores >= 500)
        OR (uas.LastAccessDate > NOW() - INTERVAL '6 months' AND uas.TotalQuestionsAsked > 0)
    )
    -- Correlated subquery in WHERE: Only include users who have at least one post with a title containing 'SQL' or 'Database'
    AND EXISTS (
        SELECT 1
        FROM Posts p_title
        WHERE p_title.OwnerUserId = uas.UserId
          AND p_title.PostTypeId = 1 -- Only consider questions
          AND p_title.Title IS NOT NULL
          AND (p_title.Title LIKE '%SQL%' OR p_title.Title LIKE '%Database%')
    )
    -- NULL logic: Only show users where their location is either known or they have a significant reputation
    AND (u.Location IS NOT NULL OR uas.Reputation > 500)
    -- Complicated predicate: Check if the user's last access date is within the last year,
    -- and if their first post was made after their first badge (if any)
    AND uas.LastAccessDate >= NOW() - INTERVAL '1 year'
    AND (ubm.EarliestBadgeDate IS NULL OR uas.FirstPostCreationDate >= ubm.EarliestBadgeDate)
ORDER BY
    ComprehensiveUserScore DESC,
    uas.LastAccessDate DESC
LIMIT 1000;
