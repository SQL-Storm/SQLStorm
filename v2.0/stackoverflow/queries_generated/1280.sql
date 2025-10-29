-- {"query": "1280.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3701} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(p.Score), 0) AS TotalPostScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 1), 0) AS AvgQuestionScore,
        COALESCE(AVG(p.Score) FILTER (WHERE p.PostTypeId = 2), 0) AS AvgAnswerScore,
        COALESCE(SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END), 0) AS TotalEditsContributed,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(b.Date) AS LatestBadgeDate,
        -- UserAgeDays calculation handling potential division by zero later
        EXTRACT(EPOCH FROM (NOW() - u.CreationDate)) / 86400.0 AS UserAgeDays
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    -- Join PostHistory to count edits contributed by the user, not necessarily on their own posts
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.Views, u.UpVotes, u.DownVotes
),
PostPerformance AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        LENGTH(p.Body) AS BodyLength,
        p.Title,
        p.Tags,
        -- Use COALESCE for IDs that can be NULL, setting a distinct non-existent ID
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COALESCE(p.ParentId, -1) AS ParentPostId,
        -- Subqueries for specific counts related to the post
        (SELECT COUNT(ph_sub.Id) FROM PostHistory ph_sub WHERE ph_sub.PostId = p.Id AND ph_sub.PostHistoryTypeId IN (4,5,6)) AS PostEditCount,
        (SELECT COUNT(v_sub.Id) FROM Votes v_sub WHERE v_sub.PostId = p.Id AND v_sub.VoteTypeId = 2) AS UpVoteCount,
        (SELECT COUNT(v_sub.Id) FROM Votes v_sub WHERE v_sub.PostId = p.Id AND v_sub.VoteTypeId = 3) AS DownVoteCount,
        -- String function combined with array for tag count
        COALESCE(ARRAY_LENGTH(STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags)-2), '><'), 1), 0) AS TagCount,
        -- Window functions
        RANK() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RankByScoreAndViews,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) AS RollingAvgUserPostScore,
        -- Check if post has an accepted answer vote
        SUM(CASE WHEN v.VoteTypeId = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id) AS IsAcceptedAnswerVoteIndicator
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId = 1 -- Only for AcceptedByOriginator check
    WHERE p.OwnerUserId IS NOT NULL -- Focus on posts with an identifiable owner
),
PostLinkSummary AS (
    -- Using FULL OUTER JOIN to capture all posts involved in links, both source and target
    -- And identifying their role with a CASE statement. Aggregates link data per PostId.
    SELECT
        COALESCE(p_all.Id, pl.PostId, pl.RelatedPostId) AS PostId,
        STRING_AGG(DISTINCT lt.Name, '; ') AS LinkTypeNames,
        MAX(CASE
            WHEN pl.PostId IS NOT NULL AND pl.RelatedPostId IS NOT NULL THEN 'LinkedAndRelated'
            WHEN pl.PostId IS NOT NULL THEN 'SourceOfLink'
            WHEN pl.RelatedPostId IS NOT NULL THEN 'TargetOfLink'
            ELSE 'NoLinkInfo'
        END) AS LinkRole,
        COUNT(DISTINCT pl.Id) AS TotalLinkCount,
        MAX(CASE WHEN pl.LinkTypeId = 3 THEN 'Duplicate' ELSE NULL END) AS IsDuplicateStatus, -- Aggregated status for duplicates
        MAX(ph_link.Comment) AS ClosedReasonComment,
        MAX(crt.Name) AS ClosedReasonName
    FROM Posts p_all
    FULL OUTER JOIN PostLinks pl ON p_all.Id = pl.PostId OR p_all.Id = pl.RelatedPostId
    LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    LEFT JOIN PostHistory ph_link ON p_all.Id = ph_link.PostId AND ph_link.PostHistoryTypeId = 10 -- Looking for closed history
    LEFT JOIN CloseReasonTypes crt ON ph_link.Comment ~ '^[0-9]+$' AND ph_link.Comment::smallint = crt.Id -- Safe cast if comment is numeric
    GROUP BY COALESCE(p_all.Id, pl.PostId, pl.RelatedPostId)
),
PostTagSentiment AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.Tags,
        CASE
            WHEN p.Title ILIKE '%performance%' OR p.Body ILIKE '%optimization%' OR p.Tags ILIKE '%<performance>%' THEN 'PerformanceRelated'
            WHEN p.Title ILIKE '%bug%' OR p.Body ILIKE '%error%' OR p.Tags ILIKE '%<bug>%' THEN 'BugRelated'
            WHEN p.Title ILIKE '%security%' OR p.Body ILIKE '%vulnerability%' OR p.Tags ILIKE '%<security>%' THEN 'SecurityRelated'
            WHEN p.Title ILIKE '%database%' OR p.Tags ILIKE '%<sql>%' OR p.Tags ILIKE '%<database>%' THEN 'DatabaseRelated'
            ELSE 'GeneralTopic'
        END AS PostCategoryByKeywords
    FROM Posts p
    WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1 -- Only questions for keyword sentiment
),
HotPostCandidates AS (
    -- Using UNION ALL to combine "hot" questions and answers based on specific criteria
    -- Demonstrates a set operator within a CTE
    SELECT
        pp.PostId,
        pp.OwnerUserId,
        pp.PostScore,
        pp.ViewCount,
        'HotQuestion' AS CandidateType,
        pp.PostCreationDate
    FROM PostPerformance pp
    WHERE pp.PostTypeId = 1 AND pp.PostScore > 150 AND pp.ViewCount > 25000 AND pp.CommentCount >= 5
    UNION ALL
    SELECT
        pp.PostId,
        pp.OwnerUserId,
        pp.PostScore,
        pp.ViewCount,
        'HotAnswer' AS CandidateType,
        pp.PostCreationDate
    FROM PostPerformance pp
    WHERE pp.PostTypeId = 2 AND pp.PostScore > 75 AND pp.RollingAvgUserPostScore > 40 AND pp.ParentPostId IN (SELECT Id FROM Posts WHERE PostTypeId = 1 AND Score > 100)
)
SELECT
    ue.UserId,
    ue.DisplayName,
    ue.Reputation,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.GoldBadges,
    ue.UserAgeDays,
    (ue.Reputation / NULLIF(ue.UserAgeDays, 0)) AS AvgReputationPerDay, -- Calculated here to avoid re-calculating in HAVING
    pp.PostId,
    pp.PostTypeName,
    pp.PostCreationDate,
    pp.PostScore,
    pp.ViewCount,
    pp.AnswerCount,
    pp.CommentCount,
    pp.TagCount,
    pp.PostEditCount,
    pp.UpVoteCount,
    pp.DownVoteCount,
    pp.RankByScoreAndViews,
    pp.PreviousPostScore,
    pp.RollingAvgUserPostScore,
    CASE
        WHEN pp.IsAcceptedAnswerVoteIndicator > 0 THEN 'AcceptedByOriginator'
        WHEN pp.AcceptedAnswerId != -1 THEN 'HasAcceptedAnswer'
        ELSE 'NoAcceptedAnswer'
    END AS AnswerStatus,
    COALESCE(pls.LinkTypeNames, 'NoLink') AS LinkTypeSummary,
    COALESCE(pls.LinkRole, 'NoLinkInfo') AS PostLinkRole,
    COALESCE(pls.ClosedReasonName, 'NotClosed') AS RelatedCloseReason,
    COALESCE(pls.IsDuplicateStatus, 'NoDuplicate') AS IsDuplicateOfPost,
    COALESCE(pts.PostCategoryByKeywords, 'UnknownTopic') AS PostCategoryByKeywords,
    COALESCE(hpc.CandidateType, 'NormalPost') AS HotPostClassification,

    -- Correlated subquery: Count specific badges for the owner of the current post, only if the badge was earned BEFORE the post.
    (
        SELECT COUNT(b_corr.Id)
        FROM Badges b_corr
        WHERE b_corr.UserId = ue.UserId
        AND b_corr.Class = 1
        AND b_corr.Date < pp.PostCreationDate
    ) AS OwnerGoldBadgesBeforePost,

    -- Complex calculations with NULLIF for division by zero
    (pp.UpVoteCount - pp.DownVoteCount) AS NetVotes,
    NULLIF(pp.ViewCount, 0)::numeric / NULLIF(pp.PostScore, 0) AS ViewScoreRatio,
    NULLIF(pp.BodyLength, 0)::numeric / NULLIF(pp.CommentCount, 0) AS BodyCommentRatio,
    NULLIF(ue.TotalPosts, 0)::numeric / NULLIF(ue.TotalCommentsMade, 0) AS PostsPerCommentRatio,

    -- String expressions
    LOWER(SUBSTRING(pp.Title, 1, 30)) AS PartialTitleLower,
    REPLACE(TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM pp.Tags)), '><', ', ') AS TagsCommaSeparatedClean, -- Clean tags
    (SELECT SUBSTRING(c_latest.Text, 1, 50) FROM Comments c_latest WHERE c_latest.PostId = pp.PostId ORDER BY c_latest.CreationDate DESC LIMIT 1) AS LatestCommentExcerpt,

    -- More complex CASE statement for user influence tier
    CASE
        WHEN ue.Reputation >= 50000 AND ue.GoldBadges >= 10 AND ue.TotalQuestions >= 100 THEN 'LegendaryArchitect'
        WHEN ue.Reputation >= 10000 AND ue.GoldBadges >= 3 AND ue.TotalAnswers >= 200 THEN 'CommunityGuru'
        WHEN ue.Reputation >= 2500 AND ue.TotalPosts >= 100 THEN 'EstablishedExpert'
        WHEN ue.Reputation >= 500 AND ue.TotalCommentsMade >= 50 THEN 'ActiveContributor'
        ELSE 'EmergingTalent'
    END AS UserInfluenceTier,

    -- NULL logic checks and boolean flags
    ue.LatestBadgeDate IS NOT NULL AS HasAnyBadgeEver,
    pp.AcceptedAnswerId = pp.ParentPostId AS IsSelfAcceptedAnswerToOwnQuestion, -- Would be false for questions
    (SELECT COUNT(v_fav.Id) FROM Votes v_fav WHERE v_fav.PostId = pp.PostId AND v_fav.VoteTypeId = 5 AND v_fav.UserId = ue.UserId) AS UserFavoritedThisPost,
    (pp.PostScore < pp.PreviousPostScore) AS ScoreRegressionFromPreviousPost,
    (pp.PostEditCount > 0 AND ue.TotalEditsContributed > 10) AS PostEditedByExperiencedEditor
FROM UserEngagement ue
JOIN PostPerformance pp ON ue.UserId = pp.OwnerUserId
LEFT JOIN PostLinkSummary pls ON pp.PostId = pls.PostId
LEFT JOIN PostTagSentiment pts ON pp.PostId = pts.PostId
LEFT JOIN HotPostCandidates hpc ON pp.PostId = hpc.PostId
WHERE
    ue.Reputation > 750 -- Filter for reasonably active/reputed users
    AND ue.UserAgeDays > 180 -- User active for at least 6 months
    AND pp.PostScore > 10 -- Only posts with decent scores
    AND pp.PostTypeName IN ('Question', 'Answer') -- Focus on main content types
    AND pp.PostCreationDate BETWEEN NOW() - INTERVAL '4 years' AND NOW() - INTERVAL '6 months' -- Posts within a specific, past timeframe
    -- Complex WHERE clause with multiple AND/OR conditions, EXISTS/NOT EXISTS, and subquery logic
    AND (
        (pp.PostTypeId = 1 AND pp.AnswerCount >= 2 AND pp.ViewCount > 5000 AND pp.TagCount > 1)
        OR
        (pp.PostTypeId = 2 AND pp.PostScore > ue.AvgAnswerScore * 1.8 AND pp.RollingAvgUserPostScore > 15)
        OR
        EXISTS (SELECT 1 FROM Badges b_sub WHERE b_sub.UserId = ue.UserId AND b_sub.Name ILIKE '%great answer%' AND b_sub.Date > pp.PostCreationDate - INTERVAL '1 year')
    )
    AND NOT EXISTS (
        SELECT 1 FROM PostHistory ph_closed_deleted
        WHERE ph_closed_deleted.PostId = pp.PostId AND ph_closed_deleted.PostHistoryTypeId IN (10, 12) -- Exclude closed or deleted posts
    )
    -- Predicate involving string search on the title
    AND (pp.Title IS NOT NULL AND (pp.Title ILIKE '%sql%' OR pp.Title ILIKE '%database%'))
HAVING
    NetVotes > 5 -- Ensure positive net votes
    AND (ue.TotalQuestions + ue.TotalAnswers) > 5 -- User has contributed more than a few posts
ORDER BY
    ue.Reputation DESC, pp.PostScore DESC, pp.PostCreationDate DESC, HotPostClassification DESC
LIMIT 5000;
