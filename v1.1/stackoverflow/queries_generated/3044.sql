-- {"query": "3044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1269} 
WITH PostStats AS (
    SELECT
        p.PostTypeId,
        COUNT(p.Id) AS TotalPosts,
        SUM(CASE WHEN p.AnswerCount IS NOT NULL THEN p.AnswerCount ELSE 0 END) AS TotalAnswers,
        AVG(p.Score) AS AvgScore,
        MAX(p.ViewCount) AS MaxViews
    FROM
        Posts p
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS AnswerCount FROM Posts WHERE PostTypeId = 2 GROUP BY PostId) ans ON p.Id = ans.PostId
    GROUP BY
        p.PostTypeId
),
RecentEdits AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        pt.Name AS EditTypeName,
        ph.UserDisplayName AS EditorName,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM
        PostHistory ph
    JOIN
        PostHistoryTypes pt ON ph.PostHistoryTypeId = pt.Id
    WHERE
        pt.Name LIKE '%Edit%'
),
TopEditedPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        ue.EditDate,
        ue.EditTypeName,
        ue.EditorName,
        COUNT(c.Id) OVER (PARTITION BY p.Id) AS CommentCount
    FROM
        Posts p
    LEFT JOIN
        Comments c ON c.PostId = p.Id
    LEFT JOIN
        RecentEdits ue ON p.Id = ue.PostId AND ue.rn = 1
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate > CURRENT_TIMESTAMP - INTERVAL '180 days'
        AND EXISTS (
            SELECT 1 FROM Votes v
            WHERE v.PostId = p.Id AND v.VoteTypeId IN (2,3)
        )
),
FilteredAnswers AS (
    SELECT
        a.Id,
        a.Score,
        a.ParentId,
        a.OwnerUserId,
        u.DisplayName AS OwnerName,
        a.LastActivityDate,
        v1.VoteCount AS UpVotes,
        v2.VoteCount AS DownVotes
    FROM
        Posts a
    LEFT JOIN
        Users u ON a.OwnerUserId = u.Id
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId) v1 ON a.Id = v1.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS VoteCount FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId) v2 ON a.Id = v2.PostId
    WHERE
        a.PostTypeId = 2
        AND a.LastActivityDate > CURRENT_TIMESTAMP - INTERVAL '180 days'
),
AnswerLinks AS (
    SELECT
        p1.Id AS AnswerId,
        p2.Id AS QuestionId,
        pl.LinkTypeId,
        lt.Name AS LinkTypeName
    FROM
        PostLinks pl
    JOIN
        Posts p1 ON pl.PostId = p1.Id
    JOIN
        Posts p2 ON pl.RelatedPostId = p2.Id
    JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE
        p1.PostTypeId = 2 AND p2.PostTypeId = 1
),
TopAnswerers AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS AnswerCount,
        AVG(Score) AS AvgScore
    FROM
        Posts
    WHERE
        PostTypeId = 2
    GROUP BY
        OwnerUserId
    HAVING
        COUNT(*) >= 10
),
UserReputation AS (
    SELECT
        u.Id,
        u.Reputation,
        u.DisplayName,
        u.Location,
        u.AccountId,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY u.LastAccessDate DESC) AS rn
    FROM
        Users u
),
RecentBadges AS (
    SELECT
        b.UserId,
        b.Name AS BadgeName,
        b.Class,
        b.Date AS BadgeDate,
        ROW_NUMBER() OVER (PARTITION BY b.UserId ORDER BY b.Date DESC) AS rn
    FROM
        Badges b
    WHERE
        b.Class IN (1,2,3)
),
FinalResult AS (
    SELECT
        ps.PostTypeId,
        ps.TotalPosts,
        ps.TotalAnswers,
        ps.AvgScore,
        ps.MaxViews,
        te.Title AS TopQuestionTitle,
        te.Tags AS TopQuestionTags,
        te.Score AS TopQuestionScore,
        te.ViewCount AS TopQuestionViews,
        te.CreationDate AS TopQuestionCreation,
        te.CommentCount,
        te.EditDate,
        te.EditTypeName,
        te.EditorName,
        f.AnswerId,
        f.OwnerName,
        f.Score AS AnswerScore,
        f.UpVotes,
        f.DownVotes,
        la.AnswerId AS LinkedAnswerId,
        la.LinkTypeName,
        ua.AnswerCount AS UserAnswerCount,
        ua.AvgScore AS UserAvgScore,
        ur.Reputation,
        ur.DisplayName AS UserDisplayName,
        rb.BadgeName,
        rb.BadgeDate
    FROM
        PostStats ps
    FULL OUTER JOIN
        TopEditedPosts te ON ps.PostTypeId = 1 AND te.PostId = te.PostId
    LEFT JOIN
        FilteredAnswers f ON f.ParentId = te.Id
    LEFT JOIN
        AnswerLinks la ON la.AnswerId = f.Id
    LEFT JOIN
        TopAnswerers ua ON ua.OwnerUserId = f.OwnerUserId
    LEFT JOIN
        UserReputation ur ON ur.Id = f.OwnerUserId AND ur.rn = 1
    LEFT JOIN
        RecentBadges rb ON rb.UserId = ur.Id AND rb.rn = 1
)
SELECT
    *
FROM
    FinalResult
ORDER BY
    TopQuestionCreation DESC
LIMIT 100;