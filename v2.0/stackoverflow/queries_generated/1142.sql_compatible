WITH UserActivitySummary AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.Views AS UserViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        COALESCE(CAST(u.UpVotes AS NUMERIC) / NULLIF(u.UpVotes + u.DownVotes, 0), 0.0) AS UpvoteRatio,
        DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - u.CreationDate) AS AccountAgeDays
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.Reputation >= 100
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate,
        u.Views, u.UpVotes, u.DownVotes
),
PostEngagementMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS PostViewCount,
        COALESCE(p.AnswerCount, 0) AS PostAnswerCount,
        COALESCE(p.CommentCount, 0) AS PostCommentCount,
        COALESCE(p.FavoriteCount, 0) AS PostFavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        p.Title,
        p.Tags,
        (
            SELECT COUNT(DISTINCT ph.Id)
            FROM PostHistory ph
            WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 24)
        ) AS EditCount,
        (
            SELECT MAX(c.Score)
            FROM Comments c
            WHERE c.PostId = p.Id
        ) AS MaxCommentScore,
        CASE
            WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS HasAcceptedAnswer,
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2
            THEN (
                SELECT COUNT(*) FROM UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS t(tag)
            )
            ELSE 0
        END AS TagCount
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.CreationDate >= DATE '2020-01-01'
      AND p.OwnerUserId IS NOT NULL
      AND p.PostTypeId IN (1, 2, 4)
),
PostLinkSummary AS (
    SELECT
        pl.PostId,
        COUNT(CASE WHEN lt.Id = 1 THEN 1 ELSE NULL END) AS LinkedPostsCount,
        COUNT(CASE WHEN lt.Id = 3 THEN 1 ELSE NULL END) AS DuplicatePostsCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
),
QuestionClosureDetails AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastClosedDate,
        MIN(ph.CreationDate) AS FirstClosedDate,
        COUNT(ph.Id) AS ClosureEventCount,
        MAX(CASE WHEN ph.Comment IS NOT NULL AND LENGTH(ph.Comment) > 0 THEN ph.Comment ELSE NULL END) AS LastCloseReasonComment,
        COALESCE(
            MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND CAST(crt_old.Id AS text) = ph.Comment THEN crt_old.Name ELSE NULL END),
            MAX(CASE WHEN ph.PostHistoryTypeId IN (101, 102, 103, 104, 105) AND CAST(crt_new.Id AS text) = ph.Comment THEN crt_new.Name ELSE NULL END)
        ) AS LastCloseReasonTypeName
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt_old ON ph.PostHistoryTypeId = 10 AND CAST(crt_old.Id AS text) = ph.Comment
    LEFT JOIN CloseReasonTypes crt_new ON ph.PostHistoryTypeId IN (101, 102, 103, 104, 105) AND CAST(crt_new.Id AS text) = ph.Comment
    WHERE ph.PostHistoryTypeId IN (10, 101, 102, 103, 104, 105)
    GROUP BY ph.PostId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.UpvoteRatio,
    uas.AccountAgeDays,
    pem.PostId,
    pem.PostTypeName,
    pem.PostCreationDate,
    pem.PostScore,
    pem.PostViewCount,
    pem.PostAnswerCount,
    pem.PostCommentCount,
    pem.PostFavoriteCount,
    pem.HasAcceptedAnswer,
    pem.EditCount,
    pem.TagCount,
    COALESCE(pls.LinkedPostsCount, 0) AS LinkedPostsCount,
    COALESCE(pls.DuplicatePostsCount, 0) AS DuplicatePostsCount,
    COALESCE(qcd.ClosureEventCount, 0) AS ClosureEventCount,
    qcd.LastCloseReasonTypeName,
    DATE_PART('day', pem.ClosedDate - pem.PostCreationDate) AS DaysToClose,
    ROW_NUMBER() OVER (PARTITION BY uas.UserId ORDER BY pem.PostScore DESC, pem.PostViewCount DESC) AS UserPostRankByScore,
    NTILE(5) OVER (ORDER BY uas.Reputation DESC) AS ReputationQuintile,
    AVG(pem.PostScore) OVER (PARTITION BY uas.UserId) AS AvgUserPostScore,
    SUM(pem.PostScore) OVER (ORDER BY pem.PostCreationDate ROWS BETWEEN 30 PRECEDING AND CURRENT ROW) AS Rolling30DayPostScore,
    LAG(pem.PostCreationDate, 1, pem.PostCreationDate) OVER (PARTITION BY uas.UserId ORDER BY pem.PostCreationDate) AS PrevPostDate,
    CASE
        WHEN pem.PostScore > 50 AND pem.PostViewCount > 1000 AND pem.EditCount >= 3 THEN 'High Impact & Refined'
        WHEN pem.PostScore > 10 AND pem.PostViewCount > 100 THEN 'Moderate Impact'
        WHEN pem.ClosedDate IS NOT NULL AND COALESCE(qcd.ClosureEventCount, 0) > 0 THEN 'Closed & Problematic'
        WHEN pem.PostTypeId = 1 AND pem.HasAcceptedAnswer THEN 'Question Answered'
        ELSE 'Other'
    END AS PostCategory,
    SUBSTRING(COALESCE(pem.Title, 'No Title') FROM 1 FOR 50) AS ShortTitle,
    UPPER(SUBSTRING(pem.PostTypeName FROM 1 FOR 3)) AS PostTypeAbbrev,
    COALESCE(pem.Tags, 'No Tags Provided') AS TagsDisplay,
    (
        SELECT c.Text
        FROM Comments c
        WHERE c.PostId = pem.PostId AND c.UserId = uas.UserId
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS LatestUserCommentOnPost,
    (
        SELECT AVG(sub.TotalBadges)
        FROM UserActivitySummary sub
        WHERE sub.Reputation BETWEEN uas.Reputation - 1000 AND uas.Reputation + 1000
    ) AS AvgBadgesInRepRange,
    (
        SELECT SUM(v.BountyAmount)
        FROM Votes v
        WHERE v.PostId = pem.PostId AND v.VoteTypeId = 8
    ) AS TotalBountyAmount
FROM UserActivitySummary uas
JOIN PostEngagementMetrics pem ON uas.UserId = pem.OwnerUserId
LEFT JOIN PostLinkSummary pls ON pem.PostId = pls.PostId
LEFT JOIN QuestionClosureDetails qcd ON pem.PostId = qcd.PostId
WHERE
    (pem.PostScore >= 5 OR pem.PostViewCount >= 50)
    AND (pem.PostCommentCount > 0 OR COALESCE(pls.LinkedPostsCount, 0) > 0 OR COALESCE(qcd.ClosureEventCount, 0) > 0 OR pem.HasAcceptedAnswer)
    AND (pem.PostTypeName = 'Question' OR (pem.PostTypeName = 'Answer' AND pem.PostScore > 5) OR (pem.PostTypeName = 'TagWikiExcerpt' AND pem.TagCount > 0))
    AND uas.TotalBadges >= 3
    AND (pem.Tags LIKE '%<sql>%' OR pem.Tags LIKE '%<database>%' OR pem.Tags LIKE '%<performance>%')
    AND pem.LastActivityDate >= uas.UserCreationDate + INTERVAL '1 month'
    AND (pem.ClosedDate IS NULL OR DATE_PART('day', CAST('2024-10-01 12:34:56' AS timestamp) - pem.ClosedDate) > 30)
ORDER BY
    uas.Reputation DESC,
    pem.PostScore DESC,
    pem.PostCreationDate DESC
LIMIT 10000;