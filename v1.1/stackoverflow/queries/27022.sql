WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivity,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS Rank
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
ActivePosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.LastActivityDate,
        COALESCE(p.AcceptedAnswerId, -1) AS AcceptedAnswerId,
        COUNT(c.Id) AS TotalComments,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        MAX(ph.CreationDate) AS LastEditDate,
        STRING_AGG(DISTINCT t.TagName, ', ') AS AllTags
    FROM
        Posts p
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    LEFT JOIN
        Tags t ON p.Tags LIKE CONCAT('%<', t.TagName, '>%')
    GROUP BY
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.LastActivityDate, p.AcceptedAnswerId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalVotes,
    ua.TotalBadges,
    ua.LastPostActivity,
    ua.Rank,
    ap.PostId,
    pt.Name AS PostTypeName,
    ap.PostCreationDate,
    ap.Score,
    ap.ViewCount,
    ap.TotalComments,
    ap.UpVotes,
    ap.DownVotes,
    ap.LastEditDate,
    ap.AllTags,
    CASE
        WHEN ap.PostTypeId = 1 THEN (SELECT COUNT(*) FROM Posts p2 WHERE p2.ParentId = ap.PostId)
        ELSE 0
    END AS AnswerCount,
    CASE
        WHEN ap.PostTypeId = 2 THEN (SELECT p3.Title FROM Posts p3 WHERE p3.Id = ap.OwnerUserId)
        ELSE NULL
    END AS RelatedQuestionTitle,
    CASE
        WHEN ap.PostTypeId = 1 AND ap.AcceptedAnswerId <> -1 THEN (SELECT p4.Title FROM Posts p4 WHERE p4.Id = ap.AcceptedAnswerId)
        ELSE NULL
    END AS AcceptedAnswerTitle,
    COALESCE(ph.Comment, 'No Close Reason') AS CloseReason,
    ph.CreationDate AS CloseDate,
    vt.Name AS VoteTypeName,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = ap.PostId AND pl.LinkTypeId = 3) AS DuplicateCount
FROM
    UserActivity ua
LEFT JOIN
    ActivePosts ap ON ua.UserId = ap.OwnerUserId
LEFT JOIN
    PostTypes pt ON ap.PostTypeId = pt.Id
LEFT JOIN
    PostHistory ph ON ap.PostId = ph.PostId AND ph.PostHistoryTypeId = 10
LEFT JOIN
    Votes v ON ap.PostId = v.PostId
LEFT JOIN
    VoteTypes vt ON v.VoteTypeId = vt.Id
WHERE
    ua.TotalPosts > 0
    AND ap.Score IS NOT NULL
    AND (
        ap.LastActivityDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
        OR ap.LastEditDate > (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY)
    )
GROUP BY
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.UserCreationDate,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalVotes,
    ua.TotalBadges,
    ua.LastPostActivity,
    ua.Rank,
    ap.PostId,
    pt.Name,
    ap.PostCreationDate,
    ap.Score,
    ap.ViewCount,
    ap.TotalComments,
    ap.UpVotes,
    ap.DownVotes,
    ap.LastEditDate,
    ap.AllTags,
    ap.PostTypeId,
    ap.AcceptedAnswerId,
    ap.OwnerUserId,
    ph.Comment,
    ph.CreationDate,
    vt.Name
ORDER BY
    ua.Rank, ap.Score DESC, ap.ViewCount DESC
LIMIT 100;