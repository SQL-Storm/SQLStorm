WITH UserAggregates AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) AS TotalQuestions,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) AS TotalAnswers,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScore,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 101) THEN 1 ELSE 0 END) AS TotalPostsClosedAsDuplicate,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.ViewCount ELSE NULL END) AS AvgQuestionViews,
        COUNT(DISTINCT c.Id) AS TotalCommentsWritten,
        (SELECT COUNT(Id) FROM Badges WHERE UserId = u.Id AND Class = 1) AS GoldBadgesCount,
        (SELECT COUNT(Id) FROM Badges WHERE UserId = u.Id AND Class = 2) AS SilverBadgesCount,
        (SELECT COUNT(Id) FROM Badges WHERE UserId = u.Id AND Class = 3) AS BronzeBadgesCount
    FROM
        Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 101)
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
QualifiedUsers AS (
    SELECT UserId FROM UserAggregates WHERE GoldBadgesCount > 0
    UNION
    SELECT ua.UserId
    FROM UserAggregates ua
    JOIN Posts p ON ua.UserId = p.OwnerUserId
    WHERE ua.Reputation > 5000 AND p.PostTypeId = 2 AND p.Score > 50
    GROUP BY ua.UserId
    HAVING COUNT(p.Id) >= 10
    EXCEPT
    SELECT UserId FROM UserAggregates WHERE LOWER(DisplayName) LIKE '%bot%' OR LOWER(DisplayName) LIKE '%auto%' OR LOWER(DisplayName) LIKE '%script%'
),
PostDetailsExtended AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.Tags,
        (SELECT COUNT(Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6)) AS EditCount,
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 9) AS TotalBountyReceived,
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) AS LinkedPostsCount,
        (SELECT COUNT(pl.RelatedPostId) FROM PostLinks pl WHERE pl.RelatedPostId = p.Id AND pl.LinkTypeId = 1) AS BackLinkedPostsCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC) AS RnkInUserPostTypeScore,
        LAG(p.LastEditDate, 1, p.CreationDate) OVER (PARTITION BY p.Id ORDER BY p.LastEditDate) AS PreviousEditDate,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerPostId
    FROM
        Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
TagAnalysis AS (
    SELECT
        TRIM(UNNEST(string_to_array(SUBSTRING(pde.Tags FROM 2 FOR LENGTH(pde.Tags) - 2), '><'))) AS TagName,
        pde.PostId
    FROM
        PostDetailsExtended pde
    WHERE pde.Tags IS NOT NULL AND pde.Tags <> ''
),
PopularTags AS (
    SELECT
        ta.TagName,
        COUNT(DISTINCT ta.PostId) AS TaggedPostsCount,
        SUM(pde.Score) AS TotalTagScore,
        AVG(pde.Score) AS AvgTagScore,
        RANK() OVER (ORDER BY COUNT(DISTINCT ta.PostId) DESC, SUM(pde.Score) DESC) AS TagPopularityRank
    FROM
        TagAnalysis ta
    JOIN PostDetailsExtended pde ON ta.PostId = pde.PostId
    GROUP BY
        ta.TagName
    HAVING
        COUNT(DISTINCT ta.PostId) > 100
),
PostHistoryTimeline AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS HistoryDate,
        ph.PostHistoryTypeId,
        pht.Name AS HistoryTypeName,
        ph.Comment,
        ph.UserId AS HistoryUserId,
        LAG(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PrevHistoryDate,
        LEAD(ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryDate
    FROM
        PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
),
PostScoresForRolling AS (
    SELECT
        pde.PostId,
        pde.PostTypeId,
        pde.PostCreationDate,
        pde.Score
    FROM PostDetailsExtended pde
    WHERE pde.PostCreationDate IS NOT NULL
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalPostScore,
    ua.GoldBadgesCount,
    ua.SilverBadgesCount,
    ua.BronzeBadgesCount,
    ua.TotalPostsClosedAsDuplicate,
    ua.AvgQuestionViews,
    ua.TotalCommentsWritten,
    pde.PostId,
    pde.PostTypeName,
    pde.Title,
    pde.Score AS PostScore,
    pde.ViewCount AS PostViewCount,
    pde.PostCreationDate,
    pde.LastActivityDate,
    pde.AnswerCount,
    pde.CommentCount AS PostCommentCount,
    pde.FavoriteCount AS PostFavoriteCount,
    pde.ClosedDate,
    pde.EditCount,
    pde.TotalBountyReceived,
    pde.LinkedPostsCount,
    pde.BackLinkedPostsCount,
    pde.RnkInUserPostTypeScore,
    EXTRACT(DAY FROM (pde.LastActivityDate - pde.PostCreationDate)) AS DaysSinceCreation,
    EXTRACT(HOUR FROM (pde.LastActivityDate - pde.PreviousEditDate)) AS HoursSinceLastEditBeforeActivity,
    COALESCE(
        (SELECT pt.AvgTagScore
         FROM PopularTags pt
         WHERE pt.TagName = (
             SELECT TRIM(UNNEST(string_to_array(SUBSTRING(pde.Tags FROM 2 FOR LENGTH(pde.Tags) - 2), '><')))
             FROM (SELECT pde.Tags) AS sub_tags
             LIMIT 1
         )
        ), 0.0
    ) AS PrimaryTagAvgScore,
    CASE
        WHEN pde.PostTypeId = 1 AND pde.AcceptedAnswerPostId <> -1 THEN 'Accepted'
        WHEN pde.PostTypeId = 1 AND pde.AcceptedAnswerPostId = -1 AND pde.AnswerCount > 0 THEN 'Unaccepted_With_Answers'
        WHEN pde.PostTypeId = 1 AND pde.AcceptedAnswerPostId = -1 AND pde.AnswerCount = 0 THEN 'No_Answers'
        WHEN pde.PostTypeId = 2 AND pde.Score > 0 THEN 'Upvoted_Answer'
        ELSE 'Other'
    END AS PostStatusCategory,
    ph_latest.HistoryTypeName AS LatestPostHistoryType,
    ph_latest.HistoryDate AS LatestPostHistoryDate,
    ph_latest.Comment AS LatestHistoryComment,
    ph_closure.HistoryDate AS ClosureDate,
    cr.Name AS CloseReason,
    -- Rolling average over past 30 days implemented via a correlated subquery to be dialect-agnostic
    (
      SELECT AVG(ps.Score)
      FROM PostScoresForRolling ps
      WHERE ps.PostTypeId = pde.PostTypeId
        AND ps.PostCreationDate BETWEEN pde.PostCreationDate - INTERVAL '30 days' AND pde.PostCreationDate
    ) AS RollingAvgScore_30Days_PostType,
    NTILE(5) OVER (ORDER BY ua.Reputation DESC, ua.TotalPosts DESC, ua.TotalPostScore DESC) AS UserEngagementQuintile,
    CASE WHEN pde.PostId IN (SELECT ph2.PostId FROM PostHistory ph2 WHERE ph2.PostHistoryTypeId = 16) THEN TRUE ELSE FALSE END AS IsCommunityOwned,
    CASE WHEN pde.PostId NOT IN (SELECT ph3.PostId FROM PostHistory ph3 WHERE ph3.PostHistoryTypeId IN (12, 10, 101)) THEN TRUE ELSE FALSE END AS IsActiveAndNotClosedOrDeleted
FROM
    UserAggregates ua
INNER JOIN QualifiedUsers qu ON ua.UserId = qu.UserId
INNER JOIN PostDetailsExtended pde ON ua.UserId = pde.OwnerUserId
LEFT JOIN PostHistoryTimeline ph_latest ON pde.PostId = ph_latest.PostId AND ph_latest.HistoryDate = (
    SELECT MAX(ph_sub.HistoryDate) FROM PostHistoryTimeline ph_sub WHERE ph_sub.PostId = pde.PostId
)
LEFT JOIN PostHistoryTimeline ph_closure ON pde.PostId = ph_closure.PostId AND ph_closure.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
LEFT JOIN CloseReasonTypes cr ON ph_closure.Comment IS NOT NULL AND cr.Id = CAST(ph_closure.Comment AS SMALLINT)
WHERE
    pde.PostTypeId IN (1, 2)
    AND pde.PostCreationDate >= TIMESTAMP '2020-01-01'
    AND EXISTS (
        SELECT 1
        FROM Posts ans
        WHERE ans.OwnerUserId = ua.UserId
          AND ans.PostTypeId = 2
          AND ans.Score > 50
    )
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_del
        WHERE ph_del.UserId = ua.UserId
          AND ph_del.PostHistoryTypeId = 12
        GROUP BY ph_del.UserId
        HAVING COUNT(ph_del.Id) > 5
    )
    AND (
        pde.LastActivityDate > pde.PostCreationDate + INTERVAL '1 day'
        OR pde.CommentCount > 0
        OR pde.FavoriteCount > 0
    )
ORDER BY
    ua.Reputation DESC, pde.Score DESC, pde.PostCreationDate DESC
LIMIT 10000;