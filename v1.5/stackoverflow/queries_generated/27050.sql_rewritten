-- {"query": "27050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "pixtral-large", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2337, "output_tokens": 1378} 
WITH UserActivity AS (
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.DisplayName,
        COUNT(p.Id) AS PostCount,
        COUNT(c.Id) AS CommentCount,
        COUNT(v.Id) AS VoteCount,
        COUNT(b.Id) AS BadgeCount,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(v.CreationDate) AS LastVoteDate,
        MAX(b.Date) AS LastBadgeDate,
        DENSE_RANK() OVER (ORDER BY COUNT(p.Id) DESC) AS PostRank,
        DENSE_RANK() OVER (ORDER BY COUNT(c.Id) DESC) AS CommentRank,
        DENSE_RANK() OVER (ORDER BY COUNT(v.Id) DESC) AS VoteRank,
        DENSE_RANK() OVER (ORDER BY COUNT(b.Id) DESC) AS BadgeRank
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
        u.Id, u.Reputation, u.DisplayName
),
HighActivityUsers AS (
    SELECT
        UserId,
        Reputation,
        DisplayName,
        PostCount,
        CommentCount,
        VoteCount,
        BadgeCount,
        QuestionCount,
        AnswerCount,
        LastPostDate,
        LastCommentDate,
        LastVoteDate,
        LastBadgeDate,
        PostRank,
        CommentRank,
        VoteRank,
        BadgeRank
    FROM
        UserActivity
    WHERE
        PostRank <= 100 OR CommentRank <= 100 OR VoteRank <= 100 OR BadgeRank <= 100
)
SELECT
    ha.UserId,
    ha.DisplayName,
    ha.Reputation,
    ha.PostCount,
    ha.CommentCount,
    ha.VoteCount,
    ha.BadgeCount,
    ha.QuestionCount,
    ha.AnswerCount,
    ha.LastPostDate,
    ha.LastCommentDate,
    ha.LastVoteDate,
    ha.LastBadgeDate,
    ha.PostRank,
    ha.CommentRank,
    ha.VoteRank,
    ha.BadgeRank,
    COALESCE(p.Title, 'No Recent Post') AS LastPostTitle,
    COALESCE(c.Text, 'No Recent Comment') AS LastCommentText,
    COALESCE(v.VoteTypeId, 0) AS LastVoteType,
    COALESCE(b.Name, 'No Recent Badge') AS LastBadgeName,
    COALESCE(p.Tags, 'No Tags') AS LastPostTags,
    SUBSTRING(COALESCE(p.Body, ''), 1, 200) AS LastPostBodySnippet,
    COALESCE(ppl.RelatedPostId, 0) AS LastRelatedPostId,
    COALESCE(l.Name, 'No Link Type') AS LastPostLinkType,
    COALESCE(ph.Comment, 'No Edit Comment') AS LastPostEditComment,
    COALESCE(vot.Name, 'No Vote Type') AS LastVoteTypeName,
    COALESCE(cr.Name, 'No Close Reason') AS LastCloseReason
FROM
    HighActivityUsers ha
LEFT JOIN
    Posts p ON ha.UserId = p.OwnerUserId AND p.CreationDate = ha.LastPostDate
LEFT JOIN
    Comments c ON ha.UserId = c.UserId AND c.CreationDate = ha.LastCommentDate
LEFT JOIN
    Votes v ON ha.UserId = v.UserId AND v.CreationDate = ha.LastVoteDate
LEFT JOIN
    Badges b ON ha.UserId = b.UserId AND b.Date = ha.LastBadgeDate
LEFT JOIN
    PostLinks ppl ON p.Id = ppl.PostId AND ppl.CreationDate = (
        SELECT MAX(pl.CreationDate)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id
    )
LEFT JOIN
    PostHistory ph ON p.Id = ph.PostId AND ph.CreationDate = (
        SELECT MAX(ph2.CreationDate)
        FROM PostHistory ph2
        WHERE ph2.PostId = p.Id
    )
LEFT JOIN
    LinkTypes l ON ppl.LinkTypeId = l.Id
LEFT JOIN
    VoteTypes vot ON v.VoteTypeId = vot.Id
LEFT JOIN
    CloseReasonTypes cr ON (
        ph.PostHistoryTypeId = 10 AND
        CAST(ph.Comment AS INT) = cr.Id
    )
WHERE ha.UserId IS NOT NULL AND p.CreationDate IS NOT NULL
ORDER BY
    ha.PostRank,
    ha.CommentRank,
    ha.VoteRank,
    ha.BadgeRank,
    ha.LastPostDate DESC,
    ha.LastCommentDate DESC,
    ha.LastVoteDate DESC,
    ha.LastBadgeDate DESC