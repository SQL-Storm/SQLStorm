-- {"query": "1359.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2940}
WITH UserActivitySummary AS (
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
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
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
    LEFT JOIN Posts q ON p.ParentId = q.Id AND q.PostTypeId = 1
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
UserBadgeMilestones AS (
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
    SELECT
        ph.UserId,
        COUNT(DISTINCT ph.PostId) AS UniquePostsEdited,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) AS EditActionsCount,
        COUNT(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15) THEN ph.Id END) AS ModerationActivityCount,
        MAX(ph.CreationDate) AS LastHistoryAction
    FROM PostHistory ph
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId
),
TopTagsByUser AS (
    WITH UserTagCounts AS (
        -- Attempt a portable extraction of tags: remove leading/trailing angle brackets then split on '><'
        SELECT
            p.OwnerUserId AS UserId,
            TRIM(tag) AS TagName,
            COUNT(*) AS TagFrequency
        FROM Posts p,
        LATERAL (
            -- Use regexp_split_to_table when available; otherwise rely on a generic string_split-like function named 'regexp_split_to_table'.
            -- This lateral will work in Postgres. For other dialects adapt to their split function.
            SELECT regexp_split_table AS tag
            FROM (
                SELECT regexp_split_to_table(
                    -- strip outer brackets if present
                    CASE
                        WHEN p.Tags LIKE '<%>' THEN SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags) - 2)
                        ELSE p.Tags
                    END,
                    '><'
                ) AS regexp_split_table
            ) s1
        ) s
        WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.OwnerUserId IS NOT NULL
        GROUP BY p.OwnerUserId, TRIM(tag)
    )
    SELECT utc.UserId, utc.TagName AS PrimaryTag, utc.TagFrequency AS PrimaryTagPostCount
    FROM (
        SELECT
            utc.*,
            ROW_NUMBER() OVER (PARTITION BY utc.UserId ORDER BY utc.TagFrequency DESC, utc.TagName ASC) AS rn
        FROM UserTagCounts utc
    ) utc
    WHERE utc.rn = 1
),
PostLinkAnalysis AS (
    SELECT
        p.OwnerUserId AS UserId,
        COUNT(DISTINCT pl_out.RelatedPostId) AS OutgoingLinksCount,
        COUNT(DISTINCT pl_in.PostId) AS IncomingLinksCount,
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
    CAST(
        (COALESCE(uas.Reputation,0) * 0.5) +
        (COALESCE(uas.SumPostScores,0) * 0.8) +
        (COALESCE(uas.UserProfileViews,0) * 0.1) +
        (COALESCE(uas.TotalUpVotesGiven,0) * 0.3) -
        (COALESCE(uas.TotalDownVotesGiven,0) * 0.15) +
        (COALESCE(ubm.GoldBadges,0) * 50) +
        (COALESCE(ubm.SilverBadges,0) * 15) +
        (COALESCE(ubm.BronzeBadges,0) * 5) +
        (COALESCE(uch.EditActionsCount,0) * 2) +
        (COALESCE(uch.ModerationActivityCount,0) * -10) +
        (COALESCE(uas.AcceptedAnswersCount,0) * 25) +
        (COALESCE(uas.QuestionsWithAcceptedAnswers,0) * 10) +
        (COALESCE(tta.PrimaryTagPostCount, 0) * 0.5)
    AS DECIMAL(18, 2)) AS ComprehensiveUserScore,
    RANK() OVER (ORDER BY uas.Reputation DESC, uas.LastAccessDate DESC) AS ReputationRank,
    LAG(uas.Reputation, 1, 0) OVER (ORDER BY uas.Reputation DESC) - uas.Reputation AS RepDiffFromHigherRank,
    NTILE(10) OVER (ORDER BY (
        (COALESCE(uas.Reputation,0) * 0.5) +
        (COALESCE(uas.SumPostScores,0) * 0.8) +
        (COALESCE(uas.UserProfileViews,0) * 0.1) +
        (COALESCE(uas.TotalUpVotesGiven,0) * 0.3) -
        (COALESCE(uas.TotalDownVotesGiven,0) * 0.15) +
        (COALESCE(ubm.GoldBadges,0) * 50) +
        (COALESCE(ubm.SilverBadges,0) * 15) +
        (COALESCE(ubm.BronzeBadges,0) * 5) +
        (COALESCE(uch.EditActionsCount,0) * 2) +
        (COALESCE(uch.ModerationActivityCount,0) * -10) +
        (COALESCE(uas.AcceptedAnswersCount,0) * 25) +
        (COALESCE(uas.QuestionsWithAcceptedAnswers,0) * 10) +
        (COALESCE(tta.PrimaryTagPostCount, 0) * 0.5)
    ) DESC) AS EngagementScoreDecile,
    CASE
        WHEN uas.Reputation >= 10000 AND COALESCE(ubm.GoldBadges,0) >= 3 AND COALESCE(uas.AcceptedAnswersCount,0) >= 10 THEN 'Legendary Contributor'
        WHEN uas.Reputation >= 5000 AND COALESCE(ubm.SilverBadges,0) >= 5 THEN 'Distinguished Expert'
        WHEN uas.Reputation >= 1000 AND COALESCE(uas.TotalPostsCreated,0) >= 50 THEN 'Active Contributor'
        WHEN uas.Reputation >= 200 AND COALESCE(uas.TotalPostsCreated,0) >= 10 THEN 'Engaged Participant'
        ELSE 'Emerging User'
    END AS UserCategory,
    EXISTS (
        SELECT 1
        FROM PostHistory ph_dup
        JOIN PostHistoryTypes pht_dup ON ph_dup.PostHistoryTypeId = pht_dup.Id
        WHERE ph_dup.UserId = uas.UserId
          AND pht_dup.Name = 'Post Closed'
          AND ph_dup.Comment LIKE '%101%'
    ) AS HasDuplicateClosedPost,
    (
        SELECT AVG(COALESCE(c_post.Score, 0))
        FROM Comments c_post
        JOIN Posts p_owned ON c_post.PostId = p_owned.Id
        WHERE p_owned.OwnerUserId = uas.UserId
          AND c_post.CreationDate BETWEEN uas.UserCreationDate AND uas.LastAccessDate
          AND c_post.Text IS NOT NULL AND CHAR_LENGTH(c_post.Text) > 10
    ) AS AvgCommentScoreOnOwnPosts
FROM UserActivitySummary uas
LEFT JOIN UserBadgeMilestones ubm ON uas.UserId = ubm.UserId
LEFT JOIN UserContentHistory uch ON uas.UserId = uch.UserId
LEFT JOIN TopTagsByUser tta ON uas.UserId = tta.UserId
LEFT JOIN PostLinkAnalysis pla ON uas.UserId = pla.UserId
LEFT JOIN Users u ON uas.UserId = u.Id
WHERE
    uas.TotalPostsCreated > 0
    AND uas.Reputation IS NOT NULL
    AND uas.DaysActive > 30
    AND (
        (uas.DisplayName LIKE 'Stack%' AND uas.UserProfileViews > 100)
        OR (uas.TotalCommentsMade >= 50 AND uas.SumPostScores >= 500)
        OR (uas.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months') AND uas.TotalQuestionsAsked > 0)
    )
    AND EXISTS (
        SELECT 1
        FROM Posts p_title
        WHERE p_title.OwnerUserId = uas.UserId
          AND p_title.PostTypeId = 1
          AND p_title.Title IS NOT NULL
          AND (p_title.Title LIKE '%SQL%' OR p_title.Title LIKE '%Database%')
    )
    AND (u.Location IS NOT NULL OR uas.Reputation > 500)
    AND uas.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
    AND (ubm.EarliestBadgeDate IS NULL OR uas.FirstPostCreationDate >= ubm.EarliestBadgeDate)
ORDER BY
    ComprehensiveUserScore DESC,
    uas.LastAccessDate DESC
LIMIT 1000;