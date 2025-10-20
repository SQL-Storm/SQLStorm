WITH TopUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        COUNT(a.Id) AS AnswerCount,
        SUM(a.Score) AS TotalAnswerScore,
        COUNT(DISTINCT b.Id) AS BadgeCount,
        MAX(b.Date) AS LastBadgeDate
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId AND p.PostTypeId = 1
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id, u.DisplayName, u.Reputation
    ORDER BY
        TotalScore DESC
    LIMIT 100
),
TopPosts AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId AS UserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CreationDate,
        u.DisplayName AS OwnerDisplayName,
        t.TagName,
        COUNT(v.Id) AS VoteCount,
        COUNT(c.Id) AS CommentCount
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    LEFT JOIN
        Tags t ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    WHERE
        p.PostTypeId = 1
    GROUP BY
        p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.AnswerCount, p.CreationDate, u.DisplayName, t.TagName
    ORDER BY
        p.Score DESC
    LIMIT 100
),
TopTags AS (
    SELECT
        t.TagName,
        t.Count,
        COUNT(p.Id) AS PostCount,
        SUM(p.Score) AS TotalScore,
        SUM(p.ViewCount) AS TotalViewCount,
        COUNT(DISTINCT u.Id) AS UserCount
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN
        Users u ON p.OwnerUserId = u.Id
    GROUP BY
        t.TagName, t.Count
    ORDER BY
        TotalScore DESC
    LIMIT 50
),
UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(p.Id) AS TotalPosts,
        COUNT(c.Id) AS TotalComments,
        COUNT(v.Id) AS TotalVotes,
        MAX(p.LastActivityDate) AS LastActivityDate,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(ph.PostHistoryTypeId) AS TotalEdits
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        PostHistory ph ON u.Id = ph.UserId
    GROUP BY
        u.Id, u.DisplayName
    ORDER BY
        TotalPosts DESC
    LIMIT 100
)
SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.AnswerCount,
    tu.TotalAnswerScore,
    tu.BadgeCount,
    tu.LastBadgeDate,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.AnswerCount,
    tp.CreationDate,
    tp.OwnerDisplayName,
    tp.TagName,
    tp.VoteCount,
    tp.CommentCount,
    tt.TagName AS TopTagName,
    tt.Count AS TopTagCount,
    tt.PostCount AS TopTagPostCount,
    tt.TotalScore AS TopTagTotalScore,
    tt.TotalViewCount AS TopTagTotalViewCount,
    tt.UserCount AS TopTagUserCount,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.LastActivityDate,
    ua.TotalBadges,
    ua.TotalEdits
FROM
    TopUsers tu
LEFT JOIN
    TopPosts tp ON tu.UserId = tp.UserId
LEFT JOIN
    TopTags tt ON tp.TagName = tt.TagName
LEFT JOIN
    UserActivity ua ON tu.UserId = ua.UserId
GROUP BY
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.PostCount,
    tu.TotalScore,
    tu.AnswerCount,
    tu.TotalAnswerScore,
    tu.BadgeCount,
    tu.LastBadgeDate,
    tp.PostId,
    tp.Title,
    tp.Score,
    tp.ViewCount,
    tp.AnswerCount,
    tp.CreationDate,
    tp.OwnerDisplayName,
    tp.TagName,
    tp.VoteCount,
    tp.CommentCount,
    tt.TagName,
    tt.Count,
    tt.PostCount,
    tt.TotalScore,
    tt.TotalViewCount,
    tt.UserCount,
    ua.TotalPosts,
    ua.TotalComments,
    ua.TotalVotes,
    ua.LastActivityDate,
    ua.TotalBadges,
    ua.TotalEdits
ORDER BY
    tu.TotalScore DESC, tp.Score DESC, tt.TotalScore DESC
LIMIT 50;