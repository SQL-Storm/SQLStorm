WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        COALESCE(u.Views, 0) AS TotalProfileViews,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswersProvided,
        COUNT(DISTINCT p.Id) AS TotalPostsCreated,
        AVG(CASE WHEN p.Score IS NOT NULL AND p.Score > 0 THEN p.Score END) AS AvgPositivePostScore,
        SUM(COALESCE(p.FavoriteCount, 0)) AS TotalFavoriteCounts,
        MAX(p.LastActivityDate) AS LastPostActivity
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
    HAVING
        COUNT(p.Id) >= 10
        AND u.Reputation > 500
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        p.Title,
        p.Tags,
        p.ClosedDate,
        MAX(ph_edit.CreationDate) FILTER (WHERE ph_edit.PostHistoryTypeId IN (4, 5, 6)) AS LastContentEditDate,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
        EXISTS (
            SELECT 1
            FROM PostHistory ph_reopen
            WHERE ph_reopen.PostId = p.Id
              AND ph_reopen.PostHistoryTypeId = 11
              AND ph_reopen.CreationDate > p.CreationDate
        ) AS WasReopened,
        EXISTS (
            SELECT 1
            FROM PostHistory ph_close
            WHERE ph_close.PostId = p.Id
              AND ph_close.PostHistoryTypeId = 10
              AND ph_close.Comment IN ('1', '101')
        ) AS WasDuplicateClosed,
        EXTRACT(EPOCH FROM (p.LastActivityDate - p.CreationDate)) / 3600 AS HoursSinceCreationActive,
        (p.CommunityOwnedDate IS NOT NULL) AS IsCommunityOwned,
        p.AcceptedAnswerId,
        p.Body
    FROM
        Posts p
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph_edit ON p.Id = ph_edit.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.Title, p.Tags, p.ClosedDate, p.LastActivityDate, p.CommunityOwnedDate, p.AcceptedAnswerId, p.Body
    HAVING
        COALESCE(p.ViewCount, 0) > 100
),
TagPerformance AS (
    SELECT
        TRIM(REPLACE(REPLACE(tag, '&lt;', '<'), '&gt;', '>')) AS TagName,
        p.Id AS PostId,
        p.Score AS PostScore,
        p.ViewCount,
        p.CreationDate
    FROM
        Posts p,
        LATERAL (
            SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS tag
        ) t
    WHERE
        p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2 AND p.PostTypeId = 1
),
AggregatedTagStats AS (
    SELECT
        tp.TagName,
        COUNT(tp.PostId) AS TaggedPostsCount,
        AVG(CASE WHEN tp.PostScore IS NOT NULL THEN tp.PostScore END) AS AvgTagPostScore,
        SUM(COALESCE(tp.ViewCount, 0)) AS TotalTagViewCount,
        MAX(tp.CreationDate) AS LatestPostInTag,
        DENSE_RANK() OVER (ORDER BY SUM(COALESCE(tp.ViewCount, 0)) DESC, COUNT(tp.PostId) DESC) AS TagEngagementRank
    FROM
        TagPerformance tp
    GROUP BY
        tp.TagName
    HAVING
        COUNT(tp.PostId) > 50
        AND SUM(COALESCE(tp.ViewCount, 0)) > 1000
),
BadgeEliteUsers AS (
    SELECT
        b.UserId,
        COUNT(b.Id) AS TotalNamedBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        MAX(b.Date) AS LastBadgeAwardDate
    FROM
        Badges b
    WHERE
        COALESCE(b.TagBased, FALSE) = FALSE
    GROUP BY
        b.UserId
    HAVING
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) >= 2 OR SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) >= 10
),
ComplicatedCommentAnalysis AS (
    SELECT
        c.PostId,
        COUNT(DISTINCT c.UserId) AS DistinctCommenters,
        AVG(LENGTH(c.Text)) AS AvgCommentLength,
        SUM(CASE WHEN c.Text ILIKE '%bug%' OR c.Text ILIKE '%error%' THEN 1 ELSE 0 END) AS ProblemKeywordsInComments,
        (CAST(SUM(COALESCE(c.Score,0)) AS NUMERIC) / NULLIF(COUNT(c.Id), 0)) AS AvgCommentScore,
        MAX(c.CreationDate) AS LastCommentDate
    FROM
        Comments c
    WHERE
        c.CreationDate >= TIMESTAMP '2020-01-01'
    GROUP BY
        c.PostId
),
PostLinkHistory AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN pl.RelatedPostId END) AS LinkedPostsCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicateLinksCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM
        PostLinks pl
    GROUP BY
        pl.PostId
)
SELECT
    ue.DisplayName AS UserName,
    ue.Reputation,
    pde.PostId,
    pde.Title AS PostTitle,
    pde.PostCreationDate,
    pde.PostScore,
    pde.ViewCount,
    pde.AnswerCount,
    pde.CommentCount,
    pde.UpVotesReceived,
    pde.DownVotesReceived,
    pde.Tags,
    pde.WasReopened,
    pde.WasDuplicateClosed,
    ats.TagName AS PrimaryTagName,
    ats.AvgTagPostScore,
    ats.TotalTagViewCount,
    COALESCE(beu.GoldBadges, 0) AS GoldBadges,
    COALESCE(beu.SilverBadges, 0) AS SilverBadges,
    cca.DistinctCommenters,
    cca.ProblemKeywordsInComments,
    plh.LinkedPostsCount,
    plh.DuplicateLinksCount,
    (
        CAST(ue.Reputation AS NUMERIC) * COALESCE(pde.PostScore, 0)
        * (COALESCE(pde.UpVotesReceived, 0) + 1) / GREATEST(COALESCE(pde.DownVotesReceived, 0) + 1, 1)
        * (1 + COALESCE(cca.DistinctCommenters, 0) * 0.1)
        * (CASE WHEN pde.WasReopened THEN 1.5 ELSE 1 END)
        * (CASE WHEN pde.IsCommunityOwned THEN 0.8 ELSE 1 END)
    ) AS InfluenceMetric,
    pde.HoursSinceCreationActive,
    CASE
        WHEN pde.PostTypeId = 1 AND pde.WasReopened AND pde.AnswerCount = 0 THEN 'ChallengingQuestion_NoAcceptedAnswer'
        WHEN pde.PostTypeId = 1 AND pde.WasReopened AND pde.AcceptedAnswerId IS NOT NULL THEN 'ReevaluatedQuestion_AcceptedAnswer'
        WHEN pde.PostTypeId = 2 AND pde.PostScore > 100 THEN 'HighlyValuedAnswer'
        WHEN pde.ClosedDate IS NOT NULL AND pde.WasDuplicateClosed THEN 'ClosedAsDuplicate'
        WHEN pde.ClosedDate IS NOT NULL AND pde.WasReopened = FALSE THEN 'StagnantClosedPost'
        WHEN pde.ViewCount > 5000 AND pde.CommentCount > 20 THEN 'HighActivityDiscussion'
        ELSE 'GeneralActivePost'
    END AS PostStatusCategory,
    RANK() OVER (PARTITION BY ats.TagName ORDER BY (ue.Reputation * COALESCE(pde.PostScore,0) * (COALESCE(pde.UpVotesReceived,0) + 1) / GREATEST(COALESCE(pde.DownVotesReceived,0) + 1,1)) DESC, pde.ViewCount DESC) AS RankWithinPrimaryTag,
    ats.TagEngagementRank
FROM
    UserEngagement ue
INNER JOIN
    PostDetailsExtended pde ON ue.UserId = pde.OwnerUserId
LEFT JOIN LATERAL (
    SELECT tp.TagName, ats_inner.AvgTagPostScore, ats_inner.TotalTagViewCount, ats_inner.TagEngagementRank
    FROM TagPerformance tp
    INNER JOIN AggregatedTagStats ats_inner ON tp.TagName = ats_inner.TagName
    WHERE tp.PostId = pde.PostId
    ORDER BY ats_inner.TagEngagementRank ASC
    LIMIT 1
) ats ON TRUE
FULL OUTER JOIN
    BadgeEliteUsers beu ON ue.UserId = beu.UserId
LEFT JOIN
    ComplicatedCommentAnalysis cca ON pde.PostId = cca.PostId
LEFT JOIN
    PostLinkHistory plh ON pde.PostId = plh.PostId
WHERE
    pde.PostCreationDate >= DATE '2021-01-01'
    AND pde.PostTypeId IN (1, 2)
    AND pde.HoursSinceCreationActive > 72
    AND (
        pde.Title ILIKE '%SQL%' OR pde.Title ILIKE '%database%' OR pde.Body ILIKE '%performance tuning%' OR pde.Tags ILIKE '%<sql-server>%'
    )
    AND (
        pde.WasReopened = TRUE
        OR pde.PostScore >= 25
        OR COALESCE(cca.ProblemKeywordsInComments, 0) >= 1
        OR COALESCE(plh.DuplicateLinksCount, 0) >= 1
        OR COALESCE(beu.GoldBadges, 0) >= 1
    )
    AND ue.DisplayName IS NOT NULL
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_modlock
        WHERE ph_modlock.PostId = pde.PostId
          AND ph_modlock.PostHistoryTypeId IN (14, 15)
    )
ORDER BY
    InfluenceMetric DESC NULLS LAST, pde.ViewCount DESC, COALESCE(beu.GoldBadges,0) DESC NULLS LAST, ats.TagEngagementRank ASC NULLS LAST
LIMIT 500;