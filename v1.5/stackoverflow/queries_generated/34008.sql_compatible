WITH QuestionStats AS (
    SELECT
        p.Id AS QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        u.DisplayName AS OwnerName,
        COUNT(DISTINCT a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(CASE WHEN v2.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpVotes,
        SUM(CASE WHEN v3.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownVotes,
        MAX(b.Date) FILTER (WHERE b.Class = 1) AS LastGoldBadgeDate,
        ARRAY_AGG(DISTINCT t.TagName) FILTER (WHERE t.TagName IS NOT NULL) AS Tags
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v2 ON v2.PostId = p.Id AND v2.VoteTypeId = 2
    LEFT JOIN Votes v3 ON v3.PostId = p.Id AND v3.VoteTypeId = 3
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON b.UserId = p.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS TagName
    ) t ON true
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.OwnerUserId, p.CreationDate, u.DisplayName
    HAVING COUNT(DISTINCT a.Id) > 3 AND AVG(a.Score) > 2
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS PostCount,
        SUM(p.Score) AS TotalPostScore,
        COUNT(DISTINCT c.Id) AS CommentCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
    HAVING COUNT(DISTINCT p.Id) > 10
),
PostLinkDetails AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        lt.Name AS LinkType,
        COUNT(*) OVER (PARTITION BY pl.PostId) AS LinkCount
    FROM PostLinks pl
    INNER JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
),
FilteredQuestions AS (
    SELECT qs.*
    FROM QuestionStats qs
    WHERE EXISTS (
        SELECT 1
        FROM PostLinkDetails pld
        WHERE pld.PostId = qs.QuestionId AND pld.LinkType = 'Duplicate'
    )
)
SELECT
    fq.QuestionId,
    fq.Title,
    fq.OwnerName,
    fq.CreationDate,
    fq.AnswerCount,
    fq.AvgAnswerScore,
    fq.TotalUpVotes,
    fq.TotalDownVotes,
    fq.LastGoldBadgeDate,
    fq.Tags,
    ua.PostCount AS OwnerPostCount,
    ua.TotalPostScore AS OwnerTotalPostScore,
    ua.CommentCount AS OwnerCommentCount,
    ua.LastPostDate,
    ua.LastCommentDate,
    COUNT(pld.RelatedPostId) FILTER (WHERE pld.LinkType = 'Duplicate') AS DuplicateLinks,
    COUNT(pld.RelatedPostId) FILTER (WHERE pld.LinkType = 'Linked') AS LinkedPosts
FROM FilteredQuestions fq
LEFT JOIN UserActivity ua ON ua.UserId = fq.OwnerUserId
LEFT JOIN PostLinkDetails pld ON pld.PostId = fq.QuestionId
GROUP BY
    fq.QuestionId,
    fq.Title,
    fq.OwnerName,
    fq.CreationDate,
    fq.AnswerCount,
    fq.AvgAnswerScore,
    fq.TotalUpVotes,
    fq.TotalDownVotes,
    fq.LastGoldBadgeDate,
    fq.Tags,
    ua.PostCount,
    ua.TotalPostScore,
    ua.CommentCount,
    ua.LastPostDate,
    ua.LastCommentDate
ORDER BY fq.AvgAnswerScore DESC, fq.TotalUpVotes DESC
LIMIT 50;