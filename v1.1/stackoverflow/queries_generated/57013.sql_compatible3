WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        COUNT(p.Id) AS TotalPosts,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestions,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswers,
        COUNT(c.Id) AS TotalComments,
        COUNT(v.Id) AS TotalVotes,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(b.Date) AS LastBadgeDate
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
    GROUP BY
        u.Id, u.Reputation, u.CreationDate
),
HighActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalComments,
        TotalVotes,
        TotalBadges,
        UserCreationDate,
        LastPostActivityDate,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate
    FROM
        UserActivity
    WHERE
        TotalPosts > 100 OR
        TotalQuestions > 50 OR
        TotalAnswers > 50 OR
        TotalComments > 100 OR
        TotalVotes > 500 OR
        TotalBadges > 20
),
RecentActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        TotalPosts,
        TotalQuestions,
        TotalAnswers,
        TotalComments,
        TotalVotes,
        TotalBadges,
        UserCreationDate,
        LastPostActivityDate,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate
    FROM
        HighActivityUsers
    WHERE
        LastPostActivityDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY OR
        LastCommentDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY OR
        LastVoteDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY OR
        LastBadgeDate >= TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30' DAY
),
TopTags AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.Count AS TagCount,
        COUNT(p.Id) AS PostsWithTag,
        SUM(p.ViewCount) AS TotalViewsForTag,
        SUM(p.Score) AS TotalScoreForTag,
        MAX(p.CreationDate) AS LastPostDateForTag
    FROM
        Tags t
    LEFT JOIN
        Posts p ON EXISTS (
            SELECT 1
            FROM regexp_split_to_table(
                CASE WHEN p.Tags IS NULL THEN '' ELSE substring(p.Tags FROM 2 FOR GREATEST(char_length(p.Tags) - 2, 0)) END,
                '><'
            ) AS tagname(tn)
            WHERE tagname.tn = t.TagName
        )
    GROUP BY
        t.Id, t.TagName, t.Count
    ORDER BY
        TagCount DESC,
        PostsWithTag DESC,
        TotalViewsForTag DESC
    LIMIT 50
),
TagActivity AS (
    SELECT
        t.TagId,
        t.TagName,
        t.TagCount,
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.LastActivityDate,
        COUNT(v.Id) AS TotalVotesForPost,
        COUNT(DISTINCT v.UserId) AS UniqueVotersForPost,
        COUNT(c.Id) AS TotalCommentsForPost,
        COUNT(DISTINCT c.UserId) AS UniqueCommentersForPost
    FROM
        TopTags t
    LEFT JOIN
        Posts p ON EXISTS (
            SELECT 1
            FROM regexp_split_to_table(
                CASE WHEN p.Tags IS NULL THEN '' ELSE substring(p.Tags FROM 2 FOR GREATEST(char_length(p.Tags) - 2, 0)) END,
                '><'
            ) AS tagname(tn)
            WHERE tagname.tn = t.TagName
        )
    LEFT JOIN
        Votes v ON p.Id = v.PostId
    LEFT JOIN
        Comments c ON p.Id = c.PostId
    GROUP BY
        t.TagId, t.TagName, t.TagCount, p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.LastActivityDate
)
SELECT
    u.UserId,
    u.Reputation,
    u.TotalPosts,
    u.TotalQuestions,
    u.TotalAnswers,
    u.TotalComments,
    u.TotalVotes,
    u.TotalBadges,
    u.UserCreationDate,
    u.LastPostActivityDate,
    u.LastCommentDate,
    u.LastVoteDate,
    u.LastBadgeDate,
    t.TagId,
    t.TagName,
    t.TagCount,
    ta.PostId,
    ta.PostTypeId,
    ta.PostCreationDate,
    ta.PostScore,
    ta.PostViewCount,
    ta.AnswerCount,
    ta.CommentCount,
    ta.LastActivityDate,
    ta.TotalVotesForPost,
    ta.UniqueVotersForPost,
    ta.TotalCommentsForPost,
    ta.UniqueCommentersForPost
FROM
    RecentActivityUsers u
JOIN
    TagActivity ta ON u.UserId = ta.OwnerUserId
JOIN
    TopTags t ON ta.TagId = t.TagId
ORDER BY
    u.Reputation DESC,
    t.TagCount DESC,
    ta.PostScore DESC
LIMIT 1000;