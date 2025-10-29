-- {"query": "1916.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3791} 

WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.WebsiteUrl,
        u.Location,
        u.AboutMe,
        u.Views AS UserProfileViews,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS QuestionCount,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS AnswerCount,
        COALESCE(COUNT(DISTINCT c.Id), 0) AS CommentCount,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END), 0) AS UpvotesGiven,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END), 0) AS DownvotesGiven,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        ARRAY_AGG(DISTINCT b.Name) FILTER (WHERE b.Name IS NOT NULL) AS UserBadgeNames
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Votes v ON u.Id = v.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.WebsiteUrl,
        u.Location, u.AboutMe, u.Views
),
PostDetailedMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.Body,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.LastActivityDate,
        p.LastEditDate,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.CommunityOwnedDate,
        LENGTH(p.Body) AS BodyLength,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        COALESCE(p.CommentCount, 0) AS DirectCommentCount,
        NULLIF(
            (SELECT COUNT(DISTINCT ph.UserId)
             FROM PostHistory ph
             WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 8, 9)
            ), 0) AS DistinctEditorCount,
        (SELECT AVG(s.Score)
         FROM Posts s
         WHERE s.ParentId = p.Id
           AND s.PostTypeId = 2
           AND s.Id != p.AcceptedAnswerId
        ) AS AvgOtherAnswerScoreForQuestion,
        STRING_TO_ARRAY(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><') AS ParsedTagsArray,
        SUM(CASE WHEN pv.VoteTypeId = 8 THEN 1 ELSE 0 END) AS BountyStartEventCount,
        MAX(CASE WHEN pv.VoteTypeId = 8 THEN pv.BountyAmount ELSE 0 END) AS MaxBountyInitiatedAmount,
        COALESCE(COUNT(DISTINCT pl_linked.RelatedPostId) FILTER (WHERE pl_linked.LinkTypeId = 1), 0) AS LinkedPostsCount,
        COALESCE(COUNT(DISTINCT pl_duplicate.RelatedPostId) FILTER (WHERE pl_duplicate.LinkTypeId = 3), 0) AS DuplicateLinksCount,
        LEAD(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextPostScoreByOwner,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScoreByOwner,
        DENSE_RANK() OVER (ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC) AS GlobalPostRank
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Votes pv ON p.Id = pv.PostId AND pv.VoteTypeId IN (8, 9)
    LEFT JOIN PostLinks pl_linked ON p.Id = pl_linked.PostId AND pl_linked.LinkTypeId = 1
    LEFT JOIN PostLinks pl_duplicate ON p.Id = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3
    GROUP BY
        p.Id, p.PostTypeId, pt.Name, p.CreationDate, p.Score, p.ViewCount, p.Body, p.OwnerUserId,
        p.Title, p.Tags, p.LastActivityDate, p.LastEditDate, p.AcceptedAnswerId, p.ClosedDate,
        p.CommunityOwnedDate, p.FavoriteCount, p.CommentCount
),
TopTagsByScore AS (
    SELECT
        t.TagName,
        AVG(pd.PostScore) AS AvgTagScore,
        COUNT(DISTINCT pd.PostId) AS PostCountForTag,
        DENSE_RANK() OVER (ORDER BY AVG(pd.PostScore) DESC) AS TagScoreRank
    FROM PostDetailedMetrics pd
    CROSS JOIN UNNEST(pd.ParsedTagsArray) AS t(TagName)
    WHERE pd.PostTypeId IN (1, 2)
    GROUP BY t.TagName
    HAVING COUNT(DISTINCT pd.PostId) > 100
),
RecentModeratorActions AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LatestModeratorActionDate,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 14, 19, 35) THEN ph.Id ELSE NULL END) AS ModeratorCloseLockMigrateCount,
        ARRAY_AGG(DISTINCT crt.Name) FILTER (WHERE crt.Name IS NOT NULL) AS CloseReasonNames
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND CAST(ph.Comment AS SMALLINT) = crt.Id
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20, 35, 36)
    GROUP BY ph.PostId
    HAVING MAX(ph.CreationDate) > NOW() - INTERVAL '2 years'
),
FlaggedContentCandidates AS (
    -- Posts that received offensive/spam flags but might still be active
    SELECT
        pdm.PostId,
        pdm.PostCreationDate,
        pdm.PostScore,
        pdm.Title,
        pdm.PostTypeName,
        pdm.OwnerUserId
    FROM PostDetailedMetrics pdm
    JOIN Votes v ON pdm.PostId = v.PostId
    WHERE v.VoteTypeId IN (4, 12)
    GROUP BY pdm.PostId, pdm.PostCreationDate, pdm.PostScore, pdm.Title, pdm.PostTypeName, pdm.OwnerUserId
    HAVING COUNT(v.Id) >= 3 AND pdm.ClosedDate IS NULL
),
HighlyControversialPosts AS (
    -- Posts with significant upvotes AND downvotes from different users
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpvoteCount,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownvoteCount
    FROM Posts p
    JOIN Votes v ON p.Id = v.PostId
    WHERE v.VoteTypeId IN (2, 3) AND p.CreationDate > NOW() - INTERVAL '3 years'
    GROUP BY p.Id, p.OwnerUserId
    HAVING SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) > 50 AND SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) > 10
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    pdm.PostId,
    pdm.PostTypeName,
    pdm.PostScore,
    pdm.ViewCount,
    pdm.BodyLength,
    pdm.Title,
    pdm.PostCreationDate,
    pdm.LastActivityDate,
    pdm.DistinctEditorCount,
    pdm.AvgOtherAnswerScoreForQuestion,
    pdm.BountyStartEventCount,
    pdm.MaxBountyInitiatedAmount,
    pdm.LinkedPostsCount,
    pdm.DuplicateLinksCount,
    pdm.NextPostScoreByOwner,
    pdm.PreviousPostScoreByOwner,
    pdm.GlobalPostRank,
    rm.LatestModeratorActionDate,
    rm.ModeratorCloseLockMigrateCount,
    rm.CloseReasonNames,
    tpt.AvgTagScore AS PrimaryTagAvgScore,
    tpt.PostCountForTag AS PrimaryTagPostCount,
    tpt.TagScoreRank AS PrimaryTagScoreRank,
    COALESCE(NULLIF(uas.WebsiteUrl, ''), 'No Website Provided') AS UserWebsiteStatus,
    CASE
        WHEN uas.Reputation > 50000 AND uas.GoldBadges >= 10 THEN 'Legendary Contributor'
        WHEN uas.Reputation > 10000 AND uas.SilverBadges >= 25 THEN 'Expert Participant'
        WHEN uas.Reputation > 1000 AND uas.BronzeBadges >= 50 THEN 'Active Community Member'
        ELSE 'Casual User'
    END AS UserEngagementLevel,
    SUBSTRING(COALESCE(uas.AboutMe, 'No About Me'), 1, 100) AS AboutMeSnippet,
    LENGTH(COALESCE(uas.Location, '')) AS LocationStringLength,
    AGE(NOW(), pdm.PostCreationDate) AS PostAge,
    EXTRACT(DOW FROM pdm.PostCreationDate) AS DayOfWeekCreated,
    NTILE(4) OVER (ORDER BY pdm.PostScore DESC) AS PostScoreQuartile,
    NULLIF(uas.QuestionCount, 0) * 1.0 / NULLIF(uas.AnswerCount, 0) AS QuestionToAnswerRatio,
    (SELECT COUNT(DISTINCT c.UserId)
     FROM Comments c
     WHERE c.PostId = pdm.PostId
       AND c.CreationDate > pdm.PostCreationDate - INTERVAL '7 days'
       AND c.Score > 0
    ) AS RecentPositiveCommenters,
    (SELECT MAX(LENGTH(body)) FROM Posts WHERE OwnerUserId = uas.UserId AND PostTypeId = 5) AS MaxTagWikiLengthByOwner,
    (SELECT t.TagName FROM TopTagsByScore t WHERE t.TagName = ANY(pdm.ParsedTagsArray) ORDER BY t.TagScoreRank LIMIT 1) AS HighestRankedTag
FROM UserActivitySummary uas
JOIN PostDetailedMetrics pdm ON uas.UserId = pdm.OwnerUserId
LEFT JOIN RecentModeratorActions rm ON pdm.PostId = rm.PostId
LEFT JOIN TopTagsByScore tpt ON tpt.TagName = pdm.ParsedTagsArray[1] -- Arbitrarily take the first tag for primary analysis
WHERE
    uas.Reputation >= 1000
    AND pdm.PostTypeId IN (1, 2)
    AND pdm.PostScore > 50
    AND pdm.ViewCount > 5000
    AND pdm.PostCreationDate BETWEEN '2021-01-01' AND '2024-01-01'
    AND pdm.LastActivityDate > NOW() - INTERVAL '1 year'
    AND (pdm.Title ILIKE '%query%' OR pdm.Body ILIKE '%optimize%')
    AND pdm.ParsedTagsArray IS NOT NULL
    AND NOT (pdm.ParsedTagsArray @> ARRAY['discussion'] OR pdm.ParsedTagsArray @> ARRAY['meta'])
    AND pdm.DistinctEditorCount IS NOT NULL
    AND pdm.AvgOtherAnswerScoreForQuestion IS NOT NULL
    AND pdm.ClosedDate IS NULL
    AND NOT EXISTS (SELECT 1 FROM HighlyControversialPosts hcp WHERE hcp.PostId = pdm.PostId)
UNION ALL
-- Another branch: Focus on underperforming posts (high views, low score) that might need attention
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.QuestionCount,
    uas.AnswerCount,
    pdm.PostId,
    pdm.PostTypeName,
    pdm.PostScore,
    pdm.ViewCount,
    pdm.BodyLength,
    pdm.Title,
    pdm.PostCreationDate,
    pdm.LastActivityDate,
    pdm.DistinctEditorCount,
    pdm.AvgOtherAnswerScoreForQuestion,
    pdm.BountyStartEventCount,
    pdm.MaxBountyInitiatedAmount,
    pdm.LinkedPostsCount,
    pdm.DuplicateLinksCount,
    pdm.NextPostScoreByOwner,
    pdm.PreviousPostScoreByOwner,
    pdm.GlobalPostRank,
    NULL AS LatestModeratorActionDate,
    NULL AS ModeratorCloseLockMigrateCount,
    NULL AS CloseReasonNames,
    NULL AS PrimaryTagAvgScore,
    NULL AS PrimaryTagPostCount,
    NULL AS PrimaryTagScoreRank,
    COALESCE(NULLIF(uas.WebsiteUrl, ''), 'No Website Provided') AS UserWebsiteStatus,
    'Under-Performing Post Focus' AS UserEngagementLevel,
    SUBSTRING(COALESCE(uas.AboutMe, 'No About Me'), 1, 100) AS AboutMeSnippet,
    LENGTH(COALESCE(uas.Location, '')) AS LocationStringLength,
    AGE(NOW(), pdm.PostCreationDate) AS PostAge,
    EXTRACT(DOW FROM pdm.PostCreationDate) AS DayOfWeekCreated,
    NTILE(4) OVER (ORDER BY pdm.PostScore DESC) AS PostScoreQuartile,
    NULLIF(uas.QuestionCount, 0) * 1.0 / NULLIF(uas.AnswerCount, 0) AS QuestionToAnswerRatio,
    (SELECT COUNT(DISTINCT c.UserId)
     FROM Comments c
     WHERE c.PostId = pdm.PostId
       AND c.CreationDate > pdm.PostCreationDate - INTERVAL '7 days'
       AND c.Score > 0
    ) AS RecentPositiveCommenters,
    (SELECT MAX(LENGTH(body)) FROM Posts WHERE OwnerUserId = uas.UserId AND PostTypeId = 5) AS MaxTagWikiLengthByOwner,
    (SELECT t.TagName FROM TopTagsByScore t WHERE t.TagName = ANY(pdm.ParsedTagsArray) ORDER BY t.TagScoreRank LIMIT 1) AS HighestRankedTag
FROM UserActivitySummary uas
JOIN PostDetailedMetrics pdm ON uas.UserId = pdm.OwnerUserId
WHERE
    pdm.PostTypeId IN (1, 2)
    AND pdm.ViewCount > 10000
    AND pdm.PostScore < 10
    AND pdm.PostCreationDate BETWEEN '2022-01-01' AND '2024-01-01'
    AND pdm.ClosedDate IS NULL
    AND NOT EXISTS (SELECT 1 FROM FlaggedContentCandidates fcc WHERE fcc.PostId = pdm.PostId)
ORDER BY
    Reputation DESC,
    PostScoreQuartile ASC,
    PostAge DESC
LIMIT 50000;
