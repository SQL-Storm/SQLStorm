WITH UserEngagementMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Location, 'Unknown') AS UserLocation,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        SUM(CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS AcceptedAnswersGiven,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreGiven,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (
            SELECT sp.Title
            FROM Posts sp
            WHERE sp.OwnerUserId = u.Id
            ORDER BY sp.CreationDate DESC
            LIMIT 1
        ) AS LatestPostTitle,
        RANK() OVER (PARTITION BY EXTRACT(YEAR FROM u.CreationDate) ORDER BY u.Reputation DESC) AS ReputationRankInYear,
        CASE WHEN COUNT(p.Id) = 0 THEN NULL ELSE CAST(SUM(COALESCE(p.Score,0)) AS DECIMAL) / NULLIF(SUM(CASE WHEN p.OwnerUserId = u.Id THEN 1 ELSE 0 END),0) END AS AvgPostScoreByOwner,
        SUM(CASE WHEN v_up.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotesReceived
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v_up ON p.Id = v_up.PostId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views
),
PostContentQuality AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        LENGTH(p.Body) AS BodyLength,
        LENGTH(p.Title) AS TitleLength,
        p.OwnerUserId,
        p.LastEditDate,
        p.ClosedDate,
        TRIM(SUBSTRING(p.Tags FROM 2 FOR (POSITION('><' IN COALESCE(p.Tags,'') || '><') - 2))) AS PrimaryTag,
        (
            p.Body ILIKE '%error%' OR
            p.Body ILIKE '%issue%' OR
            p.Body ILIKE '%problem%' OR
            p.Body ILIKE '%bug%'
        ) AS ContainsProblemKeywords,
        (p.LastEditDate IS NOT NULL AND p.LastEditDate > p.CreationDate) AS HasBeenEdited,
        COUNT(ph_edit.Id) FILTER (WHERE ph_edit.PostHistoryTypeId = 5) AS BodyEditHistoryCount,
        COUNT(ph_close.Id) FILTER (WHERE ph_close.PostHistoryTypeId = 10) AS CloseHistoryCount,
        COALESCE(
            EXTRACT(DAY FROM (p.CreationDate - LAG(p.CreationDate, 1) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate))),
            0
        ) AS DaysSincePreviousPost,
        (SELECT AVG(sa.Score) FROM Posts sa WHERE sa.PostTypeId = 2 AND sa.Id = p.AcceptedAnswerId) AS AvgAcceptedAnswerScore,
        EXISTS (SELECT 1 FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) AS IsDuplicateSource,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered & Accepted'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Open'
        END AS PostStatus
    FROM
        Posts p
    LEFT JOIN PostHistory ph_edit ON p.Id = ph_edit.PostId AND ph_edit.PostHistoryTypeId = 5
    LEFT JOIN PostHistory ph_close ON p.Id = ph_close.PostId AND ph_close.PostHistoryTypeId = 10
    WHERE
        p.PostTypeId IN (1, 2)
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount,
        p.FavoriteCount, p.Body, p.Title, p.OwnerUserId, p.LastEditDate, p.ClosedDate, p.Tags, p.AcceptedAnswerId
),
TagPerformanceOverview AS (
    SELECT
        t.TagName,
        t.Id AS TagId,
        t.Count AS TagUseCount,
        COALESCE(t.WikiPostId, t.ExcerptPostId) AS AssociatedPostId,
        AVG(pcq.PostScore) AS AvgScoreForTaggedPosts,
        COUNT(DISTINCT pcq.OwnerUserId) AS UniqueAuthorsUsingTag,
        MAX(pcq.PostCreationDate) AS LatestUseDate,
        (LENGTH(t.TagName) > 15 OR t.TagName LIKE '%-%') AS IsComplexTagName,
        (
            SELECT AVG(ue.Reputation)
            FROM UserEngagementMetrics ue
            JOIN Posts p ON ue.UserId = p.OwnerUserId
            WHERE p.Tags LIKE ('%' || '<' || t.TagName || '>' || '%')
        ) AS AvgAuthorReputationForTag
    FROM
        Tags t
    LEFT JOIN PostContentQuality pcq ON pcq.PrimaryTag = t.TagName
    GROUP BY
        t.TagName, t.Id, t.Count, t.WikiPostId, t.ExcerptPostId
    HAVING
        t.Count > 500
)
SELECT
    uem.UserId,
    uem.DisplayName,
    uem.Reputation,
    uem.UserLocation,
    pcq.PostId,
    pcq.PostCreationDate,
    pcq.PostScore,
    pcq.ViewCount,
    pcq.BodyLength,
    pcq.TitleLength,
    pcq.PrimaryTag,
    tpo.AvgScoreForTaggedPosts,
    tpo.TagUseCount,
    uem.TotalQuestions,
    uem.TotalAnswers,
    uem.GoldBadges,
    uem.SilverBadges,
    pcq.HasBeenEdited,
    pcq.ContainsProblemKeywords,
    pcq.PostStatus,
    CAST(pcq.PostScore AS DECIMAL) / NULLIF(pcq.ViewCount, 0) AS ScorePerViewRatio,
    EXTRACT(DAY FROM (pcq.PostCreationDate - uem.UserCreationDate)) AS DaysUserActiveAtPostCreation,
    NTILE(4) OVER (ORDER BY CAST(pcq.PostScore AS DECIMAL) / NULLIF(pcq.ViewCount, 0) DESC) AS ScoreViewRatioQuartile,
    (
        (pcq.PostScore * 0.5) + (pcq.ViewCount * 0.1) + (pcq.CommentCount * 0.2) + (pcq.FavoriteCount * 0.3)
        + CASE WHEN pcq.HasBeenEdited THEN 5 ELSE 0 END
        + CASE WHEN pcq.ContainsProblemKeywords THEN -3 ELSE 0 END
    ) AS PostEngagementMetric,
    pl.RelatedPostId,
    lt.Name AS LinkTypeName,
    COALESCE(uem.LatestPostTitle, 'No Recent Post') AS UserLatestPostDisplay,
    EXISTS (
        SELECT 1 FROM Votes v_mod
        WHERE v_mod.PostId = pcq.PostId AND v_mod.VoteTypeId = 15
    ) AS HasModeratorReviewVote,
    CASE
        WHEN pcq.DaysSincePreviousPost IS NULL THEN 'First Post'
        WHEN pcq.DaysSincePreviousPost BETWEEN 1 AND 7 THEN 'Frequent Poster'
        WHEN pcq.DaysSincePreviousPost > 30 THEN 'Sporadic Poster'
        ELSE 'Regular Poster'
    END AS PostingFrequencyCategory
FROM
    UserEngagementMetrics uem
INNER JOIN PostContentQuality pcq ON uem.UserId = pcq.OwnerUserId
LEFT JOIN TagPerformanceOverview tpo ON pcq.PrimaryTag = tpo.TagName
LEFT JOIN PostLinks pl ON pcq.PostId = pl.PostId AND pl.LinkTypeId IN (1, 3)
LEFT JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
WHERE
    uem.ReputationRankInYear <= 50
    AND uem.TotalPosts >= 10
    AND pcq.PostCreationDate >= DATE '2023-01-01'
    AND pcq.PostScore > 10
    AND pcq.BodyLength > 300
    AND pcq.HasBeenEdited IS TRUE
    AND (tpo.IsComplexTagName IS NULL OR tpo.IsComplexTagName IS FALSE)
    AND (tpo.AvgAuthorReputationForTag IS NULL OR tpo.AvgAuthorReputationForTag > 1000)
    AND (
        (pcq.PostTypeId = 1 AND pcq.AnswerCount >= 1 AND pcq.AvgAcceptedAnswerScore IS NOT NULL)
        OR (pcq.PostTypeId = 2 AND pcq.ContainsProblemKeywords IS FALSE AND pcq.CloseHistoryCount = 0)
    )
    AND uem.GoldBadges >= 1
ORDER BY
    uem.Reputation DESC,
    PostEngagementMetric DESC,
    pcq.PostCreationDate DESC
LIMIT 1000;