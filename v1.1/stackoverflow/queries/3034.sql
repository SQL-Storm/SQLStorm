WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes,
        MAX(p.CreationDate) AS LastPostDate
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Comments c ON u.Id = c.UserId
        LEFT JOIN Votes v ON u.Id = v.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
ActivePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.OwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.CreationDate DESC) AS RankByDate
    FROM
        Posts p
    WHERE
        p.PostTypeId IN (1,2)
),
PostRelations AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM
        PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
),
QuestionAnswerStats AS (
    SELECT
        p.Id AS QuestionId,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        MIN(a.Score) AS MinAnswerScore
    FROM
        Posts p
        LEFT JOIN Posts a ON p.Id = a.ParentId AND a.PostTypeId = 2
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id
),
RecentClosedQuestions AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.ClosedDate,
        cr.Name AS CloseReason
    FROM
        Posts p
        LEFT JOIN CloseReasonTypes cr ON p.ClosedDate IS NOT NULL AND p.ContentLicense IS NOT NULL
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.LastPostDate,
    ARRAY_AGG(DISTINCT tp.Title) FILTER (WHERE tp.RankByDate = 1) AS LatestQuestionTitles,
    ARRAY_AGG(DISTINCT ta.Title) FILTER (WHERE ta.PostTypeId = 2 AND ta.RankByDate = 1) AS LatestAnswerTitles,
    COUNT(CASE WHEN p.PostTypeId = 1 THEN 1 END) AS TotalQuestions,
    COUNT(CASE WHEN p.PostTypeId = 2 THEN 1 END) AS TotalAnswers,
    COUNT(DISTINCT pr.RelatedPostId) AS TotalLinks,
    MAX(cr.QuestionId) FILTER (WHERE cr.CloseReason IS NOT NULL) AS RecentlyClosedQuestions
FROM
    UserActivity ua
    LEFT JOIN ActivePosts tp ON ua.UserId = tp.OwnerUserId AND tp.PostTypeId = 1
    LEFT JOIN ActivePosts ta ON ua.UserId = ta.OwnerUserId AND ta.PostTypeId = 2
    LEFT JOIN Posts p ON ua.UserId = p.OwnerUserId
    LEFT JOIN PostRelations pr ON p.Id = pr.PostId
    LEFT JOIN RecentClosedQuestions cr ON p.Id = cr.QuestionId
WHERE
    ua.Reputation > 1000
    AND ua.LastAccessDate > (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '180 days')
GROUP BY
    ua.UserId, ua.DisplayName, ua.Reputation, ua.TotalPosts, ua.TotalComments, ua.TotalVotes, ua.LastPostDate
ORDER BY
    ua.Reputation DESC, ua.LastPostDate DESC
LIMIT 100;