WITH
RecentHigh AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        u.DisplayName,
        p.CreationDate,
        ROW_NUMBER() OVER (
            PARTITION BY
                SUBSTRING(p.Tags FROM 2 FOR (POSITION('><' IN (p.Tags || '><')) - 2))
            ORDER BY p.Score DESC
        ) AS TagRank
    FROM Posts p
    LEFT JOIN Users u
        ON p.OwnerUserId = u.Id
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '30 days')
),
AnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        COUNT(a.Id)                                   AS AnswerCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AnswerUpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AnswerDownVotes,
        AVG(CASE WHEN v.VoteTypeId IN (2,3) THEN CAST(v.VoteTypeId AS DOUBLE PRECISION) ELSE NULL END) AS AvgVoteType
    FROM Posts q
    LEFT JOIN Posts a
        ON a.ParentId = q.Id AND a.PostTypeId = 2
    LEFT JOIN Votes v
        ON v.PostId = a.Id
    WHERE
        q.PostTypeId = 1
    GROUP BY
        q.Id
),
CommentInsights AS (
    SELECT
        c.PostId,
        MAX(c.Score)                           AS MaxCommentScore,
        MIN(CHAR_LENGTH(c.Text))               AS MinCommentLen,
        COUNT(DISTINCT c.UserId)               AS DistinctCommenters,
        (
            SELECT string_agg(CAST(c2.UserId AS text), '|' ORDER BY c2.UserId)
            FROM Comments c2
            WHERE c2.PostId = c.PostId
        )                                      AS CommenterList
    FROM Comments c
    GROUP BY c.PostId
),
HistoryCount AS (
    SELECT
        ph.PostId,
        COUNT(*) AS EditCountLastWeek
    FROM PostHistory ph
    WHERE ph.CreationDate >= (TIMESTAMP '2024-10-01 12:34:56' - INTERVAL '1 week')
    GROUP BY ph.PostId
),
BaseRecent AS (
    SELECT
        rh.Id,
        rh.Title,
        rh.Tags,
        rh.DisplayName              AS Asker,
        rh.Score                    AS QuestionScore,
        COALESCE(ans.AnswerCount, 0)                                     AS TotalAnswers,
        COALESCE(ans.AnswerUpVotes, 0) - COALESCE(ans.AnswerDownVotes, 0)   AS NetAnswerVotes,
        ci.MaxCommentScore,
        hc.EditCountLastWeek,
        CASE WHEN rh.TagRank = 1 THEN 'TopTagQ' ELSE 'OtherTagQ' END    AS RankCategory,
        (CHAR_LENGTH(rh.Tags) - CHAR_LENGTH(REPLACE(rh.Tags, '<', ''))) / 2             AS TagCount,
        rh.CreationDate,
        (
            SELECT COUNT(*)
            FROM PostLinks pl
            WHERE pl.PostId = rh.Id
              AND pl.LinkTypeId = 1
        )                                                             AS OutgoingLinks
    FROM RecentHigh rh
    LEFT JOIN AnswerStats ans
        ON rh.Id = ans.QuestionId
    LEFT JOIN CommentInsights ci
        ON rh.Id = ci.PostId
    LEFT JOIN HistoryCount hc
        ON rh.Id = hc.PostId
    WHERE rh.TagRank <= 3
),
RecentPosts AS (
    SELECT
        p.Id,
        p.Title,
        p.Tags,
        u.DisplayName,
        p.Score,
        0                             AS TotalAnswers,
        0                             AS NetAnswerVotes,
        NULL::INTEGER                 AS MaxCommentScore,
        NULL::INTEGER                 AS EditCountLastWeek,
        'RecentQ'                     AS RankCategory,
        (CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '<', ''))) / 2 AS TagCount,
        p.CreationDate,
        0                             AS OutgoingLinks
    FROM Posts p
    LEFT JOIN Users u
        ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
),
TopRecent AS (
    SELECT *
    FROM BaseRecent

    UNION ALL

    SELECT *
    FROM RecentPosts
    ORDER BY CreationDate DESC
    LIMIT 5
)
SELECT *
FROM TopRecent

EXCEPT

SELECT
    p.Id,
    p.Title,
    p.Tags,
    COALESCE(u.DisplayName, '<anon>') AS Asker,
    p.Score                    AS QuestionScore,
    COALESCE(ans.AnswerCount, 0)                                     AS TotalAnswers,
    COALESCE(ans.AnswerUpVotes, 0) - COALESCE(ans.AnswerDownVotes, 0)   AS NetAnswerVotes,
    ci.MaxCommentScore,
    hc.EditCountLastWeek,
    'FilteredNeg'              AS RankCategory,
    (CHAR_LENGTH(p.Tags) - CHAR_LENGTH(REPLACE(p.Tags, '<', ''))) / 2 AS TagCount,
    p.CreationDate,
    (
        SELECT COUNT(*)
        FROM PostLinks pl
        WHERE pl.PostId = p.Id
          AND pl.LinkTypeId = 1
    )                             AS OutgoingLinks
FROM Posts p
LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
LEFT JOIN AnswerStats ans
    ON p.Id = ans.QuestionId
LEFT JOIN CommentInsights ci
    ON p.Id = ci.PostId
LEFT JOIN HistoryCount hc
    ON p.Id = hc.PostId
WHERE p.Score < 0;