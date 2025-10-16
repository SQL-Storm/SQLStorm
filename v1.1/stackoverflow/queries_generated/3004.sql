-- {"query": "3004.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1718} 
WITH PostStats AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.LastActivityDate,
        COALESCE(pc.CommentCount, 0) AS CommentCount,
        COALESCE(f.FavoriteCount, 0) AS FavoriteCount,
        COALESCE(v.TotalVotes, 0) AS VoteSum,
        array_length(string_to_array(p.Tags, '<>'), 1) AS TagCount,
        CASE WHEN p.PostTypeId = 1 THEN 'Question'
             WHEN p.PostTypeId = 2 THEN 'Answer'
             ELSE 'Other' END AS PostTypeLabel
    FROM
        Posts p
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS CommentCount FROM Comments GROUP BY PostId) pc ON p.Id = pc.PostId
    LEFT JOIN
        (SELECT PostId, COUNT(*) AS FavoriteCount FROM Votes WHERE VoteTypeId = 5 GROUP BY PostId) f ON p.Id = f.PostId
    LEFT JOIN
        (SELECT PostId, SUM(CASE WHEN VoteTypeId IN (2,3) THEN 1 ELSE 0 END) AS TotalVotes FROM Votes GROUP BY PostId) v ON p.Id = v.PostId
),
RecentPostChanges AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS ChangeDate,
        ph.UserId AS ChangedByUserId,
        ph.Comment AS ChangeComment,
        ph.RevisionGUID,
        ph.UserDisplayName,
        ph.Text AS RevisionText
    FROM
        PostHistory ph
    WHERE
        ph.PostHistoryTypeId IN (4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,24,37,38)
),
QuestionAnswerRelationship AS (
    SELECT
        q.Id AS QuestionId,
        a.Id AS AnswerId,
        a.Body,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        a.OwnerUserId AS AnswerOwnerId,
        a.LastActivityDate AS AnswerLastActivityDate,
        a.CommentCount AS AnswerCommentCount,
        a.ViewCount AS AnswerViewCount
    FROM
        Posts q
    LEFT JOIN
        Posts a ON a.ParentId = q.Id
    WHERE
        q.PostTypeId = 1
),
AnswerVoteCounts AS (
    SELECT
        av.PostId AS AnswerId,
        COUNT(*) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM
        Votes v
    INNER JOIN
        Posts av ON v.PostId = av.Id
    WHERE
        av.PostTypeId = 2
    GROUP BY
        av.PostId
),
UserBadgeSummary AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    GROUP BY
        u.Id
),
ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.DisplayName,
        u.Location,
        u.AboutMe,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        u.ProfileImageUrl,
        u.EmailHash,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TotalBadges
    FROM
        Users u
    LEFT JOIN
        UserBadgeSummary ub ON u.Id = ub.UserId
    WHERE
        u.LastAccessDate > NOW() - INTERVAL '180 days'
),
TagDetails AS (
    SELECT
        t.Id AS TagId,
        t.TagName,
        t.IsModeratorOnly,
        t.IsRequired,
        COUNT(p.Id) AS UsageCount,
        p.Title AS ExampleQuestionTitle
    FROM
        Tags t
    LEFT JOIN
        Posts p ON p.Tags LIKE '%' || t.TagName || '%'
    WHERE
        p.PostTypeId = 1
    GROUP BY
        t.Id, t.TagName, t.IsModeratorOnly, t.IsRequired, p.Title
),
LinkedPosts AS (
    SELECT
        pl1.PostId,
        pl1.RelatedPostId,
        lt.Name AS LinkTypeName
    FROM
        PostLinks pl1
    LEFT JOIN
        LinkTypes lt ON pl1.LinkTypeId = lt.Id
    WHERE
        lt.Name IN ('Linked', 'Duplicate')
),
QuestionStatistics AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.ViewCount,
        q.Score,
        q.CreationDate,
        q.LastActivityDate,
        COUNT(a.Id) FILTER (WHERE a.PostTypeId = 2) AS AnswerCount,
        COUNT(c.Id) AS CommentCount,
        string_agg(DISTINCT t.TagName, ',') AS TagsList,
        jsonb_agg(DISTINCT jsonb_build_object('AnswerId', a.Id, 'AnswerBody', a.Body, 'AnswerScore', a.Score, 'Owner', u.DisplayName)) AS AnswersDetails,
        COUNT(DISTINCT pl.RelatedPostId) AS NumberOfLinkedPosts
    FROM
        Posts q
    LEFT JOIN
        Posts a ON a.ParentId = q.Id
    LEFT JOIN
        Comments c ON c.PostId = q.Id
    LEFT JOIN
        Tags t ON t.Id IN (SELECT unnest(string_to_array(q.Tags, '<>')::int[]))
    LEFT JOIN
        PostLinks pl ON pl.PostId = q.Id
    LEFT JOIN
        Posts a2 ON pl.RelatedPostId = a2.Id
    LEFT JOIN
        Users u ON a.OwnerUserId = u.Id
    GROUP BY
        q.Id, q.Title, q.ViewCount, q.Score, q.CreationDate, q.LastActivityDate
)
SELECT
    ps.PostId,
    ps.PostTypeLabel,
    ps.Title,
    ps.Tags,
    ps.Score,
    ps.ViewCount,
    ps.CreationDate,
    ps.OwnerUserId,
    ru.DisplayName AS OwnerDisplayName,
    ps.AcceptedAnswerId,
    ans.AnswerId,
    ans.Body AS AnswerBody,
    ans.AnswerScore,
    ans.AnswerCreationDate,
    ans.AnswerOwnerId,
    ans.AnswerLastActivityDate,
    ans.AnswerCommentCount,
    ans.AnswerViewCount,
    ac.UpVotes,
    ac.DownVotes,
    rcv.RevisionDate,
    rcv.RevisionComment,
    qst.AnswerCount,
    qst.CommentCount AS QuestionCommentCount,
    qst.TagsList,
    qst.AnswersDetails,
    qst.NumberOfLinkedPosts,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TotalBadges
FROM
    PostStats ps
LEFT JOIN
    Users ru ON ps.OwnerUserId = ru.Id
LEFT JOIN
    QuestionAnswerRelationship ans ON ps.PostId = ans.QuestionId
LEFT JOIN
    AnswerVoteCounts ac ON ans.AnswerId = ac.AnswerId
LEFT JOIN
    RecentPostChanges rcv ON ps.PostId = rcv.PostId AND rcv.PostHistoryTypeId IN (4,5,6)
LEFT JOIN
    QuestionStatistics qst ON ps.PostId = qst.QuestionId
LEFT JOIN
    UserBadgeSummary ub ON ps.OwnerUserId = ub.UserId
WHERE
    ps.PostTypeLabel = 'Question'
ORDER BY
    ps.CreationDate DESC
LIMIT 100;