WITH RankedUsers AS (
    SELECT
        Id AS UserId,
        Reputation,
        ROW_NUMBER() OVER (ORDER BY Reputation DESC) AS Rank
    FROM
        Users
),
TopUsers AS (
    SELECT
        UserId
    FROM
        RankedUsers
    WHERE
        Rank <= 100
),
UserPosts AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        u.Reputation,
        u.DisplayName,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount
    FROM
        Posts p
    JOIN
        Users u ON p.OwnerUserId = u.Id
    JOIN
        TopUsers tu ON u.Id = tu.UserId
    WHERE
        p.PostTypeId = 1
),
TagData AS (
    SELECT
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        up.PostId AS sample_post_id
    FROM
        Tags t
    JOIN
        UserPosts up ON up.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
),
PostVotes AS (
    SELECT
        v.PostId,
        v.VoteTypeId,
        COUNT(*) AS VoteCount
    FROM
        Votes v
    JOIN
        UserPosts up ON v.PostId = up.PostId
    WHERE
        v.VoteTypeId IN (2, 3)
    GROUP BY
        v.PostId, v.VoteTypeId
),
PostComments AS (
    SELECT
        c.PostId,
        COUNT(*) AS CommentCount
    FROM
        Comments c
    JOIN
        UserPosts up ON c.PostId = up.PostId
    GROUP BY
        c.PostId
),
PostHistoryData AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        COUNT(*) AS HistoryCount
    FROM
        PostHistory ph
    JOIN
        UserPosts up ON ph.PostId = up.PostId
    GROUP BY
        ph.PostId, ph.PostHistoryTypeId
),
VictoriousComments AS (
    SELECT
        c.PostId,
        STRING_AGG(c.Text, CHR(10)) AS CommentsText,
        ARRAY_AGG(c.CreationDate ORDER BY c.CreationDate ASC) AS CreationTimes,
        COUNT(DISTINCT c.UserId) AS UniqueUsersComments,
        SUM(CASE WHEN c.Score > 0 THEN 1 ELSE 0 END) AS PositiveScoreComments
    FROM Comments c
    JOIN UserPosts up ON c.PostId = up.PostId
    GROUP BY c.PostId
    ORDER BY PositiveScoreComments DESC
    LIMIT 100
),
AggPostData AS (
    SELECT
        up.PostId,
        up.PostTypeId,
        up.CreationDate,
        up.Score,
        up.ViewCount,
        up.OwnerUserId,
        up.Tags,
        up.Reputation,
        up.DisplayName,
        up.AnswerCount,
        COALESCE(pv.VoteCount, 0) AS TotalVotes,
        COALESCE(pc.CommentCount, 0) AS TotalComments,
        COALESCE(phd.HistoryCount, 0) AS TotalHistoryCount,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        vc.CommentsText,
        vc.CreationTimes,
        vc.UniqueUsersComments,
        vc.PositiveScoreComments
    FROM
        UserPosts up
    LEFT JOIN
        PostVotes pv ON up.PostId = pv.PostId
    LEFT JOIN
        PostComments pc ON up.PostId = pc.PostId
    LEFT JOIN
        PostHistoryData phd ON up.PostId = phd.PostId
    LEFT JOIN
        TagData t ON up.Tags LIKE '%' || '<' || t.TagName || '>' || '%'
    LEFT JOIN
        VictoriousComments vc ON up.PostId = vc.PostId
)
SELECT
    apd.PostId,
    apd.PostTypeId,
    apd.CreationDate,
    apd.Score,
    apd.ViewCount,
    apd.OwnerUserId,
    apd.Tags,
    apd.Reputation,
    apd.DisplayName,
    apd.AnswerCount,
    SUM(apd.TotalVotes) AS TotalVotes,
    SUM(apd.TotalComments) AS TotalComments,
    SUM(apd.TotalHistoryCount) AS TotalHistoryCount,
    apd.TagName,
    apd.Count,
    STRING_AGG(DISTINCT COALESCE(CAST(apd.ExcerptPostId AS VARCHAR), ''), ', ') AS ExcerptPostIds,
    STRING_AGG(DISTINCT COALESCE(CAST(apd.WikiPostId AS VARCHAR), ''), ', ') AS WikiPostIds,
    STRING_AGG(DISTINCT COALESCE(apd.CommentsText, ''), ', ') AS AllCommentsText,
    STRING_AGG(DISTINCT COALESCE(CAST(apd.CreationTimes AS VARCHAR), ''), '. ') AS AllCreationTimes,
    SUM(COALESCE(apd.UniqueUsersComments, 0)) AS CommentsByUniqueUsers,
    SUM(COALESCE(apd.PositiveScoreComments, 0)) AS PositiveScoreComments,
    SUM(apd.TotalVotes) AS VotesInAllPostForms,
    SUM(apd.TotalComments) AS TotalCommentsInAll,
    SUM(apd.TotalHistoryCount) AS HistoryCountInAll
FROM
    AggPostData apd
GROUP BY
    apd.PostId,
    apd.PostTypeId,
    apd.CreationDate,
    apd.Score,
    apd.ViewCount,
    apd.OwnerUserId,
    apd.Tags,
    apd.Reputation,
    apd.DisplayName,
    apd.AnswerCount,
    apd.TagName,
    apd.Count
ORDER BY
    VotesInAllPostForms DESC,
    PositiveScoreComments DESC,
    CommentsByUniqueUsers DESC,
    TotalCommentsInAll DESC
LIMIT 50;